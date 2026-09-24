#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").stubSpeciesNames()
require("tests.fixture_data.game3_items").install()
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

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

local TRADE_CENTER = "FR_TRADE_CENTER"

local function mon(species, level, personality, extra)
  local m = {
    species = species, level = level, hp = 30, maxHp = 30,
    moves = { 33 }, pp = { 35 }, maxPp = { 35 },
    personality = personality or (species * 7), nickname = "",
    friendship = 120, otName = "RED", otId = 0x1234,
  }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = TRADE_CENTER, x = 5, y = 8,
  name = "RED", gender = 0, trainerId = 0x1234,
  party = { mon(1, 10), mon(4, 12) },
  bag = { pockets = { items = {} } },
}
local game = { data = { maps = {} }, session = session }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
  _mod = nil,
}
package.loaded["src.core.game3.player"] = { cellX = 5, cellY = 8, facing = "up" }
package.loaded["src.core.game3.map"] = { load = function() end, current = TRADE_CENTER }

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store, mapId = TRADE_CENTER, vm = { ctx = ctx, adapters = adapters },
}

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Std = require("src.core.game3.scripting.stdscripts")
local Link = require("src.core.game3.link")
local LT = require("src.core.game3.link.trade")
local Union = require("src.core.game3.link.union_room")
local Status = require("src.core.game3.link.status")
local Trade = require("src.core.game3.scripting.natives_trade")
local Flags = require("src.core.game3.scripting.flags")

