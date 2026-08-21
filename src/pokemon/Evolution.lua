-- Evolution handling (engine/pokemon/evos_moves.asm semantics):
-- level evolutions trigger after battles once the level is reached,
-- stone evolutions on item use, and trade evolutions when a link trade
-- completes (src/link/Protocol.lua TradeSession:apply).
--
-- Method dispatch runs through the merged evolution_methods registry:
-- a record's check(game, mon, evo, trigger) answers whether that
-- evolutions[] row fires for the trigger ({ kind = "levelup" | "item" |
-- "trade" | "manual" | <mod>, item = id?, ... }), wrapped by the
-- evolution.check hook so a mod can cancel or force any evolution.

local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Stats = require("src.pokemon.Stats")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")
local romText = require("src.core.RomText")

local Evolution = {}

-- engine/pokemon/evos_moves.asm:122-123 (ld c, 50 / call DelayFrames)
local EVOLVING_TEXT_FRAMES = 50

Evolution.METHODS = {
  LEVEL = {
    check = function(game, mon, evo, trigger)
      return trigger.kind == "levelup" and mon.level >= (evo.level or 0)
    end,
    describe = function(evo)
      return Strings("Level %d", evo.level or 0)
    end,
  },
  ITEM = {
    check = function(game, mon, evo, trigger)
      return trigger.kind == "item" and trigger.item == evo.item
    end,
    describe = function(evo, data)
      return (data and data.items[evo.item] or {}).name or evo.item
    end,
    consumesItem = true,
  },
  TRADE = {
    check = function(game, mon, evo, trigger)
      return trigger.kind == "trade"
    end,
    describe = function() return "Trade" end,
  },
}

function Evolution.registerInto(registry, _, owner)
  for id, record in pairs(Evolution.METHODS) do
    registry:register(id, record, owner)
  end
end

-- Single dispatch point over the merged registry, wrapped by the
-- evolution.check hook.  Returns species, evo for the first matching
-- evolutions[] row, or nil.
function Evolution.pendingFor(game, mon, trigger)
  trigger = trigger or { kind = "manual" }
  local data = game.data
  local def = data.pokemon[mon.species]
  local methods = data.evolution_methods or Evolution.METHODS
  for _, evo in ipairs(def.evolutions or {}) do
    local method = methods[evo.method]
    if method and method.check then
      local should
      if Runtime.wantsHook("evolution.check") then
        should = Runtime.call("evolution.check", function(g, m, e, t)
          return method.check(g, m, e, t)
        end, game, mon, evo, trigger)
      else
        should = method.check(game, mon, evo, trigger)
      end
      if should then return evo.species, evo end
    end
  end
  return nil
end

-- Find a pending level evolution for a mon (nil if none).  Frozen v1
-- shim: callers pass a plain data table, so it stays a hookless LEVEL
-- check; game-holding callers use pendingFor.
function Evolution.pendingLevelEvo(data, mon)
  local def = data.pokemon[mon.species]
  for _, evo in ipairs(def.evolutions) do
    if evo.method == "LEVEL" and mon.level >= evo.level then
      return evo.species
    end
  end
  return nil
end

-- Mutate the mon into the new species (stats, HP delta, dex flags).
-- via is the evolution method id when the caller knows it.
function Evolution.apply(game, mon, newSpecies, via)
  local newDef = game.data.pokemon[newSpecies]
  assert(newDef, "evolve into unknown species " .. tostring(newSpecies))
  local fromSpecies = mon.species
  local hpLost = mon.stats.hp - mon.hp
  mon.species = newSpecies
  mon.stats = Stats.calc(newDef, mon.level, mon.dvs, mon.statExp)
  mon.hp = math.max(1, mon.stats.hp - hpLost)
  if game.save.pokedex then
    game.save.pokedex.seen[newSpecies] = true
    game.save.pokedex.owned[newSpecies] = true
  end
  Runtime.emit("pokemon.evolved", {
    mon = mon, fromSpecies = fromSpecies, toSpecies = newSpecies, via = via,
  })
end

