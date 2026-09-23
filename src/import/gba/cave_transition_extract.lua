-- src/fldeff_flash.c:157-162, :361-414

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local CaveTransitionExtract = {}

CaveTransitionExtract.CACHE_SUB = "cave_transition"
CaveTransitionExtract.FILES = { "screen.bin", "palettes.lua" }

local SCREEN_W, SCREEN_H = 240, 160
local MAP_W = 32

local function palette(rom, off)
  local out = {}
  for c = 0, 15 do out[c] = rom:u16(off + c * 2) end
  return out
end

function CaveTransitionExtract.run(rom, cache, opts)
  local A = Versions.CAVE_TRANSITION
  local get = function(i) return rom:get(i) end
  local tiles = assert(Lz77.decompress(get, A.tiles), "sCaveTransitionTiles did not decompress")
  local map = assert(Lz77.decompress(get, A.tilemap), "sCaveTransitionTilemap did not decompress")
  assert(#map >= MAP_W * 20 * 2, "sCaveTransitionTilemap is too short")
  local tileCount = math.floor(#tiles / 32)
  local screen = {}
  for y = 0, SCREEN_H - 1 do
    for x = 0, SCREEN_W - 1 do
      local ty, tx = math.floor(y / 8), math.floor(x / 8)
      local mi = (ty * MAP_W + tx) * 2 + 1
      local entry = map[mi] + map[mi + 1] * 256
      local tile = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local bank = math.floor(entry / 4096) % 16
      assert(tile < tileCount, "sCaveTransitionTilemap names a missing tile")
      local px, py = x % 8, y % 8
      if hflip then px = 7 - px end
      if vflip then py = 7 - py end
      local byte = tiles[tile * 32 + py * 4 + math.floor(px / 2) + 1]
      local index = (px % 2 == 0) and (byte % 16) or math.floor(byte / 16)
      screen[#screen + 1] = string.char(bank * 16 + index)
    end
  end
  local root = (opts and opts.cacheRoot or "data/generated/gba") .. "/" .. CaveTransitionExtract.CACHE_SUB
  local serialize = require("src.import.gba.extract_scripts").serialize_lua
  assert(cache:write(root .. "/screen.bin", table.concat(screen)), "could not write cave_transition/screen.bin")
  assert(cache:write(root .. "/palettes.lua", "return " .. serialize({
    width = SCREEN_W,
    height = SCREEN_H,
    white = palette(rom, A.white_pal),
    black = palette(rom, A.black_pal),
    tiles = palette(rom, A.pal),
  }) .. "\n"), "could not write cave_transition/palettes.lua")
  return { ok = true, root = root }
end

return CaveTransitionExtract
