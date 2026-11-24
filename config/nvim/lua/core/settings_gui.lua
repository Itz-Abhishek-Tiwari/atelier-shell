local M = {}
local server_job = nil

function M.open(hash)
	hash = hash or "settings"
	local docs_path = vim.fn.stdpath("config") .. "/docs"
	local server_js = docs_path .. "/server.js"

	if vim.fn.filereadable(server_js) == 0 then
		vim.notify("Settings server script not found: " .. server_js, vim.log.levels.ERROR)
		return
	end

	-- Start server in background if it's not already running
	if not server_job then
		local cmd = { "node", server_js }
		server_job = vim.fn.jobstart(cmd, {
			env = {
				NVIM_SERVER = vim.v.servername,
				PORT = "8085",
			},
			on_exit = function(_, _)
				server_job = nil
			end,
		})
	end

	-- Wait briefly for the server to bind to the port, then open in the default browser
	vim.defer_fn(function()
		local url = "http://localhost:8085/#" .. hash
		local open_cmd
		if vim.fn.has("mac") == 1 then
			open_cmd = "open " .. vim.fn.shellescape(url)
		elseif vim.fn.has("win32") == 1 then
			open_cmd = "start " .. url
		else
			open_cmd = "xdg-open " .. vim.fn.shellescape(url)
		end
		vim.fn.system(open_cmd)
		vim.notify("⚡ NamiConfig Server opened: " .. url, vim.log.levels.INFO, { title = "NamiConfig" })
	end, 150)
end

-- Clean up background process when Neovim exits
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		if server_job then
			vim.fn.jobstop(server_job)
		end
	end,
})

return M
