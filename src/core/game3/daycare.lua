-- pokefirered/src/daycare.c:370

local Daycare = {}

local SPECIES_NONE = 0 -- pokefirered/include/constants/species.h:4
local PARTY_SIZE = 6 -- pokefirered/include/constants/global.h:78
local MAX_LEVEL = 100 -- pokefirered/include/constants/pokemon.h:187
local MAX_MON_MOVES = 4 -- pokefirered/include/constants/global.h:77
local DAYCARE_MON_COUNT = 2 -- pokefirered/include/constants/global.h:34

Daycare.SAVE_KEY = "firered_daycare"
Daycare.DAYCARE_MON_COUNT = DAYCARE_MON_COUNT
Daycare.PARTY_SIZE = PARTY_SIZE
Daycare.MAX_LEVEL = MAX_LEVEL

local function sessionOf(session)
  if session then return session end
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end
Daycare.sessionOf = sessionOf

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end
Daycare.speciesOf = speciesOf

local function pokemonMod()
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  return Pokemon
end

-- pokefirered/src/daycare.c:362 DayCare_GetBoxMonNickname
function Daycare.nickname(mon)
  if not mon then return "" end
  if mon.nickname and mon.nickname ~= "" then return tostring(mon.nickname) end
  local Pokemon = pokemonMod()
  return (Pokemon.name and Pokemon.name(speciesOf(mon))) or ""
end

local function persistentStore(session, field)
  if type(session.modData) ~= "table" then session.modData = {} end
  local root = session.modData[Daycare.SAVE_KEY]
  if type(root) ~= "table" then
    root = {}
    session.modData[Daycare.SAVE_KEY] = root
  end
  local store = root[field]
  if type(store) ~= "table" then
    store = {}
    root[field] = store
  end
  local loose = rawget(session, field)
  if type(loose) == "table" and loose ~= store then
    for k in pairs(store) do store[k] = nil end
    for k, v in pairs(loose) do store[k] = v end
  end
  session[field] = store
  return store
end

-- pokefirered/include/global.h:549 struct DayCare
function Daycare.stateOf(session)
  session = sessionOf(session)
  if not session then return nil end
  local dc = persistentStore(session, "daycare")
  if type(dc.steps) ~= "table" then dc.steps = { 0, 0 } end
  dc.stepCounter = tonumber(dc.stepCounter) or 0
  return dc
end

-- pokefirered/src/daycare.c:1563 gSaveBlock1Ptr->route5DayCareMon
function Daycare.route5Of(session)
  session = sessionOf(session)
  if not session then return nil end
  local r5 = persistentStore(session, "route5Daycare")
  r5.steps = tonumber(r5.steps) or 0
  return r5
end

function Daycare.mon(dc, index)
  if not dc then return nil end
  return dc[index] or (dc.mons and dc.mons[index])
end

function Daycare.setMon(dc, index, mon)
  dc[index] = mon
  if dc.mons then dc.mons[index] = mon end
end

local slotMon = Daycare.mon
local setSlotMon = Daycare.setMon

-- pokefirered/src/daycare.c:370 CountPokemonInDaycare
function Daycare.count(dc)
  local n = 0
  for i = 1, DAYCARE_MON_COUNT do
    if speciesOf(slotMon(dc, i)) ~= SPECIES_NONE then n = n + 1 end
  end
  return n
end

-- pokefirered/src/daycare.c:412 Daycare_FindEmptySpot
function Daycare.findEmptySpot(dc)
  for i = 1, DAYCARE_MON_COUNT do
    if speciesOf(slotMon(dc, i)) == SPECIES_NONE then return i end
  end
  return nil
end

-- pokefirered/src/daycare.c:1192 IsEggPending
function Daycare.isEggPending(dc)
  if not dc then return false end
  if dc.eggPending then return true end
  return (tonumber(dc.offspringPersonality) or 0) ~= 0
end

local function growthOf(mon)
  local Experience = require("src.core.game3.battle.experience")
  return Experience.growthRate(mon)
end

local function expOf(mon)
  local Experience = require("src.core.game3.battle.experience")
  local growth = growthOf(mon)
  return tonumber(mon and mon.exp) or Experience.expForLevel(growth, tonumber(mon and mon.level) or 1)
end

-- pokefirered/src/daycare.c:551 GetLevelAfterDaycareSteps
function Daycare.levelAfterSteps(mon, steps)
  if not mon then return 0 end
  local Experience = require("src.core.game3.battle.experience")
  return Experience.levelForExp(growthOf(mon), expOf(mon) + (tonumber(steps) or 0))
end

-- pokefirered/src/daycare.c:560 GetNumLevelsGainedFromSteps
function Daycare.levelsGained(mon, steps)
  if not mon then return 0 end
  local Experience = require("src.core.game3.battle.experience")
  local before = Experience.levelForExp(growthOf(mon), expOf(mon))
  return Daycare.levelAfterSteps(mon, steps) - before
end

