local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ══════════════════════════════════════════
--  Theme: Batman + overrides de legibilidad para Codex
-- ══════════════════════════════════════════
config.color_scheme = 'Batman'
config.colors = {
  foreground = '#f0f0f0',
  background = '#0a0a0c',
  -- Paleta compartida con apps/example-app/app/globals.css.
  ansi = {
    '#16161a',
    '#f83b61',
    '#b1f6b0',
    '#ffd463',
    '#82aaff',
    '#c792ea',
    '#b0f6f2',
    '#9a9aa2',
  },
  brights = {
    '#8c8c95',
    '#ff7070',
    '#c0f4b7',
    '#f8d675',
    '#a9c5ff',
    '#d1a9ff',
    '#bff4f2',
    '#f0f0f0',
  },
  selection_fg = '#ffffff',
  selection_bg = '#514321',
  scrollbar_thumb = '#3e3e48',
  split = '#2e2e36',
}

-- ══════════════════════════════════════════
--  Font
--  JetBrains Mono viene embebida en WezTerm (es la "bonita").
--  Cascadia Code / Consolas como fallback (instaladas en el sistema).
-- ══════════════════════════════════════════
config.font = wezterm.font_with_fallback {
  { family = 'JetBrains Mono', weight = 'Medium' },
  'Cascadia Code',
  'Consolas',
}
-- 9pt @96dpi en un 100% / 13.5pt en el portatil 150% (mismo tamaño visual
-- que 9pt nativo a 144dpi). El override por pantalla esta en apply_window_overrides.
config.font_size = 13.5
config.line_height = 1.0
-- Solo tipografia: no redimensionar la ventana al hacer Ctrl+/- o Ctrl+rueda.
config.adjust_window_size_when_changing_font_size = false

-- ══════════════════════════════════════════
--  DPI FIJO — arregla el baile de resize al mover la ventana
--  entre monitores con escalados distintos (portatil 2560x1600 @150%
--  vs externos 2560x1440 / 1920x1080 @100%).
--  96 = escalado 100%. La densidad del portatil se compensa subiendo
--  font_size a 13.5 cuando la ventana esta en esa pantalla, sin tocar DPI.
-- ══════════════════════════════════════════
config.dpi = 96
local FONT_SIZE_100 = 9
local FONT_SIZE_150 = 13.5

-- ══════════════════════════════════════════
--  Transparencia — DOS MODOS (cambia win32_system_backdrop):
--   A) 'Acrylic'  = cristal esmerilado: difumina lo de detrás,
--                   no se lee nada, look "glass". (más opaco visualmente)
--   B) 'Disable'  = transparencia REAL: ves NÍTIDO lo que hay detrás,
--                   solo atenuado. (modo actual)
--  window_background_opacity: más bajo = más transparente.
-- ══════════════════════════════════════════
config.window_background_opacity = 0.9
config.win32_system_backdrop = 'Disable'
config.text_background_opacity = 1

-- ══════════════════════════════════════════
--  Window (estilo original: tabs y decoración por defecto)
-- ══════════════════════════════════════════
-- Ancho maximo de cada pestana (retro tab bar). Default WezTerm: 16.
config.tab_max_width = 48
-- Fancy tab bar: la altura sigue a esta fuente. Default Windows: 10pt.
config.window_frame = {
  font = wezterm.font { family = 'JetBrains Mono', weight = 'Medium' },
  font_size = 12,
}
config.initial_cols = 120
config.initial_rows = 28
config.enable_scroll_bar = true
config.window_padding = {
  left = 14,
  right = 10,
  top = 10,
  bottom = 10,
}

-- No apagar los panes inactivos: todos conservan el mismo efecto Acrylic.
config.inactive_pane_hsb = {
  saturation = 1.0,
  brightness = 1.0,
}

-- ══════════════════════════════════════════
--  Performance & behavior
-- ══════════════════════════════════════════
config.scrollback_lines = 10000
config.audible_bell = 'Disabled'
config.animation_fps = 60
config.max_fps = 60

