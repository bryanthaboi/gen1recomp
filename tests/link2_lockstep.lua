-- Gen 2 lockstep link battles (src/link/LinkBattle2.lua), the Gold peer of
-- the Gen 1 section in tests/run_link_tests.lua.
--
--   luajit tests/link2_lockstep.lua
--
-- ROM-free: the dataset below is a hand-written Gen 2 shaped fixture, the
-- same trick tests/gen2_battle_pack_test.lua uses, so this needs no
-- data/generated/gold.  Both peers run the REAL src/ui/gen2/BattleState over
-- the REAL src/battle/gen2/Battle, exchanging actions over
-- Net.loopbackPair(), and every assertion is about the two simulations
-- agreeing rather than about either one on its own.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local failures = 0
local function check(cond, msg)
  if cond then
    print("ok   " .. msg)
  else
    failures = failures + 1
    print("FAIL " .. msg)
  end
end
local function eq(got, want, msg)
  check(got == want, ("%s (got %s, want %s)"):format(msg, tostring(got),
                                                     tostring(want)))
end

require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local LinkBattle2 = require("src.link.LinkBattle2")
local Mon = require("src.battle.gen2.Mon")
local Net = require("src.link.Net")
local Protocol = require("src.link.Protocol")

-- ---------------------------------------------------------------- fixture

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  SCRATCH = { id = "SCRATCH", name = "SCRATCH", power = 40, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  STRUGGLE = { id = "STRUGGLE", name = "STRUGGLE", power = 50, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 1, effect = "EFFECT_NORMAL_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local function species(id, index, stats)
  return {
    id = id, index = index, name = id,
    baseStats = stats,
    types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  }
end

local POKEMON = {
  growthRates = GROWTH,
  QUICKMON = species("QUICKMON", 1, { hp = 45, attack = 50, defense = 40,
    speed = 90, specialAttack = 40, specialDefense = 40 }),
  SLOWMON = species("SLOWMON", 2, { hp = 60, attack = 45, defense = 50,
    speed = 20, specialAttack = 40, specialDefense = 45 }),
  TANKMON = species("TANKMON", 3, { hp = 70, attack = 40, defense = 60,
    speed = 35, specialAttack = 35, specialDefense = 50 }),
}

local ITEMS = {
  -- Battle:tickHeldItem's residual arm and BattleCommand_EffectChance's
  -- flinch arm, the two held effects a link battle is most likely to split on.
  LEFTOVERS = { id = "LEFTOVERS", index = 1, name = "LEFTOVERS",
    pocket = "ITEM", heldEffect = "HELD_LEFTOVERS" },
  KINGS_ROCK = { id = "KINGS_ROCK", index = 2, name = "KING'S ROCK",
    pocket = "ITEM", heldEffect = "HELD_FLINCH", heldParameter = 30 },
}

local function engineFlagOrder()
  local order = {}
  for id, name in pairs(require("src.save_convert.data.gen2_engine_flags").gs) do order[id + 1] = name end
  return order
end

local DATA = {
  gen2Constants = { engineFlagOrder = engineFlagOrder() },
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = ITEMS,
}

local PERFECT = { attack = 15, defense = 15, speed = 15, special = 15 }
PERFECT.hp = Mon.hpDV(PERFECT)

local function fighter(id, level, item)
  local mon = Mon.new(DATA, id, level or 20, { dvs = PERFECT })
  mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 },
                { id = "SCRATCH", pp = 35, maxPp = 35 } }
  mon.item = item
  return mon
end

do
  local mon = fighter("QUICKMON", 12)
  mon.status = "poison"
  mon.hp = 1
  local packed = Protocol.packMon2(mon)
  local forced = assert(Protocol.unpackMon2(DATA, packed, { forceLevel = 50, strict = true }))
  eq(forced.level, 50, "Gen 2 forced-level party rebuilds at the agreed level")
  eq(forced.status, nil, "Gen 2 forced-level party clears the saved status")
  eq(forced.hp, forced.stats.hp, "Gen 2 forced-level party starts at full HP")
  local real = assert(Protocol.unpackMon2(DATA, packed, { forceLevel = "ANY", strict = true }))
  eq(real.level, 12, "Gen 2 ANY keeps the saved level")
  eq(real.status, "poison", "Gen 2 ANY keeps the saved status")
  eq(real.hp, 1, "Gen 2 ANY keeps the saved HP")
