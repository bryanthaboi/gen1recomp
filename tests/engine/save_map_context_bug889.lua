-- #889: a .sav exported from a save that never came from a ROM import used to
-- carry no current-map state at all.  A Continue restores that window from the
-- save and never rebuilds it (LoadMainData sets BIT_NO_PREVIOUS_MAP and
-- LoadMapHeader returns early on it), so the game continued into tileset 0,
-- a $0000 map-data pointer and sound id 0 -- a garbled map and a silent hang
-- on real hardware.
--
-- src/save_convert/MapContext.lua replays LoadMapHeader's WRAM writes from the
-- extracted ROM bytes instead.  This suite pins the layout it writes, on a
-- synthetic map whose header/object bytes are chosen so every field is
-- distinguishable, and then checks the encoder's three cases: no template
-- (rebuild), a template saved on the same map (leave the game's own bytes
-- alone, which is what keeps import -> export byte-identical), and a template
-- saved on a different map (rebuild, or the export carries the wrong map's
-- header).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local MapContext = require("src.save_convert.MapContext")
local GenSave = require("src.save_convert.GenSave")

local O = MapContext.OFFSETS
local SAVE = GenSave.OFFSETS

-- ---------------------------------------------------------------- fixtures

-- tileset 0, 4 blocks tall, 5 wide, data/text/script pointers, north|west
local HEADER = { 0x00, 0x04, 0x05, 0x21, 0x43, 0x78, 0x56, 0x89, 0x67, 0x0A }
-- two 11-byte map_connection_structs, north first then west (the order
-- LoadMapHeader copies them in), each tagged with its own filler
local CONNECTIONS = {
  0x11, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA,
  0x22, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA,
}
local OBJECTS = {
  0x0E,                                  -- wMapBackgroundTile
  2,                                     -- warps
  0x04, 0x05, 0x00, 0x26,
  0x06, 0x07, 0x01, 0x27,
  2,                                     -- signs
  0x08, 0x09, 0x03,                      -- Y, X, text id
  0x0A, 0x0B, 0x04,
  3,                                     -- sprites
  0x01, 0x14, 0x15, 0xFF, 0xD0, 0x05,    -- plain NPC
  0x02, 0x16, 0x17, 0xFE, 0x01, 0x47,    -- trainer ($40): class, party
  0x33, 0x44,
  0x03, 0x18, 0x19, 0xFF, 0xD3, 0x85,    -- item ball ($80): item id
  0x14,
}
local TILESET_HEADER = { 0x0C, 0x11, 0x40, 0x22, 0x40, 0x33, 0x40,
                         0x44, 0x55, 0x66, 0x77, 0x02 }

local function fixtureData()
  local maps = {}
  for id, map in pairs(dofile("tests/fixture_data/maps.lua")) do
    local copy = {}
    for k, v in pairs(map) do copy[k] = v end
    maps[id] = copy
  end
  maps.FIX_TOWN.sram = {
    header = HEADER, connections = CONNECTIONS, objects = OBJECTS,
  }
  return {
    maps = maps,
    pokemon = dofile("tests/fixture_data/pokemon.lua"),
    moves = dofile("tests/fixture_data/moves.lua"),
    items = dofile("tests/fixture_data/items.lua"),
    tilesets = { [maps.FIX_TOWN.tileset] = { header = TILESET_HEADER } },
    encounters = {},
    audio = {
      -- Song ids are computed from the header address
      -- (constants/music_constants.asm): (address - $4000) / 3.
      mapSongs = { FIX_TOWN = "Music_Fixture" },
      songs = { Music_Fixture = { address = 0x4000 + 3 * 0xBD, bank = 2 } },
    },
  }
end

local data = fixtureData()

-- ------------------------------------------------------------ the window

local ctx = assert(MapContext.build(data, "FIX_TOWN", 7, 4))
local w = ctx.writes

