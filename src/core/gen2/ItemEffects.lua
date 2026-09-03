-- Gen 2 pack items used on a party mon outside battle: the ITEMMENU_PARTY
-- half of engine/items/pack.asm UseItem, ported per item family from
-- engine/items/item_effects.asm.
--
-- Love-free on purpose, the same split src/core/gen2/Evolution.lua makes:
-- every routine here is table math over a party record, so the whole family
-- is assertable without a window.  The screens (PackMenu -> PartyMenu ->
-- MoveDeleter) only choose the target and print what comes back.
--
-- Two contracts every entry point keeps, both from UseItem_SelectMon:
--   - an EGG refuses with CantUseOnEggMessage before any effect runs
--     (`cp EGG` is the routine's first test after the pick), and
--   - a refusal costs nothing: the item is only removed by the caller when
--     `used` comes back true, which is UseDisposableItem's own placement at
--     the tail of each success path.

local Happiness = require("src.core.gen2.Happiness")
local Mon = require("src.battle.gen2.Mon")
local Strings = require("src.core.Strings")

local ItemEffects = {}

-- data/items/heal_hp.asm HealingHPAmounts.  MAX_STAT_VALUE (999) is the
-- table's own "everything" byte pair; nothing reaches it before the min()
-- against the missing HP.
ItemEffects.HEAL_HP = {
  FRESH_WATER = 50, SODA_POP = 60, LEMONADE = 80,
  HYPER_POTION = 200, SUPER_POTION = 50, POTION = 20,
  MAX_POTION = 999, FULL_RESTORE = 999, MOOMOO_MILK = 100,
  BERRY = 10, GOLD_BERRY = 30, ENERGYPOWDER = 50, ENERGY_ROOT = 200,
  RAGECANDYBAR = 20, BERRY_JUICE = 20,
}

-- data/items/heal_status.asm StatusHealingActions, folded to the status class
-- each row's mask names.  FULL_RESTORE is deliberately absent: its status
-- half only runs from FullRestoreEffect's full-HP arm, handled in useOnMon.
ItemEffects.HEAL_STATUS = {
  ANTIDOTE = "psn", BURN_HEAL = "brn", ICE_HEAL = "frz",
  AWAKENING = "slp", PARLYZ_HEAL = "par",
  FULL_HEAL = "all", HEAL_POWDER = "all",
  PSNCUREBERRY = "psn", PRZCUREBERRY = "par", BURNT_BERRY = "frz",
  ICE_BERRY = "brn", MINT_BERRY = "slp", MIRACLEBERRY = "all",
}

-- RevivePokemon's one split: `cp REVIVE / jr z, .revive_half_hp` -- only the
-- plain REVIVE halves, MAX_REVIVE and REVIVAL_HERB both take ReviveFullHP.
ItemEffects.REVIVE = {
  REVIVE = "half", MAX_REVIVE = "full", REVIVAL_HERB = "full",
}

-- RestorePP's per-item amounts: `ld c, 10` for the ETHER family, `ld c, 5`
-- under `cp MYSTERYBERRY`, and the `.restore_all` arm for the MAX pair.
-- `each` marks Elixer_RestorePPofAllMoves' loop over all four slots.
ItemEffects.RESTORE_PP = {
  ETHER = { amount = 10 },
  MAX_ETHER = { amount = "all" },
  MYSTERYBERRY = { amount = 5 },
  ELIXER = { amount = 10, each = true },
  MAX_ELIXER = { amount = "all", each = true },
}

-- engine/items/item_effects.asm:1245 StatExpItemPointerOffsets.
ItemEffects.VITAMIN = {
  HP_UP = "hp", PROTEIN = "attack", IRON = "defense",
  CARBOS = "speed", CALCIUM = "special",
}

-- EnergypowderEnergyRootCommon / HealPowderEffect: the herb items charge
-- happiness for tasting bitter on top of their heal.
local BITTER = {
  ENERGYPOWDER = "BITTERPOWDER", ENERGY_ROOT = "ENERGYROOT",
  HEAL_POWDER = "BITTERPOWDER", REVIVAL_HERB = "REVIVALHERB",
}

-- _ItemWontHaveEffectText / _ItemCantUseOnEggText (data/text/common_3.asm).
-- Strings.source keeps these in the catalog harvest even though they are
-- declared here and only formatted/looked up at each use site below (#186,
-- #245): every use site was a bare table read or a direct :format() call
-- until now, which meant a mod's translation catalog never had a chance to
-- apply -- every language showed this same English text.
ItemEffects.TEXT_NO_EFFECT = Strings.source("It won't have any\neffect.")
ItemEffects.TEXT_CANT_USE_ON_EGG = Strings.source("That can't be used\non an EGG.")
-- _ItemCantUseOnMonText (data/text/common_3.asm:1265).
ItemEffects.TEXT_CANT_USE_ON_MON = Strings.source("That can't be used\non this #MON.")
-- _PPRestoredText (data/text/common_3.asm).
ItemEffects.TEXT_PP_RESTORED = Strings.source("PP was restored.")
-- _PPIsMaxedOutText / _PPsIncreasedText (data/text/common_3.asm).
ItemEffects.TEXT_PP_MAXED = Strings.source("%s's PP\nis maxed out.")
ItemEffects.TEXT_PP_INCREASED = Strings.source("%s's PP\nincreased.")

-- PrintPartyMenuActionText's .MenuActionTexts (engine/pokemon/party_menu.asm),
-- keyed by the class GetItemHealingAction resolves.  Each is the two rows the
-- cart prints: the nickname line, then the fixed line.  Strings.source for
-- the same reason as the constants above: healStatus() below formats these
-- directly at each use, so without it a mod's catalog never sees them.
local STATUS_TEXT = {
  psn = Strings.source("%s's\ncured of poison."),
  par = Strings.source("%s's\nrid of paralysis."),
  brn = Strings.source("%s's\nburn was healed."),
  frz = Strings.source("%s\nwas defrosted."),
  slp = Strings.source("%s\nwoke up."),
  all = Strings.source("%s's\nhealth returned."),
}

-- The port's party records spell status several ways (the battle writes the
-- long names, the party list reads both); fold them to the class letters the
-- heal tables use.  FNT is an HP fact, not a status, and is not here.
--
-- Cross-file contract: every name src/battle/gen2/Battle.lua can write into
-- mon.status (STATUS_EFFECTS, SECONDARY_EFFECTS, HELD_STATUS_CURES and the
-- STATUS_TEXT lines beside them) must have a row here, or the cure for it
-- refuses everywhere in the pack.  tests/gen2_battle_pack_test.lua walks the
-- battle's own tables against this one so the two cannot drift apart.
ItemEffects.STATUS_CLASS = {
  psn = "psn", poison = "psn", toxic = "psn",
  brn = "brn", burn = "brn",
  frz = "frz", freeze = "frz",
  par = "par", paralysis = "par", paralyze = "par",
  slp = "slp", sleep = "slp",
}
local STATUS_CLASS = ItemEffects.STATUS_CLASS

local function monName(mon)
  return (mon and (mon.nickname or mon.name or mon.species)) or "?"
end

local function maxHpOf(mon)
  return mon.maxHp or (mon.stats and mon.stats.hp) or 0
end

local function fainted(mon)
  return (mon.hp or 0) <= 0
end

-- HealStatus's field half: the status byte, the toxic counter and the turn
-- counter all clear together (wPlayerSubStatus5's SUBSTATUS_TOXIC rides the
-- same wipe on the cart; this port keeps that ramp on the mon record, so it
-- goes with the byte rather than with the battler).
local function clearStatus(mon)
  mon.status = nil
  mon.statusTurns = nil
  mon.toxicCounter = nil
end

local function bitterHappiness(itemId, mon)
  local event = BITTER[itemId]
  if event then Happiness.change(mon, event) end
end

-- ItemRestoreHP: fainted and full-HP targets refuse before anything is spent,
-- then RestoreHealth adds the HealingHPAmounts row capped at max HP.
local function restoreHp(itemId, mon)
  local amount = ItemEffects.HEAL_HP[itemId]
  local maxHp = maxHpOf(mon)
  if fainted(mon) or (mon.hp or 0) >= maxHp then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  local healed = math.min(maxHp, (mon.hp or 0) + amount)
  local gained = healed - (mon.hp or 0)
  mon.hp = healed
  -- FullRestoreEffect's .FullRestore clears the status alongside the refill.
  if itemId == "FULL_RESTORE" then clearStatus(mon) end
  bitterHappiness(itemId, mon)
  return {
    used = true,
    -- data/text/common_1.asm:30
    -- home/text.asm:772
    text = Strings("%s\nrecovered %dHP!", monName(mon), gained),
  }
end

-- Which StatusHealingActions class cures this status.  The fold table above
-- answers for every spelling the port writes; anything it does not know is a
-- status some mod registered, and its own `statuses` record says which cure
-- answers for it (src/battle/gen2/Battle.lua STATUSES, field `healClass`) --
-- read straight off the merged table so this module does not have to require
-- the battle engine to cure a burn.
function ItemEffects.healClassOf(status, data)
  local key = tostring(status or ""):lower()
  local class = STATUS_CLASS[key]
  if class then return class end
  local statuses = data and data.gen2Statuses
  local record = statuses and (statuses[status] or statuses[key])
  return record and record.healClass or nil
end

-- UseStatusHealer: the status byte must intersect the item's mask ($ff for
-- the HEAL_ALL family); a clean or fainted mon refuses.  Field only -- the
-- confusion arm reads wPlayerSubStatus3, which does not exist out of battle.
local function healStatus(itemId, mon, class, data)
  if fainted(mon) then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  local have = ItemEffects.healClassOf(mon.status, data)
  if not have or (class ~= "all" and have ~= class) then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  clearStatus(mon)
  bitterHappiness(itemId, mon)
  local shape = STATUS_TEXT[class == "all" and "all" or have]
  return { used = true, text = Strings(shape, monName(mon)) }