end

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
    save = { party = party, player = { name = name, id = 1234 },
             inventory = { POTION = 5 }, pokedex = { seen = {}, caught = {} } },
  }
end

-- The screen is on top of the stack until it opens the party list, and the
-- forced switch after a faint opens on the mon that just fainted -- so while a
-- list is up the press walks the cursor off a fainted slot before choosing,
-- exactly the way a player does.
local function buttonFor(game, screen)
  local top = game.stack:top()
  if top and top ~= screen then
    local mon = top.party and top.index and top.party[top.index]
    if not mon or (mon.hp or 0) <= 0 or mon.isEgg then return "down" end
  end
  return "a"
end

local function step(sides)
  for _, side in ipairs(sides) do
    side.game.input.button = buttonFor(side.game, side.screen)
    side.game.stack:update(1 / 60)
    side.game.input.button = nil
    side.game.stack:update(1 / 60)
  end
end

local function packedParty(party)
  return Protocol.packParty2(party)
end

-- Build one loopback match.  Returns the two sides, each carrying its own
-- game, screen and result.
local function newMatch(hostParty, guestParty, seed, opts)
  opts = opts or {}
  local netA, netB = Net.loopbackPair()
  local gameA = makeGame("GOLD", hostParty)
  local gameB = makeGame("SILVER", guestParty)
  local packedA, packedB = packedParty(hostParty), packedParty(guestParty)

  local host, hostErr = LinkBattle2.newHost(gameA, netA, {
    myParty = packedA, theirParty = packedB, theirName = "SILVER",
    seed = seed, verdict = "full", strict = true, keepNetOpen = true,
    turnLimit = opts.turnLimit,
  })
  local guest, guestErr = LinkBattle2.newGuest(gameB, netB, {
    myParty = packedB, theirParty = packedA, theirName = "GOLD",
    seed = seed, verdict = "full", strict = true, keepNetOpen = true,
    turnLimit = opts.turnLimit,
  })
  if not host then error("host: " .. tostring(hostErr)) end
  if not guest then error("guest: " .. tostring(guestErr)) end

  local sides = {
    { game = gameA, screen = host, net = netA, role = "host" },
    { game = gameB, screen = guest, net = netB, role = "guest" },
  }
  for _, side in ipairs(sides) do
    side.screen.onFinish = function(result) side.result = result end
    side.game.stack:push(side.screen)
  end
  return sides
end

local function drive(sides, cap)
  local frame = 0
  while frame < (cap or 20000) do
    frame = frame + 1
    step(sides)
    local done = true
    for _, side in ipairs(sides) do
      if side.result == nil then done = false end
    end
    if done then return frame end
  end
  return nil
end

local function hashSplit(a, b)
  for turn, value in pairs(a.localHashes or {}) do
    local other = (b.localHashes or {})[turn]
    if other and other ~= value then return turn end
  end
  return nil
end

-- ---------------------------------------------------------------- one duel

