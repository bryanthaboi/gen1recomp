-- Warp / door / fade sequencing helpers for game3 field.

local ModRuntime = require("src.mods.Runtime")

local Warp = {}

Warp._pending = nil
Warp._busy = false

function Warp.isBusy()
  return Warp._busy == true
end

local function sameDestination(map, x, y) return map, x, y end

local function announce(game, destMap, destX, destY, kind)
  local Map = package.loaded["src.core.game3.map"]
  local fromMap = Map and Map.current
  local warp = { kind = kind, map = destMap, x = destX, y = destY }
  if ModRuntime.wantsHook("warp.destination") then
    local m, nx, ny = ModRuntime.call("warp.destination", sameDestination, destMap, destX, destY,
      { warp = warp, lastMap = fromMap, data = game and game.data })
    if m then
      destMap, destX, destY = m, tonumber(nx) or destX, tonumber(ny) or destY
    end
  end
  if ModRuntime.wants("player.warped") then
    ModRuntime.emit("player.warped", { fromMap = fromMap, toMap = destMap,
      x = destX, y = destY, warp = warp })
  end
  return destMap, destX, destY
end

--- WarpFadeOutScreen / WarpFadeInScreen (pokefirered/src/field_fadetransition.c:95
--- and :54). Every warp-out in pret routes through WarpFadeOutScreen, so the
--- colour rule is shared: a changed map section whose destination owns a cave
--- preview screen forces black, otherwise MapTransitionIsEnter decides, which is
--- true only when a warp drops the player into a MAP_TYPE_UNDERGROUND map from
--- somewhere above ground (fldeff_flash.c sTransitionTypes). The fade-in mirrors
--- it with MapTransitionIsExit, true only when leaving MAP_TYPE_UNDERGROUND.
--- Fade is passed in because warp.lua loads src.ui.game3.fade lazily per sequence.
local MAP_TYPE_UNDERGROUND = 4

local function sectionAndType(game, mapId)
  local def = game and game.data and game.data.maps and game.data.maps[mapId]
  if not def then return nil, 0 end
  return tonumber(def.regionMapSectionId), tonumber(def.mapType) or 0
end

local function warpFadeModes(Fade, game, destMap)
  local MODE = (Fade and Fade.MODE) or {}
  local toBlack, toWhite = MODE.TO_BLACK or 1, MODE.TO_WHITE or 3
  local fromBlack, fromWhite = MODE.FROM_BLACK or 0, MODE.FROM_WHITE or 2
  local Map = package.loaded["src.core.game3.map"]
  local fromSec, fromType = sectionAndType(game, Map and Map.current)
  local toSec, toType = sectionAndType(game, destMap)
  if fromSec and toSec and fromSec ~= toSec then
    local ok, MapPreviewScreen = pcall(require, "src.ui.game3.map_preview_screen")
    if ok and MapPreviewScreen and MapPreviewScreen.has then
      local okT, MapPreviewExtract = pcall(require, "src.import.gba.map_preview_extract")
      if okT and MapPreviewExtract and MapPreviewScreen.has(toSec, MapPreviewExtract.TYPE_CAVE) then
        return toBlack, fromBlack
      end
    end
  end
  local enter = fromType ~= toType and toType == MAP_TYPE_UNDERGROUND
  local exit = fromType ~= toType and fromType == MAP_TYPE_UNDERGROUND
  return (enter and toWhite or toBlack), (exit and fromWhite or fromBlack)
end

