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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("pokemon/meta.lua")
if not cacheRoot then
  print("[skip] game3_growth_test: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local ItemsData = require("src.core.game3.items_data")
ItemsData.ensureLoaded()

local BULBASAUR, PIKACHU, CHANSEY, MAGIKARP, SHEDINJA = 1, 25, 113, 129, 303
local ITEM_SOOTHE_BELL, ITEM_MACHO_BRACE = 184, 181
local ITEM_HP_UP, ITEM_PROTEIN, ITEM_CALCIUM = 63, 64, 67

local function mon(species, level, overrides)
  local m = {
    species = species,
    speciesId = species,
    level = level or 10,
    personality = 0,
    ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    pokeball = 4,
  }
  for k, v in pairs(overrides or {}) do m[k] = v end
  Pokemon.applyStats(m)
  return m
end

print("[test] 0. The growth API exists")
do
  local missing = false
  for _, name in ipairs({
    "evYield", "gainEVs", "evCount", "evsOf", "friendshipOf", "setFriendship",
    "adjustFriendship", "adjustFriendshipOnBattleFaint", "itemFriendship",
    "raiseEvFromItem", "hasPokerus", "hasHadPokerus", "checkPartyPokerus",
    "checkPartyHasHadPokerus", "randomlyGivePartyPokerus", "partySpreadPokerus",
    "updatePartyPokerusTime", "baseFriendship", "currentMapSec",
    "isLeagueTrainerClass",
  }) do
    if type(Pokemon[name]) ~= "function" then
      missing = true
      check(false, "Pokemon." .. name .. " is missing")
    end
  end
  if type(require("src.core.game3.item_use").useVitamin) ~= "function" then
    missing = true
    check(false, "ItemUse.useVitamin is missing")
  end
  if missing then finish() end
  check(true, "every AdjustFriendship / MonGainEVs / Pokerus entry point is present")
end

print("[test] 1. ROM EV yields reach the engine (pokemon.h:219 evYield bitfields)")
eq(Pokemon.evYield(BULBASAUR).spa, 1, "BULBASAUR yields 1 SP. ATK EV")
eq(Pokemon.evYield(BULBASAUR).hp, 0, "BULBASAUR yields 0 HP EVs")
eq(Pokemon.evYield(PIKACHU).spe, 2, "PIKACHU yields 2 SPEED EVs")
eq(Pokemon.evYield(MAGIKARP).spe, 1, "MAGIKARP yields 1 SPEED EV")
eq(Pokemon.evYield(CHANSEY).hp, 2, "CHANSEY yields 2 HP EVs")

print("[test] 2. MonGainEVs (pokemon.c:5512)")
do
  local m = mon(BULBASAUR, 10)
  Pokemon.gainEVs(m, PIKACHU)
  eq(m.evs.spe, 2, "beating a PIKACHU gives 2 SPEED EVs")
  eq(Pokemon.evCount(m), 2, "and nothing else")
  Pokemon.gainEVs(m, CHANSEY)
  eq(m.evs.hp, 2, "beating a CHANSEY gives 2 HP EVs")
  eq(Pokemon.evCount(m), 4, "EV count accumulates")
end

print("[test] 3. Macho Brace doubles, Pokerus doubles, both stack (pokemon.c:5537,5578)")
do
  local m = mon(BULBASAUR, 10, { item = ITEM_MACHO_BRACE })
  Pokemon.gainEVs(m, PIKACHU)
  eq(m.evs.spe, 4, "HOLD_EFFECT_MACHO_BRACE doubles the yield")

  local p = mon(BULBASAUR, 10, { pokerus = 0x41 })
  check(Pokemon.hasPokerus(p), "pokerus 0x41 is an active infection")
  check(Pokemon.hasHadPokerus(p), "pokerus 0x41 has had pokerus")
  Pokemon.gainEVs(p, PIKACHU)
  eq(p.evs.spe, 4, "Pokerus doubles the yield")

  local cured = mon(BULBASAUR, 10, { pokerus = 0x40 })
  check(not Pokemon.hasPokerus(cured), "pokerus 0x40 is cured, not infected")
  check(Pokemon.hasHadPokerus(cured), "a cured mon still counts for MonGainEVs")
  Pokemon.gainEVs(cured, PIKACHU)
  eq(cured.evs.spe, 4, "a cured mon keeps the doubling")

  local both = mon(BULBASAUR, 10, { pokerus = 0x41, item = ITEM_MACHO_BRACE })
  Pokemon.gainEVs(both, PIKACHU)
  eq(both.evs.spe, 8, "Pokerus and Macho Brace stack")
end

print("[test] 4. 255 per stat / 510 total caps (pokemon.c:5581)")
do
  local m = mon(BULBASAUR, 10, { evs = { hp = 254, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } })
  Pokemon.gainEVs(m, CHANSEY)
  eq(m.evs.hp, 255, "a 2 HP yield onto 254 clamps at MAX_PER_STAT_EVS")

  local full = mon(BULBASAUR, 10, { evs = { hp = 255, atk = 255, def = 0, spe = 0, spa = 0, spd = 0 } })
  eq(Pokemon.evCount(full), 510, "510 total already reached")
  Pokemon.gainEVs(full, PIKACHU)
  eq(full.evs.spe, 0, "MAX_TOTAL_EVS stops any further gain")

  local near = mon(BULBASAUR, 10, { evs = { hp = 255, atk = 254, def = 0, spe = 0, spa = 0, spd = 0 } })
  Pokemon.gainEVs(near, PIKACHU)
  eq(Pokemon.evCount(near), 510, "the last point is trimmed to the 510 total")
  eq(near.evs.spe, 1, "and lands on the stat pret was filling")
end

print("[test] 5. EVs move the stat formula (pokemon.c:2130 CalculateMonStats)")
do
  local bare = Pokemon.calcStats(PIKACHU, 50, {}, {}, 0)
  local maxed = Pokemon.calcStats(PIKACHU, 50, {}, { spe = 252 }, 0)
  eq(maxed.speed - bare.speed, 31, "252 SPEED EVs at Lv50 are +31 SPEED")
  local hp = Pokemon.calcStats(PIKACHU, 50, {}, { hp = 252 }, 0)
  local hp0 = Pokemon.calcStats(PIKACHU, 50, {}, {}, 0)
  eq(hp.maxHp - hp0.maxHp, 31, "252 HP EVs at Lv50 are +31 HP")
end

print("[test] 6. AdjustFriendship deltas by tier (pokemon.c:1618, :5440)")
do
  local low = mon(BULBASAUR, 10, { friendship = 70 })
  Pokemon.adjustFriendship(low, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL)
  eq(low.friendship, 75, "level up under 100 friendship is +5")
  eq(low.happiness, 75, "happiness alias tracks friendship")

  local mid = mon(BULBASAUR, 10, { friendship = 150 })
  Pokemon.adjustFriendship(mid, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL)
  eq(mid.friendship, 153, "level up in 100..199 is +3")

  local high = mon(BULBASAUR, 10, { friendship = 220 })
  Pokemon.adjustFriendship(high, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL)
  eq(high.friendship, 222, "level up at 200+ is +2")

  local faintLow = mon(BULBASAUR, 10, { friendship = 70 })
  Pokemon.adjustFriendship(faintLow, Pokemon.FRIENDSHIP_EVENT_FAINT_LARGE)
  eq(faintLow.friendship, 65, "a big-level-gap faint under 200 is -5")

  local faintHigh = mon(BULBASAUR, 10, { friendship = 220 })
  Pokemon.adjustFriendship(faintHigh, Pokemon.FRIENDSHIP_EVENT_FAINT_LARGE)
  eq(faintHigh.friendship, 210, "a big-level-gap faint at 200+ is -10")

  local small = mon(BULBASAUR, 10, { friendship = 220 })
  Pokemon.adjustFriendship(small, Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL)
  eq(small.friendship, 219, "an ordinary faint is -1 at every tier")

  local tmhm = mon(BULBASAUR, 10, { friendship = 220 })
  Pokemon.adjustFriendship(tmhm, Pokemon.FRIENDSHIP_EVENT_LEARN_TMHM)
  eq(tmhm.friendship, 220, "LEARN_TMHM is 0 at the top tier")
end

print("[test] 7. Floor / ceiling and the egg guard (pokemon.c:5458, :5503)")
do
  local zero = mon(BULBASAUR, 10, { friendship = 2 })
  Pokemon.adjustFriendship(zero, Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL)
  Pokemon.adjustFriendship(zero, Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL)
  Pokemon.adjustFriendship(zero, Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL)
  eq(zero.friendship, 0, "friendship never goes below 0")

  local cap = mon(BULBASAUR, 10, { friendship = 254 })
  Pokemon.adjustFriendship(cap, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL)
  eq(cap.friendship, 255, "friendship never goes above MAX_FRIENDSHIP")

  local egg = mon(BULBASAUR, 5, { friendship = 70, isEgg = true })
  check(not Pokemon.adjustFriendship(egg, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL),
    "an egg is skipped")
  eq(egg.friendship, 70, "and its friendship is untouched")
end

print("[test] 8. Soothe Bell, Luxury Ball, met location (pokemon.c:5490, :5497)")
do
  local bell = mon(BULBASAUR, 10, { friendship = 70, item = ITEM_SOOTHE_BELL })
  Pokemon.adjustFriendship(bell, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL)
  eq(bell.friendship, 77, "HOLD_EFFECT_FRIENDSHIP_UP turns +5 into +7")

  local bellDown = mon(BULBASAUR, 10, { friendship = 70, item = ITEM_SOOTHE_BELL })
  Pokemon.adjustFriendship(bellDown, Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL)
  eq(bellDown.friendship, 69, "Soothe Bell never softens a loss")

  local luxury = mon(BULBASAUR, 10, { friendship = 70, pokeball = 11 })
  Pokemon.adjustFriendship(luxury, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL)
  eq(luxury.friendship, 76, "ITEM_LUXURY_BALL adds 1 on a gain")

  local luxuryDown = mon(BULBASAUR, 10, { friendship = 70, pokeball = 11 })
  Pokemon.adjustFriendship(luxuryDown, Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL)
  eq(luxuryDown.friendship, 69, "and nothing on a loss")

  local home = mon(BULBASAUR, 10, { friendship = 70, metLocation = 12 })
  Pokemon.adjustFriendship(home, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL, { mapSec = 12 })
  eq(home.friendship, 76, "standing in the met location adds 1")

  local away = mon(BULBASAUR, 10, { friendship = 70, metLocation = 12 })
  Pokemon.adjustFriendship(away, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL, { mapSec = 13 })
  eq(away.friendship, 75, "and nowhere else")

  local all = mon(BULBASAUR, 10, {
    friendship = 70, item = ITEM_SOOTHE_BELL, pokeball = 11, metLocation = 12,
  })
  Pokemon.adjustFriendship(all, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL, { mapSec = 12 })
  eq(all.friendship, 79, "Soothe Bell then Luxury Ball then met location")
end

print("[test] 9. The WALKING coin flip and the LEAGUE_BATTLE gate (pokemon.c:5472, :5478)")
do
  local Rng = require("src.core.game3.rng")
  Rng.SeedRng(0x1234)
  local m = mon(BULBASAUR, 10, { friendship = 70 })
  local moved = 0
  for _ = 1, 200 do
    local before = m.friendship
    Pokemon.adjustFriendship(m, Pokemon.FRIENDSHIP_EVENT_WALKING)
    if m.friendship ~= before then moved = moved + 1 end
  end
  check(moved > 60 and moved < 140,
    "WALKING lands about half the time (" .. moved .. "/200)")

  local league = mon(BULBASAUR, 10, { friendship = 70 })
  check(not Pokemon.adjustFriendship(league, Pokemon.FRIENDSHIP_EVENT_LEAGUE_BATTLE),
    "LEAGUE_BATTLE does nothing outside a leader / E4 / champion fight")
  eq(league.friendship, 70, "and leaves friendship alone")
  Pokemon.adjustFriendship(league, Pokemon.FRIENDSHIP_EVENT_LEAGUE_BATTLE,
    { leagueBattle = true })
  eq(league.friendship, 73, "and is +3 against one")
end

print("[test] 10. AdjustFriendshipOnBattleFaint level gap (battle_util2.c:78)")
do
  local near = mon(BULBASAUR, 50, { friendship = 220 })
  Pokemon.adjustFriendshipOnBattleFaint(near, 50, 79)
  eq(near.friendship, 219, "a 29-level gap is FAINT_SMALL")

  local far = mon(BULBASAUR, 50, { friendship = 220 })
  Pokemon.adjustFriendshipOnBattleFaint(far, 50, 80)
  eq(far.friendship, 210, "a 30-level gap is FAINT_LARGE")

  local weaker = mon(BULBASAUR, 50, { friendship = 220 })
  Pokemon.adjustFriendshipOnBattleFaint(weaker, 50, 5)
  eq(weaker.friendship, 219, "losing to a weaker foe is FAINT_SMALL")
end

print("[test] 11. Pokerus is stubbed out of FRLG (pokemon.c:5612, :5674, :5680)")
do
  local party = { mon(BULBASAUR, 10), mon(PIKACHU, 10) }
  Pokemon.randomlyGivePartyPokerus(party)
  Pokemon.partySpreadPokerus(party)
  Pokemon.updatePartyPokerusTime(party)
  eq(party[1].pokerus, nil, "RandomlyGivePartyPokerus never infects anything")
  eq(Pokemon.checkPartyPokerus(party, 0), 0, "CheckPartyPokerus is 0")
  party[1].pokerus = 0x41
  party[2].pokerus = 0x40
  eq(Pokemon.checkPartyPokerus(party, 3), 1, "selection 3: only slot 1 is infected")
  eq(Pokemon.checkPartyHasHadPokerus(party, 3), 3, "but both have had it")
end

print("[test] 12. Vitamins: +10 EV to 100, friendship, Shedinja (pokemon.c:4229, party_menu.c:4405)")
do
  local ItemUse = require("src.core.game3.item_use")
  local session = { party = {}, map = nil }
  local m = mon(PIKACHU, 50, { friendship = 70 })
  session.party[1] = m
  local beforeSpeed = m.speed

  local ok, kind, text = ItemUse.useVitamin(session, m, ITEM_PROTEIN)
  check(ok, "PROTEIN is usable")
  eq(kind, "vitamin", "and reports as a vitamin")
  eq(m.evs.atk, 10, "PROTEIN adds ITEM6_ADD_EV = 10 ATTACK EVs")
  eq(m.friendship, 75, "and the vitamin friendship change is +5")
  check(type(text) == "string" and text:find("base"), "the message names the base stat")

  m.evs.spe = 95
  local okS = ItemUse.useVitamin(session, m, 66)
  check(okS, "CARBOS at 95 SPEED EVs still works")
  eq(m.evs.spe, 100, "and stops at EV_ITEM_RAISE_LIMIT")
  local okS2, kindS2 = ItemUse.useVitamin(session, m, 66)
  check(not okS2, "CARBOS at 100 SPEED EVs has no effect")
  eq(kindS2, "no_effect", "and says so")
  check(m.speed > beforeSpeed, "SPEED went up from the EVs")

  local hpMon = mon(PIKACHU, 50, { friendship = 70 })
  local beforeHp, beforeMax = hpMon.hp, hpMon.maxHp
  ItemUse.useVitamin(session, hpMon, ITEM_HP_UP)
  eq(hpMon.evs.hp, 10, "HP UP adds 10 HP EVs")
  eq(hpMon.maxHp - beforeMax, 1, "max HP rises by 1")
  eq(hpMon.hp - beforeHp, 1, "and CalculateMonStats carries it onto live HP")

  local shed = mon(SHEDINJA, 50, { friendship = 70 })
  local okSh, kindSh = ItemUse.useVitamin(session, shed, ITEM_HP_UP)
  check(not okSh, "HP UP on SHEDINJA has no effect")
  eq(kindSh, "no_effect", "NotUsingHPEVItemOnShedinja blocks it")
  eq(shed.evs.hp, 0, "and no EV is spent")
  local okSh2 = ItemUse.useVitamin(session, shed, ITEM_CALCIUM)
  check(okSh2, "but SHEDINJA can still take CALCIUM")
end

print("[test] 13. Rare Candy carries the vitamin friendship change (item_effects.h:200)")
do
  local ItemUse = require("src.core.game3.item_use")
  local m = mon(PIKACHU, 10, { friendship = 70 })
  local ok = ItemUse.useRareCandy({ party = { m } }, m)
  check(ok, "RARE CANDY works")
  eq(m.level, 11, "and levels the mon")
  eq(m.friendship, 75, "and gives ITEM5_FRIENDSHIP_ALL +5")
end

print("[test] 14. Saves written before these fields load with pret's defaults")
do
  local old = { species = CHANSEY, speciesId = CHANSEY, level = 20, personality = 0 }
  eq(Pokemon.friendshipOf(old), 140,
    "no friendship field reads as the species base friendship")
  eq(Pokemon.evCount(old), 0, "no evs field reads as 0 EVs")
  eq(type(old.evs), "table", "and evsOf materializes the table")
  check(not Pokemon.hasHadPokerus(old), "no pokerus field is no pokerus")
  Pokemon.adjustFriendship(old, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL)
  eq(old.friendship, 143, "and AdjustFriendship starts from that base")
end

print("[test] 15. The friendship checker NPC reads the real value (field_specials.c:163)")
do
  local Natives = require("src.core.game3.scripting.natives")
  local Std = require("src.core.game3.scripting.stdscripts")
  eq(Std.SPECIAL.GetLeadMonFriendship, 0xE6, "special id matches specials.inc:241")
  local key = "special:" .. Std.SPECIAL.GetLeadMonFriendship
  local handler = Natives.ALLOW and Natives.ALLOW[key]
  check(type(handler) == "function", "special 0xE6 has a handler")
  if type(handler) == "function" then
    local Runtime = require("src.core.game3.runtime")
    local session = { party = { mon(BULBASAUR, 10, { friendship = 255 }) }, vars = {} }
    local prev = Runtime.session
    Runtime.session = session
    local ctx = { vars = {}, session = session }
    local _, score = handler(ctx, nil)
    eq(score, 6, "friendship 255 scores 6")
    session.party[1].friendship = 150
    local _, s4 = handler(ctx, nil)
    eq(s4, 4, "friendship 150 scores 4")
    session.party[1].friendship = 0
    local _, s0 = handler(ctx, nil)
    eq(s0, 0, "friendship 0 scores 0")
    Runtime.session = prev
  end
end

print("[test] 16. Winning a battle awards EVs and level-up friendship (battle_script_commands.c:3271, :3314)")
do
  local Experience = require("src.core.game3.battle.experience")
  local winner = mon(BULBASAUR, 5, { friendship = 70 })
  winner.exp = Experience.expForLevel(winner, 5)
  local party = { winner }
  local foe = { mon = mon(CHANSEY, 30), species = CHANSEY, level = 30 }
  local st = {
    wild = true,
    playerParty = party,
    player = { mon = winner, partyIndex = 1, side = "player" },
    session = { party = party },
  }
  local out = Experience.awardFoe(st, foe, { trainer = false, getOpts = function()
    return { luckyEgg = false, traded = false }
  end })
  eq(#out, 1, "the sent-in mon got the award")
  eq(winner.evs.hp, 2, "and CHANSEY's 2 HP EVs")
  check(winner.level > 5, "a Lv5 BULBASAUR levels off a Lv30 CHANSEY")
  check(winner.friendship > 70,
    "and FRIENDSHIP_EVENT_GROW_LEVEL ran (" .. tostring(winner.friendship) .. ")")

  local writeBack = { species = BULBASAUR, speciesId = BULBASAUR, level = 5 }
  local Party = require("src.core.game3.party")
  Party.applyBattleFields(writeBack, {
    evs = winner.evs, friendship = winner.friendship, pokerus = winner.pokerus,
  })
  eq(writeBack.evs.hp, 2, "the battle writeback carries EVs back to the save")
  eq(writeBack.friendship, winner.friendship, "and friendship")
  eq(writeBack.happiness, winner.friendship, "and keeps the happiness alias in step")
end

print("[test] 17. MonGainEVs runs before the level-up stats (battle_script_commands.c:3271, :3283)")
do
  local Experience = require("src.core.game3.battle.experience")
  local winner = mon(BULBASAUR, 49, { friendship = 70 })
  winner.ivs.hp = 1
  winner.evs.hp = 2
  Pokemon.applyStats(winner)
  winner.exp = Experience.expForLevel(winner, 50) - 1
  winner.hp = winner.maxHp
  local party = { winner }
  local foe = { mon = mon(CHANSEY, 30), species = CHANSEY, level = 30 }
  local st = {
    wild = true, playerParty = party,
    player = { mon = winner, partyIndex = 1, side = "player" },
    session = { party = party },
  }
  Experience.awardFoe(st, foe, { trainer = false, getOpts = function()
    return { luckyEgg = false, traded = false }
  end })
  eq(winner.level, 50, "the KO levels the mon")
  eq(winner.evs.hp, 4, "and CHANSEY's 2 HP EVs land on top of the 2 it had")
  local want = mon(BULBASAUR, 50, { friendship = 70 })
  want.ivs.hp = 1
  want.evs.hp = 4
  Pokemon.applyStats(want)
  eq(winner.maxHp, want.maxHp, "the level-up stats already include this KO's EVs")
end

print("[test] 18. Bitter medicine (item_effects.h:81-113)")
do
  local ItemUse = require("src.core.game3.item_use")
  local Bag = require("src.core.game3.bag")
  local function useOn(m, itemId)
    local session = { party = { m }, bag = Bag.new(), vars = {}, flags = {} }
    Bag.add(session.bag, itemId, 1)
    return ItemUse.useField(session, session.bag, itemId, 1)
  end

  local powder = mon(PIKACHU, 50, { friendship = 120 })
  powder.hp = 1
  local okP = useOn(powder, 30)
  check(okP, "ENERGYPOWDER works on a hurt mon")
  eq(powder.hp, 51, "and restores 50 HP")
  eq(powder.friendship, 115, "and costs 5 friendship at the mid tier")

  local root = mon(CHANSEY, 50, { friendship = 220 })
  root.hp = 1
  local okR = useOn(root, 31)
  check(okR, "ENERGY ROOT works")
  eq(root.hp, 201, "and restores 200 HP")
  eq(root.friendship, 205, "and costs 15 friendship at the high tier")

  local heal = mon(PIKACHU, 50, { friendship = 50, status = "PSN" })
  local okH = useOn(heal, 32)
  check(okH, "HEAL POWDER cures a status")
  eq(heal.status, nil, "ITEM3_STATUS_ALL clears it")
  eq(heal.friendship, 45, "and costs 5 friendship at the low tier")

  local herb = mon(PIKACHU, 50, { friendship = 120 })
  herb.hp = 0
  local okV = useOn(herb, 33)
  check(okV, "REVIVAL HERB works on a fainted mon")
  eq(herb.hp, herb.maxHp, "ITEM6_HEAL_HP_FULL revives it to full")
  eq(herb.friendship, 105, "and costs 15 friendship")

  local healthy = mon(PIKACHU, 50, { friendship = 120 })
  local okN = useOn(healthy, 30)
  check(not okN, "ENERGYPOWDER on a full-HP mon does nothing")
  eq(healthy.friendship, 120, "and UPDATE_FRIENDSHIP_FROM_ITEM does not run")
end

print("[test] 19. League trainer classes (trainers.h:267, pokemon.c:5480)")
do
  check(Pokemon.isLeagueTrainerClass(84), "LEADER is a league class")
  check(Pokemon.isLeagueTrainerClass(87), "ELITE FOUR is a league class")
  check(Pokemon.isLeagueTrainerClass(90), "CHAMPION is a league class")
  check(not Pokemon.isLeagueTrainerClass(81), "RIVAL is not")
  check(not Pokemon.isLeagueTrainerClass(91), "CHANNELER is not")
  check(not Pokemon.isLeagueTrainerClass(nil), "and no class at all is not")
  local names
  local f = io.open(cacheRoot .. "/trainers.lua", "rb")
  if f then
    local src = f:read("*a")
    f:close()
    local chunk = load(src, "@trainers.lua", "t", {})
    local okP, pack = pcall(chunk)
    names = okP and type(pack) == "table" and pack.classNames or nil
  end
  check(names ~= nil, "the extracted trainer class table loaded")
  if names then
    eq(names[84], "LEADER", "the extracted class table agrees on 84")
    eq(names[87], "ELITE FOUR", "and on 87")
    eq(names[90], "CHAMPION", "and on 90")
  end
  local m = mon(BULBASAUR, 10, { friendship = 120 })
  Pokemon.adjustFriendship(m, Pokemon.FRIENDSHIP_EVENT_LEAGUE_BATTLE, {})
  eq(m.friendship, 120, "a non-league battle changes nothing")
  Pokemon.adjustFriendship(m, Pokemon.FRIENDSHIP_EVENT_LEAGUE_BATTLE, { leagueBattle = true })
  eq(m.friendship, 122, "a league battle gives +2 at the mid tier")
end

print("[test] 20. A player mon fainting in battle loses friendship (battle_script_commands.c:2878)")
do
  local State = require("src.core.game3.battle.state")
  local Engine = require("src.core.game3.battle.engine")
  local Adapter = require("src.core.game3.battle.adapter")
  local player = mon(BULBASAUR, 5, { friendship = 100 })
  player.hp = 1
  player.moves, player.pp = { 33 }, { 35 }
  local foeMon = mon(CHANSEY, 40)
  foeMon.moves, foeMon.pp = { 33 }, { 35 }
  foeMon.attack = 200
  local st = State.new({ wild = true, playerParty = { player }, foeMon = foeMon })
  st.session = { party = { player } }
  local ad = Adapter.new(st)
  st.rng = function(a, b)
    if a == 1 and b == 100 then return 1 end
    if type(a) == "number" and type(b) == "number" then return b end
    return a or 0
  end
  ad.rng = function(_, lo, hi)
    if lo == 1 and hi == 100 then return 1 end
    if lo and hi then return hi end
    return lo or 0
  end
  Engine.resolveMove(st.enemy, st.player, 33, 1, ad, st, {})
  check(st.player.fainted == true, "the player mon fainted")
  eq(Pokemon.friendshipOf(st.player.mon), 95,
    "a 35 level gap is FRIENDSHIP_EVENT_FAINT_LARGE, -5 at the mid tier")
end

print("[test] 21. Daisy's massage (field_specials.c:2075)")
do
  local Natives = require("src.core.game3.scripting.natives")
  local Std = require("src.core.game3.scripting.stdscripts")
  eq(Std.SPECIAL.DaisyMassageServices, 0x197, "special id matches specials.inc:418")
  local handler = Natives.ALLOW and Natives.ALLOW["special:" .. Std.SPECIAL.DaisyMassageServices]
  check(type(handler) == "function", "special 0x197 has a handler")
  if type(handler) == "function" then
    local Runtime = require("src.core.game3.runtime")
    local Flags = require("src.core.game3.scripting.flags")
    local m = mon(BULBASAUR, 10, { friendship = 220 })
    local session = { party = { m }, vars = {} }
    local prev = Runtime.session
    Runtime.session = session
    local ctx = { vars = {}, session = session }
    Flags.setVar(nil, ctx, 0x8004, 0)
    Flags.setVar(nil, ctx, 0x4025, 500)
    handler(ctx, nil)
    eq(m.friendship, 223, "FRIENDSHIP_EVENT_MASSAGE is +3 at every tier")
    eq(tonumber(Flags.getVar(nil, ctx, 0x4025)), 0, "and the cooldown counter resets")
    Runtime.session = prev
  end
  local StepEvents = require("src.core.game3.step_events")
  local session = { party = {}, vars = { [0x4025] = 498 }, flags = {} }
  StepEvents.onStepTaken(session, nil)
  StepEvents.onStepTaken(session, nil)
  StepEvents.onStepTaken(session, nil)
  eq(session.vars[0x4025], 500, "RunMassageCooldownStepCounter stops at 500")
end

finish()