do
  local hostParty = { fighter("QUICKMON", 20) }
  local guestParty = { fighter("SLOWMON", 20) }
  local sides = newMatch(hostParty, guestParty, 987654321)
  local host, guest = sides[1].screen, sides[2].screen

  eq(host.battle.player.species, "QUICKMON", "the host leads with its own mon")
  eq(host.battle.enemy.species, "SLOWMON",
     "the guest's party became the host's enemy side")
  eq(guest.battle.enemy.species, "QUICKMON",
     "the host's party became the guest's enemy side")
  eq(host.battle.save, nil,
     "the lockstep battle carries no save, so no badge boost applies")
  eq(host.battle:hasBadge("badges", "ZEPHYR"), false,
     "...and every badge reads false on both sides")
  eq(host.battle:badgeTypeBoost(host.battle.player, "NORMAL"), false,
     "...including the type boost DoBadgeTypeBoosts would apply")

  local frames = drive(sides)
  check(frames ~= nil,
        ("a Gen 2 lockstep battle finishes on both sides (%s / %s)")
          :format(tostring(sides[1].result), tostring(sides[2].result)))
  local a, b = sides[1].result, sides[2].result
  check((a == "win" and b == "lose") or (a == "lose" and b == "win")
        or (a == "draw" and b == "draw"),
        ("the two simulations agree on the outcome (%s / %s)")
          :format(tostring(a), tostring(b)))
  eq(host.battle.player.hp, guest.battle.enemy.hp,
     "the host's mon has identical HP on both machines")
  eq(host.battle.enemy.hp, guest.battle.player.hp,
     "the guest's mon has identical HP on both machines")
  eq(hashSplit(host, guest), nil, "no hash split across the whole battle")
  check(next(host.localHashes) ~= nil, "hashes were actually exchanged")
  eq(host.battle.rngDraws, guest.battle.rngDraws,
     "both machines drew the same number of random numbers")
  eq(hostParty[1].hp, hostParty[1].stats.hp,
     "the real party is untouched (the battle used clamped copies)")
  eq(hostParty[1].experience, guest.battle.enemy.experience,
     "no experience is paid on the cable")
end

-- ---------------------------------------------------------------- faints
-- Three mons a side, so both sides face a forced replacement and the wire
-- carries `replace` in both directions.

do
  local hostParty = { fighter("QUICKMON", 15), fighter("SLOWMON", 18),
                      fighter("TANKMON", 20) }
  local guestParty = { fighter("SLOWMON", 15), fighter("QUICKMON", 18),
                       fighter("TANKMON", 20) }
  local sides = newMatch(hostParty, guestParty, 24680)
  local host, guest = sides[1].screen, sides[2].screen

  local frames = drive(sides, 60000)
  check(frames ~= nil,
        ("a three-a-side battle finishes on both sides (%s / %s)")
          :format(tostring(sides[1].result), tostring(sides[2].result)))
  local a, b = sides[1].result, sides[2].result
  check((a == "win" and b == "lose") or (a == "lose" and b == "win")
        or (a == "draw" and b == "draw"),
        "the two simulations agree after forced replacements")
  eq(hashSplit(host, guest), nil, "no hash split across the replacements")
  eq(host.battle.rngDraws, guest.battle.rngDraws,
     "the RNG streams stayed in step through the faints")
  for i = 1, 3 do
    eq(host.battle.party[i].hp, guest.battle.enemyParty[i].hp,
       "host bench slot " .. i .. " has identical HP on both machines")
    eq(host.battle.enemyParty[i].hp, guest.battle.party[i].hp,
       "guest bench slot " .. i .. " has identical HP on both machines")
  end
  local faints = 0
  for _, mon in ipairs(host.battle.party) do
    if (mon.hp or 0) <= 0 then faints = faints + 1 end
  end
  for _, mon in ipairs(host.battle.enemyParty) do
    if (mon.hp or 0) <= 0 then faints = faints + 1 end
  end
  check(faints >= 3, "the match actually ran through faints (" .. faints .. ")")
end

-- ---------------------------------------------------------------- held items

