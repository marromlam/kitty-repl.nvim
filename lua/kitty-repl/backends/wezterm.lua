-- Backend: WezTerm terminal emulator
-- Sends text to a WezTerm pane via `wezterm cli send-text`.

local loop = vim.uv or vim.loop

local M = {}

local state = {
	pane_id = nil,
	open = false,
	config = {},
}

function M.init(cfg)
	state.config = cfg
	-- Allow pre-configuring a pane_id in setup()
	if cfg.wezterm_pane_id then
		state.pane_id = tostring(cfg.wezterm_pane_id)
		state.open = true
	end
end

function M.open()
	if state.open then
		vim.api.nvim_echo({ { "kitty-repl: REPL already open", "WarningMsg" } }, false, {})
		return
	end

	-- If a pane_direction is configured, resolve it to a pane ID automatically.
	local dir = state.config.wezterm_pane_direction
	if dir then
		local handle = io.popen("wezterm cli get-pane-direction " .. dir .. " 2>/dev/null")
		if handle then
			local result = handle:read("*a")
			handle:close()
			result = vim.trim(result)
			if result ~= "" then
				state.pane_id = result
				state.open = true
				vim.api.nvim_echo({ { "kitty-repl: attached to wezterm pane " .. result, "Normal" } }, false, {})
				return
			end
		end
	end

	-- Fall back to user prompt
	vim.fn.inputsave()
	local id = vim.fn.input("WezTerm pane_id: ", state.pane_id or "")
	vim.fn.inputrestore()
	if id ~= "" then
		state.pane_id = id
		state.open = true
		vim.api.nvim_echo({ { "kitty-repl: attached to wezterm pane " .. id, "Normal" } }, false, {})
	else
		vim.api.nvim_echo({ { "kitty-repl: no pane ID provided", "WarningMsg" } }, false, {})
	end
end

function M.send(text)
	if not state.pane_id then
		return
	end
	-- --no-paste sends literally without bracketed-paste wrapping (we handle
	-- that ourselves in the main module if cfg.bracketed_paste is set)
	loop.spawn("wezterm", {
		args = { "cli", "send-text", "--no-paste", "--pane-id", state.pane_id, text },
	})
end

function M.kill()
	-- WezTerm has no direct "kill pane" CLI; send exit command instead
	if state.pane_id then
		loop.spawn("wezterm", {
			args = { "cli", "send-text", "--no-paste", "--pane-id", state.pane_id, "exit\r" },
		})
	end
	state.pane_id = nil
	state.open = false
end

function M.is_open()
	return state.open
end

function M.ValidEnv()
	local handle = io.popen("wezterm cli list 2>/dev/null")
	if not handle then
		vim.api.nvim_echo({ { "kitty-repl: wezterm not found", "WarningMsg" } }, false, {})
		return false
	end
	local out = handle:read("*a")
	handle:close()
	if out == "" then
		vim.api.nvim_echo({ { "kitty-repl: no wezterm session found", "WarningMsg" } }, false, {})
		return false
	end
	return true
end

function M.ValidConfig()
	if not state.pane_id then
		vim.api.nvim_echo({ { "kitty-repl: no wezterm pane configured", "WarningMsg" } }, false, {})
		return false
	end
	return true
end

return M
