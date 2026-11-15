package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 rom text s7 g")
local check, eq = S.check, S.eq

local Bike = require("src.world.gen2.Bike")
local Decorations = require("src.core.gen2.Decorations")
local FieldMoves = require("src.world.gen2.FieldMoves")
local HiddenItems = require("src.world.gen2.HiddenItems")
local ItemEffects = require("src.core.gen2.ItemEffects")
local MomShopping = require("src.core.gen2.MomShopping")
local World = require("src.world.gen2.World")

local SENTINEL = {
  _UseCutText = "<CUT {STRBUF}>{PROMPT}",
  _AskSurfText = "<SURF?>{DONE}",
  _RepelWoreOffText = "<REPEL GONE>{DONE}",
  _WhitedOutText = "<WHITED OUT>{DONE}",
  _RecoveredSomeHPText = "<HEAL {STRBUF} {NUM}>{DONE}",
  _ItemWontHaveEffectText = "<NO EFFECT>{PROMPT}",
  _ItemfinderNopeText = "<NOPE>{PROMPT}",
  _CantGetOffBikeText = "<STAY ON>{DONE}",
  _MomHiHowAreYouText = "<HI>{PROMPT}",
  _MomFoundADollText = "<DOLL>{PROMPT}",
  _MomBoughtWithYourMoneyText = "<SORRY>{PROMPT}",
  _MomItsInYourRoomText = "<ROOM>{DONE}",
  _SetUpTheDecoText = "<SET {STRBUF}>{PROMPT}",
  ["DecorationNames#19"] = "<FEATHERY>",
  ["DecorationNames#14"] = "<BED>",
  _ItemStatRoseText = "<ROSE {STRBUF} {STRBUF}>{PROMPT}",
  ["StatStrings.health"] = "<HEALTH>",
}

local function without(label)
  local out = {}
  for k, v in pairs(SENTINEL) do if k ~= label then out[k] = v end end
  return { text = out }
end

local function fakeWorld(data)
  local log = {}
  local self = setmetatable({
    game = { data = data, save = { player = { money = 0 } } },
    log = log,
    showText = function(_, body) log[#log + 1] = body end,
    setNickname = function() end,
  }, { __index = World })
  return self, log
end

do
  local world, log = fakeWorld({ text = SENTINEL })
  World.runCut(world, { text = FieldMoves.TEXT.USE_CUT })
  eq(log[1], "<CUT {STRBUF}>", "USE_CUT prints data.text._UseCutText")
  local askWorld, askLog = fakeWorld({ text = SENTINEL })
  World.runOverworldFieldMove(askWorld,
    { ok = true, took = true, ask = FieldMoves.TEXT.ASK_SURF })
  eq(askLog[1], "<SURF?>", "an OW ask prints data.text._AskSurfText")
  local bare = fakeWorld(without("_UseCutText"))
  check(not pcall(World.runCut, bare, { text = FieldMoves.TEXT.USE_CUT }),
    "a dataset without _UseCutText is an error")
end

do
  local world, log = fakeWorld({ text = SENTINEL })
  World.repelWoreOff(world)
  eq(log[1], "<REPEL GONE>", "the repel line is data.text._RepelWoreOffText")
  World.whiteOut(world)
  eq(log[2], "<WHITED OUT>", "the whiteout line is data.text._WhitedOutText")
  check(not pcall(World.repelWoreOff, fakeWorld(without("_RepelWoreOffText"))),
    "a dataset without _RepelWoreOffText is an error")
end

do
  local mon = { species = "MAGIKARP", nickname = "KARP", hp = 10, maxHp = 40,
    stats = { hp = 40 } }
  local data = { text = SENTINEL }
  eq(ItemEffects.useOnMon("POTION", mon, data).text, "<HEAL KARP 20>",
    "POTION prints data.text._RecoveredSomeHPText with the name and the delta")
  local full = { species = "MAGIKARP", nickname = "KARP", hp = 40, maxHp = 40,
    stats = { hp = 40 } }
  eq(ItemEffects.useOnMon("POTION", full, data).text, "<NO EFFECT>",
    "a full mon prints data.text._ItemWontHaveEffectText")
  local hurt = { species = "MAGIKARP", nickname = "KARP", hp = 10, maxHp = 40,
    stats = { hp = 40 } }
  check(not pcall(ItemEffects.useOnMon, "POTION", hurt,
    without("_RecoveredSomeHPText")),
    "a dataset without _RecoveredSomeHPText is an error")
end

do
  local data = { text = SENTINEL }
  local nope = HiddenItems.itemfinderScript(nil, nil, data)
  eq(nope[2].text, "<NOPE>", "the itemfinder miss is data.text._ItemfinderNopeText")
  check(not pcall(HiddenItems.itemfinderScript, nil, nil,
    without("_ItemfinderNopeText")), "and errors without it")

  eq(Bike.cantGetOffScript(data)[2].text, "<STAY ON>",
    "Script_CantGetOffBike is data.text._CantGetOffBikeText")
  check(not pcall(Bike.cantGetOffScript, without("_CantGetOffBikeText")),
    "and errors without it")

  local pages = MomShopping.pages({ kind = "doll" }, data)
  eq(table.concat(pages, "|"), "<HI>|<DOLL>|<SORRY>|<ROOM>",
    ".DollScript is the four data.text lines")
  check(not pcall(MomShopping.pages, { kind = "doll" },
    without("_MomFoundADollText")), "and errors without one of them")

  Decorations.useRegistry(data)
  local _, decoPages = Decorations.apply({}, 2)
  eq(decoPages[1], "<SET <FEATHERY><BED>>",
    "SetUpTheDecoText names the bed out of DecorationNames")
  Decorations.useRegistry(without("_SetUpTheDecoText"))
  check(not pcall(Decorations.apply, {}, 2), "and errors without it")
  Decorations.useRegistry(nil)
end

do
  local mon = { species = "MAGIKARP", nickname = "KARP", hp = 10, maxHp = 40,
    stats = { hp = 40 }, level = 10 }
  eq(ItemEffects.useOnMon("HP_UP", mon, { text = SENTINEL }).text,
    "<ROSE KARP <HEALTH>>", "HP UP names the stat out of StatStrings")
  local hp = { species = "MAGIKARP", nickname = "KARP", hp = 10, maxHp = 40,
    stats = { hp = 40 }, level = 10 }
  check(not pcall(ItemEffects.useOnMon, "HP_UP", hp,
    without("StatStrings.health")), "and errors without it")
end

S.finish()
