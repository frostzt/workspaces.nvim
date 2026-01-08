# workspaces.nvim

Multi-root workspace management for Neovim, inspired by VSCode's workspace feature.

Open and manage multiple project directories in a single Neovim session with full LSP support, file navigation, and seamless integration with your favorite plugins.

## Features

- **Multi-Root Workspaces** - Open multiple project directories simultaneously
- **LSP Integration** - Automatic workspace folder management for LSP servers
- **Neo-tree Integration** - Browse all your workspace roots in the file explorer
- **Telescope/fzf-lua Pickers** - Search files and grep across all workspaces
- **Lualine Component** - See active workspace in your statusline
- **Workspace-Aware Terminals** - Spawn terminals in the correct project directory
- **Per-Workspace Git Status** - Track git state across all your projects
- **Buffer Grouping** - Organize and navigate buffers by workspace
- **Persistent Workspaces** - Save and restore your workspace configurations

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
:WorkspaceSelect                     " Pick workspace with UI
```

## Configuration

```lua
require('workspaces').setup({
  -- Where to store workspace data
  workspaces_file = vim.fn.stdpath('data') .. '/workspaces.json',

  -- Enable notifications
  notify = true,

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
    neo_tree = {
      enabled = true,
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
  },

  -- Lifecycle hooks
  hooks = {
    on_workspace_add = function(workspace)
      print('Added: ' .. workspace.name)
    end,
    on_workspace_open = function(workspace)
      -- Do something when workspace is opened
    end,
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
| `:WorkspaceSelect` | Open workspace picker |

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
local workspaces = require('workspaces')

-- Workspace management
vim.keymap.set('n', '<leader>wa', ':WorkspaceAdd<CR>', { desc = 'Add workspace' })
vim.keymap.set('n', '<leader>wo', ':WorkspaceOpen<CR>', { desc = 'Open workspace' })
vim.keymap.set('n', '<leader>wc', ':WorkspaceClose<CR>', { desc = 'Close workspace' })
vim.keymap.set('n', '<leader>wl', ':WorkspaceList<CR>', { desc = 'List workspaces' })
vim.keymap.set('n', '<leader>ws', ':WorkspaceSelect<CR>', { desc = 'Select workspace' })
vim.keymap.set('n', '<leader>wp', ':WorkspacePicker<CR>', { desc = 'Workspace picker' })

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
      -- Add workspace component
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

Or use the pre-configured component:

```lua
local ws_lualine = require('workspaces.integrations.lualine')

require('lualine').setup({
  sections = {
    lualine_c = {
      'filename',
      ws_lualine.component(),
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

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
