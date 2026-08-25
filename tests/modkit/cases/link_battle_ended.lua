-- A sandboxed mod can read the outcome of a link battle -- who won, and the
-- lockstep party copies -- through the public event surface.
--
-- The copies are the point.  Cable rules leave the real party untouched, so
-- a mode built on link battles (a tournament ladder, a battle royale) has no
-- other way to learn what the fight cost; by the time the state unwinds the
-- battle object is gone.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local LinkState = require("src.link.LinkState")

local FIXTURE = {
  ["mods/outcome_probe/manifest.json"] = [[{
    "id": "outcome_probe",
    "name": "Outcome Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/outcome_probe/main.lua"] = [[
    local mod = ...
    mod.exports.seen = 0
    mod.events:on("link.battle_ended", function(ev)
      mod.exports.seen = mod.exports.seen + 1
      mod.exports.result = ev.result
      mod.exports.role = ev.role
      mod.exports.peerName = ev.peerName
      mod.exports.myLead = ev.myParty and ev.myParty[1]
      mod.exports.theirLead = ev.theirParty and ev.theirParty[1]
    end)
  ]],
}

-- a link session parked at the end of a battle: no transport, so update()
-- goes straight to the stage that reports the outcome
local function finishedSession(result, isHost)
  local ls
  ls = setmetatable({
    stage = "battleRunning",
    isHost = isHost,
    peerName = "BLUE",
    net = nil,
    battle = {
      result = result,
      playerParty = { { species = "RATTATA", hp = 3 } },
      enemyParty = { { species = "PIDGEY", hp = 0 } },
    },
    game = { input = {}, stack = { top = function() return ls end } },
  }, { __index = LinkState })
  -- the real exit unwinds the whole link stack; the event is what is under
  -- test, so record the exit rather than run it
  ls.exitWith = function() ls.exited = true end
  return ls
end

-- ------- no mod: the battle still ends, nothing observes it

local Runtime = require("src.mods.Runtime")

local vanilla = T.sdk.loadNone({})
T.check(not Runtime.wants("link.battle_ended"),
  "with nothing subscribed the event is not wanted, so no payload is built")
local quiet = finishedSession("win", true)
quiet:update(0)
T.check(quiet.exited, "with no mod loaded the finished battle still unwinds")
T.eq(quiet.battle, nil, "and lets go of the battle")
vanilla.release()

-- ------- a mod reads the outcome and both party copies

local run = T.sdk.loadMods({ "mods/outcome_probe" }, { fs = T.sdk.memfs(FIXTURE) })
T.eq(#run.errors, 0,
  "the public outcome probe loads clean (" .. tostring(run.errors[1]) .. ")")

local session = finishedSession("win", true)
session:update(0)
local out = run.loader.exports.outcome_probe or {}
T.eq(out.seen, 1, "a finished link battle raises the event once")
T.eq(out.result, "win", "the outcome is reported")
T.eq(out.role, "host", "so is which side of the cable we were")
T.eq(out.peerName, "BLUE", "and who we played")
T.eq(out.myLead and out.myLead.species, "RATTATA",
  "the lockstep copy of our party comes with it")
T.eq(out.myLead and out.myLead.hp, 3,
  "carrying the damage the real party never took")
T.eq(out.theirLead and out.theirLead.species, "PIDGEY",
  "and the copy of theirs")
T.check(session.exited, "the state unwinds afterwards, as it always did")
T.eq(session.battle, nil, "and the battle is released")

-- the guest side says so
local guest = finishedSession("lose", false)
guest:update(0)
T.eq(run.loader.exports.outcome_probe.seen, 2, "the guest reports too")
T.eq(run.loader.exports.outcome_probe.role, "guest", "as the guest")
T.eq(run.loader.exports.outcome_probe.result, "lose", "with its own outcome")

run.release()

T.finish("link_battle_ended")
