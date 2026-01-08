---@class WorkspacesCommands
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')

---Setup user commands
function M.setup()
  -- Main workspace command with subcommands
  vim.api.nvim_create_user_command('Workspace', function(opts)
    M.handle_command(opts.fargs)
  end, {
    nargs = '*',
    complete = function(arg_lead, cmd_line, cursor_pos)
      return M.complete(arg_lead, cmd_line, cursor_pos)
    end,
    desc = 'Workspace management commands',
  })

  -- Convenience aliases
  vim.api.nvim_create_user_command('WorkspaceAdd', function(opts)
    M.cmd_add(opts.fargs[1], opts.fargs[2])
  end, {
    nargs = '*',
    complete = 'dir',
    desc = 'Add a workspace',
  })

  vim.api.nvim_create_user_command('WorkspaceRemove', function(opts)
    M.cmd_remove(opts.fargs[1])
  end, {
    nargs = '?',
    complete = function()
      return M.complete_workspace_paths()
    end,
    desc = 'Remove a workspace',
  })

  vim.api.nvim_create_user_command('WorkspaceOpen', function(opts)
    M.cmd_open(opts.fargs[1])
  end, {
    nargs = '?',
    complete = function()
      return M.complete_workspace_paths()
    end,
    desc = 'Open a workspace in current session',
  })

  vim.api.nvim_create_user_command('WorkspaceClose', function(opts)
    M.cmd_close(opts.fargs[1])
  end, {
    nargs = '?',
    complete = function()
      return M.complete_session_paths()
    end,
    desc = 'Close a workspace from current session',
  })

  vim.api.nvim_create_user_command('WorkspaceList', function()
    M.cmd_list()
  end, {
    desc = 'List all workspaces',
  })

  vim.api.nvim_create_user_command('WorkspaceSelect', function()
    M.cmd_select()
  end, {
    desc = 'Select workspace with picker',
  })
end

---Handle main Workspace command
---@param args string[]
function M.handle_command(args)
  local subcommand = args[1]

  if not subcommand then
    M.cmd_list()
    return
  end

  local handlers = {
    add = function()
      M.cmd_add(args[2], args[3])
    end,
    remove = function()
      M.cmd_remove(args[2])
    end,
    open = function()
      M.cmd_open(args[2])
    end,
    close = function()
      M.cmd_close(args[2])
    end,
    list = function()
      M.cmd_list()
    end,
    select = function()
      M.cmd_select()
    end,
    rename = function()
      M.cmd_rename(args[2], args[3])
    end,
    switch = function()
      M.cmd_switch(args[2])
    end,
    files = function()
      M.cmd_files(args[2])
    end,
    grep = function()
      M.cmd_grep(args[2])
    end,
    terminal = function()
      M.cmd_terminal(args[2])
    end,
  }

  local handler = handlers[subcommand]
  if handler then
    handler()
  else
    utils.notify('Unknown subcommand: ' .. subcommand, vim.log.levels.ERROR)
  end
end

---Add workspace command
---@param path? string
---@param name? string
function M.cmd_add(path, name)
  path = path or vim.fn.getcwd()

  local workspace, err = state.add(path, name)
  if workspace then
    utils.notify('Added workspace: ' .. workspace.name)

    -- Also open it
    state.open(workspace.path)
  else
    utils.notify(err or 'Failed to add workspace', vim.log.levels.ERROR)
  end
end

---Remove workspace command
---@param path? string
function M.cmd_remove(path)
  if not path then
    -- Use picker if no path specified
    M.pick_workspace('Remove workspace', function(workspace)
      local ok, err = state.remove(workspace.path)
      if ok then
        utils.notify('Removed workspace: ' .. workspace.name)
      else
        utils.notify(err or 'Failed to remove workspace', vim.log.levels.ERROR)
      end
    end)
    return
  end

  local ok, err = state.remove(path)
  if ok then
    utils.notify('Removed workspace')
  else
    utils.notify(err or 'Failed to remove workspace', vim.log.levels.ERROR)
  end
end

---Open workspace in session
---@param path? string
function M.cmd_open(path)
  if not path then
    M.pick_workspace('Open workspace', function(workspace)
      local ws, err = state.open(workspace.path)
      if ws then
        utils.notify('Opened workspace: ' .. ws.name)
      else
        utils.notify(err or 'Failed to open workspace', vim.log.levels.ERROR)
      end
    end)
    return
  end

  local workspace, err = state.open(path)
  if workspace then
    utils.notify('Opened workspace: ' .. workspace.name)
  else
    utils.notify(err or 'Failed to open workspace', vim.log.levels.ERROR)
  end
end

---Close workspace from session
---@param path? string
function M.cmd_close(path)
  if not path then
    M.pick_session_workspace('Close workspace', function(workspace)
      if state.close(workspace.path) then
        utils.notify('Closed workspace: ' .. workspace.name)
      end
    end)
    return
  end

  local workspace = state.find_by_path(path)
  if workspace and state.close(path) then
    utils.notify('Closed workspace: ' .. workspace.name)
  else
    utils.notify('Workspace not found in session', vim.log.levels.ERROR)
  end
end

