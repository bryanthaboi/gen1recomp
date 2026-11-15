-- engine/battle/core.asm:4965 and engine/events/battle_tower/battle_tower.asm:218
--
--   luajit tests/gen2_battle_tower_menu_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle tower menu")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local BattleState = require("src.ui.gen2.BattleState")

local function fake(tower)
  local opened = false
  local state = setmetatable({
    phase = "menu",
    game = { options = { battleStyle = "SHIFT" }, stack = {},
      data = { text = require("tests.fixture_data.gen2_rom_text_s7_b").text() } },
    battle = {
      inBattleTowerBattle = tower or nil,
      player = { hp = 10 }, trainer = {},
      party = { {}, {} },
    },
  }, { __index = BattleState })
  state.openPack = function() opened = true end
  return state, function() return opened end
end

do
  local state, opened = fake(true)
  state:chooseMenu("item")
  check(not opened(), "tower PACK does not open")
  eq(state.phase, "refuse-menu", "tower PACK refuses")
  check(state.message and state.message:find("Items can't be") ~= nil,
    "tower PACK prints ItemsCantBeUsedHere")
end

do
  local state, opened = fake(false)
  state:chooseMenu("item")
  check(opened(), "normal PACK opens")
end

do
  local tower = fake(true)
  check(not tower:shiftOfferAllowed(), "tower forces SET mode")
  local normal = fake(false)
  check(normal:shiftOfferAllowed(), "normal battle honors SHIFT")
end

do
  local tower = fake(true)
  tower.battle.outcome = "lose"
  check(not tower:whitesOut(), "tower loss does not white out")
  local normal = fake(false)
  normal.battle.outcome = "lose"
  check(normal:whitesOut(), "normal loss whites out")
end

S.finish()
