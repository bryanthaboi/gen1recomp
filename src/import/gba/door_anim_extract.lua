local Versions = require("src.import.gba.versions")
local band, rshift = bit.band, bit.rshift

local DoorAnimExtract = {}

DoorAnimExtract.CACHE_SUB = "doors"

-- sDoorGraphics table (see versions.lua for offset documentation).
local SDOOR_GRAPHICS_OFFSET = Versions.DOOR_GRAPHICS_TABLE or 0x035B5D8
local ENTRY_COUNT           = Versions.DOOR_GRAPHICS_COUNT  or 32
local ENTRY_STRIDE          = 12  -- bytes per entry: u16 mid, u8 sound, u8 size | u32 ptr_tiles | u32 ptr_pal

-- Human-readable names in table order (matches sDoorGraphics[] from field_door.c).
local ENTRY_NAMES = {
  "General",      "SlidingSingle",    "SlidingDouble",    "Pallet",
  "OaksLab",      "Viridian",         "Pewter",           "Saffron",
  "SilphCo",      "Cerulean",         "Lavender",         "Vermilion",
  "PokemonFanClub","DeptStore",       "Fuchsia",          "SafariZone",
  "CinnabarLab",  "Sevii123",         "JoyfulGameCorner", "OneIslandPokeCenter",
  "Sevii45",      "FourIslandDayCare","RocketWarehouse",  "Sevii67",
  "DeptStoreElevator","CableClub",    "HideoutElevator",  "SSAnne",
  "SilphCoElevator","Teleporter",     "TrainerTowerLobbyElevator","TrainerTowerRoofElevator",
}

-- src/field_door.c:10
local SOUND_NAMES = { [0] = "normal", [1] = "sliding" }
-- src/field_door.c:15
local SIZE_NAMES = { [0] = "1x1", [1] = "1x2" }

DoorAnimExtract.MANIFEST_VERSION = 2

-- src/field_door.c:250
local DOOR_TILESETS = {
  [0]  = "primary",
  [1]  = "primary",
  [2]  = "primary",
  [3]  = "pallet",
  [4]  = "pallet",
  [5]  = "viridian",
  [6]  = "pewter",
  [7]  = "saffron",
  [8]  = "saffron",
  [9]  = "cerulean",
  [10] = "lavender",
  [11] = "vermilion",
  [12] = "vermilion",
  [13] = "celadon",
  [14] = "fuchsia",
  [15] = "fuchsia",
  [16] = "cinnabar",
  [17] = "sevii_123",
  [18] = "sevii_123",
  [19] = "sevii_123",
  [20] = "sevii_45",
  [21] = "sevii_45",
  [22] = "sevii_45",
  [23] = "sevii_67",
  [24] = "dept_store",
  [25] = "cable_club",
  [26] = "silph_co",
  [27] = "ss_anne",
  [28] = "silph_co",
  [29] = "sea_cottage",
  [30] = "trainer_tower",
  [31] = "trainer_tower",
}

-- Primary tileset (gTileset_General) palette offset in FireRed USA 1.0 ROM.
local PRIMARY_PALETTES_OFFSET = 0x0EA1B68

