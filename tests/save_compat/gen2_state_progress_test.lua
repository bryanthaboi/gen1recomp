package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq, same = T.check, T.eq, T.same

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2State = require("src.save_convert.Gen2State")
local P = require("src.save_convert.gen2_state.progress")
local Save = require("src.core.gen2.Save")
local HallOfFame = require("src.core.gen2.HallOfFame")
local NpcTrade = require("src.core.gen2.NpcTrade")
local Decorations = require("src.core.gen2.Decorations")
local BattleTower = require("src.core.gen2.BattleTower")
local Mon = require("src.battle.gen2.Mon")
local World = require("src.world.gen2.World")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local Pokegear = require("src.ui.gen2.Pokegear")
local Music = require("src.core.Music")

local VERSIONS = { "gold", "silver", "crystal" }

local REGION_NAMES = {
  "savedAtLeastOnce", "lastDexModeAndRegistered", "hallOfFameCount", "tradeFlags",
  "decorations", "spawnAndBackupMap", "mysteryGift", "linkBattleStats", "hallOfFame",
  "gsBallFlag", "gsBallFlagBackup", "crystalData", "battleTower",
}

local DATA = {
  items = {},
  pokemon = {
    CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL", genderRatio = 0x1F },
    TOTODILE = { index = 158, dex = 158, name = "TOTODILE", genderRatio = 0x1F },
    CHIKORITA = { index = 152, dex = 152, name = "CHIKORITA", genderRatio = 0x1F },
    PIKACHU = { index = 25, dex = 25, name = "PIKACHU", genderRatio = 0x7F },
    STARMIE = { index = 121, dex = 121, name = "STARMIE", genderRatio = 0xFF },
    TYRANITAR = { index = 248, dex = 248, name = "TYRANITAR", genderRatio = 0x7F },
  },
  maps = {
    [K.GEN2_MAP] = K.gen2Data.maps[K.GEN2_MAP],
    TEST_CITY = { group = 3, map = 1 },
    TEST_CENTER = { group = 3, map = 4 },
    TEST_CENTER_2F = { group = 20, map = 1 },
    TEST_CAVE = { group = 7, map = 9 },
  },
}
for id, def in pairs(G2.ITEMS) do DATA.items[id] = def end
DATA.items.MAX_POTION.canSelect = true
DATA.items.POTION.canSelect = true
DATA.items.BICYCLE.canSelect = true

local function symsFor(v) return Gen2State.symsFor(v) end
local function ctxFor(v) return { S = symsFor(v), crystal = v == "crystal" } end

local function import(v, bytes)
  local save, err = Gen2Save.decode(bytes, v, DATA)
  check(save ~= nil, v .. " import -- " .. tostring(err))
  return save
end

local function export(v, save, template)
  local out, err = Gen2Save.encode(save, v, template, DATA)
  check(out ~= nil, v .. " export -- " .. tostring(err))
  return out, err
end

local function u8(s, at) return s:byte(at + 1) end