---List workspaces
function M.cmd_list()
  local workspaces = state.get_all_sorted()
  local session = state.get_session()
  local active = state.get_active()

  if #workspaces == 0 then
    utils.notify('No workspaces configured. Use :WorkspaceAdd to add one.')
    return
  end

  local lines = { 'Workspaces:' }

  for _, ws in ipairs(workspaces) do
    local in_session = false
    local is_active = false

    for _, sws in ipairs(session) do
      if sws.path == ws.path then
        in_session = true
        break
      end
    end

    if active and active.path == ws.path then
      is_active = true
    end

    local prefix = '  '
    if is_active then
      prefix = utils.icon('active')
    elseif in_session then
      prefix = utils.icon('inactive')
    end

    table.insert(lines, string.format('%s %s (%s)', prefix, ws.name, utils.truncate_path(ws.path, 50)))
  end

  print(table.concat(lines, '\n'))
end

---Select workspace with picker
function M.cmd_select()
  M.pick_workspace('Select workspace', function(workspace)
    state.open(workspace.path)
    utils.notify('Switched to: ' .. workspace.name)
  end)
end

---Rename workspace
---@param path? string
---@param new_name? string
function M.cmd_rename(path, new_name)
  if not path then
    M.pick_workspace('Rename workspace', function(workspace)
      vim.ui.input({ prompt = 'New name: ', default = workspace.name }, function(input)
        if input and input ~= '' then
          local ok, err = state.rename(workspace.path, input)
          if ok then
            utils.notify('Renamed to: ' .. input)
          else
            utils.notify(err or 'Failed to rename', vim.log.levels.ERROR)
          end
        end
      end)
    end)
    return
  end

  if not new_name then
    utils.notify('Please provide a new name', vim.log.levels.ERROR)
    return
  end

  local ok, err = state.rename(path, new_name)
  if ok then
    utils.notify('Renamed to: ' .. new_name)
  else
    utils.notify(err or 'Failed to rename', vim.log.levels.ERROR)
  end
end

---Switch active workspace
---@param identifier? string Path or name
function M.cmd_switch(identifier)
  if not identifier then
    M.pick_session_workspace('Switch to workspace', function(workspace)
      state.set_active(workspace)
      utils.notify('Active: ' .. workspace.name)
    end)
    return
  end

  local workspace = state.find_by_path(identifier) or state.find_by_name(identifier)
  if workspace then
    -- Ensure it's in session
    state.open(workspace.path)
    utils.notify('Active: ' .. workspace.name)
  else
    utils.notify('Workspace not found', vim.log.levels.ERROR)
  end
end

---Search files in workspace(s)
---@param workspace_path? string
function M.cmd_files(workspace_path)
  local telescope = utils.safe_require('workspaces.integrations.telescope')
  if telescope then
    telescope.find_files(workspace_path)
  else
    utils.notify('Telescope integration not available', vim.log.levels.WARN)
  end
end

---Grep in workspace(s)
---@param workspace_path? string
function M.cmd_grep(workspace_path)
  local telescope = utils.safe_require('workspaces.integrations.telescope')
  if telescope then
    telescope.live_grep(workspace_path)
  else
    utils.notify('Telescope integration not available', vim.log.levels.WARN)
  end
end

---Open terminal in workspace
---@param workspace_path? string
function M.cmd_terminal(workspace_path)
  local terminal = utils.safe_require('workspaces.terminal')
  if terminal then
    terminal.open(workspace_path)
  else
    utils.notify('Terminal integration not available', vim.log.levels.WARN)
  end
end

---Generic workspace picker using vim.ui.select
---@param title string
---@param callback fun(workspace: Workspace)
function M.pick_workspace(title, callback)
  local workspaces = state.get_all_sorted()

  if #workspaces == 0 then
    utils.notify('No workspaces available')
    return
  end

  vim.ui.select(workspaces, {
    prompt = title,
    format_item = function(ws)
      return string.format('%s %s  %s', utils.icon('workspace'), ws.name, utils.truncate_path(ws.path, 40))
    end,
  }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

---Session workspace picker
---@param title string
---@param callback fun(workspace: Workspace)
function M.pick_session_workspace(title, callback)
  local workspaces = state.get_session()

  if #workspaces == 0 then
    utils.notify('No workspaces in current session')
    return
  end

  vim.ui.select(workspaces, {
    prompt = title,
    format_item = function(ws)
      local active = state.get_active()
      local prefix = (active and active.path == ws.path) and utils.icon('active') or utils.icon('workspace')
      return string.format('%s %s  %s', prefix, ws.name, utils.truncate_path(ws.path, 40))
    end,
  }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

---Completion for workspace paths
---@return string[]
function M.complete_workspace_paths()
  local workspaces = state.get_all_sorted()
  return vim.tbl_map(function(ws)
    return ws.path
  end, workspaces)
end

---Completion for session workspace paths
---@return string[]
function M.complete_session_paths()
  local workspaces = state.get_session()
  return vim.tbl_map(function(ws)
    return ws.path
  end, workspaces)
end

---Command completion
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos number
---@return string[]
function M.complete(arg_lead, cmd_line, cursor_pos)
  local parts = vim.split(cmd_line, '%s+')
  local num_args = #parts

  -- Subcommand completion
  if num_args == 2 then
    local subcommands = {
      'add',
      'remove',
      'open',
      'close',
      'list',
      'select',
      'rename',
      'switch',
      'files',
      'grep',
      'terminal',
    }
    return vim.tbl_filter(function(cmd)
      return vim.startswith(cmd, arg_lead)
    end, subcommands)
  end

  -- Argument completion based on subcommand
  local subcommand = parts[2]
  if subcommand == 'add' then
    -- Directory completion handled by Neovim
    return {}
  elseif subcommand == 'remove' or subcommand == 'open' or subcommand == 'rename' then
    return M.complete_workspace_paths()
  elseif subcommand == 'close' or subcommand == 'switch' then
    return M.complete_session_paths()
  end

  return {}
end

return M