-- Secondary tileset palette offset for each door index (0..31).
local DOOR_SECONDARY_PALS = {
  [0]  = 0xEA1B68, -- General (Door)
  [1]  = 0xEA1B68, -- General (SlidingSingle)
  [2]  = 0xEA1B68, -- General (SlidingDouble)
  [3]  = 0x26D7C0, -- PalletTown (Door)
  [4]  = 0x26D7C0, -- PalletTown (OaksLabDoor)
  [5]  = 0x26DFC0, -- ViridianCity (Door)
  [6]  = 0x26EAB8, -- PewterCity (Door)
  [7]  = 0x275094, -- SaffronCity (Door)
  [8]  = 0x275094, -- SaffronCity (SilphCoDoor)
  [9]  = 0x26F4B8, -- CeruleanCity (Door)
  [10] = 0x270438, -- LavenderTown (Door)
  [11] = 0x270DA0, -- VermilionCity (Door)
  [12] = 0x270DA0, -- VermilionCity (SSAnneWarp / FanClub)
  [13] = 0x271C74, -- CeladonCity (DeptStoreDoor)
  [14] = 0x272A5C, -- FuchsiaCity (Door)
  [15] = 0x272A5C, -- FuchsiaCity (SafariZoneDoor)
  [16] = 0x273358, -- CinnabarIsland (LabDoor)
  [17] = 0x299AA4, -- SeviiIslands123 (Door)
  [18] = 0x299AA4, -- SeviiIslands123 (GameCornerDoor)
  [19] = 0x299AA4, -- SeviiIslands123 (PokeCenterDoor)
  [20] = 0x29AB04, -- SeviiIslands45 (Door)
  [21] = 0x29AB04, -- SeviiIslands45 (DayCareDoor)
  [22] = 0x29AB04, -- SeviiIslands45 (RocketWarehouseDoor)
  [23] = 0x29BD64, -- SeviiIslands67 (Door)
  [24] = 0xEA9D88, -- DepartmentStore (ElevatorDoor)
  [25] = 0x278CC4, -- PokemonCenter (CableClubDoor)
  [26] = 0x290DD0, -- SilphCo (HideoutElevatorDoor)
  [27] = 0x287B80, -- SSAnne (Door)
  [28] = 0x290DD0, -- SilphCo (ElevatorDoor)
  [29] = 0x28F9D8, -- SeaCottage (Teleporter)
  [30] = 0x29CEE4, -- TrainerTower (LobbyElevatorDoor)
  [31] = 0x29CEE4, -- TrainerTower (RoofElevatorDoor)
}

-- ─────────────────────────── 4bpp → RGBA decode ──────────────────────────────

-- Decode 16-color BGR555 palette from the appropriate tileset palette bank.
local function decode_palette(rom, pal_slot, door_idx)
  local pal_base
  if pal_slot < 7 then
    pal_base = PRIMARY_PALETTES_OFFSET + pal_slot * 32
  else
    local sec_base = DOOR_SECONDARY_PALS[door_idx] or PRIMARY_PALETTES_OFFSET
    pal_base = sec_base + pal_slot * 32
  end

  local pal = {}
  pal[0] = {0, 0, 0, 0} -- color 0 is transparent on GBA
  for c = 1, 15 do
    local lo  = rom:get(pal_base + c * 2)
    local hi  = rom:get(pal_base + c * 2 + 1)
    local bgr = lo + hi * 256
    local r = band(bgr,          0x1F) * 8
    local g = band(rshift(bgr,  5), 0x1F) * 8
    local b = band(rshift(bgr, 10), 0x1F) * 8
    pal[c] = {r, g, b, 255}
  end
  return pal
end

