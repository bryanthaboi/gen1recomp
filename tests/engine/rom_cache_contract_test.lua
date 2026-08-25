-- The cache contract is the shared Lua-side publication boundary.  A writer
-- may stage outputs in any order, but readiness is published only after the
-- version-specific required set exists.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq
local CacheContract = require("src.import.CacheContract")

local fs = { prefix = "initial/", files = {} }
local writes = {}
function fs.exists(path)
  return fs.files[fs.prefix .. path] ~= nil
end
function fs.read(path)
  return fs.files[fs.prefix .. path]
end
function fs.write(path, value)
  writes[#writes + 1] = fs.prefix .. path
  fs.files[fs.prefix .. path] = value
  return true
end
function fs.remove(path)
  fs.files[fs.prefix .. path] = nil
end

local required, isOverride = CacheContract.requiredFilesFor("red")
check(not isOverride, "Red uses the shared required-file list")
check(#required > 0, "Red has required outputs")
eq(CacheContract.markerFor("red"),
  CacheContract.FORMAT .. "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
  "marker contains format and Red SHA-1")

for index = 1, #required - 1 do
  fs.files["red/" .. required[index]] = true
end
local complete, missing = CacheContract.allRequiredFilesExist("red", fs)
check(not complete, "missing output keeps cache incomplete")
eq(missing, required[#required], "missing output is reported")
local published, publishError = CacheContract.publish("red", fs)
check(not published, "incomplete cache is not published")
check(publishError ~= nil, "incomplete publication explains the missing output")
check(fs.files["red/" .. CacheContract.MARKER_PATH] == nil,
  "incomplete cache has no completion marker")

-- Publication must remove a stale marker left by an interrupted replacement,
-- and must restore the caller prefix on both the success and failure paths.
fs.files["red/" .. CacheContract.MARKER_PATH] = "old-marker"
local removedMarker = CacheContract.publish("red", fs)
check(not removedMarker, "incomplete retry is still rejected")
check(fs.files["red/" .. CacheContract.MARKER_PATH] == nil,
  "incomplete retry removes a stale completion marker")
eq(fs.prefix, "initial/", "incomplete publication restores the caller prefix")

fs.files["red/" .. required[#required]] = true
fs.prefix = "caller/prefix/"
fs.files["red/" .. required[#required]] = true
for _, path in ipairs(required) do fs.files["red/" .. path] = true end
published, publishError = CacheContract.publish("red", fs)
check(published, "complete cache is published")
eq(publishError, nil, "complete publication has no error")
eq(fs.prefix, "caller/prefix/", "publication restores the caller prefix")
eq(fs.files["red/" .. CacheContract.MARKER_PATH], CacheContract.markerFor("red"),
  "marker is written under the version prefix")
local marker = CacheContract.readMarker("red", fs)
eq(marker, CacheContract.markerFor("red"), "marker reads through the version prefix")
eq(writes[#writes], "red/" .. CacheContract.MARKER_PATH,
  "the marker is the only publication write and comes last")

-- Every supported version gets its own marker and complete cache semantics;
-- Yellow adds its three outputs, while Gold/Silver replace the Gen 1 set.
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver" }) do
  local versionFiles, override = CacheContract.requiredFilesFor(version)
  for _, path in ipairs(versionFiles) do
    fs.files[version .. "/" .. path] = true
  end
  if not override then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      fs.files[version .. "/" .. path] = true
    end
  end
  local ready, missing = CacheContract.allRequiredFilesExist(version, fs)
  check(ready, version .. " complete cache is ready (" .. tostring(missing) .. ")")
  local didPublish = CacheContract.publish(version, fs)
  check(didPublish, version .. " complete cache publishes")
  eq(fs.files[version .. "/" .. CacheContract.MARKER_PATH],
    CacheContract.markerFor(version), version .. " marker is version-scoped")
  eq(fs.prefix, "caller/prefix/", version .. " publication restores prefix")
  check(CacheContract.isReady(version, fs), version .. " complete cache is ready")
end

local gold, goldOverride = CacheContract.requiredFilesFor("gold")
check(goldOverride, "Gold uses a version-specific required set")
local goldSet = {}
for _, path in ipairs(gold) do goldSet[path] = true end
check(goldSet["assets/generated/battle/hud/balls.png"],
  "Gold required set includes trainer HUD art")
check(not goldSet["assets/generated/trade/game_boy.png"],
  "Gold required set excludes Gen 1 trade art")
check(goldSet["data/generated/rom_text.lua"],
  "Gold required set includes the Gen 2 engine text table")
local silver = CacheContract.requiredFilesFor("silver")
local silverSet = {}
for _, path in ipairs(silver) do silverSet[path] = true end
check(silverSet["data/generated/rom_text.lua"],
  "Silver required set includes the Gen 2 engine text table")
check(not silverSet["assets/generated/trade/game_boy.png"],
  "Silver required set excludes Gen 1 trade art")
check(CacheContract.VERSION_REQUIRED_FILES.yellow ~= nil,
  "Yellow has version-specific required outputs")

-- Revisioned cache markers: Crystal accepts either the 1.0 or the 1.1 cart.
local CRYSTAL_1_0 = "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133"
local CRYSTAL_1_1 = "f2f52230b536214ef7c9924f483392993e226cfb"

local CRYSTAL_FORMAT = CacheContract.formatFor("crystal")

eq(CacheContract.markerFor("crystal", CRYSTAL_1_1),
  CRYSTAL_FORMAT .. CRYSTAL_1_1,
  "markerFor with an explicit sha1 uses that sha1, not the canonical one")
eq(CacheContract.markerFor("crystal"), CRYSTAL_FORMAT .. CRYSTAL_1_0,
  "markerFor with no sha1 still defaults to the canonical (1.0) sha1")

check(CacheContract.markerMatches("crystal", CRYSTAL_FORMAT .. CRYSTAL_1_0),
  "a marker written from the 1.0 hash matches crystal")
check(CacheContract.markerMatches("crystal", CRYSTAL_FORMAT .. CRYSTAL_1_1),
  "a marker written from the 1.1 hash also matches crystal")
check(not CacheContract.markerMatches("crystal",
  CRYSTAL_FORMAT .. "ea9bcae617fdf159b045185467ae58b2e4a48b9a"),
  "a marker written from Red's hash does not match crystal")
check(not CacheContract.markerMatches("red", CRYSTAL_FORMAT .. CRYSTAL_1_1),
  "a marker written from Crystal's 1.1 hash does not match red")
check(not CacheContract.markerMatches("crystal",
  CacheContract.FORMAT .. CRYSTAL_1_0),
  "a crystal marker written on the shared format no longer matches")

local crystalFs = { prefix = "crystal-marker-test/", files = {} }
function crystalFs.exists(path) return crystalFs.files[crystalFs.prefix .. path] ~= nil end
function crystalFs.read(path) return crystalFs.files[crystalFs.prefix .. path] end
function crystalFs.write(path, value)
  crystalFs.files[crystalFs.prefix .. path] = value
  return true
end
function crystalFs.remove(path) crystalFs.files[crystalFs.prefix .. path] = nil end

local crystalRequired = CacheContract.requiredFilesFor("crystal")
for _, path in ipairs(crystalRequired) do
  crystalFs.files["crystal/" .. path] = true
end
local published11 = CacheContract.publish("crystal", crystalFs, CRYSTAL_1_1)
check(published11, "publishing with the 1.1 sha1 succeeds")
eq(crystalFs.files["crystal/" .. CacheContract.MARKER_PATH],
  CRYSTAL_FORMAT .. CRYSTAL_1_1, "the marker records the 1.1 sha1")
check(CacheContract.isReady("crystal", crystalFs),
  "a cache published with the 1.1 sha1 still reads ready for crystal")

crystalFs.files["crystal/" .. CacheContract.MARKER_PATH] =
  CacheContract.FORMAT .. "ea9bcae617fdf159b045185467ae58b2e4a48b9a"
check(not CacheContract.isReady("crystal", crystalFs),
  "a marker from another version's hash does not read ready for crystal")

check(CacheContract.markerMatches("blue", CacheContract.markerFor("blue")),
  "blue's own marker still matches blue")
check(not CacheContract.markerMatches("blue", CacheContract.markerFor("red")),
  "red's marker still does not match blue")

-- A throwing adapter must not strand the process in its temporary prefix.
local throwingFs = { prefix = "before/" }
function throwingFs.exists() error("probe failed") end
local probed, probeError = CacheContract.allRequiredFilesExist("blue", throwingFs)
check(not probed and probeError ~= nil, "filesystem probe errors are returned")
eq(throwingFs.prefix, "before/", "probe errors restore the caller prefix")
function throwingFs.write() error("write failed") end
function throwingFs.remove() end
for _, path in ipairs(CacheContract.REQUIRED_FILES) do
  throwingFs.files = throwingFs.files or {}
  throwingFs.files["blue/" .. path] = true
end
function throwingFs.exists(path)
  return throwingFs.files[throwingFs.prefix .. path] ~= nil
end
local wrote = CacheContract.publish("blue", throwingFs)
check(not wrote, "write errors are returned")
eq(throwingFs.prefix, "before/", "write errors restore the caller prefix")

-- Source-tree readiness must use the same version lists and reject a cache
-- when LÖVE cannot identify a real source directory.
local oldLove = love
love = nil
check(not CacheContract.sourceTreeHasData("red"),
  "source-tree check is safe without LÖVE")
local sourceFiles = {}
love = {
  filesystem = {
    getRealDirectory = function(path) return sourceFiles[path] end,
    getSource = function() return "/source" end,
    getInfo = function(path)
      return sourceFiles[path] and { type = "file" } or nil
    end,
  },
}
for _, path in ipairs(CacheContract.REQUIRED_FILES) do sourceFiles[path] = "/source" end
check(CacheContract.sourceTreeHasData("red"),
  "Red source tree uses the shared required set")
sourceFiles[CacheContract.REQUIRED_FILES[2]] = "/save"
check(not CacheContract.sourceTreeHasData("red"),
  "source-tree readiness rejects a cache-overlaid required file")
sourceFiles = {}
local goldFiles = CacheContract.requiredFilesFor("gold")
for _, path in ipairs(goldFiles) do sourceFiles["gold/" .. path] = "/source" end
check(CacheContract.sourceTreeHasData("gold"),
  "Gold source tree uses its override set")
love = oldLove

-- Both importer completion paths must call the shared publication boundary.
local importerFile = assert(io.open("src/import/RomImporter.lua", "r"))
local importerSource = importerFile:read("*a")
importerFile:close()
local completionCalls = 0
for _ in importerSource:gmatch("CacheContract%.publish%(%s*version") do
  completionCalls = completionCalls + 1
end
eq(completionCalls, 1,
  "both thread and coroutine paths converge on one publishing helper")
check(importerSource:find("self:_completeImport%(version, prefix, displayName%)")
    ~= nil, "coroutine completion uses the shared helper")
check(importerSource:find("pcall%(self%._completeImport") ~= nil,
  "thread completion uses the shared helper")

T.finish("rom cache contract")
