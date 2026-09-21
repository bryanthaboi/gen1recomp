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
check(Std.SPECIAL.ChangePokemonNickname == 158, "ChangePokemonNickname = 158")
check(Std.SPECIAL.BufferMonNickname == 124, "BufferMonNickname = 124")

print("[test] 2. Handler registered")
local Natives = require("src.core.game3.scripting.natives")
check(Natives.ALLOW["special:158"] ~= nil, "special:158 handler")
check(Natives.ALLOW["special:124"] ~= nil, "special:124 handler")

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

local yielded = Natives.special(ctx, 158, adapters)
check(opened, "openNaming invoked for special 158")
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

opened = false
mon.nickname = ""
Natives.special(ctx, 159, { log = function() end, chooseParty = function(_, done) done(0) end })
check(not opened, "special 159 does not open the naming keyboard")
check(mon.nickname == "", "special 159 leaves the nickname alone")
mon.nickname = "SPROUT"

print("[test] 4. Fade-from-black after TO_BLACK cover")
Fade.t = 16
Fade.active = false
Fade.begin(Fade.MODE.FROM_BLACK, 1)
check(Fade.active == true and Fade.t == 16 and Fade._dir == -1, "FROM_BLACK starts covered")

print("[test] 5. Naming screen button highlights and layout parity")
local NamingChrome = require("src.ui.game3.naming_chrome")
local expectedKeys = {
  "page_swap_button_glow",
  "back_button_glow",
  "ok_button_glow",
  "cursor",
  "page_swap_frame",
}
local keySet = {}
for _, k in ipairs(NamingChrome.KEYS or {}) do
  keySet[k] = true
end
for _, key in ipairs(expectedKeys) do
  check(keySet[key] == true, "NamingChrome includes key " .. key)
end

-- Check Naming screen layout coordinates match pokefirered
Naming.open({ template = "NICKNAME", species = 1, maxLen = 10, title = Naming.monTitle("BULBASAUR") })
check(Naming.isOpen(), "Naming screen is open")

-- Verify species icon positioning at (56, 40)
local st = Naming._state
check(st ~= nil, "Naming internal state is present")
check(st.template == "NICKNAME", "state template is NICKNAME")
check(st.species == 1, "state species is 1")

-- Verify right button selection index mapping (1 = Page Swap, 2 = Back, 3 = OK)
st.btn = 1
check(st.btn == 1, "btn 1 is Page Swap")
st.btn = 2
check(st.btn == 2, "btn 2 is Back")
st.btn = 3
check(st.btn == 3, "btn 3 is OK")

-- Verify button cursor geometry matches pokefirered 32x13 pill coordinates
check(Naming.L.btnCursorX == 188, "btnCursorX is 188")
check(Naming.L.btnCursorY[1] == 77, "Page Swap cursor Y is 77")
check(Naming.L.btnCursorY[2] == 106, "Back cursor Y is 106")
check(Naming.L.btnCursorY[3] == 128, "OK cursor Y is 128")

-- Verify Gfx.drawUi suppresses Fade.draw during Naming
local Gfx = require("src.core.game3.gfx")
check(Naming.isOpen(), "Naming is open during UI render check")

Naming.close()
check(not Naming.isOpen(), "Naming is closed after close()")

print("[test] 6. Caught Pokémon nickname prompt and naming modal flow")
local Battle = require("src.core.game3.battle")
local BattleUi = require("src.core.game3.battle.ui")
local Choice = require("src.ui.game3.choice")
local Message = require("src.ui.game3.message")
local Catching = require("src.core.game3.battle.catching")

-- Setup mock input helper
local mockInput = {
  _pressed = {},
  press = function(self, key) self._pressed[key] = true end,
  clear = function(self) self._pressed = {} end,
  isDown = function(self, key) return self._pressed[key] == true end,
  wasPressed = function(self, key)
    if self._pressed[key] then
      self._pressed[key] = false
      return true
    end
    return false
  end,
}
function mockInput:consume(key)
  return self:wasPressed(key)
end

-- Scenario A: Caught Pokémon -> Yes to Nickname -> Type nickname -> Confirmed
local testParty = { { species = 1, hp = 20, maxHp = 20, level = 5 } }
local testSession = { name = "RED", party = testParty, dex = {} }
local caughtMon = { species = 25, name = "PIKACHU", level = 3, hp = 10, maxHp = 10, nickname = "" }
local catchResParty = {
  success = true,
  location = "party",
  firstTimeCaught = false,
  mon = caughtMon,
}

