---@class WorkspacesPersistence
local M = {}

local config = require('workspaces.config')

---Load workspaces from file
---@return Workspace[]?
function M.load()
  local cfg = config.get()
  local filepath = cfg.workspaces_file

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
  return M.validate(data)
end

---Save workspaces to file
---@param workspaces Workspace[]
---@return boolean
function M.save(workspaces)
  local cfg = config.get()
  local filepath = cfg.workspaces_file

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if vim.fn.isdirectory(dir) ~= 1 then
    vim.fn.mkdir(dir, 'p')
  end

  -- Prepare data
  local data = {
    version = 1,
    workspaces = workspaces,
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

---Validate and potentially migrate workspace data
---@param data table
---@return Workspace[]
function M.validate(data)
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
        settings = ws.settings or {},
      }

      -- Only add if path still exists
      if vim.fn.isdirectory(workspace.path) == 1 then
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
  -- Simple pretty printer for JSON
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

---Export workspaces to a specific file (for sharing)
---@param filepath string
---@param workspaces? Workspace[]
---@return boolean
function M.export(filepath, workspaces)
  local state = require('workspaces.state')
  workspaces = workspaces or state.workspaces

  local data = {
    version = 1,
    exported_at = os.time(),
    workspaces = vim.tbl_map(function(ws)
      return {
        name = ws.name,
        path = ws.path,
        settings = ws.settings,
      }
    end, workspaces),
  }

  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    return false
  end

  local file = io.open(filepath, 'w')
  if not file then
    return false
  end

  file:write(M.pretty_json(json))
  file:close()

  return true
end

---Import workspaces from a file
---@param filepath string
---@return Workspace[]?, string?
function M.import(filepath)
  if vim.fn.filereadable(filepath) ~= 1 then
    return nil, 'File not found: ' .. filepath
  end

  local file = io.open(filepath, 'r')
  if not file then
    return nil, 'Cannot read file: ' .. filepath
  end

  local content = file:read('*all')
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil, 'Invalid JSON in file'
  end

  return M.validate(data), nil
end

return M