end

-- RevivePokemon: only a fainted mon accepts; REVIVE stands it up at half max
-- HP (ReviveHalfHP's `srl d / rr e`), the other two at full.
local function revive(itemId, mon)
  if not fainted(mon) then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  local maxHp = maxHpOf(mon)
  mon.hp = (ItemEffects.REVIVE[itemId] == "half")
    and math.max(1, math.floor(maxHp / 2)) or maxHp
  clearStatus(mon)
  bitterHappiness(itemId, mon)
  return {
    used = true,
    text = Strings("%s\nis revitalized.", monName(mon)),
  }
end

-- RareCandyEffect: MAX_LEVEL refuses; otherwise the level goes up one, the
-- experience is SET to CalcExpAtLevel's threshold, the stats recompute and
-- the CURRENT HP gains the max-HP delta -- no clamp and no faint check, so a
-- fainted mon stands up with the delta, exactly as the cart's arithmetic
-- leaves it.  `learned` is LearnLevelMoves' slice: the EvosAttacks rows at
-- exactly the new level, for the caller to offer.
local function rareCandy(mon, data)
  if (mon.level or 0) >= Mon.MAX_LEVEL then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  local def = data and data.pokemon and data.pokemon[mon.species]
  -- through Mon.growthFor, so a growth_rates record a mod registered is the
  -- curve a Rare Candy uses too; wiring only some of the six readers would let
  -- a mod curve drive battle EXP but not the candy
  local growth = Mon.growthFor(data, def and def.growthRate)
  local newLevel = (mon.level or 1) + 1
  mon.level = newLevel
  mon.experience = Mon.experienceForLevel(growth, newLevel)
  local previousMax = maxHpOf(mon)
  if def and def.baseStats then
    mon.stats = Mon.stats(def.baseStats, mon.dvs, newLevel, mon.statExp)
    mon.maxHp = mon.stats.hp
    mon.hp = (mon.hp or previousMax) + (mon.maxHp - previousMax)
  end
  Happiness.change(mon, "GAINLEVEL")
  local learned = {}
  for _, entry in ipairs((def and def.levelMoves) or {}) do
    if entry.level == newLevel then learned[#learned + 1] = entry.move end
  end
  return {
    used = true,
    level = newLevel,
    learned = learned,
    -- data/text/common_1.asm:86
    sfx = "Sfx_DexFanfare5079",
    text = Strings("%s grew to\nlevel %d!", monName(mon), newLevel),
  }
end

-- engine/items/item_effects.asm:1216 StatStrings. Strings.source per entry,
-- the same pattern as the identical stat-name tables in MoveEffects.lua/
-- TrainerAI.lua/gen2/Effects.lua/ContestMenu.lua/SummaryMenu.lua, so a mod's
-- catalog harvest finds these independently of any other stat-name call site.
local VITAMIN_LABEL = {
  hp = Strings.source("HEALTH"), attack = Strings.source("ATTACK"),
  defense = Strings.source("DEFENSE"), speed = Strings.source("SPEED"),
  special = Strings.source("SPECIAL"),
}

-- engine/items/item_effects.asm:1149 VitaminEffect.
local function vitamin(itemId, mon, data)
  local stat = ItemEffects.VITAMIN[itemId]
  mon.statExp = mon.statExp or Mon.newStatExp()
  local cur = mon.statExp[stat] or 0
  if cur >= 25600 then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  mon.statExp[stat] = math.min(Mon.MAX_STAT_EXP, cur + 2560)
  local def = data and data.pokemon and data.pokemon[mon.species]
  if def and def.baseStats then
    mon.stats = Mon.stats(def.baseStats, mon.dvs, mon.level, mon.statExp)
    mon.maxHp = mon.stats.hp
  end
  Happiness.change(mon, "USEDITEM")
  return {
    used = true,
    text = Strings("%s's\n%s rose.", monName(mon), Strings(VITAMIN_LABEL[stat])),
  }
end

-- --------------------------------------------------------- held attributes
--
-- The `held_items` registry (src/mods/Schemas.lua), which is the last two
-- columns of data/items/attributes.asm lifted out of the item record:
-- ItemAttributes' HELD_* effect byte and its parameter.  Gen 1 has neither, so
-- this is one of the Gen 2-only registries -- gated under Gen 1, routed to
-- data.gen2HeldItems under Gen 2.
--
-- The table is a VIEW of data.items rather than a second source of truth: the
-- extractor writes both columns onto the item record and
-- src/battle/gen2/Battle.lua:itemDef reads them from there, so the registry
-- has to end up back on data.items or a mod's write would land in a table the
-- battle never opens.  Hence the three routines below and the two calls in
-- src/core/Game2.lua:load that use them:
--
--   heldItemsFrom(items)  builds the merge target, BEFORE mods:load, so the
--                         registry's base is the vanilla row and a mod's
--                         patch stacks on top of it (register collides, the
--                         way it does against any other seeded id)
--   heldSnapshot(view)    the same two bytes per id, kept aside
--   applyHeldItems(...)   AFTER the merge: writes back only the ids whose
--                         merged value differs from that snapshot
--
-- The diff is the whole reason this is not a blind write-back.  A mod may just
-- as well reach an item's held columns through the shared `items` registry;
-- that merge has already landed on data.items by the time this runs, and
-- writing every row back would revert it to the vanilla view captured before
-- the merge.  Only what the held_items merge actually changed is written, so
-- the two routes compose instead of racing.
function ItemEffects.heldItemsFrom(items)
  local out = {}
  for id, def in pairs(items or {}) do
    if type(def) == "table" and def.heldEffect ~= nil then
      out[id] = { heldEffect = def.heldEffect,
                  heldParameter = def.heldParameter or 0 }
    end
  end
  return out
end

function ItemEffects.heldSnapshot(view)
  local out = {}
  for id, row in pairs(view or {}) do
    if type(row) == "table" then
      out[id] = { heldEffect = row.heldEffect, heldParameter = row.heldParameter }
    end
  end
  return out
end

-- the merged `held_items` record for an item, the item's own columns when no
-- loader ran
function ItemEffects.heldItemFor(itemId, data)
  if itemId == nil then return nil end
  local merged = data and data.gen2HeldItems
  local row = merged and merged[itemId]
  if row then return row end
  local def = data and data.items and data.items[itemId]
  if type(def) ~= "table" or def.heldEffect == nil then return nil end
  return { heldEffect = def.heldEffect, heldParameter = def.heldParameter or 0 }
end

-- Returns the number of item records the merge changed.  Zero on a mod-free
-- boot, which is the parity claim: the seeded row IS the item's own two bytes,
-- so nothing differs and nothing is written.
function ItemEffects.applyHeldItems(data, snapshot)
  local items = data and data.items
  local merged = data and data.gen2HeldItems
  if not (items and merged) then return 0 end
  local applied = 0
  for id, row in pairs(merged) do
    if type(row) == "table" then
      local was = (snapshot or {})[id]
      if not was or was.heldEffect ~= row.heldEffect
          or was.heldParameter ~= row.heldParameter then
        local def = items[id]
        if type(def) == "table" then
          def.heldEffect = row.heldEffect
          def.heldParameter = row.heldParameter or 0
          applied = applied + 1
        end
      end
    end
  end
  -- a tombstoned id (mod.content.held_items:remove) leaves the merged table
  -- without the row, which is the cart's own "holds nothing"
  for id, was in pairs(snapshot or {}) do
    if merged[id] == nil and type(items[id]) == "table" and was.heldEffect then
      items[id].heldEffect = nil
      items[id].heldParameter = nil
      applied = applied + 1
    end
  end
  return applied
end

-- the merged `item_effects` record for an item id, the module's own when no
-- loader ran; `data` is optional so the callers that only know an item id
-- (src/core/Game2.lua asks partyAction before it has picked a mon) keep
-- their signature and read the module records
function ItemEffects.recordFor(itemId, data)
  if itemId == nil then return nil end
  local merged = data and data.gen2ItemEffects
  return (merged and merged[itemId]) or ItemEffects.RECORDS[itemId]
end

-- Which family a PACK item runs on a party mon, or nil for an id with no
-- item_effects record (engine/items/pack.asm UseItem, ITEMMENU_PARTY arm).
function ItemEffects.partyAction(itemId, data)
  local record = ItemEffects.recordFor(itemId, data)
  return record and record.action or nil
end

-- The one-call families (everything but PP, which needs a move pick first).
-- Returns { used, text, learned?, level? }.
function ItemEffects.useOnMon(itemId, mon, data)
  if not mon then return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) } end
  if mon.isEgg then
    return { used = false, text = Strings(ItemEffects.TEXT_CANT_USE_ON_EGG) }
  end
  local record = ItemEffects.recordFor(itemId, data)
  -- The PP family has its own entry point; reaching it here is the same
  -- "nothing happens" the unported items get.
  if not record or not record.use or record.action == "pp" then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  return record.use({ item = itemId, mon = mon, data = data })
