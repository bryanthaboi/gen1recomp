#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local Moves = require("src.core.game3.battle.moves")
local ROM = {
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
}
for id, row in pairs(ROM) do row.numId = id end
Moves._romLoaded = true
Moves._rom = ROM
Moves.loadRomPack = function()
  Moves._romLoaded = true
  Moves._rom = ROM
  return true
end

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local Dex = require("src.core.game3.dex")
local Catching = require("src.core.game3.battle.catching")
local BattleBridge = require("src.core.game3.battle_bridge")
local SummaryData = require("src.core.game3.summary_data")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function party_mon(friendship, extra)
  local m = {
    species = 1, name = "BULBASAUR", nickname = "ALPHA", level = 10,
    hp = 30, maxHp = 30, attack = 12, defense = 12, spAtk = 12, spDef = 12, speed = 12,
    moves = { 33 }, pp = { 35 }, friendship = friendship, happiness = friendship,
  }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

local function new_session(friendships, extra)
  local s = {
    name = "RED",
    trainerId = 31337,
    regionMapSectionId = 89,
    party = {},
    dex = Dex.new(),
  }
  for _, f in ipairs(friendships or {}) do
    s.party[#s.party + 1] = party_mon(f)
  end
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

-- pokefirered/include/constants/trainers.h:267
local CLASS_LEADER, CLASS_ELITE_FOUR, CLASS_CHAMPION = 84, 87, 90
local CLASS_YOUNGSTER = 4

print("[test] 1. AdjustFriendship(FRIENDSHIP_EVENT_LEAGUE_BATTLE) at battle start")
do
  local session = new_session({ 50, 150, 250 })
  local view = { { friendship = 50 }, { friendship = 150 }, { friendship = 250 } }
  local changed = BattleBridge.applyLeagueFriendship(session, view,
    { trainerClass = CLASS_LEADER }, {})
  check(changed, "a gym leader battle adjusts friendship")
  -- pokefirered/src/pokemon.c:1623 sFriendshipEventDeltas[FRIENDSHIP_EVENT_LEAGUE_BATTLE]
  eq(session.party[1].friendship, 53, "friendship below 100 gains 3")
  eq(session.party[2].friendship, 152, "friendship 100 to 199 gains 2")
  eq(session.party[3].friendship, 251, "friendship 200 and up gains 1")
  eq(view[1].friendship, 53, "the battle party view follows slot 1")
  eq(view[3].friendship, 251, "the battle party view follows slot 3")
end

print("[test] 2. Only LEADER / ELITE_FOUR / CHAMPION trainer battles count")
do
  for _, cls in ipairs({ CLASS_LEADER, CLASS_ELITE_FOUR, CLASS_CHAMPION }) do
    local session = new_session({ 50 })
    BattleBridge.applyLeagueFriendship(session, nil, { trainerClass = cls }, {})
    eq(session.party[1].friendship, 53, "class " .. cls .. " gains 3")
  end
  local plain = new_session({ 50 })
  check(not BattleBridge.applyLeagueFriendship(plain, nil, { trainerClass = CLASS_YOUNGSTER }, {}),
    "an ordinary trainer class changes nothing")
  eq(plain.party[1].friendship, 50, "friendship untouched by a YOUNGSTER battle")

  -- pokefirered/src/pokemon.c:5481
  local wild = new_session({ 50 })
  check(not BattleBridge.applyLeagueFriendship(wild, nil, { trainerClass = CLASS_LEADER }, { wild = true }),
    "a wild battle never counts, whatever class rides along")
  eq(wild.party[1].friendship, 50, "friendship untouched by a wild battle")

  local none = new_session({ 50 })
  check(not BattleBridge.applyLeagueFriendship(none, nil, nil, {}), "no foe, no change")
end

print("[test] 3. The class comes from the trainer table, keyed by the opponent id")
do
  local prev = package.loaded["src.core.game3.scripting.trainers"]
  package.loaded["src.core.game3.scripting.trainers"] = {
    info = function(id)
      if tonumber(id) == 414 then return { class = CLASS_LEADER } end
      return { class = CLASS_YOUNGSTER }
    end,
  }
  local session = new_session({ 50 })
  BattleBridge.applyLeagueFriendship(session, nil, { trainerId = 414 }, {})
  eq(session.party[1].friendship, 53, "a foe row with no class resolves through the trainer id")

  local other = new_session({ 50 })
  BattleBridge.applyLeagueFriendship(other, nil, { trainerClass = CLASS_LEADER }, { trainerId = 9 })
  eq(other.party[1].friendship, 50, "the trainer table wins over a stale class on the foe row")
  package.loaded["src.core.game3.scripting.trainers"] = prev
end

print("[test] 4. Luxury Ball and met-location bonuses ride along")
do
  -- pokefirered/src/pokemon.c:5497
  local session = new_session({ 50 })
  session.party[1].pokeball = 11
  BattleBridge.applyLeagueFriendship(session, nil, { trainerClass = CLASS_LEADER }, {})
  eq(session.party[1].friendship, 54, "a Luxury Ball mon gains one more")

  -- pokefirered/src/pokemon.c:5499
  local home = new_session({ 50 })
  home.party[1].metLocation = 89
  BattleBridge.applyLeagueFriendship(home, nil, { trainerClass = CLASS_LEADER }, {})
  eq(home.party[1].friendship, 54, "a mon met in the current map section gains one more")

  local away = new_session({ 50 })
  away.party[1].metLocation = 3
  BattleBridge.applyLeagueFriendship(away, nil, { trainerClass = CLASS_LEADER }, {})
  eq(away.party[1].friendship, 53, "a mon met elsewhere gains the plain 3")
end

print("[test] 5. A caught mon records where and at what level it was met")
do
  local session = new_session({})
  session.regionMapSectionId = 91
  local foe = { species = 16, mon = { species = 16, speciesId = 16, level = 9, hp = 5, maxHp = 24 } }
  local res = Catching.storeCaught(session, foe, 4)
  check(res.success, "storeCaught succeeded")
  -- pokefirered/src/pokemon.c:1817
  eq(res.mon.metLocation, 91, "metLocation is the current region map section")
  -- pokefirered/src/pokemon.c:1818
  eq(res.mon.metLevel, 9, "metLevel is the level it was caught at")
  eq(session.party[1].metLocation, 91, "the stored party row carries it")

  local later = Catching.storeCaught(session, { species = 19,
    mon = { species = 19, speciesId = 19, level = 3, hp = 1, maxHp = 12 } }, 4)
  eq(later.mon.metLevel, 3, "a second catch records its own met level")

  -- pokefirered/src/pokemon_summary_screen.c:2633
  local okSec, Sections = pcall(require, "src.import.gba.map_sections_extract")
  local okName, info = false, nil
  if okSec then okName, info = pcall(Sections.getInfo, 91, nil, 0) end
  if okName and info and info.name and info.name ~= "???" then
    eq(res.mon.metLocationName, info.name, "the trainer memo name comes from the map section table")
  else
    print("[skip] met location name: no map section table on this checkout")
  end
end

print("[test] 6. A caught mon carries the player's secret id")
do
  local session = new_session({})
  local foe = { species = 16, mon = { species = 16, speciesId = 16, level = 9, hp = 5, maxHp = 24 } }
  local first = Catching.storeCaught(session, foe, 4).mon
  check(type(first.otSecretId) == "number", "otSecretId is a number")
  check(first.otSecretId >= 0 and first.otSecretId < 0x10000, "otSecretId is 16 bit")
  eq(first.otId, 31337, "otId is still the visible trainer id")

  local second = Catching.storeCaught(session, { species = 19,
    mon = { species = 19, speciesId = 19, level = 3, hp = 1, maxHp = 12 } }, 4).mon
  eq(second.otSecretId, first.otSecretId, "every catch in one session shares one secret id")

  local reloaded = new_session({})
  reloaded.party[1] = party_mon(70, { otId = 31337, otSecretId = first.otSecretId })
  local third = Catching.storeCaught(reloaded, { species = 21,
    mon = { species = 21, speciesId = 21, level = 5, hp = 1, maxHp = 14 } }, 4).mon
  eq(third.otSecretId, first.otSecretId, "the secret id is taken back off the player's own party")
  eq(reloaded.secretId, first.otSecretId, "and cached on the session")

  local traded = new_session({})
  traded.party[1] = party_mon(70, { otId = 999, otSecretId = 4242 })
  local fresh = Catching.storeCaught(traded, { species = 23,
    mon = { species = 23, speciesId = 23, level = 5, hp = 1, maxHp = 14 } }, 4).mon
  check(fresh.otSecretId ~= 4242, "a traded mon's secret id is not adopted")
end

print("[test] 7. The shininess check reads the stored secret id")
do
  -- pokefirered/include/pokemon.h:282
  local session = new_session({})
  session.trainerId = 0
  session.secretId = 0
  local shiny = Catching.storeCaught(session, { species = 25,
    mon = { species = 25, speciesId = 25, level = 5, hp = 1, maxHp = 14, personality = 0 } }, 4).mon
  check(SummaryData.isShiny(shiny), "otId 0, secret 0 and personality 0 reads shiny")

  local plainSession = new_session({})
  plainSession.trainerId = 0
  plainSession.secretId = 0
  local plain = Catching.storeCaught(plainSession, { species = 26,
    mon = { species = 26, speciesId = 26, level = 5, hp = 1, maxHp = 14, personality = 0xFFFF } }, 4).mon
  check(not SummaryData.isShiny(plain), "a personality whose halves differ reads plain")
end

print("[test] 8. Start-of-battle ability messages reach the message log in order")
do
  local function drizzle_battle(headless)
    Battle.abort()
    local session = new_session({ 70 })
    Battle.start({
      headless = true,
      autoFight = false,
      wild = true,
      session = session,
      playerParty = session.party,
      rng = function(_, hi) return hi end,
      foe = { species = 16, nickname = "BRAVO", level = 8, hp = 24, maxHp = 24,
        attack = 10, defense = 10, spAtk = 10, spDef = 10, speed = 30, ability = "DRIZZLE",
        moves = { 33 }, pp = { 35 } },
    })
    Battle._headless = headless
    local st = Battle.getState()
    for _ = 1, 200 do
      Battle.update(0, nil)
      if Battle._phase == "command" then break end
    end
    local log = {}
    for _, t in ipairs(Ui.log() or {}) do log[#log + 1] = tostring(t) end
    Battle.abort()
    return st, log
  end

  local function index_of(log, text)
    for i, t in ipairs(log) do
      if t:find(text, 1, true) then return i end
    end
    return nil
  end

  local st, log = drizzle_battle(true)
  eq(st.weather, "RAIN", "headless: DRIZZLE set the weather")
  local sendOut = index_of(log, "Go! ALPHA!")
  local rain = index_of(log, "DRIZZLE")
  check(rain ~= nil, "headless: the DRIZZLE message is in the log")
  check(sendOut and rain and rain > sendOut, "headless: it comes after the send out")

  local st2, log2 = drizzle_battle(false)
  eq(st2.weather, "RAIN", "animated: DRIZZLE set the weather")
  local sendOut2 = index_of(log2, "Go! ALPHA!")
  local rain2 = index_of(log2, "DRIZZLE")
  check(rain2 ~= nil, "animated: the replayed DRIZZLE message is in the log")
  check(sendOut2 and rain2 and rain2 > sendOut2, "animated: it comes after the send out")
end

print("[test] 9. The wild foe is created with the player's OT id, so shininess cannot flip")
do
  local function wild_battle(session, personality)
    Battle.abort()
    Battle.start({
      headless = true,
      autoFight = false,
      wild = true,
      session = session,
      playerParty = session.party,
      rng = function(_, hi) return hi end,
      foe = { species = 16, level = 8, hp = 24, maxHp = 24, personality = personality,
        attack = 10, defense = 10, spAtk = 10, spDef = 10, speed = 30,
        moves = { 33 }, pp = { 35 } },
    })
    return Battle.getState()
  end

  -- pokefirered/src/pokemon.c:1796
  local session = new_session({ 70 }, { secretId = 4242 })
  local st = wild_battle(session, 0x00010001)
  eq(st.enemy.mon.otId, 31337, "the wild foe carries the player's visible id")
  eq(st.enemy.mon.otSecretId, 4242, "and the player's secret id")
  local inBattle = SummaryData.isShiny(st.enemy.mon)
  local caught = Catching.storeCaught(session, st.enemy, 4).mon
  eq(SummaryData.isShiny(caught), inBattle, "a plain foe is plain after the catch too")
  Battle.abort()

  local shinySession = new_session({ 70 }, { secretId = 4242 })
  local shinyPid = require("bit").bxor(31337, 4242)
  local st2 = wild_battle(shinySession, shinyPid)
  check(SummaryData.isShiny(st2.enemy.mon), "a shiny personality sparkles in the battle")
  local kept = Catching.storeCaught(shinySession, st2.enemy, 4).mon
  check(SummaryData.isShiny(kept), "and it is still shiny once caught")
  Battle.abort()

  -- pokefirered/src/battle_setup.c:897
  local trainerSession = new_session({ 70 }, { secretId = 4242 })
  Battle.abort()
  Battle.start({
    headless = true, autoFight = false, wild = false, session = trainerSession,
    playerParty = trainerSession.party, rng = function(_, hi) return hi end,
    foe = { species = 19, level = 8, hp = 20, maxHp = 20, otId = 777,
      attack = 10, defense = 10, spAtk = 10, spDef = 10, speed = 30,
      moves = { 33 }, pp = { 35 } },
  })
  check(tonumber(Battle.getState().enemy.mon.otId) ~= 31337,
    "a trainer's mon is never stamped with the player's OT id")
  Battle.abort()
end

print("[test] 10. A boxed catch keeps the player's secret id across a save and load")
do
  local Schema = require("src.core.game3.save_schema_firered")
  local s1 = Schema.newGame({ rngSeed = 1 })
  s1.party = {}
  for i = 1, 6 do
    s1.party[i] = party_mon(70, { species = 1, speciesId = 1, personality = i,
      otId = s1.trainerId })
  end
  local first = Catching.storeCaught(s1, { species = 16,
    mon = { species = 16, speciesId = 16, level = 5, hp = 5, maxHp = 20, personality = 77 } }, 4)
  eq(first.location, "pc", "a full party sends the catch to the PC")
  local s2 = Schema.fromSaveTable(Schema.toSaveTable(s1))
  s2.party = {}
  local second = Catching.storeCaught(s2, { species = 19,
    mon = { species = 19, speciesId = 19, level = 3, hp = 5, maxHp = 12, personality = 78 } }, 4)
  check(type(first.mon.otSecretId) == "number", "the boxed catch got a secret id")
  eq(second.mon.otSecretId, first.mon.otSecretId,
    "the boxed mon hands the secret id back after the reload")
end

print(string.format("%d passed, %d failed", passed, failed))
print(failed == 0 and "BATTLE_FRIENDSHIP PASS" or "BATTLE_FRIENDSHIP FAIL")
os.exit(failed == 0 and 0 or 1)
