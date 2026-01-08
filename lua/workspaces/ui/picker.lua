---@class WorkspacesPicker
---Floating window picker for workspaces
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')
local persistence = require('workspaces.persistence')

---@class PickerState
---@field buf integer?
---@field win integer?
---@field items table[]
---@field selected integer
---@field on_select function?

---@type PickerState
local picker_state = {
  buf = nil,
  win = nil,
  items = {},
  selected = 1,
  on_select = nil,
}

---Get project-scoped workspaces (session + current + related)
---@return Workspace[]
local function get_project_workspaces()
  local workspaces = {}
  local seen = {}

  -- 1. First, add ALL session workspaces (ones you've opened in this nvim instance)
  --    This ensures you can always switch back to any workspace you've visited
  for _, ws in ipairs(state.get_session()) do
    if not seen[ws.path] then
      table.insert(workspaces, ws)
      seen[ws.path] = true
    end
  end

  -- 2. Get current workspace (from active or cwd)
  local active = state.get_active()
  local cwd = vim.fn.getcwd()
  local current_ws = active or state.find_by_path(cwd)

  if current_ws then
    -- Add current if not already added
    if not seen[current_ws.path] then
      table.insert(workspaces, current_ws)
      seen[current_ws.path] = true
    end

    -- 3. Add related workspaces from .nvim-workspace.json
    local related_paths = persistence.get_related_workspaces(current_ws.path)
    for _, rel_path in ipairs(related_paths) do
      if not seen[rel_path] then
        local ws = state.find_by_path(rel_path)
        if ws then
          table.insert(workspaces, ws)
          seen[rel_path] = true
        else
          -- Workspace exists in related but not in registry - add it
          local new_ws, _ = state.add(rel_path)
          if new_ws then
            table.insert(workspaces, new_ws)
            seen[rel_path] = true
          end
        end
      end
    end
  end

  -- 4. If still no workspaces, check if cwd itself could be a workspace
  if #workspaces == 0 then
    local root = utils.find_root(cwd, require('workspaces.config').get().root_patterns)
    if root then
      local ws = state.find_by_path(root)
      if ws then
        table.insert(workspaces, ws)
      end
    end
  end

  return workspaces
end

---Show the workspace picker
---@param opts? {title?: string, on_select?: function, show_all?: boolean, show_related?: boolean}
function M.show(opts)
  opts = opts or {}

  if picker_state.win and vim.api.nvim_win_is_valid(picker_state.win) then
    M.close()
    return
  end

  -- Get workspaces based on mode
  local workspaces
  local title

  if opts.show_all then
    -- Show ALL workspaces from global registry
    workspaces = state.get_all_sorted()
    title = opts.title or 'All Workspaces'
  elseif opts.show_related ~= false then
    -- Default: Show current project + related workspaces
    workspaces = get_project_workspaces()
    title = opts.title or 'Project Workspaces'

    -- If no related workspaces, show helpful message
    if #workspaces == 0 then
      utils.notify('No workspace found for current directory.')
      utils.notify('Use :WorkspaceAdd to add current directory, or :WorkspacePicker all to see all workspaces.')
      return
    elseif #workspaces == 1 then
      -- Only current workspace, hint about adding related
      utils.notify('Tip: Use :WorkspaceRelated add <path> to add related workspaces')
    end
  else
    -- Session workspaces only
    workspaces = state.get_session()
    title = opts.title or 'Session Workspaces'
  end

  if #workspaces == 0 then
    utils.notify('No workspaces available. Use :WorkspacePicker all to see all workspaces.')
    return
  end

  picker_state.items = workspaces
  picker_state.selected = 1
  picker_state.on_select = opts.on_select

  -- Find active workspace index
  local active = state.get_active()
  if active then
    for i, ws in ipairs(workspaces) do
      if ws.path == active.path then
        picker_state.selected = i
        break
      end
    end
  end

  M.create_window(title)
  M.render()
  M.setup_keymaps()
end

---Create the picker window
---@param title string
function M.create_window(title)
  local width = math.min(60, vim.o.columns - 10)
  local height = math.min(#picker_state.items + 2, vim.o.lines - 10)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  picker_state.buf = vim.api.nvim_create_buf(false, true)

  picker_state.win = vim.api.nvim_open_win(picker_state.buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
    footer = ' j/k:nav  Enter:select  q:close ',
    footer_pos = 'center',
  })

  -- Window options
  vim.api.nvim_set_option_value('cursorline', true, { win = picker_state.win })
  vim.api.nvim_set_option_value('winhl', 'Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual', { win = picker_state.win })

  -- Buffer options
  vim.api.nvim_set_option_value('modifiable', false, { buf = picker_state.buf })
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = picker_state.buf })
end

