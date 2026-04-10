-- :checkhealth kitty-repl
local M = {}

local function check_executable(name)
    if vim.fn.executable(name) == 1 then
        vim.health.ok(name .. ' found')
        return true
    else
        vim.health.warn(name .. ' not found in PATH')
        return false
    end
end

function M.check()
    vim.health.start('kitty-repl.nvim')

    -- Neovim version
    if vim.fn.has('nvim-0.10') == 1 then
        vim.health.ok('Neovim >= 0.10')
    else
        vim.health.error('Neovim 0.10+ required (getregionpos API)')
    end

    -- Setup called?
    local ok, repl = pcall(require, 'kitty-repl')
    if not ok then
        vim.health.error('kitty-repl module not found')
        return
    end
    vim.health.ok('kitty-repl module loaded')

    -- Backend check
    local cfg = require('kitty-repl')._cfg and require('kitty-repl')._cfg() or {}
    local backend_name = cfg.backend
        or (os.getenv('TMUX') and 'tmux')
        or 'kitty'
    vim.health.info('Backend: ' .. backend_name)

    if backend_name == 'kitty' then
        vim.health.start('kitty backend')
        check_executable('kitty')
        local listen_on = os.getenv('KITTY_LISTEN_ON')
        local ssh_port  = os.getenv('KITTY_PORT')
        if listen_on then
            vim.health.ok('$KITTY_LISTEN_ON = ' .. listen_on)
        elseif ssh_port then
            vim.health.ok('$KITTY_PORT = ' .. ssh_port .. ' (SSH mode)')
        else
            vim.health.warn('$KITTY_LISTEN_ON not set — add `listen_on unix:/tmp/kitty` and `allow_remote_control yes` to kitty.conf')
        end

    elseif backend_name == 'tmux' then
        vim.health.start('tmux backend')
        check_executable('tmux')
        local tmux_env = os.getenv('TMUX')
        if tmux_env then
            vim.health.ok('Running inside tmux ($TMUX is set)')
        else
            vim.health.warn('$TMUX not set — not inside a tmux session')
        end

    elseif backend_name == 'neovim' then
        vim.health.start('neovim terminal backend')
        vim.health.ok('No external dependencies required')

    elseif backend_name == 'wezterm' then
        vim.health.start('wezterm backend')
        check_executable('wezterm')
        local wezterm_pane = os.getenv('WEZTERM_PANE')
        if wezterm_pane then
            vim.health.ok('$WEZTERM_PANE = ' .. wezterm_pane)
        else
            vim.health.warn('$WEZTERM_PANE not set — pane ID may need to be configured manually')
        end

    else
        vim.health.warn('Unknown backend: ' .. backend_name)
    end
end

return M
