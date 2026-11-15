-- Gen 2 lockstep desync fuzz, modelled on tests/link_desync_fuzz.lua.
--
--   luajit tests/link2_desync_fuzz.lua [runs] [firstSeed]
--
-- tests/link2_lockstep.lua battles a handful of fixed pairings with the A
-- button held, which reaches one code path: move slot 1, no status, no lock,
-- no weather.  Every desync a lockstep engine actually suffers lives outside
-- it, so this walks the rest -- random multi-mon parties with random
-- movesets and held items, random move choices, voluntary switches, faints
-- and replacements -- with the two sides deliberately NOT identical clients:
--
--   speed  one side takes several fixed steps per frame while the other
--          takes one, so each machine is at a different point in its own
--          message queue when the peer's action lands
--   lag    the relay is not instantaneous, so an action arrives while this
--          side is mid-turn
--
-- None of that may change the outcome: a lockstep battle is decided by the
-- two actions and the shared RNG stream and nothing else.  ROM-free, like
-- tests/link2_lockstep.lua: the dataset below is a Gen 2 shaped fixture.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

require("src.core.Logger").warn = function() end

local Json = require("src.link.Json")
local LinkBattle2 = require("src.link.LinkBattle2")
local Mon = require("src.battle.gen2.Mon")
local Net = require("src.link.Net")
local Protocol = require("src.link.Protocol")

