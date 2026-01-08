---@class WorkspacesTelescope
---Telescope integration for workspace-aware file finding and grepping
local M = {}

local state = require('workspaces.state')
local utils = require('workspaces.utils')
local config = require('workspaces.config')

local telescope_ok, telescope = pcall(require, 'telescope')
local pickers_ok, pickers = pcall(require, 'telescope.pickers')
local finders_ok, finders = pcall(require, 'telescope.finders')
local conf_ok, conf = pcall(require, 'telescope.config')
local actions_ok, actions = pcall(require, 'telescope.actions')
local action_state_ok, action_state = pcall(require, 'telescope.actions.state')

local has_telescope = telescope_ok and pickers_ok and finders_ok and conf_ok and actions_ok and action_state_ok

---Setup Telescope integration
function M.setup()
  if not has_telescope then
    return
  end

  -- Register extension
  M.register_extension()
end

---Register as Telescope extension
function M.register_extension()
  if not has_telescope then
    return
  end

  -- Register the extension
  telescope.register_extension({
    setup = function(ext_config, _)
      -- Extension setup if needed
    end,
    exports = {
      workspaces = M.workspace_picker,
      workspace_files = M.find_files,
      workspace_grep = M.live_grep,
      workspace_buffers = M.buffers,
    },
  })
end

