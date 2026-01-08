---@class WorkspacesPersistence
local M = {}

local config = require('workspaces.config')

-- File names
M.CENTRAL_FILE = 'workspaces.json' -- In stdpath('data')
M.PROJECT_FILE = '.nvim-workspace.json' -- In project root

---@class ProjectWorkspaceConfig
---@field name string? Display name for this workspace
---@field related string[]? Paths to related workspaces
---@field settings table? Project-specific settings
---@field lsp table? LSP server settings

---Get central registry file path
---@return string
function M.get_central_path()
  local cfg = config.get()
  return cfg.workspaces_file
end

---Get project config file path for a workspace
---@param workspace_path string
---@return string
function M.get_project_config_path(workspace_path)
  return workspace_path .. '/' .. M.PROJECT_FILE
end

---Load workspaces from central registry
---@return Workspace[]?
function M.load()
  local filepath = M.get_central_path()

  -- Check if file exists
  if vim.fn.filereadable(filepath) ~= 1 then
    return {}
  end

  -- Read file
  local file = io.open(filepath, 'r')
  if not file then
    return {}
  end

  local content = file:read('*all')
  file:close()

  if not content or content == '' then
    return {}
  end

  -- Parse JSON
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then
    vim.notify('Workspaces: Failed to parse workspaces file', vim.log.levels.WARN)
    return {}
  end

  -- Validate and migrate data
  return M.validate_central(data)
end

---Save workspaces to central registry (lightweight - just paths and names)
---@param workspaces Workspace[]
---@return boolean
function M.save(workspaces)
  local filepath = M.get_central_path()

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.fn.mkdir(dir, 'p')
  end

  -- Prepare data (lightweight - only essential info)
  local data = {
    version = 2,
    workspaces = vim.tbl_map(function(ws)
      return {
        path = ws.path,
        name = ws.name,
        added_at = ws.added_at,
        last_opened_at = ws.last_opened_at,
      }
    end, workspaces),
  }

  -- Encode to JSON
  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    vim.notify('Workspaces: Failed to encode workspaces', vim.log.levels.ERROR)
    return false
  end

  -- Pretty print JSON for readability
  json = M.pretty_json(json)

  -- Write to file
  local file = io.open(filepath, 'w')
  if not file then
    vim.notify('Workspaces: Failed to write workspaces file', vim.log.levels.ERROR)
    return false
  end

  file:write(json)
  file:close()

  return true
end

---Load project-specific config from .nvim-workspace.json
---@param workspace_path string
---@return ProjectWorkspaceConfig?
function M.load_project_config(workspace_path)
  local filepath = M.get_project_config_path(workspace_path)

  if vim.fn.filereadable(filepath) ~= 1 then
    return nil
  end

  local file = io.open(filepath, 'r')
  if not file then
    return nil
  end

  local content = file:read('*all')
  file:close()

  if not content or content == '' then
    return nil
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then
    return nil
  end

  return data
end

---Save project-specific config to .nvim-workspace.json
---@param workspace_path string
---@param project_config ProjectWorkspaceConfig
---@return boolean
function M.save_project_config(workspace_path, project_config)
  local filepath = M.get_project_config_path(workspace_path)

  -- Prepare data
  local data = {
    ["$schema"] = "https://raw.githubusercontent.com/yourusername/workspaces.nvim/main/schema.json",
    version = 1,
    name = project_config.name,
    related = project_config.related or {},
    settings = project_config.settings or {},
    lsp = project_config.lsp or {},
  }

  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    vim.notify('Workspaces: Failed to encode project config', vim.log.levels.ERROR)
    return false
  end

  local file = io.open(filepath, 'w')
  if not file then
    vim.notify('Workspaces: Failed to write project config', vim.log.levels.ERROR)
    return false
  end

  file:write(M.pretty_json(json))
  file:close()

  return true
end

---Get related workspaces for a project
---@param workspace_path string
---@return string[]
function M.get_related_workspaces(workspace_path)
  local project_config = M.load_project_config(workspace_path)
  if not project_config or not project_config.related then
    return {}
  end

  -- Expand paths (handle relative paths and ~)
  local utils = require('workspaces.utils')
  local related = {}

  for _, path in ipairs(project_config.related) do
    -- Handle relative paths (relative to workspace)
    local expanded
    if path:sub(1, 1) == '.' then
      expanded = utils.normalize_path(workspace_path .. '/' .. path)
    else
      expanded = utils.normalize_path(path)
    end

    if vim.fn.isdirectory(expanded) == 1 then
      table.insert(related, expanded)
    end
  end

  return related
