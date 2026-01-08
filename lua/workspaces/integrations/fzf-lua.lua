---@class WorkspacesFzfLua
---fzf-lua integration for workspace-aware operations
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')
local config = require('workspaces.config')

local fzf_ok, fzf = pcall(require, 'fzf-lua')
local has_fzf = fzf_ok

---Setup fzf-lua integration
function M.setup()
  if not has_fzf then
    return
  end

  -- Register custom commands
  M.setup_commands()
end

---Setup fzf-lua specific commands
function M.setup_commands()
  vim.api.nvim_create_user_command('FzfWorkspaces', function()
    M.workspace_picker()
  end, { desc = 'Pick workspace with fzf-lua' })

  vim.api.nvim_create_user_command('FzfWorkspaceFiles', function(opts)
    M.find_files(opts.fargs[1])
  end, {
    nargs = '?',
    complete = function()
      return vim.tbl_map(function(ws)
        return ws.path
      end, state.get_session())
    end,
    desc = 'Find files in workspace(s) with fzf-lua',
  })

  vim.api.nvim_create_user_command('FzfWorkspaceGrep', function(opts)
    M.live_grep(opts.fargs[1])
  end, {
    nargs = '?',
    complete = function()
      return vim.tbl_map(function(ws)
        return ws.path
      end, state.get_session())
    end,
    desc = 'Grep in workspace(s) with fzf-lua',
  })
end