print("[test] 1. the trade specials answer to their pret index")
local EXPECTED = {
  TryTradeLinkup = 0x1D,
  EnterTradeSeat = 0x21,
  StartWiredCableClubTrade = 0x22,
  ShowWirelessCommunicationScreen = 0x16E,
}
for name, id in pairs(EXPECTED) do
  eq(NativesLink.SPECIAL[name], id, "NativesLink.SPECIAL." .. name)
  check(Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound in Natives.ALLOW")
  eq(Std.SPECIAL_NAME_BY_ID[id], name,
    string.format("special 0x%X answers to its pret name", id))
end
-- pokefirered/include/link.h:73
eq(LT.LINKCMD.READY_TO_TRADE, 0xAABB, "LINKCMD_READY_TO_TRADE")
eq(LT.LINKCMD.INIT_BLOCK, 0xBBBB, "LINKCMD_INIT_BLOCK")
eq(LT.LINKCMD.START_TRADE, 0xCCDD, "LINKCMD_START_TRADE")
eq(LT.LINKCMD.CONFIRM_FINISH_TRADE, 0xDCBA, "LINKCMD_CONFIRM_FINISH_TRADE")
eq(LT.LINKCMD.SET_MONS_TO_TRADE, 0xDDDD, "LINKCMD_SET_MONS_TO_TRADE")
-- pokefirered/src/cable_club.c:527
eq(LT.LINKUP.linkType, 0x1133, "TryTradeLinkup asks for LINKTYPE_TRADE_SETUP")
eq(LT.LINKUP.min, 2, "and for exactly two players")
eq(LT.MSG.CONFIRM, "game3_trade_confirm", "the barrier confirm is game3_trade_confirm")
eq(LT.MSG.COMMIT, "trade_commit", "the relay answers trade_commit")
eq(LT.MSG.ABORT, "trade_abort", "or trade_abort")

print("[test] 2. the wireless communication status screen counts")
Link.reset()
LT.reset()
Union.reset()
local G = Status.GROUPTYPE
local counts = Status.counts({
  { activity = Union.ACTIVITY.TRADE },
  { activity = Union.ACTIVITY.BATTLE_SINGLE },
  { activity = Union.ACTIVITY.BATTLE_MULTI },
  { activity = Union.ACTIVITY.NONE + Union.IN_UNION_ROOM },
})
eq(counts[G.TRADE], 2, "a trading group is two people")
eq(counts[G.BATTLE], 6, "a single and a multi battle are six")
eq(counts[G.UNION], 1, "one player idling in the UNION ROOM")
eq(counts[G.TOTAL], 9, "and the total is trade plus battle plus union")
-- pokefirered/src/wireless_communication_status_screen.c:505
local wonder = Status.counts({ { activity = Union.ACTIVITY.WONDER_CARD } })
eq(wonder[G.TOTAL], 0,
  "the retail total leaves WONDER CARD players out, as the cart does")
local chat = Status.counts({
  { activity = Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM, members = 3 },
})
eq(chat[G.UNION], 3, "a chat group counts its own members")
local rows = Status.rows()
eq(#rows, 4, "the screen has four rows")
eq(rows[1].label, "sHeaderTexts[1]", "the first is the trading count (sHeaderTexts[GROUPTYPE_TRADE + 1])")
eq(rows[4].total, true, "and the last is the total")

print("[test] 3. the adapter answer and the screen the monitor opens")
Flags.setVar(store, ctx, Link.VAR_RESULT, 9)
local yieldW, value = Natives.special(ctx, NativesLink.SPECIAL.IsWirelessAdapterConnected, adapters)
eq(yieldW, false, "IsWirelessAdapterConnected does not yield")
eq(value, 0, "offline it answers FALSE, and the monitor says so")
local LinkMenu = require("src.ui.game3.link_menu")
eq(LinkMenu.isOpen(), false, "the status screen starts closed")
local closed = false
LinkMenu.show({ onClose = function() closed = true end })
eq(LinkMenu.isOpen(), true, "ShowWirelessCommunicationScreen puts it up")
eq(#LinkMenu.rows, 4, "with the four group counts on it")
LinkMenu.update(1 / 60)
eq(LinkMenu.palIdx, 0, "the wave palette does not move on the first frame")
for _ = 1, 6 do LinkMenu.update(1 / 60) end
eq(LinkMenu.palIdx, 1, "and steps once every six frames, as CyclePalette does")
eq(LinkMenu.countText(3), " 3", "counts are right aligned to two places")
LinkMenu.close()
eq(closed, true, "closing it hands the script back")

print("[test] 4. grid, HP-bar and level tile tables")
local Menu = require("src.ui.game3.link_trade_menu")
local full = {}
for i = 0, 12 do full[i] = true end
-- pokefirered/src/trade.c:349
eq(Menu.newCursorPosition(0, 4, full), 1, "0 RIGHT -> 1")
eq(Menu.newCursorPosition(1, 4, full), 6, "1 RIGHT -> 6")
eq(Menu.newCursorPosition(4, 2, full), 0, "4 DOWN wraps to 0")
eq(Menu.newCursorPosition(11, 2, full), 12, "11 DOWN -> CANCEL")
local twoEach = { [0] = true, [1] = true, [6] = true, [7] = true, [12] = true }
eq(Menu.newCursorPosition(12, 1, twoEach), 7, "CANCEL UP with two partner mons -> 7")
eq(Menu.newCursorPosition(5, 4, twoEach), 6, "an absent source still reads its row")
-- pokefirered/src/battle_interface.c:2165
eq(Menu.hpBarLevel(30, 30), 4, "full HP")
eq(Menu.hpBarLevel(20, 30), 3, "over half")
eq(Menu.hpBarLevel(10, 30), 2, "over a fifth")
eq(Menu.hpBarLevel(1, 100), 1, "one HP is still red")
eq(Menu.hpBarLevel(0, 30), 0, "fainted")
-- pokefirered/src/trade.c:2397
local lv5 = Menu.levelGenderTiles(mon(1, 5))
eq(lv5.tens, nil, "a one-digit level has no tens tile")
eq(lv5.ones, 0x75, "Lv5 ones tile")
local lv100 = Menu.levelGenderTiles(mon(1, 100))
eq(lv100.tens, 0x6A, "Lv100 uses the 10 tile")
eq(lv100.ones, 0x70, "and a 0")
check(lv100.symbol == 0x83 or lv100.symbol == 0x84 or lv100.symbol == 0x85, "gender tile is one of 0x83-0x85")
local egg = Menu.levelGenderTiles(mon(1, 5, nil, { isEgg = true }))
check(egg.egg and egg.ones == nil, "an egg prints no level")
eq(egg.symbol, 0x80, "and the egg symbol tile")
check(egg.symbolFlip, "drawn flipped")
-- pokefirered/src/trade.c:2339
eq(#Menu.movesLines(mon(1, 5)), 4, "four move rows")
eq(Menu.movesLines(mon(1, 5, nil, { isEgg = true }))[1], "gText_4Qmark", "an egg shows ????")
eq(LT.resumeMenu(), false, "resumeMenu only answers a canceled trade")

print("[test] 5. the barrier states keep the trade screen up until the commit")
Menu.reset()
LT.reset()
Menu.show()
Menu.cb = "idle"
for _, st in ipairs({ "exchange", "commit_wait" }) do
  LT.state = st
  Menu.update(0)
  check(Menu.isOpen(), "the screen stays up in " .. st)
end
LT.state = "committed"
Menu.update(0)
check(not Menu.isOpen(), "trade_commit hands off to the trade scene")
Menu.reset()
LT.reset()

print("[test] 6. a received EGG is not entered in the POKeDEX")
do
  local s = { party = { mon(1, 10), mon(4, 12) }, dex = { seen = {}, owned = {}, caught = {} } }
  -- pokefirered/src/trade_scene.c:1036
  Trade.tradeMons(s, 0, mon(152, 5, nil, { isEgg = true }))
  eq(s.party[1].species, 152, "the egg is in the party")
  check(not s.dex.seen[152], "its species is not seen")
  check(not s.dex.owned[152] and not s.dex.caught[152], "and not caught")
  Trade.tradeMons(s, 1, mon(155, 5))
  check(s.dex.seen[155] == true, "a received mon still is")
end

Link.reset()
LT.reset()
Union.reset()

if failed == 0 then
  print("[pass] link trade tables")
  os.exit(0)
end
print("[FAIL] link trade tables: " .. failed .. " failed")
os.exit(1)
