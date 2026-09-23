-- Unit tests for Issue #2314: FireRed Hidden Items & Itemfinder
local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local Game3Cache = require("tests.game3_cache")
if not Game3Cache.bundle() then print("[skip] hidden_items: " .. tostring(Game3Cache.reason)) return end

local ExtractMapEvents = require("src.import.gba.extract_map_events")
local Field = require("src.core.game3.field")
local ItemUse = require("src.core.game3.item_use")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Flags = require("src.core.game3.scripting.flags")
local Message = require("src.ui.game3.message")

print("=== [Test 1: BgEvent parsing for Hidden Items] ===")

-- Mock ROM buffer reader helper
local function create_mock_rom(bytes)
  local rom = {}
  function rom:get(addr)
    return bytes[addr + 1] or 0
  end
  function rom:u16(addr)
    local b0 = self:get(addr)
    local b1 = self:get(addr + 1)
    return b0 + b1 * 256
  end
  function rom:u32(addr)
    local b0 = self:get(addr)
    local b1 = self:get(addr + 1)
    local b2 = self:get(addr + 2)
    local b3 = self:get(addr + 3)
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
  end
  function rom:ptrOffset(ptr)
    if ptr >= 0x08000000 and ptr <= 0x09FFFFFF then
      return ptr - 0x08000000
    end
    return nil
  end
  return rom
end

-- Create mock BgEvents table in ROM:
-- BgEvent 0: Sign (kind 0) at x=5, y=10, elevation=3, scriptPtr=0x08123456
-- BgEvent 1: Hidden Item (kind 7) at x=12, y=20, elevation=0, item=14 (ANTIDOTE), hiddenItemId=1, quantity=1, underfoot=0
-- BgEvent 2: Hidden Item (kind 7) at x=3, y=4, elevation=0, item=13 (POTION), hiddenItemId=0, quantity=1, underfoot=1
local mock_bytes = {}
for i = 1, 100 do mock_bytes[i] = 0 end

-- Event 0: Sign at offset 0
mock_bytes[1] = 5; mock_bytes[2] = 0 -- x = 5
mock_bytes[3] = 10; mock_bytes[4] = 0 -- y = 10
mock_bytes[5] = 3 -- elevation = 3
mock_bytes[6] = 0 -- kind = 0 (sign)
-- scriptPtr at offset 8 = 0x08000020
mock_bytes[9] = 0x20; mock_bytes[10] = 0x00; mock_bytes[11] = 0x00; mock_bytes[12] = 0x08

-- Event 1: Hidden Antidote at offset 12
mock_bytes[13] = 12; mock_bytes[14] = 0 -- x = 12
mock_bytes[15] = 20; mock_bytes[16] = 0 -- y = 20
mock_bytes[17] = 0 -- elevation = 0
mock_bytes[18] = 7 -- kind = 7 (BG_EVENT_HIDDEN_ITEM)
mock_bytes[21] = 14; mock_bytes[22] = 0 -- item = 14 (ANTIDOTE)
mock_bytes[23] = 0x01; mock_bytes[24] = 0x01

-- Event 2: Hidden Potion at offset 24 (underfoot bit 15 set)
mock_bytes[25] = 3; mock_bytes[26] = 0 -- x = 3
mock_bytes[27] = 4; mock_bytes[28] = 0 -- y = 4
mock_bytes[29] = 0 -- elevation = 0
mock_bytes[30] = 7 -- kind = 7 (BG_EVENT_HIDDEN_ITEM)
mock_bytes[33] = 13; mock_bytes[34] = 0 -- item = 13 (POTION)
mock_bytes[35] = 0x00; mock_bytes[36] = 0x81

local rom = create_mock_rom(mock_bytes)
local mapEventsOff = 0x08000000

