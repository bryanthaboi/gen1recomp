-- The launcher's Export on a Gold save slot.
--
--   GOLD_CACHE="..." luajit tests/gen2_save_export_test.lua
--
-- src/save_convert/GenSave.lua is a Gen 1 codec: its whole offset table is
-- pokered's SRAM window, and a Gold save lives in a different one entirely
-- (pokegold ram/sram.asm sOptions/sCheckValue1/sPlayerData/sBox1-sBox14),
-- so no cart .sav can come out of a Gold slot yet.  Export used to reach
-- the codec anyway and die inside GenSave.crosswalks: the Gen 2 generated
-- tables carry top-level provenance scalars (`generation`, `source` --
-- src/import/RomExtractorGen2.lua) beside the def rows, and indexing the
-- scalar raised "attempt to index local 'def' (a number value)", which the
-- launcher then printed as a red "encode failed:" traceback.
--
-- Two guarantees pinned here:
--   * the REAL launcher path (slot registry -> gen2 Save.save ->
--     SaveFileIO.exportActiveSlot) answers a plain "not supported yet"
--     message for Gold, in both directions, and writes no export file;
--   * GenSave.crosswalks skips non-table rows, so a data set that carries
--     provenance scalars can never crash the codec again.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 save export")
local check, eq = S.check, S.eq

love = love or require("tests.love_stub")

-- An isolated in-memory love.filesystem, the same shape
-- tests/engine/save_slots.lua isolates SaveData with: full-path keys, no
-- directory support (both writers guard their createDirectory calls).
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
}

local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local GoldSave = require("src.core.gen2.Save")
local SaveFileIO = require("src.import.SaveFileIO")
local SaveConvert = require("src.save_convert.SaveConvert")
local GenSave = require("src.save_convert.GenSave")

-- ---------------------------------------------------------------------------
-- The real launcher path: a registered Gold slot holding a save the game's
-- own writer produced, exported through the same call the Export chip makes.
-- ---------------------------------------------------------------------------

SaveData.resetSlotState()
GameVersion.set("gold")

local slotId = SaveData.createSlot("gold")
check(slotId ~= nil, "a gold slot registers")
SaveData.setActiveSlot("gold", slotId)
local save = GoldSave.newGame({ playerName = "BLAKE", rivalName = "SILVER" })
eq(GoldSave.save(save), true, "the gen2 writer fills the slot")
check(files["saves/gold/" .. tostring(slotId) .. ".lua"] ~= nil,
      "the slot file the launcher lists is on disk")

local ok, res = SaveFileIO.exportActiveSlot("gold")
eq(ok, false, "Export on a cacheless Gold slot is refused, not crashed")
check(type(res) == "string" and res:find("does not name one", 1, true),
      "the refusal names the unresolved map: " .. tostring(res))
check(type(res) == "string"
      and not res:find("no cartridge image to write", 1, true),
      "and not the old lineage refusal: " .. tostring(res))
check(not tostring(res):find("GenSave", 1, true)
      and not tostring(res):find("attempt to index", 1, true),
      "no codec traceback leaks into the notice line")
local exported = false
for path in pairs(files) do
  if path:find("^exports/") then exported = true end
end
eq(exported, false, "no export file is written when the map cannot be resolved")