end

-- RestorePP over one move entry: a slot already at max refuses (`cp b /
-- jr nc, .dont_restore`), "all" fills it, a number adds capped at max.
local function restoreMove(move, amount)
  if type(move) ~= "table" or not move.id then return false end
  local maxPp = move.maxPp or move.pp or 0
  if (move.pp or 0) >= maxPp then return false end
  if amount == "all" then
    move.pp = maxPp
  else
    move.pp = math.min(maxPp, (move.pp or 0) + amount)
  end
  return true
end

-- RestorePPEffect's two shapes: the ETHER family lands on one chosen slot,
-- the ELIXER family (Elixer_RestorePPofAllMoves) walks every slot and counts
-- -- one restored move is enough for the item to be spent.
function ItemEffects.usePpItem(itemId, mon, slot, data)
  if not mon then return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) } end
  if mon.isEgg then
    return { used = false, text = Strings(ItemEffects.TEXT_CANT_USE_ON_EGG) }
  end
  local record = ItemEffects.recordFor(itemId, data)
  if not record or not record.use or record.action ~= "pp" then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  return record.use({ item = itemId, mon = mon, data = data, slot = slot })
end

-- ------------------------------------------------------------- the registry
--
-- The four tables above as records, in the shape src/mods/Schemas.lua's
-- `item_effects` registry validates.  Same registry NAME the Gen 1 catalog
-- carries, and the same two Gen 1 fields where Gen 2 has a meaning for them:
-- `use` (required) and `field`, which is true for every row here because this
-- module is the ITEMMENU_PARTY half of pack.asm and nothing else.
--
-- `use` is fn(ctx) -> { used, text, learned?, level? }, where ctx carries
-- { item, mon, data, slot }.  Gen 1 has no call site for its own item_effects
-- records yet, so this is the first shape either generation gives them; it is
-- the one Gold's two entry points already hand around.
--
-- Two fields Gen 2 adds rather than renaming anything: `action`, the family
-- src/core/Game2.lua and src/ui/gen2/BattleState.lua branch on before they
-- know a target (it is what partyAction answers), and `needsTarget`, which
-- the same screens read as "pick a party mon first".
ItemEffects.RECORDS = {}

