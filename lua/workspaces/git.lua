---@class WorkspacesGit
---Git integration for per-workspace git status
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')

---@class GitStatus
---@field branch string?
---@field ahead integer
---@field behind integer
---@field staged integer
---@field unstaged integer
---@field untracked integer
---@field conflicted integer
---@field is_repo boolean

---Cache for git status per workspace
---@type table<string, GitStatus>
M.cache = {}

---Get git status for a workspace
---@param workspace Workspace
---@return GitStatus
function M.get_status(workspace)
  local path = workspace.path

  -- Check cache
  if M.cache[path] then
    return M.cache[path]
  end

  -- Compute status
  local status = M.compute_status(path)
  M.cache[path] = status

  return status
end

---Compute git status for a directory
---@param path string
---@return GitStatus
function M.compute_status(path)
  ---@type GitStatus
  local status = {
    branch = nil,
    ahead = 0,
    behind = 0,
    staged = 0,
    unstaged = 0,
    untracked = 0,
    conflicted = 0,
    is_repo = false,
  }

  -- Check if it's a git repo
  local git_dir = path .. '/.git'
  if vim.fn.isdirectory(git_dir) ~= 1 and vim.fn.filereadable(git_dir) ~= 1 then
    return status
  end

  status.is_repo = true

  -- Get branch name
  local branch_result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(path) .. ' branch --show-current 2>/dev/null')
  if #branch_result > 0 and vim.v.shell_error == 0 then
    status.branch = branch_result[1]
  else
    -- Try to get HEAD ref (detached head)
    local head_result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(path) .. ' rev-parse --short HEAD 2>/dev/null')
    if #head_result > 0 and vim.v.shell_error == 0 then
      status.branch = 'HEAD:' .. head_result[1]
    end
  end

  -- Get ahead/behind
  local ab_result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(path) .. ' rev-list --left-right --count @{upstream}...HEAD 2>/dev/null')
  if #ab_result > 0 and vim.v.shell_error == 0 then
    local parts = vim.split(ab_result[1], '%s+')
    if #parts >= 2 then
      status.behind = tonumber(parts[1]) or 0
      status.ahead = tonumber(parts[2]) or 0
    end
  end

  -- Get file status
  local status_result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(path) .. ' status --porcelain 2>/dev/null')
  if vim.v.shell_error == 0 then
    for _, line in ipairs(status_result) do
      if #line >= 2 then
        local index = line:sub(1, 1)
        local worktree = line:sub(2, 2)

        -- Staged changes
        if index == 'A' or index == 'M' or index == 'D' or index == 'R' or index == 'C' then
          status.staged = status.staged + 1
        end

        -- Unstaged changes
        if worktree == 'M' or worktree == 'D' then
          status.unstaged = status.unstaged + 1
        end

        -- Untracked files
        if index == '?' then
          status.untracked = status.untracked + 1
        end

        -- Conflicts
        if index == 'U' or worktree == 'U' or (index == 'A' and worktree == 'A') or (index == 'D' and worktree == 'D') then
          status.conflicted = status.conflicted + 1
        end
      end
    end
  end

  return status
end

---Invalidate cache for a workspace
---@param path string
function M.invalidate_cache(path)
  M.cache[path] = nil
end

---Invalidate all cache
function M.invalidate_all()
  M.cache = {}
end

---Refresh git status for all session workspaces
function M.refresh()
  M.invalidate_all()

  local session = state.get_session()
  for _, ws in ipairs(session) do
    M.get_status(ws)
  end

  -- Trigger autocmd
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'WorkspacesGitRefreshed',
  })
end

---Get summary of all workspace git statuses
---@return table<string, GitStatus>
function M.get_all_status()
  local session = state.get_session()
  local result = {}

  for _, ws in ipairs(session) do
    result[ws.path] = M.get_status(ws)
  end

  return result
end

---Format git status for display
---@param status GitStatus
---@return string
function M.format_status(status)
  if not status.is_repo then
    return 'Not a git repo'
  end

  local parts = {}

  if status.branch then
    table.insert(parts, ' ' .. status.branch)
  end

  if status.ahead > 0 then
    table.insert(parts, '↑' .. status.ahead)
  end

  if status.behind > 0 then
    table.insert(parts, '↓' .. status.behind)
  end

  if status.staged > 0 then
    table.insert(parts, '+' .. status.staged)
  end

  if status.unstaged > 0 then
    table.insert(parts, '~' .. status.unstaged)
  end

  if status.untracked > 0 then
    table.insert(parts, '?' .. status.untracked)
  end

  if status.conflicted > 0 then
    table.insert(parts, '!' .. status.conflicted)
  end

  return table.concat(parts, ' ')
end

---Open lazygit for a workspace
---@param workspace_path? string
function M.lazygit(workspace_path)
  local ws = nil

  if workspace_path then
    ws = state.find_by_path(workspace_path)
  else
    ws = state.get_active()
  end

  if not ws then
    utils.notify('No workspace selected', vim.log.levels.ERROR)
    return
  end

  -- Try snacks lazygit first
  local snacks_ok, snacks = pcall(require, 'snacks')
  if snacks_ok and snacks.lazygit then
    snacks.lazygit({ cwd = ws.path })
    return
  end

  -- Try lazygit.nvim
  local lazygit_ok, _ = pcall(require, 'lazygit')
  if lazygit_ok then
    vim.cmd('cd ' .. vim.fn.fnameescape(ws.path))
    vim.cmd('LazyGit')
    return
  end

  -- Fallback: open in terminal
  local terminal = require('workspaces.terminal')
  terminal.run('lazygit', ws.path, { direction = 'float' })
end

---Setup git integration
function M.setup()
  -- Setup auto-refresh
  local augroup = vim.api.nvim_create_augroup('WorkspacesGit', { clear = true })

  -- Refresh on focus
  vim.api.nvim_create_autocmd('FocusGained', {
    group = augroup,
    callback = function()
      -- Debounce refresh
      vim.defer_fn(function()
        M.refresh()
      end, 500)
    end,
  })

  -- Refresh when workspace changes
  vim.api.nvim_create_autocmd('User', {
    pattern = 'WorkspacesActiveChanged',
    group = augroup,
    callback = function()
      M.refresh()
    end,
  })

  -- Commands
  vim.api.nvim_create_user_command('WorkspaceGit', function(opts)
    if opts.fargs[1] == 'status' then
      M.show_status()
    elseif opts.fargs[1] == 'lazygit' then
      M.lazygit(opts.fargs[2])
    else
      M.lazygit(opts.fargs[1])
    end
  end, {
    nargs = '*',
    complete = function(arg_lead, cmd_line)
      local parts = vim.split(cmd_line, '%s+')
      if #parts == 2 then
        return { 'status', 'lazygit' }
      end
      return vim.tbl_map(function(ws)
        return ws.path
      end, state.get_session())
    end,
    desc = 'Git operations for workspaces',
  })
end

---Show git status for all workspaces
function M.show_status()
  local session = state.get_session()

  if #session == 0 then
    utils.notify('No workspaces in session')
    return
  end

  local lines = { 'Workspace Git Status:', '' }

  for _, ws in ipairs(session) do
    local status = M.get_status(ws)
    local formatted = M.format_status(status)
    table.insert(lines, string.format('  %s: %s', ws.name, formatted))
  end

  print(table.concat(lines, '\n'))
end

return M
