-- MapContext -- the current map's engine state, as a vanilla Gen1 save has to
-- carry it (#889).
--
-- Continuing a real save never re-loads the map header.  LoadMainData
-- (engine/menus/save.asm) copies sMainData back into WRAM and then sets
-- BIT_NO_PREVIOUS_MAP in wCurMapTileset; LoadMapHeader (home/overworld.asm)
-- clears that bit and RETURNS IMMEDIATELY when it was set, so every byte it
-- would otherwise have written -- the map header, connections, warps, signs,
-- sprites, the tileset header, the map's music -- comes straight out of the
-- save file.  A cartridge save always has them because the game saved them.
--
-- An export from this port did not: GenSave models the player's progress, not
-- the engine scratch around it, and left that whole window zero-filled unless
-- it had an imported SRAM image to copy from.  The game then continued into
-- tileset 0 with a $0000 map-data pointer and sound id 0, which is the
-- garbled overworld / silent hang users reported after exporting a save that
-- began as a New Game in the port.
--
-- This module rebuilds the window from the extracted ROM data, replaying the
-- same writes LoadMapHeader makes, so a port-origin save boots on hardware.
-- The offsets are all relative to wMainDataStart (= sMainData in a .sav) and
-- were summed from ram/wram.asm, then checked byte-for-byte against a real
-- cartridge save: rebuilding its current map reproduces the bytes it already
-- held, everywhere except the stale tails of disabled connection slots (which
-- the engine never reads once the connected-map byte is $FF).
--
-- Pure Lua, no love.*: shared by the runtime exporter, the CLI and the tests.

local MapContext = {}

-- wMainDataStart-relative offsets.  Anchors: wCurMap is +103 (the offset
-- GenSave already decodes the player's map from), and the run from there is
-- wCurMap, wCurrentTileBlockMapViewPointer(2), wYCoord, wXCoord, wYBlockCoord,
-- wXBlockCoord, wLastMap, wUnusedLastMapWidth, wCurMapHeader -- so the header
-- lands at +112, and every later label follows from the declaration sizes in
-- ram/wram.asm (MAX_WARP_EVENTS 32, MAX_BG_EVENTS 16, MAX_OBJECT_EVENTS 16,
-- SPRITE_SET_LENGTH 11).
local O = {
  mapMusicSoundID   = 100,   -- wMapMusicSoundID
  mapMusicROMBank   = 101,   -- wMapMusicROMBank
  viewPointer       = 104,   -- wCurrentTileBlockMapViewPointer (2)
  yCoord            = 106,
  xCoord            = 107,
  yBlockCoord       = 108,
  xBlockCoord       = 109,
  curMapHeader      = 112,   -- wCurMapHeader (10)
  connectionHeaders = 122,   -- wNorth/South/West/EastConnectionHeader (4 x 11)
  mapBackgroundTile = 182,
  numberOfWarps     = 183,
  warpEntries       = 184,   -- MAX_WARP_EVENTS x 4
  numSigns          = 441,
  signCoords        = 442,   -- MAX_BG_EVENTS x 2
  signTextIDs       = 474,   -- MAX_BG_EVENTS
  numSprites        = 490,
  mapSpriteData     = 493,   -- MAX_OBJECT_EVENTS x 2
  mapSpriteExtra    = 525,   -- MAX_OBJECT_EVENTS x 2
  currentMapHeight2 = 557,
  currentMapWidth2  = 558,
  tilesetHeader     = 564,   -- wTilesetBank .. wGrassTile (11)
  grassRate         = 1424,  -- ram/wram.asm:2408 wGrassRate
  grassMons         = 1425,
  waterRate         = 1453,
  waterMons         = 1454,
}
MapContext.OFFSETS = O

local MAX_WARP_EVENTS = 32
local MAX_BG_EVENTS = 16
local MAX_OBJECT_EVENTS = 16
local CONNECTION_STRUCT = 11   -- map_connection_struct (macros/ram.asm)
local SPRITE_STRUCT = 16       -- one wSpriteStateData1/2 entry
local NUM_SPRITE_STRUCTS = 16
local NUM_WILDMONS = 10

-- wOverworldMap, the tile-block map the view pointer indexes.  Recovered from
-- the event_displacement formula below applied to a real save's coordinates,
-- and it is the same $C6E8 every Gen1 reference quotes.
local OVERWORLD_MAP = 0xC6E8

-- Audio header tables start at $4000 in each of the three audio banks, and
-- constants/music_constants.asm derives every song id arithmetically from
-- that base ("Song ids are calculated by address", music_const:
-- (Music_X - SFX_Headers_1) / 3).  So the extracted header address IS the id,
-- and no separate MapSongBanks extraction is needed.
local SFX_HEADERS_BASE = 0x4000

local function soundId(address)
  if type(address) ~= "number" then return nil end
  local delta = address - SFX_HEADERS_BASE
  if delta < 0 or delta % 3 ~= 0 then return nil end
  local id = delta / 3
  if id > 0xFF then return nil end
  return id
end

-- LoadMapHeader parses the map's object data (data/maps/objects/*.asm) into
-- five separate WRAM arrays.  Walk it exactly as the engine does; `bytes` is
-- the 1-based array of raw object-data bytes the extractor captured.
local function parseObjects(bytes)
  local pos = 1
  local function take()
    local b = bytes[pos]
    pos = pos + 1
    return b
  end
  local out = { warps = {}, signCoords = {}, signTexts = {},
                spriteData = {}, spriteExtra = {}, sprites = {} }

  out.backgroundTile = take()

  local warpCount = take()
  if warpCount == nil then return nil end
  out.warpCount = warpCount
  for _ = 1, math.min(warpCount, MAX_WARP_EVENTS) * 4 do
    out.warps[#out.warps + 1] = take()
  end

  local signCount = take()
  if signCount == nil then return nil end
  out.signCount = signCount
  for _ = 1, math.min(signCount, MAX_BG_EVENTS) do
    out.signCoords[#out.signCoords + 1] = take()  -- Y
    out.signCoords[#out.signCoords + 1] = take()  -- X
    out.signTexts[#out.signTexts + 1] = take()
  end

  local spriteCount = take()
  if spriteCount == nil then return nil end
  out.spriteCount = spriteCount
  for _ = 1, math.min(spriteCount, MAX_OBJECT_EVENTS) do
    local picture, mapY, mapX = take(), take(), take()
    local movement1, movement2, textId = take(), take(), take()
    if textId == nil then return nil end
    out.sprites[#out.sprites + 1] = {
      picture = picture, mapY = mapY, mapX = mapX, movement1 = movement1,
    }
    -- wMapSpriteData: movement byte 2, then the text id with its trainer/item
    -- flag bits masked off (LoadMapHeader's `and $3f`).
    out.spriteData[#out.spriteData + 1] = movement2
    out.spriteData[#out.spriteData + 1] = textId % 0x40
    -- BIT_TRAINER ($40) is tested before BIT_ITEM ($80), as LoadMapHeader does
    if textId % 0x80 >= 0x40 then   -- trainer: class, then party id
      out.spriteExtra[#out.spriteExtra + 1] = take()
      out.spriteExtra[#out.spriteExtra + 1] = take()
    elseif textId >= 0x80 then      -- item ball: item id, second byte unused
      out.spriteExtra[#out.spriteExtra + 1] = take()
      out.spriteExtra[#out.spriteExtra + 1] = 0
    else
      out.spriteExtra[#out.spriteExtra + 1] = 0
      out.spriteExtra[#out.spriteExtra + 1] = 0
    end
  end
  return out
end

-- build(data, mapId, x, y) -> ctx, err
--
-- ctx.writes      [wMainDataStart-relative offset] = array of bytes
-- ctx.spriteData  512 bytes for sSpriteData (wSpriteStateData1 then 2)
-- ctx.tileAnimations  the byte sTileAnimations holds
--
-- Returns nil plus a reason when the data set predates the extractor fields
-- this needs (an older ROM cache), so callers can fall back rather than fail.
function MapContext.build(data, mapId, x, y)
  local map = data and data.maps and data.maps[mapId]
  if not map then return nil, "unknown map " .. tostring(mapId) end
  local sram = map.sram
  if not (sram and sram.header and sram.objects) then
    return nil, "map cache has no saved-map bytes (re-import the ROM)"
  end
  x, y = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)

  local writes = {}
  local header = sram.header
  writes[O.curMapHeader] = header
  local height, width = header[2], header[3]
  local connectionFlags = header[10]

  -- Connections: LoadMapHeader writes $FF over all four connected-map bytes
  -- and then copies 11 bytes per present direction, north/south/west/east.
  -- The disabled slots' remaining bytes are never read.
  local conn = {}
  for i = 1, 4 * CONNECTION_STRUCT do conn[i] = 0 end
  for slot = 0, 3 do conn[slot * CONNECTION_STRUCT + 1] = 0xFF end
  local pos = 1
  for slot, flag in ipairs({ 0x08, 0x04, 0x02, 0x01 }) do
    if math.floor(connectionFlags / flag) % 2 == 1 then
      for i = 0, CONNECTION_STRUCT - 1 do
        conn[(slot - 1) * CONNECTION_STRUCT + 1 + i] = (sram.connections or {})[pos + i] or 0
      end
      pos = pos + CONNECTION_STRUCT
    end
  end
  writes[O.connectionHeaders] = conn

  local parsed = parseObjects(sram.objects)
  if not parsed then return nil, "malformed object data for " .. tostring(mapId) end
  writes[O.mapBackgroundTile] = { parsed.backgroundTile }
  writes[O.numberOfWarps] = { parsed.warpCount }
  writes[O.warpEntries] = parsed.warps
  writes[O.numSigns] = { parsed.signCount }
  writes[O.signCoords] = parsed.signCoords
  writes[O.signTextIDs] = parsed.signTexts
  writes[O.numSprites] = { parsed.spriteCount }
  writes[O.mapSpriteData] = parsed.spriteData
  writes[O.mapSpriteExtra] = parsed.spriteExtra

  -- "map height/width in 2x2 tile blocks", doubled at the end of LoadMapHeader
  writes[O.currentMapHeight2] = { (height * 2) % 256 }
  writes[O.currentMapWidth2] = { (width * 2) % 256 }

  -- The tileset header, as predef LoadTilesetHeader would have copied it.
  local tilesets = data.tilesets or {}
  local tilesetDef = tilesets[map.tileset]
  if not (tilesetDef and tilesetDef.header) then
    return nil, ("no tileset bytes for %s (re-import the ROM)"):format(tostring(mapId))
  end
  local row = {}
  for i = 1, 11 do row[i] = tilesetDef.header[i] end
  writes[O.tilesetHeader] = row
  local tileAnimations = tilesetDef.header[12] or 0

  -- MapSongBanks: without it the game continues with sound id 0 and audio
  -- bank 0, which is what actually hangs a Continue on a white screen.
  local audio = data.audio
  local songLabel = audio and audio.mapSongs and audio.mapSongs[mapId]
  local song = songLabel and audio.songs and audio.songs[songLabel]
  local id = song and soundId(song.address)
  if not (id and song.bank) then
    return nil, ("no map music for %s (re-import the ROM)"):format(tostring(mapId))
  end
  writes[O.mapMusicSoundID] = { id }
  writes[O.mapMusicROMBank] = { song.bank % 256 }

  -- engine/overworld/wild_mons.asm:1
  if type(data.encounters) ~= "table" then
    return nil, "no wild encounter data (re-import the ROM)"
  end
  local enc = data.encounters[mapId]
  local pokemon = data.pokemon or {}
  local function wildRows(t)
    local out = {}
    for i = 1, NUM_WILDMONS do
      local slot = t.slots and t.slots[i]
      local def = slot and pokemon[slot.species]
      if not (slot and def and def.index) then return nil end
      out[#out + 1] = (tonumber(slot.level) or 0) % 256
      out[#out + 1] = def.index % 256
    end
    return out
  end
  for _, kind in ipairs({ "grass", "water" }) do
    local t = type(enc) == "table" and enc[kind] or nil
    local rate = t and tonumber(t.rate) or 0
    writes[O[kind .. "Rate"]] = { rate % 256 }
    if rate ~= 0 then
      local rows = wildRows(t)
      if not rows then
        return nil, ("bad %s wild data for %s (re-import the ROM)"):format(kind, tostring(mapId))
      end
      writes[O[kind .. "Mons"]] = rows
    end
  end

  -- Player position within its block, and the upper-left corner of the view.
  -- The pointer is the same expression the warp_to tables are assembled with
  -- (macros/coords.asm event_displacement).
  writes[O.yBlockCoord] = { y % 2 }
  writes[O.xBlockCoord] = { x % 2 }
  local view = OVERWORLD_MAP + 7 + width
    + (width + 6) * math.floor(y / 2) + math.floor(x / 2)
  writes[O.viewPointer] = { view % 256, math.floor(view / 256) % 256 }

  -- sSpriteData.  LoadMapHeader zeroes structs 1-15, sets their image index to
  -- $ff (off screen until the engine places them), then fills in each map
  -- object's picture id and its map Y/X plus movement byte 1.  Struct 0 is the
  -- player, which SpecialEnterMap rebuilds through ResetPlayerSpriteData.
  local spriteData = {}
  for i = 1, NUM_SPRITE_STRUCTS * SPRITE_STRUCT * 2 do spriteData[i] = 0 end
  local data2 = NUM_SPRITE_STRUCTS * SPRITE_STRUCT
  for slot = 1, NUM_SPRITE_STRUCTS - 1 do
    spriteData[slot * SPRITE_STRUCT + 2 + 1] = 0xFF
  end
  for index, sprite in ipairs(parsed.sprites) do
    local base = index * SPRITE_STRUCT
    spriteData[base + 1] = sprite.picture
    spriteData[data2 + base + 4 + 1] = sprite.mapY
    spriteData[data2 + base + 5 + 1] = sprite.mapX
    spriteData[data2 + base + 6 + 1] = sprite.movement1
  end

  return {
    writes = writes,
    spriteData = spriteData,
    tileAnimations = tileAnimations,
  }
end

return MapContext
