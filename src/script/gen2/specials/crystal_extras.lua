-- ../pokecrystal/data/events/special_pointers.asm:147 MoveTutor, :161 PokeSeer,
-- :162 BuenasPassword, :163 BuenaPrize, :179 AskRememberPassword,
-- :181 UnusedFindItemInPCOrBag, plus the two rows both carts share:
-- :57 OverworldTownMap and :126 PrintDiploma.

local Bag = require("src.inventory.Bag")
local Buena = require("src.core.gen2.Buena")
local Mon = require("src.battle.gen2.Mon")
local Nests = require("src.core.gen2.Nests")
local RomText = require("src.core.RomText")
local Specials = require("src.script.gen2.Specials")

local S = Specials.shared

local M = {}

-- engine/overworld/variables.asm:65 wBlueCardBalance, :66 wBuenasPassword.
local VAR_BLUECARDBALANCE = 0x18

-- maps/RadioTower2F.asm:1 BLUE_CARD_POINT_CAP.
local BLUE_CARD_POINT_CAP = 30

local function hooks(vm)
  return (vm and vm.specials) or {}
end

local function eventTable(vm, key)
  local data = S.data(vm)
  local tables = data and data.gen2EventTables
  local value = tables and tables[key]
  if value == nil then error("events.lua has no " .. key, 2) end
  return value
end

--------------------------------------------------------------------------
-- MoveTutor -- ../pokecrystal/engine/events/move_tutor.asm:1
--------------------------------------------------------------------------

-- .GetMoveTutorMove (../pokecrystal/engine/events/move_tutor.asm:36) maps
-- MOVETUTOR_FLAMETHROWER..ICE_BEAM onto MT01..MT03, i.e. pokemon.tutorMoves.
local function tutorMove(vm, index)
  local d = S.data(vm)
  local list = d and d.pokemon and d.pokemon.tutorMoves
  if type(list) ~= "table" then return nil end
  if index ~= 1 and index ~= 2 then index = 3 end
  return list[index]
end

M.MoveTutor = function(vm)
  local h = hooks(vm)
  local moveId = tutorMove(vm, vm.scriptVar or 0)
  -- ../pokecrystal/engine/events/move_tutor.asm:29 .cancel, which is
  -- maps/GoldenrodCity.asm:72 .Incompatible.
  if not (moveId and h.pushScreen) then
    vm.scriptVar = 255
    return
  end
  local d = S.data(vm)
  local moveDef = d and d.moves and d.moves[moveId]
  local learned = Specials.block(vm, function(done)
    local ok = h.pushScreen("Gen2MoveTutor", {
      move = moveId,
      moveName = (moveDef and moveDef.name) or moveId,
      onDone = function(taught) done(taught and true or false) end,
    })
    if not ok then done(false) end
  end)
  -- ../pokecrystal/engine/events/move_tutor.asm:25 `xor a ; FALSE` on the learn arm.
  vm.scriptVar = learned and 0 or 255
end

--------------------------------------------------------------------------
-- Buena -- ../pokecrystal/engine/events/buena.asm:1, ../pokecrystal/engine/events/buena_menu.asm:1
--------------------------------------------------------------------------

-- ../pokecrystal/engine/events/buena_menu.asm:1-9: carry (NO or B) is 0 and a YES is 1.  The
-- question is the script's own writetext at maps/RadioTower2F.asm:119.
M.AskRememberPassword = function(vm)
  local yes = coroutine.yield({ kind = "yesorno" })
  S.answer(vm, yes and 1 or 0)
end

-- ../pokecrystal/engine/events/buena.asm:19-23 `ld a, [wBuenasPassword] / maskbits 3 / cp c`,
-- and :44-49 .PasswordIndices, which makes the menu's answer zero based.
M.BuenasPassword = function(vm)
  local h = hooks(vm)
  local data = S.data(vm)
  local category, answer = Buena.captured(S.save(vm), data)
  if not category then S.answer(vm, 0); return end
  local words = {}
  for row = 0, 2 do
    words[row + 1] = Buena.word(data, category, row)
  end
  if not h.pushScreen then
    S.answer(vm, 0)
    return
  end
  local picked = Specials.block(vm, function(done)
    local ok = h.pushScreen("Gen2BuenaPassword", {
      mode = "password",
      words = words,
      width = category.width,
      onDone = function(index) done(index or -1) end,
    })
    if not ok then done(-1) end
  end)
  S.answer(vm, (picked == answer) and 1 or 0)