do
  local hostParty = { fighter("TANKMON", 25, "LEFTOVERS"),
                      fighter("SLOWMON", 25, "LEFTOVERS") }
  local guestParty = { fighter("QUICKMON", 25, "KINGS_ROCK"),
                       fighter("TANKMON", 25, "KINGS_ROCK") }
  local sides = newMatch(hostParty, guestParty, 1357911)
  local host, guest = sides[1].screen, sides[2].screen

  eq(host.battle.player.item, "LEFTOVERS", "the held item survives packMon2")
  eq(guest.battle.enemy.item, "LEFTOVERS", "...and reaches the peer's copy")
  eq(host.battle.enemy.item, "KINGS_ROCK", "the foe's item comes over too")

  local frames = drive(sides, 60000)
  check(frames ~= nil,
        ("a held-item battle finishes on both sides (%s / %s)")
          :format(tostring(sides[1].result), tostring(sides[2].result)))
  eq(hashSplit(host, guest), nil,
     "Leftovers and King's Rock stay in sync across the wire")
  eq(host.battle.rngDraws, guest.battle.rngDraws,
     "...including the flinch rolls King's Rock adds")
  eq(host.battle.player.hp, guest.battle.enemy.hp,
     "the Leftovers holder's HP matches on both machines")
end

-- ---------------------------------------------------------------- cable rules

do
  local sides = newMatch({ fighter("QUICKMON", 20) },
                         { fighter("SLOWMON", 20) }, 4242)
  local host = sides[1].screen
  for _ = 1, 400 do
    step(sides)
    if host.phase == "menu" then break end
  end
  eq(host.phase, "menu", "the host reaches its own battle menu")

  host:chooseMenu("item")
  eq(host.phase, "refuse-menu", "the PACK is refused in a link battle")
  check((host.message or ""):find("Items") ~= nil,
        "...with the cable's own line: " .. tostring(host.message))

  host.phase = "menu"
  host:chooseMenu("run")
  eq(host.phase, "refuse-menu", "RUN is refused in a link battle")

  host.phase = "menu"
  eq(host:chooseMenu("fight"), true, "FIGHT still opens the move list")
  eq(host.phase, "moves", "...and reaches the move menu")
end

-- ---------------------------------------------------------------- no love.math
-- Rule 7 of .bazinga/online-handoff-rules.md: nothing on the link path may
-- roll love.math.random or read game.options.  Both peers run a whole battle
-- with love.math.random replaced by a throw.

do
  local saved = love.math.random
  love.math.random = function()
    error("love.math.random reached the link path", 2)
  end
  local ok, err = pcall(function()
    local sides = newMatch({ fighter("QUICKMON", 20), fighter("TANKMON", 22) },
                           { fighter("SLOWMON", 20), fighter("QUICKMON", 22) },
                           555777)
    local frames = drive(sides, 60000)
    if not frames then error("the battle did not finish") end
    if hashSplit(sides[1].screen, sides[2].screen) then
      error("hash split under the throwing rng")
    end
  end)
  love.math.random = saved
  check(ok, "a whole Gen 2 link battle rolls no love.math.random: "
        .. tostring(err))
end

-- ---------------------------------------------------------------- signature

do
  local hostParty = { fighter("QUICKMON", 20, "LEFTOVERS") }
  local guestParty = { fighter("SLOWMON", 20) }
  local sides = newMatch(hostParty, guestParty, 31337)
  local host, guest = sides[1].screen, sides[2].screen

  local hSig = host.battle:linkSignature("host")
  local gSig = guest.battle:linkSignature("guest")
  eq(hSig.actives, gSig.actives,
     "the two machines sign the same actives string at turn 0")
  eq(hSig.bench, gSig.bench, "...and the same bench string")
  eq(hSig.volatile, gSig.volatile, "...and the same volatile string")
  check(hSig.actives:find("LEFTOVERS", 1, true) ~= nil,
        "the held item is inside the actives component")
  check(hSig.actives:find("|r0", 1, true) ~= nil,
        "the rng draw counter rides the actives component")

  -- the components are what a mismatch NAMES: move one and only that one moves
  host.battle.weather = "rain"
  host.battle.weatherTurns = 5
  local moved = host.battle:linkSignature("host")
  eq(moved.actives, hSig.actives, "weather does not disturb the actives")
  check(moved.volatile ~= hSig.volatile, "weather lands in the volatile part")
  host.battle.weather, host.battle.weatherTurns = nil, 0

  host.battle.party[1].hp = host.battle.party[1].hp - 1
  local hurt = host.battle:linkSignature("host")
  check(hurt.actives ~= hSig.actives, "a HP change lands in the actives")
  check(hurt.bench ~= hSig.bench, "...and in the bench, which is fatal too")
