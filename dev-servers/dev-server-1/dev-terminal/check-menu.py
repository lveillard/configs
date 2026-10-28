import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import termios
import time

dev=str(Path.home()/'.local/bin/dev')
name='menu-integration-check'
subprocess.run([dev,'new',name,'--detached'],check=True)
pid,fd=pty.fork()
if pid==0:
    os.environ['TERM']='xterm-256color'
    os.execv(dev,[dev])
fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack('HHHH',36,132,0,0))
def read_for(seconds):
    out=b''; deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        ready,_,_=select.select([fd],[],[],.1)
        if ready:
            try: out+=os.read(fd,65536)
            except OSError: break
    return out
def attached():
    return subprocess.check_output(['tmux','-L','dev-sessions','display-message','-p','-t',name,'#{session_attached}']).strip()==b'1'
def tmux(*args):
    return subprocess.check_output(['tmux','-L','dev-sessions',*args]).decode().strip()
created='ux-created-check'
try:
    output=read_for(3)
    if b'\x1b[6n' in output:
        os.write(fd,b'\x1b[1;1R')
        output+=read_for(2)
    assert b'Nueva terminal' in output,'Session menu did not render: '+repr(output[-2000:])
    os.write(fd,name.encode()); read_for(.5)
    os.write(fd,b'\x1bOP'); output=read_for(1)
    assert b'Ayuda y atajos' in output,'F1 did not open selector help'
    os.write(fd,b'\x1bOP'); read_for(1)
    os.write(fd,b'\r'); output=read_for(2)
    assert attached(),'Selecting a saved terminal did not attach'
    assert b'Ctrl+B luego:' in output,'Permanent shortcut guide is missing'
    os.write(fd,b'\x02'); output=read_for(1.3)
    assert b'AHORA pulsa:' in output,'Prefix did not reveal the next-key guide'
    os.write(fd,b'\x1b'); read_for(.5)
    assert tmux('list-clients','-F','#{client_prefix}','-t',name)=='0','Escape did not cancel prefix'
    # Open the native action menu and create a window with its advertised key.
    os.write(fd,b'\x1bOP'); output=read_for(1)
    if b'Selector de terminales' not in output:
        client=tmux('list-clients','-F','#{client_name}','-t',name)
        diagnostic=subprocess.run([str(Path.home()/'.config/dev-terminal/dev-actions'),client],capture_output=True,text=True,timeout=3)
        print('Action menu diagnostic:',diagnostic.returncode,diagnostic.stdout,diagnostic.stderr)
    assert b'Selector de terminales' in output,'F1 did not open terminal actions: '+repr(output[-2500:])
    os.write(fd,b'c'); read_for(1)
    assert len(tmux('list-windows','-t',name).splitlines())==2,'Action menu did not create a window'
    os.write(fd,b'\x02v'); read_for(.6)
    assert len(tmux('list-panes','-t',name).splitlines())==2,'Advertised v shortcut did not split'
    # Click the visible F1 button in the first of the two bottom status rows.
    os.write(fd,b'\x1b[<0;123;35M\x1b[<0;123;35m'); output=read_for(1)
    assert b'Selector de terminales' in output,'Clicking the help button did not open actions'
    os.write(fd,b'\x1b'); read_for(.5)
    # A real F12 must work both here and outside tmux, without typing m into the shell.
    os.write(fd,b'\x1b[24~'); output=read_for(1)
    assert b'Nueva terminal' in output,'F12 did not open the selector popup'
    os.write(fd,b'\x1b'); read_for(.5)
    os.write(fd,b'\x02d'); output=read_for(2)
    assert not attached() and b'Nueva terminal' in output,'Detach did not return to session menu'
    os.write(fd,b'\x0e'); output=read_for(1)
    assert b'1/3' in output,'Ctrl+N did not begin the new-terminal wizard'
    os.write(fd,b'\r'); output=read_for(.7)
    assert b'2/3' in output,'Project selection did not advance'
    os.write(fd,b'\r'); output=read_for(.7)
    assert b'3/3' in output,'Profile selection did not advance'
    os.write(fd,b'bad name\r'); output=read_for(.5)
    assert b'Nombre no valido' in output,'Invalid name was not handled inside the wizard'
    os.write(fd,name.encode()+b'\r'); output=read_for(.5)
    assert b'Ya existe' in output,'Duplicate session name was not handled'
    os.write(fd,created.encode()+b'\r'); read_for(1)
    assert tmux('display-message','-p','-t',created,'#{session_attached}')=='1','Wizard did not create and open session'
    os.write(fd,b'\x02d'); read_for(1)
    os.write(fd,b'\x12'); output=read_for(.7)
    assert created.encode() in output,'Ctrl+R did not refresh the saved sessions'
    os.write(fd,b'\x1b'); read_for(1)
    result=os.waitpid(pid,os.WNOHANG)
    assert result[0]==pid and os.waitstatus_to_exitcode(result[1])==0,'Closing the menu failed'
    pid=None
    print('PASS: selector help, prefix hints, Escape, F1 actions, mouse button, F12, split, three-step creation, invalid/duplicate names, refresh and reconnect.')
finally:
    if pid:
        try: os.kill(pid,signal.SIGTERM); os.waitpid(pid,0)
        except ProcessLookupError: pass
    os.close(fd)
    subprocess.run(['tmux','-L','dev-sessions','kill-session','-t',name],check=True)
    subprocess.run(['tmux','-L','dev-sessions','kill-session','-t',created],capture_output=True)
