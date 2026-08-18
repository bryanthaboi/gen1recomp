-- A Gen 2 party member: stats, moves, level-up and experience.
--
-- Separate from src/pokemon/Pokemon.lua because the struct itself changed:
-- Gen 2 splits `special` into Special Attack and Special Defense, adds a held
-- item, happiness and pokerus, and its level-up moves come from EvosAttacks
-- rather than a Gen 1 learnset table.
--
-- Stat formula is unchanged from Gen 1 (data/pokemon/base_stats + DVs):
--   stat = floor((base * 2 + DV * 2 + floor(sqrt(statExp) / 4)) * level / 100) + 5
--   HP is the same but + level + 10
-- with the Gen 2 twist that a mon's SpA and SpD share one Special DV, which is
-- why a high-Special DV raises both.
--
-- Experience curves come from data/growth_rates.asm, whose `growth_rate` macro
-- documents its own polynomial:
--   [1]/[2] * n^3 + [3] * n^2 + [4] * n - [5]
-- with a sign bit on the n^2 term.  pokemon.lua carries those five numbers per
-- GROWTH_* so this needs no hardcoded table.

local Unown = require("src.core.gen2.Unown")
-- The mod event bus.  pokemon.level_up and pokemon.move_learned are the SAME
-- names src/battle/Experience.lua and src/battle/BattleState.lua raise on
-- Gen 1, with the same payload keys: a mod that watches a Red party watches a
-- Gold one unchanged (docs/mod-api-gen2-compat.md).
local Runtime = require("src.mods.Runtime")

local Mon = {}

Mon.MAX_LEVEL = 100
Mon.PARTY_SIZE = 6

-- DVs are 0..15 each; Attack's low bit pair also decides gender and shininess.
Mon.MAX_DV = 15

local function rand(a, b)
  if love and love.math and love.math.random then
    return love.math.random(a, b)
  end
  return math.random(a, b)
end

function Mon.randomDVs()
  return {
    hp = nil, -- derived below
    attack = rand(0, Mon.MAX_DV),
    defense = rand(0, Mon.MAX_DV),
    speed = rand(0, Mon.MAX_DV),
    special = rand(0, Mon.MAX_DV),
  }
end

-- The HP DV is not stored: it is the low bit of each of the other four
-- (Gen 1 and 2 both build it this way), which is why a perfect-HP mon needs
-- all four others odd.
function Mon.hpDV(dvs)
  local function bit(value) return (value or 0) % 2 end
  return bit(dvs.attack) * 8 + bit(dvs.defense) * 4
    + bit(dvs.speed) * 2 + bit(dvs.special)
end

local function statValue(base, dv, level, statExp)
  local exp = math.floor(math.sqrt(statExp or 0) / 4)
  return math.floor((((base or 1) * 2 + (dv or 0) * 2 + exp) * level) / 100) + 5
end

-- All six stats at a level.  `statExp` is optional per-stat effort.
function Mon.stats(baseStats, dvs, level, statExp)
  baseStats = baseStats or {}
  dvs = dvs or {}
  statExp = statExp or {}
  -- engine/pokemon/move_mon.asm:1540
  local specialDv = dvs.special
  if specialDv == nil then
    specialDv = dvs.specialAttack or dvs.specialDefense
  end
  -- engine/pokemon/move_mon.asm:1496
  local hpDv = Mon.hpDV({
    attack = dvs.attack, defense = dvs.defense,
    speed = dvs.speed, special = specialDv,
  })
  local hp = math.floor((((baseStats.hp or 1) * 2 + hpDv * 2
    + math.floor(math.sqrt(statExp.hp or 0) / 4)) * level) / 100)
    + level + 10
  return {
    hp = hp,
    attack = statValue(baseStats.attack, dvs.attack, level, statExp.attack),
    defense = statValue(baseStats.defense, dvs.defense, level, statExp.defense),
    speed = statValue(baseStats.speed, dvs.speed, level, statExp.speed),
    -- One Special DV feeds both special stats, and so does one Special stat
    -- exp: the Gen 2 party struct kept Gen 1's five exp words (macros/ram.asm
    -- box_struct ends them at SpcExp), so SpA and SpD grow together.  The
    -- per-stat keys are still read as a fallback for a record written before
    -- the shared word existed.
    specialAttack = statValue(baseStats.specialAttack, specialDv, level,
      statExp.special or statExp.specialAttack),
    specialDefense = statValue(baseStats.specialDefense, specialDv, level,
      statExp.special or statExp.specialDefense),
  }
