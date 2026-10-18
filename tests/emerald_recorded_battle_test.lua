package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

-- Pure logic only: no Emerald cache is loaded here. The SAVE_BATTLE case runs
-- before recorded_battle is required, so the lookup goes through Rse.MODULES
-- (rse/init.lua) and fails if that registration is missing.
local Rse = require("src.core.game3.rse.init")
local NativesFrontier = require("src.core.game3.scripting.natives_frontier")
local Util = require("src.core.game3.rse.frontier.util")
local SAVE_BATTLE = Util.FUNC.SAVE_BATTLE

local function resultOf(ctx)
  return Rse.specialVar(ctx, Util.VAR_RESULT)
end

-- SAVE_BATTLE: no pending record gives VAR_RESULT 0 (the record could not be
-- saved), a pending record gives 1 and makes the Frontier Pass copyable.
-- pokeemerald/src/frontier_util.c:2173
do
  local fn = NativesFrontier.FUNCS and NativesFrontier.FUNCS[SAVE_BATTLE]
  check(type(fn) == "function", "SAVE_BATTLE native is registered")

  local ctx = { specialVars = {} }
  local s = { frontier = Util.newFrontier() }
  fn(ctx, nil, s)
  eq(resultOf(ctx), 0, "SAVE_BATTLE without a pending record sets VAR_RESULT 0")
  eq(s.recordedBattle, nil, "SAVE_BATTLE without a pending record copies nothing")

  local ctx2 = { specialVars = {} }
  local s2 = { frontier = Util.newFrontier(), version = "emerald" }
  s2.pendingRecordedBattle = {
    version = "emerald", battleFlags = 1, seed = 42, party = {}, foe = {},
    turns = { [1] = { rng = 42, acts = {} } }, replaces = {},
  }
  fn(ctx2, nil, s2)
  eq(resultOf(ctx2), 1, "SAVE_BATTLE with a pending record sets VAR_RESULT 1")
  check(s2.recordedBattle ~= nil, "SAVE_BATTLE with a pending record copies it to the save")
  local impl = Rse.system("recordedBattle")
  eq(impl and impl.canCopy(s2), true, "canCopy is true once the record is saved")
end

local RB = require("src.core.game3.rse.recorded_battle")

-- newRng: same seed gives the same sequence, and getState/setState resume it
do
  local a = RB.newRng(12345)
  local b = RB.newRng(12345)
  local same = true
  for _ = 1, 50 do
    if a.fn(1, 100) ~= b.fn(1, 100) then same = false end
  end
  check(same, "newRng with the same seed gives the same sequence")

  local c = RB.newRng(777)
  c.fn()
  c.fn(6)
  local mark = c:getState()
  local v1, v2 = c.fn(1, 1000), c.fn()
  c:setState(mark)
  eq(c.fn(1, 1000), v1, "newRng setState(getState()) replays the same integer draw")
  eq(c.fn(), v2, "newRng setState(getState()) replays the same float draw")

  local lo = RB.newRng(9)
  local inRange = true
  for _ = 1, 200 do
    local v = lo.fn(3, 5)
    if v < 3 or v > 5 or v ~= math.floor(v) then inRange = false end
  end
  check(inRange, "newRng(lo, hi) stays inside the inclusive range")
  eq(RB.newRng(1).fn(0), 0, "newRng(n) with n <= 0 returns 0")
end

-- record -> replay round trip: turn(n) returns the stored actions and restores
-- the checkpoint rng; nextReplace returns faint replacements per battler in order
do
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, {
    kind = "frontier", facility = 2, lvlMode = 0,
    party = { { species = 1, level = 50, moves = { 33, 0, 0, 0 } }, { species = 4, level = 50 } },
    foe = { name = "TRAINER", trainerClass = 9, mons = { { species = 25 } } },
    startOpts = { frontier = true, double = false, trainerName = "TRAINER" },
  })

  local drawn = {}
  local acts1 = { player = { kind = "move", move = 33, slot = 0, target = 1, extra = { junk = true } },
    enemy = { kind = "move", move = 10, slot = 1, target = 0 } }
  -- one draw before the checkpoint, as the engine would do during planning
  rec.rng.fn(1, 6)
  rec:onTurn(1, acts1)
  drawn[1] = rec.rng.fn(1, 100)
  rec:onTurn(2, { player = { kind = "switch", slot = 2 }, enemy = { kind = "move", move = 5, slot = 0, target = 0 } })
  rec:onReplace(0, 3)
  rec:onReplace(2, 1)
  rec:onReplace(0, 4)
  rec:finish(sess, "win")

  local record = sess.pendingRecordedBattle
  check(record ~= nil, "finish stores the record as pendingRecordedBattle")
  eq(record.battleFlags ~= 0, true, "a finished record is flagged valid")
  check(record.turns[1] ~= nil and record.turns[2] ~= nil, "each turn is checkpointed")
  eq(record.turns[1].acts.player.extra, nil, "stored actions keep only battler action fields")
  eq(record.turns[1].acts.player.move, 33, "stored player action keeps its move")
  eq(record.party[1].species, 1, "party snapshot is stored as plain data")
  eq(record.foe.trainerClass, 9, "foe snapshot is stored as plain data")

  local rep = RB.beginReplay(record)
  local got1 = rep:turn(1)
  eq(got1.player.move, 33, "replay turn 1 returns the recorded player move")
  eq(got1.enemy.target, 0, "replay turn 1 returns the recorded enemy target")
  eq(rep.rng:getState(), record.turns[1].rng, "replay turn restores the checkpoint rng")
  eq(rep.rng.fn(1, 100), drawn[1], "replay draws match the recording after the checkpoint")
  eq(rep:turn(99), nil, "replay of an unknown turn returns nil")
  eq(rep:turn(2).player.slot, 2, "replay turn 2 returns the recorded switch")

  eq(rep:nextReplace(0), 3, "first faint replacement for battler 0 is the first recorded slot")
  eq(rep:nextReplace(2), 1, "faint replacement for battler 2 is independent of battler 0")
  eq(rep:nextReplace(0), 4, "second faint replacement for battler 0 follows recording order")
  eq(rep:nextReplace(0), nil, "no faint replacements left for battler 0")
