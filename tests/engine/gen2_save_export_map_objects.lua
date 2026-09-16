-- A Gen 2 export that moved maps carries the new map's object window
-- (data/maps/setup_scripts.asm MapSetupScript_Continue, home/map.asm
-- ReadObjectEvents). Same-map exports leave the template's window alone,
-- byte for byte, which is the #1852 guarantee these tests also pin.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2Layout = require("src.save_convert.Gen2Layout")
local Gen2MapContext = require("src.save_convert.Gen2MapContext")

local SIZE = Gen2Save.SAVE_SIZE
local MAPOBJECT = Gen2MapContext.MAPOBJECT_LENGTH
local STRUCT = Gen2MapContext.OBJECT_LENGTH

-- A sealed template standing on a chosen map, with a recognizable pattern
-- across its whole object window so both preservation and rebuild are
-- visible in the bytes. Synthesized, not checked in: a real .sav is
-- personal data, same rule tests/engine/gen2_save_import.lua follows.
local function template(L, O, group, number)
  local b = {}
  for i = 0, SIZE - 1 do b[i] = 0 end
  b[L.wMapGroup], b[L.wMapNumber] = group, number
  for i = 0, Gen2MapContext.NUM_OBJECTS * MAPOBJECT - 1 do
    b[O.mapObjects + i] = 0xA0 + i % 16
  end
  for i = 0, Gen2MapContext.NUM_OBJECT_STRUCTS * STRUCT - 1 do
    b[O.objectStructs + i] = 0xB0 + i % 16
  end
  for i = 0, Gen2MapContext.NUM_OBJECTS - 1 do b[O.objectMasks + i] = 0xC0 end
  b[O.objectFollow], b[O.objectFollow + 1] = 3, 4
  b[O.objectEventCount] = 9
  b[L.sCheckValue1] = 0x63
  b[L.sCheckValue2] = 0x7F
  local sum = 0
  for i = L.sGameData, L.sGameDataEnd - 1 do sum = (sum + b[i]) % 65536 end
  b[L.sChecksum] = sum % 256
  b[L.sChecksum + 1] = math.floor(sum / 256) % 256
  local out = {}
  for i = 0, SIZE - 1 do out[i + 1] = string.char(b[i]) end
  return table.concat(out)
end

-- The map the moved save lands on: two objects, one carrying every field a
-- real object_event can, one minimal.
local function fixtureData(group, number)
  return {
    pokemon = {}, moves = {}, items = {},
    maps = {
      FIX_HOUSE = {
        group = group, map = number,
        objectEventsAddr = 0x5A17,
        width = 4, height = 3,
        blocks = {
          0x01, 0x02, 0x03, 0x04,
          0x11, 0x12, 0x13, 0x14,
          0x21, 0x22, 0x23, 0x24,
        },
        objects = {
          {
            index = 1, spriteId = 0x2F, x = 3, y = 5, movement = 0x07,
            radius = { y = 2, x = 1 }, hours = { -1, 20 },
            palette = 4, type = 2, sight = 0,
            script = 0x6BCD, eventFlag = 0x02A5,
          },
          {
            index = 2, spriteId = 0x11, x = 0, y = 0, movement = 0x01,
            radius = { y = 0, x = 0 }, hours = { -1, -1 },
            palette = 0, type = 5, sight = 3,
            script = 0x6BE0,
          },
        },
      },
    },
  }
end

local function save(group, number, x, y)
  return {
    player = { name = "TESTER" },
    position = { mapGroup = group, mapNumber = number, x = x, y = y },
  }
end

local function u8(bytes, at) return bytes:byte(at + 1) end

