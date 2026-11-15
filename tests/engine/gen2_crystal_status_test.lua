package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")

local function fixture(roll)
  local player = { species = "TEST", hp = 100, maxHp = 100, level = 50,
    stats = { hp = 100, attack = 100, defense = 100 }, types = { "NORMAL" },
    moves = { { id = "TACKLE", pp = 0 }, { id = "SKETCH", pp = 0 } } }
  local enemy = { species = "TEST", hp = 100, maxHp = 100, level = 50,
    stats = { hp = 100, attack = 100, defense = 100 }, types = { "NORMAL" } }
  local battle = setmetatable({ player = player, enemy = enemy, events = {},
    random = function() return roll or 0 end,
    data = { pokemon = { TEST = { types = { "NORMAL" } } },
      type_chart = { types = { NORMAL = { category = "physical" },
        ELECTRIC = { category = "special" }, FIRE = { category = "special" },
        FIGHTING = { category = "physical" } }, matchups = {},
        battleRules = require("tests.gen2_battle_rules_fixture")() },
      items = {
        CURE = { name = "CURE", heldEffect = "HELD_HEAL_PARALYZE", heldParameter = 0 },
        BERRY = { name = "BERRY", heldEffect = "HELD_BERRY", heldParameter = 10 },
        PP = { name = "MYSTERYBERRY", heldEffect = "HELD_RESTORE_PP", heldParameter = 0 },
        ROCK = { name = "KING'S ROCK", heldEffect = "HELD_FLINCH", heldParameter = 30 },
      }, moves = {
        TACKLE = { id = "TACKLE", name = "TACKLE", type = "NORMAL", power = 40,
          effect = "EFFECT_NORMAL_HIT", accuracyRaw = 255 },
        EXPLOSION = { type = "NORMAL", effect = "EFFECT_SELFDESTRUCT" },
        THUNDER = { id = "THUNDER", name = "THUNDER", power = 40,
          type = "ELECTRIC", accuracy = 100, accuracyRaw = 255,
          effect = "EFFECT_THUNDER", effectChanceRaw = 76 },
        THUNDER_WAVE = { id = "THUNDER_WAVE", name = "THUNDER WAVE", power = 0,
          type = "ELECTRIC", accuracy = 100, accuracyRaw = 255,
          effect = "EFFECT_PARALYZE" },
        HYPNOSIS = { id = "HYPNOSIS", name = "HYPNOSIS", power = 0, type = "NORMAL",
          accuracy = 100, accuracyRaw = 255, effect = "EFFECT_SLEEP" },
        GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
          accuracy = 100, accuracyRaw = 255, effect = "EFFECT_ATTACK_DOWN" },
        PSYBEAM = { id = "PSYBEAM", name = "PSYBEAM", power = 65, type = "NORMAL",
          accuracy = 100, accuracyRaw = 255, effect = "EFFECT_CONFUSE_HIT",
          effectChanceRaw = 255 },
        FLAME_WHEEL = { id = "FLAME_WHEEL", name = "FLAME WHEEL", power = 60,
          type = "FIRE", accuracy = 100, accuracyRaw = 255,
          effect = "EFFECT_FLAME_WHEEL", effectChanceRaw = 25 },
        EMBER = { id = "EMBER", name = "EMBER", power = 40, type = "FIRE",
          accuracy = 100, accuracyRaw = 255, effect = "EFFECT_BURN_HIT",
          effectChanceRaw = 25 },
        TRI_ATTACK = { id = "TRI_ATTACK", name = "TRI ATTACK", power = 80,
          type = "NORMAL", accuracy = 100, accuracyRaw = 255,
          effect = "EFFECT_TRI_ATTACK", effectChanceRaw = 51 },
        SEISMIC_TOSS = { id = "SEISMIC_TOSS", name = "SEISMIC TOSS", power = 1,
          type = "FIGHTING", accuracy = 100, accuracyRaw = 255,
          effect = "EFFECT_LEVEL_DAMAGE" },
        SNORE = { id = "SNORE", name = "SNORE", power = 40, type = "NORMAL",
          accuracy = 100, accuracyRaw = 255, effect = "EFFECT_SNORE",
          effectChanceRaw = 76 },
      } },
    stages = { player = Battle.newStages(), enemy = Battle.newStages() },
    screens = { player = {}, enemy = {} } }, Battle)
  battle.data.text = require("tests.fixture_data.gen2_rom_text_s7_a").text(
    require("tests.fixture_data.gen2_rom_text_s7_b").text(nil, "crystal"), "crystal")
  for _, label in ipairs({ "FrozenSolidText", "FullyParalyzedText", "MustRechargeText",
      "FlinchedText", "DisabledNoMoreText", "ConfusedNoMoreText", "IsConfusedText",
      "DisabledMoveText", "DefrostedOpponentText", "HurtItselfText", "InLoveWithText",
      "InfatuationText", "AlreadyAsleepText", "AlreadyPoisonedText",
      "AlreadyParalyzedText", "RecoveredUsingText", "BattleText_ItemHealedConfusion",
      "BattleText_UserRecoveredPPUsing", "BattleText_TargetRecoveredWithItem",
      "DidntAffect1Text", "DoesntAffectText", "ButItFailedText", "WasDefrostedText",
      "SandstormHitsText" }) do
    battle.data.text[label] = label
  end
  battle.battlerTypes = function(_, mon) return mon.types end
  battle.battlerName = function(_, mon) return mon == player and "PLAYER" or "ENEMY" end
  battle.battleStat = function(_, mon, stat) return mon.stats[stat] end
  battle.emit = function(self, event) self.events[#self.events + 1] = event end
  return battle, player, enemy
end

do
  local b, p = fixture(0)
  p.status = "freeze"
  p.volatile = { chargeMove = "FLY", vanished = true, rampCount = 3,
    rampMove = "FURY_CUTTER", rampageMove = "THRASH", rampageTurns = 2,
    rolloutLock = "ROLLOUT", bideTurns = 2 }
  T.eq(b:canAct(p, "FLY"), false, "a frozen turn never randomly thaws before acting")
  T.eq(p.status, "freeze", "freeze survives the action gate")
  T.eq(p.volatile.chargeMove, nil, "lost turn cancels charging")
  T.eq(p.volatile.vanished, nil, "lost turn clears Fly invisibility")
  T.eq(p.volatile.rampCount, nil, "lost turn clears Fury Cutter")
  T.eq(p.volatile.rampageMove, nil, "lost turn clears Thrash")
  T.eq(p.volatile.rolloutLock, nil, "lost turn clears Rollout")
end

do
  local b, p = fixture(0)
  p.status = "freeze"
  p.volatile = { justFrozen = true }
  b:tickDefrost(p)
  T.eq(p.status, "freeze", "new freeze cannot thaw on same turn")
  b:tickDefrost(p)
  T.eq(p.status, nil, "old freeze thaws at end of turn on byte zero")
end

do
  local b, p = fixture(25)
  p.status = "freeze"
  b:tickDefrost(p)
  T.eq(p.status, "freeze", "thaw threshold excludes byte 25")
  T.check(b:canAct(p, "FLAME_WHEEL"), "Flame Wheel can pass freeze action gate")
end

do
  local b, p = fixture(63)
  p.status = "paralyze"
  T.check(b:canAct(p, "TACKLE"), "paralysis threshold excludes byte 63")
  b.random = function() return 62 end
  T.eq(b:canAct(p, "TACKLE"), false, "paralysis threshold includes byte 62")
end

do
  local b, p = fixture(255)
  p.status = "sleep"
  p.statusTurns = 3
  p.volatile = { disabled = "TACKLE", disabledTurns = 2 }
  b:canAct(p, "TACKLE")
  T.eq(p.volatile.disabledTurns, 2, "sleep pauses Disable counter")
  p.status = nil
  b:canAct(p, "TACKLE")
  T.eq(p.volatile.disabledTurns, 1, "awake action decrements Disable")
  b:tickCounters(p)
  T.eq(p.volatile.disabledTurns, 1, "end of turn does not decrement Disable")
end

do
  local b, p = fixture(255)
  p.status, p.statusTurns = "sleep", 1
  p.volatile = { flinched = true, rampMove = "THRASH", rampCount = 3 }
  T.eq(b:canAct(p, "TACKLE"), false, "waking still checks flinch")
  T.eq(p.volatile.rampCount, nil, "waking cancels locked move state")
end

do
  local b, p, e = fixture(0)
  p.volatile = { substitute = 25 }
  T.eq(b:applyStatus(p, "paralyze", e), false, "Substitute refuses hostile status")
  T.eq(p.status, nil, "Substitute leaves major status clear")
  T.check(b:statDropBlocked(p), "Substitute refuses stat drop")
  p.volatile = { vanished = true, lockOn = true }
  T.check(b:statDropBlocked(p), "hidden target refuses stat drop despite Lock On")
end

do
  local b, p, e = fixture(0)
  p.item = "CURE"
  T.check(b:applyStatus(p, "paralyze", e), "status initially lands on berry holder")
  T.eq(p.status, nil, "status berry cures immediately")
  T.eq(p.item, nil, "status berry is consumed immediately")
  p.item, p.hp = "BERRY", 50
  b:tickHeldItem(p)
  T.eq(p.hp, 50, "HP berry does not heal at exactly half")
  T.eq(p.item, "BERRY", "HP berry remains at half")
  p.hp = 49
  b:tickHeldItem(p)
  T.eq(p.hp, 59, "HP berry heals strictly below half")
  p.item = "PP"
  b:tickMysteryBerry(p)
  T.eq(p.moves[1].pp, 5, "Mystery Berry restores first zero PP slot")
  T.eq(p.moves[2].pp, 0, "Mystery Berry leaves later zero PP slot alone")
  p.item, p.moves[1].pp = "PP", 1
  b:tickMysteryBerry(p)
  T.eq(p.moves[2].pp, 1, "Mystery Berry restores Sketch to one PP")
end

do
  local b, p = fixture(0)
  p.types = { "FIRE" }
  T.check(b:statusRefusedByType(p, "FIRE", "burn"), "Fire burn checks move type")
  T.eq(b:statusRefusedByType(p, "NORMAL", "burn"), false,
    "Normal Tri Attack can burn Fire type")
  p.types, b.weather = { "ICE" }, "sun"
  T.check(b:statusRefusedByType(p, "NORMAL", "freeze"), "sun blocks Tri Attack freeze")
end

do
  local b, p = fixture(0)
  p.status, p.volatile = "sleep", { recharge = true }
  T.eq(b:flinch(p), false, "move flinch refuses sleeping target")
  T.eq(p.volatile.recharge, true, "refused move flinch preserves recharge")
  b:flinch(p, true)
  T.eq(p.volatile.recharge, nil, "King Rock flinch clears recharge")
end

do
  local b, p = fixture(0)
  local plain = b:confusionSelfHit(p, "EXPLOSION")
  p.hp, b.screens.player.reflect = 100, 5
  local reflected = b:confusionSelfHit(p, "EXPLOSION")
  T.check(reflected < plain, "own Reflect reduces confusion damage")
  p.hp, b.screens.player.reflect = 100, nil
  T.check(plain > b:confusionSelfHit(p), "Explosion retains confusion defense-halving bug")
end

do
  local b, p = fixture(0)
  local calls = {}
  local function record(label)
    return function() calls[#calls + 1] = label end
  end
  b.tickFutureSight = function(_, mon)
    calls[#calls + 1] = "future"
    if mon == p then p.hp = 0 end
  end
  b.tickWeather, b.tickWrap = record("weather"), record("wrap")
  b.tickHeldItem, b.tickScreens = record("item"), record("screen")
  b.tickPerish, b.tickMysteryBerry = function() end, function() end
  b.tickDefrost, b.tickCounters = function() end, function() end
  b.resolveFaints = record("faint")
  b:betweenTurnEffects()
  T.same(calls, { "future", "future", "faint", "weather", "faint", "wrap", "wrap",
    "faint", "faint", "item", "item", "screen", "item", "item" },
    "a faint that does not end the battle lets the end-of-turn phase continue")
  calls = {}
  p.hp = 100
  b.resolveFaints = function() calls[#calls + 1] = "faint" b.over = true end
  b:betweenTurnEffects()
  T.same(calls, { "future", "future", "faint" },
    "a faint that ends the battle stops the end-of-turn phase")
end

do
  local b, p, e = fixture(0)
  e.item = "CURE"
  b:useMove(p, e, "THUNDER")
  T.eq(e.status, nil, "Thunder status berry cures during move resolution")
  T.eq(e.item, nil, "Thunder consumes status berry before end of turn")
  e.volatile, e.hp = { substitute = 1 }, 100
  b:useMove(p, e, "THUNDER")
  T.eq(e.volatile.substitute, nil, "Thunder can break Substitute")
  T.eq(e.status, nil, "Thunder does not paralyze through broken Substitute")
  b.screens.enemy.safeguard, b.events = 5, {}
  e.volatile = {}
  b:useMove(p, e, "THUNDER")
  T.eq(e.status, nil, "Safeguard blocks damaging move secondary")
  local loud = false
  for _, event in ipairs(b.events) do
    if event.text and event.text:find("protected by SAFEGUARD", 1, true) then loud = true end
  end
  T.eq(loud, false, "secondary Safeguard block is silent")
  e.volatile = { substitute = 25 }
  b:useMove(p, e, "THUNDER_WAVE")
  T.eq(e.status, nil, "Thunder Wave dispatch respects Substitute")
end

local function said(b, label)
  for _, event in ipairs(b.events) do
    if event.text and tostring(event.text):find(label, 1, true) then return true end
  end
  return false
end

do
  local b, p, e = fixture(0)
  e.status = "paralyze"
  b:useMove(p, e, "PSYBEAM")
  T.check(e.volatile and e.volatile.confuseCount, "Psybeam confuses a paralyzed target")
end

do
  local b, p, e = fixture(0)
  b.inBattleTowerBattle = true
  b:useMove(e, p, "THUNDER_WAVE")
  T.eq(p.status, "paralyze", "Battle Tower AI status move skips the 25% fail roll")
  b.inBattleTowerBattle, p.status, b.events = nil, nil, {}
  b:useMove(e, p, "THUNDER_WAVE")
  T.eq(p.status, nil, "AI status move fails on a low roll outside the Tower")
  T.check(said(b, "DidntAffect1Text"), "AI status fail prints DidntAffect1Text")
end

do
  local b, p, e = fixture(0)
  local draws = 0
  b.random = function() draws = draws + 1 return 0 end
  p.status = "sleep"
  b:useMove(e, p, "HYPNOSIS")
  T.check(said(b, "AlreadyAsleepText"), "already asleep wins over the AI fail roll")
  T.eq(draws, 0, "already asleep draws no random byte")
end

do
  local b, p, e = fixture(0)
  e.volatile = { substitute = 25 }
  b:useMove(p, e, "THUNDER_WAVE")
  T.check(said(b, "DidntAffect1Text"), "status move into Substitute prints DidntAffect1Text")
  b.events = {}
  b:useMove(p, e, "GROWL")
  T.check(said(b, "ButItFailedText"), "Growl into Substitute prints ButItFailedText")
  e.volatile, b.events = { chargeMove = "FLY", vanished = true, lockOn = true }, {}
  b:useMove(p, e, "GROWL")
  T.eq(b.stages.enemy.attack, 0, "Lock-On Growl on a flying target lowers nothing")
  T.check(said(b, "ButItFailedText"), "Lock-On Growl on a flying target prints ButItFailedText")
end

do
  local b, p, e = fixture(0)
  p.status = "freeze"
  b.accuracyRoll = function() return false end
  b:useMove(p, e, "FLAME_WHEEL")
  T.eq(p.status, "freeze", "missed Flame Wheel leaves the user frozen")
  b.accuracyRoll = nil
  b:useMove(p, e, "FLAME_WHEEL")
  T.eq(p.status, nil, "Flame Wheel that hits thaws the user")
  T.check(said(b, "WasDefrostedText"), "Flame Wheel thaw prints WasDefrostedText")
end

do
  local b, p, e = fixture(0)
  e.volatile = { rampageMove = "THRASH", rampageTurns = 2, chargeMove = "SOLARBEAM" }
  b:useMove(p, e, "HYPNOSIS")
  T.eq(e.status, "sleep", "Hypnosis lands")
  T.eq(e.volatile.rampageMove, nil, "sleep landing cancels Thrash")
  T.eq(e.volatile.chargeMove, nil, "sleep landing cancels a charging move")
end

do
  local b, p, e = fixture(0)
  p.item = "ROCK"
  b:useMove(p, e, "SEISMIC_TOSS")
  T.check(e.volatile and e.volatile.flinched, "King's Rock flinches on Seismic Toss")
end

do
  local b, p, e = fixture(16)
  e.volatile = { substitute = 1 }
  b:useMove(p, e, "TRI_ATTACK")
  T.eq(e.volatile.substitute, nil, "Tri Attack breaks the Substitute")
  T.eq(e.status, "paralyze", "Tri Attack can inflict status through the Substitute it broke")
  e.status, e.hp, e.volatile = "freeze", 100, { substitute = 1 }
  b:useMove(p, e, "EMBER")
  T.eq(e.status, nil, "Ember that breaks a Substitute thaws the target")
  e.status, e.hp, e.volatile, b.events = "freeze", 1, {}, {}
  b:useMove(p, e, "EMBER")
  T.eq(e.hp, 0, "Ember KOs the frozen target")
  T.eq(said(b, "DefrostedOpponentText"), false, "Ember KO prints no defrost line")
end

do
  local b, p, e = fixture(16)
  p.status, p.statusTurns = "sleep", 3
  b:useMove(p, e, "SNORE")
  T.check(e.volatile and e.volatile.flinched, "Snore flinches from its move script")
end

do
  local b, p = fixture(0)
  b.weather, b.weatherTurns = "sandstorm", 3
  b:tickWeather()
  T.check(said(b, "SandstormHitsText"), "sandstorm damage prints SandstormHitsText")
  T.check(p.hp < 100, "sandstorm damages a Normal type")
end

T.finish("gen2 crystal status rules")
