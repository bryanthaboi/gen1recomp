local Strings = require("src.core.Strings")
local Std = require("src.core.game3.scripting.stdscripts")
local Model = require("src.core.game3.daycare")
local Breeding = require("src.core.game3.breeding")

local Daycare = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320

local PARTY_SIZE = 6 -- pokefirered/include/constants/global.h:78
local SPECIES_NONE = 0 -- pokefirered/include/constants/species.h:4

-- pokefirered/include/constants/daycare.h:11
local DAYCARE_NO_MONS = 0
local DAYCARE_EGG_WAITING = 1
-- pokefirered/include/constants/daycare.h:20
local DAYCARE_LEVEL_MENU_EXIT = 5
local DAYCARE_EXITED_LEVEL_MENU = 2

-- pokefirered/include/constants/daycare.h:5
local PARENTS_INCOMPATIBLE = 0
local PARENTS_LOW_COMPATIBILITY = 20
local PARENTS_MED_COMPATIBILITY = 50
local PARENTS_MAX_COMPATIBILITY = 70

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

local speciesOf = Model.speciesOf
local nicknameOf = Model.nickname
local slotMon = Model.mon
local eggPending = Model.isEggPending

Daycare.SAVE_KEY = Model.SAVE_KEY
Daycare.stateOf = Model.stateOf
Daycare.route5Of = Model.route5Of
Daycare.count = Model.count
Daycare.levelAfterSteps = Model.levelAfterSteps
Daycare.levelsGained = Model.levelsGained
Daycare.cost = Model.cost
Daycare.applyExperience = Model.applyExperience
Daycare.teachMove = Model.teachMove
Daycare.withdraw = Model.withdraw
Daycare.step = Model.step

-- pokefirered/src/daycare.c:1271 GetDaycareCompatibilityScore
Daycare.compatibility = Breeding.compatibility

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

local function levelMenu()
  return require("src.ui.game3.daycare_menu")
end

-- pokefirered/src/daycare.c:86 sDaycareLevelMenuWindowTemplate
local LEVEL_MENU_LAYOUT = {
  maxShowed = 3, count = 3, left = 12, top = 1, width = 17, keepOpen = false,
}
Daycare.LEVEL_MENU_LAYOUT = LEVEL_MENU_LAYOUT

-- pokefirered/src/daycare.c:1486 DaycarePrintMonInfo
function Daycare.levelMenuRows(dc)
  local Menu = levelMenu()
  local rows = {}
  for i, row in ipairs(Menu.rows(dc)) do
    rows[i] = {
      text = row.text,
      symbol = row.symbol,
      -- pokefirered/src/daycare.c:1482
      tailRight = Menu.LEVEL_RIGHT,
      tail = row.level,
      textX = Menu.TEXT_X,
      value = row.value,
    }
  end
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
    if not session then return false end
    local selected = varGet(ctx, VAR_0x8004)
    if selected >= PARTY_SIZE then return false end
    Model.deposit(session, selected + 1)
    return false
  end,
  -- pokefirered/src/daycare.c:1563 PutMonInRoute5Daycare
  [Std.SPECIAL.PutMonInRoute5Daycare] = function(ctx)
    local session = sessionOf()
    if not session then return false end
    local selected = varGet(ctx, VAR_0x8004)
    if selected >= PARTY_SIZE then return false end
    Model.depositRoute5(session, selected + 1)
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
    return false, Model.take(session, index)
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
    return false, Model.takeRoute5(session)
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
    local Natives = require("src.core.game3.scripting.natives")
    local Menu = levelMenu()
    local done = false
    Natives.awaitState(ctx, function() return done end)
    local shown = Menu.show(Daycare.stateOf(), function(value)
      -- pokefirered/src/daycare.c:1504 Task_HandleDaycareLevelMenuInput
      if value == 0 or value == 1 then
        setResult(ctx, value)
      else
        setResult(ctx, DAYCARE_EXITED_LEVEL_MENU)
      end
      done = true
    end)
    if not shown then
      setResult(ctx, DAYCARE_EXITED_LEVEL_MENU)
      done = true
    end
    return false
  end,
  -- pokefirered/src/daycare.c:982 RejectEggFromDayCare
  [Std.SPECIAL.RejectEggFromDayCare] = function()
    Breeding.removeEgg(Daycare.stateOf())
    return false
  end,
  -- pokefirered/src/daycare.c:1133 GiveEggFromDaycare
  [Std.SPECIAL.GiveEggFromDaycare] = function()
    local dc = Daycare.stateOf()
    if not eggPending(dc) then return false end
    local session = sessionOf()
    -- pokefirered/data/maps/FourIsland/scripts.inc:96
    local party = session and session.party or {}
    local count = 0
    for i = 1, PARTY_SIZE do
      if speciesOf(party[i]) ~= SPECIES_NONE then count = count + 1 end
    end
    if count >= PARTY_SIZE then return false end
    Breeding.giveEggFromDaycare(session)
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
