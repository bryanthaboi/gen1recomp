package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2Syms = require("src.save_convert.Gen2Syms")
local DW = require("src.save_convert.gen2_state.daycare_wild")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local K = require("tests.save_compat._codec")
local Ref = require("tests.save_compat._gen2_reference")

local Save = require("src.core.gen2.Save")
local Mon = require("src.battle.gen2.Mon")
local Breeding = require("src.core.gen2.Breeding")
local Roamers = require("src.core.gen2.Roamers")
local RoamFixture = require("tests.fixtures.gen2_roamers")
local BugContest = require("src.core.gen2.BugContest")
local Specials = require("src.script.gen2.Specials")
local KARP_TABLES = { magikarpLengths = {
  { 110, 1 }, { 310, 2 }, { 710, 4 }, { 2710, 20 }, { 7710, 50 },
  { 17710, 100 }, { 32710, 150 }, { 47710, 150 }, { 57710, 100 },
  { 62710, 50 }, { 64710, 20 }, { 65210, 5 }, { 65410, 2 }, { 65510, 1 },
}, magikarpRecordHolder = "RALPH" }

local VERSIONS = { "gold", "silver", "crystal" }
local REGIONS = { "dayCare", "roamers", "magikarpRecord", "dailyFlags" }


local MOVES = {
  TACKLE = { index = 33, pp = 35 }, GROWL = { index = 45, pp = 40 }, LEECH_SEED = { index = 73, pp = 10 },
  TRANSFORM = { index = 144, pp = 10 }, SPLASH = { index = 150, pp = 40 }, STRING_SHOT = { index = 81, pp = 40 },
  THUNDERSHOCK = { index = 84, pp = 30 }, EMBER = { index = 52, pp = 25 }, BUBBLE = { index = 145, pp = 30 },
  LEER = { index = 43, pp = 30 },
}

local POKEMON = { growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
  linear = 0, constant = 0 } } }
local function species(id, index, o)
  POKEMON[id] = {
    id = id, index = index, dex = index, name = id,
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, specialAttack = 65, specialDefense = 65 },
    types = { "NORMAL", "NORMAL" }, growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = o.genderRatio or 127, eggGroups = o.eggGroups or { "EGG_GROUND", "EGG_GROUND" },
    eggGroupsRaw = o.eggGroupsRaw, eggSteps = o.eggSteps or 20, evolutions = {},
    levelMoves = o.levelMoves or { { level = 1, move = "TACKLE" } }, tmhm = {},
    eggMoves = o.eggMoves or {},
  }
end
-- data/pokemon/egg_moves.asm:5 BulbasaurEggMoves
species("BULBASAUR", 1, { genderRatio = 31, eggGroups = { "EGG_MONSTER", "EGG_PLANT" }, eggGroupsRaw = 0x17,
  eggMoves = { "LIGHT_SCREEN", "SKULL_BASH", "SAFEGUARD", "CHARM", "RAZOR_WIND", "PETAL_DANCE" },
  levelMoves = { { level = 1, move = "TACKLE" }, { level = 4, move = "GROWL" }, { level = 7, move = "LEECH_SEED" } } })
species("CATERPIE", 10, { levelMoves = { { level = 1, move = "TACKLE" }, { level = 1, move = "STRING_SHOT" } } })
species("MAGIKARP", 129, { levelMoves = { { level = 1, move = "SPLASH" } } })
species("DITTO", 132, { genderRatio = 255, eggGroups = { "EGG_DITTO", "EGG_DITTO" },
  levelMoves = { { level = 1, move = "TRANSFORM" } } })
species("DUNSPARCE", 206, {})
for i, id in ipairs({ "RAIKOU", "ENTEI", "SUICUNE" }) do
  species(id, 242 + i, { genderRatio = 255, eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 0xFF,
    levelMoves = { { level = 1, move = "LEER" }, { level = 1, move = ({ "THUNDERSHOCK", "EMBER", "BUBBLE" })[i] } } })
end

local MAP_IDS = {
  ROUTE_29 = { 24, 3 }, ROUTE_30 = { 26, 1 }, ROUTE_31 = { 26, 2 }, ROUTE_32 = { 10, 1 }, ROUTE_33 = { 8, 6 },
  ROUTE_34 = { 11, 1 }, ROUTE_35 = { 10, 2 }, ROUTE_36 = { 10, 3 }, ROUTE_37 = { 10, 4 }, ROUTE_38 = { 1, 12 },
  ROUTE_39 = { 1, 13 }, ROUTE_42 = { 2, 5 }, ROUTE_43 = { 9, 5 }, ROUTE_44 = { 2, 6 }, ROUTE_45 = { 5, 8 },
  ROUTE_46 = { 5, 9 },
}

local DATAS = {}
local function dataFor(v)
  if DATAS[v] then return DATAS[v] end
  local maps = {}
  for id, def in pairs(K.gen2Data.maps) do maps[id] = def end
  for id, gm in pairs(MAP_IDS) do maps[id] = { group = gm[1], map = gm[2] } end
  maps.DARK_CAVE_VIOLET_ENTRANCE = { group = 3, map = v == "crystal" and 78 or 70 }
  DATAS[v] = { items = K.gen2Data.items, maps = maps, pokemon = POKEMON, moves = MOVES }
  return DATAS[v]
end

local function S(v) return v == "crystal" and Gen2Syms.crystal or Gen2Syms.goldSilver end

local function decode(bytes, v) return Gen2Save.decode(bytes, v, dataFor(v)) end
local function encode(save, v, template) return Gen2Save.encode(save, v, template, dataFor(v)) end


