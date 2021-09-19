
# kitty-repl.nvim

kitty-repl is a neovim plugin to evaluate buffer lines in a
interactive interpreter using the niceties of kitty.

![kittyREPLcast_lowres](https://user-images.githubusercontent.com/41004396/130295132-bbffaca8-b9af-4e09-8afe-3e3d7accda03.gif)

> DISCLAIMER This plugin was created very recently and it is not
finished


## Goal
The idea is to create a REPL where the user can run any bunch of lines in a nvim buffer
and send them to a kitty window where a JIT console evaluates them.
Since I mostly write python and `C/C++` code, these languages are 
the very first to have support.
In the future it would be very interesting to add more languages.


## Installation

You can use your favourite plugin manager. For example, with packer:

```lua
packer.use {
    "marromlam/kitty-repl.nvim",
    disable = false,
    event = "BufEnter",
    config = function()
      require('kitty-repl').setup()
      nvim_set_keymap('n', '<leader>;r', ':KittyREPLRun<cr>', {})
      nvim_set_keymap('x', '<leader>;s', ':KittyREPLSend<cr>', {})
      nvim_set_keymap('n', '<leader>;s', ':KittyREPLSend<cr>', {})
      nvim_set_keymap('n', '<leader>;c', ':KittyREPLClear<cr>', {})
      nvim_set_keymap('n', '<leader>;k', ':KittyREPLKill<cr>', {})
      nvim_set_keymap('n', '<leader>;l', ':KittyREPLRunAgain<cr>', {})
      nvim_set_keymap('n', '<leader>;w', ':KittyREPLStart<cr>', {})
    end
}
```


## Currently implemented features
- [x] Send buffer lines writen in `python` and `C/C++`.
- [x] Launch `ipython` and `cling` interpreters automatically on file extension.


## Contributing
I really would appreciate help with this plugin since I use only two programming languages.
This module could really benefit from the help and suggestions of other users.

