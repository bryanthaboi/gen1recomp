-- pokecrystal constants/engine_flags.asm:66-92 vs pokegold :65-91

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Fixture = require("tests.fixtures.gen2_flypoints")

local GOLD_IDS = {}
for _, row in ipairs(Fixture.ROWS) do GOLD_IDS[row[1]] = row[3] end

local function byFlag()
  local out = {}
  for _, row in ipairs(FieldMoves.FLYPOINTS) do out[row.spawn] = row.flag end
  return out
end

Fixture.bind("gold")
local gold = byFlag()
for spawn, id in pairs(GOLD_IDS) do
  T.eq(gold[spawn], id, spawn .. " binds the pokegold id")
end

FieldMoves.bindEngineFlags({ [18] = "ENGINE_BUG_CONTEST_TIMER" })
T.eq(byFlag().SPAWN_INDIGO, 63, "bindEngineFlags leaves the flypoint ids alone")

Fixture.bind("crystal")
local crystal = byFlag()
for spawn, id in pairs(GOLD_IDS) do
  T.eq(crystal[spawn], id + 1, spawn .. " binds one higher from Crystal rows")
end

local save = { engineFlags = { [64] = true } }
T.check(FieldMoves.hasVisitedSpawn(save, "SPAWN_INDIGO"),
  "Crystal flag 64 is the INDIGO_PLATEAU flypoint")
local kanto = FieldMoves.flyPoints(save, nil, "kanto")
T.eq(#kanto, 1, "the Kanto half opens on it")
T.eq(kanto[1].spawn, "SPAWN_INDIGO", "with the plateau row itself")

Fixture.bind("gold")
local again = byFlag()
for spawn, id in pairs(GOLD_IDS) do
  T.eq(again[spawn], id, spawn .. " returns to the pokegold id")
end
local goldSave = { engineFlags = { [63] = true } }
T.check(FieldMoves.hasVisitedSpawn(goldSave, "SPAWN_INDIGO"),
  "Gold flag 63 is INDIGO_PLATEAU again")

FieldMoves.bindEngineFlags(nil)
T.finish("gen2 flypoint rebind bug 1836")
