-- Crystal registration: VERSIONS row, engine lineage, ORDER slot, sha1
-- routing, the importer's required-file override and the script dialect.
--   luajit tests/engine/crystal_version_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("crystal version registration")
local check = S.check
local eq = S.eq

local GameVersion = require("src.core.GameVersion")
local Opcodes = require("src.script.gen2.Opcodes")

-- ------- 1. the VERSIONS row

local row = GameVersion.VERSIONS.crystal
check(row ~= nil, "GameVersion.VERSIONS carries a crystal row")
eq(row.id, "crystal", "row id")
eq(row.label, "Crystal", "row label")
eq(row.displayName, "Pokemon Crystal", "row display name")
eq(row.sha1, "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133", "retail Crystal sha1")
eq(row.manifest, "tools/rom_manifest_crystal.json", "row manifest path")
eq(row.cachePrefix, "crystal/", "cache prefix")
eq(row.saveSuffix, "_crystal", "save suffix")
eq(GameVersion.cachePrefix("crystal"), "crystal/", "cachePrefix() agrees")
eq(GameVersion.saveSuffix("crystal"), "_crystal", "saveSuffix() agrees")

local prefixes, suffixes = {}, {}
for _, id in ipairs(GameVersion.ORDER) do
  local info = GameVersion.info(id)
  eq(prefixes[info.cachePrefix], nil, id .. " cache prefix is unique")
  eq(suffixes[info.saveSuffix], nil, id .. " save suffix is unique")
  prefixes[info.cachePrefix] = id
  suffixes[info.saveSuffix] = id
end

-- ------- 2. generation and engine lineage

eq(GameVersion.generation("crystal"), 2, "Crystal is Gen 2")
eq(GameVersion.engine("crystal"), "crystal", "Crystal's engine lineage")
eq(GameVersion.engine("gold"), "gs", "Gold is the gs lineage")
eq(GameVersion.engine("silver"), "gs", "and so is Silver")
eq(GameVersion.engine("red"), "gen1", "Red is gen1")
eq(GameVersion.engine("blue"), "gen1", "Blue is gen1")
eq(GameVersion.engine("yellow"), "gen1", "Yellow is gen1")

local LINEAGES = { gen1 = true, gs = true, crystal = true }
for _, id in ipairs(GameVersion.ORDER) do
  check(LINEAGES[GameVersion.engine(id)] == true,
    id .. " reports a known engine lineage")
end

eq(GameVersion.generation("gold"), 2, "Gold is Gen 2")
eq(GameVersion.generation("silver"), 2, "Silver is Gen 2")
eq(GameVersion.generation("red"), 1, "Red is Gen 1")

-- ------- 3. launcher ORDER

local index
for i, id in ipairs(GameVersion.ORDER) do
  if id == "crystal" then index = i end
