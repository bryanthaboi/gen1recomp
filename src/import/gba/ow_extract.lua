-- Extract FRLG overworld object graphics (4bpp pics + OBJ pals) from ROM.
-- Pret: gObjectEventGraphicsInfoPointers + sObjectEventSpritePalettes.

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local ExtractMapEvents = require("src.import.gba.extract_map_events")

local OwExtract = {}

OwExtract.MAGIC = "SVOW"
OwExtract.FORMAT_VERSION = 1

local function u8(n)
  return string.char((tonumber(n) or 0) % 256)
end

local function u16le(n)
  n = (tonumber(n) or 0) % 65536
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function read_u16(s, i)
  return s:byte(i) + s:byte(i + 1) * 256
end

local function gba_off(ptr)
  return Versions.gbaToFile(ptr)
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

--- Load paletteTag → 16 BGR555 colors from sObjectEventSpritePalettes.
function OwExtract.loadPaletteTable(rom, version)
  version = version or {}
  local tableOff = version.ow_sprite_palettes or Versions.OW_SPRITE_PALETTES
  local palsByTag = {}
  for i = 0, 63 do
    local off = tableOff + i * 8
    local dataPtr = rom:u32(off)
    local tag = rom:u16(off + 4)
    if dataPtr == 0 and tag == 0 then break end
    local dataOff = gba_off(dataPtr)
    if dataOff and tag ~= 0 then
      local colors = {}
      for c = 0, 15 do
        colors[c] = rom:u16(dataOff + c * 2)
      end
      palsByTag[tag] = colors
    end
  end
  return palsByTag
end

local function read_graphics_info(rom, infoOff)
  local tileTag = rom:u16(infoOff)
  local paletteTag = rom:u16(infoOff + 2)
  local reflectionPaletteTag = rom:u16(infoOff + 4)
  local size = rom:u16(infoOff + 6)
  local width = rom:u16(infoOff + 8)
  if width >= 0x8000 then width = width - 0x10000 end
  local height = rom:u16(infoOff + 10)
  if height >= 0x8000 then height = height - 0x10000 end
  local flags = rom:get(infoOff + 12)
  local tracks = rom:get(infoOff + 13)
  local imagesPtr = rom:u32(infoOff + 0x1C)
  local animsPtr = rom:u32(infoOff + 0x18)
  return {
    tileTag = tileTag,
    paletteTag = paletteTag,
    reflectionPaletteTag = reflectionPaletteTag,
    size = size,
    width = math.abs(width),
    height = math.abs(height),
    paletteSlot = flags % 16,
    shadowSize = math.floor(flags / 16) % 4,
    inanimate = math.floor(flags / 64) % 2 == 1,
    tracks = tracks,
    imagesPtr = imagesPtr,
    animsPtr = animsPtr,
  }
end

--- Max imageValue referenced by anim table (capped).
local function max_anim_frame(rom, animsPtr, animCount)
  local aoff = gba_off(animsPtr)
  if not aoff then return 0 end
  animCount = animCount or 20
  local mx = 0
  for i = 0, animCount - 1 do
    local p = rom:u32(aoff + i * 4)
    local po = gba_off(p)
    if not po then break end
    for j = 0, 31 do
      local lo = rom:u16(po + j * 4)
      -- ANIMCMD_END = -2 as s16
      if lo == 0xFFFE then break end
      local w = rom:u32(po + j * 4)
      local img = w % 65536
      if img > mx then mx = img end
    end
  end
  return mx
end

--- Decode one 4bpp sprite frame (tile order: L→R, T→B 8×8) → indexed [w*h].
local function decode_frame_4bpp(raw, width, height)
  local pixels = {}
  local tilesX = math.floor(width / 8)
  local tilesY = math.floor(height / 8)
  local function nybble(byteIndex, high)
    local b
    if type(raw) == "string" then
      b = raw:byte(byteIndex + 1) or 0
    elseif raw._ffi then
      b = raw._ffi[byteIndex] or 0
    else
      b = raw[byteIndex + 1] or 0
    end
    if high then return math.floor(b / 16) % 16 end
    return b % 16
  end
  for ty = 0, tilesY - 1 do
    for tx = 0, tilesX - 1 do
      local tileIndex = ty * tilesX + tx
      local tileOff = tileIndex * 32
      for y = 0, 7 do
        for x = 0, 7 do
          local byteIndex = tileOff + y * 4 + math.floor(x / 2)
          local idx = nybble(byteIndex, x % 2 == 1)
          local px = tx * 8 + x
          local py = ty * 8 + y
          pixels[py * width + px + 1] = idx
        end
      end
    end
  end
  return pixels
end

