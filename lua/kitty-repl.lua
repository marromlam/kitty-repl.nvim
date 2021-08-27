local fn = vim.fn
local cmd = vim.cmd
local loop = vim.loop
local nvim_set_keymap = vim.api.nvim_set_keymap


local M = {}


-- local variable with the command that is going to be executed
local the_command

-- this function is only to print lua dicts
-- I use it for debugging purposes
function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
 end




-- open runner
local function open_new_repl()
  loop.spawn('kitty', {
    args = {'@',
      'launch',                   -- launches a vertical split
      '--title=' .. CMDfg.repl_id -- we need a random title
  }})
  CMDfg.runner_open = true
end


local function cook_command_python(region)
  local lines
  local command
  local last_line
  if region[1] == 0 then
    -- we only have selected one line here
    lines = vim.api.nvim_buf_get_lines(0, vim.api.nvim_win_get_cursor(0)[1]-1, vim.api.nvim_win_get_cursor(0)[1], true)
    command = table.concat(lines, '\n') .. '\n'
  else
    -- we have several lines selected here
    lines = vim.api.nvim_buf_get_lines(0, region[1]-1, region[2], true)
    last_line = lines[#lines - 0] -- lets get last_line and see if is indented or not
    -- print(dump(lines))
    -- print(last_line)
    if last_line:find("  ", 1, true) == 1 then
      -- this is an indented line, hence we add another CR in order to just run the line
      command = table.concat(lines, '\r') .. '\r\r'
    else
      command = table.concat(lines, '\n') .. '\r'
    end
  end
  return command
end


local function cook_command_cpp(region)
  local lines
  local command
  local last_line
  if region[1] == 0 then
    -- we only have selected one line here
    lines = vim.api.nvim_buf_get_lines(0, vim.api.nvim_win_get_cursor(0)[1]-1, vim.api.nvim_win_get_cursor(0)[1], true)
    command = table.concat(lines, '\n \n') .. '\n \r'
  else
    -- we have several lines selected here
    lines = vim.api.nvim_buf_get_lines(0, region[1]-1, region[2], true)
    command = table.concat(lines, '\n') .. '\n \r'
  end
  return command
end


local function cook_command(region)
  local command
  if vim.bo.filetype == "py" then
    command = cook_command_python(region)
  else
    command = cook_command_cpp(region)
  end
  return command
end




local function repl_send(cmd_args, command)
  local args = {'@'}
  for _, v in pairs(cmd_args) do
    table.insert(args, v)
  end
  table.insert(args, command)
  loop.spawn('kitty', { args = args })
end




function M.repl_run(region)
  the_command = cook_command(region)
  vim.cmd([[delm <>]]) -- delete visual selection marks
  if CMDfg.runner_open == true then
    repl_send(CMDfg.run_cmd, the_command)
  else
    open_new_repl()
  end
end


function M.repl_start(jit_runner)
  if CMDfg.runner_open == true then
    if jit_runner == "auto" then
      if vim.bo.filetype == "py" then
        repl_send(CMDfg.run_cmd, "MPLBACKEND='module://kitty' ipython" .. "\r")
      else
        repl_send(CMDfg.run_cmd, "cling" .. "\r")
      end
    else
      repl_send(CMDfg.run_cmd, jit_runner .. "\r")
    end
  else
    open_new_repl()
  end
end


function M.repl_run_again()
  if the_command then
    if CMDfg.runner_open == true then
      repl_send(CMDfg.run_cmd, the_command)
    else
      open_new_repl()
    end
  end
end


function M.repl_send_and_run(arg_command)
  if CMDfg.runner_open == true then
    repl_send(CMDfg.run_cmd, arg_command .. "\r")
  else
    open_new_repl()
  end
end


function M.repl_prompt_and_run()
  fn.inputsave()
  local command = fn.input("! ")
  fn.inputrestore()
  the_command = command .. '\r'
  if CMDfg.runner_open == true then
    repl_send(CMDfg.run_cmd, the_command)
  else
    open_new_repl()
  end
end


function M.repl_killer()
  if CMDfg.runner_open == true then
    repl_send(CMDfg.kill_cmd, nil)
  end
  CMDfg.runner_open = false
end


function M.repl_cleanup()
  if CMDfg.runner_open == true then
    repl_send(CMDfg.run_cmd, '')
  end
end


local function create_commands()
  cmd[[command! KittyREPLRunAgain lua require('kitty-repl').repl_run_again()]]
  cmd[[command! -range KittyREPLSend lua require('kitty-repl').repl_run(vim.region(0, vim.fn.getpos("'<"), vim.fn.getpos("'>"), "l", false)[0])]]
  cmd[[command! KittyREPLRun lua require('kitty-repl').repl_prompt_and_run()]]
  cmd[[command! KittyREPLClear lua require('kitty-repl').repl_cleanup()]]
  cmd[[command! KittyREPLKill lua require('kitty-repl').repl_killer()]]
  cmd[[command! KittyREPLStart lua require('kitty-repl').repl_start("auto")]]
end


local function define_keymaps()
  nvim_set_keymap('n', '<leader>tr', ':KittyREPLRun<cr>', {})
  nvim_set_keymap('x', '<leader>ts', ':KittyREPLSend<cr>', {})
  nvim_set_keymap('n', '<leader>ts', ':KittyREPLSend<cr>', {})
  nvim_set_keymap('n', '<leader>tc', ':KittyREPLClear<cr>', {})
  nvim_set_keymap('n', '<leader>tk', ':KittyREPLKill<cr>', {})
  nvim_set_keymap('n', '<leader>tl', ':KittyREPLRunAgain<cr>', {})
  -- trigger these automatically on extension
  nvim_set_keymap('n', '<leader>tw', ':KittyREPLStart<cr>', {})
end


function M.setup(cfg_)
  CMDfg = cfg_ or {}

  -- TODO: All concerning repl_id could be replaced wiht the window ID
  --       in Kitty. This could be useful if we want to reuse an existing
  --       window as repl.
  local uuid_handle = io.popen[[uuidgen|sed 's/.*/&/']]
  local uuid = uuid_handle:read("*a")
  uuid_handle:close()

  -- set run and kill commands to runner_id
  CMDfg.repl_id = 'runner ' .. uuid
  CMDfg.run_cmd = CMDfg.run_cmd or {'send-text',
                                    '--match=title:' .. CMDfg.repl_id}
  CMDfg.kill_cmd = CMDfg.kill_cmd or {'close-window',
                                      '--match=title:' .. CMDfg.repl_id}

  -- define keymaps
  create_commands()

  -- toggle keymaps
  if CMDfg.use_keymaps ~= nil then
    CMDfg.use_keymaps = CMDfg.use_keymaps
  else
    define_keymaps()
  end

  -- we do not have any runner yet
  CMDfg.runner_open = false

end


return M
