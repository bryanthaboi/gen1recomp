-- callnative / special allowlist; unknown → safe-skip + log once.
-- Handlers mirror pret specials → host adapters (heal / PC), not map coords.

local Strings = require("src.core.Strings")
local Std = require("src.core.game3.scripting.stdscripts")
local Capabilities = require("src.core.game3.capabilities")
local Profile = require("src.core.game3.profile")

local Natives = {}

Natives._logged = {}

local function yield_host(ctx, adapters, startFn)
  local finished = false
  ctx.mode = "native"
  ctx.status = "waiting"
  ctx.nativePoll = function() return finished end
  startFn(function()
    finished = true
  end)
  return not finished -- true = caller should yield
end

Natives.yieldHost = yield_host

-- pokefirered/src/script.c:366
function Natives.awaitState(ctx, task)
  if type(task) ~= "function" then return end
  ctx.stateWait = task
end

local function vsSeeker()
  return require("src.core.game3.vs_seeker")
end

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function lastTalked(ctx)
  return flagsMod().getVar(nil, ctx, 0x800F)
end

local function setResult(ctx, v)
  flagsMod().setVar(nil, ctx, 0x800D, v)
end

local function getSpecialVar(ctx, id)
  local v = tonumber(flagsMod().getVar(nil, ctx, id)) or 0
  if v == 0 and ctx and type(ctx.getVar) == "function" then
    v = tonumber(ctx:getVar(id)) or 0
  end
  return v
end

local function setSpecialVar(ctx, id, value)
  -- src/field_specials.c:2075-2078, include/constants/vars.h:75
  local Space = package.loaded["src.core.game3.scripting.space"]
  flagsMod().setVar(Space and Space.store or nil, ctx, id, value)
  if ctx and type(ctx.setVar) == "function" then ctx:setVar(id, value) end
end

local SLOT_CANCEL = 7 -- pokefirered/src/party_menu.c:87

local function partyOf()
  local rt = package.loaded["src.core.game3.runtime"]
  local session = rt and rt.getSession and rt.getSession()
  return session and session.party, session
end

local function chosenMon(ctx)
  local party = partyOf()
  return party and party[getSpecialVar(ctx, 0x8004) + 1]
end

-- pokefirered/src/field_specials.c:1631
local function boxedMon()
  local _, session = partyOf()
  if not session then return nil end
  local okS, Storage = pcall(require, "src.core.game3.storage")
  if not (okS and type(Storage) == "table" and Storage.getBoxMon) then return nil end
  return Storage.getBoxMon(Storage.ensure(session),
    (tonumber(session.monBoxId) or 0) + 1, (tonumber(session.monBoxPos) or 0) + 1)
end

-- GetMonData(MON_DATA_NICKNAME) is gText_EggNickname for an egg
-- (pokefirered/src/pokemon.c:3020)
local function ensurePokemonNames(Pokemon)
  if Pokemon._names then return end
  local okI, errI = pcall(Pokemon.install, nil)
  if not okI and not Pokemon._installWarned then
    Pokemon._installWarned = true
    print("[game3/pokemon] install failed: " .. tostring(errI))
  end
end

local function nicknameOf(mon)
  if not mon then return "" end
  local Pokemon = require("src.core.game3.pokemon")
  if Pokemon.isEgg(mon) then return require("src.core.game3.rom_text").plain("gText_EggNickname") end
  if mon.nickname and mon.nickname ~= "" then return tostring(mon.nickname) end
  ensurePokemonNames(Pokemon)
  return (Pokemon.name and Pokemon.name(mon.species or mon.speciesId)) or ""
end

local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

-- pokefirered/src/party_menu_specials.c:38, pokefirered/src/party_menu.c:6317
local function takeScreenForPartyMenu()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if not (okF and Fade and Fade.begin and Fade.MODE) then return function() end end
  local covered = not (Fade.isActive and Fade.isActive()) and (tonumber(Fade.t) or 0) >= 16
  -- pokefirered/src/party_menu.c:6329 FadeInFromBlack
  if not (covered and Fade.mode == Fade.MODE.TO_BLACK) then return function() end end
  Fade.clear()
  return function()
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  end
end