end

-- ../pokecrystal/engine/events/buena.asm:147-169
local PRIZE_TEXT = {
  which = "_BuenaAskWhichPrizeText",
  confirm = "_BuenaIsThatRightText",
  hereYouGo = "_BuenaHereYouGoText",
  notEnough = "_BuenaNotEnoughPointsText",
  noRoom = "_BuenaNoRoomText",
  comeAgain = "_BuenaComeAgainText",
}

-- wBlueCardBalance is a RETVAR_ADDR_DE var, so the point the script awards at
-- maps/RadioTower2F.asm:144-146 and this counter read one store.
local function blueCardBalance(vm)
  if not vm.readVarFn then return 0 end
  local value = math.floor(tonumber(vm.readVarFn(VAR_BLUECARDBALANCE)) or 0)
  if value < 0 then value = 0 end
  return math.min(value, BLUE_CARD_POINT_CAP)
end

local function setBlueCardBalance(vm, value)
  if vm.writeVarFn then
    vm.writeVarFn(VAR_BLUECARDBALANCE, math.max(0, value) % 256)
  end
end

-- ReceiveItem into wNumItems (../pokecrystal/engine/events/buena.asm:104-110).
local function receiveItem(vm, itemId)
  local record = S.save(vm)
  if not record then return false end
  record.inventory = record.inventory or {}
  return Bag.add(record, itemId, 1, S.data(vm)) and true or false
end

M.BuenaPrize = function(vm)
  local h = hooks(vm)
  if not h.pushScreen then return end
  local d = S.data(vm)
  local items = d and d.items
  local rows = {}
  for i, prize in ipairs(eventTable(vm, "buenaPrizes")) do
    local def = items and items[prize.item]
    rows[i] = {
      item = prize.item,
      cost = prize.cost,
      name = (def and def.name) or prize.item,
    }
  end

  while true do
    -- ../pokecrystal/engine/events/buena.asm:71-83: the page is printed and the menu opens
    -- over it, so the box is held the way a `yesorno` page is held.
    S.showRawHeld(vm, RomText(d, PRIZE_TEXT.which))
    local pick = Specials.block(vm, function(done)
      local ok = h.pushScreen("Gen2BuenaPassword", {
        mode = "prize",
        prizes = rows,
        balance = blueCardBalance(vm),
        onDone = function(index) done(index or 0) end,
      })
      if not ok then done(0) end
    end)
    -- ../pokecrystal/engine/events/buena.asm:84 `jr z, .done`: 0 is the B press.
    if not (type(pick) == "number" and rows[pick]) then break end

    local row = rows[pick]
    vm:setStringBuffer(row.name)
    S.showRawHeld(vm, RomText(d, PRIZE_TEXT.confirm))
    local sure = coroutine.yield({ kind = "yesorno" })
    if sure then
      -- ../pokecrystal/engine/events/buena.asm:95-119: the cost is checked, then ReceiveItem,
      -- and only a delivered item spends the points.
      local balance = blueCardBalance(vm)
      if balance < row.cost then
        vm:showRaw(RomText(d, PRIZE_TEXT.notEnough))
      else
        if not receiveItem(vm, row.item) then
          vm:showRaw(RomText(d, PRIZE_TEXT.noRoom))
        else
          setBlueCardBalance(vm, balance - row.cost)
          if h.playSfxNamed then h.playSfxNamed("Sfx_Transaction") end
          vm:showRaw(RomText(d, PRIZE_TEXT.hereYouGo))
        end
      end
    end
  end
  -- ../pokecrystal/engine/events/buena.asm:138-145 .done.
  vm:showRaw(RomText(d, PRIZE_TEXT.comeAgain))
end

--------------------------------------------------------------------------
-- PokeSeer -- ../pokecrystal/engine/events/poke_seer.asm:18
--------------------------------------------------------------------------

