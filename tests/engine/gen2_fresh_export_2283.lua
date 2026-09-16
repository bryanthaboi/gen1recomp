--   luajit tests/engine/gen2_fresh_export_2283.lua
--   * sOptions        data/default_options.asm
--                     engine/overworld/player_object.asm:19 SpawnPlayer
--                     engine/menus/intro_menu.asm:28 _ResetWRAM
--                     engine/overworld/decorations.asm:1 InitDecorations
--                     home/map.asm:1829 LoadConnectionBlockData
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2MapContext = require("src.save_convert.Gen2MapContext")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")

local realFS = love.filesystem

local function fixture()
  return {
    pokemon = {}, moves = {}, items = {},
    maps = { PLAYERS_HOUSE_2F = {
      group = 24, map = 7, objectEventsAddr = 0x5CF0,
      width = 4, height = 3,
      blocks = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 },
      objects = {
        { spriteId = 240, x = 4, y = 2, movement = 1, radius = { x = 0, y = 0 },
          hours = { -1, -1 }, palette = 0, type = 0, sight = 0,
          script = 0x5C5A, eventFlag = 1857 },
        { spriteId = 241, x = 4, y = 4, movement = 1, radius = { x = 0, y = 0 },
          hours = { -1, -1 }, palette = 0, type = 0, sight = 0,
          script = 0x5C54, eventFlag = 1858 },
      },
    } },
  }
end

local function save(gender)
  return {
    generation = 2,
    player = { name = "BRYAN", id = 12345, money = 3000, gender = gender },
    rival = { name = "SILVER" }, mom = { name = "MOM" },
    position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
    party = {}, boxes = {}, boxNames = {}, currentBox = 1,
  }
end

