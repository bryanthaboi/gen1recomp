#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_stitchuif_naming_pc_test")
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return { setFilter = function() end, getDimensions = function() return 8, 8 end } end
_G.love = { graphics = gfx }

local Storage = require("src.core.game3.storage")
local Flags = require("src.core.game3.scripting.flags")
local Dex = require("src.core.game3.dex")
local Runtime = require("src.core.game3.runtime")
local Catching = require("src.core.game3.battle.catching")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local romTextReal = package.loaded["src.core.game3.rom_text"]
local ROM_TEXT = { gText_PkmnsNickname = "'s nickname?", gText_YourName = "YOUR NAME?" }
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key, ctx) return ((ROM_TEXT[key] or key):gsub("{PLAYER}", ctx and ctx.playerName or "")) end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j, ctx) return romTextPlain(romTextKey(n, i, j), ctx) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}
local Naming = require("src.ui.game3.naming")
package.loaded["src.core.game3.rom_text"] = romTextReal

-- pokefirered/include/constants/vars.h:105
local VAR_PC_BOX_TO_SEND_MON = 0x4037
-- pokefirered/include/constants/flags.h:1401
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843

local key = nil
local input = { wasPressed = function(_, k) return key == k end }

local function press(k)
  key = k
  -- src/naming_screen.c:559-572
  Naming.handleInput(input)
  Naming.update(1 / 60)
  key = nil
end

local function mon(species, name)
  return {
    species = species, speciesId = species, name = name or "RATTATA",
    level = 5, hp = 20, maxHp = 20, nickname = "",
  }
end

