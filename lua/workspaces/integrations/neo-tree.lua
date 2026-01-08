---@class WorkspacesNeoTree
---Neo-tree integration for multi-root workspaces
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')
local config = require('workspaces.config')

---Setup Neo-tree integration
function M.setup()
  -- Register custom source for workspaces
  M.register_source()

  -- Setup commands
  M.setup_commands()
end

---Register workspaces as a Neo-tree source
function M.register_source()
  local ok, neo_tree = pcall(require, 'neo-tree')
  if not ok then
    return
  end

  -- Add workspaces source configuration
  local sources = neo_tree.config and neo_tree.config.sources or {}

  -- Check if already registered
  for _, source in ipairs(sources) do
    if source == 'workspaces' then
      return
    end
  end
end

---Setup Neo-tree specific commands
function M.setup_commands()
  vim.api.nvim_create_user_command('WorkspaceTree', function(opts)
    M.show_tree(opts.fargs[1])
  end, {
    nargs = '?',
    complete = function()
      local workspaces = state.get_session()
      return vim.tbl_map(function(ws)
        return ws.path
      end, workspaces)
    end,
    desc = 'Show Neo-tree for workspace(s)',
  })
end

---Show Neo-tree with workspace roots
---@param workspace_path? string Specific workspace or all session workspaces
function M.show_tree(workspace_path)
  local neo_tree_ok, _ = pcall(require, 'neo-tree')
  if not neo_tree_ok then
    utils.notify('Neo-tree not available', vim.log.levels.ERROR)
    return
  end

  local workspaces = {}

  if workspace_path then
    local ws = state.find_by_path(workspace_path)
    if ws then
      workspaces = { ws }
    else
      utils.notify('Workspace not found: ' .. workspace_path, vim.log.levels.ERROR)
      return
    end
  else
    workspaces = state.get_session()
  end

  if #workspaces == 0 then
    utils.notify('No workspaces in session. Use :WorkspaceOpen to add one.')
    return
  end

  if #workspaces == 1 then
    -- Single workspace - just reveal it
    vim.cmd('Neotree reveal dir=' .. vim.fn.fnameescape(workspaces[1].path))
  else
    -- Multiple workspaces - show picker then reveal
    M.pick_and_reveal(workspaces)
  end
end

---Pick a workspace and reveal in Neo-tree
---@param workspaces Workspace[]
function M.pick_and_reveal(workspaces)
  vim.ui.select(workspaces, {
    prompt = 'Select workspace to browse',
    format_item = function(ws)
      local active = state.get_active()
      local prefix = (active and active.path == ws.path) and utils.icon('active') or utils.icon('workspace')
      return string.format('%s %s', prefix, ws.name)
    end,
  }, function(choice)
    if choice then
      vim.cmd('Neotree reveal dir=' .. vim.fn.fnameescape(choice.path))
    end
  end)
end

---Get filesystem items for all session workspaces (for custom source)
---@return table[]
function M.get_workspace_items()
  local workspaces = state.get_session()
  local items = {}

  for _, ws in ipairs(workspaces) do
    local active = state.get_active()
    local is_active = active and active.path == ws.path

    table.insert(items, {
      id = ws.path,
      name = ws.name,
      path = ws.path,
      type = 'directory',
      is_workspace_root = true,
      is_active_workspace = is_active,
      extra = {
        workspace = ws,
      },
    })
  end

  return items
end

---Open all session workspaces in Neo-tree (multi-root view)
function M.show_all_workspaces()
  local workspaces = state.get_session()

  if #workspaces == 0 then
    utils.notify('No workspaces in session')
    return
  end

  -- For now, use the first workspace as the root
  -- Neo-tree doesn't natively support multiple roots, so we provide alternatives
  local active = state.get_active()
  local target = active or workspaces[1]

  vim.cmd('Neotree reveal dir=' .. vim.fn.fnameescape(target.path))

  -- Show info about other workspaces
  if #workspaces > 1 then
    local names = vim.tbl_map(function(ws)
      return ws.name
    end, workspaces)
    utils.notify('Workspaces in session: ' .. table.concat(names, ', '))
  end
end

---Toggle between workspace roots in Neo-tree
function M.cycle_workspace()
  local workspaces = state.get_session()
  local active = state.get_active()

  if #workspaces <= 1 then
    return
  end

  -- Find current index
  local current_idx = 1
  for i, ws in ipairs(workspaces) do
    if active and ws.path == active.path then
      current_idx = i
      break
    end
  end

  -- Move to next
  local next_idx = (current_idx % #workspaces) + 1
  local next_ws = workspaces[next_idx]

  state.set_active(next_ws)
  vim.cmd('Neotree reveal dir=' .. vim.fn.fnameescape(next_ws.path))
  utils.notify('Switched to: ' .. next_ws.name)
end

---Create a floating window showing all workspace roots
function M.show_workspace_picker()
  local workspaces = state.get_session()

  if #workspaces == 0 then
    utils.notify('No workspaces in session')
    return
  end

  local items = {}
  for _, ws in ipairs(workspaces) do
    table.insert(items, {
      workspace = ws,
      display = string.format('%s %s  %s', utils.icon('workspace'), ws.name, utils.truncate_path(ws.path, 40)),
    })
  end

  vim.ui.select(items, {
    prompt = 'Workspaces',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      state.set_active(choice.workspace)
      vim.cmd('Neotree reveal dir=' .. vim.fn.fnameescape(choice.workspace.path))
    end
  end)
end

---Get the neo-tree source definition for workspaces
---This can be used to register a custom source
---@return table
function M.get_source_definition()
  return {
    name = 'workspaces',
    display_name = ' Workspaces',
    follow_current_file = false,

    get_items = function()
      return M.get_workspace_items()
    end,

    navigate = function(state, path)
      local ws = require('workspaces.state').find_by_path(path)
      if ws then
        require('workspaces.state').set_active(ws)
      end
      require('neo-tree.sources.filesystem').navigate(state, path)
    end,
  }
end

return M
