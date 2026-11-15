package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 engine flags bind")
local check, eq = S.check, S.eq

local Apricorns = require("src.core.gen2.Apricorns")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Fixture = require("tests.fixture_data.gen2_engine_flags")
local Pokerus = require("src.core.gen2.Pokerus")

local function stocked()
  return { engineFlags = {}, events = {}, inventory = { RED_APRICORN = 1 } }
end

FieldMoves.bindEngineFlags(Fixture.order("crystal"))
eq(Apricorns.ENGINE_KURT_MAKING_BALLS, 80, "Crystal's KURT_MAKING_BALLS is 80")
eq(Apricorns.ENGINE_ALL_FRUIT_TREES, 84, "Crystal's ALL_FRUIT_TREES is 84")
eq(Pokerus.ENGINE_REACHED_GOLDENROD, 22, "Crystal's REACHED_GOLDENROD is 22")
local crystalSave = stocked()
Apricorns.give(crystalSave, "RED_APRICORN")
check(crystalSave.engineFlags[80] == true and crystalSave.engineFlags[79] == nil,
  "giving Kurt an apricorn on Crystal sets flag 80, not Gold's 79")
local trees = { engineFlags = {} }
Apricorns.tryResetFruitTrees(trees)
check(trees.engineFlags[84] == true and trees.engineFlags[83] == nil,
  "the fruit-tree reset on Crystal latches flag 84")

FieldMoves.bindEngineFlags(Fixture.order("gold"))
eq(Apricorns.ENGINE_KURT_MAKING_BALLS, 79, "Gold's KURT_MAKING_BALLS is 79")
eq(Apricorns.ENGINE_ALL_FRUIT_TREES, 83, "Gold's ALL_FRUIT_TREES is 83")
eq(Pokerus.ENGINE_REACHED_GOLDENROD, 21, "Gold's REACHED_GOLDENROD is 21")
local goldSave = stocked()
Apricorns.give(goldSave, "RED_APRICORN")
check(goldSave.engineFlags[79] == true, "giving Kurt an apricorn on Gold sets flag 79")

check(not pcall(FieldMoves.bindEngineFlags, nil),
  "a dataset with no engineFlagOrder is an error")
check(not pcall(FieldMoves.bindEngineFlags, { "ENGINE_RADIO_CARD" }),
  "and so is an order missing a flag the engine names")

S.finish()
