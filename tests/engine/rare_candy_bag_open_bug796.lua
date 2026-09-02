-- A RARE CANDY used from the field bag must leave the bag open (#796).
--
-- engine/menus/start_sub_menus.asm, StartMenu_Item / .useOrTossItem sorts the
-- chosen item with IsInArray against UsableItems_CloseMenu first and
-- UsableItems_PartyMenu second.  RARE_CANDY is in the party-menu array
-- (data/items/use_party.asm), so it reaches .useItem_partyMenu, which after
-- `call UseItem` -- when wActionResultOrTookBattleTurn is not $02 --
-- restores the screen and `jp StartMenu_Item`, i.e. re-enters the item list
-- instead of CloseStartMenu.  StartMenu_Item reloads wBagSavedMenuItem into
-- wCurrentMenuItem before DisplayListMenuID, so the cursor comes back on the
-- row you just used: that is what lets a stack of candies be mashed through.
-- engine/items/item_effects.asm ItemUseVitamin .useRareCandy ends with
-- RedrawPartyMenu / PrintStatsBox / WaitForTextScrollButtonPress /
-- LearnMoveFromLevelUp / TryEvolvingMon and `jp RemoveUsedItem` -- it never
-- whites out and never closes the start menu.  Only .useItem_closeMenu items
-- (UsableItems_CloseMenu: bike, escape rope, rods) jump to CloseStartMenu.
--
-- The port popped the bag ListMenu at the head of the leveledTo branch, which
-- also skipped the "xN" refresh below it, so the level text played over the
-- overworld and the player was dumped out of the menu per candy.
--   luajit tests/engine/rare_candy_bag_open_bug796.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq, same = T.check, T.eq, T.same
love = love or require("tests.love_stub")

-- Lazily-required inside the use branches, so seeding package.loaded before
-- the UI modules load is enough to keep the suite silent and love-free.
package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
}
-- Real TextBoxes want a Font atlas.  This flow only cares that a message
-- opened, what it says, and what its onDone does.
local jingles = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
  soundOpts = function(_, sound, opts)
    jingles[#jingles + 1] = sound
    opts = opts or {}
    opts.auto = { sound = sound, wait = true }
    return opts
  end,
}
-- BagMenu and PartyMenu bind TextBox at require time, so they load against
-- the stub; Screens caches its factory per id and must be told to forget.
package.loaded["src.ui.BagMenu"] = nil
package.loaded["src.ui.PartyMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local PartyMenu = require("src.ui.PartyMenu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")
local Pokemon = require("src.pokemon.Pokemon")

local Data = Fixtures.fresh()
-- The fixture item table has no candy of its own; ItemEffects keys the
-- level-up branch on the id, and BagMenu only reads name/keyItem off the def.
Data.items.RARE_CANDY = {
  id = "RARE_CANDY", index = 90, name = "RARE CANDY", price = 4800,
  tossable = true,
}

-- The mon: FIXMON_C has an empty `evolutions` and a learnset that stops at
-- level 1, so the 5 -> 6 candy prints its line and nothing else follows it.
-- That keeps the assertions on the bag rather than on the stat box, which
-- would need real graphics.
local function freshGame(candies)
  local mon = Pokemon.new(Data, "FIXMON_C", 5)
  local game = {
    data = Data,
    save = {
      party = { mon },
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
  -- one button edge per update, the way Input reports a fixed step
  game.input = { pressed = nil }
  function game.input:wasPressed(b) return self.pressed == b end
  -- FIX POTION first so the candy is never row 1: an index that silently
  -- reset to the top would otherwise pass the cursor assertion by accident
  Bag.add(game.save, "FIX_POTION", 1)
  Bag.add(game.save, "RARE_CANDY", candies)
  return game, mon
end

local function isPicker(s) return getmetatable(s) == PartyMenu end
local function isBox(s) return type(s) == "table" and s.textBox == true end

local function inStack(stack, pred)
  for _, s in ipairs(stack.states) do
    if pred(s) then return true end
  end
  return false
end

local function rowFor(list, id)
  for i, r in ipairs(list.items) do
    if r.value == id then return i end
  end
  return nil
end

-- Open the bag, put the cursor on `id`, choose it, take USE off the
-- USE/TOSS box, then press A on the party picker.  Returns the bag list.
local function useFromBag(game, battle, id)
  local list = BagMenu.new(game, { battle = battle })
  game.stack:push(list)
  local row = rowFor(list, id)
  if not row then return nil, "no " .. id .. " row in the bag" end
  list.index = row
  list.onChoose(list.items[row], list)
  local sub = game.stack:top()
  if not battle and sub and sub.items and sub.items[1]
     and sub.items[1].onSelect then
    game.stack:pop() -- the USE/TOSS Menu pops itself on select
    sub.items[1].onSelect()
  end
  local picker = game.stack:top()
  if not isPicker(picker) then return nil, "party picker never opened" end
  game.input.pressed = "a"
  picker:update(1 / 60)
  game.input.pressed = nil
  return list
end

-- The bug: three candies in the bag, use one in the field.
do
  local game, mon = freshGame(3)
  jingles = {}
  local list, why = useFromBag(game, nil, "RARE_CANDY")
  if check(list ~= nil, "the bag opened and reached the picker: " .. tostring(why)) then
    eq(mon.level, 6, "the candy leveled the mon 5 -> 6")
    -- .useRareCandy over the party list (item_effects.asm:1392-1418) #1594
    check(inStack(game.stack, isPicker),
          "the party picker is still up under the level text (#1594)")
    check(inStack(game.stack, function(s) return s == list end),
          "the bag list is STILL on the stack (.useItem_partyMenu re-enters "
          .. "StartMenu_Item, it does not CloseStartMenu) (#796)")

    local row = rowFor(list, "RARE_CANDY")
    if check(row ~= nil, "the RARE CANDY row survived the use") then
      eq(list.items[row].count, 2, "and its count followed the inventory")
      eq(list.index, row, "with the cursor left on it (wBagSavedMenuItem), "
                          .. "so the next candy is one A press away")
    end
    eq(game.save.inventory.RARE_CANDY, 2, "one candy was consumed")

    local box = game.stack:top()
    if check(isBox(box), "the grew-to-level line prints over the open bag") then
      check(box.text:find("level 6", 1, true) ~= nil,
            "and it names the new level: " .. tostring(box.text))
    end
    -- RareCandyText: text_far, sound_get_item_1, text_promptbutton
    -- (engine/menus/party_menu.asm:289-293)
    same(jingles, { "Get_Item1" },
         "the level-up line carries sound_get_item_1 and nothing else")
  end
end

-- .useRareCandy: TryEvolvingMon runs over the party list
-- (item_effects.asm:1392-1418) (#1594)
do
  local evolveCalls = {}
  package.loaded["src.pokemon.Evolution"] = {
    pendingFor = function() return "FIXMON_B", { method = "LEVEL" } end,
    evolve = function(_, _, to, onDone, via)
      evolveCalls[#evolveCalls + 1] = { to = to, onDone = onDone, via = via }
    end,
  }
  package.loaded["src.battle.BattleState"] = {
    StatBox = { new = function(_, _, cb, keepOpen)
      return { statBox = true, cb = cb, keepOpen = keepOpen }
    end },
  }
  local game = freshGame(3)
  local list = useFromBag(game, nil, "RARE_CANDY")
  if check(list ~= nil, "the bag reached the picker (evolution case)") then
    local box = game.stack:top()
    check(isBox(box), "the level line prints first")
    game.stack:pop() -- a real TextBox pops itself before onDone
    box.done()
    local stat = game.stack:top()
    if check(stat and stat.statBox, "then the stat window") then
      -- ../pokered/engine/pokemon/evos_moves.asm:126-128
      eq(stat.keepOpen, true,
         "which stays up: nothing wipes rows 0-11 until ClearScreenArea, "
         .. "inside TryEvolvingMon and 50 frames after 'is evolving!'")
      stat.cb()
      eq(#evolveCalls, 1, "the pending evolution starts")
      check(inStack(game.stack, function(s) return s == stat end),
            "with the stat window STILL up under the evolution movie")
      check(inStack(game.stack, isPicker),
            "with the party picker STILL up: the evolution prints over it, "
            .. "not over the bag list (#1594)")
      check(type(evolveCalls[1].onDone) == "function",
            "closePicker rides the evolution's completion callback")
      evolveCalls[1].onDone()
      check(not inStack(game.stack, function(s) return s == stat end),
            "and the stat window comes down with the picker")
      check(not inStack(game.stack, isPicker),
            "and the picker comes down once the evolution flow completes")
      check(inStack(game.stack, function(s) return s == list end),
            "while the bag list survives (#796)")
    end
  end
  package.loaded["src.pokemon.Evolution"] = nil
  package.loaded["src.battle.BattleState"] = nil
end

-- The last candy: the row goes away (RemoveUsedItem empties the slot) and the
-- cursor clamps to a real row -- but the list itself still must not close.
do
  local game = freshGame(1)
  local list = useFromBag(game, nil, "RARE_CANDY")
  if check(list ~= nil, "the bag reached the picker with a single candy") then
    check(inStack(game.stack, function(s) return s == list end),
          "the last candy does not close the bag either (#796)")
    check(rowFor(list, "RARE_CANDY") == nil, "its row was removed")
    eq(game.save.inventory.RARE_CANDY, nil, "and the slot is empty")
    check(list.index >= 1 and list.index <= #list.items,
          "the cursor clamped to a valid row (index " .. tostring(list.index)
          .. " of " .. #list.items .. ")")
  end
end

-- Boundary the fix must not have moved: a candy is refused mid-battle, so the
-- field behavior above can never be mistaken for a battle regression.
-- item_effects.asm:800-803, ItemUseVitamin reads wIsInBattle and
-- `jp nz, ItemUseNotTime` before it ever falls into ItemUseMedicine, which is
-- why the port's battle-side branch is a guard rather than a live path.  A
-- bare table stands in for the battle: nothing on this route reads it.
do
  local game, mon = freshGame(3)
  local list = useFromBag(game, { fakeBattle = true }, "RARE_CANDY")
  if check(list ~= nil, "the battle bag reached the picker") then
    eq(mon.level, 5, "a RARE CANDY mid-battle levels nothing (ItemUseVitamin "
                     .. "-> ItemUseNotTime)")
    eq(game.save.inventory.RARE_CANDY, 3, "and is not consumed")
    local box = game.stack:top()
    if check(isBox(box), "the refusal prints") then
      check(box.text:find("time to use", 1, true) ~= nil,
            "with ItemUseNotTime's line: " .. tostring(box.text))
    end
  end
end

T.finish()