local function regionBytes(s, spans)
  local out = {}
  for _, sp in ipairs(spans) do out[#out + 1] = s:sub(sp[1] + 1, sp[1] + sp[2]) end
  return table.concat(out)
end

local function hex(s) return (s:gsub(".", function(c) return ("%02X"):format(c:byte()) end)) end

local function activeRegions(v)
  local out = {}
  for _, region in ipairs(P.REGIONS) do
    local spans = P.spansFor(ctxFor(v), region.id)
    if spans then out[#out + 1] = { id = region.id, spans = spans } end
  end
  return out
end

local function teamRow(b, base, win, mons)
  B.fill(b, base, 0x62, 0)
  B.put(b, base, win)
  for i, m in ipairs(mons) do
    local o = base + 1 + (i - 1) * 0x10
    B.put(b, o, m[1])
    B.be(b, o + 1, m[2], 2)
    B.put(b, o + 3, m[3], m[4], m[5])
    B.putGbName(b, o + 6, m[6], 10)
  end
  B.put(b, base + 1 + #mons * 0x10, 0xFF)
end

local PAINT = {}

PAINT.realistic = function(v)
  return function(b, L)
    local S = symsFor(v)
    B.put(b, S.wSavedAtLeastOnce, 1)
    B.put(b, S.wSpawnAfterChampion, 1)
    B.put(b, S.wRadioTuningKnob, 16)
    B.put(b, S.wLastDexMode, 2, 0)
    B.put(b, S.wWhichRegisteredItem, 0x01, G2.ITEMS.POTION.index)
    B.put(b, S.wHallOfFameCount, 2, 0)
    teamRow(b, S.sHallOfFame, 2, { { 155, 0x1234, 0x9F, 0x6A, 50, "FLAME" }, { 25, 0x1234, 0xAA, 0xAA, 48, "SPARKY" } })
    teamRow(b, S.sHallOfFame + 0x62, 1, { { 155, 0x1234, 0x9F, 0x6A, 45, "FLAME" } })
    B.put(b, S.wTradeFlags, 0x05)
    B.put(b, S.wMooMooBerries, 3)
    B.put(b, S.wUndergroundSwitchPositions, 0x0F)
    if S.wFarfetchdPosition then B.put(b, S.wFarfetchdPosition, 5) end
    if S.wJackFightCount then
      B.put(b, S.wJackFightCount, 1, 0, 2, 3, 0, 1, 4, 2)
      B.put(b, S.wErinFightCount, 3)
    end
    if S.wCelebiEvent then B.put(b, S.wCelebiEvent, 0x04) end
    B.put(b, S.wBikeFlags, 0x02)
    B.put(b, S.wDecoBed, 3, 8, 13, 16, 22, 30, 31, 26)
    B.put(b, S.wDigWarpNumber, 2, 3, 1, 1, 3, 4)
    B.put(b, S.wLastSpawnMapGroup, 3, 1)
    B.put(b, S.wWarpNumber, 2)
    B.put(b, S.sMysteryGiftTrainerHouseFlag, 1)
    B.putGbName(b, S.sMysteryGiftPartnerName, "KEN", 11)
    B.put(b, S.sMysteryGiftTimer, 0, 7)
    B.put(b, S.sMysteryGiftDecorationsReceived, 0x21)
    B.be(b, S.sLinkBattleStats, 3, 2)
    B.be(b, S.sLinkBattleStats + 2, 1, 2)
    if S.sGSBallFlag then
      B.put(b, S.sGSBallFlag, 0x0B)
      B.put(b, S.sGSBallFlagBackup, 0x0B)
      B.put(b, S.sCrystalData + 1, 21, 13, 0x12, 0x34, 0x56, 0x78)
      B.put(b, S.sBattleTowerChallengeState, 2, 3, 5)
      B.put(b, S.sBTTrainers, 4, 9, 12, 0xFF, 0xFF, 0xFF, 0xFF)
      B.put(b, S.sBattleTowerSaveFileFlags, 3, G2.ITEMS.MAX_POTION.index)
      B.put(b, S.sBTMonOfTrainers, 155, 158, 152, 25, 248, 121)
    end
  end
end

PAINT.glitch = function(v)
  return function(b, L)
    local S = symsFor(v)
    B.put(b, S.wSavedAtLeastOnce, 0x07)
    B.put(b, S.wSpawnAfterChampion, 0x09)
    B.put(b, S.wRadioTuningKnob, 0x81)
    B.put(b, S.wLastDexMode, 7, 0xAA)
    B.put(b, S.wWhichRegisteredItem, 0x45, 0x99)
    B.put(b, S.wHallOfFameCount, 0xC8, 0x5A)
    teamRow(b, S.sHallOfFame, 0xC8, { { 252, 0xFFFF, 0x12, 0x34, 0, "AB" } })
    B.put(b, S.sHallOfFame + 1 + 6 + 3, 0x7E, 0x00, 0x13)
    B.put(b, S.sHallOfFame + 0x30, 0x66)
    B.put(b, S.sHallOfFame + 0x62 * 3 + 5, 0x77)
    B.put(b, S.wTradeFlags, 0xFF)
    for i = 1, (S.wMooMooBerries - S.wTradeFlags - 1) do B.put(b, S.wTradeFlags + i, (i * 31) % 256) end
    B.put(b, S.wMooMooBerries, 0xFE)
    B.put(b, S.wUndergroundSwitchPositions, 0x80)
    if v ~= "crystal" then B.put(b, S.wUndergroundSwitchPositions + 1, 0x11, 0x22) end
    if S.wFarfetchdPosition then B.put(b, S.wFarfetchdPosition, 0x33, 0x44, 0x55) end
    if S.wJackFightCount then
      for i = 0, 27 do B.put(b, S.wJackFightCount + i, (i * 67 + 200) % 256) end
    end
    if S.wCelebiEvent then B.put(b, S.wCelebiEvent, 0xFB, 0x91) end
    B.put(b, S.wBikeFlags, 0xF8, 0x3C)
    B.put(b, S.wDecoBed, 0xFF, 0, 0xFE, 0, 0x80, 0x7F, 0x01, 0x99)
    B.put(b, S.wDigWarpNumber, 0x90, 0x77, 0x66, 0x55, 0x77, 0x44, 0xDE, 0xAD, 0xBE)
    B.put(b, S.wLastSpawnMapGroup, 0x77, 0x76)
    if v ~= "crystal" then B.put(b, S.wLastSpawnMapGroup + 2, 0x12, 0x34) end
    B.put(b, S.wWarpNumber, 0xEE)
    for i = 0, (S.sBackupMysteryGiftItemEnd - S.sMysteryGiftData) - 1 do
      B.put(b, S.sMysteryGiftData + i, (i * 53 + 7) % 256)
    end
    for i = 0, (S.sLinkBattleStatsEnd - S.sLinkBattleStats) - 1 do
      B.put(b, S.sLinkBattleStats + i, (i * 17 + 3) % 256)
    end
    if S.sGSBallFlag then
      B.put(b, S.sGSBallFlag, 0x05)
      B.put(b, S.sGSBallFlagBackup, 0x0B)
      B.put(b, S.sCrystalData + 1, 0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA)
      for i = 0, 17 do B.put(b, S.sBattleTowerChallengeState + i, (i * 41 + 9) % 256) end
    end
  end
end

for _, v in ipairs(VERSIONS) do
  for _, kind in ipairs({ "realistic", "glitch" }) do
    local bytes = G2.build({ version = v, patch = PAINT[kind](v) })
    local save = import(v, bytes)
    if save then
      local out = export(v, save, bytes)
      local fresh1, fresh2
      local copy = {}
      for k, x in pairs(save) do copy[k] = x end
      copy.rawImport = nil
      fresh1 = export(v, copy, nil)
      local back = fresh1 and import(v, fresh1)
      fresh2 = back and export(v, back, nil)
      for _, r in ipairs(activeRegions(v)) do
        local label = ("%s %s %s"):format(v, kind, r.id)
        local want = regionBytes(bytes, r.spans)
        if out then eq(hex(regionBytes(out, r.spans)), hex(want), label .. ": R1 over the template is byte-identical") end
        if fresh1 then eq(hex(regionBytes(fresh1, r.spans)), hex(want), label .. ": templateless export reproduces the cart bytes") end
        if fresh2 then eq(hex(regionBytes(fresh2, r.spans)), hex(regionBytes(fresh1, r.spans)), label .. ": templateless export is a fixed point") end
      end
    end
  end
end

for _, v in ipairs(VERSIONS) do
  local S = symsFor(v)
  local save = import(v, G2.build({ version = v, patch = PAINT.realistic(v) }))
  local gs = v ~= "crystal"
  eq(save.spawnAfterChampion, "SPAWN_LANCE", v .. " wSpawnAfterChampion 1 is SPAWN_LANCE")
  eq(save.radioTuningKnob, 16, v .. " wRadioTuningKnob")
  eq(save.lastDexMode, "A-Z", v .. " wLastDexMode DEXMODE_ABC")
  same(save.registeredItem, { id = "POTION" }, v .. " wRegisteredItem")
  eq(save.hallOfFame.count, 2, v .. " wHallOfFameCount")
  eq(#save.hallOfFame.teams, 2, v .. " sHallOfFame rows up to the first zero win count")
  eq(save.hallOfFame.entered, true, v .. " a counted Hall of Fame has been entered")
  local m = save.hallOfFame.teams[1].mons[2]
  eq(m.species, "PIKACHU", v .. " HoF species")
  eq(m.nickname, "SPARKY", v .. " HoF nickname")
  eq(m.level, 48, v .. " HoF level")
  eq(m.otId, 0x1234, v .. " HoF ID")
  eq(m.shiny, true, v .. " HoF shiny from DVs")
  same(m.dvs, { attack = 10, defense = 10, speed = 10, special = 10, hp = 0 }, v .. " HoF DVs")
  same(save.tradeFlags, { [0] = true, [2] = true }, v .. " wTradeFlags")
  local mem = gs and { [0xD6A7] = 3, [0xD6A8] = 0x0F }
    or { [0xD962] = 3, [0xD963] = 0x0F, [0xD964] = 5, [0xD9F2] = 1, [0xD9F5] = 3, [0xD9F8] = 4, [0xDA0D] = 3 }
  if not gs then
    eq(save.scriptMem[0xD9F3], nil, v .. " a zero fight count is not stored")
    eq(P.wramOf(ctxFor(v), "wJackFightCount"), 0xD9F2, v .. " wJackFightCount derives to the scripts' $D9F2")
    eq(P.wramOf(ctxFor(v), "wErinFightCount"), 0xDA0D, v .. " wErinFightCount derives to the scripts' $DA0D")
  end
  for addr, val in pairs(mem) do eq(save.scriptMem[addr], val, ("%s scriptMem $%04X"):format(v, addr)) end
  local bike = gs and 24 or 25
  eq(save.engineFlags[bike], true, v .. " BIKEFLAGS_ALWAYS_ON_BIKE_F is ENGINE_ALWAYS_ON_BIKE")
  if not gs then eq(save.engineFlags[100], true, v .. " ENGINE_FOREST_IS_RESTLESS") end
  same(save.decorations, { bed = 3, carpet = 8, plant = 13, poster = 16, console = 22,
    leftOrnament = 30, rightOrnament = 31, bigDoll = 26 }, v .. " wDeco*")
  same(save.backupWarp, { warp = 1, map = "TEST_CENTER" }, v .. " wBackupWarpNumber triple")
  eq(save.blackoutMap, "TEST_CITY", v .. " wLastSpawnMapGroup pair")
  same(save.mysteryGift, { trainerHouse = true, partnerName = "KEN" }, v .. " sMysteryGiftTrainerHouseFlag")
  if gs then
    eq(save.battleTower, nil, v .. " has no Battle Tower")
    eq(save.crystal, nil, v .. " has no Crystal block")
  else
    eq(save.crystal.gsBall, "have", v .. " sGSBallFlag GS_BALL_AVAILABLE")
    same(save.battleTower, {
      challenge = 2, streak = 3, levelGroup = 5, trainers = { 4, 9, 12 }, saveFileFlags = 3,
      reward = "MAX_POTION", best = 0, inChallenge = false, reentry = false,
      prevTeams = { prev = { "CYNDAQUIL", "TOTODILE", "CHIKORITA" }, prevPrev = { "PIKACHU", "TYRANITAR", "STARMIE" } },
    }, v .. " SRAM Battle Tower")
  end
  check(type(save[P.CARRIER]) == "table", v .. " carries the raw region bytes")
  check(S.sHallOfFame ~= nil, v .. " sHallOfFame resolves through Gen2Syms")
end

for _, v in ipairs(VERSIONS) do
  local save = import(v, G2.build({ version = v, patch = PAINT.glitch(v) }))
  eq(save.spawnAfterChampion, nil, v .. " an unknown wSpawnAfterChampion is an ordinary continue")
  eq(save.lastDexMode, "NEW", v .. " an unknown wLastDexMode reads as DEXMODE_NEW")
  same(save.registeredItem, { id = 0x99 }, v .. " an unnamed registered item keeps its raw id")
  eq(save.backupWarp, nil, v .. " an unknown backup map is not handed to the engine")
  eq(save.blackoutMap, nil, v .. " an unknown whiteout map is not handed to the engine")
  same(save.tradeFlags, v == "crystal" and { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true }
    or { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true },
    v .. " wTradeFlags bits past NUM_NPC_TRADES stay raw")
  eq(save.hallOfFame.teams[1].mons[1].species, 252, v .. " an unknown HoF species keeps its number")
end

local function baseSave(v)
  local s = Save.newGame({ playerName = "ASH", trainerId = 0x4242 })
  s.version = v
  s.position = { map = K.GEN2_MAP, x = 3, y = 4 }
  s.inventory = { POTION = 3, BICYCLE = 1, POKE_BALL = 5 }
  s.bagOrder = { "POTION", "BICYCLE", "POKE_BALL" }
  return Save.normalize(s)
end

local function partyMon(species, level, nick, dvs, otId)
  local mon = { species = species, level = level, nickname = nick, otId = otId, dvs = dvs }
  dvs.hp = Mon.hpDV(dvs)
  return Mon.syncIdentity(mon, DATA)
end

local function drive(script)
  local vm = Vm.new({ ["s:t"] = script }, {}, Events.new(), {
    showText = function(_, onDone) onDone() end, waitSfx = function() return true end,
  })
  vm:start("s:t")
  for _ = 1, 200 do
    if not vm:running() then break end
    vm:update()
  end
  return vm
end

local function fakeWorld(save)
  return setmetatable({ game = { save = save, data = DATA }, maps = DATA.maps }, { __index = World })
end

local function decoView(state)
  local out = {}
  for _, slot in ipairs(Decorations.SLOTS) do out[slot] = (state or {})[slot] or 0 end
  return out
end

local ROSTER = {
  sampleTrainers = 3,
  trainers = { { index = 0, name = "A" }, { index = 1, name = "B" }, { index = 2, name = "C" } },
  groups = { [1] = { { species = "CYNDAQUIL" }, { species = "TOTODILE" }, { species = "CHIKORITA" },
                     { species = "PIKACHU" } } },
}

local function engineBuilt(v)
  local save = baseSave(v)
  local crystal = v == "crystal"
  local party = {
    partyMon("CYNDAQUIL", 50, "FLAME", { attack = 9, defense = 15, speed = 6, special = 10 }, 0x4242),
    { species = "TOTODILE", isEgg = true, level = 5, dvs = { attack = 1, defense = 1, speed = 1, special = 1 } },
    partyMon("PIKACHU", 47, "SPARKY", { attack = 10, defense = 10, speed = 10, special = 10 }, 0x0101),
  }
  HallOfFame.induct(save, party)
  HallOfFame.induct(save, { partyMon("TYRANITAR", 55, "ROCKY", { attack = 3, defense = 4, speed = 5, special = 6 }, 0x4242) })
  HallOfFame.markRedCredits(save)
  NpcTrade.markDone(save, 1)
  NpcTrade.markDone(save, 4)
  local deco = Decorations.state(save)
  Decorations.useRegistry({ text = require("tests.fixture_data.gen2_rom_text_s7_g").text() })
  Decorations.apply(deco, 4)
  Decorations.apply(deco, 8)
  Decorations.apply(deco, 15)
  Decorations.apply(deco, 30, "left")
  Decorations.clearOtherSide(deco, 30, "left")
  Decorations.apply(deco, 26)
  Decorations.useRegistry(nil)
  check(World.registerItem(fakeWorld(save), "BICYCLE"), v .. " World:registerItem accepts the BICYCLE")
  local w = fakeWorld(save)
  World.setBlackoutMap(w, 3, 1)
  World.recordWarpBackup(w, "TEST_CENTER", 2, { destWarp = 0xFF }, "TEST_CENTER_2F")
  save.backupWarp = w.backupWarp
  local S = symsFor(v)
  local berries = crystal and 0xD962 or 0xD6A7
  local switches = crystal and 0xD963 or 0xD6A8
  local vm = drive({
    { op = "readmem", args = { switches % 256, math.floor(switches / 256) } },
    { op = "addval", args = { 3 } },
    { op = "writemem", args = { switches % 256, math.floor(switches / 256) } },
    { op = "setval", value = 6 },
    { op = "writemem", args = { berries % 256, math.floor(berries / 256) } },
    { op = "end" },
  })
  if crystal then
    vm.mem[0xD964] = nil
    local v2 = drive({ { op = "loadmem", args = { 0x64, 0xD9, 9 } }, { op = "loadmem", args = { 0xF2, 0xD9, 4 } },
      { op = "readmem", args = { 0x0D, 0xDA } }, { op = "addval", args = { 2 } },
      { op = "writemem", args = { 0x0D, 0xDA } }, { op = "end" } })
    for k, x in pairs(v2.mem) do vm.mem[k] = x end
  end
  save.scriptMem = vm:serializeMem()
  local oldPlay, oldStop = Music.play, Music.stop
  Music.play, Music.stop = function() end, function() end
  local gear = Pokegear.new({ save = save,
    data = { text = require("tests.fixture_data.gen2_rom_text_s7_d").text(),
      gen2Landmarks = require("tests.fixture_data.gen2_landmarks_s7_d").table(
        crystal and "crystal" or "gold") },
    input = { wasPressed = function() return false end } },
    { clock = { hour = 14, minute = 0, weekday = 1 } })
  gear.tuningKnob = 28
  gear:tuneRadio()
  Music.play, Music.stop = oldPlay, oldStop
  save.lastDexMode = "OLD"
  local bikeId = crystal and 25 or 24
  World.setEngineFlag(fakeWorld(save), bikeId, true)
  save.mysteryGift = { trainerHouse = true, partnerName = "RIVAL" }
  if crystal then
    World.setEngineFlag(fakeWorld(save), 100, true)
    Save.crystalState(save).gsBall = "given"
    local seq = { 2, 1, 3, 2, 1, 1 }
    local i = 0
    local function random(n) i = i + 1; return math.min(seq[i] or 1, n) end
    BattleTower.resetTrainers(save)
    BattleTower.setChallengeState(save, BattleTower.CHALLENGE_IN_PROGRESS)
    BattleTower.setSaveFileFlag(save, BattleTower.SAVEFILE_REGISTERED)
    BattleTower.state(save).levelGroup = 4
    BattleTower.chooseTrainer(save, ROSTER, random)
    BattleTower.chooseTeam(save, ROSTER, 1, random)
    BattleTower.beginBattle(save)
    BattleTower.chooseTrainer(save, ROSTER, random)
    BattleTower.chooseTeam(save, ROSTER, 1, random)
    BattleTower.state(save).reward = "MAX_POTION"
  end
  return save
end

for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  local save = engineBuilt(v)
  local out = export(v, save, nil)
  local back = out and import(v, out)
  if back then
    local label = v .. " R2 "
    eq(back.spawnAfterChampion, save.spawnAfterChampion, label .. "spawnAfterChampion")
    eq(back.radioTuningKnob, save.radioTuningKnob, label .. "radioTuningKnob")
    eq(back.lastDexMode, save.lastDexMode, label .. "lastDexMode")
    same(back.registeredItem, save.registeredItem, label .. "registeredItem")
    same(back.hallOfFame, save.hallOfFame, label .. "hallOfFame")
    same(back.tradeFlags, save.tradeFlags, label .. "tradeFlags")
    same(back.scriptMem, save.scriptMem, label .. "scriptMem")
    for _, id in ipairs(v == "crystal" and { 24, 25, 26, 100 } or { 23, 24, 25 }) do
      eq(back.engineFlags[id], save.engineFlags[id], label .. "engineFlags " .. id)
    end
    same(decoView(back.decorations), decoView(save.decorations), label .. "decorations")
    same(back.backupWarp, save.backupWarp, label .. "backupWarp")
    eq(back.blackoutMap, save.blackoutMap, label .. "blackoutMap")
    same(back.mysteryGift, save.mysteryGift, label .. "mysteryGift")
    if v == "crystal" then
      check(Save.GS_BALL_STATES[back.crystal.gsBall], label .. "crystal.gsBall stays a GS Ball state")
      local want = BattleTower.state(save)
      local got = BattleTower.state(back)
      for _, k in ipairs({ "challenge", "streak", "levelGroup", "saveFileFlags", "reward" }) do
        eq(got[k], want[k], label .. "battleTower." .. k)
      end
      same(got.trainers, want.trainers, label .. "battleTower.trainers")
      same(got.prevTeams, want.prevTeams, label .. "battleTower.prevTeams")
    end
    if v == "crystal" then same(back.battleTower, save.battleTower, label .. "battleTower whole") end
    local r = require("tests.save_compat._gen2_reference").decode(out, v)
    check(r.checksum1 and r.checksum2, label .. "the independent reader accepts both checksums")
    local S = symsFor(v)
    -- pokecrystal macros/ram.asm:242
    eq(u8(out, S.sHallOfFame), 2, label .. "raw row 1 win count")
    eq(u8(out, S.sHallOfFame + 1), 248, label .. "raw row 1 species")
    eq(u8(out, S.sHallOfFame + 6), 55, label .. "raw row 1 level")
    eq(u8(out, S.sHallOfFame + 17), 0xFF, label .. "raw row 1 terminator")
    eq(u8(out, S.sHallOfFame + 0x62), 1, label .. "raw row 2 win count")
    eq(u8(out, S.sHallOfFame + 0x62 + 17), 25, label .. "raw row 2 skips the egg")
    eq(u8(out, S.sHallOfFame + 0x62 * 2), 0, label .. "raw row 3 absent")
    local again = export(v, back, nil)
    if again then
      for _, r in ipairs(activeRegions(v)) do
        eq(hex(regionBytes(again, r.spans)), hex(regionBytes(out, r.spans)), label .. r.id .. " fixed point")
      end
    end
  end
end

for _, v in ipairs(VERSIONS) do
  local S = symsFor(v)
  local crystal = v == "crystal"
  local bytes = G2.build({ version = v, patch = PAINT.realistic(v) })
  local save = import(v, bytes)
  save.radioTuningKnob = 40
  save.lastDexMode = "OLD"
  save.registeredItem = { id = "BICYCLE" }
  HallOfFame.induct(save, { partyMon("TOTODILE", 61, "JAWS", { attack = 12, defense = 5, speed = 7, special = 2 }, 0xBEEF) })
  HallOfFame.markRedCredits(save)
  save.tradeFlags = { [1] = true, [4] = true }
  save.scriptMem[crystal and 0xD962 or 0xD6A7] = 9
  save.scriptMem[crystal and 0xD963 or 0xD6A8] = nil
  local bike = crystal and 24 or 23
  save.engineFlags[bike] = true
  save.engineFlags[bike + 1] = nil
  save.engineFlags[bike + 2] = true
  if crystal then
    save.engineFlags[100] = nil
    save.scriptMem[0xD9F2] = 4
    save.scriptMem[0xDA0D] = nil
  end
  save.decorations = { bed = 5, carpet = 0, plant = 12, poster = 17, console = 21,
    leftOrnament = 0, rightOrnament = 33, bigDoll = 27 }
  save.backupWarp = { warp = 3, map = "TEST_CAVE" }
  save.blackoutMap = "TEST_CENTER_2F"
  save.mysteryGift = { trainerHouse = false }
  if crystal then
    save.crystal.gsBall = nil
    local tower = BattleTower.state(save)
    tower.challenge, tower.streak, tower.levelGroup = 3, 7, 9
    tower.trainers = { 1, 2, 3, 4, 5, 6, 7 }
    tower.saveFileFlags, tower.reward = 1, "POTION"
    tower.prevTeams = { prev = { "PIKACHU" }, prevPrev = {} }
  end
  local out = export(v, save, bytes)
  if out then
    local label = v .. " change "
    -- pokecrystal engine/events/halloffame.asm:53
    eq(u8(out, S.wSpawnAfterChampion), 2, label .. "SPAWN_RED is 2")
    -- pokecrystal engine/pokegear/pokegear.asm:1399
    eq(u8(out, S.wRadioTuningKnob), 40, label .. "knob byte")
    -- pokecrystal engine/pokedex/pokedex.asm:61
    eq(u8(out, S.wLastDexMode), 1, label .. "DEXMODE_OLD")
    eq(u8(out, S.wLastDexMode + 1), 0, label .. "the byte after wLastDexMode is untouched")
    -- pokecrystal engine/items/pack.asm:547
    eq(u8(out, S.wWhichRegisteredItem), 0x81, label .. "KEY_ITEM_POCKET << 6 | slot 1")
    eq(u8(out, S.wRegisteredItem), G2.ITEMS.BICYCLE.index, label .. "registered item id")
    eq(u8(out, S.wHallOfFameCount), 3, label .. "wHallOfFameCount bumped")
    local row = S.sHallOfFame
    -- pokecrystal engine/events/halloffame.asm:137
    eq(u8(out, row), 3, label .. "new row win count")
    eq(u8(out, row + 1), 158, label .. "new row species")
    eq(u8(out, row + 2) * 256 + u8(out, row + 3), 0xBEEF, label .. "new row ID big-endian")
    eq(u8(out, row + 4), 0xC5, label .. "new row DV byte 1")
    eq(u8(out, row + 5), 0x72, label .. "new row DV byte 2")
    eq(u8(out, row + 6), 61, label .. "new row level")
    eq(u8(out, row + 7), 0x89, label .. "new row nickname J")
    eq(u8(out, row + 11), 0x50, label .. "new row nickname terminator")
    eq(u8(out, row + 17), 0xFF, label .. "new row ends in -1")
    eq(u8(out, row + 0x62), 2, label .. "AddHallOfFameEntry shifted the old first row down")
    eq(hex(out:sub(row + 0x62 + 1, row + 0x62 * 3)), hex(bytes:sub(row + 1, row + 0x62 * 2)),
      label .. "the old rows moved whole")
    eq(u8(out, S.wTradeFlags), 0x12, label .. "trade bits 1 and 4")
    eq(u8(out, S.wMooMooBerries), 9, label .. "wMooMooBerries")
    eq(u8(out, S.wUndergroundSwitchPositions), 0, label .. "wUndergroundSwitchPositions cleared")
    -- pokecrystal constants/ram_constants.asm:311
    eq(u8(out, S.wBikeFlags), 0x05, label .. "strength and downhill bits")
    if crystal then
      eq(u8(out, S.wCelebiEvent), 0x00, label .. "forest no longer restless")
      eq(u8(out, S.wJackFightCount), 4, label .. "scriptMem[$D9F2] is wJackFightCount")
      eq(u8(out, S.wErinFightCount), 0, label .. "a cleared $DA0D zeroes wErinFightCount")
      eq(u8(out, S.wJackFightCount + 2), 2, label .. "an untouched fight count keeps its byte")
    end
    eq(hex(out:sub(S.wDecoBed + 1, S.wDecoBed + 8)), "05000C111500211B", label .. "wDeco* in ram order")
    eq(hex(out:sub(S.wDigWarpNumber + 1, S.wDigWarpNumber + 6)), "030709030709", label .. "both warp triples")
    eq(hex(out:sub(S.wLastSpawnMapGroup + 1, S.wLastSpawnMapGroup + 2)), "1401", label .. "wLastSpawnMap pair")
    eq(u8(out, S.sMysteryGiftTrainerHouseFlag), 0, label .. "trainer house flag cleared")
    eq(hex(out:sub(S.sMysteryGiftTimer + 1, S.sMysteryGiftTimer + 2)), "0007", label .. "the rest of the gift block is kept")
    if crystal then
      eq(u8(out, S.sGSBallFlag), 0, label .. "sGSBallFlag")
      eq(u8(out, S.sGSBallFlagBackup), 0, label .. "sGSBallFlagBackup")
      eq(hex(out:sub(S.sBattleTowerChallengeState + 1, S.sBattleTowerChallengeState + 18)),
        "030709010203040506070112190000000000", label .. "SRAM Battle Tower in sram.asm order")
    end
    local back = import(v, out)
    if back then
      eq(back.hallOfFame.count, 3, label .. "reimported count")
      eq(back.hallOfFame.teams[1].mons[1].nickname, "JAWS", label .. "reimported row")
    end
  end
end

for _, v in ipairs(VERSIONS) do
  local S = symsFor(v)
  local bytes = G2.build({ version = v, patch = PAINT.realistic(v),
    items = { { G2.ITEMS.REPEL.index, 1 }, { G2.ITEMS.POTION.index, 3 } } })
  local save = import(v, bytes)
  save.registeredItem = { id = "POTION" }
  local out = export(v, save, bytes)
  eq(u8(out, S.wWhichRegisteredItem), 0x02, v .. " the POTION is in slot 2 now")
  save.inventory.POTION = nil
  save.bagOrder = { "REPEL" }
  out = export(v, save, bytes)
  eq(u8(out, S.wWhichRegisteredItem), 0x01, v .. " a used-up registered item keeps the cart's stale slot")
  eq(u8(out, S.wRegisteredItem), G2.ITEMS.POTION.index, v .. " and its id")
end

local SWEEP = {
  gs = {
    [0xCE51] = "wOtherPlayerLinkMode", [0xD0D8] = "wStrengthSpecies", [0xD117] = "wTempWildMonSpecies",
    [0xD6A7] = "wMooMooBerries", [0xD6A8] = "wUndergroundSwitchPositions",
  },
  crystal = {
    [0xCF51] = "wOtherPlayerLinkMode", [0xCF64] = "wNrOfBeatenBattleTowerTrainers",
    [0xD1EF] = "wStrengthSpecies", [0xD22E] = "wTempWildMonSpecies",
    [0xD962] = "wMooMooBerries", [0xD963] = "wUndergroundSwitchPositions", [0xD964] = "wFarfetchdPosition",
  },
}
do
  local names = { "wJackFightCount", "wBeverlyFightCount", "wHueyFightCount", "wGavenFightCount",
    "wBethFightCount", "wJoseFightCount", "wReenaFightCount", "wJoeyFightCount", "wWadeFightCount",
    "wRalphFightCount", "wLizFightCount", "wAnthonyFightCount", "wToddFightCount", "wGinaFightCount",
    "wIrwinFightCount", "wArnieFightCount", "wAlanFightCount", "wDanaFightCount", "wChadFightCount",
    "wDerekFightCount", "wTullyFightCount", "wBrentFightCount", "wTiffanyFightCount", "wVanceFightCount",
    "wWiltonFightCount", "wKenjiFightCount", "wParryFightCount", "wErinFightCount" }
  for i, name in ipairs(names) do SWEEP.crystal[0xD9F2 + i - 1] = name end
end

local home = os.getenv("HOME") or ""
local CACHES = {
  gold = os.getenv("GOLD_CACHE") or home .. "/Library/Application Support/LOVE/gold-bsa0925-gameplay/gold",
  silver = os.getenv("SILVER_CACHE") or home .. "/Library/Application Support/LOVE/pokemon-love2d/silver",
  crystal = os.getenv("CRYSTAL_CACHE") or home .. "/Library/Application Support/LOVE/crystal-bsa0925-gameplay/crystal",
}
local MEM_OPS = { readmem = true, writemem = true, loadmem = true }

local function cacheScripts(dir)
  local out, found = {}, false
  for _, f in ipairs({ "scripts.lua", "std_scripts.lua" }) do
    local fn = loadfile(dir .. "/data/generated/" .. f)
    if fn then found = true; out[#out + 1] = fn() end
  end
  return found and out or nil
end

local function walkOps(roots, fn)
  local seen = {}
  local function walk(t)
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    if type(t.op) == "string" then fn(t) end
    for _, x in pairs(t) do walk(x) end
  end
  for _, r in ipairs(roots) do walk(r) end
end

for _, v in ipairs(VERSIONS) do
  local ctx = ctxFor(v)
  local fam = v == "crystal" and "crystal" or "gs"
  local lo, hi = P.savedWram(ctx, G2.layout(v))
  local mapped = P.scriptMemAddresses(ctx)
  for addr, name in pairs(SWEEP[fam]) do
    local label = ("%s $%04X %s"):format(v, addr, name)
    if addr >= lo and addr < hi then
      eq(mapped[addr], name, label .. " is in the saved block and scriptMem maps it to its label")
      local save = baseSave(v)
      save.scriptMem[addr] = 0x5C
      local out = export(v, save, nil)
      if out then
        eq(u8(out, ctx.S[name]), 0x5C, label .. " lands on the label's file byte")
        local back = import(v, out)
        eq(back and back.scriptMem[addr], 0x5C, label .. " round-trips through scriptMem")
      end
    else
      check(addr < lo or addr >= hi, label .. " is session WRAM outside sGameData")
      eq(mapped[addr], nil, label .. " is not written to the cartridge")
    end
  end
  for addr in pairs(mapped) do
    check(SWEEP[fam][addr] ~= nil, ("%s $%04X: every mapped scriptMem address is in the sweep"):format(v, addr))
  end
  check(BattleTower.WRAM_NR_BEATEN < lo or BattleTower.WRAM_NR_BEATEN >= hi or v ~= "crystal",
    v .. " the Battle Tower's direct vm.mem byte is session WRAM")
  local roots = CACHES[v] and cacheScripts(CACHES[v])
  if roots then
    local mems, warpmods = 0, 0
    walkOps(roots, function(cmd)
      if MEM_OPS[cmd.op] and cmd.args then
        mems = mems + 1
        local addr = (cmd.args[1] or 0) + (cmd.args[2] or 0) * 256
        check(SWEEP[fam][addr] ~= nil, ("%s cache %s $%04X is in the enumerated sweep"):format(v, cmd.op, addr))
      elseif cmd.op == "warpmod" then
        warpmods = warpmods + 1
      end
    end)
    check(mems > 0, v .. " the cache sweep saw the script memory ops")
    eq(warpmods, 0, v .. " no extracted script runs warpmod, so save.warpMod is never written")
  else
    print(("[skip] %s script cache absent: the enumerated sweep still ran"):format(v))
  end
end

do
  local count = 0
  local home = "../"
  for _, repo in ipairs({ "pokegold", "pokecrystal" }) do
    local p = io.popen(("grep -rln '\\bwarpmod\\b' '%s%s/maps' 2>/dev/null"):format(home, repo))
    if p then
      for _ in p:lines() do count = count + 1 end
      p:close()
    end
  end
  eq(count, 0, "no pret map script uses warpmod")
end

for _, v in ipairs(VERSIONS) do
  local save = baseSave(v)
  save.backupWarp = { warp = 2, map = "TEST_CENTER" }
  save.warpMod = { warp = 2, map = "TEST_CENTER", group = 3, mapNumber = 4 }
  local out = export(v, save, nil)
  check(out ~= nil, v .. " a warpMod the backup triple already holds exports")
  save.warpMod = { warp = 1, map = "TEST_CITY", group = 3, mapNumber = 1 }
  local bad, err = Gen2Save.encode(save, v, nil, DATA)
  check(bad == nil and tostring(err):find("warpmod", 1, true) ~= nil,
    v .. " a warpMod the backup triple does not hold is refused -- " .. tostring(err))
end

for _, v in ipairs(VERSIONS) do
  local function refused(edit, fragment, label)
    local save = baseSave(v)
    edit(save)
    local out, err = Gen2Save.encode(save, v, nil, DATA)
    check(out == nil and tostring(err):find(fragment, 1, true) ~= nil, v .. " refuses " .. label .. " -- " .. tostring(err))
  end
  refused(function(s) s.blackoutMap = "NOWHERE" end, "whiteout map", "an unknown whiteout map")
  refused(function(s) s.backupWarp = { warp = 1, map = "NOWHERE" } end, "backup warp map", "an unknown backup map")
  refused(function(s) s.tradeFlags = { [9] = true } end, "NPC trade 9", "a trade past NUM_NPC_TRADES")
  refused(function(s) s.radioTuningKnob = 300 end, "radio tuning knob", "a knob past a byte")
  refused(function(s) s.lastDexMode = "UNOWN" end, "Pokedex mode", "a dex mode the cart has no byte for")
  refused(function(s) s.spawnAfterChampion = "SPAWN_HOME" end, "post-champion spawn", "an unknown post-champion spawn")
  refused(function(s)
    local teams = {}
    for i = 1, 31 do teams[i] = { winCount = i, mons = {} } end
    s.hallOfFame = { count = 31, teams = teams }
  end, "Hall of Fame holds 31", "a 31-team roster")
  refused(function(s) s.hallOfFame = { count = 1, teams = { { winCount = 0, mons = {} } } } end,
    "win count of 0", "a zero win count")
  if v == "crystal" then
    refused(function(s) Save.crystalState(s).gsBall = "maybe" end, "GS Ball state", "an unknown GS Ball state")
    refused(function(s) BattleTower.state(s).trainers = { [9] = 1 } end, "trainer slot 9", "a Battle Tower slot past 7")
  end
end

do
  local files = {}
  local p = io.popen("find src -name '*.lua'")
  for line in p:lines() do files[#files + 1] = line end
  p:close()
  check(#files > 100, "the source scan found the engine")
  local PATTERNS = {
    { "savedAtLeastOnce", "[%w_%.]*[Ss]avedAtLeastOnce%s*=" },
    { "warpNumber", "save%.warpNumber%s*=" },
    { "linkBattleStats", "save%.linkBattle[%w_]*%s*=" },
    { "linkBattleStats", "linkBattleStats%s*=" },
    { "linkBattleStats", "linkBattleRecords?%s*=" },
    { "linkBattleStats", "save%.[%w_]*[Ww]ins%s*=" },
    { "linkBattleStats", "save%.[%w_]*[Ll]osses%s*=" },
    { "linkBattleStats", "save%.[%w_]*[Dd]raws%s*=" },
    { "crystalData", "playerAge%s*=" },
    { "crystalData", "prefecture%s*=" },
    { "crystalData", "postalCode%s*=" },
  }
  local SKIP = { "^src/save_convert/", "^src/core/game3/", "^src/import/gba/", "^src/ui/game3/",
                 "^src/save_convert/gen3", "^src/core/Game3" }
  for _, path in ipairs(files) do
    local skip = false
    for _, pat in ipairs(SKIP) do if path:find(pat) then skip = true end end
    if not skip then
      local f = io.open(path, "r")
      local body = f:read("*a")
      f:close()
      for _, row in ipairs(PATTERNS) do
        local at = body:find(row[2])
        check(at == nil, ("%s: %s writes %s state at byte %s"):format(row[1], path, row[1], tostring(at)))
      end
    end
  end
  for _, name in ipairs(REGION_NAMES) do check(type(name) == "string", "region " .. name) end
  local ids = {}
  for _, region in ipairs(P.REGIONS) do ids[region.id] = region.read == nil end
  eq(ids.savedAtLeastOnce, true, "wSavedAtLeastOnce is static")
  eq(ids.warpNumber, true, "wWarpNumber is static")
  eq(ids.linkBattleStats, true, "sLinkBattleStats is static")
  eq(ids.crystalProfile, true, "sCrystalData's mobile profile is static")
end

for _, v in ipairs(VERSIONS) do
  local S = symsFor(v)
  local fam = v == "crystal" and "crystal" or "gs"
  local runs = {}
  for i, row in ipairs(P.coverage) do
    local r = row.both or row[fam]
    if r then
      local from = S[r[1]]
      local to = r.len and from and from + r.len or S[r[2]]
      check(from ~= nil and to ~= nil and to > from, ("%s coverage row %d resolves"):format(v, i))
      runs[#runs + 1] = { from or 0, to or 0, i }
      check(row.mode == "modeled" or (row.mode == "static" and type(row.why) == "string"),
        ("%s coverage row %d has a mode"):format(v, i))
    end
  end
  table.sort(runs, function(a, b) return a[1] < b[1] end)
  for i = 2, #runs do
    check(runs[i][1] >= runs[i - 1][2], ("%s coverage rows %d and %d do not overlap"):format(v, runs[i - 1][3], runs[i][3]))
  end
  for _, run in ipairs(runs) do
    check(run[1] >= symsFor(v).wGameData and run[2] <= G2.layout(v).sGameDataEnd,
      ("%s coverage row %d sits inside sGameData"):format(v, run[3]))
  end
end

T.finish()