-- pokefirered/src/party_menu_specials.c:14
function Natives.choosePartyMon(ctx, adapters, menuType)
  local party, session = partyOf()
  local function resolveTo(slot0)
    setSpecialVar(ctx, 0x8004, slot0)
  end
  if adapters and adapters.chooseParty then
    local restore = takeScreenForPartyMenu()
    return yield_host(ctx, adapters, function(done)
      adapters.chooseParty({ menuType = menuType }, function(slot0)
        resolveTo(tonumber(slot0) or SLOT_CANCEL)
        restore()
        done()
      end)
    end)
  end
  local okUi, PartyMenu = pcall(require, "src.ui.game3.party_menu")
  if not (okUi and PartyMenu and PartyMenu.show and party and party[1]) then
    resolveTo(SLOT_CANCEL)
    return false
  end
  local restore = takeScreenForPartyMenu()
  local picked, settled = nil, false
  local function settle()
    if settled then return end
    settled = true
    -- pokefirered/src/party_menu.c:1252
    resolveTo(picked or SLOT_CANCEL)
  end
  local yielded = yield_host(ctx, adapters, function(done)
    PartyMenu.show(party, nil, {
      mode = "choose",
      session = session,
      onSelect = function(slot)
        picked = slot and ((tonumber(slot) or 1) - 1) or SLOT_CANCEL
      end,
      onClose = function()
        restore()
        done()
      end,
    })
  end)
  if not yielded then
    settle()
    return false
  end
  local closedPoll = ctx.nativePoll
  ctx.nativePoll = function()
    if not closedPoll() then return false end
    settle()
    return true
  end
  return true
end

local B_OUTCOME_WON = 1
local B_OUTCOME_LOST = 2
local B_OUTCOME_DREW = 3
local B_OUTCOME_RAN = 4
local B_OUTCOME_PLAYER_TELEPORTED = 5
local B_OUTCOME_MON_FLED = 6
local B_OUTCOME_CAUGHT = 7
local B_OUTCOME_NO_SAFARI_BALLS = 8
local B_OUTCOME_FORFEITED = 9
local B_OUTCOME_MON_TELEPORTED = 10

local function outcome_to_code(result)
  if type(result) == "number" then return result end
  if result == "win" or result == "won" then return B_OUTCOME_WON
  elseif result == "lose" or result == "lost" or result == "whiteout" or result == "blackout" then return B_OUTCOME_LOST
  elseif result == "draw" or result == "drew" then return B_OUTCOME_DREW
  elseif result == "run" or result == "ran" or result == "fled_player" then return B_OUTCOME_RAN
  elseif result == "teleport_player" or result == "player_teleported" then return B_OUTCOME_PLAYER_TELEPORTED
  elseif result == "fled" or result == "mon_fled" then return B_OUTCOME_MON_FLED
  elseif result == "caught" or result == "catch" then return B_OUTCOME_CAUGHT
  elseif result == "no_safari_balls" then return B_OUTCOME_NO_SAFARI_BALLS
  elseif result == "forfeited" then return B_OUTCOME_FORFEITED
  elseif result == "mon_teleported" then return B_OUTCOME_MON_TELEPORTED
  end
  return B_OUTCOME_WON
end

Natives.B_OUTCOME = {
  WON = B_OUTCOME_WON,
  LOST = B_OUTCOME_LOST,
  DREW = B_OUTCOME_DREW,
  RAN = B_OUTCOME_RAN,
  PLAYER_TELEPORTED = B_OUTCOME_PLAYER_TELEPORTED,
  MON_FLED = B_OUTCOME_MON_FLED,
  CAUGHT = B_OUTCOME_CAUGHT,
  NO_SAFARI_BALLS = B_OUTCOME_NO_SAFARI_BALLS,
  FORFEITED = B_OUTCOME_FORFEITED,
  MON_TELEPORTED = B_OUTCOME_MON_TELEPORTED,
}
Natives.outcome_to_code = outcome_to_code

-- pokefirered/src/field_specials.c:557
local VERMILION_TRASH_ADJACENT = {
  [1] = { 1, 5 },
  [2] = { 1, 5, -1 },
  [3] = { 1, 5, -1 },
  [4] = { 1, 5, -1 },
  [5] = { 5, -1 },
  [6] = { -5, 1, 5 },
  [7] = { -5, 1, 5, -1 },
  [8] = { -5, 1, 5, -1 },
  [9] = { -5, 1, 5, -1 },
  [10] = { -5, 5, -1 },
  [11] = { -5, 1 },
  [12] = { -5, 1, -1 },
  [13] = { -5, 1, -1 },
  [14] = { -5, 1, -1 },
  [15] = { -5, -1 },
}

