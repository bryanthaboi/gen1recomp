local Std = require("src.core.game3.scripting.stdscripts")

local Cutscene = {}

local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321

local SE_M_WING_ATTACK = 150 -- pokefirered/include/constants/songs.h:155
local SE_SS_ANNE_HORN = 249 -- pokefirered/include/constants/songs.h:255

local SPECIES_KABUTOPS = 141 -- pokefirered/src/script_menu.c:1165
local SPECIES_AERODACTYL = 142 -- pokefirered/src/script_menu.c:1171

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

Cutscene.HANDLERS = {
  -- pokefirered/src/field_specials.c:318
  [Std.SPECIAL.SpawnCameraObject] = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.spawn then
      pcall(CameraObject.spawn, currentGame())
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:325
  [Std.SPECIAL.RemoveCameraObject] = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.remove then
      pcall(CameraObject.remove, currentGame())
    end
    return false
  end,
  -- src/special_field_anim.c:223-265, include/constants/metatile_labels.h:177-186
  [Std.SPECIAL.AnimateTeleporterHousing] = function(ctx)
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
    local timer, state = 0, 0
    Task.spawn(function()
      if timer == 0 then
        if state % 2 == 0 then
          Field.setMetatile(x, y, 0x2B5, true)
          Field.setMetatile(x, y + 2, 0x2B7, true)
        else
          Field.setMetatile(x, y, 0x2B6, true)
          Field.setMetatile(x, y + 2, 0x2B8, true)
        end
      end
      timer = timer + 1
      if timer ~= 16 then return false end
      timer = 0
      state = state + 1
      if state ~= 13 then return false end
      Field.setMetatile(x, y, 0x28A, true)
      Field.setMetatile(x, y + 2, 0x296, true)
      return true
    end)
    return false
  end,
  -- src/special_field_anim.c:285-330
  [Std.SPECIAL.AnimateTeleporterCable] = function()
    local P = package.loaded["src.core.game3.player"]
      or require("src.core.game3.player")
    local okF, Field = pcall(require, "src.core.game3.field")
    local okT, Task = pcall(require, "src.core.game3.task")
    if not (okF and Field and Field.setMetatile and okT and Task and Task.spawn) then
      return false
    end
    local x = (tonumber(P.cellX) or 0) + 4
    local y = (tonumber(P.cellY) or 0) - 5
    local timer, state = 0, 0
    Task.spawn(function()
      if timer == 0 then
        if state ~= 0 then
          Field.setMetatile(x, y, 0x285, true)
          Field.setMetatile(x, y + 1, 0x2B4, true)
          if state == 4 then return true end
          x = x - 1
        end
        Field.setMetatile(x, y, 0x2B9, true)
        Field.setMetatile(x, y + 1, 0x2BA, true)
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
  [Std.SPECIAL.DoCredits] = function()
    return false
  end,

  -- pokefirered/src/field_specials.c:90, diploma.c:100, data/maps/CeladonCity_Condominiums_3F/scripts.inc:34, engine/events/diploma.asm
  [Std.SPECIAL.ShowDiploma] = function()
    return false
  end,

  -- pokefirered/src/ss_anne.c:82, data/maps/SSAnne_Exterior/scripts.inc:21
  [Std.SPECIAL.DoSSAnneDepartureCutscene] = function(ctx, adapters)
    playSe(adapters, SE_SS_ANNE_HORN)
    return false
  end,

  -- pokefirered/src/field_specials.c:2133, data/scripts/pokemon_league.inc:63
  [Std.SPECIAL.DoPokemonLeagueLightingEffect] = function()
    return false
  end,

  -- pokefirered/src/field_specials.c:2535, NavelRock_Summit/scripts.inc:39-41
  [Std.SPECIAL.LoopWingFlapSound] = function(ctx, adapters)
    local loops = varGet(ctx, VAR_0x8004)
    local delay = varGet(ctx, VAR_0x8005)
    playSe(adapters, SE_M_WING_ATTACK)
    if loops > 0 and delay > 0 then
      local okT, Task = pcall(require, "src.core.game3.task")
      if okT and Task and Task.spawn then
        local ticks, count = 0, 0
        Task.spawn(function()
          ticks = ticks + 1
          if ticks >= delay then
            ticks = 0
            count = count + 1
            playSe(adapters, SE_M_WING_ATTACK)
          end
          -- field_specials.c:2553, field_specials.c:2546-2554
          return count >= loops - 1
        end)
      end
    end
    return false
  end,

  -- pokefirered/src/script_menu.c:1151, scripts.inc:170-187, script_menu.c:1165-1176
  [Std.SPECIAL.OpenMuseumFossilPic] = function(ctx)
    local species = varGet(ctx, VAR_0x8004)
    if species ~= SPECIES_KABUTOPS and species ~= SPECIES_AERODACTYL then
      return false
    end
    if ctx then
      ctx.museumFossilPic = {
        species = species,
        x = varGet(ctx, VAR_0x8005),
        y = varGet(ctx, VAR_0x8006),
      }
    end
    return false
  end,

  -- pokefirered/src/script_menu.c:1184
  [Std.SPECIAL.CloseMuseumFossilPic] = function(ctx)
    if ctx then ctx.museumFossilPic = nil end
    return false
  end,
}

return Cutscene
