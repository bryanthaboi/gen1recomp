-- Additive pokemon.caught.stored contract.  This suite is intentionally
-- ROM-free: every save, party, box, battle, and listener is hand-authored.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local BattleState = require("src.battle.BattleState")
local Boxes = require("src.pokemon.Boxes")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local Gen2BattleState = require("src.ui.gen2.BattleState")
local Gen2Boxes = require("src.core.gen2.Boxes")

local savedEvents, savedHooks, savedErrors =
  Runtime.events, Runtime.hooks, Runtime.errors

local serial = 0
local function mon(species)
  serial = serial + 1
  return {
    species = species or "PIDGEY",
    name = species or "PIDGEY",
    hp = 10,
    stats = { hp = 10 },
    moves = {},
    fixtureSerial = serial,
  }
end

local function containsIdentity(list, needle)
  for _, value in ipairs(list or {}) do
    if value == needle then return true end
  end
  return false
end

local function boxedIdentity(save, needle)
  for _, box in ipairs(save.boxes or {}) do
    if containsIdentity(box, needle) then return true end
  end
  return false
end

local function storedCount(save)
  local total = #(save.party or {})
  for _, box in ipairs(save.boxes or {}) do total = total + #box end
  return total
end

local function fillParty()
  local party = {}
  for i = 1, 6 do party[i] = mon("PIDGEY") end
  return party
end

local function fillBoxes()
  local boxes = {}
  for i = 1, Boxes.COUNT do
    boxes[i] = {}
    for j = 1, Boxes.CAPACITY do boxes[i][j] = mon("RATTATA") end
  end
  return boxes
end

local function freshBuses()
  local events, hooks, errors = Events.new(), Hooks.new(), {}
  Runtime.install(events, hooks, errors)
  return events, errors
end

