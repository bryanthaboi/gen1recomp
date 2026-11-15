-- ../pokecrystal/engine/events/pokecenter_pc.asm:568
-- ../pokecrystal/engine/items/switch_items.asm:1

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
love.timer = love.timer or { getTime = function() return 0 end }

local calls = {}
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  encode = function(text) return { string.byte(tostring(text), 1) or 0 } end,
  advanceOf = function() return 8 end,
  width = function(text) return #tostring(text) * 8 end,
}
package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
  resolve = function() return nil end,
  waitSfxDone = function() end,
}
package.loaded["src.ui.gen2.Chrome"] = nil
package.loaded["src.ui.gen2.ItemPcMenu"] = nil

local Chrome = require("src.ui.gen2.Chrome")
local ItemPcMenu = require("src.ui.gen2.ItemPcMenu")
local PcItems = require("src.core.gen2.PcItems")

local ITEMS = {
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 2,
    canToss = true },
  ANTIDOTE = { id = "ANTIDOTE", name = "ANTIDOTE", pocket = "ITEM", index = 9,
    canToss = true },
  SUPER_POTION = { id = "SUPER_POTION", name = "SUPER POTION", pocket = "ITEM",
    index = 15, canToss = true },
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

local function newPc(pcItems)
  local save = { player = { name = "GOLD" }, party = {}, inventory = {},
                 flags = {}, options = {}, pcItems = pcItems }
  local input = newInput()
  local game = {
    input = input,
    save = save,
    data = { audio = {}, pokemon = {}, items = ITEMS,
      text = require("tests.fixture_data.gen2_rom_text_s7_e") },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end },
  }
  return ItemPcMenu.new(game, { save = save, items = ITEMS }), input, save
end

local function press(screen, input, ...)
  for _, button in ipairs({ ... }) do
    input:press(button)
    screen:update(0)
  end
end

local function ids(rows)
  local out = {}
  for i = 1, #rows do out[i] = rows[i].id end
  return table.concat(out, ",")
end

-- ../pokecrystal/engine/events/pokecenter_pc.asm:655
do
  local save = { pcItems = { SUPER_POTION = 1, POTION = 1, ANTIDOTE = 1 } }
  local order = PcItems.order(save, ITEMS)
  eq(table.concat(order, ","), "POTION,ANTIDOTE,SUPER_POTION",
     "a save with no pcOrder builds one in item-index order")
  check(save.pcOrder == order, "and stores it on the save")

  save.pcItems.ANTIDOTE = nil
  save.pcItems.MOON_STONE = 1
  order = PcItems.order(save, ITEMS)
  eq(table.concat(order, ","), "POTION,SUPER_POTION,MOON_STONE",
     "a direct write to pcItems drops the gone id and appends the new one")
end

-- ../pokecrystal/engine/items/switch_items.asm:38, :64
do
  local save = { pcItems = { POTION = 1, ANTIDOTE = 1, SUPER_POTION = 1 } }
  check(PcItems.move(save, "POTION", 3, ITEMS), "POTION moves to slot 3")
  eq(table.concat(save.pcOrder, ","), "ANTIDOTE,SUPER_POTION,POTION",
     "the block between rotates up, the way .below memmoves it")
  check(PcItems.move(save, "POTION", 1, ITEMS), "and back to slot 1")
  eq(table.concat(save.pcOrder, ","), "POTION,ANTIDOTE,SUPER_POTION",
     ".above puts it back")
  eq(PcItems.move(save, "POTION", 1, ITEMS), false,
     "a same-slot drop is .trivial: no move")
  eq(PcItems.move(save, "MOON_STONE", 2, ITEMS), false,
     "an id the PC does not hold moves nothing")
end

