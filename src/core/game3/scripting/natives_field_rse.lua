local Std = require("src.core.game3.scripting.stdscripts")
local Rse = require("src.core.game3.rse.init")

local FieldRse = {}

-- pokeemerald/include/constants/vars.h:280
local VAR_0x8004 = 0x8004
local function varId(name)
  return Rse.varId(name, Rse.session())
end

-- pokeemerald/include/constants/global.h:113
local MALE = 0

local function gender()
  local s = Rse.session()
  return tonumber(s and s.gender) or MALE
end

local function frameType(sess)
  local ok, Options = pcall(require, "src.core.game3.options")
  if not ok or not (Options and Options.block) then return 0 end
  local okB, block = pcall(Options.block, sess and sess.options)
  return okB and type(block) == "table" and tonumber(block.frameType) or 0
end

-- pokeemerald/src/battle_setup.c:917
function FieldRse.giveStarter(ctx, selection, sess)
  sess = sess or Rse.session()
  local StarterChoose = require("src.ui.game3.rse.starter_choose")
  Rse.setVar("VAR_STARTER_MON", selection, sess)
  local species = StarterChoose.species(nil, selection)
  if not species then error("ChooseStarter: starter_choose manifest has no species", 2) end
  local Party = require("src.core.game3.party")
  -- pokeemerald/src/script_pokemon_util.c:61
  local code = Party.giveMonToPlayer(sess, species, 5)
  return species, code
end

-- pokeemerald/src/battle_setup.c:930
function FieldRse.startFirstBattle(onEnd, logger)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local BattleBridge = require("src.core.game3.battle_bridge")
  local handle, err = BattleBridge.startFirstBattle(Runtime and Runtime._mod, Runtime and Runtime._game, {
    done = function(result)
      -- pokeemerald/src/battle_setup.c:950
      if onEnd then onEnd(result) end
    end,
  })
  if not handle and err then
    local msg = "[game3] ChooseStarter: first battle did not start (" .. tostring(err) .. ")"
    if logger then logger(msg) else print(msg) end
    if onEnd then onEnd(nil) end
  end
  return handle, err
end

local function condition(name)
  local sess = Rse.session()
  local mon = sess and sess.party and sess.party[1]
  return tonumber(mon and mon.contest and mon.contest[name]) or 0
end

