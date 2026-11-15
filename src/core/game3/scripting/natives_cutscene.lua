local Std = require("src.core.game3.scripting.stdscripts")

local Cutscene = {}

local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321

local SE = require("src.core.game3.se_ids") -- pokefirered/include/constants/songs.h:155

local SPECIES_KABUTOPS = 141 -- pokefirered/src/script_menu.c:1165
local SPECIES_AERODACTYL = 142 -- pokefirered/src/script_menu.c:1171

local function metatile(name)
  return require("src.core.game3.constants").active():require("metatile_labels", name)
end

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

local function playSe(adapters, id)
  if adapters and adapters.playSe then
    adapters.playSe(id, false)
    return
  end
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function currentGame()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt._game or nil
end

local function cameraObject()
  local ok, CameraObject = pcall(require, "src.core.game3.camera_object")
  if ok and type(CameraObject) == "table" then return CameraObject end
  return nil
end

Cutscene.BY_NAME = {
  -- pokefirered/src/field_specials.c:318
  SpawnCameraObject = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.spawn then
      pcall(CameraObject.spawn, currentGame())
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:325
  RemoveCameraObject = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.remove then
      pcall(CameraObject.remove, currentGame())
    end
    return false
  end,
  -- pokefirered/src/special_field_anim.c:223-283
  AnimateTeleporterHousing = function(ctx)
    local P = package.loaded["src.core.game3.player"]
      or require("src.core.game3.player")
    local okF, Field = pcall(require, "src.core.game3.field")
    local okT, Task = pcall(require, "src.core.game3.task")
    if not (okF and Field and Field.setMetatile and okT and Task and Task.spawn) then
      return false
    end
    local x = tonumber(P.cellX) or 0
    local y = (tonumber(P.cellY) or 0) - 5
    if varGet(ctx, VAR_0x8004) == 0 then x = x + 6 else x = x - 1 end
    local lightYellow = metatile("METATILE_SeaCottage_Teleporter_Light_Yellow")
    local doorHalf = metatile("METATILE_SeaCottage_Teleporter_Door_HalfGlowing")
    local lightRed = metatile("METATILE_SeaCottage_Teleporter_Light_Red")
    local doorFull = metatile("METATILE_SeaCottage_Teleporter_Door_FullGlowing")
    local lightGreen = metatile("METATILE_SeaCottage_Teleporter_Light_Green")
    local door = metatile("METATILE_SeaCottage_Teleporter_Door")
    local timer, state = 0, 0
    Task.spawn(function()
      if timer == 0 then
        if state % 2 == 0 then
          Field.setMetatile(x, y, lightYellow, true)
          Field.setMetatile(x, y + 2, doorHalf, true)
        else
          Field.setMetatile(x, y, lightRed, true)
          Field.setMetatile(x, y + 2, doorFull, true)
        end
      end
      timer = timer + 1
      if timer ~= 16 then return false end
      timer = 0
      state = state + 1
      if state ~= 13 then return false end
      Field.setMetatile(x, y, lightGreen, true)
      Field.setMetatile(x, y + 2, door, true)
      return true
    end)
    return false
  end,
  -- pokefirered/src/special_field_anim.c:285-336
  AnimateTeleporterCable = function()
    local P = package.loaded["src.core.game3.player"]
      or require("src.core.game3.player")
    local okF, Field = pcall(require, "src.core.game3.field")
    local okT, Task = pcall(require, "src.core.game3.task")
    if not (okF and Field and Field.setMetatile and okT and Task and Task.spawn) then
      return false
    end
    local x = (tonumber(P.cellX) or 0) + 4
    local y = (tonumber(P.cellY) or 0) - 5
    local cableTop = metatile("METATILE_SeaCottage_Teleporter_Cable_Top")
    local cableBottom = metatile("METATILE_SeaCottage_Teleporter_Cable_Bottom")
    local ballTop = metatile("METATILE_SeaCottage_Teleporter_CableBall_Top")
    local ballBottom = metatile("METATILE_SeaCottage_Teleporter_CableBall_Bottom")
    local timer, state = 0, 0
    Task.spawn(function()
      if timer == 0 then
        if state ~= 0 then
          Field.setMetatile(x, y, cableTop, true)
          Field.setMetatile(x, y + 1, cableBottom, true)
          if state == 4 then return true end
          x = x - 1
        end
        Field.setMetatile(x, y, ballTop, true)
        Field.setMetatile(x, y + 1, ballBottom, true)
      end
      timer = timer + 1
      if timer == 4 then
        timer = 0
        state = state + 1
      end
      return false
    end)
    return false
  end,

  -- pokefirered/src/credits.c:711, data/maps/IndigoPlateau_Exterior/scripts.inc:80
  DoCredits = function(ctx)
    local ok, Credits = pcall(require, "src.ui.game3.credits")
    if not (ok and ctx) then return false end
    local okStart, started = pcall(Credits.start)
    if okStart and started then
      require("src.core.game3.scripting.natives").awaitState(ctx, function() return false end)
    end
    return false
  end,

  -- pokefirered/src/field_specials.c:90, src/diploma.c:100, data/maps/CeladonCity_Condominiums_3F/scripts.inc:34
  ShowDiploma = function(ctx)
    local ok, Diploma = pcall(require, "src.ui.game3.diploma")
    if not (ok and ctx) then return false end
    local done = false
    local okShow, shown = pcall(Diploma.show, { onDone = function() done = true end })
    if okShow and shown then
      require("src.core.game3.scripting.natives").awaitState(ctx, function() return done end)
    end
    return false
  end,

  -- pokefirered/src/field_specials.c:2133, data/scripts/pokemon_league.inc:63
  DoPokemonLeagueLightingEffect = function()
    local Space = package.loaded["src.core.game3.scripting.space"]
    pcall(require("src.core.game3.league_lighting").start, Space and Space.mapId)
    return false
  end,

  -- pokefirered/src/field_specials.c:2535, NavelRock_Summit/scripts.inc:39-41
  LoopWingFlapSound = function(ctx, adapters)
    local loops = varGet(ctx, VAR_0x8004)
    local delay = varGet(ctx, VAR_0x8005)
    playSe(adapters, SE.SE_M_WING_ATTACK)
    if loops > 0 and delay > 0 then
      local okT, Task = pcall(require, "src.core.game3.task")
      if okT and Task and Task.spawn then
        local ticks, count = 0, 0
        Task.spawn(function()
          ticks = ticks + 1
          if ticks >= delay then
            ticks = 0
            count = count + 1
            playSe(adapters, SE.SE_M_WING_ATTACK)
          end
          -- field_specials.c:2553, field_specials.c:2546-2554
          return count >= loops - 1
        end)
      end
    end
    return false
  end,

  -- pokefirered/src/script_menu.c:1151, scripts.inc:170-187, script_menu.c:1165-1176
  OpenMuseumFossilPic = function(ctx)
    local species = varGet(ctx, VAR_0x8004)
    if species ~= SPECIES_KABUTOPS and species ~= SPECIES_AERODACTYL then
      return false
    end
    if ctx then
      require("src.ui.game3.museum_fossil_pic").show(ctx, species,
        varGet(ctx, VAR_0x8005), varGet(ctx, VAR_0x8006))
    end
    return false
  end,

  -- pokefirered/src/script_menu.c:1184
  CloseMuseumFossilPic = function(ctx)
    if ctx then require("src.ui.game3.museum_fossil_pic").hide(ctx) end
    return false
  end,
  -- pokefirered/src/ss_anne.c:82 DoSSAnneDepartureCutscene
  DoSSAnneDepartureCutscene = function(ctx, adapters)
    local SSAnne = require("src.core.game3.ss_anne_cutscene")
    local Natives = require("src.core.game3.scripting.natives")
    Natives.awaitState(ctx, SSAnne.start(ctx, adapters))
    return false
  end,
}
Std.legacyHandlers(Cutscene)

return Cutscene