--- Complete door entrance sequence (walking UP into a building)
function Warp.startDoorEntrance(mod, game, destMap, destX, destY, doorX, doorY)
  if Warp._busy then return false end
  destMap, destX, destY = announce(game, destMap, destX, destY, "door")
  Warp._busy = true

  local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
  if Field and Field.lock then Field.lock() end

  local Doors = require("src.core.game3.doors")
  local Player = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local Fade = require("src.ui.game3.fade")
  local curMap = (game and game.currentMap) or destMap
  local sound = Doors.getSoundForWarp(curMap, doorX, doorY, destMap, true)
  local toMode, fromMode = warpFadeModes(Fade, game, destMap)

  -- Step 1: Animate door open (Frame 0 -> 1 -> 2)
  Doors.open(curMap, doorX, doorY, { sound = sound, destMap = destMap }, function()
    -- Step 2: Door is fully open. Walk player 1 step UP into the doorway.
    Player.forceStep("up", function()
      -- Step 3: Player arrived at (doorX, doorY). Immediately hide player sprite!
      Player.setVisible(false)

      -- Step 4: Short beat, then door animates closed (Frame 2 -> 1 -> 0)
      Doors.closeAfterDelay(curMap, doorX, doorY, 8, { sound = sound, playSound = false }, function()
        -- Step 5: Screen fades to black
        Fade.begin(toMode, 1, function()
          -- Step 6: Inside black, load the indoor map
          local Map = require("src.core.game3.map")
          Map.load(mod, game, destMap, {
            x = destX,
            y = destY,
            facing = "up",
            depth1Connections = true,
          })
          Player.setVisible(true)
          Doors.reset()

          -- Step 7: Fade screen back in from black inside the building
          Fade.begin(fromMode, 1, function()
            Warp._busy = false
            if Field and Field.unlock and not (package.loaded["src.core.game3.scripting.space"]
                and package.loaded["src.core.game3.scripting.space"].vm
                and package.loaded["src.core.game3.scripting.space"].vm.isRunning
                and package.loaded["src.core.game3.scripting.space"].vm:isRunning()) then
              Field.unlock()
            end
          end)
        end)
      end)
    end)
  end)
  return true
end

--- Complete door exit sequence (walking DOWN off exit mat out to town)
function Warp.startDoorExit(mod, game, destMap, destX, destY, exitX, exitY)
  if Warp._busy then return false end
  destMap, destX, destY = announce(game, destMap, destX, destY, "exit_door")
  Warp._busy = true

  local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
  if Field and Field.lock then Field.lock() end

  local Doors = require("src.core.game3.doors")
  local Player = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local Fade = require("src.ui.game3.fade")
  local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
  local curMap = (game and game.currentMap) or destMap
  local sound = Doors.getSoundForWarp(destMap, destX, destY, curMap, true)
  local toMode, fromMode = warpFadeModes(Fade, game, destMap)

  -- Step 1: Play exit sound (SE_EXIT)
  if Audio and Audio.playSe then
    pcall(function() Audio.playSe(Doors.SOUND_EXIT) end)
  end

  -- Step 2: Screen fades to black
  Fade.begin(toMode, 1, function()
    -- Step 3: Inside black, load the destination outdoor map at (destX, destY) facing down
    local Map = require("src.core.game3.map")
    Map.load(mod, game, destMap, {
      x = destX,
      y = destY,
      facing = "down",
      depth1Connections = true,
    })
    Player.setVisible(true)
    -- Outdoor door is held fully open (Frame 2)
    Doors.holdOpen(destMap, destX, destY, { destMap = curMap })

    -- Step 4: Fade screen in from black showing player in the open doorway
    Fade.begin(fromMode, 1, function()
      -- Step 5: Force player to take 1 step DOWN out of the doorway onto (destX, destY + 1)
      Player.forceStep("down", function()
        -- Step 6: Player landed on (destX, destY + 1). Short beat, then door closes behind them!
        Doors.closeAfterDelay(destMap, destX, destY, 8, { sound = sound, playSound = false }, function()
          Warp._busy = false
          if Field and Field.unlock and not (package.loaded["src.core.game3.scripting.space"]
              and package.loaded["src.core.game3.scripting.space"].vm
              and package.loaded["src.core.game3.scripting.space"].vm.isRunning
              and package.loaded["src.core.game3.scripting.space"].vm:isRunning()) then
            Field.unlock()
          end
        end)
      end)
    end)
  end)
  return true
end

--- Complete escalator warp sequence (PokéCenter 2F, Celadon Dept Store)
function Warp.isEscalatorActive()
  return Warp._isEscalatorActive and true or false
end

