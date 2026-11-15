-- ../pokecrystal/constants/text_constants.asm:2-3
-- ../pokecrystal/data/text/name_input_chars.asm:7
package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Protocol = require("src.link.Protocol")
local Wire = require("src.link.Wire")
local Json = require("src.link.Json")
local Handshake = require("src.link.Handshake")

local MALE = "\226\153\130"
local TIMES = "\195\151"
local ELLIPSIS = "\226\128\166"

local function validUtf8(s)
  if type(s) ~= "string" then return false end
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local len = b < 0x80 and 1 or (b >= 0xC2 and b <= 0xDF) and 2
      or (b >= 0xE0 and b <= 0xEF) and 3 or (b >= 0xF0 and b <= 0xF4) and 4 or nil
    if not len or i + len - 1 > n then return false end
    for j = i + 1, i + len - 1 do
      local c = s:byte(j)
      if c < 0x80 or c > 0xBF then return false end
    end
    i = i + len
  end
  return true
end

local DATA = {
  items = {},
  moves = { TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 } },
  font = {
    charmap = {
      { seq = "<PK>", code = 0xE1 },
      { seq = "<MN>", code = 0xE2 },
      { seq = "<DOT>", code = 0xF2 },
      { seq = MALE, code = 0xEF },
      { seq = TIMES, code = 0xF1 },
      { seq = "A", code = 0x80 },
    },
  },
  pokemon = {
    growthRates = {
      GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
        linear = 0, constant = 0 },
    },
    HAUNTER = { id = "HAUNTER", name = "HAUNTER", index = 93,
      growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
      types = { "GHOST", "POISON" },
      baseStats = { hp = 45, attack = 50, defense = 45, speed = 95,
        specialAttack = 115, specialDefense = 55 },
      levelMoves = { { level = 1, move = "TACKLE" } } },
  },
}

local function newMon(ot, nickname)
  return {
    species = "HAUNTER", name = "HAUNTER", level = 30, experience = 27000,
    hp = 60, maxHp = 60,
    dvs = { attack = 10, defense = 11, speed = 12, special = 13 },
    statExp = {},
    moves = { { id = "TACKLE", pp = 35, maxPp = 35 } },
    happiness = 70, pokerus = 0, ot = ot, otId = 1234, nickname = nickname,
  }
end

local function wire(packed)
  local line = Json.encode({ type = "party", mons = { packed } })
  local msg = Wire.sanitize(Json.decode(line))
  return msg and msg.mons and msg.mons[1]
end

local function overTheWire(mon)
  local packed = wire(Protocol.packMon2(mon))
  T.check(packed ~= nil, "the offer survives the wire sanitizer")
  return Protocol.unpackMon2(DATA, packed), packed
end

for _, c in ipairs({
  { "seven times signs", TIMES:rep(7) },
  { "A and six times signs", "A" .. TIMES:rep(6) },
  { "seven male signs", MALE:rep(7) },
  { "three MN tokens", ("<MN>"):rep(3) },
  { "PK MN PK", "<PK><MN><PK>" },
}) do
  local got = overTheWire(newMon(c[2], "HAUNTER"))
  T.eq(got.ot, c[2], "gen 2 OT arrives whole: " .. c[1])
  T.eq(got.otName, c[2], "gen 2 otName matches: " .. c[1])
  T.check(validUtf8(got.ot), "gen 2 OT is valid UTF-8: " .. c[1])
end

do
  local nick = "A" .. ("<DOT>"):rep(9)
  local got = overTheWire(newMon("GOLD", nick))
  T.eq(got.nickname, nick, "a ten-glyph 46-byte nickname arrives whole")
  local tokens = ("<PK><MN>"):rep(5)
  got = overTheWire(newMon("GOLD", tokens))
  T.eq(got.nickname, tokens, "ten PK/MN glyphs arrive whole")
  got = overTheWire(newMon("GOLD", tokens .. "A"))
  T.eq(got.nickname, tokens, "an eleventh glyph is clipped by glyph, not by byte")
  got = overTheWire(newMon(MALE:rep(11), "HAUNTER"))
  T.eq(got.ot, MALE:rep(10), "an over-long OT is clipped to ten glyphs")