for _, spec in ipairs({
  { version = "crystal", L = Gen2Layout.crystal, O = Gen2MapContext.OFFSETS.crystal },
  { version = "gold", L = Gen2Layout.goldSilver, O = Gen2MapContext.OFFSETS.goldSilver },
}) do
  local L, O = spec.L, spec.O
  local tpl = template(L, O, 21, 14)

  -- Same map: the template's whole object window survives untouched.
  local bytes, err = Gen2Save.encode(save(21, 14, 6, 1), spec.version, tpl,
    fixtureData(21, 14))
  T.check(bytes, spec.version .. " same-map export succeeds: " .. tostring(err))
  local windowSame = true
  for i = 0, Gen2MapContext.NUM_OBJECTS * MAPOBJECT - 1 do
    if u8(bytes, O.mapObjects + i) ~= u8(tpl, O.mapObjects + i) then
      windowSame = false
      break
    end
  end
  T.check(windowSame, spec.version .. ": same-map export leaves wMapObjects byte-identical")
  T.eq(u8(bytes, O.objectEventCount), 9,
    spec.version .. ": same-map export leaves the object count alone")

  -- Moved: the window is the NEW map's, exactly as ReadObjectEvents lays
  -- it out.
  bytes, err = Gen2Save.encode(save(21, 15, 6, 1), spec.version, tpl,
    fixtureData(21, 15))
  T.check(bytes, spec.version .. " moved export succeeds: " .. tostring(err))

  -- home/map.asm:941 ReadObjectEvents (pokecrystal home/map.asm:572)
  local slot1 = O.mapObjects + O.firstObjectSlot * MAPOBJECT
  local expected = {
    0xFF, 0x2F, 5 + 4, 3 + 4, 0x07,
    2 * 16 + 1, 0xFF, 20, 4 * 16 + 2, 0x00,
    0xCD, 0x6B, 0xA5, 0x02, 0, 0,
  }
  for i, want in ipairs(expected) do
    T.eq(u8(bytes, slot1 + i - 1), want,
      ("%s: object 1 byte %d"):format(spec.version, i))
  end
  T.eq(u8(bytes, slot1 + MAPOBJECT + 1), 0x11, spec.version .. ": object 2 sprite")
  -- An object with no event flag writes the -1 the game uses for "none".
  T.eq(u8(bytes, slot1 + MAPOBJECT + 12), 0xFF, spec.version .. ": no-flag object writes $FFFF")
  T.eq(u8(bytes, slot1 + MAPOBJECT + 13), 0xFF, spec.version .. ": no-flag object writes $FFFF hi")
  local empty = slot1 + 2 * MAPOBJECT
  T.eq(u8(bytes, empty), 0, spec.version .. ": empty slot struct id")
  T.eq(u8(bytes, empty + 1), 0, spec.version .. ": empty slot sprite")
  T.eq(u8(bytes, empty + 2), 0xFF, spec.version .. ": empty slot y coord")
  if O.firstObjectSlot > 1 then
    T.eq(u8(bytes, O.mapObjects + MAPOBJECT + 1), 0,
      spec.version .. ": the slot Gold and Silver skip stays empty")
  end

  local screen = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x02, 0x03, 0x04, 0x00, 0x00, 0x00,
    0x12, 0x13, 0x14, 0x00, 0x00, 0x00,
    0x22, 0x23, 0x24, 0x00, 0x00, 0x00,
  }
  for i, want in ipairs(screen) do
    T.eq(u8(bytes, O.screenSave + i - 1), want,
      ("%s: screen block %d"):format(spec.version, i))
  end

  -- The player: map object coordinates re-anchored, sprite untouched.
  T.eq(u8(bytes, O.mapObjects + 2), 1 + 4, spec.version .. ": player map object y")
  T.eq(u8(bytes, O.mapObjects + 3), 6 + 4, spec.version .. ": player map object x")
  T.eq(u8(bytes, O.mapObjects + 1), u8(tpl, O.mapObjects + 1),
    spec.version .. ": player map object sprite keeps the template's byte")

  -- The player struct moves with them; the NPC structs are cleared.
  T.eq(u8(bytes, O.objectStructs + Gen2MapContext.STRUCT_MAP_X), 6 + 4,
    spec.version .. ": player struct map x")
  T.eq(u8(bytes, O.objectStructs + Gen2MapContext.STRUCT_MAP_Y), 1 + 4,
    spec.version .. ": player struct map y")
  T.eq(u8(bytes, O.objectStructs + STRUCT), 0, spec.version .. ": NPC struct 1 cleared")
  T.eq(u8(bytes, O.objectStructs + 12 * STRUCT + STRUCT - 1), 0,
    spec.version .. ": NPC struct 12 cleared to its last byte")

  -- Masks, follow, count and pointer.
  T.eq(u8(bytes, O.objectMasks), 0, spec.version .. ": object masks cleared")
  T.eq(u8(bytes, O.objectMasks + 15), 0, spec.version .. ": all sixteen of them")
  T.eq(u8(bytes, O.objectFollow), 0xFF, spec.version .. ": follow leader reset")
  T.eq(u8(bytes, O.objectFollow + 1), 0xFF, spec.version .. ": follow follower reset")
  T.eq(u8(bytes, O.objectEventCount), 2, spec.version .. ": object count")
  T.eq(u8(bytes, O.objectEventsPointer), 0x17, spec.version .. ": events pointer lo")
  T.eq(u8(bytes, O.objectEventsPointer + 1), 0x5A, spec.version .. ": events pointer hi")

  -- And the checksum still seals the block the game verifies.
  T.check(Gen2Save.checksumValid(bytes, L), spec.version .. ": moved export checksums")

  -- Refusals: an unknown map, and a cache from before the extractor kept
  -- the object-table address.
  local refused, why = Gen2Save.encode(save(9, 9, 0, 0), spec.version, tpl,
    fixtureData(21, 15))
  T.check(refused == nil and why:find("unknown map 9/9", 1, true),
    spec.version .. ": unknown map refuses: " .. tostring(why))

  local stale = fixtureData(21, 15)
  stale.maps.FIX_HOUSE.objectEventsAddr = nil
  refused, why = Gen2Save.encode(save(21, 15, 0, 0), spec.version, tpl, stale)
  T.check(refused == nil and why:find("re%-import the ROM"),
    spec.version .. ": stale cache refuses with the re-import hint: " .. tostring(why))

  local noBlocks = fixtureData(21, 15)
  noBlocks.maps.FIX_HOUSE.blocks = nil
  refused, why = Gen2Save.encode(save(21, 15, 0, 0), spec.version, tpl, noBlocks)
  T.check(refused == nil and why:find("no block data", 1, true),
    spec.version .. ": a cache with no blocks refuses rather than exporting a "
      .. "save that continues into an empty room: " .. tostring(why))
