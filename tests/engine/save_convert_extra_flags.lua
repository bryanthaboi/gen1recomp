-- Gen1 save codec (src/save_convert/GenSave.lua) for the save.flags names whose
-- vanilla home is NOT wEventFlags: exporting a slot and importing it back used
-- to drop them, so the Saffron gate guards were thirsty again (#396).  Offsets
-- are re-derived here byte by byte from ram/wram.asm rather than read out of
-- GenSave.OFFSETS, and the bit numbers come from constants/ram_constants.asm
-- (BIT_GOT_OLD_ROD 3, BIT_GAVE_SAFFRON_GUARDS_DRINK 6, BIT_GOT_LAPRAS 0,
-- BIT_STARTED_ELITE_4 1).  The trade bits are wWhichTrade, which
-- engine/events/in_game_trades.asm uses to index wCompletedInGameTradeFlags,
-- so they are checked against the 1-based rows the port's scripts pass.
--   luajit tests/engine/save_convert_extra_flags.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local bit = require("bit")
local GenSave = require("src.save_convert.GenSave")
local SaveData = require("src.core.SaveData")

-- the codec crosswalks need the real dataset; CI has no ROM
local loadPokemon = loadfile("data/generated/pokemon.lua")
if not loadPokemon then
  print("save_convert_extra_flags skipped (needs data/generated/ for the Gen1 save codec)")
  os.exit(0)
end

GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())
local events = loadfile("src/save_convert/data/event_flags.lua")()
local data = {
  pokemon = loadPokemon(),
  moves = loadfile("data/generated/moves.lua")(),
  items = loadfile("data/generated/items.lua")(),
  maps = loadfile("data/generated/maps.lua")(),
  eventFlags = events,
}
loadfile("tests/fixture_data/map_window.lua")()(data, "REDS_HOUSE_2F")

-- ------------------------------------------------------------------
-- offsets, walked forward from wTownVisitedFlag over ram/wram.asm's own
-- declaration run: 2 wTownVisitedFlag, 2 wSafariSteps, wFossilItem,
-- wFossilMon, ds 2, wEnemyMonOrTrainerClass, wPlayerJumpingYScreenCoordsIndex,
-- wRivalStarter, ds 1, wPlayerStarter, wBoulderSpriteIndex, wLastBlackoutMap,
-- wDestinationMap, wUnusedPlayerDataByte, wTileInFrontOfBoulder...,
-- wDungeonWarpDestinationMap, wWhichDungeonWarp, wUnusedCardKeyGateID, ds 8
-- ------------------------------------------------------------------

local OFF = GenSave.OFFSETS
local TOWN_VISITED = OFF.townVisited
local WRAM = {
  statusFlags1 = TOWN_VISITED + 29,
  statusFlags4 = TOWN_VISITED + 35,   -- +30 ds 1, wBeatGymFlags, ds 1, 2/3
  elite4Flags = TOWN_VISITED + 41,    -- +36 ds 1, 5, ds 1, 6, 7
  tradeFlags = TOWN_VISITED + 44,     -- +42 ds 1, wMovementFlags
  eventFlags = TOWN_VISITED + 60,     -- the run's own end, pinned already
}

eq(WRAM.eventFlags, OFF.eventFlags,
   "the wram walk lands on wEventFlags where the codec already pins it")
eq(OFF.statusFlags1, WRAM.statusFlags1, "wStatusFlags1 is wTownVisitedFlag + 29")
eq(OFF.statusFlags4, WRAM.statusFlags4, "wStatusFlags4 is wTownVisitedFlag + 35")
eq(OFF.elite4Flags, WRAM.elite4Flags, "wElite4Flags is wTownVisitedFlag + 41")
eq(OFF.tradeFlags, WRAM.tradeFlags, "wCompletedInGameTradeFlags is wTownVisitedFlag + 44")

