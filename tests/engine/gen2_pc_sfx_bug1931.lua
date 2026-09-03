-- home/menu.asm:746

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local Sound = require("src.core.Sound")
local Save = require("src.core.gen2.Save")
local PcMenu = require("src.ui.gen2.PcMenu")
local ItemPcMenu = require("src.ui.gen2.ItemPcMenu")
local BoxMenu = require("src.ui.gen2.BoxMenu")
local CenterPcMenu = require("src.ui.gen2.CenterPcMenu")

local played = {}
Sound.play = function(_data, name) played[#played + 1] = name end
Sound.waitSfxDone = function() end

local SFX = {
  Sfx_ReadText2 = true,
  Sfx_BootPc = true,
  Sfx_ShutDownPc = true,
  Sfx_ChoosePcOption = true,
  Sfx_Wrong = true,
}

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

local function newGame(save)
  return {
    input = newInput(),
    save = save,
    options = save.options,
    data = { items = {}, moves = {}, pokemon = {},
      audio = { sfx = SFX } },
    stack = { push = function() end, pop = function() end },
  }
end

local function newSave()
  local save = Save.newGame()
  save.party = { { species = "CYNDAQUIL", level = 5 } }
  save.pcItems = {}
  return save
end

local function last() return played[#played] end


local function openPc()
  local save = newSave()
  local game = newGame(save)
  local menu = PcMenu.new(game, { save = save, bills = true,
    saveExists = false, writer = function() return true end,
    onClose = function() end })
  menu.message = nil
  played = {}
  return menu, game
end

do
  local menu, game = openPc()
  menu.index = #menu.entries
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "the PC's top menu clicks on A")
end

do
  local menu, game = openPc()
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on the B that logs off")
end

do
  local menu, game = openPc()
  game.input:press("down")
  menu:update(0)
  eq(#played, 0, "walking the rows is silent")
end


do
  local menu, game = openPc()
  menu.picking = true
  menu.pickIndex = menu.save.currentBox or 1
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "CHANGE BOX's picker clicks on A")
  eq(menu.picking, false, "and the picker closes on the current box")
end

do
  local menu, game = openPc()
  menu.picking = true
  menu.pickIndex = 1
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on the B that backs out")
end


local function printedPrompt(menu)
  menu.typer = nil
  menu.savePage = #menu:savePages()
end

do
  local menu, game = openPc()
  menu.picking = true
  menu:beginChangeBox(2)
  printedPrompt(menu)
  menu.saveChoice = 2
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "the CHANGE BOX yes/no clicks on A")
end

do
  local menu, game = openPc()
  menu.picking = true
  menu:beginChangeBox(2)
  printedPrompt(menu)
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on B")
end


local function openItemPc()
  local save = newSave()
  local game = newGame(save)
  local menu = ItemPcMenu.new(game, { save = save, onClose = function() end })
  menu.message = nil
  played = {}
  return menu, game
end

do
  local menu, game = openItemPc()
  menu.index = #menu.entries
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "the item PC's menu clicks on A")
end

do
  local menu, game = openItemPc()
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on the B that turns it off")
end

do
  local menu, game = openItemPc()
  menu.phase = "withdraw"
  menu.rows = {}
  menu.listIndex = 1
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", ".PCItemsMenuData clicks on A")

  menu.phase = "withdraw"
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on the B that quits the list")
  eq(menu.phase, "menu", "which drops back to the top menu")
end

do
  local menu, game = openItemPc()
  menu.qtyState = { qty = 1, max = 9, onAccept = function() end }
  game.input:press("a")
  menu:update(0)
  eq(#played, 0, "the quantity picker stays silent")
end

do
  local menu, game = openItemPc()
  menu.confirm = { choice = 2, onNo = function() end }
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "the item PC's yes/no clicks on A")

  menu.confirm = { choice = 1, onNo = function() end }
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on B")
end


local function openBox()
  local save = newSave()
  local game = newGame(save)
  local menu = BoxMenu.new(game, { save = save, mode = "withdraw",
    onClose = function() end })
  played = {}
  return menu, game
end

do
  local menu, game = openBox()
  menu.phase = "submenu"
  menu.submenuIndex = #menu:submenuRows()
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "the box submenu clicks on A")
  eq(menu.phase, nil, "and CANCEL closes it")
end

do
  local menu, game = openBox()
  menu.phase = "submenu"
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on B")
end

do
  local menu, game = openBox()
  game.input:press("a")
  menu:update(0)
  eq(#played, 0, "the mon list itself is silent on A")

  game.input:press("b")
  menu:update(0)
  eq(#played, 0, "and on B")
end


local function openCenter()
  local save = newSave()
  local game = newGame(save)
  local menu = CenterPcMenu.new(game, { save = save, items = {},
    onClose = function() end })
  menu.message = nil
  played = {}
  return menu, game
end

do
  local menu, game = openCenter()
  menu.index = 1
  game.input:press("a")
  menu:update(0)
  eq(#played, 1, "MENU_NO_CLICK_SFX: the whose-PC menu adds no click")
  eq(last(), "Sfx_ChoosePcOption", "only PC_PlayChoosePCSound")
end

do
  local menu, game = openCenter()
  game.input:press("b")
  menu:update(0)
  eq(#played, 1, "and none on the B that shuts the PC down")
  eq(last(), "Sfx_ShutDownPc", "only PC_PlayShutdownSound")
end

do
  local menu, game = openCenter()
  menu.confirm = { choice = 2, onNo = function() end }
  game.input:press("a")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "OakPCText1's yes/no clicks on A")

  menu.confirm = { choice = 1, onNo = function() end }
  game.input:press("b")
  menu:update(0)
  eq(last(), "Sfx_ReadText2", "and on B")
end

do
  local menu, game = openPc()
  game.data.audio.sfx = {}
  game.input:press("b")
  menu:update(0)
  eq(#played, 0, "a cache without the cue simply makes no sound")
end

T.finish("gen2 pc sfx bug 1931")
