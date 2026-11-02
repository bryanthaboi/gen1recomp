local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")
local BugContest = require("src.core.gen2.BugContest")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_bug_contest_mod_encounters_3090"

return function(game)
  U.wait(45)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local world, save = game.world, game.save
  if not check(world and world.map and save, "3090_world_booted") then
    love.event.quit(1)
    return
  end

  local vanilla = game.data.gen2Encounters and game.data.gen2Encounters.bugContest
  check(type(vanilla) == "table" and #vanilla == 11, "3090_cache_has_contest_mons")
  check(BugContest.contestMons(game.data) == vanilla, "3090_contest_reads_cache_table")

  local files = {
    ["mods/probe/manifest.json"] = '{"id":"probe","name":"probe","version":"1.0.0",'
      .. '"api":2,"games":["all"],"entry":"main.lua"}',
    ["mods/probe/main.lua"] = [[local mod = ...
mod.content.encounters:override("bugContest", {
  { chance = 100, species = "SCYTHER", min = 20, max = 20 },
})]],
  }
  local loader = Loader.new({ fs = Sdk.memfs(files), generation = 2,
    version = save.version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  check(not (loader.mods.probe and loader.mods.probe.failed), "3090_override_loads")
  game.data.gen2Encounters = data.gen2Encounters

  save.party = save.party and #save.party > 0 and save.party
    or { { species = "CYNDAQUIL", name = "CYNDAQUIL", level = 10, hp = 30, maxHp = 30 } }
  BugContest.start(save)
  world:warpToMapId("NATIONAL_PARK", 10, 20, "down")
  U.wait(45)
  check(world.map and world.map.def and world.map.def.id == "NATIONAL_PARK", "3090_in_park")

  local captured
  local startBattle = world.startBattle
  world.startBattle = function(self, opts, onDone)
    captured = opts
    return startBattle(self, opts, onDone)
  end
  local realRandom = BugContest.random
  BugContest.random = function() return 0 end
  local started = world:tryContestEncounter(0x18)
  BugContest.random = realRandom
  world.startBattle = startBattle

  check(started == true, "3090_contest_encounter_started")
  local wild = captured and captured.wild
  check(wild and wild.species == "SCYTHER", "3090_mod_species_rolled")
  check(wild and wild.level == 20, "3090_mod_level_rolled")
  check(captured and captured.contest == true, "3090_contest_battle")
  local battle
  for _ = 1, 600 do
    local top = game.stack and game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  check(battle ~= nil, "3090_battle_on_stack")
  U.wait(360)
  U.still(game, SHOT_DIR .. "/3090_01_contest_scyther.png")

  love.event.quit(failures == 0 and 0 or 1)
end
