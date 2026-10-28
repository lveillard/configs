import ctypes
import datetime
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time

# Usage: python -I check-create-once.py <box name>. Drives a separate test window only.
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BOX = sys.argv[1]
CATALOGUE = json.loads((ROOT / 'boxes.json').read_text())
ENTRY = next(b for b in CATALOGUE['boxes'] if b['name'] == BOX)
STATE = Path.home() / '.local/state' / ENTRY['stateDir'] / 'create-check'
STATE.mkdir(parents=True, exist_ok=True)
SETTINGS = {'weztermGui': CATALOGUE['weztermGui']}
STAMP = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
INITIAL, TARGET = 'qa-entry-' + STAMP, 'qa-created-' + STAMP
PREFERENCE = STATE.parent / 'last-session.txt'
old_preference = PREFERENCE.read_text() if PREFERENCE.exists() else None
gui = None


def mux(*args):
    command = 'WEZTERM_UNIX_SOCKET="$HOME/.local/state/wezterm/dev-server.sock" wezterm cli --no-auto-start ' + shlex.join(args)
    result = subprocess.run(['ssh', '-n', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', BOX, command], capture_output=True, text=True, encoding='utf-8', timeout=12)
    if result.returncode:
        raise RuntimeError('Remote QA command failed; raw output withheld.')
    return result.stdout


def gui_windows(pid):
    user32 = ctypes.windll.user32
    found = []
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    @callback_type
    def collect(hwnd, _):
        owner = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(ctypes.c_void_p(hwnd), ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(ctypes.c_void_p(hwnd)):
            found.append(hwnd)
        return True
    user32.EnumWindows(collect, 0)
    return found


def read_state():
    try:
        return json.loads((STATE / 'state.json').read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


try:
    mux('spawn', '--new-window', '--workspace', INITIAL, '--cwd', '/home/' + CATALOGUE['user'] + '/projects')
    (STATE / 'fixture.json').write_text(json.dumps({'initial': INITIAL, 'target': TARGET}))
    (STATE / 'state.json').unlink(missing_ok=True)
    allowed = {'SYSTEMROOT','WINDIR','PATH','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','PROGRAMDATA','PROGRAMFILES','TEMP','TMP','USERNAME','USERDOMAIN','COMSPEC','OS'}
    env = {key: value for key, value in os.environ.items() if key.upper() in allowed}
    env['WEZTERM_REMOTE_DOMAIN'] = BOX
    env['WEZTERM_REMOTE_LAUNCHER'] = str(ROOT / 'launcher')
    env['WEZTERM_CREATE_CHECK_STATE'] = str(STATE)
    gui = subprocess.Popen([SETTINGS['weztermGui'], '--config-file', str(HERE/'create-check.lua'), 'connect', '--class', 'org.wezfurlong.wezterm.creation-test', '--workspace', INITIAL, BOX], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        state = read_state()
        windows = gui_windows(gui.pid)
        if state.get('prompted') and windows:
            break
        time.sleep(.1)
    else:
        raise RuntimeError('QA creation prompt did not open.')
    time.sleep(.5)
    user32 = ctypes.windll.user32
    hwnd = ctypes.c_void_p(windows[0])
    # Send text to this test window only, leaving the user's terminal untouched.
    for char in TARGET:
        user32.PostMessageW(hwnd, 0x0102, ord(char), 1)
    user32.PostMessageW(hwnd, 0x0100, 0x0D, 0x001C0001)
    user32.PostMessageW(hwnd, 0x0101, 0x0D, 0xC01C0001)
    for _ in range(80):
        time.sleep(.1)
        state = read_state()
        if state.get('active') == TARGET and state.get('stale_request_replayed'):
            break
    time.sleep(1.5)
    rows = [row for row in json.loads(mux('list', '--format', 'json')) if row['workspace'] == TARGET]
    result = {'single_enter_activated':state.get('active') == TARGET, 'stale_request_replayed':state.get('stale_request_replayed', False), 'server_windows':len({row['window_id'] for row in rows}), 'server_panes':len(rows), 'state':state}
    (STATE / 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result), flush=True)
    assert result['single_enter_activated'] and result['stale_request_replayed'] and result['server_windows'] == 1 and result['server_panes'] == 1, 'Creation/duplicate regression failed.'
finally:
    if gui and gui.poll() is None:
        for hwnd in gui_windows(gui.pid):
            ctypes.windll.user32.PostMessageW(ctypes.c_void_p(hwnd), 0x0010, 0, 0)
        try:
            gui.wait(timeout=5)
        except subprocess.TimeoutExpired:
            gui.terminate()
    for row in json.loads(mux('list', '--format', 'json')):
        if row['workspace'] in (INITIAL, TARGET):
            mux('kill-pane', '--pane-id', str(row['pane_id']))
    if PREFERENCE.exists() and PREFERENCE.read_text().strip() in (INITIAL, TARGET):
        if old_preference is None:
            PREFERENCE.unlink()
        else:
            PREFERENCE.write_text(old_preference)
