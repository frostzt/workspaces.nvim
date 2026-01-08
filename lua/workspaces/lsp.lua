---@class WorkspacesLsp
local M = {}

local config = require('workspaces.config')
local state = require('workspaces.state')
local utils = require('workspaces.utils')

---Add workspace folder to all active LSP clients
---@param workspace Workspace
function M.add_workspace_folder(workspace)
  local cfg = config.get()
  if not cfg.integrations.lsp.enabled then
    return
  end

  local path = workspace.path
  local uri = vim.uri_from_fname(path)

  -- Get all active clients
  local clients = vim.lsp.get_clients()

  for _, client in ipairs(clients) do
    -- Check if client supports workspace folders
    if client.server_capabilities.workspaceFolders then
      local workspace_folders = client.workspace_folders or {}

      -- Check if already added
      local already_added = false
      for _, folder in ipairs(workspace_folders) do
        if folder.uri == uri then
          already_added = true
          break
        end
      end

      if not already_added then
        -- Notify server of workspace folder addition
        local params = {
          event = {
            added = {
              { uri = uri, name = workspace.name },
            },
            removed = {},
          },
        }

        client.notify('workspace/didChangeWorkspaceFolders', params)

        -- Update client's workspace folders
        if not client.workspace_folders then
          client.workspace_folders = {}
        end
        table.insert(client.workspace_folders, { uri = uri, name = workspace.name })
      end
    end
  end
end

---Remove workspace folder from all active LSP clients
---@param workspace Workspace
function M.remove_workspace_folder(workspace)
  local cfg = config.get()
  if not cfg.integrations.lsp.enabled then
    return
  end

  local path = workspace.path
  local uri = vim.uri_from_fname(path)

  local clients = vim.lsp.get_clients()

  for _, client in ipairs(clients) do
    if client.server_capabilities.workspaceFolders and client.workspace_folders then
      -- Find and remove the folder
      for i, folder in ipairs(client.workspace_folders) do
        if folder.uri == uri then
          table.remove(client.workspace_folders, i)

          -- Notify server
          local params = {
            event = {
              added = {},
              removed = {
                { uri = uri, name = workspace.name },
              },
            },
          }

          client.notify('workspace/didChangeWorkspaceFolders', params)
          break
        end
      end
    end
  end
end

---Get all LSP workspace folders
---@return table[]
function M.get_workspace_folders()
  local folders = {}
  local seen = {}

  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do
    if client.workspace_folders then
      for _, folder in ipairs(client.workspace_folders) do
        if not seen[folder.uri] then
          seen[folder.uri] = true
          table.insert(folders, folder)
        end
      end
    end
  end

  return folders
end

---Sync session workspaces with LSP
function M.sync_workspace_folders()
  local cfg = config.get()
  if not cfg.integrations.lsp.enabled or not cfg.integrations.lsp.auto_add_workspace_folders then
    return
  end

  for _, workspace in ipairs(state.session_workspaces) do
    M.add_workspace_folder(workspace)
  end
end

---Setup LSP integration
function M.setup()
  local cfg = config.get()
  if not cfg.integrations.lsp.enabled then
    return
  end

  -- Auto-add workspace folders when LSP attaches
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('WorkspacesLspAttach', { clear = true }),
    callback = function(args)
      -- Small delay to ensure LSP is fully initialized
      vim.defer_fn(function()
        M.sync_workspace_folders()
      end, 100)
    end,
  })

  -- Listen for workspace changes
  vim.api.nvim_create_autocmd('User', {
    pattern = 'WorkspacesActiveChanged',
    group = vim.api.nvim_create_augroup('WorkspacesLspSync', { clear = true }),
    callback = function(args)
      if args.data and args.data.workspace then
        M.add_workspace_folder(args.data.workspace)
      end
    end,
  })
end

---Get workspace-specific LSP settings
---@param workspace Workspace
---@param server_name string
---@return table?
function M.get_workspace_settings(workspace, server_name)
  if not workspace.settings then
    return nil
  end

  local lsp_settings = workspace.settings.lsp
  if not lsp_settings then
    return nil
  end

  return lsp_settings[server_name]
end

---Set workspace-specific LSP settings
---@param workspace Workspace
---@param server_name string
---@param settings table
function M.set_workspace_settings(workspace, server_name, settings)
  if not workspace.settings then
    workspace.settings = {}
  end

  if not workspace.settings.lsp then
    workspace.settings.lsp = {}
  end

  workspace.settings.lsp[server_name] = vim.tbl_deep_extend(
    'force',
    workspace.settings.lsp[server_name] or {},
    settings
  )

  -- Persist
  local persistence = require('workspaces.persistence')
  persistence.save(state.workspaces)
end

return M