-- ../pokecrystal/engine/events/poke_seer.asm:289-297 SeerTexts
local SEER_TEXT = {
  intro = "_SeerSeeAllText",
  cantTell = "_SeerCantTellAThingText",
  nameLocation = "_SeerNameLocationText",
  timeLevel = "_SeerTimeLevelText",
  trade = "_SeerTradeText",
  doNothing = "_SeerDoNothingText",
  egg = "_SeerEggText",
  noLocation = "_SeerNoLocationText",
}

-- constants/pokemon_data_constants.asm:130 CAUGHT_EGG_LEVEL and
-- constants/battle_constants.asm:4 EGG_LEVEL.
local CAUGHT_EGG_LEVEL, EGG_LEVEL = 1, 5

-- GetCaughtLevel (../pokecrystal/engine/events/poke_seer.asm:148-179).
local function caughtLevel(seer, byte0)
  local level = byte0 % 0x40
  if level == 0 then return nil, seer.unknownLevel end
  if level == CAUGHT_EGG_LEVEL then level = EGG_LEVEL end
  return level, tostring(level)
end

-- GetCaughtLocation (../pokecrystal/engine/events/poke_seer.asm:217-249); the second answer
-- is the SEERACTION_* its two sentinel arms override wSeerAction with.
local function caughtLocation(vm, seer, byte1)
  local landmark = byte1 % 0x80
  if landmark == 0 then return seer.unknown, nil end
  if landmark == Mon.LANDMARK_EVENT then return nil, "level_only" end
  if landmark == Mon.LANDMARK_GIFT then return nil, "cant_tell" end
  local record = Nests.landmark(S.data(vm), landmark)
  local name = record and record.name
  if not name then return seer.unknown, nil end
  -- engine/overworld/landmarks.asm:16 GetLandmarkName copies the break byte
  -- through; engine/pokegear/townmap_convertlinebreakcharacters.asm:1 is it.
  return (tostring(name):gsub("\n", " ")), nil
end

-- SeerAdvice (../pokecrystal/engine/events/poke_seer.asm:331-355); `sub c` is one byte.
-- ../pokecrystal/data/text/common_3.asm:372-445 text_ram wSeerNickname
local function seerAdvice(vm, seer, mon, level)
  local diff = ((mon.level or 0) - (level or 0)) % 256
  local name = Mon.displayName(mon)
  for _, row in ipairs(seer.advice) do
    if diff <= row.level then
      local text = RomText(S.data(vm), row.label)
      return vm:showRaw((text:gsub("{STRBUF}", function() return name end)))
    end
  end
end

M.PokeSeer = function(vm)
  local data = S.data(vm)
  local seer = eventTable(vm, "pokeSeer")
  vm:showRaw(RomText(data, SEER_TEXT.intro))
  local _, mon = S.selectMon(vm, "choose")
  -- ../pokecrystal/engine/events/poke_seer.asm:38 .cancel.
  if not mon then
    vm:showRaw(RomText(data, SEER_TEXT.doNothing))
    return
  end
  -- :28-29 `cp EGG / jr z, .egg`, plus the IsAPokemon test at :31.
  if mon.isEgg then
    vm:showRaw(RomText(data, SEER_TEXT.egg))
    return
  end

  local byte0, byte1 = Mon.packCaughtData(mon)
  -- ReadCaughtData's `.error` (../pokecrystal/engine/events/poke_seer.asm:104-105, :133).
  if byte0 == 0 and byte1 == 0 then
    vm:showRaw(RomText(data, SEER_TEXT.cantTell))
    return
  end

  -- ../pokecrystal/engine/events/poke_seer.asm:110-119: the `cp [hl]` on the OT id's second
  -- byte is commented out, so only the HIGH byte decides "traded".
  local record = S.save(vm)
  local playerId = (record and record.player and record.player.id) or 0
  local traded = math.floor((mon.otId or 0) / 256) % 256
    ~= math.floor(playerId / 256) % 256

  local level, levelText = caughtLevel(seer, byte0)
  local place, override = caughtLocation(vm, seer, byte1)
  local name = Mon.displayName(mon)

  -- SeerAction2 / SeerAction3 (../pokecrystal/engine/events/poke_seer.asm:81-89).
  if override == "cant_tell" then
    vm:showRaw(RomText(data, SEER_TEXT.cantTell))
    return
  end
  -- SeerAction4 (../pokecrystal/engine/events/poke_seer.asm:91-95).
  if override == "level_only" then
    vm:showRaw(RomText(data, SEER_TEXT.noLocation, nil, levelText))
    return seerAdvice(vm, seer, mon, level)
  end

  local time = math.floor(byte0 / 0x40)
  local timeText = (time > 0 and seer.times[time]) or seer.unknown

  if traded then
    -- SeerAction1 (../pokecrystal/engine/events/poke_seer.asm:72-79).
    local ot = mon.otName or mon.ot or seer.unknown
    vm:showRaw(RomText(data, SEER_TEXT.trade, nil, name, ot, place, ot, name))
  else
    -- SeerAction0 (../pokecrystal/engine/events/poke_seer.asm:64-70).
    vm:showRaw(RomText(data, SEER_TEXT.nameLocation, nil, name, place))
  end
  vm:showRaw(RomText(data, SEER_TEXT.timeLevel, nil, timeText, levelText))
  seerAdvice(vm, seer, mon, level)
