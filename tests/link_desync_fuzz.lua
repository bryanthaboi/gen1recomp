-- Lockstep desync fuzz: two full LinkBattle simulations over a loopback,
-- driven the way a player drives them, checked turn by turn.
--
-- The suite in run_link_tests.lua battles one Charizard against one
-- Blastoise with the A button held, which reaches exactly one code path:
-- move slot 1, no switch, no faint, no status, no locked action.  Every
-- desync players actually hit lived outside it.  This walks the rest:
-- random multi-mon parties with random movesets, random move choices,
-- switches, faints and replacements, and -- the part that matters -- two
-- sides that are NOT identical clients.  Three things differ between two
-- real players and never differ inside one test process:
--
--   options  animations on/off, text speed, battle style change how long a
--            side spends in its message queue
--   speed    the GAME SPEED option multiplies the logic clock, so one side
--            takes several fixed steps per frame while the other takes one
--   lag      the relay is not instantaneous, so a peer's action lands while
--            this side is somewhere in the middle of its own turn
--
-- None of those may change the outcome: a lockstep battle is decided by the
-- two actions and the shared RNG stream, nothing else.  What they DID change
-- was when each machine wrote per-turn bookkeeping flags, and the state hash
-- read `false`/`0` against `nil` as a divergence and ended winnable matches
-- as draws (LinkBattle's `off`, BattleState's per-battler flinch clear, and
-- fightLockedAction no longer storing its boundTurns mirror).
--
-- Self-contained; run directly or via run_link_tests.lua:
--   luajit tests/link_desync_fuzz.lua [runs] [firstSeed]

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Data = require("src.core.Data")
if not Data.pokemon then Data:load() end
local Pokemon = require("src.pokemon.Pokemon")
local Protocol = require("src.link.Protocol")
local Net = require("src.link.Net")
local Json = require("src.link.Json")
local Input = require("src.core.Input")
local LinkBattle = require("src.link.LinkBattle")
Input:init()
require("src.render.Font").load(Data)