end

-- ---------------------------------------------------------------- spectator

do
  local hostParty = { fighter("QUICKMON", 18), fighter("TANKMON", 20) }
  local guestParty = { fighter("SLOWMON", 18), fighter("QUICKMON", 20) }
  local seed = 8080808
  local sides = newMatch(hostParty, guestParty, seed)

  -- The relay's spectate envelope: every action and replace the two real
  -- players send, tagged with the side that sent it.
  local specNet = Net.loopbackPair()
  local feed = {}
  for _, side in ipairs(sides) do
    local realSend = side.net.send
    local tag = side.role
    side.net.send = function(self, msg)
      if msg.type == "action" or msg.type == "replace" or msg.type == "bye" then
        feed[#feed + 1] = { type = "spectate", side = tag, msg = msg }
      end
      return realSend(self, msg)
    end
  end

  local specGame = makeGame("WATCHER", {})
  local inbox = {}
  local specNetStub = {
    closed = false,
    update = function() end,
    poll = function()
      local out = inbox
      inbox = {}
      return out
    end,
    send = function() end,
    close = function(self) self.closed = true end,
  }
  local spectator, specErr = LinkBattle2.newSpectator(specGame, specNetStub, {
    hostParty = packedParty(hostParty), guestParty = packedParty(guestParty),
    hostName = "GOLD", guestName = "SILVER", seed = seed,
    verdict = "full", strict = true, keepNetOpen = true,
  })
  check(spectator ~= nil, "the spectator builds: " .. tostring(specErr))
  local specResult
  spectator.onFinish = function(r) specResult = r end
  specGame.stack:push(spectator)

  local frame = 0
  while frame < 60000 do
    frame = frame + 1
    step(sides)
    for _, msg in ipairs(feed) do table.insert(inbox, msg) end
    feed = {}
    specGame.input.button = "a"
    specGame.stack:update(1 / 60)
    specGame.input.button = nil
    specGame.stack:update(1 / 60)
    if sides[1].result and sides[2].result and specResult then break end
  end

  check(sides[1].result ~= nil and sides[2].result ~= nil,
        "the spectated match finished for both players")
  check(specResult ~= nil, "the spectator finished too: " .. tostring(specResult))
  local host = sides[1].screen
  eq(spectator.battle.player.species, host.battle.player.species,
     "the spectator's host side is the host's own mon")
  eq(spectator.battle.player.hp, host.battle.player.hp,
     "the spectator converged on the host's HP")
  eq(spectator.battle.enemy.hp, host.battle.enemy.hp,
     "...and on the guest's")
  for i = 1, 2 do
    eq(spectator.battle.party[i].hp, host.battle.party[i].hp,
       "spectator host bench slot " .. i .. " converged")
    eq(spectator.battle.enemyParty[i].hp, host.battle.enemyParty[i].hp,
       "spectator guest bench slot " .. i .. " converged")
  end
end

-- ---------------------------------------------------------------- forfeit

do
  local sides = newMatch({ fighter("QUICKMON", 20) },
                         { fighter("SLOWMON", 20) }, 606060)
  local host, guest = sides[1].screen, sides[2].screen
  for _ = 1, 2000 do
    step(sides)
    if host.phase == "menu" or host.phase == "moves" then break end
  end
  guest.update(guest, 1 / 60)
  -- The peer's own shot clock ran out: unlike a mutual draw this has a winner.
  sides[1].net:send({ type = "forfeit" })
  for _ = 1, 400 do
    step(sides)
    if guest.result then break end
  end
  eq(guest.result, "win", "a forfeit from the peer is a win for the other side")
end

print(("\n%s"):format(failures == 0 and "ALL GEN 2 LOCKSTEP TESTS PASSED"
                      or failures .. " FAILURES"))
if failures > 0 then error("link2 lockstep failures: " .. failures, 0) end
