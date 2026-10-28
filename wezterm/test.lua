local wezterm = require 'wezterm'
local callbacks = {}
local original_on = wezterm.on
local original_enumerate_gpus = wezterm.gui.enumerate_gpus
local gpu_queries = 0

local function expect(condition, message)
  if not condition then
    wezterm.log_error(message)
    error(message)
  end
end

wezterm.on = function(name, callback)
  callbacks[name] = callback
end
wezterm.gui.enumerate_gpus = function()
  gpu_queries = gpu_queries + 1
  return original_enumerate_gpus()
end
wezterm.GLOBAL.available_gpus = nil

local config = dofile(wezterm.config_dir .. '/wezterm.lua')
dofile(wezterm.config_dir .. '/wezterm.lua')
expect(gpu_queries == 1, 'Color-driven reloads must reuse GPU discovery')
wezterm.on = original_on
wezterm.gui.enumerate_gpus = original_enumerate_gpus

local function tab(id)
  return {
    tab_id = function() return id end,
    get_title = function() return '' end,
  }
end

local active_tab, inactive_tab = tab(1), tab(2)
local active_pane = {
  get_user_vars = function() return { CLI_IDENTITY = 'codex-personal' } end,
  tab = function() return active_tab end,
  pane_id = function() return 10 end,
}
local inactive_pane = {
  get_user_vars = function() return { CLI_IDENTITY = '' } end,
  get_title = function() return 'pwsh.exe' end,
  tab = function() return inactive_tab end,
  pane_id = function() return 20 end,
}
active_tab.active_pane = function() return active_pane end
inactive_tab.active_pane = function() return inactive_pane end
local window = {
  active_pane = function() return active_pane end,
  active_tab = function() return active_tab end,
  get_config_overrides = function() return { colors = { background = '#10151f' } } end,
  is_focused = function() return false end,
}
wezterm.GLOBAL.tab_thread_1 = 'Active conversation'
wezterm.GLOBAL.tab_thread_2 = 'Finished conversation'
wezterm.GLOBAL.tab_title_freeze_1 = 'Active project'
wezterm.GLOBAL.tab_title_freeze_2 = 'Finished project'
callbacks['user-var-changed'](window, inactive_pane, 'CLI_IDENTITY')
expect(wezterm.GLOBAL.tab_thread_1 == 'Active conversation', 'Inactive CLI exit must preserve the active conversation title')
expect(wezterm.GLOBAL.tab_title_freeze_1 == 'Active project', 'Inactive CLI exit must preserve the active project title')
expect(wezterm.GLOBAL.tab_thread_2 == nil, 'CLI exit must clear its own conversation title')
expect(wezterm.GLOBAL.tab_title_freeze_2 == nil, 'CLI exit must clear its own project title')

local inactive_split = {
  get_user_vars = function() return { CLI_IDENTITY = '' } end,
  get_title = function() return 'pwsh.exe' end,
  tab = function() return active_tab end,
  pane_id = function() return 11 end,
}
callbacks['user-var-changed'](window, inactive_split, 'CLI_IDENTITY')
expect(wezterm.GLOBAL.tab_thread_1 == 'Active conversation', 'Inactive split exit must preserve the active conversation title')
expect(wezterm.GLOBAL.tab_title_freeze_1 == 'Active project', 'Inactive split exit must preserve the active project title')

local title_cells = callbacks['format-tab-title']({
  tab_id = 3,
  is_active = true,
  tab_title = '',
  active_pane = { title = 'Fix color responses - Codex', user_vars = { CLI_IDENTITY = 'codex-personal' } },
}, {}, {}, config, false, 80)
expect(title_cells[#title_cells].Text == ' Fix color responses ', 'Conversation title must exclude the CLI suffix')

wezterm.log_info('Config checks passed: GPU cache, inactive-tab isolation, conversation titles')
return config
