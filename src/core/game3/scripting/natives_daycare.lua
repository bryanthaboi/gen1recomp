local Strings = require("src.core.Strings")
local Std = require("src.core.game3.scripting.stdscripts")

local Daycare = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320

local PARTY_SIZE = 6 -- pokefirered/include/constants/global.h:78
local SPECIES_NONE = 0 -- pokefirered/include/constants/species.h:4
local MAX_LEVEL = 100 -- pokefirered/include/constants/pokemon.h:187
local MAX_MON_MOVES = 4 -- pokefirered/include/constants/global.h:77

-- pokefirered/include/constants/daycare.h:11
local DAYCARE_NO_MONS = 0
local DAYCARE_EGG_WAITING = 1
local DAYCARE_MON_COUNT = 2 -- pokefirered/include/constants/global.h:34
-- pokefirered/include/constants/daycare.h:20
local DAYCARE_LEVEL_MENU_EXIT = 5
local DAYCARE_EXITED_LEVEL_MENU = 2

-- pokefirered/include/constants/daycare.h:5
local PARENTS_INCOMPATIBLE = 0
local PARENTS_LOW_COMPATIBILITY = 20
local PARENTS_MED_COMPATIBILITY = 50
local PARENTS_MAX_COMPATIBILITY = 70

-- pokefirered/include/constants/pokemon.h:131
local EGG_GROUP_DITTO = 13
local EGG_GROUP_UNDISCOVERED = 15

-- pokefirered/include/constants/party_menu.h:61
local PARTY_MENU_TYPE_DAYCARE = 6

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function scriptStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf()
  return (Space and Space.store) or (session and session.store) or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(), ctx, id, tonumber(value) or 0)
end

local function setResult(ctx, value)
  varSet(ctx, VAR_RESULT, value)
end

local function boolReturn(cond)
  return false, cond and 1 or 0
end

local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

local function pokemonMod()
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  return Pokemon
end

local function nicknameOf(mon)
  if not mon then return "" end
  if mon.nickname and mon.nickname ~= "" then return tostring(mon.nickname) end
  local Pokemon = pokemonMod()
  return (Pokemon.name and Pokemon.name(speciesOf(mon))) or ""
end

Daycare.SAVE_KEY = "firered_daycare"

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
  session = session or sessionOf()
  if not session then return nil end
  local dc = persistentStore(session, "daycare")
  if type(dc.steps) ~= "table" then dc.steps = { 0, 0 } end
  return dc
end

-- pokefirered/src/daycare.c:1563 gSaveBlock1Ptr->route5DayCareMon
function Daycare.route5Of(session)
  session = session or sessionOf()
  if not session then return nil end
  local r5 = persistentStore(session, "route5Daycare")
  r5.steps = tonumber(r5.steps) or 0
  return r5
end

local function slotMon(dc, index)
  if not dc then return nil end
  return dc[index] or (dc.mons and dc.mons[index])
end

local function setSlotMon(dc, index, mon)
  dc[index] = mon
  if dc.mons then dc.mons[index] = mon end
end

-- pokefirered/src/daycare.c:370
function Daycare.count(dc)
  local n = 0
  for i = 1, DAYCARE_MON_COUNT do
    if speciesOf(slotMon(dc, i)) ~= SPECIES_NONE then n = n + 1 end
  end
  return n
end

-- pokefirered/src/daycare.c:1192
local function eggPending(dc)
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

-- pokefirered/src/daycare.c:425 StorePokemonInDaycare
local function boxify(session, mon)
  if not mon then return mon, nil end
  local stored = nil
  if session then
    -- pokefirered/src/daycare.c:427
    stored = require("src.core.game3.mail").takeMonMailForDaycare(session, mon,
      tostring(session.name or session.playerName or ""), nicknameOf(mon))
  end
  mon.status = nil
  -- pokefirered/src/pokemon.c:5998 BoxMonRestorePP
  if type(mon.pp) == "table" and type(mon.maxPp) == "table" then
    for i = 1, #mon.pp do mon.pp[i] = mon.maxPp[i] or mon.pp[i] end
  end
  return mon, stored