-- pokeemerald/src/field_poison.c:29-114
local function tryFieldPoisonWhiteOut(ctx, adapters)
  local sess = Rse.session()
  local party = sess and sess.party or {}
  local Pokemon = require("src.core.game3.pokemon")
  local fainted = {}
  for i, mon in ipairs(party) do
    local isEgg = Pokemon.isEgg and Pokemon.isEgg(mon)
    local status = tostring(mon.status or ""):upper()
    local poisoned = status == "PSN" or status == "POISON" or status == "TOXIC"
      or (tonumber(mon.statusNum) or 0) == 8
    if not isEgg and poisoned and (tonumber(mon.hp) or 0) == 0 then
      Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_FAINT_OUTSIDE_BATTLE,
        { mapSec = Pokemon.currentMapSec(sess) })
      mon.status, mon.statusNum = nil, 0
      fainted[#fainted + 1] = { slot = i, name = Pokemon.displayMonName(mon) }
    end
  end

  local function resultCode()
    local wiped = true
    for _, mon in ipairs(party) do
      if not (Pokemon.isEgg and Pokemon.isEgg(mon)) and (tonumber(mon.hp) or 0) > 0 then
        wiped = false
        break
      end
    end
    if not wiped then return 0 end
    local Pike = require("src.core.game3.rse.frontier.pike")
    local Pyramid = require("src.core.game3.rse.frontier.pyramid")
    local Hill = require("src.core.game3.rse.trainer_hill")
    if Pike.MAPS[sess and sess.map] or Pyramid.inPyramid(sess) or Hill.inChallenge(sess) then
      return 2
    end
    return 1
  end

  local function complete(done)
    Rse.setSpecialVar(ctx, varId("VAR_RESULT"), resultCode())
    done()
  end
  local Natives = require("src.core.game3.scripting.natives")
  return Natives.yieldHost(ctx, adapters, function(done)
    local index = 1
    local function nextFaintMessage()
      local row = fainted[index]
      index = index + 1
      if not row or not (adapters and adapters.openMessageAsync) then
        if row then
          while fainted[index] do index = index + 1 end
        end
        complete(done)
        return
      end
      local profile = require("src.core.game3.profile").forSession(sess)
      local key = (profile.field and profile.field.poisonFaintText) or "gText_PkmnFainted_FldPsn"
      local text = require("src.core.game3.rom_text").box(key, { stringVars = { row.name } })
      adapters.openMessageAsync(text, nextFaintMessage)
    end
    nextFaintMessage()
  end)
end

local function trainerIdForSpeech(ctx, sess)
  local TrainerSight = require("src.core.game3.trainer_sight")
  if TrainerSight.checkTrainerB and TrainerSight._pair then
    local id = TrainerSight.checkTrainerB and TrainerSight._pair.b or TrainerSight._pair.a
    if tonumber(id) and tonumber(id) > 0 then return tonumber(id) end
  end
  local id = tonumber(ctx and ctx.trainerBattleOpponentA) or 0
  if id > 0 then return id end
  local localId = Rse.specialVar(ctx, varId("VAR_LAST_TALKED"))
  local Objects = require("src.core.game3.objects")
  local eo = Objects.find(localId) or TrainerSight._approached
  if eo then return tonumber(TrainerSight.getTrainerId(eo)) or 0 end
  return 0
end

local function plainTrainerSpeech(text)
  if type(text) == "string" then return text end
  if type(text) == "table" then
    return require("src.core.game3.scripting.text_ir").toPlain(text, {})
  end
  return ""
end

local function showTrainerSpeech(ctx, adapters, text, intro)
  text = plainTrainerSpeech(text)
  if text == "" then return false end
  if intro and ctx then ctx.trainerIntroShown = true end
  local Natives = require("src.core.game3.scripting.natives")
  if not (adapters and adapters.openMessageAsync) then return false end
  return Natives.yieldHost(ctx, adapters, function(done)
    adapters.openMessageAsync(text, done)
  end)
end

FieldRse.BY_NAME = {
  TryFieldPoisonWhiteOut = tryFieldPoisonWhiteOut,
  -- pokeemerald/src/trainer_see.c:655
  DoTrainerApproach = function() return false end,
  -- pokeemerald/src/trainer_see.c:666
  TryPrepareSecondApproachingTrainer = function(ctx)
    Rse.setSpecialVar(ctx, varId("VAR_RESULT"), 0)
    return false
  end,
  -- pokeemerald/src/battle_setup.c:1378
  ShowTrainerIntroSpeech = function(ctx, adapters)
    local sess = Rse.session()
    local TrainerSight = require("src.core.game3.trainer_sight")
    local localId = Rse.specialVar(ctx, varId("VAR_LAST_TALKED"))
    local text
    local Pyramid = require("src.core.game3.rse.frontier.pyramid")
    local Hill = require("src.core.game3.rse.trainer_hill")
    if Pyramid.inPyramid(sess) then
      local id = Pyramid.localIdToTrainerId(sess, localId)
      text = Pyramid.speech(sess, id, 0)
    elseif Hill.inChallenge(sess) then
      text = Hill.trainerText(sess, Hill.TEXT.INTRO, localId)
    else
      text = require("src.core.game3.scripting.trainers").dialogs(trainerIdForSpeech(ctx, sess)).intro
    end
    return showTrainerSpeech(ctx, adapters, text, true)
  end,
  -- pokeemerald/src/battle_setup.c:1435
  ShowTrainerCantBattleSpeech = function(ctx, adapters)
    local sess = Rse.session()
    local text = require("src.core.game3.scripting.trainers")
      .dialogs(trainerIdForSpeech(ctx, sess)).notEnough
    return showTrainerSpeech(ctx, adapters, text, false)
  end,
  -- pokeemerald/src/decoration.c:2217
  GetObjectEventLocalIdByFlag = function(ctx)
    local flag = Rse.specialVar(ctx, VAR_0x8004) % 0x10000
    local Objects = require("src.core.game3.objects")
    for _, def in ipairs(Objects._defs or {}) do
      if tonumber(def.flag) == flag then
        Rse.setSpecialVar(ctx, Rse.varId("VAR_0x8005", Rse.session()), tonumber(def.localId or def.index) or 0)
        break
      end
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:2957
  ShowFrontierExchangeCornerItemIconWindow = function()
    require("src.ui.game3.screens").get("frontier_preview", Rse.session()).exchangeOpen = true
    return false
  end,
  -- pokeemerald/src/field_specials.c:2975
  CloseFrontierExchangeCornerItemIconWindow = function()
    require("src.ui.game3.screens").get("frontier_preview", Rse.session()).exchangeOpen = false
    return false
  end,
  -- pokeemerald/src/overworld.c:1142
  Overworld_PlaySpecialMapMusic = function()
    local Audio = require("src.core.game3.audio")
    local song = Audio.specialMapSong()
    if song ~= nil and song ~= Audio.currentMapMusic() then Audio.playSong(song) end
    return false
  end,
  -- pokeemerald/src/sound.c:127
  StopMapMusic = function()
    require("src.core.game3.audio").playSong(0)
    return false
  end,
  -- pokeemerald/src/field_specials.c:3582
  Unused_SetWeatherSunny = function()
    local Weather = require("src.core.game3.weather")
    local weather = Weather.SUNNY
    local Engine = require("src.core.game3.field_weather_rse")
    Engine.setCurrentAndNextWeather(weather)
    Weather.setWeather(weather, Rse.session())
    return false
  end,
  -- pokeemerald/src/field_specials.c:1190
  CheckLeadMonCool = function() return false, condition("cool") >= 200 and 1 or 0 end,
  -- pokeemerald/src/field_specials.c:1198
  CheckLeadMonBeauty = function() return false, condition("beauty") >= 200 and 1 or 0 end,
  -- pokeemerald/src/field_specials.c:1206
  CheckLeadMonCute = function() return false, condition("cute") >= 200 and 1 or 0 end,
  -- pokeemerald/src/field_specials.c:1214
  CheckLeadMonSmart = function() return false, condition("smart") >= 200 and 1 or 0 end,
  -- pokeemerald/src/field_specials.c:1222
  CheckLeadMonTough = function() return false, condition("tough") >= 200 and 1 or 0 end,
  -- pokeemerald/src/field_specials.c:906
  GetPlayerBigGuyGirlString = function(ctx)
    if ctx and ctx.stringVars then
      ctx.stringVars[1] = Rse.text(gender() == MALE and "gText_BigGuy" or "gText_BigGirl")
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:914
  GetRivalSonDaughterString = function(ctx)
    if ctx and ctx.stringVars then
      ctx.stringVars[1] = Rse.text(gender() == MALE and "gText_Daughter" or "gText_Son")
    end
    return false
  end,
  -- pokeemerald/src/battle_setup.c:911
  ChooseStarter = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    local StarterChoose = require("src.ui.game3.rse.starter_choose")
    local sess = Rse.session()
    local logger = adapters and adapters.log
    return Natives.yieldHost(ctx, adapters, function(done)
      -- pokeemerald/src/starter_choose.c:414
      local okF, Fade = pcall(require, "src.ui.game3.fade")
      if okF and Fade and Fade.clear then Fade.clear() end
      StarterChoose.open({
        frameType = frameType(sess),
        onDone = function(selection)
          -- pokeemerald/src/starter_choose.c:546
          Rse.setSpecialVar(ctx, varId("VAR_RESULT"), selection)
          FieldRse.giveStarter(ctx, selection, sess)
          FieldRse.lastSelection = selection
          FieldRse.startFirstBattle(function(result)
            FieldRse.lastBattleResult = result
            done()
          end, logger)
        end,
      })
    end)
  end,
  -- pokeemerald/src/field_camera.c:94
  DrawWholeMapView = function()
    local FieldView = package.loaded["src.core.game3.field_view"]
    if FieldView then FieldView._nativeDirty = true end
    return false
  end,
  -- pokeemerald/src/field_specials.c:1251
  SpawnCameraObject = function()
    local ok, CameraObject = pcall(require, "src.core.game3.camera_object")
    local rt = package.loaded["src.core.game3.runtime"]
    if ok and CameraObject and CameraObject.spawn then pcall(CameraObject.spawn, rt and rt._game) end
    return false
  end,
  -- pokeemerald/src/battle_setup.c:1230
  GetTrainerBattleMode = function(ctx)
    return false, tonumber(ctx and ctx.trainerBattleMode) or 0
  end,
  -- pokeemerald/src/battle_setup.c:1224
  SetTrainerFacingDirection = function(ctx)
    local localId = Rse.specialVar(ctx, varId("VAR_LAST_TALKED"))
    local Objects = require("src.core.game3.objects")
    local eo = Objects.find(localId)
    local movementType = ({ up = 7, down = 8, left = 9, right = 10 })[eo and eo.facing]
    if eo and movementType then Objects.setTrainerMovementType(eo, movementType) end
    return false
  end,
  -- pokeemerald/src/field_specials.c:1263
  RemoveCameraObject = function()
    local ok, CameraObject = pcall(require, "src.core.game3.camera_object")
    local rt = package.loaded["src.core.game3.runtime"]
    if ok and CameraObject and CameraObject.remove then
      pcall(CameraObject.remove, rt and rt._game, { preserveFocus = true })
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:1470
  ShakeCamera = function(ctx)
    local Natives = require("src.core.game3.scripting.natives")
    local h, v = Rse.specialVar(ctx, 0x8005), Rse.specialVar(ctx, 0x8004)
    local shakes, delay = Rse.specialVar(ctx, 0x8006), Rse.specialVar(ctx, 0x8007)
    local SE = require("src.core.game3.se_ids")
    pcall(function() require("src.core.game3.audio").playSe(SE.SE_M_STRENGTH) end)
    local FieldView = package.loaded["src.core.game3.field_view"]
    local okT, Task = pcall(require, "src.core.game3.task")
    local finished = not (okT and Task and Task.spawn) or delay < 1
    if not finished then
      local counter = 0
      -- pokeemerald/src/field_specials.c:1482
      Task.spawn(function()
        counter = counter + 1
        if counter % delay == 0 then
          counter = 0
          shakes = (shakes - 1) % 0x10000
          h, v = -h, -v
          if FieldView then FieldView.cameraPanX, FieldView.cameraPanY = h, v end
          if shakes == 0 then
            if FieldView then FieldView.cameraPanX, FieldView.cameraPanY = 0, 0 end
            finished = true
            return true
          end
        end
        return false
      end)
    end
    Natives.awaitState(ctx, function() return finished end)
    return false
  end,
  -- pokeemerald/src/event_data.c:63
  EnableNationalPokedex = function()
    local sess = Rse.session()
    if not sess then return false end
    local Dex = require("src.core.game3.dex")
    Dex.enableNational(sess)
    local block = Rse.profile(sess)
    local nat = block and block.dex and block.dex.national
    if nat then
      Rse.setVar(nat.var, nat.value, sess)
      Rse.setFlag(nat.flag, true, sess)
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:3443
  CreateAbnormalWeatherEvent = function()
    local Rng = require("src.core.game3.rng")
    local random = Rng.Random()
    local location
    if Rse.flag("FLAG_DEFEATED_KYOGRE") then
      location = random % 8 + 1
    elseif Rse.flag("FLAG_DEFEATED_GROUDON") then
      location = random % 8 + 9
    elseif random % 2 == 0 then
      location = Rng.Random() % 8 + 1
    else
      location = Rng.Random() % 8 + 9
    end
    Rse.setVar("VAR_ABNORMAL_WEATHER_STEP_COUNTER", 0)
    Rse.setVar("VAR_ABNORMAL_WEATHER_LOCATION", location)
    return false
  end,
  -- pokeemerald/src/field_specials.c:3470
  GetAbnormalWeatherMapNameAndType = function(ctx, adapters)
    local location = Rse.var("VAR_ABNORMAL_WEATHER_LOCATION")
    local mapSecs = {
      "ROUTE_114", "ROUTE_114", "ROUTE_115", "ROUTE_115",
      "ROUTE_116", "ROUTE_116", "ROUTE_118", "ROUTE_118",
      "ROUTE_105", "ROUTE_105", "ROUTE_125", "ROUTE_125",
      "ROUTE_127", "ROUTE_127", "ROUTE_129", "ROUTE_129",
    }
    local sectionName = mapSecs[location]
    if sectionName then
      local RegionMap = require("src.ui.game3.rse.region_map")
      local sec = RegionMap.mapsec(sectionName)
      if sec and adapters and adapters.setStringVar then
        adapters.setStringVar(1, RegionMap.mapName(sec))
      end
    end
    return false, location >= 9 and 1 or 0
  end,
  -- pokeemerald/src/field_specials.c:2761
  ShowGlassWorkshopMenu = function() return false end,
  -- pokeemerald/src/field_specials.c:3588
  GetMartEmployeeObjectEventId = function() return false, 1 end,
}

Std.legacyHandlers(FieldRse)

local Story = require("src.core.game3.rse.story_specials")

local VAR_0x8005, VAR_0x8006, VAR_0x8007 = 0x8005, 0x8006, 0x8007

-- pokeemerald/include/constants/global.h:33
local PARTY_SIZE = 6
-- pokeemerald/include/constants/global.h:30
local GAME_LANGUAGE = 2
-- pokeemerald/include/constants/pokemon.h:204
local MAX_TOTAL_EVS = 510
-- pokeemerald/include/constants/tv.h:84
local NUM_CUTIES_RIBBONS = 4
-- pokeemerald/include/constants/game_stat.h:46
local GAME_STAT_RECEIVED_RIBBONS = 42
-- pokeemerald/include/constants/heal_locations.h:13
local HEAL_LOCATION_PETALBURG_CITY = 3
local HEAL_LOCATION_DEWFORD_TOWN = 15

-- pokeemerald/include/constants/pokemon.h:18
local TYPE_GRASS = 12

-- pokeemerald/include/constants/map_types.h:5
local OUTDOOR_MAP_TYPES = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true }

