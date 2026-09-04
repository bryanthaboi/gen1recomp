-- Parity test: using a RARE CANDY from the bag returns to the bag (#796).
--
-- pokered files RARE_CANDY under UsableItems_PartyMenu (data/items/
-- use_party.asm), so after UseItem runs, start_sub_menus.asm's
-- .useItem_partyMenu jumps back to StartMenu_Item with wBagSavedMenuItem
-- still pointing at the candy -- the level text, PrintStatsBox, the
-- level-up moves and any level evolution all happen first, then the item
-- list is back with the cursor on the candy, which is what lets the
-- original button-mash through a stack of them.  The port closed the bag
-- list before the level-up sequence and never reopened it, so every candy
-- cost a full START -> ITEM trip.
--
-- Self-contained; run via `luajit tests/parity_rare_candy_menu.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity rare candy menu")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
Data:load()

local Pokemon = require("src.pokemon.Pokemon")
local Bag = require("src.inventory.Bag")

-- Real TextBoxes want a Font atlas; the flow under test only cares which
-- states land on the stack and what each onDone does.  BagMenu binds
-- TextBox at require time, so it is reloaded against the stub here and
-- dropped again at the bottom.
local realTextBox = package.loaded["src.render.TextBox"]
local realBag = package.loaded["src.ui.BagMenu"]
local realParty = package.loaded["src.ui.PartyMenu"]
-- soundOpts only builds an opts table, so the real one runs against the stub.
local soundOpts = require("src.render.TextBox").soundOpts
local strip = require("src.render.TextBox").strip
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
  soundOpts = soundOpts,
  strip = strip,
}
package.loaded["src.ui.BagMenu"] = nil
package.loaded["src.ui.PartyMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local PartyMenu = require("src.ui.PartyMenu")
require("src.ui.Screens").invalidate()

-- A stack that behaves like StateStack for the two things this flow reads:
-- top() identity (ListMenu:close) and push/pop ordering.
local function newStack()
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

-- One button per call: PartyMenu:update reads game.input once per fixed step.
local function newInput()
  local input = { pressed = nil }
  function input:wasPressed(b) return self.pressed == b end
  return input
end

-- CHARIZARD learns nothing at level 51 and has no evolution left, so a
-- candy on it ends after the stat window -- no MoveLearnMenu, no
-- EvolutionState clouding which state the stack returns to.
local function freshGame(candies)
  local lead = Pokemon.new(Data, "CHARIZARD", 50)
  local game = {
    data = Data,
    stack = newStack(),
    input = newInput(),
    save = {
      party = { lead },
      player = { name = "RED" },
      inventory = {},
      options = { battleStyle = "set", battleAnim = "on" },
      pokedex = { seen = {}, owned = {} },
      flags = {},
      money = 0,
    },
  }
  Bag.add(game.save, "RARE_CANDY", candies or 3)
  return game, lead
end

local function isPicker(s) return getmetatable(s) == PartyMenu end
local function isBox(s) return type(s) == "table" and s.textBox == true end

-- TextBox pops itself BEFORE firing onDone.
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

-- From an already-open bag list: choose the candy, take USE off the
-- submenu, press A on the party picker.  Returns the level-up text box.
local function useCandy(game, list)
  local row = rowFor(list, "RARE_CANDY")
  if not row then return nil, "no RARE CANDY row in the bag" end
  list.index = row
  list.onChoose(list.items[row], list)
  -- out of battle the bag offers USE / TOSS first (start_sub_menus.asm)
  local sub = game.stack:top()
  if sub and sub.items and sub.items[1] and sub.items[1].onSelect then
    game.stack:pop()
    sub.items[1].onSelect()
  end
  local picker = game.stack:top()
  if not isPicker(picker) then return nil, "party picker never opened" end
  game.input.pressed = "a"
  picker:update(1 / 60)
  game.input.pressed = nil
  return game.stack:top()
end

-- engine/menus/start_sub_menus.asm:414-416
local function isFlash(s)
  return type(s) == "table" and s.t ~= nil and s.frames ~= nil
end

local function drainFlash(game)
  local top = game.stack:top()
  if not isFlash(top) then return false end
  local n = 0
  while game.stack:top() == top and n < 240 do
    top:update(1 / 60)
    n = n + 1
  end
  return true
end

-- Walk the rest of the level-up sequence: dismiss the level text, then A
-- through the stat window (PrintStatsBox).
local function finishLevelUp(game, box)
  dismiss(game.stack, box)
  local top = game.stack:top()
  if isBox(top) then return end -- a "learned MOVE" line, dismissed by caller
  if top and top.update then
    game.input.pressed = "a"
    top:update(1 / 60)
    game.input.pressed = nil
  end
  return drainFlash(game)
end

-- ---- the report: one candy closed the whole menu -------------------------
do
  local game, lead = freshGame(3)
  local list = BagMenu.new(game, {})
  game.stack:push(list)
  local row = rowFor(list, "RARE_CANDY")
  check(row ~= nil, "the candy is in the bag")

  local box = useCandy(game, list)
  check(isBox(box), "the level text opened")
  eq(lead.level, 51, "the candy leveled the mon")
  eq(game.save.inventory.RARE_CANDY, 2, "the candy was consumed")
  check(game.stack.states[1] == list,
        "the bag list is STILL on the stack under the level text (#796)")
  -- .useRareCandy redraws the party menu before it prints
  -- (item_effects.asm:1392-1418) #1594
  check(isPicker(game.stack.states[2]),
        "the party picker is the backdrop for the level text (#1594)")
  -- (pokered engine/items/item_effects.asm:1392-1394)
  local picker = game.stack.states[2]
  local levelLine = box.text:gsub("{DONE}%s*$", ""):gsub("{PROMPT}%s*$", "")
  eq(picker:bottomMessage(), levelLine,
     "the party menu's bottom box holds the level text, not the item prompt (#2161)")
  dismiss(game.stack, box)
  check(not isPicker(game.stack:top()),
        "PrintStatsBox is up over the party menu")
  eq(picker:bottomMessage(), levelLine,
     "and it survives into PrintStatsBox (item_effects.asm:1403-1404)")
  game.input.pressed = "a"
  game.stack:top():update(1 / 60)
  game.input.pressed = nil
  check(drainFlash(game),
        "the bag return whites out (start_sub_menus.asm:414-416) #2125")
  for _, s in ipairs(game.stack.states) do
    check(not isPicker(s), "the picker comes down when the sequence ends")
  end
  eq(game.stack:top(), list,
     "after the stat window the bag is back on top (StartMenu_Item)")
  eq(list.index, row, "the cursor is still on the RARE CANDY row")
  eq(list.items[row] and list.items[row].count, 2,
     "the count refreshed in place")

  -- the point of the original's behavior: a second candy needs no menu trip
  local box2 = useCandy(game, list)
  check(isBox(box2), "a second candy fires from the still-open bag")
  eq(lead.level, 52, "and it levels the mon again")
  finishLevelUp(game, box2)
  eq(game.stack:top(), list, "still on the bag after the second candy")
  eq(game.save.inventory.RARE_CANDY, 1, "two candies spent")
end

-- ---- the last candy: the row empties but the bag still stays up ----------
do
  local game = freshGame(1)
  local list = BagMenu.new(game, {})
  game.stack:push(list)
  local box = useCandy(game, list)
  check(isBox(box), "the last candy levels too")
  finishLevelUp(game, box)
  eq(game.stack:top(), list, "the bag stays open after the last candy")
  eq(#list.items, 1, "the emptied row left the list, leaving only CANCEL")
  eq(game.save.inventory.RARE_CANDY, nil, "no candies left in the inventory")
end

package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.ui.BagMenu"] = realBag
package.loaded["src.ui.PartyMenu"] = realParty
require("src.ui.Screens").invalidate()
S.finish()
