"""Drop an SSH tmux client and assert that its running command survives."""
import subprocess
import time

prefix=['ssh','-T','-o','BatchMode=yes','dev-server-1']
name='dev-sessions-check'
def run(command):
    result=subprocess.run([*prefix,command],capture_output=True,text=True,check=True)
    return result.stdout.strip()
run('/home/devuser/.local/bin/dev new '+name+' --detached')
try:
    run("tmux -L dev-sessions send-keys -t "+name+" 'sleep 120' Enter")
    before=run("tmux -L dev-sessions list-panes -t "+name+" -F '#{pane_id}:#{pane_pid}:#{pane_current_command}'")
    client=subprocess.Popen(['ssh','-tt','-o','BatchMode=yes','dev-server-1','TERM=xterm-256color tmux -L dev-sessions attach -t '+name],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        for _ in range(12):
            attached=run("tmux -L dev-sessions display-message -p -t "+name+" '#{session_attached}'")
            if attached=='1': break
            time.sleep(.25)
        assert attached=='1','Test SSH client did not attach'
    finally:
        client.terminate(); client.wait(timeout=10)
    after=run("tmux -L dev-sessions list-panes -t "+name+" -F '#{pane_id}:#{pane_pid}:#{pane_current_command}'")
    assert before==after and after.endswith(':sleep'),(before,after)
    print('SSH client terminated: same tmux pane, same shell PID, command still running.')
finally:
    run('tmux -L dev-sessions kill-session -t '+name)
