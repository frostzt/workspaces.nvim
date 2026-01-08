-- workspaces.nvim - Multi-root workspace management for Neovim
-- Maintainer: frostzt
-- License: MIT

if vim.g.loaded_workspaces then
	return
end
vim.g.loaded_workspaces = true

-- Minimum Neovim version check
if vim.fn.has("nvim-0.8") ~= 1 then
	vim.notify("workspaces.nvim requires Neovim 0.8+", vim.log.levels.ERROR)
	return
end

-- Create user commands that work before setup()
vim.api.nvim_create_user_command("WorkspacesSetup", function()
	require("workspaces").setup()
end, { desc = "Initialize workspaces.nvim with default settings" })

-- Lazy setup: commands will auto-initialize if setup() wasn't called
local function ensure_setup()
	local config = require("workspaces.config")
	if not config.options or vim.tbl_isempty(config.options) then
		require("workspaces").setup()
	end
end

-- Create autocommand group
local augroup = vim.api.nvim_create_augroup("WorkspacesLazy", { clear = true })

-- Auto-setup on first relevant command
vim.api.nvim_create_autocmd("CmdlineEnter", {
	group = augroup,
	pattern = "*",
	once = true,
	callback = function()
		local cmdline = vim.fn.getcmdline()
		if cmdline:match("^Workspace") then
			ensure_setup()
		end
	end,
})