do
  local Gen2Save = require("src.save_convert.Gen2Save")
  local placed = GoldSave.newGame({ playerName = "BLAKE", rivalName = "SILVER" })
  placed.position = { mapGroup = 24, mapNumber = 7, x = 3, y = 3 }
  local data = { maps = { HOME = {
    group = 24, map = 7, objectEventsAddr = 0x5CF0,
    width = 4, height = 3,
    blocks = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 },
    objects = {},
  } } }
  local bytes, why = Gen2Save.encode(placed, "gold", nil, data)
  check(bytes ~= nil, "a fresh Gold slot exports -- " .. tostring(why))
  if bytes then
    eq(#bytes, 32768, "a full battery image")
    eq(Gen2Save.checksumValid(bytes, Gen2Save.layoutFor("gold")), true,
       "sealed the way the cartridge verifies it")
    local L = Gen2Save.layoutFor("gold")
    -- data/default_options.asm, engine/overworld/player_object.asm:411
    eq(bytes:byte(L.sOptions + 1), 0x03, "sOptions carries DefaultOptions")
    eq(bytes:byte(L.wPlayerStruct + 1), 0x01, "the player struct has a sprite")
    eq(bytes:byte(L.wPlayerStruct + 4), 0x0B, "and SPRITEMOVEDATA_PLAYER")
    eq(bytes:byte(L.wScreenSave + 1 + 7), 4,
       "and the restored screen window holds the map's own blocks")
    local back = Gen2Save.decode(bytes, "gold")
    check(back ~= nil and back.player.name == "BLAKE",
          "and the bytes decode back to the save they came from")
  end
end

-- The import direction no longer matches the export one. Gold imports through
-- Gen2Save now, so a 32 KB image aimed at Gold is decoded rather than turned
-- away by version. An all-zero image still fails, because Gen 2's guards are
-- two check values and a sum and a blank image has none of them: refused for
-- what it is, not for which game it is for.
local iok, ierr = SaveConvert.importSav(string.rep("\0", 32768), "gold", "gold")
eq(iok, nil, "a blank cart .sav for Gold is still refused")
check(type(ierr) == "string" and ierr:find("not supported yet", 1, true) == nil,
      "and no longer refused by version: " .. tostring(ierr))
check(type(ierr) == "string" and ierr:find("checksum", 1, true) ~= nil,
      "it is Gen 2's own guards that turn it away: " .. tostring(ierr))

-- Gen 1 versions still pass the gate: red reaches the codec proper and
-- fails on its own terms (an all-zero image is not a table), never on the
-- version.
local rok, rerr = SaveConvert.exportSav({}, "red")
check(rok ~= nil or not tostring(rerr):find("not supported yet", 1, true),
      "a red export is never refused by the version gate")

GameVersion.set("red")

-- ---------------------------------------------------------------------------
-- GenSave.crosswalks over def tables that carry provenance scalars.
-- ---------------------------------------------------------------------------

-- Synthetic set, ROM-free: real rows resolve, scalar rows are skipped in
-- all three builders (index, dex, machine).
local defs = {
  pokemon = {
    generation = 2,
    source = "ROM:BaseStats",
    MEW = { index = 21, source = "ROM:BaseStats[151]", name = "MEW" },
  },
  moves = {
    generation = 2,
    POUND = { index = 1 },
  },
  items = {
    generation = 2,
    source = "ROM:ItemNames",
    POKE_BALL = { index = 4 },
    TM01 = { machine = { kind = "TM", number = 1 } },
  },
  maps = {
    generation = 2,
    PALLET_TOWN = { index = 0 },
  },
}
local cok, cw = pcall(GenSave.crosswalks, defs)
eq(cok, true, "crosswalks survive scalar rows: " .. tostring(cw))
if cok then
  eq(cw.pokemonIndex.MEW, 21, "a def row beside scalars still resolves")
  eq(cw.pokemonByDex[151], "MEW", "the dex builder skips scalar rows")
  eq(cw.itemsIndex.TM01, 201, "the machine builder skips scalar rows")
  eq(cw.pokemonIndex.generation, nil, "a scalar row never becomes an id")
end

-- The real Gold tables, when a cache is around: the exact shape that
-- raised at GenSave.crosswalks before the guard.
local cache = os.getenv("GOLD_CACHE")
if cache then
  local function loadGen(name)
    local chunk = assert(loadfile(cache .. "/data/generated/" .. name .. ".lua"))
    return chunk()
  end
  local gold = {
    pokemon = loadGen("pokemon"), moves = loadGen("moves"),
    items = loadGen("items"), maps = loadGen("maps"),
  }
  eq(type(gold.items.generation), "number",
     "the gold items table really does carry a scalar row (the regression stays armed)")
  local gok, gerr = pcall(GenSave.crosswalks, gold)
  eq(gok, true, "crosswalks over the extracted Gold tables: " .. tostring(gerr))
else
  check(true, "no GOLD_CACHE: the extracted Gold tables are not checked (SKIP)")
end

S.finish()
