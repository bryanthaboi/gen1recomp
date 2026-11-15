local Gen2EngineFlags = require("src.save_convert.Gen2EngineFlags")

local M = {}

M.CARRIER = "cartProgress"

-- pokegold ram/wram.asm:2310
-- pokecrystal ram/wram.asm:2992
local WRAM_GAME_DATA = { gs = 0xD1A1, crystal = 0xD47B }

-- pokecrystal ram/wram.asm:3232
local FIGHT_COUNTS = {
  "wJackFightCount", "wBeverlyFightCount", "wHueyFightCount", "wGavenFightCount",
  "wBethFightCount", "wJoseFightCount", "wReenaFightCount", "wJoeyFightCount",
  "wWadeFightCount", "wRalphFightCount", "wLizFightCount", "wAnthonyFightCount",
  "wToddFightCount", "wGinaFightCount", "wIrwinFightCount", "wArnieFightCount",
  "wAlanFightCount", "wDanaFightCount", "wChadFightCount", "wDerekFightCount",
  "wTullyFightCount", "wBrentFightCount", "wTiffanyFightCount", "wVanceFightCount",
  "wWiltonFightCount", "wKenjiFightCount", "wParryFightCount", "wErinFightCount",
}

local SCRIPT_MEM_LABELS = {
  gs = { "wMooMooBerries", "wUndergroundSwitchPositions" },
  crystal = { "wMooMooBerries", "wUndergroundSwitchPositions", "wFarfetchdPosition" },
}
for _, label in ipairs(FIGHT_COUNTS) do
  SCRIPT_MEM_LABELS.crystal[#SCRIPT_MEM_LABELS.crystal + 1] = label
end

-- pokegold data/events/engine_flags.asm:42
-- pokecrystal data/events/engine_flags.asm:43
local BIKE_FLAGS = { "ENGINE_STRENGTH_ACTIVE", "ENGINE_ALWAYS_ON_BIKE", "ENGINE_DOWNHILL" }
-- pokecrystal data/events/engine_flags.asm:133
local ENGINE_FOREST_IS_RESTLESS = Gen2EngineFlags.id("crystal", "ENGINE_FOREST_IS_RESTLESS")
-- pokecrystal constants/ram_constants.asm:307
local CELEBIEVENT_FOREST_IS_RESTLESS_F = 2

-- pokecrystal constants/ram_constants.asm:215
local SPAWN_AFTER = { [1] = "SPAWN_LANCE", [2] = "SPAWN_RED" }
local SPAWN_AFTER_BYTE = { SPAWN_LANCE = 1, SPAWN_RED = 2 }

-- pokecrystal constants/ram_constants.asm:11
local DEX_MODES = { [0] = "NEW", [1] = "OLD", [2] = "A-Z" }
local DEX_MODE_BYTE = { NEW = 0, OLD = 1, ["A-Z"] = 2 }

-- pokecrystal constants/ram_constants.asm:297
local REGISTERED_NUMBER = 0x3F
-- pokecrystal constants/item_data_constants.asm:41
local POCKET_BITS = { ITEM = 0x00, BALL = 0x40, KEY_ITEM = 0x80, TM_HM = 0xC0 }

-- pokecrystal constants/npc_trade_constants.asm:24
local NUM_NPC_TRADES = { gs = 6, crystal = 7 }

-- pokecrystal ram/wram.asm:3303
local DECO_SLOTS = { "bed", "carpet", "plant", "poster", "console",
                     "leftOrnament", "rightOrnament", "bigDoll" }
-- pokecrystal engine/overworld/decorations.asm:1
local DECO_DEFAULT = { bed = 2, poster = 16 }

-- pokecrystal constants/pokemon_data_constants.asm:152
local HOF_MON_LENGTH = 0x10
local HOF_LENGTH = 0x62
local NUM_HOF_TEAMS = 30
local HOF_PARTY = 6
local HOF_NAME = 10

-- pokecrystal constants/battle_tower_constants.asm:47
local GS_BALL_AVAILABLE = 0x0B
local GS_BALL_STATES = { have = true, given = true, used = true }

-- pokecrystal constants/battle_tower_constants.asm:1
local BT_STREAK = 7
local BT_PARTY = 3

-- pokecrystal ram/sram.asm:142
local CRYSTAL_DATA_LENGTH = 7

local function family(ctx) return ctx.crystal and "crystal" or "gs" end

local function wramOf(ctx, label)
  return WRAM_GAME_DATA[family(ctx)] + ctx.S[label] - ctx.S.wGameData
end
M.wramOf = wramOf

function M.scriptMemAddresses(ctx)
  local out = {}
  for _, label in ipairs(SCRIPT_MEM_LABELS[family(ctx)]) do
    if ctx.S[label] then out[wramOf(ctx, label)] = label end
  end
  return out
end

function M.savedWram(ctx, L)
  local base = WRAM_GAME_DATA[family(ctx)]
  return base, base + (L.sGameDataEnd - L.sGameData)
end

local function ser(v)
  local kind = type(v)
  if kind ~= "table" then return kind:sub(1, 1) .. tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
  end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = ser(k) .. "=" .. ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local function same(a, b) return ser(a) == ser(b) end

local function byteOf(ctx, value, what)
  local n = tonumber(value)
  if not n or n ~= math.floor(n) or n < 0 or n > 255 then
    ctx.util.refuse(("%s %s does not fit the cartridge's byte"):format(what, tostring(value)))
  end
  return n
end

local function u8(t, at) return t[at] or 0 end

local function mapIdAt(ctx, t, at)
  local g, n = u8(t, at), u8(t, at + 1)
  if g == 0 and n == 0 then return nil end
  return ctx.x.maps[g * 256 + n]
end

local function mapBytes(ctx, mapId, what)
  if mapId == nil then return 0, 0 end
  local ids = ctx.x.mapIds[mapId]
  if not ids then
    ctx.util.refuse(("%s %s has no map group and number in this game's data, so it "
      .. "cannot be written to a cartridge"):format(what, tostring(mapId)))
  end
  return ids[1], ids[2]
end

local function engineFlag(save, id)
  local flags = type(save.engineFlags) == "table" and save.engineFlags or {}
  return flags[id] == true
end

local function scriptByte(ctx, save, addr)
  local mem = type(save.scriptMem) == "table" and save.scriptMem or {}
  local value = mem[addr]
  if value == nil then
    for k, v in pairs(mem) do
      if tonumber(k) == addr then value = v end
    end
  end
  if value == nil then return 0 end
  return byteOf(ctx, value, ("script memory at $%04X"):format(addr))
end

local function bitsByte(t, at, ids, base)
  local out = {}
  local byte = u8(t, at)
  for b, id in pairs(ids) do
    if math.floor(byte / 2 ^ b) % 2 == 1 then out[id] = true end
  end
  return out, base
end

local function flagView(save, ids)
  local out = {}
  for _, id in pairs(ids) do
    if engineFlag(save, id) then out[id] = true end
  end
  return out
end

local function patchFlags(ctx, t, at, ids, save)
  local byte = u8(t, at)
  for b, id in pairs(ids) do
    byte = ctx.util.setBit(byte, b, engineFlag(save, id))
  end
  t[at] = byte
end

local function bikeIds(ctx)
  local ids = {}
  local version = family(ctx) == "crystal" and "crystal" or "gold"
  for b, name in ipairs(BIKE_FLAGS) do ids[b - 1] = Gen2EngineFlags.id(version, name) end
  return ids
end

local function teamView(ctx, t, base)
  local row = { winCount = u8(t, base), mons = {} }
  for i = 0, HOF_PARTY - 1 do
    local o = base + 1 + i * HOF_MON_LENGTH
    local sp = u8(t, o)
    if sp == 0xFF then break end
    row.mons[#row.mons + 1] = {
      species = sp, otId = ctx.util.be(t, o + 1, 2),
      dv1 = u8(t, o + 3), dv2 = u8(t, o + 4), level = u8(t, o + 5),
      nickname = ctx.util.text(t, o + 6, HOF_NAME),
    }
  end
  return row
end

local function hofRead(ctx, t)
  local teams = {}
  for k = 0, NUM_HOF_TEAMS - 1 do
    local base = ctx.S.sHallOfFame + k * HOF_LENGTH
    if u8(t, base) == 0 then break end
    teams[#teams + 1] = teamView(ctx, t, base)
  end
  return teams
end

local function canonicalName(ctx, str, n)
  local codes = ctx.util.encodeText(tostring(str or ""), n)
  local tmp = {}
  for i, c in ipairs(codes) do tmp[i - 1] = c end
  tmp[#codes] = 0x50
  return ctx.util.text(tmp, 0, n)
end

local function hofCanon(ctx, teams)
  local out = {}
  for i, row in ipairs(teams) do
    local mons = {}
    for j, m in ipairs(row.mons) do
      mons[j] = { species = m.species, otId = m.otId, dv1 = m.dv1, dv2 = m.dv2, level = m.level,
                  nickname = canonicalName(ctx, m.nickname, HOF_NAME) }
    end
    out[i] = { winCount = row.winCount, mons = mons }
  end
  return out
end

local function giftCanon(ctx, v)
  if not v.trainerHouse then return v end
  return { trainerHouse = true, partnerName = canonicalName(ctx, v.partnerName, 11) }
end

local function hofTeamsView(ctx, save)
  local record = type(save.hallOfFame) == "table" and save.hallOfFame or {}
  local teams = type(record.teams) == "table" and record.teams or {}
  if #teams > NUM_HOF_TEAMS then
    ctx.util.refuse(("the Hall of Fame holds %d teams and a cartridge holds %d")
      :format(#teams, NUM_HOF_TEAMS))
  end
  local out = {}
  for i, team in ipairs(teams) do
    local win = byteOf(ctx, team.winCount, ("Hall of Fame team %d's win count"):format(i))
    if win == 0 then
      ctx.util.refuse(("Hall of Fame team %d has a win count of 0, which a cartridge reads "
        .. "as the end of the roster"):format(i))
    end
    local mons = type(team.mons) == "table" and team.mons or {}
    if #mons > HOF_PARTY then
      ctx.util.refuse(("Hall of Fame team %d has %d Pokemon"):format(i, #mons))
    end
    local row = { winCount = win, mons = {} }
    for j, mon in ipairs(mons) do
      local sp = ctx.util.indexOf(ctx.x.pokemonIndex, mon.species, "Hall of Fame species")
      if sp == 0xFF then
        ctx.util.refuse(("Hall of Fame team %d slot %d has species $FF, the roster's "
          .. "terminator"):format(i, j))
      end
      local d = type(mon.dvs) == "table" and mon.dvs or {}
      local otId = tonumber(mon.otId) or 0
      if otId < 0 or otId > 0xFFFF or otId ~= math.floor(otId) then
        ctx.util.refuse(("Hall of Fame team %d slot %d has trainer ID %s"):format(i, j, tostring(mon.otId)))
      end
      row.mons[j] = {
        species = sp, otId = otId,
        dv1 = ((tonumber(d.attack) or 0) % 16) * 16 + (tonumber(d.defense) or 0) % 16,
        dv2 = ((tonumber(d.speed) or 0) % 16) * 16 + (tonumber(d.special) or 0) % 16,
        level = byteOf(ctx, mon.level, "Hall of Fame level"),
        nickname = tostring(mon.nickname or ""),
      }
    end
    out[i] = row
  end
  return out
end

local function putRow(ctx, t, base, row)
  for k = 0, HOF_LENGTH - 1 do t[base + k] = 0 end
  t[base] = row.winCount
  for j, mon in ipairs(row.mons) do
    local o = base + 1 + (j - 1) * HOF_MON_LENGTH
    t[o] = mon.species
    ctx.util.putBE(t, o + 1, mon.otId, 2)
    t[o + 3], t[o + 4], t[o + 5] = mon.dv1, mon.dv2, mon.level
    for k = 0, HOF_NAME - 1 do t[o + 6 + k] = 0x50 end
    ctx.util.putName(t, o + 6, mon.nickname, HOF_NAME)
  end
  t[base + 1 + #row.mons * HOF_MON_LENGTH] = 0xFF
end

-- pokecrystal engine/menus/save.asm:145
local function hofPatch(ctx, t, save)
  local want = hofTeamsView(ctx, save)
  local rows, raw = {}, {}
  for k = 0, NUM_HOF_TEAMS - 1 do
    local base = ctx.S.sHallOfFame + k * HOF_LENGTH
    rows[k + 1] = ser(teamView(ctx, t, base))
    local bytes = {}
    for i = 0, HOF_LENGTH - 1 do bytes[i] = u8(t, base + i) end
    raw[k + 1] = { bytes = bytes, present = u8(t, base) ~= 0 }
  end
  for k = 1, NUM_HOF_TEAMS do
    local base = ctx.S.sHallOfFame + (k - 1) * HOF_LENGTH
    local row = want[k]
    if row then
      local key, found = ser(row), nil
      for j = 1, NUM_HOF_TEAMS do
        if raw[j].present and rows[j] == key then found = raw[j].bytes; break end
      end
      if found then
        for i = 0, HOF_LENGTH - 1 do t[base + i] = found[i] end
      else
        putRow(ctx, t, base, row)
      end
    elseif raw[k].present then
      for i = 0, HOF_LENGTH - 1 do t[base + i] = 0 end
    end
  end
end

-- pokecrystal engine/gfx/color.asm:8
local function shinyDVs(dvs)
  return dvs.defense == 10 and dvs.speed == 10 and dvs.special == 10
    and math.floor(dvs.attack / 2) % 2 == 1
end

local function decodeTeams(ctx, t)
  local teams = {}
  for _, row in ipairs(hofRead(ctx, t)) do
    local entry = { winCount = row.winCount, mons = {} }
    for _, m in ipairs(row.mons) do
      local atk, def = math.floor(m.dv1 / 16), m.dv1 % 16
      local spd, spc = math.floor(m.dv2 / 16), m.dv2 % 16
      local dvs = { attack = atk, defense = def, speed = spd, special = spc,
                    hp = (atk % 2) * 8 + (def % 2) * 4 + (spd % 2) * 2 + (spc % 2) }
      local species = ctx.util.named(ctx.x.pokemon, m.species)
      local mon = { species = species, otId = m.otId, dvs = dvs, level = m.level,
                    nickname = m.nickname, shiny = shinyDVs(dvs) or nil }
      local def_ = ctx.x.pokemonDefs[species]
      if type(def_) == "table" then
        local ratio = def_.genderRatio
        if ratio == nil or ratio == 0xFF then
          mon.gender = "unknown"
        else
          mon.gender = atk < math.floor(ratio / 16) and "female" or "male"
        end
      end
      entry.mons[#entry.mons + 1] = mon
    end
    teams[#teams + 1] = entry
  end
  return teams
end

local function locateItem(ctx, t, idx)
  local L = ctx.L
  local lists = {
    { "ITEM", L.wNumItems, L.wItems, 2, 20 },
    { "BALL", L.wNumBalls, L.wBalls, 2, 12 },
    { "KEY_ITEM", L.wNumKeyItems, L.wKeyItems, 1, 25 },
  }
  for _, p in ipairs(lists) do
    if p[2] and p[3] then
      local n = math.min(u8(t, p[2]), p[5])
      for i = 0, n - 1 do
        local raw = u8(t, p[3] + i * p[4])
        if raw == 0xFF then break end
        if raw == idx then return p[1], i end
      end
    end
  end
  return nil
end

-- pokecrystal engine/overworld/select_menu.asm:18
local function slotHolds(ctx, t, which, idx)
  local L = ctx.L
  local pocket = math.floor(which / 64)
  local number = which % 64
  if pocket == 2 then
    return (locateItem(ctx, t, idx)) == "KEY_ITEM"
  end
  local countAt, listAt
  if pocket == 0 then countAt, listAt = L.wNumItems, L.wItems
  elseif pocket == 1 then countAt, listAt = L.wNumBalls, L.wBalls
  else return false end
  if number == 0 or number - 1 >= u8(t, countAt) then return false end
  return u8(t, listAt + (number - 1) * 2) == idx
end

local function registeredRead(ctx, t)
  local at = ctx.S.wWhichRegisteredItem
  return { u8(t, at), u8(t, at + 1) }
end

local function registeredId(raw)
  if raw[1] ~= 0 and raw[2] ~= 0 then return raw[2] end
  return nil
end

local function registeredView(ctx, save, t)
  local cur = registeredRead(ctx, t)
  local reg = save.registeredItem
  local id = type(reg) == "table" and reg.id or nil
  if id == nil then
    if registeredId(cur) == nil then return cur end
    return { 0, 0 }
  end
  local idx = ctx.util.indexOf(ctx.x.itemIndex, id, "registered item")
  if idx == 0 then return { 0, 0 } end
  local pocket, pos = locateItem(ctx, t, idx)
  if registeredId(cur) == idx and (pocket == nil or slotHolds(ctx, t, cur[1], idx)) then
    return cur
  end
  if pocket then return { POCKET_BITS[pocket] + pos + 1, idx } end
  local def = ctx.x.itemDefs[id]
  local bits = POCKET_BITS[type(def) == "table" and def.pocket or "ITEM"] or 0
  return { bits + REGISTERED_NUMBER, idx }
end

local function towerRead(ctx, t)
  local S = ctx.S
  local trainers = {}
  for i = 0, BT_STREAK - 1 do
    local b = u8(t, S.sBTTrainers + i)
    if b ~= 0xFF then trainers[i + 1] = b end
  end
  local function team(at)
    local out = {}
    for i = 0, BT_PARTY - 1 do
      local b = u8(t, at + i)
      if b ~= 0 then out[#out + 1] = b end
    end
    return out
  end
  return {
    challenge = u8(t, S.sBattleTowerChallengeState),
    streak = u8(t, S.sNrOfBeatenBattleTowerTrainers),
    levelGroup = u8(t, S.sBTChoiceOfLevelGroup),
    trainers = trainers,
    saveFileFlags = u8(t, S.sBattleTowerSaveFileFlags),
    reward = u8(t, S.sBattleTowerReward),
    prev = team(S.sBTMonOfTrainers),
    prevPrev = team(S.sBTMonOfTrainers + BT_PARTY),
  }
end

local function towerView(ctx, save)
  local tower = type(save.battleTower) == "table" and save.battleTower or {}
  local trainers = {}
  local src = type(tower.trainers) == "table" and tower.trainers or {}
  for k, v in pairs(src) do
    local slot = tonumber(k)
    if not slot or slot < 1 or slot > BT_STREAK or slot ~= math.floor(slot) then
      ctx.util.refuse(("Battle Tower trainer slot %s is outside the cartridge's %d")
        :format(tostring(k), BT_STREAK))
    end
    local b = byteOf(ctx, v, "Battle Tower trainer")
    if b == 0xFF then
      ctx.util.refuse("Battle Tower trainer $FF is the cartridge's empty slot")
    end
    trainers[slot] = b
  end
  local teams = type(tower.prevTeams) == "table" and tower.prevTeams or {}
  local function team(list, what)
    local out = {}
    list = type(list) == "table" and list or {}
    if #list > BT_PARTY then
      ctx.util.refuse(("the Battle Tower's %s team has %d Pokemon"):format(what, #list))
    end
    for i, sp in ipairs(list) do
      local b = ctx.util.indexOf(ctx.x.pokemonIndex, sp, "Battle Tower species")
      if b == 0 then ctx.util.refuse("a Battle Tower team slot has no species") end
      out[i] = b
    end
    return out
  end
  return {
    challenge = byteOf(ctx, tower.challenge or 0, "Battle Tower challenge state"),
    streak = byteOf(ctx, tower.streak or 0, "Battle Tower streak"),
    levelGroup = byteOf(ctx, tower.levelGroup or 0, "Battle Tower level group"),
    trainers = trainers,
    saveFileFlags = byteOf(ctx, tower.saveFileFlags or 0, "Battle Tower save file flags"),
    reward = ctx.util.indexOf(ctx.x.itemIndex, tower.reward, "Battle Tower reward"),
    prev = team(teams.prev, "previous"),
    prevPrev = team(teams.prevPrev, "second previous"),
  }
end

local function towerPatch(ctx, t, save)
  local S, v = ctx.S, towerView(ctx, save)
  t[S.sBattleTowerChallengeState] = v.challenge
  t[S.sNrOfBeatenBattleTowerTrainers] = v.streak
  t[S.sBTChoiceOfLevelGroup] = v.levelGroup
  for i = 0, BT_STREAK - 1 do t[S.sBTTrainers + i] = v.trainers[i + 1] or 0xFF end
  t[S.sBattleTowerSaveFileFlags] = v.saveFileFlags
  t[S.sBattleTowerReward] = v.reward
  for i = 0, BT_PARTY - 1 do
    t[S.sBTMonOfTrainers + i] = v.prev[i + 1] or 0
    t[S.sBTMonOfTrainers + BT_PARTY + i] = v.prevPrev[i + 1] or 0
  end
end

local function giftRead(ctx, t)
  local S = ctx.S
  local on = u8(t, S.sMysteryGiftTrainerHouseFlag) ~= 0
  return { trainerHouse = on,
           partnerName = on and ctx.util.text(t, S.sMysteryGiftPartnerName, 11) or nil }
end

local function giftView(ctx, save)
  local gift = type(save.mysteryGift) == "table" and save.mysteryGift or {}
  local on = gift.trainerHouse == true
  return { trainerHouse = on, partnerName = on and tostring(gift.partnerName or "") or nil }
end

local function giftPatch(ctx, t, save)
  local S, v = ctx.S, giftView(ctx, save)
  if v.trainerHouse ~= (u8(t, S.sMysteryGiftTrainerHouseFlag) ~= 0) then
    t[S.sMysteryGiftTrainerHouseFlag] = v.trainerHouse and 1 or 0
  end
  if v.trainerHouse then ctx.util.putName(t, S.sMysteryGiftPartnerName, v.partnerName, 11) end
end

local function span(S, from, to)
  if not (S[from] and S[to]) then return nil end
  return { S[from], S[to] - S[from] }
end

local function one(S, label, len)
  if not S[label] then return nil end
  return { S[label], len or 1 }
end

local STATIC = "static"

local REGIONS = {
  {
    id = "savedAtLeastOnce",
    spans = function(S) return { one(S, "wSavedAtLeastOnce") } end,
  },
  {
    id = "spawnAfterChampion",
    spans = function(S) return { one(S, "wSpawnAfterChampion") } end,
    read = function(ctx, t) return SPAWN_AFTER[u8(t, ctx.S.wSpawnAfterChampion)] or false end,
    view = function(ctx, save)
      local v = save.spawnAfterChampion
      if v == nil then return false end
      if not SPAWN_AFTER_BYTE[v] then
        ctx.util.refuse(("post-champion spawn %s has no wSpawnAfterChampion value"):format(tostring(v)))
      end
      return v
    end,
    patch = function(ctx, t, save)
      t[ctx.S.wSpawnAfterChampion] = SPAWN_AFTER_BYTE[save.spawnAfterChampion] or 0
    end,
    decode = function(ctx, t, out)
      out.spawnAfterChampion = SPAWN_AFTER[u8(t, ctx.S.wSpawnAfterChampion)]
    end,
  },
  {
    id = "radioTuningKnob",
    spans = function(S) return { one(S, "wRadioTuningKnob") } end,
    read = function(ctx, t) return u8(t, ctx.S.wRadioTuningKnob) end,
    view = function(ctx, save) return byteOf(ctx, save.radioTuningKnob or 0, "radio tuning knob") end,
    patch = function(ctx, t, save)
      t[ctx.S.wRadioTuningKnob] = byteOf(ctx, save.radioTuningKnob or 0, "radio tuning knob")
    end,
    decode = function(ctx, t, out)
      local b = u8(t, ctx.S.wRadioTuningKnob)
      out.radioTuningKnob = b ~= 0 and b or nil
    end,
  },
  {
    id = "lastDexMode",
    spans = function(S) return { span(S, "wLastDexMode", "wWhichRegisteredItem") } end,
    read = function(ctx, t) return DEX_MODES[u8(t, ctx.S.wLastDexMode)] or "NEW" end,
    view = function(ctx, save)
      local v = save.lastDexMode or "NEW"
      if DEX_MODE_BYTE[v] == nil then
        ctx.util.refuse(("Pokedex mode %s has no wLastDexMode value"):format(tostring(v)))
      end
      return v
    end,
    patch = function(ctx, t, save)
      t[ctx.S.wLastDexMode] = DEX_MODE_BYTE[save.lastDexMode or "NEW"]
    end,
    decode = function(ctx, t, out)
      out.lastDexMode = DEX_MODES[u8(t, ctx.S.wLastDexMode)] or "NEW"
    end,
  },
  {
    id = "registeredItem",
    spans = function(S) return { one(S, "wWhichRegisteredItem", 2) } end,
    read = registeredRead,
    view = registeredView,
    patch = function(ctx, t, save)
      local v = registeredView(ctx, save, t)
      t[ctx.S.wWhichRegisteredItem], t[ctx.S.wWhichRegisteredItem + 1] = v[1], v[2]
    end,
    decode = function(ctx, t, out)
      local id = registeredId(registeredRead(ctx, t))
      out.registeredItem = id and { id = ctx.util.named(ctx.x.items, id) } or nil
    end,
  },
  {
    id = "hallOfFameCount",
    spans = function(S) return { span(S, "wHallOfFameCount", "wTradeFlags") } end,
    read = function(ctx, t) return u8(t, ctx.S.wHallOfFameCount) end,
    view = function(ctx, save)
      local record = type(save.hallOfFame) == "table" and save.hallOfFame or {}
      return byteOf(ctx, record.count or 0, "Hall of Fame count")
    end,
    patch = function(ctx, t, save)
      local record = type(save.hallOfFame) == "table" and save.hallOfFame or {}
      t[ctx.S.wHallOfFameCount] = byteOf(ctx, record.count or 0, "Hall of Fame count")
    end,
  },
  {
    id = "hallOfFame",
    spans = function(S) return { span(S, "sHallOfFame", "sHallOfFameEnd") } end,
    read = hofRead,
    view = hofTeamsView,
    canon = hofCanon,
    patch = hofPatch,
    decode = function(ctx, t, out)
      local count = u8(t, ctx.S.wHallOfFameCount)
      out.hallOfFame = { count = count, teams = decodeTeams(ctx, t),
                         entered = count > 0 or nil }
    end,
  },
  {
    id = "tradeFlags",
    spans = function(S) return { span(S, "wTradeFlags", "wMooMooBerries") } end,
    read = function(ctx, t)
      local out = {}
      local byte = u8(t, ctx.S.wTradeFlags)
      for id = 0, NUM_NPC_TRADES[family(ctx)] - 1 do
        if math.floor(byte / 2 ^ id) % 2 == 1 then out[#out + 1] = id end
      end
      return out
    end,
    view = function(ctx, save)
      local set = {}
      for k, v in pairs(type(save.tradeFlags) == "table" and save.tradeFlags or {}) do
        local id = tonumber(k)
        if v == true then
          if not id or id < 0 or id >= NUM_NPC_TRADES[family(ctx)] or id ~= math.floor(id) then
            ctx.util.refuse(("NPC trade %s has no wTradeFlags bit"):format(tostring(k)))
          end
          set[id] = true
        end
      end
      local out = {}
      for id = 0, NUM_NPC_TRADES[family(ctx)] - 1 do
        if set[id] then out[#out + 1] = id end
      end
      return out
    end,
    patch = function(ctx, t, save)
      local at = ctx.S.wTradeFlags
      local byte = u8(t, at)
      local flags = type(save.tradeFlags) == "table" and save.tradeFlags or {}
      for id = 0, NUM_NPC_TRADES[family(ctx)] - 1 do
        local on = flags[id] == true or flags[tostring(id)] == true
        byte = ctx.util.setBit(byte, id, on)
      end
      t[at] = byte
    end,
    decode = function(ctx, t, out)
      local flags = {}
      local byte = u8(t, ctx.S.wTradeFlags)
      for id = 0, NUM_NPC_TRADES[family(ctx)] - 1 do
        if math.floor(byte / 2 ^ id) % 2 == 1 then flags[id] = true end
      end
      out.tradeFlags = flags
    end,
  },
}

local function memRegion(label, endLabel)
  return {
    id = label,
    spans = function(S)
      if endLabel then return { span(S, label, endLabel) } end
      return { one(S, label) }
    end,
    read = function(ctx, t) return u8(t, ctx.S[label]) end,
    view = function(ctx, save) return scriptByte(ctx, save, wramOf(ctx, label)) end,
    patch = function(ctx, t, save)
      t[ctx.S[label]] = scriptByte(ctx, save, wramOf(ctx, label))
    end,
    decode = function(ctx, t, out)
      local b = u8(t, ctx.S[label])
      out.scriptMem = out.scriptMem or {}
      if b ~= 0 then out.scriptMem[wramOf(ctx, label)] = b end
    end,
  }
end

REGIONS[#REGIONS + 1] = memRegion("wMooMooBerries")
REGIONS[#REGIONS + 1] = {
  id = "wUndergroundSwitchPositions",
  spans = function(S, crystal)
    if crystal then return { one(S, "wUndergroundSwitchPositions") } end
    return { span(S, "wUndergroundSwitchPositions", "wPokecenter2FSceneID") }
  end,
  read = memRegion("wUndergroundSwitchPositions").read,
  view = memRegion("wUndergroundSwitchPositions").view,
  patch = memRegion("wUndergroundSwitchPositions").patch,
  decode = memRegion("wUndergroundSwitchPositions").decode,
}
REGIONS[#REGIONS + 1] = {
  id = "fightCounts",
  crystalOnly = true,
  spans = function(S)
    local out = {}
    for i, label in ipairs(FIGHT_COUNTS) do out[i] = one(S, label) or false end
    for _, sp in ipairs(out) do if not sp then return {} end end
    return out
  end,
  read = function(ctx, t)
    local out = {}
    for i, label in ipairs(FIGHT_COUNTS) do out[i] = u8(t, ctx.S[label]) end
    return out
  end,
  view = function(ctx, save)
    local out = {}
    for i, label in ipairs(FIGHT_COUNTS) do out[i] = scriptByte(ctx, save, wramOf(ctx, label)) end
    return out
  end,
  patch = function(ctx, t, save)
    for _, label in ipairs(FIGHT_COUNTS) do t[ctx.S[label]] = scriptByte(ctx, save, wramOf(ctx, label)) end
  end,
  decode = function(ctx, t, out)
    out.scriptMem = out.scriptMem or {}
    for _, label in ipairs(FIGHT_COUNTS) do
      local b = u8(t, ctx.S[label])
      if b ~= 0 then out.scriptMem[wramOf(ctx, label)] = b end
    end
  end,
}

local farfetchd = memRegion("wFarfetchdPosition", "wPokecenter2FSceneID")
farfetchd.crystalOnly = true
REGIONS[#REGIONS + 1] = farfetchd

REGIONS[#REGIONS + 1] = {
  id = "celebiEvent",
  crystalOnly = true,
  spans = function(S) return { span(S, "wCelebiEvent", "wBikeFlags") } end,
  read = function(ctx, t)
    return (bitsByte(t, ctx.S.wCelebiEvent,
      { [CELEBIEVENT_FOREST_IS_RESTLESS_F] = ENGINE_FOREST_IS_RESTLESS }))
  end,
  view = function(_, save)
    return flagView(save, { [CELEBIEVENT_FOREST_IS_RESTLESS_F] = ENGINE_FOREST_IS_RESTLESS })
  end,
  patch = function(ctx, t, save)
    patchFlags(ctx, t, ctx.S.wCelebiEvent,
      { [CELEBIEVENT_FOREST_IS_RESTLESS_F] = ENGINE_FOREST_IS_RESTLESS }, save)
  end,
  decode = function(ctx, t, out)
    out.engineFlags = out.engineFlags or {}
    if math.floor(u8(t, ctx.S.wCelebiEvent) / 2 ^ CELEBIEVENT_FOREST_IS_RESTLESS_F) % 2 == 1 then
      out.engineFlags[ENGINE_FOREST_IS_RESTLESS] = true
    end
  end,
}

REGIONS[#REGIONS + 1] = {
  id = "bikeFlags",
  spans = function(S) return { span(S, "wBikeFlags", "wCurMapSceneScriptPointer") } end,
  read = function(ctx, t) return (bitsByte(t, ctx.S.wBikeFlags, bikeIds(ctx))) end,
  view = function(ctx, save) return flagView(save, bikeIds(ctx)) end,
  patch = function(ctx, t, save) patchFlags(ctx, t, ctx.S.wBikeFlags, bikeIds(ctx), save) end,
  decode = function(ctx, t, out)
    out.engineFlags = out.engineFlags or {}
    for id in pairs((bitsByte(t, ctx.S.wBikeFlags, bikeIds(ctx)))) do out.engineFlags[id] = true end
  end,
}

REGIONS[#REGIONS + 1] = {
  id = "decorations",
  spans = function(S) return { span(S, "wDecoBed", "wWhichMomItem") } end,
  read = function(ctx, t)
    local out = {}
    for i, slot in ipairs(DECO_SLOTS) do out[slot] = u8(t, ctx.S.wDecoBed + i - 1) end
    return out
  end,
  view = function(ctx, save)
    local state = type(save.decorations) == "table" and save.decorations or DECO_DEFAULT
    local out = {}
    for _, slot in ipairs(DECO_SLOTS) do
      out[slot] = byteOf(ctx, state[slot] or 0, "decoration in the " .. slot .. " slot")
    end
    return out
  end,
  patch = function(ctx, t, save)
    local state = type(save.decorations) == "table" and save.decorations or DECO_DEFAULT
    for i, slot in ipairs(DECO_SLOTS) do
      t[ctx.S.wDecoBed + i - 1] = byteOf(ctx, state[slot] or 0, "decoration")
    end
  end,
  decode = function(ctx, t, out)
    local state = {}
    for i, slot in ipairs(DECO_SLOTS) do
      local b = u8(t, ctx.S.wDecoBed + i - 1)
      if b ~= 0 then state[slot] = b end
    end
    out.decorations = state
  end,
}

local function backupRead(ctx, t)
  local S = ctx.S
  local map = mapIdAt(ctx, t, S.wBackupMapGroup)
  if not map then return false end
  return { warp = u8(t, S.wBackupWarpNumber), map = map }
end

local function backupView(ctx, save)
  local b = save.backupWarp
  if type(b) ~= "table" or b.map == nil then return false end
  mapBytes(ctx, b.map, "the backup warp map")
  return { warp = byteOf(ctx, b.warp or 0, "backup warp number"), map = b.map }
end

-- pokecrystal home/map.asm:687
-- pokecrystal engine/overworld/warp_connection.asm:189
REGIONS[#REGIONS + 1] = {
  id = "digAndBackupWarp",
  spans = function(S) return { span(S, "wDigWarpNumber", "wLastSpawnMapGroup") } end,
  read = backupRead,
  view = backupView,
  patch = function(ctx, t, save)
    local S, v = ctx.S, backupView(ctx, save)
    if not v then
      t[S.wBackupWarpNumber], t[S.wBackupMapGroup], t[S.wBackupMapNumber] = 0, 0, 0
      return
    end
    local g, n = mapBytes(ctx, v.map, "the backup warp map")
    t[S.wBackupWarpNumber], t[S.wBackupMapGroup], t[S.wBackupMapNumber] = v.warp, g, n
    t[S.wDigWarpNumber], t[S.wDigMapGroup], t[S.wDigMapNumber] = v.warp, g, n
  end,
  decode = function(ctx, t, out)
    local v = backupRead(ctx, t)
    out.backupWarp = v or nil
  end,
}

-- pokecrystal engine/events/whiteout.asm:61
REGIONS[#REGIONS + 1] = {
  id = "lastSpawn",
  spans = function(S) return { span(S, "wLastSpawnMapGroup", "wWarpNumber") } end,
  read = function(ctx, t) return mapIdAt(ctx, t, ctx.S.wLastSpawnMapGroup) or false end,
  view = function(ctx, save)
    if save.blackoutMap == nil then return false end
    mapBytes(ctx, save.blackoutMap, "the whiteout map")
    return save.blackoutMap
  end,
  patch = function(ctx, t, save)
    local g, n = mapBytes(ctx, save.blackoutMap, "the whiteout map")
    t[ctx.S.wLastSpawnMapGroup], t[ctx.S.wLastSpawnMapNumber] = g, n
  end,
  decode = function(ctx, t, out)
    out.blackoutMap = mapIdAt(ctx, t, ctx.S.wLastSpawnMapGroup)
  end,
}

REGIONS[#REGIONS + 1] = {
  id = "warpNumber",
  spans = function(S) return { one(S, "wWarpNumber") } end,
}

REGIONS[#REGIONS + 1] = {
  id = "mysteryGift",
  spans = function(S) return { span(S, "sMysteryGiftData", "sBackupMysteryGiftItemEnd") } end,
  read = giftRead,
  view = giftView,
  canon = giftCanon,
  patch = giftPatch,
  decode = function(ctx, t, out) out.mysteryGift = giftRead(ctx, t) end,
}

REGIONS[#REGIONS + 1] = {
  id = "linkBattleStats",
  spans = function(S) return { span(S, "sLinkBattleStats", "sLinkBattleStatsEnd") } end,
}

REGIONS[#REGIONS + 1] = {
  id = "gsBall",
  crystalOnly = true,
  spans = function(S) return { one(S, "sGSBallFlag"), one(S, "sGSBallFlagBackup") } end,
  read = function(ctx, t) return u8(t, ctx.S.sGSBallFlag) == GS_BALL_AVAILABLE end,
  view = function(ctx, save)
    local c = type(save.crystal) == "table" and save.crystal or {}
    if c.gsBall ~= nil and not GS_BALL_STATES[c.gsBall] then
      ctx.util.refuse(("GS Ball state %s has no sGSBallFlag value"):format(tostring(c.gsBall)))
    end
    return c.gsBall ~= nil
  end,
  patch = function(ctx, t, save)
    local c = type(save.crystal) == "table" and save.crystal or {}
    local b = c.gsBall ~= nil and GS_BALL_AVAILABLE or 0
    t[ctx.S.sGSBallFlag], t[ctx.S.sGSBallFlagBackup] = b, b
  end,
  decode = function(ctx, t, out)
    out.crystal = out.crystal or {}
    out.crystal.gsBall = u8(t, ctx.S.sGSBallFlag) == GS_BALL_AVAILABLE and "have" or nil
  end,
}

REGIONS[#REGIONS + 1] = {
  id = "crystalProfile",
  crystalOnly = true,
  spans = function(S)
    if not S.sCrystalData then return { nil } end
    return { { S.sCrystalData + 1, CRYSTAL_DATA_LENGTH - 1 } }
  end,
}

REGIONS[#REGIONS + 1] = {
  id = "battleTower",
  crystalOnly = true,
  spans = function(S)
    if not (S.sBattleTowerChallengeState and S.sBTMonOfTrainers) then return { nil } end
    return { { S.sBattleTowerChallengeState,
               S.sBTMonOfTrainers + BT_PARTY * 2 - S.sBattleTowerChallengeState } }
  end,
  read = towerRead,
  view = towerView,
  patch = towerPatch,
  decode = function(ctx, t, out)
    local v = towerRead(ctx, t)
    local function names(list)
      local o = {}
      for i, b in ipairs(list) do o[i] = ctx.util.named(ctx.x.pokemon, b) end
      return o
    end
    out.battleTower = {
      challenge = v.challenge, streak = v.streak, best = 0, levelGroup = v.levelGroup,
      trainers = v.trainers, saveFileFlags = v.saveFileFlags,
      reward = ctx.util.named(ctx.x.items, v.reward),
      prevTeams = { prev = names(v.prev), prevPrev = names(v.prevPrev) },
      inChallenge = false, reentry = false,
    }
  end,
}

M.REGIONS = REGIONS

local function activeSpans(ctx, region)
  if region.crystalOnly and not ctx.crystal then return nil end
  local spans = region.spans(ctx.S, ctx.crystal)
  for i = 1, #spans do
    if not spans[i] then return nil end
  end
  if #spans == 0 then return nil end
  return spans
end

local function snapshot(t, spans)
  local out = {}
  for _, s in ipairs(spans) do
    for i = 0, s[2] - 1 do out[#out + 1] = u8(t, s[1] + i) end
  end
  return out
end

local function restore(t, spans, bytes)
  local k = 1
  for _, s in ipairs(spans) do
    for i = 0, s[2] - 1 do t[s[1] + i] = bytes[k]; k = k + 1 end
  end
end

local function toHex(bytes)
  local out = {}
  for i, b in ipairs(bytes) do out[i] = ("%02X"):format(b) end
  return table.concat(out)
end

local function spanLength(spans)
  local n = 0
  for _, s in ipairs(spans) do n = n + s[2] end
  return n
end

M.spansFor = function(ctx, id)
  for _, region in ipairs(REGIONS) do
    if region.id == id then return activeSpans(ctx, region) end
  end
  return nil
end

function M.decode(ctx, decoded)
  local carriers = {}
  for _, region in ipairs(REGIONS) do
    local spans = activeSpans(ctx, region)
    if spans then
      if region.decode then region.decode(ctx, ctx.t, decoded) end
      carriers[region.id] = toHex(snapshot(ctx.t, spans))
    end
  end
  decoded[M.CARRIER] = carriers
end

local function readOf(region, ctx, t)
  if not region.read then return STATIC end
  return region.read(ctx, t)
end

local function viewOf(region, ctx, save, t)
  if not region.view then return STATIC end
  return region.view(ctx, save, t)
end

function M.encode(ctx, save)
  local t = ctx.t
  local carriers = type(save[M.CARRIER]) == "table" and save[M.CARRIER] or {}
  if save.warpMod ~= nil then
    local mod, backup = save.warpMod, save.backupWarp
    if type(mod) ~= "table" or type(backup) ~= "table" or mod.map ~= backup.map
        or tonumber(mod.warp) ~= tonumber(backup.warp) then
      ctx.util.refuse("a warpmod destination that the backup warp does not hold cannot be ordered "
        .. "against it, so it cannot be written to wBackupWarpNumber")
    end
  end
  for _, region in ipairs(REGIONS) do
    local spans = activeSpans(ctx, region)
    if spans then
      local carrier = carriers[region.id]
      local bytes = type(carrier) == "string" and ctx.util.fromHex(carrier) or nil
      if bytes and #bytes ~= spanLength(spans) then bytes = nil end
      local done = false
      if bytes then
        local before = snapshot(t, spans)
        restore(t, spans, bytes)
        if same(readOf(region, ctx, t), viewOf(region, ctx, save, t)) then
          done = true
        elseif not ctx.fresh then
          restore(t, spans, before)
        end
      end
      if not done and not same(readOf(region, ctx, t), viewOf(region, ctx, save, t)) then
        region.patch(ctx, t, save)
        local canon = region.canon or function(_, v) return v end
        if not same(canon(ctx, readOf(region, ctx, t)), canon(ctx, viewOf(region, ctx, save, t))) then
          ctx.util.refuse(("the %s state cannot be written to a cartridge exactly"):format(region.id))
        end
      end
    end
  end
end

M.coverage = {
  { both = { "wSavedAtLeastOnce", len = 1 }, mode = "static", keys = {},
    why = "set to 1 by every save the cartridge writes; no engine save is unsaved",
    asm = "pokecrystal engine/menus/save.asm:374" },
  { both = { "wSpawnAfterChampion", len = 1 }, mode = "modeled", keys = { "spawnAfterChampion" },
    asm = "pokecrystal engine/events/halloffame.asm:11" },
  { both = { "wRadioTuningKnob", len = 1 }, mode = "modeled", keys = { "radioTuningKnob" },
    asm = "pokecrystal engine/pokegear/pokegear.asm:1390" },
  { both = { "wLastDexMode", "wWhichRegisteredItem" }, mode = "modeled", keys = { "lastDexMode" },
    asm = "pokecrystal engine/pokedex/pokedex.asm:61" },
  { both = { "wWhichRegisteredItem", len = 2 }, mode = "modeled", keys = { "registeredItem" },
    asm = "pokecrystal engine/items/pack.asm:547" },
  { both = { "wHallOfFameCount", "wTradeFlags" }, mode = "modeled", keys = { "hallOfFame.count" },
    asm = "pokecrystal ram/wram.asm:3138" },
  { both = { "wTradeFlags", "wMooMooBerries" }, mode = "modeled", keys = { "tradeFlags" },
    asm = "pokecrystal ram/wram.asm:3140" },
  { both = { "wMooMooBerries", len = 1 }, mode = "modeled", keys = { "scriptMem" },
    asm = "pokecrystal ram/wram.asm:3142" },
  { gs = { "wUndergroundSwitchPositions", "wPokecenter2FSceneID" },
    crystal = { "wUndergroundSwitchPositions", len = 1 }, mode = "modeled", keys = { "scriptMem" },
    asm = "pokegold ram/wram.asm:2457" },
  { crystal = { "wFarfetchdPosition", "wPokecenter2FSceneID" }, mode = "modeled",
    keys = { "scriptMem" }, asm = "pokecrystal ram/wram.asm:3144" },
  { crystal = { "wCelebiEvent", "wBikeFlags" }, mode = "modeled", keys = { "engineFlags" },
    asm = "pokecrystal ram/wram.asm:3271" },
  { both = { "wBikeFlags", "wCurMapSceneScriptPointer" }, mode = "modeled", keys = { "engineFlags" },
    asm = "pokecrystal ram/wram.asm:3277" },
  { both = { "wDecoBed", "wWhichMomItem" }, mode = "modeled", keys = { "decorations" },
    asm = "pokecrystal ram/wram.asm:3303" },
  { both = { "wDigWarpNumber", "wLastSpawnMapGroup" }, mode = "modeled", keys = { "backupWarp" },
    asm = "pokecrystal home/map.asm:687" },
  { both = { "wLastSpawnMapGroup", "wWarpNumber" }, mode = "modeled", keys = { "blackoutMap" },
    asm = "pokecrystal engine/overworld/scripting.asm:2105" },
  { both = { "wWarpNumber", len = 1 }, mode = "static", keys = {},
    why = "only read by GetWarpDestCoords on a warp that rewrites it first; Continue never reads it",
    asm = "pokecrystal home/map.asm:665" },
}

M.sram = {
  { both = { "sMysteryGiftData", "sBackupMysteryGiftItemEnd" }, mode = "modeled",
    keys = { "mysteryGift" }, asm = "pokecrystal ram/sram.asm:34" },
  { both = { "sLinkBattleStats", "sLinkBattleStatsEnd" }, mode = "static", keys = {},
    why = "Gen 2 link battles keep no win, loss or draw record in the engine",
    asm = "pokecrystal ram/sram.asm:115" },
  { both = { "sHallOfFame", "sHallOfFameEnd" }, mode = "modeled", keys = { "hallOfFame" },
    asm = "pokecrystal ram/sram.asm:130" },
  { crystal = { "sGSBallFlag", len = 1 }, mode = "modeled", keys = { "crystal.gsBall" },
    asm = "pokecrystal ram/sram.asm:140" },
  { crystal = { "sGSBallFlagBackup", len = 1 }, mode = "modeled", keys = { "crystal.gsBall" },
    asm = "pokecrystal ram/sram.asm:144" },
  { crystal = { "sCrystalData", len = CRYSTAL_DATA_LENGTH }, mode = "static", keys = {},
    why = "bytes 1-6 are the mobile profile (age, prefecture, postal code) the engine has no form for",
    asm = "pokecrystal ram/wram.asm:2983" },
  { crystal = { "sBattleTowerChallengeState", len = 18 }, mode = "modeled", keys = { "battleTower" },
    asm = "pokecrystal ram/sram.asm:150" },
}

return M