---Workspace picker using fzf-lua
---@param opts? table
function M.workspace_picker(opts)
  if not has_fzf then
    utils.notify('fzf-lua not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local workspaces = state.get_all_sorted()
  local session = state.get_session()
  local active = state.get_active()

  -- Create lookup for session workspaces
  local in_session = {}
  for _, ws in ipairs(session) do
    in_session[ws.path] = true
  end

  -- Build entries
  local entries = {}
  local ws_map = {}

  for _, ws in ipairs(workspaces) do
    local prefix = ''
    if active and active.path == ws.path then
      prefix = utils.icon('active')
    elseif in_session[ws.path] then
      prefix = utils.icon('inactive')
    else
      prefix = utils.icon('workspace')
    end

    local display = string.format('%s %s  %s', prefix, ws.name, utils.truncate_path(ws.path, 40))
    table.insert(entries, display)
    ws_map[display] = ws
  end

  fzf.fzf_exec(entries, vim.tbl_extend('force', opts, {
    prompt = 'Workspaces> ',
    actions = {
      ['default'] = function(selected)
        if selected and selected[1] then
          local ws = ws_map[selected[1]]
          if ws then
            state.open(ws.path)
            utils.notify('Opened: ' .. ws.name)
          end
        end
      end,
      ['ctrl-d'] = function(selected)
        if selected and selected[1] then
          local ws = ws_map[selected[1]]
          if ws then
            local ok, err = state.remove(ws.path)
            if ok then
              utils.notify('Removed: ' .. ws.name)
            else
              utils.notify(err or 'Failed to remove', vim.log.levels.ERROR)
            end
          end
        end
      end,
      ['ctrl-x'] = function(selected)
        if selected and selected[1] then
          local ws = ws_map[selected[1]]
          if ws and state.close(ws.path) then
            utils.notify('Closed from session: ' .. ws.name)
          end
        end
      end,
    },
    fzf_opts = {
      ['--header'] = 'Enter: Open | Ctrl-D: Remove | Ctrl-X: Close from session',
    },
  }))
end

---Find files across workspace(s) using fzf-lua
---@param workspace_path? string
---@param opts? table
function M.find_files(workspace_path, opts)
  if not has_fzf then
    utils.notify('fzf-lua not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local search_dirs = {}
  local title = 'Files'

  if workspace_path then
    local ws = state.find_by_path(workspace_path)
    if ws then
      search_dirs = { ws.path }
      title = 'Files in ' .. ws.name
    else
      utils.notify('Workspace not found', vim.log.levels.ERROR)
      return
    end
  else
    local session = state.get_session()
    if #session == 0 then
      utils.notify('No workspaces in session')
      return
    end
    search_dirs = vim.tbl_map(function(ws)
      return ws.path
    end, session)
    title = 'Files in Workspaces (' .. #session .. ')'
  end

  -- Use fzf-lua files with cwd set to first directory
  -- and include all directories in the search
  if #search_dirs == 1 then
    fzf.files(vim.tbl_extend('force', opts, {
      cwd = search_dirs[1],
      prompt = title .. '> ',
    }))
  else
    -- For multiple directories, we need to use a custom finder
    local cmd = 'fd --type f'
    for _, dir in ipairs(search_dirs) do
      cmd = cmd .. ' --search-path ' .. vim.fn.shellescape(dir)
    end

    fzf.fzf_exec(cmd, vim.tbl_extend('force', opts, {
      prompt = title .. '> ',
      actions = {
        ['default'] = function(selected)
          if selected and selected[1] then
            vim.cmd('edit ' .. vim.fn.fnameescape(selected[1]))
          end
        end,
      },
      previewer = 'builtin',
    }))
  end
end

---Live grep across workspace(s) using fzf-lua
---@param workspace_path? string
---@param opts? table
function M.live_grep(workspace_path, opts)
  if not has_fzf then
    utils.notify('fzf-lua not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local search_dirs = {}
  local title = 'Grep'

  if workspace_path then
    local ws = state.find_by_path(workspace_path)
    if ws then
      search_dirs = { ws.path }
      title = 'Grep in ' .. ws.name
    else
      utils.notify('Workspace not found', vim.log.levels.ERROR)
      return
    end
  else
    local session = state.get_session()
    if #session == 0 then
      utils.notify('No workspaces in session')
      return
    end
    search_dirs = vim.tbl_map(function(ws)
      return ws.path
    end, session)
    title = 'Grep in Workspaces (' .. #session .. ')'
  end

  if #search_dirs == 1 then
    fzf.live_grep(vim.tbl_extend('force', opts, {
      cwd = search_dirs[1],
      prompt = title .. '> ',
    }))
  else
    -- For multiple directories
    fzf.live_grep(vim.tbl_extend('force', opts, {
      cwd = search_dirs[1],
      search_paths = search_dirs,
      prompt = title .. '> ',
    }))
  end
end

---Show buffers filtered by workspace using fzf-lua
---@param workspace_path? string
---@param opts? table
function M.buffers(workspace_path, opts)
  if not has_fzf then
    utils.notify('fzf-lua not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local filter_ws = nil
  local title = 'Workspace Buffers'

  if workspace_path then
    filter_ws = state.find_by_path(workspace_path)
    if not filter_ws then
      utils.notify('Workspace not found', vim.log.levels.ERROR)
      return
    end
    title = 'Buffers in ' .. filter_ws.name
  end

  -- Get workspace buffers
  local buffers = vim.api.nvim_list_bufs()
  local entries = {}
  local buf_map = {}

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buflisted') then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname ~= '' then
        local ws = state.find_by_file(bufname)
        if ws then
          if not filter_ws or filter_ws.path == ws.path then
            local rel_path = utils.relative_path(bufname, ws.path)
            local display = string.format('[%s] %s', ws.name, rel_path)
            table.insert(entries, display)
            buf_map[display] = { bufnr = bufnr, bufname = bufname }
          end
        end
      end
    end
  end

  if #entries == 0 then
    utils.notify('No buffers in workspace(s)')
    return
  end

  fzf.fzf_exec(entries, vim.tbl_extend('force', opts, {
    prompt = title .. '> ',
    actions = {
      ['default'] = function(selected)
        if selected and selected[1] then
          local buf = buf_map[selected[1]]
          if buf then
            vim.api.nvim_set_current_buf(buf.bufnr)
          end
        end
      end,
    },
    previewer = 'builtin',
  }))
end

---Quick workspace switcher using fzf-lua
---@param opts? table
function M.switch_workspace(opts)
  if not has_fzf then
    utils.notify('fzf-lua not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local session = state.get_session()

  if #session == 0 then
    utils.notify('No workspaces in session')
    return
  end

  local active = state.get_active()
  local entries = {}
  local ws_map = {}

  for _, ws in ipairs(session) do
    local prefix = (active and active.path == ws.path) and utils.icon('active') or utils.icon('workspace')
    local display = string.format('%s %s', prefix, ws.name)
    table.insert(entries, display)
    ws_map[display] = ws
  end

  fzf.fzf_exec(entries, vim.tbl_extend('force', opts, {
    prompt = 'Switch Workspace> ',
    actions = {
      ['default'] = function(selected)
        if selected and selected[1] then
          local ws = ws_map[selected[1]]
          if ws then
            state.set_active(ws)
            utils.notify('Active: ' .. ws.name)
          end
        end
      end,
    },
  }))
end

return M
