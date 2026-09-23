#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
local GameCache = require("tests.game3_cache")
if not GameCache.bundle() then
  print("[skip] game3 battle items + abilities: " .. tostring(GameCache.reason))
  os.exit(0)
end
require("tests.fixture_data.game3_items").install()

local Moves = require("src.core.game3.battle.moves")

-- pokefirered/src/data/battle_moves.h:1
local ROM = {
  [1] = { effect = 0, power = 40, type = 0, accuracy = 100, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [10] = { effect = 0, power = 40, type = 0, accuracy = 100, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [12] = { effect = 38, power = 1, type = 0, accuracy = 30, pp = 5, secondaryChance = 0, target = 0, priority = 0, flags = 19 },
  [24] = { effect = 44, power = 30, type = 1, accuracy = 100, pp = 30, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [33] = { effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [45] = { effect = 18, power = 0, type = 0, accuracy = 100, pp = 40, secondaryChance = 0, target = 8, priority = 0, flags = 22 },
  [52] = { effect = 4, power = 40, type = 10, accuracy = 100, pp = 25, secondaryChance = 10, target = 0, priority = 0, flags = 18 },
  [53] = { effect = 4, power = 95, type = 10, accuracy = 100, pp = 15, secondaryChance = 10, target = 0, priority = 0, flags = 18 },
  [55] = { effect = 0, power = 40, type = 11, accuracy = 100, pp = 25, secondaryChance = 0, target = 0, priority = 0, flags = 50 },
  [85] = { effect = 6, power = 95, type = 13, accuracy = 100, pp = 15, secondaryChance = 10, target = 0, priority = 0, flags = 18 },
  [86] = { effect = 67, power = 0, type = 13, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 22 },
  [92] = { effect = 33, power = 0, type = 3, accuracy = 85, pp = 10, secondaryChance = 100, target = 0, priority = 0, flags = 22 },
  [150] = { effect = 85, power = 0, type = 0, accuracy = 0, pp = 40, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
  [163] = { effect = 43, power = 70, type = 0, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [240] = { effect = 136, power = 0, type = 11, accuracy = 0, pp = 5, secondaryChance = 0, target = 16, priority = 0, flags = 0 },
}
for id, row in pairs(ROM) do row.numId = id end
Moves._romLoaded = true
Moves._rom = ROM

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local Damage = require("src.core.game3.battle.damage")
local Types = require("src.core.game3.battle.types")
local HeldItems = require("src.core.game3.battle.held_items")
local T = Types.ID

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

local function mon(o)
  return {
    species = o.species or 1, level = o.level or 50, hp = o.hp or 100, maxHp = o.maxHp or 100,
    attack = o.attack or 50, defense = o.defense or 50, spAtk = o.spAtk or 50, spDef = o.spDef or 50,
    speed = o.speed or 50, ability = o.ability or 0, nickname = o.nickname,
    moves = o.moves or { 33 }, pp = o.pp or { 20, 20, 20, 20 }, maxPp = o.maxPp, status = o.status,
    item = o.item, heldItem = o.item, gender = o.gender, personality = o.personality or 0,
    otId = o.otId, otName = o.otName,
  }
end

local function mkRng(map)
  map = map or {}
  local cursor = {}
  return function(lo, hi)
    local key = tostring(lo) .. "," .. tostring(hi)
    local v = map[key]
    if type(v) == "table" then
      local i = (cursor[key] or 0) + 1
      cursor[key] = i
      v = v[math.min(i, #v)]
    end
    if v ~= nil then return v end
    if lo == 1 and hi == 100 then return 1 end
    return hi
  end
end

local function battle(p, e, extra)
  extra = extra or {}
  p.nickname = p.nickname or "ALPHA"
  e.nickname = e.nickname or "BRAVO"
  local party = { mon(p) }
  for _, x in ipairs(extra.bench or {}) do party[#party + 1] = mon(x) end
  local foeParty = { mon(e) }
  for _, x in ipairs(extra.foeBench or {}) do foeParty[#foeParty + 1] = mon(x) end
  local st = State.new({ wild = extra.wild ~= false, playerParty = party, foeParty = foeParty })
  st.player.type1, st.player.type2 = p.type1 or T.NORMAL, p.type2
  st.enemy.type1, st.enemy.type2 = e.type1 or T.NORMAL, e.type2
  st.player.species = p.species or st.player.species
  st.enemy.species = e.species or st.enemy.species
  st.rng = mkRng(extra.rng)
  st.badges = extra.badges
  st.playerTrainerId = extra.playerTrainerId
  st.playerName = extra.playerName
  local ad = Adapter.new(st)
  return st, ad
end

local function use(st, ad, user, move, slot)
  local target = (user == st.player) and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, slot or 1, ad, st, out)
  return table.concat(out, " || "), out
end

local function eot(st, ad)
  local events = Engine.collectResidualEvents(st, ad)
  local msgs, evs = {}, {}
  for _, ev in ipairs(events) do
    for _, m in ipairs(ev.msgs or {}) do msgs[#msgs + 1] = m end
    for _, e in ipairs(ev.events or {}) do evs[#evs + 1] = e end
  end
  return table.concat(msgs, " || "), evs
end

local function has(s, needle) return s:find(needle, 1, true) ~= nil end

local function hasAnim(evs, name, side)
  for _, e in ipairs(evs or {}) do
    if e.kind == "anim" and e.name == name and (side == nil or e.target == side) then return true end
  end
  return false
end

local function hpEvent(evs, side)
  for _, e in ipairs(evs or {}) do
    if e.kind == "hp" and e.side == side then return e end
  end
  return nil
end

print("=== LEFTOVERS ===")
do
  local st, ad = battle({ item = 200, hp = 50, maxHp = 160 }, {})
  local txt, evs = eot(st, ad)
  check(ad:hp(st.player) == 60, "Leftovers heals maxHP/16 at end of turn")
  check(has(txt, "ALPHA's LEFTOVERS\nrestored its HP a little!") or has(txt, "restored its HP a little!"), "Leftovers message")
  check(hasAnim(evs, "HELD_ITEM_EFFECT", "player") and hpEvent(evs, "player") ~= nil, "Leftovers plays HELD_ITEM_EFFECT and emits hp event")
  check(st.player.item == 200, "Leftovers is not consumed")
end

print("=== ORAN / SITRUS (consumed, persisted, recyclable) ===")
do
  local st, ad = battle({ item = 139, hp = 50, maxHp = 100 }, {})
  eot(st, ad)
  check(ad:hp(st.player) == 60, "Oran Berry restores 10 HP at <= 1/2")
  check(st.player.item == 0 and st.playerParty[1].item == nil, "consumed berry is removed from the party mon")
  check(st.playerSide.expUsedHeldItem == 139, "used held item recorded for Recycle")

  local st2, ad2 = battle({ item = 142, hp = 51, maxHp = 100 }, {})
  eot(st2, ad2)
  check(ad2:hp(st2.player) == 51 and st2.player.item == 142, "Sitrus waits until HP <= 1/2")

  local st3, ad3 = battle({ item = 139, hp = 10, maxHp = 100 }, { moves = { 33 } })
  use(st3, ad3, st3.enemy, 33)
  check(st3.player.item == 139, "HP berries do not trigger mid-turn (moveTurn)")
end

print("=== CHERI / LUM / PERSIM at move end ===")
do
  local st, ad = battle({ item = 133 }, { moves = { 86 } })
  local txt = use(st, ad, st.enemy, 86)
  check(ad:status(st.player) == nil and st.player.item == 0, "Cheri Berry cures Thunder Wave paralysis right away")
  check(has(txt, "ALPHA's CHERI BERRY\ncured paralysis!"), "Cheri message")

  local st2, ad2 = battle({ item = 141, status = "PAR" }, {})
  st2.player.confusionTurns = 3
  local txt2 = eot(st2, ad2)
  check(has(txt2, "LUM BERRY\nnormalized its status!") and ad2:status(st2.player) == nil
    and (st2.player.confusionTurns or 0) == 0, "Lum Berry normalizes multiple problems at end of turn")

  local st3, ad3 = battle({ item = 140 }, { moves = { 150 } })
  st3.player.confusionTurns = 3
  local txt3 = use(st3, ad3, st3.enemy, 150)
  check(has(txt3, "snapped it out of confusion!") and (st3.player.confusionTurns or 0) == 0, "Persim Berry at move end")
end

print("=== CONFUSION BERRIES (flavor dislike) ===")
do
  local st, ad = battle({ item = 143, hp = 40, maxHp = 80, personality = 15 }, {}, { rng = { ["0,3"] = 1 } })
  local txt = eot(st, ad)
  check(ad:hp(st.player) == 50, "Figy restores maxHP/8")
  check(has(txt, "For ALPHA,\nFIGY BERRY was too spicy!") and (st.player.confusionTurns or 0) == 3,
    "Modest nature dislikes spicy and gets confused")
  local st2, ad2 = battle({ item = 143, hp = 40, maxHp = 80, personality = 3 }, {})
  local txt2 = eot(st2, ad2)
  check(not has(txt2, "too spicy") and (st2.player.confusionTurns or 0) == 0, "Adamant nature likes spicy")
end

print("=== PINCH STAT BERRIES ===")
do
  local st, ad = battle({ item = 168, hp = 25, maxHp = 100 }, {})
  local txt, evs = eot(st, ad)
  check(st.player.stages.attack == 1 and st.player.item == 0, "Liechi raises Attack at 1/4 HP")
  check(has(txt, "Using LIECHI BERRY, the ATTACK\nof ALPHA rose!"), "stat berry message")
  check(hasAnim(evs, "HELD_ITEM_EFFECT") and hasAnim(evs, "STATS_CHANGE"), "stat berry anims")

  local st2, ad2 = battle({ item = 174, hp = 20, maxHp = 100 }, {}, { rng = { ["0,4"] = 2 } })
  local txt2 = eot(st2, ad2)
  check(st2.player.stages.speed == 2 and has(txt2, "sharply rose!"), "Starf sharply raises a random stat")

  local st3, ad3 = battle({ item = 173, hp = 20, maxHp = 100 }, {})
  local txt3 = eot(st3, ad3)
  check(st3.player.focusEnergy and has(txt3, "used\nLANSAT BERRY to hustle!"), "Lansat sets focus energy")
end

print("=== LEPPA ===")
do
  local st, ad = battle({ item = 138, moves = { 33, 1 }, pp = { 0, 5 }, maxPp = { 35, 35 } }, {})
  local txt = eot(st, ad)
  check(st.player.mon.pp[1] == 10 and st.playerParty[1].pp[1] == 10, "Leppa restores 10 PP to the empty move")
  check(has(txt, "restored TACKLE's PP!") or has(txt, "'s PP!"), "Leppa message")
end

print("=== WHITE HERB / MENTAL HERB ===")
do
  local st, ad = battle({ item = 180 }, { moves = { 45 } })
  local txt = use(st, ad, st.enemy, 45)
  check(st.player.stages.attack == 0 and st.player.item == 0 and has(txt, "WHITE HERB\nrestored its status!"),
    "White Herb restores lowered stats at move end")
  local st2, ad2 = battle({ item = 185 }, { moves = { 150 } })
  st2.player.expInfatuated = true
  st2.player.expInfatuatedWith = st2.enemy
  local txt2 = use(st2, ad2, st2.enemy, 150)
  check(not st2.player.expInfatuated and has(txt2, "MENTAL HERB\ncured its love problem!"), "Mental Herb cures infatuation")
end

print("=== DAMAGE ITEMS ===")
do
  local function base(p, e, move, extra)
    local st, ad = battle(p, e, extra)
    return Damage.base(st.player, st.enemy, ROM[move], { adapter = ad, power = ROM[move].power, moveType = ROM[move].type })
  end
  local plain = base({}, {}, 33)
  check(base({ item = 186 }, {}, 33) > plain, "Choice Band boosts physical attack")
  check(base({ item = 215 }, {}, 52) > base({}, {}, 52), "Charcoal boosts Fire moves")
  check(base({ item = 215 }, {}, 33) == plain, "Charcoal does not boost Normal moves")
  check(base({ item = 202, species = 25 }, {}, 85) > base({ species = 25 }, {}, 85), "Light Ball doubles Pikachu SpAtk")
  check(base({ item = 224, species = 104 }, {}, 33) > base({ species = 104 }, {}, 33), "Thick Club doubles Cubone Attack")
  check(base({}, { item = 223, species = 132 }, 33) < base({}, { species = 132 }, 33), "Metal Powder doubles Ditto Defense")
  check(base({ item = 192, species = 373 }, {}, 55) > base({ species = 373 }, {}, 55), "DeepSeaTooth for Clamperl")
  check(base({ item = 191, species = 407 }, {}, 55) > base({ species = 407 }, {}, 55), "Soul Dew for Latias")
  check(base({}, {}, 33, { badges = { true } }) > plain, "Boulder Badge boosts player Attack")
  check(base({ ability = "PLUS" }, { ability = "MINUS" }, 55) > base({ ability = "PLUS" }, {}, 55), "Plus with Minus on field")
end

print("=== CHOICE BAND lock ===")
do
  local st, ad = battle({ item = 186, moves = { 33, 1 } }, { hp = 999, maxHp = 999 })
  use(st, ad, st.player, 33, 1)
  check(st.player.choicedMove == 33, "Choice Band records the locked move on the battler")
  local acts = Engine.planTurnFromActions(st, ad, { kind = "move", move = 1, slot = 2 }, { kind = "move", move = 33, slot = 1 })
  local pAct
  for _, a in ipairs(acts) do if a.user == st.player then pAct = a end end
  check(pAct and pAct.move == 33 and pAct.slot == 1, "planTurn enforces the Choice Band move")
  local bad = Engine.moveLimitations(st.player, ad)
  check(bad[2] and not bad[1], "moveLimitations greys out non-choiced moves")
end

print("=== QUICK CLAW / MACHO BRACE ===")
do
  local st, ad = battle({ item = 183, speed = 10 }, { speed = 100 }, { rng = { ["0,65535"] = 100 } })
  local acts = Engine.planTurnFromActions(st, ad, { kind = "move", move = 33, slot = 1 }, { kind = "move", move = 33, slot = 1 })
  check(acts[1].user == st.player, "Quick Claw activates when randomTurnNumber < 0xFFFF*20/100")
  local st2, ad2 = battle({ item = 183, speed = 10 }, { speed = 100 }, { rng = { ["0,65535"] = 20000 } })
  local acts2 = Engine.planTurnFromActions(st2, ad2, { kind = "move", move = 33, slot = 1 }, { kind = "move", move = 33, slot = 1 })
  check(acts2[1].user == st2.enemy, "Quick Claw does not activate on a high roll")
  local st3, ad3 = battle({ item = 181, speed = 100 }, { speed = 60 })
  check(Engine.speedOf(st3.player, st3, ad3) == 50, "Macho Brace halves speed")
  local st4, ad4 = battle({ speed = 100 }, {}, { badges = { false, false, true } })
  check(Engine.speedOf(st4.player, st4, ad4) == 110, "Thunder Badge speed boost")
end

print("=== BRIGHT POWDER / LAX INCENSE ===")
do
  local st, ad = battle({ moves = { 1 } }, { item = 179, hp = 999, maxHp = 999 }, { rng = { ["1,100"] = 91 } })
  local txt = use(st, ad, st.player, 1)
  check(has(txt, "attack missed"), "Bright Powder: 100 acc -> 90")
  local st2, ad2 = battle({ moves = { 1 } }, { item = 221, hp = 999, maxHp = 999 }, { rng = { ["1,100"] = 91 } })
  local txt2 = use(st2, ad2, st2.player, 1)
  check(not has(txt2, "attack missed"), "Lax Incense uses param 5 (95)")
end

print("=== FOCUS BAND ===")
do
  local st, ad = battle({ moves = { 163 }, attack = 300 }, { item = 196, hp = 5, maxHp = 100 }, { rng = { ["0,99"] = 0 } })
  local txt, out = use(st, ad, st.player, 163)
  check(ad:hp(st.enemy) == 1, "Focus Band leaves 1 HP")
  check(has(txt, "BRAVO hung on\nusing its FOCUS BAND!"), "Focus Band message")
  check(hasAnim(out.events, "FOCUS_BAND", "enemy"), "FOCUS_BAND anim")
  local st2, ad2 = battle({ moves = { 12 }, level = 60 }, { item = 196, level = 50 }, { rng = { ["0,99"] = 0, ["1,100"] = 1 } })
  use(st2, ad2, st2.player, 12)
  check(ad2:hp(st2.enemy) == 1, "Focus Band survives an OHKO move")
end

print("=== KING'S ROCK / SHELL BELL ===")
do
  local st, ad = battle({ item = 187, moves = { 33 } }, { hp = 999, maxHp = 999 }, { rng = { ["0,99"] = 0 } })
  use(st, ad, st.player, 33)
  check(st.enemy.flinched == true, "King's Rock flinches on a contact move")
  local st2, ad2 = battle({ item = 219, moves = { 33 }, hp = 50, maxHp = 100 }, { hp = 999, maxHp = 999 })
  local _, out = use(st2, ad2, st2.player, 33)
  local dealt = 999 - ad2:hp(st2.enemy)
  check(ad2:hp(st2.player) == 50 + math.max(1, math.floor(dealt / 8)), "Shell Bell heals 1/8 damage dealt")
  check(hasAnim(out.events, "HELD_ITEM_EFFECT", "player"), "Shell Bell anim")
end

print("=== FLEE / SMOKE BALL / RUN AWAY / TRAPPING ===")
do
  local st, ad = battle({ item = 194, speed = 1 }, { speed = 200 })
  local ok, how = Engine.tryFlee(st, ad)
  check(ok and how == "item", "Smoke Ball always escapes")
  check(hasAnim(ad:events(), "SMOKEBALL_ESCAPE"), "SMOKEBALL_ESCAPE anim")
  local st2, ad2 = battle({ ability = "RUN_AWAY", speed = 1 }, { speed = 200 })
  local ok2, how2 = Engine.tryFlee(st2, ad2)
  check(ok2 and how2 == "ability", "Run Away always escapes")
  local st3, ad3 = battle({ speed = 10 }, { speed = 100 }, { rng = { ["0,255"] = 11 } })
  check(Engine.tryFlee(st3, ad3) == true, "flee: 10*128/100 = 12 > 11")
  local st4, ad4 = battle({ speed = 10 }, { speed = 100 }, { rng = { ["0,255"] = 12 } })
  check(Engine.tryFlee(st4, ad4) == false and st4.fleeAttempts == 1, "flee fails and counts attempts")
  local st5, ad5 = battle({}, { ability = "SHADOW_TAG" })
  local can, msg = Engine.canRun(st5, ad5)
  check(not can and has(msg, "prevents\nescape with SHADOW TAG!"), "Shadow Tag prevents escape")
  local st6, ad6 = battle({ type1 = T.FLYING }, { ability = "ARENA_TRAP" })
  check(Engine.canRun(st6, ad6) == true, "Arena Trap does not trap Flying types")
end

print("=== INTIMIDATE / DRIZZLE / TRACE at battle start ===")
do
  local st, ad = battle({ ability = "INTIMIDATE" }, {})
  local out = {}
  ad._say = function(t) out[#out + 1] = t end
  Engine.battleStartEffects(st, ad)
  local txt = table.concat(out, " || ")
  check(st.enemy.stages.attack == -1 and has(txt, "ALPHA's INTIMIDATE\ncuts Wild BRAVO's ATTACK!"), "Intimidate lowers foe Attack")
  check(hasAnim(ad:events(), "STATS_CHANGE", "enemy"), "Intimidate plays STATS_CHANGE on the foe")

  local st2, ad2 = battle({ ability = "INTIMIDATE" }, { ability = "HYPER_CUTTER" })
  local o2 = {}
  ad2._say = function(t) o2[#o2 + 1] = t end
  Engine.battleStartEffects(st2, ad2)
  check(st2.enemy.stages.attack == 0 and has(table.concat(o2), "Wild BRAVO's HYPER CUTTER\nprevented ALPHA's\\lINTIMIDATE from working!"),
    "Hyper Cutter blocks Intimidate")

  local st3, ad3 = battle({}, { ability = "DRIZZLE" })
  local o3 = {}
  ad3._say = function(t) o3[#o3 + 1] = t end
  Engine.battleStartEffects(st3, ad3)
  check(st3.weather == "RAIN" and (st3.weatherTurns or 0) == 0, "Drizzle sets permanent rain")
  check(has(table.concat(o3), "BRAVO's DRIZZLE\nmade it rain!") and hasAnim(ad3:events(), "RAIN_CONTINUES"), "Drizzle message + anim")

  local st4, ad4 = battle({ ability = "TRACE" }, { ability = "STATIC" })
  local o4 = {}
  ad4._say = function(t) o4[#o4 + 1] = t end
  Engine.battleStartEffects(st4, ad4)
  check(ad4:abilityOf(st4.player) == "STATIC" and has(table.concat(o4), "ALPHA TRACED\nWild BRAVO's STATIC!"), "Trace copies the foe ability")
end

print("=== CONTACT ABILITIES ===")
do
  local st, ad = battle({ moves = { 33 } }, { ability = "STATIC", hp = 999, maxHp = 999 }, { rng = { ["0,2"] = 0 } })
  local txt = use(st, ad, st.player, 33)
  check(ad:status(st.player) == "PAR" and has(txt, "BRAVO's STATIC\nparalyzed ALPHA!"), "Static paralyzes on contact")
  local st2, ad2 = battle({ moves = { 55 } }, { ability = "STATIC", hp = 999, maxHp = 999 }, { rng = { ["0,2"] = 0 } })
  use(st2, ad2, st2.player, 55)
  check(ad2:status(st2.player) == nil, "Static ignores non-contact moves")
  local st3, ad3 = battle({ moves = { 33 }, maxHp = 160, hp = 160 }, { ability = "ROUGH_SKIN", hp = 999, maxHp = 999 })
  local txt3 = use(st3, ad3, st3.player, 33)
  check(ad3:hp(st3.player) == 150 and has(txt3, "BRAVO's ROUGH SKIN\nhurt ALPHA!"), "Rough Skin deals 1/16")
  local st4, ad4 = battle({ moves = { 33 } }, { ability = "EFFECT_SPORE", hp = 999, maxHp = 999 },
    { rng = { ["0,9"] = 0, ["0,3"] = 1 } })
  local txt4 = use(st4, ad4, st4.player, 33)
  check(ad4:status(st4.player) == "SLP" and has(txt4, "EFFECT SPORE\nmade ALPHA sleep!"), "Effect Spore sleep")
  local st5, ad5 = battle({ moves = { 33 }, ability = "LIMBER" }, { ability = "STATIC", hp = 999, maxHp = 999 }, { rng = { ["0,2"] = 0 } })
  local txt5 = use(st5, ad5, st5.player, 33)
  check(ad5:status(st5.player) == nil and not has(txt5, "prevents"), "Limber silently blocks Static")
  local st6, ad6 = battle({ moves = { 33 }, gender = "M" }, { ability = "CUTE_CHARM", gender = "F", hp = 999, maxHp = 999 }, { rng = { ["0,2"] = 0 } })
  local txt6 = use(st6, ad6, st6.player, 33)
  check(st6.player.expInfatuated and has(txt6, "BRAVO's CUTE CHARM\ninfatuated ALPHA!"), "Cute Charm infatuates")
  local st7, ad7 = battle({ moves = { 52 } }, { ability = "COLOR_CHANGE", hp = 999, maxHp = 999 })
  local txt7 = use(st7, ad7, st7.player, 52)
  check(st7.enemy.type1 == T.FIRE and has(txt7, "COLOR CHANGE\nmade it the FIRE type!"), "Color Change")
end

print("=== ABSORB ABILITIES / SOUNDPROOF ===")
do
  local st, ad = battle({ moves = { 85 } }, { ability = "VOLT_ABSORB", hp = 50, maxHp = 100 })
  local txt = use(st, ad, st.player, 85)
  check(ad:hp(st.enemy) == 75 and has(txt, "BRAVO restored HP\nusing its VOLT ABSORB!"), "Volt Absorb heals 1/4")
  local st2, ad2 = battle({ moves = { 55 } }, { ability = "WATER_ABSORB" })
  local txt2 = use(st2, ad2, st2.player, 55)
  check(ad2:hp(st2.enemy) == 100 and has(txt2, "BRAVO's WATER ABSORB\nmade ") and has(txt2, " useless!"), "Water Absorb at full HP")
  local st3, ad3 = battle({ moves = { 52 } }, { ability = "FLASH_FIRE" })
  local txt3 = use(st3, ad3, st3.player, 52)
  check(st3.enemy.expFlashFire and has(txt3, "FLASH FIRE\nraised its FIRE power!"), "Flash Fire activates")
  local st4, ad4 = battle({ moves = { 45 } }, { ability = "SOUNDPROOF" })
  local txt4 = use(st4, ad4, st4.player, 45)
  check(st4.enemy.stages.attack == 0 and has(txt4, "BRAVO's SOUNDPROOF\nblocks GROWL!"), "Soundproof blocks Growl")
end

print("=== SYNCHRONIZE / IMMUNITY CURE ===")
do
  local st, ad = battle({ moves = { 86 } }, { ability = "SYNCHRONIZE" })
  local txt = use(st, ad, st.player, 86)
  check(ad:status(st.enemy) == "PAR" and ad:status(st.player) == "PAR", "Synchronize passes paralysis back")
  check(has(txt, "BRAVO's SYNCHRONIZE\nparalyzed ALPHA!"), "Synchronize message")
  local st2, ad2 = battle({ moves = { 92 } }, { ability = "SYNCHRONIZE" }, { rng = { ["1,100"] = 1 } })
  use(st2, ad2, st2.player, 92)
  check(ad2:status(st2.player) == "PSN", "Synchronize turns Toxic into regular poison")
  local st3, ad3 = battle({ status = "PSN", ability = "IMMUNITY" }, { moves = { 150 } })
  local txt3 = use(st3, ad3, st3.enemy, 150)
  check(ad3:status(st3.player) == nil and has(txt3, "ALPHA's IMMUNITY\ncured its poison problem!"), "Immunity cures poison at move end")
end

print("=== END-OF-TURN ABILITIES ===")
do
  local st, ad = battle({ ability = "SPEED_BOOST" }, {})
  st.player.isFirstTurn = 1
  local txt = eot(st, ad)
  check(st.player.stages.speed == 1 and has(txt, "ALPHA's SPEED BOOST\nraised its SPEED!"), "Speed Boost")
  local st2, ad2 = battle({ ability = "SPEED_BOOST" }, {})
  eot(st2, ad2)
  check(st2.player.stages.speed == 0, "Speed Boost skips the switch-in turn")
  local st3, ad3 = battle({ ability = "RAIN_DISH", hp = 50, maxHp = 160 }, {})
  st3.weather, st3.weatherTurns = "RAIN", 5
  eot(st3, ad3)
  check(ad3:hp(st3.player) == 60, "Rain Dish heals 1/16 in rain")
  local st4, ad4 = battle({ ability = "SHED_SKIN", status = "BRN" }, {}, { rng = { ["0,2"] = 0 } })
  local txt4 = eot(st4, ad4)
  check(ad4:status(st4.player) == nil and has(txt4, "SHED SKIN\ncured its burn problem!"), "Shed Skin")
end

print("=== TRUANT ===")
do
  local st, ad = battle({ ability = "TRUANT", moves = { 33 } }, { hp = 999, maxHp = 999 })
  use(st, ad, st.player, 33)
  eot(st, ad)
  local txt = use(st, ad, st.player, 33)
  check(has(txt, "ALPHA is\nloafing around!"), "Truant loafs every other turn")
  eot(st, ad)
  local txt2 = use(st, ad, st.player, 33)
  check(not has(txt2, "loafing"), "Truant acts again the next turn")
end

print("=== NATURAL CURE / FORECAST ===")
do
  local st, ad = battle({ ability = "NATURAL_CURE", status = "PSN" }, {})
  Engine.switchOutEffects(st, ad, st.player)
  check(ad:status(st.player) == nil and st.playerParty[1].status == nil, "Natural Cure cures on switch-out")
  local st2, ad2 = battle({}, { ability = "FORECAST", species = 385, moves = { 240 } })
  local txt2 = use(st2, ad2, st2.enemy, 240)
  check(st2.enemy.type1 == T.WATER and has(txt2, "BRAVO transformed!"), "Forecast turns Castform Water in rain")
  check(hasAnim(ad2:events(), "CASTFORM_CHANGE", "enemy"), "CASTFORM_CHANGE anim")
end

print("=== DISOBEDIENCE ===")
do
  local st, ad = battle({ moves = { 33 }, level = 60, otId = 999, otName = "ASH" }, { hp = 999, maxHp = 999 },
    { playerTrainerId = 1, playerName = "RED", rng = { ["0,255"] = { 255, 255, 0, 255 }, ["0,3"] = 1 } })
  local txt = use(st, ad, st.player, 33)
  check(has(txt, "ALPHA began to nap!") and ad:status(st.player) == "SLP", "traded mon over the cap naps")
  local st2, ad2 = battle({ moves = { 33 }, level = 60, otId = 1, otName = "RED" }, { hp = 999, maxHp = 999 },
    { playerTrainerId = 1, playerName = "RED", rng = { ["0,255"] = 255 } })
  local txt2 = use(st2, ad2, st2.player, 33)
  check(has(txt2, "ALPHA used"), "own mon always obeys")
  local st3, ad3 = battle({ moves = { 33 }, level = 60, otId = 999 }, { hp = 999, maxHp = 999 },
    { playerTrainerId = 1, playerName = "RED", badges = { true, true, true, true, true, true, true, true } })
  local txt3 = use(st3, ad3, st3.player, 33)
  check(has(txt3, "ALPHA used"), "Earth Badge makes traded mons obey")
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  print("[FAIL] game3 battle items + abilities")
  os.exit(1)
end
print("[ok] game3 battle items + abilities")
