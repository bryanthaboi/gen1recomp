-- ../pokecrystal/engine/battle/effect_commands.asm:2644-2654
-- ../pokecrystal/data/items/attributes.asm:149-150
-- ../pokegold/data/items/attributes.asm:149-150
package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Fingerprint = require("src.link.Fingerprint")
local Handshake = require("src.link.Handshake")
local Wire = require("src.link.Wire")
local GameVersion = require("src.core.GameVersion")
local Battle = require("src.battle.gen2.Battle")
local Damage = require("src.battle.gen2.Damage")
local Mon = require("src.battle.gen2.Mon")

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

local function tmhmList(n)
  local out = {}
  for i = 1, n do out[i] = "MOVE_" .. i end
  return out
end

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FIGHTING = { id = "FIGHTING", index = 1, category = "physical" },
}

local function goldData()
  return {
    pokemon = {
      growthRates = {
        GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
          linear = 0, constant = 0 },
      },
      tmhmMoves = tmhmList(57),
      MACHOP = {
        id = "MACHOP", index = 66, name = "MACHOP",
        baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
          specialAttack = 35, specialDefense = 35 },
        types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
        growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
        levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
      },
    },
    moves = {
      TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
        accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
    },
    type_chart = { generation = 2, types = deepCopy(TYPES), matchups = {} },
    gen2HeldItems = {
      ITEM_46 = { heldEffect = "HELD_NONE", heldParameter = 0 },
      ITEM_73 = { heldEffect = "HELD_NONE", heldParameter = 0 },
      LEFTOVERS = { heldEffect = "HELD_LEFTOVERS", heldParameter = 10 },
    },
  }
end

local function crystalData()
  local data = goldData()
  data.pokemon.tmhmMoves = tmhmList(60)
  data.pokemon.tutorMoves = { "FLAMETHROWER", "THUNDERBOLT", "ICE_BEAM" }
  data.gen2HeldItems.ITEM_46 = nil
  data.gen2HeldItems.ITEM_73 = nil
  data.gen2HeldItems.CLEAR_BELL = { heldEffect = "HELD_NONE", heldParameter = 0 }
  data.gen2HeldItems.GS_BALL = { heldEffect = "HELD_NONE", heldParameter = 0 }
  return data
end

do
  local gold, crystal = goldData(), crystalData()
  local g = Fingerprint.compute(gold, {}, 2)
  local c = Fingerprint.compute(crystal, {}, 2)
  T.eq(c, g, "Crystal's tutor list and renamed HELD_NONE slots do not split the digest")

  local helloG = Handshake.hello({ data = gold })
  local helloC = Handshake.hello({ data = crystal })
  T.eq(helloG.generation, 2, "the gold hello is gen 2")
  T.eq((Handshake.checkCompat(helloG, helloC)), "full",
    "a Gold hello meeting a Crystal hello pairs as full")
  T.eq((Handshake.checkCompat(helloC, helloG)), "full", "and in reverse")
end

do
  local crystal = crystalData()
  local base = Fingerprint.compute(crystal, {}, 2)
  local armed = crystalData()
  armed.gen2HeldItems.CLEAR_BELL = { heldEffect = "HELD_LEFTOVERS",
    heldParameter = 10 }
  T.check(Fingerprint.compute(armed, {}, 2) ~= base,
    "a HELD_NONE slot given a real effect moves the digest")
  local tuned = crystalData()
  tuned.gen2HeldItems.LEFTOVERS.heldParameter = 20
  T.check(Fingerprint.compute(tuned, {}, 2) ~= base,
    "a real held item's parameter still moves the digest")
  local species = crystalData()
  species.pokemon.MACHOP.baseStats.attack = 81
  T.check(Fingerprint.compute(species, {}, 2) ~= base,
    "a species edit still moves the digest")
end

do
  local gold, crystal = goldData(), crystalData()
  local cmons = Fingerprint.records(crystal, "pokemon", 2)
  T.eq(cmons.tutorMoves, nil, "tutorMoves is not a species record")
  T.eq(cmons.tmhmMoves, nil, "tmhmMoves is not a species record")
  T.eq(cmons.growthRates, nil, "growthRates is not a species record")
  T.check(cmons.MACHOP ~= nil, "a real species keeps its record")
  local gheld = Fingerprint.records(gold, "held_items", 2)
  T.check(gheld.ITEM_46 ~= nil,
    "the per-record held map keeps HELD_NONE ids for party eligibility")
  local cheld = Fingerprint.records(crystal, "held_items", 2)
  T.eq(cheld.ITEM_46, nil, "Crystal has no ITEM_46 record")
end

do
  local detail = "dataset fingerprint differs: the room has 6f577c0127a1e94d, "
    .. "you have c444a8971640c763"
  local out = Wire.sanitize({ type = "join_error", reason = "profile_mismatch",
    field = "fingerprint", detail = detail })
  T.eq(out.detail, detail, "the relay's mismatch detail survives the wire whole")
  local long = string.rep("x", 120)
  out = Wire.sanitize({ type = "join_error", reason = "x", detail = long })
  T.eq(out.detail, long, "a 120-byte detail survives")
end

do
  local data = goldData()
  data.items = {}
  local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
  perfect.hp = Mon.hpDV(perfect)
  local function highRoll(n) return 99 % math.max(1, n or 1) end

  local seen
  local realCalc = Damage.calc
  Damage.calc = function(opts)
    seen = opts
    return realCalc(opts)
  end

  local function reflectHit(version, link)
    GameVersion.set(version)
    local player = Mon.new(data, "MACHOP", 15, { dvs = perfect })
    player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local wild = Mon.new(data, "MACHOP", 15, { dvs = perfect })
    wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local battle = Battle.new({ data = data, party = { player }, wild = wild,
      random = highRoll })
    player.stats.attack = 200
    wild.stats.defense = 512
    wild.maxHp, wild.hp = 999, 999
    battle.linkBattle = link or nil
    battle.screens.enemy.reflect = 5
    seen = nil
    battle:useMove(player, wild, "TACKLE")
    battle:takeEvents()
    return 999 - wild.hp, seen and seen.reflectOverflowFixed
  end

  local restore = GameVersion.get()
  local gold = reflectHit("gold", false)
  local crystalSolo, soloFlag = reflectHit("crystal", false)
  local crystalLink, linkFlag = reflectHit("crystal", true)
  local goldLink = reflectHit("gold", true)
  GameVersion.set(restore)
  Damage.calc = realCalc

  T.check(gold > 0, "the Reflect hit lands")
  T.eq(soloFlag, nil, "a single-player battle leaves the version's fix in charge")
  T.check(crystalSolo < gold, "single-player Crystal keeps its Reflect fix")
  T.eq(linkFlag, false, "a link battle forces the single truncation pass")
  T.eq(crystalLink, gold, "a Crystal link battle computes Gold's Reflect damage")
  T.eq(goldLink, gold, "and Gold's link battle is unchanged")
end

T.finish("gen2 link cross version bug 2382")
