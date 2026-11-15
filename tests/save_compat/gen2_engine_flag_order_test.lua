package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Gen2EngineFlags = require("src.save_convert.Gen2EngineFlags")
local CacheConstants = require("tests.cache_gen2_constants")
local G2 = require("tests.fixtures.save.gen2_build")
local K = require("tests.save_compat._codec")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2State = require("src.save_convert.Gen2State")

local ORDER = Gen2EngineFlags.ORDER

for _, family in ipairs({ "gs", "crystal" }) do
  local list, seen = ORDER[family], {}
  local n = 0
  for id, name in pairs(list) do
    n = n + 1
    check(type(id) == "number" and id >= 0 and type(name) == "string" and name:match("^ENGINE_"),
      family .. " row " .. tostring(id) .. " is an ENGINE_ name")
    check(not seen[name], family .. " " .. tostring(name) .. " appears once")
    seen[name] = true
  end
  for id = 0, n - 1 do check(list[id] ~= nil, family .. " has no hole at " .. id) end
end
eq(#ORDER.gs + 1, 93, "pokegold constants/engine_flags.asm has 93 ENGINE_ constants")
eq(#ORDER.crystal + 1, 162, "pokecrystal constants/engine_flags.asm has 162")
eq(ORDER.crystal[16], "ENGINE_MOBILE_SYSTEM", "Crystal inserts ENGINE_MOBILE_SYSTEM at 16")
eq(Gen2EngineFlags.id("gold", "ENGINE_FLYPOINT_PLAYERS_HOUSE"), 50, "Gold's first fly point is 50")
eq(Gen2EngineFlags.id("silver", "ENGINE_FLYPOINT_PLAYERS_HOUSE"), 50, "Silver reads Gold's order")
eq(Gen2EngineFlags.id("crystal", "ENGINE_FLYPOINT_PLAYERS_HOUSE"), 51, "Crystal's is 51")
eq(Gen2EngineFlags.id("crystal", "ENGINE_FOREST_IS_RESTLESS"), 100, "ENGINE_FOREST_IS_RESTLESS is 100")
check(not pcall(Gen2EngineFlags.id, "gold", "ENGINE_FOREST_IS_RESTLESS"),
  "Gold has no ENGINE_FOREST_IS_RESTLESS, and asking for it is an error")

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local constants, root = CacheConstants.load(version)
  if not constants then
    print("[skip] no " .. version .. " cache: engineFlagOrder equality not checked")
  else
    local order = constants.engineFlagOrder
    check(type(order) == "table", version .. " cache carries engineFlagOrder (" .. root .. ")")
    local list = ORDER[Gen2EngineFlags.family(version)]
    eq(#(order or {}), #list + 1, version .. ": the save-format table and the cache list as many flags")
    local diff = 0
    for i, name in ipairs(order or {}) do
      if list[i - 1] ~= name then diff = diff + 1 end
    end
    eq(diff, 0, version .. ": every save-format engine flag sits at the cache's engineFlagOrder index")
  end
end

local function setBit(s, at, bit)
  local b = {}
  for i = 1, #s do b[i - 1] = s:byte(i) end
  b[at] = (b[at] or 0) + 2 ^ bit
  return b
end

local function pack(b)
  local parts = {}
  for i = 0, G2.SIZE - 1 do parts[#parts + 1] = string.char(b[i] or 0) end
  return table.concat(parts)
end

-- pokecrystal data/events/engine_flags.asm:133, :108, :199; pokegold :107
local CASES = {
  { "crystal", "wCelebiEvent", 2, "ENGINE_FOREST_IS_RESTLESS" },
  { "crystal", "wDailyFlags1", 0, "ENGINE_KURT_MAKING_BALLS" },
  { "crystal", "wSwarmFlags", 2, "ENGINE_DUNSPARCE_SWARM" },
  { "crystal", "wBikeFlags", 1, "ENGINE_ALWAYS_ON_BIKE" },
  { "crystal", "wStatusFlags2", 6, "ENGINE_REACHED_GOLDENROD" },
  { "gold", "wDailyFlags1", 0, "ENGINE_KURT_MAKING_BALLS" },
  { "gold", "wBikeFlags", 1, "ENGINE_ALWAYS_ON_BIKE" },
  { "gold", "wStatusFlags2", 6, "ENGINE_REACHED_GOLDENROD" },
}

for _, c in ipairs(CASES) do
  local version, label, bit, name = c[1], c[2], c[3], c[4]
  local S = Gen2State.symsFor(version)
  local blank = G2.build({ version = version })
  local b = setBit(blank, S[label], bit)
  G2.seal(b, version)
  local save = Gen2Save.decode(pack(b), version, K.gen2Data)
  local id = Gen2EngineFlags.id(version, name)
  check(save and save.engineFlags and save.engineFlags[id] == true,
    ("%s import: %s bit %d is %s (%d)"):format(version, label, bit, name, id))

  local base = assert(Gen2Save.decode(blank, version, K.gen2Data))
  base.engineFlags = base.engineFlags or {}
  base.engineFlags[id] = true
  local out = assert(Gen2Save.encode(base, version, blank, K.gen2Data))
  local byte = out:byte(S[label] + 1)
  check(math.floor(byte / 2 ^ bit) % 2 == 1,
    ("%s export: %s (%d) sets %s bit %d"):format(version, name, id, label, bit))
end

T.finish()
