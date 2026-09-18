-- Game3 Door & Entrance Animation and Audio Engine (FRLG / GBA).
-- Implements:
-- 1. Exact sound selection per door type (SE_SLIDING_DOOR vs SE_DOOR vs SE_EXIT).
-- 2. Multi-frame door opening and closing state machine (1x1 and 1x2 sizes).
-- 3. Script opcode integration (opendoor, closedoor, waitdooranim).
-- 4. Warp / field transition coordination.

local SE = require("src.core.game3.se_ids")

local Doors = {}

Doors.SOUND_NORMAL = SE.SE_DOOR or 241
Doors.SOUND_SLIDING = SE.SE_SLIDING_DOOR or 18
Doors.SOUND_EXIT = SE.SE_EXIT or 238

Doors.FRAME_TICKS = 4 -- 4 engine frames per door animation step (FRLG standard)
Doors.NUM_FRAMES = 3  -- 3 animation frames (0: closed, 1: half, 2: fully open)

-- Active door animation state
Doors._activeAnim = nil
Doors._manifest = nil
Doors._sheets = {} -- [tileName] = { image, quads, width, height, frame_width, frame_height, frames }
Doors._manifestLoaded = false

local function loadManifest()
  if Doors._manifestLoaded then return Doors._manifest end
  Doors._manifestLoaded = true

  local ok, manifest = pcall(require, "data.generated.gba.doors.manifest")
  if ok and type(manifest) == "table" then
    Doors._manifest = manifest
    return manifest
  end

  -- Fallback attempt reading directly
  local manifestPath = "data/generated/gba/doors/manifest.lua"
  local f = io.open(manifestPath, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local chunk = load(content, "@" .. manifestPath, "t", {})
    if chunk then
      Doors._manifest = chunk()
    end
  end
  return Doors._manifest
end

Doors._layoutCache = {}

local function isPairMatch(doorTileset, pair)
  if not doorTileset or doorTileset == "primary" then return true end
  local p = string.lower(tostring(pair or ""))
  if p == "" then return false end
  if doorTileset == "pallet" and (p:find("pallet") or p:find("oaks_lab")) then return true end
  if doorTileset == "viridian" and p:find("viridian") then return true end
  if doorTileset == "pewter" and p:find("pewter_outdoor") then return true end
  if doorTileset == "saffron" and p:find("saffron") then return true end
  if doorTileset == "cerulean" and p:find("cerulean") then return true end
  if doorTileset == "lavender" and p:find("lavender") then return true end
  if doorTileset == "vermilion" and p:find("vermilion") then return true end
  if doorTileset == "celadon" and p:find("celadon") then return true end
  if doorTileset == "fuchsia" and p:find("fuchsia") then return true end
  if doorTileset == "cinnabar" and p:find("cinnabar") then return true end
  if doorTileset == "sevii_123" and (p:find("sevii_outdoor") or p:find("sevii_123") or p:find("one_island") or p:find("two_island") or p:find("three_island")) then return true end
  if doorTileset == "sevii_45" and (p:find("sevii_45") or p:find("four_island") or p:find("five_island") or p:find("rocket_warehouse")) then return true end
  if doorTileset == "sevii_67" and (p:find("sevii_67") or p:find("six_island") or p:find("seven_island")) then return true end
  if doorTileset == "dept_store" and (p:find("dept_store") or p:find("department_store")) then return true end
  if doorTileset == "cable_club" and (p:find("cable_club") or p:find("network") or p:find("pokemon_center")) then return true end
  if doorTileset == "silph_co" and (p:find("silph_co") or p:find("rocket_hideout")) then return true end
  if doorTileset == "ss_anne" and p:find("ss_anne") then return true end
  if doorTileset == "sea_cottage" and p:find("sea_cottage") then return true end
  if doorTileset == "trainer_tower" and p:find("trainer_tower") then return true end
  return false
end

local function resolveLayout(mapId)
  if not mapId then return nil end
  local function norm(m)
    return tostring(m or ""):gsub("^FR_", ""):gsub("^MAP_", "")
  end
  local key = norm(mapId)

  local Map = package.loaded["src.core.game3.map"]
  if Map and Map._def and Map._def.midLayout then
    if norm(Map.current) == key or norm(Map._def.id or Map._def.name) == key then
      return Map._def.midLayout, Map._def.pair
    end
  end

  if Map and Map.neighbors then
    for _, n in pairs(Map.neighbors) do
      if n.def and n.def.midLayout then
        if norm(n.map or n.mapId) == key then
          return n.def.midLayout, n.def.pair
        end
      end
    end
  end

  local Runtime = package.loaded["src.core.game3.runtime"]
  local g = Runtime and Runtime._game
  if g and g.data and g.data.maps then
    local m = g.data.maps[mapId] or g.data.maps["FR_" .. key] or g.data.maps[key]
    if m and m.midLayout then
      return m.midLayout, m.pair
    end
  end

  if Doors._layoutCache[key] ~= nil then
    local cached = Doors._layoutCache[key]
    if cached then return cached, cached.pair end
    return nil, nil
  end

  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset then
    local cache = Dataset.cache and Dataset.cache()
    if cache then
      local rel1 = "data/generated/gba/native/layouts/" .. mapId .. ".mid"
      local rel2 = "data/generated/gba/native/layouts/FR_" .. key .. ".mid"
      local rel3 = "data/generated/gba/native/layouts/" .. key .. ".mid"
      local blob = cache:read(rel1) or cache:read(rel2) or cache:read(rel3)
      if blob then
        local pair = nil
        local okM, natManifest = pcall(require, "data.generated.gba.native.manifest")
        if okM and natManifest and natManifest.layouts then
          local info = natManifest.layouts[mapId] or natManifest.layouts["FR_" .. key] or natManifest.layouts[key]
          pair = info and info.pair
        end
        if not pair then
          local okV, Versions = pcall(require, "src.import.gba.versions")
          if okV and Versions and Versions.MAPS then
            local spec = Versions.MAPS[mapId] or Versions.MAPS["FR_" .. key] or Versions.MAPS[key]
            pair = spec and spec.pair
          end
        end
        local NativePack = require("src.import.gba.native_pack")
        local LayoutNative = require("src.core.game3.layout_native")
        local decoded = NativePack.decodeMidLayout(blob)
        if decoded then
          local layout = LayoutNative.fromDecoded(decoded, mapId, pair)
          Doors._layoutCache[key] = layout
          return layout, pair
        end
      end
    end
  end

  Doors._layoutCache[key] = false
  return nil, nil
end

--- Get door metadata entry for a map tile at (x, y) if available
function Doors.getDoorEntryAt(mapId, x, y)
  local manifest = loadManifest()
  if not manifest or not manifest.by_mid then return nil end

  local layout, pair = resolveLayout(mapId)
  local mid = nil
  if layout and layout.midAt then
    mid = layout:midAt(x, y)
  end

  if mid and manifest.by_mid[mid] then
    local entry = manifest.by_mid[mid]
    local p = pair or (layout and layout.pair)
    if isPairMatch(entry.tileset, p) then
      local doorInfo = manifest.doors and manifest.doors[entry.tile]
      return entry, doorInfo
    end
  end

  return nil
end

--- Determine the exact sound effect and door animation kind for a warp / doorway
function Doors.getSoundForWarp(mapId, x, y, destMap, isDoor)
  if isDoor == false then
    return Doors.SOUND_EXIT, "exit"
  end

  -- Check ROM metatile manifest first at (mapId, x, y)
  if x and y then
    local entry, _ = Doors.getDoorEntryAt(mapId, x, y)
    if entry then
      local snd = (entry.sound == "sliding") and Doors.SOUND_SLIDING or Doors.SOUND_NORMAL
      return snd, entry.tile
    end
  end

  local mapUpper = string.upper(tostring(mapId or ""))
  local destUpper = string.upper(tostring(destMap or ""))

  -- Double sliding doors: Celadon Dept Store, Silph Co
  local isDouble = destUpper:find("DEPT_STORE")
    or destUpper:find("SILPH_CO")
    or mapUpper:find("DEPT_STORE")
    or mapUpper:find("SILPH_CO")

  if isDouble then
    return Doors.SOUND_SLIDING, "sliding_double"
  end

  -- Sliding doors: Poké Center, Mart, Dept Store, Silph Co, Safari Zone, Game Corner, Elevators
  local isSliding = destUpper:find("POKECENTER")
    or destUpper:find("POKEMON_CENTER")
    or destUpper:find("CENTER")
    or destUpper:find("MART")
    or destUpper:find("SAFARI_ZONE")
    or destUpper:find("GAME_CORNER")
    or destUpper:find("CABLE_CLUB")
    or destUpper:find("ELEVATOR")
    or destUpper:find("TELEPORTER")
    or mapUpper:find("POKECENTER")
    or mapUpper:find("POKEMON_CENTER")
    or mapUpper:find("CENTER")
    or mapUpper:find("MART")
    or mapUpper:find("SAFARI_ZONE")
    or mapUpper:find("GAME_CORNER")

  if isSliding then
    return Doors.SOUND_SLIDING, "sliding"
  end

  return Doors.SOUND_NORMAL, "normal"
end

local function resolveDoorKind(mapId, x, y, destMap, sound)
  if x and y then
    local entry, _ = Doors.getDoorEntryAt(mapId, x, y)
    if entry then
      return entry.tile, entry.size
    end
  end
  if sound == Doors.SOUND_SLIDING then
    return "SlidingSingle", "1x1"
  end
  return "General", "1x1"
end

--- Start door opening animation + sound
function Doors.open(mapId, x, y, opts, onDone)
  opts = opts or {}
  local sound, defaultKind = Doors.getSoundForWarp(mapId, x, y, opts.destMap, true)
  if opts.sound then sound = opts.sound end

  local tile, size = resolveDoorKind(mapId, x, y, opts.destMap, sound)

  if opts.playSound ~= false then
    local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
    if Audio and Audio.playSe then
      Audio.playSe(sound)
    end
  end

  Doors._activeAnim = {
    mapId = mapId,
    x = x,
    y = y,
    kind = defaultKind or ((sound == Doors.SOUND_SLIDING) and "sliding" or "normal"),
    tile = tile,
    size = size or "1x1",
    mode = "open",
    frame = 0,
    timer = 0,
    targetFrame = Doors.NUM_FRAMES - 1,
    onDone = onDone,
  }
  return Doors._activeAnim
end

--- Set door at (mapId, x, y) immediately to fully open (frame 2) in hold mode
function Doors.holdOpen(mapId, x, y, opts)
  opts = opts or {}
  local sound, defaultKind = Doors.getSoundForWarp(mapId, x, y, opts.destMap, true)
  if opts.sound then sound = opts.sound end

  local tile, size = resolveDoorKind(mapId, x, y, opts.destMap, sound)

  Doors._activeAnim = {
    mapId = mapId,
    x = x,
    y = y,
    kind = defaultKind or ((sound == Doors.SOUND_SLIDING) and "sliding" or "normal"),
    tile = tile,
    size = size or "1x1",
    mode = "hold",
    frame = Doors.NUM_FRAMES - 1,
    timer = 0,
    targetFrame = Doors.NUM_FRAMES - 1,
  }
  return Doors._activeAnim
end

--- Start door closing animation + sound
function Doors.close(mapId, x, y, opts, onDone)
  opts = opts or {}
  local sound, defaultKind = Doors.getSoundForWarp(mapId, x, y, opts.destMap, true)
  if opts.sound then sound = opts.sound end

  local tile, size = resolveDoorKind(mapId, x, y, opts.destMap, sound)

  Doors._activeAnim = {
    mapId = mapId,
    x = x,
    y = y,
    kind = defaultKind or ((sound == Doors.SOUND_SLIDING) and "sliding" or "normal"),
    tile = tile,
    size = size or "1x1",
    mode = "close",
    frame = Doors.NUM_FRAMES - 1,
    timer = 0,
    targetFrame = 0,
    onDone = function()
      if opts.playSound ~= false then
        local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
        if Audio and Audio.playSe then
          Audio.playSe(sound)
        end
      end
      if onDone then onDone() end
    end,
  }
  return Doors._activeAnim
end

--- Start door closing animation after a delay (beat) in ticks
function Doors.closeAfterDelay(mapId, x, y, delayTicks, opts, onDone)
  opts = opts or {}
  local sound, defaultKind = Doors.getSoundForWarp(mapId, x, y, opts.destMap, true)
  if opts.sound then sound = opts.sound end

  local tile, size = resolveDoorKind(mapId, x, y, opts.destMap, sound)

  Doors._activeAnim = {
    mapId = mapId,
    x = x,
    y = y,
    kind = defaultKind or ((sound == Doors.SOUND_SLIDING) and "sliding" or "normal"),
    tile = tile,
    size = size or "1x1",
    mode = "delay_close",
    frame = Doors.NUM_FRAMES - 1,
    timer = 0,
    delayTimer = delayTicks or 10,
    targetFrame = 0,
    onDone = function()
      if opts.playSound == true then
        local Audio = package.loaded["src.core.game3.audio"] or require("src.core.game3.audio")
        if Audio and Audio.playSe then
          Audio.playSe(sound)
        end
      end
      if onDone then onDone() end
    end,
  }
  return Doors._activeAnim
end

--- Advance active animation frame
function Doors.update(dt)
  local anim = Doors._activeAnim
  if not anim then return end

  if anim.mode == "delay_close" then
    anim.delayTimer = (anim.delayTimer or 1) - 1
    if anim.delayTimer <= 0 then
      anim.mode = "close"
      anim.timer = 0
    end
    return
  end

  if anim.mode == "hold" then
    return
  end

  anim.timer = anim.timer + 1
  if anim.timer >= Doors.FRAME_TICKS then
    anim.timer = 0
    if anim.mode == "open" then
      if anim.frame < anim.targetFrame then
        anim.frame = anim.frame + 1
      else
        local cb = anim.onDone
        anim.onDone = nil
        anim.mode = "hold" -- Hold open frame while player steps through
        if cb then cb() end
      end
    elseif anim.mode == "close" then
      if anim.frame > anim.targetFrame then
        anim.frame = anim.frame - 1
      else
        local cb = anim.onDone
        Doors._activeAnim = nil
        if cb then cb() end
      end
    end
  end
end

--- Check if door at (mapId, x, y) is currently animating
function Doors.getActiveAnim(mapId, x, y)
  local anim = Doors._activeAnim
  if anim and (not mapId or anim.mapId == mapId) and (not x or anim.x == x) and (not y or anim.y == y) then
    return anim
  end
  return nil
end

--- Check if door at (mapId, x, y) is fully open / holding open
function Doors.isOpen(mapId, x, y)
  local anim = Doors._activeAnim
  if anim and (not mapId or anim.mapId == mapId) and (not x or anim.x == x) and (not y or anim.y == y) then
    return anim.frame >= (Doors.NUM_FRAMES - 1)
  end
  return false
end

local function loadSheet(tileName)
  if not tileName then return nil end
  if Doors._sheets[tileName] ~= nil then
    return Doors._sheets[tileName]
  end

  if not (love and love.image and love.graphics and love.image.newImageData) then
    return nil
  end

  local manifest = loadManifest()
  local info = manifest and manifest.doors and manifest.doors[tileName]
  if not info then
    Doors._sheets[tileName] = false
    return nil
  end

  local relPath = "data/generated/gba/doors/" .. info.file
  local bytes = nil

  if love.filesystem and love.filesystem.read then
    local readBytes = love.filesystem.read(relPath)
    if readBytes then bytes = readBytes end
  end

  if not bytes then
    local f = io.open(relPath, "rb")
    if f then
      bytes = f:read("*a")
      f:close()
    end
  end

  if not bytes or #bytes < (info.width * info.height * 4) then
    Doors._sheets[tileName] = false
    return nil
  end

  local ok, imgData = pcall(love.image.newImageData, info.width, info.height, "rgba8", bytes)
  if not ok or not imgData then
    imgData = love.image.newImageData(info.width, info.height)
    local i = 1
    for y = 0, info.height - 1 do
      for x = 0, info.width - 1 do
        local r = (bytes:byte(i) or 0) / 255
        local g = (bytes:byte(i + 1) or 0) / 255
        local b = (bytes:byte(i + 2) or 0) / 255
        local a = (bytes:byte(i + 3) or 0) / 255
        imgData:setPixel(x, y, r, g, b, a)
        i = i + 4
      end
    end
  end

  local img = love.graphics.newImage(imgData)
  if img.setFilter then img:setFilter("nearest", "nearest") end

  local quads = {}
  local frameH = info.frame_height
  local frameW = info.frame_width
  for fi = 0, info.frames - 1 do
    quads[fi] = love.graphics.newQuad(0, fi * frameH, frameW, frameH, info.width, info.height)
  end

  local sheet = {
    image = img,
    quads = quads,
    width = info.width,
    height = info.height,
    frame_width = frameW,
    frame_height = frameH,
    frames = info.frames,
  }
  Doors._sheets[tileName] = sheet
  return sheet
end

--- Draw active door animation overlay
function Doors.draw(camX, camY)
  local anim = Doors._activeAnim
  if not anim then return end
  if not (love and love.graphics and love.graphics.rectangle) then return end

  local CELL = 16
  local sx = anim.x * CELL - (camX or 0)
  local sy = anim.y * CELL - (camY or 0)

  -- Viewport bounds check
  if sx < -CELL or sy < -32 or sx > 256 or sy > 176 then
    return
  end

  local tileName = anim.tile
  if not tileName then
    local entry, _ = Doors.getDoorEntryAt(anim.mapId, anim.x, anim.y)
    if entry then tileName = entry.tile end
  end

  local sheet = tileName and loadSheet(tileName)

  if sheet and sheet.image and sheet.quads then
    local frame = math.min(anim.frame, sheet.frames - 1)
    local yOffset = (sheet.frame_height > 16) and 16 or 0

    -- Authentic black interior background behind the door graphic
    love.graphics.setColor(0.05, 0.07, 0.1, 1)
    love.graphics.rectangle("fill", sx, sy - yOffset, sheet.frame_width, sheet.frame_height)

    -- Draw authentic ROM-derived door quad
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sheet.image, sheet.quads[frame], sx, sy - yOffset)
    return
  end

  -- Fallback vector drawing when sheets are unavailable
  if anim.frame == 0 then return end

  love.graphics.setColor(0.05, 0.07, 0.1, 1)
  love.graphics.rectangle("fill", sx + 1, sy + 1, 14, 15)

  if anim.kind == "sliding_double" then
    if anim.frame == 1 then
      love.graphics.setColor(0.65, 0.8, 0.88, 0.95)
      love.graphics.rectangle("fill", sx + 1, sy + 1, 4, 14)
      love.graphics.setColor(0.35, 0.5, 0.6, 1)
      love.graphics.rectangle("line", sx + 1, sy + 1, 4, 14)
      love.graphics.setColor(0.65, 0.8, 0.88, 0.95)
      love.graphics.rectangle("fill", sx + 11, sy + 1, 4, 14)
      love.graphics.setColor(0.35, 0.5, 0.6, 1)
      love.graphics.rectangle("line", sx + 11, sy + 1, 4, 14)
    end
  elseif anim.kind == "sliding" or anim.kind == "SlidingSingle" then
    if anim.frame == 1 then
      love.graphics.setColor(0.65, 0.8, 0.88, 0.95)
      love.graphics.rectangle("fill", sx + 8, sy + 1, 7, 14)
      love.graphics.setColor(0.35, 0.5, 0.6, 1)
      love.graphics.rectangle("line", sx + 8, sy + 1, 7, 14)
      love.graphics.setColor(0.85, 0.95, 1.0, 0.8)
      love.graphics.line(sx + 10, sy + 2, sx + 10, sy + 13)
    end
  else
    if anim.frame == 1 then
      love.graphics.setColor(0.62, 0.42, 0.24, 0.95)
      love.graphics.rectangle("fill", sx + 8, sy + 1, 7, 14)
      love.graphics.setColor(0.35, 0.22, 0.1, 1)
      love.graphics.rectangle("line", sx + 8, sy + 1, 7, 14)
      love.graphics.setColor(0.45, 0.28, 0.14, 0.8)
      love.graphics.line(sx + 11, sy + 2, sx + 11, sy + 13)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function Doors.isBusy()
  local anim = Doors._activeAnim
  return anim ~= nil and (anim.mode == "open" or anim.mode == "close" or anim.mode == "delay_close")
end

function Doors.reset()
  Doors._activeAnim = nil
end

return Doors