end

-- home/map.asm:1169, :1829
local function connectedData()
  local function neighbour(group, number, base)
    local blocks = {}
    for i = 1, 16 do blocks[i] = base + i end
    return {
      group = group, map = number, objectEventsAddr = 0x4000,
      width = 4, height = 4, blocks = blocks, objects = {},
    }
  end
  return {
    pokemon = {}, moves = {}, items = {},
    maps = {
      FIX_TOWN = {
        group = 30, map = 1, objectEventsAddr = 0x4A00,
        width = 4, height = 4, objects = {},
        blocks = {
          0x11, 0x12, 0x13, 0x14,
          0x21, 0x22, 0x23, 0x24,
          0x31, 0x32, 0x33, 0x34,
          0x41, 0x42, 0x43, 0x44,
        },
        connections = {
          north = { group = 30, map = 2, mapId = "FIX_NORTH",
                    stripLength = 4, width = 4, offset = 0 },
          south = { group = 30, map = 3, mapId = "FIX_SOUTH",
                    stripLength = 4, width = 4, offset = 0 },
          west  = { group = 30, map = 4, mapId = "FIX_WEST",
                    stripLength = 4, width = 4, offset = 0 },
          east  = { group = 30, map = 5, mapId = "FIX_EAST",
                    stripLength = 4, width = 4, offset = 0 },
        },
      },
      FIX_NORTH = neighbour(30, 2, 0x50),
      FIX_SOUTH = neighbour(30, 3, 0x60),
      FIX_WEST = neighbour(30, 4, 0x70),
      FIX_EAST = neighbour(30, 5, 0x80),
    },
  }
end

for _, spec in ipairs({
  { version = "crystal", L = Gen2Layout.crystal, O = Gen2MapContext.OFFSETS.crystal },
  { version = "gold", L = Gen2Layout.goldSilver, O = Gen2MapContext.OFFSETS.goldSilver },
}) do
  local L, O = spec.L, spec.O
  local tpl = template(L, O, 21, 14)
  local bytes, err = Gen2Save.encode(save(30, 1, 0, 0), spec.version, tpl,
    connectedData())
  T.check(bytes, spec.version .. " moved onto a connected map: " .. tostring(err))
  if bytes then
    local northWest = {
      0x00, 0x00, 0x59, 0x5A, 0x5B, 0x5C,
      0x00, 0x00, 0x5D, 0x5E, 0x5F, 0x60,
      0x73, 0x74, 0x11, 0x12, 0x13, 0x14,
      0x77, 0x78, 0x21, 0x22, 0x23, 0x24,
      0x7B, 0x7C, 0x31, 0x32, 0x33, 0x34,
    }
    for i, want in ipairs(northWest) do
      T.eq(u8(bytes, O.screenSave + i - 1), want,
        ("%s: connected screen block %d"):format(spec.version, i))
    end
  end

  bytes, err = Gen2Save.encode(save(30, 1, 7, 7), spec.version, tpl, connectedData())
  T.check(bytes, spec.version .. " moved to the far corner: " .. tostring(err))
  if bytes then
    local southEast = {
      0x22, 0x23, 0x24, 0x85, 0x86, 0x87,
      0x32, 0x33, 0x34, 0x89, 0x8A, 0x8B,
      0x42, 0x43, 0x44, 0x8D, 0x8E, 0x8F,
      0x62, 0x63, 0x64, 0x00, 0x00, 0x00,
      0x66, 0x67, 0x68, 0x00, 0x00, 0x00,
    }
    for i, want in ipairs(southEast) do
      T.eq(u8(bytes, O.screenSave + i - 1), want,
        ("%s: far-corner screen block %d"):format(spec.version, i))
    end
  end

  -- engine/menus/intro_menu.asm:148
  bytes = Gen2Save.encode(save(21, 15, 0, 0), spec.version, tpl, fixtureData(21, 15))
  T.check(bytes, spec.version .. ": an export with no box names at all")
  if bytes then
    local box1 = { 0x81, 0x8E, 0x97, 0xF7, 0x50 }
    for i, want in ipairs(box1) do
      T.eq(u8(bytes, L.wBoxNames + i - 1), want,
        ("%s: default box 1 name byte %d"):format(spec.version, i))
    end
    T.eq(u8(bytes, L.wBoxNames + 13 * 9 + 4), 0xFA,
      spec.version .. ": and box 14 ends in a 4")
  end
end

T.finish("gen2 save export map objects")
