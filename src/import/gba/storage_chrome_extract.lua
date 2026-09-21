-- Pokémon Storage System chrome extractor: PC UI sheets and the 16 box
-- wallpapers, decoded straight out of the FRLG ROM into CacheFS

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BattleAnimExtract = require("src.import.gba.battle_anim_extract")

local StorageChromeExtract = {}

StorageChromeExtract.CACHE_SUB = "pokemon/storage"
StorageChromeExtract.FORMAT_VERSION = 3

StorageChromeExtract.WALLPAPER_NAMES = {
  "forest", "city", "desert", "savanna",
  "crag", "volcano", "snow", "cave",
  "beach", "seafloor", "river", "sky",
  "stars", "pokecenter", "tiles", "simple",
}

StorageChromeExtract.TEXTURE_FILES = {
  { key = "cursor", file = "cursor.png" },
  { key = "cursor_shadow", file = "cursor_shadow.png" },
  { key = "arrow", file = "box_scroll_arrow.png" },
  { key = "menu", file = "menu.png" },
  { key = "menu_pal0", file = "menu_pal0.png" },
  { key = "scrolling_bg", file = "scrolling_bg.png" },
  { key = "waveform", file = "waveform.png" },
  { key = "frame", file = "interface_frame.png" },
  { key = "button_party", file = "button_party.png" },
  { key = "button_close", file = "button_close.png" },
  { key = "party_drawer_bg", file = "party_drawer_bg.png" },
  { key = "party_drawer_full", file = "party_drawer_full.png" },
  { key = "party_slot_filled", file = "party_slot_filled.png" },
  { key = "party_slot_empty", file = "party_slot_empty.png" },
}

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function get_byte(rom, off)
  if rom.get then return rom:get(off) end
  if rom.data then return rom.data:byte(off + 1) or 0 end
  return 0
end

local function get_u16(rom, off)
  return get_byte(rom, off) + get_byte(rom, off + 1) * 256
end

local function get_u32(rom, off)
  return get_byte(rom, off)
    + get_byte(rom, off + 1) * 256
    + get_byte(rom, off + 2) * 65536
    + get_byte(rom, off + 3) * 16777216
end

local function ptr_to_offset(addr)
  if not addr or addr < 0x08000000 or addr >= 0x0A000000 then return nil end
  return addr - 0x08000000
end

local function ensure_dir(dir)
  pcall(function()
    local lfs = require("lfs")
    local current = ""
    for part in dir:gmatch("[^/]+") do
      current = current == "" and part or (current .. "/" .. part)
      lfs.mkdir(current)
    end
  end)
end

local function write_file(cache, path, data)
  if cache and cache.write then
    cache:write(path, data)
    return true
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.write then
    local ok = pcall(CacheFs.write, path, data)
    if ok then return true end
  end
  if love and love.filesystem and love.filesystem.write then
    local ok = pcall(love.filesystem.write, path, data)
    if ok then return true end
  end
  local dir = path:match("^(.*)/[^/]+$")
  if dir then ensure_dir(dir) end
  local f = io.open(path, "wb")
  if f then
    f:write(data)
    f:close()
    return true
  end
  return false
end

local function read_palette(rom, off, count)
  local pal = {}
  for i = 0, count - 1 do
    local c = get_u16(rom, off + i * 2) % 32768
    local r = math.floor((c % 32) * 255 / 31 + 0.5)
    local g = math.floor((math.floor(c / 32) % 32) * 255 / 31 + 0.5)
    local b = math.floor((math.floor(c / 1024) % 32) * 255 / 31 + 0.5)
    pal[i] = { r, g, b, 255 }
  end
  return pal
end

local function read_sheet(rom, spec)
  if not spec then return nil end
  if spec.lz then
    local ok, bytes = pcall(Lz77.decompress, function(i) return get_byte(rom, i) end, spec.off)
    if not ok then return nil end
    return bytes, Lz77.len(bytes)
  end
  local bytes = {}
  for i = 1, spec.size do bytes[i] = get_byte(rom, spec.off + i - 1) end
  return bytes, spec.size
end

