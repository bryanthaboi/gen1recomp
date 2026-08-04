-- Gen1 save transformer tests (src/save_convert/GenSave.lua): a
-- round-trip of a fresh SaveData.newGame() save (no real save data
-- checked in as a fixture), plus targeted checks for the checksum
-- routine, the species/move/item/map crosswalks, and name encoding.
--
-- Run: luajit tests/save_convert_tests.lua

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
local data = {
  pokemon = loadfile("data/generated/pokemon.lua")(),
  moves = loadfile("data/generated/moves.lua")(),
  items = loadfile("data/generated/items.lua")(),
  maps = loadfile("data/generated/maps.lua")(),
  eventFlags = loadfile("src/save_convert/data/event_flags.lua")(),
}

-- Independent re-implementation of CalcCheckSum (complement of the additive
-- byte sum) so the export scenarios below can verify all three SRAM checksums
-- straight off the emitted bytes, without trusting GenSave's own writer.
local bit = require("bit")
local OFF = GenSave.OFFSETS
local function rawChecksum(bytes, from, to)
  local sum = 0
  for i = from, to - 1 do sum = bit.band(sum + bytes:byte(i + 1), 0xFF) end
  return bit.band(bit.bnot(sum), 0xFF)
end
local function checksumValid(bytes, from, to, storeOff)
  return rawChecksum(bytes, from, to) == bytes:byte(storeOff + 1)
end
-- A box bank (2 or 3) holds 6 box regions, one one-byte checksum each, plus a
-- bank aggregate computed over the ENTIRE six-box region (pokered
-- engine/menus/save.asm: CalcCheckSum over all 6 x 1122 bytes), independently
-- re-derived here so this test cannot inherit an encoder bug.
local function boxBankChecksumValid(bytes, bankBase, aggOff, indivOff)
  for b = 0, 5 do
    local base = bankBase + b * GenSave.BOX_REGION_SIZE
    local c = rawChecksum(bytes, base, base + GenSave.BOX_REGION_SIZE)
    if c ~= bytes:byte(indivOff + b + 1) then return false end
  end
  local agg = rawChecksum(bytes, bankBase, bankBase + 6 * GenSave.BOX_REGION_SIZE)
  return agg == bytes:byte(aggOff + 1)
end

-- ------------------------------------------------------------------
-- crosswalks: one species/move/item/map roundtrip each
-- ------------------------------------------------------------------

local cw = GenSave.crosswalks(data)
check(cw.pokemonIndex.MEW == 21, "MEW's internal ROM index is 21 (the classic MissingNo fact)")
check(cw.pokemonByIndex[21] == "MEW", "index 21 resolves back to MEW")
check(cw.pokemonDex.MEW == 151, "MEW's national dex number is 151 (BaseStats[151])")
check(cw.pokemonByDex[151] == "MEW", "dex 151 resolves back to MEW")
check(cw.pokemonDex.BULBASAUR == 1, "BULBASAUR is dex #1")

check(cw.movesByIndex[cw.movesIndex.THUNDERBOLT] == "THUNDERBOLT",
      "a move id round-trips through its index")
check(cw.itemsByIndex[cw.itemsIndex.POKE_BALL] == "POKE_BALL",
      "an item id round-trips through its index")
check(cw.itemsByIndex[cw.itemsIndex.TM_THUNDER_WAVE] == "TM_THUNDER_WAVE",
      "a TM item (no `index` field, only machine.number) round-trips via its derived item id")
check(cw.mapsIndex.PALLET_TOWN == 0, "PALLET_TOWN is map index 0")
check(cw.mapsByIndex[0] == "PALLET_TOWN", "map index 0 resolves back to PALLET_TOWN")

-- ------------------------------------------------------------------
-- a fresh new-game save round-trips through encode -> decode
-- ------------------------------------------------------------------