function Warp.startEscalator(mod, game, destMap, destX, destY, dir, approachDir, escX, escY)
  if Warp._busy then return false end
  destMap, destX, destY = announce(game, destMap, destX, destY, "escalator")
  Warp._busy = true
  Warp._isEscalatorActive = true

  local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
  if Field and Field.lock then Field.lock() end

  local Player = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local Fade = require("src.ui.game3.fade")
  local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local Map = require("src.core.game3.map")
  local Task = require("src.core.game3.task")
  local SpecialAnim = require("src.core.game3.special_field_anim")

  local goingUp = (dir ~= "down")
  local toMode, fromMode = warpFadeModes(Fade, game, destMap)

  -- GBA pret trig offsets for escalator (field_effect.c)
  local function getOffsets(amp, isGoingUp, isLanding)
    local x = -amp
    local y = 0
    if isGoingUp then
      if not isLanding then
        -- Going UP departing (1F): moves left & UP into ceiling (0 -> -8)
        y = -math.floor(amp * 8 / 16)
      else
        -- Going UP arriving (2F): starts below floor (+8) and glides right & UP into floor (+8 -> 0)
        y = math.floor(amp * 8 / 16)
      end
    else
      if not isLanding then
        -- Going DOWN departing (2F): moves left & DOWN into lower floor (0 -> +8)
        y = math.floor(amp * 8 / 16)
      else
        -- Going DOWN arriving (1F): starts above floor (-8) and glides right & DOWN into floor (-8 -> 0)
        y = -math.floor(amp * 8 / 16)
      end
    end
    return x, y
  end

  local function doWarpIn()
    -- Destination map loaded at (destX, destY)
    Player.facing = "right"
    Player.setVisible(true)

    -- Initial position: 16px to the left on destination escalator
    local initX, initY = getOffsets(16, goingUp, true)
    Player.spriteXOffset = initX
    Player.spriteYOffset = initY

    local destLayout = Map._def and Map._def.midLayout
    SpecialAnim.startEscalator(destLayout, destX, destY, goingUp)

    Fade.begin(fromMode, 1, function() end)

    Task.spawn(function(t)
      -- 16 amp steps over 32 frames (every 2 frames advances 1 amp)
      local amp = math.max(0, 16 - math.floor(t.frames / 2))
      local xOff, yOff = getOffsets(amp, goingUp, true)
      Player.spriteXOffset = xOff
      Player.spriteYOffset = yOff

      if amp <= 0 then
        Player.spriteXOffset = 0
        Player.spriteYOffset = 0
        SpecialAnim.stopEscalator()

        -- In FRLG: Player takes 1 normal walk step EAST (DIR_EAST) off the escalator
        Player.forceStep("right", function()
          Warp._busy = false
          Warp._isEscalatorActive = false
          if Field and Field.unlock and not (package.loaded["src.core.game3.scripting.space"]
              and package.loaded["src.core.game3.scripting.space"].vm
              and package.loaded["src.core.game3.scripting.space"].vm.isRunning
              and package.loaded["src.core.game3.scripting.space"].vm:isRunning()) then
            Field.unlock()
          end
        end)
        return true
      end
      return false
    end)
  end

  local function doRideAndTransition()
    if Audio and Audio.playSe then
      pcall(function() Audio.playSe(SE.SE_ESCALATOR or 73) end)
    end

    -- Keep current facing while riding out
    Player.facing = approachDir or "left"

    local curLayout = Map._def and Map._def.midLayout
    SpecialAnim.startEscalator(curLayout, Player.cellX, Player.cellY, goingUp)

    local fadeStarted = false
    local fadeDone = false

    Task.spawn(function(t)
      -- 16 amp steps over 32 frames (every 2 frames advances 1 amp)
      local amp = math.min(16, math.floor(t.frames / 2))
      local xOff, yOff = getOffsets(amp, goingUp, false)
      Player.spriteXOffset = xOff
      Player.spriteYOffset = yOff

      -- In FRLG: when task->data[2] > 3 (after ~8 frames), begin fade out
      if t.frames >= 8 and not fadeStarted then
        fadeStarted = true
        Fade.begin(toMode, 1, function()
          fadeDone = true
        end)
      end

      if amp >= 16 and fadeDone then
        SpecialAnim.stopEscalator()
        Player.spriteXOffset = 0
        Player.spriteYOffset = 0

        Map.load(mod, game, destMap, {
          x = destX,
          y = destY,
          facing = "right",
          depth1Connections = true,
        })

        doWarpIn()
        return true
      end
      return false
    end)
  end

  -- If player is standing adjacent to the escalator, step onto it first
  if approachDir and (Player.cellX ~= escX or Player.cellY ~= escY) then
    Player.forceStep(approachDir, function()
      doRideAndTransition()
    end)
  else
    doRideAndTransition()
  end

  return true
end

