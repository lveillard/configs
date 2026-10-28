# Usage: python -I check-picker.py <box>. Opens a test window with the auto picker, presses Esc twice, fires Ctrl+Shift+S's event twice.
import ctypes, json, os, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent; ROOT = HERE.parent; BOX = sys.argv[1]
cat = json.loads((ROOT / 'boxes.json').read_text())
allowed = {'SYSTEMROOT','WINDIR','PATH','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','PROGRAMDATA','PROGRAMFILES','TEMP','TMP','USERNAME','USERDOMAIN','COMSPEC','OS'}
env = {k: v for k, v in os.environ.items() if k.upper() in allowed}
env.update(WEZTERM_REMOTE_DOMAIN=BOX, WEZTERM_REMOTE_LAUNCHER=str(ROOT / 'launcher'), WEZTERM_REMOTE_SHOW_SESSIONS='1')
gui = subprocess.Popen([cat['weztermGui'], '--config-file', str(HERE / 'picker-check.lua'), 'connect', '--class', 'org.wezfurlong.wezterm.picker-test', BOX], env=env)
u = ctypes.windll.user32
def windows():
    found = []
    cb = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    @cb
    def f(h, _):
        pid = ctypes.c_ulong(); u.GetWindowThreadProcessId(ctypes.c_void_p(h), ctypes.byref(pid))
        if pid.value == gui.pid and u.IsWindowVisible(ctypes.c_void_p(h)): found.append(h)
        return True
    u.EnumWindows(f, 0); return found
def esc():
    for h in windows():
        u.PostMessageW(ctypes.c_void_p(h), 0x0100, 0x1B, 0x00010001); u.PostMessageW(ctypes.c_void_p(h), 0x0101, 0x1B, 0xC0010001)
try:
    time.sleep(6); esc()          # close the auto-opened picker
    time.sleep(5); esc()          # close picker #1 (fired at ~8s)
    time.sleep(6); esc()          # close picker #2 (fired at ~14s)
    time.sleep(1)
finally:
    for h in windows(): u.PostMessageW(ctypes.c_void_p(h), 0x0010, 0, 0)
    try: gui.wait(timeout=5)
    except subprocess.TimeoutExpired: gui.terminate()
log = Path.home() / '.local/share/wezterm' / f'wezterm-gui.exe-log-{gui.pid}.txt'
lines = [l.strip() for l in log.read_text(encoding='utf-8', errors='replace').splitlines() if 'sessions:' in l or 'picker-check' in l or 'ERROR' in l]
print('\n'.join(l[l.find('>')+2:][:120] for l in lines))