---Render the picker content
function M.render()
  if not picker_state.buf or not vim.api.nvim_buf_is_valid(picker_state.buf) then
    return
  end

  local lines = {}
  local active = state.get_active()
  local session = state.get_session()
  local session_paths = {}
  for _, ws in ipairs(session) do
    session_paths[ws.path] = true
  end

  for i, ws in ipairs(picker_state.items) do
    local prefix = ''
    if active and active.path == ws.path then
      prefix = utils.icon('active')
    elseif session_paths[ws.path] then
      prefix = utils.icon('inactive')
    else
      prefix = '  '
    end

    local line = string.format('%s %s', prefix, ws.name)
    local path_display = utils.truncate_path(ws.path, 40)
    local padding = string.rep(' ', math.max(1, 35 - #ws.name))
    line = line .. padding .. path_display

    table.insert(lines, line)
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = picker_state.buf })
  vim.api.nvim_buf_set_lines(picker_state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = picker_state.buf })

  -- Set cursor position
  if picker_state.win and vim.api.nvim_win_is_valid(picker_state.win) then
    vim.api.nvim_win_set_cursor(picker_state.win, { picker_state.selected, 0 })
  end
end

---Setup keymaps for the picker
function M.setup_keymaps()
  local buf = picker_state.buf
  local opts = { buffer = buf, nowait = true, silent = true }

  -- Navigation
  vim.keymap.set('n', 'j', function()
    M.move_selection(1)
  end, opts)

  vim.keymap.set('n', 'k', function()
    M.move_selection(-1)
  end, opts)

  vim.keymap.set('n', '<Down>', function()
    M.move_selection(1)
  end, opts)

  vim.keymap.set('n', '<Up>', function()
    M.move_selection(-1)
  end, opts)

  vim.keymap.set('n', 'G', function()
    picker_state.selected = #picker_state.items
    M.render()
  end, opts)

  vim.keymap.set('n', 'gg', function()
    picker_state.selected = 1
    M.render()
  end, opts)

  -- Selection
  vim.keymap.set('n', '<CR>', function()
    M.select()
  end, opts)

  vim.keymap.set('n', 'l', function()
    M.select()
  end, opts)

  vim.keymap.set('n', '<Tab>', function()
    M.select()
  end, opts)

  -- Close
  vim.keymap.set('n', 'q', function()
    M.close()
  end, opts)

  vim.keymap.set('n', '<Esc>', function()
    M.close()
  end, opts)

  -- Actions
  vim.keymap.set('n', 'o', function()
    M.action_open()
  end, opts)

  vim.keymap.set('n', 'x', function()
    M.action_close_from_session()
  end, opts)

  vim.keymap.set('n', 'd', function()
    M.action_remove()
  end, opts)

  vim.keymap.set('n', 'r', function()
    M.action_rename()
  end, opts)

  vim.keymap.set('n', 't', function()
    M.action_terminal()
  end, opts)

  vim.keymap.set('n', 'f', function()
    M.action_files()
  end, opts)

  vim.keymap.set('n', 'g', function()
    M.action_grep()
  end, opts)
end

---Move selection
---@param delta integer
function M.move_selection(delta)
  picker_state.selected = picker_state.selected + delta

  if picker_state.selected < 1 then
    picker_state.selected = #picker_state.items
  elseif picker_state.selected > #picker_state.items then
    picker_state.selected = 1
  end

  M.render()
end

