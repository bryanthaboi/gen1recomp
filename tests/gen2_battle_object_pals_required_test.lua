package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle object pals required")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local BattleHud = require("src.ui.gen2.BattleHud")
local BattleAnimView = require("src.ui.gen2.BattleAnimView")
local BattleState = require("src.ui.gen2.BattleState")

local YELLOW = { { 255, 255, 255 }, { 255, 255, 0 }, { 255, 115, 0 }, { 0, 0, 0 } }
local GRAY = { { 255, 255, 255 }, { 189, 189, 189 }, { 107, 107, 107 }, { 0, 0, 0 } }

local function fails(fn, needle, label)
  local ok, err = pcall(fn)
  check(not ok and tostring(err):find(needle, 1, true) ~= nil,
    label .. " (" .. tostring(err) .. ")")
end

fails(function() return BattleHud.ballColors({ palettes = {} }) end,
  "no battleObjects", "the party balls need palettes.battleObjects")
fails(function() return BattleHud.ballColors({ palettes = { battleObjects = {} } }) end,
  "PAL_BATTLE_OB_YELLOW", "and its PAL_BATTLE_OB_YELLOW row")
eq(BattleHud.ballColors({ palettes = { battleObjects = { PAL_BATTLE_OB_YELLOW = YELLOW } } }),
  YELLOW, "the balls wear PAL_BATTLE_OB_YELLOW")

fails(function() return BattleAnimView.objPalette({ palettes = {} }, "PAL_BATTLE_OB_GRAY") end,
  "no battleObjects", "an animation object needs palettes.battleObjects")
fails(function()
  return BattleAnimView.objPalette({ palettes = { battleObjects = { PAL_BATTLE_OB_GRAY = GRAY } } },
    "PAL_BATTLE_OB_RED")
end, "PAL_BATTLE_OB_RED", "and the row it names")
eq(BattleAnimView.objPalette({ palettes = { battleObjects = { PAL_BATTLE_OB_GRAY = GRAY } } },
  "PAL_BATTLE_OB_GRAY"), GRAY, "a named row is that row")

fails(function()
  BattleState.drawExpBurst({ expBurst = { frame = 1 }, palettes = {},
    hud = { drawExpBarEnd = function() end } })
end, "no battleObjects", "the exp burst needs palettes.battleObjects")
fails(function()
  BattleState.drawExpBurst({ expBurst = { frame = 1 }, palettes = { battleObjects = {} },
    hud = { drawExpBarEnd = function() end } })
end, "PAL_BATTLE_OB_BLUE", "and its PAL_BATTLE_OB_BLUE row")

S.finish()
