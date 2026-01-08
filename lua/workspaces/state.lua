---@class Workspace
---@field name string Display name
---@field path string Absolute path to the workspace root
---@field added_at number Timestamp when added
---@field last_opened_at number? Timestamp when last opened
---@field settings table<string, any>? Per-workspace settings

---@class WorkspacesState
---@field workspaces Workspace[] List of all workspaces
---@field active_workspace Workspace? Currently active workspace
---@field session_workspaces Workspace[] Workspaces active in current session

local M = {}

local config = require('workspaces.config')
local persistence = require('workspaces.persistence')
local utils = require('workspaces.utils')

---@type Workspace[]
M.workspaces = {}

---@type Workspace?
M.active_workspace = nil

---@type Workspace[]
M.session_workspaces = {}

---Initialize state from persistence
function M.init()
  M.workspaces = persistence.load() or {}
  M.session_workspaces = {}
  M.active_workspace = nil
end

---Find workspace by path
---@param path string
---@return Workspace?
function M.find_by_path(path)
  local normalized = utils.normalize_path(path)
  for _, ws in ipairs(M.workspaces) do
    if utils.normalize_path(ws.path) == normalized then
      return ws
    end
  end
  return nil
end

---Find workspace by name
---@param name string
---@return Workspace?
function M.find_by_name(name)
  for _, ws in ipairs(M.workspaces) do
    if ws.name == name then
      return ws
    end
  end
  return nil
end

---Find workspace containing a file path
---@param filepath string
---@return Workspace?
function M.find_by_file(filepath)
  local normalized = utils.normalize_path(filepath)
  local best_match = nil
  local best_len = 0

  for _, ws in ipairs(M.session_workspaces) do
    local ws_path = utils.normalize_path(ws.path)
    if vim.startswith(normalized, ws_path) and #ws_path > best_len then
      best_match = ws
      best_len = #ws_path
    end
  end

  return best_match
end

---Add a new workspace
---@param path string
---@param name? string
---@return Workspace?, string?
function M.add(path, name)
  local normalized = utils.normalize_path(path)

  -- Validate path exists
  if vim.fn.isdirectory(normalized) ~= 1 then
    return nil, 'Path does not exist: ' .. normalized
  end

  -- Check if already exists
  if M.find_by_path(normalized) then
    return nil, 'Workspace already exists: ' .. normalized
  end

  -- Generate name if not provided
  local ws_name = name or vim.fn.fnamemodify(normalized, ':t')

  -- Ensure unique name
  local base_name = ws_name
  local counter = 1
  while M.find_by_name(ws_name) do
    ws_name = base_name .. ' (' .. counter .. ')'
    counter = counter + 1
  end

  ---@type Workspace
  local workspace = {
    name = ws_name,
    path = normalized,
    added_at = os.time(),
    last_opened_at = nil,
    settings = {},
  }

  table.insert(M.workspaces, workspace)
  persistence.save(M.workspaces)

  -- Trigger hook
  local hooks = config.get().hooks
  if hooks.on_workspace_add then
    hooks.on_workspace_add(workspace)
  end
  if hooks.on_workspaces_changed then
    hooks.on_workspaces_changed(M.workspaces)
  end

  return workspace, nil
end

---Remove a workspace
---@param path string
---@return boolean, string?
function M.remove(path)
  local normalized = utils.normalize_path(path)

  for i, ws in ipairs(M.workspaces) do
    if utils.normalize_path(ws.path) == normalized then
      local removed = table.remove(M.workspaces, i)
      persistence.save(M.workspaces)

      -- Remove from session if present
      for j, sws in ipairs(M.session_workspaces) do
        if utils.normalize_path(sws.path) == normalized then
          table.remove(M.session_workspaces, j)
          break
        end
      end

      -- Clear active if it was this one
      if M.active_workspace and utils.normalize_path(M.active_workspace.path) == normalized then
        M.active_workspace = M.session_workspaces[1] or nil
      end

      -- Trigger hooks
      local hooks = config.get().hooks
      if hooks.on_workspace_remove then
        hooks.on_workspace_remove(removed)
      end
      if hooks.on_workspaces_changed then
        hooks.on_workspaces_changed(M.workspaces)
      end

      return true, nil
    end
  end

  return false, 'Workspace not found: ' .. normalized