end

-- pokefirered/src/pokemon_storage_system_data.c:904 CompactPartySlots
local function compactParty(session)
  local party = session and session.party
  if type(party) ~= "table" then return end
  local out = {}
  for i = 1, PARTY_SIZE do
    if party[i] and speciesOf(party[i]) ~= SPECIES_NONE then out[#out + 1] = party[i] end
  end
  for i = 1, PARTY_SIZE do party[i] = out[i] end
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
  -- pokefirered/src/daycare.c:491 MonTryLearningNewMove / DeleteFirstMoveAndGiveMoveToMon
  for level = from + 1, to do
    for _, moveId in ipairs(Pokemon.movesLearnedAt(speciesOf(mon), level) or {}) do
      Daycare.teachMove(mon, moveId)
    end
  end
  return to - from
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

-- pokefirered/src/daycare.c:508 TakeSelectedPokemonFromDaycare
function Daycare.withdraw(session, mon, steps, stored)
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
  session.party[#session.party + 1] = mon
  -- pokefirered/src/daycare.c:526
  if stored then
    require("src.core.game3.mail").giveDaycareMailToMon(session, mon, stored)
  end
  compactParty(session)
  return species
end

-- pokefirered/src/daycare.c:462 ShiftDaycareSlots
local function shiftSlots(dc)
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

-- pokefirered/src/daycare.c:1271 GetDaycareCompatibilityScore
function Daycare.compatibility(dc)
  local Pokemon = pokemonMod()
  local mons = { slotMon(dc, 1), slotMon(dc, 2) }
  local groups, species, ids, genders = {}, {}, {}, {}
  for i = 1, DAYCARE_MON_COUNT do
    local mon = mons[i]
    species[i] = speciesOf(mon)
    ids[i] = tonumber(mon and (mon.otId or mon.ot_id)) or 0
    genders[i] = (mon and Pokemon.gender and Pokemon.gender(species[i], mon.personality)) or "U"
    local meta = (Pokemon.speciesMeta and Pokemon.speciesMeta(species[i])) or {}
    groups[i] = { tonumber(meta.eggGroup1) or EGG_GROUP_UNDISCOVERED,
      tonumber(meta.eggGroup2) or EGG_GROUP_UNDISCOVERED }
  end
  if groups[1][1] == EGG_GROUP_UNDISCOVERED or groups[2][1] == EGG_GROUP_UNDISCOVERED then
    return PARENTS_INCOMPATIBLE
  end
  if groups[1][1] == EGG_GROUP_DITTO and groups[2][1] == EGG_GROUP_DITTO then
    return PARENTS_INCOMPATIBLE
  end
  if groups[1][1] == EGG_GROUP_DITTO or groups[2][1] == EGG_GROUP_DITTO then
    if ids[1] == ids[2] then return PARENTS_LOW_COMPATIBILITY end
    return PARENTS_MED_COMPATIBILITY
  end
  if genders[1] == genders[2] then return PARENTS_INCOMPATIBLE end
  if genders[1] == "U" or genders[2] == "U" then return PARENTS_INCOMPATIBLE end
  -- pokefirered/src/daycare.c:1255 EggGroupsOverlap
  local overlap = false
  for _, a in ipairs(groups[1]) do
    for _, b in ipairs(groups[2]) do
      if a == b then overlap = true end
    end
  end
  if not overlap then return PARENTS_INCOMPATIBLE end
  if species[1] == species[2] then
    if ids[1] == ids[2] then return PARENTS_MED_COMPATIBILITY end
    return PARENTS_MAX_COMPATIBILITY
  end
  if ids[1] ~= ids[2] then return PARENTS_MED_COMPATIBILITY end
  return PARENTS_LOW_COMPATIBILITY
end

-- pokefirered/src/strings.c:1252 sCompatibilityMessages
function Daycare.compatibilityText(score)
  if score == PARENTS_INCOMPATIBLE then
    return Strings("The two prefer to play with other\nPOKéMON than each other.")
  end
  if score == PARENTS_LOW_COMPATIBILITY then
    return Strings("The two don't seem to like\neach other much.")
  end
  if score == PARENTS_MED_COMPATIBILITY then
    return Strings("The two seem to get along.")
  end
  return Strings("The two seem to get along\nvery well.")
end

-- pokefirered/src/daycare.c:86 sDaycareLevelMenuWindowTemplate
local LEVEL_MENU_LAYOUT = {
  maxShowed = 3, count = 3, left = 12, top = 1, width = 17, keepOpen = false,
}
Daycare.LEVEL_MENU_LAYOUT = LEVEL_MENU_LAYOUT

-- pokefirered/src/daycare.c:1486 DaycarePrintMonInfo
function Daycare.levelMenuRows(dc)
  local rows = {}
  for i = 1, DAYCARE_MON_COUNT do
    local mon = slotMon(dc, i)
    if mon then
      rows[i] = {
        text = nicknameOf(mon),
        -- pokefirered/src/daycare.c:1482
        tailRight = 132,
        tail = Strings("Lv") .. tostring(Daycare.levelAfterSteps(mon, dc.steps[i])),
        textX = 8,
      }
    else
      rows[i] = { text = "", tailRight = 132, tail = "", textX = 8 }
    end
  end
  -- pokefirered/src/daycare.c:97 sLevelMenuItems
  rows[3] = { text = Strings("EXIT"), tailRight = 132, tail = "", textX = 8 }
  return rows
end

Daycare.HANDLERS = {
  -- pokefirered/src/daycare.c:1227 GetDaycareState
  [Std.SPECIAL.GetDaycareState] = function(ctx)
    local dc = Daycare.stateOf()
    local state = DAYCARE_NO_MONS
    if dc then
      if eggPending(dc) then
        state = DAYCARE_EGG_WAITING
      else
        local n = Daycare.count(dc)
        -- pokefirered/src/daycare.c:1236
        if n > 0 then state = n + 1 end
      end
    end
    setResult(ctx, state)
    return false, state
  end,
  -- pokefirered/src/daycare.c:1575
  [Std.SPECIAL.IsThereMonInRoute5Daycare] = function(ctx)
    local r5 = Daycare.route5Of()
    return boolReturn(speciesOf(r5 and r5.mon) ~= SPECIES_NONE)
  end,
  -- pokefirered/src/daycare.c:1244
  [Std.SPECIAL.GetDaycarePokemonCount] = function()
    return false, Daycare.count(Daycare.stateOf())
  end,
  -- pokefirered/src/daycare.c:1555 ChooseSendDaycareMon
  [Std.SPECIAL.ChooseSendDaycareMon] = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    return Natives.choosePartyMon(ctx, adapters, PARTY_MENU_TYPE_DAYCARE)
  end,
  -- pokefirered/src/daycare.c:455 StoreSelectedPokemonInDaycare
  [Std.SPECIAL.StoreSelectedPokemonInDaycare] = function(ctx)
    local session = sessionOf()
    local dc = Daycare.stateOf(session)
    if not (session and dc) then return false end
    local slot = varGet(ctx, VAR_0x8004) + 1
    local mon = session.party and session.party[slot]
    if not mon or slot > PARTY_SIZE or (tonumber(varGet(ctx, VAR_0x8004)) or 0) >= PARTY_SIZE then
      return false
    end
    -- pokefirered/src/daycare.c:412 Daycare_FindEmptySpot
    local free = nil
    for i = 1, DAYCARE_MON_COUNT do
      if not slotMon(dc, i) then
        free = i
        break
      end
    end
    if not free then return false end
    local stored, storedMail = boxify(session, mon)
    setSlotMon(dc, free, stored)
    dc.mail = dc.mail or {}
    dc.mail[free] = storedMail
    dc.steps[free] = 0
    session.party[slot] = nil
    compactParty(session)
    return false
  end,
  -- pokefirered/src/daycare.c:1563 PutMonInRoute5Daycare
  [Std.SPECIAL.PutMonInRoute5Daycare] = function(ctx)
    local session = sessionOf()
    local r5 = Daycare.route5Of(session)
    if not (session and r5) or r5.mon then return false end
    local slot = varGet(ctx, VAR_0x8004) + 1
    local mon = session.party and session.party[slot]
    if not mon then return false end
    local stored, storedMail = boxify(session, mon)
    r5.mon = stored
    r5.mail = storedMail
    r5.steps = 0
    session.party[slot] = nil
    compactParty(session)
    return false
  end,
  -- pokefirered/src/daycare.c:546 TakePokemonFromDaycare
  [Std.SPECIAL.TakePokemonFromDaycare] = function(ctx, adapters)
    local session = sessionOf()
    local dc = Daycare.stateOf(session)
    local index = varGet(ctx, VAR_0x8004) + 1
    local mon = slotMon(dc, index)
    if not mon then
      setResult(ctx, SPECIES_NONE)
      return false, SPECIES_NONE
    end
    setStringVar(ctx, adapters, 1, nicknameOf(mon))
    dc.mail = dc.mail or {}
    local species = Daycare.withdraw(session, mon, dc.steps[index], dc.mail[index])
    setSlotMon(dc, index, nil)
    dc.mail[index] = nil
    dc.steps[index] = 0
    shiftSlots(dc)
    return false, species
  end,
  -- pokefirered/src/daycare.c:1588 TakePokemonFromRoute5Daycare
  [Std.SPECIAL.TakePokemonFromRoute5Daycare] = function(ctx, adapters)
    local session = sessionOf()
    local r5 = Daycare.route5Of(session)
    local mon = r5 and r5.mon
    if not mon then
      setResult(ctx, SPECIES_NONE)
      return false, SPECIES_NONE
    end
    setStringVar(ctx, adapters, 1, nicknameOf(mon))
    local species = Daycare.withdraw(session, mon, r5.steps, r5.mail)
    r5.mon = nil
    r5.mail = nil
    r5.steps = 0
    return false, species
  end,
  -- pokefirered/src/daycare.c:594 GetDaycareCost
  [Std.SPECIAL.GetDaycareCost] = function(ctx, adapters)
    local dc = Daycare.stateOf()
    local index = varGet(ctx, VAR_0x8004) + 1
    local mon = slotMon(dc, index)
    setStringVar(ctx, adapters, 1, nicknameOf(mon))
    local cost = mon and Daycare.cost(mon, dc.steps[index]) or 0
    varSet(ctx, VAR_0x8005, cost)
    setStringVar(ctx, adapters, 2, tostring(cost))
    return false
  end,
  -- pokefirered/src/daycare.c:1569 GetCostToWithdrawRoute5DaycareMon
  [Std.SPECIAL.GetCostToWithdrawRoute5DaycareMon] = function(ctx, adapters)
    local r5 = Daycare.route5Of()
    local mon = r5 and r5.mon
    setStringVar(ctx, adapters, 1, nicknameOf(mon))
    local cost = mon and Daycare.cost(mon, r5.steps) or 0
    varSet(ctx, VAR_0x8005, cost)
    setStringVar(ctx, adapters, 2, tostring(cost))
    return false
  end,
  -- pokefirered/src/daycare.c:606 GetNumLevelsGainedFromDaycare
  [Std.SPECIAL.GetNumLevelsGainedFromDaycare] = function(ctx, adapters)
    local dc = Daycare.stateOf()
    local index = varGet(ctx, VAR_0x8004) + 1
    local mon = slotMon(dc, index)
    if not mon then return false, 0 end
    local gained = Daycare.levelsGained(mon, dc.steps[index])
    setStringVar(ctx, adapters, 1, nicknameOf(mon))
    setStringVar(ctx, adapters, 2, tostring(gained))
    return false, gained
  end,
  -- pokefirered/src/daycare.c:1583 GetNumLevelsGainedForRoute5DaycareMon
  [Std.SPECIAL.GetNumLevelsGainedForRoute5DaycareMon] = function(ctx, adapters)
    local r5 = Daycare.route5Of()
    local mon = r5 and r5.mon
    if not mon then return false, 0 end
    local gained = Daycare.levelsGained(mon, r5.steps)
    setStringVar(ctx, adapters, 1, nicknameOf(mon))
    setStringVar(ctx, adapters, 2, tostring(gained))
    return false, gained
  end,
  -- pokefirered/src/daycare.c:1200 _GetDaycareMonNicknames
  [Std.SPECIAL.GetDaycareMonNicknames] = function(ctx, adapters)
    local dc = Daycare.stateOf()
    local first = slotMon(dc, 1)
    if first then
      setStringVar(ctx, adapters, 1, nicknameOf(first))
      setStringVar(ctx, adapters, 3, tostring(first.otName or first.ot or ""))
    end
    local second = slotMon(dc, 2)
    if second then setStringVar(ctx, adapters, 2, nicknameOf(second)) end
    return false
  end,
  -- pokefirered/src/daycare.c:1338 SetDaycareCompatibilityString
  [Std.SPECIAL.SetDaycareCompatibilityString] = function(ctx, adapters)
    local text = Daycare.compatibilityText(Daycare.compatibility(Daycare.stateOf()))
    setStringVar(ctx, adapters, 4, text)
    return false
  end,
  -- pokefirered/src/daycare.c:1531 ShowDaycareLevelMenu
  [Std.SPECIAL.ShowDaycareLevelMenu] = function(ctx)
    local dc = Daycare.stateOf()
    local ListMenu = require("src.core.game3.scripting.natives_listmenu")
    local rows = Daycare.levelMenuRows(dc)
    return ListMenu.presentItems(ctx, "daycare_level", rows, LEVEL_MENU_LAYOUT,
      function(index)
        -- pokefirered/src/daycare.c:1498 Task_HandleDaycareLevelMenuInput
        if index == 0 or index == 1 then
          setResult(ctx, index)
        else
          setResult(ctx, DAYCARE_EXITED_LEVEL_MENU)
        end
      end)
  end,
  -- pokefirered/src/daycare.c:982 RejectEggFromDayCare
  [Std.SPECIAL.RejectEggFromDayCare] = function()
    local dc = Daycare.stateOf()
    if not dc then return false end
    -- pokefirered/src/daycare.c:976 RemoveEggFromDayCare
    dc.offspringPersonality = 0
    dc.stepCounter = 0
    dc.eggPending = false
    return false
  end,
  -- pokefirered/src/daycare.c:1133 GiveEggFromDaycare
  [Std.SPECIAL.GiveEggFromDaycare] = function(_, adapters)
    local dc = Daycare.stateOf()
    if not eggPending(dc) then return false end
    if adapters and adapters.log then
      adapters.log("[game3] GiveEggFromDaycare has no egg to hand over yet")
    end
    dc.offspringPersonality = 0
    dc.stepCounter = 0
    dc.eggPending = false
    return false
  end,
}

Daycare.DAYCARE_NO_MONS = DAYCARE_NO_MONS
Daycare.DAYCARE_EGG_WAITING = DAYCARE_EGG_WAITING
Daycare.DAYCARE_EXITED_LEVEL_MENU = DAYCARE_EXITED_LEVEL_MENU
Daycare.DAYCARE_LEVEL_MENU_EXIT = DAYCARE_LEVEL_MENU_EXIT
Daycare.PARENTS_INCOMPATIBLE = PARENTS_INCOMPATIBLE
Daycare.PARENTS_LOW_COMPATIBILITY = PARENTS_LOW_COMPATIBILITY
Daycare.PARENTS_MED_COMPATIBILITY = PARENTS_MED_COMPATIBILITY
Daycare.PARENTS_MAX_COMPATIBILITY = PARENTS_MAX_COMPATIBILITY

return Daycare