end

-- save-section round trip: the record survives export and restore, and a
-- record that was never saved reads as invalid
do
  local SaveSections = require("src.core.game3.save_sections")
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, { party = { { species = 7, level = 5 } }, foe = {} })
  rec.rng.fn()
  rec:onTurn(1, { player = { kind = "move", move = 1, slot = 0, target = 1 } })
  rec:finish(sess, "lose")

  local s = { version = "emerald", frontier = Util.newFrontier() }
  eq(RB.moveToSaveData(s), false, "moveToSaveData refuses when there is no pending record")
  s.pendingRecordedBattle = sess.pendingRecordedBattle
  eq(RB.moveToSaveData(s), true, "moveToSaveData accepts a valid pending record")

  local section = SaveSections.of("emerald")
  local found = nil
  for _, entry in ipairs(section) do
    if entry.name == "recordedBattle" then found = entry.def end
  end
  check(found ~= nil, "recordedBattle is a registered save section for emerald")

  local out = {}
  found.export(s, out)
  check(out.recordedBattle ~= nil, "export writes the recordedBattle section")
  eq(out.recordedBattle.turns[1].acts.player.move, 1, "exported record keeps its turn actions")

  local restored = {}
  found.restore({ recordedBattle = out.recordedBattle }, restored)
  eq(RB.canCopy(restored), true, "restored save reads back as a valid recorded battle")
  eq(restored.recordedBattle.seed, s.recordedBattle.seed, "restored record keeps its seed")
  eq(RB.canCopy({}), false, "no saved record means canCopy is false")
end

-- finish with no recorded turns (a failed start) keeps the last valid pending record
do
  local sess = { version = "emerald" }
  local good = RB.beginRecording(sess, { party = {}, foe = {} })
  good:onTurn(1, { player = { kind = "move", move = 1, slot = 0, target = 1 } })
  good:finish(sess, "win")
  local kept = sess.pendingRecordedBattle
  check(kept ~= nil, "a recording with turns becomes the pending record")

  local failed = RB.beginRecording(sess, { party = {}, foe = {} })
  local out = failed:finish(sess, "win")
  eq(out, nil, "finish with no turns returns nothing")
  eq(sess.pendingRecordedBattle, kept, "finish with no turns leaves the pending record untouched")

  failed:onTurn(1, { player = { kind = "move", move = 2, slot = 0, target = 1 } })
  eq(failed:finish(sess, "win"), nil, "a finished recording ignores later turns and stays empty")
  eq(sess.pendingRecordedBattle, kept, "a frozen empty recording does not replace the pending record")
end

-- a forfeited frontier battle leaves no record and disables recording (battle_main.c:5062)
do
  local Util = require("src.core.game3.rse.frontier.util")
  local sess = { version = "emerald", frontier = Util.newFrontier() }
  local good = RB.beginRecording(sess, { party = {}, foe = {} })
  good:onTurn(1, { player = { kind = "move", move = 1, slot = 0, target = 1 } })
  good:finish(sess, "win")
  local kept = sess.pendingRecordedBattle

  local forfeit = RB.beginRecording(sess, { party = {}, foe = {} })
  forfeit:onTurn(1, { player = { kind = "move", move = 2, slot = 0, target = 1 } })
  eq(forfeit:finish(sess, "forfeited"), nil, "a forfeited battle returns no record")
  eq(sess.pendingRecordedBattle, kept, "a forfeited battle leaves the pending record untouched")
  eq(Util.frontier(sess).disableRecordBattle, 1, "a forfeited battle sets disableRecordBattle")
