local loop = vim.uv or vim.loop

local M = {}

local state = {
	window_id = nil,
	run_cmd = nil,
	kill_cmd = nil,
	open = false,
	config = {},
}

function M.init(cfg)
	state.config = cfg
	state.window_id = cfg.window_id or nil
end

-- Get largest id from all kitty windows.
-- If id is provided, returns it directly (allows manual window selection).
local function get_largest_id(id)
	local foo
	if os.getenv("SSH_TTY") then
		foo = io.popen(
			[[ kitty @ --to=tcp:localhost:$KITTY_PORT ls | grep \"id\" | tr "\"id\":" " " | tr "," " " | tail -1 | sed 's/^ *//g' ]]
		)
	else
		foo = io.popen(
			[[ kitty @ --to=$KITTY_LISTEN_ON ls | grep \"id\" | tr "\"id\":" " " | tr "," " " | tail -1 | sed 's/^ *//g' ]]
		)
	end

	if not foo then
		return tonumber(id)
	end
	local bar = foo:read("*a")
	foo:close()
	return tonumber(id or bar)
end

-- Allow the user to manually target a specific kitty window.
function M.set_window_id(id)
	state.window_id = id
	if state.open then
		-- Rebuild run/kill commands for the new window ID
		local ssh = os.getenv("SSH_TTY")
		if ssh then
			local port = "--to=tcp:localhost:" .. os.getenv("KITTY_PORT")
			state.run_cmd = { port, "send-text", "--match=id:" .. id }
			state.kill_cmd = { port, "close-window", "--match=id:" .. id }
		else
			state.run_cmd = { "send-text", "--match=id:" .. id }
			state.kill_cmd = { "close-window", "--match=id:" .. id }
		end
	end
	print("Selected kitty window ID: " .. tostring(id))
end

-- Poll kitty for the new window ID, retrying up to max_attempts times.
-- Returns the window id or nil on timeout.
local function wait_for_new_window(old_id, max_attempts, interval_ms)
	for _ = 1, max_attempts do
		vim.uv.sleep(interval_ms)
		local new_id = get_largest_id(nil)
		if new_id and new_id ~= old_id then
			return new_id
		end
	end
	return nil
end

function M.open()
	-- Guard: don't spawn a second window if already open
	if state.open then
		vim.api.nvim_echo({ { "kitty-repl: REPL already open", "WarningMsg" } }, false, {})
		return
	end

	-- If the user pre-selected a window ID, trust it instead of spawning
	if state.window_id then
		local id = state.window_id
		local ssh = os.getenv("SSH_TTY")
		if ssh then
			local port = "--to=tcp:localhost:" .. os.getenv("KITTY_PORT")
			state.run_cmd = { port, "send-text", "--match=id:" .. id }
			state.kill_cmd = { port, "close-window", "--match=id:" .. id }
		else
			state.run_cmd = { "send-text", "--match=id:" .. id }
			state.kill_cmd = { "close-window", "--match=id:" .. id }
		end
		state.open = true
		vim.api.nvim_echo({ { "kitty-repl: attached to window " .. id, "Normal" } }, false, {})
		return
	end

	-- Snapshot the current largest ID so we can detect the new window
	local old_id = get_largest_id(nil) or 0

	local cfg = state.config
	local launch_args = { "@" }
	if cfg.window_kind == "attached" then
		if os.getenv("SSH_TTY") then
			table.insert(launch_args, "--to=tcp:localhost:" .. os.getenv("KITTY_PORT"))
		elseif os.getenv("KITTY_LISTEN_ON") then
			table.insert(launch_args, "--to=" .. os.getenv("KITTY_LISTEN_ON"))
		end
	end
	table.insert(launch_args, "launch")
	table.insert(launch_args, "--title=REPL")
	loop.spawn("kitty", { args = launch_args })

	-- Poll until the new window appears (up to 3 s in 100 ms steps)
	local window_id = wait_for_new_window(old_id, 30, 100)
	if not window_id then
		vim.api.nvim_echo({ { "kitty-repl: timed out waiting for new kitty window", "ErrorMsg" } }, false, {})
		return
	end

	state.run_cmd = { "send-text", "--match=id:" .. window_id }
	state.kill_cmd = { "close-window", "--match=id:" .. window_id }
	if os.getenv("SSH_TTY") then
		local port = "--to=tcp:localhost:" .. os.getenv("KITTY_PORT")
		state.run_cmd = { port, "send-text", "--match=id:" .. window_id }
		state.kill_cmd = { port, "close-window", "--match=id:" .. window_id }
	end
	state.open = true
	vim.api.nvim_echo({ { "kitty-repl: opened window " .. window_id, "Normal" } }, false, {})
end

local function kitty_send_stdin(text)
	local parts = { "kitty", "@" }
	for _, v in ipairs(state.run_cmd) do
		table.insert(parts, v)
	end
	table.insert(parts, "--stdin")
	local cmd = table.concat(
		vim.tbl_map(function(a)
			return "'" .. a:gsub("'", "'\\''") .. "'"
		end, parts),
		" "
	)
	local handle = io.popen(cmd, "w")
	if handle then
		handle:write(text)
		handle:close()
	end
end

function M.send(text)
	-- Normalize line endings, strip trailing newline (vim-slime pattern)
	local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	local has_trailing_newline = normalized:sub(-1) == "\n"
	local text_to_paste = normalized:gsub("\n$", "")

	if text_to_paste ~= "" then
		kitty_send_stdin(text_to_paste)
	end

	-- Send trailing newline as a separate call (vim-slime approach)
	if has_trailing_newline then
		kitty_send_stdin("\n")
	end
end

function M.kill()
	local args = { "@" }
	for _, v in ipairs(state.kill_cmd) do
		table.insert(args, v)
	end
	loop.spawn("kitty", { args = args })
	state.open = false
end

function M.is_open()
	return state.open
end

function M.ValidEnv()
	local listen_on = os.getenv("KITTY_LISTEN_ON")
	local ssh_port = os.getenv("KITTY_PORT")
	if not listen_on and not ssh_port then
		vim.api.nvim_echo(
			{ { "kitty-repl: $KITTY_LISTEN_ON not set — is kitty running with allow_remote_control?", "WarningMsg" } },
			false,
			{}
		)
		return false
	end
	return true
end

function M.ValidConfig()
	if not state.open then
		vim.api.nvim_echo({ { "kitty-repl: no kitty REPL window open", "WarningMsg" } }, false, {})
		return false
	end
	return true
end

return M
