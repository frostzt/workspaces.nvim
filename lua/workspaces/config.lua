---@class WorkspacesConfig
---@field workspaces_file string Path to the global workspaces file
---@field notify boolean Enable notifications
---@field sort_by "name"|"recent"|"path" How to sort workspaces
---@field auto_detect_root boolean Auto-detect project root when opening files
---@field root_patterns string[] Patterns to detect project root
---@field icons WorkspacesIcons Icon configuration
---@field integrations WorkspacesIntegrations Integration settings
---@field hooks WorkspacesHooks Lifecycle hooks

---@class WorkspacesIcons
---@field workspace string
---@field folder string
---@field active string
---@field inactive string

---@class WorkspacesIntegrations
---@field neo_tree NeoTreeIntegration
---@field telescope TelescopeIntegration
---@field fzf_lua FzfLuaIntegration
---@field lualine LualineIntegration
---@field lsp LspIntegration
---@field gitsigns GitsignsIntegration

---@class NeoTreeIntegration
---@field enabled boolean
---@field show_in_sidebar boolean

---@class TelescopeIntegration
---@field enabled boolean

---@class FzfLuaIntegration
---@field enabled boolean

---@class LualineIntegration
---@field enabled boolean
---@field show_icon boolean

---@class LspIntegration
---@field enabled boolean
---@field auto_add_workspace_folders boolean

---@class GitsignsIntegration
---@field enabled boolean

---@class WorkspacesHooks
---@field on_workspace_add fun(workspace: Workspace)?
---@field on_workspace_remove fun(workspace: Workspace)?
---@field on_workspace_open fun(workspace: Workspace)?
---@field on_workspaces_changed fun(workspaces: Workspace[])?

local M = {}

---@type WorkspacesConfig
M.defaults = {
  -- Where to store workspace configurations
  workspaces_file = vim.fn.stdpath('data') .. '/workspaces.json',

  -- Enable notifications
  notify = true,

  -- How to sort workspaces in lists: "name", "recent", "path"
  sort_by = 'recent',

  -- Auto-detect project root when opening files outside known workspaces
  auto_detect_root = true,

  -- Patterns to identify project root directories
  root_patterns = {
    '.git',
    '.hg',
    '.svn',
    'package.json',
    'Cargo.toml',
    'go.mod',
    'pyproject.toml',
    'Makefile',
    '.project',
    '.workspace',
  },

  -- Icons (requires Nerd Font)
  icons = {
    workspace = ' ',
    folder = ' ',
    active = ' ',
    inactive = ' ',
  },

  -- Integration settings
  integrations = {
    neo_tree = {
      enabled = true,
      show_in_sidebar = true,
    },
    telescope = {
      enabled = true,
    },
    fzf_lua = {
      enabled = true,
    },
    lualine = {
      enabled = true,
      show_icon = true,
    },
    lsp = {
      enabled = true,
      auto_add_workspace_folders = true,
    },
    gitsigns = {
      enabled = true,
    },
  },

  -- Lifecycle hooks
  hooks = {
    on_workspace_add = nil,
    on_workspace_remove = nil,
    on_workspace_open = nil,
    on_workspaces_changed = nil,
  },
}

---@type WorkspacesConfig
M.options = {}

---Setup configuration
---@param opts? WorkspacesConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', {}, M.defaults, opts or {})
end

---Get current configuration
---@return WorkspacesConfig
function M.get()
  return M.options
end

return M
