local M = {}
local Syms = require("src.save_convert.Gen2Syms")
local Gen2EngineFlags = require("src.save_convert.Gen2EngineFlags")

local NAME = 11
local BOX = 32
local PARTY = 48
local ROAM = 7
local NAMED_MON = NAME + NAME + BOX

M.CARRIER = "cartDayCareWild"

-- pokecrystal constants/ram_constants.asm:349
local MAN_HAS_MON, MAN_COMPATIBLE, MAN_HAS_EGG, INTRO_SEEN = 0, 5, 6, 7
local LADY_HAS_MON = 0
-- pokecrystal engine/pokemon/breeding.asm:224
local HATCH_HAPPINESS = 0x78
-- pokecrystal constants/battle_constants.asm:162
local SLP_MASK = 7
local STATUS_BITS = { { 3, "psn" }, { 4, "brn" }, { 5, "frz" }, { 6, "par" } }
-- pokecrystal data/events/engine_flags.asm:126-127, :199-200
local SWARM_FLAGS = {
  [0] = "ENGINE_BUENAS_PASSWORD_2", [1] = "ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON",
  [2] = "ENGINE_DUNSPARCE_SWARM", [3] = "ENGINE_YANMA_SWARM",
}
M.SWARM_FLAG_IDS = {}
for bitN, name in pairs(SWARM_FLAGS) do M.SWARM_FLAG_IDS[bitN] = Gen2EngineFlags.id("crystal", name) end
-- pokecrystal engine/menus/intro_menu.asm:268
local KARP_FEET, KARP_INCHES, KARP_NAME = 3, 6, "RALPH"
local PRISTINE_ROAMER = { 0, 0, 0xFF, 0xFF, 0, 0, 0 }

M.coverage = {
  { both = { "wDayCareMan", "wBugContestSecondPartySpecies" }, mode = "modeled",
    keys = { "dayCare.man", "dayCare.lady", "dayCare.compatible", "dayCare.hasEgg", "dayCare.stepsToEgg",
             "dayCare.motherOrNonDitto", "dayCare.egg" },
    asm = "pokecrystal ram/wram.asm:3448" },
  { both = { "wBugContestSecondPartySpecies", "wContestMonStructEnd" }, mode = "modeled",
    keys = { "bugContest.caught", "bugContest.stash" }, asm = "pokecrystal ram/wram.asm:3479" },
  { gs = { "wSwarmMapGroup", len = 3 }, crystal = { "wDunsparceMapGroup", len = 3 }, mode = "modeled",
    keys = { "swarmMaps.DUNSPARCE", "swarmMap", "dailyFlags.fishingSwarm" },
    asm = "pokecrystal ram/wram.asm:3482" },
  { both = { "wRoamMon1", "wRoamMons_CurMapNumber" }, mode = "modeled", keys = { "roamers" },
    asm = "pokecrystal ram/wram.asm:3486" },
  { both = { "wRoamMons_CurMapNumber", len = 4 }, mode = "modeled", keys = { "roamerMaps" },
    asm = "pokecrystal ram/wram.asm:3490" },
  { both = { "wBestMagikarpLengthFeet", len = 13 }, mode = "modeled", keys = { "magikarpRecord" },
    asm = "pokecrystal ram/wram.asm:3495" },
  { both = { "wBugContestStartTime", len = 4 }, mode = "modeled", keys = { "bugContest.startTime" },
    asm = "pokecrystal ram/wram.asm:3334" },
  { crystal = { "wSwarmFlags", len = 1 }, mode = "modeled",
    keys = {
      "engineFlags[" .. M.SWARM_FLAG_IDS[0] .. "]", "engineFlags[" .. M.SWARM_FLAG_IDS[1] .. "]",
      "engineFlags[" .. M.SWARM_FLAG_IDS[2] .. "]", "engineFlags[" .. M.SWARM_FLAG_IDS[3] .. "]",
    },
    asm = "pokecrystal ram/wram.asm:3320" },
}

local function swarmAt(S) return S.wSwarmMapGroup or S.wDunsparceMapGroup end

