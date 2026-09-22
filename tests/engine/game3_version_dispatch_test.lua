package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Schemas = require("src.mods.Schemas")
local Loader = require("src.mods.Loader")

local prevVersion = GameVersion.get()

eq(Loader.apiModule("battle", 3, nil), "src.battle.game3.BattleAPI",
  "gen3 battle facade default is the FireRed-backed module")
eq(Loader.apiModule("world", 3, nil), "src.world.game3.WorldAPI",
  "gen3 world facade default is the FireRed-backed module")
eq(Loader.apiModule("battle", 3, "firered"), "src.battle.game3.BattleAPI",
  "firered resolves the FireRed-backed facade")
eq(Loader.apiModule("battle", 3, "leafgreen"), "src.battle.game3.BattleAPI",
  "leafgreen shares the FireRed-backed facade")
eq(Loader.apiModule("world", 3, "leafgreen"), "src.world.game3.WorldAPI",
  "leafgreen world facade")
eq(Loader.apiModule("battle", 3, "ruby"), "src.battle.game3.BattleAPI",
  "an RSE id with no row falls back to the FireRed-backed facade")
eq(Loader.apiModule("world", 3, "not-a-game"), "src.world.game3.WorldAPI",
  "an unknown id falls back to the FireRed-backed facade")

eq(Loader.apiModule("battle", 2, nil), "src.battle.gen2.BattleAPI", "gen2 battle facade")
eq(Loader.apiModule("world", 2, nil), "src.world.gen2.WorldAPI", "gen2 world facade")
eq(Loader.apiModule("battle", 1, nil), "src.battle.BattleAPI", "gen1 battle facade")
eq(Loader.apiModule("world", 1, nil), "src.world.WorldAPI", "gen1 world facade")

check(Schemas.routing(3, nil) == Schemas.GEN3, "gen3 routing without a version is GEN3")
check(Schemas.routing(3, "firered") == Schemas.GEN3, "firered has no overlay, so GEN3")
check(Schemas.routing(3, "ruby") == Schemas.GEN3, "an overlay-less RSE id reads GEN3")
check(Schemas.routing(2, nil) == Schemas.GEN2, "gen2 routing unchanged")
check(Schemas.routing(1, nil) == Schemas.GEN1, "gen1 routing unchanged")

local spec = Schemas.REGISTRIES.pokemon
check(spec ~= nil, "the pokemon registry spec exists to test against")
eq(Schemas.targetFor("pokemon", spec, 3, "firered"), "gen3Pokemon",
  "firered routes pokemon to the shared gen3Pokemon root")
eq(Schemas.targetFor("pokemon", spec, 3, "ruby"), "gen3Pokemon",
  "an overlay-less RSE id routes pokemon to the shared root")
check(Schemas.gatedFor("pokemon", 3, "firered") == false, "pokemon is not gated under FireRed")

Schemas.GEN3_ROUTING["testgame"] = { pokemon = "gen3PokemonTest", moves = false }
local routed = Schemas.routing(3, "testgame")
check(routed ~= Schemas.GEN3, "an overlay produces a distinct merged view")
eq(routed.pokemon, "gen3PokemonTest", "the overlay's row wins")
eq(routed.moves, false, "the overlay can gate a registry")
eq(routed.items, Schemas.GEN3.items, "registries the overlay omits are inherited")
eq(Schemas.targetFor("pokemon", spec, 3, "testgame"), "gen3PokemonTest",
  "targetFor consults the overlay")
check(Schemas.gatedFor("moves", 3, "testgame") == true,
  "the overlay can gate a registry the default leaves open")
check(Schemas.gatedFor("moves", 3, "firered") == false,
  "the default view is untouched by the overlay")
check(Schemas.routing(3, "firered") == Schemas.GEN3, "the merged view is never written back")
Schemas.GEN3_ROUTING["testgame"] = nil

local probe = { measure = function() return 1 end }
package.loaded["tests.dispatch_probe"] = probe
Schemas.GEN3_LIVE_MODULES["testgame"] = { gen3Pokemon = "tests.dispatch_probe" }
check(Schemas.liveModuleFor("gen3Pokemon", "testgame") == probe,
  "a version overlay selects its own live module")
check(Schemas.liveModuleFor("gen3Pokemon", "firered") ~= probe,
  "the FireRed live module is unaffected")
Schemas.GEN3_LIVE_MODULES["testgame"] = nil
package.loaded["tests.dispatch_probe"] = nil

local data = { gen3Pokemon = { names = {} } }
Schemas.bindGen3(data, "testgame")
eq(Schemas.boundVersion(data), "testgame", "bindGen3 records the version id")
local legacy = { gen3Pokemon = { names = {} } }
Schemas.bindGen3(legacy)
eq(Schemas.boundVersion(legacy), nil, "a version-less bind reports nil")

local function memfs(files)
  return {
    read = function(_, path) return files[path] end,
    write = function(_, path, data) files[path] = data; return true end,
    getInfo = function(_, path) return files[path] and { type = "file" } or nil end,
    getDirectoryItems = function()
      local items = {}
      for key in pairs(files) do items[#items + 1] = key end
      table.sort(items)
      return items
    end,
  }
end

GameVersion.set("firered")
local loader = Loader.new({ fs = memfs({}) })
eq(loader.generation, 3, "a Gen 3 boot builds a Gen 3 loader")
eq(loader.version, "firered", "the loader carries the active game id")

local injected = Loader.new({ fs = memfs({}), generation = 3, version = "testgame" })
eq(injected.version, "testgame", "opts.version is the test seam")
eq(Loader.apiModule("world", injected.generation, injected.version), "src.world.game3.WorldAPI",
  "an injected game with no row still resolves the default facade")

GameVersion.set(prevVersion)
T.finish("game3_version_dispatch_test")
