local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local MonOps = {}

function MonOps.create(data, species, level, gen)
  level = math.max(1, math.min(100, math.floor(tonumber(level) or 5)))
  if gen == 3 then
    local PokemonG3 = require("src.core.game3.pokemon")
    local SummaryData = require("src.core.game3.summary_data")
    pcall(PokemonG3.install, nil)

    local spId = tonumber(species) or (PokemonG3.speciesFromName and PokemonG3.speciesFromName(tostring(species))) or 1
    local name = (PokemonG3.name and PokemonG3.name(spId)) or tostring(species)

    local personality = (love and love.math and love.math.random and love.math.random(0, 0xFFFFFFFF))
      or (math.floor(math.random() * 0x100000000) % 0x100000000)

    local ivs = {}
    for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
      ivs[k] = (love and love.math and love.math.random and love.math.random(0, 31)) or math.random(0, 31)
    end

    local meta = PokemonG3.speciesMeta and PokemonG3.speciesMeta(spId)
    local friendship = (meta and meta.friendship) or 70
    local growthRate = (meta and tonumber(meta.growthRate)) or 0
    local ability = PokemonG3.abilityId and PokemonG3.abilityId(spId, personality) or 0
    local gender = PokemonG3.gender and PokemonG3.gender(spId, personality) or "U"

    local moves, pp, maxPp = {}, {}, {}
    if PokemonG3.movesAtLevel then
      moves, pp, maxPp = PokemonG3.movesAtLevel(spId, level)
    end

    local monMoves = {}
    for slot = 1, 4 do
      local mvId = moves[slot]
      if mvId and mvId > 0 then
        monMoves[slot] = {
          id = mvId,
          moveId = mvId,
          pp = pp[slot] or 10,
          maxPp = maxPp[slot] or 10,
        }
      end
    end

    local mon = {
      species = spId,
      speciesId = spId,
      name = name,
      nickname = "",
      level = level,
      growthRate = growthRate,
      exp = SummaryData.expForLevel(growthRate, level),
      moves = monMoves,
      personality = personality,
      nature = PokemonG3.natureId and PokemonG3.natureId(personality) or 0,
      ivs = ivs,
      dvs = {
        attack = math.floor(ivs.atk / 2),
        defense = math.floor(ivs.def / 2),
        speed = math.floor(ivs.spe / 2),
        special = math.floor(ivs.spa / 2),
        hp = math.floor(ivs.hp / 2),
      },
      evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
      ability = ability,
      gender = gender,
      happiness = friendship,
      friendship = friendship,
      pokeball = 4, -- pokefirered/src/pokemon.c:1820
    }

    require("src.core.game3.save_mon").normalize(mon)
    mon.stats = {
      hp = mon.maxHp,
      attack = mon.attack,
      defense = mon.defense,
      speed = mon.speed,
      spAtk = mon.spAtk,
      spDef = mon.spDef,
      specialAttack = mon.spAtk,
      specialDefense = mon.spDef,
    }
    return mon
  elseif gen == 2 then
    local Mon = require("src.battle.gen2.Mon")
    local mon = Mon.new(data, species, level)
    assert(mon, "unknown species " .. tostring(species))
    return mon
  end
  return Pokemon.new(data, species, level)
end

function MonOps.recalc(data, mon, gen)
  if type(mon) ~= "table" then return end
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
    or (mon.ivs ~= nil) or (mon.evs ~= nil and mon.evs.spa ~= nil)
  if isG3 then
    local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
    if okP and PokemonG3 then
      require("src.core.game3.save_mon").normalize(mon)
      if mon.personality then
        mon.nature = PokemonG3.natureId and PokemonG3.natureId(mon.personality) or mon.nature
        mon.gender = PokemonG3.gender and PokemonG3.gender(mon.speciesId or mon.species, mon.personality) or mon.gender
        local pair = PokemonG3.abilities(mon.speciesId or mon.species)
        mon.abilityNum = mon.abilityNum or (pair[2] and pair[2] ~= 0 and mon.personality % 2 or 0)
        mon.ability = pair[mon.abilityNum + 1] or pair[1]
        mon.abilityId = mon.ability
      end
      if mon.maxHp then
        mon.hp = math.max(0, math.min(mon.hp or mon.maxHp, mon.maxHp))
      end
    end
    return
  end
  if gen == 2 or (mon.stats and mon.stats.specialAttack) or mon.experience then
    require("src.battle.gen2.Mon").refreshStats(mon, data)
    return
  end
  local def = data and data.pokemon and data.pokemon[mon.species]
  assert(def, "unknown species")
  mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
  mon.hp = math.max(0, math.min(mon.hp or mon.stats.hp, mon.stats.hp))
