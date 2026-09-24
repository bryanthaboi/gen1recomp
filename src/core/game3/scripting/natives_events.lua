local Std = require("src.core.game3.scripting.stdscripts")

local Events = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321
local VAR_FACING = 0x800C

-- pokefirered/src/field_tasks.c:51
local ICEFALL_CAVE_ICE_COORDS = {
  { 8, 3 }, { 10, 5 }, { 15, 5 },
  { 8, 9 }, { 9, 9 }, { 16, 9 },
  { 8, 10 }, { 9, 10 }, { 8, 14 },
}

-- pokefirered/include/constants/metatile_labels.h:188
local METATILE_SEAFOAM_CRACKED_ICE = 0x35A
local METATILE_SEAFOAM_ICE_HOLE = 0x35B

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
Events.METATILE_SEAFOAM_ICE_HOLE = METATILE_SEAFOAM_ICE_HOLE

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
        Field.setMetatile(c[1], c[2], METATILE_SEAFOAM_CRACKED_ICE, false)
      end
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:97
  [Std.SPECIAL.ForcePlayerOntoBike] = function()
    local okP, Player = pcall(require, "src.core.game3.player")
    if okP and Player and not Player.surfing then
      Player.biking = true
      Player.surfHopping = false
    end
    require("src.core.game3.audio").bikeMusic(true, true)
    return false
  end,
  -- pokefirered/src/field_specials.c:1513
  [Std.SPECIAL.ForcePlayerToStartSurfing] = function()
    local okP, Player = pcall(require, "src.core.game3.player")
    if okP and Player then
      Player.surfing = true
      Player.biking = false
      Player.surfHopping = false
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
    if ctx then ctx.messageOpen = true end
    local openStay = adapters and (adapters.openMessageStay or adapters.openMessageAsync)
    if openStay then
      openStay(text, nil)
    elseif adapters and adapters.openMessage then
      adapters.openMessage(text)
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

    -- field_specials.c:1737, include/constants/game_stat.h:14
    local hof = stats[10] or stats.enteredHof
      or (session and (session.hofClears or session.hallOfFameCount))
      or (Flags.getFlag(store, ctx, "FLAG_SYS_GAME_CLEAR") and 1 or 0)
    hof = tonumber(hof) or 0

    -- game_stat.h:17
    local eggs = stats[13] or stats.hatchedEggs
      or (session and session.eggsHatched) or 0
    eggs = tonumber(eggs) or 0
    local eggsClamped = math.min(0xFFFF, eggs)

    -- game_stat.h:27
    local linkWins = stats[23] or stats.linkBattleWins
      or (session and (session.linkWins or session.linkBattleWins)) or 0
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
  -- src/field_specials.c:461-493, include/constants/songs.h:212
  [Std.SPECIAL.ShakeScreen] = function(ctx)
    local x = varGet(ctx, VAR_0x8005)
    local y = varGet(ctx, VAR_0x8004)
    local iters = varGet(ctx, VAR_0x8006)
    local dur = varGet(ctx, 0x8007)
    if (x == 0 and y == 0) or iters < 1 or dur < 1 then return false end
    local FieldView = package.loaded["src.core.game3.field_view"]
    local okT, Task = pcall(require, "src.core.game3.task")
    if not (okT and Task and Task.spawn) then return false end
    pcall(function() require("src.core.game3.audio").playSe(207) end)
    local frame, left, cx, cy = 0, iters, x, y
    Task.spawn(function()
      frame = frame + 1
      if frame % dur == 0 then
        left = left - 1
        cx, cy = -cx, -cy
        if FieldView then
          FieldView.cameraPanX = cx
          FieldView.cameraPanY = cy
        end
        if left == 0 then
          if FieldView then
            FieldView.cameraPanX = 0
            FieldView.cameraPanY = 0
          end
          return true
        end
      end
      return false
    end)
    return false
  end,
  -- src/roamer.c:120
  [Std.SPECIAL.InitRoamer] = function(ctx)
    local session = sessionOf(ctx)
    local VAR_STARTER_MON = 0x4031 -- pokefirered/include/constants/vars.h:98
    local starter = varGet(ctx, VAR_STARTER_MON)
    local okR, Roamer = pcall(require, "src.core.game3.roamer")
    if okR and Roamer and Roamer.init then
      Roamer.init(session, starter)
    end
    return false
  end,
  -- src/field_specials.c:679-690
  [Std.SPECIAL.SampleResortGorgeousMonAndReward] = function(ctx, adapters)
    local session = sessionOf(ctx)
    if not session then return false end
    local VAR_REQ = 0x4036 -- include/constants/vars.h:104
    local VAR_REWARD = 0x403B -- vars.h:109
    local VAR_STEP = 0x4035 -- vars.h:103
    local requested = varGet(ctx, VAR_REQ)
    local store = scriptStore(ctx)
    local F = flagsMod()
    if requested == 0 or requested == 0xFFFF then
      local Rng = require("src.core.game3.rng")
      local ownedT = (session.dex and (session.dex.owned or session.dex.caught)) or {}
      local NUM = 411 -- species.h:423
      local sp, found = 1, false
      for _ = 1, 100 do
        sp = (Rng.Random() % NUM) + 1
        if ownedT[sp] then found = true break end
      end
      if not found then
        for _ = 1, 500 do
          if ownedT[sp] then found = true break end
          if sp == 1 then sp = NUM else sp = sp - 1 end
        end
      end
      F.setVar(store, ctx, VAR_REQ, sp)
      -- items.h:72,110-114
      local rewards = { 107, 106, 108, 109, 110, 68 }
      local reward = 11
      if (Rng.Random() % 100) < 30 then
        reward = rewards[(Rng.Random() % #rewards) + 1]
      end
      F.setVar(store, ctx, VAR_REWARD, reward)
      F.setVar(store, ctx, VAR_STEP, 0)
    end
    -- pokefirered/src/field_specials.c:688
    local nameOf = package.loaded["src.core.game3.pokemon"]
      or require("src.core.game3.pokemon")
    local name = (nameOf.name and nameOf.name(varGet(ctx, VAR_REQ))) or ""
    if adapters and adapters.setStringVar then adapters.setStringVar(1, name) end
    if ctx and ctx.stringVars then ctx.stringVars[1] = name end
    return false
  end,
  -- pokefirered/src/script.c:245
  [Std.SPECIAL.DisableMsgBoxWalkaway] = function(ctx)
    if ctx then
      ctx.canWalkAway = false
    end
    local session = sessionOf(ctx)
    if session then
      session.canWalkAway = false
    end
    return false
  end,
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
  -- src/field_specials.c:2512-2531, game_stat.h:14
  [Std.SPECIAL.UpdateLoreleiDollCollection] = function(ctx)
    local session = sessionOf(ctx)
    local stats = session and (session.gameStats or session.stats) or {}
    local n = tonumber(stats[10]) or 0
    local F = flagsMod()
    local store = scriptStore(ctx)
    local dolls = {
      { 25, "FLAG_HIDE_LORELEI_HOUSE_MEOWTH_DOLL" },
      { 50, "FLAG_HIDE_LORELEI_HOUSE_CHANSEY_DOLL" },
      { 75, "FLAG_HIDE_LORELEIS_HOUSE_NIDORAN_F_DOLL" },
      { 100, "FLAG_HIDE_LORELEI_HOUSE_JIGGLYPUFF_DOLL" },
      { 125, "FLAG_HIDE_LORELEIS_HOUSE_NIDORAN_M_DOLL" },
      { 150, "FLAG_HIDE_LORELEIS_HOUSE_FEAROW_DOLL" },
      { 175, "FLAG_HIDE_LORELEIS_HOUSE_PIDGEOT_DOLL" },
      { 200, "FLAG_HIDE_LORELEIS_HOUSE_LAPRAS_DOLL" },
    }
    for _, d in ipairs(dolls) do
      if n >= d[1] then F.setFlag(store, ctx, d[2], false) end
    end
    return false
  end,
}

Events.HANDLERS[Std.SPECIAL.SetPostgameFlagsUnusedSlot] =
  Events.HANDLERS[Std.SPECIAL.SetPostgameFlags]

-- pokefirered/include/constants/global.h
local DIR_BY_NAME = { down = 1, up = 2, left = 3, right = 4 }
local WALKAWAY_ORDER = { "up", "down", "left", "right" }

-- pokefirered/src/field_control_avatar.c:301, overworld.c:1402, data/event_scripts.s:1166
function Events.pollWalkaway(vm, input)
  if not vm or not vm.ctx then return end
  local ctx = vm.ctx
  local session = sessionOf(ctx)

  local function clearWalkaway()
    ctx.walkAwayFromSignInhibitTimer = nil
    ctx.msgBoxIsCancelable = nil
    ctx.canWalkAway = nil
    if session then
      session.walkAwayFromSignInhibitTimer = nil
      session.msgBoxIsCancelable = nil
      session.canWalkAway = nil
    end
  end

  -- script.c:349
  if not (vm.isRunning and vm:isRunning()) then
    if ctx.walkAwayFromSignInhibitTimer ~= nil
      or ctx.msgBoxIsCancelable ~= nil
      or ctx.canWalkAway ~= nil then
      clearWalkaway()
    end
    return
  end

  local timer = tonumber(ctx.walkAwayFromSignInhibitTimer)
  if not timer then return end
  if timer > 0 then
    ctx.walkAwayFromSignInhibitTimer = timer - 1
    if session then
      session.walkAwayFromSignInhibitTimer = math.max(0, timer - 1)
    end
    return
  end

  local cancelable = ctx.msgBoxIsCancelable
  local canWalk = ctx.canWalkAway
  if session then
    if cancelable == nil then cancelable = session.msgBoxIsCancelable end
    if canWalk == nil then canWalk = session.canWalkAway end
  end
  if cancelable ~= true then return end
  if ctx.messageOpen ~= true then return end

  local dir
  if input and input.isDown then
    -- pokefirered/src/field_control_avatar.c:147
    for _, d in ipairs(WALKAWAY_ORDER) do
      if input:isDown(d) then
        dir = d
        break
      end
    end
  end
  local facing = ctx.specialVars and tonumber(ctx.specialVars[VAR_FACING])
  if not facing then
    local P = package.loaded["src.core.game3.player"]
    facing = P and DIR_BY_NAME[P.facing] or nil
  end
  local walked = dir and facing and facing ~= DIR_BY_NAME[dir]
  -- pokefirered/src/field_control_avatar.c:311
  if walked and canWalk ~= true then return end
  -- pokefirered/src/field_control_avatar.c:324
  local started = not walked and input and input.wasPressed and input:wasPressed("start")
  if not walked and not started then return end

  -- data/event_scripts.s:1166
  if vm.adapters and vm.adapters.closeMessage then
    vm.adapters.closeMessage()
  end
  ctx.messageOpen = false
  if ctx.frozen then
    local okF, Field = pcall(require, "src.core.game3.field")
    if okF and Field and Field.unlock then Field.unlock() end
  end
  clearWalkaway()
  -- pokefirered/src/script.c:353
  local HudW = package.loaded["src.ui.game3.hud"]
  if HudW and HudW.clearWaitButton then HudW.clearWaitButton() end
  vm:halt(true)
  if started then
    -- pokefirered/src/field_control_avatar.c:329
    local Runtime = package.loaded["src.core.game3.runtime"]
    if Runtime and Runtime.defer then
      Runtime.defer(function()
        local Hud = package.loaded["src.ui.game3.hud"]
        local Field = package.loaded["src.core.game3.field"]
        if Hud and Hud.openStartMenu and Field then
          Hud.openStartMenu(Field._game, Field._session)
        end
      end)
    end
  end
end

return Events