end

-- the saved record keeps no live handles from the start flags
do
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, {
    party = {}, foe = {},
    startOpts = { double = true, recorder = { x = 1 }, replay = { y = 2 }, rng = function() end,
      done = function() end, session = { z = 3 } },
  })
  rec:onTurn(1, { player = { kind = "move", move = 1, slot = 0, target = 1 } })
  rec:finish(sess, "win")
  local opts = sess.pendingRecordedBattle.startOpts
  eq(opts.double, true, "start flags that are plain data are kept")
  for _, k in ipairs({ "recorder", "replay", "rng", "done", "session" }) do
    eq(opts[k], nil, "the saved record has no " .. k .. " key")
  end
end

-- meta is read at finish time, so fields set after beginRecording are recorded
do
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, { party = { { species = 1 } } })
  rec.meta.foe = { name = "LATE", trainerClass = 4 }
  rec:onTurn(1, { player = { kind = "move", move = 1, slot = 0, target = 1 } })
  rec:finish(sess, "win")
  eq(sess.pendingRecordedBattle.foe.name, "LATE", "a foe set on rec.meta after beginRecording is recorded")
end

-- setFoe records the foe as fought, and is ignored once the recording is frozen
do
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, { party = {}, foe = { name = "META" } })
  rec:setFoe({ name = "HOOKED", fn = function() end })
  rec:onTurn(1, { player = { kind = "move", move = 1, slot = 0, target = 1 } })
  rec:finish(sess, "win")
  eq(sess.pendingRecordedBattle.foe.name, "HOOKED", "setFoe overrides meta.foe in the record")
  rec:setFoe({ name = "LATER" })
  eq(sess.pendingRecordedBattle.foe.name, "HOOKED", "setFoe after finish does not change the record")
end

-- RB.plain is the plain-data copy used by the recorder
do
  local src = { a = 1, nested = { b = "x" }, fn = function() end }
  src.self = src
  local out = RB.plain(src)
  eq(out.a, 1, "RB.plain keeps scalars")
  eq(out.nested.b, "x", "RB.plain copies nested tables")
  eq(out.fn, nil, "RB.plain drops functions")
  eq(out.self, nil, "RB.plain drops cycles")
  check(out.nested ~= src.nested, "RB.plain returns a new table")
end

-- engine-read action fields survive the recording; live battler tables do not
do
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, { party = {}, foe = {} })
  local live = { side = "enemy", mon = { species = 1 }, fn = function() end }
  rec:onTurn(1, {
    player = { kind = "item", user = "player", itemId = 17, moveSlot = 2, battler = 0,
      meta = { itemId = 17, action = "pokeblock", pokeblock = { flavors = { 1, 2, 3, 4, 5 } } },
      pokeblock = { flavors = { 9, 8 } }, fn = function() end },
    enemy = { kind = "move", move = 10, user = live, battler = 1 },
  })
  rec:finish(sess, "win")
  local act = sess.pendingRecordedBattle.turns[1].acts
  eq(act.player.user, "player", "the user side name is kept")
  eq(act.player.itemId, 17, "itemId is kept")
  eq(act.player.moveSlot, 2, "moveSlot is kept")
  eq(act.player.meta.pokeblock.flavors[5], 5, "meta is plain-copied")
  eq(act.player.pokeblock.flavors[2], 8, "pokeblock is plain-copied")
  eq(act.player.fn, nil, "functions in an action are dropped")
  eq(act.enemy.user, nil, "a live battler table in user is dropped")
  eq(act.enemy.battler, 1, "battler id is kept when user is a table")
end

-- bag and forfeit run actions survive record, save serializer and replay
do
  local Serializer = require("src.core.SaveSerializer")
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, { party = {}, foe = {} })
  rec:onTurn(1, {
    player = { kind = "bag", itemId = 17, partySlot = 2, usedInMenu = true, battler = 0, user = "player" },
    enemy = { kind = "run", forfeit = true, battler = 1, locked = false, user = "enemy" },
  })
  rec:finish(sess, "lose")
  local s = { version = "emerald", pendingRecordedBattle = sess.pendingRecordedBattle }
  eq(RB.moveToSaveData(s), true, "a bag and run record is saved")
  local back = Serializer.decode(Serializer.encode({ recordedBattle = s.recordedBattle }))
  eq(RB.canCopy(back), true, "the decoded bag and run record is valid")
  local rep = RB.beginReplay(back.recordedBattle)
  local acts = rep:turn(1)
  eq(acts.player.kind, "bag", "replay keeps the bag action kind")
  eq(acts.player.itemId, 17, "replay keeps the bag itemId")
  eq(acts.player.partySlot, 2, "replay keeps the bag partySlot")
  eq(acts.player.usedInMenu, true, "replay keeps usedInMenu")
  eq(acts.enemy.kind, "run", "replay keeps the run action kind")
  eq(acts.enemy.forfeit, true, "replay keeps forfeit")
  eq(acts.enemy.locked, false, "replay keeps locked")
