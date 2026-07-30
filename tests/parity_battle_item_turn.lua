-- Parity test: using an item in battle spends the turn, medicine included
-- (#379).  pokered engine/items/item_effects.asm:1-3 zeroes
-- wActionResultOrTookBattleTurn to the success value before UseItem, and
-- ItemUseMedicine only clears it on its failure paths (:826 empty party,
-- :1241 .healingItemNoEffect), so a POTION that lands costs the turn the same
-- way a status cure does.  The party HP bar fill (.doneHealing / UpdateHPBar2
-- with the menu still up) is the field-only case (#252).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local ItemEffects = require("src.inventory.ItemEffects")
local S = require("tests.harness").suite("parity battle item turn")
local check, eq = S.check, S.eq

-- Real TextBoxes want a Font atlas, and the flow under test only cares that a
-- message opened and what its onDone does.  Restored at the bottom for the
-- suites run_tests.lua chains after this file.
local realTextBox = package.loaded["src.render.TextBox"]
local realBag = package.loaded["src.ui.BagMenu"]
local realParty = package.loaded["src.ui.PartyMenu"]
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
}
-- BagMenu and PartyMenu bind TextBox at require time, so they are reloaded
-- against the stub here and dropped again at the bottom
package.loaded["src.ui.BagMenu"] = nil
package.loaded["src.ui.PartyMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local PartyMenu = require("src.ui.PartyMenu")
-- src.ui.Screens caches its factory per id, so a suite that already opened a
-- PartyMenu would hand BagMenu the pre-reload class and the picker identity
-- check below would never match
require("src.ui.Screens").invalidate()

-- A stack that behaves like StateStack for the two things this flow reads:
-- top() identity (PartyMenu:close) and push/pop ordering.
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

local function freshGame(monHP, status)
  local lead = Pokemon.new(Data, "CHARIZARD", 50)
  lead.hp = monHP or 10
  lead.status = status
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
  local Bag = require("src.inventory.Bag")
  for _, id in ipairs({ "POTION", "SUPER_POTION", "ANTIDOTE" }) do
    Bag.add(game.save, id, 3)
  end
  return game, lead
end

local function isPicker(s) return getmetatable(s) == PartyMenu end
local function isBox(s) return type(s) == "table" and s.textBox == true end

local function inStack(stack, pred)
  for _, s in ipairs(stack.states) do
    if pred(s) then return true end
  end
  return false
end

-- TextBox pops itself BEFORE firing onDone, which is what PartyMenu:close's
-- identity check depends on.
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

-- Open the bag on `id`, choose it, then press A on the party picker.  Returns
-- the picker (nil when none opened) so the caller can inspect the fill.
local function useFromBag(game, battle, id)
  local list = BagMenu.new(game, { battle = battle })
  game.stack:push(list)
  local row = rowFor(list, id)
  if not row then return nil, "no " .. id .. " row in the bag" end
  list.index = row
  list.onChoose(list.items[row], list)
  -- out of battle the bag offers USE / TOSS first (start_sub_menus.asm)
  local sub = game.stack:top()
  if not battle and sub and sub.items and sub.items[1]
     and sub.items[1].onSelect then
    game.stack:pop()
    sub.items[1].onSelect()
  end
  local picker = game.stack:top()
  if not isPicker(picker) then return nil, "party picker never opened" end
  game.input.pressed = "a"
  picker:update(1 / 60)
  game.input.pressed = nil
  return picker
end

-- Pump the picker until its bar fill lands (it blocks input while it runs).
local function runFill(picker)
  for _ = 1, 400 do
    if not picker.heal then return true end
    picker:update(1 / 60)
  end
  return false
end

-- Count the turn: BattleState:itemUsed is the only path that queues the foe's
-- action plus end-of-turn, so wrapping it is the flag check.
local function watchTurn(battle)
  local rec = { itemUsed = 0, messages = {} }
  local real = battle.itemUsed
  battle.itemUsed = function(self, messages)
    rec.itemUsed = rec.itemUsed + 1
    return real(self, messages)
  end
  return rec
end

do
  check(ItemEffects.healsHP("POTION"), "POTION is an HP medicine")
  check(not ItemEffects.healsHP("ANTIDOTE"), "ANTIDOTE is a status cure")
end

-- The report: a POTION mid-battle healed for free.  BagMenu gated its
-- animate-the-bar branch on the picker existing, and in battle the picker is
-- non-nil (PartyMenu hands itself to onSwitch after popping), so the branch
-- swallowed the message, the itemUsed tail, and the turn.
do
  local game, lead = freshGame(10)
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  local rec = watchTurn(battle)
  local picker, why = useFromBag(game, battle, "POTION")
  check(picker ~= nil, "the picker opened for a POTION in battle: " .. tostring(why))
  if picker then
    eq(lead.hp, 30, "the POTION restored 20 HP")
    check(picker.heal == nil, "no party-menu bar fill in battle (#252 is field-only)")
    check(not inStack(game.stack, isPicker), "the picker is gone")
    local box = game.stack:top()
    check(isBox(box), "the restored-HP message opened (#379)")
    if isBox(box) then
      check(box.text:find("was restored", 1, true) ~= nil,
            "and it is the restored-HP line: " .. tostring(box.text))
      dismiss(game.stack, box)
    end
    eq(rec.itemUsed, 1, "a POTION in battle costs the turn (#379)")
    check(#battle.queue > 0, "and the foe's action is queued behind it")
  end
end

-- Same for the tier above it: the gate is per-item, so a SUPER POTION taking
-- the animate branch while a POTION does not would be the bug half-fixed.
do
  local game = freshGame(10)
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  local rec = watchTurn(battle)
  local picker = useFromBag(game, battle, "SUPER_POTION")
  if check(picker ~= nil, "the picker opened for a SUPER POTION") then
    local box = game.stack:top()
    check(isBox(box), "a SUPER POTION prints its message too")
    if isBox(box) then dismiss(game.stack, box) end
    eq(rec.itemUsed, 1, "a SUPER POTION in battle costs the turn (#379)")
  end
end

-- Control: status cures always spent the turn, and still must.
do
  local game, lead = freshGame(40, "PSN")
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  local rec = watchTurn(battle)
  local picker = useFromBag(game, battle, "ANTIDOTE")
  if check(picker ~= nil, "the picker opened for an ANTIDOTE") then
    check(lead.status == nil, "PSN was cured")
    local box = game.stack:top()
    if isBox(box) then dismiss(game.stack, box) end
    eq(rec.itemUsed, 1, "a status cure still costs the turn")
  end
end

-- .healingItemNoEffect (item_effects.asm:1241) clears the flag: a POTION on a
-- full-HP mon is refused and the turn is NOT spent.
do
  local game, lead = freshGame(nil)
  lead.hp = lead.stats.hp
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  local rec = watchTurn(battle)
  local picker = useFromBag(game, battle, "POTION")
  if check(picker ~= nil, "the picker opened for the refused POTION") then
    local box = game.stack:top()
    check(isBox(box) and box.text:find("won't have", 1, true) ~= nil,
          "the refusal prints \"It won't have any effect.\"")
    if isBox(box) then dismiss(game.stack, box) end
    eq(rec.itemUsed, 0, "a refused item does not cost the turn")
    eq(game.save.inventory.POTION, 3, "and the POTION is not consumed")
  end
end

-- Field regression guard for #252: out of battle the picker stays up and
-- animates, which is the behavior the #379 gate must not have taken away.
do
  local game, lead = freshGame(10)
  local picker = useFromBag(game, nil, "POTION")
  if check(picker ~= nil, "the field picker opened for a POTION") then
    check(picker.keepOpen == true, "keepOpen is set out of battle (#252)")
    check(inStack(game.stack, isPicker),
          "the party menu is still on the stack after the pick (#252)")
    check(type(picker.heal) == "table" and picker.heal.from == 10,
          "the bar fill started from the pre-heal HP")
    check(runFill(picker), "the fill lands")
    local box = game.stack:top()
    check(isBox(box), "then the message prints over the still-drawn menu")
    check(inStack(game.stack, isPicker), "...with the picker underneath it")
    if isBox(box) then
      dismiss(game.stack, box)
      check(not inStack(game.stack, isPicker),
            "dismissing the message closes the picker")
    end
    eq(lead.hp, 30, "and the field POTION healed the same 20 HP")
  end
end

package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.ui.BagMenu"] = realBag
package.loaded["src.ui.PartyMenu"] = realParty
require("src.ui.Screens").invalidate()
S.finish()
