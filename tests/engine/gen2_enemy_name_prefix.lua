-- ../pokecrystal/home/text.asm:322-345 PlaceBattlersName: <USER> / <TARGET>
-- print "Enemy " ahead of wEnemyMonNickname on the foe's side, in wild,
-- trainer and link battles alike.  Lines that read the nickname RAM directly
-- (data/text/battle.asm:10-55, :162-167, :208-212, :240-246) print it bare.
--
--   luajit tests/engine/gen2_enemy_name_prefix.lua
--
-- ROM-free.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Mon = require("src.battle.gen2.Mon")
local RomText = require("src.core.RomText")
local TextBox = require("src.render.TextBox")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GHOST = { id = "GHOST", index = 8, category = "physical" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
  DARK = { id = "DARK", index = 27, category = "special" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
  CONFUSE_RAY = { id = "CONFUSE_RAY", name = "CONFUSE RAY", power = 0,
    type = "GHOST", accuracy = 100, accuracyRaw = 255, pp = 10, effect = "EFFECT_CONFUSE" },
  EMBER = { id = "EMBER", name = "EMBER", power = 40, type = "FIRE",
    accuracy = 100, accuracyRaw = 255, pp = 25, effect = "EFFECT_BURN_HIT", effectChance = 100, effectChanceRaw = 255 },
  WRAP = { id = "WRAP", name = "WRAP", power = 15, type = "NORMAL",
    accuracy = 85, accuracyRaw = 216, pp = 20, effect = "EFFECT_TRAP_TARGET" },
  THIEF = { id = "THIEF", name = "THIEF", power = 40, type = "DARK",
    accuracy = 100, accuracyRaw = 255, pp = 10, effect = "EFFECT_THIEF", effectChance = 100, effectChanceRaw = 255 },
  STRUGGLE = { id = "STRUGGLE", name = "STRUGGLE", power = 50, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 1, effect = "EFFECT_RECOIL_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local function species(id, index)
  return {
    id = id, index = index, name = id,
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  }
end

local DATA = {
  pokemon = {
    growthRates = GROWTH,
    MACHOP = species("MACHOP", 66),
    PIDGEY = species("PIDGEY", 16),
    GEODUDE = species("GEODUDE", 74),
  },
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = {
    METAL_COAT = { id = "METAL_COAT", name = "METAL COAT", pocket = "ITEM" },
    BERRY = { id = "BERRY", name = "BERRY", pocket = "ITEM",
      heldEffect = "HELD_BERRY", heldParameter = 10 },
  },
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function zero() return 0 end

local function mon(id, level, moves)
  local m = Mon.new(DATA, id, level, { dvs = perfect })
  m.moves = {}
  for i, move in ipairs(moves or { "TACKLE" }) do
    m.moves[i] = { id = move, pp = 30, maxPp = 30 }
  end
  return m
end

local function texts(events)
  local out = {}
  for _, e in ipairs(events or {}) do
    if type(e.text) == "string" then out[#out + 1] = e.text end
  end
  return out
end

local function line(label, fills)
  return TextBox.strip(RomText(DATA, label, nil, fills))
end

local function has(events, text)
  for _, t in ipairs(texts(events)) do if t == text then return true end end
  return false
end

local function lacks(events, pattern)
  for _, t in ipairs(texts(events)) do
    if t:find(pattern, 1, true) then return false, t end
  end
  return true
end

local function wildBattle(playerMoves, wildMoves, wildId)
  local player = mon("MACHOP", 15, playerMoves)
  local wild = mon(wildId or "PIDGEY", 15, wildMoves)
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = zero })
  return battle, player, wild
end

local function trainerBattle(playerMoves, foeMoves)
  local player = mon("MACHOP", 15, playerMoves)
  local foe = mon("GEODUDE", 15, foeMoves)
  local battle = Battle.new({ data = DATA, party = { player },
    trainer = { class = "YOUNGSTER", name = "JOEY", party = { foe } },
    random = zero })
  return battle, player, foe
end

-- ---- the helper itself ----------------------------------------------------
do
  local battle, player, wild = wildBattle()
  T.eq(battle:battlerName(wild), "Enemy PIDGEY", "foe side: Enemy + nickname")
  T.eq(battle:battlerName(player), "MACHOP", "player side: bare nickname")
  T.eq(battle:monName(wild), "PIDGEY", "monName stays raw")
  local benched = mon("MACHOP", 5)
  T.eq(battle:battlerName(benched), "MACHOP",
    "a mon that is not the foe's active never gets the prefix")
end

-- ---- _ActorNameText + _UsedMove1Text (data/text/common_2.asm:738-746) ----
do
  local battle, player, wild = wildBattle()
  battle:useMove(player, wild, "TACKLE")
  T.check(has(battle:takeEvents(), "MACHOP\nused TACKLE!"), "wild: player's move line is bare")
  battle:useMove(wild, player, "TACKLE")
  T.check(has(battle:takeEvents(), "Enemy PIDGEY\nused TACKLE!"), "wild: foe's move line is prefixed")

  local tb, tp, foe = trainerBattle()
  tb:useMove(foe, tp, "TACKLE")
  T.check(has(tb:takeEvents(), "Enemy GEODUDE\nused TACKLE!"), "trainer: foe's move line is prefixed")

  local lb, lp, link = trainerBattle()
  lb.linkBattle = true
  lb:useMove(link, lp, "TACKLE")
  T.check(has(lb:takeEvents(), "Enemy GEODUDE\nused TACKLE!"),
    "link: PlaceBattlersName has no wLinkMode check")
end

-- ---- stat changes: Text_BattleFoeEffectActivate (common_2.asm:688) --------
do
  local battle, player, wild = wildBattle({ "GROWL" }, { "GROWL" })
  battle:useMove(player, wild, "GROWL")
  T.check(has(battle:takeEvents(), "Enemy PIDGEY's\nATTACK fell!"), "foe's stat line")
  battle.random = function(n) return 200 % math.max(1, n or 256) end
  battle:useMove(wild, player, "GROWL")
  T.check(has(battle:takeEvents(), "MACHOP's\nATTACK fell!"), "player's stat line")
  battle.random = zero
  for _ = 1, 6 do battle:useMove(player, wild, "GROWL") end
  T.check(has(battle:takeEvents(), line("WontDropAnymoreText",
    { TARGET = "Enemy PIDGEY", STRBUF = DATA.text["StatNames#1"] })),
    "WontDropAnymoreText (battle.asm:740)")
end

-- ---- status: BecameConfusedText / WasBurnedText / HurtByBurnText ---------
do
  local battle, player, wild = wildBattle({ "CONFUSE_RAY", "EMBER" }, { "EMBER" })
  battle:useMove(player, wild, "CONFUSE_RAY")
  T.check(has(battle:takeEvents(), line("BecameConfusedText", { TARGET = "Enemy PIDGEY" })),
    "BecameConfusedText (battle.asm:413)")
  battle:useMove(player, wild, "EMBER")
  T.check(has(battle:takeEvents(), line("WasBurnedText", { TARGET = "Enemy PIDGEY" })),
    "WasBurnedText (battle.asm:717)")
  battle:tickStatus(wild)
  T.check(has(battle:takeEvents(), line("HurtByBurnText", { USER = "Enemy PIDGEY" })),
    "HurtByBurnText (battle.asm:62)")
  battle:useMove(wild, player, "EMBER")
  battle:takeEvents()
  battle:tickStatus(player)
  T.check(has(battle:takeEvents(), line("HurtByBurnText", { USER = "MACHOP" })),
    "player's residual line is bare")
  T.eq(battle:canAct(wild, "TACKLE") ~= nil, true, "canAct runs")
  T.check(has(battle:takeEvents(), "Enemy PIDGEY\nis confused!"), "IsConfusedText (battle.asm:398)")
end

-- ---- partial trap: WrappedByText / UsersHurtByStringBuffer1 --------------
do
  local battle, player, wild = wildBattle({ "WRAP" })
  battle:useMove(player, wild, "WRAP")
  T.check(has(battle:takeEvents(), line("WrappedByText",
    { TARGET = "Enemy PIDGEY", USER = "MACHOP" })),
    "WrappedByText: <TARGET> prefixed, <USER> bare (battle.asm:463)")
  battle:tickWrap(wild)
  T.check(has(battle:takeEvents(), line("BattleText_UsersHurtByStringBuffer1",
    { USER = "Enemy PIDGEY", STRBUF = "WRAP" })), "BattleText_UsersHurtByStringBuffer1")
end

-- ---- held berry: RecoveredUsingText (battle.asm:289) ---------------------
do
  local battle, _, wild = wildBattle()
  wild.item = "BERRY"
  wild.hp = 1
  battle:tickHeldItem(wild)
  local evs = battle:takeEvents()
  local ok = false
  for _, t in ipairs(texts(evs)) do
    if t:find("^Enemy PIDGEY%s") then ok = true end
  end
  T.check(ok, "the foe's berry line carries the prefix")
end

-- ---- Thief: StoleText (battle.asm:946) ------------------------------------
do
  local battle, player, wild = wildBattle({ "THIEF" }, { "THIEF" })
  wild.item = "METAL_COAT"
  battle:useMove(player, wild, "THIEF")
  T.check(has(battle:takeEvents(), "MACHOP\nstole METAL COAT\vfrom its foe!"), "player steals: bare")
  player.item = "METAL_COAT"
  wild.item = nil
  battle:useMove(wild, player, "THIEF")
  T.check(has(battle:takeEvents(), "Enemy PIDGEY\nstole METAL COAT\vfrom its foe!"), "foe steals: prefixed")
end

-- ---- faint: BattleText_EnemyMonFainted spells "Enemy @" itself -----------
do
  local battle, player, wild = wildBattle()
  wild.hp = 0
  battle:announceEnemyFaint()
  T.check(has(battle:takeEvents(), line("BattleText_EnemyMonFainted", { STRBUF = "PIDGEY" })),
    "wild foe: Enemy X fainted! (battle.asm:162)")
  local tb, _, foe = trainerBattle()
  foe.hp = 0
  tb:announceEnemyFaint()
  T.check(has(tb:takeEvents(), line("BattleText_EnemyMonFainted", { STRBUF = "GEODUDE" })),
    "trainer foe: the same line")
  player.hp = 0
  battle:announcePlayerFaint()
  T.check(has(battle:takeEvents(), line("BattleText_MonFainted", { STRBUF = "MACHOP" })),
    "BattleText_MonFainted is bare (battle.asm:208)")
end

-- ---- raw-nickname lines stay bare ----------------------------------------
do
  T.eq(BattleState.battleStartText(DATA, "PIDGEY", nil), "Wild PIDGEY\nappeared!",
    "WildPokemonAppearedText (battle.asm:10)")
  T.eq(line("BattleText_EnemySentOut", { ENEMY = "JOEY", STRBUF = "GEODUDE" }),
    "JOEY\nsent out\vGEODUDE!",
    "BattleText_EnemySentOut (battle.asm:240)")
  local battle = wildBattle()
  battle:enemyFled()
  local evs = battle:takeEvents()
  T.check(has(evs, line("BattleText_WildFled", { STRBUF = "PIDGEY" })),
    "BattleText_WildFled (battle.asm:43)")
  T.check(lacks(evs, "Enemy "), "and no Enemy anywhere in the fled turn")

  local tb = trainerBattle()
  tb.enemyParty[2] = mon("PIDGEY", 15)
  tb:switchEnemy(2)
  local sw = tb:takeEvents()
  T.check(has(sw, line("EnemyWithdrewText", { ENEMY = "JOEY", STRBUF = "GEODUDE" })),
    "the withdraw line names the mon bare")
  T.check(lacks(sw, "Enemy "), "and the send-out does too")
end

-- ---- mod payloads keep the raw name -------------------------------------
do
  local battle, _, wild = wildBattle()
  battle:useMove(wild, battle.player, "TACKLE")
  for _, e in ipairs(battle:takeEvents()) do
    if e.kind == "move" then
      T.eq(e.side, "enemy", "the move event carries the side")
      T.eq(e.mon, nil, "and no name field to drift")
    end
  end
  T.eq(wild.name, "PIDGEY", "the record itself is untouched")
end

-- ---- the cross-gen facade renders the peer as Enemy ----------------------
do
  local okF, F = pcall(require, "tests.engine._g3u_fixture")
  local okL, L = pcall(require, "tests.support.g3u_loopback")
  local okG, Gen2Facade = pcall(require, "src.ui.g3u.Gen2Facade")
  local okTbl, Table = pcall(require, "src.battle.g3u.Table")
  local okBS, BattleSession = pcall(require, "src.online.union.BattleSession")
  if okF and okL and okG and okTbl and okBS then
    local pokemon, moves = {}, {}
    for n = 1, 251 do
      pokemon[("MON%03d"):format(n)] = { dex = n, name = ("MON%03d"):format(n), types = { "NORMAL" } }
    end
    for id = 1, 251 do
      moves[("MOVE%03d"):format(id)] = { index = id, name = ("MOVE%03d"):format(id) }
    end
    pokemon.growthRates = {}
    local game = { data = { pokemon = pokemon, moves = moves,
      text = require("tests.fixture_data.gen2_rom_text_s7_b").text() },
      save = { player = { name = "GOLD" } } }
    local t2 = assert(Table.build(F.gen2(), 2))
    local netA, netB = L.pair()
    local go = { seed = 11, size = 6 }
    local gens = { [0] = 2, [1] = 3 }
    local names = { [0] = "GOLD", [1] = "MAY" }
    local mine = { F.record(t2, 25, { 33 }, 50, { nickname = "SPARKY" }) }
    local foe = { F.record(t2, 4, { 33 }) }
    local me = BattleSession.new({ net = netA, seat = 0, go = go, gens = gens,
      data = F.gen2(), records = mine, names = names })
    local bot = BattleSession.new({ net = netB, seat = 1, go = go, gens = gens,
      records = foe, names = names })
    local facade = Gen2Facade.new(game, me, { names = { me = "GOLD", foe = "MAY" } })
    for _ = 1, 4 do
      me:update()
      bot:update()
      facade:translate(me:events())
    end
    T.check(facade.ready, "facade ready")
    T.eq(facade:N({ side = 0, index = 1 }), "SPARKY", "facade: my mon is bare")
    T.eq(facade:N({ side = 1, index = 1 }), "Enemy MON004", "facade: the peer's mon is Enemy")
    T.eq(facade:nameOf(facade.enemy), "MON004", "facade: nameOf stays raw")
    local msg = Gen2Facade.MSG.STRINGID_PKMNFLINCHED(facade, { atk = { side = 1, index = 1 } })
    T.eq(msg, "Enemy MON004\nflinched!", "facade: <USER> text on the peer")
  else
    print("[skip] g3u fixtures unavailable")
  end
end

T.finish("gen2 enemy name prefix")
