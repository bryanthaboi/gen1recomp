package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] online_trade_gen3: " .. tostring(Cache.reason))
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local SaveData = require("src.core.SaveData")
local Trade = require("src.online.Trade")
local TeamPick = require("src.online.TeamPick")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Mail = require("src.core.game3.mail")
local Schema = require("src.core.game3.save_schema_firered")
Pokemon.install(nil)
T.check(Pokemon._names ~= nil, "FireRed species tables load from the cache")

local files = {}
local fs = {
  getInfo = function(name) return files[name] and { type = "file" } or nil end,
  read = function(name) return files[name] end,
  write = function(name, body) files[name] = body return true end,
  remove = function(name) files[name] = nil return true end,
  createDirectory = function() return true end,
}
SaveData.portableFs = function() return fs end

local DATA = { generation = 3, Pokemon = Pokemon }

local function makeSave(version, name, trainerId, mons, national)
  local session = Schema.newGame({ version = version, name = name, rngSeed = trainerId })
  session.trainerId = trainerId
  session.party = {}
  for _, row in ipairs(mons) do
    assert(Party.giveMon(session, row.species, row.level, row.nickname))
    local mon = session.party[#session.party]
    for k, v in pairs(row.extra or {}) do mon[k] = v end
  end
  if national then session.dex.nationalUnlocked = true end
  local save = Schema.toSaveTable(session)
  return SaveData.decode(SaveData.encode(save))
end

local function handle(version, slotId, save)
  return {
    version = version, generation = 3, slotId = slotId, save = save,
    path = Trade.slotPath(version, slotId), party = save.party, data = DATA,
  }
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

do
  local fr = makeSave("firered", "RED", 11111, {
    { species = 64, level = 30, nickname = "ABRA CAD" },
    { species = 25, level = 12, extra = { item = 13, heldItem = 13 } },
  }, true)
  local lg = makeSave("leafgreen", "LEAF", 22222, {
    { species = 95, level = 25, extra = { item = 199, heldItem = 199 } },
    { species = 1, level = 8 },
  }, false)
  local A, B = handle("firered", "slot1", fr), handle("leafgreen", "slot1", lg)
  local kadabra, onix = copy(fr.party[1]), copy(lg.party[1])

  local plan, why = Trade.plan({ from = A, to = B, fromIndex = 1, toIndex = 1 })
  T.check(plan ~= nil, "a FireRed <-> LeafGreen trade plans: " .. tostring(why))
  T.eq(plan and plan.get.species, 208, "FireRed's Onix holding Metal Coat evolves into Steelix")
  T.eq(plan and plan.get.item, 0, "the Metal Coat is used up")
  T.eq(plan and plan.give.species, 65, "LeafGreen's Kadabra evolves into Alakazam")
  T.eq(plan and plan.give.nickname, "ABRA CAD", "the nickname rides along")
  T.eq(plan and plan.give.otName, "RED", "the OT name rides along")
  T.eq(plan and plan.give.otId, kadabra.otId, "the OT id rides along")
  T.eq(plan and plan.give.personality, kadabra.personality, "the personality rides along")
  T.check(plan and same(plan.give.moves, kadabra.moves), "the moves ride along")
  T.check(plan and same(plan.give.ivs, kadabra.ivs), "the IVs ride along")
  T.eq(plan and plan.get.personality, onix.personality, "Onix keeps its personality")
  T.eq(plan and plan.get.friendship, 70, "a traded mon's friendship is 70")
  T.eq(plan and plan.give.friendship, 70, "on both sides")
  T.eq(fr.party[1].species, 64, "planning leaves the FireRed save untouched")

  local ok, err = Trade.commit(plan)
  T.check(ok, "the trade commits: " .. tostring(err))
  local frNow = SaveData.decode(files["saves/firered/slot1.lua"] or "")
  local lgNow = SaveData.decode(files["saves/leafgreen/slot1.lua"] or "")
  T.eq(frNow and frNow.party[1].species, 208, "the FireRed file holds Steelix")
  T.eq(lgNow and lgNow.party[1].species, 65, "the LeafGreen file holds Alakazam")
  T.eq(frNow and frNow.party[2].item, 13, "untraded party mons keep their items")
  T.check(frNow and frNow.dex.owned[95] and frNow.dex.owned[208],
    "FireRed's dex owns Onix and Steelix")
  T.check(lgNow and lgNow.dex.owned[64] and lgNow.dex.owned[65],
    "LeafGreen's dex owns Kadabra and Alakazam")
  T.check(pcall(Schema.fromSaveTable, frNow), "the FireRed file loads back")
  T.check(pcall(Schema.fromSaveTable, lgNow), "the LeafGreen file loads back")
  T.eq(frNow and frNow.gameStats and frNow.gameStats[21], 1, "FireRed counts the trade")
  T.eq(lgNow and lgNow.gameStats and lgNow.gameStats[21], 1, "LeafGreen counts the trade")
  local function lastEvent(save)
    local okS, session = pcall(Schema.fromSaveTable, save)
    local scenes = okS and session.questLog and session.questLog.scenes or {}
    local scene = scenes[#scenes]
    return scene and scene.events[#scene.events], scene
  end
  local frEv, frScene = lastEvent(frNow)
  T.eq(frEv and frEv.key, "TradedMon1ForPersonsMon2", "FireRed's quest log records the link trade")
  T.eq(frEv and frEv.args.S1, "LEAF", "naming the partner")
  T.eq(frEv and frEv.args.S2, Pokemon.name(95), "the mon received, before it evolved")
  T.eq(frEv and frEv.args.S3, Pokemon.name(64), "and the mon sent")
  T.eq(frScene and frScene.map, frNow and frNow.map, "on the save's map")
  local lgEv = lastEvent(lgNow)
  T.eq(lgEv and lgEv.args.S1, "RED", "LeafGreen's entry names RED")
  T.eq(lgEv and lgEv.args.S2, Pokemon.name(64), "and the KADABRA it got")
end

do
  local fr = makeSave("firered", "RED", 11111, {
    { species = 25, level = 12, extra = { item = 13, heldItem = 13 } },
    { species = 16, level = 5 },
  }, false)
  local lg = makeSave("leafgreen", "LEAF", 22222, {
    { species = 19, level = 7 },
    { species = 1, level = 8 },
  }, false)
  fr.mail = Mail.restore({})
  local sessionLike = { mail = fr.mail, name = "RED", trainerId = 11111 }
  fr.party[1].item, fr.party[1].heldItem = 0, 0
  local id = Mail.giveMailToMon(sessionLike, fr.party[1], 121)
  fr.mail[id + 1].words[1] = 1234
  local A, B = handle("firered", "slot2", fr), handle("leafgreen", "slot2", lg)
  local plan, why = Trade.plan({ from = A, to = B, fromIndex = 1, toIndex = 1 })
  T.check(plan ~= nil, "a mail trade plans: " .. tostring(why))
  local got = plan and plan.give
  T.eq(got and got.item, 121, "the mail item rides along")
  local sideB = plan and plan.sides[2]
  local record = sideB and Mail.get(sideB.save3, got.mail)
  T.eq(record and record.words[1], 1234, "the partner's mail lands in the receiver's pool")
  local sideA = plan and plan.sides[1]
  T.check(sideA and Mail.isEmpty(Mail.slot(sideA.save3, id)),
    "the sender's copy of the mail is cleared")
  T.eq(plan and plan.get.species, 19, "Rattata goes the other way")
end

do
  local lone = makeSave("firered", "RED", 1, { { species = 25, level = 5 } }, false)
  local lg = makeSave("leafgreen", "LEAF", 2, { { species = 19, level = 5 }, { species = 1, level = 5 } }, false)
  local _, why = Trade.plan({ from = handle("firered", "s", lone),
    to = handle("leafgreen", "s", lg), fromIndex = 1, toIndex = 1 })
  T.eq(why, "that's your only POKéMON for battle", "the last mon can't be traded")

  local mew = makeSave("firered", "RED", 1, {
    { species = 151, level = 5, extra = { fatefulEncounter = false } },
    { species = 25, level = 5 },
  }, true)
  _, why = Trade.plan({ from = handle("firered", "s", mew),
    to = handle("leafgreen", "s", lg), fromIndex = 1, toIndex = 1 })
  T.eq(why, "that POKéMON can't be traded now", "a Mew without the fateful bit is refused")

  local johto = makeSave("firered", "RED", 1, {
    { species = 208, level = 30 }, { species = 25, level = 5 },
  }, true)
  _, why = Trade.plan({ from = handle("firered", "s", johto),
    to = handle("leafgreen", "s", lg), fromIndex = 1, toIndex = 1 })
  T.eq(why, "that POKéMON can't be traded now",
    "a non-Kanto mon can't go to a partner without the National Dex")

  local noNat = makeSave("firered", "RED", 1, {
    { species = 208, level = 30 }, { species = 25, level = 5 },
  }, false)
  _, why = Trade.plan({ from = handle("firered", "s", noNat),
    to = handle("leafgreen", "s", lg), fromIndex = 1, toIndex = 1 })
  T.eq(why, "that POKéMON can't be traded now",
    "a non-Kanto mon can't leave a save without the National Dex")

  local two = makeSave("firered", "RED", 1, { { species = 25, level = 5 }, { species = 16, level = 5 } }, false)
  _, why = Trade.plan({ from = handle("firered", "s", two),
    to = handle("leafgreen", "s", lg), fromIndex = { where = "box", box = 1, index = 1 }, toIndex = 1 })
  T.eq(why, "that's not in the party", "FireRed trades come from the party only")

  local red = { version = "red", generation = 1, slotId = "r", path = "saves/red/r.lua",
    save = { party = { { species = "PIKACHU", level = 5, moves = {} } } } }
  red.party = red.save.party
  _, why = Trade.plan({ from = handle("firered", "s", two), to = red, fromIndex = 1, toIndex = 1 })
  T.eq(why, "Those two games can't trade.", "FireRed and Red can't trade")

  local remote, rwhy = Trade.remote(handle("firered", "s", two), { send = function() end })
  T.eq(remote, nil, "no internet trade for a FireRed save")
  T.eq(rwhy, Trade.GEN3_LOCAL_ONLY, "and it says why")

  local packed, pwhy = TeamPick.pack({ party = two.party, generation = 3 }, { 1 }, 3)
  T.eq(packed, nil, "a FireRed team can't be packed for a room")
  T.eq(pwhy, TeamPick.GEN3_OFFLINE, "and it says why")
end

do
  local fr = makeSave("firered", "RED", 1, {
    { species = 25, level = 5 }, { species = 16, level = 5 },
  }, true)
  local lg = makeSave("leafgreen", "LEAF", 2, {
    { species = 152, level = 5, extra = { isEgg = true } }, { species = 1, level = 5 },
  }, true)
  local plan, why = Trade.plan({ from = handle("firered", "e", fr),
    to = handle("leafgreen", "e", lg), fromIndex = 1, toIndex = 1 })
  T.check(plan ~= nil, "an egg trades once both sides have the National Dex: " .. tostring(why))
  local sideA = plan and plan.sides[1]
  T.check(sideA and not (sideA.save3.dex.seen or {})[152],
    "a received egg does not mark the dex")
  T.eq(sideA and sideA.record.friendship, lg.party[1].friendship,
    "egg friendship is left alone")
  local scenes = sideA and sideA.save3.questLog and sideA.save3.questLog.scenes or {}
  local ev = scenes[#scenes] and scenes[#scenes].events[1]
  T.eq(ev and ev.args.S2, require("src.core.game3.rom_text").plain("gText_EggNickname"),
    "the quest log names a received egg EGG")

  local lgNoNat = makeSave("leafgreen", "LEAF", 2, {
    { species = 152, level = 5, extra = { isEgg = true } }, { species = 1, level = 5 },
  }, false)
  local _, ewhy = Trade.plan({ from = handle("firered", "e", fr),
    to = handle("leafgreen", "e", lgNoNat), fromIndex = 1, toIndex = 1 })
  T.check(ewhy ~= nil, "an egg can't leave a save without the National Dex")
end

T.finish()
