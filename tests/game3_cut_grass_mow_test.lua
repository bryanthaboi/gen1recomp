package.path = "./?.lua;./?/init.lua;" .. package.path

require("src.core.GameVersion").set("firered")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

package.loaded["src.core.game3.field_move_show_mon"] = { start = function(_, _, fn) fn() end }
package.loaded["src.core.game3.quest_log_recorder"] = { event = function() end, location = function() end }

local FieldMoves = require("src.core.game3.field_moves")
local LayoutNative = require("src.core.game3.layout_native")
local FieldEffects = require("src.core.game3.field_effects")
local Audio = require("src.core.game3.audio")
local Field = require("src.core.game3.field")
local Map = require("src.core.game3.map")
local Player = require("src.core.game3.player")

check(FieldMoves.CUT_GRASS_METATILES[0x284] == 0x281, "Viridian Forest HugeTreeTopMiddle_Grass mows to 0x281")
check(LayoutNative.setMidAt == nil, "LayoutNative has no setMidAt, writes go through applyOverride")

local function grid(w, h, fill, coll)
  local cells = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      cells[y * w + x + 1] = { mid = fill(x, y), coll = coll or 0, elev = 3 }
    end
  end
  return LayoutNative.fromDecoded({ width = w, height = h, cells = cells }, "FR_CUT_TEST", "cut_test")
end

local L = grid(5, 5, function() return 0x00D end)
L.cells[1 * 5 + 1 + 1] = { mid = 0x00D, coll = 0, elev = 4 }
L.cells[3 * 5 + 3 + 1] = { mid = 0x284, coll = 0, elev = 3 }
L.cells[1 * 5 + 3 + 1] = { mid = 0x3FF, coll = 0, elev = 3 }
local n = FieldMoves.mowGrass3x3(2, 2,
  function(x, y) return L:midAt(x, y) end,
  function(x, y, mid) L:applyOverride(x, y, mid, 0, L:elevAt(x, y)) end,
  function(x, y) return L:elevAt(x, y) == 3 end)
check(n == 7, "seven cells mowed (got " .. n .. ")")
check(L:midAt(2, 2) == 0x001 and L:midAt(1, 3) == 0x001, "plain grass becomes Plain_Mowed")
check(L:midAt(3, 3) == 0x281, "0x284 becomes 0x281")
check(L:midAt(1, 1) == 0x00D, "grass at another elevation is left alone")
check(L:midAt(3, 1) == 0x3FF, "unmapped metatile is left alone")
check(L:midAt(0, 0) == 0x00D, "cells outside the 3x3 are untouched")

local def = { id = "FR_CUT_TEST", pair = "cut_test", width = 3, height = 3, connections = {}, objects = {}, warps = {} }
def.midLayout = grid(6, 6, function(x) return x == 5 and 0x001 or 0x00D end, 0x18)
def.midLayout.cells[1 * 6 + 1 + 1] = { mid = 0x284, coll = 0, elev = 3 }
def.midLayout.cells[2 * 6 + 0 + 1] = { mid = 0x3FF, coll = 0x18, elev = 0 }
local game = { data = { maps = { FR_CUT_TEST = def } }, save = {} }
local session = { map = "FR_CUT_TEST", flags = {}, vars = {} }
Field._game, Field._session = game, session
Map._def, Map.current = def, "FR_CUT_TEST"
Player.cellX, Player.cellY, Player.elevation = 0, 2, 3
Audio.playSe = function() end
require("src.core.game3.collision").bindMap(game, "FR_CUT_TEST", def)
local grassCb = 0
FieldEffects.startCutGrass = function(_, _, cb) grassCb = grassCb + 1; if cb then cb() end end
local events = {}
local ModRuntime = require("src.mods.Runtime")
local wants, emit = ModRuntime.wants, ModRuntime.emit
ModRuntime.wants = function(name) return name == "world.block_replaced" or wants(name) end
ModRuntime.emit = function(name, ev) if name == "world.block_replaced" then events[#events + 1] = ev else return emit(name, ev) end end

Field.executeFieldMove({ action = "cut_grass", mon = {} })
ModRuntime.wants, ModRuntime.emit = wants, emit

local count = 0
for _ in pairs(def.midLayout.overrides) do count = count + 1 end
check(count == 4, "edge cut writes the four in-bounds grass cells at the player's elevation (got " .. count .. ")")
check(def.midLayout:midAt(1, 1) == 0x284, "table id on a non-grass cell is left alone")
check(def.midLayout:midAt(0, 2) == 0x3FF, "player's elevation-0 cell does not drive the cut elevation")
check(def.midLayout:midAt(0, 1) == 0x001 and def.midLayout:midAt(1, 3) == 0x001, "field branch mows through Field.setMetatile")
check(def.midLayout.overrides[2 * 1024 - 1] == nil and def.midLayout.overrides[1 * 1024 - 1] == nil,
  "no write outside the map")
check(#events == 4, "every mowed cell raises world.block_replaced")
check(Field.metatileOverrideAt("FR_CUT_TEST", 1, 2) ~= nil, "override is recorded for the map")
check(grassCb == 1 and Field.locked == false, "leaf animation runs and unlocks the field")

Field.clearMetatiles(def.midLayout)
check(def.midLayout:midAt(1, 2) == 0x00D, "map reload grows the grass back")

os.exit(failures == 0 and 0 or 1)