local function eqBytes(got, want, msg)
  got = got or {}
  T.eq(#got, #want, msg .. " (length)")
  for i = 1, #want do
    T.eq(got[i], want[i], ("%s (byte %d)"):format(msg, i))
  end
end

eqBytes(w[O.curMapHeader], HEADER, "wCurMapHeader is the ROM header verbatim")

-- north and west are present; south and east must read $FF, or LoadTileBlockMap
-- walks a connection that is not there
local conn = w[O.connectionHeaders]
T.eq(#conn, 44, "all four connection structs are written")
T.eq(conn[1], 0x11, "north takes the first connection struct")
T.eq(conn[11], 0xAA, "north keeps all 11 of its bytes")
T.eq(conn[12], 0xFF, "south is disabled with $FF")
T.eq(conn[23], 0x22, "west takes the second connection struct")
T.eq(conn[34], 0xFF, "east is disabled with $FF")

eqBytes(w[O.mapBackgroundTile], { 0x0E }, "wMapBackgroundTile")
eqBytes(w[O.numberOfWarps], { 2 }, "wNumberOfWarps")
eqBytes(w[O.warpEntries], { 0x04, 0x05, 0x00, 0x26, 0x06, 0x07, 0x01, 0x27 },
        "wWarpEntries are the raw 4-byte rows")
eqBytes(w[O.numSigns], { 2 }, "wNumSigns")
eqBytes(w[O.signCoords], { 0x08, 0x09, 0x0A, 0x0B },
        "wSignCoords are split out of the 3-byte sign rows")
eqBytes(w[O.signTextIDs], { 0x03, 0x04 }, "wSignTextIDs")
eqBytes(w[O.numSprites], { 3 }, "wNumSprites")
-- movement byte 2 and the text id with its flag bits masked ("and $3f")
eqBytes(w[O.mapSpriteData], { 0xD0, 0x05, 0x01, 0x07, 0xD3, 0x05 },
        "wMapSpriteData is (movement byte 2, text id & $3f) per sprite")
eqBytes(w[O.mapSpriteExtra], { 0, 0, 0x33, 0x44, 0x14, 0 },
        "wMapSpriteExtraData holds trainer class/party and item id")
eqBytes(w[O.currentMapHeight2], { 8 }, "map height doubled into 2x2 blocks")
eqBytes(w[O.currentMapWidth2], { 10 }, "map width doubled into 2x2 blocks")

local tilesetRow = {}
for i = 1, 11 do tilesetRow[i] = TILESET_HEADER[i] end
eqBytes(w[O.tilesetHeader], tilesetRow,
        "wTilesetBank..wGrassTile is the Tilesets row (11 bytes)")
T.eq(ctx.tileAnimations, 0x02, "the 12th tileset byte rides in sTileAnimations")

eqBytes(w[O.mapMusicSoundID], { 0xBD }, "the song id is derived from its header address")
eqBytes(w[O.mapMusicROMBank], { 2 }, "the song's audio bank comes with it")

-- x=7,y=4: block coords are the odd/even halves, and the view pointer is
-- macros/coords.asm event_displacement over the map width.
eqBytes(w[O.yBlockCoord], { 0 }, "wYBlockCoord is y & 1")
eqBytes(w[O.xBlockCoord], { 1 }, "wXBlockCoord is x & 1")
local view = 0xC6E8 + 7 + 5 + (5 + 6) * 2 + 3
eqBytes(w[O.viewPointer], { view % 256, math.floor(view / 256) },
        "wCurrentTileBlockMapViewPointer")

-- sSpriteData: picture ids in structs 1..3 of page 1, positions in page 2,
-- and every non-player struct's image index disabled at $ff
T.eq(#ctx.spriteData, 512, "sSpriteData is the full 512-byte window")
T.eq(ctx.spriteData[16 + 1], 0x01, "sprite 1 picture id")
T.eq(ctx.spriteData[16 + 3], 0xFF, "sprite 1 image index starts disabled")
T.eq(ctx.spriteData[256 + 16 + 5], 0x14, "sprite 1 map Y")
T.eq(ctx.spriteData[256 + 16 + 6], 0x15, "sprite 1 map X")
T.eq(ctx.spriteData[256 + 16 + 7], 0xFF, "sprite 1 movement byte 1")
T.eq(ctx.spriteData[3 * 16 + 1], 0x03, "sprite 3 picture id")
T.eq(ctx.spriteData[1], 0, "the player's struct is left to ResetPlayerSpriteData")

-- a map the cache has no bytes for degrades instead of raising
T.eq(MapContext.build(data, "FIX_ROUTE", 0, 0), nil,
     "a map with no extracted bytes returns nil, not an error")

-- ------------------------------------------------------- through the codec

GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())

local save = {
  player = { name = "RED", rival = "BLUE", map = "FIX_TOWN", x = 7, y = 4 },
  money = 3000, inventory = {}, pokedex = { seen = {}, owned = {} },
  flags = {}, party = {}, boxes = {},
}

local function byteAt(bytes, mainOffset)
  return bytes:byte(SAVE.mainData + mainOffset + 1)
end

local fresh = GenSave.encode(save, data, nil)
T.eq(byteAt(fresh, O.curMapHeader + 1), 0x04,
     "a templateless export carries the map header")
T.eq(byteAt(fresh, O.tilesetHeader), 0x0C,
     "a templateless export carries the tileset header")
T.eq(byteAt(fresh, O.mapMusicSoundID), 0xBD,
     "a templateless export carries the map's music, not sound id 0")
T.eq(fresh:byte(SAVE.checksumEnd - 1 + 1), 0x02,
     "sTileAnimations is written before the checksum covers it")
T.eq(GenSave.mainChecksumValid(fresh), true,
     "the rebuilt window is inside a valid main-data checksum")

-- a template still on its own map keeps the game's own bytes: those include
-- live NPC positions, and preserving them is the round-trip invariant
local template = {}
for i = 1, #fresh do template[i] = fresh:sub(i, i) end
template[SAVE.mainData + O.curMapHeader + 1] = string.char(0x99)
template[SAVE.spriteData + 17] = string.char(0x77)
local sameMap = GenSave.encode(save, data, table.concat(template))
T.eq(byteAt(sameMap, O.curMapHeader), 0x99,
     "a template saved on this map keeps its map header untouched")
T.eq(sameMap:byte(SAVE.spriteData + 17), 0x77,
     "a template saved on this map keeps its live sprite data")

-- a template saved somewhere else is stale: it holds the OTHER map's header,
-- which is exactly as unbootable as an empty one
template[SAVE.mainData + SAVE.curMap - SAVE.mainData + 1] = nil
local other = {}
for i = 1, #fresh do other[i] = fresh:sub(i, i) end
other[SAVE.curMap + 1] = string.char(0xFE) -- some map this save is not on
other[SAVE.mainData + O.curMapHeader + 1] = string.char(0x99)
local moved = GenSave.encode(save, data, table.concat(other))
T.eq(byteAt(moved, O.curMapHeader), HEADER[1],
     "a template saved on another map is rebuilt for the map the save is on")