end

MonOps.SPECIES_UNOWN_G3 = 201
MonOps.UNOWN_FORMS_G3 = 28

local function spliceLetterBits(half, lo2, hi2)
  local bit = require("bit")
  return bit.bor(bit.band(half, 0xFCFC), lo2, hi2 * 256)
end

-- include/pokemon.h:364 GET_UNOWN_LETTER, src/pokemon.c:2318 CreateMonWithGenderNatureLetter
function MonOps.unownPid(pid, letter, nature, shiny, tid, sid)
  local bit = require("bit")
  local PokemonG3 = require("src.core.game3.pokemon")
  pid = (tonumber(pid) or 0) % 4294967296
  letter = math.floor(tonumber(letter) or 0) % MonOps.UNOWN_FORMS_G3
  nature = nature ~= nil and tonumber(nature) or nil
  local tsv = bit.bxor((tonumber(tid) or 0) % 65536, (tonumber(sid) or 0) % 65536)
  local oldLow, oldHigh = pid % 65536, math.floor(pid / 65536)
  local function accept(high, low)
    local p = high * 65536 + low
    if p == 0 then return nil end
    if nature ~= nil and p % 25 ~= nature then return nil end
    local isShiny = bit.bxor(tsv, bit.bxor(high, low)) < 8
    if shiny ~= nil and isShiny ~= (shiny and true or false) then return nil end
    if PokemonG3.unownLetter(p) ~= letter then return nil end
    return p
  end
  local same = accept(oldHigh, oldLow)
  if same then return same end
  local tsv89 = math.floor(tsv / 256) % 4
  for d = 0, 4095 do
    local low0 = bit.bxor(oldLow, (d % 64) * 4 + math.floor(d / 64) * 1024)
    if shiny then
      for b1 = 0, 3 do
        local b3 = bit.bxor(b1, tsv89)
        for b0 = 0, 3 do
          for b2 = 0, 3 do
            if (b3 * 64 + b2 * 16 + b1 * 4 + b0) % MonOps.UNOWN_FORMS_G3 == letter then
              local low = spliceLetterBits(low0, b0, b1)
              local base = bit.bxor(low, tsv)
              for k2 = 0, 1 do
                local high = bit.bor(bit.band(bit.bxor(base, k2 * 4), 0xFFFC), b2)
                local p = accept(high, low)
                if p then return p end
              end
            end
          end
        end
      end
    else
      for v = letter, 255, MonOps.UNOWN_FORMS_G3 do
        local b0, b1 = v % 4, math.floor(v / 4) % 4
        local b2, b3 = math.floor(v / 16) % 4, math.floor(v / 64)
        local p = accept(spliceLetterBits(oldHigh, b2, b3), spliceLetterBits(low0, b0, b1))
        if p then return p end
      end
    end
  end
  return nil
end

local function unownReq(mon)
  if tonumber(mon.speciesId or mon.species) ~= MonOps.SPECIES_UNOWN_G3 then return nil end
  return require("src.core.game3.pokemon").unownLetter(mon.personality)
end

-- src/pokemon.c:5751 DRAW_SPINDA_SPOTS
local function spindaPid(base, tsv, accept, shinyOnly)
  local bit = require("bit")
  base = (tonumber(base) or 0) % 4294967296
  local ob = {}
  for i = 0, 3 do ob[i] = bit.band(bit.rshift(base, 8 * i), 0xFF) end
  local best, bestCost
  local function try(p)
    if not accept(p) then return end
    local cost = 0
    for i = 0, 3 do
      local b = bit.band(bit.rshift(p, 8 * i), 0xFF)
      if b ~= ob[i] then
        cost = cost + 1000 + math.abs(b % 16 - ob[i] % 16)
          + math.abs(bit.rshift(b, 4) - bit.rshift(ob[i], 4))
      end
    end
    if not bestCost or cost < bestCost then best, bestCost = p, cost end
  end
  if shinyOnly then
    for low = 0, 65535 do
      local h0 = bit.bxor(low, tsv)
      for s = 0, 7 do try(bit.bxor(h0, s) * 65536 + low) end
    end
    return best
  end
  try(base)
  if best then return best end
  local function with(p, i, v)
    return p + (v - bit.band(bit.rshift(p, 8 * i), 0xFF)) * 256 ^ i
  end
  for i = 0, 3 do
    for v = 0, 255 do
      if v ~= ob[i] then try(with(base, i, v)) end
    end
  end
  if best then return best end
  for i = 0, 2 do
    for j = i + 1, 3 do
      for v = 0, 255 do
        if v ~= ob[i] then
          local pi = with(base, i, v)
          for w = 0, 255 do
            if w ~= ob[j] then try(with(pi, j, w)) end
          end
        end
      end
    end
  end
  return best
