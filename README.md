# workspaces.nvim

https://github.com/user-attachments/assets/24e9e845-26f6-46e9-92e1-ce870df7168e

Multi-root workspace management for Neovim, inspired by VSCode's workspace feature.

Open and manage multiple project directories in a single Neovim session with full LSP support, file navigation, and seamless integration with your favorite plugins.

## Features

- **Multi-Root Workspaces** - Open multiple project directories simultaneously
- **Hybrid Storage** - Central registry + per-project `.nvim-workspace.json` files
- **Related Workspaces** - Define related projects that open together (like monorepos)
- **LSP Integration** - Automatic workspace folder management for LSP servers
- **Neo-tree Integration** - Browse all your workspace roots in the file explorer
- **Telescope/fzf-lua Pickers** - Search files and grep across all workspaces
- **Lualine Component** - See active workspace in your statusline
- **Workspace-Aware Terminals** - Spawn terminals in the correct project directory
- **Per-Workspace Git Status** - Track git state across all your projects
- **Buffer Grouping** - Organize and navigate buffers by workspace
- **Shareable Configs** - Commit `.nvim-workspace.json` to share with your team

## How It Works

workspaces.nvim uses a **hybrid storage approach**:

```
~/.local/share/nvim/workspaces.json     # Central registry (paths + names only)
~/Projects/app/.nvim-workspace.json     # Project-specific config (shareable)
```

- **Central Registry**: Lightweight file tracking all known workspace paths
- **Project Config**: Per-project settings, related workspaces, LSP config (git-friendly)

## Requirements

