"""Linux wrapper regressions with isolated fake tmux/WezTerm processes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'dev-server-1/dev-server'
STUB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps([tool, *args]) + '\\n')
if tool == 'tmux' and args[0] == 'has-session':
    sys.exit(int(os.environ.get('HAS_SESSION_EXIT', '0')))
if tool == 'wezterm' and 'list' in args:
    counter = pathlib.Path(os.environ['CALL_LOG'] + '.count')
    count = int(counter.read_text()) if counter.exists() else 0
    counter.write_text(str(count + 1))
    if count == 1 and os.environ.get('REPLACE_SOCKET'):
        socket = pathlib.Path(os.environ['WEZTERM_UNIX_SOCKET'])
        socket.rename(str(socket) + '.old')
        socket.touch()
    print(os.environ.get('PANES', '[]'))
elif tool == 'wezterm' and 'spawn' in args:
    print('41')
'''


class AgentTools(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='configs-agent-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ('tmux', 'wezterm'):
            path = self.root / name
            path.write_text(STUB)
            path.chmod(0o755)
        self.log = self.root / 'calls.jsonl'
        self.socket = self.root / 'mux.sock'
        self.socket.touch()
        self.env = dict(os.environ, PATH=str(self.root) + ':' + os.environ['PATH'],
                        CALL_LOG=str(self.log), WEZTERM_UNIX_SOCKET=str(self.socket))

    def run_tool(self, name, *args):
        return subprocess.run(['bash', str(TOOLS / name), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_kill_treats_quotes_as_data_and_targets_only_matching_workspace(self):
        name = "review'quoted"
        self.env['PANES'] = json.dumps([
            {'workspace': name, 'pane_id': 41}, {'workspace': 'another-agent', 'pane_id': 99}])
        result = self.run_tool('agent-kill', name)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(['tmux', 'kill-session', '-t', '=review_quoted'], self.calls())
        kills = [c for c in self.calls() if 'kill-pane' in c]
        self.assertEqual(kills, [['wezterm', 'cli', '--no-auto-start', 'kill-pane', '--pane-id', '41']])

    def test_kill_refuses_empty_default_or_missing_names(self):
        for args in [(), ('',), ('default',), ('one', 'two')]:
            self.assertEqual(self.run_tool('agent-kill', *args).returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_kill_refuses_panes_after_mux_replacement(self):
        self.env.update(PANES='[{"workspace":"review","pane_id":41}]', REPLACE_SOCKET='1')
        result = self.run_tool('agent-kill', 'review')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Mux changed', result.stderr)
        self.assertFalse(any('kill-pane' in c for c in self.calls()))

    def test_kill_still_stops_tmux_when_mux_is_absent(self):
        self.socket.unlink()
        result = self.run_tool('agent-kill', 'review')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(['tmux', 'kill-session', '-t', '=review'], self.calls())
        self.assertFalse(any(c[0] == 'wezterm' for c in self.calls()))

    def test_spawn_creates_detached_tmux_before_attaching_pane(self):
        self.env['HAS_SESSION_EXIT'] = '1'
        result = self.run_tool('agent-spawn', 'review', '/tmp/project path', 'codex', 'model', '--', 'echo', 'hello')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        new_session = next(c for c in calls if c[:2] == ['tmux', 'new-session'])
        self.assertIn('-d', new_session)
        self.assertEqual(new_session[new_session.index('-c') + 1], '/tmp/project path')
        spawn = next(c for c in calls if 'spawn' in c)
        self.assertIn('tmux attach-session -t =review', spawn[-1])
        self.assertLess(calls.index(new_session), calls.index(spawn))

    def test_spawn_duplicate_never_starts_another_agent(self):
        result = self.run_tool('agent-spawn', 'review', '/tmp', 'codex', 'model', '--', 'echo')
        self.assertEqual(result.returncode, 3)
        self.assertFalse(any('new-session' in c or 'spawn' in c for c in self.calls()))

    def test_spawn_explicit_plain_pane(self):
        self.env['AGENT_SPAWN_TMUX'] = '0'
        result = self.run_tool('agent-spawn', 'review', '/tmp', 'codex', 'model', '--', 'echo')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[0] == 'tmux' for c in self.calls()))
        self.assertTrue(any('spawn' in c for c in self.calls()))


if __name__ == '__main__':
    unittest.main()
