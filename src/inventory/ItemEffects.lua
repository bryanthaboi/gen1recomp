-- Item use effects, ported from engine/items/item_effects.asm.
-- Heal amounts and behaviors match Gen 1; TMs/HMs teach their machine
-- move when the species' tmhm list allows it.
--
-- ItemEffects.use returns:
--   "consumed", messages            item used up
--   "kept", messages                used but not consumed (TM kept? no --
--                                   HMs and key items)
--   "failed", messages              no effect ("It won't have any effect.")
--   "ball"                          caller must throw it (battle only)
--   "learn", moveId                 caller must run the learn-move flow

local Flags = require("src.script.Flags")
local Strings = require("src.core.Strings")
local romText = require("src.core.RomText")

local ItemEffects = {}

local function notTime(data, save)
  return romText(data, "_ItemUseNotTimeText",
    "OAK: %s!\nThis isn't the\ntime to use that!", save.player.name)
end

local function noEffect(data)
  return romText(data, "_ItemUseNoEffectText", "It won't have\nany effect.")
end

local function registeredEffect(data, itemDef)
    if not data or not itemDef or not itemDef.effect then
        return nil
    end

    if not data.item_effects then
        return nil
    end

    return data.item_effects[itemDef.effect]
end

local HEAL_AMOUNT = {
  POTION = 20, SUPER_POTION = 50, HYPER_POTION = 200,
  FRESH_WATER = 50, SODA_POP = 60, LEMONADE = 80,
}

local STATUS_HEAL = {
  ANTIDOTE = { PSN = true }, BURN_HEAL = { BRN = true },
  ICE_HEAL = { FRZ = true }, AWAKENING = { SLP = true },
  PARLYZ_HEAL = { PAR = true },
  FULL_HEAL = { PSN = true, BRN = true, FRZ = true, SLP = true, PAR = true },
}

local BALLS = {
  POKE_BALL = true, GREAT_BALL = true, ULTRA_BALL = true,
  MASTER_BALL = true, SAFARI_BALL = true,
}

local STONES = {
  FIRE_STONE = true, WATER_STONE = true, THUNDER_STONE = true,
  LEAF_STONE = true, MOON_STONE = true,
}

-- vitamins: stat-exp boosters (ItemUseVitamin)
local VITAMINS = { HP_UP = "hp", PROTEIN = "attack", IRON = "defense",
                   CARBOS = "speed", CALCIUM = "special" }

