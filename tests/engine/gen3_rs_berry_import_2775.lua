package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local eq, check = T.eq, T.check
local B = require("tests.fixtures.save.bytes")
local Mon = require("tests.fixtures.save.gen3_build")
local Gen3 = require("src.save_convert.Gen3Save")
local Rtc = require("src.core.game3.rtc")

-- pokeruby/src/save.c:110
local chunks = { [0] = 0x890, 0xF80, 0xF80, 0xF80, 0xC40, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0 }

local function putTime(b, at, t)
  B.le(b, at, t.days % 65536, 2)
  B.put(b, at + 2, t.hours % 256, t.minutes % 256, t.seconds % 256)
end

local function flash(offset, last, trees)
  local sb2, sb1, storage = B.new(0x890), B.new(0x3AC0), B.new(0x83D0)
  for i, v in ipairs(Mon.text("BRENDAN", 8)) do sb2[i - 1] = v end
  B.le(sb2, 0xA, 0x1234, 2); B.le(sb2, 0xC, 0x5678, 2)
  -- pokeruby/include/global.h:860
  putTime(sb2, 0x98, offset)
  putTime(sb2, 0xA0, last)
  B.put(sb1, 4, 25, 40, 255, 0); B.le(sb1, 8, 2, 2); B.le(sb1, 10, 2, 2)
  -- pokeruby/include/global.h:704
  for id, t in pairs(trees) do
    local at = 0x1608 + id * 8
    B.put(sb1, at, t[1], t[2])
    B.le(sb1, at + 2, t[3], 2)
    B.put(sb1, at + 4, t[4], t[5])
  end
  for i = 0, 24 do sb1[0x2738 + i * 36] = 255 end
  local out = B.new(0x20000, 255)
  local parts = { [0] = { sb2, 0 } }
  local o = 0
  for id = 1, 4 do parts[id] = { sb1, o }; o = o + chunks[id] end
  o = 0
  for id = 5, 13 do parts[id] = { storage, o }; o = o + chunks[id] end
  for id = 0, 13 do
    local at = (14 + id) * 0x1000
    B.fill(out, at, 0xF80, 0)
    local src, start = parts[id][1], parts[id][2]
    for i = 0, chunks[id] - 1 do out[at + i] = src[start + i] end
    local sum = 0
    for i = 0, chunks[id] - 4, 4 do sum = (sum + B.getLE(out, at + i, 4)) % 4294967296 end
    B.le(out, at + 0xFF4, id, 2); B.le(out, at + 0xFF6, (sum + math.floor(sum / 65536)) % 65536, 2)
    B.le(out, at + 0xFF8, 0x08012025, 4); B.le(out, at + 0xFFC, 3, 4)
  end
  return B.pack(out)
end

Rtc.reset()
Rtc.setFixed("2026-10-01T09:30:00")
local clock = {}
local offset = Rtc.calcLocalTimeOffset(clock, 0, 10, 0, 0)
Rtc.setFixed("2026-10-07T20:00:00")
local last = Rtc.calcLocalTime(clock)

local trees = {
  [70] = { 7, 1, 180, 0, 0x10 },
  [71] = { 2, 2 + 128, 40, 0, 3 + 0x20 + 0x40 },
  [127] = { 43, 5, 2, 6, 0 },
}

for _, game in ipairs({ "ruby", "sapphire" }) do
  Rtc.setFixed("2026-10-08T08:00:00")
  local codec = Gen3.forVersion(game)
  local save, why = codec.importPort(flash(offset, last, trees), game)
  check(save ~= nil, game .. " imports: " .. tostring(why))
  if save then
    local bt = save.berryTrees or {}
    eq(bt[70] and bt[70].berry, 7, game .. " tree 70 berry")
    eq(bt[70] and bt[70].stage, 1, game .. " tree 70 stage")
    eq(bt[70] and bt[70].minutesUntilNextStage, 180, game .. " tree 70 minutes")
    check(bt[70] and bt[70].watered1 and not bt[70].stopGrowth, game .. " tree 70 watered, growing")
    eq(bt[71] and bt[71].stage, 2, game .. " tree 71 stage")
    check(bt[71] and bt[71].stopGrowth, game .. " tree 71 growth sparkle bit")
    eq(bt[71] and bt[71].regrowthCount, 3, game .. " tree 71 regrowth count")
    check(bt[71] and bt[71].watered2 and bt[71].watered3 and not bt[71].watered1, game .. " tree 71 water bits")
    eq(bt[127] and bt[127].berryYield, 6, game .. " last tree yield")
    eq(bt[0], nil, game .. " empty tree stays empty")
    eq(save.lastBerryTreeUpdate.days, last.days, game .. " lastBerryTreeUpdate day")
    eq(save.localTimeOffset.days, offset.days, game .. " localTimeOffset day")
    eq(save.rtcSkew, 0, game .. " host-clock save keeps the real clock")
    local now = Rtc.calcLocalTime(save)
    eq(Rtc.timeMinutes(Rtc.calcTimeDifference(save.lastBerryTreeUpdate, now)), 12 * 60,
      game .. " 12 hours off between cart save and import reach BerryTreeTimeUpdate")
  end
end

Rtc.reset()
T.finish("gen3_rs_berry_import_2775")
