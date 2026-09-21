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

local function sessionOf(ctx)
  local rt = package.loaded["src.core.game3.runtime"]
  return (rt and rt.getSession and rt.getSession())
    or (ctx and ctx.session)
    or nil
end

local function scriptStore(ctx)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf(ctx)
  return (Space and Space.store)
    or (session and (session.store or session))
    or (ctx and (ctx.store or ctx.session or (ctx.vars and ctx)))
    or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(ctx), ctx, id)) or 0
end

-- pokefirered/src/scrcmd.c:99
local function setResult(ctx, value)
  flagsMod().setVar(scriptStore(ctx), ctx, VAR_RESULT, tonumber(value) or 0)
end

local function currentMapId(ctx)
  local session = sessionOf(ctx)
  if session and session.map then return session.map end
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.current
end

local function partyOf(ctx)
  local session = sessionOf(ctx)
  return (session and session.party) or (ctx and ctx.party) or {}, session
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
    local store = scriptStore(ctx)
    for i = 1, #ICEFALL_CAVE_ICE_COORDS do
      if Flags.getFlag(store, ctx, i) then
        local c = ICEFALL_CAVE_ICE_COORDS[i]
        Field.setMetatile(c[1], c[2], METATILE_SEAFOAM_CRACKED_ICE, true)
      end
    end
    return false
  end,
  -- pokefirered/src/field_tasks.c:166
  [Std.SPECIAL.ShowIcefallCaveCrackedIceAttempt] = function(ctx, adapters)
    local Flags = flagsMod()
    local store = scriptStore(ctx)
    local total = 0
    for i = 1, #ICEFALL_CAVE_ICE_COORDS do
      if Flags.getFlag(store, ctx, i) then
        total = total + 1
      end
    end
    setResult(ctx, total)
    return false
  end,
  -- pokefirered/src/bicycle.c:120
  [Std.SPECIAL.ForcePlayerOntoBike] = function(ctx)
    local session = sessionOf(ctx)
    if session and session.player then
      session.player.ridingBike = true
      session.player.state = "bike"
    end
    local rt = package.loaded["src.core.game3.runtime"]
    if rt and rt.player then
      rt.player.ridingBike = true
      rt.player.state = "bike"
    end
    return false
  end,
  -- pokefirered/src/field_player_avatar.c:1570
  [Std.SPECIAL.ForcePlayerToStartSurfing] = function(ctx)
    local session = sessionOf(ctx)
    if session and session.player then
      session.player.surfing = true
      session.player.state = "surf"
    end
    local rt = package.loaded["src.core.game3.runtime"]
    if rt and rt.player then
      rt.player.surfing = true
      rt.player.state = "surf"
    end
    return false
  end,
  -- pokefirered/src/wild_encounter.c:446
  [Std.SPECIAL.RockSmashWildEncounter] = function(ctx, adapters)
    local okE, Enc = pcall(require, "src.core.game3.encounters")
    local foe
    if okE and Enc and type(Enc.rollRocks) == "function" then
      foe = Enc.rollRocks(currentMapId(ctx))
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
  [Std.SPECIAL.SetPostgameFlags] = function(ctx)
    local session = sessionOf(ctx)
    if not session then return false end
    local Bit = require("bit")
    session.gcnLinkFlags = Bit.bor(tonumber(session.gcnLinkFlags) or 0, 0x800E)
    session.specialSaveWarpFlags =
      Bit.bor(tonumber(session.specialSaveWarpFlags) or 0, CHAMPION_SAVEWARP)
    return false
  end,
  -- pokefirered/src/field_specials.c:120 ShowFieldMessageStringVar4
  [Std.SPECIAL.ShowFieldMessageStringVar4] = function(ctx, adapters)
    local text = (ctx and ctx.stringVars and ctx.stringVars[4]) or ""
    if adapters and adapters.showMessage then
      adapters.showMessage(text)
    end
    return false
  end,
  -- pokefirered/src/script.c:260 SetWalkingIntoSignVars
  [Std.SPECIAL.SetWalkingIntoSignVars] = function(ctx)
    if ctx then
      ctx.walkAwayFromSignInhibitTimer = 6
      ctx.msgBoxIsCancelable = true
      ctx.canWalkAway = true
    end
    local session = sessionOf(ctx)
    if session then
      session.walkAwayFromSignInhibitTimer = 6
      session.msgBoxIsCancelable = true
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:1733 StickerManGetBragFlags
  [Std.SPECIAL.StickerManGetBragFlags] = function(ctx)
    local session = sessionOf(ctx)
    local Flags = flagsMod()
    local store = scriptStore(ctx)
    local stats = session and (session.gameStats or session.stats) or {}

    -- HOF enters: GAME_STAT_ENTERED_HOF = 13 (or hofClears / FLAG_SYS_GAME_CLEAR)
    local hof = (session and (session.hofClears or session.hallOfFameCount))
      or stats[13] or stats.enteredHof or (Flags.getFlag(store, ctx, "FLAG_SYS_GAME_CLEAR") and 1 or 0)
    hof = tonumber(hof) or 0

    -- Hatched eggs: GAME_STAT_HATCHED_EGGS = 18
    local eggs = (session and session.eggsHatched) or stats[18] or stats.hatchedEggs or 0
    eggs = tonumber(eggs) or 0
    local eggsClamped = math.min(0xFFFF, eggs)

    -- Link battle wins: GAME_STAT_LINK_BATTLE_WINS = 24
    local linkWins = (session and (session.linkWins or session.linkBattleWins))
      or stats[24] or stats.linkBattleWins or 0
    linkWins = tonumber(linkWins) or 0

    Flags.setVar(store, ctx, VAR_0x8004, hof)
    Flags.setVar(store, ctx, VAR_0x8005, eggsClamped)
    Flags.setVar(store, ctx, VAR_0x8006, linkWins)

    local result = 0
    if hof ~= 0 then result = result + 1 end
    if eggsClamped ~= 0 then result = result + 2 end
    if linkWins ~= 0 then result = result + 4 end

    Flags.setVar(store, ctx, 0x8008, result)
    setResult(ctx, result)
    return false, result
  end,
  -- pokefirered/src/field_specials.c:1710 UpdateTrainerCardPhotoIcons
  [Std.SPECIAL.UpdateTrainerCardPhotoIcons] = function(ctx)
    local party, session = partyOf(ctx)
    local Flags = flagsMod()
    local store = scriptStore(ctx)
    local partyCount = (party and #party) or 0

    local VAR_TRAINER_CARD_MON_ICON_1 = 0x4043
    local VAR_TRAINER_CARD_MON_ICON_TINT_IDX = 0x4042

    for i = 1, 6 do
      local iconSpecies = 0
      if party and i <= partyCount and party[i] then
        local mon = party[i]
        if mon.isEgg then
          iconSpecies = 412 -- SPECIES_EGG
        else
          iconSpecies = tonumber(mon.speciesId or mon.species) or 0
        end
      end
      Flags.setVar(store, ctx, VAR_TRAINER_CARD_MON_ICON_1 + i - 1, iconSpecies)
    end

    local tint = varGet(ctx, VAR_0x8004)
    Flags.setVar(store, ctx, VAR_TRAINER_CARD_MON_ICON_TINT_IDX, tint)
    return false
  end,
  -- pokefirered/src/field_player_avatar.c:1603 SeafoamIslandsB4F_CurrentDumpsPlayerOnLand
  [Std.SPECIAL.SeafoamIslandsB4F_CurrentDumpsPlayerOnLand] = function(ctx, adapters)
    local function finishDismount()
      local session = sessionOf(ctx)
      if session then
        session.surfing = false
        if session.player then
          session.player.surfing = false
          session.player.state = "walk"
          session.player.facing = "up"
        end
        session.facing = "up"
      end
      local rt = package.loaded["src.core.game3.runtime"]
      if rt and rt.player then
        rt.player.surfing = false
        rt.player.state = "walk"
        rt.player.facing = "up"
      end
      local okP, Player = pcall(require, "src.core.game3.player")
      if okP and Player then
        Player.surfing = false
        Player.state = "walk"
        Player.facing = "up"
      end
      local Field = package.loaded["src.core.game3.field"]
      if Field and Field.stopSurfing then
        pcall(Field.stopSurfing)
      end
    end

    if adapters and adapters.applyMovement then
      local Natives = require("src.core.game3.scripting.natives")
      return Natives.yieldHost(ctx, adapters, function(done)
        -- 0xA7 = MOVEMENT_ACTION_JUMP_SPECIAL_WITH_EFFECT_UP (jump 1 cell up onto stairs)
        adapters.applyMovement(255, { 0xA7, 0xFE }, function()
          finishDismount()
          done()
        end)
      end)
    else
      local okP, Player = pcall(require, "src.core.game3.player")
      if okP and Player and Player.cellY then
        Player.cellY = Player.cellY - 1
        Player.targetY = Player.cellY
        Player.py = Player.cellY * 16
      end
      finishDismount()
      return false
    end
  end,
  -- pokefirered/src/start_menu.c:620 Field_AskSaveTheGame
  [Std.SPECIAL.Field_AskSaveTheGame] = function(ctx, adapters)
    local okL, Link = pcall(require, "src.core.game3.link.init")
    if okL and Link and Link.askSaveTheGame then
      return Link.askSaveTheGame(ctx, adapters)
    end
    setResult(ctx, 0)
    return false
  end,
  -- pokefirered/src/load_save.c:208 LoadPlayerBag
  [Std.SPECIAL.LoadPlayerBag] = function()
    local okL, Link = pcall(require, "src.core.game3.link.init")
    if okL and Link and Link.loadPlayerBag then
      Link.loadPlayerBag()
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
  -- pokefirered/src/field_specials.c:2319
  [Std.SPECIAL.DoDeoxysTriangleInteraction] = function(ctx)
    local session = sessionOf()
    if not session then return false end
    local Deoxys = require("src.core.game3.deoxys")
    -- The script does `waitstate` then `switch VAR_RESULT`; the rock animation
    -- runs on in the background exactly as pret's Task_WaitDeoxysFieldEffect does.
    setResult(ctx, Deoxys.interact(session))
    return false
  end,
  -- pokefirered/src/field_specials.c:2451
  [Std.SPECIAL.SetDeoxysTrianglePalette] = function(ctx)
    local session = sessionOf()
    local Deoxys = require("src.core.game3.deoxys")
    local num = session and Deoxys.getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM)
    if num == nil then num = varGet(ctx, Deoxys.VAR_DEOXYS_INTERACTION_NUM) end
    Deoxys.applyRockPalette(num or 0)
    return false
  end,
  -- pokefirered/src/field_specials.c:2512
  [Std.SPECIAL.UpdateLoreleiDollCollection] = noop,
}

Events.HANDLERS[Std.SPECIAL.SetPostgameFlagsUnusedSlot] =
  Events.HANDLERS[Std.SPECIAL.SetPostgameFlags]

return Events