-- REPEL / SUPER_REPEL / MAX_REPEL all funnel through ItemUseRepelCommon,
-- which refuses mid-battle before writing wRepelRemainingSteps (#894)
local REPELS = { REPEL = true, SUPER_REPEL = true, MAX_REPEL = true }

ItemEffects.BALLS = BALLS

function ItemEffects.isBall(id) return BALLS[id] or false end
function ItemEffects.isStone(id) return STONES[id] or false end

-- Does using this item take item_effects.asm's .healHP path, the one that
-- plays SFX_HEAL_HP and lengthens the party HP bar with UpdateHPBar2 before
-- the message (item_effects.asm .doneHealing)?  The status-only cures branch
-- to .playStatusAilmentCuringSound instead and never touch the bar.  BagMenu
-- keeps the party picker open for these so the fill has something to draw
-- on (#252).
function ItemEffects.healsHP(id)
  return HEAL_AMOUNT[id] ~= nil or id == "MAX_POTION" or id == "FULL_RESTORE"
      or id == "REVIVE" or id == "MAX_REVIVE"
end

-- Does this item need a party-member target?
-- 'data' is optional for compat purposes; targeting falls back to itemDef/vanilla detection
function ItemEffects.needsTarget(id, itemDef, data)
  if itemDef and itemDef.needsTarget ~= nil then
      return itemDef.needsTarget
  end

  local effect = registeredEffect(data, itemDef)

  if effect and effect.needsTarget ~= nil then
    return effect.needsTarget
  end

  return HEAL_AMOUNT[id] or STATUS_HEAL[id] or id == "MAX_POTION"
      or id == "FULL_RESTORE" or id == "REVIVE" or id == "MAX_REVIVE"
      or id == "RARE_CANDY" or STONES[id]
      or (itemDef and itemDef.machine) or id == "ETHER"
      or id == "MAX_ETHER" or id == "ELIXER" or id == "MAX_ELIXER"
      or VITAMINS[id] or id == "PP_UP"
end

local function monName(data, mon)
  return mon.nickname or data.pokemon[mon.species].name
end

-- Curing the ACTIVE battler clears its Toxic escalation flag
-- (.cureStatusAilment / trainer_ai.asm AICureStatus both do
-- `res BADLY_POISONED`); the raw w*ToxicCounter is NOT reset by item
-- cures in Gen 1, so battle.sideToxic is deliberately left alone.
local function cureActiveToxic(battle, target)
  if not battle then return end
  for _, b in ipairs({ battle.player, battle.enemy }) do
    if b and b.mon == target then b.toxicCounter = nil end
  end
end

-- the per-item cure lines (item_effects.asm .cureStatusAilment picks the
-- text by item id); FULL_RESTORE lands here too when it acts as a cure
local CURE_TEXT = {
  ANTIDOTE = "_AntidoteText", BURN_HEAL = "_BurnHealText",
  ICE_HEAL = "_IceHealText", AWAKENING = "_AwakeningText",
  PARLYZ_HEAL = "_ParlyzHealText", FULL_HEAL = "_FullHealText",
}

-- battle-only stat boosters (engine/items/item_effects.asm ItemUseXStat)
local X_ITEMS = {
  X_ATTACK = "attack", X_DEFEND = "defense", X_SPEED = "speed",
  X_SPECIAL = "special", X_ACCURACY = "accuracy",
}

-- The two static Snorlax encounters (scripts/Route12.asm, Route16.asm).
-- ItemUsePokeFlute only wakes one when the player is on its route, hasn't
-- beaten it yet, and is standing in one of the four cells orthogonally
-- adjacent to it (Route12SnorlaxFluteCoords/Route16SnorlaxFluteCoords are
-- exactly Snorlax's four neighbors, so a Manhattan distance of 1 from the
-- NPC matches them without hand-listing map coordinates here).
local SNORLAX_ROUTES = {
  ROUTE_12 = { obj = "ROUTE12_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE12_SNORLAX" },
  ROUTE_16 = { obj = "ROUTE16_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE16_SNORLAX" },
}

-- Is the player adjacent to a not-yet-beaten Snorlax on the current map?
-- Returns the map id and NPC to wake it, or nil.
local function adjacentSleepingSnorlax(save, ow)
  local route = ow and ow.map and SNORLAX_ROUTES[ow.map.id]
  if not route or Flags.get(save, route.beatFlag) then return nil end
  local p = ow.player
  if not p then return nil end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.name == route.obj then
      if math.abs(p.cellX - npc.cellX) + math.abs(p.cellY - npc.cellY) == 1 then
        return ow.map.id, npc
      end
      return nil
    end
  end
  return nil
end

-- Use an item on a target party mon (target may be nil for targetless
-- items).  data = generated data tables; battle = BattleState when used
-- mid-battle; ow = the overworld (OverworldState), needed only to check
-- Snorlax adjacency for a field-used POKé FLUTE.
function ItemEffects.use(data, save, itemId, target, battle, moveIndex, ow)
  local itemDef = data.items[itemId]
  local name = itemDef and itemDef.name or itemId

  local effectDef = registeredEffect(data, itemDef)
  if effectDef then
    if battle and effectDef.battle == false then
        return "failed", { notTime(data, save) }
    end

    if not battle and effectDef.field == false then
        return "failed", { notTime(data, save) }
    end

    return effectDef.use({
        data = data,
        save = save,
        itemId = itemId,
        item = itemDef,
        target = target,
        battle = battle,
        moveIndex = moveIndex,
        overworld = ow,
    })
  end

  -- ItemUseVitamin / ItemUsePPUp / ItemUseEvoStone / ItemUseCoinCase /
  -- ItemUseTMHM / ItemUseRepelCommon all refuse mid-battle
  -- (jp nz, ItemUseNotTime)
  if battle and (VITAMINS[itemId] or STONES[itemId] or itemId == "PP_UP"
                 or itemId == "RARE_CANDY" or itemId == "COIN_CASE"
                 or REPELS[itemId]
                 or (itemDef and itemDef.machine)) then
    return "failed", { notTime(data, save) }
  end

  if BALLS[itemId] then
    return "ball"
  end

  -- The POKé FLUTE wakes every sleeping Pokémon on both sides
  -- (ItemUsePokeFlute, engine/items/item_effects.asm); never consumed.
  if itemId == "POKE_FLUTE" then
    if not battle then
      -- standing next to a not-yet-beaten Snorlax: this is the ONLY way
      -- Snorlax wakes -- using the flute from the item-use menu, never
      -- just talking to it with the flute in the bag (see
      -- data/scripts/story.lua's snorlaxWake)
      local mapId, npc = adjacentSleepingSnorlax(save, ow)
      if npc then
        return "flute_wake", { romText(data, "_PlayedFluteHadEffectText",
          "{PLAYER} played the\nPOKé FLUTE.") },
          { mapId = mapId, npc = npc }
      end
      -- otherwise: play the tune, nothing happens (ItemUsePokeFlute's
      -- PlayedFluteNoEffectText branch)
      return "flute_field", { romText(data, "_PlayedFluteNoEffectText",
        "Played the POKé\nFLUTE.\fNow, that's a\ncatchy tune!") }
    end
    local woke = false
    local function wake(mon)
      if mon and mon.status == "SLP" then
        mon.status = nil
        woke = true
      end
    end
    for _, mon in ipairs(save.party) do wake(mon) end
    wake(battle.player and battle.player.mon)
    wake(battle.enemy and battle.enemy.mon)
    -- WakeUpEntireParty runs on the enemy's bench too
    for _, mon in ipairs(battle.enemyParty or {}) do wake(mon) end
    if not woke then
      return "failed", { romText(data, "_PlayedFluteNoEffectText",
        "Played the POKé\nFLUTE.\fNow, that's a\ncatchy tune!") }
    end
    return "flute", { romText(data, "_PlayedFluteHadEffectText",
                        "%s played the\nPOKé FLUTE.", save.player.name),
                      romText(data, "_FluteWokeUpText",
                        "All sleeping\nPOKéMON woke up!") }
  end

  -- battle-only items
  if X_ITEMS[itemId] or itemId == "DIRE_HIT" or itemId == "GUARD_SPEC"
     or itemId == "POKE_DOLL" then
    if not battle then
      return "failed", { notTime(data, save) }
    end
    local b = battle.player
    -- PIKAHAPPY_USEDXITEM (item_effects.asm ItemUseXAccuracy /
    -- GuardSpec / DireHit / XStat) on the active companion
    if itemId ~= "POKE_DOLL" then
      require("src.world.PikachuFollower")
        .modifyHappiness(save, "USEDXITEM", b and b.mon)
    end
    if itemId == "X_ACCURACY" then
      -- ItemUseXAccuracy sets USING_X_ACCURACY: moves never miss
      -- (not an accuracy stage)
      b.xAccuracy = true
      return "consumed", { Strings("%s's\nhits will never\nmiss!", b.name) }
    end
    if X_ITEMS[itemId] then
      local stat = X_ITEMS[itemId]
      local cur = b.stages[stat] or 0
      -- ItemUseXStat removes the item BEFORE running the stat-up
      -- effect, so at +6 it is still consumed and StatModifierUpEffect
      -- just prints "Nothing happened!"
      if cur >= 6 then
        return "consumed", { romText(data, "_NothingHappenedText",
          "Nothing happened!") }
      end
      b.stages[stat] = cur + 1
      return "consumed", { Strings("%s's\n%s rose!", b.name, stat:upper()) }
    end
    -- ItemUseDireHit/ItemUseGuardSpec always set the bit and consume
    -- the item, even when it is already active
    if itemId == "DIRE_HIT" then
      b.focusEnergy = true
      return "consumed", { romText(data, "_GettingPumpedText",
        "%s's\ngetting pumped!", b.name) }
    end
    if itemId == "GUARD_SPEC" then
      b.mist = true
      return "consumed", { Strings("%s's\nprotected against\nstat changes!", b.name) }
    end
    if itemId == "POKE_DOLL" then
      if battle.kind ~= "wild" then
        -- ItemUsePokeDoll jumps to ItemUseNotTime in trainer battles
        return "failed", { notTime(data, save) }
      end
      return "consumed_escape", { romText(data, "_WildRanText",
        "The wild POKéMON\nran away!", battle.enemy and battle.enemy.name) }
    end
  end

  -- PP restores.  The ETHERs restore the move the player picked
  -- (moveIndex, from the ItemUsePPRestore move menu); the ELIXERs
  -- restore every move with no menu.
  if itemId == "ETHER" or itemId == "MAX_ETHER"
     or itemId == "ELIXER" or itemId == "MAX_ELIXER" then
    if not target then return "failed", { noEffect(data) } end
    local restored = false
    local full = itemId == "MAX_ETHER" or itemId == "MAX_ELIXER"
    local allMoves = itemId == "ELIXER" or itemId == "MAX_ELIXER"
    local function restore(mv)
      local mdef = data.moves[mv.id]
      local maxPP = mdef and (mdef.pp + (mv.ppUps or 0) * math.floor(mdef.pp / 5))
      if maxPP and mv.pp < maxPP then
        mv.pp = full and maxPP or math.min(maxPP, mv.pp + 10)
        return true
      end
      return false
    end
    if allMoves then
      for _, mv in ipairs(target.moves) do
        restored = restore(mv) or restored
      end
    else
      local mv = target.moves[moveIndex or 1]
      restored = mv and restore(mv) or false
    end
    if not restored then
      return "failed", { noEffect(data) }
    end
    -- pokered's line names no mon, so the extracted text takes no args
    return "consumed", { romText(data, "_PPRestoredText", "PP was restored.") }
  end

  -- PIKAHAPPY_USEDITEM (item_effects.asm ItemUseMedicine, item id up to
  -- CALCIUM): fires once a medicine has a target, before the effect
  -- resolves -- potions, status cures, revives and vitamins all count,
  -- RARE_CANDY does not (its success is a LEVELUP bump instead)
  if target and (HEAL_AMOUNT[itemId] or STATUS_HEAL[itemId]
                 or itemId == "MAX_POTION" or itemId == "FULL_RESTORE"
                 or itemId == "REVIVE" or itemId == "MAX_REVIVE"
                 or VITAMINS[itemId]) then
    require("src.world.PikachuFollower")
      .modifyHappiness(save, "USEDITEM", target)
  end

  local heal = HEAL_AMOUNT[itemId]
  if heal or itemId == "MAX_POTION" or itemId == "FULL_RESTORE" then
    -- a FULL RESTORE on a statused mon already at full HP acts as a
    -- Full Heal: cured, consumed, ailment sound (item_effects.asm
    -- swaps wCurItem to FULL_HEAL and jumps to .cureStatusAilment)
    if itemId == "FULL_RESTORE" and target and target.hp > 0
       and target.hp >= target.stats.hp and target.status then
      target.status = nil
      cureActiveToxic(battle, target)
      require("src.core.Sound").play(data, "Heal_Ailment")
      return "consumed", { romText(data, CURE_TEXT.FULL_HEAL,
        "%s's\nstatus returned\nto normal!", monName(data, target)) }
    end
    if not target or target.hp <= 0 or target.hp >= target.stats.hp then
      return "failed", { noEffect(data) }
    end
    -- wHPBarOldHP: the bar animation starts from the HP the mon had BEFORE
    -- the item landed (item_effects.asm latches it with the party menu still
    -- up), so latch it here and hand it back as extra.healedFrom for the
    -- party-menu fill (#252)
    local before = target.hp
    if itemId == "MAX_POTION" or itemId == "FULL_RESTORE" then
      target.hp = target.stats.hp
    else
      target.hp = math.min(target.stats.hp, target.hp + heal)
    end
    -- _PotionText's second slot is the recovered amount ({NUM:
    -- wHPBarHPDifference}); the engine fallback never prints it
    local msgs = { romText(data, "_PotionText", "%s's HP\nwas restored!",
                     monName(data, target), target.hp - before) }
    if itemId == "FULL_RESTORE" then
      target.status = nil
      cureActiveToxic(battle, target)
    end
    require("src.core.Sound").play(data, "Heal_HP")
    return "consumed", msgs, { healedFrom = before }
  end

  local cures = STATUS_HEAL[itemId]
  if cures then
    if not target or not target.status or not cures[target.status] then
      return "failed", { noEffect(data) }
    end
    target.status = nil
    cureActiveToxic(battle, target)
    require("src.core.Sound").play(data, "Heal_Ailment")
    return "consumed", { romText(data, CURE_TEXT[itemId],
      "%s's\nstatus returned\nto normal!", monName(data, target)) }
  end

  if itemId == "REVIVE" or itemId == "MAX_REVIVE" then
    if not target or target.hp > 0 then
      return "failed", { noEffect(data) }
    end
    target.status = nil
    target.hp = itemId == "REVIVE" and math.floor(target.stats.hp / 2) or target.stats.hp
    require("src.core.Sound").play(data, "Heal_HP")
    -- a revive takes the same .healHP -> .doneHealing route, animating up
    -- from the fainted mon's 0 HP (#252)
    -- re-add to participants so the revived mon gets its share of exp
    -- at battle end (onFaint clears the flag; revive must restore it)
    if battle and battle.participants then
      battle.participants[target] = true
    end
    return "consumed", { romText(data, "_ReviveText",
      "%s\nis revitalized!", monName(data, target)) },
           { healedFrom = 0 }
  end

  if itemId == "RARE_CANDY" then
    if not target or target.level >= 100 then
      return "failed", { noEffect(data) }
    end
    local Growth = require("src.pokemon.Growth")
    local Stats = require("src.pokemon.Stats")
    local speciesDef = data.pokemon[target.species]
    target.level = target.level + 1
    target.exp = Growth.expForLevel(speciesDef.growthRate, target.level)
    local old = target.stats
    target.stats = Stats.calc(speciesDef, target.level, target.dvs, target.statExp)
    target.hp = math.min(target.stats.hp, target.hp + (target.stats.hp - old.hp))
    -- PIKAHAPPY_LEVELUP on a candy level (item_effects.asm:1540)
    require("src.world.PikachuFollower")
      .modifyHappiness(save, "LEVELUP", target)
    return "consumed", { romText(data, "_RareCandyText",
      "%s grew\nto level %d!", monName(data, target), target.level) },
           { leveledTo = target.level }
  end

  if STONES[itemId] then
    if not target then return "failed", { noEffect(data) } end
    -- Yellow's starter Pikachu never evolves: ItemUseEvoStone runs
    -- IsThisPartyMonStarterPikachu (OT identity match) before
    -- TryEvolvingMon and bails with the voiced cry + RefusingText.
    -- The stone is NOT consumed on the refuse path.
    if target.species == "PIKACHU"
       and require("src.core.GameVersion").isYellow()
       and target.ot == save.player.name
       and target.otId == save.player.id then
      require("src.core.Sound").playCry(data, "PIKACHU")
      return "failed", { romText(data, "_RefusingText",
        "%s\nis refusing!", monName(data, target)) }
    end
    local speciesDef = data.pokemon[target.species]
    for _, evo in ipairs(speciesDef.evolutions) do
      if evo.method == "ITEM" and evo.item == itemId then
        return "consumed", nil, { evolveTo = evo.species }
      end
    end
    return "failed", { noEffect(data) }
  end

  -- vitamins: +2560 stat exp, refused at 25600+ (ItemUseVitamin,
  -- engine/items/item_effects.asm)
  local vitaminStat = VITAMINS[itemId]
  if vitaminStat then
    if not target then return "failed", { noEffect(data) } end
    target.statExp = target.statExp or {}
    local cur = target.statExp[vitaminStat] or 0
    if cur >= 25600 then
      return "failed", { noEffect(data) }
    end
    target.statExp[vitaminStat] = math.min(65535, cur + 2560)
    local Stats = require("src.pokemon.Stats")
    target.stats = Stats.calc(data.pokemon[target.species], target.level,
                              target.dvs, target.statExp)
    target.hp = math.min(target.hp, target.stats.hp)
    -- _VitaminStatRoseText's slot order is localization-dependent (the
    -- Spanish ROM puts the stat before the name), so the extracted line
    -- cannot be filled positionally; the engine wording stands
    return "consumed", { Strings("%s's %s\nrose!", monName(data, target),
      vitaminStat == "hp" and "HP" or vitaminStat:upper()) }
  end

  -- PP UP boosts the move the player picked (ItemUsePPUp's move menu)
  if itemId == "PP_UP" then
    if not target then return "failed", { noEffect(data) } end
    local mv = target.moves[moveIndex or 1]
    local mdef = mv and data.moves[mv.id]
    if mdef and (mv.ppUps or 0) < 3 then
      mv.ppUps = (mv.ppUps or 0) + 1
      -- each PP UP adds maxPP/5 uses on top of the base maximum
      mv.pp = mv.pp + math.floor(mdef.pp / 5)
      return "consumed", { romText(data, "_PPIncreasedText",
        "%s's PP\nincreased!", mdef.name) }
    end
    return "failed", { noEffect(data) }
  end

  if itemDef and itemDef.machine then
    if not target then return "failed", { noEffect(data) } end
    local speciesDef = data.pokemon[target.species]
    local ok = false
    for _, m in ipairs(speciesDef.tmhm) do
      if m == itemDef.machine.move then ok = true break end
    end
    if not ok then
      -- the only item-use refusal with a sound in pokered: item_effects.asm
      -- plays SFX_DENIED before MonCannotLearnMachineMoveText (the generic
      -- ItemUseNotTime/NoCyclingAllowedHere paths are silent)
      require("src.core.Sound").play(data, "Denied")
      local moveName = data.moves[itemDef.machine.move].name
      return "failed", { romText(data, "_MonCannotLearnMachineMoveText",
        "%s can't\nlearn that move!",
        monName(data, target), moveName, moveName) }
    end
    for _, mv in ipairs(target.moves) do
      if mv.id == itemDef.machine.move then
        return "failed", { romText(data, "_AlreadyKnowsText",
          "It knows that\nmove already!",
          monName(data, target), data.moves[itemDef.machine.move].name) }
      end
    end
    -- HMs are never consumed; TMs are single-use
    return (itemDef.machine.kind == "HM" and "learnkept" or "learn"), itemDef.machine.move
  end

  if itemId == "OLD_ROD" or itemId == "GOOD_ROD" or itemId == "SUPER_ROD" then
    if battle then
      return "failed", { notTime(data, save) }
    end
    -- FishingInit (engine/items/item_effects.asm): cp wWalkBikeSurfState, 2
    -- (surfing) sets carry, and every ItemUseXRod does jp c, ItemUseNotTime
    -- on that carry -- surfing refuses the rod with the same OAK text as
    -- the mid-battle case above, no rod-specific message (#533)
    if ow and ow.player and ow.player.surfing then
      return "failed", { notTime(data, save) }
    end
    return "fish", itemId
  end

  if itemId == "BICYCLE" then
    if battle then
      return "failed", { notTime(data, save) }
    end
    -- ItemUseBicycle (engine/items/item_effects.asm) opens with
    -- `cp 2 ; is the player surfing?` -> jp z, ItemUseNotTime, so the
    -- BICYCLE refuses on the water with the same OAK text as the rods
    -- above (#846)
    if ow and ow.player and ow.player.surfing then
      return "failed", { notTime(data, save) }
    end
    return "bicycle"
  end

  if itemId == "ESCAPE_ROPE" then
    return "escape_rope"
  end
  if itemId == "TOWN_MAP" then
    if battle then
      return "failed", { notTime(data, save) }
    end
    return "townmap"
  end
  if itemId == "ITEMFINDER" then
    if battle then
      return "failed", { notTime(data, save) }
    end
    return "itemfinder"
  end
  if itemId == "COIN_CASE" then
    return "failed", { romText(data, "_CoinCaseNumCoinsText",
      "Coin count:\n%d", save.coins or 0) }
  end
  if REPELS[itemId] then
    local steps = itemId == "REPEL" and 100 or itemId == "SUPER_REPEL" and 200 or 250
    save.repelSteps = steps
    return "consumed", { Strings("%s used\n%s!", save.player.name, name) }
  end

  return "failed", { notTime(data, save) }
end

return ItemEffects