-- one PRNG per run so a failure replays from its seed alone
local function makeRandom(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(a, b)
    s = (s * 16807) % 2147483647
    if a == nil then return s / 2147483647 end
    if b == nil then a, b = 1, a end
    return a + (s % (b - a + 1))
  end
end

local SPECIES = {}
for id in pairs(Data.pokemon) do SPECIES[#SPECIES + 1] = id end
table.sort(SPECIES) -- pairs order is not stable; the seed has to be the only input
local MOVES = {}
for id, m in pairs(Data.moves) do
  if id ~= "STRUGGLE" and m.pp and m.pp > 0 then MOVES[#MOVES + 1] = id end
end
table.sort(MOVES)

-- a loopback pair that holds each message for `delay` pumps before it lands
-- in the peer's inbox, so one side is mid-queue when the other's action
-- arrives (Net.loopbackPair on its own delivers instantly, which is the one
-- thing the real relay never does)
-- mutation mode: a peer whose messages arrive with a random field (or the
-- type itself) at the wrong Lua type.  What is delivered is what Session
-- would deliver -- Wire.sanitize's output, or nothing at all -- so a run
-- exercises the real receive path rather than a hand-written stand-in.
local Wire = require("src.link.Wire")
local HOSTILE = { {}, { 1, 2, 3 }, 0, -1, 999, "s", "", true, false, math.huge }

local function mutate(rnd, msg)
  local keys = {}
  for k in pairs(msg) do
    if k ~= "type" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  if #keys == 0 or rnd(1, 100) <= 20 then
    msg.type = HOSTILE[rnd(1, #HOSTILE)]
  else
    msg[keys[rnd(1, #keys)]] = HOSTILE[rnd(1, #HOSTILE)]
  end
  return msg
end

local function laggyPair(delayA, delayB, rnd, mutateRate)
  local a, b = Net.loopbackPair()
  a.wire, b.wire = {}, {}
  a.delay, b.delay = delayA or 0, delayB or 0
  a.mutateRate, b.mutateRate = mutateRate or 0, mutateRate or 0
  local function send(self, msg)
    if self.closed then return end
    local decoded = Json.decode(Json.encode(msg)) -- same round trip as the wire
    if decoded and self.mutateRate > 0 then
      if rnd(1, 100) <= self.mutateRate then decoded = mutate(rnd, decoded) end
      decoded = Wire.sanitize(decoded)
    end
    if decoded then table.insert(self.wire, { msg = decoded, at = self.delay }) end
  end
  local function update(self)
    for i = #self.wire, 1, -1 do
      local row = self.wire[i]
      row.at = row.at - 1
      if row.at <= 0 then
        table.remove(self.wire, i)
        if not self.peerEnd.closed then table.insert(self.peerEnd.inbox, row.msg) end
      end
    end
  end
  a.send, b.send = send, send
  a.update, b.update = update, update
  return a, b
end

local function makeFakeGame(name, options)
  local save = require("src.core.SaveData").newGame()
  save.player.name = name
  for k, v in pairs(options or {}) do save.options[k] = v end
  local stack = { list = {} }
  function stack:push(s, ...)
    table.insert(self.list, s)
    if s.enter then s:enter(...) end
  end
  function stack:pop() table.remove(self.list) end
  function stack:top() return self.list[#self.list] end
  function stack:update(dt)
    local t = self:top()
    if t and t.update then t:update(dt) end
  end
  return { data = Data, input = Input, stack = stack, save = save }
end

-- random movesets, not level-up ones: status, trapping, thrash, bide,
-- Hyper Beam and Rage are where the locked-action paths live
local function randomParty(rnd, size)
  local party = {}
  for _ = 1, size do
    local mon = Pokemon.new(Data, SPECIES[rnd(1, #SPECIES)], rnd(5, 60))
    mon.moves = {}
    for _ = 1, rnd(1, 4) do
      local id = MOVES[rnd(1, #MOVES)]
      table.insert(mon.moves, { id = id, pp = Data.moves[id].pp })
    end
    party[#party + 1] = mon
  end
  return party
end

local PARTS = { "actives", "volatile", "bench" }
local function firstMismatch(a, b)
  local turns = {}
  for t in pairs(a.localParts) do turns[t] = true end
  for t in pairs(b.localParts) do turns[t] = true end
  local ordered = {}
  for t in pairs(turns) do ordered[#ordered + 1] = t end
  table.sort(ordered)
  for _, t in ipairs(ordered) do
    local mine, theirs = a.localParts[t], b.localParts[t]
    if mine and theirs then
      for _, part in ipairs(PARTS) do
        if mine[part] ~= theirs[part] then return t, part end
      end
    end
  end
end

-- Returns nil when the run agreed, or a description of how it split.
local function runOne(seed, mutateRate)
  local rnd = makeRandom(seed)
  -- the two sides are deliberately different clients
  local optsA = { animations = false, textSpeed = 1, battleStyle = "SET" }
  local optsB = { animations = true, textSpeed = 3, battleStyle = "SHIFT" }
  local stepsA, stepsB = rnd(1, 4), 1   -- A fast-forwards, B does not
  local lagA, lagB = rnd(0, 8), rnd(0, 8)

  local gameA, gameB = makeFakeGame("RED", optsA), makeFakeGame("BLUE", optsB)
  gameA.save.party = randomParty(rnd, rnd(1, 4))
  gameB.save.party = randomParty(rnd, rnd(1, 4))

  local netA, netB = laggyPair(lagA, lagB, rnd, mutateRate)
  local battleSeed = rnd(1, 2 ^ 30)
  local battleA = LinkBattle.newHost(gameA, netA, {
    myParty = Protocol.packParty(gameA.save.party),
    theirParty = Protocol.packParty(gameB.save.party),
    theirName = "BLUE", seed = battleSeed })
  local battleB = LinkBattle.newGuest(gameB, netB, {
    myParty = Protocol.packParty(gameB.save.party),
    theirParty = Protocol.packParty(gameA.save.party),
    theirName = "RED", seed = battleSeed })
  if not battleA or not battleB then return nil, 0 end

  local resA, resB
  battleA.onFinish = function(r) resA = r end
  battleB.onFinish = function(r) resB = r end
  gameA.stack:push(battleA)
  gameB.stack:push(battleB)

  local sides = {
    { bt = battleA, game = gameA, party = battleA.playerParty, steps = stepsA },
    { bt = battleB, game = gameB, party = battleB.playerParty, steps = stepsB },
  }

  -- Only the cursor is steered; A (held below) does the committing, so the
  -- battle is reached through DisplayBattleMenu exactly as a player reaches
  -- it and every locked action (recharge / thrash / rage / bide / trapping /
  -- bound / Struggle) fires from its own code path rather than being
  -- injected.  A switch waits for a second menu frame for the same reason:
  -- the real PKMN branch sits behind the menu-entry bookkeeping.
  local function drive(side)
    local bt = side.bt
    if bt.result then return end
    local top = side.game.stack:top()
    if top and top.forceSwitch and top.party then
      for i, mon in ipairs(top.party) do
        if mon.hp > 0 then top.index = i break end
      end
      return
    end
    if bt.phase ~= "menu" then side.menuFrames = 0 end
    if bt.phase == "moveSelect" then
      local usable = {}
      for i, mv in ipairs(bt.player.curMoves) do
        if (mv.pp or 0) > 0 and bt.player.disabledSlot ~= i then usable[#usable + 1] = i end
      end
      if #usable > 0 then bt.moveIndex = usable[rnd(1, #usable)] end
      bt.menuIndex = 1
    elseif bt.phase == "menu" then
      bt.menuIndex = 1 -- FIGHT
      side.menuFrames = (side.menuFrames or 0) + 1
      if side.menuFrames >= 2 and not bt:menuLockedAction(bt.player)
         and rnd(1, 100) <= 10 then
        for _ = 1, 4 do
          local mon = side.party[rnd(1, #side.party)]
          if mon.hp > 0 and mon ~= bt.player.mon then
            bt:resolveSwitch(mon)
            side.menuFrames = 0
            return
          end
        end
      end
    end
  end

  local guard = 0
  while (resA == nil or resB == nil) and guard < 60000 do
    guard = guard + 1
    Input.pressed = { a = true }
    for _, side in ipairs(sides) do
      for _ = 1, side.steps do
        drive(side)
        side.game.stack:update(1 / 60)
      end
    end
    local turn, part = firstMismatch(battleA, battleB)
    if turn and mutateRate then
      -- a corrupted action IS a divergence; what matters here is that the
      -- match ends by its own rules (desync draw, forfeit, disconnect)
      -- rather than throwing
      return nil, battleA.turnCount or 0
    end
    if turn then
      return ("seed %d: turn %d %s split (lag %d/%d, steps %d/%d)"):format(
        seed, turn, part, lagA, lagB, stepsA, stepsB), battleA.turnCount or 0
    end
  end
  -- a battle still running at the guard is a stalemate (two mons that cannot
  -- KO each other), not a split; only a finished one can be checked mirrored
  if not mutateRate and guard < 60000
     and (battleA.player.mon.hp ~= battleB.enemy.mon.hp
          or battleA.enemy.mon.hp ~= battleB.player.mon.hp) then
    return ("seed %d: final HP not mirrored (%d/%d vs %d/%d)"):format(
      seed, battleA.player.mon.hp, battleA.enemy.mon.hp,
      battleB.enemy.mon.hp, battleB.player.mon.hp), battleA.turnCount or 0
  end
  return nil, battleA.turnCount or 0
end

local RUNS = tonumber(arg and arg[1]) or 40
local FIRST = tonumber(arg and arg[2]) or 1

local MUTATION_RUNS = tonumber(arg and arg[3]) or math.max(4, math.floor(RUNS / 4))

local failures, turns = 0, 0
for seed = FIRST, FIRST + RUNS - 1 do
  local ok, why, t = pcall(runOne, seed)
  turns = turns + (t or 0)
  if not ok then
    failures = failures + 1
    print("FAIL link desync fuzz seed " .. seed .. ": " .. tostring(why))
  elseif why then
    failures = failures + 1
    print("FAIL link desync fuzz " .. why)
  end
end
print(("link desync fuzz: %d runs, %d turns, %d failures"):format(RUNS, turns, failures))

local mutationFailures = 0
for seed = FIRST, FIRST + MUTATION_RUNS - 1 do
  local ok, why = pcall(runOne, seed, 15)
  if not ok then
    mutationFailures = mutationFailures + 1
    print("FAIL link mutation fuzz seed " .. seed .. ": " .. tostring(why))
  elseif why then
    mutationFailures = mutationFailures + 1
    print("FAIL link mutation fuzz " .. why)
  end
end
print(("link mutation fuzz: %d runs, %d failures"):format(
  MUTATION_RUNS, mutationFailures))

assert(failures == 0, failures .. " lockstep run(s) diverged")
assert(mutationFailures == 0, mutationFailures .. " mutated run(s) threw")
return true