-- pokefirered/src/field_fadetransition.c:794
function Warp.startStairWarp(mod, game, destMap, destX, destY, behavior)
  if Warp._busy then return false end
  destMap, destX, destY = announce(game, destMap, destX, destY, "stairs")
  Warp._busy = true

  local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
  if Field and Field.lock then Field.lock() end

  local Collision = require("src.core.game3.collision")
  local Player = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local Fade = require("src.ui.game3.fade")
  local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local Map = require("src.core.game3.map")
  local Task = require("src.core.game3.task")
  local toMode, fromMode = warpFadeModes(Fade, game, destMap)

  local function finish()
    Warp._busy = false
    if Field and Field.unlock and not (package.loaded["src.core.game3.scripting.space"]
        and package.loaded["src.core.game3.scripting.space"].vm
        and package.loaded["src.core.game3.scripting.space"].vm.isRunning
        and package.loaded["src.core.game3.scripting.space"].vm:isRunning()) then
      Field.unlock()
    end
  end

  -- pokefirered/src/field_fadetransition.c:922
  local function exitStairs()
    local destBeh = Collision.behavior(destX, destY)
    local facing = Collision.stairArrivalFacing(destBeh)
    if facing then
      Player.facing = facing
      Player.syncSavePosition(game)
    end
    local speedX, speedY = Collision.stairSpeeds(destBeh)
    local offX, offY = speedX * 16, speedY * 16
    local timer = 16
    speedX, speedY = -speedX, -speedY
    Player.walkInPlace = true
    Player.walkInPlaceFast = true
    Player.spriteXOffset = math.floor(offX / 32)
    Player.spriteYOffset = math.floor(offY / 32)

    Fade.begin(fromMode, 1, function() end)

    Task.spawn(function()
      if timer > 0 then
        offX = offX + speedX
        offY = offY + speedY
        Player.spriteXOffset = math.floor(offX / 32)
        Player.spriteYOffset = math.floor(offY / 32)
        timer = timer - 1
        return false
      end
      Player.spriteXOffset = 0
      Player.spriteYOffset = 0
      Player.walkInPlace = false
      Player.walkInPlaceFast = false
      finish()
      return true
    end)
  end

  local speedX, speedY = Collision.stairSpeeds(behavior)
  local offX, offY, timer = 0, 0, 0
  local fadeStarted, fadeDone = false, false

  if Audio and Audio.playSe then
    pcall(function() Audio.playSe(SE.SE_EXIT or 9) end)
  end
  Player.walkInPlace = true
  Player.walkInPlaceFast = false

  -- pokefirered/src/field_fadetransition.c:846
  Task.spawn(function()
    if speedY > 0 or timer > 6 then offY = offY + speedY end
    offX = offX + speedX
    timer = timer + 1
    Player.spriteXOffset = math.floor(offX / 32)
    Player.spriteYOffset = math.floor(offY / 32)

    if timer >= 12 and not fadeStarted then
      fadeStarted = true
      Fade.begin(toMode, 1, function() fadeDone = true end)
    end

    if fadeDone then
      Player.spriteXOffset = 0
      Player.spriteYOffset = 0
      Player.walkInPlace = false
      Map.load(mod, game, destMap, {
        x = destX,
        y = destY,
        facing = Player.facing,
        depth1Connections = true,
      })
      Player.setVisible(true)
      exitStairs()
      return true
    end
    return false
  end)

  return true
end

