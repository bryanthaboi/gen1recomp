
local RomText = require("src.core.game3.rom_text")
local Std = require("src.core.game3.scripting.stdscripts")

local Seagallop = {}

local VERMILION_CITY = 0
local ONE_ISLAND = 1
local TWO_ISLAND = 2
local THREE_ISLAND = 3
local FOUR_ISLAND = 4
local FIVE_ISLAND = 5
local SIX_ISLAND = 6
local SEVEN_ISLAND = 7
local CINNABAR_ISLAND = 8
local NAVEL_ROCK = 9
local BIRTH_ISLAND = 10
local SEAGALLOP_MORE = 254

-- pokefirered/include/constants/menu.h:4
local SCR_MENU_CANCEL = 127
local SCR_MENU_UNSET = 255

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_ORIGIN = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_PAGE = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_DEST = 0x8006 -- pokefirered/include/constants/vars.h:321

local SE_SHIP = 19 -- pokefirered/include/constants/songs.h:23
local SE_EXIT = 9 -- pokefirered/include/constants/songs.h:13

-- pokefirered/src/seagallop.c:286
local CROSSING_FRAMES = 140

-- pokefirered/src/seagallop.c:62
local WARPS = {
  [VERMILION_CITY] = { 3, 5, 0x17, 0x20 },
  [ONE_ISLAND] = { 32, 4, 0x08, 0x05 },
  [TWO_ISLAND] = { 33, 4, 0x08, 0x05 },
  [THREE_ISLAND] = { 38, 0, 0x08, 0x05 },
  [FOUR_ISLAND] = { 35, 5, 0x08, 0x05 },
  [FIVE_ISLAND] = { 36, 2, 0x08, 0x05 },
  [SIX_ISLAND] = { 37, 2, 0x08, 0x05 },
  [SEVEN_ISLAND] = { 31, 6, 0x08, 0x05 },
  [CINNABAR_ISLAND] = { 3, 8, 0x15, 0x07 },
  [NAVEL_ROCK] = { 2, 59, 0x08, 0x05 },
  [BIRTH_ISLAND] = { 2, 58, 0x08, 0x05 },
}
Seagallop.WARPS = WARPS
Seagallop.WARP_COUNT = 11

-- pokefirered/src/script_menu.c:664
local function destLabel(id)
  return RomText.at("sSeagallopDestStrings", id)
end

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function scriptStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then return Space.store end
  local rt = package.loaded["src.core.game3.runtime"]
  local session = rt and rt.getSession and rt.getSession()
  return session and session.store or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(), ctx, id, tonumber(value) or 0)
end

-- pokefirered/src/seagallop.c:454
function Seagallop.seagallopNumber(originId, destId)
  if originId == CINNABAR_ISLAND or destId == CINNABAR_ISLAND then return 1 end
  if originId == VERMILION_CITY or destId == VERMILION_CITY then return 7 end
  if originId == NAVEL_ROCK or destId == NAVEL_ROCK then return 10 end
  if originId == BIRTH_ISLAND or destId == BIRTH_ISLAND then return 12 end
  local function isOneToThree(v)
    return v == ONE_ISLAND or v == TWO_ISLAND or v == THREE_ISLAND
  end
  if isOneToThree(originId) and isOneToThree(destId) then return 2 end
  local function isFourOrFive(v) return v == FOUR_ISLAND or v == FIVE_ISLAND end
  if isFourOrFive(originId) and isFourOrFive(destId) then return 3 end
  local function isSixOrSeven(v) return v == SIX_ISLAND or v == SEVEN_ISLAND end
  if isSixOrSeven(originId) and isSixOrSeven(destId) then return 5 end
  return 6
end

