-- engine/menus/start_sub_menus.asm:330-345, home/window.asm:119-206
--   luajit tests/engine/bag_use_toss_hollow_cursor_2063.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }
package.loaded["src.core.Music"] = { playMap = function() end }
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
  soundOpts = function() return nil end,
}
package.loaded["src.ui.BagMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local Menu = require("src.ui.Menu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")

local Data = Fixtures.fresh()
Data.items.BICYCLE = { id = "BICYCLE", index = 6, name = "BICYCLE", price = 0,
                       keyItem = true }
Data.items.FIX_POTION = Data.items.FIX_POTION
  or { id = "FIX_POTION", index = 20, name = "FIX POTION", price = 300 }
local tmMove = next(Data.moves)
Data.items.FIX_TM = { id = "FIX_TM", index = 201, name = "TM01", price = 3000,
                      machine = { move = tmMove, kind = "TM" } }

local function freshGame()
  local game = {
    data = Data,
    save = {
      party = {},
      player = { name = "RED", id = 1 },
      inventory = {},
      options = {},
      flags = {},
      money = 0,
    },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = { pressed = nil }
  function game.input:wasPressed(b) return self.pressed == b end
  function game.input:isDown() return false end
  game.overworld = { map = { id = "FIX_TOWN", def = { tileset = "OVERWORLD" } },
                     player = { surfing = false } }
  Bag.add(game.save, "FIX_POTION", 3)
  Bag.add(game.save, "BICYCLE", 1)
  Bag.add(game.save, "FIX_TM", 1)
  return game
end

local function rowFor(list, pred)
  for i, r in ipairs(list.items) do
    if pred(r) then return i end
  end
  return nil
end

local function openOn(game, pred, opts)
  local list = BagMenu.new(game, opts or {})
  game.stack:push(list)
  local row = rowFor(list, pred)
  if not row then return nil end
  list.index = row
  return list
end

local function pressA(game, list)
  game.input.pressed = "a"
  list:update(1 / 60)
  game.input.pressed = nil
end

local function byId(id)
  return function(r) return r.value == id end
end
local isCancelRow = function(r) return r.cancel == true end

do
  local game = freshGame()
  local list = openOn(game, byId("FIX_POTION"))
  if check(list ~= nil, "the bag opened on an ordinary item") then
    check(list.hollowIndex == nil, "the row starts on the filled '▶'")
    local chosen = list.index
    pressA(game, list)
    check(getmetatable(game.stack:top()) == Menu, "the USE/TOSS box is up")
    eq(list.hollowIndex, chosen,
       "and the chosen row wears the hollow '▷' behind it")

    game.stack:pop()
    list:update(1 / 60)
    check(list.hollowIndex == nil,
          "the filled '▶' comes back once the list owns input again")
  end
end

do
  local game = freshGame()
  local list = openOn(game, byId("FIX_TM"))
  if check(list ~= nil, "the bag opened on the TM row") then
    check(list.index > 1, "which is not the first row")
    pressA(game, list)
    eq(list.hollowIndex, list.index, "the TM's own row goes hollow")
  end
end

-- CANCEL exits like B and never opens the box (home/list_menu.asm:105-110)
do
  local game = freshGame()
  local list = openOn(game, isCancelRow)
  if check(list ~= nil, "the bag opened on CANCEL") then
    pressA(game, list)
    check(list.hollowIndex == nil, "CANCEL leaves no hollow cursor behind")
    check(getmetatable(game.stack:top()) ~= Menu, "and opens no option box")
  end
end

-- the BICYCLE skips the box entirely (start_sub_menus.asm:340-342) #1705
do
  local game = freshGame()
  local list = openOn(game, byId("BICYCLE"))
  if check(list ~= nil, "the bag opened on the BICYCLE row") then
    pressA(game, list)
    check(list.hollowIndex == nil, "the bike's row keeps the filled '▶'")
    eq(game.save.onBike, true, "and the one press still mounted")
  end
end

-- the in-battle bag has no option box either (core.asm:2210-2234)
do
  local game = freshGame()
  local battle = { isBattle = true }
  local list = openOn(game, byId("FIX_TM"), { battle = battle })
  if check(list ~= nil, "the bag opened mid-battle") then
    pressA(game, list)
    check(list.hollowIndex == nil, "the in-battle row keeps the filled '▶'")
    check(getmetatable(game.stack:top()) ~= Menu, "and no USE/TOSS box appeared")
  end
end

-- ListMenu:update returns before the clear (parity_J, core.asm:2210)
do
  local game = freshGame()
  local ListMenu = require("src.ui.ListMenu")
  local list = ListMenu.new(game, "ITEMS", {
    { value = "POKE_BALL", label = "POKé BALL", count = 50 },
  }, { itemBox = true, script = function(l) l.hollowIndex = l.index end })
  game.stack:push(list)
  list:update(1 / 60)
  eq(list.hollowIndex, 1, "the scripted auto-A's hollow '▷' survives update")
end

package.loaded["src.core.Sound"] = nil
package.loaded["src.core.Music"] = nil
package.loaded["src.render.TextBox"] = nil
package.loaded["src.ui.BagMenu"] = nil
require("src.ui.Screens").invalidate()

T.finish()