end

-- The species string is the source of truth.  `mon.name` is a copy of that
-- species' display name (GetPokemonName), kept so menus can print without a
-- Data lookup.  It is NOT the nickname: an un-nicknamed mon has nickname nil
-- and prints this copy.  Changing species without rewriting it leaves the
-- previous species' name on the party list and the SUMMARY's top line.
function Mon.syncIdentity(mon, data)
  if type(mon) ~= "table" then return mon end
  local def = data and data.pokemon and data.pokemon[mon.species]
  if not def then return mon end
  mon.name = def.name or mon.species
  if def.types then mon.types = def.types end
  if mon.dvs then
    mon.gender = Mon.gender(def, mon.dvs,
      { species = mon.species, level = mon.level })
    -- shiny is monotonic once true, the same as opts.shiny winning over
    -- shiny.roll at Mon.new: a forced shiny (the scripted-shiny path, DVs
    -- that do not themselves read as shiny) must not un-shiny the moment
    -- this runs again, and it runs on every SummaryMenu open via
    -- refreshStats.  A mon not already shiny still promotes normally if
    -- its DVs justify it, e.g. after an edit.
    mon.shiny = mon.shiny or Mon.isShiny(mon.dvs,
      { species = mon.species, def = def, level = mon.level })
    if mon.species == Unown.SPECIES then
      mon.unownLetter = Unown.letterFromDVs(mon.dvs)
    else
      mon.unownLetter = nil
    end
  end
  return mon
end

-- Every screen that prints a mon without a Data lookup should go through here:
-- nickname if the player set one, otherwise the species display copy `name`.
-- Skipping `name` and jumping to `species` is how a swapped mon can still
-- read as ABRA on one menu and RAYQUAZA on another.
function Mon.displayName(mon)
  if type(mon) ~= "table" then return "?" end
  return mon.nickname or mon.name or mon.species or "?"
end

-- Party, boxes, both Day-Care sides, and a pending egg.  Editor CONTINUE and
-- hydrate have to walk the same set: leaving dayCare.man.mon on the old
-- `name` is the ABRA bug in a second closet.
function Mon.eachSaveMon(save, fn)
  if type(save) ~= "table" or type(fn) ~= "function" then return end
  for _, mon in ipairs(save.party or {}) do fn(mon) end
  for _, box in pairs(save.boxes or {}) do
    if type(box) == "table" then
      for _, mon in ipairs(box) do fn(mon) end
    end
  end
  local dc = save.dayCare
  if type(dc) == "table" then
    if dc.man and dc.man.mon then fn(dc.man.mon) end
    if dc.lady and dc.lady.mon then fn(dc.lady.mon) end
    if dc.egg then fn(dc.egg) end
  end
  if save.daycare and save.daycare.mon then fn(save.daycare.mon) end
end

function Mon.syncSaveIdentity(save, data)
  Mon.eachSaveMon(save, function(mon) Mon.syncIdentity(mon, data) end)
end

function Mon.refreshStats(mon, data)
  if type(mon) ~= "table" then return mon end
  local def = data and data.pokemon and data.pokemon[mon.species]
  if not (def and def.baseStats) then return mon end
  Mon.syncIdentity(mon, data)
  -- engine/pokemon/move_mon.asm:1402
  local stats = Mon.stats(def.baseStats, mon.dvs, mon.level or 1, mon.statExp)
  mon.stats = stats
  mon.maxHp = stats.hp
  if mon.hp == nil or mon.hp > stats.hp then
    mon.hp = stats.hp
  end
  return mon
end

-- The five stat exp words, in struct order.  There is no sixth: see Mon.stats.
Mon.STAT_EXP_ORDER = { "hp", "attack", "defense", "speed", "special" }

-- Each word is 16 bit and GiveExperiencePoints stops it at $ffff rather than
-- letting it wrap (.stat_exp_maxed_out).
Mon.MAX_STAT_EXP = 65535

