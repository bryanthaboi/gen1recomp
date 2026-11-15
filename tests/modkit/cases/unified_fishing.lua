package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified fishing")
local Sdk = require("tests.modkit.sdk")
local Fixtures = require("tests.modkit.fixtures")
local Merge = require("src.mods.Merge")
local Version = require("src.core.GameVersion")
local ModRuntime = require("src.mods.Runtime")
local OW = require("src.world.OverworldController")
local World2 = require("src.world.gen2.World")
local Map2 = require("src.world.gen2.Map")
local Encounters = require("src.core.game3.encounters")
local Runtime3 = require("src.core.game3.runtime")
local Pokemon3 = require("src.core.game3.pokemon")
local Profile = require("src.core.game3.profile")
local Versions = require("src.import.gba.versions")
local Rng = require("src.core.game3.rng")

local savedVersion, savedNativeVersion = Version.get(), Versions.active()
local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }
local savedRng = Rng.getState()
local rods = { "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }
local species = { "CHARMANDER", "CHARMELEON", "PIDGEY", "MEW" }
local numbers = { CHARMANDER = 4, CHARMELEON = 5, PIDGEY = 16, MEW = 151,
  MAGIKARP = 129, GOLDEEN = 118, POLIWAG = 60 }

local files = {
  ["mods/fishing_probe/manifest.json"] = [[{"id":"fishing_probe","name":"Fishing probe","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/fishing_probe/main.lua"] = [[
    local mod = ...
    local out = mod.exports
    out.mode, out.calls = "observe", 0
    out.install = function()
      return mod.hooks:wrap("encounter.fishing", function(next, rod, map, pool)
        out.calls = out.calls + 1
        out.rod, out.map, out.pool = rod, map, pool
        local changed = pool
        if out.mode == "replace" then
          changed = { { species = "CHARMANDER", level = 17 } }
        elseif out.mode == "append" or out.mode == "cdf" then
          local names = { "CHARMANDER", "CHARMELEON", "PIDGEY", "MEW" }
          changed = {}
          for i = 1, 4 do
            local prior = pool and pool[i]
            changed[i] = { species = names[i], level = 23,
              chance = prior and prior.chance }
            if out.mode == "cdf" then changed[i].chance = i == 4 and 256 or 0 end
          end
        end
        out.result = next(rod, map, changed)
        return out.result
      end)
    end
  ]],
}

local function fixture(version, f)
  Version.set(version)
  if Version.generation() == 2 then require("tests.fixture_data.gen2_engine_flags").bind(version) end
  f.generation, f.restore = Version.generation(), {}
  local function replace(owner, key, value)
    local old = owner[key]
    f.restore[#f.restore + 1] = function() owner[key] = old end
    owner[key] = value
  end
  function f:finish()
    if self.run then self.run.release() end
    for i = #self.restore, 1, -1 do self.restore[i]() end
    OW._setGameForTest(require("src.core.Game"))
  end
  local data = f.generation == 3 and Sdk.gen3Data() or Fixtures.fresh()
  if f.generation < 3 then
    require("src.render.Font").load(data)
    for name, index in pairs(numbers) do
      local def = Merge.deepCopy(data.pokemon.FIXMON_A)
      def.id, def.name, def.index, def.dex = name, name, index, index
      def.baseStats.specialAttack, def.baseStats.specialDefense = 65, 65
      def.levelMoves, def.evolutions = {}, {}
      data.pokemon[name] = def
    end
  end
  local save = { version = version, player = { name = "RED" }, party = {},
    flags = {}, vars = {}, engineFlags = {}, inventory = {}, options = {},
    modData = {}, pokedex = { seen = {}, caught = {} } }
  local game = { data = data, save = save, phase = "field" }
  game.stack = { states = {} }
  function game.stack:push(state) self.states[#self.states + 1] = state end
  function game.stack:top() return self.states[#self.states] end
  function game.stack:pop() return table.remove(self.states) end
  f.game, f.data = game, data
  f.mapId = "FIX_TOWN"

  if f.generation == 1 then
    data.field.superRod = { [f.mapId] = {
      { species = "PIDGEY", level = 5 }, { species = "CHARMANDER", level = 9 },
    } }
    f.world = setmetatable({ map = { id = f.mapId }, player = { facing = "down" } },
      { __index = OW })
    replace(package.loaded, "src.core.Game", game)
    OW._setGameForTest(game)
  elseif f.generation == 2 then
    local world = World2.new(game)
    local def = { id = f.mapId, width = 2, height = 2, blocks = { 1, 1, 1, 1 },
      fishGroup = "FISHGROUP_POND", connections = {}, warps = {} }
    world.maps = { [f.mapId] = def }
    world.map = Map2.new(def, { collision = { [2] = { 0x29, 0x29, 0x29, 0x29 } } })
    world.player = { cellX = 1, cellY = 1, facing = "down" }
    world.constants, world.tod = {}, "DAY"
    f.group = { chance = 256,
      old = { { species = "PIDGEY", level = 5, chance = 256 } },
      good = { { species = "PIDGEY", level = 5, chance = 128 },
        { species = "CHARMANDER", level = 9, chance = 192 },
        { species = 0, level = 0, chance = 256, timeGroup = 1 } },
      super = { { chance = 256,
        day = { species = "PIDGEY", level = 7 },
        nite = { species = "CHARMANDER", level = 19 } } },
    }
    world.encounters = { fishGroups = { FISHGROUP_POND = f.group },
      timeFishGroups = { [1] = { day = { species = "PIDGEY", level = 7 },
        nite = { species = "CHARMANDER", level = 19 } } } }
    f.world, game.world = world, world
    f.originalGroups = Merge.deepCopy(world.encounters)
  else
    Versions.select(version)
    Profile.reset()
    for key, value in pairs(data.gen3Pokemon) do replace(Pokemon3, key, value) end
    replace(Pokemon3, "_byName", { CHARMANDER = 4, CHARMELEON = 5, PIDGEY = 16, MEW = 151 })
    replace(Pokemon3, "_national", { toNational = { [4] = 4, [5] = 5, [16] = 16, [151] = 151 } })
    replace(Runtime3, "active", true)
    replace(Runtime3, "session", save)
    replace(Runtime3, "_game", game)
    game.session = save
    f.mapId = Profile.active().map.enginePrefix .. "OAKS_LAB"
    save.map = f.mapId
    local slots = {}
    for i = 1, 10 do slots[i] = { species = 16, minLevel = 5, maxLevel = 9 } end
    replace(Encounters, "_tables", { [f.mapId] = { fishing = { rate = 100, slots = slots } } })
    replace(Encounters, "_loaded", true)
    replace(Encounters, "_encounterRateBuff", 0)
    replace(Encounters, "_stepsSinceLastEncounter", 0)
    f.slots = slots
  end

  f.run = Sdk.loadMods({ "mods/fishing_probe" }, {
    generation = f.generation, data = data, fs = Sdk.memfs(files),
  })
  f.run.loader.game = game
  f.out = f.run.loader.exports.fishing_probe
  T.eq(#f.run.errors, 0, version .. " same API 3 entry loads")

  function f:roll(rod, seed, direct)
    if love.math.setRandomSeed then love.math.setRandomSeed(seed)
    else math.randomseed(seed) end
    Rng.setState({ value = seed, value2 = 98765, wild = 4321 })
    local enc, outcome
    if self.generation == 1 then
      game.stack.states = {}
      self.world:goFishing(rod)
      local box = game.stack:top()
      T.check(box and box.auto ~= nil, version .. " real controller schedules its cast")
      for i = 1, 16 do
        local name, value = debug.getupvalue(box.onDone, i)
        if not name then break end
        if name == "enc" then enc = value; break end
      end
      T.eq(box.auto.delay, OW.fishAnimFrames(enc ~= nil), version .. " native bite timing")
    elseif self.generation == 2 then
      game.save.pokedex = { seen = {}, caught = {} }
      outcome, enc = self.world:rollFishing(rod)
    else
      Encounters._encounterRateBuff, Encounters._stepsSinceLastEncounter = 0, 0
      local index = rod == "OLD_ROD" and 0 or rod == "GOOD_ROD" and 1 or 2
      if direct then enc = Encounters.rules().rollFishing(self.mapId, index)
      else enc = Encounters.rollFishing(self.mapId, index) end
    end
    local randomState = love.math.getRandomState and love.math.getRandomState() or nil
    local tail = {}
    for i = 1, 8 do tail[i] = love.math.random(0, 65535) end
    return { encounter = enc, outcome = outcome, rng = Rng.getState(), tail = tail,
      randomState = randomState,
      buff = self.generation == 3 and Encounters._encounterRateBuff or nil,
      steps = self.generation == 3 and Encounters._stepsSinceLastEncounter or nil }
  end
end

local function scenario(version, f)
  local out, generation = f.out, f.generation
  for _, rod in ipairs(rods) do
    local stock = {}
    for seed = 1, 32 do
      stock[seed] = f:roll(rod, seed)
      if generation == 3 then
        T.same(stock[seed], f:roll(rod, seed, true), version .. " facade preserves native backend")
      end
    end
    local remove = out.install()
    local raw, removeRaw
    if generation == 2 then
      removeRaw = ModRuntime.hooks:wrap("encounter.fishing", function(next, ...)
        raw = { n = select("#", ...), ... }
        return next(...)
      end, -10000, "native_fishing_probe")
    end
    out.mode = "observe"
    local calls = out.calls
    for seed = 1, 32 do
      T.same(f:roll(rod, seed), stock[seed], version .. " observer keeps result and RNG")
    end
    T.eq(out.calls - calls, 32, version .. " actual consumer invokes the shared hook once")
    T.eq(out.rod, rod, version .. " canonical rod string")
    T.eq(out.map, f.mapId, version .. " actual map reaches the hook")
    if generation == 1 and rod == "OLD_ROD" then
      T.eq(out.pool, nil, version .. " stock always-catch rod has no candidate array")
      T.eq(out.result.species, "MAGIKARP", version .. " stock Old Rod species")
      T.eq(out.result.level, 5, version .. " stock Old Rod level")
    else
      T.check(type(out.pool) == "table" and #out.pool > 0, version .. " selected rod array")
      T.eq(out.pool.old, nil, version .. " array excludes whole-group old list")
      T.eq(out.pool.good, nil, version .. " array excludes whole-group good list")
      T.eq(out.pool.super, nil, version .. " array excludes whole-group super list")
      if rod ~= "SUPER_ROD" or generation ~= 2 then
        T.eq(type(out.pool[1].species), "string", version .. " canonical candidate species")
        T.eq(type(out.pool[1].level), "number", version .. " canonical candidate level")
      end
      if generation == 3 then
        local expected = rod == "OLD_ROD" and 2 or rod == "GOOD_ROD" and 3 or 5
        T.eq(#out.pool, expected, version .. " native numeric rod selects the correct window")
        T.eq(out.pool[#out.pool].chance, 256, version .. " inherited byte CDF ends at 256")
      end
    end
    if generation == 2 then
      T.eq(raw.n, 4, version .. " three-argument next retains native arity")
      T.eq(raw[3], f.group, version .. " observer passes the original native group")
      T.eq(raw[4].encounters, f.world.encounters, version .. " native timed context survives")
      local key = rod == "OLD_ROD" and "old" or rod == "GOOD_ROD" and "good" or "super"
      T.eq(out.pool[#out.pool].chance, 256, version .. " native byte CDF survives")
      f.world.tod = "NITE"
      remove(); removeRaw()
      local night = f:roll(rod, 23)
      remove = out.install()
      T.same(f:roll(rod, 23), night, version .. " three-argument observer retains night rows")
      if rod == "SUPER_ROD" then
        T.eq(out.result.species, "CHARMANDER", version .. " night sentinel resolves through native context")
        T.eq(out.result.level, 19, version .. " night sentinel level survives")
      end
      f.world.tod = "DAY"
      removeRaw = ModRuntime.hooks:wrap("encounter.fishing", function(next, ...)
        raw = { n = select("#", ...), ... }
        return next(...)
      end, -10000, "native_fishing_probe")
      out.mode = "replace"
      f:roll(rod, 23)
      T.neq(raw[3], f.group, version .. " replacement gets a native group copy")
      T.eq(raw[3].chance, f.group.chance, version .. " group bite chance survives replacement")
      for _, other in ipairs({ "old", "good", "super" }) do
        if other ~= key then
          T.same(raw[3][other], f.group[other], version .. " replacement preserves other rod sentinels")
        end
      end
      T.eq(raw.n, 4, version .. " replacement retains trailing context")
      T.eq(raw[4].tod, "DAY", version .. " replacement retains time of day")
    end
    out.mode = "replace"
    for seed = 1, 32 do
      local result = f:roll(rod, seed)
      if generation == 1 and rod == "OLD_ROD" then
        T.same(result, stock[seed], version .. " Old Rod keeps its native always-catch rule")
      else
        T.check(generation == 1 or result.encounter ~= nil,
          version .. " native consumer applies its bite rule")
        if result.encounter then
          T.eq(out.result.species, "CHARMANDER", version .. " downstream canonical species")
          T.eq(out.result.level, 17, version .. " downstream canonical level")
          T.eq(result.encounter.species, generation == 3 and 4 or "CHARMANDER",
            version .. " native consumer receives its own species representation")
          T.eq(result.encounter.level, 17, version .. " native consumer applies replacement level")
        else
          T.eq(out.result, nil, version .. " native no-bite result remains nil downstream")
        end
      end
    end
    if rod == "GOOD_ROD" then
      out.mode = "append"
      local seen = {}
      for seed = 1, 1000 do
        local result = f:roll(rod, seed)
        if result.encounter then
          seen[out.result.species] = true
          T.eq(out.result.level, 23, version .. " four-entry pool applies its level")
        end
      end
      for _, name in ipairs(species) do
        T.eq(seen[name], true, version .. " all four Good Rod candidates eligible: " .. name)
      end
      if generation >= 2 then
        out.mode = "cdf"
        for seed = 1, 32 do
          local result = f:roll(rod, seed)
          T.check(result.encounter ~= nil, version .. " explicit byte CDF produces a catch")
          T.eq(out.result.species, "MEW", version .. " explicit 0/0/0/256 CDF selects its fourth row")
        end
      end
    end
    if removeRaw then removeRaw() end
    remove()
    T.same(f:roll(rod, 1), stock[1], version .. " unsubscribe restores native fishing")
    if generation == 2 then
      T.same(f.world.encounters, f.originalGroups, version .. " full native groups and timed rows stay intact")
    elseif generation == 3 then
      for _, row in ipairs(f.slots) do
        T.same(row, { species = 16, minLevel = 5, maxLevel = 9 }, version .. " native slots stay intact")
      end
    end
    T.eq(#f.run.errors, 0, version .. " callback completes without fallback errors")
  end
end

for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal",
    "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  local f = {}
  local ok, err = xpcall(function()
    fixture(version, f)
    scenario(version, f)
  end, debug.traceback)
  T.check(ok, version .. " native fishing scenario: " .. tostring(err))
  if f.finish then
    local cleaned, why = pcall(function() f:finish() end)
    T.check(cleaned, version .. " fixture cleanup: " .. tostring(why))
  end
end

Versions.select(savedNativeVersion)
Version.set(savedVersion)
Profile.reset()
require("src.render.Font").invalidate()
Rng.setState(savedRng)
ModRuntime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