function M.ranges(S)
  local out = {
    { S.wDayCareMan, S.wMagikarpRecordHoldersName + NAME },
    { S.wBugContestStartTime, S.wBugContestStartTime + 4 },
  }
  if S.wSwarmFlags then out[#out + 1] = { S.wSwarmFlags, S.wSwarmFlags + 1 } end
  return out
end

local function rangeBytes(S)
  local n = 0
  for _, r in ipairs(M.ranges(S)) do n = n + r[2] - r[1] end
  return n
end

function M.dailyReset(save)
  if save.version ~= "crystal" then return end
  local raw = save[M.CARRIER]
  if type(raw) ~= "string" or #raw ~= rangeBytes(Syms.crystal) * 2 or raw:find("[^%x]") then return end
  save[M.CARRIER] = raw:sub(1, -3) .. "00"
end

local function byteValue(u, v, what)
  local n = tonumber(v)
  if not n or n ~= math.floor(n) or n < 0 or n > 255 then
    u.refuse(("%s %s does not fit the cartridge's one byte"):format(what, tostring(v)))
  end
  return n
end

local function sameBytes(a, b, n)
  for i = 0, n - 1 do
    if (a[i] or 0) ~= (b[i] or 0) then return false end
  end
  return true
end

local function zeros(n)
  local b = {}
  for i = 0, n - 1 do b[i] = 0 end
  return b
end

local function copyInto(t, at, b, n, skip)
  for i = 0, n - 1 do
    if i ~= skip then t[at + i] = b[i] end
  end
end

local function mapName(ctx, group, number)
  return ctx.x.maps[group * 256 + number]
end

local function mapIds(ctx, mapId, what)
  local ids = ctx.x.mapIds[mapId]
  if not ids then
    ctx.util.refuse(("%s %s has no map group and number in this game's data, so it cannot be "
      .. "written to a cartridge"):format(what, tostring(mapId)))
  end
  return ids[1], ids[2]
end

-- pokecrystal engine/menus/intro_menu.asm:164
function M.defaults(ctx, t)
  local S, u = ctx.S, ctx.util
  for _, r in ipairs(M.ranges(S)) do
    for i = r[1], r[2] - 1 do t[i] = 0 end
  end
  for _, at in ipairs({ S.wRoamMon1, S.wRoamMon2, S.wRoamMon3 }) do
    t[at + 2], t[at + 3] = 0xFF, 0xFF
  end
  t[S.wBestMagikarpLengthFeet] = KARP_FEET
  t[S.wBestMagikarpLengthInches] = KARP_INCHES
  local codes = u.encodeText(KARP_NAME, NAME)
  for k, c in ipairs(codes) do t[S.wMagikarpRecordHoldersName + k - 1] = c end
  t[S.wMagikarpRecordHoldersName + #codes] = 0x50
end


local function nicknameOf(ctx, mon)
  local nick = mon.nickname
  if type(nick) == "string" and nick ~= "" then return nick end
  if mon.isEgg then return "EGG" end
  if type(mon.name) == "string" and mon.name ~= "" then return mon.name end
  local def = ctx.x.pokemonDefs[mon.species]
  if type(def) == "table" and type(def.name) == "string" then return def.name end
  if type(mon.species) == "string" then return mon.species end
  return "?"
end

local function markEgg(mon)
  mon.isEgg = true
  mon.eggSteps = mon.happiness
  mon.happiness = HATCH_HAPPINESS
end

local function decodeNamedMon(ctx, t, nickAt, otAt, at, egg)
  local u = ctx.util
  local mon = u.decodeBoxMon(t, at, ctx.x, ctx.crystal)
  if egg then markEgg(mon) end
  mon.nickname = u.text(t, nickAt, NAME)
  mon.ot = u.text(t, otAt, NAME)
  return mon
end

local function boxBytes(ctx, mon)
  local b = zeros(BOX)
  ctx.util.putBoxMon(b, 0, mon, ctx.x, ctx.crystal)
  return b
end

local function putStruct(ctx, t, at, mon, cur, size, bytesOf)
  if mon.species == nil and (cur == nil or cur.species == nil) then return end
  local want = bytesOf(ctx, mon)
  if cur and cur.species ~= nil and sameBytes(want, bytesOf(ctx, cur), size) then return end
  copyInto(t, at, want, size, size == PARTY and 0x21 or nil)
end

local function putNamedMon(ctx, t, nickAt, otAt, at, mon, egg)
  local u = ctx.util
  if type(mon) ~= "table" then u.refuse("a day-care slot holds something that is not a Pokemon") end
  putStruct(ctx, t, at, mon, decodeNamedMon(ctx, t, nickAt, otAt, at, egg), BOX, boxBytes)
  u.putName(t, nickAt, nicknameOf(ctx, mon), NAME)
  u.putName(t, otAt, mon.ot or "", NAME)
end

local function decodeStatus(byte)
  local turns = byte % (SLP_MASK + 1)
  if turns > 0 then return "slp", turns end
  for _, row in ipairs(STATUS_BITS) do
    if math.floor(byte / 2 ^ row[1]) % 2 == 1 then return row[2], nil end
  end
  return nil, nil
end

local function encodeStatus(name, turns)
  if name == "slp" then return math.min(math.max(turns or 1, 1), SLP_MASK) end
  for _, row in ipairs(STATUS_BITS) do
    if row[2] == name then return 2 ^ row[1] end
  end
  return 0
end

local function decodePartyMon(ctx, t, at)
  local u = ctx.util
  local mon = u.decodeBoxMon(t, at, ctx.x, ctx.crystal)
  mon.status, mon.statusTurns = decodeStatus(u.u8(t, at + 0x20))
  mon.hp = u.be(t, at + 0x22, 2)
  mon.maxHp = u.be(t, at + 0x24, 2)
  mon.stats = {
    hp = mon.maxHp,
    attack = u.be(t, at + 0x26, 2), defense = u.be(t, at + 0x28, 2),
    speed = u.be(t, at + 0x2A, 2), specialAttack = u.be(t, at + 0x2C, 2),
    specialDefense = u.be(t, at + 0x2E, 2),
  }
  return mon
end

local function partyBytes(ctx, mon)
  local u = ctx.util
  local b = zeros(PARTY)
  u.putBoxMon(b, 0, mon, ctx.x, ctx.crystal)
  u.putU8(b, 0x20, encodeStatus(mon.status, mon.statusTurns))
  u.putBE(b, 0x22, mon.hp or 0, 2)
  local st = mon.stats or {}
  u.putBE(b, 0x24, mon.maxHp or st.hp or 0, 2)
  u.putBE(b, 0x26, st.attack or 0, 2); u.putBE(b, 0x28, st.defense or 0, 2)
  u.putBE(b, 0x2A, st.speed or 0, 2); u.putBE(b, 0x2C, st.specialAttack or 0, 2)
  u.putBE(b, 0x2E, st.specialDefense or 0, 2)
  return b
end


function M.readDayCare(ctx, t)
  local S, u = ctx.S, ctx.util
  local man, lady = u.u8(t, S.wDayCareMan), u.u8(t, S.wDayCareLady)
  local dc = {
    man = { introSeen = u.bit(man, INTRO_SEEN) },
    lady = { introSeen = u.bit(lady, INTRO_SEEN) },
    compatible = u.bit(man, MAN_COMPATIBLE),
    hasEgg = u.bit(man, MAN_HAS_EGG),
    stepsToEgg = u.u8(t, S.wStepsToEgg),
    motherOrNonDitto = u.u8(t, S.wBreedMotherOrNonDitto),
  }
  if u.bit(man, MAN_HAS_MON) then
    dc.man.mon = decodeNamedMon(ctx, t, S.wBreedMon1Nickname, S.wBreedMon1OT, S.wBreedMon1)
  end
  if u.bit(lady, LADY_HAS_MON) then
    dc.lady.mon = decodeNamedMon(ctx, t, S.wBreedMon2Nickname, S.wBreedMon2OT, S.wBreedMon2)
  end
  if u.u8(t, S.wEggMon) ~= 0 then
    dc.egg = decodeNamedMon(ctx, t, S.wEggMonNickname, S.wEggMonOT, S.wEggMon, true)
  end
  if not (dc.man.mon or dc.lady.mon or dc.egg or dc.man.introSeen or dc.lady.introSeen
      or dc.compatible or dc.hasEgg or dc.stepsToEgg ~= 0 or dc.motherOrNonDitto ~= 0) then
    return nil
  end
  return dc
end

local function putDayCare(ctx, t, dc)
  local S, u = ctx.S, ctx.util
  if dc ~= nil and type(dc) ~= "table" then u.refuse("the day-care record is not a table") end
  dc = dc or {}
  local man = type(dc.man) == "table" and dc.man or {}
  local lady = type(dc.lady) == "table" and dc.lady or {}
  local b = u.u8(t, S.wDayCareMan)
  b = u.setBit(b, MAN_HAS_MON, man.mon ~= nil)
  b = u.setBit(b, MAN_COMPATIBLE, dc.compatible == true)
  b = u.setBit(b, MAN_HAS_EGG, dc.hasEgg == true)
  b = u.setBit(b, INTRO_SEEN, man.introSeen == true)
  t[S.wDayCareMan] = b
  b = u.u8(t, S.wDayCareLady)
  b = u.setBit(b, LADY_HAS_MON, lady.mon ~= nil)
  b = u.setBit(b, INTRO_SEEN, lady.introSeen == true)
  t[S.wDayCareLady] = b
  t[S.wStepsToEgg] = byteValue(u, dc.stepsToEgg or 0, "the day-care egg countdown")
  if dc.motherOrNonDitto ~= nil then
    t[S.wBreedMotherOrNonDitto] = byteValue(u, dc.motherOrNonDitto, "wBreedMotherOrNonDitto")
  end
  if man.mon ~= nil then
    putNamedMon(ctx, t, S.wBreedMon1Nickname, S.wBreedMon1OT, S.wBreedMon1, man.mon)
  end
  if lady.mon ~= nil then
    putNamedMon(ctx, t, S.wBreedMon2Nickname, S.wBreedMon2OT, S.wBreedMon2, lady.mon)
  end
  if dc.egg ~= nil then
    putNamedMon(ctx, t, S.wEggMonNickname, S.wEggMonOT, S.wEggMon, dc.egg, true)
  elseif u.u8(t, S.wEggMon) ~= 0 then
    -- pokecrystal engine/events/daycare.asm:548
    for i = 0, NAMED_MON - 1 do t[S.wEggMonNickname + i] = 0 end
  end
end


local function readStartTime(ctx, t)
  local S, u = ctx.S, ctx.util
  local at = S.wBugContestStartTime
  local d, h, m, s = u.u8(t, at), u.u8(t, at + 1), u.u8(t, at + 2), u.u8(t, at + 3)
  if d == 0 and h == 0 and m == 0 and s == 0 then return nil end
  return { day = d, hour = h, minute = m, second = s }
end

function M.readBugContest(ctx, t)
  local S = ctx.S
  local out = { startTime = readStartTime(ctx, t) }
  if ctx.util.u8(t, S.wContestMon) ~= 0 then out.caught = decodePartyMon(ctx, t, S.wContestMon) end
  if out.startTime == nil and out.caught == nil then return nil end
  return out
end

local function putBugContest(ctx, t, bc)
  local S, u = ctx.S, ctx.util
  if bc ~= nil and type(bc) ~= "table" then u.refuse("the bug contest record is not a table") end
  bc = bc or {}
  if type(bc.stash) == "table" then
    if #bc.stash > 0 then
      u.refuse("this save was made during the Bug-Catching Contest with Pokemon dropped off at the "
        .. "gate, and a cartridge cannot save during the contest")
    end
    -- pokecrystal engine/events/bug_contest/contest_2.asm:75
    t[S.wBugContestSecondPartySpecies] = 0xFF
  end
  if bc.caught ~= nil then
    if type(bc.caught) ~= "table" then u.refuse("the bug contest catch is not a Pokemon") end
    local cur = u.u8(t, S.wContestMon) ~= 0 and decodePartyMon(ctx, t, S.wContestMon) or nil
    putStruct(ctx, t, S.wContestMon, bc.caught, cur, PARTY, partyBytes)
  elseif u.u8(t, S.wContestMon) ~= 0 then
    -- pokecrystal engine/events/bug_contest/contest.asm:1
    t[S.wContestMon] = 0
  end
  -- pokecrystal engine/overworld/time.asm:144
  local st = bc.startTime
  local at = S.wBugContestStartTime
  if st == nil then
    for i = 0, 3 do t[at + i] = 0 end
  else
    if type(st) ~= "table" then u.refuse("the bug contest start time is not a table") end
    t[at] = byteValue(u, st.day or 0, "the bug contest start day")
    t[at + 1] = byteValue(u, st.hour or 0, "the bug contest start hour")
    t[at + 2] = byteValue(u, st.minute or 0, "the bug contest start minute")
    t[at + 3] = byteValue(u, st.second or 0, "the bug contest start second")
  end
end


local function readPair(ctx, t, groupAt, numberAt)
  local g, n = ctx.util.u8(t, groupAt), ctx.util.u8(t, numberAt)
  if g == 0 and n == 0 then return nil end
  return mapName(ctx, g, n)
end

local function putPair(ctx, t, groupAt, numberAt, mapId, what)
  if readPair(ctx, t, groupAt, numberAt) == mapId then return end
  if mapId == nil then
    t[groupAt], t[numberAt] = 0, 0
  else
    t[groupAt], t[numberAt] = mapIds(ctx, mapId, what)
  end
end

function M.dunsparceMap(save)
  local maps = type(save.swarmMaps) == "table" and save.swarmMaps or nil
  if save.swarmMap ~= nil and (maps == nil or maps.YANMA == nil) then return save.swarmMap end
  return maps and maps.DUNSPARCE or nil
end

-- pokegold engine/events/specials.asm:288
local function putSwarm(ctx, t, save)
  local S, u = ctx.S, ctx.util
  local at = swarmAt(S)
  putPair(ctx, t, at, at + 1, M.dunsparceMap(save), "the swarm map")
  local daily = type(save.dailyFlags) == "table" and save.dailyFlags or {}
  t[S.wFishingSwarmFlag] = byteValue(u, daily.fishingSwarm or 0, "wFishingSwarmFlag")
end

local function putSwarmFlags(ctx, t, save)
  local S, u = ctx.S, ctx.util
  if not S.wSwarmFlags then return end
  local flags = type(save.engineFlags) == "table" and save.engineFlags or {}
  local b = u.u8(t, S.wSwarmFlags)
  local raw = save[M.CARRIER]
  if type(raw) == "string" and #raw == rangeBytes(S) * 2 and not raw:find("[^%x]") then
    b = tonumber(raw:sub(-2), 16)
  end
  for bitN, id in pairs(M.SWARM_FLAG_IDS) do b = u.setBit(b, bitN, flags[id] == true) end
  t[S.wSwarmFlags] = b
end


local function decodeDVs(hi, lo)
  local atk, def, spd, spc = math.floor(hi / 16), hi % 16, math.floor(lo / 16), lo % 16
  return { attack = atk, defense = def, speed = spd, special = spc,
           hp = (atk % 2) * 8 + (def % 2) * 4 + (spd % 2) * 2 + (spc % 2) }
end

local function readRoamer(ctx, t, at)
  local u = ctx.util
  local g, n = u.u8(t, at + 2), u.u8(t, at + 3)
  local hp, d0, d1 = u.u8(t, at + 4), u.u8(t, at + 5), u.u8(t, at + 6)
  return {
    species = u.named(ctx.x.pokemon, u.u8(t, at)),
    level = u.u8(t, at + 1),
    map = not (g == 0xFF and n == 0xFF) and mapName(ctx, g, n) or nil,
    hp = hp,
    dvs = not (hp == 0 and d0 == 0 and d1 == 0) and decodeDVs(d0, d1) or nil,
  }
end

-- pokecrystal macros/ram.asm:218, engine/battle/core.asm:8620
local function roamerBytes(ctx, slot)
  local u = ctx.util
  if slot == nil then
    local b = {}
    for i = 1, ROAM do b[i - 1] = PRISTINE_ROAMER[i] end
    return b
  end
  if type(slot) ~= "table" then u.refuse("a roaming Pokemon slot is not a table") end
  local b = zeros(ROAM)
  b[0] = u.indexOf(ctx.x.pokemonIndex, slot.species, "roaming species")
  b[1] = byteValue(u, slot.level or 0, "the roaming Pokemon's level")
  if slot.map == nil then
    b[2], b[3] = 0xFF, 0xFF
  else
    b[2], b[3] = mapIds(ctx, slot.map, "the roaming Pokemon's map")
  end
  b[4] = byteValue(u, slot.hp or 0, "the roaming Pokemon's HP")
  if slot.dvs ~= nil then
    local d = slot.dvs
    b[5] = byteValue(u, (d.attack or 0) * 16 + (d.defense or 0), "the roaming Pokemon's DVs")
    b[6] = byteValue(u, (d.speed or 0) * 16 + (d.special or 0), "the roaming Pokemon's DVs")
  end
  return b
end

local function roamerAt(S, i)
  return ({ S.wRoamMon1, S.wRoamMon2, S.wRoamMon3 })[i]
end

function M.readRoamers(ctx, t)
  local slots, last = {}, 0
  local pristine = roamerBytes(ctx, nil)
  for i = 1, 3 do
    slots[i] = readRoamer(ctx, t, roamerAt(ctx.S, i))
    if not sameBytes(roamerBytes(ctx, slots[i]), pristine, ROAM) then last = i end
  end
  if last == 0 then return nil end
  local out = {}
  for i = 1, last do out[i] = slots[i] end
  return out
end

local function putRoamers(ctx, t, list)
  local u = ctx.util
  if list ~= nil and type(list) ~= "table" then u.refuse("the roaming Pokemon are not a list") end
  list = list or {}
  if #list > 3 then u.refuse(("a cartridge holds three roaming Pokemon and this save has %d"):format(#list)) end
  for i = 1, 3 do
    local at = roamerAt(ctx.S, i)
    local want = roamerBytes(ctx, list[i])
    if not sameBytes(want, roamerBytes(ctx, readRoamer(ctx, t, at)), ROAM) then
      copyInto(t, at, want, ROAM)
    end
  end
end

-- pokecrystal engine/overworld/wildmons.asm:743
function M.readRoamerMaps(ctx, t)
  local S, u = ctx.S, ctx.util
  for i = 0, 3 do
    if u.u8(t, S.wRoamMons_CurMapNumber + i) ~= 0 then
      return {
        current = readPair(ctx, t, S.wRoamMons_CurMapGroup, S.wRoamMons_CurMapNumber),
        last = readPair(ctx, t, S.wRoamMons_LastMapGroup, S.wRoamMons_LastMapNumber),
      }
    end
  end
  return nil
end

local function putRoamerMaps(ctx, t, marks)
  local S, u = ctx.S, ctx.util
  if marks ~= nil and type(marks) ~= "table" then u.refuse("the roaming map marks are not a table") end
  marks = marks or {}
  putPair(ctx, t, S.wRoamMons_CurMapGroup, S.wRoamMons_CurMapNumber, marks.current, "the roamers' current map")
  putPair(ctx, t, S.wRoamMons_LastMapGroup, S.wRoamMons_LastMapNumber, marks.last, "the roamers' last map")
end


function M.readMagikarp(ctx, t)
  local S, u = ctx.S, ctx.util
  local rec = {
    feet = u.u8(t, S.wBestMagikarpLengthFeet),
    inches = u.u8(t, S.wBestMagikarpLengthInches),
    name = u.text(t, S.wMagikarpRecordHoldersName, NAME),
  }
  if rec.feet == KARP_FEET and rec.inches == KARP_INCHES and rec.name == KARP_NAME then return nil end
  return rec
end

-- pokecrystal engine/events/magikarp.asm:43
local function putMagikarp(ctx, t, rec)
  local S, u = ctx.S, ctx.util
  if rec ~= nil and type(rec) ~= "table" then u.refuse("the Magikarp record is not a table") end
  local at = S.wMagikarpRecordHoldersName
  if rec == nil then
    t[S.wBestMagikarpLengthFeet] = KARP_FEET
    t[S.wBestMagikarpLengthInches] = KARP_INCHES
    if u.text(t, at, NAME) ~= KARP_NAME then
      local codes = u.encodeText(KARP_NAME, NAME)
      for i = 0, NAME - 1 do t[at + i] = 0 end
      for k, c in ipairs(codes) do t[at + k - 1] = c end
      t[at + #codes] = 0x50
    end
    return
  end
  t[S.wBestMagikarpLengthFeet] = byteValue(u, rec.feet or 0, "the Magikarp record's feet")
  t[S.wBestMagikarpLengthInches] = byteValue(u, rec.inches or 0, "the Magikarp record's inches")
  u.putName(t, at, rec.name or "", NAME)
end


function M.apply(ctx, t, save)
  putDayCare(ctx, t, save.dayCare)
  putBugContest(ctx, t, save.bugContest)
  putSwarm(ctx, t, save)
  putRoamers(ctx, t, save.roamers)
  putRoamerMaps(ctx, t, save.roamerMaps)
  putMagikarp(ctx, t, save.magikarpRecord)
  putSwarmFlags(ctx, t, save)
end

local function carrierOf(ctx, t)
  local out = {}
  for _, r in ipairs(M.ranges(ctx.S)) do
    out[#out + 1] = ctx.util.hex(t, r[1], r[2] - r[1])
  end
  return table.concat(out)
end

local function pasteCarrier(ctx, t, raw)
  if type(raw) ~= "string" or #raw ~= rangeBytes(ctx.S) * 2 or raw:find("[^%x]") then return end
  local bytes = ctx.util.fromHex(raw)
  local k = 1
  for _, r in ipairs(M.ranges(ctx.S)) do
    for i = r[1], r[2] - 1 do t[i] = bytes[k]; k = k + 1 end
  end
end

function M.decode(ctx, decoded)
  local t, S, u = ctx.t, ctx.S, ctx.util
  decoded.dayCare = M.readDayCare(ctx, t)
  decoded.bugContest = M.readBugContest(ctx, t)
  local swarm = readPair(ctx, t, swarmAt(S), swarmAt(S) + 1)
  if swarm ~= nil then
    decoded.swarmMap = swarm
    decoded.swarmMaps = type(decoded.swarmMaps) == "table" and decoded.swarmMaps or {}
    decoded.swarmMaps.DUNSPARCE = swarm
  end
  local fishing = u.u8(t, S.wFishingSwarmFlag)
  if fishing ~= 0 then
    decoded.dailyFlags = type(decoded.dailyFlags) == "table" and decoded.dailyFlags or {}
    decoded.dailyFlags.fishingSwarm = fishing
  end
  decoded.roamers = M.readRoamers(ctx, t)
  decoded.roamerMaps = M.readRoamerMaps(ctx, t)
  decoded.magikarpRecord = M.readMagikarp(ctx, t)
  if S.wSwarmFlags then
    local b = u.u8(t, S.wSwarmFlags)
    for bitN, id in pairs(M.SWARM_FLAG_IDS) do
      if u.bit(b, bitN) then
        decoded.engineFlags = decoded.engineFlags or {}
        decoded.engineFlags[id] = true
      end
    end
  end
  local scratch = setmetatable({}, { __index = t })
  M.defaults(ctx, scratch)
  local ok = pcall(M.apply, ctx, scratch, decoded)
  local same = ok
  for _, r in ipairs(M.ranges(S)) do
    for i = r[1], r[2] - 1 do
      if not same then break end
      same = rawget(scratch, i) == u.u8(t, i)
    end
  end
  if not same then decoded[M.CARRIER] = carrierOf(ctx, t) end
end

function M.encode(ctx, save)
  local t = ctx.t
  if ctx.fresh then
    M.defaults(ctx, t)
    pasteCarrier(ctx, t, save[M.CARRIER])
  end
  M.apply(ctx, t, save)
end

return M
