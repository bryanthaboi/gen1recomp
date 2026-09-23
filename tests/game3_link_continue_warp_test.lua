#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").stubSpeciesNames()

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Schema = require("src.core.game3.save_schema_firered")

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"

local function linkSession(room)
  local s = Schema.newGame({ gender = 0 })
  s.map, s.x, s.y = room, 5, 8
  s.dynamicWarp = { map = CENTER_2F, warpId = 0, x = 9, y = 1 }
  return s
end

local trade = linkSession("FR_TRADE_CENTER")
local saved = Schema.toSaveTable(trade)
check(saved.map == "FR_TRADE_CENTER", "save keeps the trade center position")
check(saved.specialSaveWarpFlags == 1, "trade center save carries CONTINUE_GAME_WARP")
local w = saved.continueGameWarp or {}
check(w.map == CENTER_2F and w.x == 9 and w.y == 1, "continue warp is the dynamic warp")
check((tonumber(trade.specialSaveWarpFlags) or 0) == 0, "live flag stays clear after the save")

local cont = Schema.fromSaveTable(saved)
check(cont.map == CENTER_2F and cont.x == 9 and cont.y == 1,
  "continue lands at the cable club door (got " .. tostring(cont.map) .. " "
  .. tostring(cont.x) .. "," .. tostring(cont.y) .. ")")
check(cont.specialSaveWarpFlags == 0, "CONTINUE_GAME_WARP cleared on continue")

local again = Schema.fromSaveTable(Schema.toSaveTable(cont))
check(again.map == CENTER_2F and again.x == 9 and again.y == 1, "a save outside the link room keeps its position")

for _, room in ipairs({ "FR_BATTLE_COLOSSEUM_2P", "FR_BATTLE_COLOSSEUM_4P", "FR_RECORD_CORNER", "FR_UNION_ROOM" }) do
  local c = Schema.fromSaveTable(Schema.toSaveTable(linkSession(room)))
  check(c.map == CENTER_2F and c.x == 9 and c.y == 1, room .. " save continues at the dynamic warp")
end

local outside = linkSession(CENTER_2F)
outside.x, outside.y = 7, 4
local o = Schema.fromSaveTable(Schema.toSaveTable(outside))
check(o.map == CENTER_2F and o.x == 7 and o.y == 4, "a normal save with a stale dynamic warp is not redirected")

local gcn = Schema.newGame({ gender = 0 })
gcn.gcnLinkFlags = 0x800E
local g = Schema.fromSaveTable(Schema.toSaveTable(gcn))
check(g.gcnLinkFlags == 0x800E, "gcnLinkFlags survive a save")
check(Schema.fromSaveTable(Schema.toSaveTable(Schema.newGame({ gender = 0 }))).gcnLinkFlags == 0,
  "gcnLinkFlags default to 0")

local battleSession = linkSession("FR_BATTLE_COLOSSEUM_2P")
battleSession.party = { { species = 6, level = 50, hp = 150, maxHp = 150 } }
local written
local game = {
  session = battleSession,
  saveGame = function(self)
    written = Schema.toSaveTable(self.session)
    return true
  end,
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return battleSession end,
  _game = game,
}
local Link = require("src.core.game3.link")
local LB = require("src.core.game3.link.battle")
local sent = {}
Link.link = {
  isOpen = function() return true end,
  send = function(_, msg) sent[#sent + 1] = msg end,
}
LB.reset()
LB.mode = Link.USING.SINGLE_BATTLE
LB._started = true
LB.peer = { name = "BLUE", trainerId = 0x2222 }
LB.finish("win")
check(written ~= nil, "a finished link battle saves the game")
local bw = written and written.continueGameWarp or {}
check(written and written.specialSaveWarpFlags == 1 and bw.map == CENTER_2F and bw.x == 9 and bw.y == 1,
  "post-battle save continues at the dynamic warp")

written = nil
Link.link = { isOpen = function() return false end, send = function() end }
LB.reset()
LB.mode = Link.USING.SINGLE_BATTLE
LB._started = true
LB.finish("draw")
check(written == nil, "a dropped link does not save")
Link.link = nil
LB.reset()

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
