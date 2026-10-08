-- Game3 native field renderer (FRLG 240×160, 1:1 world pixels).
-- Owns tile palette blits + OW sprites. Does NOT call World:draw / Zoom / Chrome.

local Display = require("src.core.game3.display")
local Versions = require("src.import.gba.versions")
local GfxIds = require("src.core.game3.scripting.gfx_ids")
local FieldModules = require("src.core.game3.field_modules")
local Sem = require("src.core.game3.field_semantics")

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
FieldView._nativeBaseBx = nil
FieldView._nativeBaseBy = nil
FieldView._nativeViewCols = nil
FieldView._nativeViewRows = nil
FieldView._nativeVisibleCells = nil
FieldView._nativeFreeUnder = nil
FieldView._nativeFreeOver = nil
FieldView._nativeSpriteSlots = 0
FieldView._nativePair = nil
FieldView._nativeDirty = true
FieldView._nativeOverOx = 0
FieldView._nativeOverOy = 0
FieldView._nativeOverPair = nil
FieldView._loggedNative = false
FieldView._loggedNativeFallback = false

-- pokefirered/src/field_screen_effect.c:18
local FLASH_LEVEL_RADIUS = { [0] = 200, 72, 56, 40, 24 }

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

local _M = {}
local function getMod(key, path)
  local m = _M[key]
  if not m then
    m = package.loaded[path]
    if not m then
      local ok, loaded = pcall(require, path)
      if ok then m = loaded end
    end
    _M[key] = m
  end
  return m
end

local function modObjects() return getMod("Objects", "src.core.game3.objects") end
local function modOwSprites() return getMod("OwSprites", "src.core.game3.ow_sprites") end
local function modNativeTileset() return getMod("NativeTileset", "src.core.game3.tileset_native") end
local function modFieldEffects() return getMod("FieldEffects", "src.core.game3.field_effects") end
local function modSpriteRenderer() return getMod("SpriteRenderer", "src.render.SpriteRenderer") end
local function modPalettes() return getMod("Palettes", "src.world.gen2.Palettes") end
local function modFlags() return getMod("Flags", "src.core.game3.scripting.flags") end
local function modDoors() return getMod("Doors", "src.core.game3.doors") end
local function modHeal() return getMod("Heal", "src.core.game3.pokecenter_heal") end
local function modSSAnne()
  if not FieldModules.enabled("ssAnne") then return nil end
  return getMod("SSAnne", "src.core.game3.ss_anne_cutscene")
end
local function modFieldWeather() return getMod("FieldWeather", "src.core.game3.field_weather") end
local function modAssets() return getMod("Assets", "src.render.Assets") end
local function modPlayer() return getMod("Player", "src.core.game3.player") end
local function modGbcPalette() return getMod("GbcPalette", "src.render.GbcPalette") end
local function modSeagallop() return getMod("SeagallopUi", "src.ui.game3.seagallop") end
local function modShopMenu() return getMod("ShopMenu", "src.ui.game3.shop_menu") end
local function modFollower() return getMod("Follower", "src.world.game3.Follower") end

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
  local Assets = modAssets()
  if Assets and Assets.image then
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
  local Palettes = modPalettes()
  if not Palettes then return nil end
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
  local G3Player = modPlayer()
  local Runtime = package.loaded["src.core.game3.runtime"]
  if G3Player and Runtime and Runtime.isActive and Runtime.isActive() then
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

local function palettes()
  return modPalettes()
end

local function daytimeFor(game, mapDef)
  local world = game and (game.overworld or game.world)
  if world and world.daytime then return world.daytime end
  local Palettes = palettes()
  if Palettes and Palettes.daytimeFor and world and world.hour then
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

  local SpriteRenderer = modSpriteRenderer()
  if not SpriteRenderer then return nil end
  local sr = SpriteRenderer.new(def, seed or spriteName)

  local Palettes = modPalettes()
  local pals = data and (data.gen2Palettes or data.palettes)
  if Palettes and pals and sr.setObjPalette then
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

local function neighborActorDefs(mapId, def)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local ev = Space and Space.bundle and Space.bundle.events
    and Space.bundle.events[mapId]
  local defs = ev and (ev.objects or ev.objectEvents)
  if type(defs) ~= "table" then defs = def and def.objects end
  return type(defs) == "table" and defs or nil
end

local ghostActors = setmetatable({}, { __mode = "k" })
local ACTOR_CULL_MARGIN = 64

local function entryInView(entry, x0, y0, x1, y1)
  local L = entry.def and entry.def.midLayout
  local w = (L and L.width) or ((tonumber(entry.def and entry.def.width) or 0) * 2)
  local h = (L and L.height) or ((tonumber(entry.def and entry.def.height) or 0) * 2)
  local ex, ey = entry.ox * CELL, entry.oy * CELL
  return ex + w * CELL > x0 and ex < x1 and ey + h * CELL > y0 and ey < y1
end