end
eq(index, 6, "crystal is ORDER slot 6")
eq(#GameVersion.ORDER, 6, "ORDER is six games")
eq(GameVersion.ORDER[4], "gold", "gold keeps slot 4")
eq(GameVersion.ORDER[5], "silver", "silver keeps slot 5")

-- ------- 4. sha1 routing

eq(GameVersion.forSha1("f4cd194bdee0d04ca4eac29e09b8e4e9d818c133"), "crystal",
  "the retail Crystal 1.0 sha1 resolves to crystal")
eq(GameVersion.forSha1("f2f52230b536214ef7c9924f483392993e226cfb"), "crystal",
  "the retail Crystal 1.1 sha1 also resolves to crystal")
eq(GameVersion.forSha1("d8b8a3600a465308c9953dfa04f0081c05bdcb94"), "gold",
  "Gold's sha1 still resolves to gold")
eq(GameVersion.forSha1("deadbeef"), nil, "an unknown ROM resolves to nothing")

-- ------- 4b. revisions / acceptsSha1 / revisionLabel

local crystalRevisions = GameVersion.revisions("crystal")
eq(#crystalRevisions, 2, "crystal lists both accepted revisions")
eq(crystalRevisions[1].sha1, "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133",
  "revision 1 is the 1.0 sha1")
eq(crystalRevisions[1].label, "1.0", "revision 1 is labeled 1.0")
eq(crystalRevisions[2].sha1, "f2f52230b536214ef7c9924f483392993e226cfb",
  "revision 2 is the 1.1 sha1")
eq(crystalRevisions[2].label, "1.1", "revision 2 is labeled 1.1")

check(GameVersion.acceptsSha1("crystal", "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133"),
  "crystal accepts the 1.0 sha1")
check(GameVersion.acceptsSha1("crystal", "f2f52230b536214ef7c9924f483392993e226cfb"),
  "crystal accepts the 1.1 sha1")
check(not GameVersion.acceptsSha1("crystal", "deadbeef"),
  "crystal rejects an unknown sha1")

eq(GameVersion.revisionLabel("crystal", "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133"),
  "1.0", "revisionLabel resolves the 1.0 hash")
eq(GameVersion.revisionLabel("crystal", "f2f52230b536214ef7c9924f483392993e226cfb"),
  "1.1", "revisionLabel resolves the 1.1 hash")
eq(GameVersion.revisionLabel("crystal", "deadbeef"), nil,
  "revisionLabel is nil for an unrecognized hash")

local goldRevisions = GameVersion.revisions("gold")
eq(#goldRevisions, 1, "gold synthesizes a single revision entry")
eq(goldRevisions[1].sha1, GameVersion.info("gold").sha1,
  "the synthesized entry carries gold's canonical sha1")
check(GameVersion.acceptsSha1("gold", GameVersion.info("gold").sha1),
  "gold accepts its own canonical sha1")
check(not GameVersion.acceptsSha1("gold", "deadbeef"),
  "gold rejects an unknown sha1")
eq(GameVersion.revisionLabel("gold", GameVersion.info("gold").sha1), nil,
  "gold's synthesized entry carries no label")

local redRevisions = GameVersion.revisions("red")
eq(#redRevisions, 1, "red synthesizes a single revision entry")
check(GameVersion.acceptsSha1("red", GameVersion.info("red").sha1),
  "red accepts its own canonical sha1")
eq(GameVersion.forSha1(GameVersion.info("red").sha1), "red",
  "and forSha1 still resolves red through the synthesized entry")

-- ------- 5. set / get round trip

local savedCurrent = GameVersion.get()
eq(GameVersion.set("crystal"), "crystal", "set('crystal') is accepted")
eq(GameVersion.get(), "crystal", "and becomes current")
eq(GameVersion.engine(), "crystal", "engine() with no argument reads current")
check(not GameVersion.isGold(), "isGold() stays false on Crystal")
GameVersion.set(savedCurrent)

-- ------- 6. the importer's required-file list

local CacheContract = require("src.import.CacheContract")

local function requiredSet(version)
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local required, isOverride = CacheContract.requiredFilesFor(version)
  local seen, count = {}, 0
  local function add(path)
    if not seen[prefix .. path] then count = count + 1 end
    seen[prefix .. path] = true
  end
  for _, path in ipairs(required) do add(path) end
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      add(path)
    end
  end
  return seen, count
end

local crystalSeen, crystalCount = requiredSet("crystal")
local redSeen = requiredSet("red")

check(select(2, CacheContract.requiredFilesFor("crystal")) == true,
  "crystal has its own required-file override, not the Gen 1 list")
check(crystalCount > 20,
  ("the crystal list is substantial (%d entries)"):format(crystalCount))
for _, path in ipairs({
  "crystal/data/generated/encounters.lua",
  "crystal/data/generated/landmarks.lua",
  "crystal/data/generated/title.lua",
  "crystal/data/generated/intro.lua",
  "crystal/assets/generated/title/crystal_logo.png",
  "crystal/assets/generated/title/crystal_wordmark.png",
  "crystal/assets/generated/title/crystal_suicune.png",
  "crystal/assets/generated/splash/ditto.png",
  "crystal/assets/generated/intro/chris.png",
  "crystal/assets/generated/intro/kris.png",
  "crystal/assets/generated/battle/front/wooper.png",
}) do
  check(crystalSeen[path] == true, "crystal requires " .. path)
end

for _, path in ipairs({
  "crystal/assets/generated/battle/anims/move_anim_0.png",
  "crystal/assets/generated/battle/anims/move_anim_1.png",
  "crystal/data/generated/battle_anims.lua",
  "crystal/assets/generated/trade/game_boy.png",
}) do
  eq(crystalSeen[path], nil, "crystal does not wait on " .. path)
end

check(redSeen["assets/generated/battle/anims/move_anim_0.png"] == true,
  "red still requires the Gen 1 battle anim sheet")
eq(redSeen["assets/generated/title/crystal_logo.png"], nil,
  "and none of Crystal's title art")

-- ------- 7. script dialect

local crystalTable = Opcodes.forEdition("crystal")
local goldTable = Opcodes.forEdition("gold")
check(crystalTable ~= goldTable,
  "forEdition('crystal') is not the Gold table")
eq(Opcodes.forEdition("silver"), goldTable, "Silver shares Gold's table")
eq(goldTable, Opcodes, "and Gold's table is the module itself")
eq(Opcodes.forEdition(nil), Opcodes, "an absent edition falls back to Gold")

-- pokecrystal/macros/scripts/events.asm:541
eq(crystalTable[0x52] and crystalTable[0x52].name, "farjumptext",
  "Crystal $52 is farjumptext")
eq(goldTable[0x52] and goldTable[0x52].name, "jumptext",
  "Gold $52 is jumptext")
eq(crystalTable[0x53] and crystalTable[0x53].name, "jumptext",
  "and Crystal's jumptext moved to $53")

local function count(tbl)
  local n = 0
  for key in pairs(tbl) do if type(key) == "number" then n = n + 1 end end
  return n
end
eq(count(crystalTable), 170, "Crystal names 170 commands")
eq(count(goldTable), 162, "Gold names 162")

local diverged
for byte = 0x00, 0x51 do
  local a = crystalTable[byte] and crystalTable[byte].name
  local b = goldTable[byte] and goldTable[byte].name
  if a ~= b then diverged = byte; break end
end
eq(diverged, nil, "$00-$51 are the same commands in both dialects")

check(Opcodes.TERMINATORS.farjumptext == true,
  "farjumptext is a terminator")

-- ------- 8. the launcher reaches the crystal tab

local RomImporter = require("src.import.RomImporter")

local visited = {}
local fake = setmetatable({ tab = GameVersion.ORDER[1] }, RomImporter)
fake._switchTab = function(self, id)
  self.tab = id
  visited[#visited + 1] = id
end

for _ = 1, 12 do fake:_cycleTab(1) end
local sawCrystal, sawMods, sawBug = false, false, false
for _, id in ipairs(visited) do
  if id == "crystal" then sawCrystal = true end
  if id == "mods" then sawMods = true end
  if id == "bug" then sawBug = true end
end
check(sawCrystal, "cycling the launcher tabs reaches crystal")
check(sawMods and sawBug, "and still reaches the mods and bug tabs")

local seen, cycle = {}, 0
fake.tab = "crystal"
repeat
  seen[fake.tab] = true
  fake:_cycleTab(1)
  cycle = cycle + 1
until fake.tab == "crystal" or cycle > 40
eq(cycle, #GameVersion.ORDER + 4,
  "the ring is the six games plus mods/find/skins/bug")

fake.tab = "crystal"
fake:_cycleTab(-1)
eq(fake.tab, "silver", "and stepping back off crystal lands on silver")

S.finish()