end

function MonOps.generatePid(species, otId, otSecretId, reqs)
  reqs = reqs or {}
  local PokemonG3 = require("src.core.game3.pokemon")
  local bit = require("bit")

  local spId = tonumber(species) or (PokemonG3.speciesFromName and PokemonG3.speciesFromName(tostring(species))) or 1
  if spId == MonOps.SPECIES_UNOWN_G3 and reqs.unownLetter ~= nil then
    local p = MonOps.unownPid(reqs.basePid, reqs.unownLetter, reqs.nature, reqs.shiny, otId, otSecretId)
    if p then return p end
  end
  otId = bit.band(tonumber(otId) or 0, 0xFFFF)
  otSecretId = bit.band(tonumber(otSecretId) or 0, 0xFFFF)
  local trainerXor = bit.bxor(otId, otSecretId)

  local meta = PokemonG3.speciesMeta and PokemonG3.speciesMeta(spId)
  local ratio = (meta and meta.genderRatio) or 127

  local targetNature = reqs.nature and tonumber(reqs.nature)
  local targetAbility = reqs.ability and tonumber(reqs.ability)
  local targetGender = reqs.gender
  local targetShiny = reqs.shiny

  if spId == PokemonG3.SPECIES_SPINDA and reqs.basePid ~= nil then
    local p = spindaPid(reqs.basePid, trainerXor, function(p)
      if p == 0 then return false end
      if targetNature ~= nil and p % 25 ~= targetNature then return false end
      local b0 = p % 256
      if targetAbility ~= nil and b0 % 2 ~= targetAbility then return false end
      if targetGender ~= nil and targetGender ~= "" and targetGender ~= "U" then
        local g
        if ratio == PokemonG3.GENDER_MALE then g = "M"
        elseif ratio == PokemonG3.GENDER_FEMALE then g = "F"
        elseif ratio == PokemonG3.GENDER_GENDERLESS then g = "U"
        elseif ratio > b0 then g = "F"
        else g = "M" end
        if g ~= targetGender then return false end
      end
      if targetShiny ~= nil then
        local isShiny = bit.bxor(trainerXor, bit.bxor(math.floor(p / 65536), p % 65536)) < 8
        if isShiny ~= (targetShiny and true or false) then return false end
      end
      return true
    end, targetShiny == true)
    if p then return p end
  end

  -- 1. Determine valid low-byte (b0) for gender & ability slot
  local validB0 = {}
  for b = 0, 255 do
    local ok = true
    if targetAbility ~= nil and (b % 2) ~= targetAbility then ok = false end
    if ok and targetGender ~= nil and targetGender ~= "" and targetGender ~= "U" then
      local g
      if ratio == PokemonG3.GENDER_MALE then g = "M"
      elseif ratio == PokemonG3.GENDER_FEMALE then g = "F"
      elseif ratio == PokemonG3.GENDER_GENDERLESS then g = "U"
      elseif ratio > b then g = "F"
      else g = "M" end
      if g ~= targetGender then ok = false end
    end
    if ok then validB0[#validB0 + 1] = b end
  end
  if #validB0 == 0 then
    for b = 0, 255 do
      if targetAbility == nil or (b % 2) == targetAbility then validB0[#validB0 + 1] = b end
    end
  end

  local sOffset = (targetShiny == true) and math.random(0, 7) or (targetShiny == false and math.random(8, 255) or math.random(0, 255))
  local targetXor = bit.bxor(trainerXor, sOffset)

  -- 2. Search across b0 and b1 for matching nature modulo 25
  for _, b0 in ipairs(validB0) do
    for b1 = 0, 255 do
      local pLow = b1 * 256 + b0
      local pHigh = bit.bxor(pLow, targetXor)
      local p = pHigh * 65536 + pLow
      if targetNature == nil or (p % 25) == targetNature then
        return p
      end
    end
  end

  -- Fallback satisfying nature and ability parity
  local base = (targetNature or 0)
  if targetAbility == 1 and (base % 2 == 0) then
    base = base + 25
  elseif targetAbility == 0 and (base % 2 == 1) then
    base = base + 25
  end
  return base
end

function MonOps.setHeldItem(data, mon, itemId, gen)
  if type(mon) ~= "table" then return end
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
  if isG3 then
    local ItemsData = require("src.core.game3.items_data")
    local numId = tonumber(itemId) or (itemId and ItemsData.toNumericId and ItemsData.toNumericId(itemId))
    mon.heldItem = numId or itemId
    mon.item = mon.heldItem
    return
  end
  mon.item = itemId
end

function MonOps.setHappiness(data, mon, val, gen)
  if type(mon) ~= "table" then return end
  local v = math.max(0, math.min(255, math.floor(tonumber(val) or 0)))
  mon.happiness = v
  mon.friendship = v
end

function MonOps.setNature(data, mon, natureId, gen)
  if type(mon) ~= "table" then return end
  natureId = math.max(0, math.min(24, math.floor(tonumber(natureId) or 0)))
  mon.nature = natureId
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
  if isG3 then
    local currentAbility = mon.abilityNum or (mon.personality and (mon.personality % 2)) or 0
    local isShiny = require("src.core.game3.summary_data").isShiny(mon)
    mon.personality = MonOps.generatePid(mon.speciesId or mon.species, mon.otId or 0, mon.otSecretId or 0, {
      nature = natureId,
      ability = currentAbility,
      gender = mon.gender,
      shiny = isShiny,
      unownLetter = unownReq(mon),
      basePid = mon.personality,
    })
    MonOps.recalc(data, mon, gen)
  end
end

function MonOps.setAbility(data, mon, abilitySlot, gen)
  if type(mon) ~= "table" then return end
  abilitySlot = (tonumber(abilitySlot) or 0) % 2
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
  if isG3 then
    local currentNature = (mon.personality and (mon.personality % 25)) or mon.nature or 0
    local isShiny = require("src.core.game3.summary_data").isShiny(mon)
    mon.personality = MonOps.generatePid(mon.speciesId or mon.species, mon.otId or 0, mon.otSecretId or 0, {
      nature = currentNature,
      ability = abilitySlot,
      gender = mon.gender,
      shiny = isShiny,
      unownLetter = unownReq(mon),
      basePid = mon.personality,
    })
    mon.abilityNum = abilitySlot
    local PokemonG3 = require("src.core.game3.pokemon")
    mon.ability = PokemonG3.abilityId(mon.speciesId or mon.species, mon.personality)
    MonOps.recalc(data, mon, gen)
  end
end

function MonOps.setGender(data, mon, gender, gen)
  if type(mon) ~= "table" then return end
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
  if isG3 then
    local currentNature = (mon.personality and (mon.personality % 25)) or mon.nature or 0
    local currentAbility = mon.abilityNum or (mon.personality and (mon.personality % 2)) or 0
    local isShiny = require("src.core.game3.summary_data").isShiny(mon)
    mon.personality = MonOps.generatePid(mon.speciesId or mon.species, mon.otId or 0, mon.otSecretId or 0, {
      nature = currentNature,
      ability = currentAbility,
      gender = gender,
      shiny = isShiny,
      unownLetter = unownReq(mon),
      basePid = mon.personality,
    })
    local PokemonG3 = require("src.core.game3.pokemon")
    mon.gender = PokemonG3.gender(mon.speciesId or mon.species, mon.personality)
    MonOps.recalc(data, mon, gen)
  else
    mon.gender = gender
  end
end

function MonOps.setShiny(data, mon, shiny, gen)
  if type(mon) ~= "table" then return end
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
  if isG3 then
    local currentNature = (mon.personality and (mon.personality % 25)) or mon.nature or 0
    local currentAbility = mon.abilityNum or (mon.personality and (mon.personality % 2)) or 0
    mon.personality = MonOps.generatePid(mon.speciesId or mon.species, mon.otId or 0, mon.otSecretId or 0, {
      nature = currentNature,
      ability = currentAbility,
      gender = mon.gender,
      shiny = shiny,
      unownLetter = unownReq(mon),
      basePid = mon.personality,
    })
    mon.isShiny = shiny
    MonOps.recalc(data, mon, gen)
  else
    mon.shiny = shiny
  end
end

function MonOps.setLevel(data, mon, level, gen)
  if type(mon) ~= "table" then return end
  level = math.max(1, math.min(100, math.floor(level)))
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil) or (mon.ivs ~= nil)
  mon.level = level

  if isG3 then
    local SummaryData = require("src.core.game3.summary_data")
    local gr = require("src.core.game3.pokemon").growthRate(require("src.core.game3.pokemon").speciesOf(mon)) or mon.growthRate or 0
    mon.exp = SummaryData.expForLevel(gr, level)
    mon.experience = mon.exp
    MonOps.recalc(data, mon, gen)
    return
  end

  local def = data and data.pokemon and data.pokemon[mon.species]
  if gen == 2 or mon.experience ~= nil then
    local Mon = require("src.battle.gen2.Mon")
    local growth = Mon.growthFor(data, def and def.growthRate)
    mon.experience = Mon.experienceForLevel(growth, level)
    Mon.refreshStats(mon, data)
    return
  end
  mon.exp = Growth.expForLevel(def and def.growthRate or 0, level)
  MonOps.recalc(data, mon, gen)
end

function MonOps.clearMove(mon, slot)
  for _, key in ipairs({ "moves", "pp", "maxPp", "moveIds", "ppBonuses", "ppBonus", "ppUp" }) do
    if type(mon[key]) == "table" then mon[key][slot] = nil end
  end
  if type(mon.ppBonusesPacked) == "number" then
    local bit = require("bit")
    mon.ppBonusesPacked = bit.band(mon.ppBonusesPacked, bit.bnot(bit.lshift(3, (slot - 1) * 2)))
  end
end

function MonOps.setMove(data, mon, slot, moveId)
  assert(slot >= 1 and slot <= 4)
  local mdef = data and data.moves and data.moves[moveId]
  local numMove = tonumber(moveId)
  if not mdef and numMove then
    local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
    if okP and PokemonG3 then
      local mName = PokemonG3.moveName(numMove)
      local bMove = PokemonG3.battleMove(numMove)
      mdef = {
        id = mName,
        moveId = numMove,
        name = mName,
        pp = (bMove and tonumber(bMove.pp)) or 10,
        maxPp = (bMove and tonumber(bMove.pp)) or 10,
      }
    end
  end
  assert(type(mdef) == "table", "unknown move: " .. tostring(moveId))
  mon.moves = mon.moves or {}
  local basePp = mdef.pp or 10
  if mon.speciesId ~= nil or mon.personality ~= nil then
    local nativeId = assert(tonumber(mdef.moveId or numMove), "unknown native move")
    MonOps.clearMove(mon, slot)
    mon.moves[slot] = nativeId
    mon.pp, mon.maxPp = mon.pp or {}, mon.maxPp or {}
    mon.pp[slot], mon.maxPp[slot] = basePp, basePp
    return
  end
  local currentUps = (mon.moves[slot] and mon.moves[slot].ppUps) or 0
  mon.moves[slot] = {
    id = mdef.id or mdef.name or tostring(moveId),
    moveId = mdef.moveId or numMove,
    pp = basePp + currentUps * math.floor(basePp / 5),
    ppUps = currentUps > 0 and currentUps or nil,
    maxPp = basePp + currentUps * math.floor(basePp / 5),
  }
end

function MonOps.getPpUps(mon, slot)
  if type(mon) ~= "table" or not slot then return 0 end
  if type(mon.ppBonusesPacked) == "number" then
    local bit = require("bit")
    return bit.band(bit.rshift(mon.ppBonusesPacked, (slot - 1) * 2), 3)
  end
  local mv = mon.moves and mon.moves[slot]
  if type(mv) == "table" and mv.ppUps ~= nil then
    return tonumber(mv.ppUps) or 0
  end
  if type(mon.ppBonuses) == "table" and mon.ppBonuses[slot] ~= nil then
    return tonumber(mon.ppBonuses[slot]) or 0
  end
  return 0
end

function MonOps.getBasePp(data, mon, slot)
  if type(mon) ~= "table" or not slot then return 10 end
  local mv = mon.moves and mon.moves[slot]
  local moveId = nil
  if type(mv) == "table" then
    moveId = mv.moveId or mv.id or mv.move
    if mv.basePp then return tonumber(mv.basePp) end
  elseif type(mv) == "number" then
    moveId = mv
  elseif type(mv) == "string" then
    moveId = mv
  end
  if not moveId then return 10 end

  local num = tonumber(moveId)
  local mdef = data and data.moves and (data.moves[moveId] or (num and data.moves[num]))
  if mdef and mdef.pp then return tonumber(mdef.pp) end

  if num and ((mon.speciesId ~= nil) or (mon.personality ~= nil)) then
    return require("src.core.game3.pokemon").movePp(num)
  end

  return 10
end

function MonOps.calcMaxPp(basePp, ppUps, gen)
  basePp = math.max(1, tonumber(basePp) or 10)
  ppUps = math.max(0, math.min(3, tonumber(ppUps) or 0))
  if gen == 1 or gen == 2 then
    -- GBPKM.GetMovePP and Gen 2 engine/items/item_effects.asm cap the
    -- per-PP-Up bonus at seven: a 40 PP move reaches 61, not 64.
    return basePp + ppUps * math.min(7, math.floor(basePp / 5))
  end
  return basePp + math.floor(basePp * 20 * ppUps / 100)
end

function MonOps.setPpUps(data, mon, slot, ppUps, gen)
  if type(mon) ~= "table" or not slot then return end
  ppUps = math.max(0, math.min(3, math.floor(tonumber(ppUps) or 0)))
  local basePp = MonOps.getBasePp(data, mon, slot)
  if basePp == 1 then ppUps = 0 end -- Sketch cannot receive PP Ups.

  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil) or (type(mon.ppBonusesPacked) == "number")
  local newMaxPp = MonOps.calcMaxPp(basePp, ppUps, isG3 and 3 or (gen or 1))
  if isG3 then
    local bit = require("bit")
    local shift = (slot - 1) * 2
    local packed = tonumber(mon.ppBonusesPacked) or 0
    mon.ppBonusesPacked = bit.bor(bit.band(packed, bit.bnot(bit.lshift(3, shift))), bit.lshift(ppUps, shift))
    mon.maxPp = mon.maxPp or {}
    mon.maxPp[slot] = newMaxPp
    mon.pp = mon.pp or {}
    if mon.pp[slot] == nil or mon.pp[slot] > newMaxPp then
      mon.pp[slot] = newMaxPp
    end
    local mv = mon.moves and mon.moves[slot]
    if type(mv) == "table" then
      mv.pp, mv.maxPp = mon.pp[slot], newMaxPp
      mv.ppUps = ppUps > 0 and ppUps or nil
    end
  else
    local mv = mon.moves and mon.moves[slot]
    if type(mv) == "table" then
      mv.ppUps = ppUps > 0 and ppUps or nil
      mv.maxPp = newMaxPp
      if mv.pp == nil or mv.pp > newMaxPp then
        mv.pp = newMaxPp
      end
    end
    if type(mon.pp) == "table" and (mon.pp[slot] == nil or mon.pp[slot] > newMaxPp) then
      mon.pp[slot] = newMaxPp
    end
    if type(mon.maxPp) == "table" then
      mon.maxPp[slot] = newMaxPp
    end
  end
  return ppUps, newMaxPp