function Mon.newStatExp()
  return { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
end

-- GiveExperiencePoints' .stat_exp_loop (engine/battle/core.asm): the defeated
-- mon's base stats are added to every participant's stat exp, and the loop runs
-- NUM_EXP_STATS = 5 times over a six-entry base stat block, so the Special word
-- takes the loser's Special ATTACK and the Special Defense base stat is never
-- read at all.
--
-- `.EvenlyDivideExpAmongParticipants` divides the base stats in place before
-- any of this, and only when two or more mons took part, which is why the
-- divisor is shared with Mon.experienceGain rather than computed here.
--
-- Pokerus adds the same value a SECOND time (`jr z, .stat_exp_awarded` skips
-- the second add when the byte is zero) -- doubled, not multiplied by a rate,
-- so it stacks with nothing.
-- `halved` is the EXP.SHARE tax: with any holder in the party the whole
-- wEnemyMon base stat block is `srl`'d in place before EITHER pass runs
-- (engine/battle/core.asm, the IsAnyMonHoldingExpShare block ahead of the
-- first GiveExperiencePoints call), so participants and holders both draw
-- stat exp from the halved values.
function Mon.gainStatExp(mon, loserDef, participants, doubled, halved)
  if type(mon) ~= "table" then return nil end
  local base = (loserDef and loserDef.baseStats) or {}
  local share = math.max(1, math.floor(participants or 1))
  mon.statExp = mon.statExp or Mon.newStatExp()
  local gains = {}
  for _, key in ipairs(Mon.STAT_EXP_ORDER) do
    local from = (key == "special") and base.specialAttack or base[key]
    from = from or 0
    if halved then from = math.floor(from / 2) end
    local gain = math.floor(from / share)
    if doubled then gain = gain * 2 end
    local value = (mon.statExp[key] or 0) + gain
    if value > Mon.MAX_STAT_EXP then value = Mon.MAX_STAT_EXP end
    mon.statExp[key] = value
    gains[key] = gain
  end
  return gains
end

-- Total experience needed to *be* `level`, from a GROWTH_* record.
-- The single point every experience calculation resolves its curve through.
-- The merged growth_rates registry wins, then the extractor's own coefficient
-- rows on data.pokemon.growthRates, so a mod-free boot reads exactly the table
-- it always did and a boot with a registered curve reads that instead.
--
-- Both live at the same key space (GROWTH_MEDIUM_FAST and friends), and the
-- registry's Data path is the shared `growth_rates` one Gen 1 uses -- the
-- point of routing it there rather than to a gen2 table is that a mod writes
-- ONE record for both games (src/mods/Builtins.lua's Gen 2 registrant seeds
-- this registry from the coefficient rows, so the vanilla curves are Gold's
-- own).
function Mon.growthFor(data, curve)
  if not curve then return nil end
  local registered = data and data.growth_rates and data.growth_rates[curve]
  if registered then return registered end
  return data and data.pokemon and data.pokemon.growthRates
    and data.pokemon.growthRates[curve]
end

-- Seeds the growth_rates registry with Gold's own curves, as records carrying
-- expForLevel so the id space and the record shape both match Gen 1's.  Called
-- by src/mods/Builtins.lua under Gen 2.  A dataset with no coefficient rows
-- (the ROM-free fixtures) seeds nothing rather than registering broken curves.
function Mon.registerInto(registry, data, owner)
  local rows = data and data.pokemon and data.pokemon.growthRates
  if type(rows) ~= "table" then return end
  for curve, row in pairs(rows) do
    -- the closure holds the coefficient row, so the registered record computes
    -- exactly what the arm below would have
    registry:register(curve, {
      expForLevel = function(level) return Mon.experienceForLevel(row, level) end,
    }, owner)
  end
end

-- `growth` is either the extractor's coefficient row (numerator / denominator /
-- squared / linear / constant, straight off GrowthRates in the ROM) or a
-- growth_rates REGISTRY record, which carries expForLevel(level) instead --
-- the same record shape Gen 1's registry uses (src/pokemon/Growth.lua), so a
-- mod that registers a custom curve writes one record and it works in both
-- games.  A registered curve wins outright; the coefficient arm is what a
-- mod-free boot and every driver still run.
function Mon.experienceForLevel(growth, level)
  if growth and growth.expForLevel then
    return math.max(0, math.floor(growth.expForLevel(level) or 0))
  end
  if not growth then return level * level * level end
  local n = level
  local numerator = growth.numerator or 1
  local denominator = growth.denominator or 1
  local value = math.floor(numerator * n * n * n / denominator)
  value = value + (growth.squared or 0) * n * n
  value = value + (growth.linear or 0) * n
  value = value - (growth.constant or 0)
  return math.max(0, value)