---Workspace picker
---@param opts? table
function M.workspace_picker(opts)
  if not has_telescope then
    utils.notify('Telescope not available', vim.log.levels.ERROR)
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

  pickers
    .new(opts, {
      prompt_title = 'Workspaces',
      finder = finders.new_table({
        results = workspaces,
        entry_maker = function(ws)
          local prefix = ''
          if active and active.path == ws.path then
            prefix = utils.icon('active')
          elseif in_session[ws.path] then
            prefix = utils.icon('inactive')
          else
            prefix = utils.icon('workspace')
          end

          return {
            value = ws,
            display = string.format('%s %s  %s', prefix, ws.name, utils.truncate_path(ws.path, 40)),
            ordinal = ws.name .. ' ' .. ws.path,
            path = ws.path,
          }
        end,
      }),
      sorter = conf.values.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        -- Enter: Open workspace
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            state.open(selection.value.path)
            utils.notify('Opened: ' .. selection.value.name)
          end
        end)

        -- Ctrl-d: Remove from workspaces
        map('i', '<C-d>', function()
          local selection = action_state.get_selected_entry()
          if selection then
            local ok, err = state.remove(selection.value.path)
            if ok then
              utils.notify('Removed: ' .. selection.value.name)
              -- Refresh picker
              M.workspace_picker(opts)
            else
              utils.notify(err or 'Failed to remove', vim.log.levels.ERROR)
            end
          end
          actions.close(prompt_bufnr)
        end)

        -- Ctrl-r: Rename workspace
        map('i', '<C-r>', function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.ui.input({ prompt = 'New name: ', default = selection.value.name }, function(input)
              if input and input ~= '' then
                local ok, err = state.rename(selection.value.path, input)
                if ok then
                  utils.notify('Renamed to: ' .. input)
                else
                  utils.notify(err or 'Failed to rename', vim.log.levels.ERROR)
                end
              end
            end)
          end
        end)

        -- Ctrl-x: Close from session
        map('i', '<C-x>', function()
          local selection = action_state.get_selected_entry()
          if selection and state.close(selection.value.path) then
            utils.notify('Closed from session: ' .. selection.value.name)
            M.workspace_picker(opts)
          end
          actions.close(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

---Get project-scoped workspaces (current + related)
---Get project-scoped workspaces (session + current + related)
---@return Workspace[]
local function get_project_workspaces()
  local persistence = require('workspaces.persistence')
  local workspaces = {}
  local seen = {}

  -- 1. Add ALL session workspaces first
  for _, ws in ipairs(state.get_session()) do
    if not seen[ws.path] then
      table.insert(workspaces, ws)
      seen[ws.path] = true
    end
  end

  -- 2. Get current workspace
  local active = state.get_active()
  local cwd = vim.fn.getcwd()
  local current_ws = active or state.find_by_path(cwd)

  if current_ws then
    if not seen[current_ws.path] then
      table.insert(workspaces, current_ws)
      seen[current_ws.path] = true
    end

    -- 3. Add related workspaces
    local related_paths = persistence.get_related_workspaces(current_ws.path)
    for _, rel_path in ipairs(related_paths) do
      if not seen[rel_path] then
        local ws = state.find_by_path(rel_path)
        if ws then
          table.insert(workspaces, ws)
          seen[rel_path] = true
        end
      end
    end
  end

  return workspaces
end

---Find files across workspace(s)
---@param workspace_path? string Specific workspace path or nil for project workspaces
---@param opts? table
function M.find_files(workspace_path, opts)
  if not has_telescope then
    utils.notify('Telescope not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local search_dirs = {}

  if workspace_path then
    local ws = state.find_by_path(workspace_path)
    if ws then
      search_dirs = { ws.path }
      opts.prompt_title = 'Files in ' .. ws.name
    else
      utils.notify('Workspace not found', vim.log.levels.ERROR)
      return
    end
  else
    -- Use project-scoped workspaces (current + related)
    local workspaces = get_project_workspaces()
    if #workspaces == 0 then
      utils.notify('No workspace for current directory. Use :WorkspaceAdd first.')
      return
    end
    search_dirs = vim.tbl_map(function(ws)
      return ws.path
    end, workspaces)
    if #workspaces == 1 then
      opts.prompt_title = 'Files in ' .. workspaces[1].name
    else
      opts.prompt_title = 'Files in Project (' .. #workspaces .. ' workspaces)'
    end
  end

  -- Use telescope builtin with search_dirs
  require('telescope.builtin').find_files(vim.tbl_extend('force', opts, {
    search_dirs = search_dirs,
  }))
end

---Live grep across workspace(s)
---@param workspace_path? string
---@param opts? table
function M.live_grep(workspace_path, opts)
  if not has_telescope then
    utils.notify('Telescope not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local search_dirs = {}

  if workspace_path then
    local ws = state.find_by_path(workspace_path)
    if ws then
      search_dirs = { ws.path }
      opts.prompt_title = 'Grep in ' .. ws.name
    else
      utils.notify('Workspace not found', vim.log.levels.ERROR)
      return
    end
  else
    -- Use project-scoped workspaces (current + related)
    local workspaces = get_project_workspaces()
    if #workspaces == 0 then
      utils.notify('No workspace for current directory. Use :WorkspaceAdd first.')
      return
    end
    search_dirs = vim.tbl_map(function(ws)
      return ws.path
    end, workspaces)
    if #workspaces == 1 then
      opts.prompt_title = 'Grep in ' .. workspaces[1].name
    else
      opts.prompt_title = 'Grep in Project (' .. #workspaces .. ' workspaces)'
    end
  end

  require('telescope.builtin').live_grep(vim.tbl_extend('force', opts, {
    search_dirs = search_dirs,
  }))
end

---Show buffers filtered by workspace
---@param workspace_path? string
---@param opts? table
function M.buffers(workspace_path, opts)
  if not has_telescope then
    utils.notify('Telescope not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local filter_ws = nil

  if workspace_path then
    filter_ws = state.find_by_path(workspace_path)
    if not filter_ws then
      utils.notify('Workspace not found', vim.log.levels.ERROR)
      return
    end
    opts.prompt_title = 'Buffers in ' .. filter_ws.name
  else
    opts.prompt_title = 'Workspace Buffers'
  end

  -- Get buffers
  local buffers = vim.api.nvim_list_bufs()
  local workspace_buffers = {}

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buflisted') then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname ~= '' then
        local ws = state.find_by_file(bufname)
        if ws then
          if not filter_ws or filter_ws.path == ws.path then
            table.insert(workspace_buffers, {
              bufnr = bufnr,
              bufname = bufname,
              workspace = ws,
            })
          end
        end
      end
    end
  end

  if #workspace_buffers == 0 then
    utils.notify('No buffers in workspace(s)')
    return
  end

  pickers
    .new(opts, {
      prompt_title = opts.prompt_title,
      finder = finders.new_table({
        results = workspace_buffers,
        entry_maker = function(entry)
          local rel_path = utils.relative_path(entry.bufname, entry.workspace.path)
          return {
            value = entry,
            display = string.format('[%s] %s', entry.workspace.name, rel_path),
            ordinal = entry.workspace.name .. ' ' .. rel_path,
            bufnr = entry.bufnr,
            filename = entry.bufname,
          }
        end,
      }),
      sorter = conf.values.generic_sorter(opts),
      previewer = conf.values.file_previewer(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            vim.api.nvim_set_current_buf(selection.bufnr)
          end
        end)
        return true
      end,
    })
    :find()
end

---Add current directory as workspace via Telescope directory picker
---@param opts? table
function M.add_workspace(opts)
  if not has_telescope then
    utils.notify('Telescope not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}

  require('telescope.builtin').find_files(vim.tbl_extend('force', opts, {
    prompt_title = 'Select Workspace Directory',
    find_command = { 'find', '.', '-type', 'd', '-maxdepth', '3' },
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          local path = selection.path or selection[1]
          local ws, err = state.add(path)
          if ws then
            state.open(ws.path)
            utils.notify('Added workspace: ' .. ws.name)
          else
            utils.notify(err or 'Failed to add workspace', vim.log.levels.ERROR)
          end
        end
      end)
      return true
    end,
  }))
end

---Quick workspace switcher
---@param opts? table
function M.switch_workspace(opts)
  if not has_telescope then
    utils.notify('Telescope not available', vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local session = state.get_session()

  if #session == 0 then
    utils.notify('No workspaces in session')
    return
  end

  local active = state.get_active()

  pickers
    .new(opts, {
      prompt_title = 'Switch Workspace',
      finder = finders.new_table({
        results = session,
        entry_maker = function(ws)
          local prefix = (active and active.path == ws.path) and utils.icon('active') or utils.icon('workspace')
          return {
            value = ws,
            display = string.format('%s %s', prefix, ws.name),
            ordinal = ws.name,
          }
        end,
      }),
      sorter = conf.values.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            state.set_active(selection.value)
            utils.notify('Active: ' .. selection.value.name)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