end

---Add a related workspace to project config
---@param workspace_path string
---@param related_path string
---@return boolean
function M.add_related_workspace(workspace_path, related_path)
  local project_config = M.load_project_config(workspace_path) or {}

  if not project_config.related then
    project_config.related = {}
  end

  -- Check if already exists
  local utils = require('workspaces.utils')
  local normalized = utils.normalize_path(related_path)

  for _, existing in ipairs(project_config.related) do
    if utils.normalize_path(existing) == normalized then
      return true -- Already exists
    end
  end

  table.insert(project_config.related, related_path)
  return M.save_project_config(workspace_path, project_config)
end

---Remove a related workspace from project config
---@param workspace_path string
---@param related_path string
---@return boolean
function M.remove_related_workspace(workspace_path, related_path)
  local project_config = M.load_project_config(workspace_path)
  if not project_config or not project_config.related then
    return false
  end

  local utils = require('workspaces.utils')
  local normalized = utils.normalize_path(related_path)

  for i, existing in ipairs(project_config.related) do
    if utils.normalize_path(existing) == normalized then
      table.remove(project_config.related, i)
      return M.save_project_config(workspace_path, project_config)
    end
  end

  return false
end

---Validate central registry data
---@param data table
---@return Workspace[]
function M.validate_central(data)
  local workspaces = {}

  -- Handle versioned format
  local ws_data = data.workspaces or data

  if type(ws_data) ~= 'table' then
    return {}
  end

  for _, ws in ipairs(ws_data) do
    if type(ws) == 'table' and ws.path then
      -- Validate required fields
      local workspace = {
        name = ws.name or vim.fn.fnamemodify(ws.path, ':t'),
        path = ws.path,
        added_at = ws.added_at or os.time(),
        last_opened_at = ws.last_opened_at,
        settings = {}, -- Settings now come from project config
      }

      -- Only add if path still exists
      if vim.fn.isdirectory(workspace.path) == 1 then
        -- Load project-specific settings if available
        local project_config = M.load_project_config(workspace.path)
        if project_config then
          workspace.settings = project_config.settings or {}
          if project_config.name then
            workspace.name = project_config.name
          end
        end

        table.insert(workspaces, workspace)
      end
    end
  end

  return workspaces
end

---Pretty print JSON with indentation
---@param json string
---@return string
function M.pretty_json(json)
  local result = {}
  local indent = 0
  local in_string = false
  local prev_char = ''

  for i = 1, #json do
    local char = json:sub(i, i)

    if char == '"' and prev_char ~= '\\' then
      in_string = not in_string
    end

    if not in_string then
      if char == '{' or char == '[' then
        table.insert(result, char)
        indent = indent + 1
        table.insert(result, '\n' .. string.rep('  ', indent))
      elseif char == '}' or char == ']' then
        indent = indent - 1
        table.insert(result, '\n' .. string.rep('  ', indent))
        table.insert(result, char)
      elseif char == ',' then
        table.insert(result, char)
        table.insert(result, '\n' .. string.rep('  ', indent))
      elseif char == ':' then
        table.insert(result, ': ')
      elseif char ~= ' ' and char ~= '\n' and char ~= '\t' then
        table.insert(result, char)
      end
    else
      table.insert(result, char)
    end

    prev_char = char
  end

  return table.concat(result)
end

---Initialize project config file in a workspace
---@param workspace_path string
---@param name? string
---@return boolean
function M.init_project_config(workspace_path, name)
  local existing = M.load_project_config(workspace_path)
  if existing then
    return true -- Already exists
  end

  local project_config = {
    name = name or vim.fn.fnamemodify(workspace_path, ':t'),
    related = {},
    settings = {},
    lsp = {},
  }

  return M.save_project_config(workspace_path, project_config)
end

---Check if a project has a workspace config file
---@param workspace_path string
---@return boolean
function M.has_project_config(workspace_path)
  local filepath = M.get_project_config_path(workspace_path)
  return vim.fn.filereadable(filepath) == 1
end

---Export for sharing (creates a .nvim-workspace.json with related projects)
---@param workspace_path string
---@param related_paths string[]
---@return boolean
function M.export_workspace(workspace_path, related_paths)
  local project_config = M.load_project_config(workspace_path) or {}
  project_config.related = related_paths
  return M.save_project_config(workspace_path, project_config)
end

---Import workspaces from a project's .nvim-workspace.json
---@param workspace_path string
---@return string[]? related paths
function M.import_related(workspace_path)
  return M.get_related_workspaces(workspace_path)
end

return M