-- After the "evolved into" text, Gen1 re-runs the level-up learn check on
-- the EVOLVED species (engine/pokemon/evos_moves.asm EvolveMon calls the
-- LearnMoveFromLevelUp predef, engine/pokemon/learn_move.asm) -- a mon
-- evolving at exactly a learnset level gains that move (GYARADOS learns
-- BITE at 20, so MAGIKARP->GYARADOS @20 learns BITE, @21 does not) (#12).
-- Mirrors the rare-candy learn loop in src/ui/BagMenu.lua so a full move
-- list opens the forget prompt.  mon.species is already the new species
-- (Evolution.apply ran before the congrats text).  onDone runs once the
-- learn list is exhausted, replacing the caller's direct onDone.
function Evolution.learnEvolutionMoves(game, mon, onDone)
  local Experience = require("src.battle.Experience")
  local def = game.data.pokemon[mon.species]
  -- movesLearnedAt uses entry.level == level (exact Gen1 rule); do NOT use
  -- Pokemon.movesAtLevel (<= level), which would over-grant older moves.
  local moves = Experience.movesLearnedAt(def, mon.level)
  local i = 0
  local function nextStep()
    i = i + 1
    local moveId = moves[i]
    if not moveId then
      if onDone then onDone() end
      return
    end
    for _, mv in ipairs(mon.moves) do
      if mv.id == moveId then return nextStep() end
    end
    local mdef = game.data.moves[moveId]
    if not mdef then return nextStep() end
    local name = mon.nickname or def.name
    if #mon.moves < 4 then
      table.insert(mon.moves, { id = moveId, pp = mdef.pp })
      Runtime.emit("pokemon.move_learned", { mon = mon, moveId = moveId })
      -- LearnedMove1Text: text_far, sound_get_item_1, text_promptbutton
      -- (learn_move.asm), so the jingle rides the box
      game.stack:push(TextBox.new(game,
        romText(game.data, "_LearnedMove1Text",
          "%s learned\n%s!", name, mdef.name), nextStep,
        TextBox.soundOpts(game, "Get_Item1")))
    else
      -- LearnMoveFromLevelUp with a full moveset: the forget UI
      Screens.push(game, "MoveLearnMenu", mon, moveId, nextStep)
    end
  end
  nextStep()
end

-- Play the evolution movie (flashing forms), then apply + text.
-- Headless (no real graphics) falls back to the plain text flow.
function Evolution.evolve(game, mon, newSpecies, onDone, via)
  local oldName = mon.nickname or game.data.pokemon[mon.species].name
  -- IsEvolvingText, DelayFrames 50; ClearScreenArea then wipes rows 0-11
  -- ONLY, so the box rides through EvolveMon (evos_moves.asm:120-134)
  local isEvolving = romText(game.data, "_IsEvolvingText",
    "What?\n%s is\nevolving!", oldName)
  if love.image and love.image.newImageData then
    local intro
    intro = TextBox.new(game, isEvolving, nil, { stay = {
      onShown = function()
        -- DelayFrames 50 with the box and the old screen still up
        -- (evos_moves.asm:122-123)
        local hold = { t = 0 }
        hold.update = function()
          hold.t = hold.t + 1
          if hold.t < EVOLVING_TEXT_FRAMES then return end
          game.stack:pop() -- this hold
          -- forward `via` so trade evolutions stay non-cancelable while
          -- others accept B (evos_moves.asm:72-75) (#213)
          Screens.push(game, "EvolutionState", mon, newSpecies, function()
            -- the result/cancel box owns the intro box's pop (#1596)
            if game.stack:top() == intro then game.stack:pop() end
            if onDone then onDone() end
          end, via)
        end
        hold.draw = function() end
        game.stack:push(hold)
      end,
    } })
    game.stack:push(intro)
    return
  end
  Music.play(game.data, Music.special(game.data, "evolution"))
  Evolution.apply(game, mon, newSpecies, via)
  -- EvolvedText then IntoText in the same box (evos_moves.asm:136-150)
  local msg = isEvolving .. "\f"
    .. romText(game.data, "_EvolvedText", "%s evolved", oldName)
    .. romText(game.data, "_IntoText", "\ninto %s!",
         game.data.pokemon[newSpecies].name)
  game.stack:push(TextBox.new(game, msg, function()
    Music.restoreMap(game.data)
    -- re-run the evolved species' level-up learn check before onDone
    -- (evos_moves.asm EvolveMon -> learn_move.asm LearnMoveFromLevelUp, #12)
    Evolution.learnEvolutionMoves(game, mon, onDone)
  end, TextBox.soundOpts(game, "Get_Item2")))
end

-- Entry point for mods whose methods fire outside the vanilla moments
-- (location or time triggers): runs pendingFor with the caller's trigger
-- and, on a match, plays the standard evolve movie.  Returns the target
-- species or nil.
function Evolution.request(game, mon, trigger, onDone)
  local species, evo = Evolution.pendingFor(game, mon, trigger)
  if not species then
    if onDone then onDone() end
    return nil
  end
  Evolution.evolve(game, mon, species, onDone, evo and evo.method)
  return species
end

-- After-battle hook: evolve mons that leveled this battle and still
-- qualify (queued one at a time, party order).  Gen1 EvolveAfterBattle
-- only considers mons that gained a level during the fight -- a B-cancel
-- means "not this time", and the next offer waits for the next level-up
-- (or Rare Candy / stone, which call Evolution.evolve directly).
-- leveledUp is a set of party mon tables; nil/empty yields no evolutions.
function Evolution.checkParty(game, onDone, leveledUp)
  local pending = {}
  if leveledUp then
    for _, mon in ipairs(game.save.party) do
      if leveledUp[mon] then
        local target, evo = Evolution.pendingFor(game, mon, { kind = "levelup" })
        if target then
          table.insert(pending, { mon = mon, to = target, via = evo and evo.method })
        end
      end
    end
  end
  local i = 0
  local function nextOne()
    i = i + 1
    local p = pending[i]
    if not p then
      if onDone then onDone() end
      return
    end
    Evolution.evolve(game, p.mon, p.to, nextOne, p.via)
  end
  nextOne()
  return #pending
end

return Evolution
