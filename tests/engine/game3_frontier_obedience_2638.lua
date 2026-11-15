package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
require("tests.game3_cache").mountOrSkip("game3_frontier_obedience_2638", "emerald", "pokemon/battle_moves.lua")
require("tests.fixture_data.game3_items").install()

local Battle = require("src.core.game3.battle.init")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local BattleProfile = require("src.core.game3.battle.profile")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local T = require("tests.harness")

local function mon(species, otId, fateful)
  return { species = species, level = 30, hp = 200, maxHp = 200,
    attack = 80, defense = 80, spAtk = 80, spDef = 80, speed = 80, ability = 0,
    nickname = "RENTAL", otId = otId, otName = otId == 1 and "PLAYER" or "RENTAL",
    modernFatefulEncounter = fateful, moves = { 33, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }
end

local function run(o)
  GameVersion.set(o.version or "emerald")
  local user, foe = mon(o.species or 1, o.own and 1 or 2, o.fateful), mon(1, 3)
  user.otSecretId, user.level = o.monSid or 0, o.level or 30
  user.otName = o.monName or user.otName
  local session = { version = o.version or "emerald", name = "PLAYER", trainerId = 1,
    secretId = o.playerSid or 0, party = { user } }
  if o.legacy then user.otSecretId, session.secretId = nil, nil end
  if o.sync then
    user.personality = 12345
    local Sync = require("src.core.TrainerIdSync")
    local owners = {}
    Sync.addOwner(owners, { id = 1, sid = 7, name = "MAY" }, 3)
    T.check(Sync.rewriteSave(session, 3, { id = 1, sid = 42, name = "PLAYER" }, owners),
      o.label .. " syncs original OT identity")
  end
  Space.store = Flags.newStore()
  Battle.start({ headless = false, autoFight = false, session = session, playerParty = session.party,
    foe = { species = 1, level = 30, mon = foe }, wild = o.wild == true, frontier = o.frontier,
    rng = function(lo, hi) if lo == 1 and hi == 100 then return 1 end return hi end })
  local st = assert(Battle.getState())
  st.badges, st.playerTrainerId, st.playerOtName = {}, 1, "PLAYER"
  st.link = o.link == true
  if o.badge then
    st.badges = nil
    Space.store = Flags.newStore()
    Flags.setFlag(Space.store, nil, BattleProfile.of(st).badgeFlags[o.badge], true)
    T.check(Engine.hasBadge(st, o.badge), o.label .. " canonical Emerald badge flag is read")
  end
  T.eq(st.kinds.frontier == true, o.frontier == true, o.label .. " Battle.start propagates Frontier kind")
  T.check(o.own or Engine.isTradedMon(st, st.player.mon), o.label .. " foreign rental OT is preserved")
  local hp, pp = st.enemy.mon.hp, st.player.mon.pp[1]
  local out = {}
  Engine.resolveMove(st.player, st.enemy, 33, 1, Adapter.new(st), st, out)
  T.eq(out._anim.cancelled ~= true, o.obey, o.label .. " real move caller follows obedience gate")
  T.eq(st.enemy.mon.hp < hp, o.obey, o.label .. " selected move damages foe only when obedient")
  T.eq(st.player.mon.pp[1] < pp, o.obey, o.label .. " selected move consumes PP only when obedient")
  Battle.reset()
end

-- pokeemerald/src/battle_util.c:3909
run({ frontier = true, obey = true, label = "Emerald Frontier rental" })
run({ obey = false, label = "Emerald ordinary traded trainer" })
run({ wild = true, obey = false, label = "Emerald ordinary traded wild" })
run({ frontier = true, species = 151, fateful = false, own = true, obey = false, label = "Illegal Mew Frontier" })
run({ frontier = true, species = 410, fateful = false, own = true, obey = false, label = "Illegal Deoxys Frontier" })
run({ frontier = true, species = 151, fateful = true, obey = true, label = "Legal Mew Frontier" })
run({ frontier = true, species = 410, fateful = true, obey = true, label = "Legal Deoxys Frontier" })
run({ version = "firered", frontier = true, obey = false, label = "FireRed Frontier flag control" })
run({ version = "leafgreen", frontier = true, obey = false, label = "LeafGreen Frontier flag control" })
run({ own = true, obey = true, label = "Emerald own OT" })
run({ link = true, obey = true, label = "Emerald link" })
run({ badge = 2, obey = true, label = "Emerald badge two level 30" })
run({ badge = 8, obey = true, label = "Emerald badge eight" })
run({ own = true, level = 100, playerSid = 42, monSid = 42, obey = true,
  label = "Level 100 full own identity with no badges" })
run({ own = true, level = 100, playerSid = 42, monSid = 7, obey = false,
  label = "Level 100 same TID and name but foreign SID" })
run({ own = true, level = 100, playerSid = 42, monSid = 7, monName = "MAY", sync = true, obey = true,
  label = "Level 100 synced name TID SID with no badges" })
run({ own = true, level = 100, legacy = true, wild = true, obey = true,
  label = "Level 100 own mon on a save with no secret id in a wild battle" })
T.finish("game3_frontier_obedience_2638")
