---@class WorkspacesLualine
---Lualine integration for workspace status display
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')
local config = require('workspaces.config')

---Setup lualine integration
function M.setup()
  -- The component is available as require('workspaces.integrations.lualine').component
  -- Users can add it to their lualine config
end

---Get the lualine component definition
---@return table
function M.component()
  return {
    function()
      return M.get_status()
    end,
    cond = function()
      return M.has_workspaces()
    end,
    icon = M.get_icon(),
    color = M.get_color(),
    on_click = function()
      M.on_click()
    end,
  }
end

---Check if there are any session workspaces
---@return boolean
function M.has_workspaces()
  local session = state.get_session()
  return #session > 0
end

---Get current workspace status string
---@return string
function M.get_status()
  local active = state.get_active()
  local session = state.get_session()

  if not active then
    if #session > 0 then
      return string.format('%d workspaces', #session)
    end
    return ''
  end

  local cfg = config.get()
  local show_icon = cfg.integrations.lualine.show_icon

  local status = active.name

  -- Show count if multiple workspaces
  if #session > 1 then
    status = status .. string.format(' [%d/%d]', M.get_active_index(), #session)
  end

  if show_icon then
    status = utils.icon('workspace') .. status
  end

  return status
end

---Get the index of active workspace in session
---@return integer
function M.get_active_index()
  local active = state.get_active()
  local session = state.get_session()

  if not active then
    return 0
  end

  for i, ws in ipairs(session) do
    if ws.path == active.path then
      return i
    end
  end

  return 0
end

---Get icon for lualine
---@return string
function M.get_icon()
  local cfg = config.get()
  if cfg.integrations.lualine.show_icon then
    return utils.icon('workspace')
  end
  return ''
end

---Get color for lualine component
---@return table?
function M.get_color()
  -- Return nil to use default lualine colors
  -- Users can customize this
  return nil
end

---Handle click on lualine component
function M.on_click()
  -- Open workspace picker
  local telescope = utils.safe_require('workspaces.integrations.telescope')
  if telescope then
    telescope.switch_workspace()
  else
    -- Fallback to vim.ui.select
    local session = state.get_session()
    if #session == 0 then
      return
    end

    vim.ui.select(session, {
      prompt = 'Switch Workspace',
      format_item = function(ws)
        local active = state.get_active()
        local prefix = (active and active.path == ws.path) and utils.icon('active') or utils.icon('workspace')
        return prefix .. ' ' .. ws.name
      end,
    }, function(choice)
      if choice then
        state.set_active(choice)
      end
    end)
  end
end

---Get a simple status function for direct use
---@return function
function M.status_function()
  return function()
    return M.get_status()
  end
end

---Get condition function
---@return function
function M.condition_function()
  return function()
    return M.has_workspaces()
  end
end

---Create a workspace indicator component showing all session workspaces
---@return table
function M.full_component()
  return {
    function()
      return M.get_full_status()
    end,
    cond = function()
      return M.has_workspaces()
    end,
  }
end

---Get full status with all workspace names
---@return string
function M.get_full_status()
  local active = state.get_active()
  local session = state.get_session()

  if #session == 0 then
    return ''
  end

  local parts = {}
  for _, ws in ipairs(session) do
    if active and ws.path == active.path then
      table.insert(parts, '[' .. ws.name .. ']')
    else
      table.insert(parts, ws.name)
    end
  end

  return utils.icon('workspace') .. table.concat(parts, ' | ')
end

---Create a minimal component showing just the active workspace name
---@return table
function M.minimal_component()
  return {
    function()
      local active = state.get_active()
      if active then
        return active.name
      end
      return ''
    end,
    cond = function()
      return state.get_active() ~= nil
    end,
    icon = utils.icon('workspace'),
  }
end

return M