local DC_BASE = { gs = 0x2AA8, crystal = 0x2A83 }
local START_TIME = { gs = 0x27E7, crystal = 0x27C3 }
local SWARM_FLAGS = 0x27AE
local O = {
  man = 0x00, nick1 = 0x01, ot1 = 0x0C, mon1 = 0x17, lady = 0x37, steps = 0x38, mother = 0x39,
  nick2 = 0x3A, ot2 = 0x45, mon2 = 0x50, eggNick = 0x70, eggOT = 0x7B, egg = 0x86, second = 0xA6,
  contest = 0xA7, swarmGroup = 0xD7, swarmNumber = 0xD8, fishing = 0xD9, roam = 0xDA,
  curNumber = 0xEF, curGroup = 0xF0, lastNumber = 0xF1, lastGroup = 0xF2, feet = 0xF3, inches = 0xF4,
  karpName = 0xF5, finish = 0x100,
}

local function fam(v) return v == "crystal" and "crystal" or "gs" end
local function rb(s, at) return s:byte(at + 1) end
local function rbe(s, at, n)
  local x = 0
  for i = 0, n - 1 do x = x * 256 + rb(s, at + i) end
  return x
end

for _, v in ipairs({ "gold", "crystal" }) do
  local syms, base = S(v), DC_BASE[fam(v)]
  eq(syms.wDayCareMan, base, v .. ": the reader's day-care base is wDayCareMan")
  eq(syms.wRoamMon1, base + O.roam, v .. ": and wRoamMon1 sits 0xDA in")
  eq(syms.wBestMagikarpLengthFeet, base + O.feet, v .. ": and the Magikarp record 0xF3 in")
  eq(syms.wContestMon, base + O.contest, v .. ": and wContestMon 0xA7 in")
  eq(syms.wBugContestStartTime, START_TIME[fam(v)], v .. ": wBugContestStartTime")
end
eq(Gen2Syms.crystal.wSwarmFlags, SWARM_FLAGS, "crystal: wSwarmFlags")
eq(Gen2Syms.goldSilver.wSwarmFlags, nil, "gold has no wSwarmFlags")

local function readRef(s, v)
  local b = DC_BASE[fam(v)]
  local function mon(at, nickAt, otAt)
    return { species = rb(s, at), level = rb(s, at + 0x1F), exp = rbe(s, at + 8, 3), byte1B = rb(s, at + 0x1B),
             otId = rbe(s, at + 6, 2), move1 = rb(s, at + 2),
             nick = nickAt and Ref.text(s, nickAt, 11), ot = otAt and Ref.text(s, otAt, 11) }
  end
  local out = {
    man = rb(s, b + O.man), lady = rb(s, b + O.lady), steps = rb(s, b + O.steps), mother = rb(s, b + O.mother),
    mon1 = mon(b + O.mon1, b + O.nick1, b + O.ot1), mon2 = mon(b + O.mon2, b + O.nick2, b + O.ot2),
    egg = mon(b + O.egg, b + O.eggNick, b + O.eggOT), second = rb(s, b + O.second),
    contest = mon(b + O.contest), contestHp = rbe(s, b + O.contest + 0x22, 2),
    contestStatus = rb(s, b + O.contest + 0x20),
    swarm = { rb(s, b + O.swarmGroup), rb(s, b + O.swarmNumber) }, fishing = rb(s, b + O.fishing),
    roam = {}, cur = { rb(s, b + O.curGroup), rb(s, b + O.curNumber) },
    last = { rb(s, b + O.lastGroup), rb(s, b + O.lastNumber) },
    feet = rb(s, b + O.feet), inches = rb(s, b + O.inches), karpName = Ref.text(s, b + O.karpName, 11),
    start = { rb(s, START_TIME[fam(v)]), rb(s, START_TIME[fam(v)] + 1), rb(s, START_TIME[fam(v)] + 2),
              rb(s, START_TIME[fam(v)] + 3) },
  }
  for i = 0, 2 do
    local at = b + O.roam + i * 7
    out.roam[i + 1] = { rb(s, at), rb(s, at + 1), rb(s, at + 2), rb(s, at + 3), rb(s, at + 4), rb(s, at + 5),
                        rb(s, at + 6) }
  end
  if v == "crystal" then out.swarmFlags = rb(s, SWARM_FLAGS) end
  return out
end

