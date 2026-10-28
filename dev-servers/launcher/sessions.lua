local wezterm = require 'wezterm'
local M = {}
-- Box-specific values arrive through M.configure(config, box).
local domain, remote_root, preference_path
local ssh = 'C:/Windows/System32/OpenSSH/ssh.exe'
local picker_state = {}
local picker_keys = 'remote_session_picker'

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Read and close through the same remote mux. Client-side pane IDs are not
-- server-side IDs. Socket identity also prevents acting on a restarted mux.
local snapshot_python = [=[
import json, os, subprocess
socket = os.path.expanduser('~/.local/state/wezterm/dev-server.sock')
env = dict(os.environ, WEZTERM_UNIX_SOCKET=socket)
def snapshot(name):
    info = os.stat(socket)
    rows = json.loads(subprocess.check_output(['/usr/bin/wezterm','cli','--no-auto-start','list','--format','json'],env=env))
    panes = sorted([r['pane_id'],r['tab_id'],r['window_id']] for r in rows if r['workspace']==name)
    return {'name':name,'socket':[str(info.st_dev),str(info.st_ino),str(info.st_ctime_ns)],'panes':panes}
]=]

local function remote_python(source)
  return wezterm.run_child_process {
    ssh, '-n', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
    '-o', 'ServerAliveInterval=3', '-o', 'ServerAliveCountMax=2', domain,
    'timeout 15s python3 -c ' .. shell_quote(source),
  }
end