local fresh = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
-- newGame's party/boxes are empty and its map is an interior with no
-- gen1-save equivalent tileset concerns -- exactly the baseline this
-- codec needs to handle cleanly with no real playthrough data at all.
local bytes = GenSave.encode(fresh, data, nil)
check(#bytes == GenSave.SAVE_SIZE, "encode() produces exactly 32768 bytes")

local decoded = GenSave.decode(bytes, data)
check(#decoded.warnings == 0, "a freshly-encoded save passes its own checksum")
check(decoded.player.name == "RED", "player name round-trips")
check(decoded.player.rival == "BLUE", "rival name round-trips")
check(decoded.player.map == fresh.player.map, "spawn map round-trips (" ..
      tostring(decoded.player.map) .. " vs " .. tostring(fresh.player.map) .. ")")
check(decoded.player.x == fresh.player.x and decoded.player.y == fresh.player.y,
      "spawn position round-trips")
check(decoded.money == fresh.money, "money round-trips")
check(#decoded.party == 0, "an empty party stays empty")

-- ------------------------------------------------------------------
-- a populated save: party, boxes, badges, bag, pokedex, flags
-- ------------------------------------------------------------------

local save = SaveData.newGame({ playerName = "ASH", rivalName = "GARY" })
save.player.id = 12345
save.money = 3000
save.coins = 50
save.inventory = { POKE_BALL = 5, BOULDERBADGE = 1, ANTIDOTE = 1 }
save.bagOrder = { "POKE_BALL", "ANTIDOTE" }
save.pcItems = { REVIVE = 2 }
save.pokedex = { seen = { MEW = true, PIKACHU = true }, owned = { PIKACHU = true } }
save.flags = { EVENT_GOT_STARTER = true, EVENT_GOT_POKEDEX = true }
-- the FLY destination set (pokered's wTownVisitedFlag), keyed by map id
save.visited = { PALLET_TOWN = true, CELADON_CITY = true }
save.boxes = {}
save.party = {
  {
    species = "MEW", level = 100, exp = 1059860,
    dvs = { hp = 13, attack = 15, defense = 11, speed = 12, special = 15 },
    statExp = { hp = 65535, attack = 65535, defense = 65535, speed = 65535, special = 65535 },
    stats = { hp = 399, attack = 298, defense = 290, speed = 292, special = 298 },
    hp = 399, status = nil,
    moves = { { id = "TRANSFORM", pp = 16, ppUps = 3 }, { id = "MEGA_PUNCH", pp = 16, ppUps = 3 } },
    nickname = "MEW", ot = "Lt<DOT>Ash", otId = 55721, catchRate = 45,
  },
}
for i = 1, 12 do save.boxes[i] = {} end
save.boxes[3] = { {
  species = "PIKACHU", level = 10, exp = 1000,
  dvs = { hp = 1, attack = 2, defense = 3, speed = 4, special = 5 },
  statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
  hp = 30, status = "PSN",
  moves = { { id = "THUNDERSHOCK", pp = 30, ppUps = 0 } },
  nickname = "PIKA", ot = "ASH", otId = 12345, catchRate = 190,
} }
save.currentBox = 1

local bytes2 = GenSave.encode(save, data, nil)
local decoded2 = GenSave.decode(bytes2, data)
check(#decoded2.warnings == 0, "a populated save passes its own checksum")
check(decoded2.player.id == 12345, "player ID round-trips")
check(decoded2.money == 3000 and decoded2.coins == 50, "money and coins round-trip")
check(decoded2.inventory.BOULDERBADGE == 1, "a badge round-trips as a truthy inventory entry")
check(decoded2.inventory.POKE_BALL == 5 and decoded2.inventory.ANTIDOTE == 1,
      "bag items round-trip")
check(decoded2.inventory.POKE_BALL and not decoded2.pcItems.POKE_BALL,
      "bag items don't leak into PC storage")
check(decoded2.pcItems.REVIVE == 2, "PC items round-trip")
check(decoded2.pokedex.seen.MEW and decoded2.pokedex.seen.PIKACHU and decoded2.pokedex.owned.PIKACHU,
      "pokedex seen/owned round-trip")
check(not decoded2.pokedex.owned.MEW, "a species only marked seen doesn't also come back owned")
check(decoded2.flags.EVENT_GOT_STARTER and decoded2.flags.EVENT_GOT_POKEDEX,
      "event flags round-trip")
-- wTownVisitedFlag: bit index == map index, LSB first (PALLET_TOWN is bit 0,
-- CELADON_CITY bit 6).  Before #263 decode never touched it, so an imported
-- save reached FLY with no destinations at all.
check(decoded2.visited and decoded2.visited.PALLET_TOWN and decoded2.visited.CELADON_CITY,
      "visited towns (the FLY destination set) round-trip")
check(decoded2.visited and not decoded2.visited.PEWTER_CITY,
      "a town that was never visited does not come back visited")

local mon1 = decoded2.party[1]
check(mon1 and mon1.species == "MEW", "party mon species round-trips")
check(mon1 and mon1.level == 100 and mon1.exp == 1059860, "party mon level/exp round-trip")
check(mon1 and mon1.hp == 399 and mon1.stats and mon1.stats.hp == 399,
      "party mon current HP and max HP stat round-trip")
check(mon1 and mon1.dvs.attack == 15 and mon1.dvs.speed == 12, "party mon DVs round-trip")
check(mon1 and mon1.moves[1].id == "TRANSFORM" and mon1.moves[1].pp == 16
      and mon1.moves[1].ppUps == 3, "party mon move/PP/PP-Up round-trip")
-- Gen1 has no "is nicknamed" bit: an un-nicknamed mon stores its species'
-- standard name in the nickname slot (engine/menus/naming_screen.asm AskName
-- .declinedNickname) and the game reads exactly that back as "not nicknamed"
-- (engine/pokemon/evos_moves.asm RenameEvolvedMon).  This project spells that
-- state mon.nickname == nil, so this fixture's MEW named "MEW" must come back
-- with no nickname at all, or it would refuse to rename itself on evolution
-- and export as a forced nickname (#257).
check(mon1 and mon1.nickname == nil and mon1.otId == 55721,
      "a stored name equal to the species name decodes as NOT nicknamed, OT ID round-trips")
check(mon1 and mon1.ot == "Lt<DOT>Ash",
      "an OT name containing a bracketed charmap token (\"<DOT>\") round-trips as one unit, "..
      "not per-byte \"?\" (got " .. tostring(mon1 and mon1.ot) .. ")")

local box3mon = decoded2.boxes[3][1]
check(box3mon and box3mon.species == "PIKACHU" and box3mon.status == "PSN",
      "a boxed mon's species and status condition round-trip")
-- the positive half of the #257 rule: a name that differs from the species
-- name IS a real nickname and must survive untouched
check(box3mon and box3mon.nickname == "PIKA",
      "a real nickname (different from the species name) still round-trips")
check(box3mon and box3mon.moves[1].id == "THUNDERSHOCK", "a boxed mon's move round-trips")
check(decoded2.currentBox == 1, "current box selection round-trips")

-- ------------------------------------------------------------------
-- checksum: a corrupted byte is detected on decode (warned, not thrown --
-- decode() must still succeed on a foreign save with a bad checksum)
-- ------------------------------------------------------------------

local O = GenSave.OFFSETS
local corrupted = bytes2:sub(1, O.money) ..
                  string.char((bytes2:byte(O.money + 1) + 1) % 256) ..
                  bytes2:sub(O.money + 2)
local decodedCorrupt = GenSave.decode(corrupted, data)
check(#decodedCorrupt.warnings == 1, "a corrupted byte trips the checksum warning")

-- ------------------------------------------------------------------
-- Scenario 2 (always-on): engine-origin export. A save that never came
-- from a real cartridge -- SaveData.newGame() plus a small party, bag,
-- PC and badge set built through the documented save shape -- must
-- encode with NO template into a structurally valid 32768-byte SRAM
-- image: exact size, all three SRAM checksums valid, and a clean
-- re-import that reproduces party / items / badges / name. (The vendor
-- gen1lib parse of this same image is exercised out-of-band under Lua
-- 5.4, since gen1lib cannot even be loaded by luajit.)
-- ------------------------------------------------------------------

local eng = SaveData.newGame({ playerName = "OAK", rivalName = "BLUE" })
eng.money = 1234
eng.inventory = { POTION = 3, POKE_BALL = 10, THUNDERBADGE = 1 }
eng.bagOrder = { "POTION", "POKE_BALL" }
eng.pcItems = { REVIVE = 1, FULL_RESTORE = 2 }
eng.pcOrder = { "REVIVE", "FULL_RESTORE" }
eng.party = {
  {
    species = "CHARMANDER", level = 5, exp = 135,
    dvs = { hp = 8, attack = 9, defense = 10, speed = 11, special = 12 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 20, attack = 11, defense = 10, speed = 12, special = 11 },
    hp = 20, status = nil,
    moves = { { id = "SCRATCH", pp = 35, ppUps = 0 }, { id = "GROWL", pp = 40, ppUps = 0 } },
    nickname = "CHAR", ot = "OAK", otId = eng.player.id, catchRate = 45,
  },
  {
    species = "PIDGEY", level = 4, exp = 64,
    dvs = { hp = 1, attack = 2, defense = 3, speed = 4, special = 5 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = { hp = 18, attack = 9, defense = 9, speed = 10, special = 8 },
    hp = 18, status = nil,
    moves = { { id = "TACKLE", pp = 35, ppUps = 0 } },
    nickname = "PIDGE", ot = "OAK", otId = eng.player.id, catchRate = 255,
  },
}

local engBytes = GenSave.encode(eng, data, nil) -- NO template: pure engine origin
check(#engBytes == GenSave.SAVE_SIZE, "engine-origin: encode is exactly 32768 bytes")
check(checksumValid(engBytes, OFF.checksumStart, OFF.checksumEnd, OFF.mainChecksum),
      "engine-origin: main data checksum valid")
check(boxBankChecksumValid(engBytes, OFF.box1, OFF.boxBank2Checksum, OFF.boxBank2IndividualChecksums),
      "engine-origin: bank 2 box checksums valid")
check(boxBankChecksumValid(engBytes, OFF.box7, OFF.boxBank3Checksum, OFF.boxBank3IndividualChecksums),
      "engine-origin: bank 3 box checksums valid")

local engDec = GenSave.decode(engBytes, data)
check(#engDec.warnings == 0, "engine-origin: re-import passes its own checksum")
check(engDec.player.name == "OAK", "engine-origin: player name reproduces")
check(#engDec.party == 2, "engine-origin: party size reproduces (got " .. #engDec.party .. ")")
check(engDec.party[1] and engDec.party[1].species == "CHARMANDER" and engDec.party[1].level == 5,
      "engine-origin: party[1] species/level reproduce")
check(engDec.party[2] and engDec.party[2].species == "PIDGEY"
      and engDec.party[2].moves[1] and engDec.party[2].moves[1].id == "TACKLE",
      "engine-origin: party[2] species/move reproduce")
check(engDec.inventory.POTION == 3 and engDec.inventory.POKE_BALL == 10,
      "engine-origin: bag items reproduce")
check(engDec.pcItems.REVIVE == 1 and engDec.pcItems.FULL_RESTORE == 2,
      "engine-origin: PC items reproduce")
check(engDec.inventory.THUNDERBADGE == 1, "engine-origin: badge reproduces as an inventory entry")
check(not engDec.pcItems.THUNDERBADGE, "engine-origin: badge doesn't leak into PC items")
-- expose the image for the out-of-band gen1lib parse (scenario 2 oracle)
do local w = io.open("/tmp/engine_origin.sav", "wb"); if w then w:write(engBytes); w:close() end end

-- ------------------------------------------------------------------
-- SaveConvert: the runtime-facing module (moved paths + shared merge).
-- SaveConvert loads its OWN crosswalk data through `require` (the same
-- src/core/Data.lua pattern), independent of the `data` table above, so
-- these checks also prove the moved src/save_convert/{GenSave,data/*} paths
-- resolve. bytes2 (a valid populated image built earlier) is the input.
-- ------------------------------------------------------------------

local scSave, scErr = SaveConvert.importSav(bytes2, 2)
check(scSave ~= nil, "SaveConvert.importSav returns a save table (" .. tostring(scErr) .. ")")
check(scSave and scSave.player and scSave.player.id == 12345,
      "SaveConvert.importSav: decoded player fields survive the merge")
check(scSave and scSave.inventory and scSave.inventory.POKE_BALL == 5,
      "SaveConvert.importSav: decoded bag items survive the merge")
-- merge over new-game defaults
check(scSave and type(scSave.options) == "table" and scSave.options.ruleset == "gen1_faithful",
      "SaveConvert.importSav: new-game default options merged in")
check(scSave and type(scSave.defeatedTrainers) == "table" and type(scSave.modData) == "table"
      and scSave.repelSteps == 0,
      "SaveConvert.importSav: default defeatedTrainers/modData/repelSteps merged in")
-- version tag
check(scSave and scSave.meta and scSave.meta.version == 2,
      "SaveConvert.importSav: save is tagged with the requested version")
-- derived heal/outdoor anchors
check(scSave and scSave.lastHeal and scSave.lastHeal.map == scSave.player.map,
      "SaveConvert.importSav: lastHeal derives from the decoded position")
check(scSave and scSave.lastOutdoor and scSave.lastOutdoor.id ~= nil,
      "SaveConvert.importSav: lastOutdoor is set")
-- The original SRAM image carries the current-map cache that Red restores on
-- Continue, while decode warnings are only import diagnostics.
check(scSave and type(scSave.rawImport) == "string" and scSave.warnings == nil,
      "SaveConvert.importSav: keeps the SRAM template but drops warnings")

-- size / type validation
local badSize, badSizeErr = SaveConvert.importSav("too short", 2)
check(badSize == nil and type(badSizeErr) == "string",
      "SaveConvert.importSav: rejects a wrong-size input with an error")
local nilIn, nilInErr = SaveConvert.importSav(nil, 2)
check(nilIn == nil and type(nilInErr) == "string",
      "SaveConvert.importSav: rejects a non-string input with an error")

-- checksum validation: flip a modeled byte so the stored checksum no longer
-- matches -> importSav must reject (GenSave.decode alone only warns).
local scCorrupt = bytes2:sub(1, OFF.money) ..
                  string.char((bytes2:byte(OFF.money + 1) + 1) % 256) ..
                  bytes2:sub(OFF.money + 2)
local scBad, scBadErr = SaveConvert.importSav(scCorrupt, 2)
check(scBad == nil and type(scBadErr) == "string" and tostring(scBadErr):find("checksum"),
      "SaveConvert.importSav: rejects a bad-checksum save with a checksum error")

-- exportSav zero-fill path: a merged import table carries no template, so the
-- export must still be a structurally valid 32768-byte image.
local scOut, scOutErr = SaveConvert.exportSav(scSave)
check(scOut ~= nil and #scOut == GenSave.SAVE_SIZE,
      "SaveConvert.exportSav: produces exactly 32768 bytes (" .. tostring(scOutErr) .. ")")
check(scOut and checksumValid(scOut, OFF.checksumStart, OFF.checksumEnd, OFF.mainChecksum),
      "SaveConvert.exportSav: main data checksum valid on a templateless export")
local scRt = SaveConvert.importSav(scOut, 2)
check(scRt and scRt.party[1] and scRt.party[1].species == "MEW",
      "SaveConvert import -> export -> import round-trips the party")
check(scRt and scRt.inventory.BOULDERBADGE == 1,
      "SaveConvert round-trip preserves a badge")

-- exportSav bad input
local scNilOut, scNilOutErr = SaveConvert.exportSav("not a table")
check(scNilOut == nil and type(scNilOutErr) == "string",
      "SaveConvert.exportSav: rejects a non-table input with an error")

-- exportSav template-aware path: a table still carrying the stashed import
-- template reproduces the source's UNMODELED regions byte-for-byte. Poke a
-- sentinel into the sprite-buffer region (inside the checksum window but not
-- written by encode), decode straight through GenSave (which keeps rawImport),
-- and confirm it survives on export while a templateless export zero-fills it.
local spriteOff = OFF.spriteData + 10
local sentinel = 0xAB
local templateSrc = bytes2:sub(1, spriteOff) .. string.char(sentinel) .. bytes2:sub(spriteOff + 2)
local tmplSave = GenSave.decode(templateSrc, data) -- rawImport = templateSrc
local tmplOut, tmplErr = SaveConvert.exportSav(tmplSave)
check(tmplOut ~= nil and #tmplOut == GenSave.SAVE_SIZE,
      "SaveConvert.exportSav: template-aware export is 32768 bytes (" .. tostring(tmplErr) .. ")")
check(tmplOut and tmplOut:byte(spriteOff + 1) == sentinel,
      "SaveConvert.exportSav: template-aware export carries an unmodeled region byte through")
check(tmplOut and checksumValid(tmplOut, OFF.checksumStart, OFF.checksumEnd, OFF.mainChecksum),
      "SaveConvert.exportSav: template-aware export still writes a valid checksum")
check(scOut and scOut:byte(spriteOff + 1) == 0,
      "SaveConvert.exportSav: templateless export zero-fills the same unmodeled region")

-- SaveConvert.loadData exposes the shared crosswalk set (require-loaded).
local scData = SaveConvert.loadData()
check(type(scData) == "table" and type(scData.pokemon) == "table"
      and type(scData.eventFlags) == "table",
      "SaveConvert.loadData: returns the crosswalk data set via require")

-- ------------------------------------------------------------------
-- Real-save import audit (fixture-gated). POKEPORT_SAV_FIXTURE must point
-- at a readable 32768-byte battery save (a personal .sav never checked in);
-- when it's unset or unusable the whole block skips with one notice, so the
-- suite stays green on any machine. When present, the full import is run and
-- audited for plausibility -- the same checks convert.lua's output has to
-- satisfy for SaveData.load to accept it without quarantine.
-- ------------------------------------------------------------------

local fixturePath = os.getenv("POKEPORT_SAV_FIXTURE")
local fixtureBytes
if fixturePath then
  local ff = io.open(fixturePath, "rb")
  if ff then
    fixtureBytes = ff:read("*a")
    ff:close()
    if #fixtureBytes ~= GenSave.SAVE_SIZE then fixtureBytes = nil end
  end
end

if not fixtureBytes then
  print("fixture checks skipped (set POKEPORT_SAV_FIXTURE to a 32KB .sav to run them)")
else
  local rs = GenSave.decode(fixtureBytes, data)

  check(type(rs.player.name) == "string" and #rs.player.name > 0,
        "fixture: player name decodes non-empty")

  local badges = 0
  for bit0 = 0, 7 do
    local names = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
                    "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE" }
    if rs.inventory[names[bit0 + 1]] then badges = badges + 1 end
  end
  check(badges >= 0 and badges <= 8, "fixture: badge count in 0..8 (got " .. badges .. ")")

  check(type(rs.money) == "number" and rs.money >= 0 and rs.money <= 999999,
        "fixture: money is a sane BCD value (got " .. tostring(rs.money) .. ")")
  check(type(rs.coins) == "number" and rs.coins >= 0 and rs.coins <= 9999,
        "fixture: coins is a sane BCD value (got " .. tostring(rs.coins) .. ")")

  check(#rs.party >= 1 and #rs.party <= 6,
        "fixture: party holds 1..6 mons (got " .. #rs.party .. ")")
  for i, mon in ipairs(rs.party) do
    check(data.pokemon[mon.species] ~= nil,
          "fixture: party mon " .. i .. " has a known species (" .. tostring(mon.species) .. ")")
    check(mon.level >= 2 and mon.level <= 100,
          "fixture: party mon " .. i .. " level in 2..100 (got " .. tostring(mon.level) .. ")")
    check(#mon.moves >= 1 and #mon.moves <= 4,
          "fixture: party mon " .. i .. " has 1..4 moves (got " .. #mon.moves .. ")")
    for _, mv in ipairs(mon.moves) do
      check(data.moves[mv.id] ~= nil,
            "fixture: party mon " .. i .. " move is known (" .. tostring(mv.id) .. ")")
      check(mv.pp >= 0 and mv.pp <= 63,
            "fixture: party mon " .. i .. " move PP in 0..63 (got " .. tostring(mv.pp) .. ")")
    end
    check(type(mon.exp) == "number" and mon.exp > 0,
          "fixture: party mon " .. i .. " has nonzero EXP")
  end

  local owned, seen = 0, 0
  for _ in pairs(rs.pokedex.owned) do owned = owned + 1 end
  for _ in pairs(rs.pokedex.seen) do seen = seen + 1 end
  check(owned <= seen and seen <= 151,
        "fixture: pokedex owned <= seen <= 151 (owned " .. owned .. ", seen " .. seen .. ")")

  check(rs.player.map ~= nil and data.maps[rs.player.map] ~= nil,
        "fixture: current map resolves to a real map id (" .. tostring(rs.player.map) .. ")")
  check(type(rs.player.x) == "number" and type(rs.player.y) == "number"
        and rs.player.x >= 0 and rs.player.y >= 0,
        "fixture: player position is in-bounds non-negative")

  local boxed = 0
  for b = 1, 12 do boxed = boxed + #rs.boxes[b] end
  check(boxed >= 0 and boxed <= 12 * 20,
        "fixture: boxed mon count within 12 boxes x 20 (got " .. boxed .. ")")

  local nflags = 0
  for _ in pairs(rs.flags) do nflags = nflags + 1 end
  check(nflags > 0, "fixture: at least one event flag populated (got " .. nflags .. ")")

  -- play time (mapped from wPlayTimeHours/Minutes/Seconds/Frames into
  -- save.playTime seconds): a real playthrough has a positive clock, and
  -- it must round-trip through encode() back to the same H:M:S:F.
  check(type(rs.playTime) == "number" and rs.playTime > 0,
        "fixture: play time decodes to a positive second count (got "
        .. tostring(rs.playTime) .. ")")
  local rtBytes = GenSave.encode(rs, data, fixtureBytes)
  local rt = GenSave.decode(rtBytes, data)
  check(math.abs(rt.playTime - rs.playTime) < 1e-6,
        "fixture: play time round-trips through encode()")
  check(#rt.warnings == 0, "fixture: re-encoded save passes its own checksum")

  -- Scenario 1 (fixture-gated): full export fidelity of the real save.
  check(#rtBytes == GenSave.SAVE_SIZE, "fixture export: exactly 32768 bytes")
  check(checksumValid(rtBytes, OFF.checksumStart, OFF.checksumEnd, OFF.mainChecksum),
        "fixture export: main data checksum valid")
  check(boxBankChecksumValid(rtBytes, OFF.box1, OFF.boxBank2Checksum, OFF.boxBank2IndividualChecksums),
        "fixture export: bank 2 box checksums valid")
  check(boxBankChecksumValid(rtBytes, OFF.box7, OFF.boxBank3Checksum, OFF.boxBank3IndividualChecksums),
        "fixture export: bank 3 box checksums valid")
  -- Byte-for-byte fidelity with the original as template: every byte GenSave
  -- emits must reproduce the source EXCEPT the derived integrity bytes (the
  -- main checksum and the two 7-byte box-bank checksum footers). Zero content
  -- diffs proves both that every modeled region re-encodes identically AND
  -- that the template carries each unmodeled region (sprite buffers, Hall of
  -- Fame, Day Care, options, connection cache, ...) through untouched. A
  -- tampered source can carry stale box checksums; the export rewrites them to
  -- valid values, which is why the checksum bytes are the only exemptions.
  local exempt = {}
  exempt[OFF.mainChecksum] = true
  for b = 0, 6 do exempt[OFF.boxBank2Checksum + b] = true end
  for b = 0, 6 do exempt[OFF.boxBank3Checksum + b] = true end
  local contentDiffs = 0
  for i = 0, GenSave.SAVE_SIZE - 1 do
    if not exempt[i] and rtBytes:byte(i + 1) ~= fixtureBytes:byte(i + 1) then
      contentDiffs = contentDiffs + 1
    end
  end
  check(contentDiffs == 0,
        "fixture export: modeled + template-preserved bytes reproduce the source "
        .. "byte-for-byte (got " .. contentDiffs .. " unexpected diffs)")
  -- Expose the export so crosscheck.lua can be reused as the vendor oracle:
  --   POKEPORT_SAV_FIXTURE=/tmp/roundtrip.sav lua tools/save_convert/crosscheck.lua
  -- confirms gen1lib parse_save accepts these exported bytes and agrees.
  do local w = io.open("/tmp/roundtrip.sav", "wb"); if w then w:write(rtBytes); w:close() end end

  print(("fixture audit OK: name=%s badges=%d money=%d party=%d boxed=%d dex=%d/%d play=%dh%02dm"):format(
        rs.player.name, badges, rs.money, #rs.party, boxed, owned, seen,
        math.floor(rs.playTime / 3600), math.floor(rs.playTime / 60) % 60))
end

-- ------------------------------------------------------------------
-- #206 export fidelity, found while auditing the reporter's PKHeX shots:
--
-- 1. Name fields on a templateless (engine-origin) export must be
--    $50-PADDED after the terminator, like every real save the naming
--    screen ever wrote -- a zero tail is what PKHeX rendered as "JOHN{}".
-- 2. wOptions (0x2601) must carry the text speed / battle style / battle
--    effects bits; it was never written at all.
-- 3. The party/box catch-rate byte freezes at catch time in Gen1
--    (evolution does NOT update it), so a mon carries its
--    as-caught catchRate and encode() must write that, not blindly
--    re-derive from the current species (PKHeX: "Expected a preevolution
--    catch rate").
-- ------------------------------------------------------------------

-- (1) templateless export pads every name tail with $50
do
  local function nameField(bytes, off, label)
    local term
    for i = 0, 10 do
      if bytes:byte(off + i + 1) == 0x50 then term = i break end
    end
    check(term ~= nil, label .. ": a $50 terminator exists")
    if term then
      for i = term + 1, 10 do
        if bytes:byte(off + i + 1) ~= 0x50 then
          check(false, label .. ": tail byte " .. i .. " is $50 padding, got $"
                .. ("%02X"):format(bytes:byte(off + i + 1)))
          return
        end
      end
      check(true, label .. ": the tail is $50-padded")
    end
  end
  -- bytes2 is templateless (ASH/GARY, MEW in the party, PIKACHU boxed)
  nameField(bytes2, OFF.playerName, "player name")
  nameField(bytes2, OFF.rivalName, "rival name")
  nameField(bytes2, OFF.partyMonOT, "party OT")
  nameField(bytes2, OFF.partyMonNicks, "party nickname")
  local box3 = OFF.box1 + 2 * GenSave.BOX_REGION_SIZE
  nameField(bytes2, box3 + 22 + 20 * 33, "box OT")
  nameField(bytes2, box3 + 22 + 20 * (33 + 11), "box nickname")
  -- ...while a template's nonzero stale bytes still survive (round-trip):
  -- the template-aware block above already proves byte-identical tails.
end

-- (2) wOptions carries text speed (bits 2-0), battle style (bit 6) and
-- battle effects off (bit 7)
do
  local o = SaveData.newGame({ playerName = "RED" })
  o.options = SaveData.mergeOptions({ textSpeed = 1, battleStyle = "set",
                                      animations = false })
  local ob = GenSave.encode(o, data, nil)
  check(ob:byte(OFF.options + 1) == 0x80 + 0x40 + 1,
        ("wOptions packs effects-off + set style + fast text ($%02X)"):format(
          ob:byte(OFF.options + 1)))
  local o2 = SaveData.newGame({ playerName = "RED" })
  o2.options = SaveData.defaultOptions() -- textSpeed 3, shift, animations on
  local ob2 = GenSave.encode(o2, data, nil)
  check(ob2:byte(OFF.options + 1) == 3,
        ("wOptions defaults to medium text, shift style, effects on ($%02X)"):format(
          ob2:byte(OFF.options + 1)))
  -- ...but with a template the cartridge's own byte wins (the round-trip
  -- invariant): an imported save's FAST+SET options must not be flattened
  -- to the session defaults on re-export
  local tpl = {}
  for i = 1, GenSave.SAVE_SIZE do tpl[i] = string.char(0) end
  tpl[OFF.options + 1] = string.char(0xC1)
  local ob3 = GenSave.encode(o2, data, table.concat(tpl))
  check(ob3:byte(OFF.options + 1) == 0xC1,
        ("wOptions survives from the template on re-export ($%02X)"):format(
          ob3:byte(OFF.options + 1)))
end

-- (3) catchRate: Pokemon.new stamps the as-caught byte, evolution keeps it,
-- encode prefers the mon's byte over the current species def
do
  local Pokemon = require("src.pokemon.Pokemon")
  local Evolution = require("src.pokemon.Evolution")
  local mon = Pokemon.new(data, "NIDORAN_F", 16)
  check(mon.catchRate == data.pokemon.NIDORAN_F.catchRate,
        "Pokemon.new stamps the species catchRate (the as-caught byte)")
  local game = { data = data, save = { pokedex = { seen = {}, owned = {} } } }
  Evolution.apply(game, mon, "NIDORINA")
  check(mon.species == "NIDORINA" and mon.catchRate == data.pokemon.NIDORAN_F.catchRate,
        "evolution preserves the as-caught catchRate byte (Gen1 quirk)")
  local s = SaveData.newGame({ playerName = "RED" })
  s.party = { mon }
  for i = 1, 12 do s.boxes = s.boxes or {}; s.boxes[i] = {} end
  local sb = GenSave.encode(s, data, nil)
  check(sb:byte(OFF.partyMons + 7 + 1) == data.pokemon.NIDORAN_F.catchRate,
        "encode writes the mon's catchRate, not the evolved species' ("
        .. sb:byte(OFF.partyMons + 7 + 1) .. " vs "
        .. data.pokemon.NIDORAN_F.catchRate .. ")")
end

-- (4) name-field tails: real cartridge saves legitimately hold 0x00 (and
-- stale glyph) bytes after a name's $50 terminator, and rewriting them broke
-- the import -> export byte-identical round trip.  With a template every
-- tail byte must survive verbatim; only a templateless (engine-origin)
-- export $50-pads the tail (#206).
do
  local s = SaveData.newGame({ playerName = "RED" })
  for i = 1, 12 do s.boxes = s.boxes or {}; s.boxes[i] = {} end
  local b1 = GenSave.encode(s, data, nil)
  -- templateless: the tail past "RED@" must be all $50 padding
  local ok50 = true
  for i = 4, 10 do
    if b1:byte(OFF.playerName + i + 1) ~= 0x50 then ok50 = false end
  end
  check(ok50, "templateless export $50-pads the player-name tail (#206)")
  -- build a template whose player-name tail mixes 0x00 and stale glyphs
  -- after the terminator, exactly like a real traded/edited cartridge save
  local tpl = {}
  for i = 1, #b1 do tpl[i] = b1:sub(i, i) end
  tpl[OFF.playerName + 5] = string.char(0x00)
  tpl[OFF.playerName + 6] = string.char(0x81)
  tpl[OFF.playerName + 7] = string.char(0x00)
  local tplBytes = table.concat(tpl)
  local decoded = GenSave.decode(tplBytes, data)
  check(decoded.player.name == "RED",
        "a 0x00/stale tail past the terminator does not leak into the name")
  local b2 = GenSave.encode(decoded, data)
  check(b2:sub(OFF.playerName + 1, OFF.playerName + 11)
          == tplBytes:sub(OFF.playerName + 1, OFF.playerName + 11),
        "template name tails (incl. 0x00 bytes) round-trip byte-identical")
end

print(string.format("save convert: %d/%d checks passed", checks - failures, checks))
if failures > 0 then os.exit(1) end
