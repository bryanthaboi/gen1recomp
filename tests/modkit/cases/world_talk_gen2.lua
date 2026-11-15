package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local UnifiedCallbacks = require("src.mods.UnifiedCallbacks")
local World = require("src.world.gen2.World")

local FIXTURE = {
  ["mods/talk2/manifest.json"] = [[{"id":"talk2","name":"Talk 2","version":"1.0.0",
    "api":2,"games":["all"],"entry":"main.lua"}]],
  ["mods/talk2/main.lua"] = [[
    local mod = ...
    local e = mod.exports
    e.talk, e.interacted = 0, 0
    mod.hooks:wrap("world.talk", function(next, world, target)
      e.talk = e.talk + 1
      e.world = world
      if target and target.def and target.def.modOwned then
        e.claimed = target.def.modOwned
        return
      end
      return next(world, target)
    end)
    mod.events:on("world.interacted", function(p)
      e.interacted = e.interacted + 1
      e.kind = p.kind
    end)
  ]],
}

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  T.eq(UnifiedCallbacks.supports("hooks", "world.talk", 2, version), true,
    "world.talk is supported on " .. version)
end

local started, current = {}, nil
local function newWorld()
  local w = setmetatable({
    player = { cellX = 4, cellY = 5, facing = "up", moving = false },
    vm = { start = function(_, key) started[#started + 1] = key return true end },
    map = { id = "ROUTE_29", def = { bgEvents = {}, objects = {} } },
  }, { __index = World })
  w.busy = function() return false end
  w.cellCollisionAcross = function() return 0 end
  w.npcAt = function(_, x, y) if x == 4 and y == 4 then return current end end
  w.freezeNpc = function() end
  w.trainerRefused = function() return false end
  w.bgEventAt = function() return nil end
  w.tryCutOW = function() return false end
  w.tryWhirlpoolOW = function() return false end
  w.tryWaterfallOW = function() return false end
  w.tryHeadbuttOW = function() return false end
  w.trySurfOW = function() return false end
  return w
end

do
  local none = T.sdk.loadNone({ generation = 2 })
  started = {}
  current = { cellX = 4, cellY = 4, moving = false,
    def = { scriptKey = "s:hello", index = 2 } }
  local w = newWorld()
  T.eq(w:interactBody(), true, "no mod: the A press is taken")
  T.eq(started[1], "s:hello", "no mod: the object's script runs")
  none.release()
end

local run = T.sdk.loadMods({ "mods/talk2" }, { fs = T.sdk.memfs(FIXTURE), generation = 2 })
T.eq(#run.errors, 0, "the Gen 2 talk probe loads clean (" .. tostring(run.errors[1]) .. ")")
local e = run.loader.exports.talk2

local function reset()
  e.talk, e.interacted, e.claimed, e.kind, e.world = 0, 0, nil, nil, nil
  started = {}
end

reset()
current = { cellX = 4, cellY = 4, moving = false,
  def = { runtime = true, index = 7, modOwned = "GHOST" } }
local w = newWorld()
T.eq(w:interactBody(), true, "a claimed press is consumed")
T.eq(e.talk, 1, "world.talk fires once on a spawned object")
T.eq(e.claimed, "GHOST", "the mod sees the object it owns")
T.eq(e.world, w, "and the Gen 2 World as the first argument")
T.eq(e.interacted, 1, "world.interacted still fires once")
T.eq(e.kind, "npc", "with kind npc")

reset()
current = { cellX = 4, cellY = 4, moving = false,
  def = { scriptKey = "s:hello", index = 2, modOwned = "SCRIPTED" } }
w = newWorld()
w:interactBody()
T.eq(e.talk, 1, "world.talk fires on a scripted object")
T.eq(#started, 0, "a claim keeps the object's script from running")

reset()
current = { cellX = 4, cellY = 4, moving = false,
  def = { scriptKey = "s:hello", index = 2 } }
w = newWorld()
T.eq(w:interactBody(), true, "an unclaimed press is taken")
T.eq(e.talk, 1, "world.talk fires on an object the mod does not own")
T.eq(started[1], "s:hello", "next() runs the object's own script")
T.eq(e.interacted, 1, "world.interacted fires once")

reset()
current = { cellX = 4, cellY = 4, moving = false,
  def = { trainer = { id = 1 }, scriptKey = "s:trainer", index = 3 } }
w = newWorld()
w.startTrainerScript = function() started[#started + 1] = "trainer" return true end
w:interactBody()
T.eq(e.talk, 1, "world.talk fires on a trainer")
T.eq(started[1], "trainer", "next() starts the trainer script")
T.eq(e.kind, "trainer", "and world.interacted keeps kind trainer")

reset()
current = { cellX = 4, cellY = 4, moving = true,
  def = { runtime = true, index = 7, modOwned = "WALKER" } }
w = newWorld()
w:interactBody()
T.eq(e.talk, 0, "an object mid-step raises no talk hook")

reset()
current = nil
w = newWorld()
T.eq(w:interactBody(), false, "an empty cell falls through to the tile events")
T.eq(e.talk, 0, "and raises no talk hook")
T.eq(e.kind, "none", "world.interacted reports none")

run.release()

T.finish("world_talk_gen2")