-- ../pokecrystal/engine/events/pokecenter_pc.asm:604
do
  local pc, input, save = newPc({ POTION = 1, ANTIDOTE = 1, SUPER_POTION = 1 })
  press(pc, input, "a")
  eq(pc.phase, "withdraw", "WITHDRAW ITEM opens the list")
  eq(ids(pc.rows), "POTION,ANTIDOTE,SUPER_POTION", "in pcOrder")

  press(pc, input, "select")
  eq(pc.switching, 1, "SELECT arms wSwitchItem on the cursor row")
  press(pc, input, "down", "down")
  eq(pc.listIndex, 3, "the cursor still moves while an item is held")
  eq(pc.switching, 1, "and the held row does not change")
  press(pc, input, "a")
  eq(pc.switching, nil, ".a_select_2 drops it")
  eq(ids(pc.rows), "ANTIDOTE,SUPER_POTION,POTION", "the list rotated")
  eq(table.concat(save.pcOrder, ","), "ANTIDOTE,SUPER_POTION,POTION",
     "and the order rode back onto the save")

  press(pc, input, "b")
  eq(pc.phase, "menu", "B leaves the list")
  press(pc, input, "a")
  eq(ids(pc.rows), "ANTIDOTE,SUPER_POTION,POTION",
     "re-entering WITHDRAW keeps the player's order")
end

-- ../pokecrystal/engine/items/switch_items.asm:33
do
  local pc, input, save = newPc({ POTION = 1, ANTIDOTE = 1 })
  press(pc, input, "a", "select", "a")
  eq(pc.switching, nil, "the held item is put back down")
  eq(table.concat(save.pcOrder, ","), "POTION,ANTIDOTE", "with nothing moved")
  eq(pc.qtyState, nil, "and that A never fell through to the withdraw prompt")
end

-- ../pokecrystal/engine/events/pokecenter_pc.asm:615
do
  local pc, input, save = newPc({ POTION = 1, ANTIDOTE = 1 })
  press(pc, input, "a", "select", "down", "select")
  eq(table.concat(save.pcOrder, ","), "ANTIDOTE,POTION",
     "PAD_SELECT reaches .a_select_2 as well as PAD_A")

  press(pc, input, "select", "down", "b")
  eq(pc.switching, nil, ".b_2 zeroes wSwitchItem")
  eq(table.concat(save.pcOrder, ","), "ANTIDOTE,POTION", "and moves nothing")
end

-- ../pokecrystal/engine/items/switch_items.asm:12
do
  local pc, input, save = newPc({ POTION = 1, ANTIDOTE = 1 })
  press(pc, input, "a", "down", "down")
  eq(pc.listIndex, 3, "the cursor is on CANCEL")
  press(pc, input, "select")
  eq(pc.switching, nil, "SELECT on CANCEL arms nothing")

  press(pc, input, "up", "up", "select")
  eq(pc.switching, 1, "POTION is held")
  press(pc, input, "down", "down", "a")
  eq(pc.switching, 1, "dropping on the terminator is SwitchItemsInBag's `ret z`")
  eq(table.concat(save.pcOrder, ","), "POTION,ANTIDOTE", "so nothing moved")
end

-- ../pokecrystal/engine/events/pokecenter_pc.asm:569
do
  local pc, input = newPc({ POTION = 1, ANTIDOTE = 1 })
  press(pc, input, "a", "select")
  eq(pc.switching, 1, "held")
  pc.phase = "menu"
  press(pc, input, "down", "down", "a")
  eq(pc.phase, "toss", "TOSS ITEM opens the same list")
  eq(pc.switching, nil, "with wSwitchItem zeroed")
end

-- ../pokecrystal/home/menu.asm:50
do
  local pc, input = newPc({ POTION = 1, ANTIDOTE = 1 })
  press(pc, input, "a", "select", "down")
  calls = {}
  pc:drawList()
  local hollow, solid = false, false
  for _, c in ipairs(calls) do
    if c[1] == "code" and c[2] == Chrome.CURSOR_HOLLOW and c[4] == 2 * 8 then
      hollow = true
    end
    if c[1] == "code" and c[2] == Chrome.CURSOR and c[4] == 4 * 8 then
      solid = true
    end
  end
  check(hollow, "PlaceHollowCursor marks the picked-up row")
  check(solid, "and the solid cursor is on the row the item would land on")
end

package.loaded["src.render.Font"] = nil
package.loaded["src.core.Sound"] = nil
package.loaded["src.ui.gen2.Chrome"] = nil
package.loaded["src.ui.gen2.ItemPcMenu"] = nil

T.finish()
