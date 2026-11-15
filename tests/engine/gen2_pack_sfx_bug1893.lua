-- engine/menus/scrolling_menu.asm:23 (#1893)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local PackMenu = require("src.ui.gen2.PackMenu")
local Save = require("src.core.gen2.Save")
local Sound = require("src.core.Sound")

local ITEMS = {
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 17,
    canToss = true, canSelect = false, fieldMenu = "ITEMMENU_PARTY" },
  ESCAPE_ROPE = { id = "ESCAPE_ROPE", name = "ESCAPE ROPE", pocket = "ITEM",
    index = 29, canToss = true, canSelect = true,
    fieldMenu = "ITEMMENU_CLOSE" },
}

local played = {}
local realPlay = Sound.play
Sound.play = function(_data, name) played[#played + 1] = name end

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local function openPack()
  local save = Save.newGame()
  save.inventory = { POTION = 5, ESCAPE_ROPE = 1 }
  save.bagOrder = { "POTION", "ESCAPE_ROPE" }
  local game = {
    input = newInput(),
    save = save,
    options = save.options,
    data = { items = ITEMS, moves = {}, pokemon = {},
      text = require("tests.fixtures.gen2_rom_text").text(),
      gen2Text = require("tests.fixtures.gen2_common_text").text(),
      gen2EventTables = require("tests.fixtures.gen2_phone_events").events,
      audio = { sfx = {
      Sfx_ReadText2 = true,
      Sfx_SwitchPockets = true,
      Sfx_SwitchPokemon = true,
    } } },
    stack = { push = function() end, pop = function() end },
  }
  local pack = PackMenu.new(game, { save = save, pocket = "ITEM",
    onClose = function() end,
    world = { useFieldItem = function() end } })
  pack.gfx = { available = function() return false end, draw = function() end,
    colorsAt = function() return nil end }
  played = {}
  return pack, game
end

local function last()
  return played[#played]
end

do
  local pack, game = openPack()
  game.input:press("right")
  pack:update(0)
  eq(pack:pocket().id, "BALL", "right moves on to the next pocket")
  eq(last(), "Sfx_SwitchPockets", "and rings the pocket cue")
end

do
  local pack, game = openPack()
  game.input:press("down")
  pack:update(0)
  eq(#played, 0, "down the list is silent")
  game.input:press("up")
  pack:update(0)
  eq(#played, 0, "so is up")

  game.input:press("a")
  pack:update(0)
  eq(last(), "Sfx_ReadText2", "A on a row clicks")
  check(pack.submenu ~= nil, "and opens the item submenu")

  game.input:press("b")
  pack:update(0)
  eq(last(), "Sfx_ReadText2", "B out of the submenu clicks too")
end

do
  local pack, game = openPack()
  pack.index = 1
  game.input:press("select")
  pack:update(0)
  eq(#played, 0, "SELECT arming a move is silent")
  eq(pack.switching, 1, "and the row is held")

  game.input:press("down")
  pack:update(0)
  game.input:press("a")
  pack:update(0)
  eq(last(), "Sfx_SwitchPokemon", "putting it down rings the swap cue")
  eq(pack.switching, nil, "and the move ends")
end

do
  local pack, game = openPack()
  pack.index = 1
  game.input:press("select")
  pack:update(0)
  game.input:press("a")
  pack:update(0)
  eq(last(), "Sfx_SwitchPokemon", "placing it back on its own row still rings")
end

do
  local pack, game = openPack()
  game.data.audio.sfx = {}
  game.input:press("right")
  pack:update(0)
  eq(#played, 0, "a cache without the cue simply makes no sound")
end

Sound.play = realPlay

T.finish("gen2 pack sfx bug 1893")
