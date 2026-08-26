-- Contract gate for the two narrow Gen 1 seams added for a composable
-- post-departure S.S. Anne dock mod.  The suite is ROM-free: it drives the
-- real hook bus and WorldAPI against hand-written maps and save snapshots.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local WorldAPI = require("src.world.WorldAPI")

local oldHooks = Runtime.hooks
local oldTextBox = package.loaded["src.render.TextBox"]

package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { text = text, done = done } end,
}

local story = dofile("data/scripts/story3.lua")
local VERSIONS = { "red", "blue", "yellow" }

local function newDock(version, wrappers)
  local blocks, pushes, warps = {}, {}, {}
  local rebuilds = 0
  local save = {
    version = version,
    flags = { EVENT_SS_ANNE_LEFT = true },
    marker = "save-must-not-change",
  }
  local map = {
    id = "VERMILION_DOCK",
    setBlock = function(_, bx, by, block)
      blocks[bx .. "," .. by] = block
    end,
    renderer = { rebuild = function() rebuilds = rebuilds + 1 end },
  }
  local game = {
    save = save,
    data = { text = {
      _VermilionCitySailor1ShipSetSailText = "The ship set sail.",
    } },
    stack = { push = function(_, value) pushes[#pushes + 1] = value end },
  }
  local ow = {
    map = map,
    player = { cellX = 14, cellY = 2, facing = "down" },
    startWarpTo = function(_, ...)
      warps[#warps + 1] = { ... }
    end,
  }

  local hooks = Hooks.new()
  Runtime.hooks = hooks
  for _, entry in ipairs(wrappers or {}) do
    hooks:wrap("map.occupancy_allowed", entry.fn, entry.priority or 0,
      entry.owner)
  end

  story.VERMILION_DOCK.onEnter(game, ow)
  if pushes[1] and pushes[1].done then pushes[1].done() end
  return {
    blocks = blocks, pushes = pushes, warps = warps, rebuilds = rebuilds,
    save = save, map = map, game = game, ow = ow, hooks = hooks,
  }
end

local function allowedWrapper(owner, inspect)
  return {
    owner = owner,
    fn = function(nextFn, game, ctx)
      if inspect then inspect(game, ctx) end
      local downstream = nextFn(game, ctx)
      local ownClaim = true
      return downstream == true or ownClaim == true
    end,
  }
end

-- With no subscriber, the post-departure branch remains byte-for-byte
-- vanilla in effect: erase the ship, show its line, and eject the player.
do
  local run = newDock("red")
  T.eq(run.rebuilds, 1, "vanilla re-entry rebuilds the erased dock")
  T.eq(run.blocks["5,1"], 1, "vanilla re-entry erases the upper hull")
  T.eq(run.blocks["8,2"], 13, "vanilla re-entry erases the lower hull")
  T.eq(#run.pushes, 1, "vanilla re-entry shows the ship-set-sail line")
  T.eq(run.pushes[1].text, "The ship set sail.",
    "vanilla re-entry preserves its dialogue")
  T.eq(run.warps[1] and run.warps[1][1], "VERMILION_CITY",
    "vanilla re-entry ejects to Vermilion City")
end

-- The new permission seam is post-departure only.  An ordinary HM01 exit
-- must not invoke it or change the existing departure-script path.
do
  local hookCalls, queued = 0, nil
  local hooks = Hooks.new()
  Runtime.hooks = hooks
  hooks:wrap("map.occupancy_allowed", function(nextFn, game, ctx)
    hookCalls = hookCalls + 1
    return nextFn(game, ctx)
  end, 0, "must_not_run")

  local savedMusic = package.loaded["src.core.Music"]
  package.loaded["src.core.Music"] = {
    stop = function() end,
    play = function() end,
  }
  local game = {
    save = { version = "red", flags = { EVENT_GOT_HM01 = true } },
    data = {},
  }
  local ow = {
    player = { cellX = 14, cellY = 2 },
    startDustAnim = function(_, _, _, done) if done then done() end end,
    queueScript = function(_, rows) queued = rows end,
  }
  story.VERMILION_DOCK.onEnter(game, ow)
  package.loaded["src.core.Music"] = savedMusic

  T.eq(hookCalls, 0, "normal HM01 departure never calls the occupancy seam")
  T.eq(game.save.flags.EVENT_SS_ANNE_LEFT, true,
    "normal HM01 departure still sets the vanilla event flag")
  T.check(type(queued) == "table" and #queued > 0,
    "normal HM01 departure still queues its sail-away script")
end

-- One cooperative claimant may permit occupancy.  The callback receives a
-- detached data snapshot, not the live overworld, map, player, or save.
do
  local seenGame, seenCtx
  local run = newDock("red", { allowedWrapper("mew_fixture", function(game, ctx)
    seenGame = game
    seenCtx = {
      mapId = ctx.mapId, reason = ctx.reason, gameVersion = ctx.gameVersion,
      x = ctx.x, y = ctx.y,
    }
    ctx.mapId, ctx.x, ctx.y = "MUTATED", -1, -1
  end) })
  T.eq(seenGame, run.game, "occupancy callback receives the live game explicitly")
  T.same(seenCtx, {
    mapId = "VERMILION_DOCK", reason = "ss_anne_departed",
    gameVersion = "red", x = 14, y = 2,
  }, "occupancy context is the exact detached Red dock snapshot")
  T.eq(run.ow.map.id, "VERMILION_DOCK", "context mutation cannot change the map")
  T.eq(run.ow.player.cellX, 14, "context mutation cannot change player X")
  T.eq(run.ow.player.cellY, 2, "context mutation cannot change player Y")
  T.eq(run.save.marker, "save-must-not-change", "permission check does not mutate save")
  T.same(run.save, {
    version = "red", flags = { EVENT_SS_ANNE_LEFT = true },
    marker = "save-must-not-change",
  }, "permission check preserves the complete save snapshot")
  T.eq(#run.pushes, 0, "an exact true suppresses the vanilla rejection dialog")
  T.eq(#run.warps, 0, "an exact true permits post-departure dock occupancy")
  T.eq(run.blocks["5,1"], 1, "permitted occupancy still erases the departed ship")
  T.eq(run.rebuilds, 1, "permitted occupancy still rebuilds the water layout")
end

-- Standard hook composition also means a non-cooperative false/no-next
-- wrapper can suppress downstream claims.  This remains safe because false
-- is denial; it cannot accidentally grant occupancy.
do
  local downstreamCalls = 0
  local run = newDock("red", {
    {
      owner = "denier", priority = 10,
      fn = function() return false end,
    },
    {
      owner = "unreached_claimant", priority = 0,
      fn = function()
        downstreamCalls = downstreamCalls + 1
        return true
      end,
    },
  })
  T.eq(downstreamCalls, 0, "no-next denial suppresses downstream by hook semantics")
  T.eq(run.warps[1] and run.warps[1][1], "VERMILION_CITY",
    "non-cooperative false remains fail-closed")
end

-- Cooperative peers all run through next().  A lower-priority peer claim is
-- preserved by a higher-priority peer that has no claim of its own.
do
  local calls, contextIdentity = {}, nil
  local run = newDock("blue", {
    {
      owner = "peer_high", priority = 10,
      fn = function(nextFn, game, ctx)
        calls[#calls + 1] = "high-before"
        contextIdentity = ctx
        local allowed = nextFn(game, ctx)
        calls[#calls + 1] = "high-after"
        return allowed == true or false
      end,
    },
    {
      owner = "peer_low", priority = 0,
      fn = function(nextFn, game, ctx)
        calls[#calls + 1] = "low"
        T.eq(ctx, contextIdentity, "peer wrappers share one detached snapshot instance")
        local allowed = nextFn(game, ctx)
        local ownClaim = true
        return allowed == true or ownClaim == true
      end,
    },
  })
  T.same(calls, { "high-before", "low", "high-after" },
    "multiple peer handlers preserve hook-chain order")
  T.eq(#run.warps, 0, "a cooperative peer claim survives the whole chain")
end

-- Absent, throwing, or malformed callbacks fail closed.  Only boolean true
-- can turn off ejection; truthy strings/tables/numbers do not grant access.
do
  local malformed = {
    { label = "nil", value = nil },
    { label = "false", value = false },
    { label = "string", value = "yes" },
    { label = "number", value = 1 },
    { label = "table", value = {} },
  }
  for _, case in ipairs(malformed) do
    local run = newDock("red", { {
      owner = "malformed_" .. case.label,
      fn = function() return case.value end,
    } })
    T.eq(run.warps[1] and run.warps[1][1], "VERMILION_CITY",
      "malformed " .. case.label .. " permission fails closed")
  end

  local beforeNext = newDock("red", { {
    owner = "throws_before_next",
    fn = function() error("fixture throws before next", 0) end,
  } })
  T.eq(beforeNext.warps[1] and beforeNext.warps[1][1], "VERMILION_CITY",
    "throwing callback before next fails closed")

  local afterNext = newDock("red", { {
    owner = "throws_after_next",
    fn = function(nextFn, game, ctx)
      nextFn(game, ctx)
      error("fixture throws after next", 0)
    end,
  } })
  T.eq(afterNext.warps[1] and afterNext.warps[1][1], "VERMILION_CITY",
    "throwing callback after next keeps the downstream denial")
end

-- The context carries one version only.  A Red-only claimant must not leak
-- access into Blue or Yellow, and each call gets its own snapshot.
do
  local contexts = {}
  for _, version in ipairs(VERSIONS) do
    local run = newDock(version, { {
      owner = "red_only",
      fn = function(nextFn, game, ctx)
        contexts[#contexts + 1] = ctx
        local downstream = nextFn(game, ctx)
        return downstream == true or ctx.gameVersion == "red"
      end,
    } })
    T.eq(#run.warps == 0, version == "red",
      version .. " occupancy is decided only by its own version context")
  end
  T.eq(contexts[1].gameVersion, "red", "Red context stays Red")
  T.eq(contexts[2].gameVersion, "blue", "Blue context stays Blue")
  T.eq(contexts[3].gameVersion, "yellow", "Yellow context stays Yellow")
  T.check(contexts[1] ~= contexts[2] and contexts[2] ~= contexts[3],
    "Red, Blue, and Yellow calls do not share context tables")
end

-- Removing the owner is the engine's disable/uninstall path.  It restores
-- vanilla denial immediately and leaves no save flag or serialized state.
do
  local run = newDock("yellow", { allowedWrapper("removable") })
  T.eq(#run.warps, 0, "installed owner may grant Yellow dock occupancy")
  run.hooks:removeOwner("removable")
  local pushes, warps = {}, {}
  run.game.stack.push = function(_, value) pushes[#pushes + 1] = value end
  run.ow.startWarpTo = function(_, ... ) warps[#warps + 1] = { ... } end
  story.VERMILION_DOCK.onEnter(run.game, run.ow)
  if pushes[1] and pushes[1].done then pushes[1].done() end
  T.eq(warps[1] and warps[1][1], "VERMILION_CITY",
    "disabling the owner restores vanilla ejection")
  T.eq(run.hooks.chains["map.occupancy_allowed"], nil,
    "uninstall removes the occupancy chain itself")
  T.eq(run.save.marker, "save-must-not-change",
    "disable/uninstall writes no persistent permission state")
  T.same(run.save, {
    version = "yellow", flags = { EVENT_SS_ANNE_LEFT = true },
    marker = "save-must-not-change",
  }, "disable/uninstall preserves the complete Yellow save snapshot")
end

-- activeBlockAt is read-only and fail-closed.  A successful call exposes
-- only one scalar from the active runtime layout, never its backing table.
local function blockApi(version, blockAt)
  local backing = { 4, 5, 6, 8, 9, 10 }
  local map = {
    id = "VERMILION_DOCK",
    def = { width = 3, height = 2, blocks = backing },
    blockAt = blockAt or function(_, bx, by)
      return backing[by * 3 + bx + 1]
    end,
  }
  local world = { isOverworld = true, map = map }
  local game = {
    save = { version = version },
    stack = { states = { world } },
    overworld = world,
  }
  return WorldAPI.new(game, "contract_fixture"), backing, game, map
end

do
  for _, version in ipairs(VERSIONS) do
    local api, backing = blockApi(version)
    local block, err = api:activeBlockAt("VERMILION_DOCK", 1, 0)
    T.eq(block, 5, version .. " reads its active dock block")
    T.eq(err, nil, version .. " valid active block has no error")
    block = 99
    T.eq(backing[2], 5, version .. " scalar result cannot mutate the map")
  end

  local api = blockApi("red")
  local wrong, wrongErr = api:activeBlockAt("VERMILION_CITY", 1, 0)
  T.eq(wrong, nil, "wrong map has no block result")
  T.eq(wrongErr, "map is not active", "wrong map fails closed explicitly")

  local invalid = {
    { "nil x", nil, 0 }, { "string x", "1", 0 }, { "table x", {}, 0 },
    { "fraction x", 0.5, 0 }, { "negative infinity x", -math.huge, 0 },
    { "infinity y", 0, math.huge }, { "NaN y", 0, 0 / 0 },
  }
  for _, case in ipairs(invalid) do
    local value, err = api:activeBlockAt("VERMILION_DOCK", case[2], case[3])
    T.eq(value, nil, case[1] .. " returns no block")
    T.eq(err, "invalid block coordinates", case[1] .. " is rejected by type")
  end
  for _, coords in ipairs({ { -1, 0 }, { 0, -1 }, { 3, 0 }, { 0, 2 } }) do
    local value, err = api:activeBlockAt("VERMILION_DOCK", coords[1], coords[2])
    T.eq(value, nil, "out-of-bounds coordinate returns no block")
    T.eq(err, "block coordinates out of bounds", "bounds fail closed explicitly")
  end
end

do
  local malformed = {
    { label = "nil", get = function() return nil end },
    { label = "negative", get = function() return -1 end },
    { label = "fractional", get = function() return 1.5 end },
    { label = "infinite", get = function() return math.huge end },
    { label = "NaN", get = function() return 0 / 0 end },
    { label = "string", get = function() return "4" end },
    { label = "table", get = function() return {} end },
    { label = "throwing", get = function() error("bad map", 0) end },
  }
  for _, case in ipairs(malformed) do
    local api = blockApi("red", case.get)
    local block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
    T.eq(block, nil, "malformed active block " .. case.label .. " returns no value")
    T.eq(err, "block unavailable",
      "malformed active block " .. case.label .. " fails closed")
  end
end


-- Invalid map shapes are untrusted runtime data too.  None may escape as a
-- block or raise through the mod facade.
do
  local badDefs = {
    { label = "missing def", value = nil },
    { label = "missing width", value = { height = 2, blocks = {} } },
    { label = "string width", value = { width = "3", height = 2, blocks = {} } },
    { label = "fractional width", value = { width = 1.5, height = 2, blocks = {} } },
    { label = "nonpositive width", value = { width = 0, height = 2, blocks = {} } },
    { label = "infinite height", value = { width = 3, height = math.huge, blocks = {} } },
    { label = "missing blocks", value = { width = 3, height = 2 } },
    { label = "scalar blocks", value = { width = 3, height = 2, blocks = 4 } },
  }
  for _, case in ipairs(badDefs) do
    local api, _, _, map = blockApi("red")
    map.def = case.value
    local block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
    T.eq(block, nil, case.label .. " returns no block")
    T.eq(err, "block unavailable", case.label .. " fails closed")
  end

  local api, _, _, map = blockApi("red")
  map.blockAt = nil
  local block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
  T.eq(block, nil, "missing blockAt returns no block")
  T.eq(err, "block unavailable", "missing blockAt fails closed")
  map.blockAt = "not a function"
  block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
  T.eq(block, nil, "malformed blockAt returns no block")
  T.eq(err, "block unavailable", "malformed blockAt fails closed")

  api, _, _, map = blockApi("red")
  map.def.blocks = {}
  block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
  T.eq(block, nil, "sparse stored block slot returns no block")
  T.eq(err, "block unavailable", "sparse stored block slot fails closed")

  api, _, _, map = blockApi("red")
  map.def.blocks[1] = "4"
  block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
  T.eq(block, nil, "malformed stored block slot returns no block")
  T.eq(err, "block unavailable", "malformed stored block slot fails closed")

  api, _, _, map = blockApi("red", function() return 5 end)
  block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
  T.eq(block, nil, "stored/accessor mismatch returns no block")
  T.eq(err, "block unavailable", "stored/accessor mismatch fails closed")
end

do
  local api = WorldAPI.new({ stack = { states = {} } }, "contract_fixture")
  local block, err = api:activeBlockAt("VERMILION_DOCK", 0, 0)
  T.eq(block, nil, "no-overworld lookup returns no block")
  T.eq(err, "no overworld", "no-overworld lookup reports its state")
end

Runtime.hooks = oldHooks
package.loaded["src.render.TextBox"] = oldTextBox
T.finish("mew dock seam contract")
