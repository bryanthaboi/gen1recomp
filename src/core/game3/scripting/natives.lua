-- callnative / special allowlist; unknown → safe-skip + log once.
-- Handlers mirror pret specials → host adapters (heal / PC), not map coords.

local Std = require("src.core.game3.scripting.stdscripts")

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

Natives.ALLOW = {
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
    if scope then
      -- pokefirered/src/battle_setup.c:327
      foe.gender, foe.nature = "F", 12
      foe.ivs = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
    end
    return yield_host(ctx, adapters, function(done)
      adapters.startWildBattle(foe, function(result)
        -- pokefirered/src/battle_setup.c:458
        require("src.core.game3.scripting.flags").setVar(nil, ctx, 0x800D, (result == "win") and 0 or 1)
        if done then done() end
      end)
    end)
  end,
  ["special:" .. Std.SPECIAL.HealPlayerParty] = function(ctx, adapters)
    if not (adapters and adapters.nurseHeal) then return false end
    return yield_host(ctx, adapters, adapters.nurseHeal)
  end,
  ["special:" .. Std.SPECIAL.ShowPokemonStorageSystemPC] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, adapters.openPc)
  end,
  ["special:" .. Std.SPECIAL.PlayerPC] = function(ctx, adapters)
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, adapters.openPc)
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
  ["special:" .. Std.SPECIAL.CreatePCMenu] = function(ctx, adapters)
    -- Cart builds a menu; host PC UI is the whole menu — open it directly.
    if not (adapters and adapters.openPc) then return false end
    return yield_host(ctx, adapters, adapters.openPc)
  end,
  ["special:" .. Std.SPECIAL.ShowRegionMap] = function(ctx, adapters)
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
      adapters.openNaming({ title = "NAME?" }, done)
    end)
  end,
  -- pret EventScript_ChangePokemonNickname: fadescreen TO_BLACK → this → waitstate.
  -- Opens naming under the held black, fades in, writes nickname on confirm.
  ["special:" .. Std.SPECIAL.ChangePokemonNickname] = function(ctx, adapters)
    if not (adapters and adapters.openNaming) then return false end
    return yield_host(ctx, adapters, function(done)
      local slot = 0
      if ctx and ctx.getVar then
        slot = tonumber(ctx:getVar(0x8004)) or 0
      end
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      local mon = session and session.party and session.party[slot + 1]
      local species = mon and tonumber(mon.species or mon.speciesId) or 1
      local Pokemon = require("src.core.game3.pokemon")
      pcall(function()
        if not Pokemon._names then Pokemon.install(nil) end
      end)
      local sname = (Pokemon.name and Pokemon.name(species)) or "POKéMON"
      adapters.openNaming({
        title = sname .. "'s nickname?",
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
  ["special:" .. Std.SPECIAL.BufferMonNickname] = function(ctx, adapters)
    -- pret BufferMonNickname → gStringVar1; host buffers for {STR_VAR_1}.
    local slot = 0
    if ctx and ctx.getVar then
      slot = tonumber(ctx:getVar(0x8004)) or 0
    end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local mon = session and session.party and session.party[slot + 1]
    local nick = ""
    if mon then
      if mon.nickname and mon.nickname ~= "" then
        nick = tostring(mon.nickname)
      else
        local Pokemon = require("src.core.game3.pokemon")
        pcall(function()
          if not Pokemon._names then Pokemon.install(nil) end
        end)
        nick = (Pokemon.name and Pokemon.name(mon.species or mon.speciesId)) or ""
      end
    end
    if adapters and adapters.setStringVar then
      adapters.setStringVar(1, nick)
    elseif ctx and ctx.stringVars then
      ctx.stringVars[1] = nick
    end
    return false
  end,
  ["special:" .. Std.SPECIAL.PlayCry] = function(ctx, adapters)
    local Audio = require("src.core.game3.audio")
    local species = 0
    if ctx and ctx.getVar then
      species = tonumber(ctx:getVar(0x8000)) or 0
    end
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
  ["special:" .. Std.SPECIAL.IsNationalPokedexEnabled] = function(ctx, adapters)
    local PokedexData = require("src.core.game3.pokedex_data")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local dex = session and session.dex
    local isUnlocked = PokedexData.isNationalUnlocked(session, dex)
    local resVal = isUnlocked and 1 or 0
    if ctx and ctx.setVar then
      ctx:setVar(0x800D, resVal) -- VAR_RESULT
    end
    if adapters and adapters.setVar then
      adapters.setVar(0x800D, resVal)
    end
    return false
  end,
  ["special:" .. Std.SPECIAL.SetUnlockedPokedexFlags] = function(ctx, adapters)
    local Flags = require("src.core.game3.scripting.flags")
    local Space = package.loaded["src.core.game3.scripting.space"]
    local store = Space and Space.store
    if store and Flags and Flags.setFlag then
      Flags.setFlag(store, nil, 0x829, true) -- FLAG_SYS_POKEDEX_GET
    end
    if adapters and adapters.setFlag then
      adapters.setFlag(0x829, true)
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
function Natives.callnative(ctx, fnAddr, adapters)
  local id = tonumber(fnAddr) or 0
  local handler = Natives.ALLOW["native:" .. id]
  if handler then
    return handler(ctx, adapters) and true or false
  end
  log_once("callnative", id, adapters and adapters.log)
  return false
end

function Natives.special(ctx, specialId, adapters)
  local id = tonumber(specialId) or 0
  local handler = Natives.ALLOW["special:" .. id]
  if handler then
    return handler(ctx, adapters) and true or false
  end
  log_once("special", id, adapters and adapters.log)
  return false
end

return Natives