-- pokefirered/src/field_specials.c:552 SetVermilionTrashCans
function Natives.setVermilionTrashCans(random)
  local first = (random() % 15) + 1
  local second = first
  local deltas = VERMILION_TRASH_ADJACENT[first]
  if deltas then
    second = (second + deltas[(random() % #deltas) + 1]) % 65536
  end
  if second > 15 then
    if first % 5 == 1 then
      second = first + 1
    elseif first % 5 == 0 then
      second = first - 1
    else
      second = first + 1
    end
  end
  return first, second
end

Natives.ALLOW = {
  -- pokefirered/src/field_specials.c:552
  ["special:" .. Std.SPECIAL.SetVermilionTrashCans] = function(ctx)
    local Rng = require("src.core.game3.rng")
    local first, second = Natives.setVermilionTrashCans(Rng.Random)
    local Flags = flagsMod()
    Flags.setVar(nil, ctx, 0x8004, first)
    Flags.setVar(nil, ctx, 0x8005, second)
    return false
  end,
  -- pokefirered/src/battle_setup.c:865
  ["special:" .. Std.SPECIAL.Script_HasTrainerBeenFought] = function(ctx)
    local Flags = flagsMod()
    local fid = Flags.trainerFlagId(ctx.trainerBattleOpponentA or 0)
    setResult(ctx, Flags.getFlag(vsSeeker().store(), ctx, fid) and 1 or 0)
    return false
  end,
  -- pokefirered/src/battle_setup.c:1007
  ["special:" .. Std.SPECIAL.PlayTrainerEncounterMusic] = function(ctx)
    if ctx.trainerBattleMode == 1 or ctx.trainerBattleMode == 8 then return false end
    local Trainers = require("src.core.game3.scripting.trainers")
    local song = Trainers.getEncounterMusic and Trainers.getEncounterMusic(ctx.trainerBattleOpponentA or 0)
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.playSong and song then Audio.playSong(song) end
    return false
  end,
  -- pokefirered/src/vs_seeker.c:1013
  ["special:" .. Std.SPECIAL.ShouldTryRematchBattle] = function(ctx)
    local VsSeeker = vsSeeker()
    local ok = VsSeeker.shouldTryRematchBattle(ctx.trainerBattleOpponentA or 0, lastTalked(ctx), VsSeeker.store())
    setResult(ctx, ok and 1 or 0)
    return false
  end,
  -- pokefirered/src/vs_seeker.c:1086
  ["special:" .. Std.SPECIAL.IsTrainerReadyForRematch] = function(ctx)
    local ok = vsSeeker().isTrainerReadyForRematch(ctx.trainerBattleOpponentA or 0, lastTalked(ctx))
    setResult(ctx, ok and 1 or 0)
    return false
  end,
  -- pokefirered/src/script_pokemon_util.c:90
  ["special:" .. Std.SPECIAL.HasEnoughMonsForDoubleBattle] = function(ctx)
    local Party = require("src.core.game3.party")
    local rt = package.loaded["src.core.game3.runtime"]
    local session = rt and rt.getSession and rt.getSession()
    setResult(ctx, Party.monsStateToDoubles(session and session.party))
    return false
  end,
  -- pokefirered/src/battle_setup.c:848
  ["special:" .. Std.SPECIAL.SetUpTrainerMovement] = function(ctx)
    local Objects = package.loaded["src.core.game3.objects"]
    local lid = lastTalked(ctx)
    local eo = Objects and not Objects.isPlayer(lid) and Objects.find(lid)
    if eo and Objects.setTrainerMovementType then
      Objects.setTrainerMovementType(eo, vsSeeker().faceTypeFor(eo.facing))
    end
    return false
  end,
  -- pokefirered/src/vs_seeker.c:636
  ["special:" .. Std.SPECIAL.VsSeekerResetObjectMovementAfterChargeComplete] = function()
    vsSeeker().resetObjectMovementAfterChargeComplete()
    return false
  end,
  -- pokefirered/src/vs_seeker.c:598
  ["special:" .. Std.SPECIAL.VsSeekerFreezeObjectsAfterChargeComplete] = function()
    local Objects = package.loaded["src.core.game3.objects"]
    for _, lid in ipairs(Objects and Objects._order or {}) do
      local eo = Objects._byId[lid]
      if eo then eo.frozen = true end
    end
    return false
  end,
  -- pokefirered/src/battle_setup.c:870
  ["special:" .. Std.SPECIAL.SetBattledTrainerFlag] = function(ctx)
    local Flags = flagsMod()
    local store = vsSeeker().store()
    if store then Flags.setFlag(store, ctx, Flags.trainerFlagId(ctx.trainerBattleOpponentA or 0), true) end
    return false
  end,
  ["special:" .. Std.SPECIAL.SetUsedPkmnCenterQuestLogEvent] = function()
    local rt=package.loaded["src.core.game3.runtime"]
    require("src.core.game3.quest_log_recorder").event(rt and rt.getSession(),"MonsWereFullyRestoredAtCenter",{})
    return false
  end,
  ["special:" .. Std.SPECIAL.GetQuestLogState] = function(ctx)
    -- Playback has no script VM; scripts executing here always belong to live play.
    require("src.core.game3.scripting.flags").setVar(nil,ctx,0x800D,0)
    return false
  end,
  ["special:" .. Std.SPECIAL.QuestLog_CutRecording] = function()
    local rt=package.loaded["src.core.game3.runtime"]
    local session=rt and rt.getSession()
    if session then session._questNewScene=true end
    return false
  end,
  ["special:" .. Std.SPECIAL.QuestLog_StartRecordingInputsAfterDeferredEvent] = function()
    return false -- Events are captured at their completed engine transactions.
  end,
  ["special:" .. Std.SPECIAL.Script_SetHelpContext] = function(ctx)
    local id = require("src.core.game3.scripting.flags").getVar(nil, ctx, 0x8004)
    require("src.ui.game3.help_system").setContext(id)
    return false
  end,
  ["special:" .. Std.SPECIAL.BackupHelpContext] = function()
    local Help = require("src.ui.game3.help_system")
    Help.contextBackup = Help.contextOverride
    return false
  end,
  ["special:" .. Std.SPECIAL.RestoreHelpContext] = function()
    local Help = require("src.ui.game3.help_system")
    Help.contextOverride = Help.contextBackup
    return false
  end,
  ["special:" .. Std.SPECIAL.SetHelpContextForMap] = function()
    require("src.ui.game3.help_system").setContext(nil)
    return false
  end,
  ["special:" .. Std.SPECIAL.HelpSystem_Disable] = function()
    require("src.ui.game3.help_system").enabled = false
    return false
  end,
  ["special:" .. Std.SPECIAL.HelpSystem_Enable] = function()
    require("src.ui.game3.help_system").enabled = true
    return false
  end,
  -- pokefirered/src/field_specials.c:153
  ["special:" .. Std.SPECIAL.GetBattleOutcome] = function(ctx)
    local outcome = ctx and ctx.lastBattleOutcome or B_OUTCOME_WON
    setResult(ctx, outcome)
    return false, outcome
  end,
  -- pokefirered/src/field_specials.c:163
  ["special:" .. Std.SPECIAL.GetLeadMonFriendship] = function(ctx)
    local rt = package.loaded["src.core.game3.runtime"]
    local session = rt and rt.getSession and rt.getSession()
    local Pokemon = require("src.core.game3.pokemon")
    local party = (session and session.party) or {}
    local lead = party[1]
    for _, mon in ipairs(party) do
      local sp = tonumber(mon.species or mon.speciesId) or 0
      if sp ~= 0 and not (mon.isEgg or mon.egg) then lead = mon break end
    end
    local f = lead and Pokemon.friendshipOf(lead) or 0
    local score = 0
    if f == 255 then score = 6
    elseif f >= 200 then score = 5
    elseif f >= 150 then score = 4
    elseif f >= 100 then score = 3
    elseif f >= 50 then score = 2
    elseif f > 0 then score = 1 end
    setResult(ctx, score)
    return false, score
  end,
  -- pokefirered/src/field_specials.c:2075
  ["special:" .. Std.SPECIAL.DaisyMassageServices] = function(ctx)
    local Pokemon = require("src.core.game3.pokemon")
    local _, session = partyOf()
    local mon = chosenMon(ctx)
    if mon then
      Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_MASSAGE,
        { mapSec = Pokemon.currentMapSec(session) })
    end
    setSpecialVar(ctx, 0x4025, 0)
    return false
  end,
  -- pokefirered/src/battle_setup.c:320
  ["special:" .. Std.SPECIAL.StartMarowakBattle] = function(ctx, adapters)
    local Enc = require("src.core.game3.encounters")
    local foe = Enc.takePendingWild()
    if not (foe and adapters and adapters.startWildBattle) then return false end
    local rt = package.loaded["src.core.game3.runtime"]
    local session = rt and rt.getSession and rt.getSession()
    local okB, Bag = pcall(require, "src.core.game3.bag")
    local scope = okB and session and session.bag and Bag.has(session.bag, 359, 1) or false
    foe.ghost = true
    foe.ghostUnveiled = scope
    foe.wildScripted = true
    if scope then
      -- pokefirered/src/battle_setup.c:327
      foe.gender, foe.nature = "F", 12
      foe.ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
    end
    return yield_host(ctx, adapters, function(done)
      adapters.startWildBattle(foe, function(result)
        local code = outcome_to_code(result)
        if ctx then ctx.lastBattleOutcome = code end
        -- pokefirered/src/battle_setup.c:458
        setResult(ctx, code == B_OUTCOME_WON and 0 or 1)
        if done then done() end
      end, { wildScripted = true })
    end)
  end,
  -- pokefirered/src/battle_setup.c:349 StartLegendaryBattle (special 0x138 / 312)
  ["special:" .. Std.SPECIAL.StartLegendaryBattle] = function(ctx, adapters)
    local Enc = require("src.core.game3.encounters")
    local foe = Enc.takePendingWild()
    if not (foe and adapters and adapters.startWildBattle) then return false end
    foe.legendary = true
    foe.specialWild = true
    return yield_host(ctx, adapters, function(done)
      adapters.startWildBattle(foe, function(result)
        local code = outcome_to_code(result)
        if ctx then ctx.lastBattleOutcome = code end
        setResult(ctx, code)
        if done then done() end
      end, { legendary = true })
    end)
  end,
  -- pokefirered/src/battle_setup.c:378 StartGroudonKyogreBattle (special 0x137 / 311)
  ["special:" .. Std.SPECIAL.StartGroudonKyogreBattle] = function(ctx, adapters)
    return Natives.ALLOW["special:" .. Std.SPECIAL.StartLegendaryBattle](ctx, adapters)
  end,
  -- pokefirered/src/battle_setup.c:393 StartRegiBattle (special 0x139 / 313)
  ["special:" .. Std.SPECIAL.StartRegiBattle] = function(ctx, adapters)
    return Natives.ALLOW["special:" .. Std.SPECIAL.StartLegendaryBattle](ctx, adapters)
  end,
  -- pokefirered/src/battle_setup.c:339 StartSouthernIslandBattle (special 0x143 / 323)
  ["special:" .. Std.SPECIAL.StartSouthernIslandBattle] = function(ctx, adapters)
    return Natives.ALLOW["special:" .. Std.SPECIAL.StartLegendaryBattle](ctx, adapters)
  end,
  -- pokefirered/src/battle_setup.c:301 StartOldManTutorialBattle (special 0x9D / 157)
  ["special:" .. Std.SPECIAL.StartOldManTutorialBattle] = function(ctx, adapters)
    local foe = {
      species = 13, -- WEEDLE
      level = 5,
      gender = "M",
      oldManTutorial = true,
    }
    if not (adapters and adapters.startWildBattle) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.startWildBattle(foe, function(result)
        local code = outcome_to_code(result)
        if ctx then ctx.lastBattleOutcome = code end
        setResult(ctx, code)
        if done then done() end
      end, { oldManTutorial = true })
    end)
  end,
  ["special:" .. Std.SPECIAL.HealPlayerParty] = function(ctx, adapters)
    if not (adapters and adapters.nurseHeal) then return false end
    return yield_host(ctx, adapters, adapters.nurseHeal)
  end,
  -- pokefirered/src/pokemon_storage_system_menu.c:354
  ["special:" .. Std.SPECIAL.ShowPokemonStorageSystemPC] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.openPc(function() done() end, { mode = "storage" })
    end)
  end,
  -- pokefirered/src/player_pc.c:163
  ["special:" .. Std.SPECIAL.PlayerPC] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.openPc(function() done() end, { mode = "player" })
    end)
  end,
  -- pokefirered/src/player_pc.c:151
  ["special:" .. Std.SPECIAL.BedroomPC] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.openPc(function()
        -- pokefirered/data/maps/PalletTown_PlayersHouse_2F/scripts.inc:46
        local Flags = require("src.core.game3.scripting.flags")
        Flags.setVar(nil, ctx, 0x8004, 1)
        require("src.core.game3.pc_anim").turnOff(ctx)
        if done then done() end
      end, { bedroom = true })
    end)
  end,
  -- pokefirered/src/field_specials.c:212
  ["special:" .. Std.SPECIAL.AnimatePcTurnOn] = function(ctx)
    require("src.core.game3.pc_anim").turnOn(ctx)
    return false
  end,
  -- pokefirered/src/field_specials.c:286
  ["special:" .. Std.SPECIAL.AnimatePcTurnOff] = function(ctx)
    require("src.core.game3.pc_anim").turnOff(ctx)
    return false
  end,
  -- pokefirered/src/script_menu.c:977
  ["special:" .. Std.SPECIAL.CreatePCMenu] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.openPc(function(result)
        setResult(ctx, tonumber(result) or 127)
        done()
      end, { mode = "select" })
    end)
  end,
  -- pokefirered/src/hof_pc.c:23
  ["special:" .. Std.SPECIAL.HallOfFamePCBeginFade] = function(ctx, adapters)
    if not (adapters and adapters.hallOfFamePc) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.hallOfFamePc(function()
        -- pokefirered/src/hof_pc.c:40
        adapters.openPc(function(result)
          setResult(ctx, tonumber(result) or 127)
          done()
        end, { mode = "select", reshow = true })
      end)
    end)
  end,
  ["special:" .. Std.SPECIAL.FieldShowRegionMap] = function(ctx, adapters)
    if not (adapters and adapters.showTownMap) then return false end
    return yield_host(ctx, adapters, adapters.showTownMap)
  end,
  -- Shared intro/field primitives (fade / naming / cry)
  ["special:" .. Std.SPECIAL.FadeScreen] = function(ctx, adapters)
    if not (adapters and adapters.fadeScreen) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.fadeScreen(0, 1, done)
    end)
  end,
  ["special:" .. Std.SPECIAL.OpenNaming] = function(ctx, adapters)
    if not (adapters and adapters.openNaming) then return false end
    return yield_host(ctx, adapters, function(done)
      adapters.openNaming({ title = Strings("NAME?") }, done)
    end)
  end,
  -- pokefirered/src/easy_chat_2.c:256 ShowEasyChatScreen (special 0x5F / 95)
  ["special:" .. Std.SPECIAL.ShowEasyChatScreen] = function(ctx, adapters)
    if not (adapters and adapters.openEasyChat) then
      setResult(ctx, 0)
      flagsMod().setVar(nil, ctx, 0x8004, 1)
      return false
    end
    return yield_host(ctx, adapters, function(done)
      local chatType = flagsMod().getVar(nil, ctx, 0x8004) or 0
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      local EasyChatData = require("src.core.game3.easy_chat_text")
      local currentWords = (session and session.easyChatProfile) or EasyChatData.DEFAULT_PROFILE
      adapters.openEasyChat({
        type = chatType,
        words = currentWords,
        session = session,
      }, function(confirmed, words)
        if confirmed then
          if session then
            session.easyChatProfile = words
            if session.flags then
              session.flags[0x82D] = true
              session.flags["FLAG_SYS_SET_TRAINER_CARD_PROFILE"] = true
            end
          end
          local Flags = flagsMod()
          local Space = package.loaded["src.core.game3.scripting.space"]
          local store = (Space and Space.store) or (session and session.store)
          if store then
            Flags.setFlag(store, ctx, 0x82D, true)
          end
          if chatType == 0 then -- EASY_CHAT_TYPE_PROFILE
            local matches = true
            for i = 1, 4 do
              if words[i] ~= EasyChatData.PASSPHRASE_MYSTERY_EVENT[i] then
                matches = false
                break
              end
            end
            Flags.setVar(nil, ctx, 0x8004, matches and 0 or 1)
          elseif chatType == 14 then -- EASY_CHAT_TYPE_QUESTIONNAIRE
            local matches = true
            for i = 1, 4 do
              if words[i] ~= EasyChatData.PASSPHRASE_QUESTIONNAIRE[i] then
                matches = false
                break
              end
            end
            Flags.setVar(nil, ctx, 0x8004, matches and 0 or 1)
          else
            Flags.setVar(nil, ctx, 0x8004, 1)
          end
          setResult(ctx, 1)
        else
          setResult(ctx, 0)
          flagsMod().setVar(nil, ctx, 0x8004, 1)
        end
        done()
      end)
    end)
  end,
  -- pokefirered/src/easy_chat.c:276 ShowEasyChatMessage (special 0x60 / 96)
  ["special:" .. Std.SPECIAL.ShowEasyChatMessage] = function(ctx, adapters)
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local EasyChatText = require("src.core.game3.easy_chat_text")
    local words = (session and session.easyChatProfile) or EasyChatText.DEFAULT_PROFILE
    -- The saved profile is a list of word ids; the words themselves are drawn
    -- here, so they go through the catalog like the picker's own list.
    local text = EasyChatText.phrase(words, 2, 2)
    if adapters and adapters.openMessage then
      adapters.openMessage(text)
    end
    return false
  end,
  -- pret EventScript_ChangePokemonNickname: fadescreen TO_BLACK → this → waitstate.
  -- Opens naming under the held black, fades in, writes nickname on confirm.
  ["special:" .. Std.SPECIAL.ChangePokemonNickname] = function(ctx, adapters)
    if not (adapters and adapters.openNaming) then return false end
    return yield_host(ctx, adapters, function(done)
      local mon = chosenMon(ctx)
      local species = mon and tonumber(mon.species or mon.speciesId) or 1
      local Pokemon = require("src.core.game3.pokemon")
      ensurePokemonNames(Pokemon)
      -- pokefirered/src/field_specials.c:1656
      local before = nicknameOf(mon)
      setStringVar(ctx, adapters, 3, before)
      setStringVar(ctx, adapters, 2, before)
      local sname = Pokemon.name(species)
      adapters.openNaming({
        title = require("src.ui.game3.naming").monTitle(sname),
        template = "NICKNAME",
        maxLen = 10, -- pret POKEMON_NAME_LENGTH
        species = species,
        personality = mon and mon.personality,
        gender = mon and mon.gender,
      }, function(name)
        if mon and type(name) == "string" and name ~= "" then
          mon.nickname = name
        end
        done()
      end)
    end)
  end,
  -- pokefirered/src/field_specials.c:1629 ChangeBoxPokemonNickname
  ["special:" .. Std.SPECIAL.ChangeBoxPokemonNickname] = function(ctx, adapters)
    local mon = boxedMon()
    if not (mon and adapters and adapters.openNaming) then return false end
    return yield_host(ctx, adapters, function(done)
      local species = tonumber(mon.species or mon.speciesId) or 1
      local Pokemon = require("src.core.game3.pokemon")
      ensurePokemonNames(Pokemon)
      local before = nicknameOf(mon)
      setStringVar(ctx, adapters, 3, before)
      setStringVar(ctx, adapters, 2, before)
      local sname = Pokemon.name(species)
      adapters.openNaming({
        title = require("src.ui.game3.naming").monTitle(sname),
        template = "NICKNAME",
        -- pokefirered/include/constants/global.h:63
        maxLen = 10,
        species = species,
        personality = mon.personality,
        gender = mon.gender,
      }, function(name)
        -- pokefirered/src/field_specials.c:1647 SetBoxMonNickAt
        if type(name) == "string" and name ~= "" then
          mon.nickname = name
          setStringVar(ctx, adapters, 2, name)
        end
        done()
      end)
    end)
  end,
  -- pokefirered/src/field_specials.c:2478 BrailleCursorToggle
  ["special:" .. Std.SPECIAL.BrailleCursorToggle] = function(ctx)
    local okB, Braille = pcall(require, "src.ui.game3.braille")
    if not (okB and type(Braille) == "table") then return false end
    if getSpecialVar(ctx, 0x8006) == 0 then
      pcall(Braille.setCursor, getSpecialVar(ctx, 0x8004) + 27, getSpecialVar(ctx, 0x8005))
    else
      pcall(Braille.clearCursor)
    end
    return false
  end,
  -- pokefirered/src/party_menu_specials.c:14
  ["special:" .. Std.SPECIAL.ChoosePartyMon] = function(ctx, adapters)
    return Natives.choosePartyMon(ctx, adapters, "choose_single")
  end,
  -- pokefirered/src/party_menu.c:5793
  ["special:" .. Std.SPECIAL.ChooseMonForMoveTutor] = function(ctx)
    -- pokefirered/src/party_menu.c:855
    setResult(ctx, 0)
    return false
  end,
  -- pokefirered/src/field_specials.c:1677
  ["special:" .. Std.SPECIAL.IsMonOTIDNotPlayers] = function(ctx)
    local _, session = partyOf()
    local mon = chosenMon(ctx)
    local playerId = tonumber(session and (session.trainerId or session.id or session.playerId)) or 0
    local monOt = tonumber(mon and (mon.otId or mon.ot_id)) or playerId
    setResult(ctx, monOt ~= playerId and 1 or 0)
    return false
  end,
  -- pokefirered/src/field_specials.c:1671
  ["special:" .. Std.SPECIAL.BufferMonNickname] = function(ctx, adapters)
    setStringVar(ctx, adapters, 1, nicknameOf(chosenMon(ctx)))
    return false
  end,
  ["special:" .. Std.SPECIAL.PlayCry] = function(ctx, adapters)
    local Audio = require("src.core.game3.audio")
    local Flags = require("src.core.game3.scripting.flags")
    local Space = package.loaded["src.core.game3.scripting.space"]
    local species = tonumber(Flags.getVar(Space and Space.store, ctx, 0x8000)) or 0
    Audio.playCry(species)
    return false
  end,
  ["special:" .. Std.SPECIAL.EnableNationalPokedex] = function(ctx, adapters)
    local Flags = require("src.core.game3.scripting.flags")
    local Space = package.loaded["src.core.game3.scripting.space"]
    local store = Space and Space.store
    if store and Flags and Flags.setFlag then
      Flags.setFlag(store, nil, 0x840, true) -- FLAG_SYS_NATIONAL_DEX
      if Flags.setVar then
        Flags.setVar(store, nil, 0x404E, 0x6258) -- VAR_NATIONAL_DEX
      end
    end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    if session then
      session.national_dex_unlocked = true
      if session.dex then
        session.dex.nationalUnlocked = true
      end
      if session.store and Flags and Flags.setFlag then
        Flags.setFlag(session.store, nil, 0x840, true)
        if Flags.setVar then
          Flags.setVar(session.store, nil, 0x404E, 0x6258)
        end
      end
    end
    if adapters and adapters.setFlag then
      adapters.setFlag(0x840, true)
    end
    return false
  end,
  -- pokefirered/src/event_data.c:107 IsNationalPokedexEnabled
  ["special:" .. Std.SPECIAL.IsNationalPokedexEnabled] = function(ctx)
    local PokedexData = require("src.core.game3.pokedex_data")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local dex = session and session.dex
    local isUnlocked = PokedexData.isNationalUnlocked(session, dex)
    local resVal = isUnlocked and 1 or 0
    setResult(ctx, resVal)
    return false, resVal
  end,
  -- pokefirered/src/save_location.c:98
  ["special:" .. Std.SPECIAL.SetUnlockedPokedexFlags] = function()
    local rt = package.loaded["src.core.game3.runtime"]
    local session = rt and rt.getSession and rt.getSession()
    if session then
      local bits = tonumber(session.gcnLinkFlags) or 0
      local Bit = require("bit")
      session.gcnLinkFlags = Bit.bor(bits, 0x31)
    end
    return false
  end,
  ["special:" .. Std.SPECIAL.EnterHallOfFame] = function(ctx, adapters)
    local Flags = require("src.core.game3.scripting.flags")
    local flagGameClear = (Flags.IDS and Flags.IDS.SYS_GAME_CLEAR) or 0x82C
    local Space = package.loaded["src.core.game3.scripting.space"]
    local store = Space and Space.store
    if store and Flags and Flags.setFlag then
      Flags.setFlag(store, nil, flagGameClear, true) -- FLAG_SYS_GAME_CLEAR
    end
    if adapters and adapters.setFlag then
      adapters.setFlag(flagGameClear, true)
    end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    if session then
      session.game_cleared = true
      if session.store and Flags and Flags.setFlag then
        Flags.setFlag(session.store, nil, flagGameClear, true)
      end
    end
    if adapters and adapters.hallOfFame then
      return yield_host(ctx, adapters, adapters.hallOfFame)
    end
    return false
  end,
}