local function myBytes(s, v)
  local out = {}
  for _, r in ipairs(DW.ranges(S(v))) do out[#out + 1] = s:sub(r[1] + 1, r[2]) end
  return table.concat(out)
end

local function firstDiff(a, b, v)
  for _, r in ipairs(DW.ranges(S(v))) do
    for i = r[1], r[2] - 1 do
      if a:byte(i + 1) ~= b:byte(i + 1) then
        return ("0x%X %02X>%02X"):format(i, a:byte(i + 1), b:byte(i + 1))
      end
    end
  end
  return "none"
end


local ser
ser = function(x)
  if type(x) ~= "table" then return tostring(x) end
  local keys = {}
  for k in pairs(x) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(x[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function nickOf(mon)
  if type(mon.nickname) == "string" and mon.nickname ~= "" then return mon.nickname end
  if mon.isEgg then return "EGG" end
  return mon.name or (POKEMON[mon.species] and POKEMON[mon.species].name) or tostring(mon.species)
end

local function projMon(mon, v, party, names)
  if mon == nil then return nil end
  local moves = {}
  for i, m in ipairs(mon.moves or {}) do
    moves[i] = ("%s:%d:%d"):format(tostring(m.id), m.pp or 0, m.ppUps or 0)
  end
  local se, d = mon.statExp or {}, mon.dvs or {}
  local p = {
    species = mon.species, item = mon.item or 0, moves = moves, otId = mon.otId or 0,
    experience = mon.experience or 0, level = mon.level or 0, pokerus = mon.pokerus or 0,
    statExp = { se.hp or 0, se.attack or 0, se.defense or 0, se.speed or 0, se.special or 0 },
    dvs = { d.attack or 0, d.defense or 0, d.speed or 0, d.special or 0 },
    isEgg = mon.isEgg == true,
  }
  if mon.isEgg then p.eggSteps = mon.eggSteps or 0 else p.happiness = mon.happiness or 70 end
  if v == "crystal" then
    local g = mon.caughtByGender
    p.caught = { (mon.caughtTime or 0) % 4, (mon.caughtLevel or 0) % 64, (mon.caughtLocation or 0) % 128,
                 (g == "girl" or g == "female") and "girl" or "boy" }
  else
    p.caught = mon.caughtData or 0
  end
  if names then p.nickname, p.ot = nickOf(mon), mon.ot or "" end
  if party then
    local st = mon.stats or {}
    p.status, p.hp, p.maxHp = mon.status or "none", mon.hp or 0, mon.maxHp or st.hp or 0
    p.stats = { st.attack or 0, st.defense or 0, st.speed or 0, st.specialAttack or 0, st.specialDefense or 0 }
  end
  return p
end

local function project(save, v)
  local dc = save.dayCare or {}
  local man, lady = dc.man or {}, dc.lady or {}
  local bc = save.bugContest or {}
  local roamers = {}
  for i, slot in ipairs(save.roamers or {}) do
    local d = slot.dvs
    roamers[i] = { species = slot.species, level = slot.level or 0, map = slot.map, hp = slot.hp or 0,
                   dvs = d and { d.attack, d.defense, d.speed, d.special } or "none" }
  end
  local marks = save.roamerMaps or {}
  local flags = {}
  if v == "crystal" then
    for _, id in pairs(DW.SWARM_FLAG_IDS) do flags[id] = (save.engineFlags or {})[id] == true end
  end
  return {
    dayCare = {
      manIntro = man.introSeen == true, ladyIntro = lady.introSeen == true,
      compatible = dc.compatible == true, hasEgg = dc.hasEgg == true, stepsToEgg = dc.stepsToEgg or 0,
      man = projMon(man.mon, v, false, true) or "none", lady = projMon(lady.mon, v, false, true) or "none",
      egg = projMon(dc.egg, v, false, true) or "none",
    },
    bugContest = { caught = projMon(bc.caught, v, true, false) or "none", startTime = bc.startTime or "none" },
    swarm = { map = DW.dunsparceMap(save) or "none", fishing = (save.dailyFlags or {}).fishingSwarm or 0 },
    roamers = roamers,
    roamerMaps = { current = marks.current or "none", last = marks.last or "none" },
    magikarpRecord = save.magikarpRecord or "none",
    swarmFlags = flags,
  }
end

local function sameProjection(label, a, b, v)
  local pa, pb = project(a, v), project(b, v)
  for k, x in pairs(pa) do
    eq(ser(pb[k]), ser(x), label .. " " .. k)
  end
end


local function putBox(b, at, m)
  B.put(b, at, m.species, m.item or 0)
  for i = 1, 4 do B.put(b, at + 1 + i, (m.moves or {})[i] or 0) end
  B.be(b, at + 6, m.otId or 0, 2)
  B.be(b, at + 8, m.exp or 0, 3)
  for i = 0, 4 do B.be(b, at + 0x0B + i * 2, (m.statExp or {})[i + 1] or 0, 2) end
  local dv = m.dvs or { 0, 0, 0, 0 }
  B.put(b, at + 0x15, dv[1] * 16 + dv[2], dv[3] * 16 + dv[4])
  for i = 1, 4 do B.put(b, at + 0x16 + i, (m.pp or {})[i] or 0) end
  B.put(b, at + 0x1B, m.happiness or 70, m.pokerus or 0)
  B.be(b, at + 0x1D, m.caught or 0, 2)
  B.put(b, at + 0x1F, m.level or 5)
end

local function putParty(b, at, m)
  putBox(b, at, m)
  B.put(b, at + 0x20, m.status or 0, m.unused or 0)
  B.be(b, at + 0x22, m.hp or 0, 2)
  B.be(b, at + 0x24, m.maxHp or 0, 2)
  for k = 0, 4 do B.be(b, at + 0x26 + k * 2, (m.stats or {})[k + 1] or 0, 2) end
end

local unpackAll = table.unpack or unpack
local function roam(b, at, bytes) B.put(b, at, unpackAll(bytes)) end

local function realistic(v)
  return function(b)
    local s = S(v)
    local crystal = v == "crystal"
    B.put(b, s.wDayCareMan, 0x81 + 0x20)
    B.putGbName(b, s.wBreedMon1Nickname, "BULBA", 11)
    B.putGbName(b, s.wBreedMon1OT, "ASH", 11)
    putBox(b, s.wBreedMon1, { species = 1, moves = { 33, 45 }, pp = { 35, 40 + 64 }, otId = 0x1234, exp = 1800,
      statExp = { 10, 20, 30, 40, 50 }, dvs = { 10, 12, 7, 9 }, happiness = 88, level = 12,
      caught = crystal and 0x4C05 or 0 })
    B.put(b, s.wDayCareLady, 0x81)
    B.put(b, s.wStepsToEgg, 0xC8, 1)
    B.putGbName(b, s.wBreedMon2Nickname, "DITTO", 11)
    B.putGbName(b, s.wBreedMon2OT, "ASH", 11)
    putBox(b, s.wBreedMon2, { species = 132, moves = { 144 }, pp = { 10 }, otId = 0x1234, exp = 3375,
      dvs = { 3, 4, 5, 6 }, level = 15 })
    B.putGbName(b, s.wEggMonNickname, "EGG", 11)
    B.putGbName(b, s.wEggMonOT, "ASH", 11)
    putBox(b, s.wEggMon, { species = 1, moves = { 33, 45 }, pp = { 35, 40 }, otId = 0x1234, exp = 125,
      dvs = { 2, 12, 9, 1 }, happiness = 20, level = 5 })
    B.put(b, s.wBugContestSecondPartySpecies, 0)
    putParty(b, s.wContestMon, { species = 10, moves = { 33, 81 }, pp = { 35, 40 }, otId = 0x1234, exp = 729,
      dvs = { 15, 14, 13, 12 }, level = 9, status = 0x08, hp = 21, maxHp = 30, stats = { 15, 16, 17, 18, 19 } })
    local swarm = s.wSwarmMapGroup or s.wDunsparceMapGroup
    B.put(b, swarm, 3, crystal and 78 or 70, 1)
    roam(b, s.wRoamMon1, { 243, 40, 2, 5, 0x80, 0xAB, 0xCD })
    roam(b, s.wRoamMon2, { 244, 40, 10, 4, 0, 0, 0 })
    if not crystal then roam(b, s.wRoamMon3, { 0, 40, 0xFF, 0xFF, 0, 0x12, 0x34 }) end
    if crystal then roam(b, s.wRoamMon3, { 0, 0, 0xFF, 0xFF, 0, 0, 0 }) end
    B.put(b, s.wRoamMons_CurMapNumber, 3, 24, 1, 26)
    B.put(b, s.wBestMagikarpLengthFeet, 1, 0)
    B.putGbName(b, s.wMagikarpRecordHoldersName, "GOLD", 11)
    B.put(b, s.wBugContestStartTime, 12, 13, 14, 15)
    if s.wSwarmFlags then B.put(b, s.wSwarmFlags, 0x05) end
  end
end

local function glitch(v)
  return function(b)
    local s = S(v)
    B.put(b, s.wDayCareMan, 0x9F)
    B.putGbName(b, s.wBreedMon1Nickname, "ODD", 11, 0x7F)
    for i = 0, 10 do b[s.wBreedMon1OT + i] = (i * 29 + 3) % 256 end
    putBox(b, s.wBreedMon1, { species = 252, moves = { 33, 0, 45, 0 }, pp = { 35, 9, 40, 7 }, otId = 0xBEEF,
      exp = 0xFFFFFF, dvs = { 15, 0, 15, 0 }, happiness = 255, pokerus = 0x13, level = 200, caught = 0xFFFF })
    B.put(b, s.wDayCareLady, 0x7E)
    for i = 0, 53 do b[s.wBreedMon2Nickname + i] = (i * 7 + 1) % 256 end
    B.put(b, s.wStepsToEgg, 0, 0xEE)
    for i = 0, 53 do b[s.wEggMonNickname + i] = (i * 13 + 5) % 256 end
    b[s.wEggMon] = 0
    B.put(b, s.wBugContestSecondPartySpecies, 0x42)
    putParty(b, s.wContestMon, { species = 10, moves = { 0, 81, 0, 33 }, pp = { 1, 2, 3, 4 }, otId = 1, exp = 2,
      dvs = { 1, 2, 3, 4 }, level = 0, status = 0xFF, unused = 0xA5, hp = 0xFFFF, maxHp = 1,
      stats = { 1, 2, 3, 4, 5 } })
    local swarm = s.wSwarmMapGroup or s.wDunsparceMapGroup
    B.put(b, swarm, 77, 99, 7)
    roam(b, s.wRoamMon1, { 250, 99, 0xFF, 0x00, 0, 0, 0 })
    roam(b, s.wRoamMon2, { 0, 0, 0x33, 0x44, 0, 0, 0 })
    roam(b, s.wRoamMon3, { 0, 0, 0xFF, 0xFF, 0, 0, 0 })
    B.put(b, s.wRoamMons_CurMapNumber, 0, 0, 0x99, 0x77)
    B.put(b, s.wBestMagikarpLengthFeet, 3, 6)
    B.putGbName(b, s.wMagikarpRecordHoldersName, "RALPH", 11, 0xEE)
    B.put(b, s.wBugContestStartTime, 0xFF, 0x00, 0xFE, 0x01)
    if s.wSwarmFlags then B.put(b, s.wSwarmFlags, 0xF4) end
  end
end

local function fresh(v)
  return function(b)
    local s = S(v)
    for _, at in ipairs({ s.wRoamMon1, s.wRoamMon2, s.wRoamMon3 }) do B.put(b, at + 2, 0xFF, 0xFF) end
    B.put(b, s.wBestMagikarpLengthFeet, 3, 6)
    local codes = B.gbText("RALPH")
    for k, c in ipairs(codes) do b[s.wMagikarpRecordHoldersName + k - 1] = c end
    b[s.wMagikarpRecordHoldersName + 5] = 0x50
  end
end


for _, v in ipairs({ "gold", "crystal" }) do
  local syms = S(v)
  local owned = {}
  for _, row in ipairs(DW.coverage) do
    local spec = row.both or (v == "crystal" and row.crystal or row.gs)
    if spec then
      local from = assert(syms[spec[1]], spec[1])
      local to = spec.len and (from + spec.len) or assert(syms[spec[2]], tostring(spec[2]))
      for i = from, to - 1 do
        check(not owned[i], ("%s: coverage byte 0x%X claimed once"):format(v, i))
        owned[i] = true
      end
    end
  end
  local want, n = {}, 0
  for _, r in ipairs(DW.ranges(syms)) do
    for i = r[1], r[2] - 1 do want[i] = true; n = n + 1 end
  end
  local got = 0
  for i in pairs(owned) do
    got = got + 1
    check(want[i], ("%s: coverage byte 0x%X is inside the window"):format(v, i))
  end
  eq(got, n, v .. ": coverage tiles wDayCareMan..wMagikarpRecordHoldersName+11 plus the carve-outs")
  eq(syms.wMagikarpRecordHoldersName + 11 - syms.wDayCareMan, 0x100, v .. ": the window is 256 bytes")
end


for _, v in ipairs(VERSIONS) do
  for _, case in ipairs({ { "realistic", realistic(v) }, { "glitch", glitch(v) }, { "newgame", fresh(v) } }) do
    local label = ("r1 %s %s %s"):format(v, case[1], table.concat(REGIONS, "/"))
    local bytes = G2.build({ version = v, patch = case[2] })
    local save, err = decode(bytes, v)
    check(save ~= nil, label .. ": imports -- " .. tostring(err))
    if save then
      local out, xerr = encode(save, v, bytes)
      check(out ~= nil, label .. ": exports onto its template -- " .. tostring(xerr))
      if out then
        eq(out, bytes, label .. ": byte-identical with the template, first diff " .. firstDiff(bytes, out, v))
      end
      save.rawImport = nil
      local loose, ferr = encode(save, v, nil)
      check(loose ~= nil, label .. ": exports without a template -- " .. tostring(ferr))
      if loose then
        eq(myBytes(loose, v), myBytes(bytes, v),
          label .. ": the templateless export reproduces every owned byte, first diff " .. firstDiff(bytes, loose, v))
        local back = assert(decode(loose, v))
        sameProjection(label .. " reimport", save, back, v)
        back.rawImport = nil
        local again = encode(back, v, nil)
        eq(again, loose, label .. ": templateless export is a fixed point")
      end
    end
  end
end

do
  local s = S("gold")
  local save = assert(decode(G2.build({ version = "gold", patch = realistic("gold") }), "gold"))
  local dc = save.dayCare
  eq(dc.man.mon.species, "BULBASAUR", "realistic: the man's mon")
  eq(dc.man.mon.nickname, "BULBA", "with its nickname")
  eq(dc.man.mon.ot, "ASH", "and OT")
  eq(dc.man.introSeen, true, "DAYCARE_INTRO_SEEN_F on the man")
  eq(dc.compatible, true, "DAYCAREMAN_MONS_COMPATIBLE_F")
  eq(dc.hasEgg, false, "no egg ready")
  eq(dc.lady.mon.species, "DITTO", "the lady's mon")
  eq(dc.stepsToEgg, 0xC8, "wStepsToEgg")
  eq(dc.motherOrNonDitto, 1, "wBreedMotherOrNonDitto rides raw")
  eq(dc.egg.isEgg, true, "the egg is an egg")
  eq(dc.egg.eggSteps, 20, "whose happiness byte is its hatch counter")
  eq(dc.egg.happiness, Gen2Save.HATCH_HAPPINESS, "and happiness is the hatch value")
  eq(save.bugContest.caught.species, "CATERPIE", "the contest catch")
  eq(save.bugContest.caught.status, "psn", "keeps its party status")
  eq(save.bugContest.caught.hp, 21, "and HP")
  eq(ser(save.bugContest.startTime), ser({ day = 12, hour = 13, minute = 14, second = 15 }), "contest start time")
  eq(save.swarmMap, "DARK_CAVE_VIOLET_ENTRANCE", "the Gold swarm pair")
  eq(save.swarmMaps.DUNSPARCE, "DARK_CAVE_VIOLET_ENTRANCE", "keyed the way Roamers.Swarm reads it")
  eq(save.dailyFlags.fishingSwarm, 1, "wFishingSwarmFlag")
  eq(#save.roamers, 3, "three Gold roamers")
  eq(save.roamers[1].map, "ROUTE_42", "Raikou's map")
  eq(save.roamers[1].hp, 0x80, "Raikou's banked HP")
  eq(save.roamers[1].dvs.attack, 10, "Raikou's DVs")
  eq(save.roamers[2].dvs, nil, "an unrolled roamer has no DVs")
  eq(save.roamers[3].species, nil, "a caught Suicune has no species")
  eq(save.roamers[3].map, nil, "nor a map")
  eq(save.roamers[3].level, 40, "but keeps its level")
  eq(save.roamerMaps.current, "ROUTE_29", "wRoamMons_CurMap")
  eq(save.roamerMaps.last, "ROUTE_30", "wRoamMons_LastMap")
  eq(ser(save.magikarpRecord), ser({ feet = 1, inches = 0, name = "GOLD" }), "the Magikarp record")
  eq(save[DW.CARRIER], nil, "a clean cart needs no raw carrier")
  local stale = assert(decode(G2.build({ version = "gold", patch = function(b, L)
    realistic("gold")(b, L)
    b[s.wBugContestSecondPartySpecies] = 0x9B
  end }), "gold"))
  check(type(stale[DW.CARRIER]) == "string", "a stale wBugContestSecondPartySpecies rides the carrier")
  local c = assert(decode(G2.build({ version = "crystal", patch = realistic("crystal") }), "crystal"))
  eq(#c.roamers, 2, "Crystal's InitRoamMons fills two slots")
  eq(c.engineFlags[96], true, "SWARMFLAGS_BUENAS_PASSWORD_F lands on ENGINE_BUENAS_PASSWORD_2")
  eq(c.engineFlags[160], true, "SWARMFLAGS_DUNSPARCE_SWARM_F on ENGINE_DUNSPARCE_SWARM")
  eq(c.engineFlags[97], nil, "the clear bits stay clear")
  eq(c.dayCare.man.mon.caughtLevel, 0x0C, "Crystal breed mons keep caught data")
  local n = assert(decode(G2.build({ version = "gold", patch = fresh("gold") }), "gold"))
  eq(n.dayCare, nil, "an untouched day care imports as no record")
  eq(n.roamers, nil, "no roamers before InitRoamMons")
  eq(n.magikarpRecord, nil, "RALPH's 3'6\" is no record")
  eq(n.bugContest, nil, "no contest")
  eq(n[DW.CARRIER], nil, "and a NewGame image needs no carrier")
  local g = assert(decode(G2.build({ version = "gold", patch = glitch("gold") }), "gold"))
  check(type(g[DW.CARRIER]) == "string", "glitch bytes ride the raw carrier")
  eq(g.dayCare.man.mon.species, 252, "an unnamed breed species stays a number")
  eq(g.dayCare.lady.mon, nil, "a lady byte without DAYCARELADY_HAS_MON_F has no mon")
  eq(g.dayCare.egg, nil, "a zero egg species is no egg")
  eq(g.roamers[1].species, 250, "an unnamed roamer species stays a number")
  eq(#g.roamers, 1, "pristine-looking trailing slots are not roamers")
  eq(s.wDayCareMan ~= nil, true, "layout sanity")
end


local function rngOf(list)
  local i = 0
  return function()
    i = i + 1
    return list[(i - 1) % #list + 1]
  end
end

local function pick(n) return function(m) return n % m end end

local function engineSave(v)
  local data = dataFor(v)
  local save = Save.newGame({ playerName = "GOLD", trainerId = 0x4321 })
  save.version = v
  save.position = { map = K.GEN2_MAP, x = 4, y = 3 }
  save.player.money = 50000
  save.party = {
    Mon.new(data, "BULBASAUR", 12, { dvs = { attack = 10, defense = 12, speed = 7, special = 9 }, nickname = "BULBA" }),
    Mon.new(data, "DITTO", 15, { dvs = { attack = 3, defense = 4, speed = 5, special = 6 } }),
    Mon.new(data, "MAGIKARP", 10, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } }),
  }
  for _, m in ipairs(save.party) do Mon.stampOT(save, m); m.otId = 0x4321 end
  local rng = rngOf({ 10, 200, 0x5A, 0xA5, 3, 7 })
  assert(Breeding.deposit(data, save, "man", 1, { rng = rng }))
  assert(Breeding.deposit(data, save, "lady", 1, { rng = rng }))
  Breeding.takeIntro(save, "man")
  for _ = 1, 37 do Breeding.step(data, save, rng) end
  BugContest.start(save, { day = 33, hour = 9, minute = 30, second = 5 })
  BugContest.catch(save, Mon.new(data, "CATERPIE", 9, { dvs = { attack = 1, defense = 2, speed = 3, special = 4 } }))
  local enc = RoamFixture.encounters(v)
  Roamers.init(save, { encounters = enc })
  Roamers.beginBattle(save, 1, data)
  Roamers.endBattle(save, 1, "run", 77, "ROUTE_29", pick(5), enc)
  Roamers.endBattle(save, 2, "caught")
  Roamers.update(save, "ROUTE_30", pick(9), enc)
  Roamers.Swarm.set(save, "DARK_CAVE_VIOLET_ENTRANCE")
  Specials.HANDLERS.ActivateFishingSwarm({ specials = { save = function() return save end }, scriptVar = 2 })
  local karp = save.party[1]
  karp.otId = 0
  Specials.HANDLERS.CheckMagikarpLength({ scriptVar = 0, setStringBuffer = function() end,
    specials = { save = function() return save end, selectPartyMon = function(_, done) done(1, karp) end,
      data = function() return { gen2EventTables = KARP_TABLES } end } })
  if v == "crystal" then
    save.engineFlags = save.engineFlags or {}
    save.engineFlags[160], save.engineFlags[97] = true, true
  end
  return save
end

for _, v in ipairs(VERSIONS) do
  local label = "r2 " .. v
  local save = engineSave(v)
  check(save.dayCare.compatible ~= nil and save.dayCare.egg ~= nil, label .. ": the engine bred an egg")
  check(save.magikarpRecord ~= nil, label .. ": the guru wrote a record")
  check(save.bugContest.caught ~= nil and save.bugContest.startTime ~= nil, label .. ": the contest ran")
  local out, err = encode(save, v, nil)
  check(out ~= nil, label .. ": exports -- " .. tostring(err))
  if out then
    local r = readRef(out, v)
    local dc = save.dayCare
    eq(r.man, 1 + (dc.compatible and 32 or 0) + (dc.hasEgg and 64 or 0) + 128, label .. ": wDayCareMan bits")
    eq(r.lady, 1, label .. ": wDayCareLady bits")
    eq(r.steps, dc.stepsToEgg, label .. ": wStepsToEgg")
    eq(r.mon1.species, 1, label .. ": breed mon 1 species")
    eq(r.mon1.nick, "BULBA", label .. ": breed mon 1 nickname")
    eq(r.mon1.ot, "GOLD", label .. ": breed mon 1 OT")
    eq(r.mon1.exp, dc.man.mon.experience, label .. ": breed mon 1 grew in the day care")
    eq(r.mon1.level, 12, label .. ": at its deposited level")
    eq(r.mon2.species, 132, label .. ": breed mon 2 species")
    eq(r.mon2.nick, "DITTO", label .. ": an un-nicknamed breed mon writes its species name")
    eq(r.egg.species, 1, label .. ": the egg species")
    eq(r.egg.byte1B, dc.egg.eggSteps, label .. ": the egg's hatch counter")
    eq(r.egg.nick, "EGG", label .. ": EGG")
    eq(r.egg.ot, "GOLD", label .. ": the player is the egg's OT")
    eq(r.egg.otId, 0x4321, label .. ": and its ID")
    eq(r.contest.species, 10, label .. ": wContestMon")
    eq(r.contestHp, save.bugContest.caught.hp, label .. ": the contest mon's HP")
    eq(ser(r.start), ser({ 33, 9, 30, 5 }), label .. ": wBugContestStartTime")
    eq(ser(r.swarm), ser({ 3, v == "crystal" and 78 or 70 }), label .. ": the Dunsparce swarm pair")
    eq(r.fishing, 2, label .. ": FISHSWARM_REMORAID")
    local s1 = save.roamers[1]
    local ids = MAP_IDS[s1.map]
    eq(ser(r.roam[1]), ser({ 243, 40, ids[1], ids[2], 77, s1.dvs.attack * 16 + s1.dvs.defense,
      s1.dvs.speed * 16 + s1.dvs.special }), label .. ": Raikou's roam_struct")
    eq(ser(r.roam[2]), ser({ 0, 40, 0xFF, 0xFF, 0, 0, 0 }), label .. ": a caught Entei")
    if v == "crystal" then
      eq(ser(r.roam[3]), ser({ 0, 0, 0xFF, 0xFF, 0, 0, 0 }), label .. ": Crystal's unused third slot")
    else
      local ids3 = MAP_IDS[save.roamers[3].map]
      eq(ser(r.roam[3]), ser({ 245, 40, ids3[1], ids3[2], 0, 0, 0 }), label .. ": Suicune")
    end
    eq(ser(r.cur), ser(MAP_IDS.ROUTE_30), label .. ": wRoamMons_CurMap")
    eq(ser(r.last), ser(MAP_IDS.ROUTE_29), label .. ": wRoamMons_LastMap")
    eq(r.feet, save.magikarpRecord.feet, label .. ": record feet")
    eq(r.inches, save.magikarpRecord.inches, label .. ": record inches")
    eq(r.karpName, "GOLD", label .. ": record holder")
    if v == "crystal" then eq(r.swarmFlags, 0x06, label .. ": wSwarmFlags bits 1 and 2") end
    local back, ierr = decode(out, v)
    check(back ~= nil, label .. ": reimports -- " .. tostring(ierr))
    if back then
      sameProjection(label, save, back, v)
      back.rawImport = nil
      local again = encode(back, v, nil)
      eq(again, out, label .. ": export -> import -> export is a fixed point, first diff "
        .. (again and firstDiff(out, again, v) or "export failed"))
    end
  end
end

do
  local save = engineSave("gold")
  save.bugContest.stash = { save.party[1] }
  local out, err = encode(save, "gold", nil)
  eq(out, nil, "a contest save with dropped-off mons is refused")
  check(tostring(err):find("Bug%-Catching Contest") ~= nil, "naming why: " .. tostring(err))
  save = engineSave("gold")
  save.roamers[4] = { species = "SUICUNE", level = 40, hp = 0 }
  out, err = encode(save, "gold", nil)
  eq(out, nil, "a fourth roamer is refused")
  save = engineSave("gold")
  save.roamers[1].map = "NOWHERE"
  out, err = encode(save, "gold", nil)
  eq(out, nil, "a roamer on a map the game cannot name is refused")
  check(tostring(err):find("NOWHERE") ~= nil, "naming the map: " .. tostring(err))
  save = engineSave("gold")
  save.dayCare.stepsToEgg = 300
  out = encode(save, "gold", nil)
  eq(out, nil, "an egg countdown past one byte is refused")
end


for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  local label = "change " .. v
  local syms = S(v)
  local bytes = G2.build({ version = v, patch = realistic(v) })
  local data = dataFor(v)
  local save = assert(decode(bytes, v))
  save.player.money = 99999
  local manBefore = bytes:sub(syms.wBreedMon1 + 1, syms.wBreedMon1 + 32)
  assert(Breeding.withdraw(data, save, "lady"))
  Breeding.dayCareStep(data, save, rngOf({ 0 }))
  Roamers.endBattle(save, 1, "win")
  save.dailyFlags.swarm = nil
  Roamers.Swarm.check(save)
  BugContest.start(save, { day = 100, hour = 23, minute = 59, second = 58 })
  local karp = Mon.new(data, "MAGIKARP", 10, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  karp.otId = 0
  Specials.HANDLERS.CheckMagikarpLength({ scriptVar = 0, setStringBuffer = function() end,
    specials = { save = function() return save end, selectPartyMon = function(_, done) done(1, karp) end,
      data = function() return { gen2EventTables = KARP_TABLES } end } })
  local feet, inches = Specials.magikarpLength(KARP_TABLES.magikarpLengths, karp.otId,
    Specials.dvWord(karp.dvs))
  if v == "crystal" then save.engineFlags[96] = nil; save.engineFlags[161] = true end
  local out, err = encode(save, v, bytes)
  check(out ~= nil, label .. ": exports -- " .. tostring(err))
  if out then
    -- pokecrystal engine/events/daycare.asm:87
    eq(rb(out, syms.wDayCareLady) % 2, 0, label .. ": DAYCARELADY_HAS_MON_F cleared")
    eq(math.floor(rb(out, syms.wDayCareMan) / 32) % 2, 0, label .. ": DAYCAREMAN_MONS_COMPATIBLE_F cleared")
    eq(rb(out, syms.wDayCareMan) % 2, 1, label .. ": the man keeps his mon")
    -- pokecrystal engine/events/happiness_egg.asm:142
    eq(rbe(out, syms.wBreedMon1Exp, 3), 1801, label .. ": DayCareStep's +1 exp")
    eq(out:sub(syms.wBreedMon1 + 1, syms.wBreedMon1 + 8), manBefore:sub(1, 8), label .. ": the rest untouched")
    eq(rb(out, syms.wBreedMon2Species), 132, label .. ": a withdrawn mon's bytes stay behind")
    -- pokecrystal engine/battle/core.asm:8620
    eq(ser({ rb(out, syms.wRoamMon1Species), rb(out, syms.wRoamMon1Level), rb(out, syms.wRoamMon1MapGroup),
      rb(out, syms.wRoamMon1MapNumber), rb(out, syms.wRoamMon1HP), rbe(out, syms.wRoamMon1DVs, 2) }),
      ser({ 0, 40, 0xFF, 0xFF, 0, 0xABCD }), label .. ": a beaten roamer")
    -- pokegold engine/events/specials.asm:307
    local swarm = syms.wSwarmMapGroup or syms.wDunsparceMapGroup
    eq(ser({ rb(out, swarm), rb(out, swarm + 1), rb(out, syms.wFishingSwarmFlag) }),
      ser(v == "crystal" and { rb(bytes, swarm), rb(bytes, swarm + 1), rb(bytes, syms.wFishingSwarmFlag) } or { 0, 0, 0 }),
      label .. (v == "crystal" and ": inactive Crystal swarm bytes retained" or ": Gold/Silver CheckSwarmFlag clears bytes"))
    -- pokecrystal engine/events/bug_contest/contest.asm:1
    eq(rb(out, syms.wContestMon), 0, label .. ": GiveParkBalls clears wContestMon")
    eq(rb(out, syms.wContestMon + 1), rb(bytes, syms.wContestMon + 1), label .. ": and only its species")
    -- pokecrystal engine/overworld/time.asm:144
    eq(ser({ rb(out, syms.wBugContestStartTime), rb(out, syms.wBugContestStartTime + 1),
      rb(out, syms.wBugContestStartTime + 2), rb(out, syms.wBugContestStartTime + 3) }), ser({ 100, 23, 59, 58 }),
      label .. ": StartBugContestTimer's stamp")
    -- pokecrystal engine/events/magikarp.asm:43
    eq(ser({ rb(out, syms.wBestMagikarpLengthFeet), rb(out, syms.wBestMagikarpLengthInches) }),
      ser({ feet, inches }), label .. ": the new Magikarp record")
    eq(Ref.text(out, syms.wMagikarpRecordHoldersName, 11), "ASH", label .. ": and its holder")
    if v == "crystal" then
      eq(rb(out, syms.wSwarmFlags), 0x0C, label .. ": wSwarmFlags follows the engine flags")
    end
    eq(out:sub(syms.wRoamMon2 + 1, syms.wRoamMon2 + 7), bytes:sub(syms.wRoamMon2 + 1, syms.wRoamMon2 + 7),
      label .. ": an untouched roamer keeps its bytes")
    local back = assert(decode(out, v))
    sameProjection(label .. " reimport", save, back, v)
  end
end

for _, v in ipairs(VERSIONS) do
  local label = "collect " .. v
  local syms = S(v)
  local bytes = G2.build({ version = v, patch = function(b, L)
    realistic(v)(b, L)
    B.put(b, syms.wDayCareMan, 0x81 + 0x40)
    B.put(b, syms.wDayCareLady, 0x00)
  end })
  local save = assert(decode(bytes, v))
  check(Breeding.collectEgg(dataFor(v), save), label .. ": the man hands the egg over")
  local out = assert(encode(save, v, bytes))
  -- pokecrystal engine/events/daycare.asm:398
  eq(math.floor(rb(out, syms.wDayCareMan) / 64) % 2, 0, label .. ": DAYCAREMAN_HAS_EGG_F cleared")
  eq(rb(out, syms.wEggMon), 0, label .. ": the egg slot is empty once nothing rebuilds it")
  eq(rb(out, syms.wPartySpecies + 1), G2.EGG, label .. ": and the egg is in the party")
  local back = assert(decode(out, v))
  eq(back.dayCare.egg, nil, label .. ": reimports with no day-care egg")
end


do
  local hits = {}
  local p = io.popen("grep -rn 'motherOrNonDitto' src")
  for line in p:lines() do hits[#hits + 1] = line end
  p:close()
  check(#hits > 0, "the scan finds the codec's own use")
  for _, line in ipairs(hits) do
    check(line:find("^src/save_convert/") ~= nil,
      "only the codec touches dayCare.motherOrNonDitto, it is the cart's own carried byte: " .. line)
  end
end

T.finish()