end

function MonOps.setPp(data, mon, slot, value, gen)
  if type(mon) ~= "table" or not slot then return end
  local basePp = MonOps.getBasePp(data, mon, slot)
  local ppUps = MonOps.getPpUps(mon, slot)
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil) or (type(mon.ppBonusesPacked) == "number")
  local maxPp = MonOps.calcMaxPp(basePp, ppUps, isG3 and 3 or (gen or 1))
  local target = math.max(0, math.min(maxPp, math.floor(tonumber(value) or 0)))
  if isG3 then
    mon.pp = mon.pp or {}
    mon.pp[slot] = target
    mon.maxPp = mon.maxPp or {}
    mon.maxPp[slot] = maxPp
    local mv = mon.moves and mon.moves[slot]
    if type(mv) == "table" then mv.pp, mv.maxPp = target, maxPp end
  else
    local mv = mon.moves and mon.moves[slot]
    if type(mv) == "table" then
      mv.pp = target
      mv.maxPp = maxPp
    end
    if type(mon.pp) == "table" then
      mon.pp[slot] = target
    end
  end
  return target, maxPp
end

function MonOps.maxAllPpUps(data, mon, gen)
  if type(mon) ~= "table" or not mon.moves then return end
  local ups = (mon.isEgg or mon.egg) and 0 or 3
  for slot = 1, 4 do
    local move = mon.moves[slot]
    local id = type(move) == "table" and (move.moveId or move.id) or move
    if id and id ~= 0 then
      MonOps.setPpUps(data, mon, slot, ups, gen)
      local basePp = MonOps.getBasePp(data, mon, slot)
      local isG3 = gen == 3 or mon.speciesId ~= nil or mon.personality ~= nil
      local maxPp = MonOps.calcMaxPp(basePp, MonOps.getPpUps(mon, slot), isG3 and 3 or (gen or 1))
      MonOps.setPp(data, mon, slot, maxPp, gen)
    end
  end
