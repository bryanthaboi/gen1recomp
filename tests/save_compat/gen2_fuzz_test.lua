package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local R2 = require("tests.save_compat._r2")
local Ref = require("tests.save_compat._gen2_reference")
local Gen2Save = require("src.save_convert.Gen2Save")
local Compat = require("src.save_convert.Compat")

local N = tonumber(os.getenv("SAVE_COMPAT_FUZZ_N")) or 340
local SEED = tonumber(os.getenv("SAVE_COMPAT_FUZZ_SEED")) or 20261001
local VERSIONS = { "gold", "silver", "crystal" }

local ROOTS = { "player", "rival", "mom", "party", "boxes", "inventory", "bagOrder", "pcItems", "pcOrder",
                "mail", "currentBox", "pokedex", "unownDex", "firstUnownSeen", "position", "playTime", "events",
                "mapScenes", "engineFlags", "boxNames", "variableSprites", "playerState", "options" }
R2.ROOTS[2] = ROOTS

local state = SEED
local function rnd(a, b)
  state = (state * 48271) % 2147483647
  return a + state % (b - a + 1)
end
local function chance(p) return rnd(1, 1000) <= p * 1000 end
local function pick(list) return list[rnd(1, #list)] end

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function name(lo, hi)
  local out = {}
  for i = 1, rnd(lo, hi) do
    local k = rnd(1, #LETTERS)
    out[i] = LETTERS:sub(k, k)
  end
  return table.concat(out)
end

local function internalError(why)
  return type(why) == "string" and why:find("codec failed", 1, true) ~= nil
end

-- data/events/engine_flags.asm:11-40, :65-101
local ENGINE_IDS = { 0, 1, 2, 3, 4, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 42, 43, 44, 45, 46, 47, 48, 49 }
for i = 50, 76 do ENGINE_IDS[#ENGINE_IDS + 1] = i end

local SCENES = {}
for mapId in pairs(G2.layout("gold").sceneVars) do SCENES[#SCENES + 1] = mapId end
table.sort(SCENES)
local CRYSTAL_SCENES = {}
for mapId in pairs(G2.layout("crystal").sceneVars) do CRYSTAL_SCENES[#CRYSTAL_SCENES + 1] = mapId end
table.sort(CRYSTAL_SCENES)

local ITEMS, KEYS, BALLS = {}, {}, {}
for i = 1, 26 do ITEMS[#ITEMS + 1] = "ITEM_" .. i end
for i = 1, 25 do KEYS[#KEYS + 1] = "KEY_" .. i end
for i = 1, 12 do BALLS[#BALLS + 1] = "BALL_" .. i end

local function tmIndex(n)
  if n <= 4 then return 0xBF + n - 1 end
  if n <= 28 then return 0xC4 + n - 5 end
  if n <= 50 then return 0xDD + n - 29 end
  return 0xF3 + n - 51
end

local function randomMon(version, party)
  local moves = {}
  for i = 1, rnd(1, 4) do moves[i] = { id = rnd(1, 251), pp = rnd(0, 63), ppUps = rnd(0, 3) } end
  local dvs = { attack = rnd(0, 15), defense = rnd(0, 15), speed = rnd(0, 15), special = rnd(0, 15) }
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 + (dvs.speed % 2) * 2 + dvs.special % 2
  local m = {
    species = rnd(1, 251), moves = moves, otId = rnd(0, 65535), experience = rnd(0, 0xFFFFFF),
    statExp = { hp = rnd(0, 65535), attack = rnd(0, 65535), defense = rnd(0, 65535), speed = rnd(0, 65535),
                special = rnd(0, 65535) },
    dvs = dvs, happiness = rnd(0, 255), pokerus = rnd(0, 255), level = rnd(1, 100),
    ot = name(1, 7), nickname = name(1, 10),
  }
  if chance(0.3) then m.item = pick(ITEMS) elseif chance(0.1) then m.item = rnd(0xFA, 0xFF) end
  if chance(0.1) then
    m.isEgg, m.eggSteps, m.happiness = true, rnd(0, 255), Gen2Save.HATCH_HAPPINESS
  end
  if version == "crystal" then
    m.caughtTime, m.caughtLevel, m.caughtLocation = rnd(0, 3), rnd(0, 63), rnd(0, 127)
    m.caughtByGender = chance(0.5) and "girl" or "boy"
  else
    m.caughtData = rnd(0, 65535)
  end
  if party then
    local st = { attack = rnd(0, 999), defense = rnd(0, 999), speed = rnd(0, 999),
                 specialAttack = rnd(0, 999), specialDefense = rnd(0, 999) }
    m.maxHp = rnd(1, 999)
    st.hp = m.maxHp
    m.stats, m.hp = st, rnd(0, m.maxHp)
    local status = rnd(0, 5)
    if status == 1 then m.status, m.statusTurns = "sleep", rnd(1, 7)
    elseif status > 1 then m.status = ({ "poison", "burn", "freeze", "paralyze" })[status - 1] end
  end
  return m
end

local function randomSave(version)
  local crystal = version == "crystal"
  local s = {
    player = { name = name(1, 7), id = rnd(0, 65535), money = rnd(0, 999999), coins = rnd(0, 9999),
               badges = {}, kantoBadges = {} },
    rival = { name = name(1, 7) },
    mom = { name = name(1, 7), savedMoney = rnd(0, 999999), active = chance(0.5), savingMoney = chance(0.5),
            whichItem = rnd(0, 255), triggerBalance = rnd(0, 999999) },
    party = {}, boxes = {}, inventory = {}, bagOrder = {}, pcItems = {}, pcOrder = {},
    mail = { party = {}, box = {} }, currentBox = rnd(1, 14),
    pokedex = { caught = {}, seen = {} }, unownDex = {}, firstUnownSeen = rnd(0, 26),
    position = { map = K.GEN2_MAP, mapGroup = 24, mapNumber = 7, x = rnd(0, 3), y = rnd(0, 3) },
    playTime = { hours = rnd(0, 65535), minutes = rnd(0, 59), seconds = rnd(0, 59), frames = rnd(0, 59) },
    events = {}, mapScenes = {}, engineFlags = {}, boxNames = {}, variableSprites = {},
    playerState = pick({ "normal", "bike", "surf", "surf_pika" }),
    options = { textSpeed = pick({ "FAST", "MID", "SLOW" }), battleScene = chance(0.5),
                battleStyle = pick({ "SHIFT", "SET" }), sound = pick({ "MONO", "STEREO" }), frame = rnd(1, 8),
                print = pick({ "LIGHTEST", "LIGHTER", "NORMAL", "DARKER", "DARKEST" }), menuAccount = chance(0.5) },
  }
  if crystal then s.player.gender = chance(0.5) and "female" or "male" end
  for _, b in ipairs(Gen2Save.JOHTO_BADGES) do if chance(0.5) then s.player.badges[b] = true end end
  for _, b in ipairs(Gen2Save.KANTO_BADGES) do if chance(0.5) then s.player.kantoBadges[b] = true end end
  for i = 1, rnd(0, 6) do s.party[i] = randomMon(version, true) end
  for b = 1, 14 do
    s.boxes[b] = {}
    if chance(0.4) then for i = 1, rnd(0, 20) do s.boxes[b][i] = randomMon(version, false) end end
    s.boxNames[b] = chance(0.3) and ("BOX" .. b) or name(1, 9)
  end
  for i, mon in ipairs(s.party) do
    if chance(0.3) then
      mon.item = "FLOWER_MAIL"
      local msg = name(0, 32)
      s.mail.party[i] = { type = "FLOWER_MAIL", message = msg, author = name(1, crystal and 8 or 10),
                          authorId = rnd(0, 65535), species = rnd(1, 251) }
    end
  end
  for k = 1, rnd(0, 10) do
    s.mail.box[k] = { type = "FLOWER_MAIL", message = name(0, 32), author = name(1, crystal and 8 or 10),
                      authorId = rnd(0, 65535), species = rnd(1, 251) }
  end
  local function fill(pool, cap, perStack, list, map, order)
    local used, slots = {}, 0
    while slots < cap and chance(0.8) do
      local id = pick(pool)
      if not used[id] then
        local n = rnd(1, perStack and 250 or 1)
        local need = perStack and math.ceil(n / 99) or 1
        if slots + need > cap then break end
        used[id] = true
        slots = slots + need
        map[id] = n
        order[#order + 1] = id
      end
    end
  end
  fill(ITEMS, 20, true, nil, s.inventory, s.bagOrder)
  fill(KEYS, 25, false, nil, s.inventory, s.bagOrder)
  fill(BALLS, 12, true, nil, s.inventory, s.bagOrder)
  for n = 1, 57 do
    if chance(0.3) then
      local id = n == 1 and "TM_DYNAMICPUNCH" or tmIndex(n)
      s.inventory[id] = rnd(1, 99)
      s.bagOrder[#s.bagOrder + 1] = id
    end
  end
  fill(ITEMS, 50, true, nil, s.pcItems, s.pcOrder)
  for i = 1, 251 do
    if chance(0.3) then s.pokedex.caught[i] = true end
    if chance(0.5) then s.pokedex.seen[i] = true end
  end
  local letters = {}
  for i = 1, 26 do letters[i] = i end
  for i = 1, rnd(0, 26) do
    local k = rnd(i, 26)
    letters[i], letters[k] = letters[k], letters[i]
    s.unownDex[i] = letters[i]
  end
  for i = 0, 255 do s.events[i] = rnd(0, 255) end
  for _, mapId in ipairs(crystal and CRYSTAL_SCENES or SCENES) do
    if chance(0.2) then s.mapScenes[mapId] = rnd(1, 255) end
  end
  for _, id in ipairs(ENGINE_IDS) do
    if chance(0.5) then s.engineFlags[(crystal and id >= 16) and id + 1 or id] = true end
  end
  for i = 0, 15 do if chance(0.3) then s.variableSprites[i] = rnd(1, 255) end end
  return s
end

for _, v in ipairs(VERSIONS) do
  local bad = 0
  for n = 1, N do
    local s = randomSave(v)
    local out, why = Gen2Save.encode(s, v, nil, K.gen2Data)
    if not out then
      bad = bad + 1
      if bad <= 3 then check(false, ("%s model %d exports -- %s"):format(v, n, tostring(why))) end
    else
      local report = Compat.check(out, v)
      if #report.errors > 0 then
        bad = bad + 1
        if bad <= 3 then check(false, ("%s model %d: %s"):format(v, n, Compat.describe(report))) end
      end
      local ref = Ref.decode(out, v)
      if not (ref.checksum1 and ref.checksum2) then
        bad = bad + 1
        if bad <= 3 then check(false, ("%s model %d: the reference decoder rejects a checksum"):format(v, n)) end
      end
      local back = Gen2Save.decode(out, v, K.gen2Data)
      local want, got = R2.project(2, s), back and R2.project(2, back) or {}
      for path, value in pairs(want) do
        if got[path] ~= value then
          bad = bad + 1
          if bad <= 3 then check(false, ("%s model %d: %s %s -> %s"):format(v, n, path, value, tostring(got[path]))) end
          break
        end
      end
      local again = back and Gen2Save.encode(back, v, nil, K.gen2Data)
      if again ~= out then
        bad = bad + 1
        if bad <= 3 then check(false, ("%s model %d: export is not a fixed point"):format(v, n)) end
      end
    end
  end
  eq(bad, 0, ("%s: %d random models round trip through the cart"):format(v, N))
end

local function excludedFor(L)
  local ranges = {}
  local function ex(from, size) ranges[#ranges + 1] = { from, from + size } end
  ex(L.wPartyCount, 8)
  for i = 0, 5 do
    local o = L.wPartyMons + i * 48
    ex(o + 2, 4); ex(o + 0x17, 4); ex(o + 0x20, 1)
  end
  for _, base in ipairs(L.boxes) do
    ex(base, 22)
    for i = 0, 19 do
      local o = base + 0x16 + i * 32
      ex(o + 2, 4); ex(o + 0x17, 4)
    end
  end
  ex(L.sBox, Gen2Save.BOX_BYTES)
  for _, seg in ipairs(L.backupSave.segments) do ex(seg[2], seg[3]) end
  ex(L.backupSave.options, 9)
  ex(L.backupSave.checksum, 3)
  ex(L.sCheckValue1, 1); ex(L.sChecksum, 3)
  ex(L.wNumItems, 1); ex(L.wNumKeyItems, 1); ex(L.wNumBalls, 1); ex(L.wNumPCItems, 1)
  ex(L.wItems, 41); ex(L.wKeyItems, 26); ex(L.wBalls, 25); ex(L.wPCItems, 101)
  ex(L.sMailboxCount, 1); ex(L.sMailboxCountBackup, 1)
  ex(L.wMapGroup, 4)
  ex(L.wPlayerStruct - 9, 0x28 * 13 + 9)
  ex(L.wMapObjects, 16 * 16 + 32)
  ex(L.wScreenSave, 30)
  return function(o)
    for _, r in ipairs(ranges) do if o >= r[1] and o < r[2] then return true end end
    return false
  end
end

for _, v in ipairs(VERSIONS) do
  local L = G2.layout(v)
  local excluded = excludedFor(L)
  local base = B.fromString(assert(G2.build({ version = v, boxes = { [1] = G2.boxOf(5, 3), [9] = G2.boxOf(20, 7) },
    party = { G2.mon(), G2.mon({ species = 25, item = G2.ITEMS.FLOWER_MAIL.index }) }, mail = true,
    hallOfFame = true, unownDex = true, currentBox = 8,
    items = { { G2.ITEMS.POTION.index, 5 }, { G2.ITEMS.REPEL.index, 9 }, { G2.ITEMS.POTION.index, 99 } },
    pcItems = { { G2.ITEMS.MAX_POTION.index, 3 } } })))
  local bad = 0
  for n = 1, N do
    local b = {}
    for i = 0, 0x7FFF do b[i] = base[i] end
    b.size = 0x8000
    local touched = {}
    for _ = 1, rnd(1, 8) do
      local o
      repeat o = rnd(0, 0x7FFF) until not excluded(o)
      b[o] = rnd(0, 255)
      touched[#touched + 1] = ("%04X"):format(o)
    end
    local cur = b[L.wCurBox] < 14 and b[L.wCurBox] + 1 or 1
    B.copy(b, L.boxes[cur], L.sBox, Gen2Save.BOX_BYTES)
    B.copy(b, L.sPartyMailBackup, L.sPartyMail, 6 * Gen2Save.MAIL_STRUCT)
    B.copy(b, L.sMailboxCountBackup, L.sMailboxCount, 1 + 10 * Gen2Save.MAIL_STRUCT)
    G2.seal(b, v)
    local src = B.pack(b)
    local save, why = Gen2Save.decode(src, v, K.gen2Data)
    local out, xwhy
    if save then out, xwhy = Gen2Save.encode(save, v, src, K.gen2Data) end
    if out ~= src then
      bad = bad + 1
      if bad <= 3 then
        local first
        if out then for i = 1, #src do if src:byte(i) ~= out:byte(i) then first = i - 1 break end end end
        check(false, ("%s mutation %d at %s: %s"):format(v, n, table.concat(touched, ","),
          out and ("first difference 0x%04X"):format(first or -1) or tostring(why or xwhy)))
      end
    end
  end
  eq(bad, 0, ("%s: %d mutated carts reproduce byte for byte"):format(v, N))
end

for _, v in ipairs(VERSIONS) do
  local src = G2.build({ version = v, boxes = { [2] = G2.boxOf(20, 1) }, mail = true })
  local bad = 0
  for n = 1, N do
    local b = B.fromString(src)
    for _ = 1, rnd(1, 64) do b[rnd(0, 0x7FFF)] = rnd(0, 255) end
    if chance(0.5) then G2.seal(b, v) end
    local bytes = B.pack(b)
    local ok, save, why = pcall(Gen2Save.decode, bytes, v, K.gen2Data)
    if not ok or internalError(why) or (save == nil and type(why) ~= "string") then
      bad = bad + 1
      if bad <= 3 then check(false, ("%s corruption %d decode: %s"):format(v, n, tostring(ok and why or save))) end
    elseif save then
      local ok2, out, xwhy = pcall(Gen2Save.encode, save, v, bytes, K.gen2Data)
      if not ok2 or internalError(xwhy) or (out == nil and type(xwhy) ~= "string") then
        bad = bad + 1
        if bad <= 3 then check(false, ("%s corruption %d encode: %s"):format(v, n, tostring(ok2 and xwhy or out))) end
      end
    end
  end
  eq(bad, 0, ("%s: %d corrupted carts never raise"):format(v, N))

  local junk = { 7, "x", {}, { party = "no" }, { party = { 5 } }, { boxes = { { "a" } } },
                 { inventory = { [true] = 3 } }, { mail = { party = { "x" } } }, { position = { x = "a" } },
                 { playTime = "1" }, { options = 3 }, { mom = { savedMoney = "lots" } } }
  for i, s in ipairs(junk) do
    local ok, out, why = pcall(Gen2Save.encode, s, v, src, K.gen2Data)
    check(ok and not internalError(why) and (out ~= nil or type(why) == "string"),
      ("%s: junk save %d is answered, not raised -- %s"):format(v, i, tostring(why)))
  end
end

for _, v in ipairs(VERSIONS) do
  local src = G2.build({ version = v })
  for _, size in ipairs({ 0, 1, 100, 0x7FFF, 0x8000, 0x8007, 0x800C, 0x8030, 0x8040, 0x10000 }) do
    local bytes = size <= #src and src:sub(1, size) or (src .. string.rep("\170", size - #src))
    local ok, save, why = pcall(Gen2Save.decode, bytes, v, K.gen2Data)
    check(ok and not internalError(why), ("%s size %d: decode answers -- %s"):format(v, size, tostring(why)))
    if size < 0x8000 then
      eq(save, nil, ("%s size %d: a short image is refused"):format(v, size))
    else
      check(save ~= nil, ("%s size %d: a full image with any trailer imports"):format(v, size))
      local out = save and Gen2Save.encode(save, v, bytes, K.gen2Data)
      eq(out, bytes, ("%s size %d: and exports back byte for byte, trailer included"):format(v, size))
    end
    local ok2, out, xwhy = pcall(Gen2Save.encode, assert(Gen2Save.decode(src, v, K.gen2Data)), v, bytes, K.gen2Data)
    check(ok2 and not internalError(xwhy), ("%s size %d: as a template it is answered -- %s"):format(v, size, tostring(xwhy)))
    if size < 0x8000 then
      check(out ~= nil, ("%s size %d: a short template is rebuilt from the save"):format(v, size))
      eq(xwhy, Gen2Save.MSG.rebuilt, ("%s size %d: and the export says so"):format(v, size))
    end
  end
end

T.finish()
