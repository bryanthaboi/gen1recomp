-- Bill's PC d-pad: only MOVE <PK><MN> W/O MAIL walks the boxes (#1710).
--
--   luajit tests/gen2_billspc_dpad_test.lua
--
-- ROM-free.  Withdraw_UpDown is the entire joypad handler for the WITHDRAW
-- list and the DEPOSIT list (engine/pokemon/bills_pc.asm:806-820) and reads
-- PAD_UP and PAD_DOWN and nothing else.  BillsPC_PressLeft / PressRight
-- (:909-931) are reachable only through MoveMonWithoutMail_DPad and
-- MoveMonWithoutMail_DPad_2 (:822-869), whose one caller is
-- _MovePKMNWithoutMail (:480) -- so left and right belong to the MOVE screen
-- alone, both while it is choosing a mon and while the insert cursor is up.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 bills pc dpad")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local BoxMenu = require("src.ui.gen2.BoxMenu")
local Boxes = require("src.core.gen2.Boxes")

local function mon(species)
  return { species = species, nickname = species, name = species,
    level = 5, hp = 20, maxHp = 20 }
end

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
  local input = newInput()
  return {
    input = input,
    save = save,
    data = { audio = {}, pokemon = {} },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }, input
end

-- Three party mons and two boxes with something in them, so every list under
-- test has rows and the last-healthy rule never gets in the way.
local function newSave()
  local save = { party = { mon("CYNDAQUIL"), mon("TOTODILE"), mon("PIDGEY") },
    boxes = {}, boxNames = {}, currentBox = 3 }
  Boxes.box(save, 3)[1] = mon("GEODUDE")
  Boxes.box(save, 3)[2] = mon("ZUBAT")
  Boxes.box(save, 4)[1] = mon("ONIX")
  return save
end

local function press(screen, input, ...)
  for _, button in ipairs({ ... }) do
    input:press(button)
    screen:update(0)
  end
end

local function open(mode)
  local save = newSave()
  local game, input = newGame(save)
  local menu = BoxMenu.new(game, { save = save, mode = mode,
    onClose = function() end })
  return menu, input, save
end

-- ---- the withdraw list ----------------------------------------------------
do
  local menu, input = open("withdraw")
  eq(menu.boxIndex, 3, "the withdraw list opens on the current box")
  eq(menu:title(), "BOX3", "and the header names it")

  press(menu, input, "left")
  eq(menu.boxIndex, 3, "LEFT on the withdraw list does not change the box")
  eq(menu:title(), "BOX3", "the header still reads BOX3")
  eq(menu.index, 1, "and the cursor has not been reset by a box step")

  -- Two more LEFTs, so a screen that steps and then steps back cannot pass by
  -- landing on 3 again.
  press(menu, input, "left", "left")
  eq(menu.boxIndex, 3, "and neither do two more")
  eq(#menu:list(), 2, "the list is still BOX3's two mons")

  -- RIGHT from a fresh screen, for the same reason.
  menu, input = open("withdraw")
  press(menu, input, "right", "right")
  eq(menu.boxIndex, 3, "RIGHT does not change the box either")
  eq(menu:title(), "BOX3", "the header is unmoved")

  -- Withdraw_UpDown DOES read up and down, so the fix must not have taken the
  -- whole d-pad away.
  press(menu, input, "down")
  eq(menu.index, 2, "DOWN still walks the list")
  press(menu, input, "up")
  eq(menu.index, 1, "and UP walks back")
end

-- ---- the deposit list -----------------------------------------------------
--
-- _DepositPKMN's .HandleJoypad calls the same Withdraw_UpDown, and its list is
-- the party (wBillsPC_LoadedBox is zeroed at bills_pc.asm:17-18), so there is
-- no box for left and right to walk to in the first place.
do
  local menu, input = open("deposit")
  eq(menu:title(), "PARTY <PK><MN>", "the deposit list browses the party")
  local before = menu.boxIndex
  press(menu, input, "left", "right", "left")
  eq(menu.boxIndex, before, "the deposit list ignores left and right")
  eq(menu:title(), "PARTY <PK><MN>", "and stays on the party")
  eq(#menu:list(), 3, "with all three party mons")
  press(menu, input, "down")
  eq(menu.index, 2, "up and down still work here too")
end

-- ---- the move screen ------------------------------------------------------
--
-- The half that is supposed to have box stepping.  Gating this on the wrong
-- mode string ("withdraw") would leave the reported bug in place and break
-- this instead, which is why it is asserted next to the other two.
do
  local menu, input, save = open("move")
  eq(menu.boxIndex, 3, "the move screen opens on the current box")

  press(menu, input, "right")
  eq(menu.boxIndex, 4, "RIGHT walks to the next box")
  eq(menu:title(), "BOX4", "and the header follows")
  eq(#menu:list(), 1, "showing BOX4's one mon")

  press(menu, input, "left", "left", "left", "left")
  eq(menu.boxIndex, 0, "four LEFTs from BOX4 reach the PARTY, box 0")
  eq(menu:title(), "PARTY <PK><MN>", "BillsPC_BoxName's .party arm")
  eq(#menu:list(), 3, "and the list is the party")

  press(menu, input, "left")
  eq(menu.boxIndex, Boxes.NUM_BOXES,
    "LEFT off box 0 wraps to the last box (BillsPC_PressLeft)")
  press(menu, input, "right")
  eq(menu.boxIndex, 0, "and RIGHT wraps back through it")

  -- The insert cursor is the separate .Joypad2 arm, and it walks boxes too:
  -- choose the first party mon, MOVE, then drive the cursor to BOX1.
  press(menu, input, "a", "a")
  eq(menu.phase, "insert", "MOVE opens the insert cursor")
  press(menu, input, "right")
  eq(menu.boxIndex, 1, "RIGHT walks the insert cursor to BOX1")
  eq(menu:title(), "BOX1", "and the header names the destination")
  press(menu, input, "left")
  eq(menu.boxIndex, 0, "LEFT walks it back to the party")
  press(menu, input, "right", "a")
  eq(#save.party, 2, "A there really does move the mon")
  eq(Boxes.box(save, 1)[1].nickname, "CYNDAQUIL", "into the box it named")
end

S.finish()