local function new_session(partyCount)
  local session = { name = "RED", party = {}, store = Flags.newStore(), dex = Dex.new() }
  for _ = 1, partyCount do session.party[#session.party + 1] = mon(19) end
  Storage.ensure(session)
  session.storage.currentBox = 1
  Flags.setVar(session.store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
  Flags.setFlag(session.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
  Runtime.session = session
  return session
end

local function catch_a_magikarp(session)
  local enemy = { species = 129, level = 5, hp = 10, maxHp = 10, mon = mon(129, "MAGIKARP") }
  return Catching.storeCaught(session, enemy, 4)
end

local function open_for(res)
  local done = nil
  Naming.open({
    template = "CAUGHT_MON",
    maxLen = 10,
    species = 129,
    seed = "MAGIKARP",
    title = Naming.monTitle("MAGIKARP"),
    -- pokefirered/src/naming_screen.c:696
    sentToPc = (res and res.location == "pc") or false,
    onDone = function(name) done = name or false end,
  })
  return function() return done end
end

local function typeName(text)
  Naming._state.name = text
end

print("[test] 1. naming a mon the catch sent to the PC prints the transfer line (naming_screen.c:696)")
local s1 = new_session(6)
local res1 = catch_a_magikarp(s1)
eq(res1 and res1.location, "pc", "a full party sends the caught mon to the PC")
local done1 = open_for(res1)
check(Naming.isOpen(), "the naming screen opened")
typeName("SPLASH")
press("start")
press("a")
check(Naming.isOpen(), "OK does not close the screen while the message is up")
eq(done1(), nil, "the caller has not been called back yet")
local st1 = Naming._state
check(st1 ~= nil and st1.pcPages ~= nil, "the sent-to-PC message is on screen")
local pcPages1 = (st1 and st1.pcPages) or {}
local page1 = pcPages1[1] or ""
check(page1:find("SPLASH", 1, true) ~= nil,
  "it uses the nickname the player just typed (" .. page1 .. ")")
check(page1:find("transferred to", 1, true) ~= nil, "and reads as the transfer line")
local joined = table.concat(pcPages1, " | ")
check(joined:find("BOX 1", 1, true) ~= nil, "the destination box is named (" .. joined .. ")")

print("[test] 2. A walks the pages and then closes")
eq(st1 and st1.pcPage, 1, "the message starts on page 1")
local pages = #pcPages1
check(pages >= 2, "the transfer line is a two-page text (" .. pages .. ")")
press("a")
eq(Naming._state and Naming._state.pcPage, 2, "A moved to page 2")
press("a")
check(not Naming.isOpen(), "A on the last page closed the naming screen")
eq(done1(), "SPLASH", "and handed the typed nickname back")

print("[test] 3. a full box selects the box-was-full wording (naming_screen.c:743)")
local s2 = new_session(6)
for slot = 1, Storage.IN_BOX_COUNT do
  s2.storage.boxes[1].mons[slot] = mon(19)
end
local res2 = catch_a_magikarp(s2)
eq(res2 and res2.location, "pc", "the spilled mon still went to the PC")
open_for(res2)
typeName("GYARADOS")
press("start")
press("a")
local st2 = Naming._state
check(st2 ~= nil and st2.pcPages ~= nil, "the message is up")
local joined2 = table.concat((st2 and st2.pcPages) or {}, " | ")
check(joined2:find("was full", 1, true) ~= nil,
  "the box-was-full variant is picked (" .. joined2 .. ")")
check(joined2:find("GYARADOS was transferred to", 1, true) ~= nil,
  "the typed nickname is the one transferred")
check(joined2:find("BOX 2", 1, true) ~= nil,
  "the box named is the one VAR_PC_BOX_TO_SEND_MON already pointed at")
check(Flags.getFlag(s2.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE),
  "and the latch is set so the line is shown once (field_specials.c:1985)")
press("a")
press("a")
check(not Naming.isOpen(), "the screen closed after the message")

print("[test] 4. a catch with five in the party keeps the mon, so no transfer line")
local s3 = new_session(5)
local res3 = catch_a_magikarp(s3)
eq(res3 and res3.location, "party", "the sixth mon joins the party")
eq(#s3.party, 6, "and the party is full at the moment the naming screen opens")
local done3 = open_for(res3)
typeName("SPARKY")
press("start")
press("a")
check(not Naming.isOpen(), "a mon that went to the party gets no PC message")
eq(done3(), "SPARKY", "the nickname came straight back")

print("[test] 5. renaming a boxed mon never prints the transfer line")
local s4 = new_session(6)
catch_a_magikarp(s4)
local done4 = nil
Naming.open({
  template = "NICKNAME",
  maxLen = 10,
  species = 129,
  seed = "MAGIKARP",
  onDone = function(name) done4 = name end,
})
typeName("RENAMED")
press("start")
press("a")
check(not Naming.isOpen(), "the NICKNAME template closes on OK")
eq(done4, "RENAMED", "and returns the new name")

print("[test] 6. with no flag passed the screen reads the catch the ball sequence recorded")
local Anim = require("src.core.game3.battle.anim")
local BattleUi = require("src.core.game3.battle.ui")
Anim._headless = true
BattleUi._headless = true

local function run_ball(session)
  local enemy = { species = 129, level = 5, hp = 10, maxHp = 10, mon = mon(129, "MAGIKARP") }
  local st = { wild = true, enemy = enemy, player = { mon = session.party[1] }, playerName = "RED" }
  CatchSeq.begin(st, 4, true, 4, { session = session, pushMsg = function() end })
  local guard = 0
  while not CatchSeq.update() and guard < 600 do guard = guard + 1 end
  return CatchSeq.catchResult()
end

local s5 = new_session(6)
local ball5 = run_ball(s5)
eq(ball5 and ball5.location, "pc", "the ball sequence stored the mon in the PC")
Naming.open({
  template = "CAUGHT_MON",
  maxLen = 10,
  species = 129,
  seed = "MAGIKARP",
  onDone = function() end,
})
typeName("PCMON")
press("start")
press("a")
check(Naming._state ~= nil and Naming._state.pcPages ~= nil,
  "the transfer line is printed without the caller passing anything")
press("a")
press("a")
check(not Naming.isOpen(), "and the screen closes after it")

local s6 = new_session(5)
local ball6 = run_ball(s6)
eq(ball6 and ball6.location, "party", "the same sequence with room keeps the mon")
local done6 = nil
Naming.open({
  template = "CAUGHT_MON",
  maxLen = 10,
  species = 129,
  seed = "MAGIKARP",
  onDone = function(name) done6 = name end,
})
typeName("PARTYMON")
press("start")
press("a")
check(not Naming.isOpen(), "no transfer line for the mon that joined the party")
eq(done6, "PARTYMON", "and OK handed the nickname straight back")

-- pokefirered/src/naming_screen.c:696, pokefirered/data/battle_scripts_2.s:87
print("[test] 7. the battle itself tells the screen the mon went to the PC")
local Battle = require("src.core.game3.battle")
local BattleUi = require("src.core.game3.battle.ui")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")

local realCatchResult = CatchSeq.catchResult
CatchSeq.catchResult = function() return nil end

local function through_the_battle(session, nick)
  local caught = mon(129, "MAGIKARP")
  Battle.start({
    wild = true,
    playerParty = session.party,
    foe = { species = 129, level = 5, hp = 10, maxHp = 10, mon = caught },
    headless = false,
    session = session,
  })
  local res = Catching.storeCaught(session, { species = 129, level = 5, mon = caught }, 4)
  Battle.startPostCatchFlow(res)
  local aInput = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }
  for _ = 1, 600 do
    if Message.isOpen() then Message.tick() end
    BattleUi.pump()
    Battle.update(1 / 60, { input = aInput })
    if Naming.isOpen() then break end
  end
  if not Naming.isOpen() then return res, nil end
  typeName(nick)
  press("start")
  press("a")
  return res, Naming._state
end

local s7 = new_session(6)
local res7, st7 = through_the_battle(s7, "FLAGGED")
eq(res7 and res7.location, "pc", "a full party sends the battle's catch to the PC")
check(st7 ~= nil and st7.pcPages ~= nil,
  "the transfer line is up with CatchSeq.catchResult() stubbed to nil")
local flagged = table.concat((st7 and st7.pcPages) or {}, " | ")
check(flagged:find("FLAGGED was transferred to", 1, true) ~= nil,
  "and it names the typed nickname (" .. flagged .. ")")
press("a")
press("a")
check(not Naming.isOpen(), "the screen closed after the flagged transfer line")
Battle.abort()

local s8 = new_session(5)
local res8, st8 = through_the_battle(s8, "NOFLAG")
eq(res8 and res8.location, "party", "a catch with room keeps the mon")
check(st8 == nil or st8.pcPages == nil,
  "a party catch prints no transfer line, fallback or not")
if Naming.isOpen() then Naming.close("NOFLAG") end
Battle.abort()

CatchSeq.catchResult = realCatchResult

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
