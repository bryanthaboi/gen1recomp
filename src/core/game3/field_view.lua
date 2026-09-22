-- Game3 native field renderer (FRLG 240×160, 1:1 world pixels).
-- Owns tile palette blits + OW sprites. Does NOT call World:draw / Zoom / Chrome.

local Display = require("src.core.game3.display")
local Versions = require("src.import.gba.versions")
local GfxIds = require("src.core.game3.scripting.gfx_ids")

local FieldView = {}

FieldView._atlas = nil
FieldView._atlasPath = nil
FieldView._quads = {}
FieldView._tilesPerRow = 16
FieldView._blockTiles = nil
FieldView._tilePalettes = nil -- [tileId+1] = BG slot 1..8
FieldView._spriteCache = {} -- key → SpriteRenderer
FieldView._logged = false
FieldView._loggedPal = false
FieldView._nativeBatch = nil
FieldView._nativeBatches = nil
FieldView._nativeOverBatches = nil
FieldView._nativeBx = nil
FieldView._nativeBy = nil
FieldView._nativePair = nil
FieldView._nativeDirty = true
FieldView._nativeOverOx = 0
FieldView._nativeOverOy = 0
FieldView._nativeOverPair = nil
FieldView._loggedNative = false
FieldView._loggedNativeFallback = false

-- pokefirered/src/field_screen_effect.c:18
local FLASH_LEVEL_RADIUS = { [0] = 200, 72, 56, 40, 24 }
-- pokefirered/include/constants/flags.h:1333
local FLAG_SYS_FLASH_ACTIVE = 0x806

FieldView.MAX_FLASH_LEVEL = 4
FieldView.flashLevel = 0
FieldView.cameraPanX = 0
FieldView.cameraPanY = 0
FieldView._flashRadius = nil
FieldView._flashMapId = nil
FieldView._flashSpans = nil
FieldView._flashSpanR = nil
FieldView._flashSpanCX = nil
FieldView._flashSpanCY = nil
FieldView._flashSpanW = nil
FieldView._flashSpanH = nil

local CELL = 16
local BLOCK = 32

-- pokefirered/src/event_object_movement.c:4992
local PLAYER_SCREEN_X = 112
-- pokefirered/src/field_camera.c:527
local PLAYER_SCREEN_Y = 72

local function screenAnchor(px, py, camX, camY)
  return (px - camX) - PLAYER_SCREEN_X, (py - camY) - PLAYER_SCREEN_Y
end

local function log(msg)
  print("[game3/field] " .. tostring(msg))
end

local function resolveMapDef(game, mapId)
  if not mapId then return nil end
  local data = game and game.data
  return data and data.maps and data.maps[mapId]
end

local function resolveTileset(game, mapDef)
  if not mapDef then return nil end
  local tsId = mapDef.tileset
  if not tsId and mapDef.pair and Versions.PAIR_TILESET then
    tsId = Versions.PAIR_TILESET[mapDef.pair]
  end
  local data = game and game.data
  local sets = data and (data.tilesets or data.gen2Tilesets)
  return tsId and sets and sets[tsId], tsId
end

local function loadAtlas(tileset)
  if not tileset or not tileset.image then return nil end
  local path = tileset.image
  if FieldView._atlas and FieldView._atlasPath == path then
    FieldView._blockTiles = tileset.blocks
    FieldView._tilePalettes = tileset.tilePalettes
    FieldView._tilesPerRow = tileset.tilesPerRow or FieldView._tilesPerRow
    return FieldView._atlas
  end
  local img
  local ok, Assets = pcall(require, "src.render.Assets")
  if ok and Assets and Assets.image then
    local aok, aimg = pcall(Assets.image, path)
    if aok then img = aimg end
  end
  if not img then
    local iok, iimg = pcall(love.graphics.newImage, path)
    if iok then img = iimg end
  end
  if not img then
    log("atlas load failed: " .. tostring(path))
    return nil
  end
  if img.setFilter then img:setFilter("nearest", "nearest") end
  FieldView._atlas = img
  FieldView._atlasPath = path
  FieldView._quads = {}
  FieldView._tilesPerRow = tileset.tilesPerRow or 16
  FieldView._blockTiles = tileset.blocks
  FieldView._tilePalettes = tileset.tilePalettes
  if not FieldView._logged then
    log("native atlas ready path=" .. tostring(path)
      .. " tilesPerRow=" .. tostring(FieldView._tilesPerRow)
      .. " hasTilePalettes=" .. tostring(FieldView._tilePalettes ~= nil))
    FieldView._logged = true
  end
  return img
end

local function quadFor(tile)
  local q = FieldView._quads[tile]
  if q then return q end
  local atlas = FieldView._atlas
  if not atlas then return nil end
  local per = FieldView._tilesPerRow
  local sx = (tile % per) * 8
  local sy = math.floor(tile / per) * 8
  q = love.graphics.newQuad(sx, sy, 8, 8, atlas:getDimensions())
  FieldView._quads[tile] = q
  return q
end

local function blockIdAt(mapDef, bx, by)
  local w = mapDef.width or 0
  local h = mapDef.height or 0
  local blocks = mapDef.blocks
  if not blocks or w < 1 then return mapDef.borderBlock or 0 end
  if bx < 0 or by < 0 or bx >= w or by >= h then
    return mapDef.borderBlock or 0
  end
  return blocks[by * w + bx + 1] or 0
end

--- Resolve Sevii special BG palette set (8 slots × 4 RGB).
local function resolveBgSet(game, mapDef, daytime)
  local ok, Palettes = pcall(require, "src.world.gen2.Palettes")
  if not ok or not Palettes then return nil end
  local data = game and game.data
  local pals = data and (data.gen2Palettes or data.palettes)
  if not pals then return nil end
  -- Sevii uses specialTilesets[SEVII_*]; prefer specialSet (does not need bg pool).
  if Palettes.specialSet then
    local set = Palettes.specialSet(pals, mapDef)
    if set then return set end
  end
  if Palettes.bgSet then
    return Palettes.bgSet(pals, mapDef, daytime or "DAY")
  end
  return nil
