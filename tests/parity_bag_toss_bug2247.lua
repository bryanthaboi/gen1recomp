-- engine/menus/start_sub_menus.asm:330-362, 424-439;
-- engine/items/item_effects.asm:2547-2595
-- Self-contained; run via `luajit tests/parity_bag_toss_bug2247.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity bag toss #2247")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
Data:load()

local Bag = require("src.inventory.Bag")
local Timing = require("src.core.Timing")

local realTextBox = package.loaded["src.render.TextBox"]
local realBag = package.loaded["src.ui.BagMenu"]
local soundOpts = require("src.render.TextBox").soundOpts
local strip = require("src.render.TextBox").strip
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done, opts)
    return { textBox = true, text = text, done = done, opts = opts }
  end,
  soundOpts = soundOpts,
  strip = strip,
}
package.loaded["src.ui.BagMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local Menu = require("src.ui.Menu")
local QuantityBox = require("src.ui.QuantityBox")
local ChoiceBox = require("src.ui.ChoiceBox")
require("src.ui.Screens").invalidate()

local function newStack()
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

local function newInput()
  local input = { pressed = nil }
  function input:wasPressed(b) return self.pressed == b end
  return input
end

local function freshGame(id, n)
  local game = {
    data = Data,
    stack = newStack(),
    input = newInput(),
    save = {
      party = {},
      player = { name = "RED" },
      inventory = {},
      options = {},
      pokedex = { seen = {}, owned = {} },
      flags = {},
      money = 0,
    },
  }
  Bag.add(game.save, id, n)
  return game
end

local function isBox(s) return type(s) == "table" and s.textBox == true end
local function is(s, class) return getmetatable(s) == class end

local function press(game, state, btn)
  game.input.pressed = btn
  state:update(1 / 60)
  game.input.pressed = nil
end

local function dismiss(stack, box)
  if stack:top() == box then stack:pop() end
  if box.done then box.done() end
end

local function rowFor(list, id)
  for i, r in ipairs(list.items) do
    if r.value == id then return i end
  end
  return nil
end

local function names(stack)
  local out = {}
  for _, s in ipairs(stack.states) do
    out[#out + 1] = is(s, Menu) and "Menu" or is(s, QuantityBox) and "QuantityBox"
      or is(s, ChoiceBox) and "ChoiceBox" or isBox(s) and "TextBox"
      or (s.items and "ListMenu") or "?"
  end
  return table.concat(out, ",")
end

local function chooseToss(game, id)
  local list = BagMenu.new(game, {})
  game.stack:push(list)
  local row = rowFor(list, id)
  list.index = row
  list.onChoose(list.items[row], list)
  local sub = game.stack:top()
  check(is(sub, Menu), "USE/TOSS menu opened")
  sub.noSound = true
  sub.index = 2
  eq(sub.items[2].label, "TOSS", "row 2 is TOSS")
  press(game, sub, "a")
  return list, row, sub
end

local function answer(game, choice, btn)
  press(game, choice, btn)
  for _ = 1, Timing.YES_NO_ANSWER + 1 do
    if game.stack:top() ~= choice then break end
    choice:update(1 / 60)
  end
  check(game.stack:top() ~= choice, "the YES/NO box came down after the hold")
end

do
  local game = freshGame("GREAT_BALL", 14)
  local list, row, sub = chooseToss(game, "GREAT_BALL")
  -- start_sub_menus.asm:362
  eq(names(game.stack), "ListMenu,Menu,QuantityBox",
     "TOSS keeps the USE/TOSS menu up under the quantity box")
  eq(sub.hollowIndex, 2, "TOSS row keeps the hollow cursor")

  local qbox = game.stack:top()
  press(game, qbox, "a")
  eq(names(game.stack), "ListMenu,Menu,QuantityBox,TextBox",
     "A on the quantity box prints over the kept boxes")
  local ask = game.stack:top()
  check(ask.text:find("^Is it OK to toss") ~= nil, "it is the IsItOKToTossItemText")
  check(ask.text:find("GREAT BALL", 1, true) ~= nil, "naming the item")
  check(ask.text:find("{RAM:", 1, true) == nil, "wStringBuffer is filled in")
  check(ask.opts and ask.opts.stay and ask.opts.stay.prompt == true,
        "it is a prompt the box stays up under")
  eq(game.save.inventory.GREAT_BALL, 14, "nothing removed yet")

  ask.opts.stay.onShown()
  eq(names(game.stack), "ListMenu,Menu,QuantityBox,TextBox,ChoiceBox",
     "YES/NO only after A on the prompt")
  eq(game.save.inventory.GREAT_BALL, 14, "still nothing removed")

  answer(game, game.stack:top(), "a")
  eq(game.save.inventory.GREAT_BALL, 13, "YES removes the item")
  eq(list.items[row].count, 14, "but the list row still shows the old count")
  eq(names(game.stack), "ListMenu,Menu,QuantityBox,TextBox",
     "Threw away prints over the kept quantity box and menu")
  local threw = game.stack:top()
  check(threw.text:find("^Threw away") ~= nil, "it is ThrewAwayItemText")

  dismiss(game.stack, threw)
  eq(names(game.stack), "ListMenu", "ItemMenuLoop: every box is gone")
  eq(list.items[row].count, 13, "and the list is redrawn with the new count")
  eq(list.index, row, "cursor still on the row")
end

do
  local game = freshGame("GREAT_BALL", 14)
  local list, row = chooseToss(game, "GREAT_BALL")
  press(game, game.stack:top(), "b")
  eq(names(game.stack), "ListMenu", "B drops the quantity box and the menu")
  eq(game.save.inventory.GREAT_BALL, 14, "inventory intact")
  eq(list.items[row].count, 14, "list intact")
end

do
  local game = freshGame("GREAT_BALL", 14)
  local list, row = chooseToss(game, "GREAT_BALL")
  press(game, game.stack:top(), "a")
  game.stack:top().opts.stay.onShown()
  answer(game, game.stack:top(), "b")
  eq(names(game.stack), "ListMenu", "NO drops the prompt, quantity box and menu")
  eq(game.save.inventory.GREAT_BALL, 14, "inventory intact")
  eq(list.items[row].count, 14, "list intact")
end

do
  local game = freshGame("TOWN_MAP", 1)
  local list, row = chooseToss(game, "TOWN_MAP")
  eq(names(game.stack), "ListMenu,Menu,TextBox",
     "the refusal prints over the kept USE/TOSS menu")
  local msg = game.stack:top()
  check(msg.text:find("too impor", 1, true) ~= nil, "it is TooImportantToTossText")
  dismiss(game.stack, msg)
  eq(names(game.stack), "ListMenu", "and dismissing it drops the menu too")
  eq(game.save.inventory.TOWN_MAP, 1, "inventory intact")
  eq(list.items[row].value, "TOWN_MAP", "list intact")
end

package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.ui.BagMenu"] = realBag
require("src.ui.Screens").invalidate()
S.finish()
