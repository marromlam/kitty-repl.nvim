# kitty-repl.nvim

Send code from Neovim to an interactive REPL — inspired by [vim-slime](https://github.com/jpalardy/vim-slime).

Supports multiple terminal backends: **kitty**, **tmux**, **Neovim terminal**, and **WezTerm**.

---

## Requirements

- Neovim 0.10+
- One of the supported backends (kitty, tmux, wezterm, or just Neovim itself)

---

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'your-username/kitty-repl.nvim',
  config = function()
    require('kitty-repl').setup()
  end,
}
```

---

## Quick Start

### kitty (default)

Requires kitty to be running with remote control enabled. Add to `kitty.conf`:

```
allow_remote_control yes
listen_on unix:/tmp/kitty
```

```lua
require('kitty-repl').setup()
-- or explicitly:
require('kitty-repl').setup({ backend = 'kitty' })
```

### tmux

```lua
require('kitty-repl').setup({ backend = 'tmux' })
```

### Neovim terminal (no external terminal needed)

```lua
require('kitty-repl').setup({ backend = 'neovim' })
```

### WezTerm

```lua
require('kitty-repl').setup({ backend = 'wezterm' })
```

---

## Default Keymaps

| Keys | Mode | Action |
|------|------|--------|
| `<leader>s{motion}` | Normal | Send via motion (e.g. `<leader>sip`, `<leader>s3j`) |
| `<leader>ss` | Normal | Send current line |
| `<leader>sp` | Normal | Send current paragraph |
| `<leader>s` | Visual | Send selection |
| `<leader>sc` | Normal | Send current cell (`# %%` block) |
| `<leader>;w` | Normal | Start REPL (auto-detect interpreter) |
| `<leader>;k` | Normal | Kill REPL |
| `<leader>;c` | Normal | Clear REPL |
| `<leader>;l` | Normal | Run last command again |
| `<leader>;r` | Normal | Prompt and run |
| `<leader>;s` | Normal/Visual | Send (legacy) |
| `<S-CR>` | Normal/Visual | Send (legacy) |

Disable all default keymaps:

```lua
require('kitty-repl').setup({ use_keymaps = false })
```

### `<Plug>` mappings (for custom remapping)

```lua
vim.keymap.set('n', '<leader>x',  '<Plug>(KittyREPLSend)',       { desc = 'Send motion' })
vim.keymap.set('n', '<leader>xx', '<Plug>(KittyREPLSendLine)',   { desc = 'Send line' })
vim.keymap.set('x', '<leader>x',  '<Plug>(KittyREPLSendVisual)', { desc = 'Send selection' })
vim.keymap.set('n', '<leader>xc', '<Plug>(KittyREPLSendCell)',      { desc = 'Send cell' })
vim.keymap.set('n', '<leader>xp', '<Plug>(KittyREPLSendParagraph)', { desc = 'Send paragraph' })
```

---

## Commands

| Command | Description |
|---------|-------------|
| `:KittyREPLStart` | Open REPL and start interpreter (auto-detected) |
| `:KittyREPLKill` | Close the REPL |
| `:KittyREPLClear` | Clear the REPL prompt |
| `:KittyREPLSend` | Send visual selection or current line |
| `:KittyREPLSendLine [N]` | Send N lines from cursor (default: 1) |
| `:KittyREPLSendCell` | Send current `# %%` cell |
| `:KittyREPLRunAgain` | Re-send the last command |
| `:KittyREPLRun` | Prompt for a command and run it |
| `:KittyREPLSend1 {text}` | Send `{text}` with Enter |
| `:KittyREPLSend0 {text}` | Send `{text}` as-is (no Enter) |

---

## Cells

Cells let you split a file into executable blocks, like Jupyter notebooks.

Mark cell boundaries with `# %%` (Python/R) or `-- %%` (Lua):

```python
# %%
import numpy as np
x = np.arange(10)

# %%
print(x ** 2)
```

Place your cursor anywhere in a cell and press `<leader>sc` to send it.

Configure the delimiter:

```lua
require('kitty-repl').setup({
  cell_delimiter = '# ---',  -- custom marker
})
```

---

## Configuration