end

do
  local broken = MALE:rep(3) .. "\226"
  local packed = Protocol.packMon2(newMon(broken, MALE .. "\153"))
  T.eq(packed.ot, MALE:rep(3), "packMon2 drops a dangling lead byte from the OT")
  T.eq(packed.nickname, MALE, "packMon2 drops a stray continuation byte from the nickname")
  local g1 = Protocol.packMon({ moves = {}, ot = broken, nickname = "A\226\153" })
  T.eq(g1.ot, MALE:rep(3), "packMon drops a dangling lead byte from the OT")
  T.eq(g1.nickname, "A", "packMon drops a partial sequence from the nickname")
  T.eq(Protocol.packMon({ moves = {}, ot = "RED" }).ot, "RED", "a clean OT packs unchanged")
  local hostile = Protocol.packMon2(newMon("GOLD", "HAUNTER"))
  hostile.ot = broken
  local got = Protocol.unpackMon2(DATA, wire(hostile))
  T.check(validUtf8(got.ot), "a received dangling byte never reaches the mon")
end

do
  for _, n in ipairs({ 1, 15, 16, 17, 20, 64 }) do
    local s = Wire.str(MALE:rep(30), nil, n)
    T.check(validUtf8(s), ("Wire.str at %d bytes ends on a character boundary"):format(n))
  end
  T.eq(Wire.str(MALE:rep(7), nil, 16), MALE:rep(5), "Wire.str backs off to the last whole character")
  T.eq(Wire.str("ABCDEFGHIJ", nil, 4), "ABCD", "Wire.str still cuts ASCII by byte")
  local m3 = Wire.mon3({ nickname = MALE:rep(11), otName = ELLIPSIS:rep(11) })
  T.check(validUtf8(m3.nickname) and validUtf8(m3.otName), "mon3 names end on a character boundary")
end

do
  local m = Wire.member({ id = "0123abcd", name = MALE:rep(6),
    avatar = { name = MALE:rep(7) } })
  T.eq(m.name, MALE:rep(6), "a six-character display name arrives whole")
  T.eq(m.avatar.name, MALE:rep(7), "a seven-character male-sign avatar name arrives whole")
  local a = Wire.avatar({ name = ELLIPSIS:rep(7) })
  T.eq(a.name, ELLIPSIS:rep(7), "a seven-character ellipsis avatar name arrives whole")
  a = Wire.avatar({ name = MALE:rep(12) })
  T.eq(a.name, MALE:rep(10), "an avatar name is capped at ten characters")
  T.eq(Wire.member({ id = "0123abcd", name = ("A"):rep(20) }).name, ("A"):rep(16),
    "an ASCII display name keeps its sixteen-character cap")
end

do
  local name = MALE:rep(7)
  local hello = Wire.sanitize(Json.decode(Json.encode({ type = "hello", name = name,
    engineVersion = "1.0.1", ruleset = "x", protocol = 2 })))
  local mine = { engineVersion = "1.0.0", ruleset = "gen1_faithful", protocol = 2 }
  for _, verdict in ipairs({ "engine_skew", "ruleset_skew" }) do
    local found = false
    for _, line in ipairs(Handshake.describe(mine, hello, verdict, "battle")) do
      T.check(validUtf8(line), verdict .. " line is valid UTF-8: " .. line)
      if line:find(name, 1, true) then found = true end
    end
    T.check(found, verdict .. " names the whole seven-character peer")
  end
  local long = Handshake.describe(mine, { name = MALE:rep(9), engineVersion = "1.0.1",
    protocol = 2 }, "engine_skew", "battle")
  local hit
  for _, line in ipairs(long) do
    if line:find(MALE, 1, true) then hit = line end
  end
  T.eq(hit, " " .. MALE:rep(7) .. ": v1.0.1", "an over-long peer name is clipped to seven characters")
end

T.finish("link name bytes")