end

-- a saved record built through the real recorder, for the cases below
local function savedRecord()
  local sess = { version = "emerald" }
  local rec = RB.beginRecording(sess, {
    party = { { species = 1, level = 50 } }, foe = { name = "TRAINER" },
    startOpts = { double = true, trainerName = "TRAINER", done = function() end },
  })
  rec.rng.fn()
  rec:onTurn(1, { [0] = { kind = "move", move = 33, slot = 0, target = 1, battler = 0 },
    [1] = { kind = "move", move = 10, slot = 1, target = 0, battler = 1 } })
  rec:onReplace(0, 3)
  rec:finish(sess, "win")
  local s = { version = "emerald", pendingRecordedBattle = sess.pendingRecordedBattle }
  eq(RB.moveToSaveData(s), true, "savedRecord copies a valid record to the save")
  return s
end

-- canCopy rejects malformed saves, not only missing ones
do
  eq(RB.canCopy(savedRecord()), true, "canCopy accepts a well-formed saved record")
  local cases = {
    { "battleFlags 0", function(r) r.battleFlags = 0 end },
    { "turn rng not a number", function(r) r.turns[1].rng = "x" end },
    { "turn without an acts table", function(r) r.turns[1].acts = nil end },
    { "replaces not a table", function(r) r.replaces = 7 end },
    { "replace entry with a non-numeric slot", function(r) r.replaces = { { battler = 0, slot = "a" } } end },
    { "version not a string", function(r) r.version = 7 end },
    { "empty version", function(r) r.version = "" end },
  }
  for _, c in ipairs(cases) do
    local s = savedRecord()
    c[2](s.recordedBattle)
    eq(RB.canCopy(s), false, "canCopy rejects a record with " .. c[1])
  end
end

-- save text round trip through the save serializer, including the [0] battler key
do
  local Serializer = require("src.core.SaveSerializer")
  local s = savedRecord()
  local back = Serializer.decode(Serializer.encode({ recordedBattle = s.recordedBattle }))
  check(back ~= nil and back.recordedBattle ~= nil, "save text decodes back to a recordedBattle section")
  eq(RB.canCopy(back), true, "decoded save reads back as a valid recorded battle")
  eq(back.recordedBattle.turns[1].acts[0].move, 33, "the [0] battler action survives encode and decode")
  eq(back.recordedBattle.replaces[1].battler, 0, "the replacement battler 0 survives encode and decode")
  local rep = RB.beginReplay(back.recordedBattle)
  eq(rep:turn(1)[0].move, 33, "replay of the decoded record returns the [0] action")
  eq(rep:nextReplace(0), 3, "replay of the decoded record returns the faint replacement")
end

-- RB.play calls onDone exactly once, including when the bridge reports a failed start
do
  local bridgeKey, runtimeKey = "src.core.game3.battle_bridge", "src.core.game3.runtime"
  local realBridge, realRuntime = package.loaded[bridgeKey], package.loaded[runtimeKey]
  package.loaded[runtimeKey] = { _mod = {}, _game = {} }
  local s = savedRecord()
  local n, got = 0, {}
  local function onDone(result, err)
    n = n + 1
    got = { result = result, err = err }
  end

  package.loaded[bridgeKey] = { start = function(_, _, _, opts)
    check(opts.replay ~= nil and opts.fade == false and opts.recordedParty ~= nil,
      "play passes replay, fade=false and the recorded party to the bridge")
    opts.done("win")
    return nil, "err"
  end }
  RB.play(s, onDone)
  eq(n, 1, "onDone runs once when the bridge reports a failed start")
  eq(got.result, nil, "a failed start reports no battle result")
  eq(got.err, "err", "a failed start reports the bridge error")

  package.loaded[bridgeKey] = { start = function(_, _, _, opts)
    opts.done("lose")
    return true
  end }
  n = 0
  RB.play(s, onDone)
  eq(n, 1, "onDone runs once when the battle ends")
  eq(got.result, "lose", "onDone receives the battle result")

  package.loaded[bridgeKey] = { start = function() error("boom", 0) end }
  n = 0
  RB.play(s, onDone)
  eq(n, 1, "onDone runs once when the bridge throws")
  check(tostring(got.err):find("boom", 1, true) ~= nil, "onDone receives the thrown error")

  package.loaded[bridgeKey] = realBridge
  package.loaded[runtimeKey] = realRuntime
end

T.finish("emerald_recorded_battle_test")
