package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available({ "red" }) then
  print("gen1_sleep_battle skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local G1 = require("tests.fixtures.save.gen1_build")
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local Game = require("src.core.Game")
local SaveConvert = require("src.save_convert.SaveConvert")
local BattleState = require("src.battle.BattleState")
local Status = require("src.battle.Status")
local MoveEffects = require("src.battle.MoveEffects")
local Protocol = require("src.link.Protocol")
local Wire = require("src.link.Wire")
local Json = require("src.link.Json")

local O = GenSave.OFFSETS
local PARTY_STATUS = O.partyMons + 4

local function cartWithStatus(n)
  return G1.build({ version = "red", party = { G1.mon({ status = n, nick = "NAPPY" }), G1.mon({ nick = "BENCH" }) } })
end

local function importSave(bytes)
  K.gen1Data("red")
  return assert(SaveConvert.importSav(bytes, "red", "red"))
end

local function battleFor(save)
  Game.data = Data
  Game.save = save
  return BattleState.newWild(Game, "PIDGEY", 5)
end

local function stubText(b)
  b.sayNext = function() end
  b.statusOnomatopoeia = function() end
  b.queue, b.nextInsert = {}, 0
end

for n = 1, 7 do
  local save = importSave(cartWithStatus(n))
  eq(save.party[1].status, "SLP", ("%d: status byte %d imports as SLP"):format(n, n))
  eq(save.party[1].sleepTurns, n, ("%d: the sleep counter rides the mon"):format(n))
  local b = battleFor(save)
  eq(b.player.mon, save.party[1], n .. ": the sleeper leads")
  eq(b.player.sleepTurns, n, n .. ": the battler starts with the saved counter")
  local woke
  for turn = 1, n + 2 do
    local canMove, msgs = Status.beforeMove(b.player, b.rng, b)
    if save.party[1].status == nil then woke = turn; break end
    eq(canMove, false, ("%d: turn %d still asleep"):format(n, turn))
    eq(save.party[1].sleepTurns, n - turn, ("%d: turn %d counter written back"):format(n, turn))
    local out = K.export(1, "red", save)
    eq(out:byte(PARTY_STATUS + 1), n - turn, ("%d: turn %d exports the live counter"):format(n, turn))
  end
  eq(woke, n, ("%d: a mon saved with %d sleep turns wakes on turn %d"):format(n, n, n))
  eq(save.party[1].sleepTurns, nil, n .. ": the counter is gone once awake")
  eq(K.export(1, "red", save):byte(PARTY_STATUS + 1), 0, n .. ": the exported status byte is clear once awake")
end

do
  local save = importSave(cartWithStatus(5))
  local b = battleFor(save)
  stubText(b)
  local turns = 0
  repeat
    turns = turns + 1
    b:preRechargeChecks(b.player, b.enemy)
  until save.party[1].status == nil or turns > 10
  eq(turns, 5, "the recharge-turn sleep check decrements the same counter and wakes on turn 5")
end

do
  local save = importSave(cartWithStatus(6))
  local b = battleFor(save)
  Status.beforeMove(b.player, b.rng, b)
  Status.beforeMove(b.player, b.rng, b)
  local again = BattleState.makeBattler(Data, save.party[1], true, save)
  eq(again.sleepTurns, 4, "switching back in resumes the counter where it stopped")
  eq(K.export(1, "red", save):byte(PARTY_STATUS + 1), 4, "a mon switched out mid-sleep exports its counter")
end

do
  local save = importSave(cartWithStatus(3))
  save.party[2].status = nil
  local b = battleFor(save)
  local target = { mon = save.party[2], name = "BENCH" }
  local record = Status.RECORDS.SLP
  record.onInflict({ rng = function() return 6 end, data = Data }, target, {}, "BENCH")
  eq(target.sleepTurns, 6, "infliction rolls the counter")
  eq(save.party[2].sleepTurns, 6, "infliction writes the roll to the mon")
  save.party[2].status = "SLP"
  eq(K.export(1, "red", save):byte(O.partyMons + 44 + 4 + 1), 6, "an inflicted counter exports as the status byte")
end

do
  local save = importSave(cartWithStatus(0))
  local b = battleFor(save)
  local mon = save.party[1]
  mon.hp = 1
  local msgs = MoveEffects.primary.HEAL_EFFECT(b, b.player, b.enemy, { id = "REST" })
  eq(mon.status, "SLP", "Rest puts the user to sleep")
  eq(mon.sleepTurns, 2, "Rest sets the counter to 2 (effects.asm)")
  eq(K.export(1, "red", save):byte(PARTY_STATUS + 1), 2, "Rest exports a status byte of 2")
  local first = Status.beforeMove(b.player, b.rng, b)
  local second = Status.beforeMove(b.player, b.rng, b)
  eq(first, false, "Rest sleep: turn 1 asleep")
  eq(second, false, "Rest sleep: turn 2 wakes and loses the turn")
  eq(mon.status, nil, "Rest sleep ends after exactly 2 turns")
end

do
  local save = importSave(cartWithStatus(0))
  eq(save.party[1].status, nil, "an awake mon imports clean")
  eq(save.party[1].sleepTurns, nil, "an awake mon carries no counter")
  local b = battleFor(save)
  eq(b.player.sleepTurns, nil, "an awake battler has no counter")
end

do
  local save = importSave(cartWithStatus(0x0B))
  eq(save.party[1].status, "SLP", "sleep wins over a stray bit in the multi-bit status byte")
  eq(save.party[1].sleepTurns, 3, "stray-bit byte 0x0B keeps its counter")
  eq(K.export(1, "red", save):byte(PARTY_STATUS + 1), 0x0B, "the stray-bit byte survives the export")
  local b = battleFor(save)
  Status.beforeMove(b.player, b.rng, b)
  eq(K.export(1, "red", save):byte(PARTY_STATUS + 1), 2, "ticking the counter rewrites the whole byte as the game does")
end

for n = 1, 7 do
  local save = importSave(cartWithStatus(n))
  local packet = Json.decode(Json.encode({ type = "party", mons = Protocol.packParty(save.party) }))
  local clean = assert(Wire.sanitize(packet))
  eq(clean.mons[1].sleepTurns, n, n .. ": the saved sleep counter survives the transport schema")
  local peer = assert(Protocol.unpackMon(Data, clean.mons[1], { strict = true }))
  eq(peer.sleepTurns, n, n .. ": the peer rebuilds the saved sleep counter")
  local ownerBattler = BattleState.makeBattler(Data, save.party[1], true, nil)
  local peerBattler = BattleState.makeBattler(Data, peer, false, nil)
  for turn = 1, n do
    local ownerCanMove = Status.beforeMove(ownerBattler, function() return 1 end, { data = Data })
    local peerCanMove = Status.beforeMove(peerBattler, function() return 1 end, { data = Data })
    eq(peerCanMove, ownerCanMove, ("%d: link turn %d has the same sleep result"):format(n, turn))
    eq(peer.status, save.party[1].status, ("%d: link turn %d has the same status"):format(n, turn))
    eq(peer.sleepTurns, save.party[1].sleepTurns, ("%d: link turn %d has the same remaining counter"):format(n, turn))
  end
end

do
  local save = importSave(cartWithStatus(5))
  local packed = Protocol.packMon(save.party[1])
  local variants = {
    { value = -4, want = 1 }, { value = 999, want = 7 }, { value = "4.9", want = 4 },
    { value = "oops", want = 1 }, { value = {}, want = 1 }, { value = 0/0, want = 1 },
    { value = math.huge, want = 1 }, { value = -math.huge, want = 1 },
  }
  for i, variant in ipairs(variants) do
    packed.sleepTurns = variant.value
    local peer = assert(Protocol.unpackMon(Data, packed))
    eq(peer.sleepTurns, variant.want, "sleep wire validation case " .. i)
  end
  packed.sleepTurns = nil
  eq(Protocol.unpackMon(Data, packed).sleepTurns, 1, "a legacy sleeping peer retains its one-turn fallback")
  packed.sleepTurns = 6
  packed.status = "PSN"
  eq(Protocol.unpackMon(Data, packed).sleepTurns, nil, "an awake wire mon drops a stale sleep counter")
  packed.status = "SLP"
  local forced = assert(Protocol.unpackMon(Data, packed, { forceLevel = 50 }))
  eq(forced.status, nil, "a forced-level battle starts with status cleared")
  eq(forced.sleepTurns, nil, "a forced-level battle clears the saved sleep counter")
  eq(forced.hp, forced.stats.hp, "a forced-level battle starts at full HP")
  local any = assert(Protocol.unpackMon(Data, packed, { forceLevel = "ANY" }))
  eq(any.status, "SLP", "ANY retains the party status")
  eq(any.sleepTurns, 6, "ANY retains the saved sleep counter")
end

T.finish()
