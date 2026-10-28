local wezterm = require 'wezterm'
local config = wezterm.config_builder()
wezterm.on('format-window-title', function() return 'Dev Sessions - dev-server-1' end)
config.default_prog = {
  'C:\\Windows\\System32\\OpenSSH\\ssh.exe', '-tt',
  '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=3',
  'dev-server-1', '/home/devuser/.local/bin/dev',
}
config.font = wezterm.font_with_fallback { 'JetBrains Mono', 'Cascadia Code', 'Consolas' }
config.font_size = 11
config.color_scheme = 'Tokyo Night Storm'
config.initial_cols = 132
config.initial_rows = 36
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = 'NeverPrompt'
config.window_padding = { left = 8, right = 8, top = 6, bottom = 4 }
config.keys = {
  { key = 'q', mods = 'CTRL|SHIFT', action = wezterm.action.SendKey { key = 'UpArrow', mods = 'ALT' } },
  { key = 'F1', mods = 'NONE', action = wezterm.action.SendKey { key = 'F1' } },
  { key = 'F12', mods = 'NONE', action = wezterm.action.SendKey { key = 'F12' } },
}
return config
