#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
local GV = require("src.core.GameVersion")
local V = require("src.import.gba.versions")
local LG = "574fa542ffebb14be69902d1d36f1ec0a4afd71e"
local LG11 = "7862c67bdecbe21d1d69ce082ce34327e1c6ed5e"
local FR = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"
assert(GV.forSha1(LG) == "leafgreen")
assert(GV.forSha1(LG11) == "leafgreen" and GV.revisionLabel("leafgreen", LG11) == "1.1")
assert(GV.engine("leafgreen") == "game3" and GV.generation("leafgreen") == 3)
assert(GV.info("leafgreen").cachePrefix ~= GV.info("firered").cachePrefix)
assert(GV.info("leafgreen").saveSuffix ~= GV.info("firered").saveSuffix)
local audio, song = V.AUDIO, V.AUDIO.song_table
for _ = 1, 3 do
  V.select(LG)
  assert(V.lookup(LG).game == "leafgreen")
  assert(V.AUDIO == audio and V.AUDIO.song_table == 0x4A2BA8)
  assert(V.INTRO.mon_front_pic_table == 0x235088)
  assert(V.address(0x2350AC) == 0x235088)
  V.select(FR)
  assert(V.AUDIO == audio and V.AUDIO.song_table == song)
  assert(V.INTRO.mon_front_pic_table == 0x2350AC)
end
local root = os.getenv("POKEFIRERED") or "../pokefirered"
local function openRom(file, hash)
  local f = io.open(root .. "/" .. file, "rb")
  if not f then return nil end
  local data = f:read("*a"); f:close()
  return assert(require("src.import.gba.rom").open({
    info = function() return { size = #data, md5 = hash } end,
    read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
  }, GV.forSha1(hash)))
end
-- Independent expected symbols and version differences from pret's matching builds.
for _, case in ipairs({ { "pokefirered.gba", FR, 180, 20, { 29, 0x4c970b89, 30, 55 } },
    { "pokeleafgreen.gba", LG, 70, 160, { 32, 0x4c970b9e, 33, 80 } },
    { "pokeleafgreen_rev1.gba", LG11, 70, 160, { 32, 0x4c970b9e, 33, 80 } } }) do
  local rom = openRom(case[1], case[2])
  if rom then
    assert(rom:u16(V.DEOXYS_BASE_STATS + 2) == case[3])
    assert(rom:u16(V.DEOXYS_BASE_STATS + 4) == case[4])
    local trades = require("src.import.gba.ingame_trades_extract").extract(rom).trades
    assert(trades[2].species == case[5][1] and trades[2].personality == case[5][2])
    assert(trades[4].species == case[5][3] and trades[5].requestedSpecies == case[5][4])
    local ptr = rom:u32(V.INTRO.mon_front_pic_table + 8)
    local off = assert(rom:ptrOffset(ptr))
    local tiles = require("src.import.gba.lz77").decompress(function(i) return rom:get(i) end, off)
    assert(#tiles >= 2048, "Bulbasaur front sprite decodes")
    assert(rom:u32(V.G_MAP_GROUPS + 12) >= 0x08000000, "map group pointer")
    print("PASS " .. case[1] .. " pointers and edition data")
  else
    print("SKIP " .. case[1] .. " (build with pret to check ROM data)")
  end
end
do
  local function bytes(name)
    local f = io.open(root .. "/" .. name, "rb")
    if not f then return nil end
    local data = f:read("*a"); f:close(); return data
  end
  local base = bytes("pokeleafgreen.gba")
  local revision = bytes("pokeleafgreen_rev1.gba")
  if base and revision then
    local normalized = require("src.import.gba.revision_view").apply(revision, LG11)
    local differences = 0
    for i = 0x1E0001, #base do
      if base:byte(i) ~= normalized:byte(i) then differences = differences + 1 end
    end
    assert(differences <= 300, "LeafGreen 1.1 data relocation mismatch: " .. differences)
    print("PASS LeafGreen 1.1 relocated data region (" .. differences .. " differing bytes)")
  else
    print("SKIP LeafGreen revision comparison (local pret builds unavailable)")
  end
end
GV.set("leafgreen")
local Party = require("src.core.game3.party")
assert(Party.metGame() == 5)
GV.set("firered")
assert(Party.metGame() == 4)
V.select(FR)
print("PASS LeafGreen registration edition switching ROM data and trades")