end

local function currentMapId(game)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  if session and session.map then return session.map end
  local world = game and (game.overworld or game.world)
  if world and world.map and world.map.id then return world.map.id end
  local pos = game and game.save and game.save.position
  return pos and pos.map
end

local function playerPixels(game)
  -- Game3 avatar is source of truth while Runtime is active.
  local okP, G3Player = pcall(require, "src.core.game3.player")
  local Runtime = package.loaded["src.core.game3.runtime"]
  if okP and G3Player and Runtime and Runtime.isActive and Runtime.isActive() then
    local xOff = G3Player.spriteXOffset or 0
    local yOff = G3Player.spriteYOffset or 0
    if yOff == 0 and G3Player.jumpSpriteY then
      yOff = G3Player.jumpSpriteY() or 0
    end
    return G3Player.px, G3Player.py, G3Player.facing or "down",
      G3Player.walkPhase(), G3Player.drawFlip(), G3Player, yOff, xOff
  end
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local world = game and (game.overworld or game.world)
  local p = world and world.player
  if p then
    local px = tonumber(p.px)
    local py = tonumber(p.py)
    if not px then px = (tonumber(p.cellX or p.x) or 0) * CELL end
    if not py then py = (tonumber(p.cellY or p.y) or 0) * CELL end
    local facing = p.facing or "down"
    local walkPhase = 0
    if type(p.walkPhase) == "function" then
      walkPhase = p:walkPhase() or 0
    else
      walkPhase = p.movePhase or p.walkPhase or 0
    end
    local stepFlip = false
    if type(p.drawFlip) == "function" then
      stepFlip = p:drawFlip() and true or false
    else
      stepFlip = p.stepFlip and true or false
    end
    return px, py, facing, walkPhase, stepFlip, p, p.spriteYOffset or 0, p.spriteXOffset or 0
  end
  if session then
    local cx, cy = session.x or 0, session.y or 0
    return cx * CELL, cy * CELL, session.facing or "down", 0, false, nil, 0, 0
  end
  return 0, 0, "down", 0, false, nil, 0, 0
end

local function facingFromObj(obj)
  local r = tostring(obj.facing or obj.range or "DOWN"):lower()
  if r == "up" or r == "down" or r == "left" or r == "right" then
    return r
  end
  return "down"
end

local function spriteNameForObj(obj)
  if type(obj.sprite) == "string" and obj.sprite ~= "" then
    return obj.sprite
  end
  local g = obj.graphics or obj.graphicsId
  return GfxIds.spriteFor(g)
end

local function playerSpriteName(game)
  local save = game and game.save
  local session = game and game.session
  local gender = (session and session.gender)
    or (save and (save.gender or (save.player and save.player.gender)))
  if gender == "female" or gender == "F" or gender == 1 then
    return "SPRITE_KRIS"
  end
  return "SPRITE_CHRIS"
end

local function daytimeFor(game, mapDef)
  local world = game and (game.overworld or game.world)
  if world and world.daytime then return world.daytime end
  local ok, Palettes = pcall(require, "src.world.gen2.Palettes")
  if ok and Palettes and Palettes.daytimeFor and world and world.hour then
    local hour = type(world.hour) == "function" and world:hour() or 12
    return Palettes.daytimeFor(mapDef, hour, world.flashUsed)
  end
  return "DAY"
end

local function getSpriteRenderer(game, spriteName, seed, objDef, daytime)
  local palKey = tostring(daytime or "DAY")
  local key = tostring(spriteName) .. ":" .. tostring(seed) .. ":" .. palKey
  local cached = FieldView._spriteCache[key]
  if cached then return cached end

  local data = game and game.data
  local sprites = data and (data.gen2Sprites or data.sprites)
  local def = sprites and sprites[spriteName]
  if not def or not def.image then
    return nil
  end

  local ok, SpriteRenderer = pcall(require, "src.render.SpriteRenderer")
  if not ok or not SpriteRenderer then return nil end
  local sr = SpriteRenderer.new(def, seed or spriteName)

  local okP, Palettes = pcall(require, "src.world.gen2.Palettes")
  local pals = data and (data.gen2Palettes or data.palettes)
  if okP and Palettes and pals and sr.setObjPalette then
    local colors = Palettes.spritePalette(pals, daytime or "DAY", def, objDef)
    if colors then
      local id = (Palettes.objectPaletteId and Palettes.objectPaletteId(objDef))
        or def.paletteId or spriteName
      sr:setObjPalette(colors, "game3:" .. palKey .. ":" .. tostring(id))
    end
  end

  FieldView._spriteCache[key] = sr
  return sr
end

local function objectVisible(obj)
  local flag = obj.flag
  if not flag or flag == 0 then return true end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.objectVisible then
    return Space.objectVisible(obj)
  end
  return true
end