end

---Add workspace to current session
---@param path string
---@return Workspace?, string?
function M.open(path)
  local normalized = utils.normalize_path(path)

  -- Find or create workspace
  local workspace = M.find_by_path(normalized)
  if not workspace then
    -- Auto-add if it's a valid directory
    local ws, err = M.add(normalized)
    if not ws then
      return nil, err
    end
    workspace = ws
  end

  -- Check if already in session
  for _, sws in ipairs(M.session_workspaces) do
    if utils.normalize_path(sws.path) == normalized then
      M.set_active(workspace)
      return workspace, nil
    end
  end

  -- Add to session
  table.insert(M.session_workspaces, workspace)

  -- Update last opened
  workspace.last_opened_at = os.time()
  persistence.save(M.workspaces)

  -- Set as active
  M.set_active(workspace)

  -- Trigger hook
  local hooks = config.get().hooks
  if hooks.on_workspace_open then
    hooks.on_workspace_open(workspace)
  end

  return workspace, nil
end

---Remove workspace from current session
---@param path string
---@return boolean
function M.close(path)
  local normalized = utils.normalize_path(path)

  for i, ws in ipairs(M.session_workspaces) do
    if utils.normalize_path(ws.path) == normalized then
      table.remove(M.session_workspaces, i)

      -- Update active
      if M.active_workspace and utils.normalize_path(M.active_workspace.path) == normalized then
        M.active_workspace = M.session_workspaces[1] or nil
      end

      return true
    end
  end

  return false
end

---Set active workspace
---@param workspace Workspace
---@param opts? {change_dir?: boolean, open_explorer?: boolean}
function M.set_active(workspace, opts)
  opts = opts or {}
  M.active_workspace = workspace

  -- Change directory to workspace root
  local cfg = config.get()
  local should_cd = opts.change_dir
  if should_cd == nil then
    should_cd = cfg.change_dir_on_switch ~= false -- default true
  end

  if should_cd then
    vim.cmd('cd ' .. vim.fn.fnameescape(workspace.path))
  end

  -- Trigger user autocmd
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'WorkspacesActiveChanged',
    data = { workspace = workspace },
  })
end

---Get all workspaces sorted according to config
---@return Workspace[]
function M.get_all_sorted()
  local sorted = vim.deepcopy(M.workspaces)
  local sort_by = config.get().sort_by

  if sort_by == 'name' then
    table.sort(sorted, function(a, b)
      return a.name:lower() < b.name:lower()
    end)
  elseif sort_by == 'recent' then
    table.sort(sorted, function(a, b)
      local a_time = a.last_opened_at or a.added_at
      local b_time = b.last_opened_at or b.added_at
      return a_time > b_time
    end)
  elseif sort_by == 'path' then
    table.sort(sorted, function(a, b)
      return a.path < b.path
    end)
  end

  return sorted
end

---Get session workspaces
---@return Workspace[]
function M.get_session()
  return M.session_workspaces
end

---Get active workspace
---@return Workspace?
function M.get_active()
  return M.active_workspace
end

---Rename a workspace
---@param path string
---@param new_name string
---@return boolean, string?
function M.rename(path, new_name)
  local workspace = M.find_by_path(path)
  if not workspace then
    return false, 'Workspace not found'
  end

  -- Check name uniqueness
  local existing = M.find_by_name(new_name)
  if existing and existing ~= workspace then
    return false, 'A workspace with this name already exists'
  end

  workspace.name = new_name
  persistence.save(M.workspaces)

  return true, nil
end

---Update workspace settings
---@param path string
---@param settings table<string, any>
---@return boolean, string?
function M.update_settings(path, settings)
  local workspace = M.find_by_path(path)
  if not workspace then
    return false, 'Workspace not found'
  end

  workspace.settings = vim.tbl_deep_extend('force', workspace.settings or {}, settings)
  persistence.save(M.workspaces)

  return true, nil
end

return M
