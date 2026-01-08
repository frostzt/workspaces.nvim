---@class Workspaces
---@field config WorkspacesConfig
---@field state WorkspacesState
local M = {}

local config = require('workspaces.config')
local state = require('workspaces.state')
local utils = require('workspaces.utils')

---Setup the plugin
---@param opts? WorkspacesConfig
function M.setup(opts)
  -- Initialize configuration
  config.setup(opts)

  -- Initialize state
  state.init()

  -- Setup commands
  require('workspaces.commands').setup()

  -- Setup LSP integration
  require('workspaces.lsp').setup()

  -- Setup integrations based on config
  M.setup_integrations()

  -- Setup autocommands
  M.setup_autocmds()

  -- Auto-detect current directory as workspace
  local cfg = config.get()
  if cfg.auto_detect_root then
    vim.defer_fn(function()
      M.auto_detect_workspace()
    end, 100)
  end
end

---Setup plugin integrations
function M.setup_integrations()
  local cfg = config.get()

  -- Neo-tree integration
  if cfg.integrations.neo_tree.enabled and utils.has_plugin('neo-tree') then
    local ok, neo_tree = pcall(require, 'workspaces.integrations.neo-tree')
    if ok then
      neo_tree.setup()
    end
  end

  -- Telescope integration
  if cfg.integrations.telescope.enabled and utils.has_plugin('telescope') then
    local ok, telescope = pcall(require, 'workspaces.integrations.telescope')
    if ok then
      telescope.setup()
    end
  end

  -- fzf-lua integration
  if cfg.integrations.fzf_lua.enabled and utils.has_plugin('fzf-lua') then
    local ok, fzf = pcall(require, 'workspaces.integrations.fzf-lua')
    if ok then
      fzf.setup()
    end
  end

  -- Lualine integration
  if cfg.integrations.lualine.enabled and utils.has_plugin('lualine') then
    local ok, lualine = pcall(require, 'workspaces.integrations.lualine')
    if ok then
      lualine.setup()
    end
  end

  -- Always setup these modules (they have their own commands)
  require('workspaces.ui.picker').setup()
  require('workspaces.terminal').setup()
  require('workspaces.git').setup()
  require('workspaces.buffers').setup()
end

---Setup autocommands
function M.setup_autocmds()
  local augroup = vim.api.nvim_create_augroup('Workspaces', { clear = true })

  -- Track active workspace based on buffer
  vim.api.nvim_create_autocmd('BufEnter', {
    group = augroup,
    callback = function(args)
      -- Guard against invalid buffers
      if not args.buf or not vim.api.nvim_buf_is_valid(args.buf) then
        return
      end

      local ok, bufname = pcall(vim.api.nvim_buf_get_name, args.buf)
      if not ok or bufname == '' then
        return
      end

      local workspace = state.find_by_file(bufname)
      if workspace and state.active_workspace ~= workspace then
        -- Don't change dir on every BufEnter, just track active
        state.set_active(workspace, { change_dir = false })
      end
    end,
  })

  -- Auto-detect workspace for new files
  vim.api.nvim_create_autocmd('BufNew', {
    group = augroup,
    callback = function(args)
      local cfg = config.get()
      if not cfg.auto_detect_root then
        return
      end

      vim.defer_fn(function()
        -- Check if buffer is still valid before accessing it
        if not args.buf or not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end

        local ok, bufname = pcall(vim.api.nvim_buf_get_name, args.buf)
        if not ok or bufname == '' then
          return
        end

        if not state.find_by_file(bufname) then
          local root = utils.find_root(bufname, cfg.root_patterns)
          if root and not state.find_by_path(root) then
            -- Optionally auto-add detected roots
            -- For now, just skip
          end
        end
      end, 100)
    end,
  })
end

---Auto-detect workspace from current directory
function M.auto_detect_workspace()
  local cwd = vim.fn.getcwd()
  local cfg = config.get()

  -- Check if current directory should be a workspace
  local root = utils.find_root(cwd, cfg.root_patterns)
  if root then
    -- Check if already exists
    if not state.find_by_path(root) then
      -- Don't auto-add, but if it exists, open it
    else
      state.open(root)
    end
  elseif vim.fn.isdirectory(cwd) == 1 then
    -- CWD is valid, check if it's a known workspace
    local existing = state.find_by_path(cwd)
    if existing then
      state.open(cwd)
    end
  end
end

-- Public API --

---Add a workspace
---@param path string
---@param name? string
---@return Workspace?, string?
function M.add(path, name)
  return state.add(path, name)
end

---Remove a workspace
---@param path string
---@return boolean, string?
function M.remove(path)
  return state.remove(path)
end

---Open a workspace in the current session
---@param path string
---@return Workspace?, string?
function M.open(path)
  return state.open(path)
end

---Close a workspace from the current session
---@param path string
---@return boolean
function M.close(path)
  return state.close(path)
end

---Get all workspaces
---@return Workspace[]
function M.get_all()
  return state.get_all_sorted()
end

---Get session workspaces
---@return Workspace[]
function M.get_session()
  return state.get_session()
end

---Get active workspace
---@return Workspace?
function M.get_active()
  return state.get_active()
end

---Set active workspace
---@param path string
---@return boolean
function M.set_active(path)
  local workspace = state.find_by_path(path)
  if workspace then
    state.set_active(workspace)
    return true
  end
  return false
end

---Find workspace containing a file
---@param filepath string
---@return Workspace?
function M.find_by_file(filepath)
  return state.find_by_file(filepath)
end

---Find workspace by path
---@param path string
---@return Workspace?
function M.find_by_path(path)
  return state.find_by_path(path)
end

---Find workspace by name
---@param name string
---@return Workspace?
function M.find_by_name(name)
  return state.find_by_name(name)
end

---Rename a workspace
---@param path string
---@param new_name string
---@return boolean, string?
function M.rename(path, new_name)
  return state.rename(path, new_name)
end

---Get current configuration
---@return WorkspacesConfig
function M.get_config()
  return config.get()
end

return M