local function collectNeighborActors(actors, baseIndex, hostMapId, hostDef, camX, camY)
  local Map = package.loaded["src.core.game3.map"]
  if not (Map and type(Map.world) == "table") then return baseIndex end
  local Ghosts = package.loaded["src.core.game3.ghosts"]
  local Objects = package.loaded["src.core.game3.objects"]
  local vw = FieldView._viewW or Display.W
  local vh = FieldView._viewH or Display.H
  local cull = camX ~= nil and camY ~= nil
  local x0, y0 = (camX or 0) - ACTOR_CULL_MARGIN, (camY or 0) - ACTOR_CULL_MARGIN
  local x1, y1 = (camX or 0) + vw + ACTOR_CULL_MARGIN, (camY or 0) + vh + ACTOR_CULL_MARGIN
  for _, entry in ipairs(Map.world) do
    if entry.id ~= hostMapId and entry.def ~= hostDef
        and (not cull or entryInView(entry, x0, y0, x1, y1)) then
      local live = Ghosts and Ghosts.forDraw and Ghosts.forDraw(entry.id)
      if live then
        for _, eo in ipairs(live) do
          local x = (eo.px or (eo.cellX or 0) * CELL) + entry.ox * CELL
          local y = (eo.py or (eo.cellY or 0) * CELL) + entry.oy * CELL
          if not cull or (x > x0 and x < x1 and y > y0 and y < y1) then
            baseIndex = baseIndex + 1
            local a = ghostActors[eo]
            if not a then
              a = { kind = "npc", eventObject = eo }
              ghostActors[eo] = a
            end
            a.i = baseIndex
            a.obj = eo.def
            a.ghost = entry.id
            a.x = x
            a.y = y
            a.facing = eo.facing or "down"
            a.walkPhase = Objects and Objects.walkPhase and Objects.walkPhase(eo) or 0
            a.stepFlip = eo.stepFlip and true or false
            a.sprite = eo.sprite or spriteNameForObj(eo.def or {})
            a.graphicsId = eo.graphicsId
              or (eo.def and (eo.def.graphicsId or eo.def.graphics))
            a.alpha = Objects and Objects.fadeAlpha and Objects.fadeAlpha(eo) or nil
            a.elevation = nil
            a.priority = nil
            a.subpriority = nil
            actors[#actors + 1] = a
          end
        end
      else
        local defs = neighborActorDefs(entry.id, entry.def)
        local bounds = Objects and Objects.layoutBounds
          and Objects.layoutBounds(entry.def) or nil
        local Space = package.loaded["src.core.game3.scripting.space"]
        local nb = Space and Space.neighborObjectState
          and Space.neighborObjectState(entry.id)
          or { store = { flags = {}, vars = {} }, perm = {}, movementType = {} }
        if defs then
          for _, obj in ipairs(defs) do
            local lid = tonumber(obj.localId or obj.index) or 0
            local p = nb.perm[lid]
            local ox = p and p.x or tonumber(obj.x) or 0
            local oy = p and p.y or tonumber(obj.y) or 0
            local out = bounds and (ox < -16 or oy < -16
              or ox >= bounds.w + 16 or oy >= bounds.h + 16)
            -- src/event_object_movement.c:8014
            if tonumber(obj.movementType) == 0x4C then out = true end
            local gid = obj.graphicsId or obj.graphics
            if Space and Space.resolveObjectGraphicsId then
              gid = Space.resolveObjectGraphicsId(obj, nb)
            end
            if objectVisible(obj) and not out and gid then
              local mt = nb.movementType[lid]
              baseIndex = baseIndex + 1
              actors[#actors + 1] = {
                kind = "npc",
                i = baseIndex,
                obj = obj,
                ghost = entry.id,
                x = (entry.ox + ox) * CELL,
                y = (entry.oy + oy) * CELL,
                facing = (mt and GfxIds.initialFacing(mt))
                  or (obj.movementType ~= nil and GfxIds.initialFacing(obj.movementType))
                  or facingFromObj(obj),
                sprite = spriteNameForObj(obj),
                graphicsId = gid,
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
  if a.oamPriority then return a.oamPriority end
  if a.kind == "player" then
    local PlayerMod = package.loaded["src.core.game3.player"]
    if PlayerMod and (PlayerMod.jumping or PlayerMod.surfHopping) then
      return 1
    end
    -- pokefirered/src/field_effect.c:2413
    if PlayerMod and PlayerMod.oamPriority then return PlayerMod.oamPriority end
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

-- pokeemerald/src/event_object_movement.c:7691
local ELEV_TO_SUBPRIORITY = {
  [0] = 115, [1] = 115, [2] = 83, [3] = 115, [4] = 83, [5] = 115,
  [6] = 83, [7] = 115, [8] = 83, [9] = 115, [10] = 83, [11] = 115,
  [12] = 83, [13] = 0, [14] = 0, [15] = 115
}

local function sortActors(a, b)
  if a.subpriority == b.subpriority then
    local ay = a.sortY or a.y or 0
    local by = b.sortY or b.y or 0
    if ay == by then return (a.i or 0) < (b.i or 0) end
    return ay < by
  end
  return a.subpriority > b.subpriority
end

local drawOrderObjects = {}

-- event_object_movement.c:7739-7754, scrcmd.c:1130
local function applyDrawOrder(actors, underActors, overActors, camY)
  underActors = underActors or {}
  overActors = overActors or {}
  for i = #underActors, 1, -1 do underActors[i] = nil end
  for i = #overActors, 1, -1 do overActors[i] = nil end
  for obj in pairs(drawOrderObjects) do drawOrderObjects[obj] = nil end
  for _, a in ipairs(actors) do
    local obj = a.eventObject
    if obj then drawOrderObjects[obj] = a end
    if (obj and obj.fixedPriority) or a.fixedPriority then
      a.fixedPriority = true
      if obj and obj.fixedClass == nil then obj.fixedClass = a.priority or actorPriority(a) end
      a.subpriority = (obj and obj.subpriority) or a.subpriority or 83
      a.priority = (obj and obj.fixedClass) or a.priority or actorPriority(a)
    else
      if obj then obj.fixedClass = nil end
      a.fixedPriority = false
      a.priority = actorPriority(a)
      local screenY = math.floor((a.y or 0) - (camY or 0))
      local gridY = math.floor(screenY / 16)
      local y = (16 - gridY) * 2
      local base = ELEV_TO_SUBPRIORITY[a.elevation or 3] or 115
      a.subpriority = base + y + 1
    end
    if (a.priority or 2) < 2 then
      overActors[#overActors + 1] = a
    else
      underActors[#underActors + 1] = a
    end
  end
  -- pokeemerald/src/field_effect_helpers.c:1365
  for _, a in ipairs(actors) do
    local linked = a.disguiseObject and drawOrderObjects[a.disguiseObject]
    if linked then a.subpriority = (linked.subpriority - 1) % 256 end
  end
  table.sort(underActors, sortActors)
  table.sort(overActors, sortActors)
  return underActors, overActors
end
FieldView.applyDrawOrder = applyDrawOrder

local owOpts = {}

local function weatherMask()
  local W = package.loaded["src.core.game3.field_weather_rse"]
  return W and W.maskActive and W.maskActive() and W or nil
end

local function drawSingleActor(game, mapDef, a, camX, camY)
  local daytime = daytimeFor(game, mapDef)
  local OwSprites = modOwSprites()
  local useOw = OwSprites and OwSprites.ready and OwSprites.ready()
  love.graphics.setColor(1, 1, 1, 1)
  local billboarded = pushBillboard(a.x, a.y, camX, camY)
  local drew = false
  if a.draw then
    a:draw(camX, camY)
    drew = true
  end
  if not drew and a.renderer then
    a.renderer:draw(a.x, a.y, camX, camY, a.facing, a.walkPhase or 0, false)
    drew = true
  end
  if not drew and useOw and a.graphicsId ~= nil then
    local opts = owOpts
    opts.bow = a.bow
    opts.fieldMove = a.fieldMove
    opts.fieldMoveFrame = a.fieldMoveFrame
    opts.fishing = a.fishing
    opts.fishFrame = a.fishFrame
    opts.frame = a.frame
    opts.running = a.running
    opts.alpha = a.alpha
    drew = OwSprites.draw(
      a.graphicsId, a.x, a.y, camX, camY, a.facing, a.walkPhase, a.stepFlip, opts)
    local W = drew and weatherMask()
    if W then
      local spr = OwSprites.getDraw(a.graphicsId)
      -- pokeruby/src/field_weather.c:580
      W.writeActorMask(W.actorMaskCode(spr and spr.paletteSlot), function()
        OwSprites.draw(a.graphicsId, a.x, a.y, camX, camY, a.facing, a.walkPhase, a.stepFlip, opts)
      end)
    end
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

local frameActors, frameUnder, frameOver = {}, {}, {}
local npcActors = setmetatable({}, { __mode = "k" })
local playerActor = {}

local function collectGame3Actors(game, mapDef, camX, camY, px, py, facing, walkPhase, stepFlip, playerYOff, playerXOff)
  local Objects = modObjects()
  local OwSprites = modOwSprites()
  local useOw = OwSprites and OwSprites.ready and OwSprites.ready()
  local actors = frameActors
  for i = #actors, 1, -1 do actors[i] = nil end
  local hasObjects = Objects and Objects.hasMap and Objects.hasMap()

  if hasObjects then
    for _, eo in ipairs(Objects.forDraw()) do
      local sortY = eo.py or (eo.cellY * CELL)
      if eo.moving and eo.targetY and eo.targetY > (eo.cellY or 0) then
        sortY = math.max(sortY, eo.targetY * CELL)
      end
      local a = npcActors[eo]
      if not a then
        a = { kind = "npc", eventObject = eo }
        npcActors[eo] = a
      end
      a.i = eo.localId
      a.obj = eo.def
      a.elevation = eo.elevation or (eo.def and eo.def.elevation) or 0
      a.x = (eo.px or (eo.cellX * CELL)) + (eo.raiseX or 0)
      a.y = (eo.py or (eo.cellY * CELL)) + (eo.raiseY or 0)
      a.sortY = sortY
      a.facing = eo.facing or "down"
      a.walkPhase = Objects.walkPhase(eo)
      a.stepFlip = eo.stepFlip and true or false
      -- pokeemerald/src/data/object_events/object_event_anims.h:602
      a.bow = (eo.bowFrames and eo.bowFrames > 8 and eo.bowFrames <= 40) or eo.raiseHand == true
      a.frame = eo.customFrame
      a.sprite = eo.sprite or spriteNameForObj(eo.def or {})
      a.graphicsId = eo.graphicsId or (eo.def and (eo.def.graphicsId or eo.def.graphics))
      a.alpha = Objects.fadeAlpha(eo)
      a.draw = eo.foreign and eo.draw or nil
      a.priority = nil
      a.subpriority = nil
      actors[#actors + 1] = a
    end
    collectNeighborActors(actors, 10000, currentMapId(game),
      resolveMapDef(game, currentMapId(game)), camX, camY)
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.resolveObjectGraphicsId then
      for _, a in ipairs(actors) do
        if a.obj and not a.ghost and not (a.eventObject and a.eventObject.graphicsId ~= nil) then
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
    local fieldMove = (PlayerMod and PlayerMod.fieldMoveAnim and PlayerMod.fieldMoveAnim > 0) or false
    local fieldMoveFrame
    if fieldMove and useOw and OwSprites.fieldMoveFrame then
      fieldMoveFrame = OwSprites.fieldMoveFrame(
        (PlayerMod.fieldMoveTotal or PlayerMod.fieldMoveAnim) - PlayerMod.fieldMoveAnim,
        PlayerMod.fieldMoveKind)
    end
    local FieldMod = package.loaded["src.core.game3.field"]
    local fishFrame, fishX2, fishY2
    if not fieldMove and FieldMod and FieldMod.fishingPose then
      fishFrame, fishX2, fishY2 = FieldMod.fishingPose()
    end
    local a = playerActor
    a.kind = "player"
    a.elevation = PlayerMod and PlayerMod.elevation or 3
    a.x = px + (playerXOff or 0) + (fishX2 or 0)
    a.y = py + (playerYOff or 0) + (fishY2 or 0)
    a.sortY = playerSortY
    a.facing = facing or "down"
    a.walkPhase = (walkPhase == 1 or walkPhase == true) and 1 or 0
    a.stepFlip = stepFlip and true or false
    a.fieldMove = fieldMove
    a.fieldMoveFrame = fieldMoveFrame
    a.fishing = fishFrame ~= nil
    a.fishFrame = fishFrame
    a.running = PlayerMod and PlayerMod.runPose and PlayerMod.runPose() or nil
    a.frame = PlayerMod and PlayerMod.acroFrame and PlayerMod.acroFrame() or nil
    a.sprite = playerSpriteName(game)
    a.graphicsId = useOw and OwSprites.playerGraphicsId(game) or nil
    a.priority = nil
    a.fixedPriority = PlayerMod and PlayerMod.fixedPriority
    a.subpriority = PlayerMod and PlayerMod.subpriority
    actors[#actors + 1] = a
  end

  local Follower = modFollower()
  local follower = Follower and Follower.actor and Follower.actor()
  if follower then actors[#actors + 1] = follower end

  local FieldEffects = modFieldEffects()
  if FieldEffects and FieldEffects.collectActors then
    FieldEffects.collectActors(actors)
  end

  return applyDrawOrder(actors, frameUnder, frameOver, camY)
end

--- Collect visible tile draws grouped by palette slot for batched GbcPalette.with.
local tile_draw_pool, tile_draw_count, tile_draw_slots = {}, 0, {}

local function collectTileDraws(mapDef, camX, camY, canvasW, canvasH)
  local bySlot = tile_draw_slots
  for slot, list in pairs(bySlot) do
    for i = #list, 1, -1 do list[i] = nil end
    bySlot[slot] = nil
  end
  tile_draw_count = 0
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
            local d = tile_draw_pool[tile_draw_count + 1]
            if not d then
              d = { q = false, x = 0, y = 0 }
              tile_draw_pool[tile_draw_count + 1] = d
            end
            tile_draw_count = tile_draw_count + 1
            d.q = q
            d.x = originX + (i % 4) * 8
            d.y = originY + math.floor(i / 4) * 8
            list[#list + 1] = d
          end
        end
      end
    end
  end
  return bySlot
end

local palAtlas, palList
local function draw_pal_list()
  for _, d in ipairs(palList) do
    love.graphics.draw(palAtlas, d.q, d.x, d.y)
  end
end

local function drawTilesColored(atlas, bySlot, bgSet)
  local GbcPalette = modGbcPalette()
  local usePal = GbcPalette and GbcPalette.available and GbcPalette.available()
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
        palAtlas, palList = atlas, list
        GbcPalette.with(colors, draw_pal_list)
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

local function releaseBatch(batch)
  if batch and batch.release then pcall(batch.release, batch) end
end

-- Outside a full reset, visible cells hold sprite indices into the batch
-- stored under `srcPair`, so a texture swap cannot replace it in place (the
-- next releaseNativeSprite would index a smaller batch).  Report the swap and
-- let drawNativeTiles rebuild everything this frame instead.
local function ensure_batch(store, srcPair, texture, capacity)
  local batch = store[srcPair]
  if batch and batch.getTexture and batch:getTexture() ~= texture then
    if not FieldView._nativeResetting then
      FieldView._nativeSwap = true
      return nil
    end
    releaseBatch(batch)
    batch = nil
  end
  if not batch then
    batch = love.graphics.newSpriteBatch(texture, capacity)
    store[srcPair] = batch
  end
  return batch
end

local nativeAtlasByPair = {}
local HIDDEN_SPRITE_X, HIDDEN_SPRITE_Y = -1000000, -1000000

local function nativeAtlas(NativeTileset, pair)
  local ts = nativeAtlasByPair[pair]
  if not ts or (NativeTileset._pairs and NativeTileset._pairs[pair] ~= ts) then
    ts = NativeTileset.get(pair)
    if ts then nativeAtlasByPair[pair] = ts end
  end
  return ts
end

function FieldView.trimNative(NativeTileset, Map, pair, visiblePairs)
  local keep, busy = {}, {}
  keep[pair] = true
  for p in pairs(visiblePairs or {}) do keep[p] = true end
  local x0, y0, x1, y1
  if Map.warmRect then x0, y0, x1, y1 = Map.warmRect() end
  for _, entry in ipairs(Map.world or {}) do
    local def = entry.def
    local p = def and (def.pair or (def.midLayout and def.midLayout.pair))
    if p and (not Map.warmNear or Map.warmNear(entry, x0, y0, x1, y1)) then keep[p] = true end
  end
  local function mark(store)
    for _, b in pairs(store or {}) do
      if b.getTexture then busy[b:getTexture()] = true end
    end
  end
  mark(FieldView._nativeBatches)
  mark(FieldView._nativeOverBatches)
  local from = FieldView._voidFrom
  if from then
    mark(from.under)
    mark(from.over)
  end
  local evicted = NativeTileset.trim(keep, NativeTileset.RESIDENT_MAX, busy)
  for _, p in ipairs(evicted) do nativeAtlasByPair[p] = nil end
  return evicted
end

-- Physical sprite slots per layer (free-list reuse does not grow them).
local nativeSlots = { under = 0, over = 0 }

local function acquireNativeSprite(store, free, key, texture, capacity, quad, x, y, layer)
  local batch = ensure_batch(store, key, texture, capacity)
  if not batch then return nil end
  local available = free[key]
  local index
  if available and #available > 0 then
    index = available[#available]
    available[#available] = nil
    batch:set(index, quad, x, y)
  else
    index = batch:add(quad, x, y)
    local n = nativeSlots[layer] + 1
    nativeSlots[layer] = n
    if n > FieldView._nativeSpriteSlots then FieldView._nativeSpriteSlots = n end
  end
  return { key = key, index = index, quad = quad }
end

local function releaseNativeSprite(store, free, sprite)
  if not sprite then return true end
  local batch = store[sprite.key]
  if not (batch and batch.set) then return false end
  if batch.getCount and sprite.index > batch:getCount() then return false end
  batch:set(sprite.index, sprite.quad, HIDDEN_SPRITE_X, HIDDEN_SPRITE_Y)
  local available = free[sprite.key]
  if not available then
    available = {}
    free[sprite.key] = available
  end
  available[#available + 1] = sprite.index
  return true
end

-- Clear every native batch for a full rebuild, keeping the SpriteBatch
-- objects (and their GPU buffers) for reuse.  Batches that cannot be cleared
-- (test doubles) are dropped.
local function clearNativeStore(store)
  for k, batch in pairs(store) do
    if batch.clear then
      batch:clear()
    else
      releaseBatch(batch)
      store[k] = nil
    end
  end
end

-- After a rebuild, release batches no visible cell uses any more.
local function pruneNativeStore(store)
  for k, batch in pairs(store) do
    if batch.getCount and batch:getCount() == 0 then
      releaseBatch(batch)
      store[k] = nil
    end
  end
end

local function releaseVoidFrom(from)
  if not from then return end
  for _, t in ipairs({ from.under, from.over }) do
    for _, batch in pairs(t or {}) do releaseBatch(batch) end
  end
end

--- Mark one cell of the drawn map's layout for re-sampling on the next draw
-- (metatile writes).  x, y are layout (current-map) cell coordinates.  Cells
-- that are not visible need nothing: they are sampled when they scroll in.
function FieldView.invalidateCell(x, y, layout)
  if FieldView._nativeDirty or type(FieldView._nativeVisibleCells) ~= "table" then return end
  x, y = tonumber(x), tonumber(y)
  if not (x and y) or (layout ~= nil and layout ~= FieldView._nativeLayout) then
    FieldView._nativeDirty = true
    return
  end
  local cells = FieldView._nativeDirtyCells
  if not cells then
    cells = {}
    FieldView._nativeDirtyCells = cells
  end
  local n = #cells
  if n >= 1024 then
    FieldView._nativeDirty = true
    return
  end
  cells[n + 1] = x
  cells[n + 2] = y
end

--- Metatile write on `layout` at its own (x, y).  Only the drawn map's own
-- layout maps 1:1 onto view cells; anything else (neighbour maps, a layout
-- shared with a neighbour) falls back to a full rebuild.
function FieldView.invalidateLayoutCell(layout, x, y)
  if FieldView._nativeDirty then return end
  if layout == nil or layout ~= FieldView._nativeLayout then
    FieldView._nativeDirty = true
    return
  end
  local Map = package.loaded["src.core.game3.map"]
  for _, entry in ipairs((Map and Map.world) or {}) do
    if entry.def and entry.def.midLayout == layout then
      FieldView._nativeDirty = true
      return
    end
  end
  FieldView.invalidateCell(x, y, layout)
end

FieldView.VOID_FADE_FRAMES = 20
local voidKeys = setmetatable({}, { __index = function(t, pair)
  local k = "void|" .. pair
  t[pair] = k
  return k
end })

local function isVoidKey(k)
  return type(k) == "string" and k:sub(1, 5) == "void|"
end

local function connectedTo(Map, def)
  for _, n in ipairs(Map.neighborList or {}) do
    if n.def == def then return true end
  end
  return false
end

local function beginVoidFade(Map, mapDef, camX, camY, voidMode)
  local prev = FieldView._voidMapDef
  if prev == mapDef then return end
  FieldView._voidMapDef = mapDef
  FieldView._voidFrom = nil
  if not (prev and voidMode == "map" and FieldView._lastCamX and connectedTo(Map, prev)) then return end
  local from = { under = {}, over = {}, bx = FieldView._nativeBaseBx or FieldView._nativeBx or 0,
    by = FieldView._nativeBaseBy or FieldView._nativeBy or 0,
    dx = FieldView._lastCamX - camX, dy = FieldView._lastCamY - camY, t = 0 }
  for _, store in ipairs({ { FieldView._nativeBatches, from.under }, { FieldView._nativeOverBatches, from.over } }) do
    for k, b in pairs(store[1] or {}) do
      if isVoidKey(k) then
        store[2][k] = b
        store[1][k] = nil
      end
    end
  end
  if next(from.under) then FieldView._voidFrom = from end
  FieldView._nativeDirty = true
end

local function drawVoidFrom(batches, camX, camY)
  local f = FieldView._voidFrom
  if not f then return end
  love.graphics.setColor(1, 1, 1, 1 - f.t / FieldView.VOID_FADE_FRAMES)
  local x, y = f.bx * CELL - (camX + f.dx), f.by * CELL - (camY + f.dy)
  for _, b in pairs(batches) do love.graphics.draw(b, x, y) end
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawLayer(batches, pair, ox, oy, fromBatches, camX, camY)
  for k, b in pairs(batches) do
    if isVoidKey(k) then love.graphics.draw(b, ox, oy) end
  end
  if fromBatches then drawVoidFrom(fromBatches, camX, camY) end
  if batches[pair] then love.graphics.draw(batches[pair], ox, oy) end
  for k, b in pairs(batches) do
    if k ~= pair and not isVoidKey(k) then love.graphics.draw(b, ox, oy) end
  end
end

--- Prefer native mid atlas when ready. Supports cross-pair connection seams
-- (e.g. Route1 pallet_outdoor → Viridian viridian_outdoor) by batching per pair.
-- Draws under-layer (BG3/BG1) only; call drawNativeOverTiles after sprites for BG2.
local function drawNativeTiles(mapDef, camX, camY, canvasW, canvasH)
  if not Versions.NATIVE_RENDER then return false end
  local layout = mapDef.midLayout
  local pair = mapDef.pair or (layout and layout.pair)
  if not layout or not pair then return false end

  local NativeTileset = modNativeTileset()
  if not (NativeTileset and NativeTileset.ready and NativeTileset.ready(pair)) then
    if not FieldView._loggedNativeFallback then
      log("native unavailable for " .. tostring(pair) .. " — Gen2 atlas fallback")
      FieldView._loggedNativeFallback = true
    end
    return false
  end
  local mainTs = nativeAtlas(NativeTileset, pair)
  if not mainTs then return false end

  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)

  local cols = math.ceil(canvasW / CELL) + 3
  local rows = math.ceil(canvasH / CELL) + 3
  local cx0 = math.floor(camX / CELL) - 1
  local cy0 = math.floor(camY / CELL) - 1
  local capacity = cols * rows

  local Map = package.loaded["src.core.game3.map"]
    or require("src.core.game3.map")
  local VoidFill = require("src.core.game3.void_fill")
  local voidMode = VoidFill.normalize(VoidFill.mode)
  beginVoidFade(Map, mapDef, camX, camY, voidMode)

  local underStore = FieldView._nativeBatches
  if not underStore then
    underStore = {}
    FieldView._nativeBatches = underStore
  end
  local overStore = FieldView._nativeOverBatches
  if not overStore then
    overStore = {}
    FieldView._nativeOverBatches = overStore
  end
  local mainBatch = underStore[pair]

  local moved = FieldView._nativeBx ~= cx0 or FieldView._nativeBy ~= cy0
  local reset = FieldView._nativeDirty
    or FieldView._nativeVoid ~= voidMode
    or FieldView._nativePair ~= pair
    or FieldView._nativeLayout ~= layout
    or FieldView._nativeViewCols ~= cols
    or FieldView._nativeViewRows ~= rows
    or type(FieldView._nativeVisibleCells) ~= "table"
    or type(FieldView._nativeFreeUnder) ~= "table"
    or type(FieldView._nativeFreeOver) ~= "table"
    or (FieldView._nativeSpriteSlots or 0) > capacity * 4
    -- primary atlas reloaded (tileset reinstall): cells index the old texture
    or (mainBatch ~= nil and mainBatch.getTexture ~= nil and mainBatch:getTexture() ~= mainTs.image)
  if not reset and moved then
    local dx = math.abs(cx0 - (FieldView._nativeBx or cx0))
    local dy = math.abs(cy0 - (FieldView._nativeBy or cy0))
    if dx >= cols or dy >= rows then
      reset = true
    else
      for _, store in ipairs({ underStore, overStore }) do
        for _, batch in pairs(store) do
          if type(batch.set) ~= "function" then reset = true; break end
        end
        if reset then break end
      end
    end
  end

  local visibleCells = FieldView._nativeVisibleCells
  local visiblePairs = FieldView._nativeVisiblePairs
  local baseBx, baseBy = FieldView._nativeBaseBx, FieldView._nativeBaseBy
  local CellPlan = require("src.core.game3.field_plan")
  -- A same-layout bulk invalidation can come from a mod editing its cells
  -- directly. Resnapshot it rather than reuse an older planned window.
  if FieldView._nativeDirty and FieldView._nativeLayout == layout then CellPlan.invalidate() end
  local preparedCells = CellPlan.get(mapDef, cx0, cy0, cols, rows, voidMode)
  FieldView._cellPreparationRoute = preparedCells and "worker" or "sync"
  local function addCell(wx, wy)
    local mid, srcPair, isVoid
    local skip = false
    if preparedCells then
      mid, srcPair, isVoid, skip = CellPlan.cell(preparedCells, wx, wy)
    elseif Map.worldMidAt then
      mid, srcPair, isVoid = Map.worldMidAt(wx, wy, mapDef)
      srcPair = srcPair or pair
    else
      mid, srcPair, isVoid = layout:midAt(wx, wy), pair, false
    end
    if not preparedCells and isVoid and voidMode ~= "map" then
      local fill = VoidFill.fillAt(voidMode, wx, wy,
        function(m) return NativeTileset.hasMid(pair, m) end, VoidFill.primaryFor(pair))
      if fill == false then
        skip = true
      elseif fill then
        mid, srcPair = fill, pair
      end
    end
    if not NativeTileset.ready(srcPair) then srcPair = pair end
    local info = { pair = srcPair, draw = not skip }
    if not skip then
      local key = (isVoid and voidMode == "map") and voidKeys[srcPair] or srcPair
      info.key = key
      local ts = nativeAtlas(NativeTileset, srcPair)
      if ts and ts.image then
        local slot = NativeTileset.slotFor(ts, mid)
        local q = NativeTileset.quad(ts, slot)
        if q then
          info.under = acquireNativeSprite(underStore,
            FieldView._nativeFreeUnder, key, ts.image, capacity, q,
            (wx - baseBx) * CELL, (wy - baseBy) * CELL, "under")
        end
        if ts.layered and ts.overImage then
          local oq = NativeTileset.overQuad(ts, slot)
          if oq then
            info.over = acquireNativeSprite(overStore,
              FieldView._nativeFreeOver, key, ts.overImage, capacity, oq,
              (wx - baseBx) * CELL, (wy - baseBy) * CELL, "over")
          end
        end
      end
    end
    return info
  end

  local function releaseCell(info)
    return releaseNativeSprite(underStore, FieldView._nativeFreeUnder, info.under)
      and releaseNativeSprite(overStore, FieldView._nativeFreeOver, info.over)
  end

  if not reset and moved then
    for wy, row in pairs(visibleCells) do
      for wx, info in pairs(row) do
        if wx < cx0 or wx >= cx0 + cols or wy < cy0 or wy >= cy0 + rows then
          if not releaseCell(info) then
            reset = true
            break
          end
          row[wx] = nil
        end
      end
      if next(row) == nil then visibleCells[wy] = nil end
      if reset then break end
    end
  end

  -- Metatile writes since the last draw: drop just those cells so the fill
  -- loop below re-samples them (FieldView.invalidateCell).
  local dirtyCells = FieldView._nativeDirtyCells
  if dirtyCells then
    FieldView._nativeDirtyCells = nil
    if not reset then
      for i = 1, #dirtyCells - 1, 2 do
        local wx, wy = dirtyCells[i], dirtyCells[i + 1]
        local row = visibleCells[wy]
        local info = row and row[wx]
        if info then
          if not releaseCell(info) then
            reset = true
            break
          end
          row[wx] = nil
        end
      end
    end
  end

  local function resetNative()
    clearNativeStore(underStore)
    clearNativeStore(overStore)
    FieldView._nativeFreeUnder, FieldView._nativeFreeOver = {}, {}
    visibleCells = {}
    FieldView._nativeVisibleCells = visibleCells
    visiblePairs = {}
    FieldView._nativeVisiblePairs = visiblePairs
    nativeSlots.under, nativeSlots.over = 0, 0
    FieldView._nativeSpriteSlots = 0
    FieldView._nativeBaseBx, FieldView._nativeBaseBy = cx0, cy0
    FieldView._nativeViewCols, FieldView._nativeViewRows = cols, rows
    baseBx, baseBy = cx0, cy0
  end

  if reset then
    resetNative()
  elseif moved then
    for k in pairs(visiblePairs) do visiblePairs[k] = nil end
  end

  local function fill()
    for wy = cy0, cy0 + rows - 1 do
      local row = visibleCells[wy]
      if not row then
        row = {}
        visibleCells[wy] = row
      end
      for wx = cx0, cx0 + cols - 1 do
        local info = row[wx]
        if not info then
          info = addCell(wx, wy)
          if FieldView._nativeSwap then return false end
          row[wx] = info
        end
        if info.draw then visiblePairs[info.pair] = true end
      end
    end
    return true
  end

  FieldView._nativeSwap = false
  FieldView._nativeResetting = reset
  if not fill() then
    -- An atlas was reloaded while its cells were live: rebuild everything
    -- this frame rather than swap the batch under their sprite indices.
    FieldView._nativeSwap = false
    reset = true
    resetNative()
    FieldView._nativeResetting = true
    fill()
  end
  FieldView._nativeResetting = false
  FieldView._nativeSwap = false
  if reset then
    pruneNativeStore(underStore)
    pruneNativeStore(overStore)
  end
  if NativeTileset.trim and (FieldView._nativeTrimGen ~= NativeTileset._gen or FieldView._nativeLayout ~= layout) then
    FieldView._nativeTrimGen = NativeTileset._gen
    if NativeTileset.resident() > NativeTileset.RESIDENT_MAX then
      FieldView.trimNative(NativeTileset, Map, pair, visiblePairs)
    end
  end

  FieldView._nativeBx, FieldView._nativeBy = cx0, cy0
  FieldView._nativePair = pair
  FieldView._nativeLayout = layout
  FieldView._nativeVoid = voidMode
  FieldView._nativeDirty = false
  if reset or moved then
    local TilesetAnim = package.loaded["src.core.game3.tileset_anim"]
      or require("src.core.game3.tileset_anim")
    if TilesetAnim and TilesetAnim.setVisiblePairs then
      TilesetAnim.setVisiblePairs(visiblePairs)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  local ox = baseBx * CELL - camX
  local oy = baseBy * CELL - camY
  FieldView._nativeOverOx = ox
  FieldView._nativeOverOy = oy
  FieldView._nativeOverPair = pair
  FieldView._nativeCamX, FieldView._nativeCamY = camX, camY
  local from = FieldView._voidFrom
  drawLayer(FieldView._nativeBatches, pair, ox, oy, from and from.under, camX, camY)
  if from then
    from.t = from.t + 1
    if from.t >= FieldView.VOID_FADE_FRAMES then
      releaseVoidFrom(from)
      FieldView._voidFrom = nil
    end
  end
  FieldView._lastCamX, FieldView._lastCamY = camX, camY

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
  local from = FieldView._voidFrom
  drawLayer(batches, pair, ox, oy, from and from.over,
    FieldView._nativeCamX or 0, FieldView._nativeCamY or 0)
end

local function rseFamily()
  local Profile = package.loaded["src.core.game3.profile"] or require("src.core.game3.profile")
  local ok, row = pcall(Profile.forSession)
  return ok and row ~= nil and row.family == "rse"
end

-- pokeemerald/src/field_screen_effect.c:53
local function flashRadii()
  if not rseFamily() then return FLASH_LEVEL_RADIUS end
  local ok, FxRse = pcall(require, "src.core.game3.field_effects_rse")
  local m = ok and FxRse and FxRse.fc()
  return m and m.flashRadii or FLASH_LEVEL_RADIUS
end
FieldView.flashRadii = flashRadii

-- pokeemerald/src/field_screen_effect.c:54
function FieldView.maxFlashLevel()
  local t = flashRadii()
  if t == FLASH_LEVEL_RADIUS then return FieldView.MAX_FLASH_LEVEL end
  local n = 0
  for k in pairs(t) do if k > n then n = k end end
  return n
end

function FieldView.radiusForLevel(level)
  level = tonumber(level) or 0
  local t = flashRadii()
  return t[level] or t[0]
end

-- pokefirered/src/overworld.c:966
function FieldView.setFlashLevel(level)
  level = tonumber(level) or 0
  if level < 0 or level > FieldView.maxFlashLevel() then level = 0 end
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
  local FieldEffects = modFieldEffects()
  if FieldEffects and FieldEffects.animateFlashLevel then
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
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local flashFlag = Sem.flag(session, "flashActive")
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then
    local Flags = modFlags()
    if Flags and Flags.getFlag
        and Flags.getFlag(Space.store, nil, flashFlag) then
      return true
    end
  end
  local flags = session and session.flags
  return (flags and flags[flashFlag]) and true or false
end

-- pokefirered/src/overworld.c:958
local function mapIsCave(def)
  if def and def.cave ~= nil then return (tonumber(def.cave) or 0) ~= 0 end
  return false
end

-- pokefirered/src/overworld.c:956
function FieldView.defaultFlashLevel(game, mapId)
  if not mapIsCave(resolveMapDef(game, mapId)) then return 0 end
  if rseFamily() then
    -- pokeemerald/src/overworld.c:971
    if flashActive() then return 1 end
    return FieldView.maxFlashLevel() - 1
  end
  if flashActive() then return 0 end
  return FieldView.MAX_FLASH_LEVEL
end

-- pokeemerald/src/field_screen_effect.c:994
function FieldView.setPyramidLightRadius(radius)
  FieldView.setFlashRadius(radius)
end

-- pokeemerald/src/battle_pyramid.c:1187
function FieldView.setBgPaletteOverride(slot, pal16)
  local NativeTileset = require("src.core.game3.tileset_native")
  local prev = FieldView._bgPalOverride
  if prev and (pal16 == nil or prev.slot ~= slot) then
    NativeTileset.resetSlotPalette(prev.pair, prev.slot)
    FieldView._bgPalOverride = nil
  end
  if pal16 == nil then return true end
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map.currentDef and Map.currentDef()
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  if not pair then return false end
  if not NativeTileset.setSlotPalette(pair, slot, pal16) then return false end
  FieldView._bgPalOverride = { pair = pair, slot = slot }
  return true
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

  local SeagallopUi = modSeagallop()
  if SeagallopUi and SeagallopUi.isActive and SeagallopUi.isActive() then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

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
  local ShopMenu = modShopMenu()
  if ShopMenu and ShopMenu.isShopCamera and ShopMenu.isShopCamera() then
    local fx, fy = px, py
    if facing == "up" or facing == "north" then fy = fy - CELL
    elseif facing == "down" or facing == "south" then fy = fy + CELL
    elseif facing == "left" or facing == "west" then fx = fx - CELL
    elseif facing == "right" or facing == "east" then fx = fx + CELL
    else fx = fx - CELL end
    local fTileX = math.floor(fx / CELL)
    local fTileY = math.floor(fy / CELL)
    local off = ShopMenu.shopCameraOffset and ShopMenu.shopCameraOffset()
    if off then
      camX = (fTileX + off.x) * CELL
      camY = (fTileY + off.y) * CELL
    else
      camX = (fTileX - 2) * CELL
      camY = (fTileY - 4) * CELL
    end
  end

  FieldView._billboard = opts.billboard
    and { vw = canvasW, vh = canvasH } or nil
  FieldView._viewW, FieldView._viewH = canvasW, canvasH

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
      local FieldEffects = modFieldEffects()
      if FieldEffects and FieldEffects.drawBehind then
        FieldEffects.drawBehind(camX, camY)
      end
    end

    -- Door opening/closing animation overlays (under actors).
    do
      local Doors = modDoors()
      if Doors and Doors.draw then
        Doors.draw(camX, camY, canvasW, canvasH)
      end
    end
    local FieldWeather = modFieldWeather()
    if FieldWeather and FieldWeather.drawBelow then
      -- pokeemerald/src/field_weather_effect.c:1280
      FieldWeather.drawBelow(camX, camY, canvasW, canvasH)
    end
  end

  -- pokefirered/src/field_effect.c:910
  if not opts.actorsOnly then
    local Heal = modHeal()
    if Heal and Heal.drawBalls then
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
    local FieldEffects = modFieldEffects()
    if FieldEffects and FieldEffects.bgFlashAlpha then
      local a = FieldEffects.bgFlashAlpha()
      if a and a > 0 then
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  -- S.S. Anne wake (pret oam.priority = 2, subpriority = 0xFF: under boat hull).
  if not opts.actorsOnly then
    local SSAnne = modSSAnne()
    if SSAnne and SSAnne.drawWake then
      SSAnne.drawWake(camX, camY)
    end
  end

  -- Collect Game3 actors partitioned by OAM priority.
  local underActors, overActors = nil, nil
  -- pokefirered/src/credits.c:717
  if not (opts.skipActors or FieldView.hideActors) then
    underActors, overActors = collectGame3Actors(
      game, mapDef, camX, camY, px, py, facing, walkPhase, stepFlip, playerYOff, playerXOff)
  end

  -- Draw Game3 actors with normal priority (under BG1 / overhead layer).
  if underActors then
    for _, a in ipairs(underActors) do
      drawSingleActor(game, mapDef, a, camX, camY)
    end
    if usedNative and opts.endUnderActors then opts.endUnderActors(drawNativeOverTiles) end
  end

  -- pret BG1: metatile top layer covers normal OW sprites (roofs, desk counters, trees).
  if usedNative and not opts.actorsOnly then
    drawNativeOverTiles()
    local W = weatherMask()
    if W then W.writeActorMask(0, drawNativeOverTiles) end
  end

  -- Draw Game3 actors with elevated priority (over BG1 / overhead layer, e.g. bridges/cliffs/jumping/escalators).
  if overActors then
    for _, a in ipairs(overActors) do
      drawSingleActor(game, mapDef, a, camX, camY)
    end
  end

  -- Tall grass over feet (pret subpriority above avatar).
  if not opts.actorsOnly then
    local FieldEffects = modFieldEffects()
    if FieldEffects and FieldEffects.drawFront then
      FieldEffects.drawFront(camX, camY, py)
      local W = weatherMask()
      if W then W.writeActorMask(0, function() FieldEffects.drawFront(camX, camY, py) end) end
    end
  end

  if underActors or overActors then
    local LinkTags = package.loaded["src.ui.game3.link_tags"]
    if LinkTags and LinkTags.draw then
      LinkTags.draw(underActors, overActors, camX, camY, canvasW, canvasH,
        FieldView._billboard and pushBillboard or nil)
    end
  end

  -- pokefirered/src/field_effect.c:1024
  if not opts.actorsOnly then
    local Heal = modHeal()
    if Heal and Heal.drawMonitor then
      local sx, sy = screenAnchor(px, py, camX, camY)
      love.graphics.push()
      love.graphics.translate(sx, sy)
      Heal.drawMonitor(camX, camY)
      love.graphics.pop()
    end
  end

  -- Pokemon Center heal machine (screen-space OAM, pret FLDEFF_POKECENTER_HEAL).
  if not opts.actorsOnly then
    local FieldEffects = modFieldEffects()
    if FieldEffects and FieldEffects.drawOverlay then
      love.graphics.push()
      love.graphics.translate(screenOx, screenOy)
      FieldEffects.drawOverlay(camX, camY)
      love.graphics.pop()
    end
    local SSAnne = modSSAnne()
    if SSAnne and SSAnne.drawSmoke then
      SSAnne.drawSmoke(camX, camY)
    end
    local FieldWeather = modFieldWeather()
    if FieldWeather and FieldWeather.draw then
      FieldWeather.draw(camX, camY, canvasW, canvasH, opts.exchangeCanvas)
    end
  end

  if not opts.actorsOnly then
    local crisis = package.loaded["src.core.game3.rse.weather_flash_rs"]
    if crisis and crisis.drawField then crisis.drawField() end
  end
  drawFlashMask(canvasW, canvasH)

  love.graphics.setColor(1, 1, 1, 1)
end

--- Drop cached atlases/sprites (tileset hot-reload).
function FieldView.invalidate()
  local Plan = package.loaded["src.core.game3.field_plan"]
  if Plan then Plan.invalidate() end
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
  FieldView._nativeVisibleCells = nil
  FieldView._nativeVisiblePairs = nil
  FieldView._nativeFreeUnder, FieldView._nativeFreeOver = nil, nil
  FieldView._nativeSpriteSlots = 0
  nativeSlots.under, nativeSlots.over = 0, 0
  FieldView._nativeDirtyCells = nil
  FieldView._nativeLayout = nil
  FieldView._voidFrom, FieldView._voidMapDef = nil, nil
  FieldView._lastCamX, FieldView._lastCamY = nil, nil
  FieldView._nativeBx = nil
  FieldView._nativeBy = nil
  FieldView._nativeBaseBx = nil
  FieldView._nativeBaseBy = nil
  FieldView._nativeViewCols = nil
  FieldView._nativeViewRows = nil
  FieldView._nativePair = nil
  FieldView._nativeOverPair = nil
  FieldView._nativeDirty = true
  nativeAtlasByPair = {}
  FieldView._loggedNative = false
  FieldView._loggedNativeFallback = false
  FieldView._flashSpans = nil
  FieldView._flashSpanR = nil
  local NativeTileset = modNativeTileset()
  if NativeTileset and NativeTileset.invalidate then
    NativeTileset.invalidate()
  end
  local OwSprites = modOwSprites()
  if OwSprites and OwSprites.invalidate then
    OwSprites.invalidate()
  end
  local WeatherRse = package.loaded["src.core.game3.field_weather_rse"]
  if WeatherRse and WeatherRse.invalidate then WeatherRse.invalidate() end
  local FieldEffects = modFieldEffects()
  if FieldEffects and FieldEffects.invalidate then
    FieldEffects.invalidate()
  end
end

local Assets = require("src.render.Assets")
if Assets.register and not Assets._game3FieldInvalidatorRegistered then
  Assets._game3FieldInvalidatorRegistered = true
  Assets.register(function()
    local current = package.loaded["src.core.game3.field_view"]
    if current then current.invalidate() end
  end)
end

return FieldView