local function u8(bytes, at) return bytes:byte(at + 1) end
-- constants/charmap.asm: "A" is $80 and "0" is $F6.
local function nameAt(bytes, at, n)
  local out = {}
  for i = 0, n - 1 do
    local c = u8(bytes, at + i)
    if c == 0x50 then break end
    if c >= 0xF6 then out[#out + 1] = string.char(c - 0xF6 + 48)
    else out[#out + 1] = string.char(c - 0x80 + 65) end
  end
  return table.concat(out)
end
local function textAt(bytes, at, n)
  local out = {}
  for i = 0, n - 1 do
    local c = u8(bytes, at + i)
    if c == 0x50 then break end
    out[#out + 1] = string.char(c - 0x80 + 65)
  end
  return table.concat(out)
end


for _, version in ipairs({ "gold", "crystal" }) do
  local L = Gen2Save.layoutFor(version)
  local O = Gen2MapContext.offsetsFor(version)
  local bytes, why = Gen2Save.encode(save("male"), version, nil, fixture())
  check(bytes ~= nil, version .. ": a slot with no cartridge exports -- " .. tostring(why))
  if not bytes then break end

  eq(#bytes, Gen2Save.SAVE_SIZE, version .. ": a full battery image")
  eq(Gen2Save.checksumValid(bytes, L), true,
    version .. ": the check values and sum the cartridge verifies")

  -- data/default_options.asm
  local options = { 0x03, 0x01, 0x00, 0x01, 0x40, 0x01, 0x00, 0x00 }
  for i, want in ipairs(options) do
    eq(u8(bytes, L.sOptions + i - 1), want, version .. ": sOptions byte " .. i)
  end

  eq(u8(bytes, L.wSavedAtLeastOnce), 1, version .. ": the save counts as saved")
  eq(textAt(bytes, L.wRedsName, 11), "RED", version .. ": RED@")
  eq(textAt(bytes, L.wGreensName, 11), "GREEN", version .. ": GREEN@")
  eq(u8(bytes, L.wMomItemTriggerBalance) * 65536
     + u8(bytes, L.wMomItemTriggerBalance + 1) * 256
     + u8(bytes, L.wMomItemTriggerBalance + 2), 2300,
    version .. ": MOM_MONEY is the trigger balance")
  for _, at in ipairs({ L.wRoamMon1MapGroup, L.wRoamMon2MapGroup,
                        L.wRoamMon3MapGroup }) do
    eq(u8(bytes, at), 0xFF, version .. ": a roamer's map group is -1")
    eq(u8(bytes, at + 1), 0xFF, version .. ": and its map number")
  end
  eq(u8(bytes, L.wBestMagikarpLengthFeet), 3, version .. ": 3 feet")
  eq(u8(bytes, L.wBestMagikarpLengthInches), 6, version .. ": 6 inches")
  eq(textAt(bytes, L.wMagikarpRecordHoldersName, 11), "RALPH",
    version .. ": held by RALPH")
  eq(u8(bytes, L.sMysteryGiftUnlocked), 0xFF, version .. ": mystery gift -1")
  eq(u8(bytes, L.wNumPCItems), 0, version .. ": the PC is empty")
  eq(u8(bytes, L.wNumPCItems + 1), 0xFF, version .. ": and terminated")
  eq(u8(bytes, L.wDecoBed), 2, version .. ": DECO_FEATHERY_BED")
  eq(u8(bytes, L.wDecoPoster), 16, version .. ": DECO_TOWN_MAP")
  local box1 = { 0x81, 0x8E, 0x97, 0xF7, 0x50 }
  for i, want in ipairs(box1) do
    eq(u8(bytes, L.wBoxNames + i - 1), want, version .. ": box 1 name byte " .. i)
  end
  local box14 = { 0x81, 0x8E, 0x97, 0xF7, 0xFA, 0x50 }
  for i, want in ipairs(box14) do
    eq(u8(bytes, L.wBoxNames + 13 * 9 + i - 1), want,
      version .. ": box 14 name byte " .. i)
  end

  local wantObject = { 0x00, 0x01, 3 + 4, 3 + 4, 0x0B, 0xFF, 0xFF, 0xFF,
                       0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xD5, 0x78 }
  if version == "crystal" then wantObject[9] = 0x80 end
  for i, want in ipairs(wantObject) do
    eq(u8(bytes, O.mapObjects + i - 1), want,
      ("%s: player map object byte %d"):format(version, i - 1))
  end

  local wantStruct = { 0x01, 0x00, 0x00, 0x0B, 0x02, 0x00, 0x00, 0xFF,
                       0x00, 0x01, 0x00, 0x01, 0x00, 0xFF, 0x00, 0x00,
                       7, 7, 7, 7, 7, 7, 0x00, 0x40, 0x40 }
  for i, want in ipairs(wantStruct) do
    eq(u8(bytes, O.objectStructs + i - 1), want,
      ("%s: player struct byte %d"):format(version, i - 1))
  end
  for i = 25, 39 do
    eq(u8(bytes, O.objectStructs + i), 0,
      ("%s: player struct byte %d is zero"):format(version, i))
  end

  local first = O.mapObjects + O.firstObjectSlot * Gen2MapContext.MAPOBJECT_LENGTH
  eq(u8(bytes, first), 0xFF, version .. ": NPC 1 has no struct yet")
  eq(u8(bytes, first + 1), 240, version .. ": NPC 1 sprite")
  eq(u8(bytes, first + 2), 2 + 4, version .. ": NPC 1 y")
  eq(u8(bytes, first + 3), 4 + 4, version .. ": NPC 1 x")
  eq(u8(bytes, O.objectEventCount), 2, version .. ": two object events")
  eq(u8(bytes, O.objectEventsPointer), 0xF0, version .. ": pointer lo")
  eq(u8(bytes, O.objectEventsPointer + 1), 0x5C, version .. ": pointer hi")
  eq(u8(bytes, O.objectFollow), 0xFF, version .. ": nobody is following")

  local screen = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x04, 0x01, 0x03, 0x02, 0x00,
    0x00, 0x05, 0x06, 0x05, 0x05, 0x00,
    0x00, 0x05, 0x05, 0x07, 0x05, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  }
  for i, want in ipairs(screen) do
    eq(u8(bytes, O.screenSave + i - 1), want,
      ("%s: screen block %d"):format(version, i))
  end

  local back, derr = Gen2Save.decode(bytes, version)
  check(back ~= nil, version .. ": the image decodes -- " .. tostring(derr))
  if back then
    eq(back.player.name, "BRYAN", version .. ": the player name survives")
    eq(back.player.money, 3000, version .. ": and the money")
    eq(back.position.mapGroup, 24, version .. ": and the map group")
    eq(back.position.mapNumber, 7, version .. ": and the map number")
    eq(back.position.x, 3, version .. ": and x")
    eq(back.position.y, 3, version .. ": and y")
  end
end

do
  local O = Gen2MapContext.offsetsFor("crystal")
  local female = Gen2Save.encode(save("female"), "crystal", nil, fixture())
  check(female ~= nil, "crystal: a female save exports")
  if female then
    eq(u8(female, O.mapObjects + 8), 0x90, "crystal: PAL_NPC_BLUE for Kris")
  end
end

-- SetDefaultBoxNames left it (engine/menus/intro_menu.asm:148)
do
  for _, version in ipairs({ "gold", "crystal" }) do
    local L = Gen2Save.layoutFor(version)
    local named = save("male")
    named.boxNames = { [2] = "MISC", [3] = "" }
    local bytes = Gen2Save.encode(named, version, nil, fixture())
    check(bytes ~= nil, version .. ": a save with one renamed box exports")
    if bytes then
      eq(nameAt(bytes, L.wBoxNames, 9), "BOX1",
        version .. ": box 1 keeps its default name")
      eq(nameAt(bytes, L.wBoxNames + 9, 9), "MISC",
        version .. ": box 2 keeps the name the player gave it")
      eq(nameAt(bytes, L.wBoxNames + 18, 9), "BOX3",
        version .. ": an empty name is the default, not a blank box")
      eq(nameAt(bytes, L.wBoxNames + 13 * 9, 9), "BOX14",
        version .. ": and box 14")
    end
  end
end

-- home/map.asm:1169
local function connectedFixture()
  local function neighbour(group, number, base)
    local blocks = {}
    for i = 1, 16 do blocks[i] = base + i end
    return {
      group = group, map = number, objectEventsAddr = 0x4000,
      width = 4, height = 4, blocks = blocks, objects = {},
    }
  end
  local town = {
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
                stripLength = 4, width = 4, offset = 0, xOffset = 0, yOffset = 7 },
      south = { group = 30, map = 3, mapId = "FIX_SOUTH",
                stripLength = 4, width = 4, offset = 0, xOffset = 0, yOffset = 0 },
      west  = { group = 30, map = 4, mapId = "FIX_WEST",
                stripLength = 4, width = 4, offset = 0, xOffset = 7, yOffset = 0 },
      east  = { group = 30, map = 5, mapId = "FIX_EAST",
                stripLength = 4, width = 4, offset = 0, xOffset = 0, yOffset = 0 },
    },
  }
  return {
    pokemon = {}, moves = {}, items = {},
    maps = {
      FIX_TOWN = town,
      FIX_NORTH = neighbour(30, 2, 0x50),
      FIX_SOUTH = neighbour(30, 3, 0x60),
      FIX_WEST = neighbour(30, 4, 0x70),
      FIX_EAST = neighbour(30, 5, 0x80),
    },
  }
end

local function connectedSave(x, y)
  local s = save("male")
  s.position = { map = "FIX_TOWN", x = x, y = y }
  return s
end

do
  local northWest = {
    0x00, 0x00, 0x59, 0x5A, 0x5B, 0x5C,
    0x00, 0x00, 0x5D, 0x5E, 0x5F, 0x60,
    0x73, 0x74, 0x11, 0x12, 0x13, 0x14,
    0x77, 0x78, 0x21, 0x22, 0x23, 0x24,
    0x7B, 0x7C, 0x31, 0x32, 0x33, 0x34,
  }
  local southEast = {
    0x22, 0x23, 0x24, 0x85, 0x86, 0x87,
    0x32, 0x33, 0x34, 0x89, 0x8A, 0x8B,
    0x42, 0x43, 0x44, 0x8D, 0x8E, 0x8F,
    0x62, 0x63, 0x64, 0x00, 0x00, 0x00,
    0x66, 0x67, 0x68, 0x00, 0x00, 0x00,
  }
  for _, version in ipairs({ "gold", "crystal" }) do
    local O = Gen2MapContext.offsetsFor(version)
    for _, case in ipairs({
      { name = "north-west", x = 0, y = 0, want = northWest },
      { name = "south-east", x = 7, y = 7, want = southEast },
    }) do
      local bytes, why = Gen2Save.encode(connectedSave(case.x, case.y), version,
        nil, connectedFixture())
      check(bytes ~= nil, ("%s: a fresh save at the %s connection exports -- %s")
        :format(version, case.name, tostring(why)))
      if bytes then
        for i, want in ipairs(case.want) do
          eq(u8(bytes, O.screenSave + i - 1), want,
            ("%s: %s screen block %d"):format(version, case.name, i))
        end
      end
    end
  end

  local gone = connectedFixture()
  gone.maps.FIX_EAST = nil
  local bytes, why = Gen2Save.encode(connectedSave(7, 7), "gold", nil, gone)
  eq(bytes, nil, "a window that reaches an uncached connection is refused")
  check(type(why) == "string" and why:find("FIX_EAST", 1, true)
    and why:find("re%-import the ROM"),
    "and names the map it cannot read -- " .. tostring(why))
  bytes, why = Gen2Save.encode(connectedSave(0, 0), "gold", nil, gone)
  check(bytes ~= nil, "a window that never reaches it still exports -- "
    .. tostring(why))
end

do
  local out, why = Gen2Save.encode({ player = { name = "A" } }, "gold", nil, {})
  eq(out, nil, "a save with no position is refused")
  check(type(why) == "string" and why:find("does not name one", 1, true),
    "and says so -- " .. tostring(why))

  out, why = Gen2Save.encode(save("male"), "gold", nil, { maps = {} })
  eq(out, nil, "a save whose map this cache does not know is refused")
  check(type(why) == "string" and why:find("does not name one", 1, true),
    "and says so too -- " .. tostring(why))
end


do
  local files = {}
  love.filesystem = {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
  SaveData.resetSlotState()
  GameVersion.set("gold")

  local image = Gen2Save.encode(save("male"), "gold", nil, fixture())
  check(image ~= nil, "a 32 KB Gold image to import")

  local ok, slotId = SaveFileIO.importToSlot(image, "gold", true)
  check(ok, "the image imports into a slot -- " .. tostring(slotId))
  local cartPath = "saves/gold/" .. tostring(slotId) .. ".cart"
  check(files[cartPath] ~= nil, "and its cartridge image is kept beside it")

  eq(SaveData.deleteSlot("gold", slotId), true, "the slot is deleted")
  eq(files["saves/gold/" .. tostring(slotId) .. ".lua"], nil, "its save is gone")
  check(files[cartPath] == nil,
    "and so is its cartridge image: slot ids are reused, so a lingering "
      .. ".cart hands the next game on that id a stranger's playthrough")

  local reused = SaveData.createSlot("gold")
  eq(reused, slotId, "the id really is handed out again")
  check(files["saves/gold/" .. tostring(reused) .. ".cart"] == nil,
    "and the fresh slot inherits no cartridge image")

  love.filesystem = realFS
  SaveData.resetSlotState()
  GameVersion.set("red")
end

T.finish("gen2 fresh export 2283")
