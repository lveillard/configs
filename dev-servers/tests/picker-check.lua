-- Test wrapper: real launcher config, then fires the Ctrl+Shift+S event twice on a timer.
local wezterm = require 'wezterm'
local config = dofile(os.getenv('WEZTERM_REMOTE_LAUNCHER') .. '/wezterm.lua')
wezterm.on('update-status', function(window, pane)
  local g = wezterm.GLOBAL
  g.picker_check_start = g.picker_check_start or os.time()
  local t = os.time() - g.picker_check_start
  if t >= 8 and not g.picker_check_first then
    g.picker_check_first = true
    wezterm.log_info('picker-check: firing remote-sessions #1')
    window:perform_action(wezterm.action.EmitEvent 'remote-sessions', pane)
  end
  if t >= 14 and not g.picker_check_second then
    g.picker_check_second = true
    wezterm.log_info('picker-check: firing remote-sessions #2')
    window:perform_action(wezterm.action.EmitEvent 'remote-sessions', pane)
  end
end)
return config