end

-- The level a total experience buys.  Walks up rather than inverting the
-- polynomial, which the cart also does (it only ever compares against the next
-- level's threshold).
function Mon.levelForExperience(growth, experience)
  local level = 1
  while level < Mon.MAX_LEVEL do
    if experience < Mon.experienceForLevel(growth, level + 1) then break end
    level = level + 1
  end
  return level
end

-- The moves a species knows on arrival at `level`: its last four level-up
-- moves at or below it (EvosAttacks order, later moves pushing earlier ones
-- out, which is what makes a caught mon's moveset deterministic).
function Mon.movesAtLevel(def, level, moves)
  local known = {}
  for _, entry in ipairs((def and def.levelMoves) or {}) do
    if entry.level <= level then
      -- A move already known is not learned twice.
      local duplicate = false
      for _, existing in ipairs(known) do
        if existing == entry.move then duplicate = true break end
      end
      if not duplicate then
        known[#known + 1] = entry.move
        if #known > 4 then table.remove(known, 1) end
      end
    end
  end
  local out = {}
  for _, id in ipairs(known) do
    local moveDef = moves and moves[id]
    out[#out + 1] = {
      id = id,
      pp = moveDef and moveDef.pp or 0,
      maxPp = moveDef and moveDef.pp or 0,
    }
  end
  return out
end

-- Build a party member.  `data` needs `pokemon` and `moves`; growth records
-- live on data.pokemon.growthRates (written by the extractor).
function Mon.new(data, species, level, opts)
  opts = opts or {}
  local def = data and data.pokemon and data.pokemon[species]
  if not def then return nil end
  level = math.max(1, math.min(Mon.MAX_LEVEL, level or 5))
  local dvs = opts.dvs or Mon.randomDVs()
  dvs.hp = Mon.hpDV(dvs)
  local statExp = opts.statExp or Mon.newStatExp()
  local stats = Mon.stats(def.baseStats, dvs, level, statExp)
  local growth = Mon.growthFor(data, def.growthRate)
  return {
    species = species,
    name = def.name or species,
    nickname = opts.nickname,
    level = level,
    experience = Mon.experienceForLevel(growth, level),
    dvs = dvs,
    -- The five stat exp words.  A wild or gift mon starts at zero: nothing in
    -- the cart seeds them, MON_STAT_EXP is zeroed by _MoveMon.
    statExp = statExp,
    -- MON_PKRS.  Zero is "never infected"; src/core/gen2/Pokerus.lua owns every
    -- read and write of it after this.
    pokerus = opts.pokerus or 0,
    stats = stats,
    hp = opts.hp or stats.hp,
    maxHp = stats.hp,
    types = def.types,
    moves = opts.moves or Mon.movesAtLevel(def, level, data.moves),
    -- Held item; wild mons roll one from BaseData's two item slots on the cart,
    -- which is not modeled yet, so only scripted gifts carry one.
    item = opts.item,
    status = nil,
    -- 70 for a caught mon, 120 for a gift/hatched one.
    happiness = opts.happiness or 70,
    caughtLevel = level,
    -- shiny.roll / gender.roll get the species and level as context; opts.shiny
    -- still wins, because a FORCED shiny battle (Red Gyarados) is the cart
    -- overriding the roll rather than a roll to be hooked.
    shiny = opts.shiny or Mon.isShiny(dvs,
      { species = species, def = def, level = level }),
    gender = Mon.gender(def, dvs, { species = species, level = level }),
    -- Unown has no gender and no shininess worth looking at, but it does have
    -- a FORM, and the form is the same DVs read a different way
    -- (GetUnownLetter, engine/gfx/load_pics.asm).  Stamped at build time so
    -- every screen that shows an Unown -- the battle pic, the box, the #DEX --
    -- reads one field instead of each redoing the bit shuffle.
    unownLetter = (species == Unown.SPECIES)
      and Unown.letterFromDVs(dvs) or nil,
  }
end

-- AddPartyMon copies wPlayerName into wPartyMonOTs and wPlayerID into MON_ID
-- (move_mon.asm:44-56, :143-149); SendMonIntoBox does the same (:970-994).
function Mon.stampOT(save, mon)
  local player = save and save.player
  if not (mon and player) then return mon end
  if player.id == nil then player.id = rand(0, 65535) end
  mon.ot = mon.ot or player.name
  -- NpcTrade.lua:150: `ot` is what Breeding reads, `otName` what the summary prints.
  mon.otName = mon.otName or mon.ot
  -- engine/battle/experience.asm:69: a traded mon keeps its own OT id
  if not mon.traded then mon.otId = mon.otId or player.id end
  return mon
end

-- shiny.roll and gender.roll, two of the names Gen 2 invents: Gen 1 has
-- neither shininess nor gender in the ROM at all (Red's shiny indicator mods
-- read src/pokemon/Stats.lua's virtual pattern, which is a mod-side
-- convention, not an engine seam), so there is no Gen 1 name to share.
--
-- Both wrap the DV-derived roll rather than the mon that comes out of it,
-- because on the cart these ARE the roll: CheckShininess and GetGender read
-- the same two DV bytes LoadEnemyMon just generated, and nothing later can
-- change the answer without changing the DVs.  Wrapping here means a shiny-odds
-- mod and a gender-ratio mod work on every route a mon arrives by -- a wild
-- encounter, a gift, a hatch, a trade -- because Mon.new is the one builder.
--
-- Shared ctx keys:
--   dvs      the DV set being read, exactly as stored on the mon
--   species  the species id, nil when the caller had none to give
--   def      that species' record, nil likewise
--   level    the level the mon is being built at, nil for a bare query
--
-- gender.roll's ctx carries `ratio` as well, BaseData's genderRatio byte, so a
-- mod can shift the threshold rather than restate the whole rule.  A chain that
-- returns something that is not one of "male" / "female" / "unknown" is
-- ignored, because every screen that prints a gender indexes by those three.

-- Gen 2 shininess: the classic DV pattern (Speed/Defense/Special all 10, and
-- Attack in {2,3,6,7,10,11,14,15}).
function Mon.vanillaShiny(dvs)
  if not dvs then return false end
  if dvs.speed ~= 10 or dvs.defense ~= 10 or dvs.special ~= 10 then
    return false
  end
  local attack = dvs.attack or 0
  return attack % 4 == 2 or attack % 4 == 3
end

function Mon.isShiny(dvs, ctx)
  if not Runtime.wantsHook("shiny.roll") then return Mon.vanillaShiny(dvs) end
  local shiny = Runtime.call("shiny.roll", function(c)
    return Mon.vanillaShiny(c.dvs)
  end, { dvs = dvs, species = ctx and ctx.species, def = ctx and ctx.def,
         level = ctx and ctx.level })
  return shiny and true or false
end

-- Gender comes from the Attack DV against the species' ratio threshold: an
-- Attack DV *below* the threshold is female (BaseData's `db GENDER_F12_5` is
-- already scaled out of 256).
function Mon.vanillaGender(def, dvs)
  local ratio = def and def.genderRatio
  if not ratio then return "unknown" end
  if ratio == 0xff then return "unknown" end
  -- The DV is 0..15; the threshold is out of 256 in steps of 16.
  local threshold = math.floor(ratio / 16)
  return ((dvs and dvs.attack or 0) < threshold) and "female" or "male"
end

local GENDERS = { male = true, female = true, unknown = true }

function Mon.gender(def, dvs, ctx)
  if not Runtime.wantsHook("gender.roll") then
    return Mon.vanillaGender(def, dvs)
  end
  local gender = Runtime.call("gender.roll", function(c)
    return Mon.vanillaGender(c.def, c.dvs)
  end, { def = def, dvs = dvs, ratio = def and def.genderRatio,
         species = (ctx and ctx.species) or (def and def.id),
         level = ctx and ctx.level })
  if not GENDERS[gender] then return Mon.vanillaGender(def, dvs) end
  return gender
end

-- Experience for defeating `loser`, per recipient.  Gen 2:
--   exp = baseExp * loserLevel / 7, split among the recipients of the pass,
-- then GiveExperiencePoints' three BoostExp arms in the cart's own order,
-- each a floored x1.5 on the running amount:
--   traded    the mon's OT id differs from the player's (BoostedExpPointsText)
--   trainer   a trainer battle (wBattleMode)
--   luckyEgg  the mon HOLDS a LUCKY_EGG -- checked by item id, not held
--             effect, exactly as the cart's `cp LUCKY_EGG` does
-- opts.halved is the EXP.SHARE tax: any holder in the party halves the base
-- exp byte before either pass (the same `srl` block that halves stat exp).
function Mon.experienceGain(loserDef, loserLevel, participants, trainer, opts)
  opts = opts or {}
  local baseExp = (loserDef and loserDef.baseExp) or 0
  if opts.halved then baseExp = math.floor(baseExp / 2) end
  local value = math.floor(baseExp * (loserLevel or 1) / 7)
  value = math.floor(value / math.max(1, participants or 1))
  if opts.traded then value = math.floor(value * 3 / 2) end
  if trainer then value = math.floor(value * 3 / 2) end
  if opts.luckyEgg then value = math.floor(value * 3 / 2) end
  return math.max(1, value)
end

-- Award experience, level up as far as it reaches, and report what happened so
-- the battle can print "grew to level N!" and offer new moves.
function Mon.gainExperience(mon, amount, data)
  local def = data and data.pokemon and data.pokemon[mon.species]
  local growth = Mon.growthFor(data, def and def.growthRate)
  mon.experience = (mon.experience or 0) + math.max(0, amount or 0)
  local before = mon.level
  local capped = Mon.experienceForLevel(growth, Mon.MAX_LEVEL)
  if mon.experience > capped then mon.experience = capped end
  local after = Mon.levelForExperience(growth, mon.experience)
  if after <= before then
    return { levels = 0, learned = {} }
  end
  mon.level = after
  -- Recompute stats and carry the HP gain, the way the cart adds the delta
  -- rather than refilling.
  local previousMax = mon.maxHp or (mon.stats and mon.stats.hp) or 1
  mon.stats = Mon.stats(def and def.baseStats, mon.dvs, after, mon.statExp)
  mon.maxHp = mon.stats.hp
  mon.hp = math.min(mon.maxHp, (mon.hp or previousMax)
    + (mon.maxHp - previousMax))

  -- pokemon.level_up, once per level crossed and after the stats were
  -- recalculated, exactly as src/battle/Experience.lua raises it on Gen 1 --
  -- a jump of three levels is three events, not one.  `learnable` is the moves
  -- this species learns at exactly that level, the same list Gen 1 carries.
  if Runtime.wants("pokemon.level_up") then
    for level = before + 1, after do
      local learnable = {}
      for _, entry in ipairs((def and def.levelMoves) or {}) do
        if entry.level == level then learnable[#learnable + 1] = entry.move end
      end
      Runtime.emit("pokemon.level_up", {
        mon = mon, level = level, prevLevel = level - 1, learnable = learnable,
      })
    end
  end

  -- Every level-up move between the old and new level is offered.
  local learned = {}
  for _, entry in ipairs((def and def.levelMoves) or {}) do
    if entry.level > before and entry.level <= after then
      learned[#learned + 1] = entry.move
    end
  end
  return { levels = after - before, learned = learned, from = before, to = after }
end

-- Teach a move, or report that all four slots are full so the caller can ask
-- which to forget.
function Mon.learnMove(mon, moveId, data)
  mon.moves = mon.moves or {}
  for _, move in ipairs(mon.moves) do
    if move.id == moveId then return false, "known" end
  end
  local def = data and data.moves and data.moves[moveId]
  local entry = {
    id = moveId,
    pp = def and def.pp or 0,
    maxPp = def and def.pp or 0,
  }
  if #mon.moves >= 4 then return false, "full", entry end
  mon.moves[#mon.moves + 1] = entry
  -- pokemon.move_learned, the payload BattleState:learnMove emits on Gen 1.
  -- This is Gen 2's single choke point for teaching a move -- the level-up
  -- award, an evolution's new move and the TM path all arrive here -- so the
  -- event covers all three rather than only the battle's.
  Runtime.emit("pokemon.move_learned", { mon = mon, moveId = moveId })
  return true
end

-- Which evolution (if any) fires at this level.
function Mon.evolutionAtLevel(def, level)
  for _, entry in ipairs((def and def.evolutions) or {}) do
    if entry.method == "EVOLVE_LEVEL" and (entry.level or 0) <= level then
      return entry
    end
  end
  return nil
end

return Mon