```lua
require('kitty-repl').setup({
  -- Backend: 'kitty' | 'tmux' | 'neovim' | 'wezterm'
  backend = 'kitty',

  -- How to open the REPL window:
  --   kitty:   'attached' (inside current kitty) | 'native' (standalone window)
  --   tmux:    'split' (pane to the right, default) | 'window' (new tmux window) | 'attach' (pick existing pane)
  --   neovim:  'split' (vertical split right, default) | 'split_below' (horizontal split) | 'window' (new tab)
  --   wezterm: unused (attaches to existing pane)
  window_kind = 'attached',

  -- Wrap sends in bracketed paste codes (\27[200~ ... \27[201~).
  -- Prevents REPLs from misinterpreting indentation or special characters.
  bracketed_paste = false,

  -- Restore cursor position after a motion-based send (e.g. <leader>sip).
  preserve_curpos = true,

  -- Cell delimiter marker (overrides per-filetype defaults).
  cell_delimiter = '# %%',

  -- Delay in seconds between lines when using :KittyREPLRunRepl (# ! lines).
  repl_run_delay = 2,

  -- Delay in ms to wait after opening the pane before sending the first command.
  -- Prevents text from landing in the shell before it's ready.
  open_delay = 500,

  -- Disable default keymaps.
  use_keymaps = true,

  -- Python-specific options:
  --   python_ipython: use %cpaste for multi-line sends (requires IPython). Default: true.
  --   dispatch_ipython_pause: ms to wait after %cpaste before sending code. Default: 100.
  python_ipython = true,
  dispatch_ipython_pause = 100,

  -- Custom language escape functions (override or extend built-ins).
  -- Receives raw text (string), must return escaped string.
  escape_fns = {
    julia = function(text)
      return text:gsub('\n', '\r') .. '\r'
    end,
  },
})
```

### Per-buffer config override

Override any config option for a specific buffer:

```lua
vim.b.kitty_repl_config = { bracketed_paste = true }
```

---

## Language Support

kitty-repl.nvim includes built-in handling for:

| Language | Behaviour |
|----------|-----------|
| **Python** | Single lines sent directly. Multi-line blocks wrapped in `%cpaste -q` / `--` (IPython protocol). Internal blank lines preserved. |
| **Everything else** | Lines joined with `\r`, terminated with `\r`. |

### Adding a custom language

```lua
require('kitty-repl').setup({
  escape_fns = {
    julia = function(text)
      local lines = vim.split(text, '\n', { plain = true })
      while #lines > 0 and lines[#lines]:match('^%s*$') do
        table.remove(lines)
      end
      return table.concat(lines, '\r') .. '\r'
    end,
  },
})
```

---

## Backend Details

### kitty

Communicates via `kitty @` remote control. Requires:

```
# kitty.conf
allow_remote_control yes
listen_on unix:/tmp/kitty
```

Works over SSH if `$KITTY_PORT` is set. To manually target a specific kitty window:

```lua
require('kitty-repl').repl_select(42)  -- target window ID 42
```

Or pre-configure it:

```lua
require('kitty-repl').setup({ backend = 'kitty', window_id = 42 })
```

### tmux

Opens a new pane in the current tmux session. No extra configuration needed.

```lua
require('kitty-repl').setup({
  backend     = 'tmux',
  window_kind = 'split',   -- 'split' (pane right, default) | 'window' (new tmux window) | 'attach' (pick existing pane)
})
```

### Neovim terminal

Opens a `:terminal` buffer inside Neovim itself. Tracks terminal buffers automatically — the most recently opened terminal receives sends.

```lua
require('kitty-repl').setup({
  backend     = 'neovim',
  window_kind = 'split',   -- 'split' (default) or 'window' (new tab)
})
```

### WezTerm

Targets an existing WezTerm pane. Either provide the pane ID or a direction:

```lua
require('kitty-repl').setup({
  backend                = 'wezterm',
  wezterm_pane_id        = 3,       -- target this specific pane
  -- or:
  wezterm_pane_direction = 'Right', -- resolve pane to the Right of the current one
})
```

If neither is set, you will be prompted for the pane ID on first use.

---

## `# !` Script Mode

Lines prefixed with `# !` in a buffer are treated as REPL commands. Run them all in sequence with `:KittyREPLRunRepl`:

```python
# ! import numpy as np
# ! x = np.linspace(0, 10, 100)
# ! import matplotlib.pyplot as plt
# ! plt.plot(x, np.sin(x))
# ! plt.show()
```

Configure the delay between commands (default: 2 seconds):

```lua
require('kitty-repl').setup({ repl_run_delay = 1 })
```
