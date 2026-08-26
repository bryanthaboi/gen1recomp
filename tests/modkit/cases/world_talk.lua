-- A sandboxed mod can claim the A press on an object it owns, using only
-- public mod surfaces, and an unhooked build still talks to it as before.
--
-- The seam exists because a runtime object (WorldAPI:spawnNpc) carries no
-- TEXT_* id: the vanilla talk path has nothing to say for one, so a mod that
-- spawned it has to be able to answer instead.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local OverworldState = require("src.world.OverworldController")

local FIXTURE = {
  ["mods/talk_probe/manifest.json"] = [[{
    "id": "talk_probe",
    "name": "Talk Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/talk_probe/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("world.talk", function(next, ow, target)
      if target and target.claimedByMod then
        mod.exports.claimed = target.id
        return   -- deliberately not calling next(): the mod answers instead
      end
      return next(ow, target)
    end)
  ]],
}

-- enough of an overworld to reach the A press: a player facing one cell, an
-- object standing on it, and a map with no counter to talk across
local function fixtureOverworld(npc)
  local ow
  ow = setmetatable({
    npcs = { npc },
    player = {
      facing = "up",
      facingCell = function() return 4, 5 end,
    },
    map = {
      id = "FIX_ROUTE",
      isCounterCell = function() return false end,
    },
    talked = {},
  }, { __index = OverworldState })
  -- the vanilla destination, recorded rather than run: talkTo walks into the
  -- map's text tables, which a fixture map does not have
  ow.talkTo = function(_, target) ow.talked[#ow.talked + 1] = target.id end
  return ow
end

local function objectAt(id, claimed)
  return { id = id, cellX = 4, cellY = 5, targetX = 4, targetY = 5,
           moving = false, claimedByMod = claimed or nil, def = {} }
end

-- ------- no mod: the A press lands in the vanilla talk path

local vanilla = T.sdk.loadNone({})
local plain = fixtureOverworld(objectAt("SIGNPOST_MAN"))
plain:interact()
T.eq(#plain.talked, 1, "with no mod loaded the A press reaches talkTo")
T.eq(plain.talked[1], "SIGNPOST_MAN", "and it is handed the object it faced")
vanilla.release()

-- ------- a mod that owns the object answers for it

local run = T.sdk.loadMods({ "mods/talk_probe" }, { fs = T.sdk.memfs(FIXTURE) })
T.eq(#run.errors, 0,
  "the public talk probe loads clean (" .. tostring(run.errors[1]) .. ")")

local owned = fixtureOverworld(objectAt("GHOST_PLAYER", true))
owned:interact()
local out = run.loader.exports.talk_probe or {}
T.eq(out.claimed, "GHOST_PLAYER", "a public hook sees the object it owns")
T.eq(#owned.talked, 0,
  "and a hook that does not call next keeps the vanilla text path out of it")

-- ...while everything the mod does not own falls straight through
local other = fixtureOverworld(objectAt("NURSE_JOY"))
other:interact()
T.eq(#other.talked, 1, "an object the mod does not claim still reaches talkTo")
T.eq(other.talked[1], "NURSE_JOY", "unchanged")

-- an object mid-step is not talkable in either build (walk_npc.asm), so the
-- hook must not fire for one either
local walking = fixtureOverworld(objectAt("WALKER", true))
walking.npcs[1].moving = true
walking:interact()
T.eq(run.loader.exports.talk_probe.claimed, "GHOST_PLAYER",
  "an object mid-step raises no talk hook")
T.eq(#walking.talked, 0, "and reaches no talk path at all")

run.release()

T.finish("world_talk")
