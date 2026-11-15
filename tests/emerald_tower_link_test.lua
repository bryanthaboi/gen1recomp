package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function has(rel)
  local src = cache and cache.read and cache:read(rel)
  return type(src) == "string"
end
if not (has("data/generated/gba/frontier/trainers.lua") and has("data/generated/gba/rse/frontier/manifest.lua")) then
  print("emerald_tower_link_test: skipped (no Emerald cache with rse/frontier; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Runtime = require("src.core.game3.runtime")
local Rng = require("src.core.game3.rng")
local Json = require("src.link.Json")

local store = { flags = {}, vars = {} }
local Space = require("src.core.game3.scripting.space")
Space.store = store

local function newSess(name, tid)
  return { version = "emerald", name = name, trainerId = tid, secretId = 1, money = 0, party = {}, gender = 0,
    bag = {}, flags = store.flags, vars = store.vars }
end
local sessions = { [0] = newSess("BRENDAN", 111), [1] = newSess("MAY", 222) }
local current = sessions[0]
Runtime.getSession = function() return current end

local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")
local Rse = require("src.core.game3.rse.init")
local TowerLink = require("src.core.game3.link.tower_link")
local LB = require("src.core.game3.link.battle")

local Wire = require("src.link.Wire")
local function wire(msg)
  if Wire.SCHEMAS[msg.type] then return Wire.sanitize(msg) end
  local out = Wire.plain(msg)
  out.type = msg.type
  return out
end

local function hub(n)
  local inbox, links = {}, {}
  for i = 0, n - 1 do inbox[i] = {} end
  for i = 0, n - 1 do
    local lk = { seat = i, open = true, bytes = 0 }
    function lk:getSeat() return self.seat end
    function lk:isOpen() return self.open end
    function lk:send(msg)
      local text = Json.encode(msg)
      if #text > self.bytes then self.bytes = #text end
      for j = 0, n - 1 do
        if j ~= i then table.insert(inbox[j], wire(Json.decode(text))) end
      end
      return true
    end
    function lk:take(kind, pred)
      local q = inbox[i]
      for k = 1, #q do
        if q[k].type == kind and (pred == nil or pred(q[k])) then return table.remove(q, k) end
      end
      return nil
    end
    links[i] = lk
  end
  return links
end

Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.TOWER, current)
Rse.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.LINK_MULTIS, current)
for i = 0, 1 do
  Util.newGame(sessions[i])
  local f = Util.frontier(sessions[i])
  f.lvlMode = D.LVL.L50
  f.curChallengeBattleNum = 0
end
Util.set2(Util.frontier(sessions[0]).towerWinStreaks, D.MODE.LINK_MULTIS, D.LVL.L50, 7)
Util.set2(Util.frontier(sessions[1]).towerWinStreaks, D.MODE.LINK_MULTIS, D.LVL.L50, 21)