local function C(sess)
  local Constants = require("src.core.game3.constants")
  return Constants.of(Constants.versionOf(sess or Rse.session()))
end

local function partyOf(sess)
  sess = sess or Rse.session()
  return (sess and sess.party) or {}
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

local function isEgg(mon)
  return mon ~= nil and (mon.isEgg == true or mon.egg == true)
end

-- pokeemerald/src/pokemon.c:4141 MON_DATA_SPECIES_OR_EGG
local function speciesOrEgg(mon)
  if speciesOf(mon) == 0 then return 0 end
  if isEgg(mon) or mon.isBadEgg then return C():require("species", "SPECIES_EGG") end
  return speciesOf(mon)
end

local function partyCount(sess)
  local n = 0
  local p = partyOf(sess)
  for i = 1, PARTY_SIZE do
    if speciesOf(p[i]) ~= 0 then n = i end
  end
  return n
end

-- pokeemerald/src/field_specials.c:1531 GetLeadMonIndex
function FieldRse.leadMonIndex(sess)
  local p = partyOf(sess)
  local egg = C(sess):require("species", "SPECIES_EGG")
  for i = 1, partyCount(sess) do
    local s = speciesOrEgg(p[i])
    if s ~= egg and s ~= 0 then return i end
  end
  return 1
end

local function leadMon(sess)
  return partyOf(sess)[FieldRse.leadMonIndex(sess)]
end

local function field()
  return package.loaded["src.core.game3.field"] or require("src.core.game3.field")
end

local function metatileAt(x, y)
  local Collision = package.loaded["src.core.game3.collision"]
  local def = Collision and Collision._mapDef
  local layout = def and def.midLayout
  return layout and layout.midAt and layout:midAt(x, y) or 0
end
FieldRse.metatileAt = metatileAt

local function setMetatile(x, y, mid, impassable)
  field().setMetatile(x, y, mid, impassable == true)
end
FieldRse.setMetatile = setMetatile

local function drawWholeMapView()
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
end

local function playSe(name)
  local SE = require("src.core.game3.se_ids")
  if SE[name] then pcall(function() require("src.core.game3.audio").playSe(SE[name]) end) end
end