-- pokefirered/src/script_menu.c:1234
function Seagallop.destinationMenu(originId, page)
  local labels, top, numItems, destinationId
  if page == 1 then
    destinationId = (originId < FIVE_ISLAND) and FIVE_ISLAND or FOUR_ISLAND
    numItems, top = 5, 2
  else
    destinationId = VERMILION_CITY
    numItems, top = 6, 0
  end
  labels = {}
  local i = 0
  while i < numItems - 2 do
    if destinationId ~= originId then
      labels[#labels + 1] = destLabel(destinationId)
      i = i + 1
    end
    destinationId = destinationId + 1
    if destinationId == SEVEN_ISLAND + 1 then destinationId = VERMILION_CITY end
  end
  labels[#labels + 1] = RomText.plain("gText_Other")
  labels[#labels + 1] = RomText.plain("gOtherText_Exit")
  return labels, top
end

-- pokefirered/src/script_menu.c:1291
function Seagallop.selectedDestination(originId, page, result)
  if result == SCR_MENU_CANCEL then return SCR_MENU_CANCEL end
  if page == 1 then
    if result == 3 then return SEAGALLOP_MORE end
    if result == 4 then return SCR_MENU_CANCEL end
    if result == 0 then
      return (originId > FOUR_ISLAND) and FOUR_ISLAND or FIVE_ISLAND
    end
    if result == 1 then
      return (originId > FIVE_ISLAND) and FIVE_ISLAND or SIX_ISLAND
    end
    if result == 2 then
      return (originId > SIX_ISLAND) and SIX_ISLAND or SEVEN_ISLAND
    end
  else
    if result == 4 then return SEAGALLOP_MORE end
    if result == 5 then return SCR_MENU_CANCEL end
    if result >= originId then return result + 1 end
    return result
  end
  return VERMILION_CITY
end

Seagallop.MENU_LIST_ID = 0xF001

-- pokefirered/src/seagallop.c:174
function Seagallop.ferryTask(ctx, adapters, destId)
  local frames = 0
  local phase = "cross"
  local warp = WARPS[destId]
  return function()
    if phase == "cross" then
      frames = frames + 1
      if frames == 1 then
        local okA, Audio = pcall(require, "src.core.game3.audio")
        if okA and Audio and Audio.playSe then pcall(Audio.playSe, SE_SHIP) end
      end
      if frames < CROSSING_FRAMES then return false end
      phase = "warp"
      return false
    end
    if phase == "warp" then
      phase = "arrived"
      local okA, Audio = pcall(require, "src.core.game3.audio")
      if okA and Audio and Audio.playSe then pcall(Audio.playSe, SE_EXIT) end
      if warp and adapters and adapters.warp then
        adapters.warp(warp[1], warp[2], -1, warp[3], warp[4], function() end)
      elseif adapters and adapters.log then
        adapters.log(string.format("[game3] seagallop has no warp for dest %s", tostring(destId)))
      end
      -- pokefirered/src/seagallop.c:316
      local okF, Fade = pcall(require, "src.ui.game3.fade")
      if okF and Fade and Fade.begin then
        Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
      end
      return true
    end
    return true
  end
end

Seagallop.HANDLERS = {
  -- pokefirered/src/seagallop.c:174
  [Std.SPECIAL.DoSeagallopFerryScene] = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    local destId = varGet(ctx, VAR_DEST)
    -- pokefirered/src/seagallop.c:309
    if destId < 0 or destId >= Seagallop.WARP_COUNT then
      destId = VERMILION_CITY
      varSet(ctx, VAR_DEST, destId)
    end
    Natives.awaitState(ctx, Seagallop.ferryTask(ctx, adapters, destId))
    return false
  end,
  -- pokefirered/src/seagallop.c:454
  [Std.SPECIAL.GetSeagallopNumber] = function(ctx)
    return false, Seagallop.seagallopNumber(varGet(ctx, VAR_ORIGIN), varGet(ctx, VAR_DEST))
  end,
  -- pokefirered/src/script_menu.c:1234
  [Std.SPECIAL.DrawSeagallopDestinationMenu] = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    varSet(ctx, VAR_RESULT, SCR_MENU_UNSET)
    local originId = varGet(ctx, VAR_ORIGIN)
    local page = varGet(ctx, VAR_PAGE)
    local labels, top = Seagallop.destinationMenu(originId, page)
    if not (adapters and adapters.multichoice) then
      varSet(ctx, VAR_RESULT, SCR_MENU_CANCEL)
      return false
    end
    local Multichoice = require("src.core.game3.scripting.multichoice")
    Multichoice.LISTS[Seagallop.MENU_LIST_ID] = { labels = labels, count = #labels }
    local picked = false
    Natives.awaitState(ctx, function() return picked end)
    adapters.multichoice({
      op = "multichoice",
      [1] = 17, [2] = top, [3] = Seagallop.MENU_LIST_ID, [4] = 0,
    }, function(sel)
      varSet(ctx, VAR_RESULT, tonumber(sel) or SCR_MENU_CANCEL)
      picked = true
    end)
    return false
  end,
  -- pokefirered/src/script_menu.c:1291
  [Std.SPECIAL.GetSelectedSeagallopDestination] = function(ctx)
    local dest = Seagallop.selectedDestination(
      varGet(ctx, VAR_ORIGIN), varGet(ctx, VAR_PAGE), varGet(ctx, VAR_RESULT))
    return false, dest
  end,
}

return Seagallop
