-- The end of the game has to hand the controller back.
--
--   GOLD_CACHE=".../gold" luajit tests/gen2_hof_continue_test.lua
--
-- Script_halloffame ends on ReturnFromCredits (engine/overworld/
-- scripting.asm): Script_endall plus MAPSTATUS_DONE, which returns out of
-- OverworldLoop entirely.  FinishContinueFunction (engine/menus/
-- intro_menu.asm) then reads wSpawnAfterChampion:
--
--   SPAWN_RED       SpawnAfterRed: wDefaultSpawnpoint = SPAWN_MT_SILVER,
--                   clear the byte, MAPSETUP_WARP, loop back into the
--                   overworld -- play resumes outside Silver Cave.
--   anything else   `jp Reset` -- the champion's credits end on the title
--                   screen, and the induction's SaveGameData already put
--                   SPAWN_LANCE in the save.
--
-- and Continue's own `cp SPAWN_LANCE / jr z, .SpawnAfterE4` consumes the
-- saved byte BEFORE the saved position is honoured, spawning at New Bark
-- Town.  Without either half the champion was left standing in HALL_OF_FAME,
-- whose only exit is the sealed Lance's room door: a soft lock at the moment
-- of victory.
--
-- These drive the shipped World:hallOfFame / World:credits /
-- World:consumePostGameSpawn against the real cache; only the screens are
-- registry fakes (they are pure presentation, and Screens.push resolves the
-- registry first for exactly this reason).
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 hof continue")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local HallOfFame = require("src.core.gen2.HallOfFame")

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local probe = io.open(cache .. "/data/generated/landmarks.lua", "r")
if not probe then
  check(true, "gold cache absent (SKIP)")
  S.finish()
  return
end
probe:close()

local function loadLua(rel) return assert(loadfile(cache .. "/" .. rel))() end
local maps = loadLua("data/generated/maps.lua")
local landmarks = loadLua("data/generated/landmarks.lua")

-- One registry serves the whole file; Screens caches factories per id, so the
-- fakes are registered once and the recorder is swapped per test.
local pushes
local registry = {}
for _, id in ipairs({ "Gen2HallOfFame", "Gen2Credits" }) do
  registry[id] = { new = function(_game, opts)
    pushes[#pushes + 1] = { id = id, opts = opts }
    return { screenId = id }
  end }
end

local function makeStack()
  local stack = { items = {} }
  function stack:push(inst) self.items[#self.items + 1] = inst end
  function stack:pop()
    local top = self.items[#self.items]
    self.items[#self.items] = nil
    return top
  end
  return stack
end

local function makeWorld()
  pushes = {}
  local game = {
    data = { audio = {}, screens = registry },
    save = {
      version = "gold",
      generation = 2,
      player = { name = "GOLD" },
      party = { { species = "TYPHLOSION", level = 50, hp = 120,
        otId = 33333 } },
    },
    stack = makeStack(),
    titled = 0,
  }
  game.returnToTitle = function(g) g.titled = g.titled + 1 end
  local w = World.new(game)
  w.maps = maps
  w.landmarks = landmarks
  w.loaded = nil
  w.setMap = function(self, id, x, y, facing)
    self.loaded = { id = id, x = x, y = y, facing = facing }
    return true
  end
  return w, game
end

-- ---- the champion's ending: induct, roll, reset ---------------------------
do
  local w, game = makeWorld()
  local scriptResumed = false
  check(w:hallOfFame(function() scriptResumed = true end),
    "the halloffame command takes the screen")

  -- The ceremony's bookkeeping ran before the screen came up.
  eq(game.save.spawnAfterChampion, HallOfFame.SPAWN_LANCE,
    "induction writes wSpawnAfterChampion = SPAWN_LANCE")
  eq(HallOfFame.count(game.save), 1, "and bumps the win count")
  eq(pushes[1].id, "Gen2HallOfFame", "the roster ceremony is up first")

  -- `pop af / jp Credits`.
  pushes[1].opts.onDone()
  eq(pushes[2] and pushes[2].id, "Gen2Credits", "the roll follows the ceremony")
  eq(pushes[2].opts.allowSkip, false,
    "a first-time champion cannot hurry the roll (the PRE-induction flags)")

  -- The credits end: the script resumes (and immediately ends, as
  -- ReturnFromCredits' Script_endall does), and then the reset.
  eq(game.titled, 0, "no reset while the roll is still up")
  pushes[2].opts.onDone()
  check(scriptResumed, "the script got its resume before the teardown")
  eq(game.titled, 1, "`jp Reset`: the credits end on the title screen")
  check(w.loaded == nil, "and no warp happened in this session")
end

-- ---- CONTINUE consumes the saved spawn ------------------------------------
do
  local w, game = makeWorld()
  HallOfFame.induct(game.save, game.save.party)
  eq(game.save.spawnAfterChampion, HallOfFame.SPAWN_LANCE, "the save is armed")

  local spawn = w:consumePostGameSpawn()
  check(spawn ~= nil, "Continue's .SpawnAfterE4 arm fires")
  eq(spawn.map, "NEW_BARK_TOWN", "SPAWN_NEW_BARK is New Bark Town")
  eq(spawn.x, 13, "at the spawn point's x")
  eq(spawn.y, 6, "and y")
  eq(game.save.spawnAfterChampion, nil,
    "PostCreditsSpawn zeroes the byte on the way")
  check(w:consumePostGameSpawn() == nil, "so the next load is ordinary")
end

-- ---- the Red ending: no reset, straight back to Silver Cave ---------------
do
  local w, game = makeWorld()
  local scriptResumed = false
  check(w:credits(function() scriptResumed = true end),
    "the credits command takes the screen")
  eq(game.save.spawnAfterChampion, HallOfFame.SPAWN_RED,
    "RedCredits writes wSpawnAfterChampion = SPAWN_RED")
  eq(pushes[1].id, "Gen2Credits", "and goes straight to the roll")

  pushes[1].opts.onDone()
  check(scriptResumed, "the script got its resume")
  eq(game.titled, 0, ".AfterRed does not reset")
  check(w.loaded ~= nil, "it re-enters the overworld instead")
  eq(w.loaded.id, "SILVER_CAVE_OUTSIDE", "outside Silver Cave")
  eq(w.loaded.x, 23, "at SPAWN_MT_SILVER's x")
  eq(w.loaded.y, 20, "and y")
  eq(game.save.spawnAfterChampion, nil, "with the byte consumed in session")
end

-- ---- an ordinary continue is untouched ------------------------------------
do
  local w, game = makeWorld()
  game.save.position = { map = "GOLDENROD_CITY", x = 5, y = 5 }
  check(w:consumePostGameSpawn() == nil,
    "no pending spawn means the saved position stays in charge")
  eq(game.save.position.map, "GOLDENROD_CITY", "and is not disturbed")
end

S.finish()