-- independent flag_array read (byte = index / 8, bit = index % 8), so nothing
-- below trusts the writer it is checking
local function flagGet(bytes, base, index)
  local byte = bytes:byte(base + math.floor(index / 8) + 1)
  return bit.band(bit.rshift(byte, index % 8), 1) == 1
end

-- ------------------------------------------------------------------
-- the names under test, and the proof they cannot ride wEventFlags
-- ------------------------------------------------------------------

local EXTRA = {
  { "EVENT_GOT_OLD_ROD", "statusFlags1", 3 },
  { "EVENT_GOT_GOOD_ROD", "statusFlags1", 4 },
  { "EVENT_GOT_SUPER_ROD", "statusFlags1", 5 },
  { "EVENT_GAVE_GUARDS_DRINK", "statusFlags1", 6 },
  { "EVENT_GOT_LAPRAS", "statusFlags4", 0 },
  { "EVENT_STARTED_ELITE_4", "elite4Flags", 1 },
}

local named = 0
for _ in pairs(events.byName) do named = named + 1 end
eq(named, 507, "event_flags.lua carries every EVENT_* constant and no more")
for _, row in ipairs(EXTRA) do
  eq(events.byName[row[1]], nil, row[1] .. " has no wEventFlags bit to ride")
end

-- ------------------------------------------------------------------
-- trade rows as the port's scripts actually pass them: `{ "trade", N, FLAG }`
-- with N the 1-based data/events/trades.asm row, so the bit is N - 1
-- ------------------------------------------------------------------

