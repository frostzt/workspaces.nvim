---@class WorkspacesHealth
---Health check module for workspaces.nvim
local M = {}

local health = vim.health

---Run health checks
function M.check()
  health.start('workspaces.nvim')

  -- Check Neovim version
  M.check_nvim_version()

  -- Check required dependencies
  M.check_dependencies()

  -- Check optional integrations
  M.check_integrations()

  -- Check configuration
  M.check_config()

  -- Check workspace file
  M.check_workspace_file()
end

---Check Neovim version
function M.check_nvim_version()
  local version = vim.version()
  local version_str = string.format('%d.%d.%d', version.major, version.minor, version.patch)

  if version.major >= 0 and version.minor >= 9 then
    health.ok('Neovim version: ' .. version_str)
  elseif version.minor >= 8 then
    health.warn('Neovim version: ' .. version_str .. ' (0.9+ recommended)')
  else
    health.error('Neovim version: ' .. version_str .. ' (0.8+ required)')
  end
end

---Check required dependencies
function M.check_dependencies()
  -- plenary.nvim (optional but recommended)
  local plenary_ok = pcall(require, 'plenary')
  if plenary_ok then
    health.ok('plenary.nvim: installed')
  else
    health.info('plenary.nvim: not installed (optional)')
  end

  -- Check for JSON support
  if vim.json then
    health.ok('vim.json: available')
  else
    health.error('vim.json: not available (required for persistence)')
  end

  -- Check for vim.uv/vim.loop
  if vim.uv or vim.loop then
    health.ok('vim.uv/vim.loop: available')
  else
    health.warn('vim.uv/vim.loop: not available (some features may not work)')
  end
end

---Check optional integrations
function M.check_integrations()
  local config = require('workspaces.config').get()

  health.start('Optional Integrations')

  -- Neo-tree
  if config.integrations.neo_tree.enabled then
    local ok = pcall(require, 'neo-tree')
    if ok then
      health.ok('neo-tree.nvim: installed and enabled')
    else
      health.warn('neo-tree.nvim: enabled but not installed')
    end
  else
    health.info('neo-tree.nvim: disabled')
  end

  -- Telescope
  if config.integrations.telescope.enabled then
    local ok = pcall(require, 'telescope')
    if ok then
      health.ok('telescope.nvim: installed and enabled')
    else
      health.warn('telescope.nvim: enabled but not installed')
    end
  else
    health.info('telescope.nvim: disabled')
  end

  -- fzf-lua
  if config.integrations.fzf_lua.enabled then
    local ok = pcall(require, 'fzf-lua')
    if ok then
      health.ok('fzf-lua: installed and enabled')
    else
      health.info('fzf-lua: enabled but not installed')
    end
  else
    health.info('fzf-lua: disabled')
  end

  -- Lualine
  if config.integrations.lualine.enabled then
    local ok = pcall(require, 'lualine')
    if ok then
      health.ok('lualine.nvim: installed and enabled')
    else
      health.warn('lualine.nvim: enabled but not installed')
    end
  else
    health.info('lualine.nvim: disabled')
  end

  -- LSP
  if config.integrations.lsp.enabled then
    health.ok('LSP integration: enabled')
  else
    health.info('LSP integration: disabled')
  end

  -- Check for terminal integrations
  local toggleterm_ok = pcall(require, 'toggleterm')
  if toggleterm_ok then
    health.ok('toggleterm.nvim: installed')
  else
    health.info('toggleterm.nvim: not installed (using built-in terminal)')
  end

  -- Check for git tools
  local lazygit_installed = vim.fn.executable('lazygit') == 1
  if lazygit_installed then
    health.ok('lazygit: installed')
  else
    health.info('lazygit: not installed (optional)')
  end

  -- Check for fd (faster file finding)
  local fd_installed = vim.fn.executable('fd') == 1
  if fd_installed then
    health.ok('fd: installed (faster file finding)')
  else
    health.info('fd: not installed (using find)')
  end

  -- Check for ripgrep
  local rg_installed = vim.fn.executable('rg') == 1
  if rg_installed then
    health.ok('ripgrep: installed')
  else
    health.info('ripgrep: not installed (required for live grep)')
  end
end

---Check configuration
function M.check_config()
  health.start('Configuration')

  local ok, config = pcall(require, 'workspaces.config')
  if not ok then
    health.error('Failed to load configuration module')
    return
  end

  local cfg = config.get()

  -- Check workspaces file path
  if cfg.workspaces_file then
    health.ok('Workspaces file: ' .. cfg.workspaces_file)
  else
    health.error('Workspaces file path not configured')
  end

  -- Check root patterns
  if cfg.root_patterns and #cfg.root_patterns > 0 then
    health.ok('Root patterns configured: ' .. #cfg.root_patterns .. ' patterns')
  else
    health.warn('No root patterns configured')
  end

  -- Check sort_by
  local valid_sort = { 'name', 'recent', 'path' }
  if vim.tbl_contains(valid_sort, cfg.sort_by) then
    health.ok('Sort by: ' .. cfg.sort_by)
  else
    health.warn('Invalid sort_by value: ' .. tostring(cfg.sort_by))
  end
end

---Check workspace file
function M.check_workspace_file()
  health.start('Workspace Data')

  local config = require('workspaces.config').get()
  local filepath = config.workspaces_file

  if vim.fn.filereadable(filepath) == 1 then
    health.ok('Workspace file exists: ' .. filepath)

    -- Try to load it
    local persistence = require('workspaces.persistence')
    local workspaces = persistence.load()

    if workspaces then
      health.ok('Workspaces loaded: ' .. #workspaces .. ' workspace(s)')

      -- Check for invalid paths
      local invalid = 0
      for _, ws in ipairs(workspaces) do
        if vim.fn.isdirectory(ws.path) ~= 1 then
          invalid = invalid + 1
        end
      end

      if invalid > 0 then
        health.warn(invalid .. ' workspace(s) have invalid paths')
      end
    else
      health.warn('Failed to load workspaces from file')
    end
  else
    health.info('Workspace file does not exist yet (will be created on first use)')
  end

  -- Check file permissions
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if vim.fn.isdirectory(dir) == 1 then
    health.ok('Data directory exists: ' .. dir)
  else
    health.info('Data directory will be created: ' .. dir)
  end
end

return M