print("[test] LoadLinkMultiOpponentsData over the link (pokeemerald/src/battle_tower.c:2570)")
do
  local ids = TowerLink.generateTrainerIds(2, function(c, b) return c * 100 + b * 10 + (Rng.Random() % 3) end)
  eq(#ids, 14, "14 trainer ids for seven double stages")
  local seen, dup = {}, false
  for _, v in ipairs(ids) do
    if seen[v] then dup = true end
    seen[v] = true
  end
  check(not dup, "trainer ids are unique")
  eq(math.floor(ids[13] / 10) % 10, 6, "last pair draws from stage 6 (battle_tower.c:2608)")

  local links = hub(2)
  local ctxs = { [0] = { specialVars = {} }, [1] = { specialVars = {} } }
  for i = 0, 1 do ctxs[i].specialVars[Util.VAR_RESULT] = 0 end
  Rng.SeedRng(0x4455)
  local frames = 0
  for _ = 1, 40 do
    frames = frames + 1
    local done = true
    for i = 0, 1 do
      current = sessions[i]
      TowerLink._link = links[i]
      if Rse.specialVar(ctxs[i], Util.VAR_RESULT) ~= TowerLink.LOAD.DONE then
        TowerLink.loadLinkMultiOpponents(ctxs[i], sessions[i], nil)
        done = false
      end
    end
    if done then break end
  end
  TowerLink._link = nil
  for i = 0, 1 do
    eq(Rse.specialVar(ctxs[i], Util.VAR_RESULT), 6, "seat " .. i .. " finishes at state 6")
  end
  local a, b = Util.frontier(sessions[0]).trainerIds, Util.frontier(sessions[1]).trainerIds
  local same = true
  for k = 1, 14 do if a[k] ~= b[k] then same = false end end
  check(same, "both seats battle the leader's trainer list (battle_tower.c:2641)")
  local classes = D.pack("classes")
  local range = classes.trainerIdRanges[3 + 1]
  check(a[1] >= range[1] and a[1] <= range[2],
    "trainers come from the higher challenge of the pair (max of 1 and 3 -> challenge 3)")
  eq(sessions[1].frontierOpponentA, a[1], "opponent A set from the pair")
  eq(sessions[1].frontierOpponentB, a[2], "opponent B set from the pair")
  check(links[0].bytes <= 8192 and links[1].bytes <= 8192, "tower messages fit the 8KB relay cap")
end

print("[test] multi partner battle setup (pokeemerald/src/battle_main.c:1161)")
do
  local C = require("src.core.game3.constants").of("emerald")
  local function mon(name, level)
    return D.createMon(C.species.byName[name], level, 20, 7, 99)
  end
  sessions[0].party = { mon("SPECIES_SWAMPERT", 50), mon("SPECIES_SALAMENCE", 50) }
  sessions[1].party = { mon("SPECIES_METAGROSS", 50), mon("SPECIES_GARDEVOIR", 50) }
  current = sessions[0]
  Rng.SeedRng(0x77)
  local lead = TowerLink.buildSetup(sessions[0], 0, 0, 0xABCDEF)
  current = sessions[1]
  local guest = TowerLink.buildSetup(sessions[1], 1, 0, nil)
  check(type(lead.foes) == "table" and #lead.foes == 2, "leader sends both opponents' parties")
  eq(guest.foes, nil, "partner sends only its own party")
  eq(#lead.foes[1].party, 2, "opponent A brings two mons")
  local text = Json.encode(lead)
  check(#text <= 8192, "leader setup fits the 8KB relay cap (" .. #text .. " bytes)")
  local wire = Json.decode(text)
  for _, pair in ipairs({ { wire, Json.decode(Json.encode(guest)) }, { Json.decode(Json.encode(guest)), wire } }) do
    local setups, seed = TowerLink.setupsFor(pair[1], pair[2])
    eq(setups[0].name, "BRENDAN", "leader fights from multi seat 0")
    eq(setups[2].name, "MAY", "partner fights from multi seat 2")
    eq(setups[3].trainerId, sessions[0].frontierOpponentA, "opponent A on seat 3, battler 1")
    eq(setups[1].trainerId, sessions[0].frontierOpponentB, "opponent B on seat 1, battler 3")
    eq(seed, 0xABCDEF, "battle seed comes from the leader")
  end
  local setups = TowerLink.setupsFor(wire, Json.decode(Json.encode(guest)))
  local opts = TowerLink.battleOpts(sessions[1], setups)
  local tidA, tidB = sessions[0].frontierOpponentA, sessions[0].frontierOpponentB
  check(opts.towerLinkMulti == true, "battle runs as BATTLE_TYPE_TOWER_LINK_MULTI")
  eq(opts.trainerPicId, D.frontSpriteId(sessions[1], tidA, D.FACILITY.TOWER),
    "opponent A shows its frontier trainer pic, not a link pic")
  eq(opts.frontierTrainerB.pic, D.frontSpriteId(sessions[1], tidB, D.FACILITY.TOWER),
    "opponent B shows its frontier trainer pic")
  check(opts.trainerPicId ~= LB.TRAINER_PIC_RED and opts.trainerPicId ~= LB.TRAINER_PIC_LEAF,
    "opponent A pic is not the link RED/LEAF pic")
  eq(opts.trainerName, D.trainerName(sessions[1], tidA, D.FACILITY.TOWER), "opponent A keeps its frontier name")
  check(type(opts.defeatText) == "string" and opts.defeatText ~= "", "opponent A lose text resolves")
  check(type(opts.defeatTextB) == "string" and opts.defeatTextB ~= "", "opponent B lose text resolves")
  local IntroSeq = require("src.core.game3.battle.intro_seq")
  local pics = IntroSeq.multiTrainerPics({ multi = true, linkOwn = 0, linkGenders = { [0] = 0, 0, 1, 1 },
    towerLinkMulti = true, trainerPicId = opts.trainerPicId, trainerB = { pic = opts.frontierTrainerB.pic } }, 0)
  eq(pics.enemyPic, opts.trainerPicId, "intro draws opponent A's frontier pic at battler 1")
  eq(pics.enemyPic2, opts.frontierTrainerB.pic, "intro draws opponent B's frontier pic at battler 3")
  local BattleText = require("src.core.game3.battle.battle_text")
  eq(BattleText.key(0, { trainer = true, link = true, multi = true, towerLinkMulti = true }),
    "sText_TwoTrainersWantToBattle", "intro text names both frontier trainers")
  eq(BattleText.key(5, { outcome = "won", link = true, multi = true, towerLinkMulti = true }),
    "sText_TwoInGameTrainersDefeated", "win text is the in-game pair, not the link pair")
  local party = LB.unpackParty(wire.foes[1].party, { strict = true })
  check(party and #party == 2, "opponent party survives the wire")
  eq(party and party[1].level, 50, "level 50 opponents keep their level")
  local own = LB.unpackParty(wire.party, { strict = true })
  eq(own and own[1].species, sessions[0].party[1].species, "leader's own mon survives the wire")
end

print("[test] seat layout matches CB2_HandleStartMultiPartnerBattle (pokeemerald/src/battle_main.c:1197)")
do
  eq(LB.localBattler(0, 0) .. LB.localBattler(0, 1) .. LB.localBattler(0, 2) .. LB.localBattler(0, 3), "0321",
    "leader view: partner battler 2, opponents on 3 and 1")
  eq(LB.localBattler(2, 0) .. LB.localBattler(2, 1) .. LB.localBattler(2, 2) .. LB.localBattler(2, 3), "0321",
    "partner sees the same battler numbering, so both run one battle state")
end

T.finish()