-- Decode door tiles into an RGBA byte string.
-- GBA doors have 3 animation frames (half-open 1, half-open 2, fully-open).
-- 1x1 doors: 4 tiles per frame (TL, TR, BL, BR) -> 16x16 px per frame, total 16x48 px.
-- 1x2 doors: 8 tiles per frame (4 top metatile, 4 bottom metatile) -> 16x32 px per frame, total 16x96 px.
local function decode_door_sheet_rgba(rom, tiles_off, pal_nums, is_large, door_idx)
  local W = 16
  local frame_h = is_large and 32 or 16
  local H = frame_h * 3
  local tiles_per_frame = is_large and 8 or 4

  -- Pre-decode palettes for each subtile slot
  local tile_pals = {}
  for t = 0, tiles_per_frame - 1 do
    local pal_slot = pal_nums[t + 1] or 0
    tile_pals[t] = decode_palette(rom, pal_slot, door_idx)
  end

  local pixels = {}
  for i = 1, W * H * 4 do pixels[i] = 0 end

  for f = 0, 2 do
    for t_idx = 0, tiles_per_frame - 1 do
      local tx, ty
      if is_large then
        local meta_row = math.floor(t_idx / 4) -- 0: top metatile, 1: bottom metatile
        local sub_t = t_idx % 4
        tx = (sub_t % 2) * 8
        ty = f * 32 + meta_row * 16 + math.floor(sub_t / 2) * 8
      else
        tx = (t_idx % 2) * 8
        ty = f * 16 + math.floor(t_idx / 2) * 8
      end

      local pal = tile_pals[t_idx]
      local global_t = f * tiles_per_frame + t_idx
      local t_base = tiles_off + global_t * 32

      for row = 0, 7 do
        for col = 0, 3 do
          local b  = rom:get(t_base + row * 4 + col)
          local lo = band(b, 0xF)
          local hi = band(rshift(b, 4), 0xF)

          local c_lo = pal[lo] or {0, 0, 0, 0}
          local base_lo = ((ty + row) * W + (tx + col * 2)) * 4 + 1
          pixels[base_lo    ] = c_lo[1]
          pixels[base_lo + 1] = c_lo[2]
          pixels[base_lo + 2] = c_lo[3]
          pixels[base_lo + 3] = c_lo[4]

          local c_hi = pal[hi] or {0, 0, 0, 0}
          local base_hi = ((ty + row) * W + (tx + col * 2 + 1)) * 4 + 1
          pixels[base_hi    ] = c_hi[1]
          pixels[base_hi + 1] = c_hi[2]
          pixels[base_hi + 2] = c_hi[3]
          pixels[base_hi + 3] = c_hi[4]
        end
      end
    end
  end

  return string.char(unpack(pixels)), W, H, frame_h
end

-- ────────────────────────────── Main extract ─────────────────────────────────

function DoorAnimExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or "data/generated/gba"
  local root = cacheRoot .. "/" .. DoorAnimExtract.CACHE_SUB

  if not rom then
    print("[door_extract] no ROM handle; writing stub manifest")
    return DoorAnimExtract._writeStub(cache, root)
  end

  local manifest_doors   = {}
  local manifest_by_mid  = {}
  local manifest_entries = {}

  -- src/field_door.c:396
  local limit = math.max(ENTRY_COUNT, 0)
  for i = 0, limit - 1 do
    local base      = SDOOR_GRAPHICS_OFFSET + i * ENTRY_STRIDE
    local mid_flags = rom:u32(base)
    local ptr_tiles = rom:u32(base + 4)
    local ptr_pal   = rom:u32(base + 8)
    if ptr_tiles == 0 then break end

    local mid       = band(mid_flags, 0xFFFF)
    local sound_id  = band(rshift(mid_flags, 16), 0xFF)
    local size_id   = band(rshift(mid_flags, 24), 0xFF)
    local is_large  = (size_id == 1)
    local name      = ENTRY_NAMES[i + 1] or ("door_" .. i)

    local tiles_off = rom:ptrOffset(ptr_tiles)
    local pal_off   = rom:ptrOffset(ptr_pal)
    if not (tiles_off and pal_off) then
      print(string.format("[door_extract] bad ptr for entry %d (%s); skipping", i, name))
      goto continue
    end

    local pal_nums = {}
    for p = 0, 7 do
      pal_nums[p + 1] = rom:get(pal_off + p)
    end

    local rgba_str, W, H, frame_h = decode_door_sheet_rgba(rom, tiles_off, pal_nums, is_large, i)

    local fname = name:lower() .. ".rgba"
    cache:write(root .. "/" .. fname, rgba_str)

    manifest_doors[name] = {
      file        = fname,
      width       = W,
      height      = H,
      frame_width = W,
      frame_height= frame_h,
      frames      = 3,
    }

    local entry = {
      index      = i,
      mid        = mid,
      tile       = name,
      sound      = SOUND_NAMES[sound_id] or "normal",
      sound_type = sound_id,
      size       = SIZE_NAMES[size_id] or "1x1",
      size_type  = size_id,
      tileset    = DOOR_TILESETS[i] or "primary",
    }
    manifest_by_mid[mid] = entry
    manifest_entries[#manifest_entries + 1] = entry

    ::continue::
  end

  rom:clearCache()

  local names = {}
  for k in pairs(manifest_doors) do names[#names + 1] = k end
  table.sort(names)

  -- Build and write manifest.lua through the cache.
  local mlines = {
    "return {",
    string.format("  version = %d,", DoorAnimExtract.MANIFEST_VERSION),
    string.format("  count = %d,", #manifest_entries),
    "  doors = {",
  }
  for _, k in ipairs(names) do
    local v = manifest_doors[k]
    mlines[#mlines + 1] = string.format(
      "    [%q] = { file = %q, width = %d, height = %d, frame_width = %d, frame_height = %d, frames = %d },",
      k, v.file, v.width, v.height, v.frame_width, v.frame_height, v.frames)
  end
  mlines[#mlines + 1] = "  },"
  mlines[#mlines + 1] = "  entries = {"
  for _, v in ipairs(manifest_entries) do
    mlines[#mlines + 1] = string.format(
      "    { index = %d, mid = %d, tile = %q, sound = %q, sound_type = %d, size = %q, size_type = %d, tileset = %q },",
      v.index, v.mid, v.tile, v.sound, v.sound_type, v.size, v.size_type, v.tileset)
  end
  mlines[#mlines + 1] = "  },"
  mlines[#mlines + 1] = "  by_mid = {"
  for _, v in ipairs(manifest_entries) do
    mlines[#mlines + 1] = string.format(
      "    [%d] = { index = %d, mid = %d, tile = %q, sound = %q, sound_type = %d, size = %q, size_type = %d, tileset = %q },",
      v.mid, v.index, v.mid, v.tile, v.sound, v.sound_type, v.size, v.size_type, v.tileset)
  end
  mlines[#mlines + 1] = "  },"
  mlines[#mlines + 1] = "}"
  mlines[#mlines + 1] = ""
  cache:write(root .. "/manifest.lua", table.concat(mlines, "\n"))

  print(string.format("[door_extract] wrote %d door sheets, %d metatile entries",
    #names, #manifest_entries))
  return true
end

-- src/field_door.c:250
function DoorAnimExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or "data/generated/gba") .. "/" .. DoorAnimExtract.CACHE_SUB
  local body = cache and cache.read and cache:read(root .. "/manifest.lua")
  if type(body) ~= "string" or #body == 0 then return false end
  local chunk = load(body, "@" .. root .. "/manifest.lua", "t", {})
  if not chunk then return false end
  local ok, manifest = pcall(chunk)
  if not ok or type(manifest) ~= "table" then return false end
  if manifest.version ~= DoorAnimExtract.MANIFEST_VERSION then return false end
  if type(manifest.by_mid) ~= "table" then return false end
  local n = 0
  for _, entry in pairs(manifest.by_mid) do
    if type(entry) ~= "table" or type(entry.sound_type) ~= "number" then return false end
    n = n + 1
  end
  return n >= ENTRY_COUNT
end

-- Write a stub manifest + pallet.rgba so CacheContract is satisfied even when
-- no ROM handle is available.
function DoorAnimExtract._writeStub(cache, root)
  local lines = {
    "return {",
    string.format("  version = %d,", DoorAnimExtract.MANIFEST_VERSION),
    "  count = 0,",
    "  doors = {},",
    "  entries = {},",
    "  by_mid = {},",
    "}",
    "",
  }
  cache:write(root .. "/manifest.lua", table.concat(lines, "\n"))
  cache:write(root .. "/pallet.rgba", string.rep("\0", 16 * 16 * 4))
  return false
end

return DoorAnimExtract