local function record(itemId, action, use)
  ItemEffects.RECORDS[itemId] = {
    use = use, action = action, field = true, needsTarget = true,
  }
end

-- Built in reverse precedence order, so an id that appeared in two of the
-- source tables would resolve the way partyAction's if-chain used to: heal
-- first, then status, revive, candy and pp.  Nothing overlaps today; the order
-- is what keeps that true if something ever does.
for itemId, row in pairs(ItemEffects.RESTORE_PP) do
  record(itemId, "pp", function(ctx)
    -- RestorePPEffect's two shapes: the ETHER family lands on the chosen slot,
    -- the ELIXER family (Elixer_RestorePPofAllMoves) walks every slot and
    -- counts -- one restored move is enough for the item to be spent.
    local moves = ctx.mon.moves or {}
    local any = false
    if row.each then
      for _, move in ipairs(moves) do
        if restoreMove(move, row.amount) then any = true end
      end
    else
      any = restoreMove(moves[ctx.slot], row.amount)
    end
    if not any then
      return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
    end
    return { used = true, text = Strings(ItemEffects.TEXT_PP_RESTORED) }
  end)
end

-- engine/items/item_effects.asm:2320 RestorePPEffect's PP_UP arm.
record("PP_UP", "pp", function(ctx)
  local move = (ctx.mon.moves or {})[ctx.slot]
  if type(move) ~= "table" or not move.id then
    return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
  end
  local row = ((ctx.data and ctx.data.moves) or {})[move.id]
  local name = (row and row.name) or move.id
  -- constants/pokemon_data_constants.asm:216 PP_UP_MASK.
  if move.id == "SKETCH" or (move.ppUps or 0) >= 3 then
    return { used = false, text = Strings(ItemEffects.TEXT_PP_MAXED, name) }
  end
  local base = (row and row.pp) or move.maxPp
  if not base then
    return { used = false, text = Strings(ItemEffects.TEXT_PP_MAXED, name) }
  end
  -- engine/items/item_effects.asm:2736 ComputeMaxPP.
  local bonus = math.min(math.floor(base / 5), 7)
  move.ppUps = (move.ppUps or 0) + 1
  move.maxPp = base + move.ppUps * bonus
  move.pp = (move.pp or 0) + bonus
  return { used = true, text = Strings(ItemEffects.TEXT_PP_INCREASED, name) }
end)

