-- Cheat Engine mod for gen1recomp
-- Features:
--   * Super powers list with ON/OFF toggles (from START menu or F6 hotkey)
--   * Heal party to full HP (instant action + optional auto-heal toggle)
--   * Max EXP: instant level 100 for the whole party + EXP gain multiplier
--   * Rare Candy multiplier: one candy grants N levels
--   * Change any party pokemon into any species (evolve)
--   * Give items (bag) and add money
--   * No wild encounters / spawn any wild pokemon (species + level)
--   * Always catch, always flee, always crit
--   * God mode (no damage taken), one-hit KO
--   * Walk through walls, movement speed multiplier
--   * Perfect DVs, max stat exp, all gym badges, give all TM/HM
--   * Infinite PP, infinite items
--
-- Requires engine_internals permission (wraps ItemEffects.use and uses
-- src.pokemon.* internals).  State persists via mod.save.

local SCREEN = "CheatEngine"
local EVOLVE_SCREEN = "CheatEvolve"
local SPECIES_SCREEN = "CheatEvolveSpecies"
local GIVE_SCREEN = "CheatGive"
local MONEY_SCREEN = "CheatMoney"
local SPAWN_SCREEN = "CheatSpawn"
local ADD_SCREEN = "CheatAdd"
local MON_SCREEN = "CheatMonActions"
local GIVEALL_SCREEN = "CheatGiveAll"

local HOTKEY = "f6"

local MULTS = { 1, 2, 5, 10, 20, 50, 100 }
local SPEED_MULTS = { 1, 2, 4, 8 }

-- Gen1 money is a 3-byte BCD value: the hard cap is 999999 (GenSave clamps
-- there too).  Anything above overflows the money box.
local MONEY_CAP = 999999

-- Preset amounts to add, so you don't have to step a QuantityBox by 1.
local MONEY_PRESETS = {
  1000,
  5000,
  10000,
  50000,
  100000,
  500000,
  MONEY_CAP,
}

-- Items you can give yourself from the cheat menu (id -> display name)
local GIVE_ITEMS = {
  { id = "RARE_CANDY", label = "RARE CANDY" },
  { id = "MASTER_BALL", label = "MASTER BALL" },
  { id = "POKE_BALL", label = "POKé BALL" },
  { id = "GREAT_BALL", label = "GREAT BALL" },
  { id = "ULTRA_BALL", label = "ULTRA BALL" },
  { id = "FULL_RESTORE", label = "FULL RESTORE" },
  { id = "MAX_POTION", label = "MAX POTION" },
  { id = "MAX_REVIVE", label = "MAX REVIVE" },
  { id = "MAX_ELIXER", label = "MAX ELIXER" },
  { id = "MAX_ETHER", label = "MAX ETHER" },
  { id = "MAX_REPEL", label = "MAX REPEL" },
  { id = "FIRE_STONE", label = "FIRE STONE" },
  { id = "THUNDER_STONE", label = "THUNDER STONE" },
  { id = "WATER_STONE", label = "WATER STONE" },
  { id = "LEAF_STONE", label = "LEAF STONE" },
  { id = "MOON_STONE", label = "MOON STONE" },
}

