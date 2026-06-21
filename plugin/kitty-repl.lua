-- Plugin entry point for kitty-repl.nvim
-- Prevents double-loading and ensures the module is available on startup.
if vim.g.loaded_kitty_repl then
	return
end
vim.g.loaded_kitty_repl = true

-- Commands and keymaps are registered in setup(). This file only ensures the
-- module is reachable. Users must call require('kitty-repl').setup() in their
-- config to activate the plugin.
