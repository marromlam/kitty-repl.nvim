local fn = vim.fn
local cmd = vim.cmd
local loop = vim.loop
local nvim_set_keymap = vim.api.nvim_set_keymap

local M = {}

-- local variable with the command that is going to be executed
local the_command

-- this function is only to print lua dicts
-- I use it for debugging purposes
local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

--- Sleep function
--- Lua misses a sleep function, so I made one using the shell
--- sleep function. Be aware this function does not work on Windows
--- @param n number of seconds to sleep
local function sleep(n) os.execute('sleep ' .. tonumber(n)) end

-- Get largest id from all kitty windows
-- If the ID window is empty (default) then this function is used to get the
-- largest id from all kitty windows which should correspond with the kitty
-- window we just created.
-- @param id number identifying the kitty window, if this number is provided
-- then the function will return it
local function get_largest_id(id)
    local foo = nil
    if os.getenv('SSH_TTY') then
        foo = io.popen(
            [[ kitty @ --to=tcp:localhost:$KITTY_PORT ls | grep \"id\" | tr "\"id\":" " " | tr "," " " | tail -1 | sed 's/^ *//g' ]]
        )
    else
        foo = io.popen(
            [[ kitty @ --to=$KITTY_LISTEN_ON ls | grep \"id\" | tr "\"id\":" " " | tr "," " " | tail -1 | sed 's/^ *//g' ]]
        )
    end

    local bar = foo:read('*a')
    return tonumber(id or bar)
end

-- Get largest id from all kitty windows (wrapper for get_largest_id function)
-- If the ID window is empty (default) then this function is used to get the
-- largest id from all kitty windows which should correspond with the kitty
-- window we just created.
-- @param id number identifying the kitty window, if this number is provided
-- then the function will return it
function M.get_id(id) return get_largest_id(id) end

-- open runner
local function open_new_repl()
    if REPL.window_kind == 'attached' then
        if os.getenv('SSH_TTY') then
            loop.spawn('kitty', {
                args = {
                    '@',
                    '--to=tcp:localhost:' .. os.getenv('KITTY_PORT'),
                    'launch',
                    '--title=REPL',
                },
            })
        else
            -- print('Opening attached REPL')
            loop.spawn('kitty', {
                args = {
                    '@',
                    '--to=' .. os.getenv('KITTY_LISTEN_ON'),
                    'launch',
                    '--title=REPL',
                },
            })
        end
    else
        loop.spawn('kitty', { args = { '@', 'launch', '--title=REPL' } })
    end

    sleep(0.1)
    -- let's hope nobody creates a new kitty window before we get to it
    local window_id = get_largest_id(REPL.window_id)
    -- now we are ready to set the basic info for the repl
    REPL.run_cmd = { 'send-text', '--match=id:' .. window_id }
    REPL.kill_cmd = { 'close-window', '--match=id:' .. window_id }
    if os.getenv('SSH_TTY') then
        REPL.run_cmd = {
            '--to=tcp:localhost:' .. os.getenv('KITTY_PORT'),
            'send-text',
            '--match=id:' .. window_id,
        }
        REPL.kill_cmd = {
            '--to=tcp:localhost:' .. os.getenv('KITTY_PORT'),
            'close-window',
            '--match=id:' .. window_id,
        }
    end
    REPL.runner_open = true
end

local function repl_send(cmd_args, command)
    local args = { '@' }
    for _, v in pairs(cmd_args) do
        table.insert(args, v)
    end
    table.insert(args, command)
    loop.spawn('kitty', { args = args })
end

