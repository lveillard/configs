-- One WezTerm Remote config for every box in ../boxes.json.
-- launch.ps1 sets WEZTERM_REMOTE_DOMAIN to the box name.
local wezterm = require 'wezterm'
local config = dofile(wezterm.home_dir .. '/.wezterm.lua')
-- launch.ps1 passes the launcher folder; WezTerm's Lua has no debug library to find it.
local here = os.getenv('WEZTERM_REMOTE_LAUNCHER') or (wezterm.home_dir .. '/configs/dev-servers/launcher')
local file = assert(io.open(here .. '/../boxes.json', 'r'))
local catalogue = wezterm.json_parse(file:read('*a'))
file:close()
local name = os.getenv('WEZTERM_REMOTE_DOMAIN') or 'dev-server-1'
local box
for _, entry in ipairs(catalogue.boxes) do
  if entry.name == name then box = entry end
end
assert(box, 'Unknown box: ' .. name)
local user = catalogue.user
local remote_root = '/home/' .. user .. '/projects'
local socket = '/home/' .. user .. '/.local/state/wezterm/dev-server.sock'
local ssh = 'C:/Windows/System32/OpenSSH/ssh.exe'
local key_base = wezterm.home_dir .. '/.ssh/' .. box.name

config.unix_domains = {}
config.ssh_domains = {
  {
    name = box.name,
    remote_address = box.name .. '.' .. catalogue.tailnet,
    username = user,
    no_agent_auth = true,
    multiplexing = 'WezTerm',
    override_proxy_command = 'WEZTERM_UNIX_SOCKET=' .. socket .. ' /usr/bin/wezterm cli --prefer-mux --no-auto-start proxy',
    ssh_option = {
      identityfile = key_base .. '_ed25519',
      userknownhostsfile = key_base .. '_known_hosts',
      stricthostkeychecking = 'yes',
    },
  },
}
config.default_domain = box.name
config.default_gui_startup_args = { 'connect', '--class', 'org.wezfurlong.wezterm.remote-' .. box.label, box.name }
-- The Linux mux chooses its shell; sending a Windows CommandBuilder is not portable.
config.default_prog = nil
config.default_cwd = remote_root

if box.tint then
  config.colors.background = box.tint.background
  config.colors.split = box.tint.split
end

wezterm.on('format-window-title', function()
  local session = wezterm.mux.get_active_workspace()
  if session == 'default' then session = 'General' end
  return box.shortcut .. ' - ' .. session .. ' - ' .. box.name
end)

wezterm.on('launch-remote-project', function(window, pane)
  local choices = { { id = remote_root, label = 'projects (carpeta de trabajo)' } }
  local ok, stdout = wezterm.run_child_process {
    ssh, '-T', '-o', 'ConnectTimeout=4', box.name,
    "(find " .. remote_root .. " -mindepth 1 -maxdepth 1 -type d -printf '%P\n'; find " .. remote_root .. " -mindepth 3 -maxdepth 3 -type d -path '*/.worktrees/*' -printf '%P\n') | sort",
  }
  if ok then
    for entry in stdout:gmatch('[^\r\n]+') do
      table.insert(choices, { id = remote_root .. '/' .. entry, label = entry:gsub('/%.worktrees/', ' / ') })
    end
  end
  window:perform_action(wezterm.action.InputSelector {
    title = 'Abrir proyecto en ' .. box.name,
    description = 'Abre una terminal en la carpeta remota',
    choices = choices,
    action = wezterm.action_callback(function(win, _, cwd)
      if cwd then
        win:mux_window():spawn_tab { domain = { DomainName = box.name }, cwd = cwd }
      end
    end),
  }, pane)
end)

return dofile(here .. '/sessions.lua').configure(config, {
  domain = box.name,
  user = user,
  preference_path = wezterm.home_dir .. '/.local/state/' .. box.stateDir .. '/last-session.txt',
})
