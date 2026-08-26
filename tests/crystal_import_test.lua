-- Crystal manifest shape and the specials surface the extractor pins to it.
-- ROM-free: reads tools/rom_manifest_crystal.json out of the source tree.
--   luajit tests/crystal_import_test.lua
-- Also dofile'd by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("crystal import")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Json = require("src.link.Json")
local GameVersion = require("src.core.GameVersion")

local function manifest(path)
  local file = assert(io.open(path, "r"))
  local data = assert(Json.decode(file:read("*a")))
  file:close()
  return data
end

local function size(tbl)
  local n = 0
  for _ in pairs(tbl or {}) do n = n + 1 end
  return n
end

local crystal = manifest("tools/rom_manifest_crystal.json")
local gold = manifest("tools/rom_manifest_gold.json")

-- ------- 1. the manifest the launcher row points at

eq(GameVersion.VERSIONS.crystal.manifest, "tools/rom_manifest_crystal.json",
  "the crystal row names this manifest")
eq(crystal.romSha1, GameVersion.VERSIONS.crystal.sha1,
  "and the manifest carries the same sha1")
eq(crystal.generation, 2, "generation 2")
eq(crystal.format, gold.format, "same manifest format as Gold")

-- ------- 1b. the 1.1 revision's symbol delta

local rev11
for _, revision in ipairs(GameVersion.revisions("crystal")) do
  if revision.label == "1.1" then rev11 = revision end
end
check(rev11 ~= nil, "the crystal row names a 1.1 revision")

if rev11 then
  check(GameVersion.acceptsSha1("crystal", GameVersion.VERSIONS.crystal.sha1),
    "the crystal row accepts the canonical 1.0 sha1")
  check(GameVersion.acceptsSha1("crystal", rev11.sha1),
    "and the 1.1 sha1 too")

  local overlay = (crystal.symbolRevisions or {})[rev11.sha1]
  check(type(overlay) == "table",
    "the manifest carries a symbolRevisions overlay for the 1.1 sha1")
  if overlay then
    eq(size(overlay), 1, "with exactly one symbol moved")
    local moved = overlay.Stadium2N64Attrmap
    check(type(moved) == "table", "and it names Stadium2N64Attrmap")
    local base = crystal.symbols.Stadium2N64Attrmap
    check(base ~= nil, "the base manifest still carries Stadium2N64Attrmap")
    if moved and base then
      check(not (moved[1] == base[1] and moved[2] == base[2]),
        "at a location different from the base symbols entry")
    end
  end
end

-- ------- 2. content counts

eq(size(crystal.maps), 388, "388 maps")
eq(size(crystal.tilesets), 36, "36 tilesets")
eq(size(crystal.pokemonAssets), 251, "251 pokemon asset rows")
eq(size(crystal.constants), 50, "50 constants keys")
eq(type(crystal.constants.engineFlagOrder), "table",
  "the 50th is engineFlagOrder, the key Gold has no counterpart for")
check(size(crystal.symbols) > 2000,
  ("symbols table is populated (%d)"):format(size(crystal.symbols)))
check(size(crystal.charmap) > 200,
  ("charmap is populated (%d)"):format(size(crystal.charmap)))
check(#(crystal.fontCharmap or {}) > 200,
  ("fontCharmap is populated (%d)"):format(#(crystal.fontCharmap or {})))

-- pokecrystal/constants/map_constants.asm:504, pokegold:484
eq(size(gold.maps), 368, "Gold names 368")
local added, removed = 0, 0
for name in pairs(crystal.maps) do
  if not gold.maps[name] then added = added + 1 end
end
for name in pairs(gold.maps) do
  if not crystal.maps[name] then removed = removed + 1 end
end
eq(added, 21, "Crystal adds 21 maps")
eq(removed, 1, "and drops one")
-- pokegold/constants/map_constants.asm:152
eq(crystal.maps.ECRUTEAK_TIN_TOWER_BACK_ENTRANCE, nil,
  "the one Gold map Crystal drops is ECRUTEAK_TIN_TOWER_BACK_ENTRANCE")
check(crystal.maps.BATTLE_TOWER_1F ~= nil, "and BATTLE_TOWER_1F is new")

-- ------- 3. every map row is addressable

local badMap
for name, row in pairs(crystal.maps) do
  if type(row) ~= "table" then badMap = name; break end
end
eq(badMap, nil, "every map row is a table")

-- ------- 4. the text labels resolve, as they must for the Dialogue stage

local labels = (crystal.text or {}).labels or {}
check(#labels > 800, ("crystal names %d text labels"):format(#labels))
local unresolved = {}
for _, label in ipairs(labels) do
  if not crystal.symbols[label] then unresolved[#unresolved + 1] = label end
end
eq(#unresolved, 0,
  ("every crystal text label resolves to a symbol (%s)")
    :format(table.concat(unresolved, ", "):sub(1, 60)))

-- ------- 5. specials: constants.specialOrder against the handler table

local Specials = require("src.script.gen2.Specials")

local order = crystal.constants.specialOrder
check(type(order) == "table", "constants.specialOrder is a list")
eq(#order, 169, "Crystal's SpecialsPointers has 169 rows")

local missing = {}
for index, name in ipairs(order) do
  if not Specials.ALL[name] then
    missing[#missing + 1] = ("%d (%s)"):format(index - 1, name)
  end
end
eq(#missing, 0,
  ("every crystal special has a handler (%s)")
    :format(table.concat(missing, ", "):sub(1, 80)))

local goldOrder = gold.constants.specialOrder
local goldMissing = {}
for index, name in ipairs(goldOrder or {}) do
  if not Specials.ALL[name] then
    goldMissing[#goldMissing + 1] = ("%d (%s)"):format(index - 1, name)
  end
end
eq(#goldMissing, 0,
  ("every gold special has a handler too (%s)")
    :format(table.concat(goldMissing, ", "):sub(1, 80)))

local sameOrder = #order == #(goldOrder or {})
if sameOrder then
  for index, name in ipairs(order) do
    if goldOrder[index] ~= name then sameOrder = false; break end
  end
end
check(not sameOrder, "the Crystal and Gold special orders are not the same")

-- ------- 6. handler bookkeeping

local overlap = {}
for name in pairs(Specials.STUBS) do
  if Specials.HANDLERS[name] then overlap[#overlap + 1] = name end
end
eq(#overlap, 0,
  ("HANDLERS and STUBS are disjoint (%s)"):format(table.concat(overlap, ", ")))

local unexplained = {}
for name in pairs(Specials.STUBS) do
  local reason = (Specials.STUB_REASONS or {})[name]
  if type(reason) ~= "string" or reason == "" then
    unexplained[#unexplained + 1] = name
  end
end
eq(#unexplained, 0,
  ("every stub records a reason (%s)")
    :format(table.concat(unexplained, ", "):sub(1, 80)))

-- ------- 7. the Crystal-only assets the completeness gate pins

local CacheContract = require("src.import.CacheContract")
local requiredFiles, isOverride = CacheContract.requiredFilesFor("crystal")
check(isOverride, "crystal has its own required-file list")

local required = {}
for _, path in ipairs(requiredFiles) do required[path] = true end
for _, path in ipairs({
  "assets/generated/title/crystal_logo.png",
  "assets/generated/title/crystal_wordmark.png",
  "assets/generated/title/crystal_suicune.png",
  "assets/generated/splash/ditto.png",
  "assets/generated/intro/chris.png",
  "assets/generated/intro/kris.png",
}) do
  check(required[path], "the crystal cache contract still requires " .. path)
end

S.finish()
