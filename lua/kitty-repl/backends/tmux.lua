-------------------------------------------------------------------------------
-- TMUX BACKEND
-------------------------------------------------------------------------------
-- Sends text via tmux load-buffer | paste-buffer.
-- open() creates a new pane (split right) or new window based on window_kind.
-- If window_kind = 'attach', prompts the user to pick an existing pane.
-------------------------------------------------------------------------------

local loop = vim.uv or vim.loop

local M = {}

local state = {
	pane_id = nil,
	open = false,
	config = {},
}

function M.init(cfg)
	state.config = cfg
end

--- List all tmux panes as "pane_id  session:window.pane" strings.
local function list_panes()
	local handle = io.popen(
		"tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{window_name}#{?window_active, (active),}' 2>/dev/null"
	)
	if not handle then
		return {}
	end
	local out = handle:read("*a")
	handle:close()
	local panes = {}
	for line in out:gmatch("[^\n]+") do
		table.insert(panes, line)
	end
	return panes
end

function M.open()
	if state.open then
		vim.api.nvim_echo({ { "kitty-repl: REPL already open", "WarningMsg" } }, false, {})
		return
	end

	local kind = state.config.window_kind or "split"

	if kind == "attach" then
		-- Let user pick from existing panes
		local panes = list_panes()
		if #panes == 0 then
			vim.api.nvim_echo({ { "kitty-repl: no tmux panes found", "ErrorMsg" } }, false, {})
			return
		end
		vim.fn.inputsave()
		vim.api.nvim_echo({ { "Available panes:", "Normal" } }, true, {})
		for i, p in ipairs(panes) do
			vim.api.nvim_echo({ { string.format("  %d) %s", i, p), "Normal" } }, true, {})
		end
		local choice = vim.fn.input("Select pane (pane_id or number): ")
		vim.fn.inputrestore()
		if choice == "" then
			vim.api.nvim_echo({ { "kitty-repl: no pane selected", "WarningMsg" } }, false, {})
			return
		end
		-- Accept a number index or a raw pane_id like %3
		local idx = tonumber(choice)
		if idx and panes[idx] then
			state.pane_id = panes[idx]:match("^(%S+)")
		else
			state.pane_id = choice
		end
		state.open = true
		vim.api.nvim_echo({ { "kitty-repl: attached to tmux pane " .. state.pane_id, "Normal" } }, false, {})
		return
	end

	-- Create a new pane
	local tmux_cmd
	if kind == "window" then
		tmux_cmd = "tmux new-window -P -F '#{pane_id}' 2>&1"
	else
		-- 'split' (default): new pane to the right
		tmux_cmd = "tmux split-window -h -P -F '#{pane_id}' 2>&1"
	end

	local handle = io.popen(tmux_cmd)
	if not handle then
		vim.api.nvim_echo({ { "kitty-repl: failed to run tmux", "ErrorMsg" } }, false, {})
		return
	end
	local result = handle:read("*a")
	handle:close()
	local pane_id = vim.trim(result)
	if pane_id == "" then
		vim.api.nvim_echo(
			{ { 'kitty-repl: tmux returned no pane ID — try window_kind="attach"', "ErrorMsg" } },
			false,
			{}
		)
		return
	end
	if pane_id:find("^error") or pane_id:find("^can") then
		vim.api.nvim_echo({ { "kitty-repl: tmux error: " .. pane_id, "ErrorMsg" } }, false, {})
		return
	end
	state.pane_id = pane_id
	state.open = true
	vim.api.nvim_echo({ { "kitty-repl: opened tmux pane " .. pane_id, "Normal" } }, false, {})
end

function M.send(text)
	if not state.pane_id then
		return
	end

	-- Normalize: replace \r\n or \r with \n, then strip trailing newline
	local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	local has_trailing_newline = normalized:sub(-1) == "\n"
	local text_to_paste = normalized:gsub("\n$", "")

	if text_to_paste == "" then
		if has_trailing_newline then
			loop.spawn("tmux", { args = { "send-keys", "-t", state.pane_id, "Enter" } })
		end
		return
	end

	-- Chunk and send via load-buffer stdin + paste-buffer
	local chunk_size = 1000
	local len = #text_to_paste
	local i = 0
	repeat
		local chunk = text_to_paste:sub(i + 1, i + chunk_size)
		-- load-buffer - reads from stdin
		local handle = io.popen("tmux load-buffer -", "w")
		if handle then
			handle:write(chunk)
			handle:close()
		end
		os.execute("tmux paste-buffer -d -p -t " .. state.pane_id)
		i = i + chunk_size
	until i >= len

	-- Send Enter if original text had a trailing newline
	if has_trailing_newline then
		loop.spawn("tmux", { args = { "send-keys", "-t", state.pane_id, "Enter" } })
	end
end

function M.kill()
	if not state.pane_id then
		return
	end
	loop.spawn("tmux", {
		args = { "kill-pane", "-t", state.pane_id },
	})
	state.pane_id = nil
	state.open = false
end

function M.is_open()
	return state.open
end

function M.ValidEnv()
	local handle = io.popen("tmux list-sessions 2>/dev/null")
	if not handle then
		vim.api.nvim_echo({ { "kitty-repl: tmux not found", "WarningMsg" } }, false, {})
		return false
	end
	local out = handle:read("*a")
	handle:close()
	if out == "" then
		vim.api.nvim_echo({ { "kitty-repl: no tmux session running", "WarningMsg" } }, false, {})
		return false
	end
	return true
end

function M.ValidConfig()
	if not state.pane_id then
		vim.api.nvim_echo({ { "kitty-repl: no tmux pane open", "WarningMsg" } }, false, {})
		return false
	end
	return true
end

return M
