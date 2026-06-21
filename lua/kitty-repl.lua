local fn = vim.fn

local M = {}

-- last executed command (for repl_run_again)
local the_command
-- active backend table
local backend
-- resolved backend name (set in setup)
local backend_name
-- user config
local cfg = {}

-- Default cell delimiters per filetype
local default_cell_delimiters = {
    python     = '# %%',
    lua        = '-- %%',
    r          = '# %%',
}

-- Start command prefix per filetype (e.g. '#;' in python means '#; ipython')
local default_start_prefixes = {
    python     = '#;',
    r          = '#;',
    lua        = '--;',
    cpp        = '//;',
    c          = '//;',
    javascript = '//;',
    typescript = '//;',
    julia      = '#;',
    sh         = '#;',
    bash       = '#;',
}

--- Return effective config, merging buffer-level overrides on top of global cfg.
local function effective_cfg()
    local buf_cfg = vim.b.kitty_repl_config
    if type(buf_cfg) == 'table' then
        local merged = {}
        for k, v in pairs(cfg) do merged[k] = v end
        for k, v in pairs(buf_cfg) do merged[k] = v end
        return merged
    end
    return cfg
end

-- Built-in language escape functions (user-extensible via cfg.escape_fns)
local escape_fns = {}

escape_fns.python = function(text)
    local cfg_local = effective_cfg() -- defined below, called at runtime only
    local use_ipython = cfg_local.python_ipython ~= false  -- default true

    local lines = vim.split(text, '\n', { plain = true })

    -- strip leading/trailing blank lines
    while #lines > 0 and lines[1]:match('^%s*$') do table.remove(lines, 1) end
    while #lines > 0 and lines[#lines]:match('^%s*$') do table.remove(lines) end
    if #lines == 0 then return '\n' end

    if #lines > 1 and use_ipython then
        -- IPython %cpaste protocol for multi-line
        backend.send('%cpaste -q\n')
        vim.uv.sleep(cfg_local.dispatch_ipython_pause or 100)
        return table.concat(lines, '\n') .. '\n--\n'
    end

    -- Single line or standard Python: dedent, then add a trailing newline
    -- after any indented block so Python doesn't wait for more input
    local indent = lines[1]:match('^(%s*)')
    local dedented = {}
    for _, l in ipairs(lines) do
        dedented[#dedented + 1] = l:sub(#indent + 1)
    end

    -- Insert extra newline after indented blocks (so `if/for/def` blocks execute)
    local result = {}
    for i, l in ipairs(dedented) do
        result[#result + 1] = l
        local next_l = dedented[i + 1]
        if next_l and l:match('^%s') and not next_l:match('^%s') and
           not next_l:match('^elif') and not next_l:match('^else') and
           not next_l:match('^except') and not next_l:match('^finally') then
            result[#result + 1] = ''
        end
    end

    return table.concat(result, '\n') .. '\n'
end

-- Apply filetype-specific escaping, falling back to appending \n
local function escape_text(text)
    local ft = vim.bo.filetype
    local escape_fn = (cfg.escape_fns and cfg.escape_fns[ft]) or escape_fns[ft]
    if escape_fn then return escape_fn(text) end
    -- Default: ensure text ends with a single newline
    return text:gsub('\n*$', '') .. '\n'
end


--- Open the backend pane, printing a notification first.
local function open_backend()
    vim.api.nvim_echo({ { 'kitty-repl: using backend ' .. backend_name .. ' to open a new pane', 'Normal' } }, false, {})
    backend.open()
end

--- Send raw text to the REPL, applying escaping and bracketed paste.
--- This is the single entry point for all text delivery.
--- Also stores the result in `the_command` for repl_run_again.
function M.send_text(text)
    -- Check environment is sane before trying to open
    if not backend.is_open() then
        if backend.ValidEnv and not backend.ValidEnv() then return end
        open_backend()
        -- Wait for the pane/shell to be ready before sending
        vim.uv.sleep(cfg.open_delay or 500)
    end
    local ecfg = effective_cfg()
    local escaped = escape_text(text)
    if ecfg.bracketed_paste then
        escaped = '\27[200~' .. escaped .. '\27[201~'
    end
    backend.send(escaped)
    the_command = escaped
end

--- Operator function: called by vim after the user completes a motion.
--- @param type string 'char', 'line', or 'block'
function M.send_op(type)
    local saved = fn.getreg('"')
    local saved_type = fn.getregtype('"')
    if type == 'line' then
        vim.cmd("silent '[,']yank")
    elseif type == 'char' then
        vim.cmd("silent normal! `[v`]y")
    else
        -- block: fall back to line-wise for REPL purposes
        vim.cmd("silent '[,']yank")
    end
    local text = fn.getreg('"')
    fn.setreg('"', saved, saved_type)

    local curpos
    if cfg.preserve_curpos ~= false then
        curpos = vim.api.nvim_win_get_cursor(0)
    end

    M.send_text(text)

    if curpos then
        vim.api.nvim_win_set_cursor(0, curpos)
    end
end

--- Set operatorfunc and return 'g@' to trigger operator mode.
--- Intended for use with `expr` keymap option.
function M.send_operator()
    vim.o.operatorfunc = "v:lua.require'kitty-repl'.send_op"
    return 'g@'
end

--- Send N lines from the current cursor position (default: 1) and advance cursor.
--- @param count number
function M.send_lines(count)
    count = count or 1
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, row - 1, row - 1 + count, false)
    M.send_text(table.concat(lines, '\n'))
    -- Advance cursor by count lines (stops at last line)
    local total = vim.api.nvim_buf_line_count(0)
    local next_row = math.min(row + count, total)
    vim.api.nvim_win_set_cursor(0, { next_row, 0 })
end

--- Send the current cell (block between cell delimiter lines).
function M.send_cell()
    local delimiter = cfg.cell_delimiter
        or default_cell_delimiters[vim.bo.filetype]
        or '# %%'
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- scan backward for the start of this cell
    local start_line = 1
    for i = cur - 1, 1, -1 do
        if lines[i]:find(vim.pesc(delimiter), 1, true) then
            start_line = i + 1
            break
        end
    end

    -- scan forward for the end of this cell
    local end_line = #lines
    for i = cur, #lines do
        if lines[i]:find(vim.pesc(delimiter), 1, true) then
            end_line = i - 1
            break
        end
    end

    local cell_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    M.send_text(table.concat(cell_lines, '\n') .. '\n')
end

--- Send selected/current-line region (used by KittyREPLSend command).
--- @param region table|nil {0} for single line, {start, end} for multi-line
function M.repl_run(region)
    if not backend.is_open() then
        M.repl_start('auto')
        return
    end
    if region == nil then
        local start_pos = vim.fn.getpos("'<")
        local end_pos   = vim.fn.getpos("'>")
        if start_pos[2] == 0 or end_pos[2] == 0 then
            -- no prior visual selection — send current line
            region = { 0 }
        else
            local r = vim.fn.getregionpos(start_pos, end_pos, { type = "V" })
            if #r <= 1 then
                region = { 0 }
            else
                region = { r[1][1][2], r[#r][2][2] }
            end
        end
    end

    local lines
    if region[1] == 0 then
        lines = vim.api.nvim_buf_get_lines(
            0,
            vim.api.nvim_win_get_cursor(0)[1] - 1,
            vim.api.nvim_win_get_cursor(0)[1],
            true
        )
    else
        lines = vim.api.nvim_buf_get_lines(0, region[1] - 1, region[2], true)
    end

    vim.cmd([[delm <>]]) -- delete visual selection marks
    M.send_text(table.concat(lines, '\n'))
end

function M.repl_select(id)
    if backend_name == 'kitty' then
        require('kitty-repl.backends.kitty').set_window_id(id)
    else
        vim.api.nvim_echo({ { 'kitty-repl: repl_select is only supported for the kitty backend', 'WarningMsg' } }, false, {})
    end
end

function M.repl_start(jit_runner)
    if backend.is_open() then
        vim.api.nvim_echo({ { 'kitty-repl: REPL already open', 'WarningMsg' } }, false, {})
        return
    end
    if backend.ValidEnv and not backend.ValidEnv() then return end
    open_backend()
    if not backend.is_open() then return end  -- open() failed
    if jit_runner == 'auto' then
        local ft = vim.bo.filetype
        local start_prefix = (cfg.start_prefixes and cfg.start_prefixes[ft])
            or default_start_prefixes[ft]
        local start_cmd
        if start_prefix then
            local pattern = '^' .. vim.pesc(start_prefix) .. '%s*(.+)'
            for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
                local cmd = line:match(pattern)
                if cmd then
                    start_cmd = cmd
                    break
                end
            end
        end
        if ft == 'python' then
            local mpl_prefix = (backend_name == 'kitty' or backend_name == 'tmux')
                and "MPLBACKEND='module://kitty' "
                or ''
            backend.send(mpl_prefix .. (start_cmd or 'ipython') .. '\n')
        elseif start_cmd then
            backend.send(start_cmd .. '\n')
        end
        -- other filetypes: just open the pane, don't assume an interpreter
    elseif jit_runner then
        backend.send(jit_runner .. '\n')
    end
end

function M.repl_run_again()
    if the_command then
        if not backend.is_open() then open_backend() end
        backend.send(the_command)
    end
end

function M.repl_send_and_run(arg_command)
    if not backend.is_open() then open_backend() end
    backend.send(arg_command .. '\r')
end

function M.repl_prompt_and_run()
    fn.inputsave()
    local command = fn.input('! ')
    fn.inputrestore()
    M.send_text(command)
end

--- Send text raw (no escaping, no \r appended). Used by :KittyREPLSend0.
function M.backend_send_raw(text)
    if not backend.is_open() then
        if backend.ValidEnv and not backend.ValidEnv() then return end
        open_backend()
    end
    backend.send(text)
end

function M.repl_killer()
    if backend.is_open() then
        backend.kill()
        vim.api.nvim_echo({ { 'kitty-repl: REPL closed', 'Normal' } }, false, {})
    end
end

function M.repl_cleanup()
    -- Ctrl-C to interrupt + Ctrl-U to clear the line
    if backend.is_open() then
        backend.send('\x03')
        backend.send('\x15')
    end
end

function M.repl_run_repl()
    local ft = vim.bo.filetype
    local prefix = (cfg.start_prefixes and cfg.start_prefixes[ft])
        or default_start_prefixes[ft]
        or '#;'
    local pattern = '^' .. vim.pesc(prefix) .. '%s*(.*)'
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    local repl_lines = {}
    for _, line in ipairs(lines) do
        local cmd = line:match(pattern)
        if cmd then
            table.insert(repl_lines, cmd)
        end
    end
    if not backend.is_open() then
        if backend.ValidEnv and not backend.ValidEnv() then return end
        open_backend()
        vim.uv.sleep(cfg.open_delay or 500)
        if not backend.is_open() then return end
    end
    local delay_ms = (cfg.repl_run_delay or 2) * 1000
    for _, line in ipairs(repl_lines) do
        backend.send(line .. '\n')
        vim.uv.sleep(delay_ms)
    end
end

local function create_commands()
    local c = vim.api.nvim_create_user_command
    c('KittyREPLRunAgain',  function() M.repl_run_again() end,       { force = true, desc = 'Re-send last command' })
    c('KittyREPLSend',      function(o)
        if o.range > 0 then
            M.repl_run({ o.line1, o.line2 })
        else
            M.repl_run()
        end
    end, { force = true, range = true, desc = 'Send selection/line to REPL' })
    c('KittyREPLSendLine',  function(o) M.send_lines(o.count) end,   { force = true, count = 1,    desc = 'Send N lines to REPL' })
    c('KittyREPLSendCell',  function() M.send_cell() end,            { force = true, desc = 'Send current cell to REPL' })
    c('KittyREPLSendRepl',  function() M.repl_run_repl() end,        { force = true, desc = 'Run all # ! lines in buffer' })
    c('KittyREPLRun',       function() M.repl_prompt_and_run() end,  { force = true, desc = 'Prompt and send to REPL' })
    c('KittyREPLClear',     function() M.repl_cleanup() end,         { force = true, desc = 'Clear REPL' })
    c('KittyREPLKill',      function() M.repl_killer() end,          { force = true, desc = 'Kill REPL' })
    c('KittyREPLStart',     function() M.repl_start('auto') end,     { force = true, desc = 'Start REPL interpreter' })
    c('KittyREPLSend1', function(o) M.repl_send_and_run(o.args) end, { force = true, nargs = 1, desc = 'Send text to REPL with Enter' })
    c('KittyREPLSend0', function(o) M.backend_send_raw(o.args) end,  { force = true, nargs = 1, desc = 'Send raw text to REPL' })
end

local function define_keymaps()
    local map = vim.keymap.set
    local o   = { noremap = true, silent = true }
    local ox  = { noremap = true, silent = true, expr = true }

    -- <Plug> mappings (always registered, safe to remap)
    map('n', '<Plug>(KittyREPLSend)',          M.send_operator,              { expr = true, desc = 'Send motion to REPL' })
    map('n', '<Plug>(KittyREPLSendLine)',      '<cmd>KittyREPLSendLine<cr>', { desc = 'Send current line to REPL' })
    map('x', '<Plug>(KittyREPLSendVisual)',    ':<C-u>KittyREPLSend<cr>',   { noremap = true, silent = true, desc = 'Send selection to REPL' })
    map('n', '<Plug>(KittyREPLSendCell)',      '<cmd>KittyREPLSendCell<cr>', { desc = 'Send current cell to REPL' })
    map('n', '<Plug>(KittyREPLSendParagraph)', function()
        vim.o.operatorfunc = "v:lua.require'kitty-repl'.send_op"
        return 'g@ip'
    end, { expr = true, desc = 'Send paragraph to REPL' })

    -- Default keymaps (skip if already mapped by user)
    local function nmap(lhs, rhs, desc)
        if vim.fn.mapcheck(lhs, 'n') == '' then
            map('n', lhs, rhs, vim.tbl_extend('force', o, { desc = desc }))
        end
    end
    local function xmap(lhs, rhs, desc)
        if vim.fn.mapcheck(lhs, 'x') == '' then
            -- Use :<C-u> instead of <cmd> so '< '> marks are set before the command runs
            map('x', lhs, rhs, vim.tbl_extend('force', o, { desc = desc }))
        end
    end

    -- Motion-based send: <leader>s{motion}
    if vim.fn.mapcheck('<leader>s', 'n') == '' then
        map('n', '<leader>s',  M.send_operator, vim.tbl_extend('force', ox, { desc = 'Send motion to REPL' }))
    end
    nmap('<leader>ss', '<cmd>KittyREPLSendLine<cr>',              'Send current line to REPL')
    nmap('<leader>sp', '<Plug>(KittyREPLSendParagraph)',          'Send current paragraph to REPL')
    xmap('<leader>s',  ':<C-u>KittyREPLSend<cr>',                'Send selection to REPL')
    nmap('<leader>sc', '<cmd>KittyREPLSendCell<cr>',             'Send current cell to REPL')

    -- Legacy keymaps
    nmap('<leader>;r', '<cmd>KittyREPLRun<cr>',       'REPL: prompt and run')
    xmap('<leader>;s', ':<C-u>KittyREPLSend<cr>',     'REPL: send selection')
    nmap('<leader>;s', '<cmd>KittyREPLSend<cr>',      'REPL: send line')
    xmap('<S-CR>', ':<C-u>KittyREPLSend<cr>', 'REPL: start or send selection')
    nmap('<S-CR>', '<cmd>KittyREPLSend<cr>',  'REPL: start or send line')
    nmap('<leader>;c', '<cmd>KittyREPLClear<cr>',     'REPL: clear')
    nmap('<leader>;k', '<cmd>KittyREPLKill<cr>',      'REPL: kill')
    nmap('<leader>;l', '<cmd>KittyREPLRunAgain<cr>',  'REPL: run again')
    nmap('<leader>;w', '<cmd>KittyREPLStart<cr>',     'REPL: start interpreter')
end

--- Returns true if the REPL is currently open. Useful for statuslines.
function M.is_open()
    return backend ~= nil and backend.is_open()
end


function M.setup(user_config)
    -- Kill any existing REPL before replacing the backend
    if backend and backend.is_open() then
        backend.kill()
    end

    cfg = user_config or {}
    cfg.window_kind = cfg.window_kind or 'attached'

    -- Merge user escape_fns on top of built-ins
    if cfg.escape_fns then
        for ft, fn_override in pairs(cfg.escape_fns) do
            escape_fns[ft] = fn_override
        end
    end

    local function default_backend()
        if os.getenv('TMUX') then return 'tmux' end
        return 'kitty'
    end
    backend_name = cfg.backend or default_backend()
    backend = require('kitty-repl.backends.' .. backend_name)
    backend.init(cfg)

    create_commands()

    if cfg.use_keymaps ~= false then
        define_keymaps()
    end

    -- Register QuitPre cleanup inside setup so backend is always available
    vim.api.nvim_create_autocmd('QuitPre', {
        group = vim.api.nvim_create_augroup('KittyREPL', { clear = true }),
        callback = function()
            if backend and backend.is_open() then backend.kill() end
        end,
    })
end

return M