---Select current item
function M.select()
  local ws = picker_state.items[picker_state.selected]
  if not ws then
    return
  end

  M.close()

  if picker_state.on_select then
    picker_state.on_select(ws)
  else
    state.open(ws.path)
    utils.notify('Switched to: ' .. ws.name .. ' (' .. ws.path .. ')')
    -- Update neo-tree root without closing (preserves expanded dirs)
    vim.defer_fn(function()
      pcall(vim.cmd, 'Neotree dir=' .. vim.fn.fnameescape(ws.path))
    end, 100)
  end
end

---Close the picker
function M.close()
  if picker_state.win and vim.api.nvim_win_is_valid(picker_state.win) then
    vim.api.nvim_win_close(picker_state.win, true)
  end

  if picker_state.buf and vim.api.nvim_buf_is_valid(picker_state.buf) then
    vim.api.nvim_buf_delete(picker_state.buf, { force = true })
  end

  picker_state.win = nil
  picker_state.buf = nil
end

---Action: Open workspace
function M.action_open()
  local ws = picker_state.items[picker_state.selected]
  if ws then
    state.open(ws.path)
    utils.notify('Opened: ' .. ws.name)
    M.render()
  end
end

---Action: Close from session
function M.action_close_from_session()
  local ws = picker_state.items[picker_state.selected]
  if ws and state.close(ws.path) then
    utils.notify('Closed from session: ' .. ws.name)
    M.render()
  end
end

---Action: Remove workspace
function M.action_remove()
  local ws = picker_state.items[picker_state.selected]
  if not ws then
    return
  end

  M.close()

  vim.ui.select({ 'Yes', 'No' }, {
    prompt = 'Remove workspace "' .. ws.name .. '"?',
  }, function(choice)
    if choice == 'Yes' then
      local ok, err = state.remove(ws.path)
      if ok then
        utils.notify('Removed: ' .. ws.name)
      else
        utils.notify(err or 'Failed to remove', vim.log.levels.ERROR)
      end
    end
  end)
end

---Action: Rename workspace
function M.action_rename()
  local ws = picker_state.items[picker_state.selected]
  if not ws then
    return
  end

  M.close()

  vim.ui.input({ prompt = 'New name: ', default = ws.name }, function(input)
    if input and input ~= '' then
      local ok, err = state.rename(ws.path, input)
      if ok then
        utils.notify('Renamed to: ' .. input)
      else
        utils.notify(err or 'Failed to rename', vim.log.levels.ERROR)
      end
    end
  end)
end

---Action: Open terminal in workspace
function M.action_terminal()
  local ws = picker_state.items[picker_state.selected]
  if ws then
    M.close()
    local terminal = require('workspaces.terminal')
    terminal.open(ws.path)
  end
end

---Action: Find files in workspace
function M.action_files()
  local ws = picker_state.items[picker_state.selected]
  if ws then
    M.close()
    vim.defer_fn(function()
      local telescope = utils.safe_require('workspaces.integrations.telescope')
      if telescope then
        telescope.find_files(ws.path)
      end
    end, 50)
  end
end

---Action: Grep in workspace
function M.action_grep()
  local ws = picker_state.items[picker_state.selected]
  if ws then
    M.close()
    vim.defer_fn(function()
      local telescope = utils.safe_require('workspaces.integrations.telescope')
      if telescope then
        telescope.live_grep(ws.path)
      end
    end, 50)
  end
end

---Show all workspaces picker (global registry)
function M.show_all()
  M.show({ title = 'All Workspaces (Global)', show_all = true })
end

---Show session workspaces picker
function M.show_session()
  M.show({ title = 'Session Workspaces', show_all = false, show_related = false })
end

---Show project workspaces (current + related) - DEFAULT
function M.show_project()
  M.show({ title = 'Project Workspaces', show_related = true })
end

---Setup commands
function M.setup()
  vim.api.nvim_create_user_command('WorkspacePicker', function(opts)
    if opts.args == 'all' then
      M.show_all()
    elseif opts.args == 'session' then
      M.show_session()
    else
      -- Default: show project workspaces (current + related)
      M.show_project()
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'all', 'session' }
    end,
    desc = 'Show workspace picker (default: project, "all" for global, "session" for active session)',
  })
end

return M
