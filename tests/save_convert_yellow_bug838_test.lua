-- Yellow save export/import checks for #838: the codec used to run the
-- Red/Blue tables unmodified for Yellow, so (1) event flags went through
-- pokered's bit numbering even though pokeyellow renumbers wEventFlags,
-- and (2) wPikachuHappiness (pokeyellow d46f, absolute 0x271C in SRAM)
-- was never encoded or decoded.  Yellow offsets are verified against the
-- pokeyellow symbol file -- no local pokeyellow checkout exists, so
-- ../pokered can only vouch for the shared R/B layout, which pokeyellow's
-- sram.asm matches byte for byte.  Needs data/generated/, same as
-- tests/save_convert_tests.lua (its natural eventual home).
--
-- Run: luajit tests/save_convert_yellow_bug838_test.lua

package.path = "./?.lua;" .. package.path
_G.love = require("tests.love_stub")

local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")

local checks, failures = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())

local redFlags = loadfile("src/save_convert/data/event_flags.lua")()
local yellowFlags = loadfile("src/save_convert/data/event_flags_yellow.lua")()

-- Red/Blue and Yellow crosswalk sets over the same generated tables; the
-- only differences the codec keys off are the event-flag numbering and the
-- gameVersion tag (SaveConvert.ensureData stamps the same shape, #838).
local shared = {
  pokemon = loadfile("data/generated/pokemon.lua")(),
  moves = loadfile("data/generated/moves.lua")(),
  items = loadfile("data/generated/items.lua")(),
  maps = loadfile("data/generated/maps.lua")(),
}
local redData = {
  pokemon = shared.pokemon, moves = shared.moves, items = shared.items,
  maps = shared.maps, eventFlags = redFlags,
}
local yellowData = {
  pokemon = shared.pokemon, moves = shared.moves, items = shared.items,
  maps = shared.maps, eventFlags = yellowFlags, gameVersion = "yellow",
}

-- home/overworld.asm:2016 (#1691)
local stampMapWindow = loadfile("tests/fixture_data/map_window.lua")()
for mapId in pairs(shared.maps) do stampMapWindow(redData, mapId) end
yellowData.tilesets, yellowData.audio = redData.tilesets, redData.audio
yellowData.encounters = redData.encounters

local OFF = GenSave.OFFSETS

-- ------------------------------------------------------------------
-- the Yellow event-flag table itself: pokeyellow's renumbering, not a
-- copy of the Red table under a new filename
-- ------------------------------------------------------------------

check(yellowFlags.count == 2560,
      "yellow table covers the full 2560-bit wEventFlags array")
check(type(yellowFlags.byName) == "table" and type(yellowFlags.byBit) == "table",
      "yellow table has the byName/byBit shape the codec reads")

-- shared names on DIFFERENT bits: Yellow inserts events ahead of them
check(redFlags.byName.EVENT_GOT_DOME_FOSSIL == 1406
      and yellowFlags.byName.EVENT_GOT_DOME_FOSSIL == 1400,
      "EVENT_GOT_DOME_FOSSIL sits on red bit 1406 vs yellow bit 1400")
check(redFlags.byName.EVENT_BEAT_MT_MOON_3_TRAINER_0 == 1402
      and yellowFlags.byName.EVENT_BEAT_MT_MOON_3_TRAINER_0 == 1403,
      "the Mt Moon 3 trainer block shifts +1 in yellow (Jessie & James insert)")
check(redFlags.byName.EVENT_BEAT_SILPH_CO_11F_TRAINER_0 == 1924
      and yellowFlags.byName.EVENT_BEAT_SILPH_CO_11F_TRAINER_0 == 1925,
      "the Silph Co 11F trainer block shifts +1 in yellow")

-- yellow-only names the port's Yellow scripts set (data/scripts/
-- yellow_jessie_james.lua and the catch-training tutorial): absent from
-- the Red table, so exporting through it silently dropped them
check(yellowFlags.byName.EVENT_BEAT_MT_MOON_3_JESSIE_JAMES == 1402
      and redFlags.byName.EVENT_BEAT_MT_MOON_3_JESSIE_JAMES == nil,
      "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES is yellow bit 1402, unknown to red")
check(yellowFlags.byName.EVENT_COMPLETED_CATCH_TRAINING == 45
      and redFlags.byName.EVENT_COMPLETED_CATCH_TRAINING == nil,
      "EVENT_COMPLETED_CATCH_TRAINING is yellow bit 45, unknown to red")
check(yellowFlags.byName.EVENT_GOT_SQUIRTLE_FROM_OFFICER_JENNY ~= nil
      and redFlags.byName.EVENT_GOT_SQUIRTLE_FROM_OFFICER_JENNY == nil,
      "the Officer Jenny Squirtle event exists only in the yellow table")

-- byBit/byName agree on the renumbered entries
check(yellowFlags.byBit[1400] == "EVENT_GOT_DOME_FOSSIL"
      and yellowFlags.byBit[1402] == "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES",
      "yellow byBit resolves the renumbered bits back to their names")

-- ------------------------------------------------------------------
-- wPikachuHappiness offset: d46f - wMainDataStart d2f6 = 377 past
-- sMainData, absolute 0x271C (per the pokeyellow symbol file)
-- ------------------------------------------------------------------

check(OFF.pikachuHappiness == 10012,
      "OFFSETS.pikachuHappiness is absolute 0x271C (got "
      .. tostring(OFF.pikachuHappiness) .. ")")
check(OFF.pikachuHappiness == OFF.mainData + 377,
      "pikachuHappiness sits 377 bytes past sMainData (wram d46f - d2f6)")
-- the byte is INSIDE the checksummed main-data window, so writing it
-- without recomputing the checksum would brick the save on a cartridge
check(OFF.pikachuHappiness >= OFF.checksumStart
      and OFF.pikachuHappiness < OFF.checksumEnd,
      "pikachuHappiness lies inside the main checksum window")

-- ------------------------------------------------------------------
-- encode/decode gate: yellow data writes and reads the byte, R/B data
-- leaves it alone (in Red/Blue it is current-map scratch)
-- ------------------------------------------------------------------

local save = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
save.pikachuHappiness = 200
-- the follower seeds happiness at 90 (src/world/PikachuFollower.lua), so
-- 200 can only come from this table -- no default could fake the check

local yBytes = GenSave.encode(save, yellowData, nil)
check(#yBytes == GenSave.SAVE_SIZE, "yellow encode produces exactly 32768 bytes")
check(yBytes:byte(OFF.pikachuHappiness + 1) == 200,
      "yellow encode writes pikachuHappiness to 0x271C (got "
      .. yBytes:byte(OFF.pikachuHappiness + 1) .. ")")
check(GenSave.mainChecksumValid(yBytes),
      "yellow encode still emits a valid main-data checksum")
local yDec = GenSave.decode(yBytes, yellowData)
check(yDec.pikachuHappiness == 200,
      "yellow decode reads pikachuHappiness back (got "
      .. tostring(yDec.pikachuHappiness) .. ")")

-- a yellow save whose table never held the field falls back to the
-- follower's seed value instead of exporting friendship 0
local noHap = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
noHap.pikachuHappiness = nil
local seedBytes = GenSave.encode(noHap, yellowData, nil)
check(seedBytes:byte(OFF.pikachuHappiness + 1) == 90,
      "a missing pikachuHappiness exports as the follower seed 90, not 0")

-- R/B output unchanged: same save through the red data set leaves the
-- scratch byte zero-filled and decode never invents the field
local rBytes = GenSave.encode(save, redData, nil)
check(rBytes:byte(OFF.pikachuHappiness + 1) == 0,
      "red/blue encode leaves the 0x271C scratch byte zero-filled")
check(GenSave.decode(rBytes, redData).pikachuHappiness == nil,
      "red/blue decode does not fabricate a pikachuHappiness field")

-- ------------------------------------------------------------------
-- event flags land on pokeyellow bits.  Independent LSB-first flag_array
-- read (pokered home FlagAction convention: byte N/8, bit N%8) so the
-- assertions cannot inherit a codec bit-order bug.
-- ------------------------------------------------------------------

local bit = require("bit")
local function flagBit(bytes, index)
  local b = bytes:byte(OFF.eventFlags + math.floor(index / 8) + 1)
  return bit.band(bit.rshift(b, index % 8), 1) == 1
end

local fsave = SaveData.newGame({ playerName = "ASH", rivalName = "GARY" })
fsave.flags = {
  EVENT_GOT_DOME_FOSSIL = true,
  EVENT_BEAT_MT_MOON_3_JESSIE_JAMES = true,
  EVENT_COMPLETED_CATCH_TRAINING = true,
}

local yfBytes = GenSave.encode(fsave, yellowData, nil)
check(flagBit(yfBytes, 1400) and not flagBit(yfBytes, 1406),
      "yellow export puts EVENT_GOT_DOME_FOSSIL on bit 1400, not red's 1406")
check(flagBit(yfBytes, 1402),
      "yellow export carries EVENT_BEAT_MT_MOON_3_JESSIE_JAMES on bit 1402")
check(flagBit(yfBytes, 45),
      "yellow export carries EVENT_COMPLETED_CATCH_TRAINING on bit 45")
local yfDec = GenSave.decode(yfBytes, yellowData)
check(yfDec.flags.EVENT_GOT_DOME_FOSSIL
      and yfDec.flags.EVENT_BEAT_MT_MOON_3_JESSIE_JAMES
      and yfDec.flags.EVENT_COMPLETED_CATCH_TRAINING,
      "yellow-numbered flags round-trip through decode")

-- the pre-fix failure mode, pinned so it can never quietly return: the
-- red table lands the fossil on the wrong yellow bit and drops the
-- yellow-only names entirely
local rfBytes = GenSave.encode(fsave, redData, nil)
check(flagBit(rfBytes, 1406) and not flagBit(rfBytes, 1400),
      "the red table writes the fossil on 1406, which yellow reads as another event")
check(not flagBit(rfBytes, 1402) and not flagBit(rfBytes, 45),
      "the red table silently drops both yellow-only flags")

-- ------------------------------------------------------------------
-- SaveConvert.ensureData substitutes the yellow flag table (and stamps
-- gameVersion) when the caller names yellow; the versionless set still
-- resolves red numbering, per-version cached separately (#420 pattern)
-- ------------------------------------------------------------------

local yData, yErr = SaveConvert.loadData("yellow")
check(yData ~= nil, "SaveConvert.loadData('yellow') resolves (" .. tostring(yErr) .. ")")
check(yData and yData.gameVersion == "yellow",
      "loadData('yellow') stamps gameVersion for the codec's byte gate")
check(yData and yData.eventFlags.byName.EVENT_GOT_DOME_FOSSIL == 1400
      and yData.eventFlags.byName.EVENT_BEAT_MT_MOON_3_JESSIE_JAMES == 1402,
      "loadData('yellow') serves the pokeyellow flag numbering")
local dData = SaveConvert.loadData()
check(dData and dData.eventFlags.byName.EVENT_GOT_DOME_FOSSIL == 1406
      and dData.gameVersion == nil,
      "versionless loadData still serves the red numbering, untagged")

-- scripts/OaksLab.asm:1020, :231, :381
local cw = GenSave.crosswalks(yellowData)
local starter = SaveData.newGame({ playerName = "ASH", rivalName = "GARY" })
starter.flags = { EVENT_GOT_STARTER = true, EVENT_CHOSE_PIKACHU = true }
starter.rivalStarter = 3

local sBytes = GenSave.encode(starter, yellowData, nil)
check(sBytes:byte(OFF.playerStarter + 1) == cw.pokemonIndex.PIKACHU,
      "yellow encode writes STARTER_PIKACHU into wPlayerStarter (got "
      .. sBytes:byte(OFF.playerStarter + 1) .. ")")
check(sBytes:byte(OFF.rivalStarter + 1) == 3,
      "yellow encode writes RIVAL_STARTER_VAPOREON into wRivalStarter (got "
      .. sBytes:byte(OFF.rivalStarter + 1) .. ")")
local sDec = GenSave.decode(sBytes, yellowData)
check(sDec.rivalStarter == 3,
      "yellow decode reads save.rivalStarter back (got "
      .. tostring(sDec.rivalStarter) .. ")")
check(sDec.flags.EVENT_CHOSE_PIKACHU == true,
      "yellow decode restores EVENT_CHOSE_PIKACHU from wPlayerStarter")

check(GenSave.decode(GenSave.encode(starter, redData, nil), redData).rivalStarter == nil,
      "red/blue decode does not fabricate a rivalStarter index")

print(string.format("save convert yellow #838: %d/%d checks passed",
      checks - failures, checks))
if failures > 0 then os.exit(1) end
