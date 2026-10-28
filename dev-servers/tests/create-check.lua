local wezterm = require 'wezterm'
local launcher = os.getenv('WEZTERM_REMOTE_LAUNCHER') .. '/'
local state = os.getenv('WEZTERM_CREATE_CHECK_STATE') .. '/'
local box = os.getenv('WEZTERM_REMOTE_DOMAIN')
local config = dofile(launcher .. 'wezterm.lua')
local sessions = dofile(launcher .. 'sessions.lua')
local catalogue = wezterm.json_parse(io.open(launcher .. '../boxes.json'):read('*a'))
for _, b in ipairs(catalogue.boxes) do
  if b.name == box then
    sessions.bind { domain = box, user = catalogue.user, preference_path = wezterm.home_dir .. '/.local/state/' .. b.stateDir .. '/last-session.txt' }
  end
end
local fixture_file = assert(io.open(state .. 'fixture.json', 'r'))
local fixture = wezterm.json_parse(fixture_file:read('*a'))
fixture_file:close()
wezterm.on('update-status', function(window, pane)
  local remote = wezterm.mux.get_domain(box)
  if not remote or remote:state() ~= 'Attached' then return end
  if not wezterm.GLOBAL.create_check_prompted and window:active_workspace() == fixture.initial then
    wezterm.GLOBAL.create_check_prompted = true
    window:perform_action(wezterm.action.EmitEvent 'remote-session-new', pane)
  end
  if window:active_workspace() == fixture.target and not wezterm.GLOBAL.create_check_replayed then
    wezterm.GLOBAL.create_check_replayed = true
    local actual_list = sessions.list
    sessions.list = function() return {} end -- simulate a stale client-side list
    sessions.create(window, pane, fixture.target)
    sessions.list = actual_list
  end
  local entries = {}
  for _, item in ipairs(sessions.list()) do
    if item.name == fixture.initial or item.name == fixture.target then
      table.insert(entries, {name=item.name, windows=item.windows})
    end
  end
  local file = assert(io.open(state .. 'state.json', 'w'))
  file:write(wezterm.json_encode {
    prompted=wezterm.GLOBAL.create_check_prompted,
    stale_request_replayed=wezterm.GLOBAL.create_check_replayed,
    active=wezterm.mux.get_active_workspace(),
    pending=wezterm.GLOBAL.remote_pending_session,
    sessions=entries,
  })
  file:close()
end)
return config