local function nextMult(mult)
  for i, v in ipairs(MULTS) do
    if v == mult then
      return MULTS[(i % #MULTS) + 1]
    end
  end
  return 2
end

local function cycleMult(list, cur)
  for i, v in ipairs(list) do
    if v == cur then
      return list[(i % #list) + 1]
    end
  end
  return list[1] or 1
end

return function(mod)
  local Pokemon, Stats, Growth, Evolution, ItemEffects, Bag, Badges, Data, Party

  -- The vanilla bag caps at 20 slots but the game ships ~55 TM/HM items;
  -- "give all TMs" (and generous cheating in general) needs the room.
  mod.content.constants:patch("bagSize", 99)

  local function getState()
    return mod.save:get("state", {})
  end

  local function setState(s)
    mod.save:set("state", s)
  end

  -- ------------------------------------------------------------------
  -- Cheat actions
  -- ------------------------------------------------------------------

  local function healParty(game)
    for _, mon in ipairs(game.save.party) do
      Pokemon.heal(mon)
    end
  end

  local function maxExpParty(game)
    for _, mon in ipairs(game.save.party) do
      local def = mod.content.pokemon:get(mon.species)
      if def then
        mon.level = 100
        mon.exp = Growth.expForLevel(def.growthRate, 100)
        mon.stats = Stats.calc(def, 100, mon.dvs, mon.statExp)
        mon.hp = mon.stats.hp
      end
    end
  end

  -- Bike anywhere: widen field.bikeRiding (every map + tileset) so both
  -- the BagMenu mount check and setOnMap's dismount allowlist pass on any
  -- map.  Also hands the player the BICYCLE item and mounts it outright,
  -- because the point of the toggle is "ride the bike everywhere".
  local function applyBikeAnywhere(game, on)
    local field = game.data.field
    if not field then return end
    if on then
      local maps, tilesets = {}, {}
      local seen = {}
      if game.data.maps then
        for id, def in pairs(game.data.maps) do
          maps[#maps + 1] = id
          local t = def and def.tileset
          if t and not seen[t] then seen[t] = true; tilesets[#tilesets + 1] = t end
        end
      end
      field.bikeRiding = { maps = maps, tilesets = tilesets }
      -- make sure the bike exists in the bag and mount it now
      local inv = game.save.inventory
      if not inv.BICYCLE or inv.BICYCLE <= 0 then inv.BICYCLE = 1 end
      game.save.onBike = true
      local ow = game.overworld
      if ow and ow.map then
        require("src.core.Music").playMap(game.data, ow.map.id, true)
      end
    else
      field.bikeRiding = nil
      if game.save.onBike then
        game.save.onBike = false
        local ow = game.overworld
        if ow and ow.map then
          require("src.core.Music").playMap(game.data, ow.map.id, false)
        end
      end
    end
  end

  -- Give all Pokemon: rebuilds the whole party with the legendaries
  -- (Mew, Mewtwo, Articuno, Zapdos, Moltres) filled out with Gyarados to
  -- a full 6, every other species lands in the PC boxes, and the whole
  -- dex is stamped seen+owned.  Shiny grants the Gen1 shiny DV pattern
  -- (Defense/Speed/Special 10, Attack 15) to everything added.  Existing
  -- party mons are moved to the PC so nothing is lost.
  local LEGENDARY_TEAM = { "MEW", "MEWTWO", "ARTICUNO", "ZAPDOS", "MOLTRES" }
  local FILLER = "GYARADOS"
  local function giveAllPokemon(game, shiny, level)
    local save = game.save
    local dex = save.pokedex or { seen = {}, owned = {} }
    save.pokedex = dex
    local boxes = save.boxes
    if not boxes then boxes = {}; save.boxes = boxes end
    local MONS_PER_BOX = 20
    local boxIdx = save.currentBox or 1
    if boxIdx < 1 or boxIdx > 12 then boxIdx = 1 end
    level = level or 100
    if level < 1 then level = 1 end
    if level > 100 then level = 100 end

    local function boxFull()
      local b = boxes[boxIdx]
      return (b and #b or 0) >= MONS_PER_BOX
    end

    local function stash(mon)
      if boxFull() and boxes[boxIdx] then
        local start = boxIdx
        repeat
          boxIdx = (boxIdx % 12) + 1
        until not boxFull() or boxIdx == start
        if boxFull() then return false end
      end
      local b = boxes[boxIdx]
      if not b then b = {}; boxes[boxIdx] = b end
      b[#b + 1] = mon
      return true
    end

    local function makeMon(id)
      local mon = Pokemon.new(game.data, id, level)
      if shiny then
        mon.dvs = { attack = 15, defense = 10, speed = 10, special = 10 }
        local def = mod.content.pokemon:get(id)
        if def then
          mon.stats = Stats.calc(def, level, mon.dvs, mon.statExp)
          mon.hp = mon.stats.hp
        end
      end
      return mon
    end

    -- move the current party into the PC first, then rebuild
    for _, mon in ipairs(save.party) do
      stash(mon)
    end
    save.party = {}

    -- the legendaries + Gyarados fill a full 6-slot team
    for _, id in ipairs(LEGENDARY_TEAM) do
      save.party[#save.party + 1] = makeMon(id)
      dex.seen[id] = true
      dex.owned[id] = true
    end
    if #save.party < Party.MAX then
      save.party[#save.party + 1] = makeMon(FILLER)
      dex.seen[FILLER] = true
      dex.owned[FILLER] = true
    end

    -- every remaining species goes to the PC and registers in the dex
    local added = 0
    for id in mod.content.pokemon:each() do
      if not dex.owned[id] then
        local mon = makeMon(id)
        if stash(mon) then
          dex.seen[id] = true
          dex.owned[id] = true
          added = added + 1
        end
      end
    end
    return #save.party, added, shiny
  end

  -- Perfect DVs (15 across the board) on the whole party
  local function perfectDvsParty(game)
    for _, mon in ipairs(game.save.party) do
      mon.dvs = { hp = 15, attack = 15, defense = 15, speed = 15, special = 15 }
      local def = mod.content.pokemon:get(mon.species)
      if def then
        mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
        mon.hp = mon.stats.hp
      end
    end
  end

  -- Maxed stat exp (65535 per stat, the Gen1 cap)
  local function maxStatExpParty(game)
    for _, mon in ipairs(game.save.party) do
      mon.statExp = {
        hp = 65535, attack = 65535, defense = 65535,
        speed = 65535, special = 65535,
      }
      local def = mod.content.pokemon:get(mon.species)
      if def then
        mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
        mon.hp = mon.stats.hp
      end
    end
  end

  -- All 8 gym badges
  local function giveAllBadges(game)
    local granted = 0
    for _, entry in ipairs(Badges.list(Data)) do
      game.save.inventory[Badges.itemFor(entry)] = true
      granted = granted + 1
    end
    return granted
  end

  -- Every TM and HM in the game (discovered from the merged item catalog)
  local function giveAllTms(game)
    local given = 0
    for id, item in mod.content.items:each() do
      local machine = item.machine
      if machine and (machine.kind == "TM" or machine.kind == "HM") then
        if Bag.add(game.save, id, 1) then
          given = given + 1
        end
      end
    end
    return given
  end

  -- ------------------------------------------------------------------
  -- Hooks
  -- ------------------------------------------------------------------

  -- EXP gain multiplier
  mod.hooks:wrap("exp.gain", function(next, ctx)
    local exp = next(ctx)
    local mult = getState().expMult or 1
    if mult > 1 and exp then
      exp = math.floor(exp * mult)
    end
    return exp
  end)

  -- Auto-heal every tick while enabled
  mod.hooks:wrap("input.step", function(next, game, dt)
    local s = getState()
    for _, mon in ipairs(game.save.party) do
      if s.autoHeal and mon.hp < mon.stats.hp then
        Pokemon.heal(mon)
      end
      -- Infinite PP: keep every move at base + PP-Up bonus each tick
      if s.infPP and Data and Data.moves then
        for _, mv in ipairs(mon.moves) do
          local mdef = Data.moves[mv.id]
          if mdef then
            mv.pp = mdef.pp + (mv.ppUps or 0) * math.floor(mdef.pp / 5)
          end
        end
      end
    end
    -- Surf always: keep riding whenever standing on water (the engine
    -- dismounts on land via isWalkableCell; re-applying here means a
    -- shore approach never drops the surf).  Also lets the player ride
    -- water without owning the HM (fieldmove.eligibility below).
    if s.surfAlways then
      local ow = game.overworld
      if ow and ow.player and ow.map and ow.map:isWaterCell(ow.player.cellX, ow.player.cellY) then
        ow.player.surfing = true
        if ow.syncSurfingPikachu then ow:syncSurfingPikachu() end
      end
    end
    return next(game, dt)
  end)

  -- Surf always: unlock the SURF field move regardless of the party
  -- (eligibility hooks can answer before the vanilla party scan).  The
  -- enable-cut/rock toggle reuses the same gate.
  mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
    local s = getState()
    if s.surfAlways and moveId == "SURF" then
      local party = ctx and ctx.save and ctx.save.party
      return party and party[1] or true
    end
    if s.fieldMoves and (moveId == "CUT" or moveId == "STRENGTH") then
      local party = ctx and ctx.save and ctx.save.party
      return party and party[1] or true
    end
    return next(moveId, ctx)
  end)

  -- Enable CUT + STRENGTH in the party menu (trees + boulders) without the
  -- badge / without a mon knowing the HM: inject the entries the vanilla
  -- list-time badge+move filter would have dropped.  The existing action
  -- handlers (PartyMenu "cut"/"strength") then drive tryCut / strengthActive.
  -- Surf always rides the same injection (partyKnows gate is handled by
  -- fieldmove.eligibility above, so useSurfFieldMove passes the no_badge
  -- check and trySurf the mount).
  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local res = next(game, items, mon, ctx)
    if res and not (ctx and ctx.battle) then
      local s = getState()
      if s.fieldMoves or s.surfAlways then
        local hasAction = {}
        for _, it in ipairs(res) do
          if it.action then hasAction[it.action] = true end
        end
        if s.fieldMoves and not hasAction.cut then
          table.insert(res, 1, { label = "CUT", action = "cut" })
        end
        if s.fieldMoves and not hasAction.strength then
          table.insert(res, 1, { label = "STRENGTH", action = "strength" })
        end
        if s.surfAlways and not hasAction.surf then
          table.insert(res, 1, { label = "SURF", action = "surf" })
        end
      end
    end
    return res
  end)

  -- No wild encounters / spawn a forced pokemon (once)
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    local s = getState()
    if s.forceEncounter then
      local enc = { species = s.forceEncounter.species,
                    level = s.forceEncounter.level }
      s.forceEncounter = nil
      setState(s)
      return enc
    end
    if s.noEncounters then
      return nil
    end
    return next(encDef, ctx)
  end)

  -- Always catch: force Catching.attempt to succeed (3 shakes)
  mod.hooks:wrap("catch.rate", function(next, ball, mon, def, opts)
    if getState().alwaysCatch then
      return true, 3
    end
    return next(ball, mon, def, opts)
  end)

  -- Always flee trainer/wild battles
  mod.hooks:wrap("battle.run", function(next, ctx)
    if getState().alwaysFlee then
      return true
    end
    return next(ctx)
  end)

  -- Always crit for the player
  mod.hooks:wrap("battle.crit", function(next, ctx)
    if getState().alwaysCrit and ctx.attacker and ctx.attacker.isPlayer then
      return true
    end
    return next(ctx)
  end)

  -- God mode (no damage on the player) + one-hit KO (player OHKOs enemies)
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local dmg, meta = next(ctx)
    local s = getState()
    if s.godMode and ctx.target and ctx.target.isPlayer then
      return 0, meta
    end
    if s.ohko and ctx.user and ctx.user.isPlayer
        and ctx.target and not ctx.target.isPlayer
        and dmg and dmg > 0 then
      return ctx.target.mon.stats.hp, meta
    end
    return dmg, meta
  end)

  -- Walk through walls: always allow the step (and say why).  Surf always:
  -- stepping into a water cell mounts the surf automatically (the vanilla
  -- verdict blocks water unless mover.surfing; we mount + allow instead).
  mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
    local s = getState()
    if s.noClip then
      ctx.reason = "cheat"
      return true
    end
    if s.surfAlways and ctx and ctx.map and ctx.mover
        and not allowed
        and ctx.map:isWaterCell(ctx.toX, ctx.toY)
        and not ctx.mover.surfing then
      ctx.mover.surfing = true
      require("src.mods.Runtime").emit("cheat.surf_mounted",
        { mover = ctx.mover, mapId = ctx.map.id, toX = ctx.toX, toY = ctx.toY })
      ctx.reason = "cheat_surf"
      return true
    end
    return next(allowed, ctx)
  end)

  -- Movement speed multiplier (fewer frames per step = faster)
  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    local mult = getState().speedMult or 1
    if mult > 1 then
      return math.max(1, math.floor(frames / mult))
    end
    return next(frames, ctx)
  end)

  -- Rare Candy multiplier: wrap ItemEffects.use (nuzlocke-style engine wrap)
  mod.events:on("game.ready", function(ev)
    Pokemon = require("src.pokemon.Pokemon")
    Stats = require("src.pokemon.Stats")
    Growth = require("src.pokemon.Growth")
    Evolution = require("src.pokemon.Evolution")
    ItemEffects = require("src.inventory.ItemEffects")
    Bag = require("src.inventory.Bag")
    Badges = require("src.inventory.Badges")
    Data = require("src.core.Data")
    Party = require("src.pokemon.Party")

    -- re-apply a persisted bike-anywhere toggle to the fresh game's data
    if getState().bikeAnywhere and ev and ev.game and ev.game.data then
      applyBikeAnywhere(ev.game, true)
    end

    local vanilla = ItemEffects.use
    ItemEffects.use = function(data, save, itemId, target, battle, moveIndex, ow)
      local result, payload, extra = vanilla(data, save, itemId, target, battle, moveIndex, ow)
      if itemId == "RARE_CANDY" and result == "consumed" and target then
        local mult = getState().candyMult or 1
        if mult > 1 then
          local speciesDef = data.pokemon[target.species]
          for _ = 2, mult do
            if target.level >= 100 then break end
            target.level = target.level + 1
            target.exp = Growth.expForLevel(speciesDef.growthRate, target.level)
            local old = target.stats
            target.stats = Stats.calc(speciesDef, target.level, target.dvs, target.statExp)
            target.hp = math.min(target.stats.hp, target.hp + (target.stats.hp - old.hp))
          end
          extra.leveledTo = target.level
        end
      end
      return result, payload, extra
    end

    -- Infinite items: Bag.remove is a no-op while the toggle is on
    local vanillaRemove = Bag.remove
    Bag.remove = function(save, id, qty)
      if getState().infItems then
        return
      end
      return vanillaRemove(save, id, qty)
    end

    -- Catch enemy pokemon in trainer battles: vanilla throwBall runs the
    -- "trainer blocked the BALL" branch whenever kind ~= "wild" and never
    -- rolls the catch.  The bag menu always calls battle:throwBall for a
    -- ball item, so swapping the branch for the real catch attempt here is
    -- the whole gate.  Catching sends the mon to the party (or PC) via the
    -- same storeCaughtMon path a wild catch uses; the trainer battle then
    -- resolves however afterBattle handles result ~= "lose".
    local BattleState = require("src.battle.BattleState")
    local Strings = require("src.core.Strings")
    local vanillaThrowBall = BattleState.throwBall
    BattleState.throwBall = function(self, ball)
      if getState().catchEnemy
          and self.kind ~= "wild" and not self.ghost and not self.noCatch then
        require("src.core.Sound").play(self.data, "Ball_Toss")
        self:animNext("TOSS_ANIM", true, nil, ball)
        -- act like a wild toss: record the ball, attempt the catch, and on
        -- success run the party/box + dex path.  A failed roll keeps the
        -- trainer battle going with the enemy's next action, same as any
        -- failed wild throw.
        self.lastBall = ball
        local caught, shakes = self:catchAttempt(ball)
        require("src.mods.Runtime").emit("battle.ball_thrown", {
          battle = self, ball = ball, caught = caught, shakes = shakes,
        })
        self.nextInsert = (self.nextInsert or 0) + 1
        table.insert(self.queue, self.nextInsert, { wait = 20 })
        self:ballChain(self:tossAnimFor(ball), caught, shakes, ball)
        if caught then
          self:actNext(function()
            require("src.core.Sound").play(self.data, "Caught_Mon")
          end)
          self:sayNext(Strings("All right!\n%s was\ncaught!", self.enemy.name))
          self:act(function() self:storeCaughtMon() end)
        else
          self:sayNext(self:ballMissMessage(shakes))
          self:act(function()
            self:executeAction(self.enemy, self.player, self:enemyAction())
          end)
          self:queueResidual(self.player, self.enemy)
          self:act(function() self:endOfTurn() end)
        end
        return
      end
      return vanillaThrowBall(self, ball)
    end

    -- Hotkey: F6 opens the cheat menu from anywhere (wrap Game:keypressed)
    local Game = require("src.core.Game")
    local vanillaKey = Game.keypressed
    Game.keypressed = function(self, key)
      if key == HOTKEY then
        mod.ui.push(self, SCREEN)
        return
      end
      return vanillaKey(self, key)
    end
  end)

  -- ------------------------------------------------------------------
  -- UI: start menu entry
  -- ------------------------------------------------------------------

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "SAVE", {
      label = "CHEATS",
      onSelect = function()
        mod.ui.push(game, SCREEN)
      end,
    })
  end)

  -- ------------------------------------------------------------------
  -- Screens
  -- ------------------------------------------------------------------

  -- Main cheat menu: super powers with ON/OFF toggles
  mod.content.screens:register(SCREEN, {
    new = function(game)
      local s = getState()
      local items = {
        { label = "HEAL PARTY", value = "heal" },
        { label = "MAX EXP (Lv100)", value = "maxexp" },
        { label = "LEVEL x" .. (s.expMult or 1), value = "expmult" },
        { label = "RARE CANDY x" .. (s.candyMult or 1), value = "candymult" },
        { label = "AUTO HEAL: " .. (s.autoHeal and "ON" or "OFF"), value = "autoheal" },
        { label = "GIVE ITEM", value = "give" },
        { label = "ADD MONEY", value = "money" },
        { label = "CHANGE POKéMON", value = "evolve" },
        { label = "ADD POKéMON", value = "add" },
        { label = "NO ENCOUNTERS: " .. (s.noEncounters and "ON" or "OFF"), value = "noencounters" },
        { label = "SPAWN POKéMON", value = "spawn" },
        { label = "ALWAYS CATCH: " .. (s.alwaysCatch and "ON" or "OFF"), value = "catch" },
        { label = "ALWAYS RUN: " .. (s.alwaysFlee and "ON" or "OFF"), value = "flee" },
        { label = "ALWAYS CRIT: " .. (s.alwaysCrit and "ON" or "OFF"), value = "crit" },
        { label = "GOD MODE: " .. (s.godMode and "ON" or "OFF"), value = "godmode" },
        { label = "ONE-HIT KO: " .. (s.ohko and "ON" or "OFF"), value = "ohko" },
        { label = "WALK WALLS: " .. (s.noClip and "ON" or "OFF"), value = "noclip" },
        { label = "SPEED x" .. (s.speedMult or 1), value = "speed" },
        { label = "AUTO SURF: " .. (s.surfAlways and "ON" or "OFF"), value = "surfalways" },
        { label = "CUT/ROCK: " .. (s.fieldMoves and "ON" or "OFF"), value = "fieldmoves" },
        { label = "BIKE ALL: " .. (s.bikeAnywhere and "ON" or "OFF"), value = "bikeanywhere" },
        { label = "CATCH ENEMY: " .. (s.catchEnemy and "ON" or "OFF"), value = "catchenemy" },
        { label = "GIVE ALL POKéMON", value = "giveall" },
        { label = "PERFECT DVs", value = "perfectdvs" },
        { label = "MAX STAT EXP", value = "maxstexp" },
        { label = "ALL BADGES", value = "badges" },
        { label = "GIVE ALL TM/HM", value = "tms" },
        { label = "PP INFINITE: " .. (s.infPP and "ON" or "OFF"), value = "infpp" },
        { label = "ITEMS INFINITE: " .. (s.infItems and "ON" or "OFF"), value = "infitems" },
      }
      return mod.ui.ListMenu.new(game, "CHEAT ENGINE", items, {
        onChoose = function(item, menu)
          local v = item.value
          if v == "heal" then
            healParty(game)
            menu:close()
          elseif v == "maxexp" then
            maxExpParty(game)
            menu:close()
          elseif v == "expmult" then
            local st = getState()
            st.expMult = nextMult(st.expMult or 1)
            setState(st)
            item.label = "LEVEL x" .. st.expMult
          elseif v == "candymult" then
            local st = getState()
            st.candyMult = nextMult(st.candyMult or 1)
            setState(st)
            item.label = "RARE CANDY x" .. st.candyMult
          elseif v == "autoheal" then
            local st = getState()
            st.autoHeal = not st.autoHeal
            setState(st)
            item.label = "AUTO HEAL: " .. (st.autoHeal and "ON" or "OFF")
          elseif v == "give" then
            mod.ui.push(game, GIVE_SCREEN)
          elseif v == "money" then
            mod.ui.push(game, MONEY_SCREEN)
          elseif v == "evolve" then
            mod.ui.push(game, EVOLVE_SCREEN)
          elseif v == "add" then
            mod.ui.push(game, ADD_SCREEN)
          elseif v == "bikeanywhere" then
            local st = getState()
            st.bikeAnywhere = not st.bikeAnywhere
            setState(st)
            applyBikeAnywhere(game, st.bikeAnywhere)
            item.label = "BIKE ALL: " .. (st.bikeAnywhere and "ON" or "OFF")
          elseif v == "surfalways" then
            local st = getState()
            st.surfAlways = not st.surfAlways
            setState(st)
            item.label = "AUTO SURF: " .. (st.surfAlways and "ON" or "OFF")
          elseif v == "giveall" then
            mod.ui.push(game, GIVEALL_SCREEN)
          elseif v == "noencounters" then
            local st = getState()
            st.noEncounters = not st.noEncounters
            setState(st)
            item.label = "NO ENCOUNTERS: " .. (st.noEncounters and "ON" or "OFF")
          elseif v == "spawn" then
            mod.ui.push(game, SPAWN_SCREEN)
          elseif v == "catch" then
            local st = getState()
            st.alwaysCatch = not st.alwaysCatch
            setState(st)
            item.label = "ALWAYS CATCH: " .. (st.alwaysCatch and "ON" or "OFF")
          elseif v == "catchenemy" then
            local st = getState()
            st.catchEnemy = not st.catchEnemy
            setState(st)
            item.label = "CATCH ENEMY: " .. (st.catchEnemy and "ON" or "OFF")
          elseif v == "fieldmoves" then
            local st = getState()
            st.fieldMoves = not st.fieldMoves
            setState(st)
            item.label = "CUT/ROCK: " .. (st.fieldMoves and "ON" or "OFF")
          elseif v == "flee" then
            local st = getState()
            st.alwaysFlee = not st.alwaysFlee
            setState(st)
            item.label = "ALWAYS RUN: " .. (st.alwaysFlee and "ON" or "OFF")
          elseif v == "crit" then
            local st = getState()
            st.alwaysCrit = not st.alwaysCrit
            setState(st)
            item.label = "ALWAYS CRIT: " .. (st.alwaysCrit and "ON" or "OFF")
          elseif v == "godmode" then
            local st = getState()
            st.godMode = not st.godMode
            setState(st)
            item.label = "GOD MODE: " .. (st.godMode and "ON" or "OFF")
          elseif v == "ohko" then
            local st = getState()
            st.ohko = not st.ohko
            setState(st)
            item.label = "ONE-HIT KO: " .. (st.ohko and "ON" or "OFF")
          elseif v == "noclip" then
            local st = getState()
            st.noClip = not st.noClip
            setState(st)
            item.label = "WALK WALLS: " .. (st.noClip and "ON" or "OFF")
          elseif v == "speed" then
            local st = getState()
            st.speedMult = cycleMult(SPEED_MULTS, st.speedMult or 1)
            setState(st)
            item.label = "SPEED x" .. st.speedMult
          elseif v == "perfectdvs" then
            perfectDvsParty(game)
            menu:close()
          elseif v == "maxstexp" then
            maxStatExpParty(game)
            menu:close()
          elseif v == "badges" then
            giveAllBadges(game)
            menu:close()
          elseif v == "tms" then
            giveAllTms(game)
            menu:close()
          elseif v == "infpp" then
            local st = getState()
            st.infPP = not st.infPP
            setState(st)
            item.label = "PP INFINITE: " .. (st.infPP and "ON" or "OFF")
          elseif v == "infitems" then
            local st = getState()
            st.infItems = not st.infItems
            setState(st)
            item.label = "ITEMS INFINITE: " .. (st.infItems and "ON" or "OFF")
          end
        end,
        onCancel = function()
          -- no-op: ListMenu B handler already popped us from the stack
        end,
      })
    end,
  })

  -- Pick a party mon to change into any species
  mod.content.screens:register(EVOLVE_SCREEN, {
    new = function(game)
      local items = {}
      for _, mon in ipairs(game.save.party) do
        local def = mod.content.pokemon:get(mon.species)
        -- captured mons store nickname="" (truthy) when the player skipped
        -- the nickname prompt; treat an empty string as no nickname
        local name = mon.nickname
        if not (type(name) == "string" and #name > 0) then
          name = (def and def.name) or mon.species
        end
        if type(name) ~= "string" then name = tostring(name) end
        items[#items + 1] = {
          label = name .. " L" .. mon.level,
          value = mon,
        }
      end
      return mod.ui.ListMenu.new(game, "CHANGE POKéMON", items, {
        onChoose = function(item, menu)
          mod.ui.push(game, MON_SCREEN, item.value)
        end,
        onCancel = function() end,
      })
    end,
  })

  -- Per-mon actions: change species, make shiny / make normal
  mod.content.screens:register(MON_SCREEN, {
    new = function(game, mon)
      local shiny = Stats.isShiny(mon.dvs)
      return mod.ui.ListMenu.new(game, "WHAT DO?", {
        { label = shiny and "MAKE NORMAL" or "MAKE SHINY", value = "shiny" },
        { label = "CHANGE SPECIES", value = "species" },
      }, {
        onChoose = function(item, menu)
          if item.value == "species" then
            mod.ui.push(game, SPECIES_SCREEN, mon)
          else
            -- Gen 1 shiny = Defense/Speed/Special DV 10 + Attack DV
            -- in {2,3,6,7,10,11,14,15}; normal rolls fresh random DVs
            -- (1/8192 chance of landing shiny again is the vanilla odds).
            if Stats.isShiny(mon.dvs) then
              mon.dvs = Stats.randomDVs()
            else
              mon.dvs = { attack = 15, defense = 10, speed = 10, special = 10 }
            end
            local def = mod.content.pokemon:get(mon.species)
            if def then
              mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
              mon.hp = mon.stats.hp
            end
            menu:close()
          end
        end,
        onCancel = function() end,
      })
    end,
  })

  -- Pick the target species
  mod.content.screens:register(SPECIES_SCREEN, {
    new = function(game, mon)
      local items = {}
      for id, def in mod.content.pokemon:each() do
        items[#items + 1] = { label = def.name or id, value = id }
      end
      table.sort(items, function(a, b) return a.label < b.label end)
      return mod.ui.ListMenu.new(game, "CHANGE INTO?", items, {
        pageJump = true,
        onChoose = function(item, menu)
          -- pick the new level (defaults to 25), then apply
          game.stack:push(mod.ui.QuantityBox.new(game, {
            max = 100,
            start = 25,
            onDone = function(level)
              if level then
                -- Evolution.apply keeps the old mon's moves (right for real
                -- evolutions); the cheat changes the species wholesale, so
                -- apply the level + rebuild the learnset for the new species
                -- at that level, the same way Pokemon.new does.  Level first:
                -- Evolution.apply recalcs stats from mon.level.
                mon.level = math.max(1, math.min(100, level))
                local newDef = mod.content.pokemon:get(item.value)
                if newDef then
                  -- Pokemon.new seeds exp for the target level; changing
                  -- the level without resetting exp left the old mon's
                  -- accumulated exp (e.g. L100) attached, so the next win
                  -- queued level-ups straight back up to where the exp sat.
                  mon.exp = Growth.expForLevel(newDef.growthRate, mon.level)
                  local moves = {}
                  for _, id in ipairs(Pokemon.movesAtLevel(newDef, mon.level)) do
                    local mdef = Data.moves[id]
                    moves[#moves + 1] = { id = id, pp = mdef and mdef.pp or 0 }
                  end
                  mon.moves = moves
                end
                Evolution.evolve(game, mon, item.value, nil, "manual")
              end
            end,
          }))
        end,
        onCancel = function() end,
      })
    end,
  })

  -- Pick a species + level and add it straight to the party
  mod.content.screens:register(ADD_SCREEN, {
    new = function(game)
      local items = {}
      for id, def in mod.content.pokemon:each() do
        items[#items + 1] = { label = def.name or id, value = id }
      end
      table.sort(items, function(a, b) return a.label < b.label end)
      return mod.ui.ListMenu.new(game, "ADD WHICH?", items, {
        pageJump = true,
        onChoose = function(item, menu)
          game.stack:push(mod.ui.QuantityBox.new(game, {
            max = 100,
            start = 5,
            onDone = function(qty)
              if qty then
                local mon = Pokemon.new(game.data, item.value, qty)
                local TextBox = require("src.render.TextBox")
                if #game.save.party >= Party.MAX then
                  game.stack:push(TextBox.new(game, "Party is full!"))
                else
                  Party.add(game.save.party, mon)
                  local name = mon.nickname or mod.content.pokemon:get(item.value).name
                  game.stack:push(TextBox.new(game, ("%s L%d joined!"):format(name, qty)))
                end
              end
            end,
          }))
        end,
        onCancel = function() end,
      })
    end,
  })

  -- Pick the species for the next wild encounter, then its level
  mod.content.screens:register(SPAWN_SCREEN, {
    new = function(game)
      local items = {}
      for id, def in mod.content.pokemon:each() do
        items[#items + 1] = { label = def.name or id, value = id }
      end
      table.sort(items, function(a, b) return a.label < b.label end)
      return mod.ui.ListMenu.new(game, "SPAWN WHICH?", items, {
        pageJump = true,
        onChoose = function(item, menu)
          game.stack:push(mod.ui.QuantityBox.new(game, {
            max = 100,
            start = 5,
            onDone = function(qty)
              if qty then
                local st = getState()
                st.forceEncounter = { species = item.value, level = qty }
                setState(st)
              end
            end,
          }))
        end,
        onCancel = function() end,
      })
    end,
  })

  -- Pick an item to give yourself, then a quantity
  mod.content.screens:register(GIVE_SCREEN, {
    new = function(game)
      local items = {}
      for _, entry in ipairs(GIVE_ITEMS) do
        items[#items + 1] = { label = entry.label, value = entry.id }
      end
return mod.ui.ListMenu.new(game, "GIVE ITEM", items, {
        onChoose = function(item, menu)
          local itemId = item.value
          game.stack:push(mod.ui.QuantityBox.new(game, {
            max = 99,
            start = 1,
            onDone = function(qty)
              if qty then
                Bag.add(game.save, itemId, qty)
              end
            end,
          }))
        end,
        onCancel = function(menu)
          -- no-op: ListMenu B handler already popped us from the stack
        end,
      })
    end,
  })

  -- Add money: pick a preset amount, clamped to the Gen1 BCD cap
  mod.content.screens:register(MONEY_SCREEN, {
    new = function(game)
      local items = {}
      for _, amount in ipairs(MONEY_PRESETS) do
        items[#items + 1] = { label = ("¥%d"):format(amount), value = amount }
      end
      return mod.ui.ListMenu.new(game, "ADD MONEY", items, {
        onChoose = function(item, menu)
          local current = game.save.money or 0
          game.save.money = math.min(MONEY_CAP, current + item.value)
          menu:close()
        end,
        onCancel = function() end,
      })
    end,
  })

  -- Give all pokemon: ask shiny or normal, then a level, then rebuild
  mod.content.screens:register(GIVEALL_SCREEN, {
    new = function(game)
      local function pickLevel(shiny)
        game.stack:push(mod.ui.QuantityBox.new(game, {
          max = 100,
          start = 100,
          onDone = function(level)
            if level then
              local team = giveAllPokemon(game, shiny, level)
              local TextBox = require("src.render.TextBox")
              game.stack:push(TextBox.new(game,
                ("%s team: %d POKéMON L%d! Legendaries + the rest to the PC.")
                  :format(shiny and "SHINY" or "", team, level)))
            end
          end,
        }))
      end
      return mod.ui.Menu.new(game, {
        { label = "NORMAL", onSelect = function()
          pickLevel(false)
        end },
        { label = "SHINY", onSelect = function()
          pickLevel(true)
        end },
      }, { cancelable = true })
    end,
  })
end