for itemId in pairs(ItemEffects.VITAMIN) do
  record(itemId, "vitamin", function(ctx)
    return vitamin(ctx.item, ctx.mon, ctx.data)
  end)
end

record("RARE_CANDY", "candy", function(ctx)
  return rareCandy(ctx.mon, ctx.data)
end)

for _, itemId in ipairs({ "SUN_STONE", "MOON_STONE", "FIRE_STONE",
                          "THUNDERSTONE", "WATER_STONE", "LEAF_STONE" }) do
  record(itemId, "stone", function(ctx)
    if ctx.mon.item == "EVERSTONE" then
      return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) }
    end
    local Evolution = require("src.core.gen2.Evolution")
    local entry = Evolution.checkMon(ctx.data, ctx.mon,
      { force = true, item = ctx.item })
    if not entry then return { used = false, text = Strings(ItemEffects.TEXT_NO_EFFECT) } end
    return { used = true, evolution = entry }
  end)
end

for itemId in pairs(ItemEffects.REVIVE) do
  record(itemId, "revive", function(ctx) return revive(ctx.item, ctx.mon) end)
end

for itemId, class in pairs(ItemEffects.HEAL_STATUS) do
  record(itemId, "status", function(ctx)
    return healStatus(ctx.item, ctx.mon, class, ctx.data)
  end)
end

for itemId in pairs(ItemEffects.HEAL_HP) do
  record(itemId, "heal", function(ctx)
    -- FullRestoreEffect: a full-HP target falls through to FullyHealStatus
    -- rather than refusing, so a paralyzed mon at full health is still cured.
    if ctx.item == "FULL_RESTORE" and not fainted(ctx.mon)
        and (ctx.mon.hp or 0) >= maxHpOf(ctx.mon) then
      return healStatus(ctx.item, ctx.mon, "all", ctx.data)
    end
    return restoreHp(ctx.item, ctx.mon)
  end)
end

-- vanilla registrations, engine-owned (Schemas.ENGINE), so a mod's register of
-- one of these ids collides the way it does on Red and has to say override
function ItemEffects.registerInto(registry, _, owner)
  for id, entry in pairs(ItemEffects.RECORDS) do
    registry:register(id, entry, owner)
  end
end

return ItemEffects
