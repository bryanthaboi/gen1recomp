#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Prize = require("src.core.game3.battle.prize")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")

local function meowth(level)
  return { species = 52, level = level, hp = 120, maxHp = 120, moves = { 6 }, pp = { 20 }, maxPp = { 20 },
    attack = 60, defense = 40, spAtk = 40, spDef = 40, speed = 90, item = 13 }
end

local function setup(st)
  st.rng = function(lo, hi)
    if lo == 1 and hi == 100 then return 1 end
    if lo and hi then return hi end
    return lo or 0
  end
  return Adapter.new(st)
end

print("[test] 1. Pay Day coins only count for the player's side")
do
  local Moves = require("src.core.game3.battle.moves")
  local EffectIds = require("src.core.game3.battle.effect_ids")
  local Types = require("src.core.game3.battle.types")
  local savedRom, savedLoaded = Moves._rom, Moves._romLoaded
  Moves._romLoaded = true
  Moves._rom = { [6] = { power = 40, type = Types.ID.NORMAL, accuracy = 100, pp = 20,
    effect = EffectIds.PAY_DAY, secondaryChance = 100, target = 0, priority = 0, flags = 0 } }
  local st = State.new({ wild = true, playerParty = { meowth(24) }, foeMon = meowth(30) })
  local ad = setup(st)
  local out = {}
  Engine.resolveMove(st.enemy, st.player, 6, 1, ad, st, out)
  check((st.payDayCoins or 0) == 0, "foe Pay Day scatters no player coins")
  check(table.concat(out, " "):find("Coins scattered", 1, true) ~= nil, "foe Pay Day still prints Coins scattered")
  out = {}
  Engine.resolveMove(st.player, st.enemy, 6, 1, ad, st, out)
  check(st.payDayCoins == 24 * 5, "player Pay Day adds level * 5")
  st.payDayCoins = 0xFFFF - 10
  Engine.resolveMove(st.player, st.enemy, 6, 1, ad, st, {})
  check(st.payDayCoins == 0xFFFF, "gPaydayMoney saturates at 0xFFFF")
  Moves._rom, Moves._romLoaded = savedRom, savedLoaded
end

print("[test] 2. givepaydaymoney")
do
  local session = { money = 999990 }
  check(Prize.payDay(session, 0) == 0, "no coins pays nothing")
  local bonus = Prize.payDay(session, 120, { moneyMultiplier = 2 })
  check(bonus == 240, "bonus is coins * moneyMultiplier")
  check(session.money == 999999, "money capped at MAX_MONEY")
  check(Prize.payDayMessage("RED", 240) == "RED picked up\n¥240!", "picked up text")
  local s2 = { money = 100 }
  check(Prize.payDay(s2, 50, { link = true }) == 0 and s2.money == 100, "link battles pay nothing")
end

print("[test] 3. pickup")
do
  local calls = 0
  local seq
  local function rnd()
    calls = calls + 1
    return table.remove(seq, 1) or 1
  end
  local party = {
    { species = 52, level = 10, abilityId = 53 },
    { species = 52, level = 10, abilityId = 53, item = 13, heldItem = 13 },
    { species = 16, level = 10, abilityId = 51 },
    { species = 52, level = 10, abilityId = 53, isEgg = true },
    { species = 52, level = 10, abilityId = 53 },
    { species = 52, level = 10, abilityId = 53 },
  }
  seq = { 0, 0, 0, 99, 3 }
  local picked = Prize.pickup(party, rnd)
  check(party[1].item == 139 and party[1].heldItem == 139, "roll 0 gives ORAN BERRY")
  check(party[2].item == 13, "holding mon keeps its item")
  check(party[3].item == nil, "non-Pickup mon gets nothing")
  check(party[4].item == nil, "egg gets nothing")
  check(party[5].item == 167, "roll 99 gives BELUE BERRY")
  check(party[6].item == nil, "failed 1-in-10 gives nothing")
  check(calls == 5, "Random only drawn for eligible mons")
  check(#picked == 2, "two pickups reported")
  local p2 = { { species = 52, abilityId = 53 } }
  seq = { 0, 94 }
  Prize.pickup(p2, rnd)
  check(p2[1].item == 110, "roll 94 gives NUGGET")
end

local realRuntime = package.loaded["src.core.game3.runtime"]
local session = { name = "RED", money = 1000 }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local payDayPack = {
  read = function()
    local EffectIds = require("src.core.game3.battle.effect_ids")
    local Types = require("src.core.game3.battle.types")
    return string.format("return { moves = { [6] = { power = 40, type = %d, accuracy = 100, pp = 20, "
      .. "effect = %d, secondaryChance = 100, target = 0, priority = 0, flags = 0 } } }",
      Types.ID.NORMAL, EffectIds.PAY_DAY)
  end,
}

local function run(opts)
  if Battle.isActive() then Battle.abort("win") end
  local ok = Battle.start(opts)
  local res = Battle.runToEnd()
  local log = {}
  for i, t in ipairs(Ui.log() or {}) do log[i] = t end
  return ok, res, log
end

local function find(log, needle)
  for i, t in ipairs(log) do
    if t:find(needle, 1, true) then return i end
  end
  return nil
end

local function count(log, needle)
  local n = 0
  for _, t in ipairs(log) do
    if t:find(needle, 1, true) then n = n + 1 end
  end
  return n
end

print("[test] 4. wild win pays Pay Day money after EXP")
do
  session.money = 1000
  session.party = { meowth(50) }
  local ok, res, log = run({ wild = true, headless = true, cache = payDayPack, playerParty = session.party,
    foe = { species = 16, level = 2 } })
  check(ok and res == "win", "wild battle won")
  local n = count(log, "Coins scattered")
  check(n >= 1, "Pay Day hit")
  local iExp = find(log, "EXP. Points")
  local iPick = find(log, "picked up\n")
  check(iPick ~= nil, "picked up line present")
  check(iPick and log[iPick] == string.format("RED picked up\n¥%d!", 250 * n), "picked up amount is 250 per hit")
  check(iExp and iPick and iExp < iPick, "picked up follows EXP")
  check(iPick == #log, "picked up is the last line")
  check(n >= 1 and session.money == 1000 + 250 * n, "money added")
end

print("[test] 5. trainer win: prize money before picked up")
do
  session.money = 1000
  session.party = { meowth(50) }
  local ok, res, log = run({ wild = false, headless = true, trainerId = 326, cache = payDayPack, playerParty = session.party,
    foe = { species = 7, level = 5, trainerId = 326 } })
  check(ok and res == "win", "trainer battle won")
  local iMoney = find(log, "for winning")
  local iPick = find(log, "picked up\n")
  check(iMoney ~= nil and iPick ~= nil, "prize and picked up lines present")
  check(iMoney and iPick and iMoney < iPick, "prize money precedes picked up")
end

print("[test] 6. no Pay Day, no picked up line")
do
  session.money = 1000
  session.party = { { species = 6, level = 60, hp = 200, maxHp = 200, moves = { 53 }, pp = { 15 }, maxPp = { 15 }, item = 13 } }
  local ok, res, log = run({ wild = true, headless = true, playerParty = session.party, foe = { species = 16, level = 2 } })
  check(ok and res == "win", "wild battle won")
  check(find(log, "picked up") == nil, "no picked up line")
  check(session.money == 1000, "money unchanged")
end

package.loaded["src.core.game3.runtime"] = realRuntime

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3 payday pickup")