-- one PRNG per run so a failure replays from its seed alone
local function makeRandom(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(a, b)
    s = (s * 16807) % 2147483647
    if b == nil then a, b = 1, a end
    return a + (s % (b - a + 1))
  end
end

-- ---------------------------------------------------------------- fixture

local TYPE_IDS = { "NORMAL", "FIRE", "WATER", "GRASS", "GHOST" }
local TYPES = {}
for index, id in ipairs(TYPE_IDS) do
  TYPES[id] = { id = id, index = index - 1,
    category = (id == "FIRE" or id == "WATER" or id == "GRASS")
      and "special" or "physical" }
end

-- A chart with real supereffective / resisted / immune cells, so damage is
-- not one flat number and the Ghost immunity exercises the miss path.
local MATCHUPS = {
  { attacker = "FIRE", defender = "GRASS", multiplier = 20 },
  { attacker = "GRASS", defender = "WATER", multiplier = 20 },
  { attacker = "WATER", defender = "FIRE", multiplier = 20 },
  { attacker = "FIRE", defender = "WATER", multiplier = 5 },
  { attacker = "GRASS", defender = "FIRE", multiplier = 5 },
  { attacker = "WATER", defender = "GRASS", multiplier = 5 },
  { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
}

local function move(id, kind, power, effect, chance, chanceRaw)
  return { id = id, name = id, power = power, type = kind,
    accuracy = 95, accuracyRaw = 242, pp = 15, effect = effect, effectChance = chance,
    effectChanceRaw = chanceRaw or 0 }
end

local MOVES = {
  STRUGGLE = move("STRUGGLE", "NORMAL", 50, "EFFECT_NORMAL_HIT"),
  HIT_A = move("HIT_A", "NORMAL", 40, "EFFECT_NORMAL_HIT"),
  HIT_B = move("HIT_B", "FIRE", 45, "EFFECT_NORMAL_HIT"),
  HIT_C = move("HIT_C", "WATER", 45, "EFFECT_NORMAL_HIT"),
  HIT_D = move("HIT_D", "GRASS", 45, "EFFECT_NORMAL_HIT"),
  QUICK = move("QUICK", "NORMAL", 25, "EFFECT_PRIORITY_HIT"),
  MULTI = move("MULTI", "NORMAL", 15, "EFFECT_MULTI_HIT"),
  DRAIN = move("DRAIN", "GRASS", 30, "EFFECT_LEECH_HIT"),
  RECOIL = move("RECOIL", "NORMAL", 60, "EFFECT_RECOIL_HIT"),
  FLINCHER = move("FLINCHER", "NORMAL", 25, "EFFECT_FLINCH_HIT", 30, 76),
  POISON_JAB = move("POISON_JAB", "NORMAL", 25, "EFFECT_POISON_HIT", 40, 102),
  BURNER = move("BURNER", "FIRE", 25, "EFFECT_BURN_HIT", 40, 102),
  ZAPPER = move("ZAPPER", "NORMAL", 25, "EFFECT_PARALYZE_HIT", 40, 102),
  MUDDLER = move("MUDDLER", "WATER", 25, "EFFECT_CONFUSE_HIT", 40, 102),
  SLEEPER = move("SLEEPER", "NORMAL", 0, "EFFECT_SLEEP"),
  VENOM = move("VENOM", "NORMAL", 0, "EFFECT_TOXIC"),
  SCARE = move("SCARE", "GHOST", 0, "EFFECT_CONFUSE"),
  GROWLER = move("GROWLER", "NORMAL", 0, "EFFECT_ATTACK_DOWN"),
  HARDEN = move("HARDEN", "NORMAL", 0, "EFFECT_DEFENSE_UP"),
  AGILE = move("AGILE", "NORMAL", 0, "EFFECT_SPEED_UP_2"),
  WRAPPER = move("WRAPPER", "NORMAL", 20, "EFFECT_TRAP_TARGET"),
  THRASHER = move("THRASHER", "NORMAL", 45, "EFFECT_RAMPAGE"),
  BOULDER = move("BOULDER", "NORMAL", 25, "EFFECT_ROLLOUT"),
  CURL = move("CURL", "NORMAL", 0, "EFFECT_DEFENSE_CURL"),
  BEAM = move("BEAM", "NORMAL", 80, "EFFECT_HYPER_BEAM"),
  DIVE = move("DIVE", "WATER", 60, "EFFECT_FLY"),
  SEEDER = move("SEEDER", "GRASS", 0, "EFFECT_LEECH_SEED"),
  DUMMY = move("DUMMY", "NORMAL", 0, "EFFECT_SUBSTITUTE"),
  SHIELD = move("SHIELD", "NORMAL", 0, "EFFECT_PROTECT"),
  GLASS = move("GLASS", "NORMAL", 0, "EFFECT_LIGHT_SCREEN"),
  MIRROR = move("MIRROR", "NORMAL", 0, "EFFECT_REFLECT"),
  CALTROPS = move("CALTROPS", "NORMAL", 0, "EFFECT_SPIKES"),
  DIRGE = move("DIRGE", "NORMAL", 0, "EFFECT_PERISH_SONG"),
  RERUN = move("RERUN", "NORMAL", 0, "EFFECT_ENCORE"),
  STORM = move("STORM", "NORMAL", 0, "EFFECT_SANDSTORM"),
  DELUGE = move("DELUGE", "WATER", 0, "EFFECT_RAIN_DANCE"),
  HEX = move("HEX", "GHOST", 0, "EFFECT_CURSE"),
  SIGHT = move("SIGHT", "NORMAL", 0, "EFFECT_LOCK_ON"),
  RAGER = move("RAGER", "NORMAL", 20, "EFFECT_RAGE"),
  MENDER = move("MENDER", "NORMAL", 0, "EFFECT_HEAL"),
}

local MOVE_POOL = {}
for id in pairs(MOVES) do
  if id ~= "STRUGGLE" then MOVE_POOL[#MOVE_POOL + 1] = id end
end
table.sort(MOVE_POOL) -- pairs order is not stable; the seed is the only input

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = { growthRates = GROWTH }
local SPECIES = {}
do
  local rows = {
    { "ALFAMON", "NORMAL", "NORMAL", 45, 60, 45, 85, 50, 45 },
    { "BETAMON", "FIRE", "NORMAL", 60, 55, 60, 45, 65, 55 },
    { "GAMMAMON", "WATER", "WATER", 70, 45, 70, 30, 55, 70 },
    { "DELTAMON", "GRASS", "GHOST", 55, 65, 40, 60, 70, 45 },
    { "EPSILMON", "GHOST", "GHOST", 50, 50, 55, 55, 60, 60 },
  }
  for index, row in ipairs(rows) do
    POKEMON[row[1]] = {
      id = row[1], index = index, name = row[1],
      baseStats = { hp = row[4], attack = row[5], defense = row[6],
        speed = row[7], specialAttack = row[8], specialDefense = row[9] },
      types = { row[2], row[3] }, catchRate = 45, baseExp = 65,
      growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
      levelMoves = { { level = 1, move = "HIT_A" } }, evolutions = {},
    }
    SPECIES[#SPECIES + 1] = row[1]
  end
end
table.sort(SPECIES)

local ITEMS = {
  LEFTOVERS = { id = "LEFTOVERS", index = 1, name = "LEFTOVERS",
    pocket = "ITEM", heldEffect = "HELD_LEFTOVERS" },
  KINGS_ROCK = { id = "KINGS_ROCK", index = 2, name = "KING'S ROCK",
    pocket = "ITEM", heldEffect = "HELD_FLINCH", heldParameter = 30 },
  QUICK_CLAW = { id = "QUICK_CLAW", index = 3, name = "QUICK CLAW",
    pocket = "ITEM", heldEffect = "HELD_QUICK_CLAW", heldParameter = 60 },
  FOCUS_BAND = { id = "FOCUS_BAND", index = 4, name = "FOCUS BAND",
    pocket = "ITEM", heldEffect = "HELD_FOCUS_BAND", heldParameter = 30 },
  BERRY = { id = "BERRY", index = 5, name = "BERRY", pocket = "ITEM",
    heldEffect = "HELD_BERRY", heldParameter = 10 },
  PSNCUREBERRY = { id = "PSNCUREBERRY", index = 6, name = "PSNCUREBERRY",
    pocket = "ITEM", heldEffect = "HELD_HEAL_POISON" },
  SCOPE_LENS = { id = "SCOPE_LENS", index = 7, name = "SCOPE LENS",
    pocket = "ITEM", heldEffect = "HELD_CRITICAL_UP" },
  BRIGHTPOWDER = { id = "BRIGHTPOWDER", index = 8, name = "BRIGHTPOWDER",
    pocket = "ITEM", heldEffect = "HELD_BRIGHTPOWDER", heldParameter = 20 },
}
local ITEM_POOL = {}
for id in pairs(ITEMS) do ITEM_POOL[#ITEM_POOL + 1] = id end
table.sort(ITEM_POOL)

local function engineFlagOrder()
  local order = {}
  for id, name in pairs(require("src.save_convert.data.gen2_engine_flags").gs) do order[id + 1] = name end
  return order
end

local DATA = {
  gen2Constants = { engineFlagOrder = engineFlagOrder() },
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = MATCHUPS,
    battleRules = require("tests.gen2_battle_rules_fixture")() },
  items = ITEMS,
  text = require("tests.gen2_battle_text_fixture")(),
}

-- ---------------------------------------------------------------- harness

local function fakeInput()
  local input = { button = nil }
  function input:wasPressed(button) return self.button == button end
  function input:isDown() return false end
  function input:step() end
  return input
end

local function makeGame(name, party)
  local stack = { list = {} }
  function stack:push(state, ...)
    table.insert(self.list, state)
    if state.enter then state:enter(...) end
  end
  function stack:pop() return table.remove(self.list) end
  function stack:top() return self.list[#self.list] end
  function stack:clear() self.list = {} end
  function stack:update(dt)
    local top = self:top()
    if top and top.update then top:update(dt) end
  end
  return {
    data = DATA,
    input = fakeInput(),
    stack = stack,
    options = {},
    save = { party = party, player = { name = name, id = 4242 },
             inventory = {}, pokedex = { seen = {}, caught = {} } },
  }
end

-- a loopback pair that holds each message for `delay` pumps before it lands
-- in the peer's inbox: Net.loopbackPair on its own delivers instantly, which
-- is the one thing a real relay never does
local function laggyPair(delayA, delayB)
  local a, b = Net.loopbackPair()
  a.wire, b.wire = {}, {}
  a.delay, b.delay = delayA or 0, delayB or 0
  local function send(self, msg)
    if self.closed then return end
    local decoded = Json.decode(Json.encode(msg))
    if decoded then table.insert(self.wire, { msg = decoded, at = self.delay }) end
  end
  local function update(self)
    for i = #self.wire, 1, -1 do
      local row = self.wire[i]
      row.at = row.at - 1
      if row.at <= 0 then
        table.remove(self.wire, i)
        if not self.peerEnd.closed then
          table.insert(self.peerEnd.inbox, row.msg)
        end
      end
    end
  end
  a.send, b.send = send, send
  a.update, b.update = update, update
  return a, b
end

local function randomParty(rnd, size)
  local party = {}
  for _ = 1, size do
    local mon = Mon.new(DATA, SPECIES[rnd(1, #SPECIES)], rnd(20, 40), {
      dvs = { attack = rnd(0, 15), defense = rnd(0, 15),
              speed = rnd(0, 15), special = rnd(0, 15) },
    })
    local moves, seen = {}, {}
    for _ = 1, 4 do
      local id = MOVE_POOL[rnd(1, #MOVE_POOL)]
      if not seen[id] then
        seen[id] = true
        moves[#moves + 1] = { id = id, pp = MOVES[id].pp,
                              maxPp = MOVES[id].pp }
      end
    end
    if #moves == 0 then
      moves[1] = { id = "HIT_A", pp = 15, maxPp = 15 }
    end
    mon.moves = moves
    if rnd(1, 100) <= 60 then mon.item = ITEM_POOL[rnd(1, #ITEM_POOL)] end
    party[#party + 1] = mon
  end
  return party
end

-- The screen drives itself from the pad, so the fuzz steers it the way the
-- lockstep suite does -- press A, and walk the cursor off a fainted slot --
-- plus a random move pick and the occasional voluntary switch.
local function drive(side, rnd)
  local screen = side.screen
  local game = side.game
  local top = game.stack:top()
  if top and top ~= screen then
    local mon = top.party and top.index and top.party[top.index]
    if not mon or (mon.hp or 0) <= 0 or mon.isEgg then
      -- walk to the first healthy slot rather than one step at a time, so a
      -- laggy run cannot spend its whole guard in the list
      for i, candidate in ipairs(top.party or {}) do
        if (candidate.hp or 0) > 0 and not candidate.isEgg then
          top.index = i
          break
        end
      end
    end
    game.input.button = "a"
    return
  end
  if screen.phase == "menu" then
    -- a voluntary switch now and then, which is the other action the wire
    -- carries and the one that re-enters the turn loop without a move
    if rnd(1, 100) <= 8 then
      for _ = 1, 4 do
        local index = rnd(1, #screen.battle.party)
        local mon = screen.battle.party[index]
        if (mon.hp or 0) > 0 and mon ~= screen.battle.player
            and not screen.battle:switchLocked() then
          screen:submit({ kind = "switch", index = index })
          game.input.button = nil
          return
        end
      end
    end
    screen.menuIndex = 1 -- FIGHT
  elseif screen.phase == "moves" then
    local usable = {}
    for i, mv in ipairs(screen.battle.player.moves or {}) do
      if (mv.pp or 0) > 0
          and not screen.battle:moveDisabled(screen.battle.player, mv.id) then
        usable[#usable + 1] = i
      end
    end
    if #usable > 0 then screen.moveIndex = usable[rnd(1, #usable)] end
  end
  game.input.button = "a"
end

LinkBattle2.keepSignatures = true

local function firstSplit(a, b)
  local found
  for turn, value in pairs(a.localHashes or {}) do
    local other = (b.localHashes or {})[turn]
    if other and other ~= value and (not found or turn < found) then
      found = turn
    end
  end
  return found
end

-- The strings behind the digests, so a failure names the component and shows
-- both sides of it rather than two hex blobs.
local function splitDetail(a, b, turn)
  local mine = (a.linkSignatures or {})[turn]
  local theirs = (b.linkSignatures or {})[turn]
  if not (mine and theirs) then return "" end
  for _, part in ipairs({ "actives", "volatile", "bench" }) do
    if mine[part] ~= theirs[part] then
      return ("\n  %s:\n    host  %s\n    guest %s"):format(part, mine[part],
        theirs[part])
    end
  end
  return ""
end

local function runOne(seed)
  local rnd = makeRandom(seed)
  local lagA, lagB = rnd(0, 3), rnd(0, 3)
  local stepsA, stepsB = rnd(1, 3), rnd(1, 3)
  local netA, netB = laggyPair(lagA, lagB)

  local partyA = randomParty(rnd, rnd(1, 4))
  local partyB = randomParty(rnd, rnd(1, 4))
  local gameA = makeGame("GOLD", partyA)
  local gameB = makeGame("SILVER", partyB)
  local packedA = Protocol.packParty2(partyA)
  local packedB = Protocol.packParty2(partyB)
  local battleSeed = rnd(1, 2147483000)

  local host, hostErr = LinkBattle2.newHost(gameA, netA, {
    myParty = packedA, theirParty = packedB, theirName = "SILVER",
    seed = battleSeed, verdict = "full", strict = true, keepNetOpen = true,
  })
  local guest, guestErr = LinkBattle2.newGuest(gameB, netB, {
    myParty = packedB, theirParty = packedA, theirName = "GOLD",
    seed = battleSeed, verdict = "full", strict = true, keepNetOpen = true,
  })
  if not host then return ("seed %d: host refused (%s)"):format(seed, tostring(hostErr)) end
  if not guest then return ("seed %d: guest refused (%s)"):format(seed, tostring(guestErr)) end

  local sides = {
    { game = gameA, screen = host, steps = stepsA },
    { game = gameB, screen = guest, steps = stepsB },
  }
  for _, side in ipairs(sides) do
    side.screen.onFinish = function(result) side.result = result end
    side.game.stack:push(side.screen)
  end

  local guard = 0
  while (sides[1].result == nil or sides[2].result == nil) and guard < 40000 do
    guard = guard + 1
    for _, side in ipairs(sides) do
      for _ = 1, side.steps do
        drive(side, rnd)
        side.game.stack:update(1 / 60)
        side.game.input.button = nil
        side.game.stack:update(1 / 60)
      end
    end
    local turn = firstSplit(host, guest)
    if turn then
      return ("seed %d: turn %d hash split (lag %d/%d, steps %d/%d)%s"):format(
        seed, turn, lagA, lagB, stepsA, stepsB, splitDetail(host, guest, turn)),
        host.battle.turn or 0
    end
  end

  -- a battle still running at the guard is a stalemate (two mons that cannot
  -- KO each other), not a split; only a finished one can be checked mirrored
  if sides[1].result and sides[2].result then
    if host.battle.player.hp ~= guest.battle.enemy.hp
        or host.battle.enemy.hp ~= guest.battle.player.hp then
      return ("seed %d: final HP not mirrored (%d/%d vs %d/%d)"):format(
        seed, host.battle.player.hp, host.battle.enemy.hp,
        guest.battle.enemy.hp, guest.battle.player.hp), host.battle.turn or 0
    end
    if host.battle.rngDraws ~= guest.battle.rngDraws then
      return ("seed %d: rng draw counts differ (%d vs %d)"):format(
        seed, host.battle.rngDraws or -1, guest.battle.rngDraws or -1),
        host.battle.turn or 0
    end
    local a, b = sides[1].result, sides[2].result
    local agrees = (a == "win" and b == "lose") or (a == "lose" and b == "win")
      or (a == "draw" and b == "draw")
    if not agrees then
      return ("seed %d: results disagree (%s vs %s)"):format(seed, tostring(a),
        tostring(b)), host.battle.turn or 0
    end
  end
  return nil, host.battle.turn or 0
end

local RUNS = tonumber(arg and arg[1]) or 40
local FIRST = tonumber(arg and arg[2]) or 1

local failures, turns = 0, 0
for seed = FIRST, FIRST + RUNS - 1 do
  local ok, why, t = pcall(runOne, seed)
  turns = turns + (t or 0)
  if not ok then
    failures = failures + 1
    print("FAIL gen2 desync fuzz seed " .. seed .. ": " .. tostring(why))
  elseif why then
    failures = failures + 1
    print("FAIL gen2 desync fuzz " .. why)
  end
end
print(("gen2 link desync fuzz: %d runs, %d turns, %d failures"):format(
  RUNS, turns, failures))

assert(failures == 0, failures .. " Gen 2 lockstep run(s) diverged")
return true
