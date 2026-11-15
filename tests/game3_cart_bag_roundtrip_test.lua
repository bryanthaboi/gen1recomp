#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq

local GAME = arg[1]
if not GAME then
  for _, v in ipairs({ "emerald", "ruby" }) do
    local st = os.execute("luajit tests/game3_cart_bag_roundtrip_test.lua " .. v)
    check(st == 0 or st == true, v .. " bag round trip")
  end
end

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

GAME = GAME or "firered"
require("src.import.gba.versions").select(GAME)
if not require("tests.game3_cache").mount(GAME) then
  print("[skip] game3_cart_bag_roundtrip_test " .. GAME .. ": no cache")
  T.finish("game3_cart_bag_roundtrip_test")
  os.exit(T.failures == 0 and 0 or 1)
end
require("src.core.game3.dataset").mountExtractRoots()
require("src.core.GameVersion").set(GAME)

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveSerializer = require("src.core.SaveSerializer")
local Schema = require("src.core.game3.save_schema_firered")
local G = require("src.save_convert.Gen3Save").forVersion(GAME)

local function session(cart)
  local save = assert(SaveConvert.importSav(cart, GAME, GAME))
  return Schema.fromSaveTable(assert(SaveSerializer.decode(SaveSerializer.encode(save))))
end

local function roundTrip(label, cart)
  local out, err = SaveConvert.exportSav(Schema.toSaveTable(session(cart)), GAME, cart)
  check(out ~= nil, label .. " exports (" .. tostring(err) .. ")")
  if not out then return end
  local a, b = G.readBlocks(cart), G.readBlocks(out)
  local diff = {}
  for i = 1, #a.sb1 do
    if a.sb1:byte(i) ~= b.sb1:byte(i) then diff[#diff + 1] = ("0x%04X"):format(i - 1) end
  end
  eq(table.concat(diff, " "), "", label .. " SaveBlock1 byte-identical through a loaded session")
  check(a.sb2 == b.sb2 and a.storage == b.storage, label .. " SaveBlock2 and storage byte-identical")
end

if GAME == "firered" then
  local F = require("tests.fixture_data.gen3_saves")
  for _, name in ipairs({ "fr_rich_game", "lg_rich_game" }) do roundTrip(name, unrle(F.images[name])) end
end

local born = assert(SaveConvert.exportSav(Schema.toSaveTable(Schema.newGame({ version = GAME, name = "BAG", gender = 0, trainerIdLower = 4321 })), GAME, nil))
local c, blocks = assert(G.decode(born))
c.pockets.TM_CASE = { { id = 339, qty = 1 }, { id = 290, qty = 1 }, { id = 289, qty = 2 } }
c.pockets.ITEMS = { { id = 13, qty = 5 }, { id = 0, qty = 0 }, { id = 14, qty = 3 } }
c.pockets.BERRY_POUCH = { { id = 139, qty = 7 }, { id = 133, qty = 2 } }
local cart = G.encode(c, { template = blocks })
local doctored = assert(G.decode(cart))
eq(doctored.pockets.TM_CASE[1].id, 339, GAME .. " doctored cart keeps HM01 ahead of the TMs")
roundTrip(GAME .. " unsorted TM/berry pockets with a hole", cart)

local s = session(cart)
local items = s.bag.pockets.ITEMS
items[#items + 1] = { id = 17, qty = 1 }
local edited = assert(G.decode(assert(SaveConvert.exportSav(Schema.toSaveTable(s), GAME, cart))))
local ids = {}
for _, it in ipairs(edited.pockets.ITEMS) do ids[#ids + 1] = it.id .. "x" .. it.qty end
eq(table.concat(ids, " "), "13x5 14x3 17x1", GAME .. " an edited pocket exports the session's slots")

local function exportedSlots(sess, pocket)
  local d = assert(G.decode(assert(SaveConvert.exportSav(Schema.toSaveTable(sess), GAME, cart))))
  local out = {}
  for _, it in ipairs(d.pockets[pocket]) do out[#out + 1] = it.id .. "x" .. it.qty end
  return table.concat(out, " ")
end

-- pokefirered/src/item_menu.c:967
s = session(cart)
items = s.bag.pockets.ITEMS
items[1], items[2] = items[2], items[1]
eq(exportedSlots(s, "ITEMS"), "14x3 13x5", GAME .. " a reordered pocket exports the session's order")

s = session(cart)
local Bag = require("src.core.game3.bag")
assert(Bag.remove(s.bag, 13, 5))
assert(Bag.add(s.bag, 13, 5))
eq(exportedSlots(s, "ITEMS"), "14x3 13x5", GAME .. " a stack tossed and picked up again goes to the end")

T.finish("game3_cart_bag_roundtrip_test " .. GAME)