local TRADE_ROWS = {}
local scripts = io.popen("ls data/scripts/*.lua")
for path in scripts:lines() do
  local f = io.open(path, "r")
  local src = f:read("*a")
  f:close()
  for index, flag in src:gmatch('"trade",%s*(%d+),%s*"(EVENT_[A-Z0-9_]+)"') do
    TRADE_ROWS[#TRADE_ROWS + 1] = { flag = flag, index = tonumber(index) }
  end
end
scripts:close()
check(#TRADE_ROWS == 8, "all eight scripted trade rows are found")
-- trade slot 6 is scripted twice: Red's youngster and Yellow's gate cook
-- share the index and its done flag, one row per version (#651)
local slot6 = 0
for _, row in ipairs(TRADE_ROWS) do
  if row.index == 6 then slot6 = slot6 + 1 end
end
eq(slot6, 2, "trade slot 6 has a row for each version")

-- ------------------------------------------------------------------
-- round trips
-- ------------------------------------------------------------------

local function seedSave()
  local save = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
  save.party = { {
    species = "SQUIRTLE", level = 6, exp = 200,
    dvs = { hp = 1, attack = 2, defense = 3, speed = 4, special = 5 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 22, attack = 12, defense = 13, speed = 11, special = 12 },
    hp = 22,
    moves = { { id = "TACKLE", pp = 35, ppUps = 0 } },
    nickname = "SQ", ot = "RED", otId = save.player.id, catchRate = 45,
  } }
  return save
end

local set = seedSave()
for _, row in ipairs(EXTRA) do set.flags[row[1]] = true end
for _, row in ipairs(TRADE_ROWS) do set.flags[row.flag] = true end
set.flags.EVENT_RECEIVED_BIKE_VOUCHER = true

local setBytes = GenSave.encode(set, data, nil)
eq(#setBytes, GenSave.SAVE_SIZE, "the export is a 32768-byte save")

for _, row in ipairs(EXTRA) do
  check(flagGet(setBytes, WRAM[row[2]], row[3]),
        row[1] .. " reaches the .sav as its " .. row[2] .. " bit " .. row[3])
end
for _, row in ipairs(TRADE_ROWS) do
  check(flagGet(setBytes, WRAM.tradeFlags, row.index - 1),
        row.flag .. " reaches wCompletedInGameTradeFlags bit " .. (row.index - 1))
end
-- the port spells bit 337 EVENT_RECEIVED_BIKE_VOUCHER; vanilla calls it
-- EVENT_GOT_BIKE_VOUCHER (constants/event_constants.asm)
eq(events.byName.EVENT_GOT_BIKE_VOUCHER, 337, "the bike voucher is event bit 337")
check(flagGet(setBytes, WRAM.eventFlags, 337),
      "EVENT_RECEIVED_BIKE_VOUCHER reaches the real bike voucher event bit")

-- no spill into the neighbouring bits of a shared byte
eq(bit.band(setBytes:byte(WRAM.statusFlags1 + 1), 0x87), 0,
   "wStatusFlags1 keeps its other bits (0-2, 7) clear")
eq(bit.band(setBytes:byte(WRAM.tradeFlags + 1), 0x04), 0,
   "the unused CHIKUCHIKU trade bit stays clear")

local back = GenSave.decode(setBytes, data)
eq(#(back.warnings or {}), 0, "the export decodes with no warnings")
local reflags = back.flags
for _, row in ipairs(EXTRA) do
  eq(reflags[row[1]], true, row[1] .. " survives export -> import")
end
for _, row in ipairs(TRADE_ROWS) do
  eq(reflags[row.flag], true, row.flag .. " survives export -> import")
end
eq(reflags.EVENT_RECEIVED_BIKE_VOUCHER, true,
   "EVENT_RECEIVED_BIKE_VOUCHER comes back under the port's own spelling")
eq(reflags.EVENT_GOT_BIKE_VOUCHER, true, "and under the vanilla spelling too")

-- ------------------------------------------------------------------
-- the port's save is the only authority for these bits, so a save that does
-- NOT hold one must clear it out of the template rather than inherit it
-- ------------------------------------------------------------------

local clear = seedSave()
local clearBytes = GenSave.encode(clear, data, setBytes)
for _, row in ipairs(EXTRA) do
  check(not flagGet(clearBytes, WRAM[row[2]], row[3]),
        row[1] .. " is cleared, not inherited from the template")
end
for _, row in ipairs(TRADE_ROWS) do
  check(not flagGet(clearBytes, WRAM.tradeFlags, row.index - 1),
        row.flag .. " is cleared, not inherited from the template")
end
local reclear = GenSave.decode(clearBytes, data)
eq(reclear.flags.EVENT_GAVE_GUARDS_DRINK, nil,
   "a save that never watered the guards imports back thirsty")

-- ------------------------------------------------------------------
-- cross-file pin: the four Saffron gates read this exact spelling
-- (data/scripts/story2.lua, pokered scripts/Route5Gate.asm and its twins)
-- ------------------------------------------------------------------

local sf = io.open("data/scripts/story2.lua", "r")
local story2 = sf:read("*a")
sf:close()
check(story2:find("flags.EVENT_GAVE_GUARDS_DRINK", 1, true) ~= nil,
      "the gate scripts still spell the drink flag EVENT_GAVE_GUARDS_DRINK")

-- ram/wram.asm:2057-2078; engine/debug/debug_party.asm:119

eq(OFF.rivalStarter, TOWN_VISITED + 10, "wRivalStarter is wTownVisitedFlag + 10")
eq(OFF.playerStarter, TOWN_VISITED + 12, "wPlayerStarter is wTownVisitedFlag + 12")
check(OFF.playerStarter >= OFF.checksumStart and OFF.playerStarter < OFF.checksumEnd,
      "both starter bytes lie inside the main checksum window")

local cw = GenSave.crosswalks(data)
eq(cw.pokemonIndex.CHARMANDER, 176, "STARTER1 CHARMANDER is internal index 176")
eq(cw.pokemonIndex.SQUIRTLE, 177, "STARTER2 SQUIRTLE is internal index 177")
eq(cw.pokemonIndex.BULBASAUR, 153, "STARTER3 BULBASAUR is internal index 153")

for _, species in ipairs({ "CHARMANDER", "SQUIRTLE", "BULBASAUR" }) do
  eq(events.byName["EVENT_CHOSE_" .. species], nil,
     "EVENT_CHOSE_" .. species .. " has no wEventFlags bit to ride")
end

-- scripts/OaksLab.asm:797-825; scripts/PokemonTower2F.asm:155-168
local COUNTERPICK = {
  CHARMANDER = "SQUIRTLE", SQUIRTLE = "BULBASAUR", BULBASAUR = "CHARMANDER",
}
for player, rival in pairs(COUNTERPICK) do
  local chose = seedSave()
  chose.flags.EVENT_GOT_STARTER = true
  chose.flags["EVENT_CHOSE_" .. player] = true
  local bytes = GenSave.encode(chose, data, nil)
  eq(bytes:byte(OFF.playerStarter + 1), cw.pokemonIndex[player],
     "EVENT_CHOSE_" .. player .. " reaches wPlayerStarter as " .. player)
  eq(bytes:byte(OFF.rivalStarter + 1), cw.pokemonIndex[rival],
     "and hands the rival " .. rival .. " in wRivalStarter")
  check(GenSave.mainChecksumValid(bytes),
        "the " .. player .. " export still checksums")
  local back = GenSave.decode(bytes, data)
  eq(back.flags["EVENT_CHOSE_" .. player], true,
     "EVENT_CHOSE_" .. player .. " survives export -> import")
  eq(back.flags["EVENT_CHOSE_" .. rival], nil,
     "and no second starter flag comes back with it")
end

local function patch(bytes, off, value)
  local out = bytes:sub(1, off) .. string.char(value) .. bytes:sub(off + 2)
  local sum = 0
  for i = OFF.checksumStart + 1, OFF.checksumEnd do sum = (sum + out:byte(i)) % 256 end
  return out:sub(1, OFF.mainChecksum) .. string.char(255 - sum) .. out:sub(OFF.mainChecksum + 2)
end

local plain = seedSave()
plain.flags.EVENT_GOT_STARTER = true
local cart = GenSave.encode(plain, data, nil)
cart = patch(cart, OFF.playerStarter, cw.pokemonIndex.BULBASAUR)
cart = patch(cart, OFF.rivalStarter, cw.pokemonIndex.CHARMANDER)
local cartSave = GenSave.decode(cart, data)
eq(cartSave.flags.EVENT_CHOSE_BULBASAUR, true,
   "a cart save that chose BULBASAUR imports with the BULBASAUR flag set")

-- scripts/OaksLab.asm:322-323
local rivalOnly = GenSave.decode(patch(cart, OFF.playerStarter, 0), data)
eq(rivalOnly.flags.EVENT_CHOSE_BULBASAUR, true,
   "a blank wPlayerStarter falls back to the wRivalStarter counterpick")

local neither = GenSave.decode(
  patch(patch(cart, OFF.playerStarter, 0), OFF.rivalStarter, 0), data)
eq(neither.flags.EVENT_CHOSE_BULBASAUR, nil,
   "an empty starter pair invents no choice")
local warned = false
for _, w in ipairs(neither.warnings or {}) do
  if w:find("starter", 1, true) then warned = true end
end
check(warned, "and the import warns that the rival parties will default")

local preLab = seedSave()
preLab.flags.EVENT_GOT_STARTER = nil
eq(GenSave.encode(preLab, data, cart):byte(OFF.playerStarter + 1),
   cw.pokemonIndex.BULBASAUR,
   "a save with no EVENT_CHOSE_* leaves the template's starter bytes alone")

-- scripts/OaksLab.asm:335
local preBytes = patch(GenSave.encode(preLab, data, nil),
                       OFF.playerStarter, cw.pokemonIndex.BULBASAUR)
eq(GenSave.decode(preBytes, data).flags.EVENT_CHOSE_BULBASAUR, nil,
   "a pre-lab import sets no starter flag")

T.finish("save_convert_extra_flags")