local function load_frame_bytes(rom, dataPtr, nbytes)
  local off = gba_off(dataPtr)
  if not off then return nil end
  -- Uncompressed OW pics are the common case; try raw first.
  local raw = rom:readBytes(off, nbytes)
  if type(raw) == "table" then
    local s = {}
    for i = 1, nbytes do s[i] = string.char(raw[i] or 0) end
    return table.concat(s)
  end
  if type(raw) == "string" and #raw >= nbytes then
    return raw:sub(1, nbytes)
  end
  -- LZ fallback
  local ok, dec = pcall(Lz77.decompress, function(i) return rom:get(i) end, off)
  if ok and dec then
    if type(dec) == "string" then return dec:sub(1, nbytes) end
    local s = {}
    local n = math.min(nbytes, dec._len or #dec)
    for i = 1, n do
      s[i] = string.char((dec._ffi and dec._ffi[i - 1]) or dec[i] or 0)
    end
    return table.concat(s)
  end
  return nil
end

--- Extract one graphicsId → { w, h, frameCount, frames (indexed), palette (BGR555) }.
function OwExtract.extractOne(rom, graphicsId, palsByTag, version)
  version = version or {}
  local pointers = version.ow_gfx_pointers or Versions.OW_GFX_POINTERS
  local num = version.num_obj_event_gfx or Versions.NUM_OBJ_EVENT_GFX
  graphicsId = tonumber(graphicsId) or 0
  if graphicsId < 0 or graphicsId >= num then
    return nil, "graphicsId out of range"
  end
  local infoPtr = rom:u32(pointers + graphicsId * 4)
  local infoOff = gba_off(infoPtr)
  if not infoOff then return nil, "bad info ptr" end
  local info = read_graphics_info(rom, infoOff)
  local w, h = info.width, info.height
  if w < 8 or h < 8 or w > 128 or h > 128 then
    return nil, "bad dimensions"
  end
  -- Only ANIM_STD_* (0..19). Run/spin anims can reference higher indices
  -- that aren't in the base pic table for ordinary NPCs.
  local maxFrame = max_anim_frame(rom, info.animsPtr, 20)
  local frameCount = math.max(1, maxFrame + 1)
  if frameCount > 18 then frameCount = 18 end

  local imagesOff = gba_off(info.imagesPtr)
  if not imagesOff then return nil, "bad images ptr" end

  local expected = math.floor(w * h / 2)
  local frames = {}
  for i = 0, frameCount - 1 do
    local dataPtr = rom:u32(imagesOff + i * 8)
    local frameSize = rom:u16(imagesOff + i * 8 + 4)
    if frameSize < 1 then frameSize = expected end
    if frameSize > expected * 4 then frameSize = expected end
    local bytes = load_frame_bytes(rom, dataPtr, math.max(frameSize, expected))
    if not bytes or #bytes < expected then
      -- pad / blank
      frames[i + 1] = {}
      for p = 1, w * h do frames[i + 1][p] = 0 end
    else
      frames[i + 1] = decode_frame_4bpp(bytes, w, h)
    end
  end

  local pal = palsByTag and palsByTag[info.paletteTag]
  if not pal then
    pal = {}
    for c = 0, 15 do pal[c] = 0 end
  end

  return {
    graphicsId = graphicsId,
    width = w,
    height = h,
    frameCount = frameCount,
    frames = frames,
    paletteTag = info.paletteTag,
    palette = pal,
    inanimate = info.inanimate,
  }
end

--- Bake frames stacked vertically → RGBA8 string + meta.
function OwExtract.bakeRgba(sprite)
  local w, h = sprite.width, sprite.height
  local n = sprite.frameCount
  local pal = sprite.palette
  local rgb = {}
  for c = 0, 15 do
    local r, g, b = bgr555_to_rgb8(pal[c] or 0)
    rgb[c] = { r, g, b }
  end
  local chunks = {}
  for fi = 1, n do
    local frame = sprite.frames[fi]
    for py = 0, h - 1 do
      local line = {}
      for px = 0, w - 1 do
        local idx = frame[py * w + px + 1] or 0
        if idx == 0 then
          line[px + 1] = string.char(0, 0, 0, 0)
        else
          local c = rgb[idx] or rgb[0]
          line[px + 1] = string.char(c[1], c[2], c[3], 255)
        end
      end
      chunks[#chunks + 1] = table.concat(line)
    end
  end
  return table.concat(chunks), w, h * n
end

function OwExtract.encodeMeta(sprite)
  return table.concat({
    OwExtract.MAGIC,
    u8(OwExtract.FORMAT_VERSION),
    u8(sprite.inanimate and 1 or 0),
    u16le(sprite.graphicsId),
    u16le(sprite.width),
    u16le(sprite.height),
    u16le(sprite.frameCount),
    u16le(sprite.paletteTag or 0),
  })
end

function OwExtract.decodeMeta(blob)
  if type(blob) ~= "string" or #blob < 12 or blob:sub(1, 4) ~= OwExtract.MAGIC then
    return nil, "bad ow meta"
  end
  return {
    formatVersion = blob:byte(5),
    inanimate = blob:byte(6) == 1,
    graphicsId = read_u16(blob, 7),
    width = read_u16(blob, 9),
    height = read_u16(blob, 11),
    frameCount = read_u16(blob, 13),
    paletteTag = read_u16(blob, 15),
  }
end

--- Collect every OBJ_EVENT_GFX id (0 .. NUM-1).
function OwExtract.collectAllIds(version)
  version = version or {}
  local num = version.num_obj_event_gfx or Versions.NUM_OBJ_EVENT_GFX or 152
  local list = {}
  for g = 0, num - 1 do
    list[#list + 1] = g
  end
  return list
end

--- Collect graphicsIds used on Island 1 (+ player Red/Green).
function OwExtract.collectIsland1Ids(rom, version)
  local ids = { [0] = true, [7] = true } -- player
  local ok, events = pcall(ExtractMapEvents.extractIsland1, rom, version)
  if ok and events then
    local byMap = events
    for _, ev in pairs(type(byMap) == "table" and byMap or {}) do
      if type(ev) == "table" and ev.objects then
        for _, obj in ipairs(ev.objects) do
          local g = tonumber(obj.graphicsId or obj.graphics)
          if g then ids[g] = true end
        end
      end
    end
  end
  for _, g in ipairs({
    16, 19, 22, 24, 30, 32, 35, 39, 40, 43, 44, 45, 46, 54, 56, 57,
    62, 64, 65, 69, 73, 89, 92, 96, 108,
  }) do
    ids[g] = true
  end
  local list = {}
  for g in pairs(ids) do list[#list + 1] = g end
  table.sort(list)
  return list
end

--- Write ow/* sheets. opts.all=true extracts every OBJ_EVENT_GFX (firered default).
function OwExtract.writeExtract(rom, cache, root, version, opts)
  root = root or "data/generated/gba"
  opts = opts or {}
  local owRoot = root .. "/ow"
  version = version or Versions.lookup(rom.md5) or {}
  local palsByTag = OwExtract.loadPaletteTable(rom, version)
  local extractAll = opts.all
  if extractAll == nil then
    -- Standalone firered cache wants the full table; Island-1 demake can pass all=false.
    extractAll = (root:find("data/generated/gba", 1, true) ~= nil) or opts.firered == true
  end
  local ids = extractAll and OwExtract.collectAllIds(version)
    or OwExtract.collectIsland1Ids(rom, version)
  local manifest = {
    ow_version = Versions.OW_VERSION or 1,
    sprites = {},
  }
  local okCount = 0
  for _, gid in ipairs(ids) do
    local spr, err = OwExtract.extractOne(rom, gid, palsByTag, version)
    if spr then
      local rgba, aw, ah = OwExtract.bakeRgba(spr)
      local meta = OwExtract.encodeMeta(spr)
      cache:write(owRoot .. "/" .. gid .. ".meta", meta)
      cache:write(owRoot .. "/" .. gid .. ".rgba", rgba)
      manifest.sprites[gid] = {
        width = spr.width,
        height = spr.height,
        frameCount = spr.frameCount,
        paletteTag = spr.paletteTag,
        inanimate = spr.inanimate,
        atlasW = aw,
        atlasH = ah,
      }
      okCount = okCount + 1
    else
      print("[ow] skip gfx " .. tostring(gid) .. ": " .. tostring(err))
    end
  end
  local lines = {
    "return {\n",
    ("  ow_version = %d,\n"):format(manifest.ow_version),
    ("  count = %d,\n"):format(okCount),
    ("  total = %d,\n"):format(#ids),
    "  sprites = {\n",
  }
  for _, gid in ipairs(ids) do
    local s = manifest.sprites[gid]
    if s then
      lines[#lines + 1] = ("    [%d] = { width = %d, height = %d, frameCount = %d, paletteTag = %d, inanimate = %s, atlasW = %d, atlasH = %d },\n"):format(
        gid, s.width, s.height, s.frameCount, s.paletteTag,
        s.inanimate and "true" or "false", s.atlasW, s.atlasH)
    end
  end
  lines[#lines + 1] = "  },\n}\n"
  cache:write(owRoot .. "/manifest.lua", table.concat(lines))
  print(string.format("[ow] extracted %d / %d object graphics → %s", okCount, #ids, owRoot))
  return manifest
end

function OwExtract.ready(cache, root)
  root = root or "data/generated/gba"
  return cache and cache:exists(root .. "/ow/manifest.lua")
end

return OwExtract
