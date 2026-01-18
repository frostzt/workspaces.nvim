local M = {}

---Normalize a file path (expand ~, resolve symlinks, ensure trailing slash consistency)
---@param path string
---@return string
function M.normalize_path(path)
  -- Skip special buffer names (e.g., [dap-repl], term://, etc.)
  if not path or path == '' or path:match('^%[') or path:match('^%w+://') then
    return path or ''
  end
  -- Expand ~ and environment variables
  local expanded = vim.fn.expand(path)
  -- Get absolute path
  local absolute = vim.fn.fnamemodify(expanded, ':p')
  -- Remove trailing slash for consistency
  absolute = absolute:gsub('/$', '')
  return absolute
end

---Check if path is a subdirectory of parent
---@param path string
---@param parent string
---@return boolean
function M.is_subpath(path, parent)
  local norm_path = M.normalize_path(path)
  local norm_parent = M.normalize_path(parent)
  return vim.startswith(norm_path, norm_parent .. '/')
end

---Get relative path from base
---@param path string
---@param base string
---@return string
function M.relative_path(path, base)
  local norm_path = M.normalize_path(path)
  local norm_base = M.normalize_path(base)

  if vim.startswith(norm_path, norm_base) then
    local rel = norm_path:sub(#norm_base + 1)
    if rel:sub(1, 1) == '/' then
      rel = rel:sub(2)
    end
    return rel == '' and '.' or rel
  end

  return norm_path
end

---Find project root from a file path
---@param filepath string
---@param patterns string[]
---@return string?
function M.find_root(filepath, patterns)
  local path = M.normalize_path(filepath)

  -- If it's a file, start from its directory
  if vim.fn.filereadable(path) == 1 then
    path = vim.fn.fnamemodify(path, ':h')
  end

  -- Search upwards for root patterns
  local current = path
  while current ~= '/' and current ~= '' do
    for _, pattern in ipairs(patterns) do
      local test_path = current .. '/' .. pattern
      if vim.fn.isdirectory(test_path) == 1 or vim.fn.filereadable(test_path) == 1 then
        return current
      end
    end
    current = vim.fn.fnamemodify(current, ':h')
  end

  return nil
end

---Notify user with consistent formatting
---@param msg string
---@param level? integer
function M.notify(msg, level)
  local config = require('workspaces.config').get()
  if not config.notify then
    return
  end

  level = level or vim.log.levels.INFO
  vim.notify(msg, level, { title = 'Workspaces' })
end

---Get icon from config
---@param name string
---@return string
function M.icon(name)
  local config = require('workspaces.config').get()
  return config.icons[name] or ''
end

---Debounce a function
---@param fn function
---@param ms integer
---@return function
function M.debounce(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

---Truncate path for display
---@param path string
---@param max_len? integer
---@return string
function M.truncate_path(path, max_len)
  max_len = max_len or 40
  if #path <= max_len then
    return path
  end

  -- Try to show ~ for home
  local home = vim.fn.expand('~')
  if vim.startswith(path, home) then
    path = '~' .. path:sub(#home + 1)
  end

  if #path <= max_len then
    return path
  end

  -- Truncate from the middle
  local half = math.floor((max_len - 3) / 2)
  return path:sub(1, half) .. '...' .. path:sub(-half)
end

---Check if a plugin is available
---@param name string
---@return boolean
function M.has_plugin(name)
  local ok, _ = pcall(require, name)
  return ok
end

---Safe require with fallback
---@param name string
---@return any?
function M.safe_require(name)
  local ok, mod = pcall(require, name)
  if ok then
    return mod
  end
  return nil
end

---Create a unique ID
---@return string
function M.uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return string.gsub(template, '[xy]', function(c)
    local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
    return string.format('%x', v)
  end)
end

return M