--- Prefer live host entities (animated + already palette-baked). Returns true if drawn.
local function drawWorldEntities(world, camX, camY)
  local entities = world and world.entities
  if type(entities) ~= "table" or #entities == 0 then return false end

  local PlayerMod = package.loaded["src.core.game3.player"]
  local list = {}
  for _, e in ipairs(entities) do
    local isPlayer = (world and world.player and e == world.player) or (e.isPlayer == true) or (e.id == "player")
    if isPlayer then
      if (PlayerMod and PlayerMod.isVisible and not PlayerMod.isVisible()) or (e.visible == false) or (e.hidden == true) then
        -- Skip hidden player entity
      elseif e and e.sprite then
        list[#list + 1] = e
      end
    elseif e and e.sprite and (e.visible ~= false) and (e.hidden ~= true) then
      list[#list + 1] = e
    end
  end
  if #list == 0 then return false end

  table.sort(list, function(a, b)
    local ay = a.py or ((a.cellY or 0) * CELL)
    local by = b.py or ((b.cellY or 0) * CELL)
    if ay == by then
      return tostring(a.id or "") < tostring(b.id or "")
    end
    return ay < by
  end)

  -- Ensure OBJ palettes are current (World normally does this; re-apply cheaply).
  if world.applySpritePalette then
    for _, e in ipairs(list) do
      world:applySpritePalette(e)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  for _, e in ipairs(list) do
    local px = e.px or ((e.cellX or 0) * CELL)
    local py = e.py or ((e.cellY or 0) * CELL)
    local facing = e.facing or "down"
    local phase = 0
    if type(e.walkPhase) == "function" then
      phase = e:walkPhase() or 0
    end
    local flip = e.stepFlip
    if type(e.drawFlip) == "function" then
      flip = e:drawFlip()
    end
    e.sprite:draw(px, py, camX, camY, facing, phase, flip)
  end
  return true
end

local function neighborActorDefs(mapId, def)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local ev = Space and Space.bundle and Space.bundle.events
    and Space.bundle.events[mapId]
  local defs = ev and (ev.objects or ev.objectEvents)
  if type(defs) ~= "table" then defs = def and def.objects end
  return type(defs) == "table" and defs or nil
end

local function collectNeighborActors(actors, baseIndex, hostMapId, hostDef)
  local Map = package.loaded["src.core.game3.map"]
  if not (Map and type(Map.world) == "table") then return baseIndex end
  local Ghosts = package.loaded["src.core.game3.ghosts"]
  local Objects = package.loaded["src.core.game3.objects"]
  for _, entry in ipairs(Map.world) do
    if entry.id ~= hostMapId and entry.def ~= hostDef then
      local live = Ghosts and Ghosts.forDraw and Ghosts.forDraw(entry.id)
      if live then
        for _, eo in ipairs(live) do
          baseIndex = baseIndex + 1
          actors[#actors + 1] = {
            kind = "npc",
            i = baseIndex,
            obj = eo.def,
            ghost = entry.id,
            x = (eo.px or (eo.cellX or 0) * CELL) + entry.ox * CELL,
            y = (eo.py or (eo.cellY or 0) * CELL) + entry.oy * CELL,
            facing = eo.facing or "down",
            walkPhase = Objects and Objects.walkPhase and Objects.walkPhase(eo) or 0,
            stepFlip = eo.stepFlip and true or false,
            sprite = eo.sprite or spriteNameForObj(eo.def or {}),
            graphicsId = eo.graphicsId
              or (eo.def and (eo.def.graphicsId or eo.def.graphics)),
          }
        end
      else
        local defs = neighborActorDefs(entry.id, entry.def)
        local bounds = Objects and Objects.layoutBounds
          and Objects.layoutBounds(entry.def) or nil
        if defs then
          for _, obj in ipairs(defs) do
            local ox, oy = tonumber(obj.x) or 0, tonumber(obj.y) or 0
            local out = bounds and (ox < 0 or oy < 0
              or ox >= bounds.w or oy >= bounds.h)
            if objectVisible(obj) and not out then
              baseIndex = baseIndex + 1
              actors[#actors + 1] = {
                kind = "npc",
                i = baseIndex,
                obj = obj,
                ghost = entry.id,
                x = (entry.ox + (tonumber(obj.x) or 0)) * CELL,
                y = (entry.oy + (tonumber(obj.y) or 0)) * CELL,
                facing = facingFromObj(obj),
                sprite = spriteNameForObj(obj),
                graphicsId = obj.graphicsId or obj.graphics,
              }
            end
          end
        end
      end
    end
  end
  return baseIndex
end

local function pushBillboard(x, y, camX, camY)
  local bb = FieldView._billboard
  if not bb then return false end
  local Tilt = require("src.render.Tilt")
  local fx = (x - camX) + CELL / 2
  local fy = (y - camY) + CELL
  local sx, sy = Tilt.groundPoint(fx, fy, bb.vw, bb.vh)
  love.graphics.push()
  love.graphics.translate(sx - fx, sy - fy)
  return true
end

-- pokefirered/src/event_object_movement.c:8368 sElevationToPriority
local ELEVATION_TO_PRIORITY = {
  [0] = 2, [1] = 2, [2] = 2, [3] = 2,
  [4] = 1, [5] = 2, [6] = 1, [7] = 2,
  [8] = 1, [9] = 2, [10] = 1, [11] = 2,
  [12] = 1, [13] = 0, [14] = 0, [15] = 2,
}

local function actorPriority(a)
  if a.kind == "player" then
    local PlayerMod = package.loaded["src.core.game3.player"]
    if PlayerMod and (PlayerMod.jumping or PlayerMod.surfHopping) then
      return 1
    end
    local WarpMod = package.loaded["src.core.game3.warp"]
    if WarpMod and WarpMod.isEscalatorActive and WarpMod.isEscalatorActive() then
      return 1
    end
    local SpecialAnim = package.loaded["src.core.game3.special_field_anim"]
    if SpecialAnim and SpecialAnim.isActive and SpecialAnim.isActive() then
      return 1
    end
    local elev = a.elevation or (PlayerMod and PlayerMod.elevation) or 3
    return ELEVATION_TO_PRIORITY[elev] or 2
  else
    local elev = a.elevation or (a.obj and (a.obj.elevation or (a.obj.def and a.obj.def.elevation))) or 3
    return ELEVATION_TO_PRIORITY[elev] or 2
  end
end

local function drawSingleActor(game, mapDef, a, camX, camY)
  local daytime = daytimeFor(game, mapDef)
  local okOw, OwSprites = pcall(require, "src.core.game3.ow_sprites")
  local useOw = okOw and OwSprites and OwSprites.ready and OwSprites.ready()
  love.graphics.setColor(1, 1, 1, 1)
  local billboarded = pushBillboard(a.x, a.y, camX, camY)
  local drew = false
  if useOw and a.graphicsId ~= nil then
    local opts = {
      bow = a.bow,
      fieldMove = a.fieldMove,
      frame = a.frame,
    }
    drew = OwSprites.draw(
      a.graphicsId, a.x, a.y, camX, camY, a.facing, a.walkPhase, a.stepFlip, opts)
  end
  if not drew then
    local sr = getSpriteRenderer(
      game, a.sprite, a.kind .. ":" .. tostring(a.i or "p"), a.obj, daytime)
    if sr then
      sr:draw(a.x, a.y, camX, camY, a.facing, a.walkPhase or 0, a.stepFlip)
    else
      local sx, sy = a.x - camX, a.y - camY
      if a.kind == "player" then
        love.graphics.setColor(0.95, 0.25, 0.25, 1)
      else
        love.graphics.setColor(0.3, 0.55, 0.95, 1)
      end
      love.graphics.rectangle("fill", sx + 4, sy + 2, 8, 12)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  if billboarded then love.graphics.pop() end
end

local function collectGame3Actors(game, mapDef, camX, camY, px, py, facing, walkPhase, stepFlip, playerYOff, playerXOff)
  local okO, Objects = pcall(require, "src.core.game3.objects")
  local okOw, OwSprites = pcall(require, "src.core.game3.ow_sprites")
  local useOw = okOw and OwSprites and OwSprites.ready and OwSprites.ready()
  local actors = {}
  local hasObjects = okO and Objects and Objects.hasMap and Objects.hasMap()

  if hasObjects then
    for _, eo in ipairs(Objects.forDraw()) do
      local sortY = eo.py or (eo.cellY * CELL)
      if eo.moving and eo.targetY and eo.targetY > (eo.cellY or 0) then
        sortY = math.max(sortY, eo.targetY * CELL)
      end
      actors[#actors + 1] = {
        kind = "npc",
        i = eo.localId,
        obj = eo.def,
        elevation = eo.elevation or (eo.def and eo.def.elevation) or 0,
        x = (eo.px or (eo.cellX * CELL)) + (eo.raiseX or 0),
        y = (eo.py or (eo.cellY * CELL)) + (eo.raiseY or 0),
        sortY = sortY,
        facing = eo.facing or "down",
        walkPhase = Objects.walkPhase(eo),
        stepFlip = eo.stepFlip and true or false,
        bow = (eo.bowFrames and eo.bowFrames > 0) or eo.raiseHand == true,
        frame = eo.customFrame,
        sprite = eo.sprite or spriteNameForObj(eo.def or {}),
        graphicsId = eo.graphicsId or (eo.def and (eo.def.graphicsId or eo.def.graphics)),
      }
    end
    collectNeighborActors(actors, 10000, currentMapId(game),
      resolveMapDef(game, currentMapId(game)))
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.resolveObjectGraphicsId then
      for _, a in ipairs(actors) do
        if a.obj and not a.ghost then
          local gid = Space.resolveObjectGraphicsId(a.obj)
          if gid then a.graphicsId = gid end
        end
      end
    end
  else
    local world = game and (game.overworld or game.world)
    if world and world.npcs then
      for i, npc in ipairs(world.npcs) do
        actors[#actors + 1] = {
          kind = "npc",
          i = i,
          obj = npc.def,
          elevation = npc.elevation or (npc.def and npc.def.elevation) or 0,
          x = npc.px or ((npc.cellX or 0) * CELL),
          y = npc.py or ((npc.cellY or 0) * CELL),
          sortY = npc.py or ((npc.cellY or 0) * CELL),
          facing = npc.facing or "down",
          sprite = spriteNameForObj(npc.def or {}),
          graphicsId = useOw and OwSprites.playerGraphicsId and npc.graphicsId or nil,
        }
      end
    elseif type(mapDef.objects) == "table" then
      for i, obj in ipairs(mapDef.objects) do
        if objectVisible(obj) then
          actors[#actors + 1] = {
            kind = "npc",
            i = i,
            obj = obj,
            elevation = obj.elevation or 0,
            x = (tonumber(obj.x) or 0) * CELL,
            y = (tonumber(obj.y) or 0) * CELL,
            sortY = (tonumber(obj.y) or 0) * CELL,
            facing = facingFromObj(obj),
            sprite = spriteNameForObj(obj),
            graphicsId = obj.graphicsId or obj.graphics,
          }
        end
      end
    end
  end

  local PlayerMod = package.loaded["src.core.game3.player"]
  if not PlayerMod or (PlayerMod.isVisible and PlayerMod.isVisible()) then
    local playerSortY = py
    if PlayerMod and PlayerMod.moving and PlayerMod.targetY and PlayerMod.targetY > (PlayerMod.cellY or 0) then
      playerSortY = math.max(playerSortY, PlayerMod.targetY * CELL)
    end
    actors[#actors + 1] = {
      kind = "player",
      elevation = PlayerMod and PlayerMod.elevation or 3,
      x = px + (playerXOff or 0),
      y = py + (playerYOff or 0),
      sortY = playerSortY,
      facing = facing or "down",
      walkPhase = (walkPhase == 1 or walkPhase == true) and 1 or 0,
      stepFlip = stepFlip and true or false,
      fieldMove = (PlayerMod and PlayerMod.fieldMoveAnim and PlayerMod.fieldMoveAnim > 0),
      sprite = playerSpriteName(game),
      graphicsId = useOw and OwSprites.playerGraphicsId(game) or nil,
    }
  end

  local underActors = {}
  local overActors = {}
  for _, a in ipairs(actors) do
    a.priority = actorPriority(a)
    if (a.priority or 2) < 2 then
      overActors[#overActors + 1] = a
    else
      underActors[#underActors + 1] = a
    end
  end

  local function sortActors(a, b)
    local ay = a.sortY or a.y
    local by = b.sortY or b.y
    if ay == by then return (a.i or 0) < (b.i or 0) end
    return ay < by
  end
  table.sort(underActors, sortActors)
  table.sort(overActors, sortActors)

  return underActors, overActors
end

--- Collect visible tile draws grouped by palette slot for batched GbcPalette.with.
local function collectTileDraws(mapDef, camX, camY, canvasW, canvasH)
  local bySlot = {} -- slot → { {quad, x, y}, ... }
  local blocksTbl = FieldView._blockTiles
  local tilePals = FieldView._tilePalettes
  local bx0 = math.floor(camX / BLOCK) - 1
  local by0 = math.floor(camY / BLOCK) - 1
  local bx1 = math.floor((camX + canvasW) / BLOCK) + 1
  local by1 = math.floor((camY + canvasH) / BLOCK) + 1

  for by = by0, by1 do
    for bx = bx0, bx1 do
      local blockId = blockIdAt(mapDef, bx, by)
      local block = blocksTbl[(blockId or 0) + 1]
      if type(block) == "table" then
        local tiles = block.tiles or block
        local originX = bx * BLOCK - camX
        local originY = by * BLOCK - camY
        for i = 0, 15 do
          local tile = tiles[i + 1] or 0
          local q = quadFor(tile)
          if q then
            local slot = (tilePals and tilePals[tile + 1]) or 1
            local list = bySlot[slot]
            if not list then
              list = {}
              bySlot[slot] = list
            end
            list[#list + 1] = {
              q = q,
              x = originX + (i % 4) * 8,
              y = originY + math.floor(i / 4) * 8,
            }
          end
        end
      end
    end
  end
  return bySlot
end

local function drawTilesColored(atlas, bySlot, bgSet)
  local ok, GbcPalette = pcall(require, "src.render.GbcPalette")
  local usePal = ok and GbcPalette and GbcPalette.available and GbcPalette.available()
    and bgSet and GbcPalette.with

  love.graphics.setColor(1, 1, 1, 1)
  if usePal then
    if not FieldView._loggedPal then
      log("tile palettes ON (GbcPalette.with per BG slot)")
      FieldView._loggedPal = true
    end
    for slot, list in pairs(bySlot) do
      local colors = bgSet[slot] or bgSet[1]
      if colors then
        GbcPalette.with(colors, function()
          for _, d in ipairs(list) do
            love.graphics.draw(atlas, d.q, d.x, d.y)
          end
        end)
      else
        for _, d in ipairs(list) do
          love.graphics.draw(atlas, d.q, d.x, d.y)
        end
      end
    end
  else
    if not FieldView._loggedPal then
      log("tile palettes OFF (unshaded atlas blit)")
      FieldView._loggedPal = true
    end
    for _, list in pairs(bySlot) do
      for _, d in ipairs(list) do
        love.graphics.draw(atlas, d.q, d.x, d.y)
      end
    end
  end
end

local function washColor(bgSet)
  if bgSet and bgSet[1] and bgSet[1][1] then
    local c = bgSet[1][1]
    return (c[1] or 40) / 255, (c[2] or 80) / 255, (c[3] or 60) / 255
  end
  return 0.12, 0.28, 0.22
end

local function ensure_batch(store, srcPair, texture, capacity)
  local batch = store[srcPair]
  if not batch then
    batch = love.graphics.newSpriteBatch(texture, capacity)
    store[srcPair] = batch
  elseif batch.getTexture and batch:getTexture() ~= texture then
    batch = love.graphics.newSpriteBatch(texture, capacity)
    store[srcPair] = batch
  end
  return batch
end

--- Prefer native mid atlas when ready. Supports cross-pair connection seams
-- (e.g. Route1 pallet_outdoor → Viridian viridian_outdoor) by batching per pair.
-- Draws under-layer (BG3/BG1) only; call drawNativeOverTiles after sprites for BG2.
local function drawNativeTiles(mapDef, camX, camY, canvasW, canvasH)
  if not Versions.NATIVE_RENDER then return false end
  local layout = mapDef.midLayout
  local pair = mapDef.pair or (layout and layout.pair)
  if not layout or not pair then return false end

  local okN, NativeTileset = pcall(require, "src.core.game3.tileset_native")
  if not (okN and NativeTileset and NativeTileset.ready(pair)) then
    if not FieldView._loggedNativeFallback then
      log("native unavailable for " .. tostring(pair) .. " — Gen2 atlas fallback")
      FieldView._loggedNativeFallback = true
    end
    return false
  end
  if not NativeTileset.get(pair) then return false end

  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)

  local cols = math.ceil(canvasW / CELL) + 3
  local rows = math.ceil(canvasH / CELL) + 3
  local cx0 = math.floor(camX / CELL) - 1
  local cy0 = math.floor(camY / CELL) - 1
  local capacity = cols * rows

  FieldView._nativeBatches = FieldView._nativeBatches or {}
  FieldView._nativeOverBatches = FieldView._nativeOverBatches or {}

  local Map = package.loaded["src.core.game3.map"]
    or require("src.core.game3.map")
  local VoidFill = require("src.core.game3.void_fill")
  local voidMode = VoidFill.normalize(VoidFill.mode)

  if FieldView._nativeDirty
      or FieldView._nativeVoid ~= voidMode
      or FieldView._nativeBx ~= cx0
      or FieldView._nativeBy ~= cy0
      or FieldView._nativePair ~= pair then
    for _, batch in pairs(FieldView._nativeBatches) do
      batch:clear()
    end
    for _, batch in pairs(FieldView._nativeOverBatches) do
      batch:clear()
    end
    FieldView._nativeOverByRow = {}
    for r = 0, rows - 1 do
      FieldView._nativeOverByRow[r] = {}
    end
    local cellsByPair = {}
    local voidHas, voidPrimary = nil, nil
    if voidMode ~= "map" and voidMode ~= "black" then
      voidHas = function(m) return NativeTileset.hasMid(pair, m) end
      voidPrimary = VoidFill.primaryFor(pair)
    end
    for row = 0, rows - 1 do
      for col = 0, cols - 1 do
        local mid, srcPair, isVoid = layout:midAt(cx0 + col, cy0 + row), pair, false
        if Map.worldMidAt then
          mid, srcPair, isVoid = Map.worldMidAt(cx0 + col, cy0 + row, mapDef)
          srcPair = srcPair or pair
        end
        local skip = false
        if isVoid and voidMode ~= "map" then
          local fill = VoidFill.fillAt(voidMode, cx0 + col, cy0 + row, voidHas, voidPrimary)
          if fill == false then
            skip = true
          elseif fill then
            mid, srcPair = fill, pair
          end
        end
        if not NativeTileset.ready(srcPair) then
          srcPair = pair
        end
        if not skip then
          local list = cellsByPair[srcPair]
          if not list then
            list = {}
            cellsByPair[srcPair] = list
          end
          list[#list + 1] = { mid = mid, x = col * CELL, y = row * CELL }
        end
      end
    end
    for srcPair, cells in pairs(cellsByPair) do
      local ts = NativeTileset.get(srcPair)
      if ts and ts.image then
        local batch = ensure_batch(FieldView._nativeBatches, srcPair, ts.image, capacity)
        batch:clear()
        local overBatch = nil
        if ts.layered and ts.overImage then
          overBatch = ensure_batch(
            FieldView._nativeOverBatches, srcPair, ts.overImage, capacity)
          overBatch:clear()
        end
        for _, cell in ipairs(cells) do
          local slot = NativeTileset.slotFor(ts, cell.mid)
          local q = NativeTileset.quad(ts, slot)
          if q then batch:add(q, cell.x, cell.y) end
          if overBatch then
            local oq = NativeTileset.overQuad(ts, slot)
            if oq then
              overBatch:add(oq, cell.x, cell.y)
            end
          end
        end
      end
    end
    require("src.core.game3.tileset_anim").setVisiblePairs(cellsByPair)
    FieldView._nativeBx = cx0
    FieldView._nativeBy = cy0
    FieldView._nativePair = pair
    FieldView._nativeVoid = voidMode
    FieldView._nativeDirty = false
  end

  love.graphics.setColor(1, 1, 1, 1)
  local ox = -(camX % CELL) - CELL
  local oy = -(camY % CELL) - CELL
  FieldView._nativeOverOx = ox
  FieldView._nativeOverOy = oy
  FieldView._nativeOverPair = pair
  if FieldView._nativeBatches[pair] then
    love.graphics.draw(FieldView._nativeBatches[pair], ox, oy)
  end
  for srcPair, batch in pairs(FieldView._nativeBatches) do
    if srcPair ~= pair then
      love.graphics.draw(batch, ox, oy)
    end
  end

  if not FieldView._loggedNative then
    log("native mid atlas ON pair=" .. tostring(pair))
    FieldView._loggedNative = true
  end
  return true
end

--- BG2 overhead (building eaves, desk tops) — draw after OW sprites.
local function drawNativeOverTiles()
  local batches = FieldView._nativeOverBatches
  if not batches then return end
  local pair = FieldView._nativeOverPair
  local ox = FieldView._nativeOverOx or 0
  local oy = FieldView._nativeOverOy or 0
  love.graphics.setColor(1, 1, 1, 1)
  if pair and batches[pair] then
    love.graphics.draw(batches[pair], ox, oy)
  end
  for srcPair, batch in pairs(batches) do
    if srcPair ~= pair then
      love.graphics.draw(batch, ox, oy)
    end
  end
end

function FieldView.radiusForLevel(level)
  level = tonumber(level) or 0
  return FLASH_LEVEL_RADIUS[level] or FLASH_LEVEL_RADIUS[0]
end

-- pokefirered/src/overworld.c:966
function FieldView.setFlashLevel(level)
  level = tonumber(level) or 0
  if level < 0 or level > FieldView.MAX_FLASH_LEVEL then level = 0 end
  FieldView.flashLevel = level
  FieldView._flashRadius = nil
  -- pokefirered/include/global.h:770 gSaveBlock1Ptr->flashLevel
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  if session then session.flashLevel = level end
end

-- pokefirered/src/overworld.c:973
function FieldView.getFlashLevel()
  return FieldView.flashLevel
end

function FieldView.setFlashRadius(radius)
  FieldView._flashRadius = tonumber(radius)
end

-- pokefirered/src/field_screen_effect.c:194
function FieldView.animateFlashLevel(fromLevel, toLevel)
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if okFx and FieldEffects and FieldEffects.animateFlashLevel then
    return FieldEffects.animateFlashLevel(fromLevel, toLevel)
  end
  FieldView.setFlashLevel(toLevel)
  return nil
end

-- pokefirered/src/overworld.c:1756
function FieldView.flashRadius()
  if FieldView._flashRadius then return FieldView._flashRadius end
  if FieldView.flashLevel == 0 then return nil end
  return FieldView.radiusForLevel(FieldView.flashLevel)
end

-- pokefirered/src/field_camera.c:507
function FieldView.setCameraPanning(x, y)
  FieldView.cameraPanX = tonumber(x) or 0
  FieldView.cameraPanY = tonumber(y) or 0
end

local function flashActive()
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags and Flags.getFlag
        and Flags.getFlag(Space.store, nil, FLAG_SYS_FLASH_ACTIVE) then
      return true
    end
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local flags = session and session.flags
  return (flags and flags[FLAG_SYS_FLASH_ACTIVE]) and true or false
end

-- pokefirered/src/overworld.c:958
local function mapIsCave(def)
  if def and def.cave ~= nil then return (tonumber(def.cave) or 0) ~= 0 end
  return false
end

-- pokefirered/src/overworld.c:956
function FieldView.defaultFlashLevel(game, mapId)
  if not mapIsCave(resolveMapDef(game, mapId)) then return 0 end
  if flashActive() then return 0 end
  return FieldView.MAX_FLASH_LEVEL
end

function FieldView.setDefaultFlashLevel(game, mapId)
  FieldView._flashMapId = mapId
  FieldView.setFlashLevel(FieldView.defaultFlashLevel(game, mapId))
  return FieldView.flashLevel
end

-- pokefirered/src/field_screen_effect.c:90
local function flashWindowRows(centerX, centerY, radius, w, h)
  local rows = {}
  local maxX = 255
  if w > maxX then maxX = w end
  local function put(y, left, right)
    if y >= 0 and y <= h then
      if left < 0 then left = 0 elseif left > maxX then left = maxX end
      if right < 0 then right = 0 elseif right > maxX then right = maxX end
      rows[y] = { left, right }
    end
  end
  local xy, err, yx = radius, radius, 0
  while xy >= yx do
    put(centerY - yx, centerX - xy, centerX + xy)
    put(centerY + yx, centerX - xy, centerX + xy)
    put(centerY - xy, centerX - yx, centerX + yx)
    put(centerY + xy, centerX - yx, centerX + yx)
    err = err - ((yx * 2) - 1)
    yx = yx + 1
    if err < 0 then
      err = err + 2 * (xy - 1)
      xy = xy - 1
    end
  end
  return rows
end

-- pokefirered/src/field_screen_effect.c:37
function FieldView.flashSpans(radius, w, h, centerX, centerY)
  w = math.floor(tonumber(w) or Display.W)
  h = math.floor(tonumber(h) or Display.H)
  centerX = math.floor(centerX or (w / 2))
  centerY = math.floor(centerY or (h / 2))
  local rows = flashWindowRows(centerX, centerY, math.floor(radius), w, h)
  local spans = {}
  local y = 0
  while y < h do
    local r = rows[y]
    local left = r and r[1] or 0
    local right = r and r[2] or 0
    local y2 = y + 1
    while y2 < h do
      local n = rows[y2]
      if (n and n[1] or 0) ~= left or (n and n[2] or 0) ~= right then break end
      y2 = y2 + 1
    end
    spans[#spans + 1] = { y = y, height = y2 - y, left = left, right = right }
    y = y2
  end
  return spans
end

function FieldView.flashSpansFor(radius, w, h, cx, cy)
  local spans = FieldView._flashSpans
  if spans
      and FieldView._flashSpanR == radius
      and FieldView._flashSpanCX == cx and FieldView._flashSpanCY == cy
      and FieldView._flashSpanW == w and FieldView._flashSpanH == h then
    return spans
  end
  spans = FieldView.flashSpans(radius, w, h, cx, cy)
  FieldView._flashSpans = spans
  FieldView._flashSpanR = radius
  FieldView._flashSpanCX = cx
  FieldView._flashSpanCY = cy
  FieldView._flashSpanW = w
  FieldView._flashSpanH = h
  return spans
end

-- pokefirered/src/overworld.c:2077
local function drawFlashMask(w, h)
  local radius = FieldView.flashRadius()
  if not radius then return end
  local cx, cy = math.floor(w / 2), math.floor(h / 2)
  local spans = FieldView.flashSpansFor(radius, w, h, cx, cy)
  love.graphics.setColor(0, 0, 0, 1)
  for i = 1, #spans do
    local s = spans[i]
    if s.left > 0 then
      love.graphics.rectangle("fill", 0, s.y, s.left, s.height)
    end
    if s.right < w then
      love.graphics.rectangle("fill", s.right, s.y, w - s.right, s.height)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function FieldView.draw(game, canvasW, canvasH, opts)
  canvasW = canvasW or Display.W
  canvasH = canvasH or Display.H
  opts = opts or {}

  local mapId = currentMapId(game)
  local mapDef = resolveMapDef(game, mapId)
  if FieldView._flashMapId ~= mapId then
    FieldView.setDefaultFlashLevel(game, mapId)
  end
  if not mapDef or (not mapDef.blocks and not mapDef.midLayout) or not mapDef.width then
    love.graphics.setColor(0.2, 0.35, 0.55, 1)
    love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)
    love.graphics.print("game3: no layout " .. tostring(mapId), 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local px, py, facing, walkPhase, stepFlip, _, playerYOff, playerXOff = playerPixels(game)
  playerXOff = playerXOff or 0
  playerYOff = playerYOff or 0
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local world = game and (game.overworld or game.world)
  if session then
    session.x = math.floor((px or 0) / CELL)
    session.y = math.floor((py or 0) / CELL)
    session.facing = facing
    if mapId then session.map = mapId end
  end

  -- pret CameraUpdate: always track the player. No map-rect clamp — edges
  -- show connected neighbors (or border), same as walking mid-town.
  local camX = math.floor(px + CELL / 2 - canvasW / 2)
  local camY = math.floor(py + CELL / 2 - canvasH / 2)
  -- pokefirered/src/field_camera.c:89
  camX = camX + (FieldView.cameraPanX or 0)
  camY = camY + (FieldView.cameraPanY or 0)

  local screenOx = math.floor((canvasW - Display.W) / 2)
  local screenOy = math.floor((canvasH - Display.H) / 2)

  -- pret BuyMenuDrawMapBg (shop.c:731-734): Frame player & counter in left gap (X: 0..80, Y: 0..160)
  local okShop, ShopMenu = pcall(require, "src.ui.game3.shop_menu")
  if okShop and ShopMenu and ShopMenu.isShopCamera and ShopMenu.isShopCamera() then
    local fx, fy = px, py
    if facing == "up" or facing == "north" then fy = fy - CELL
    elseif facing == "down" or facing == "south" then fy = fy + CELL
    elseif facing == "left" or facing == "west" then fx = fx - CELL
    elseif facing == "right" or facing == "east" then fx = fx + CELL
    else fx = fx - CELL end
    local fTileX = math.floor(fx / CELL)
    local fTileY = math.floor(fy / CELL)
    camX = (fTileX - 2) * CELL
    camY = (fTileY - 4) * CELL
  end

  FieldView._billboard = opts.billboard
    and { vw = canvasW, vh = canvasH } or nil

  if not opts.actorsOnly then
    local Map = package.loaded["src.core.game3.map"]
      or require("src.core.game3.map")
    if Map.refreshWorld then
      Map.refreshWorld(game, math.ceil(canvasW / CELL), math.ceil(canvasH / CELL), mapId)
    end
  end

  local usedNative = FieldView._nativeOverPair ~= nil
  if not opts.actorsOnly then
    usedNative = drawNativeTiles(mapDef, camX, camY, canvasW, canvasH)
    if usedNative then
      -- Native batch already covers viewport (+ overscan); wash skipped.
    else
      local tileset = resolveTileset(game, mapDef)
      local atlas = loadAtlas(tileset)
      if not atlas or not FieldView._blockTiles then
        love.graphics.setColor(0.45, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)
        love.graphics.print("game3: no tileset atlas", 8, 8)
        love.graphics.setColor(1, 1, 1, 1)
        return
      end

      local bgSet = resolveBgSet(game, mapDef, daytimeFor(game, mapDef))
      local wr, wg, wb = washColor(bgSet)
      love.graphics.setColor(wr, wg, wb, 1)
      love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)

      local bySlot = collectTileDraws(mapDef, camX, camY, canvasW, canvasH)
      drawTilesColored(atlas, bySlot, bgSet)
    end

    -- Tall grass under body (pret lower OAM priority).
    do
      local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
      if okFx and FieldEffects and FieldEffects.drawBehind then
        FieldEffects.drawBehind(camX, camY)
      end
    end

    -- Door opening/closing animation overlays (under actors).
    do
      local okDoors, Doors = pcall(require, "src.core.game3.doors")
      if okDoors and Doors and Doors.draw then
        Doors.draw(camX, camY, canvasW, canvasH)
      end
    end
  end

  -- pokefirered/src/field_effect.c:910
  if not opts.actorsOnly then
    local okHeal, Heal = pcall(require, "src.core.game3.pokecenter_heal")
    if okHeal and Heal and Heal.drawBalls then
      local sx, sy = screenAnchor(px, py, camX, camY)
      love.graphics.push()
      love.graphics.translate(sx, sy)
      Heal.drawBalls(camX, camY)
      love.graphics.pop()
    end
  end

  -- pokefirered/src/field_effect.c:3946: the Deoxys shatter blends only the BG
  -- palettes to white, so the map washes out while the rock fragments (OBJ
  -- sprites) keep their colours.  Painted here, between the last map layer and
  -- the actors, for exactly that reason -- a Renderer.screenVeil would cover
  -- the fragments too and the shatter would be invisible.
  if not opts.actorsOnly then
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.bgFlashAlpha then
      local a = FieldEffects.bgFlashAlpha()
      if a and a > 0 then
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  -- Collect Game3 actors partitioned by OAM priority.
  local underActors, overActors = nil, nil
  if not opts.skipActors then
    underActors, overActors = collectGame3Actors(
      game, mapDef, camX, camY, px, py, facing, walkPhase, stepFlip, playerYOff, playerXOff)
  end

  -- Draw Game3 actors with normal priority (under BG1 / overhead layer).
  if underActors then
    for _, a in ipairs(underActors) do
      drawSingleActor(game, mapDef, a, camX, camY)
    end
  end

  -- pret BG1: metatile top layer covers normal OW sprites (roofs, desk counters, trees).
  if usedNative and not opts.actorsOnly then
    drawNativeOverTiles()
  end

  -- Draw Game3 actors with elevated priority (over BG1 / overhead layer, e.g. bridges/cliffs/jumping/escalators).
  if overActors then
    for _, a in ipairs(overActors) do
      drawSingleActor(game, mapDef, a, camX, camY)
    end
  end

  -- Tall grass over feet (pret subpriority above avatar).
  if not opts.actorsOnly then
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.drawFront then
      FieldEffects.drawFront(camX, camY, py)
    end
  end

  -- pokefirered/src/field_effect.c:1024
  if not opts.actorsOnly then
    local okHeal, Heal = pcall(require, "src.core.game3.pokecenter_heal")
    if okHeal and Heal and Heal.drawMonitor then
      local sx, sy = screenAnchor(px, py, camX, camY)
      love.graphics.push()
      love.graphics.translate(sx, sy)
      Heal.drawMonitor(camX, camY)
      love.graphics.pop()
    end
  end

  -- Pokemon Center heal machine (screen-space OAM, pret FLDEFF_POKECENTER_HEAL).
  if not opts.actorsOnly then
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.drawOverlay then
      love.graphics.push()
      love.graphics.translate(screenOx, screenOy)
      FieldEffects.drawOverlay(camX, camY)
      love.graphics.pop()
    end
  end

  drawFlashMask(canvasW, canvasH)

  love.graphics.setColor(1, 1, 1, 1)
end

--- Drop cached atlases/sprites (tileset hot-reload).
function FieldView.invalidate()
  FieldView._atlas = nil
  FieldView._atlasPath = nil
  FieldView._quads = {}
  FieldView._blockTiles = nil
  FieldView._tilePalettes = nil
  FieldView._spriteCache = {}
  FieldView._logged = false
  FieldView._loggedPal = false
  FieldView._nativeBatch = nil
  FieldView._nativeBatches = nil
  FieldView._nativeOverBatches = nil
  FieldView._nativeBx = nil
  FieldView._nativeBy = nil
  FieldView._nativePair = nil
  FieldView._nativeOverPair = nil
  FieldView._nativeDirty = true
  FieldView._loggedNative = false
  FieldView._loggedNativeFallback = false
  FieldView._flashSpans = nil
  FieldView._flashSpanR = nil
  local okN, NativeTileset = pcall(require, "src.core.game3.tileset_native")
  if okN and NativeTileset and NativeTileset.invalidate then
    NativeTileset.invalidate()
  end
  local okO, OwSprites = pcall(require, "src.core.game3.ow_sprites")
  if okO and OwSprites and OwSprites.invalidate then
    OwSprites.invalidate()
  end
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if okFx and FieldEffects and FieldEffects.invalidate then
    FieldEffects.invalidate()
  end
end

return FieldView
