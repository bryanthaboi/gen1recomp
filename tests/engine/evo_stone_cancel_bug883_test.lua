-- A stone evolution started from the bag must not be cancelable (#883).
--
-- engine/items/item_effects.asm ItemUseEvoStone sets wForceEvolution before
-- `call TryEvolvingMon`, and engine/movie/evolution.asm
-- Evolution_CheckForCancel reads the joypad but throws the B press away while
-- that flag is set (#290).  So the B abort is a level-up/rare-candy behavior
-- only: a stone is removed from the bag the moment it is used, and an
-- evolution the player can cancel out of would eat the stone for nothing.
--
-- src/ui/EvolutionState.lua encodes the flag as `via`: cancelable is
-- (via ~= "TRADE" and via ~= "ITEM").  The bag's stone branch omitted the
-- argument entirely, so `via` arrived nil and the movie accepted B.  The
-- assertion here is on the value that reaches the screen, which is the only
-- thing standing between the two behaviors.
--
-- ROM-free: the fixture dataset plus a registry-supplied EvolutionState, so
-- the real Screens.push resolution runs and no sprite is ever loaded.
--   luajit tests/engine/evo_stone_cancel_bug883_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Lazily required inside the use branches; seeding package.loaded first keeps
-- the suite silent and free of a real Font atlas.
package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done, opts)
    return { textBox = true, text = text, done = done, opts = opts }
  end,
}
-- BagMenu and PartyMenu bind TextBox at require time, so they load against the
-- stub; Screens caches its factory per id and must be told to forget.
package.loaded["src.ui.BagMenu"] = nil
package.loaded["src.ui.PartyMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local PartyMenu = require("src.ui.PartyMenu")
local Screens = require("src.ui.Screens")
Screens.invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")
local Pokemon = require("src.pokemon.Pokemon")
local EvolutionState = require("src.ui.EvolutionState")

local Data = Fixtures.fresh()
-- The fixture item table carries no stone, and ItemEffects keys its stone
-- branch on the id; BagMenu only reads name/keyItem off the def.
Data.items.THUNDER_STONE = {
  id = "THUNDER_STONE", index = 33, name = "THUNDERSTONE", price = 2100,
  tossable = true,
}
-- and no fixture species evolves, so give A the stone evolution the branch
-- looks for (evo.method == "ITEM" and evo.item == the stone used).
Data.pokemon.FIXMON_A.evolutions = {
  { method = "ITEM", item = "THUNDER_STONE", species = "FIXMON_B" },
}

-- The seam: Screens resolves an id through game.data.screens before falling
-- back to the builtin module, which is the same path a mod-replaced screen
-- takes.  Recording the factory here catches exactly what Evolution.evolve
-- forwards, with no monkeypatching of Screens itself.
local pushed
Data.screens = Data.screens or {}
Data.screens.EvolutionState = function(game, mon, newSpecies, onDone, via)
  pushed = { game = game, mon = mon, newSpecies = newSpecies,
             onDone = onDone, via = via }
  return { evoRecorder = true }
end
Screens.invalidate()

local function freshGame()
  local mon = Pokemon.new(Data, "FIXMON_A", 20)
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
  Bag.add(game.save, "THUNDER_STONE", 1)
  return game, mon
end

local function isPicker(s) return getmetatable(s) == PartyMenu end

local function rowFor(list, id)
  for i, r in ipairs(list.items) do
    if r.value == id then return i end
  end
  return nil
end

-- Open the bag, put the cursor on the stone, choose it, take USE off the
-- USE/TOSS box, then press A on the party picker.
local function useStone(game)
  local list = BagMenu.new(game, {})
  game.stack:push(list)
  local row = rowFor(list, "THUNDER_STONE")
  if not row then return nil, "no THUNDER_STONE row in the bag" end
  list.index = row
  list.onChoose(list.items[row], list)
  local sub = game.stack:top()
  if sub and sub.items and sub.items[1] and sub.items[1].onSelect then
    game.stack:pop() -- the USE/TOSS Menu pops itself on select
    sub.items[1].onSelect()
  end
  local picker = game.stack:top()
  if not isPicker(picker) then return nil, "party picker never opened" end
  game.input.pressed = "a"
  picker:update(1 / 60)
  game.input.pressed = nil
  -- IsEvolvingText STAYS up; its onShown starts the DelayFrames 50 hold,
  -- which then pushes the movie over it (evos_moves.asm:120-134) (#1596)
  local intro = game.stack:top()
  if not (intro and intro.textBox and intro.opts and intro.opts.stay) then
    return nil, "the \"is evolving!\" box never opened"
  end
  if not tostring(intro.text):find("evolving") then
    return nil, "the box before the movie is not _IsEvolvingText"
  end
  intro.opts.stay.onShown()
  local hold = game.stack:top()
  for _ = 1, 60 do
    if pushed then break end
    if hold.update then hold.update() end
  end
  return list
end

do
  local game, mon = freshGame()
  local list, why = useStone(game)
  if check(list ~= nil, "the bag opened and reached the picker: " .. tostring(why)) then
    if check(pushed ~= nil, "the stone use pushed the evolution screen") then
      eq(pushed.newSpecies, "FIXMON_B", "and it is the stone's evolution")
      eq(pushed.mon, mon, "for the mon the stone was used on")
      eq(pushed.via, "ITEM",
         "the evolution runs as via = \"ITEM\" (wForceEvolution), which is "
         .. "what makes it non-cancelable (#883)")
    end
    eq(game.save.inventory.THUNDER_STONE, nil,
       "the stone is already gone by then, so a cancel would cost it for "
       .. "nothing")
  end
end

-- The value only matters because of what EvolutionState does with it, so
-- assert that half against the real constructor rather than trusting the
-- comment.  new() loads sprites through pcall and plays music through the
-- stubbed Sound, so it is safe headless.
do
  local game = freshGame()
  local mon = game.save.party[1]
  local stoneEvo = EvolutionState.new(game, mon, "FIXMON_B", nil, "ITEM")
  check(stoneEvo.cancelable == false,
        "EvolutionState refuses B for a stone evolution (evolution.asm "
        .. "Evolution_CheckForCancel with wForceEvolution set)")
  local levelEvo = EvolutionState.new(game, mon, "FIXMON_B", nil, "LEVEL")
  check(levelEvo.cancelable == true,
        "and still honours B for a level-up evolution, so the fix did not "
        .. "silently disable the cancel everywhere (#290, #213)")
end

T.finish()