local function makeStack()
  return {
    states = {},
    push = function(self, state) self.states[#self.states + 1] = state end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
end

local function gen1Fixture(version, opts)
  opts = opts or {}
  local caught = opts.caught or mon(opts.species or "MEW")
  local pokedex = {
    seen = {}, owned = opts.owned and { [caught.species] = true } or {},
  }
  if opts.noPokedex then pokedex = nil end
  local save = {
    version = version,
    player = { name = "RED", id = opts.playerId == false and nil or 1234 },
    party = opts.party or { mon("BULBASAUR") },
    currentBox = opts.currentBox,
    boxes = opts.boxes,
    box = opts.legacyBox,
    flags = {},
    pokedex = pokedex,
    options = {},
    inventory = {},
    money = 3000,
  }
  local stack = makeStack()
  local game = { save = save, data = {}, stack = stack }
  local battle = setmetatable({
    game = game,
    data = game.data,
    kind = opts.kind or "wild",
    enemy = { mon = caught, name = caught.name or caught.species },
    queue = {},
    lastBall = opts.ball or "POKE_BALL",
    nextInsert = 0,
  }, { __index = BattleState })
  stack:push(battle)
  return battle, save, caught
end

local function hasQueuedText(battle, fragment)
  for _, item in ipairs(battle.queue or {}) do
    if type(item.text) == "string" and item.text:find(fragment, 1, true) then
      return true
    end
  end
  return false
end

local function captureGen1(version, opts, listenerSetup)
  local events, errors = freshBuses()
  local battle, save, caught = gen1Fixture(version, opts)
  local payloads = {}
  if listenerSetup then listenerSetup(events, payloads, save, caught, battle) end
  events:on("pokemon.caught", function(payload)
    payloads[#payloads + 1] = payload
  end, -100, "contract-observer")
  battle:storeCaughtMon()
  return battle, save, caught, payloads, errors, events
end

-- Red, Blue, and Yellow are named independently even though they share the
-- Gen 1 storage function.  This prevents later version routing from silently
-- dropping one edition.
for _, version in ipairs({ "red", "blue", "yellow" }) do
  do
    local battle, save, caught, payloads = captureGen1(version)
    local ev = payloads[1]
    T.eq(#payloads, 1, version .. " party success emits exactly once")
    T.eq(ev and ev.stored, true, version .. " party success reports stored=true")
    T.eq(ev and ev.destination, "party", version .. " party destination is preserved")
    T.check(ev and ev.mon == caught, version .. " payload keeps exact caught identity")
    T.check(containsIdentity(save.party, caught),
      version .. " exact identity is in party before observer returns")
    T.eq(battle.result, "caught", version .. " party success keeps caught result")
  end

  do
    local party = fillParty()
    local battle, save, caught, payloads = captureGen1(version, { party = party })
    local ev = payloads[1]
    T.eq(#payloads, 1, version .. " box success emits exactly once")
    T.eq(ev and ev.stored, true, version .. " box success reports stored=true")
    T.eq(ev and ev.destination, "box", version .. " box destination is preserved")
    T.check(boxedIdentity(save, caught),
      version .. " exact identity is boxed before observer returns")
    T.eq(save.currentBox, 1, version .. " lazy box initialization selects box 1")
    T.eq(battle.result, "caught", version .. " box success keeps caught result")
  end

  do
    local boxes = fillBoxes()
    local before = 6 + Boxes.COUNT * Boxes.CAPACITY
    local battle, save, caught, payloads = captureGen1(version,
      { party = fillParty(), boxes = boxes, currentBox = 7 })
    local ev = payloads[1]
    T.eq(#payloads, 1, version .. " full storage still emits exactly once")
    T.eq(ev and ev.stored, false, version .. " full storage reports stored=false")
    T.eq(ev and ev.destination, "box", version .. " full storage keeps legacy destination")
    T.eq(storedCount(save), before, version .. " full storage count is unchanged")
    T.check(not containsIdentity(save.party, caught) and not boxedIdentity(save, caught),
      version .. " rejected identity is absent from party and boxes")
    T.check(save.pokedex.owned[caught.species] == true,
      version .. " Pokédex mutation is not confused with storage")
    T.check(hasQueuedText(battle, "every BOX"), version .. " full-box line remains queued")
    T.eq(save.currentBox, 7, version .. " failed storage preserves current box")
    T.eq(battle.result, "caught", version .. " failed storage keeps caught result")
  end
end

-- The event must observe settled state, not a promise that a later queue item
-- will perform the insertion.
do
  local seenInListener = false
  local _, _, caught, payloads = captureGen1("red", nil,
    function(events, _, save, expected)
      events:on("pokemon.caught", function(payload)
        seenInListener = payload.mon == expected
          and containsIdentity(save.party, expected)
          and payload.stored == true
      end, 100, "identity-first")
    end)
  T.check(seenInListener, "party identity exists before the first listener")
  T.check(payloads[1] and payloads[1].mon == caught,
    "later listener sees the same caught identity")
end

-- Current-box overflow and wrap are existing Gen 1 behavior.  The new field
-- must describe the successful insert without changing currentBox.
do
  local boxes = {}
  for i = 1, Boxes.COUNT do boxes[i] = {} end
  for i = 1, Boxes.CAPACITY do boxes[3][i] = mon("RATTATA") end
  local _, save, caught, payloads = captureGen1("red",
    { party = fillParty(), boxes = boxes, currentBox = 3 })
  T.eq(payloads[1].stored, true, "overflow into a later box reports stored=true")
  T.check(containsIdentity(save.boxes[4], caught), "overflow uses the next box with room")
  T.eq(save.currentBox, 3, "overflow does not change currentBox")
end

do
  local boxes = {}
  for i = 1, Boxes.COUNT do boxes[i] = {} end
  for i = 1, Boxes.CAPACITY do boxes[12][i] = mon("RATTATA") end
  local _, save, caught, payloads = captureGen1("red",
    { party = fillParty(), boxes = boxes, currentBox = 12 })
  T.eq(payloads[1].stored, true, "box-12 wrap reports stored=true")
  T.check(containsIdentity(save.boxes[1], caught), "box-12 overflow wraps to box 1")
  T.eq(save.currentBox, 12, "box-12 wrap does not change currentBox")
end

-- Old single-box saves are migrated by the same insertion.  Both the old mon
-- and the caught mon survive, and the event is emitted after that migration.
do
  local legacy = mon("SPEAROW")
  local _, save, caught, payloads = captureGen1("blue", {
    party = fillParty(), legacyBox = { legacy }, currentBox = 9,
  })
  T.eq(payloads[1].stored, true, "legacy box migration reports successful storage")
  T.check(containsIdentity(save.boxes[1], legacy), "legacy box occupant survives migration")
  T.check(containsIdentity(save.boxes[1], caught), "caught identity joins migrated box 1")
  T.eq(save.box, nil, "legacy single box is retired")
  T.eq(save.currentBox, 1, "legacy migration keeps its established box-1 rule")
end

-- New/owned Pokédex state, a missing Pokédex, and an old save with no trainer
-- ID must not affect storage truth.
do
  local _, save, caught, payloads = captureGen1("red", { species = "MEW" })
  T.eq(payloads[1].isNew, true, "new species keeps isNew=true")
  T.eq(payloads[1].stored, true, "new species storage is independently true")
  T.check(save.pokedex.seen.MEW and save.pokedex.owned.MEW,
    "new species keeps existing Pokédex mutation")
  T.check(caught.ot == "RED" and caught.otId == 1234, "existing OT stamping remains")
end

do
  local _, _, _, payloads = captureGen1("red", { species = "MEW", owned = true })
  T.eq(payloads[1].isNew, false, "already-owned species keeps isNew=false")
  T.eq(payloads[1].stored, true, "already-owned species still reports storage")
end

do
  local _, save, _, payloads = captureGen1("yellow", { noPokedex = true })
  T.eq(payloads[1].isNew, false, "absent Pokédex keeps legacy falsey isNew value")
  T.eq(payloads[1].stored, true, "absent Pokédex does not block storage truth")
  T.eq(save.pokedex, nil, "catch does not create an absent Gen 1 Pokédex")
end

do
  local _, save, caught, payloads = captureGen1("blue", { playerId = false })
  T.eq(payloads[1].stored, true, "missing player OT id does not affect storage truth")
  T.check(type(save.player.id) == "number", "legacy save receives an OT id")
  T.eq(caught.otId, save.player.id, "caught mon receives the repaired OT id")
  T.eq(caught.ot, "RED", "caught mon receives the player OT name")
end

-- A listener failure is isolated, and a legacy listener that ignores the new
-- key keeps its event count and existing fields.
do
  local throwingCalls, legacyCalls, legacyDestination = 0, 0, nil
  local battle, save, caught, payloads, errors = captureGen1("red", nil,
    function(events)
      events:on("pokemon.caught", function()
        throwingCalls = throwingCalls + 1
        error("fixture listener failure")
      end, 100, "throwing-fixture")
      events:on("pokemon.caught", function(payload)
        legacyCalls = legacyCalls + 1
        legacyDestination = payload.destination
      end, 50, "legacy-fixture")
    end)
  T.eq(throwingCalls, 1, "throwing listener runs once")
  T.eq(legacyCalls, 1, "legacy listener still runs once after a sibling throws")
  T.eq(legacyDestination, "party", "legacy listener keeps the destination field")
  T.eq(#payloads, 1, "contract observer still runs after throwing listener")
  T.eq(payloads[1].stored, true, "throwing listener does not alter storage result")
  T.check(containsIdentity(save.party, caught), "throwing listener cannot undo insertion")
  T.eq(battle.result, "caught", "throwing listener cannot interrupt battle completion")
  T.check(#errors == 0 or tostring(errors[1]):find("throwing%-fixture") ~= nil,
    "listener failure is isolated through the event bus")
end

-- Event ordering remains pokemon.caught before battle.ended.  finish() is the
-- real Gen 1 teardown; the stub stack accepts its transition state.
do
  local order = {}
  local events = freshBuses()
  local battle = gen1Fixture("red")
  events:on("pokemon.caught", function() order[#order + 1] = "caught" end)
  events:on("battle.ended", function() order[#order + 1] = "ended" end)
  battle:storeCaughtMon()
  battle:finish()
  T.eq(order[1], "caught", "pokemon.caught remains first")
  T.eq(order[2], "ended", "battle.ended remains after pokemon.caught")
end

-- Ordinary and Safari callers both reach the shared caught-storage tail.  A
-- synchronous queue fixture keeps this caller proof independent of generated
-- graphics, audio, and ROM-derived data while still running the real caller.
local function callerFixture(version)
  local battle, save, caught = gen1Fixture(version)
  battle.enemy.def = { catchRate = 255 }
  battle.data = {
    items = {
      POKE_BALL = { name = "POKE BALL" },
      SAFARI_BALL = { name = "SAFARI BALL" },
    },
    text = {},
  }
  battle.game.data = battle.data
  battle.act = function(_, fn) return fn() end
  battle.actNext = battle.act
  battle.sayAuto = function() end
  battle.sayNext = function() end
  battle.sayNextWaitSfx = function() end
  battle.ballChain = function() end
  battle.tossAnimFor = function() return "TOSS_ANIM" end
  battle.ballMissMessage = function() return "The ball missed." end
  battle.executeAction = function() end
  battle.enemyAction = function() return {} end
  battle.queueResidual = function() end
  battle.endOfTurn = function() end
  return battle, save, caught
end

do
  local events = freshBuses()
  local payloads = {}
  events:on("pokemon.caught", function(payload) payloads[#payloads + 1] = payload end)
  local battle = callerFixture("red")
  battle.catchAttempt = function() return true, 3 end
  battle:throwBall("POKE_BALL")
  T.eq(#payloads, 1, "ordinary ball caller emits one pokemon.caught")
  T.eq(payloads[1] and payloads[1].stored, true,
    "ordinary ball caller carries stored=true")
end

do
  local events = freshBuses()
  local payloads = {}
  events:on("pokemon.caught", function(payload) payloads[#payloads + 1] = payload end)
  local battle = callerFixture("yellow")
  battle:makeSafari({ balls = 5, steps = 100 })
  battle.catchAttempt = function() return true, 3 end
  battle:safariAction("ball")
  T.eq(#payloads, 1, "Safari caller emits one pokemon.caught")
  T.eq(payloads[1] and payloads[1].ball, "SAFARI_BALL",
    "Safari caller keeps its ball identity")
  T.eq(payloads[1] and payloads[1].stored, true,
    "Safari caller carries stored=true")
end

do
  local events = freshBuses()
  local caughtEvents, ballEvents = 0, 0
  events:on("pokemon.caught", function() caughtEvents = caughtEvents + 1 end)
  events:on("battle.ball_thrown", function(payload)
    ballEvents = ballEvents + 1
    T.eq(payload.caught, false, "failed ball keeps caught=false")
  end)
  local battle = callerFixture("blue")
  battle.catchAttempt = function() return false, 0 end
  battle:throwBall("POKE_BALL")
  T.eq(ballEvents, 1, "failed ball still emits battle.ball_thrown")
  T.eq(caughtEvents, 0, "failed ball emits no pokemon.caught")
end

-- Storage state survives the existing save serializer; the event field itself
-- adds no save key or migration.  Failure likewise round-trips without a
-- phantom caught mon.
do
  local _, save, caught, payloads = captureGen1("red")
  local decoded = assert(SaveData.decode(SaveData.encode(save)))
  T.eq(payloads[1].stored, true, "successful pre-save event reports true")
  T.check(containsIdentity(save.party, caught), "live save owns caught identity")
  local found = false
  for _, value in ipairs(decoded.party or {}) do
    if value.fixtureSerial == caught.fixtureSerial then found = true end
  end
  T.check(found, "successful storage survives save encode/decode")
  T.eq(decoded.stored, nil, "event result does not add a top-level save field")
end

do
  local boxes = fillBoxes()
  local before = 6 + Boxes.COUNT * Boxes.CAPACITY
  local _, save, caught, payloads = captureGen1("red",
    { party = fillParty(), boxes = boxes, currentBox = 5 })
  local decoded = assert(SaveData.decode(SaveData.encode(save)))
  T.eq(payloads[1].stored, false, "failed pre-save event reports false")
  T.eq(storedCount(decoded), before, "failed storage round-trip has no phantom mon")
  local found = false
  for _, value in ipairs(decoded.party or {}) do
    if value.fixtureSerial == caught.fixtureSerial then found = true end
  end
  for _, box in ipairs(decoded.boxes or {}) do
    for _, value in ipairs(box) do
      if value.fixtureSerial == caught.fixtureSerial then found = true end
    end
  end
  T.check(not found, "rejected caught identity stays absent after reload")
  T.eq(decoded.stored, nil, "failed event adds no save field")
end

-- Consumer rule used by Mew Under the Truck: only exact true advances.
local function confirmsStorage(payload)
  return type(payload) == "table" and payload.stored == true
end

T.check(confirmsStorage({ stored = true }), "consumer accepts exact true")
for label, payload in pairs({
  false_value = { stored = false },
  absent = {},
  string = { stored = "true" },
  number = { stored = 1 },
  table_value = { stored = {} },
  no_payload = false,
}) do
  T.check(not confirmsStorage(payload), "consumer fails closed: " .. label)
end
T.check(not confirmsStorage(nil), "consumer fails closed: nil payload")

-- Gen 2 shares the event name and field.  Its normal event path is reached
-- only after insertion; tutorial and Bug-Catching Contest catches return
-- before it and remain excluded.
local function gen2Fixture(opts)
  opts = opts or {}
  local save = {
    player = { name = "CHRIS", id = 4321 },
    party = opts.party or { mon("CYNDAQUIL") },
    boxes = opts.boxes or {},
    currentBox = opts.currentBox or 1,
    pokedex = { seen = {}, caught = {} },
    engineFlags = {},
    inventory = {},
  }
  local game = { save = save, data = { pokemon = {} } }
  local battle = { over = false, outcome = nil, payDay = nil }
  local screen = setmetatable({
    game = game,
    save = save,
    battle = battle,
    queue = {},
    tutorial = opts.tutorial and true or nil,
    contest = opts.contest and true or nil,
  }, { __index = Gen2BattleState })
  return screen, battle, save, opts.caught or mon("PIDGEY")
end

local function captureGen2(opts)
  local events = freshBuses()
  local payloads = {}
  events:on("pokemon.caught", function(payload) payloads[#payloads + 1] = payload end)
  local screen, battle, save, caught = gen2Fixture(opts)
  screen:pushCaught(caught, "POKE_BALL")
  return screen, battle, save, caught, payloads
end

do
  local _, battle, save, caught, payloads = captureGen2()
  T.eq(#payloads, 1, "Gen 2 party success emits once")
  T.eq(payloads[1] and payloads[1].stored, true, "Gen 2 party success reports true")
  T.eq(payloads[1] and payloads[1].destination, "party",
    "Gen 2 party destination remains")
  T.check(payloads[1] and payloads[1].mon == caught
      and containsIdentity(save.party, caught),
    "Gen 2 party identity is settled before listener")
  T.eq(battle.outcome, "caught", "Gen 2 party success keeps caught outcome")
end

do
  local party = fillParty()
  local boxes = {}
  local _, battle, save, caught, payloads = captureGen2({
    party = party, boxes = boxes, currentBox = 4,
  })
  T.eq(#payloads, 1, "Gen 2 box success emits once")
  T.eq(payloads[1] and payloads[1].stored, true, "Gen 2 box success reports true")
  T.eq(payloads[1] and payloads[1].destination, "box",
    "Gen 2 box destination remains")
  T.check(containsIdentity(Gen2Boxes.box(save, 4), caught),
    "Gen 2 exact identity is boxed before listener")
  T.eq(save.currentBox, 4, "Gen 2 capture does not change current box")
  T.eq(battle.outcome, "caught", "Gen 2 box success keeps caught outcome")
end

do
  local _, battle, save, caught, payloads = captureGen2({ tutorial = true })
  T.eq(#payloads, 0, "Gen 2 tutorial catch emits no pokemon.caught")
  T.check(not containsIdentity(save.party, caught), "Gen 2 tutorial catch is not stored")
  T.eq(battle.outcome, "caught", "Gen 2 tutorial keeps its caught demonstration outcome")
end

do
  local _, battle, save, caught, payloads = captureGen2({ contest = true })
  T.eq(#payloads, 0, "Gen 2 contest catch emits no pokemon.caught")
  T.check(not containsIdentity(save.party, caught), "Gen 2 contest mon is not party-owned")
  T.check(save.bugContest and save.bugContest.caught == caught,
    "Gen 2 contest retains its separate held-mon behavior")
  T.eq(battle.outcome, "caught", "Gen 2 contest keeps caught outcome")
end

Runtime.install(savedEvents, savedHooks, savedErrors)
T.finish("pokemon.caught stored contract")