-- In GBA MapEvents: bgEvents count is at offset 2 (u8), pointer is at offset 8 (u32)
local eventsHeader = {}
for i = 1, 32 do eventsHeader[i] = 0 end
eventsHeader[1] = 0 -- objCount
eventsHeader[2] = 0 -- warpCount
eventsHeader[3] = 3 -- bgCount = 3
eventsHeader[4] = 0 -- coordCount
-- bgEvents pointer = 0x08000000 (at offset 8 in MapEvents struct: objectsPtr(4), warpsPtr(4), bgEventsPtr(4))
-- actually MapEvents struct in GBA:
-- u8 objectEventCount (0)
-- u8 warpCount (1)
-- u8 coordEventCount (2)
-- u8 bgEventCount (3)
-- u32 objectEvents (4)
-- u32 warps (8)
-- u32 coordEvents (12)
-- u32 bgEvents (16)
eventsHeader[4] = 3 -- bgCount = 3
eventsHeader[17] = 0x00; eventsHeader[18] = 0x00; eventsHeader[19] = 0x00; eventsHeader[20] = 0x08

local full_bytes = {}
for i, b in ipairs(eventsHeader) do full_bytes[i] = b end
for i, b in ipairs(mock_bytes) do full_bytes[#eventsHeader + i] = b end
-- bgEvents pointer at offset 16 points to offset 32 (0x08000020)
full_bytes[17] = 32; full_bytes[18] = 0; full_bytes[19] = 0; full_bytes[20] = 0x08

local romFull = create_mock_rom(full_bytes)
local parsed = ExtractMapEvents.parseMapEvents(romFull, 0x08000000)
assert(parsed ~= nil, "parseMapEvents should succeed")
assert(#parsed.bgEvents == 3, "should parse 3 bgEvents")

local sign = parsed.bgEvents[1]
assert(sign.type == "sign", "bgEvent 1 should be sign")
assert(sign.x == 5 and sign.y == 10, "sign coords match")

local antidote = parsed.bgEvents[2]
assert(antidote.type == "hidden_item", "bgEvent 2 should be hidden_item")
assert(antidote.x == 12 and antidote.y == 20, "antidote coords match")
assert(antidote.item == 14, "antidote item ID is 14")
assert(antidote.hiddenItemId == 1, "hiddenItemId is 1")
assert(antidote.quantity == 1, "quantity is 1")
assert(antidote.underfoot == false, "underfoot is false")
assert(antidote.flag == 0x3E8 + 1, "flag is 0x3E9 (1001)")

local potion = parsed.bgEvents[3]
assert(potion.type == "hidden_item", "bgEvent 3 should be hidden_item")
assert(potion.x == 3 and potion.y == 4, "potion coords match")
assert(potion.item == 13, "potion item ID is 13")
assert(potion.hiddenItemId == 0, "hiddenItemId is 0")
assert(potion.quantity == 1, "quantity is 1")
assert(potion.underfoot == true, "underfoot is true")
assert(potion.flag == 0x3E8 + 0, "flag is 0x3E8 (1000)")

print("[OK] BgEvent parsing correctly extracted hidden items and unpacked union fields.")

for _, hiddenId in ipairs({ 0, 1, 190, 255 }) do
  for _, quantity in ipairs({ 1, 2, 3, 63, 64, 127 }) do
    for _, underfoot in ipairs({ false, true }) do
      full_bytes[32 + 23] = hiddenId
      full_bytes[32 + 24] = quantity + (underfoot and 128 or 0)
      local event = ExtractMapEvents.parseMapEvents(romFull, 0x08000000).bgEvents[2]
      assert(event.hiddenItemId == hiddenId, "quantity must not leak into hidden item flag")
      assert(event.flag == 1000 + hiddenId and event.flag < 1256, "hidden flags stay in their eight-bit range")
      assert(event.quantity == quantity, "all seven quantity bits must survive extraction")
      assert(event.underfoot == underfoot, "underfoot must not change quantity or flag")
    end
  end
end
full_bytes[32 + 23], full_bytes[32 + 24] = 1, 1
print("PASS hidden_item_flag_quantity_bit_boundaries")

print("=== [Test 2: Hidden Item Field Pickup & Bag Integration] ===")

local game = {
  data = {
    maps = {
      ["MAP_VIRIDIAN_FOREST"] = {
        bgEvents = parsed.bgEvents
      }
    }
  }
}

local session = {
  name = "RED",
  map = "MAP_VIRIDIAN_FOREST",
  flags = {},
  bag = Bag.new(),
  playerX = 12,
  playerY = 19,
}
Field._session = session
Field._game = game

-- Test hidden item lookup
local hiddenFound = Field.hiddenItemAt(game, 12, 20, 0)
assert(hiddenFound ~= nil, "Should find hidden Antidote at 12, 20")
assert(hiddenFound.item == 14, "Found item is Antidote")

-- Test picking up Antidote
local initialAntidoteCount = Bag.get(session.bag, 14)
assert(initialAntidoteCount == 0, "Bag starts with 0 Antidote")
assert(Flags.getFlag(session, nil, 0x3E9) == false, "Flag 0x3E9 starts false")

local pickedUp = Field.pickUpHiddenItem(game, hiddenFound)
assert(pickedUp == true, "pickUpHiddenItem should return true")
assert(Bag.get(session.bag, 14) == 1, "Bag now has 1 Antidote")
assert(Flags.getFlag(session, nil, 0x3E9) == true, "Flag 0x3E9 is now true")

-- Trying to find or pick up again should fail
local hiddenAgain = Field.hiddenItemAt(game, 12, 20, 0)
assert(hiddenAgain == nil, "Hidden item should no longer be found once flag is set")

local pickedUpAgain = Field.pickUpHiddenItem(game, hiddenFound)
assert(pickedUpAgain == false, "Cannot pick up already collected hidden item")

print("[OK] Hidden item pickup successfully added to bag and marked flag.")

print("=== [Test 3: Itemfinder Scanning Logic] ===")

-- Session at (12, 18), hidden Antidote (12, 20) is already collected (flag set),
-- hidden Potion is at (3, 4).
-- Distance from (12, 18) to Potion (3, 4) is dx = -9, dy = -14 (out of range > 7).

session.playerX = 12
session.playerY = 18
local ok, kind, text = ItemUse.useField(session, session.bag, ItemsData.ITEM_ITEMFINDER, nil)
assert(ok == false, "Itemfinder should not respond when out of range")
assert(text == "… … … …Nope!\nThere's no response.", "Response text matches pret nope string")

-- pokefirered/src/itemfinder.c:216
Flags.setFlag(session, nil, 0x3E9, false)
local okNear, kindNear, textNear = ItemUse.useField(session, session.bag, ItemsData.ITEM_ITEMFINDER, nil)
assert(okNear == true, "Itemfinder should detect nearby hidden item")
assert(textNear == "Huh?\nThe ITEMFINDER's responding!\fThere's an item buried around here!", "Nearby text matches pret")
Flags.setFlag(session, nil, 0x3E9, true)

-- pokefirered/src/itemfinder.c:213
session.playerX = 5
session.playerY = 6
local okAway = ItemUse.useField(session, session.bag, ItemsData.ITEM_ITEMFINDER, nil)
assert(okAway == false, "An underfoot item only answers when the player stands on it")

session.playerX = 3
session.playerY = 4
local okFeet, kindFeet, textFeet = ItemUse.useField(session, session.bag, ItemsData.ITEM_ITEMFINDER, nil)
assert(okFeet == true, "Itemfinder should detect underfoot hidden item")
assert(textFeet == "Oh!\nThe ITEMFINDER's shaking wildly!\fThere's an item buried underfoot!\f… … … … … …", "Underfoot text matches pret")

local hiddenPotion = Field.hiddenItemAt(game, 3, 4, 0)
assert(hiddenPotion ~= nil, "Should find hidden Potion at 3, 4")
assert(Field.digUpUnderfootItem(game, hiddenPotion), "the Itemfinder digs the underfoot item up")
assert(Bag.get(session.bag, 13) == 1, "Bag now has 1 Potion")
assert(Flags.getFlag(session, nil, 0x3E8) == true, "Flag 0x3E8 is now true")
Message.close()

local okDone, kindDone, textDone = ItemUse.useField(session, session.bag, ItemsData.ITEM_ITEMFINDER, nil)
assert(okDone == false, "Itemfinder has no response after items collected")
assert(textDone == "… … … …Nope!\nThere's no response.")

print("[OK] Itemfinder detects underfoot, nearby, and no-response cases with accurate FireRed text.")

print("=== All Issue #2314 Hidden Item & Itemfinder tests passed! ===")
