-- Run with: nvim --headless -u NONE -l tests/init_spec.lua
-- Uses a fake vim.system so the tests need neither IBus nor gsettings.

vim.opt.rtp:prepend(vim.fn.getcwd())

local calls = {}
local inputmode = 1
local original_system = vim.system

vim.system = function(command)
  calls[#calls + 1] = command
  local stdout = ""
  if command[1] == "gsettings" and command[2] == "get" then
    stdout = tostring(inputmode) .. "\n"
  elseif command[1] == "gsettings" and command[2] == "set" then
    inputmode = tonumber(command[5])
  end
  return { wait = function() return { code = 0, stdout = stdout, stderr = "" } end }
end

local plugin = require("ibus-table-remote")
plugin.setup({ schema = "zhengma", notify = false })

assert(inputmode == 0, "setup in normal mode must enable Direct mode")
assert(#calls == 2, "normal-mode entry must read then write once")

plugin._on_mode_changed("o")
assert(#calls == 2, "operator-pending mode must not issue redundant commands")

plugin._on_mode_changed("i")
assert(inputmode == 1, "entering insert mode must restore the saved mode")
assert(#calls == 3, "restore must issue one write")

plugin.setup({ schema = "wubi", notify = false })
assert(inputmode == 0, "setup in normal mode must activate the new schema")
assert(calls[#calls][3]:find("wubi", 1, true), "new setup must use its new schema")

vim.system = original_system