end

-- HP DV is derived from the low bits of the other four (Stats.randomDVs).
function MonOps.syncHpDv(dvs)
  if not dvs then return end
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
         + (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

local function deriveGen2(data, mon)
  local Mon = require("src.battle.gen2.Mon")
  local Unown = require("src.core.gen2.Unown")
  mon.dvs.hp = Mon.hpDV(mon.dvs)
  local def = data and data.pokemon and data.pokemon[mon.species]
  if def then
    mon.gender = Mon.gender(def, mon.dvs, { species = mon.species, level = mon.level })
  end
  mon.shiny = Mon.isShiny(mon.dvs, { species = mon.species, def = def, level = mon.level })
  if mon.species == Unown.SPECIES then
    mon.unownLetter = Unown.letterFromDVs(mon.dvs)
  end
end

function MonOps.setDv(data, mon, key, value, gen)
  if type(mon) ~= "table" then return end
  mon.dvs = mon.dvs or { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
  mon.dvs[key] = math.max(0, math.min(15, math.floor(value)))
  if key ~= "hp" then
    MonOps.syncHpDv(mon.dvs)
  end

  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil) or (mon.ivs ~= nil)
  if isG3 then
    mon.ivs = mon.ivs or {}
    mon.ivs.hp = math.min(31, (mon.dvs.hp or 0) * 2 + 1)
    mon.ivs.atk = math.min(31, (mon.dvs.attack or 0) * 2 + 1)
    mon.ivs.def = math.min(31, (mon.dvs.defense or 0) * 2 + 1)
    mon.ivs.spe = math.min(31, (mon.dvs.speed or 0) * 2 + 1)
    mon.ivs.spa = math.min(31, (mon.dvs.special or 0) * 2 + 1)
    mon.ivs.spd = math.min(31, (mon.dvs.special or 0) * 2 + 1)
  elseif gen == 2 or (mon.stats and mon.stats.specialAttack) then
    deriveGen2(data, mon)
  end
  MonOps.recalc(data, mon, gen)
end

local DV_KEYS = { "attack", "defense", "speed", "special" }

-- engine/gfx/load_pics.asm:1 GetUnownLetter, engine/gfx/color.asm:8 CheckShininess
function MonOps.unownDvs(dvs, letter, keepShiny)
  local Mon = require("src.battle.gen2.Mon")
  letter = math.floor(tonumber(letter) or 1)
  if letter < 1 or letter > 26 then return nil end
  local lo, hi = (letter - 1) * 10, math.min(255, letter * 10 - 1)
  local best, bestKey
  for p = lo, hi do
    local out = {}
    for i, k in ipairs(DV_KEYS) do
      local d = tonumber(dvs[k]) or 0
      local mid = math.floor(p / 4 ^ (4 - i)) % 4
      out[k] = d - (math.floor(d / 2) % 4) * 2 + mid * 2
    end
    local cost = 0
    for _, k in ipairs(DV_KEYS) do cost = cost + math.abs(out[k] - (tonumber(dvs[k]) or 0)) end
    local key = (Mon.vanillaShiny(out) == (keepShiny and true or false) and 0 or 1000) + cost
    if not bestKey or key < bestKey then best, bestKey = out, key end
  end
  return best
end

-- pokecrystal/engine/gfx/color.asm:8 CheckShininess, pokecrystal/engine/battle/hidden_power.asm:13
function MonOps.maxGen2Dvs(data, mon, gen)
  if type(mon) ~= "table" then return end
  local Mon = require("src.battle.gen2.Mon")
  local Unown = require("src.core.gen2.Unown")
  mon.dvs = mon.dvs or {}
  local keepShiny = mon.shiny == true or Mon.vanillaShiny(mon.dvs)
  local out = keepShiny and { attack = 15, defense = 10, speed = 10, special = 10 }
    or { attack = 15, defense = 15, speed = 15, special = 15 }
  if mon.species == Unown.SPECIES then
    out = MonOps.unownDvs(out, Unown.monLetter(mon), keepShiny) or out
  end
  for k, v in pairs(out) do mon.dvs[k] = v end
  deriveGen2(data, mon)
  MonOps.recalc(data, mon, gen)
  return keepShiny and mon.shiny == true
end

function MonOps.setUnownForm(data, mon, letter, gen)
  if type(mon) ~= "table" then return nil end
  if gen == 3 then
    local Summary = require("src.core.game3.summary_data")
    local p = MonOps.unownPid(mon.personality, letter, (tonumber(mon.personality) or 0) % 25,
      Summary.isShiny(mon), mon.otId, mon.otSecretId)
    if not p then return nil end
    mon.personality = p
    mon.isShiny = nil
    MonOps.recalc(data, mon, gen)
    return true
  end
  local Mon = require("src.battle.gen2.Mon")
  mon.dvs = mon.dvs or { attack = 0, defense = 0, speed = 0, special = 0 }
  local wasShiny = mon.shiny == true or Mon.vanillaShiny(mon.dvs)
  local out = MonOps.unownDvs(mon.dvs, letter, wasShiny)
  if not out then return nil end
  for k, v in pairs(out) do mon.dvs[k] = v end
  deriveGen2(data, mon)
  MonOps.recalc(data, mon, gen)
  return true, wasShiny and not mon.shiny
end

local EV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }

function MonOps.setEv(data, mon, key, value, gen)
  if type(mon) ~= "table" or not key then return end
  mon.evs = mon.evs or { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
  local target = math.max(0, math.min(255, math.floor(tonumber(value) or 0)))
  local otherTotal = 0
  for _, k in ipairs(EV_KEYS) do
    if k ~= key then
      otherTotal = otherTotal + (tonumber(mon.evs[k]) or 0)
    end
  end
  if otherTotal + target > 510 then
    target = math.max(0, 510 - otherTotal)
  end
  mon.evs[key] = target
  MonOps.recalc(data, mon, gen)
  return target
end

function MonOps.clearEvs(data, mon, gen)
  if type(mon) ~= "table" then return end
  mon.evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
  MonOps.recalc(data, mon, gen)
end

function MonOps.setIv(data, mon, key, value, gen)
  if type(mon) ~= "table" or not key then return end
  mon.ivs = mon.ivs or { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
  local target = math.max(0, math.min(31, math.floor(tonumber(value) or 0)))
  mon.ivs[key] = target
  mon.dvs = mon.dvs or {}
  mon.dvs.attack = math.floor((mon.ivs.atk or 0) / 2)
  mon.dvs.defense = math.floor((mon.ivs.def or 0) / 2)
  mon.dvs.speed = math.floor((mon.ivs.spe or 0) / 2)
  mon.dvs.special = math.floor(((mon.ivs.spa or 0) + (mon.ivs.spd or 0)) / 4)
  mon.dvs.hp = math.floor((mon.ivs.hp or 0) / 2)
  MonOps.recalc(data, mon, gen)
  return target
end

function MonOps.maxIvs(data, mon, gen)
  if type(mon) ~= "table" then return end
  mon.ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
  mon.dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
  MonOps.recalc(data, mon, gen)
end

function MonOps.setSpecies(data, mon, species, gen)
  if type(mon) ~= "table" then return end
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
  if isG3 then
    local PokemonG3 = require("src.core.game3.pokemon")
    pcall(PokemonG3.install, nil)
    local spId = tonumber(species) or (PokemonG3.speciesFromName and PokemonG3.speciesFromName(tostring(species))) or 1
    local name = (PokemonG3.name and PokemonG3.name(spId)) or tostring(species)
    mon.species = spId
    mon.speciesNumbering = PokemonG3.NUMBERING_INTERNAL
    mon.speciesId = spId
    mon.name = name
    local meta = PokemonG3.speciesMeta and PokemonG3.speciesMeta(spId)
    mon.growthRate = (meta and tonumber(meta.growthRate)) or 0
    MonOps.setLevel(data, mon, mon.level or 5, gen)
    return
  end
  assert(data.pokemon[species], "unknown species: " .. tostring(species))
  mon.species = species
  MonOps.setLevel(data, mon, mon.level, gen)
  if gen == 2 or mon.experience ~= nil or (mon.stats and mon.stats.specialAttack) then
    require("src.battle.gen2.Mon").syncIdentity(mon, data)
  end
end

return MonOps