- Neovim >= 0.8.0
- Optional: [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- Optional: [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- Optional: [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)
- Optional: [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'yourusername/workspaces.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim', -- optional
  },
  config = function()
    require('workspaces').setup({
      -- your configuration
    })
  end,
}
```

### Local Development

```lua
{
  dir = '~/Github/workspaces.nvim',
  config = function()
    require('workspaces').setup()
  end,
}
```

## Quick Start

```lua
require('workspaces').setup()
```

Then use these commands:

```vim
:WorkspaceAdd ~/Projects/my-app      " Add a workspace
:WorkspaceOpen ~/Projects/api        " Add and open in session
:WorkspaceList                       " List all workspaces
:WorkspaceSelect                     " Pick workspace with UI (switches directory)
```

## Project Config File

Initialize a project-specific config with `:WorkspaceInit`:

```json
// ~/Projects/my-app/.nvim-workspace.json
{
  "version": 1,
  "name": "My App",
  "related": [
    "../shared-lib",
    "~/Projects/api-server"
  ],
  "settings": {
    "formatOnSave": true
  },
  "lsp": {
    "tsserver": {
      "init_options": {}
    }
  }
}
```

Open all related workspaces with `:WorkspaceRelated open`.

## Configuration

```lua
require('workspaces').setup({
  -- Central registry location
  workspaces_file = vim.fn.stdpath('data') .. '/workspaces.json',

  -- Enable notifications
  notify = true,

  -- Change directory when switching workspaces
  change_dir_on_switch = true,

  -- Sort workspaces by: "name", "recent", "path"
  sort_by = 'recent',

  -- Auto-detect project root when opening files
  auto_detect_root = true,

  -- Patterns to identify project roots
  root_patterns = {
    '.git',
    'package.json',
    'Cargo.toml',
    'go.mod',
    'pyproject.toml',
    'Makefile',
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
    neo_tree = { enabled = true },
    telescope = { enabled = true },
    fzf_lua = { enabled = true },
    lualine = { enabled = true, show_icon = true },
    lsp = { enabled = true, auto_add_workspace_folders = true },
  },

  -- Lifecycle hooks
  hooks = {
    on_workspace_add = function(workspace) end,
    on_workspace_open = function(workspace) end,
    on_workspace_remove = function(workspace) end,
    on_workspaces_changed = function(workspaces) end,
  },
})
```

## Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `:Workspace [subcommand]` | Main command with subcommands |
| `:WorkspaceAdd [path] [name]` | Add a workspace (defaults to cwd) |
| `:WorkspaceRemove [path]` | Remove a workspace |
| `:WorkspaceOpen [path]` | Open workspace in current session |
| `:WorkspaceClose [path]` | Close workspace from session |
| `:WorkspaceList` | List all workspaces |
| `:WorkspaceSelect` | Pick workspace (changes directory) |

### Project Config Commands

| Command | Description |
|---------|-------------|
| `:WorkspaceInit [path]` | Create `.nvim-workspace.json` |
| `:WorkspaceEdit` | Edit project's `.nvim-workspace.json` |
| `:WorkspaceRelated list` | List related workspaces |
| `:WorkspaceRelated add <path>` | Add a related workspace |
| `:WorkspaceRelated remove` | Remove a related workspace |
| `:WorkspaceRelated open` | Open all related workspaces |

### Telescope Commands

| Command | Description |
|---------|-------------|
| `:Telescope workspaces` | Pick workspace |
| `:Telescope workspace_files` | Find files in workspaces |
| `:Telescope workspace_grep` | Grep in workspaces |
| `:Telescope workspace_buffers` | Show buffers by workspace |

### Other Commands

| Command | Description |
|---------|-------------|
| `:WorkspaceTree` | Show Neo-tree for workspace |
| `:WorkspaceTerminal[!]` | Open terminal (! for floating) |
| `:WorkspaceGit [status\|lazygit]` | Git operations |
| `:WorkspaceBuffers [close\|orphans]` | Buffer management |
| `:WorkspacePicker [all\|session]` | Floating picker UI |

## Keymaps

The plugin doesn't set any keymaps by default. Here are some suggestions:

```lua
-- Workspace management
vim.keymap.set('n', '<leader>wa', ':WorkspaceAdd<CR>', { desc = 'Add workspace' })
vim.keymap.set('n', '<leader>wo', ':WorkspaceOpen<CR>', { desc = 'Open workspace' })
vim.keymap.set('n', '<leader>wc', ':WorkspaceClose<CR>', { desc = 'Close workspace' })
vim.keymap.set('n', '<leader>wl', ':WorkspaceList<CR>', { desc = 'List workspaces' })
vim.keymap.set('n', '<leader>ws', ':WorkspaceSelect<CR>', { desc = 'Select workspace' })
vim.keymap.set('n', '<leader>wp', ':WorkspacePicker<CR>', { desc = 'Workspace picker' })

-- Related workspaces
vim.keymap.set('n', '<leader>wr', ':WorkspaceRelated open<CR>', { desc = 'Open related' })

-- Telescope
vim.keymap.set('n', '<leader>wf', ':Telescope workspace_files<CR>', { desc = 'Workspace files' })
vim.keymap.set('n', '<leader>wg', ':Telescope workspace_grep<CR>', { desc = 'Workspace grep' })

-- Terminal
vim.keymap.set('n', '<leader>wt', ':WorkspaceTerminal<CR>', { desc = 'Workspace terminal' })
vim.keymap.set('n', '<leader>wT', ':WorkspaceTerminal!<CR>', { desc = 'Floating terminal' })
```

## Lualine Integration

Add the workspace component to your lualine config:

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      'filename',
      {
        function()
          return require('workspaces.integrations.lualine').get_status()
        end,
        cond = function()
          return require('workspaces.integrations.lualine').has_workspaces()
        end,
      },
    },
  },
})
```

## API

```lua
local workspaces = require('workspaces')

-- Add/remove workspaces
workspaces.add('/path/to/project', 'My Project')
workspaces.remove('/path/to/project')

-- Session management
workspaces.open('/path/to/project')
workspaces.close('/path/to/project')

-- Query workspaces
local all = workspaces.get_all()
local session = workspaces.get_session()
local active = workspaces.get_active()

-- Find workspaces
local ws = workspaces.find_by_path('/path')
local ws = workspaces.find_by_name('My Project')
local ws = workspaces.find_by_file('/path/to/file.lua')

-- Set active workspace
workspaces.set_active('/path/to/project')

-- Rename
workspaces.rename('/path', 'New Name')
```

## Events

The plugin fires these User autocommands:

```lua
-- When active workspace changes
vim.api.nvim_create_autocmd('User', {
  pattern = 'WorkspacesActiveChanged',
  callback = function(args)
    local workspace = args.data.workspace
    print('Active workspace: ' .. workspace.name)
  end,
})

-- When git status is refreshed
vim.api.nvim_create_autocmd('User', {
  pattern = 'WorkspacesGitRefreshed',
  callback = function()
    -- Update your UI
  end,
})
```

## Health Check

Run `:checkhealth workspaces` to verify your setup.

## File Locations

| File | Purpose |
|------|---------|
| `~/.local/share/nvim/workspaces.json` | Central registry of all workspaces |
| `<project>/.nvim-workspace.json` | Project-specific config (commit to git!) |

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
