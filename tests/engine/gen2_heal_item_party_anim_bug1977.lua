-- engine/items/item_effects.asm:1644
-- engine/items/item_effects.asm:1671
-- engine/items/item_effects.asm:1748
-- data/text/common_1.asm:30
-- home/text.asm:772

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local HpBar = require("src.battle.gen2.HpBar")
local ItemEffects = require("src.core.gen2.ItemEffects")
local PartyMenu = require("src.ui.gen2.PartyMenu")


T.eq(HpBar.stepToward(10, 30, 39), 11, "under 48 max HP the bar steps one HP")
T.eq(HpBar.stepToward(30, 10, 39), 29, "and one hit point back down")
T.eq(HpBar.stepToward(0, 200, 96), 2,
  "from 48 up a step is ceil(maxHp / 48) hit points")
T.eq(HpBar.stepToward(28, 30, 200), 30, "and it never overshoots the target")


local mon = { species = "SUICUNE", nickname = "SUICUNE", hp = 197,
  maxHp = 199, stats = { hp = 199 } }
local HEAL_TEXT = require("tests.fixture_data.gen2_rom_text_s7_g").text()
local result = ItemEffects.useOnMon("POTION", mon, { text = HEAL_TEXT })
T.eq(result.text, (HEAL_TEXT._RecoveredSomeHPText:gsub("{STRBUF}", "SUICUNE")
  :gsub("{NUM}", "2"):gsub("{DONE}", "")),
  "TextCommand_DECIMAL is left-aligned, so no padding and no space before HP!")


local input = { pressed = {} }
function input:press(button) self.pressed[button] = true end
function input:wasPressed(button)
  if self.pressed[button] then
    self.pressed[button] = nil
    return true
  end
  return false
end
function input:isDown() return false end

local party = { { species = "SENTRET", nickname = "SENTRET", level = 5,
  hp = 1, maxHp = 20, stats = { hp = 20 }, moves = {} } }
local game = { data = { gen2MenuGfx = {} }, input = input,
  save = { party = party } }
local menu = PartyMenu.new(game, { party = party, prompt = "useItem" })

local done = false
menu:showItemResult(1, { fromHp = 1, toHp = 11, sfx = "Sfx_Potion",
  text = "SENTRET\nrecovered 10HP!", onDone = function() done = true end })
T.check(menu:itemResultClimbing(), "the pick arms the bar climb")
T.eq(menu:shownHpFor(1, party[1]), 1, "the row reads the pre-heal HP first")
T.eq(PartyMenu.rowFor(party[1], menu:shownHpFor(1, party[1])).hp, "  1/ 20",
  "and the digits follow the bar, not the mon")

for _ = 1, 9 do menu:update(1 / 60) end
T.eq(menu.itemResult.shown, 10, "one hit point a step under 48 max HP")
menu:update(1 / 60)
T.eq(menu.itemResult.shown, 11, "landing on the healed value")
T.check(not menu:itemResultClimbing(), "with the climb finished")

for _ = 1, PartyMenu.ACTION_TEXT_DELAY do
  input:press("a")
  menu:update(1 / 60)
end
T.check(not done, "the button is dead through DelayFrames' 50 frames")
input:press("a")
menu:update(1 / 60)
T.check(done, "and WaitPressAorB_BlinkCursor answers after them")
T.eq(menu.itemResult, nil, "clearing the result with it")

menu:showItemResult(1, { text = "SENTRET\nis cured of poison." })
T.check(not menu:itemResultClimbing(), "a status cure runs no HealHP_SFX_GFX")
T.eq(menu:shownHpFor(1, party[1]), party[1].hp,
  "and the row reads the mon straight")

local before = menu.index
input:press("down")
menu:update(1 / 60)
T.eq(menu.index, before, "the list is frozen behind the action text")

T.finish("gen2 heal item party anim bug 1977")
