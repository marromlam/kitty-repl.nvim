
# kitty-repl.nvim


> DISCLAIMER This plugin was created very recently and it is not
finished. Expect bugs.

![kittyREPLcast_lowres](https://user-images.githubusercontent.com/41004396/130295132-bbffaca8-b9af-4e09-8afe-3e3d7accda03.gif)

kitty-repl is a neovim plugin to eval buffer lines in a
interactive interpreter using the niceities of kitty.


## Features
- [x] Send buffer lines and blocks of lines written in `python`.
- [x] Send buffer lines and blocks of lines written in `C` and `C++`.
- [x] Launch `python` and `cling` interpreters.
- [x] Automatically launch proper JIT interpreter atending to filetype.
- [x] Custom JIT interpreter can be launched. 
- [ ] **HELP WANTED** : Currently python blocks of lines are sent line by line
it would be nice if they are sent in the same ipython cell.