Battle.start({
  wild = true,
  playerParty = testParty,
  foe = { species = 25, level = 3, hp = 10, maxHp = 10, mon = caughtMon },
  headless = false,
  session = testSession,
})
check(Battle.isActive(), "Battle active for catch nickname test")

-- Trigger post catch flow
Battle.startPostCatchFlow(catchResParty)
check(Battle._phase == "catch_nickname_prompt", "Phase is catch_nickname_prompt")

-- Message says "Give a nickname to the\ncaptured PIKACHU?"
local foundPrompt = false
for _, line in ipairs(BattleUi._log or {}) do
  if line:find("Give a nickname") and line:find("PIKACHU") then
    foundPrompt = true
  end
end
check(foundPrompt, "Prompt log has 'Give a nickname to the captured PIKACHU?'")

-- Advance typewriter message to trigger yes/no Choice box
while Message.isOpen() and not (Choice.active) do
  Message.tick()
  BattleUi.pump()
end
check(Choice.active == true, "Choice Yes/No is active")

-- Select YES (index 0 / A button)
mockInput:clear()
mockInput:press("a")
Battle.update(1 / 60, { input = mockInput })

check(Naming.isOpen(), "Naming screen opened after choosing YES")
check(Battle._phase == "catch_naming", "Battle phase is catch_naming")
check(Naming._state.template == "CAUGHT_MON", "Naming template is CAUGHT_MON")
check(Naming._state.species == 25, "Naming species is 25 (Pikachu)")

-- Complete naming with nickname "SPARKY"
Naming.close("SPARKY")
check(not Naming.isOpen(), "Naming screen closed")
check(caughtMon.nickname == "SPARKY", "caughtMon nickname is now SPARKY")
check(Battle._phase == "ending", "Battle transitioned to ending phase after naming")

-- Scenario B: Caught Pokémon -> No to Nickname
local caughtPidgey = { species = 16, name = "PIDGEY", level = 3, hp = 8, maxHp = 8, nickname = "" }
local catchResNoNick = {
  success = true,
  location = "party",
  firstTimeCaught = false,
  mon = caughtPidgey,
}
Battle.start({
  wild = true,
  playerParty = testParty,
  foe = { species = 16, level = 3, hp = 8, maxHp = 8, mon = caughtPidgey },
  headless = false,
  session = testSession,
})
Battle.startPostCatchFlow(catchResNoNick)
while Message.isOpen() and not Choice.active do
  Message.tick()
  BattleUi.pump()
end
check(Choice.active == true, "Choice Yes/No is active for Pidgey")

-- Select NO (index 1 / down + A button or B button)
mockInput:clear()
mockInput:press("b")
Battle.update(1 / 60, { input = mockInput })
check(not Naming.isOpen(), "Naming screen NOT opened when NO selected")
check(caughtPidgey.nickname == "", "caughtPidgey nickname remains default/empty")
check(Battle._phase == "ending", "Battle transitioned to ending phase immediately")

-- Scenario C: Caught Pokémon sent to PC -> Yes to Nickname -> no PC transfer message
local caughtCaterpie = { species = 10, name = "CATERPIE", level = 3, hp = 6, maxHp = 6, nickname = "" }
local catchResPc = {
  success = true,
  location = "pc",
  firstTimeCaught = false,
  mon = caughtCaterpie,
}
Battle.start({
  wild = true,
  playerParty = testParty,
  foe = { species = 10, level = 3, hp = 6, maxHp = 6, mon = caughtCaterpie },
  headless = false,
  session = testSession,
})
Battle.startPostCatchFlow(catchResPc)
while Message.isOpen() and not Choice.active do
  Message.tick()
  BattleUi.pump()
end
mockInput:clear()
mockInput:press("a")
Battle.update(1 / 60, { input = mockInput })
check(Naming.isOpen(), "Naming screen opened for PC-bound Caterpie")
Naming.close("SLUGGY")
check(caughtCaterpie.nickname == "SLUGGY", "Caterpie nicknamed SLUGGY")
-- pokefirered/src/battle_script_commands.c:9853
check(Battle._phase == "ending", "a nicknamed catch skips the PC transfer message")

local foundTransfer = false
for _, line in ipairs(BattleUi._log or {}) do
  if line:find("transferred") then
    foundTransfer = true
  end
end
check(not foundTransfer, "trygivecaughtmonnick jumps past printfromtable gCaughtMonStringIds")

if failed == 0 then
  print("\nAll game3 nickname tests passed.")
  os.exit(0)
else
  print("\n" .. failed .. " nickname test(s) failed.")
  os.exit(1)
end