--- Complete teleport spin sequence (Silph Co, Sabrina's Gym warp pads)
function Warp.startTeleport(mod, game, destMap, destX, destY)
  if Warp._busy then return false end
  destMap, destX, destY = announce(game, destMap, destX, destY, "teleport")
  Warp._busy = true

  local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
  if Field and Field.lock then Field.lock() end

  local Player = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local Fade = require("src.ui.game3.fade")
  local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")

  if Audio and Audio.playSe then
    pcall(function() Audio.playSe(SE.SE_WARP_IN or 39) end)
  end

  local toMode, fromMode = warpFadeModes(Fade, game, destMap)

  Fade.begin(toMode, 1, function()
    local Map = require("src.core.game3.map")
    Map.load(mod, game, destMap, {
      x = destX,
      y = destY,
      facing = "down",
      depth1Connections = true,
    })
    Player.setVisible(true)

    if Audio and Audio.playSe then
      pcall(function() Audio.playSe(SE.SE_WARP_OUT or 40) end)
    end

    Fade.begin(fromMode, 1, function()
      Warp._busy = false
      if Field and Field.unlock and not (package.loaded["src.core.game3.scripting.space"]
          and package.loaded["src.core.game3.scripting.space"].vm
          and package.loaded["src.core.game3.scripting.space"].vm.isRunning
          and package.loaded["src.core.game3.scripting.space"].vm:isRunning()) then
        Field.unlock()
      end
    end)
  end)
  return true
end

--- Complete fall hole sequence (Mt. Moon, Seafoam drop holes)
function Warp.startFall(mod, game, destMap, destX, destY)
  if Warp._busy then return false end
  destMap, destX, destY = announce(game, destMap, destX, destY, "fall")
  Warp._busy = true

  local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
  if Field and Field.lock then Field.lock() end

  local Player = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local Fade = require("src.ui.game3.fade")
  local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")

  if Audio and Audio.playSe then
    pcall(function() Audio.playSe(SE.SE_FALL or 37) end)
  end

  local toMode, fromMode = warpFadeModes(Fade, game, destMap)

  Fade.begin(toMode, 1, function()
    local Map = require("src.core.game3.map")
    Map.load(mod, game, destMap, {
      x = destX,
      y = destY,
      facing = "down",
      depth1Connections = true,
    })
    Player.setVisible(true)

    if Audio and Audio.playSe then
      pcall(function() Audio.playSe(SE.SE_LEDGE or 10) end)
    end

    Fade.begin(fromMode, 1, function()
      Warp._busy = false
      if Field and Field.unlock and not (package.loaded["src.core.game3.scripting.space"]
          and package.loaded["src.core.game3.scripting.space"].vm
          and package.loaded["src.core.game3.scripting.space"].vm.isRunning
          and package.loaded["src.core.game3.scripting.space"].vm:isRunning()) then
        Field.unlock()
      end
    end)
  end)
  return true
end

function Warp.request(mod, game, mapId, x, y, facing, opts)
  opts = opts or {}
  if Warp._busy then return nil, "warp busy" end

  if opts.door then
    return Warp.startDoorEntrance(mod, game, mapId, x, y, opts.doorX or x, opts.doorY or y)
  end
  if opts.exitDoor then
    return Warp.startDoorExit(mod, game, mapId, x, y, opts.doorX or x, opts.doorY or y)
  end
  if opts.escalator then
    return Warp.startEscalator(mod, game, mapId, x, y, opts.escalatorDir or "up", opts.approachDir, opts.escX, opts.escY)
  end
  if opts.teleport then
    return Warp.startTeleport(mod, game, mapId, x, y)
  end
  if opts.fall then
    return Warp.startFall(mod, game, mapId, x, y)
  end
  mapId, x, y = announce(game, mapId, x, y, "warp")

  Warp._pending = {
    mapId = mapId,
    x = x,
    y = y,
    facing = facing or "down",
    fade = opts.fade ~= false,
  }

  local Doors = require("src.core.game3.doors")
  local Player = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local curMap = (game and game.currentMap) or mapId
  local sound = opts.se or Doors.getSoundForWarp(curMap, x, y, mapId, false)

  local function doLoad()
    local Map = require("src.core.game3.map")
    local result = Map.load(mod, game, mapId, {
      x = x,
      y = y,
      facing = facing or "down",
      depth1Connections = true,
    })
    Warp._pending = nil
    if Player and Player.setVisible then
      Player.setVisible(true)
    end
    Doors.reset()
    return result
  end

  if opts.fade == false then
    if opts.se ~= false then
      local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
      if Audio and Audio.playSe then pcall(function() Audio.playSe(sound) end) end
    end
    return doLoad()
  end

  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if not (okF and Fade and Fade.begin) then
    if opts.se ~= false then
      local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
      if Audio and Audio.playSe then pcall(function() Audio.playSe(sound) end) end
    end
    return doLoad()
  end

  Warp._busy = true
  local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
  if Field and Field.lock then Field.lock() end
  local toMode, fromMode = warpFadeModes(Fade, game, mapId)

  if opts.se ~= false then
    local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
    if Audio and Audio.playSe then pcall(function() Audio.playSe(sound) end) end
  end

  Fade.begin(toMode, 1, function()
    doLoad()
    if Player and Player.setVisible then
      Player.setVisible(true)
    end
    Doors.reset()
    Fade.begin(fromMode, 1, function()
      Warp._busy = false
      if Field and Field.unlock and not (package.loaded["src.core.game3.scripting.space"]
          and package.loaded["src.core.game3.scripting.space"].vm
          and package.loaded["src.core.game3.scripting.space"].vm.isRunning
          and package.loaded["src.core.game3.scripting.space"].vm:isRunning()) then
        Field.unlock()
      end
    end)
  end)

  return true
end

function Warp.clear()
  Warp._pending = nil
  Warp._busy = false
  Warp._isEscalatorActive = false
  local Player = package.loaded["src.core.game3.player"]
  if Player and Player.setVisible then
    Player.walkInPlace = false
    Player.walkInPlaceFast = false
    Player.spriteXOffset = 0
    Player.spriteYOffset = 0
    Player.setVisible(true)
  end
end

return Warp