function M.close_session(window, pane, name)
  local ok, output = remote_python(snapshot_python
    .. '\nprint(json.dumps(snapshot(' .. wezterm.json_encode(name) .. ')))')
  local parsed, snapshot = pcall(wezterm.json_parse, output or '')
  if not ok or not parsed or not snapshot.panes or #snapshot.panes == 0 then
    window:toast_notification('Sesiones', 'No se pudo verificar la sesion; no se ha cerrado nada.', nil, 5000)
    return
  end
  window:perform_action(wezterm.action.InputSelector {
    title = 'Cerrar sesion: ' .. M.display_name(name),
    description = 'Termina los procesos adjuntos de sus ' .. #snapshot.panes
      .. ' paneles; no es desconectar. Los procesos separados pueden seguir vivos.',
    fuzzy = false,
    choices = {
      { id = 'cancel', label = 'Cancelar (conservar sesion)' },
      { id = 'close', label = 'Cerrar ' .. M.display_name(name) .. ' y sus ' .. #snapshot.panes .. ' paneles' },
    },
    action = wezterm.action_callback(function(win, _, choice)
      if choice ~= 'close' then return end
      local expected = wezterm.json_encode(snapshot)
      local success = remote_python(snapshot_python .. '\nexpected = json.loads('
        .. wezterm.json_encode(expected) .. ')\n'
        .. [=[if snapshot(expected['name']) != expected:
    raise SystemExit('Session changed; reopen confirmation')
for pane_id, tab_id, window_id in expected['panes']:
    current = snapshot(expected['name'])
    if current['socket'] != expected['socket'] or [pane_id,tab_id,window_id] not in current['panes']:
        raise SystemExit('Session changed during close')
    subprocess.run(['/usr/bin/wezterm','cli','--no-auto-start','kill-pane','--pane-id',str(pane_id)],env=env,check=True)
]=])
      if not success then
        win:toast_notification('Sesiones', 'La sesion cambio o fallo el cierre. Revisa las sesiones; no se reintenta automaticamente.', nil, 6000)
      end
    end),
  }, pane)
end

function M.display_name(name)
  return name == 'default' and 'General' or name
end

local function clean(value)
  if type(value) ~= 'string' then return '' end
  return value:gsub('%c', ' '):match('^%s*(.-)%s*$')
end

local harnesses = {
  devin = 'Devin', codex = 'Codex', pi = 'Pi', claude = 'Claude',
  grok = 'Grok', gemini = 'Gemini',
}

function M.devin_footer_summary(text)
  local lines = {}
  for line in (text .. '\n'):gmatch('(.-)\n') do
    table.insert(lines, (line:gsub('\r$', ''):gsub('%s+$', '')))
  end
  local function border(line)
    return line and line:sub(1, #'────────') == '────────'
  end
  for index = math.max(4, #lines - 2), #lines do
    local line = lines[index]
    if line:match('^SWE%-2 High%s+Context:%s*%d+[kKmM]?%s*/%s*%d+[kKmM]? tokens %(%d+%%%)$')
      and border(lines[index - 1]) and border(lines[index - 3])
      and lines[index - 2]:match('^❭ ') then
      local status = lines[index - 4] or ''
      local running = status:match('^[^%w]*Thinking · [%dhms ]+ %(esc twice to interrupt%)$')
      -- A ready composer can coexist with queued/background work above this region.
      return { model = 'SWE-2 High', state = running and 'running' or 'unknown' }
    end
  end
  return { state = 'unknown' }
end

function M.pane_summary(pane, include_footer)
  local ok, vars = pcall(function() return pane:get_user_vars() end)
  vars = ok and vars or {}
  local title = clean(pane:get_title())
  local identity = clean(vars.CLI_IDENTITY):lower():match('^[^-]+')
  local harness = harnesses[identity]
  local task = title
  if not harness then
    local prefix, rest = title:match('^(%a+):%s*(.*)$')
    local suffix = title:match('%s%-%s*(%a+)$')
    harness = harnesses[(prefix or suffix or ''):lower()]
    if harness and prefix then task = rest end
  end
  if harness then
    task = task:gsub('%s%-%s*%a+$', function(suffix)
      return harnesses[suffix:match('(%a+)$'):lower()] and '' or suffix
    end)
  else
    task = ''
  end
  -- Only explicit terminal status is evidence; quiet output is not idle.
  local lower = title:lower()
  local state = 'unknown'
  if lower:match('^thinking%s*%-') or lower:match('^running:') then
    state = 'running'
  elseif lower:match('^loading[%s:]') then
    state = 'loading'
  elseif lower:match('^waiting[%s:]') then
    state = lower:match('%f[%a]ci%f[%A]') and 'waiting for CI' or 'waiting'
  elseif lower == 'idle' or lower:match('^idle%s*%-') then
    state = 'idle'
  end
  local model
  if include_footer and harness == 'Devin' then
    local footer_ok, footer = pcall(function()
      local dims = pane:get_dimensions()
      -- Read current physical screen rows only, on picker open; never scrollback.
      return pane:get_lines_as_text(math.min(8, dims.viewport_rows))
    end)
    if footer_ok and type(footer) == 'string' then
      local detail = M.devin_footer_summary(footer)
      if detail.state ~= 'unknown' then state = detail.state end
      model = detail.model
    end
  end
  -- agent-spawn labels each pane with CLI_IDENTITY and CLI_MODEL user vars.
  local declared_model = clean(vars.CLI_MODEL)
  if not model and declared_model ~= '' then model = declared_model end
  return { harness = harness or 'Unknown', state = state, task = clean(task), model = model }
end

function M.label(session, active)
  local parts = { (session.name == active and '> ' or '  ') .. M.display_name(session.name) }
  local seen = {}
  for _, summary in ipairs(session.panes) do
    local detail = summary.harness .. ' / ' .. summary.state
    if summary.model then detail = detail .. ' / ' .. summary.model end
    if summary.task ~= '' and summary.task:lower() ~= session.name:lower() then
      detail = detail .. ' / ' .. wezterm.truncate_right(summary.task, 64)
    end
    if not seen[detail] then
      table.insert(parts, detail)
      seen[detail] = true
    end
  end
  if session.windows > 1 then table.insert(parts, session.windows .. ' ventanas') end
  if session.tabs > 1 then table.insert(parts, session.tabs .. ' pestanas') end
  if #session.panes > session.tabs then table.insert(parts, #session.panes .. ' paneles') end
  return table.concat(parts, '  |  ')
end

function M.list(include_footer)
  local by_name = {}
  for _, mux_window in ipairs(wezterm.mux.all_windows()) do
    local name = mux_window:get_workspace()
    local entry = by_name[name] or { name = name, windows = 0, tabs = 0, panes = {} }
    entry.windows = entry.windows + 1
    entry.tabs = entry.tabs + #mux_window:tabs()
    for _, tab in ipairs(mux_window:tabs()) do
      for _, pane in ipairs(tab:panes()) do
        table.insert(entry.panes, M.pane_summary(pane, include_footer))
      end
    end
    by_name[name] = entry
  end
  local entries = {}
  for _, entry in pairs(by_name) do table.insert(entries, entry) end
  table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
  return entries
end

function M.remember(name)
  if not name or name == '' or name:find('[\r\n]') then return end
  if wezterm.GLOBAL.remote_last_session == name then return end
  local file = io.open(preference_path, 'w')
  if file then
    file:write(name .. '\n')
    file:close()
    wezterm.GLOBAL.remote_last_session = name
  end
end

local function current_directory(pane)
  -- Prompt/selector callbacks may hand back their already-closed overlay pane.
  local ok, cwd = pcall(function() return pane and pane:get_current_working_dir() end)
  if not ok then return remote_root end
  if cwd then
    local path = tostring(cwd):match('^file://[^/]*(/.*)$')
    if path and not path:match('^/[A-Za-z]:') then
      return (path:gsub('%%(%x%x)', function(hex)
        return string.char(tonumber(hex, 16))
      end))
    end
  end
  return remote_root
end

local function real_pane(window)
  local ok, p = pcall(function() return window:active_tab():active_pane() end)
  if ok then return p end
end

function M.create(window, pane, name)
  name = (name or ''):gsub('%c', ' '):match('^%s*(.-)%s*$')
  if name == '' then return end
  if name:lower() == 'general' then name = 'default' end
  for _, session in ipairs(M.list()) do
    if session.name == name then
      wezterm.GLOBAL.remote_pending_session = { name = name, deadline = os.time() + 15 }
      return
    end
  end
  -- A repeat request can arrive before this client lists the first window.
  local creating = wezterm.GLOBAL.remote_creating_session
  if creating and creating.name == name and os.time() < creating.deadline then return end
  wezterm.GLOBAL.remote_creating_session = { name = name, deadline = os.time() + 15 }
  -- Create through this GUI's own attached domain: a workspace spawned out of band
  -- (ssh + wezterm cli) never reaches this client's window list, so it could not be selected.
  -- Callback panes are the closing prompt/selector overlay ("pane id N is not valid"):
  -- wait for it to close, then act on the tab's real pane.
  wezterm.time.call_after(0.15, function()
    local real = real_pane(window)
    if not real then return end
    -- SwitchToWorkspace{spawn=...} sends a Windows CommandBuilder (with the local
    -- environment) that the Linux mux cannot decode ("cannot deserialize Windows OS
    -- string on Unix"), dropping the connection. mux.spawn_window without args sends
    -- no command, like new tabs do, and goes through this client's own domain.
    local ok, err = pcall(function()
      local _, _, mux_window = wezterm.mux.spawn_window {
        domain = { DomainName = domain },
        workspace = name,
        cwd = current_directory(real),
      }
      -- The client domain spawns remotely in the *active* workspace, ignoring
      -- `workspace`: the server would file this window under the session we are
      -- leaving, and the new session would vanish on reconnect. Only a local
      -- workspace change is forwarded (SetWindowWorkspace), and setting the same
      -- name is a no-op, so step through a temporary name; the forwarder reads
      -- the final name when it runs.
      mux_window:set_workspace(name .. ' (moving)')
      mux_window:set_workspace(name)
    end)
    if not ok then
      window:toast_notification('Sesiones', 'No se pudo crear la sesion: ' .. tostring(err), nil, 6000)
      return
    end
    window:perform_action(wezterm.action.SwitchToWorkspace { name = name }, real)
    M.remember(name)
  end)
end

function M.show(window, pane)
  local window_id = window:window_id()
  local open = picker_state[window_id]
  -- The guard only stops a double open. A selector closed without calling back
  -- (overlay replaced, workspace switched) must not block the shortcut for good.
  if open and os.time() - (open.opened or 0) < 3 then
    wezterm.log_info('sessions: picker already open, ignoring Ctrl+Shift+S')
    return
  end
  wezterm.log_info('sessions: opening picker' .. (open and ' (stale guard cleared)' or ''))
  local active = window:active_workspace()
  local sessions = M.list(true)
  table.sort(sessions, function(a, b)
    if a.name == active then return b.name ~= active end
    if b.name == active then return false end
    return a.name:lower() < b.name:lower()
  end)
  local new_session_id = '__new_session__'
  local choices = { { id = new_session_id, label = '  + Nueva sesion...  (Ctrl+Shift+A)' } }
  for _, session in ipairs(sessions) do
    table.insert(choices, {
      id = session.name,
      label = M.label(session, active),
    })
  end
  local state = { closing = false, opened = os.time() }
  picker_state[window_id] = state
  window:perform_action(wezterm.action.ActivateKeyTable {
    name = picker_keys, one_shot = false,
  }, pane)
  window:perform_action(wezterm.action.InputSelector {
    title = 'Sesiones vivas en ' .. domain,
    description = 'Enter: recuperar   Supr: cerrar sesion   Esc: volver',
    fuzzy_description = 'Buscar sesion  |  Enter: recuperar (o + Nueva sesion)   Supr: cerrar sesion   Esc: volver',
    fuzzy = true,
    choices = choices,
    action = wezterm.action_callback(function(win, original_pane, name)
      picker_state[window_id] = nil
      win:perform_action(wezterm.action.PopKeyTable, original_pane)
      if not name then return end
      if name == new_session_id then
        if not state.closing then
          -- The selector overlay is still closing here; prompt on the real pane once it is gone.
          wezterm.time.call_after(0.15, function()
            local real = real_pane(win)
            if real then win:perform_action(wezterm.action.EmitEvent 'remote-session-new', real) end
          end)
        end
        return
      end
      if state.closing then
        M.close_session(win, original_pane, name)
        return
      end
      -- Only resume a workspace that still exists; do not recreate ended tasks.
      for _, session in ipairs(M.list()) do
        if session.name == name then
          wezterm.GLOBAL.remote_pending_session = nil
          win:perform_action(wezterm.action.SwitchToWorkspace { name = name }, original_pane)
          M.remember(name)
          return
        end
      end
    end),
  }, pane)
end

function M.bind(box)
  domain = box.domain
  remote_root = '/home/' .. box.user .. '/projects'
  preference_path = box.preference_path
end

function M.configure(config, box)
  M.bind(box)
  config.key_tables = config.key_tables or {}
  config.key_tables[picker_keys] = {
    { key = 'Delete', mods = 'NONE', action = wezterm.action_callback(function(window, pane)
      local state = picker_state[window:window_id()]
      if not state or state.closing then return end
      state.closing = true
      -- Let the native selector resolve its highlighted row, including fuzzy
      -- matching. The callback above removes the key table before confirmation.
      window:perform_action(wezterm.action.SendKey { key = 'Enter' }, pane)
      -- Enter has no selection when the filter is empty. Escape targets this
      -- same overlay ID only, clearing its close intent in that case.
      pcall(function()
        window:perform_action(wezterm.action.SendKey { key = 'Escape' }, pane)
      end)
    end) },
  }
  table.insert(config.keys, {
    key = 's', mods = 'CTRL|SHIFT',
    action = wezterm.action.EmitEvent 'remote-sessions',
  })
  table.insert(config.keys, {
    key = 'a', mods = 'CTRL|SHIFT',
    action = wezterm.action.EmitEvent 'remote-session-new',
  })
  wezterm.on('remote-sessions', M.show)
  wezterm.on('remote-session-new', function(window, pane)
    window:perform_action(wezterm.action.PromptInputLine {
      description = 'Nombre de la sesion (por ejemplo: main-tests o feature-api)',
      action = wezterm.action_callback(function(win, original_pane, name)
        if name then M.create(win, original_pane, name) end
      end),
    }, pane)
  end)
  wezterm.on('update-status', function(window)
    local remote = wezterm.mux.get_domain(domain)
    if not remote or remote:state() ~= 'Attached' then return end
    local pending = wezterm.GLOBAL.remote_pending_session
    if type(pending) == 'string' then
      pending = { name = pending, deadline = os.time() + 15 }
      wezterm.GLOBAL.remote_pending_session = pending
    end
    if pending then
      if window:active_workspace() == pending.name
        and window:mux_window():get_workspace() == pending.name then
        wezterm.GLOBAL.remote_pending_session = nil
        M.remember(pending.name)
      elseif os.time() > pending.deadline then
        wezterm.GLOBAL.remote_pending_session = nil
        window:toast_notification('Sesiones', 'La sesion existe pero no se pudo seleccionar. Recuperala con Ctrl+Shift+S.', nil, 5000)
      else
        for _, session in ipairs(M.list()) do
          if session.name == pending.name then
            -- Only use this action after the workspace exists. Its GUI switch
            -- guard protects window reconciliation, without spawning a program.
            window:perform_action(wezterm.action.SwitchToWorkspace { name = pending.name },
              window:active_tab():active_pane())
            break
          end
        end
      end
    end
    local name = window:active_workspace()
    window:set_right_status('Sesion: ' .. M.display_name(name) .. '  |  Ctrl+Shift+S: sesiones  |  Ctrl+Shift+A: nueva')
    if window:is_focused() then M.remember(name) end
    if os.getenv('WEZTERM_REMOTE_SHOW_SESSIONS') == '1'
      and not wezterm.GLOBAL.remote_session_picker_shown then
      wezterm.GLOBAL.remote_session_picker_shown = true
      M.show(window, window:active_tab():active_pane())
    end
  end)
  return config
end

return M