local function cook_command_python(region)
    local lines
    local command
    local last_line
    if region[1] == 0 then
        -- we only have selected one line here
        lines = vim.api.nvim_buf_get_lines(
            0,
            vim.api.nvim_win_get_cursor(0)[1] - 1,
            vim.api.nvim_win_get_cursor(0)[1],
            true
        )
        command = table.concat(lines, '\r') .. '\r'
    else
        -- we have several lines selected here
        lines = vim.api.nvim_buf_get_lines(0, region[1] - 1, region[2], true)
        --[[ last_line = lines[#lines - 0] -- lets get last_line and see if is indented or not
    -- print(dump(lines))
    -- print(last_line)
    if last_line:find("  ", 1, true) == 1 then
      -- this is an indented line, hence we add another CR in order to just run the line
      command = table.concat(lines, '\r') .. '\r\r'
    else
      command = table.concat(lines, '\n') .. '\r'
    end ]]

        -- lets use cpaste for now
        repl_send(REPL.run_cmd, '%cpaste -q\r')
        sleep(0.1)
        command = table.concat(lines, '\r') .. '\r--\r'
    end
    return command
end

local function cook_command_cpp(region)
    local lines
    local command
    local last_line
    if region[1] == 0 then
        -- we only have selected one line here
        lines = vim.api.nvim_buf_get_lines(
            0,
            vim.api.nvim_win_get_cursor(0)[1] - 1,
            vim.api.nvim_win_get_cursor(0)[1],
            true
        )
        command = table.concat(lines, '\r') .. '\r'
    else
        -- we have several lines selected here
        lines = vim.api.nvim_buf_get_lines(0, region[1] - 1, region[2], true)
        command = table.concat(lines, '\r') .. '\r'
    end
    return command
end

local function cook_command(region)
    local command
    if vim.bo.filetype == 'python' then
        command = cook_command_python(region)
    else
        command = cook_command_cpp(region)
    end
    return command
end

function M.repl_run(region)
    the_command = cook_command(region)
    vim.cmd([[delm <>]]) -- delete visual selection marks
    if REPL.runner_open == true then
        repl_send(REPL.run_cmd, the_command)
    else
        open_new_repl()
    end
end

function M.repl_select(id)
    REPL.window_id = id or REPL.window_id
    print('You have selected the following kitty window ID:', REPL.window_id)
end

function M.repl_start(jit_runner)
    if REPL.runner_open == true then
        if jit_runner == 'auto' then
            if vim.bo.filetype == 'python' then
                repl_send(
                    REPL.run_cmd,
                    "MPLBACKEND='module://kitty' ipython" .. '\r'
                )
            else
                repl_send(REPL.run_cmd, 'icpp' .. '\r')
            end
        else
            repl_send(REPL.run_cmd, jit_runner .. '\r')
        end
    else
        open_new_repl()
    end
end

function M.repl_run_again()
    if the_command then
        if REPL.runner_open == true then
            repl_send(REPL.run_cmd, the_command)
        else
            open_new_repl()
        end
    end
end

function M.repl_send_and_run(arg_command)
    if REPL.runner_open == true then
        repl_send(REPL.run_cmd, arg_command .. '\r')
    else
        open_new_repl()
    end
end

function M.repl_prompt_and_run()
    fn.inputsave()
    local command = fn.input('! ')
    fn.inputrestore()
    the_command = command .. '\r'
    if REPL.runner_open == true then
        repl_send(REPL.run_cmd, the_command)
    else
        open_new_repl()
    end
end

function M.repl_killer()
    if REPL.runner_open == true then repl_send(REPL.kill_cmd, nil) end
    REPL.runner_open = false
end

function M.repl_cleanup()
    if REPL.runner_open == true then repl_send(REPL.run_cmd, '') end
end

function M.repl_run_repl()
    -- get all the lines in the current buffer
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    -- get all lines starting with '# repl:'
    local repl_lines = {}
    for _, line in ipairs(lines) do
        if line:find('^# !') then
            table.insert(repl_lines, string.sub(line, 4))
        end
    end
    -- print the repl lines
    if REPL.runner_open == true then
        for _, line in ipairs(repl_lines) do
            repl_send(REPL.run_cmd, line .. '\n')
            os.execute('sleep ' .. tonumber(2))
        end
    else
        open_new_repl()
    end
end

local function create_commands()
    cmd(
        [[command! KittyREPLRunAgain lua require('kitty-repl').repl_run_again()]]
    )
    cmd(
        [[command! -range KittyREPLSend lua require('kitty-repl').repl_run(vim.region(0, vim.fn.getpos("'<"), vim.fn.getpos("'>"), "l", false)[0])]]
    )
    cmd(
        [[command! KittyREPLRun lua require('kitty-repl').repl_prompt_and_run()]]
    )
    cmd([[command! KittyREPLClear lua require('kitty-repl').repl_cleanup()]])
    cmd([[command! KittyREPLKill lua require('kitty-repl').repl_killer()]])
    cmd(
        [[command! KittyREPLStart lua require('kitty-repl').repl_start("auto")]]
    )
end

local function define_keymaps()
    opts = { noremap = true, silent = true }
    nvim_set_keymap('n', '<leader>;r', ':KittyREPLRun<cr>', opts)
    nvim_set_keymap('x', '<leader>;s', ':KittyREPLSend<cr>', opts)
    nvim_set_keymap('n', '<leader>;s', ':KittyREPLSend<cr>', opts)
    nvim_set_keymap('x', '<S-CR>', ':KittyREPLSend<cr><cr>', opts)
    nvim_set_keymap('n', '<S-CR>', ':KittyREPLSend<cr><cr>', opts)
    nvim_set_keymap('n', '<leader>;c', ':KittyREPLClear<cr>', opts)
    nvim_set_keymap('n', '<leader>;k', ':KittyREPLKill<cr>', opts)
    nvim_set_keymap('n', '<leader>;l', ':KittyREPLRunAgain<cr>', opts)
    -- trigger these automatically on extension
    nvim_set_keymap('n', '<leader>;w', ':KittyREPLStart<cr>', opts)
end

function M.setup(user_config)
    REPL = user_config or {}

    -- store the window id of the kitty window used for the REPL
    REPL.window_id = nil
    -- store kind of window will have the repl it can be `attached` or `native`
    REPL.window_kind = 'attached'
    REPL.debug = false
    if REPL.debug == true then LOGFILE = io.open('test.log', 'a') end
    -- we do not have any runner yet
    REPL.runner_open = false

    -- define keymaps
    create_commands()

    -- toggle keymaps
    if REPL.use_keymaps ~= nil then
        REPL.use_keymaps = REPL.use_keymaps
    else
        define_keymaps()
    end
end

-- Now let's ensure not REPL is open after we exit
vim.cmd([[
augroup KittyREPL
  autocmd!
  autocmd FileType * autocmd BufDelete <buffer> KittyREPLKill
  autocmd QuitPre *  KittyREPLKill
augroup end
]])

return M