local MODULE_DIR = "src/core/game3/scripting"
local MODULE_PACKAGE = "src.core.game3.scripting."

local KNOWN_MODULES = {
  "natives_corner",
  "natives_cutscene",
  "natives_daycare",
  "natives_elevator",
  "natives_events",
  "natives_fame",
  "natives_fan_club",
  "natives_gift",
  "natives_link",
  "natives_listmenu",
  "natives_moveteach",
  "natives_queries",
  "natives_seagallop",
  "natives_size_record",
  "natives_tower",
  "natives_trade",
  "natives_wireless",
}
Natives.KNOWN_MODULES = KNOWN_MODULES
Natives.MODULE_DIR = MODULE_DIR

local function moduleNames()
  local names = Profile.active().nativeModules
  return type(names) == "table" and names or KNOWN_MODULES
end
Natives.moduleNames = moduleNames

local function collectModule(names, seen, entry)
  local base = type(entry) == "string" and entry:match("^(natives_[%w_]+)%.lua$")
  if base and not seen[base] then
    seen[base] = true
    names[#names + 1] = base
  end
end

local function discoverModules()
  local names, seen = {}, {}
  local fs = type(love) == "table" and love.filesystem
  if fs and fs.getDirectoryItems then
    pcall(function()
      for _, entry in ipairs(fs.getDirectoryItems(MODULE_DIR)) do
        collectModule(names, seen, entry)
      end
    end)
  elseif io and io.popen then
    pcall(function()
      local pipe = io.popen('ls -1 "' .. MODULE_DIR .. '" 2>/dev/null')
      if not pipe then return end
      for line in pipe:lines() do collectModule(names, seen, line) end
      pipe:close()
    end)
  end
  for _, base in ipairs(moduleNames()) do collectModule(names, seen, base .. ".lua") end
  table.sort(names)
  return names
end

Natives.MODULE_NAMES = discoverModules()
Natives.MODULES = {}

for _, base in ipairs(Natives.MODULE_NAMES) do
  if Capabilities.nativeAllowed(nil, base) then
    local ok, mod = pcall(require, MODULE_PACKAGE .. base)
    if ok and type(mod) == "table" then
      Natives.MODULES[base] = mod
      for id, handler in pairs(mod.HANDLERS or {}) do
        Natives.ALLOW["special:" .. id] = handler
      end
    end
  end
end

Natives.Queries = Natives.MODULES["natives_queries"]
Natives.Seagallop = Natives.MODULES["natives_seagallop"]

function Natives.resetLog()
  Natives._logged = {}
end

local function log_once(kind, id, logger)
  local key = kind .. ":" .. tostring(id)
  if Natives._logged[key] then return end
  Natives._logged[key] = true
  local msg = string.format("[game3] skip unknown %s 0x%X", kind, tonumber(id) or 0)
  if logger then logger(msg) else print(msg) end
end

--- Returns whether the VM should yield (native wait).
Natives.log_once = log_once

function Natives.callnative(ctx, fnAddr, adapters)
  local id = tonumber(fnAddr) or 0
  local handler = Natives.ALLOW["native:" .. id]
  if handler then
    return handler(ctx, adapters) and true or false
  end
  log_once("callnative", id, adapters and adapters.log)
  return false
end

-- src/scrcmd.c:92-97
Natives.NATIVE_SYMBOLS = {}
function Natives.resolveNative(addr)
  local id = tonumber(addr) or 0
  local sym = Natives.NATIVE_SYMBOLS[id]
  if sym then
    local fn = Natives.ALLOW["native:" .. sym]
    if fn then return fn end
  end
  return Natives.ALLOW["native:" .. id]
end

function Natives.special(ctx, specialId, adapters)
  local id = tonumber(specialId) or 0
  local handler = Natives.ALLOW["special:" .. id]
  if handler then
    local yield, value = handler(ctx, adapters)
    return yield and true or false, value, true
  end
  log_once("special", id, adapters and adapters.log)
  return false, nil, false
end

return Natives