local function read_tilemap(rom, spec)
  if not spec then return nil end
  local entries = {}
  if spec.lz then
    local ok, bytes = pcall(Lz77.decompress, function(i) return get_byte(rom, i) end, spec.off)
    if not ok then return nil end
    local n = math.floor(Lz77.len(bytes) / 2)
    for i = 1, n do
      entries[i] = (bytes[i * 2 - 1] or 0) + (bytes[i * 2] or 0) * 256
    end
  else
    for i = 1, spec.w * spec.h do
      entries[i] = get_u16(rom, spec.off + (i - 1) * 2)
    end
  end
  return entries
end

local function blit_tile(px, imgW, tiles, tileIndex, pal, dx, dy, hflip, vflip)
  local base = tileIndex * 32
  for row = 0, 7 do
    local srcRow = vflip and (7 - row) or row
    for col = 0, 7 do
      local srcCol = hflip and (7 - col) or col
      local byte = tiles[base + srcRow * 4 + math.floor(srcCol / 2) + 1] or 0
      local idx = (srcCol % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      local o = ((dy + row) * imgW + (dx + col)) * 4 + 1
      if idx == 0 then
        px[o], px[o + 1], px[o + 2], px[o + 3] = 0, 0, 0, 0
      else
        local c = pal[idx] or { 0, 0, 0, 255 }
        px[o], px[o + 1], px[o + 2], px[o + 3] = c[1], c[2], c[3], 255
      end
    end
  end
end

function StorageChromeExtract.bakeSheet(tiles, byteLen, pal, cols)
  local tileCount = math.floor(byteLen / 32)
  if tileCount < 1 then return nil end
  local rows = math.ceil(tileCount / cols)
  local w, h = cols * 8, rows * 8
  local px = {}
  for i = 1, w * h * 4 do px[i] = 0 end
  for t = 0, tileCount - 1 do
    blit_tile(px, w, tiles, t, pal, (t % cols) * 8, math.floor(t / cols) * 8, false, false)
  end
  return BattleAnimExtract.encodePng(px, w, h), w, h
end

function StorageChromeExtract.bakeTilemap(entries, w, h, tiles, pals, palBase, tileBase)
  if not (entries and tiles) then return nil end
  local imgW, imgH = w * 8, h * 8
  local px = {}
  for i = 1, imgW * imgH * 4 do px[i] = 0 end
  local bankCount = #pals
  for i = 0, w * h - 1 do
    local e = entries[i + 1] or 0
    local tile = e % 1024 - (tileBase or 0)
    local hflip = math.floor(e / 1024) % 2 == 1
    local vflip = math.floor(e / 2048) % 2 == 1
    local bank = math.floor(e / 4096) - (palBase or 0)
    if bank < 0 then bank = 0 end
    if bank >= bankCount then bank = bankCount - 1 end
    if tile >= 0 then
      blit_tile(px, imgW, tiles, tile, pals[bank + 1], (i % w) * 8, math.floor(i / w) * 8, hflip, vflip)
    end
  end
  return BattleAnimExtract.encodePng(px, imgW, imgH), imgW, imgH
end

-- src/pokemon_storage_system_tasks.c:2484
local function fill_party_slots(drawer, slotTiles)
  local out = {}
  for i, v in ipairs(drawer) do out[i] = v end
  for pos = 1, 5 do
    local index = 3 * (3 * (pos - 1) + 1) * 4 + 7
    local src = 0
    for i = 0, 2 do
      for j = 0, 3 do
        out[index + i * 12 + j + 1] = slotTiles[src + j + 1] or out[index + i * 12 + j + 1]
      end
      src = src + 4
    end
  end
  return out
end

function StorageChromeExtract.ready(cache, root)
  root = root or default_cache_root()
  local outDir = root .. "/" .. StorageChromeExtract.CACHE_SUB
  local function valid_file(rel, minSize)
    minSize = minSize or 1
    if cache and cache.read then
      local data = cache:read(rel)
      return (data and #data >= minSize) or false
    end
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      local data = CacheFs.readActive(rel)
      if data and #data >= minSize then return true end
    end
    if love and love.filesystem and love.filesystem.read then
      local ok, data = pcall(love.filesystem.read, rel)
      if ok and data and #data >= minSize then return true end
    end
    local f = io.open(rel, "rb")
    if f then
      local data = f:read(minSize)
      f:close()
      if data and #data >= minSize then return true end
    end
    return false
  end

  local manifestData = nil
  if cache and cache.read then
    manifestData = cache:read(outDir .. "/manifest.lua")
  end
  if not manifestData then
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      manifestData = CacheFs.readActive(outDir .. "/manifest.lua")
    end
  end
  if not manifestData and love and love.filesystem and love.filesystem.read then
    local ok, d = pcall(love.filesystem.read, outDir .. "/manifest.lua")
    if ok then manifestData = d end
  end
  if not manifestData then
    local f = io.open(outDir .. "/manifest.lua", "rb")
    if f then manifestData = f:read("*a"); f:close() end
  end
  if not manifestData then return false end
  local v = tonumber(manifestData:match("version%s*=%s*(%d+)"))
  if v ~= StorageChromeExtract.FORMAT_VERSION then return false end

  for _, tex in ipairs(StorageChromeExtract.TEXTURE_FILES) do
    if not valid_file(outDir .. "/" .. tex.file, 30) then return false end
  end
  for _, wp in ipairs(StorageChromeExtract.WALLPAPER_NAMES) do
    if not valid_file(outDir .. "/wallpapers/" .. wp .. ".png", 50) then return false end
  end
  return true
end

function StorageChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  opts.cache = cache or opts.cache
  return StorageChromeExtract.extract(rom, opts)
end

function StorageChromeExtract.extract(rom, opts)
  opts = opts or {}
  local cache = opts.cache
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local outDir = cacheRoot .. "/" .. StorageChromeExtract.CACHE_SUB

  if not opts.force and StorageChromeExtract.ready(cache, cacheRoot) then
    return { ok = true, root = outDir, skipped = true }
  end
  if not rom then
    return { ok = false, root = outDir, count = 0, err = "storage chrome needs a ROM" }
  end

  ensure_dir(outDir)
  ensure_dir(outDir .. "/wallpapers")

  local palOff = Versions.STORAGE_PALETTES or {}
  local sheetOff = Versions.STORAGE_SHEETS or {}
  local mapOff = Versions.STORAGE_TILEMAPS or {}

  local pal = {}
  for name, off in pairs(palOff) do pal[name] = read_palette(rom, off, 16) end

  local sheet, sheetLen = {}, {}
  for name, spec in pairs(sheetOff) do
    local bytes, len = read_sheet(rom, spec)
    sheet[name], sheetLen[name] = bytes, len
  end

  local written, manifestTextures = 0, {}
  local function emit(key, file, png)
    if not png then return end
    if write_file(cache, outDir .. "/" .. file, png) then
      manifestTextures[key] = file
      written = written + 1
    end
  end

  emit("cursor", "cursor.png",
    (StorageChromeExtract.bakeSheet(sheet.handCursor, sheetLen.handCursor, pal.misc2, 4)))
  emit("cursor_shadow", "cursor_shadow.png",
    (StorageChromeExtract.bakeSheet(sheet.handCursorShadow, sheetLen.handCursorShadow, pal.misc2, 2)))
  emit("arrow", "box_scroll_arrow.png",
    (StorageChromeExtract.bakeSheet(sheet.boxScrollArrow, sheetLen.boxScrollArrow, pal.misc2, 1)))
  emit("waveform", "waveform.png",
    (StorageChromeExtract.bakeSheet(sheet.waveform, sheetLen.waveform, pal.misc2, 2)))
  emit("scrolling_bg", "scrolling_bg.png",
    (StorageChromeExtract.bakeSheet(sheet.scrollingBg, sheetLen.scrollingBg, pal.scrollingBg, 4)))
  emit("menu", "menu.png",
    (StorageChromeExtract.bakeSheet(sheet.menu, sheetLen.menu, pal.interface, 16)))
  emit("menu_pal0", "menu_pal0.png",
    (StorageChromeExtract.bakeSheet(sheet.menu, sheetLen.menu, pal.menu, 16)))

  -- src/pokemon_storage_system_tasks.c:2126
  local menuTiles = sheet.menu
  local bgPals = { pal.interface, pal.partyMenu, pal.interfaceNoMon, pal.scrollingBg }
  local bgBase = Versions.STORAGE_BG1_BASE_TILE or 0x100
  local function bakeBg1(spec, entries)
    return (StorageChromeExtract.bakeTilemap(entries or read_tilemap(rom, spec),
      spec.w, spec.h, menuTiles, bgPals, 0, bgBase))
  end
  if mapOff.menu then
    emit("frame", "interface_frame.png", bakeBg1(mapOff.menu))
  end
  if mapOff.partyMenu then
    local s = mapOff.partyMenu
    local drawer = read_tilemap(rom, s)
    if drawer then
      -- Party tab button is the bottom 2 rows (rows 20..21, 12x2 tiles) of party_menu
      local buttonPartyEntries = {}
      for r = 0, 1 do
        for c = 0, 11 do
          buttonPartyEntries[r * 12 + c + 1] = drawer[(20 + r) * 12 + c + 1] or 0
        end
      end
      emit("button_party", "button_party.png",
        StorageChromeExtract.bakeTilemap(buttonPartyEntries, 12, 2, menuTiles, bgPals, 0, bgBase))

      emit("party_drawer_bg", "party_drawer_bg.png", bakeBg1(s, drawer))
      local filled = mapOff.partySlotFilled and read_tilemap(rom, mapOff.partySlotFilled)
      if filled then
        emit("party_drawer_full", "party_drawer_full.png", bakeBg1(s, fill_party_slots(drawer, filled)))
      end
    end
  end
  if mapOff.closeBoxButton then
    local closeEntries = read_tilemap(rom, mapOff.closeBoxButton)
    if closeEntries then
      -- Normal CLOSE BOX button is the top 2 rows (9x2 tiles)
      local normalClose = {}
      for i = 1, 18 do normalClose[i] = closeEntries[i] or 0 end
      emit("button_close", "button_close.png",
        StorageChromeExtract.bakeTilemap(normalClose, 9, 2, menuTiles, bgPals, 0, bgBase))
    end
  end
  if mapOff.partySlotFilled then
    emit("party_slot_filled", "party_slot_filled.png", bakeBg1(mapOff.partySlotFilled))
  end
  if mapOff.partySlotEmpty then
    emit("party_slot_empty", "party_slot_empty.png", bakeBg1(mapOff.partySlotEmpty))
  end

  local manifestWallpapers = {}
  local wpBase = Versions.STORAGE_WALLPAPERS
  local wpW = Versions.STORAGE_WALLPAPER_W or 20
  local wpH = Versions.STORAGE_WALLPAPER_H or 18
  if wpBase then
    for i, name in ipairs(StorageChromeExtract.WALLPAPER_NAMES) do
      local entry = wpBase + (i - 1) * 12
      local tilesOff = ptr_to_offset(get_u32(rom, entry))
      local mapPtr = ptr_to_offset(get_u32(rom, entry + 4))
      local palPtr = ptr_to_offset(get_u32(rom, entry + 8))
      if tilesOff and mapPtr and palPtr then
        local tiles = read_sheet(rom, { off = tilesOff, lz = true })
        local entries = read_tilemap(rom, { off = mapPtr, lz = true, w = wpW, h = wpH })
        local pals = { read_palette(rom, palPtr, 16), read_palette(rom, palPtr + 32, 16) }
        -- src/pokemon_storage_system_graphics.c:1226
        local png = StorageChromeExtract.bakeTilemap(entries, wpW, wpH, tiles, pals, 1)
        local rel = "wallpapers/" .. name .. ".png"
        if png and write_file(cache, outDir .. "/" .. rel, png) then
          manifestWallpapers[name] = rel
          written = written + 1
        end
      end
    end
  end

  local lines = {
    "-- Auto-generated FRLG storage chrome manifest from ROM. DO NOT EDIT DIRECTLY.",
    "return {",
    string.format("  version = %d,", StorageChromeExtract.FORMAT_VERSION),
    "  textures = {",
  }
  for _, tex in ipairs(StorageChromeExtract.TEXTURE_FILES) do
    if manifestTextures[tex.key] then
      lines[#lines + 1] = string.format("    %s = \"%s\",", tex.key, manifestTextures[tex.key])
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  wallpapers = {"
  for _, name in ipairs(StorageChromeExtract.WALLPAPER_NAMES) do
    if manifestWallpapers[name] then
      lines[#lines + 1] = string.format("    %s = \"%s\",", name, manifestWallpapers[name])
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  write_file(cache, outDir .. "/manifest.lua", table.concat(lines, "\n"))
  print("[game3/storage_chrome_extract] storage chrome ready (" .. outDir .. ", " .. written .. " assets)")
  return { ok = written > 0, root = outDir, count = written }
end

return StorageChromeExtract
