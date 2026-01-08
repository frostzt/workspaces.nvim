---@class WorkspacesTerminal
---Terminal integration for workspace-aware terminal spawning
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')
local config = require('workspaces.config')

---Open a terminal in the specified or active workspace
---@param workspace_path? string
---@param opts? table
function M.open(workspace_path, opts)
  opts = opts or {}
  local ws = nil

  if workspace_path then
    ws = state.find_by_path(workspace_path)
    if not ws then
      utils.notify('Workspace not found: ' .. workspace_path, vim.log.levels.ERROR)
      return
    end
  else
    ws = state.get_active()
    if not ws then
      local session = state.get_session()
      if #session > 0 then
        ws = session[1]
      end
    end
  end

  if not ws then
    utils.notify('No workspace available. Opening terminal in current directory.')
    M.open_terminal(vim.fn.getcwd(), opts)
    return
  end

  M.open_terminal(ws.path, opts)
end

---Open a terminal with the specified cwd
---@param cwd string
---@param opts? table
function M.open_terminal(cwd, opts)
  opts = opts or {}

  -- Try to use toggleterm if available
  local toggleterm_ok, toggleterm = pcall(require, 'toggleterm.terminal')
  if toggleterm_ok then
    M.open_toggleterm(cwd, opts)
    return
  end

  -- Try to use snacks terminal if available
  local snacks_ok, snacks = pcall(require, 'snacks')
  if snacks_ok and snacks.terminal then
    M.open_snacks_terminal(cwd, opts)
    return
  end

  -- Fallback to built-in terminal
  M.open_builtin_terminal(cwd, opts)
end

---Open terminal using toggleterm
---@param cwd string
---@param opts? table
function M.open_toggleterm(cwd, opts)
  opts = opts or {}
  local Terminal = require('toggleterm.terminal').Terminal

  local term = Terminal:new({
    dir = cwd,
    direction = opts.direction or 'horizontal',
    close_on_exit = opts.close_on_exit or false,
    on_open = function(t)
      -- Set terminal title to workspace name
      local ws = state.find_by_path(cwd)
      if ws then
        vim.api.nvim_buf_set_name(t.bufnr, 'term://' .. ws.name)
      end
    end,
  })

  term:toggle()
end

---Open terminal using snacks.nvim
---@param cwd string
---@param opts? table
function M.open_snacks_terminal(cwd, opts)
  opts = opts or {}
  local snacks = require('snacks')

  snacks.terminal({
    cwd = cwd,
  })
end

---Open terminal using built-in terminal
---@param cwd string
---@param opts? table
function M.open_builtin_terminal(cwd, opts)
  opts = opts or {}

  -- Save current directory
  local original_cwd = vim.fn.getcwd()

  -- Change to workspace directory
  vim.cmd('cd ' .. vim.fn.fnameescape(cwd))

  -- Open terminal
  local position = opts.position or 'below'
  local size = opts.size or 15

  if position == 'below' then
    vim.cmd('belowright ' .. size .. 'split | terminal')
  elseif position == 'above' then
    vim.cmd('aboveleft ' .. size .. 'split | terminal')
  elseif position == 'right' then
    vim.cmd('belowright ' .. size .. 'vsplit | terminal')
  elseif position == 'left' then
    vim.cmd('aboveleft ' .. size .. 'vsplit | terminal')
  elseif position == 'tab' then
    vim.cmd('tabnew | terminal')
  elseif position == 'float' then
    M.open_floating_terminal(cwd, opts)
    return
  else
    vim.cmd('terminal')
  end

  -- Enter insert mode
  vim.cmd('startinsert')

  -- Restore original directory for other windows
  -- Note: The terminal will keep its cwd
end

---Open a floating terminal
---@param cwd string
---@param opts? table
function M.open_floating_terminal(cwd, opts)
  opts = opts or {}

  local width = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Terminal ',
    title_pos = 'center',
  })

  -- Change to workspace directory and open terminal
  vim.fn.termopen(vim.o.shell, {
    cwd = cwd,
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })

  vim.cmd('startinsert')

  -- Set up keymaps for the floating terminal
  vim.keymap.set('t', '<Esc><Esc>', function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, desc = 'Close floating terminal' })
end

---Open terminal picker to select workspace
---@param opts? table
function M.pick_and_open(opts)
  opts = opts or {}
  local session = state.get_session()

  if #session == 0 then
    utils.notify('No workspaces in session')
    return
  end

  vim.ui.select(session, {
    prompt = 'Open terminal in workspace',
    format_item = function(ws)
      return utils.icon('workspace') .. ' ' .. ws.name
    end,
  }, function(choice)
    if choice then
      M.open(choice.path, opts)
    end
  end)
end

---Run a command in the workspace terminal
---@param cmd string
---@param workspace_path? string
---@param opts? table
function M.run(cmd, workspace_path, opts)
  opts = opts or {}
  local ws = nil

  if workspace_path then
    ws = state.find_by_path(workspace_path)
  else
    ws = state.get_active()
  end

  local cwd = ws and ws.path or vim.fn.getcwd()

  -- Try toggleterm first
  local toggleterm_ok, _ = pcall(require, 'toggleterm')
  if toggleterm_ok then
    local Terminal = require('toggleterm.terminal').Terminal
    local term = Terminal:new({
      cmd = cmd,
      dir = cwd,
      close_on_exit = false,
      direction = opts.direction or 'horizontal',
    })
    term:toggle()
    return
  end

  -- Fallback: open terminal and send command
  M.open_builtin_terminal(cwd, opts)
  vim.defer_fn(function()
    vim.api.nvim_feedkeys(cmd .. '\n', 'n', false)
  end, 100)
end

---Setup terminal commands
function M.setup()
  vim.api.nvim_create_user_command('WorkspaceTerminal', function(opts)
    M.open(opts.fargs[1], {
      position = opts.bang and 'float' or 'below',
    })
  end, {
    nargs = '?',
    bang = true,
    complete = function()
      return vim.tbl_map(function(ws)
        return ws.path
      end, state.get_session())
    end,
    desc = 'Open terminal in workspace (! for floating)',
  })

  vim.api.nvim_create_user_command('WorkspaceRun', function(opts)
    local args = opts.fargs
    local cmd = table.concat(args, ' ')
    M.run(cmd, nil, { direction = 'horizontal' })
  end, {
    nargs = '+',
    desc = 'Run command in active workspace',
  })
end

return M
