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

-- Sound IDs from se_ids.lua constants (used in manifest for game code).
local SOUND_FOR_MID = {
  [0x062] = "sliding", [0x15B] = "sliding", [0x2BC] = "sliding", [0x294] = "sliding",
  [0x2D2] = "sliding", [0x29B] = "sliding", [0x28D] = "sliding", [0x2DE] = "sliding",
  [0x2AB] = "sliding", [0x2E2] = "sliding", [0x296] = "sliding", [0x2C3] = "sliding",
  [0x356] = "sliding",
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

  local manifest_doors  = {}
  local manifest_by_mid = {}

  for i = 0, ENTRY_COUNT - 1 do
    local base      = SDOOR_GRAPHICS_OFFSET + i * ENTRY_STRIDE
    local mid_flags = rom:u32(base)
    local ptr_tiles = rom:u32(base + 4)
    local ptr_pal   = rom:u32(base + 8)

    local mid       = band(mid_flags, 0xFFFF)
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

local DOOR_TILESETS = {
  [0]  = "primary",           -- General
  [1]  = "primary",           -- SlidingSingle
  [2]  = "primary",           -- SlidingDouble
  [3]  = "pallet",            -- Pallet
  [4]  = "pallet",            -- OaksLab
  [5]  = "viridian",          -- Viridian
  [6]  = "pewter",            -- Pewter
  [7]  = "saffron",           -- Saffron
  [8]  = "saffron",           -- SilphCo
  [9]  = "cerulean",          -- Cerulean
  [10] = "lavender",          -- Lavender
  [11] = "vermilion",         -- Vermilion
  [12] = "vermilion",         -- PokemonFanClub
  [13] = "celadon",           -- DeptStore
  [14] = "fuchsia",           -- Fuchsia
  [15] = "fuchsia",           -- SafariZone
  [16] = "cinnabar",          -- CinnabarLab
  [17] = "sevii_123",         -- Sevii123
  [18] = "sevii_123",         -- JoyfulGameCorner
  [19] = "sevii_123",         -- OneIslandPokeCenter
  [20] = "sevii_45",          -- Sevii45
  [21] = "sevii_45",          -- FourIslandDayCare
  [22] = "sevii_45",          -- RocketWarehouse
  [23] = "sevii_67",          -- Sevii67
  [24] = "dept_store",        -- DeptStoreElevator
  [25] = "cable_club",        -- CableClub
  [26] = "silph_co",          -- HideoutElevator
  [27] = "ss_anne",           -- SSAnne
  [28] = "silph_co",          -- SilphCoElevator
  [29] = "sea_cottage",       -- Teleporter
  [30] = "trainer_tower",     -- TrainerTowerLobbyElevator
  [31] = "trainer_tower",     -- TrainerTowerRoofElevator
}

    local sound = SOUND_FOR_MID[mid] or "normal"
    local size  = is_large and "1x2" or "1x1"
    local tset  = DOOR_TILESETS[i] or "primary"
    manifest_by_mid[mid] = {
      mid     = mid,
      tile    = name,
      sound   = sound,
      size    = size,
      tileset = tset,
    }

    ::continue::
  end

  rom:clearCache()

  -- Build and write manifest.lua through the cache.
  local mlines = { "return {", "  doors = {" }
  for k, v in pairs(manifest_doors) do
    mlines[#mlines + 1] = string.format(
      "    [%q] = { file = %q, width = %d, height = %d, frame_width = %d, frame_height = %d, frames = %d },",
      k, v.file, v.width, v.height, v.frame_width, v.frame_height, v.frames)
  end
  mlines[#mlines + 1] = "  },"
  mlines[#mlines + 1] = "  by_mid = {"
  for mid, v in pairs(manifest_by_mid) do
    mlines[#mlines + 1] = string.format(
      "    [%d] = { mid = %d, tile = %q, sound = %q, size = %q, tileset = %q },",
      mid, mid, v.tile, v.sound, v.size, v.tileset or "primary")
  end
  mlines[#mlines + 1] = "  }"
  mlines[#mlines + 1] = "}"
  mlines[#mlines + 1] = ""
  cache:write(root .. "/manifest.lua", table.concat(mlines, "\n"))

  local n_doors = 0
  for _ in pairs(manifest_doors) do n_doors = n_doors + 1 end
  print(string.format("[door_extract] wrote %d door sheets, %d metatile entries",
    n_doors, ENTRY_COUNT))
  return true
end

-- Write a stub manifest + pallet.rgba so CacheContract is satisfied even when
-- no ROM handle is available.
function DoorAnimExtract._writeStub(cache, root)
  local STUB_ENTRIES = {
    {0x03D,"General","normal","1x1","primary"},{0x062,"SlidingSingle","sliding","1x1","primary"},
    {0x15B,"SlidingDouble","sliding","1x1","primary"},{0x2A3,"Pallet","normal","1x1","pallet"},
    {0x2AC,"OaksLab","normal","1x1","pallet"},{0x299,"Viridian","normal","1x1","viridian"},
    {0x2CE,"Pewter","normal","1x1","pewter"},{0x284,"Saffron","normal","1x1","saffron"},
    {0x2BC,"SilphCo","sliding","1x1","saffron"},{0x298,"Cerulean","normal","1x1","cerulean"},
    {0x2A2,"Lavender","normal","1x1","lavender"},{0x29E,"Vermilion","normal","1x1","vermilion"},
    {0x2E1,"PokemonFanClub","normal","1x1","vermilion"},{0x294,"DeptStore","sliding","1x1","celadon"},
    {0x2BF,"Fuchsia","normal","1x1","fuchsia"},{0x2D2,"SafariZone","sliding","1x1","fuchsia"},
    {0x2AD,"CinnabarLab","normal","1x1","cinnabar"},{0x297,"Sevii123","normal","1x1","sevii_123"},
    {0x29B,"JoyfulGameCorner","sliding","1x1","sevii_123"},{0x2EB,"OneIslandPokeCenter","normal","1x1","sevii_123"},
    {0x29A,"Sevii45","normal","1x1","sevii_45"},{0x2B9,"FourIslandDayCare","normal","1x1","sevii_45"},
    {0x2AF,"RocketWarehouse","normal","1x1","sevii_45"},{0x30C,"Sevii67","normal","1x1","sevii_67"},
    {0x28D,"DeptStoreElevator","sliding","1x2","dept_store"},{0x2DE,"CableClub","sliding","1x2","cable_club"},
    {0x2AB,"HideoutElevator","sliding","1x2","silph_co"},{0x281,"SSAnne","normal","1x2","ss_anne"},
    {0x2E2,"SilphCoElevator","sliding","1x2","silph_co"},{0x296,"Teleporter","sliding","1x2","sea_cottage"},
    {0x2C3,"TrainerTowerLobbyElevator","sliding","1x2","trainer_tower"},
    {0x356,"TrainerTowerRoofElevator","sliding","1x2","trainer_tower"},
  }
  local lines = {"return {", "  doors = {},", "  by_mid = {"}
  for _, e in ipairs(STUB_ENTRIES) do
    lines[#lines + 1] = string.format(
      "    [%d] = { mid = %d, tile = %q, sound = %q, size = %q, tileset = %q },",
      e[1], e[1], e[2], e[3], e[4], e[5])
  end
  lines[#lines + 1] = "  }"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  cache:write(root .. "/manifest.lua", table.concat(lines, "\n"))
  cache:write(root .. "/pallet.rgba", string.rep("\0", 16 * 16 * 4))
  return false
end

return DoorAnimExtract