-- pokefirered/src/daycare.c:578 GetDaycareCostForSelectedMon
function Daycare.cost(mon, steps)
  return 100 + 100 * Daycare.levelsGained(mon, steps)
end

-- pokefirered/src/pokemon.c:2288 MonTryLearningNewMove
function Daycare.teachMove(mon, moveId)
  moveId = tonumber(moveId) or 0
  if not (mon and moveId > 0) then return false end
  mon.moves = mon.moves or {}
  mon.pp = mon.pp or {}
  mon.maxPp = mon.maxPp or {}
  for i = 1, #mon.moves do
    if mon.moves[i] == moveId then return false end
  end
  local Pokemon = pokemonMod()
  local maxPp = 0
  if Pokemon.movePp then maxPp = tonumber(Pokemon.movePp(moveId)) or 0 end
  if #mon.moves < MAX_MON_MOVES then
    mon.moves[#mon.moves + 1] = moveId
    mon.pp[#mon.moves] = maxPp
    mon.maxPp[#mon.moves] = maxPp
    return true
  end
  -- pokefirered/src/daycare.c:495 DeleteFirstMoveAndGiveMoveToMon
  table.remove(mon.moves, 1)
  table.remove(mon.pp, 1)
  table.remove(mon.maxPp, 1)
  mon.moves[MAX_MON_MOVES] = moveId
  mon.pp[MAX_MON_MOVES] = maxPp
  mon.maxPp[MAX_MON_MOVES] = maxPp
  return true
end

-- pokefirered/src/daycare.c:478 ApplyDaycareExperience
function Daycare.applyExperience(mon, steps)
  if not mon then return 0 end
  local Pokemon = pokemonMod()
  local Experience = require("src.core.game3.battle.experience")
  local from = tonumber(mon.level) or 1
  if from >= MAX_LEVEL then return 0 end
  local res = Experience.apply(mon, steps)
  local to = tonumber(res and res.toLevel) or from
  -- pokefirered/src/daycare.c:491 MonTryLearningNewMove
  for level = from + 1, to do
    for _, moveId in ipairs(Pokemon.movesLearnedAt(speciesOf(mon), level) or {}) do
      Daycare.teachMove(mon, moveId)
    end
  end
  -- pokefirered/src/daycare.c:505 CalculateMonStats
  Pokemon.applyStats(mon)
  return to - from
end

-- pokefirered/src/pokemon_storage_system_data.c:904 CompactPartySlots
function Daycare.compactParty(session)
  local party = session and session.party
  if type(party) ~= "table" then return end
  local out = {}
  for i = 1, PARTY_SIZE do
    if party[i] and speciesOf(party[i]) ~= SPECIES_NONE then out[#out + 1] = party[i] end
  end
  for i = 1, PARTY_SIZE do party[i] = out[i] end
end

-- pokefirered/src/daycare.c:425 StorePokemonInDaycare
function Daycare.boxify(session, mon)
  if not mon then return mon, nil end
  local stored = nil
  if session then
    -- pokefirered/src/daycare.c:427
    stored = require("src.core.game3.mail").takeMonMailForDaycare(session, mon,
      tostring(session.name or session.playerName or ""), Daycare.nickname(mon))
  end
  mon.status = nil
  -- pokefirered/src/pokemon.c:5998 BoxMonRestorePP
  if type(mon.pp) == "table" and type(mon.maxPp) == "table" then
    for i = 1, #mon.pp do mon.pp[i] = mon.maxPp[i] or mon.pp[i] end
  end
  return mon, stored
end

-- pokefirered/src/daycare.c:449 StorePokemonInEmptyDaycareSlot
function Daycare.deposit(session, partySlot)
  session = sessionOf(session)
  local dc = Daycare.stateOf(session)
  if not (session and dc) then return nil end
  local mon = session.party and session.party[partySlot]
  if not mon or partySlot < 1 or partySlot > PARTY_SIZE then return nil end
  local free = Daycare.findEmptySpot(dc)
  if not free then return nil end
  local stored, storedMail = Daycare.boxify(session, mon)
  setSlotMon(dc, free, stored)
  dc.mail = dc.mail or {}
  dc.mail[free] = storedMail
  dc.steps[free] = 0
  session.party[partySlot] = nil
  Daycare.compactParty(session)
  return free
end

-- pokefirered/src/daycare.c:1563 PutMonInRoute5Daycare
function Daycare.depositRoute5(session, partySlot)
  session = sessionOf(session)
  local r5 = Daycare.route5Of(session)
  if not (session and r5) or r5.mon then return false end
  local mon = session.party and session.party[partySlot]
  if not mon or partySlot < 1 or partySlot > PARTY_SIZE then return false end
  local stored, storedMail = Daycare.boxify(session, mon)
  r5.mon = stored
  r5.mail = storedMail
  r5.steps = 0
  session.party[partySlot] = nil
  Daycare.compactParty(session)
  return true
end

-- pokefirered/src/daycare.c:508 TakeSelectedPokemonFromDaycare
function Daycare.withdraw(session, mon, steps, stored)
  session = sessionOf(session)
  if not (session and mon) then return SPECIES_NONE end
  local Pokemon = pokemonMod()
  local species = speciesOf(mon)
  -- pokefirered/src/pokemon.c:2172 BoxMonToMon
  mon.status = nil
  mon.hp = nil
  Pokemon.applyStats(mon)
  if (tonumber(mon.level) or 1) ~= MAX_LEVEL then
    Daycare.applyExperience(mon, steps)
  end
  session.party = session.party or {}
  -- pokefirered/src/daycare.c:525 gPlayerParty[PARTY_SIZE - 1] = pokemon
  session.party[PARTY_SIZE] = mon
  -- pokefirered/src/daycare.c:526
  if stored then
    require("src.core.game3.mail").giveDaycareMailToMon(session, mon, stored)
  end
  Daycare.compactParty(session)
  return species
end

-- pokefirered/src/daycare.c:462 ShiftDaycareSlots
function Daycare.shiftSlots(dc)
  if slotMon(dc, 2) and not slotMon(dc, 1) then
    setSlotMon(dc, 1, slotMon(dc, 2))
    setSlotMon(dc, 2, nil)
    dc.steps[1] = dc.steps[2] or 0
    dc.steps[2] = 0
    -- pokefirered/src/daycare.c:471 daycare->mons[0].mail = daycare->mons[1].mail
    dc.mail = dc.mail or {}
    dc.mail[1] = dc.mail[2]
    dc.mail[2] = nil
  end
end

-- pokefirered/src/daycare.c:539 TakeSelectedPokemonMonFromDaycareShiftSlots
function Daycare.take(session, index)
  session = sessionOf(session)
  local dc = Daycare.stateOf(session)
  local mon = slotMon(dc, index)
  if not mon then return SPECIES_NONE end
  dc.mail = dc.mail or {}
  local species = Daycare.withdraw(session, mon, dc.steps[index], dc.mail[index])
  setSlotMon(dc, index, nil)
  dc.mail[index] = nil
  dc.steps[index] = 0
  Daycare.shiftSlots(dc)
  return species
end

-- pokefirered/src/daycare.c:1588 TakePokemonFromRoute5Daycare
function Daycare.takeRoute5(session)
  session = sessionOf(session)
  local r5 = Daycare.route5Of(session)
  local mon = r5 and r5.mon
  if not mon then return SPECIES_NONE end
  local species = Daycare.withdraw(session, mon, r5.steps, r5.mail)
  r5.mon = nil
  r5.mail = nil
  r5.steps = 0
  return species
end

-- pokefirered/src/daycare.c:1168 MON_DATA_FRIENDSHIP
local function eggCyclesOf(mon)
  return tonumber(mon.friendship or mon.eggCycles or mon.cycles) or 20
end

local function isEgg(mon)
  return (mon.isEgg == true) or (type(mon.egg) == "boolean" and mon.egg)
end

-- pokefirered/src/daycare.c:1157
function Daycare.tickEggCycles(session)
  local party = session and session.party
  if type(party) ~= "table" then return nil end
  for slotIdx = 1, PARTY_SIZE do
    local mon = party[slotIdx]
    -- pokefirered/src/daycare.c:1161
    if mon and isEgg(mon) and not mon.isBadEgg then
      local cycles = eggCyclesOf(mon)
      if cycles ~= 0 then
        -- pokefirered/src/daycare.c:1171 steps -= 1
        cycles = cycles - 1
        mon.friendship = cycles
        mon.eggCycles = cycles
      else
        -- pokefirered/src/daycare.c:1176 gSpecialVar_0x8004 = i
        return slotIdx
      end
    end
  end
  return nil
end

-- pokefirered/src/daycare.c:1185 ShouldEggHatch
function Daycare.step(session)
  session = sessionOf(session)
  if not session then return 0 end
  local r5 = Daycare.route5Of(session)
  if r5 and speciesOf(r5.mon) ~= SPECIES_NONE then
    r5.steps = r5.steps + 1
  end
  local dc = Daycare.stateOf(session)
  if not dc then return 0 end
  -- pokefirered/src/daycare.c:1142
  local validEggs = 0
  for i = 1, DAYCARE_MON_COUNT do
    if speciesOf(slotMon(dc, i)) ~= SPECIES_NONE then
      dc.steps[i] = (tonumber(dc.steps[i]) or 0) + 1
      validEggs = validEggs + 1
    end
  end
  -- pokefirered/src/daycare.c:1148
  local Breeding = package.loaded["src.core.game3.breeding"]
    or require("src.core.game3.breeding")
  Breeding.tryProduceEgg(session, dc, validEggs)
  -- pokefirered/src/daycare.c:1157 ++daycare->stepCounter == 255
  dc.stepCounter = (dc.stepCounter + 1) % 256
  local hatchSlot = nil
  if dc.stepCounter == 255 then
    hatchSlot = Daycare.tickEggCycles(session)
  end
  return validEggs, hatchSlot
end

return Daycare
