-- ../pokecrystal/constants/text_constants.asm:2-3
package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Trade = require("src.online.Trade")
local Protocol = require("src.link.Protocol")
local Wire = require("src.link.Wire")
local Json = require("src.link.Json")

local FILES = {
  pokemon = [[return { TESTMON = { name = "TESTMON", types = { "NORMAL" },
    baseStats = { hp = 50, attack = 50, defense = 50, speed = 50,
      specialAttack = 50, specialDefense = 50 } } }]],
  items = "return {}",
  moves = [[return { TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 } }]],
  type_chart = "return {}",
  constants = "return {}",
  font = [[return { charmap = {
    { seq = "<PK>", code = 225 }, { seq = "<MN>", code = 226 },
    { seq = "A", code = 128 }, { seq = "B", code = 129 } } }]],
}
for name, body in pairs(FILES) do
  love.filesystem.write("gold/data/generated/" .. name .. ".lua", body)
end

local function roundTrip(data, field, value)
  local mon = {
    species = "TESTMON", level = 20, experience = 8000, hp = 30, maxHp = 30,
    dvs = { attack = 10, defense = 11, speed = 12, special = 13 }, statExp = {},
    moves = { { id = "TACKLE", pp = 5, maxPp = 5 } },
    happiness = 70, pokerus = 0, ot = "GOLD", otId = 1234, nickname = "MON",
  }
  mon[field] = value
  local line = Json.encode({ type = "party", mons = { Protocol.packMon2(mon) } })
  local packed = Wire.sanitize(Json.decode(line)).mons[1]
  local got = Protocol.unpackMon2(data, packed, { strict = true })
  return got and got[field]
end

local seen = {}
local ok, why = Trade.withDataset("gold", function(data)
  seen.font = type(data.font) == "table" and type(data.font.charmap) == "table"
  seen.nick9 = roundTrip(data, "nickname", "<PK>ABCDEFGH")
  seen.nick7 = roundTrip(data, "nickname", "<PK><MN>ABCDE")
  seen.ot = roundTrip(data, "ot", "<PK><MN><PK>")
  seen.long = roundTrip(data, "nickname", "<PK>ABCDEFGHIJ")
  return true
end)

T.check(ok == true, "game-closed gold dataset mounts " .. tostring(why))
T.check(seen.font == true, "game-closed gold dataset carries the font charmap")
T.eq(seen.nick9, "<PK>ABCDEFGH", "PK plus eight letters arrives whole")
T.eq(seen.nick7, "<PK><MN>ABCDE", "PK MN plus five letters arrives whole")
T.eq(seen.ot, "<PK><MN><PK>", "PK MN PK trainer name arrives whole")
T.eq(seen.long, "<PK>ABCDEFGHI", "eleven cells are cut to ten")

T.finish()