end

--------------------------------------------------------------------------
-- UnusedFindItemInPCOrBag -- ../pokecrystal/mobile/mobile_12_2.asm:191
--------------------------------------------------------------------------

-- CheckItem against wNumPCItems, then wNumItems (../pokecrystal/mobile/mobile_12_2.asm:194,
-- :201); either hit is TRUE.
M.UnusedFindItemInPCOrBag = function(vm)
  local h = hooks(vm)
  local index = vm.scriptVar or 0
  local record = S.save(vm)
  local d = S.data(vm)
  local id
  for key, def in pairs((d and d.items) or {}) do
    if type(def) == "table" and def.index == index then id = key break end
  end
  local pc = record and record.pcItems
  if id and type(pc) == "table" and (tonumber(pc[id]) or 0) > 0 then
    S.answer(vm, 1)
    return
  end
  if h.hasItem and h.hasItem(index) then
    S.answer(vm, 1)
    return
  end
  S.answer(vm, 0)
end

--------------------------------------------------------------------------
-- The wall map -- engine/events/specials.asm:100
--------------------------------------------------------------------------

-- OverworldTownMap is `FadeToMenu / farcall _TownMap / ExitAllMenus`, so it
-- never writes wScriptVar; both callers (engine/events/std_scripts.asm:145
-- TownMapScript and engine/overworld/decorations.asm:1005
-- DecorationDesc_TownMapPoster) follow it with a bare `closetext`.
--
-- _TownMap (engine/pokegear/pokegear.asm:1709) draws the SAME region map the
-- POKeGEAR's MAP card draws -- it calls Pokegear_LoadGFX and PokegearMap for
-- it -- with no card strip, no ENGINE_MAP_CARD gate and no A press, which is
-- src/ui/gen2/Pokegear.lua's `townMap` mode.
M.OverworldTownMap = function(vm)
  local h = S.hooks(vm)
  if not h.pushScreen then return end
  Specials.block(vm, function(done)
    local ok = h.pushScreen("Gen2Pokegear", {
      townMap = true,
      onClose = function() done(true) end,
    })
    if not ok then done(false) end
  end)
end

--------------------------------------------------------------------------
-- The printed diploma -- engine/events/specials.asm:448
--------------------------------------------------------------------------

-- _PrintDiploma (engine/printer/printer.asm:382) opens with the very page
-- `special Diploma` shows -- `farcall PlaceDiplomaOnScreen`,
-- engine/events/diploma.asm:12 -- and only then reaches for the serial port.
-- The second sheet is built with hBGMapMode zeroed and SafeLoadTempTilemapToTilemap
-- puts page 1 straight back, so PrintDiplomaPage2 never reaches the screen on
-- the cartridge either: page 1 IS the whole visible routine.
--
-- The two SendScreenToPrinter passes are the same missing peripheral
-- H.PhotoStudio and H.UnownPrinter degrade around, and .CancelPrinting
-- (maps/CeladonMansion3F.asm:60) is unreferenced, so the cart has no text for
-- a failed print and neither does this.
M.PrintDiploma = function(vm)
  local h = S.hooks(vm)
  if not h.showDiploma then return end
  Specials.block(vm, function(done)
    h.showDiploma(function() done(true) end)
  end)
end

return M