local function stringVar(ctx, adapters, i, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(i, text) end
  if ctx and ctx.stringVars then ctx.stringVars[i] = text end
end

local function boolRet(v)
  return false, v and 1 or 0
end

-- pokeemerald/src/pokedex.c:4387
function FieldRse.hasAllHoennMons(sess)
  local id = require("src.core.game3.constants").versionOf(sess)
  if id == "ruby" or id == "sapphire" then return require("src.core.game3.profiles.rs.pokedex").completedHoenn(sess) end
  local Dex = require("src.core.game3.dex")
  local caught = sess and sess.dex and (sess.dex.caught or sess.dex.owned) or {}
  local need = Dex.regionalMax() - 2
  local have = 0
  for species = 1, 440 do
    local n = Dex.regionalNumber(species)
    if n and n >= 1 and n <= need and caught[species] then have = have + 1 end
  end
  return have >= need
end

-- pokeemerald/src/trainer_card.c:663
function FieldRse.countTrainerStars(sess)
  if not sess then return 0 end
  local stars = 0
  -- pokeemerald/include/constants/game_stat.h:14
  if (tonumber((sess.gameStats or {})[10]) or 0) > 0 then stars = stars + 1 end
  if FieldRse.hasAllHoennMons(sess) then stars = stars + 1 end
  -- pokeemerald/src/contest_util.c:2381
  local paintings = 0
  local winners = sess.contestWinners or {}
  for i = 9, 13 do
    local w = winners[i]
    if type(w) == "table" and (tonumber(w.species) or 0) ~= 0 then paintings = paintings + 1 end
  end
  if paintings >= 5 then stars = stars + 1 end
  -- pokeemerald/src/trainer_card.c:652
  local Flags = require("src.core.game3.scripting.flags")
  local symbols = true
  local base = Rse.flagId("FLAG_SYS_TOWER_SILVER", sess)
  for i = 0, 6 do
    if not (Flags.getFlag(Rse.store(), nil, base + 2 * i) and Flags.getFlag(Rse.store(), nil, base + 2 * i + 1)) then
      symbols = false
    end
  end
  if symbols then stars = stars + 1 end
  return stars
end

local function flagSetting(name)
  return function()
    return boolRet(Rse.flag(name))
  end
end

local function localDays(sess)
  local Rtc = require("src.core.game3.rtc")
  return Rtc.calcLocalTime(sess or Rse.session())
end

-- pokeemerald/src/overworld.c:1354 IsMapTypeOutdoors
function FieldRse.lastUsedWarpOutdoors(sess)
  sess = sess or Rse.session()
  local last = sess and sess.lastUsedWarp
  if type(last) ~= "table" then return nil end
  local mapType = tonumber(last.mapType)
  if mapType == nil and last.map then
    local rt = package.loaded["src.core.game3.runtime"]
    local game = rt and rt._game
    local def = game and game.data and game.data.maps and game.data.maps[last.map]
    mapType = def and tonumber(def.mapType)
  end
  if mapType == nil then return nil end
  return OUTDOOR_MAP_TYPES[mapType] == true
end

local function delegate(module, name)
  return function(...)
    local mod = require("src.core.game3.scripting." .. module)
    return mod.BY_NAME[name](...)
  end
end

-- pokeemerald/src/load_save.c:160 SavePlayerParty
function FieldRse.savePlayerParty(sess)
  sess = sess or Rse.session()
  if not sess then return end
  local saved = {}
  for i = 1, PARTY_SIZE do
    local mon = sess.party and sess.party[i]
    if mon then
      local okC, copy = pcall(function()
        local out = {}
        local function deep(v)
          if type(v) ~= "table" then return v end
          local t = {}
          for k, x in pairs(v) do t[k] = deep(x) end
          return t
        end
        out = deep(mon)
        return out
      end)
      saved[i] = okC and copy or mon
    end
  end
  sess.savedPlayerParty = saved
end

-- pokeemerald/src/load_save.c:170 LoadPlayerParty
function FieldRse.loadPlayerParty(sess)
  sess = sess or Rse.session()
  if not (sess and type(sess.savedPlayerParty) == "table") then return end
  local party = {}
  for i = 1, PARTY_SIZE do party[i] = sess.savedPlayerParty[i] end
  sess.party = party
end

-- pokeemerald/src/field_specials.c:1423 LoadWallyZigzagoon
function FieldRse.loadWallyZigzagoon(sess)
  sess = sess or Rse.session()
  if not sess then return nil end
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local K = C(sess)
  local species = K:require("species", "SPECIES_ZIGZAGOON")
  local scratch = setmetatable({ party = {}, dex = { seen = {}, owned = {}, caught = {} } }, { __index = sess })
  local ok, _, mon = Party.giveMon(scratch, species, 7)
  if not (ok and mon) then return nil end
  mon.abilityNum = 1
  mon.ability = Pokemon.abilities(species)[2]
  mon.abilityId = mon.ability
  local tackle = K:require("moves", "MOVE_TACKLE")
  local pp = tonumber(Pokemon.movePp(tackle)) or 35
  mon.moves, mon.pp, mon.maxPp = { tackle }, { pp }, { pp }
  sess.party = sess.party or {}
  sess.party[1] = mon
  return mon
end

-- pokeemerald/src/time_events.c:31
function FieldRse.updateMirageRnd(sess, days)
  local Rng = require("src.core.game3.rng")
  local rnd = Rse.var("VAR_MIRAGE_RND_H", sess) * 0x10000 + Rse.var("VAR_MIRAGE_RND_L", sess)
  for _ = 1, tonumber(days) or 0 do
    rnd = (Rng.mulU32(rnd, 1103515245) + 12345) % 0x100000000
  end
  Rse.setVar("VAR_MIRAGE_RND_H", math.floor(rnd / 0x10000), sess)
  Rse.setVar("VAR_MIRAGE_RND_L", rnd % 0x10000, sess)
end

-- pokeemerald/src/time_events.c:42
function FieldRse.isMirageIslandPresent(sess)
  local rnd = Rse.var("VAR_MIRAGE_RND_H", sess)
  local p = partyOf(sess)
  for i = 1, PARTY_SIZE do
    local mon = p[i]
    if speciesOf(mon) ~= 0 and (tonumber(mon.personality) or 0) % 0x10000 == rnd then return true end
  end
  return false
end

-- pokeemerald/src/time_events.c:56
FieldRse.SHOAL_TIDE = {
  [0] = 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1,
}

-- pokeemerald/src/time_events.c:54
function FieldRse.updateShoalTideFlag(sess)
  sess = sess or Rse.session()
  if FieldRse.lastUsedWarpOutdoors(sess) ~= true then return false end
  local lt = localDays(sess)
  Rse.setFlag("FLAG_SYS_SHOAL_TIDE", FieldRse.SHOAL_TIDE[(tonumber(lt.hours) or 0) % 24] == 1, sess)
  return true
end

-- pokeemerald/src/clock.c:44
function FieldRse.installTimeHooks()
  local TimeEvents = require("src.core.game3.time_events")
  local perDay = TimeEvents.handlers()
  if perDay.UpdateMirageRnd == nil then
    TimeEvents.onDay("UpdateMirageRnd", function(sess, days) FieldRse.updateMirageRnd(sess, days) end)
  end
  if perDay.UpdateBirchState == nil then
    -- pokeemerald/src/time_events.c:113
    TimeEvents.onDay("UpdateBirchState", function(sess, days)
      Rse.setVar("VAR_BIRCH_STATE", (Rse.var("VAR_BIRCH_STATE", sess) + (tonumber(days) or 0)) % 7, sess)
    end)
  end
  if perDay.SetShoalItemFlag == nil then
    -- pokeemerald/src/field_specials.c:1418
    TimeEvents.onDay("SetShoalItemFlag", function(sess) Rse.setFlag("FLAG_SYS_SHOAL_ITEM", true, sess) end)
  end
end

-- pokeemerald/src/field_specials.c:2254
FieldRse.SCROLL_MULTI = {
  [1] = { maxShowed = 5, count = 8, left = 1, top = 1, width = 9, height = 10 },
  [2] = { maxShowed = 6, count = 12, left = 1, top = 1, width = 7, height = 12 },
  [3] = { maxShowed = 6, count = 11, left = 14, top = 1, width = 15, height = 12 },
  [4] = { maxShowed = 6, count = 6, left = 14, top = 1, width = 15, height = 12 },
  [5] = { maxShowed = 6, count = 7, left = 14, top = 1, width = 15, height = 12 },
  [6] = { maxShowed = 6, count = 10, left = 14, top = 1, width = 15, height = 12 },
  [7] = { maxShowed = 6, count = 12, left = 15, top = 1, width = 14, height = 12 },
  [8] = { maxShowed = 6, count = 10, left = 17, top = 1, width = 11, height = 12 },
  [9] = { maxShowed = 6, count = 11, left = 15, top = 1, width = 14, height = 12 },
  [10] = { maxShowed = 6, count = 11, left = 15, top = 1, width = 14, height = 12 },
  [11] = { maxShowed = 6, count = 7, left = 19, top = 1, width = 10, height = 12 },
  [12] = { maxShowed = 6, count = 7, left = 17, top = 1, width = 12, height = 12 },
}
-- pokeemerald/include/constants/script_menu.h:8
local MULTI_B_PRESSED = 127

function FieldRse.scrollMultichoiceLabels(id)
  local RomText = require("src.core.game3.rom_text")
  local layout = FieldRse.SCROLL_MULTI[id]
  if not layout then return nil end
  local out = {}
  for i = 0, layout.count - 1 do
    local key = RomText.key("sScrollableMultichoiceOptions", id, i)
    if not RomText.has(key) then return nil end
    out[i + 1] = RomText.plain(key)
  end
  return out
end

local STORY = {
  -- pokeemerald/src/field_specials.c:620
  MauvilleGymPressSwitch = function(ctx)
    Story.mauvillePressSwitch(Rse.specialVar(ctx, VAR_0x8004), metatileAt, setMetatile, C())
    return false
  end,
  -- pokeemerald/src/field_specials.c:633
  MauvilleGymSetDefaultBarriers = function()
    Story.mauvilleSetDefaultBarriers(metatileAt, setMetatile, C())
    return false
  end,
  -- pokeemerald/src/field_specials.c:727
  MauvilleGymDeactivatePuzzle = function()
    Story.mauvilleDeactivatePuzzle(metatileAt, setMetatile, C())
    return false
  end,
  -- pokeemerald/src/field_specials.c:794
  PetalburgGymSlideOpenRoomDoors = function(ctx)
    local Natives = require("src.core.game3.scripting.natives")
    local Task = require("src.core.game3.task")
    local room, K = Rse.specialVar(ctx, VAR_0x8004), C()
    local done = false
    playSe("SE_UNLOCK")
    local step = Story.slideDoorsTask(room, setMetatile, K, drawWholeMapView)
    if step() then done = true else Task.spawn(function()
      if step() then done = true return true end
      return false
    end) end
    Natives.awaitState(ctx, function() return done end)
    return false
  end,
  -- pokeemerald/src/field_specials.c:885
  PetalburgGymUnlockRoomDoors = function(ctx)
    Story.petalburgSetDoorMetatiles(Rse.specialVar(ctx, VAR_0x8004), Story.slidingDoorMetatile(C(), 4), setMetatile)
    drawWholeMapView()
    return false
  end,
  -- pokeemerald/src/field_specials.c:1328
  FoundAbandonedShipRoom1Key = function(ctx)
    local id = Rse.flagId("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_1_KEY")
    Rse.setSpecialVar(ctx, VAR_0x8004, id)
    return boolRet(Rse.flag("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_1_KEY"))
  end,
  -- pokeemerald/src/field_specials.c:1339
  FoundAbandonedShipRoom2Key = function(ctx)
    local id = Rse.flagId("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_2_KEY")
    Rse.setSpecialVar(ctx, VAR_0x8004, id)
    return boolRet(Rse.flag("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_2_KEY"))
  end,
  -- pokeemerald/src/field_specials.c:1350
  FoundAbandonedShipRoom4Key = function(ctx)
    local id = Rse.flagId("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_4_KEY")
    Rse.setSpecialVar(ctx, VAR_0x8004, id)
    return boolRet(Rse.flag("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_4_KEY"))
  end,
  -- pokeemerald/src/field_specials.c:1361
  FoundAbandonedShipRoom6Key = function(ctx)
    local id = Rse.flagId("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_6_KEY")
    Rse.setSpecialVar(ctx, VAR_0x8004, id)
    return boolRet(Rse.flag("FLAG_HIDDEN_ITEM_ABANDONED_SHIP_RM_6_KEY"))
  end,
  -- pokeemerald/src/field_specials.c:1372
  LeadMonHasEffortRibbon = function()
    local mon = leadMon()
    return boolRet(mon ~= nil and require("src.core.game3.rse.ribbons").get(mon, "effort") == 1)
  end,
  -- pokeemerald/src/field_specials.c:1377
  GiveLeadMonEffortRibbon = function(ctx, adapters)
    local sess = Rse.session()
    if type(sess.gameStats) ~= "table" then sess.gameStats = {} end
    sess.gameStats[GAME_STAT_RECEIVED_RIBBONS] = math.min(0xFFFFFF,
      math.floor(tonumber(sess.gameStats[GAME_STAT_RECEIVED_RIBBONS]) or 0) + 1)
    Rse.setFlag("FLAG_SYS_RIBBON_GET", true, sess)
    local mon = leadMon(sess)
    if mon then
      local Ribbons = require("src.core.game3.rse.ribbons")
      Ribbons.set(mon, "effort", 1)
      if Ribbons.count(mon) > NUM_CUTIES_RIBBONS then
        Rse.call("tv", "tryPutSpotTheCutiesOnAir", "GiveLeadMonEffortRibbon", adapters and adapters.log, mon, "effort")
      end
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:1390
  Special_AreLeadMonEVsMaxedOut = function()
    local Pokemon = require("src.core.game3.pokemon")
    local mon = leadMon()
    return boolRet(mon ~= nil and (tonumber(Pokemon.evCount(mon)) or 0) >= MAX_TOTAL_EVS)
  end,
  -- pokeemerald/src/field_specials.c:1174
  SetTrickHouseNuggetFlag = function(ctx)
    Rse.setSpecialVar(ctx, VAR_0x8004, Rse.flagId("FLAG_HIDDEN_ITEM_TRICK_HOUSE_NUGGET"))
    Rse.setFlag("FLAG_HIDDEN_ITEM_TRICK_HOUSE_NUGGET", true)
    return false
  end,
  -- pokeemerald/src/field_specials.c:1182
  ResetTrickHouseNuggetFlag = function(ctx)
    Rse.setSpecialVar(ctx, VAR_0x8004, Rse.flagId("FLAG_HIDDEN_ITEM_TRICK_HOUSE_NUGGET"))
    Rse.setFlag("FLAG_HIDDEN_ITEM_TRICK_HOUSE_NUGGET", false)
    return false
  end,
  -- pokeemerald/src/field_specials.c:1514
  FoundBlackGlasses = flagSetting("FLAG_HIDDEN_ITEM_ROUTE_116_BLACK_GLASSES"),
  -- pokeemerald/src/field_specials.c:1519
  SetRoute119Weather = function()
    if FieldRse.lastUsedWarpOutdoors() ~= true then
      require("src.core.game3.weather").setSaved(C():require("weather", "WEATHER_ROUTE119_CYCLE"))
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:1525
  SetRoute123Weather = function()
    if FieldRse.lastUsedWarpOutdoors() ~= true then
      require("src.core.game3.weather").setSaved(C():require("weather", "WEATHER_ROUTE123_CYCLE"))
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:895
  StorePlayerCoordsInVars = function(ctx)
    local P = package.loaded["src.core.game3.player"]
    local sess = Rse.session()
    Rse.setSpecialVar(ctx, VAR_0x8004, tonumber(P and P.cellX) or tonumber(sess and sess.x) or 0)
    Rse.setSpecialVar(ctx, VAR_0x8005, tonumber(P and P.cellY) or tonumber(sess and sess.y) or 0)
    return false
  end,
  -- pokeemerald/src/field_specials.c:901
  GetPlayerTrainerIdOnesDigit = function()
    local sess = Rse.session()
    return false, (math.floor(tonumber(sess and sess.trainerId) or 0) % 0x10000) % 10
  end,
  -- pokeemerald/src/field_specials.c:927
  CableCarWarp = function(ctx, adapters)
    require("src.core.game3.rse.cable_car").setWarp(ctx, adapters)
    return false
  end,
  -- pokeemerald/src/cable_car.c:236
  CableCar = function(ctx, adapters)
    return require("src.core.game3.rse.cable_car").start(ctx, adapters)
  end,
  -- pokeemerald/src/field_specials.c:940
  GetWeekCount = function()
    return false, Story.weekCount(localDays().days)
  end,
  -- pokeemerald/src/field_specials.c:949
  GetLeadMonFriendshipScore = function()
    local mon = leadMon()
    local f = tonumber(mon and (mon.friendship or mon.happiness)) or 0
    local score = 0
    if f == 255 then score = 6 elseif f >= 200 then score = 5 elseif f >= 150 then score = 4
    elseif f >= 100 then score = 3 elseif f >= 50 then score = 2 elseif f >= 1 then score = 1 end
    return false, score
  end,
  -- pokeemerald/src/field_specials.c:1555
  GetDaysUntilPacifidlogTMAvailable = function()
    return false, Story.daysUntilPacifidlogTM(localDays().days, Rse.var("VAR_PACIFIDLOG_TM_RECEIVED_DAY"))
  end,
  -- pokeemerald/src/field_specials.c:1566
  SetPacifidlogTMReceivedDay = function()
    local days = localDays().days
    Rse.setVar("VAR_PACIFIDLOG_TM_RECEIVED_DAY", days % 0x10000)
    return false, days % 0x10000
  end,
  -- pokeemerald/src/field_specials.c:2254
  ShowScrollableMultichoice = function(ctx, adapters)
    local id = Rse.specialVar(ctx, VAR_0x8004)
    local layout = FieldRse.SCROLL_MULTI[id]
    local labels = layout and FieldRse.scrollMultichoiceLabels(id)
    if not labels then
      if layout then Rse.missing("scrollMultichoice", "sScrollableMultichoiceOptions text", adapters and adapters.log) end
      Rse.setSpecialVar(ctx, varId("VAR_RESULT"), MULTI_B_PRESSED)
      return false
    end
    local ListMenu = require("src.core.game3.scripting.natives_listmenu")
    local copy = { keepOpen = false }
    for k, v in pairs(layout) do copy[k] = v end
    copy.exchangeMenuId = id
    return ListMenu.presentItems(ctx, "scroll_multichoice", labels, copy, function(index)
      Rse.setSpecialVar(ctx, varId("VAR_RESULT"), index)
    end)
  end,
  -- pokeemerald/src/field_specials.c:1969
  BufferVarsForIVRater = function(ctx)
    local Rng = require("src.core.game3.rng")
    local mon = partyOf()[Rse.specialVar(ctx, VAR_0x8004) + 1]
    local total, best, val = Story.ivRater(mon and mon.ivs, Rng.Random)
    Rse.setSpecialVar(ctx, VAR_0x8005, total)
    Rse.setSpecialVar(ctx, VAR_0x8006, best)
    Rse.setSpecialVar(ctx, VAR_0x8007, val)
    return false
  end,
  -- pokeemerald/src/field_specials.c:1437
  IsStarterInParty = function()
    local StarterChoose = require("src.ui.game3.rse.starter_choose")
    local starter = StarterChoose.species(nil, Rse.var("VAR_STARTER_MON"))
    local p = partyOf()
    for i = 1, partyCount() do
      if speciesOrEgg(p[i]) == starter then return boolRet(true) end
    end
    return boolRet(false)
  end,
  -- pokeemerald/src/field_specials.c:1423
  LoadWallyZigzagoon = function()
    FieldRse.loadWallyZigzagoon()
    return false
  end,
  -- pokeemerald/src/field_specials.c:1398
  TryUpdateRusturfTunnelState = function()
    local sess = Rse.session()
    if not Rse.flag("FLAG_RUSTURF_TUNNEL_OPENED") and sess and sess.map == "EM_RUSTURF_TUNNEL" then
      if Rse.flag("FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1") then
        Rse.setVar("VAR_RUSTURF_TUNNEL_STATE", 4)
        return boolRet(true)
      elseif Rse.flag("FLAG_HIDE_RUSTURF_TUNNEL_ROCK_2") then
        Rse.setVar("VAR_RUSTURF_TUNNEL_STATE", 5)
        return boolRet(true)
      end
    end
    return boolRet(false)
  end,
  -- pokeemerald/src/field_specials.c:1230
  IsGrassTypeInParty = function(ctx)
    local Pokemon = require("src.core.game3.pokemon")
    local grass = TYPE_GRASS
    for _, mon in ipairs(partyOf()) do
      if speciesOf(mon) ~= 0 and not isEgg(mon) then
        local t = Pokemon.types(speciesOf(mon)) or {}
        if t[1] == grass or t[2] == grass then
          Rse.setSpecialVar(ctx, varId("VAR_RESULT"), 1)
          return false
        end
      end
    end
    Rse.setSpecialVar(ctx, varId("VAR_RESULT"), 0)
    return false
  end,
  -- pokeemerald/src/field_specials.c:1544
  ScriptGetPartyMonSpecies = function(ctx)
    return false, speciesOrEgg(partyOf()[Rse.specialVar(ctx, VAR_0x8004) + 1])
  end,
  -- pokeemerald/src/field_specials.c:1455
  IsPokerusInParty = function()
    local Pokemon = require("src.core.game3.pokemon")
    return boolRet(Pokemon.checkPartyPokerus(partyOf(), 0x3F) ~= 0)
  end,
  -- pokeemerald/src/field_specials.c:1572
  MonOTNameNotPlayer = function(ctx, adapters)
    local sess = Rse.session()
    local mon = partyOf(sess)[Rse.specialVar(ctx, VAR_0x8004) + 1]
    if mon and (tonumber(mon.language) or GAME_LANGUAGE) ~= GAME_LANGUAGE then return boolRet(true) end
    local ot = tostring(mon and (mon.otName or mon.ot) or "")
    stringVar(ctx, adapters, 1, ot)
    return boolRet(ot ~= tostring(sess and (sess.name or sess.playerName) or ""))
  end,
  -- pokeemerald/src/field_specials.c:3881
  ResetHealLocationFromDewford = function()
    local sess = Rse.session()
    local HealLocations = require("src.core.game3.heal_locations")
    local dewford = HealLocations.get(HEAL_LOCATION_DEWFORD_TOWN)
    if sess and dewford and sess.healMap == dewford.map then
      field().setRespawn(HEAL_LOCATION_PETALBURG_CITY)
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:3630
  ShouldDistributeEonTicket = function()
    return boolRet(Rse.var("VAR_DISTRIBUTE_EON_TICKET") ~= 0)
  end,
  -- pokeemerald/src/time_events.c:42
  IsMirageIslandPresent = function()
    return boolRet(FieldRse.isMirageIslandPresent())
  end,
  -- pokeemerald/src/time_events.c:54
  UpdateShoalTideFlag = function()
    FieldRse.updateShoalTideFlag()
    return false
  end,
  -- pokeemerald/src/time_events.c:103
  WaitWeather = function(ctx)
    local Natives = require("src.core.game3.scripting.natives")
    local Weather = require("src.core.game3.weather")
    local E = Weather.rseEngine and Weather.rseEngine()
    Natives.awaitState(ctx, function() return not E or E.isWeatherChangeComplete() end)
    return false
  end,
  -- pokeemerald/src/time_events.c:108
  InitBirchState = function()
    Rse.setVar("VAR_BIRCH_STATE", 0)
    return false
  end,
  -- pokeemerald/src/field_screen_effect.c:1253
  Script_FadeOutMapMusic = function(ctx)
    local Natives = require("src.core.game3.scripting.natives")
    local Audio = require("src.core.game3.audio")
    Audio.fadeOutBgm(4)
    local frames = 0
    Natives.awaitState(ctx, function()
      frames = frames + 1
      return Audio._fadeOut == nil or frames > 64
    end)
    return false
  end,
  -- pokeemerald/src/field_specials.c:3802
  LoopWingFlapSE = function(ctx)
    local Task = require("src.core.game3.task")
    local total, every = Rse.specialVar(ctx, VAR_0x8004), Rse.specialVar(ctx, VAR_0x8005)
    local count, delay = 0, 0
    playSe("SE_M_WING_ATTACK")
    Task.spawn(function()
      delay = delay + 1
      if delay == every then
        count = count + 1
        delay = 0
        playSe("SE_M_WING_ATTACK")
      end
      return count == total - 1
    end)
    return false
  end,
  -- pokeemerald/src/load_save.c:160
  SavePlayerParty = function()
    FieldRse.savePlayerParty()
    return false
  end,
  -- pokeemerald/src/load_save.c:170
  LoadPlayerParty = function()
    FieldRse.loadPlayerParty()
    return false
  end,
  -- pokeemerald/src/egg_hatch.c:941 CountPartyAliveNonEggMons
  CountPartyAliveNonEggMons = function()
    local n = 0
    for _, mon in ipairs(partyOf()) do
      if speciesOf(mon) ~= 0 and not isEgg(mon) and (tonumber(mon.hp) or 1) ~= 0 then n = n + 1 end
    end
    return false, n
  end,
  -- pokeemerald/src/field_specials.c:890
  ShowFieldMessageStringVar4 = delegate("natives_events", "ShowFieldMessageStringVar4"),
  -- pokeemerald/src/wild_encounter.c:668
  RockSmashWildEncounter = delegate("natives_events", "RockSmashWildEncounter"),
  -- pokeemerald/src/field_specials.c:935
  SetHiddenItemFlag = delegate("natives_queries", "SetHiddenItemFlag"),
  -- pokeemerald/src/pokemon.c:4481
  CalculatePlayerPartyCount = delegate("natives_queries", "CalculatePlayerPartyCount"),
  -- pokeemerald/src/pokemon_storage_system.c:1424
  CountPartyNonEggMons = delegate("natives_queries", "CountPartyNonEggMons"),
  -- pokeemerald/src/pokemon_storage_system.c:1458
  CountPartyAliveNonEggMons_IgnoreVar0x8004Slot = delegate("natives_queries", "CountPartyAliveNonEggMons_IgnoreVar0x8004Slot"),
  -- pokeemerald/src/daycare.c:960
  GetSelectedMonNicknameAndSpecies = delegate("natives_queries", "GetSelectedMonNicknameAndSpecies"),
  -- pokeemerald/src/money.c:123
  IsEnoughForCostInVar0x8005 = delegate("natives_queries", "IsEnoughForCostInVar0x8005"),
  -- pokeemerald/src/money.c:128
  SubtractMoneyFromVar0x8005 = delegate("natives_queries", "SubtractMoneyFromVar0x8005"),
  -- pokeemerald/src/field_player_avatar.c:1182
  GetPlayerFacingDirection = delegate("natives_queries", "GetPlayerFacingDirection"),
  -- pokeemerald/src/field_specials.c:1649
  IsBadEggInParty = delegate("natives_queries", "IsBadEggInParty"),
  -- pokeemerald/src/field_specials.c:1638
  BufferTMHMMoveName = delegate("natives_queries", "BufferTMHMMoveName"),
  -- pokeemerald/src/field_specials.c:1450
  ScriptCheckFreePokemonStorageSpace = delegate("natives_queries", "IsThereRoomInAnyBoxForMorePokemon"),
  -- pokeemerald/src/dodrio_berry_picking.c:2911
  IsDodrioInParty = delegate("natives_queries", "IsDodrioInParty"),
  -- pokeemerald/src/item.c:158
  HasAtLeastOneBerry = delegate("natives_queries", "HasAtLeastOneBerry"),
  -- pokeemerald/src/field_specials.c:3405
  ShouldShowBoxWasFullMessage = delegate("natives_queries", "ShouldShowBoxWasFullMessage"),
  -- pokeemerald/src/pokemon_jump.c:2687
  IsPokemonJumpSpeciesInParty = delegate("natives_wireless", "IsPokemonJumpSpeciesInParty"),
  -- pokeemerald/src/party_menu.c:5818
  ChooseMonForWirelessMinigame = delegate("natives_wireless", "ChooseMonForWirelessMinigame"),
  -- pokeemerald/src/pokemon_jump.c:4487
  ShowPokemonJumpRecords = delegate("natives_wireless", "ShowPokemonJumpRecords"),
  -- pokeemerald/src/dodrio_berry_picking.c:2929
  ShowDodrioBerryPickingRecords = delegate("natives_wireless", "ShowDodrioBerryPickingRecords"),
  -- pokeemerald/src/berry_crush.c:3189
  ShowBerryCrushRankings = delegate("natives_wireless", "ShowBerryCrushRankings"),
  -- pokeemerald/src/mauville_old_man.c:746
  SetMauvilleOldManObjEventGfx = function()
    local C = require("src.core.game3.constants").active(Rse.session())
    Rse.setVar("VAR_OBJ_GFX_ID_0", C:require("event_objects", "OBJ_EVENT_GFX_BARD"))
    return false
  end,
  -- pokeemerald/src/field_specials.c:2045
  PlayerNotAtTrainerHillEntrance = function()
    local sess = Rse.session()
    return boolRet(not (sess and sess.map == "EM_TRAINER_HILL_ENTRANCE"))
  end,
  -- pokeemerald/src/pokedex.c:4387
  HasAllHoennMons = function()
    return boolRet(FieldRse.hasAllHoennMons(Rse.session()))
  end,
  CompletedHoennPokedex = function()
    return boolRet(FieldRse.hasAllHoennMons(Rse.session()))
  end,
  -- pokeemerald/src/trainer_card.c:663
  CountPlayerTrainerStars = function()
    return false, FieldRse.countTrainerStars(Rse.session())
  end,
  -- pokeemerald/src/union_room.c:3294
  InitUnionRoom = function()
    return false
  end,
  -- pokeemerald/src/union_room.c:3379
  BufferUnionRoomPlayerName = function()
    return false, 0
  end,
  -- pokeemerald/src/save_location.c:125
  SetUnlockedPokedexFlags = function()
    local sess = Rse.session()
    if sess then
      sess.gcnLinkFlags = require("bit").bor(tonumber(sess.gcnLinkFlags) or 0, 0x803F)
    end
    return false
  end,
  -- pokeemerald/src/battle_setup.c:1858
  ShouldTryGetTrainerScript = function()
    local TS = require("src.core.game3.trainer_sight")
    if (tonumber(TS.retScriptCount) or 0) > 1 then
      TS.retScriptCount = 0
      TS.checkTrainerB = true
      return false, 1
    end
    TS.checkTrainerB = false
    return false, 0
  end,
  -- pokeemerald/src/trainer_see.c:794
  PlayerFaceTrainerAfterBattle = function()
    local TS = package.loaded["src.core.game3.trainer_sight"]
    local eo = TS and TS._approached
    if eo and eo.facing then
      local P = require("src.core.game3.player")
      local OPP = { up = "down", down = "up", left = "right", right = "left" }
      P.facing = OPP[eo.facing] or P.facing
    end
    return false
  end,
}

-- pokeemerald/include/constants/field_specials.h:68
local FANCLUB_GOT_FIRST_FANS = 7
local FANCLUB_MEMBER1 = 8
local NUM_TRAINER_FAN_CLUB_MEMBERS = 8
local FANCLUB_COUNTER = 0x7F

local function fanBits() return tonumber(Rse.var("VAR_FANCLUB_FAN_COUNTER")) or 0 end
local function setFanBits(v) Rse.setVar("VAR_FANCLUB_FAN_COUNTER", require("bit").band(v, 0xFFFF)) end
local function fanFlag(f) return require("bit").band(require("bit").rshift(fanBits(), f), 1) == 1 end
local function setFanFlag(f) setFanBits(require("bit").bor(fanBits(), require("bit").lshift(1, f))) end
local function flipFanFlag(f) setFanBits(require("bit").bxor(fanBits(), require("bit").lshift(1, f))) end

local function playTimeHours()
  local sess = Rse.session()
  local pt = sess and (sess.playtime or sess.playTime)
  return tonumber(type(pt) == "table" and pt.hours or sess and sess.playTimeHours) or 0
end

-- pokeemerald/src/field_specials.c:4116
function FieldRse.numFans()
  local n = 0
  for i = 0, NUM_TRAINER_FAN_CLUB_MEMBERS - 1 do
    if fanFlag(i + FANCLUB_MEMBER1) then n = n + 1 end
  end
  return n
end

local function fanRandom()
  return require("src.core.game3.rng").Random()
end

-- pokeemerald/src/field_specials.c:4041
local GAIN_ORDER = { 8, 9, 10, 11, 12, 13, 14, 15 }
function FieldRse.playerGainRandomTrainerFan()
  local idx = 0
  for i = 0, #GAIN_ORDER - 1 do
    if not fanFlag(GAIN_ORDER[i + 1]) then
      idx = i
      if require("bit").band(fanRandom(), 1) == 1 then
        setFanFlag(GAIN_ORDER[idx + 1])
        return idx
      end
    end
  end
  setFanFlag(GAIN_ORDER[idx + 1])
  return idx
end

-- pokeemerald/src/field_specials.c:4077
local LOSE_ORDER = { 8, 13, 14, 11, 10, 12, 15, 9 }
function FieldRse.playerLoseRandomTrainerFan()
  if FieldRse.numFans() == 1 then return 0 end
  local idx = 0
  for i = 0, #LOSE_ORDER - 1 do
    if fanFlag(LOSE_ORDER[i + 1]) then
      idx = i
      if require("bit").band(fanRandom(), 1) == 1 then
        flipFanFlag(LOSE_ORDER[idx + 1])
        return idx
      end
    end
  end
  if fanFlag(LOSE_ORDER[idx + 1]) then flipFanFlag(LOSE_ORDER[idx + 1]) end
  return idx
end

-- pokeemerald/src/field_specials.c:4131
function FieldRse.tryLoseFansFromPlayTime()
  local hours = playTimeHours()
  if hours >= 999 then return end
  local i = 0
  while true do
    if FieldRse.numFans() < 5 then
      Rse.setVar("VAR_FANCLUB_LOSE_FAN_TIMER", hours)
      break
    elseif i == NUM_TRAINER_FAN_CLUB_MEMBERS then
      break
    elseif hours - (tonumber(Rse.var("VAR_FANCLUB_LOSE_FAN_TIMER")) or 0) < 12 then
      return
    end
    FieldRse.playerLoseRandomTrainerFan()
    Rse.setVar("VAR_FANCLUB_LOSE_FAN_TIMER", (tonumber(Rse.var("VAR_FANCLUB_LOSE_FAN_TIMER")) or 0) + 12)
    i = i + 1
  end
end

-- pokeemerald/src/field_specials.c:4003
local COUNTER_INCREMENTS = { [0] = 2, [1] = 1, [2] = 2, [3] = 1 }
function FieldRse.tryGainNewFanFromCounter(incrementId)
  local bit = require("bit")
  if (tonumber(Rse.var("VAR_LILYCOVE_FAN_CLUB_STATE")) or 0) == 2 then
    local inc = COUNTER_INCREMENTS[tonumber(incrementId) or 0] or 0
    local counter = bit.band(fanBits(), FANCLUB_COUNTER)
    if counter + inc > 19 then
      if FieldRse.numFans() < 3 then
        FieldRse.playerGainRandomTrainerFan()
        setFanBits(bit.band(fanBits(), bit.bnot(FANCLUB_COUNTER)))
      else
        setFanBits(bit.bor(bit.band(fanBits(), bit.bnot(FANCLUB_COUNTER)), 20))
      end
    else
      setFanBits(fanBits() + inc)
    end
  end
  return bit.band(fanBits(), FANCLUB_COUNTER)
end

-- pokeemerald/src/field_specials.c:4244
function FieldRse.updateTrainerFansAfterLinkBattle(won)
  if (tonumber(Rse.var("VAR_LILYCOVE_FAN_CLUB_STATE")) or 0) ~= 2 then return end
  if fanFlag(FANCLUB_GOT_FIRST_FANS) then
    FieldRse.tryLoseFansFromPlayTime()
    Rse.setVar("VAR_FANCLUB_LOSE_FAN_TIMER", playTimeHours())
  end
  if won then
    FieldRse.playerGainRandomTrainerFan()
  else
    FieldRse.playerLoseRandomTrainerFan()
  end
end

-- pokeemerald/src/field_specials.c:4170
local FAN_NAME_SOURCES = {
  [9] = { 0, 3 }, [10] = { 0, 1 }, [11] = { 1, 0 }, [12] = { 0, 4 }, [13] = { 1, 5 },
}
local NPC_FAN_NAMES = { [0] = "gText_Wallace", "gText_Steven", "gText_Brawly", "gText_Winona", "gText_Phoebe", "gText_Glacia" }

local FAN_CLUB = {
  -- pokeemerald/src/field_specials.c:3984
  UpdateTrainerFanClubGameClear = function()
    if not fanFlag(FANCLUB_GOT_FIRST_FANS) then
      setFanFlag(FANCLUB_GOT_FIRST_FANS)
      -- pokeemerald/src/field_specials.c:4163
      setFanFlag(FANCLUB_MEMBER1 + 5)
      setFanFlag(FANCLUB_MEMBER1)
      setFanFlag(FANCLUB_MEMBER1 + 2)
      Rse.setVar("VAR_FANCLUB_LOSE_FAN_TIMER", playTimeHours())
      for _, f in ipairs({ "FLAG_HIDE_FANCLUB_OLD_LADY", "FLAG_HIDE_FANCLUB_BOY", "FLAG_HIDE_FANCLUB_LITTLE_BOY",
          "FLAG_HIDE_FANCLUB_LADY", "FLAG_HIDE_LILYCOVE_FAN_CLUB_INTERVIEWER" }) do
        Rse.setFlag(f, false)
      end
      Rse.setVar("VAR_LILYCOVE_FAN_CLUB_STATE", 1)
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:4267
  Script_TryGainNewFanFromCounter = function(ctx)
    return false, FieldRse.tryGainNewFanFromCounter(Rse.specialVar(ctx, VAR_0x8004))
  end,
  -- pokeemerald/src/field_specials.c:4116
  GetNumFansOfPlayerInTrainerFanClub = function()
    return false, FieldRse.numFans()
  end,
  -- pokeemerald/src/field_specials.c:4158
  IsFanClubMemberFanOfPlayer = function(ctx)
    return boolRet(fanFlag(tonumber(Rse.specialVar(ctx, VAR_0x8004)) or 0))
  end,
  -- pokeemerald/src/field_specials.c:4131
  TryLoseFansFromPlayTime = function()
    FieldRse.tryLoseFansFromPlayTime()
    return false
  end,
  -- pokeemerald/src/field_specials.c:3975
  TryLoseFansFromPlayTimeAfterLinkBattle = function()
    if fanFlag(FANCLUB_GOT_FIRST_FANS) then
      FieldRse.tryLoseFansFromPlayTime()
      Rse.setVar("VAR_FANCLUB_LOSE_FAN_TIMER", playTimeHours())
    end
    return false
  end,
  -- pokeemerald/src/field_specials.c:4261
  SetPlayerGotFirstFans = function()
    setFanFlag(FANCLUB_GOT_FIRST_FANS)
    return false
  end,
  -- pokeemerald/src/field_specials.c:4170
  BufferFanClubTrainerName = function(ctx)
    local src = FAN_NAME_SOURCES[tonumber(Rse.specialVar(ctx, VAR_0x8004)) or 0] or { 0, 0 }
    local sess = Rse.session()
    local rec = type(sess and sess.linkBattleRecords) == "table" and sess.linkBattleRecords[src[1] + 1] or nil
    local name = type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" and rec.name:sub(1, 7) or nil
    -- pokeemerald/src/field_specials.c:4206
    if ctx and ctx.stringVars then ctx.stringVars[1] = name or Rse.text(NPC_FAN_NAMES[src[2]] or "gText_Wallace") end
    return false
  end,
  -- pokeemerald/src/save_location.c:136
  SetChampionSaveWarp = function()
    local sess = Rse.session()
    if sess then
      -- pokeemerald/include/save_location.h:13
      sess.specialSaveWarpFlags = require("bit").bor(tonumber(sess.specialSaveWarpFlags) or 0, 0x80)
    end
    return false
  end,
  -- pokeemerald/src/birch_pc.c:7
  ScriptGetPokedexInfo = function(ctx)
    local sess = Rse.session()
    local Dex = require("src.core.game3.dex")
    local Pokemon = require("src.core.game3.pokemon")
    local dex = sess and sess.dex
    local national = Rse.specialVar(ctx, VAR_0x8004) ~= 0
    local seen, caught = 0, 0
    local id = require("src.core.game3.constants").versionOf(sess)
    if id == "ruby" or id == "sapphire" then
      seen, caught = require("src.core.game3.profiles.rs.pokedex").counts(sess, national)
    else for species = 1, 440 do
      local ok, nat = pcall(Pokemon.national, species)
      local counted
      if national then
        counted = ok and nat and nat >= 1 and nat <= 386
      else
        counted = Dex.regionalNumber(species) ~= nil
      end
      if counted and dex then
        if Dex.isSeen(dex, species) then seen = seen + 1 end
        if Dex.isCaught(dex, species) then caught = caught + 1 end
      end
    end end
    Rse.setSpecialVar(ctx, 0x8005, seen)
    Rse.setSpecialVar(ctx, 0x8006, caught)
    local okN, enabled = pcall(Dex.nationalEnabled, sess)
    return boolRet(okN and enabled == true)
  end,
  -- pokeemerald/src/birch_pc.c:85
  ShowPokedexRatingMessage = function(ctx, adapters)
    local text = FieldRse.pokedexRatingText(Rse.specialVar(ctx, VAR_0x8004))
    local body = require("src.core.game3.rom_text").box(text, ctx)
    if ctx then ctx.messageOpen = true end
    local openStay = adapters and (adapters.openMessageStay or adapters.openMessageAsync)
    if openStay then
      openStay(body, nil)
    elseif adapters and adapters.openMessage then
      adapters.openMessage(body)
    end
    return false
  end,
}

-- pokeemerald/src/birch_pc.c:24
function FieldRse.pokedexRatingText(count)
  count = tonumber(count) or 0
  if count < 200 then
    return "gBirchDexRatingText_LessThan" .. ((math.floor(count / 10) + 1) * 10)
  end
  local sess = Rse.session()
  local dex = sess and sess.dex
  local Dex = require("src.core.game3.dex")
  local Constants = require("src.core.game3.constants")
  local C = Constants.of(Constants.versionOf(sess))
  local jirachi = dex and Dex.isCaught(dex, C:require("species", "SPECIES_JIRACHI"))
  local deoxys = dex and Dex.isCaught(dex, C:require("species", "SPECIES_DEOXYS"))
  local hoennCount = Dex.regionalMax()
  if count == hoennCount - 2 then
    return (jirachi or deoxys) and "gBirchDexRatingText_LessThan200" or "gBirchDexRatingText_DexCompleted"
  end
  if count == hoennCount - 1 then
    return (jirachi and deoxys) and "gBirchDexRatingText_LessThan200" or "gBirchDexRatingText_DexCompleted"
  end
  if count == hoennCount then return "gBirchDexRatingText_DexCompleted" end
  return "gBirchDexRatingText_LessThan10"
end

for name, fn in pairs(FAN_CLUB) do FieldRse.BY_NAME[name] = fn end
for name, fn in pairs(STORY) do FieldRse.BY_NAME[name] = fn end
for name, fn in pairs(require("src.core.game3.bike.specials_rse").BY_NAME) do FieldRse.BY_NAME[name] = fn end

FieldRse.installTimeHooks()

return FieldRse
