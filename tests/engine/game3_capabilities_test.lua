package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Capabilities = require("src.core.game3.capabilities")
local FireredProfile = require("src.core.game3.profiles.firered")

local prevVersion = GameVersion.get()

for name, value in pairs(Capabilities.NAMES) do
  check(value == true, "NAMES." .. name .. " is a legal flag")
end

local function subset(inner, outer, label)
  for key in pairs(inner) do
    check(outer[key] ~= nil, label .. " carries " .. key)
  end
end

for key in pairs(Capabilities.CORE) do
  check(Capabilities.NAMES[key] ~= nil, "CORE flag " .. key .. " is legal")
  check(Capabilities.FRLG[key] ~= nil, "CORE flag " .. key .. " is in FRLG")
  check(Capabilities.RSE[key] ~= nil, "CORE flag " .. key .. " is in RSE")
end
subset(Capabilities.FRLG, Capabilities.NAMES, "FRLG")
subset(Capabilities.RSE, Capabilities.NAMES, "RSE")
for key in pairs(Capabilities.FRLG) do
  check(Capabilities.RSE[key] == nil or Capabilities.CORE[key] ~= nil,
    "FRLG-only flag " .. key .. " is not shared with RSE")
end

GameVersion.set("firered")
local row = FireredProfile
local okAudit, problems = Capabilities.audit(row.capabilities)
check(okAudit, "the FireRed capability row audits clean"
  .. (okAudit and "" or (": " .. table.concat(problems, "; "))))

for key in pairs(Capabilities.FRLG) do
  check(row.capabilities[key] == true, "FireRed row enables FRLG flag " .. key)
end
for _, rseOnly in ipairs({ "contests", "secretBase", "matchCall", "pokeNav", "battleTower" }) do
  check(row.capabilities[rseOnly] == nil, "FireRed row leaves RSE flag " .. rseOnly .. " unset")
end

local function fileExists(rel)
  local f = io.open(rel, "r")
  if f then f:close() return true end
  return false
end

local function modulePath(value)
  if value:sub(1, 4) == "src." then return (value:gsub("%.", "/") .. ".lua") end
  return "src/core/game3/scripting/" .. value .. ".lua"
end

for id, feature in pairs(Capabilities.FEATURES) do
  check(Capabilities.NAMES[feature.cap] ~= nil, id .. " maps to a legal flag")
  check(type(feature.label) == "string" and #feature.label > 0, id .. " has a label")
  local repo, rel = feature.source:match("^(%w+)/(.+)$")
  check(repo ~= nil and rel ~= nil, id .. " cites a pret repo + path")
  check(type(feature.counterpart) == "string" and #feature.counterpart > 0,
    id .. " records the counterpart check")
  for _, field in ipairs({ "core", "ui", "data", "natives" }) do
    local value = feature[field]
    if value then
      check(fileExists(modulePath(value)), id .. "." .. field .. " exists: " .. modulePath(value))
    end
  end
  if feature.extractor then
    check(fileExists("src/import/gba/" .. feature.extractor .. ".lua"),
      id .. ".extractor exists: src/import/gba/" .. feature.extractor .. ".lua")
  end
end

for _, id in ipairs({ "fame_checker", "teachy_tv", "vs_seeker", "trainer_tower", "seagallop" }) do
  check(Capabilities.FEATURES[id] ~= nil, "feature registered: " .. id)
  check(Capabilities.FRLG[Capabilities.FEATURES[id].cap] == true,
    "feature is in the FRLG set: " .. id)
end

local repoCloned = {}
do
  for _, feature in pairs(Capabilities.FEATURES) do
    local repo, rel = feature.source:match("^(%w+)/(.+)$")
    if repo and not repoCloned[repo] then
      repoCloned[repo] = fileExists("../" .. repo .. "/Makefile")
        or fileExists("../" .. repo .. "/README.md")
    end
    if repo and repoCloned[repo] then
      check(fileExists("../" .. repo .. "/" .. rel),
        "pret source exists for " .. feature.cap .. ": " .. feature.source)
    end
  end
end

eq(Capabilities.has({ version = "firered" }, "fameChecker"), true,
  "FireRed has the Fame Checker")
eq(Capabilities.has({ version = "firered" }, "contests"), false,
  "FireRed has no contests")
eq(Capabilities.has({ version = "firered" }, "noSuchFlag"), false,
  "an unknown flag reads false, not nil")
eq(Capabilities.gate({ version = "firered" }, "fame_checker"), true,
  "the Fame Checker gate is open on FireRed")
eq(Capabilities.gate({ version = "firered" }, "tm_case"), true,
  "the TM Case gate is open on FireRed")
eq(Capabilities.gate({ version = "firered" }, "contests"), false,
  "an unknown feature id reads false (and warns once)")

eq(Capabilities.gate({ version = "ruby" }, "fame_checker"), true,
  "an RSE id without a profile fails closed to FireRed")

eq(Capabilities.enabled({ vsSeeker = false }, "vs_seeker"), false,
  "enabled() reads the feature's own flag")
eq(Capabilities.enabled(Capabilities.FRLG, "fame_checker"), true,
  "enabled() accepts a composed set")
eq(Capabilities.enabled(Capabilities.RSE, "fame_checker"), false,
  "the RSE set has no Fame Checker")
eq(Capabilities.enabled(Capabilities.RSE, "contests"), true,
  "the RSE set has contests")
eq(Capabilities.enabled(nil, "fame_checker"), false, "nil caps is false")
eq(Capabilities.enabled({}, "no_such_feature"), false, "an unknown feature is false")

eq(Capabilities.nativeFeature("natives_fame"), "fame_checker",
  "the Fame Checker natives module maps to its feature")
eq(Capabilities.nativeFeature("natives_tower"), "trainer_tower",
  "the tower natives module maps to its feature")
eq(Capabilities.nativeFeature("natives_queries"), nil,
  "an unmapped natives module is shared")
eq(Capabilities.nativeAllowed({ version = "firered" }, "natives_fame"), true,
  "FireRed allows the Fame Checker natives module")
eq(Capabilities.nativeAllowed({ version = "firered" }, "natives_queries"), true,
  "shared natives modules are always allowed")
eq(Capabilities.nativeAllowed({ version = "firered" }, "natives_bogus"), true,
  "an unknown module name is treated as shared, not gated")
eq(Capabilities.nativeAllowed({ version = "firered" }, nil), true,
  "a nil module name is shared")

local okBad, badProblems = Capabilities.audit({ bogusFlag = true })
check(okBad == false, "audit rejects an unknown flag")
check(#badProblems == 1 and badProblems[1]:find("bogusFlag", 1, true) ~= nil,
  "audit names the offending flag")

local okType, typeProblems = Capabilities.audit({ fameChecker = 1 })
check(okType == false, "audit rejects a non-boolean flag")
check(#typeProblems == 1 and typeProblems[1]:find("fameChecker", 1, true) ~= nil,
  "audit names the non-boolean flag")

local okNil, nilProblems = Capabilities.audit(nil)
check(okNil == false, "audit rejects a missing table")
eq(#nilProblems, 1, "a missing table is one problem")

check(Capabilities.audit(Capabilities.RSE) == true, "the RSE set audits clean")

Capabilities.reset()
GameVersion.set(prevVersion)
T.finish("game3_capabilities_test")
