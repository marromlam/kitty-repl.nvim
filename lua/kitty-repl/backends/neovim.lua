-- Backend: Neovim built-in terminal (:terminal)
-- Sends text to a :terminal buffer inside Neovim via chansend.
-- Tracks open terminal buffers via TermOpen/TermClose autocmds (registered in setup).

local M = {}

local state = {
	jobid = nil, -- channel ID of the target terminal
	open = false,
	config = {},
}

function M.init(cfg)
	state.config = cfg

	-- Register autocmds to track :terminal buffers
	vim.api.nvim_create_autocmd("TermOpen", {
		group = vim.api.nvim_create_augroup("KittyREPLNeovimBackend", { clear = true }),
		callback = function(ev)
			-- Store the most recently opened terminal as default target
			local jobid = vim.bo[ev.buf].channel
			if jobid and jobid ~= 0 then
				state.jobid = jobid
				state.open = true
			end
		end,
	})

	vim.api.nvim_create_autocmd("TermClose", {
		group = "KittyREPLNeovimBackend",
		callback = function(ev)
			local jobid = vim.bo[ev.buf].channel
			if jobid == state.jobid then
				state.jobid = nil
				state.open = false
			end
		end,
	})
end

function M.open()
	if state.open then
		vim.api.nvim_echo({ { "kitty-repl: REPL already open", "WarningMsg" } }, false, {})
		return
	end
	local kind = state.config.window_kind or "split"
	if kind == "window" then
		vim.cmd("tabnew | terminal")
	elseif kind == "split_below" then
		vim.cmd("split | terminal")
	else
		-- default: vertical split (pane to the right, consistent with tmux)
		vim.cmd("vsplit | terminal")
	end
	-- TermOpen autocmd fires synchronously and sets state.jobid / state.open
	vim.api.nvim_echo({ { "kitty-repl: opened Neovim terminal", "Normal" } }, false, {})
end

function M.send(text)
	if not state.jobid then
		return
	end
	-- chansend expects a list of lines or a single string
	vim.fn.chansend(state.jobid, text)
end

function M.kill()
	if not state.jobid then
		return
	end
	-- closing the terminal buffer stops the job
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].channel == state.jobid then
			vim.api.nvim_buf_delete(buf, { force = true })
			break
		end
	end
	state.jobid = nil
	state.open = false
end

function M.is_open()
	return state.open
end

function M.ValidEnv()
	-- Neovim terminal is always available
	return true
end

function M.ValidConfig()
	if not state.jobid then
		vim.api.nvim_echo({ { "kitty-repl: no terminal open", "WarningMsg" } }, false, {})
		return false
	end
	return true
end

return M
