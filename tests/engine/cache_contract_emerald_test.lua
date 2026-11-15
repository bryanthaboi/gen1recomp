package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local CacheContract = require("src.import.CacheContract")

local SHA = "f3ae088181bf583e55daf962a92bb46f4f1d07b7"

local function digest(list)
  local h = 0
  for _, p in ipairs(list) do
    for i = 1, #p do h = (h * 31 + p:byte(i)) % 4294967291 end
    h = (h * 31 + 10) % 4294967291
  end
  return h
end

eq(CacheContract.markerFor("emerald", SHA), "rom-cache-v5-emerald:" .. SHA, "emerald marker")
check(CacheContract.markerMatches("emerald", "rom-cache-v5-emerald:" .. SHA), "emerald marker matches")
check(not CacheContract.markerMatches("emerald", "rom-cache-v17-firered:" .. SHA), "a FireRed marker does not")

eq(#CacheContract.requiredFiles("firered"), 487, "FireRed required list size")
eq(digest(CacheContract.requiredFiles("firered")), 973901655, "FireRed required list")
eq(#CacheContract.requiredFiles("leafgreen"), 488, "LeafGreen required list size")
eq(digest(CacheContract.requiredFiles("leafgreen")), 2859500251, "LeafGreen required list")
eq(digest(CacheContract.requiredFiles("firered", true)), 243231348, "FireRed semantic list")
eq(digest(CacheContract.requiredFiles("leafgreen", true)), 3356429722, "LeafGreen semantic list")

local em, isOverride = CacheContract.requiredFilesFor("emerald")
check(isOverride == true, "emerald is a composed list, not the gen 1 list")
local set = {}
for _, p in ipairs(em) do set[p] = true end
for _, p in ipairs(CacheContract.PLAN_CORE_FILES) do
  check(set[p], "emerald requires core file " .. p)
end
local core = {}
for _, p in ipairs(CacheContract.PLAN_CORE_FILES) do core[p] = true end
for _, p in ipairs(CacheContract.REQUIRED_FILES) do
  if not core[p] then check(not set[p], "emerald does not require gen 1 file " .. p) end
end
for _, p in ipairs(em) do
  for _, bad in ipairs({ "fame_checker", "teachy_tv", "trainer_tower", "seagallop", "/help/", "quest_log" }) do
    check(not p:find(bad, 1, true), "emerald requires no FRLG-only path " .. p)
  end
end

local Plans = require("src.import.gba.plans.registry")
local plan = Plans.of("emerald")
eq(plan.id, "rse", "emerald imports through the rse plan")
eq(Plans.of("firered").id, "frlg", "firered imports through the frlg plan")
for _, module in ipairs(Plans.modules(plan)) do
  local mod = require(module)
  for _, rel in ipairs(mod.REQUIRED or {}) do
    local path = (rel:match("^data/") or rel:match("^assets/")) and rel or ("data/generated/gba/" .. rel)
    check(set[path], module .. " REQUIRED " .. rel .. " is in the emerald contract")
  end
end

local function memfs(files)
  local fs = { prefix = "" }
  function fs.read(rel) return files[fs.prefix .. rel] end
  function fs.exists(rel) return files[fs.prefix .. rel] ~= nil end
  return fs
end
local Frlg = require("src.import.gba.versions_frlg")
local Em = require("src.import.gba.games.emerald")
local emMeta = '{"cache_version":' .. Em.CACHE_VERSION .. '}'
local frMeta = '{"cache_version":' .. Frlg.CACHE_VERSION .. '}'
local fs = memfs({
  ["emerald/data/generated/gba/meta.json"] = emMeta,
  ["firered/data/generated/gba/meta.json"] = frMeta,
})
check(CacheContract.cacheVersionCurrent("emerald", fs), "an emerald meta stamped with the emerald stamp is current")
check(CacheContract.cacheVersionCurrent("firered", fs), "a firered meta stamped with the firered stamp is current")
local prev = Frlg.CACHE_VERSION
Frlg.CACHE_VERSION = prev + 1
check(CacheContract.cacheVersionCurrent("emerald", fs), "bumping the FireRed stamp leaves emerald current")
check(not CacheContract.cacheVersionCurrent("firered", fs), "bumping the FireRed stamp stales firered")
Frlg.CACHE_VERSION = prev
local stale = memfs({ ["emerald/data/generated/gba/meta.json"] = frMeta })
check(not CacheContract.cacheVersionCurrent("emerald", stale), "an emerald meta with the FireRed stamp is stale")

local complete = {}
for _, p in ipairs(em) do complete["emerald/" .. p] = "x" end
complete["emerald/" .. CacheContract.MARKER_PATH] = "rom-cache-v5-emerald:" .. SHA
complete["emerald/data/generated/gba/meta.json"] = emMeta
check(CacheContract.isReady("emerald", memfs(complete)), "a complete emerald cache is ready")

T.finish("cache_contract_emerald_test")