-- ══════════════════════════════════════════
--  GPU: fijar WezTerm a la iGPU (Intel Arc) vía WebGpu.
--  CLAVE: WebGpu permite elegir el adaptador EXPLÍCITAMENTE, así que
--  el render queda anclado a la iGPU. Si la NVIDIA RTX 5080 se
--  desconecta o sufre un TDR, las terminales NO se mueren porque
--  nunca dependieron de ella. El glass/Acrylic funciona igual con WebGpu.
--  Orden de preferencia:
--    1) Intel (iGPU) vía DX12 (Vulkan de Intel: sospechoso de los cuelgues de oct-2026)
--    2) Intel (iGPU) vía Vulkan
--    3) Software (CPU) como último recurso
--  (Nota: además dejé una preferencia de GPU de Windows -"Ahorro de
--   energía"- para wezterm-gui.exe como refuerzo. Se puede quitar si
--   prefieres que todo el forzado viva solo aquí en el .lua.)
-- ══════════════════════════════════════════
local picked_adapter = nil
local picked_backend = nil
-- Window color overrides reload this file; GPU discovery must not stall terminal replies.
local available_gpus = wezterm.GLOBAL.available_gpus
if not available_gpus then
  available_gpus = wezterm.gui.enumerate_gpus()
  wezterm.GLOBAL.available_gpus = available_gpus
end
for _, backend in ipairs({ 'Dx12', 'Vulkan' }) do
  for _, gpu in ipairs(available_gpus) do
    if gpu.device_type == 'IntegratedGpu' and gpu.backend == backend then
      picked_adapter = gpu
      picked_backend = backend
      break
    end
  end
  if picked_adapter then break end
end

if picked_adapter then
  config.front_end = 'WebGpu'
  config.webgpu_preferred_adapter = picked_adapter
  config.webgpu_power_preference = 'LowPower'
  wezterm.log_info('WezTerm GPU: iGPU ' .. picked_backend .. ' -> ' .. picked_adapter.name)
else
  -- sin iGPU detectada: render por CPU (lento pero inmune a crashes de GPU)
  config.front_end = 'Software'
  wezterm.log_warn('WezTerm GPU: sin iGPU, usando Software renderer')
end

-- ══════════════════════════════════════════
--  Shell: PowerShell
-- ══════════════════════════════════════════
config.default_prog = { 'pwsh.exe', '-NoLogo' }

-- ══════════════════════════════════════════
--  Keybindings
-- ══════════════════════════════════════════
config.keys = {
  -- Ctrl+C inteligente: copia si hay selección, si no manda Ctrl+C real
  {
    key = 'c',
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      local selection = window:get_selection_text_for_pane(pane)
      if selection == '' then
        window:perform_action(wezterm.action.SendKey { key = 'c', mods = 'CTRL' }, pane)
      else
        window:perform_action(wezterm.action.CopyTo 'ClipboardAndPrimarySelection', pane)
      end
    end),
  },
  -- Ctrl+V = Paste
  { key = 'v', mods = 'CTRL', action = wezterm.action.PasteFrom 'Clipboard' },
  -- Ctrl+Shift+C = Copy (forzado)
  { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.CopyTo 'Clipboard' },

  -- Pending Codex questions: send Alt+Up directly, bypassing pane navigation.
  { key = 'q', mods = 'CTRL|SHIFT', action = wezterm.action.SendKey { key = 'UpArrow', mods = 'ALT' } },

  -- Ctrl+Backspace = Delete word backward
  { key = 'Backspace', mods = 'CTRL', action = wezterm.action.SendKey { key = 'w', mods = 'CTRL' } },

  -- Ctrl+Shift+T = New tab
  { key = 't', mods = 'CTRL|SHIFT', action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  -- Ctrl+Shift+W = input del titulo (PromptInputLine). El menu de color/fondo
  -- no puede encadenar otro overlay: InputSelector se come el PromptInputLine.
  -- Click derecho sigue abriendo Ajustes rapidos.
  {
    key = 'w',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.EmitEvent 'rename-tab',
  },
  -- Abrir proyecto (repo -> tool -> perfil). N es el entry point;
  -- O queda de atajo extra. Ctrl+Shift+P es la paleta de WezTerm.
  {
    key = 'n',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.EmitEvent 'launch-project',
  },
  {
    key = 'o',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.EmitEvent 'launch-project',
  },

  -- Alt+1..5 = Switch tabs
  { key = '1', mods = 'ALT', action = wezterm.action.ActivateTab(0) },
  { key = '2', mods = 'ALT', action = wezterm.action.ActivateTab(1) },
  { key = '3', mods = 'ALT', action = wezterm.action.ActivateTab(2) },
  { key = '4', mods = 'ALT', action = wezterm.action.ActivateTab(3) },
  { key = '5', mods = 'ALT', action = wezterm.action.ActivateTab(4) },

  -- Split panes
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },

  -- Navigate panes with Alt+Arrows
  { key = 'LeftArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = wezterm.action.ActivatePaneDirection 'Down' },

  -- Font size
  { key = '+', mods = 'CTRL', action = wezterm.action.IncreaseFontSize },
  { key = '-', mods = 'CTRL', action = wezterm.action.DecreaseFontSize },
  { key = '0', mods = 'CTRL', action = wezterm.action.ResetFontSize },
}

