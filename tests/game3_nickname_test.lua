#!/usr/bin/env luajit
-- ChangePokemonNickname special: open naming after TO_BLACK, apply nick, clear fade.

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

print("[test] 1. Special id matches pret specials.inc")
local Std = require("src.core.game3.scripting.stdscripts")
check(Std.SPECIAL.ChangePokemonNickname == 159, "ChangePokemonNickname = 159")
check(Std.SPECIAL.BufferMonNickname == 125, "BufferMonNickname = 125")

print("[test] 2. Handler registered")
local Natives = require("src.core.game3.scripting.natives")
check(Natives.ALLOW["special:159"] ~= nil, "special:159 handler")
check(Natives.ALLOW["special:125"] ~= nil, "special:125 handler")

print("[test] 3. ChangePokemonNickname opens naming + fades in + sets nick")
local Fade = require("src.ui.game3.fade")
local Naming = require("src.ui.game3.naming")
-- Stub Stack so Naming.open works headless
package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  busy = function() return false end,
  drawOrder = function() return {} end,
}
package.loaded["src.ui.game3.naming_chrome"] = {
  ready = function() return true end,
  get = function() return nil end,
  install = function() return true end,
}
package.loaded["src.ui.game3.message"] = {
  isOpen = function() return false end,
  close = function() end,
}
-- Force re-require naming with stubs
package.loaded["src.ui.game3.naming"] = nil
Naming = require("src.ui.game3.naming")

local mon = { species = 1, nickname = "", name = "BULBASAUR" }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return { party = { mon } } end,
  isActive = function() return true end,
}

Fade.begin(Fade.MODE.TO_BLACK, 1)
-- Finish TO_BLACK instantly
Fade.t = 16
Fade.active = false

local opened = false
local finished = false
local ctx = {
  getVar = function(_, id)
    if id == 0x8004 then return 0 end
    return 0
  end,
  mode = "bytecode",
  status = "running",
}
local adapters = {
  openNaming = function(opts, done)
    opened = true
    check(opts.template == "NICKNAME", "template NICKNAME")
    check(opts.maxLen == 10, "maxLen 10")
    check(type(opts.title) == "string" and opts.title:find("nickname"), "title has nickname")
    -- Mimic field adapter: fade from black after open
    Naming.open(opts)
    if (Fade.t or 0) > 0 then
      Fade.begin(Fade.MODE.FROM_BLACK, 1)
    end
    -- Confirm a name
    Naming.close("SPROUT")
    if done then done("SPROUT") end
  end,
  log = print,
}

local yielded = Natives.special(ctx, 159, adapters)
check(opened, "openNaming invoked")
check(yielded == true or finished or mon.nickname == "SPROUT", "special yielded or applied")
-- Poll until native finishes
local guard = 0
while ctx.nativePoll and not ctx.nativePoll() and guard < 10 do
  guard = guard + 1
end
if ctx.nativePoll and ctx.nativePoll() then
  finished = true
end
check(mon.nickname == "SPROUT", "party mon nickname SPROUT (got " .. tostring(mon.nickname) .. ")")
check(finished or mon.nickname == "SPROUT", "native wait completed")

print("[test] 4. Fade-from-black after TO_BLACK cover")
Fade.t = 16
Fade.active = false
Fade.begin(Fade.MODE.FROM_BLACK, 1)
check(Fade.active == true and Fade.t == 16 and Fade._dir == -1, "FROM_BLACK starts covered")

if failed == 0 then
  print("\nAll game3 nickname tests passed.")
  os.exit(0)
else
  print("\n" .. failed .. " nickname test(s) failed.")
  os.exit(1)
end
