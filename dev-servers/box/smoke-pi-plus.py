"""RPC smoke test for a pi profile: no model call, no session, no config writes.

Starts the given profile in RPC mode, asks for state and commands, and fails if
an extension error is reported. For pi-plus, the ledger commands must be there.
"""
import json
import os
import selectors
import subprocess
import sys
import tempfile
import time
from pathlib import Path

home = Path.home()
name = sys.argv[1] if len(sys.argv) > 1 else 'pi-plus'
workspace = home / '.local/state/pi-smoke'
workspace.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env['PATH'] = str(home / '.local/bin') + ':' + env['PATH']
binary = str(home / '.local/bin' / name)
with tempfile.TemporaryFile() as stderr:
    proc = subprocess.Popen(
        [binary, '--mode', 'rpc', '--no-session', '--no-approve'],
        cwd=workspace, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr)
    proc.stdin.write(b'{"id":"state","type":"get_state"}\n{"id":"commands","type":"get_commands"}\n')
    proc.stdin.flush()
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    found, errors, buffer = {}, [], b''
    deadline = time.monotonic() + 60
    try:
        while len(found) < 2 and time.monotonic() < deadline:
            for key, _ in selector.select(timeout=.5):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    break
                buffer += chunk
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    try:
                        item = json.loads(line)
                    except ValueError:
                        continue
                    if item.get('type') == 'extension_error':
                        errors.append(item.get('extensionPath', 'unknown extension'))
                    if item.get('id') in ('state', 'commands'):
                        found[item['id']] = item
            if proc.poll() is not None:
                break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        selector.close()
    stderr.seek(0)
    diagnostics = stderr.read().decode(errors='replace')
failed = any(text in diagnostics.lower() for text in (
    'failed to load extension', 'cannot find module', 'error loading extension'))
ok = len(found) == 2 and all(x.get('success') for x in found.values()) and not errors and not failed
commands = [c['name'] for c in found.get('commands', {}).get('data', {}).get('commands', [])]
state = found.get('state', {}).get('data', {})
ledger = {'ledger', 'closing'} <= set(commands)
ok = ok and (ledger or name != 'pi-plus')
print(name + ': ' + ('OK' if ok else 'FAILED'))
print('  model: ' + str(state.get('model', {}).get('id', '?')))
print('  ledger commands: ' + (', '.join(x for x in commands if x in ('ledger', 'closing')) or 'none'))
if not ok:
    print(diagnostics[-2000:])
    raise SystemExit(1)
