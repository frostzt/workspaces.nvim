---@class WorkspacesBuffers
---Buffer management grouped by workspace
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')

---@class WorkspaceBuffer
---@field bufnr integer
---@field name string
---@field workspace Workspace?
---@field relative_path string

---Get all buffers grouped by workspace
---@return table<string, WorkspaceBuffer[]>
function M.get_grouped()
  local buffers = vim.api.nvim_list_bufs()
  local grouped = {}
  local orphans = {}

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)

      if name ~= '' then
        local ws = state.find_by_file(name)

        ---@type WorkspaceBuffer
        local buf_entry = {
          bufnr = bufnr,
          name = name,
          workspace = ws,
          relative_path = ws and utils.relative_path(name, ws.path) or name,
        }

        if ws then
          if not grouped[ws.path] then
            grouped[ws.path] = {}
          end
          table.insert(grouped[ws.path], buf_entry)
        else
          table.insert(orphans, buf_entry)
        end
      end
    end
  end

  -- Add orphans under a special key
  if #orphans > 0 then
    grouped['__orphans__'] = orphans
  end

  return grouped
end

---Get buffers for a specific workspace
---@param workspace_path string
---@return WorkspaceBuffer[]
function M.get_for_workspace(workspace_path)
  local normalized = utils.normalize_path(workspace_path)
  local buffers = vim.api.nvim_list_bufs()
  local result = {}

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)

      if name ~= '' then
        local ws = state.find_by_file(name)
        if ws and utils.normalize_path(ws.path) == normalized then
          table.insert(result, {
            bufnr = bufnr,
            name = name,
            workspace = ws,
            relative_path = utils.relative_path(name, ws.path),
          })
        end
      end
    end
  end

  return result
end

---Get buffers for active workspace
---@return WorkspaceBuffer[]
function M.get_active()
  local active = state.get_active()
  if not active then
    return {}
  end
  return M.get_for_workspace(active.path)
end

---Close all buffers for a workspace
---@param workspace_path string
---@param force? boolean
---@return integer Number of closed buffers
function M.close_workspace_buffers(workspace_path, force)
  local buffers = M.get_for_workspace(workspace_path)
  local closed = 0

  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      local ok = pcall(vim.api.nvim_buf_delete, buf.bufnr, { force = force or false })
      if ok then
        closed = closed + 1
      end
    end
  end

  return closed
end

---Close buffers not belonging to any session workspace
---@param force? boolean
---@return integer
function M.close_orphan_buffers(force)
  local grouped = M.get_grouped()
  local orphans = grouped['__orphans__'] or {}
  local closed = 0

  for _, buf in ipairs(orphans) do
    if vim.api.nvim_buf_is_valid(buf.bufnr) then
      local ok = pcall(vim.api.nvim_buf_delete, buf.bufnr, { force = force or false })
      if ok then
        closed = closed + 1
      end
    end
  end

  return closed
end

---Switch to next buffer in the same workspace
function M.next_in_workspace()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_name = vim.api.nvim_buf_get_name(current_buf)
  local ws = state.find_by_file(current_name)

  if not ws then
    vim.cmd('bnext')
    return
  end

  local buffers = M.get_for_workspace(ws.path)
  if #buffers <= 1 then
    return
  end

  -- Find current buffer index
  local current_idx = 1
  for i, buf in ipairs(buffers) do
    if buf.bufnr == current_buf then
      current_idx = i
      break
    end
  end

  -- Go to next
  local next_idx = (current_idx % #buffers) + 1
  vim.api.nvim_set_current_buf(buffers[next_idx].bufnr)
end

---Switch to previous buffer in the same workspace
function M.prev_in_workspace()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_name = vim.api.nvim_buf_get_name(current_buf)
  local ws = state.find_by_file(current_name)

  if not ws then
    vim.cmd('bprev')
    return
  end

  local buffers = M.get_for_workspace(ws.path)
  if #buffers <= 1 then
    return
  end

  -- Find current buffer index
  local current_idx = 1
  for i, buf in ipairs(buffers) do
    if buf.bufnr == current_buf then
      current_idx = i
      break
    end
  end

  -- Go to previous
  local prev_idx = ((current_idx - 2) % #buffers) + 1
  vim.api.nvim_set_current_buf(buffers[prev_idx].bufnr)
end

---Show buffer list grouped by workspace
function M.show()
  local grouped = M.get_grouped()
  local session = state.get_session()
  local active = state.get_active()

  local lines = { 'Buffers by Workspace:', '' }

  -- Show session workspaces first
  for _, ws in ipairs(session) do
    local buffers = grouped[ws.path] or {}
    local prefix = (active and active.path == ws.path) and utils.icon('active') or utils.icon('workspace')

    table.insert(lines, string.format('%s %s (%d buffers)', prefix, ws.name, #buffers))

    for _, buf in ipairs(buffers) do
      local modified = vim.bo[buf.bufnr].modified and ' [+]' or ''
      table.insert(lines, string.format('    %d: %s%s', buf.bufnr, buf.relative_path, modified))
    end

    table.insert(lines, '')
  end

  -- Show orphan buffers
  local orphans = grouped['__orphans__'] or {}
  if #orphans > 0 then
    table.insert(lines, string.format('Orphan Buffers (%d):', #orphans))
    for _, buf in ipairs(orphans) do
      local modified = vim.bo[buf.bufnr].modified and ' [+]' or ''
      table.insert(lines, string.format('    %d: %s%s', buf.bufnr, utils.truncate_path(buf.name, 50), modified))
    end
  end

  print(table.concat(lines, '\n'))
end

---Setup buffer commands
function M.setup()
  vim.api.nvim_create_user_command('WorkspaceBuffers', function(opts)
    if opts.fargs[1] == 'close' then
      local ws_path = opts.fargs[2]
      if ws_path then
        local closed = M.close_workspace_buffers(ws_path, opts.bang)
        utils.notify('Closed ' .. closed .. ' buffers')
      else
        -- Close active workspace buffers
        local active = state.get_active()
        if active then
          local closed = M.close_workspace_buffers(active.path, opts.bang)
          utils.notify('Closed ' .. closed .. ' buffers from ' .. active.name)
        end
      end
    elseif opts.fargs[1] == 'orphans' then
      local closed = M.close_orphan_buffers(opts.bang)
      utils.notify('Closed ' .. closed .. ' orphan buffers')
    else
      M.show()
    end
  end, {
    nargs = '*',
    bang = true,
    complete = function(arg_lead, cmd_line)
      local parts = vim.split(cmd_line, '%s+')
      if #parts == 2 then
        return { 'close', 'orphans' }
      elseif #parts == 3 and parts[2] == 'close' then
        return vim.tbl_map(function(ws)
          return ws.path
        end, state.get_session())
      end
      return {}
    end,
    desc = 'Buffer management by workspace',
  })

  -- Navigation keymaps (users can override these)
  vim.api.nvim_create_user_command('WorkspaceBnext', function()
    M.next_in_workspace()
  end, { desc = 'Next buffer in workspace' })

  vim.api.nvim_create_user_command('WorkspaceBprev', function()
    M.prev_in_workspace()
  end, { desc = 'Previous buffer in workspace' })
end

return M
