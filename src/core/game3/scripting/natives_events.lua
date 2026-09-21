local Std = require("src.core.game3.scripting.stdscripts")

local Events = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321

-- pokefirered/src/field_tasks.c:51
local ICEFALL_CAVE_ICE_COORDS = {
  { 8, 3 }, { 10, 5 }, { 15, 5 },
  { 8, 9 }, { 9, 9 }, { 16, 9 },
  { 8, 10 }, { 9, 10 }, { 8, 14 },
}

-- pokefirered/include/constants/metatile_labels.h:188
local METATILE_SEAFOAM_CRACKED_ICE = 0x35A

-- pokefirered/include/constants/songs.h:290
local MUS_CYCLING = 282

-- pokefirered/include/save_location.h:9
local CHAMPION_SAVEWARP = 0x80

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

-- pokefirered/src/scrcmd.c:99
local function setResult(ctx, value)
  flagsMod().setVar(scriptStore(), ctx, VAR_RESULT, tonumber(value) or 0)
end

local function currentMapId()
  local session = sessionOf()
  if session and session.map then return session.map end
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.current
end

local function noop()
  return false
end

Events.ICEFALL_CAVE_ICE_COORDS = ICEFALL_CAVE_ICE_COORDS
Events.METATILE_SEAFOAM_CRACKED_ICE = METATILE_SEAFOAM_CRACKED_ICE

Events.HANDLERS = {
  -- pokefirered/src/field_camera.c:93
  [Std.SPECIAL.DrawWholeMapView] = function()
    local FieldView = package.loaded["src.core.game3.field_view"]
    if FieldView then FieldView._nativeDirty = true end
    return false
  end,
  -- pokefirered/src/pokemon.c:6215
  [Std.SPECIAL.CreateEnemyEventMon] = function(ctx)
    local okE, Enc = pcall(require, "src.core.game3.encounters")
    if not (okE and Enc and Enc.setWildBattle) then return false end
    local item = varGet(ctx, VAR_0x8006)
    Enc.setWildBattle(varGet(ctx, VAR_0x8004), varGet(ctx, VAR_0x8005),
      item ~= 0 and item or nil)
    -- pokefirered/src/pokemon.c:2026
    local pending = Enc._pendingWild
    if pending then pending.fatefulEncounter = true end
    return false
  end,
  -- pokefirered/src/safari_zone.c:27
  [Std.SPECIAL.EnterSafariMode] = function()
    pcall(function() require("src.core.game3.safari").enter() end)
    return false
  end,
  -- pokefirered/src/safari_zone.c:35
  [Std.SPECIAL.ExitSafariMode] = function()
    pcall(function() require("src.core.game3.safari").exit() end)
    return false
  end,
  -- pokefirered/src/field_tasks.c:152
  [Std.SPECIAL.SetIcefallCaveCrackedIceMetatiles] = function(ctx)
    local okF, Field = pcall(require, "src.core.game3.field")
    if not (okF and Field and Field.setMetatile) then return false end
    local Flags = flagsMod()
    local store = scriptStore()
    for i = 1, #ICEFALL_CAVE_ICE_COORDS do
      if Flags.getFlag(store, ctx, i) then
        local coord = ICEFALL_CAVE_ICE_COORDS[i]
        Field.setMetatile(coord[1], coord[2], METATILE_SEAFOAM_CRACKED_ICE, false)
      end
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:97
  [Std.SPECIAL.ForcePlayerOntoBike] = function()
    local okP, Player = pcall(require, "src.core.game3.player")
    if okP and Player and not Player.surfing then
      Player.biking = true
      Player.running = false
    end
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.playSong then pcall(Audio.playSong, MUS_CYCLING) end
    return false
  end,
  -- pokefirered/src/field_specials.c:1513
  [Std.SPECIAL.ForcePlayerToStartSurfing] = function()
    local okP, Player = pcall(require, "src.core.game3.player")
    if not (okP and Player) then return false end
    Player.biking = false
    Player.running = false
    Player.surfHopping = false
    Player.dismounting = false
    Player.surfing = true
    return false
  end,
  -- pokefirered/src/wild_encounter.c:446
  [Std.SPECIAL.RockSmashWildEncounter] = function(ctx, adapters)
    local okE, Enc = pcall(require, "src.core.game3.encounters")
    local foe
    if okE and Enc and type(Enc.rollRocks) == "function" then
      foe = Enc.rollRocks(currentMapId())
    end
    if not (foe and adapters and adapters.startWildBattle) then
      setResult(ctx, 0)
      return false
    end
    foe.wildScripted = true
    setResult(ctx, 1)
    local Natives = require("src.core.game3.scripting.natives")
    return Natives.yieldHost(ctx, adapters, function(done)
      adapters.startWildBattle(foe, function(result)
        local code = Natives.outcome_to_code(result)
        if ctx then ctx.lastBattleOutcome = code end
        done()
      end, { wildScripted = true })
    end)
  end,
  -- pokefirered/src/save_location.c:105
  [Std.SPECIAL.SetPostgameFlags] = function()
    local session = sessionOf()
    if not session then return false end
    local Bit = require("bit")
    session.gcnLinkFlags = Bit.bor(tonumber(session.gcnLinkFlags) or 0, 0x800E)
    session.specialSaveWarpFlags =
      Bit.bor(tonumber(session.specialSaveWarpFlags) or 0, CHAMPION_SAVEWARP)
    return false
  end,
  -- pokefirered/src/field_specials.c:120 ShowFieldMessageStringVar4
  [Std.SPECIAL.ShowFieldMessageStringVar4] = function(ctx, adapters)
    local body = tostring((ctx and ctx.stringVars and ctx.stringVars[4]) or "")
    if body == "" then return false end
    -- pokefirered/src/field_message_box.c:65 ShowFieldMessage
    ctx.messageOpen = true
    ctx.printerDone = false
    local open = adapters and (adapters.openMessageStay or adapters.openMessageAsync)
    if open then
      open(body, nil)
    elseif adapters and adapters.openMessage then
      adapters.openMessage(body)
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:461
  [Std.SPECIAL.ShakeScreen] = noop,
  -- pokefirered/src/roamer.c:120
  [Std.SPECIAL.InitRoamer] = noop,
  -- pokefirered/src/field_specials.c:679
  [Std.SPECIAL.SampleResortGorgeousMonAndReward] = noop,
  -- pokefirered/src/script.c:245
  [Std.SPECIAL.DisableMsgBoxWalkaway] = noop,
  -- pokefirered/src/field_specials.c:2451
  [Std.SPECIAL.SetDeoxysTrianglePalette] = noop,
  -- pokefirered/src/field_specials.c:2512
  [Std.SPECIAL.UpdateLoreleiDollCollection] = noop,
}

Events.HANDLERS[Std.SPECIAL.SetPostgameFlagsUnusedSlot] =
  Events.HANDLERS[Std.SPECIAL.SetPostgameFlags]

return Events