-- Click derecho: menu al SOLTAR el boton. Down/Drag se anulan para que
-- mover el raton no cierre el overlay (si se abre en Down, el drag lo mata).
-- El par mouse_reporting true/false cubre panes normales y Claude.
local open_quick_menu = wezterm.action.EmitEvent 'edit-tab-appearance'
config.mouse_bindings = {}
for _, reporting in ipairs({ false, true }) do
  for _, kind in ipairs({ 'Down', 'Drag' }) do
    table.insert(config.mouse_bindings, {
      event = { [kind] = { streak = 1, button = 'Right' } },
      mods = 'NONE',
      mouse_reporting = reporting,
      action = wezterm.action.Nop,
    })
  end
  table.insert(config.mouse_bindings, {
    event = { Up = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    mouse_reporting = reporting,
    action = open_quick_menu,
  })
  table.insert(config.mouse_bindings, {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'CTRL',
    mouse_reporting = reporting,
    action = wezterm.action.IncreaseFontSize,
  })
  table.insert(config.mouse_bindings, {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'CTRL',
    mouse_reporting = reporting,
    action = wezterm.action.DecreaseFontSize,
  })
end

-- Account indicators set by the PowerShell CLI wrappers.
local amber = { accent = '#ffd463', background = '#19160e', tab = '#3a301b' }
local workspace_red = { name = 'Rojo', accent = '#ff8585', background = '#1c1013', tab = '#412126' }
local orange = { accent = '#ffb577', background = '#1d150f', tab = '#422e1d' }
local cli_styles = {
  claude = amber,
  codex = amber,
  grok = amber,
  ['claude-work'] = workspace_red,
  ['codex-work'] = workspace_red,
  ['devin-work'] = workspace_red,
  ['claude-personal'] = { accent = '#82aaff', background = '#10151f', tab = '#202f48' },
  ['codex-personal'] = { accent = '#82aaff', background = '#10151f', tab = '#202f48' },
  ['claude-secondary'] = { accent = '#b1f6b0', background = '#101a13', tab = '#203b28' },
  ['claude-api'] = orange,
  ['grok-api'] = orange,
  ['codex-api'] = orange,
}

local tab_palette = {
  { name = 'Amarillo / ambar', accent = '#ffd463', background = '#19160e', tab = '#3a301b' },
  workspace_red,
  { name = 'Verde', accent = '#b1f6b0', background = '#101a13', tab = '#203b28' },
  { name = 'Azul', accent = '#82aaff', background = '#10151f', tab = '#202f48' },
  { name = 'Violeta', accent = '#c792ea', background = '#191220', tab = '#342443' },
  { name = 'Turquesa', accent = '#b0f6f2', background = '#0e1a1b', tab = '#1c393b' },
  { name = 'Naranja', accent = '#ffb577', background = '#1d150f', tab = '#422e1d' },
  { name = 'Rosa', accent = '#f6a6d7', background = '#1d111a', tab = '#402238' },
}

local function tab_style(tab_id, user_vars)
  -- One choice per tab, shared by its panes and retained across config reloads.
  local manual = wezterm.GLOBAL['tab_tint_' .. tostring(tab_id)]
  return tab_palette[manual] or cli_styles[(user_vars or {}).CLI_IDENTITY]
end

local function title_freeze_key(tab_id)
  return 'tab_title_freeze_' .. tostring(tab_id)
end

-- Each wezterm-gui.exe is its own mux, so pane id 0 is reused in every window.
-- The PR-tag hook writes ~/.claude-hooks/pr-tag/panes/<WEZTERM_PANE>.txt and
-- used to paint [1324] onto every first tab. Tabs now show the session thread
-- name instead; PRs stay in the CLI status line.
local pr_prefix_pattern = '^%[%d[%d,%s%*]*%]%s*'

local function is_placeholder_title(title)
  if not title or title == '' then return true end
  local lower = title:lower()
  if lower:match('%.exe$') then return true end
  if lower:match('^[a-z]:[\\/]') then return true end
  return lower == 'pwsh' or lower == 'powershell' or lower == 'cmd'
    or lower == 'claude' or lower == 'grok' or lower == 'codex'
end

local function is_status_title(title)
  local lower = title:lower()
  return lower:match('^thinking') or lower:match('^running:') or lower:match('^waiting')
end

local function thread_from_osc(title)
  if not title or title == '' then return nil end
  title = title:gsub('%s*%-%s*[Gg]rok%s*$', '')
  title = title:gsub('%s*%-%s*[Cc]laude%s*$', '')
  title = title:gsub('%s*%-%s*[Cc]odex%s*$', '')
  title = title:gsub('^[^%w%[]+%s*', '')
  title = title:gsub('^Thinking%s*%-%s*', '')
  title = title:gsub('^Running:%s.-%s*%-%s*', '')
  title = title:gsub(pr_prefix_pattern, '')
  title = title:gsub('^%s+', ''):gsub('%s+$', '')
  if is_placeholder_title(title) or is_status_title(title) then return nil end
  return title
end

local function thread_latch_key(tab_id)
  return 'tab_thread_' .. tostring(tab_id)
end

local function cli_tab_title(pane, tab_id)
  local live = thread_from_osc(pane.title)
  local key = thread_latch_key(tab_id)
  if live then wezterm.GLOBAL[key] = live end
  return wezterm.GLOBAL[key]
end

local tab_title_sources = {
  codex = cli_tab_title,
  claude = cli_tab_title,
  grok = cli_tab_title,
}

local function tab_display_title(tab)
  local pane = tab.active_pane
  local identity = (pane.user_vars or {}).CLI_IDENTITY or ''
  local source = tab_title_sources[identity:match('^[^-]+')]
  local automatic_title
  if source then automatic_title = source(pane, tab.tab_id) end
  local title = tab.tab_title
  if not title or title == '' then
    title = automatic_title or wezterm.GLOBAL[title_freeze_key(tab.tab_id)] or pane.title
  end
  return title
end

wezterm.on('format-tab-title', function(tab, tabs, panes, effective_config, hover, max_width)
  local style = tab_style(tab.tab_id, tab.active_pane.user_vars)
  local title = tab_display_title(tab)
  if not style then
    return wezterm.truncate_right(title, max_width)
  end
  title = wezterm.truncate_right(title, math.max(1, max_width - 2))
  return {
    { Background = { Color = (tab.is_active or hover) and style.tab or style.background } },
    { Foreground = { Color = style.accent } },
    { Text = ' ' .. title .. ' ' },
  }
end)

local function is_dense_laptop_screen(screen)
  if not screen then return false end
  local w, h = screen.width, screen.height
  -- 2560x1600 fisico, o 1707x1067 logico @150%.
  if w >= 2500 and w <= 2620 and h >= 1550 and h <= 1650 then return true end
  if w >= 1680 and w <= 1740 and h >= 1040 and h <= 1100 then return true end
  return false
end

local function font_size_for_focused_screen(window)
  local ok_dims, dims = pcall(function() return window:get_dimensions() end)
  if ok_dims and dims and dims.dpi and dims.dpi >= 120 then return FONT_SIZE_150 end
  if not wezterm.gui then return FONT_SIZE_150 end
  local ok_screens, screens = pcall(wezterm.gui.screens)
  if ok_screens and is_dense_laptop_screen(screens.active) then return FONT_SIZE_150 end
  return FONT_SIZE_100
end

local function apply_window_overrides(window)
  -- Tint follows the selected pane; font follows the screen (DPI fijo).
  local pane = window:active_pane()
  if not pane then return end
  local tab = window:active_tab()
  if not tab then return end
  local style = tab_style(tab:tab_id(), pane:get_user_vars())
  local background = style and style.background or config.colors.background
  local overrides = window:get_config_overrides() or {}
  local current_bg = overrides.colors and overrides.colors.background or config.colors.background
  local want_font = overrides.font_size
  local ok_focus, focused = pcall(function() return window:is_focused() end)
  if ok_focus and focused then
    want_font = font_size_for_focused_screen(window)
    if want_font == config.font_size then want_font = nil end
  end
  local current_font = overrides.font_size
  if current_bg == background and current_font == want_font then return end
  local colors = {}
  for key, value in pairs(config.colors) do colors[key] = value end
  for key, value in pairs(overrides.colors or {}) do colors[key] = value end
  colors.background = background
  overrides.colors = colors
  overrides.font_size = want_font
  window:set_config_overrides(overrides)
end

local function suggested_tab_name(window, pane)
  local tab = window:active_tab()
  if not tab then return '' end
  local custom = tab:get_title() or ''
  if custom ~= '' then return custom end
  local latch = wezterm.GLOBAL[thread_latch_key(tab:tab_id())]
  if latch and latch ~= '' then return latch end
  return thread_from_osc(pane:get_title()) or pane:get_title() or ''
end

local function apply_tab_name(window, line)
  if line == nil then return end
  local tab = window:active_tab()
  if not tab then return end
  if line == '' then
    tab:set_title('')
    wezterm.GLOBAL[title_freeze_key(tab:tab_id())] = nil
    wezterm.GLOBAL[thread_latch_key(tab:tab_id())] = nil
  else
    tab:set_title(line)
  end
end

wezterm.on('rename-tab', function(window, pane)
  -- PromptInputLine tiene que ser el overlay de primer nivel. Encadenarlo
  -- al cerrar InputSelector (el menu de Ajustes) no llega a pintarse.
  window:perform_action(
    wezterm.action.PromptInputLine {
      description = 'Nombre de la tab (enter: override, vacio: automatico)',
      initial_value = suggested_tab_name(window, pane),
      action = wezterm.action_callback(function(win, _, line)
        apply_tab_name(win, line)
      end),
    },
    pane
  )
end)

local function window_is_solid(window)
  local overrides = window:get_config_overrides() or {}
  local opacity = overrides.window_background_opacity
  if opacity == nil then
    opacity = config.window_background_opacity
  end
  return opacity >= 0.999
end

local function set_window_opacity(window, opacity)
  local overrides = window:get_config_overrides() or {}
  overrides.window_background_opacity = opacity
  window:set_config_overrides(overrides)
end

local show_quick_menu

-- Recetas: una por fila. aside pega /btw (Claude, Grok) o /side (Codex)
-- para no cortar el turno. Tests va al hilo: necesita tools.
local recipes = {
  { id = 'recipe-resume', label = 'Resume', aside = true, prompt = 'Resume el estado, lo pendiente y el siguiente paso concreto.' },
  { id = 'recipe-diff', label = 'Diff', aside = true, prompt = 'Revisa git diff / cambios locales y senala riesgos.' },
  { id = 'recipe-tests', label = 'Tests', prompt = 'Mira los tests que fallan o el comando de test del repo y arregla lo concreto.' },
  { id = 'recipe-pr', label = 'PR', aside = true, prompt = 'Resume el branch, lo que falta y si esto esta listo para PR.' },
}

local function pane_cli_family(pane)
  local identity = string.lower((pane:get_user_vars() or {}).CLI_IDENTITY or '')
  if identity:match('^codex') then return 'codex' end
  if identity:match('^grok') then return 'grok' end
  if identity:match('^claude') then return 'claude' end
  local title = string.lower(pane:get_title() or '')
  if title:find('codex', 1, true) then return 'codex' end
  if title:find('grok', 1, true) then return 'grok' end
  if title:find('claude', 1, true) then return 'claude' end
  return nil
end

local function pane_is_agent(pane)
  return pane_cli_family(pane) ~= nil
end

local function recipe_send_text(pane, recipe)
  local text = recipe.prompt
  if recipe.aside then
    local prefix = pane_cli_family(pane) == 'codex' and '/side ' or '/btw '
    text = prefix .. text
  end
  return text .. '\r'
end

local function fill_row(text, cols)
  local t = '  ' .. text
  local pad = math.max(1, cols - wezterm.column_width(t) - 1)
  return t .. string.rep(' ', pad)
end

local function swatch_row(checked, accent, cols)
  local mark = checked and '[x] ' or '[ ] '
  local prefix = '  ' .. mark
  local pad = math.max(1, cols - wezterm.column_width(prefix .. '■■') - 1)
  return wezterm.format {
    { Text = prefix },
    { Foreground = { Color = accent } },
    { Text = '■■' .. string.rep(' ', pad) },
  }
end

local function focus_menu_row(window, pane, index)
  if not index or index <= 1 then return end
  local keys = {}
  for _ = 2, index do
    table.insert(keys, wezterm.action.SendKey { key = 'DownArrow' })
  end
  wezterm.time.call_after(0.05, function()
    if not wezterm.GLOBAL.quick_menu_open then return end
    window:perform_action(wezterm.action.Multiple(keys), pane)
  end)
end

local function close_quick_menu(window, pane)
  wezterm.GLOBAL.quick_menu_open = false
  window:perform_action(wezterm.action.SendKey { key = 'Escape' }, pane)
end

show_quick_menu = function(window, pane, focus)
  local tab = window:active_tab()
  if not tab then return end
  local tab_id = tab:tab_id()
  local custom_title = tab:get_title() or ''

  local color_index = wezterm.GLOBAL['tab_tint_' .. tostring(tab_id)] or 0
  local solid = window_is_solid(window)
  local fondo_label = solid
    and '[x] solido   [ ] transparente'
    or '[ ] solido   [x] transparente'

  local dims = pane:get_dimensions()
  local cols = dims.cols or 80
  local rows = dims.viewport_rows or 24
  -- title, 3 gaps, color-0, palette, fondo, hdr, recipes, abrir
  local real_count = 8 + #tab_palette + #recipes
  local chrome = 3
  local pad_top = math.max(1, math.floor((rows - chrome - real_count) / 2))

  local choices = {}
  for _ = 1, pad_top do
    table.insert(choices, { id = '_pad', label = ' ' })
  end
  table.insert(choices, { id = 'title', label = fill_row('Titulo: ' .. (custom_title ~= '' and custom_title or '(automatico)'), cols) })
  table.insert(choices, { id = '_gap', label = ' ' })
  table.insert(choices, {
    id = 'color-0',
    label = swatch_row(color_index == 0, '#9a9aa2', cols),
  })
  for index, style in ipairs(tab_palette) do
    table.insert(choices, {
      id = 'color-' .. tostring(index),
      label = swatch_row(color_index == index, style.accent, cols),
    })
  end
  table.insert(choices, { id = 'fondo', label = fill_row('Fondo: ' .. fondo_label, cols) })
  table.insert(choices, { id = '_gap', label = ' ' })
  table.insert(choices, { id = '_hdr', label = fill_row('┌ recetas', cols) })
  for _, recipe in ipairs(recipes) do
    table.insert(choices, { id = recipe.id, label = fill_row('│ ' .. recipe.label, cols) })
  end
  table.insert(choices, { id = '_gap', label = ' ' })
  if os.getenv('WEZTERM_REMOTE_DOMAIN') then
    table.insert(choices, { id = 'remote-sessions', label = fill_row('Sesiones (Ctrl+Shift+S)', cols) })
  end
  table.insert(choices, { id = 'launch', label = fill_row('Abrir proyecto', cols) })

  local focus_index = pad_top + 1
  if focus then
    for index, choice in ipairs(choices) do
      if choice.id == focus then
        focus_index = index
        break
      end
    end
  end

  wezterm.GLOBAL.quick_menu_open = true
  window:perform_action(wezterm.action.InputSelector {
    title = 'Ajustes rapidos',
    description = 'Click: toggle y cierra    Esc / click derecho: cerrar',
    alphabet = '',
    choices = choices,
    action = wezterm.action_callback(function(sel_window, sel_pane, id)
      if id == '_gap' then
        show_quick_menu(sel_window, sel_pane, focus)
        return
      end
      if not id or id == '_pad' or id == '_hdr' then
        wezterm.GLOBAL.quick_menu_open = false
        return
      end
      wezterm.GLOBAL.quick_menu_open = false
      local color_n = id:match('^color%-(%d+)$')
      if color_n then
        local n = tonumber(color_n)
        local current = wezterm.GLOBAL['tab_tint_' .. tostring(tab_id)] or 0
        if current == n then
          wezterm.GLOBAL['tab_tint_' .. tostring(tab_id)] = 0
        else
          wezterm.GLOBAL['tab_tint_' .. tostring(tab_id)] = n
        end
        apply_window_overrides(sel_window)
        return
      end
      if id == 'title' then
        wezterm.time.call_after(0.15, function()
          sel_window:perform_action(wezterm.action.EmitEvent 'rename-tab', sel_pane)
        end)
      elseif id == 'fondo' then
        if window_is_solid(sel_window) then
          set_window_opacity(sel_window, config.window_background_opacity)
        else
          set_window_opacity(sel_window, 1.0)
        end
      elseif id:find('^recipe%-') then
        if not pane_is_agent(sel_pane) then return end
        for _, recipe in ipairs(recipes) do
          if recipe.id == id then
            sel_pane:send_text(recipe_send_text(sel_pane, recipe))
            break
          end
        end
      elseif id == 'remote-sessions' then
        wezterm.time.call_after(0.1, function()
          sel_window:perform_action(wezterm.action.EmitEvent 'remote-sessions', sel_pane)
        end)
      elseif id == 'launch' then
        wezterm.time.call_after(0.05, function()
          sel_window:perform_action(wezterm.action.EmitEvent 'launch-project', sel_pane)
        end)
      end
    end),
  }, pane)
  focus_menu_row(window, pane, focus_index)
end

wezterm.on('edit-tab-appearance', function(window, pane)
  if wezterm.GLOBAL.quick_menu_open then
    close_quick_menu(window, pane)
    return
  end
  -- Espera a que termine el click (up/drag) para que no cierre el overlay.
  wezterm.time.call_after(0.05, function()
    if wezterm.GLOBAL.quick_menu_open then return end
    show_quick_menu(window, pane)
  end)
end)

-- Abrir proyecto: repo -> tool -> perfil. Un InputSelector por paso
-- (WezTerm no tiene sub-botones en una fila). Anade repos a launch_repos.
local launch_repos = {
  {
    id = 'example-project',
    label = 'example-project',
    cwd = table.concat({ wezterm.home_dir, 'Desktop', 'projects', 'example-project' }, '\\'),
  },
}

local launch_tools = {
  {
    id = 'claude',
    label = 'claude',
    profiles = {
      { id = 'claude', label = 'default' },
      { id = 'claude-work', label = 'sap' },
      { id = 'claude-personal', label = 'vei' },
      { id = 'claude-secondary', label = 'bg' },
      { id = 'claude-api', label = 'api' },
    },
  },
  {
    id = 'grok',
    label = 'grok',
    profiles = {
      { id = 'grok', label = 'default  xAI' },
      { id = 'grok-api', label = 'api  Azure' },
    },
  },
  {
    id = 'codex',
    label = 'codex',
    profiles = {
      { id = 'codex', label = 'default' },
      { id = 'codex-work', label = 'sap' },
      { id = 'codex-personal', label = 'vei' },
      { id = 'codex-api', label = 'api  Azure' },
    },
  },
}

local function find_by_id(list, id)
  for _, item in ipairs(list) do
    if item.id == id then return item end
  end
end

local function ps_single_quote(s)
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

local function spawn_project_tab(window, repo, command)
  local mux_win = window:mux_window()
  if not mux_win then return end
  -- En Windows el cwd de spawn_tab a menudo se ignora (cae a $HOME).
  -- -WorkingDirectory + Set-Location fuerzan el repo antes de lanzar el CLI.
  local script = string.format(
    'Set-Location -LiteralPath %s; %s',
    ps_single_quote(repo.cwd),
    command
  )
  local tab = mux_win:spawn_tab {
    cwd = repo.cwd,
    args = {
      'pwsh.exe',
      '-NoLogo',
      '-NoExit',
      '-WorkingDirectory',
      repo.cwd,
      '-Command',
      script,
    },
  }
  if tab then
    wezterm.GLOBAL[title_freeze_key(tab:tab_id())] = repo.label
  end
end

local show_launch_profiles

local function show_launch_tools(window, pane, repo)
  local choices = {}
  for _, tool in ipairs(launch_tools) do
    table.insert(choices, { id = tool.id, label = '  ' .. tool.label })
  end
  window:perform_action(wezterm.action.InputSelector {
    title = '2/3  tool  ·  ' .. repo.label,
    description = 'claude / grok / codex     Esc: cancelar',
    alphabet = '',
    choices = choices,
    action = wezterm.action_callback(function(sel_window, sel_pane, id)
      if not id then return end
      local tool = find_by_id(launch_tools, id)
      if tool then
        show_launch_profiles(sel_window, sel_pane, repo, tool)
      end
    end),
  }, pane)
end

show_launch_profiles = function(window, pane, repo, tool)
  local choices = {}
  for _, profile in ipairs(tool.profiles) do
    table.insert(choices, { id = profile.id, label = '  ' .. profile.label })
  end
  window:perform_action(wezterm.action.InputSelector {
    title = '3/3  perfil  ·  ' .. repo.label .. ' / ' .. tool.label,
    description = 'Abre pestaña nueva en el repo     Esc: cancelar',
    alphabet = '',
    choices = choices,
    action = wezterm.action_callback(function(sel_window, _, id)
      if not id then return end
      spawn_project_tab(sel_window, repo, id)
    end),
  }, pane)
end

wezterm.on('launch-project', function(window, pane)
  if os.getenv('WEZTERM_REMOTE_DOMAIN') then
    window:perform_action(wezterm.action.EmitEvent 'launch-remote-project', pane)
    return
  end
  local choices = {}
  for _, repo in ipairs(launch_repos) do
    table.insert(choices, { id = repo.id, label = '  ' .. repo.label })
  end
  window:perform_action(wezterm.action.InputSelector {
    title = '1/3  repo',
    description = 'Por ahora solo example-project     Esc: cancelar',
    alphabet = '',
    choices = choices,
    action = wezterm.action_callback(function(sel_window, sel_pane, id)
      if not id then return end
      local repo = find_by_id(launch_repos, id)
      if repo then
        show_launch_tools(sel_window, sel_pane, repo)
      end
    end),
  }, pane)
end)

config.status_update_interval = 200
wezterm.on('update-status', apply_window_overrides)
wezterm.on('user-var-changed', function(window, pane, name)
  if name ~= 'CLI_IDENTITY' then return end
  apply_window_overrides(window)
  local tab = pane:tab()
  if not tab then return end
  local tab_pane = tab:active_pane()
  if not tab_pane or tab_pane:pane_id() ~= pane:pane_id() then return end
  local identity = (pane:get_user_vars() or {}).CLI_IDENTITY
  local key = title_freeze_key(tab:tab_id())
  if identity and identity ~= '' then
    local live = pane:get_title()
    if (tab:get_title() or '') == '' and not wezterm.GLOBAL[key] and not is_placeholder_title(live) then
      wezterm.GLOBAL[key] = live
    end
  else
    wezterm.GLOBAL[key] = nil
    wezterm.GLOBAL[thread_latch_key(tab:tab_id())] = nil
  end
end)

return config
