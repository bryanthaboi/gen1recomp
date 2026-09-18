-- Move table: curated defs + optional ROM gBattleMoves pack.

local Types = require("src.core.game3.battle.types")
local EffectIds = require("src.core.game3.battle.effect_ids")
local Extract = require("src.import.gba.extract_island1")

local Moves = {}

Moves._rom = nil -- { [id] = row }
Moves._romLoaded = false

local function M(id, power, typeId, category, accuracy, pp, extra)
  extra = extra or {}
  return {
    id = id,
    power = power or 0,
    type = typeId or 0,
    category = category or (Types.isPhysical(typeId) and "physical" or "special"),
    accuracy = accuracy or 100,
    pp = pp or 20,
    effectId = extra.effectId,
    effect = extra.effect,
    secondaryChance = extra.secondaryChance,
    priority = extra.priority or 0,
    flags = extra.flags or 0,
    hits = extra.hits,
    afterHit = extra.afterHit,
  }
end

local T = Types.ID

-- Curated names for display + overrides (ROM fills numeric stats when present).
Moves.BY_ID = {
  TACKLE = M("TACKLE", 35, T.NORMAL, "physical", 95, 35),
  SCRATCH = M("SCRATCH", 40, T.NORMAL, "physical", 100, 35),
  POUND = M("POUND", 40, T.NORMAL, "physical", 100, 35),
  QUICK_ATTACK = M("QUICK_ATTACK", 40, T.NORMAL, "physical", 100, 30, { priority = 1, effect = EffectIds.QUICK_ATTACK }),
  STRUGGLE = M("STRUGGLE", 50, T.NORMAL, "physical", 100, 1, { afterHit = { kind = "recoil", fraction = 0.25 } }),
  EMBER = M("EMBER", 40, T.FIRE, "special", 100, 25, { effect = EffectIds.BURN_HIT, secondaryChance = 10 }),
  WATER_GUN = M("WATER_GUN", 40, T.WATER, "special", 100, 25),
  VINE_WHIP = M("VINE_WHIP", 35, T.GRASS, "physical", 100, 10),
  THUNDERSHOCK = M("THUNDERSHOCK", 40, T.ELECTRIC, "special", 100, 30, { effect = EffectIds.PARALYZE_HIT, secondaryChance = 10 }),
  THUNDERBOLT = M("THUNDERBOLT", 95, T.ELECTRIC, "special", 100, 15, { effect = EffectIds.PARALYZE_HIT, secondaryChance = 10 }),
  RAZOR_LEAF = M("RAZOR_LEAF", 55, T.GRASS, "physical", 95, 25, { effect = EffectIds.HIGH_CRITICAL }),
  BITE = M("BITE", 60, T.DARK, "physical", 100, 25, { effect = EffectIds.FLINCH_HIT, secondaryChance = 30 }),
  GUST = M("GUST", 40, T.FLYING, "special", 100, 35),
  CONFUSION = M("CONFUSION", 50, T.PSYCHIC, "special", 100, 25, { effect = EffectIds.CONFUSE_HIT, secondaryChance = 10 }),
  PSYCHIC = M("PSYCHIC", 90, T.PSYCHIC, "special", 100, 10, { effect = EffectIds.SPECIAL_DEFENSE_DOWN_HIT, secondaryChance = 10 }),
  ICE_BEAM = M("ICE_BEAM", 95, T.ICE, "special", 100, 10, { effect = EffectIds.FREEZE_HIT, secondaryChance = 10 }),
  FLAMETHROWER = M("FLAMETHROWER", 95, T.FIRE, "special", 100, 15, { effect = EffectIds.BURN_HIT, secondaryChance = 10 }),
  SURF = M("SURF", 95, T.WATER, "special", 100, 15),
  EARTHQUAKE = M("EARTHQUAKE", 100, T.GROUND, "physical", 100, 10),
  ROCK_THROW = M("ROCK_THROW", 50, T.ROCK, "physical", 90, 15),
  WING_ATTACK = M("WING_ATTACK", 60, T.FLYING, "physical", 100, 35),
  ABSORB = M("ABSORB", 20, T.GRASS, "special", 100, 20, { effect = EffectIds.ABSORB }),
  MEGA_DRAIN = M("MEGA_DRAIN", 40, T.GRASS, "special", 100, 10, { effect = EffectIds.ABSORB }),
  GIGA_DRAIN = M("GIGA_DRAIN", 60, T.GRASS, "special", 100, 5, { effect = EffectIds.ABSORB }),
  SLASH = M("SLASH", 70, T.NORMAL, "physical", 100, 20, { effect = EffectIds.HIGH_CRITICAL }),
  BODY_SLAM = M("BODY_SLAM", 85, T.NORMAL, "physical", 100, 15, { effect = EffectIds.PARALYZE_HIT, secondaryChance = 30 }),
  DOUBLE_EDGE = M("DOUBLE_EDGE", 120, T.NORMAL, "physical", 100, 15, { effect = EffectIds.DOUBLE_EDGE }),
  HYPER_BEAM = M("HYPER_BEAM", 150, T.NORMAL, "special", 90, 5),
  BRICK_BREAK = M("BRICK_BREAK", 75, T.FIGHTING, "physical", 100, 15, { effect = EffectIds.BRICK_BREAK }),
  HEADBUTT = M("HEADBUTT", 70, T.NORMAL, "physical", 100, 15, { effect = EffectIds.FLINCH_HIT, secondaryChance = 30 }),
  WATERFALL = M("WATERFALL", 80, T.WATER, "physical", 100, 15, { effect = EffectIds.FLINCH_HIT, secondaryChance = 20 }),
  GROWL = M("GROWL", 0, T.NORMAL, "status", 100, 40, { effectId = "EXP_GROWL", effect = EffectIds.ATTACK_DOWN }),
  TAIL_WHIP = M("TAIL_WHIP", 0, T.NORMAL, "status", 100, 30, { effectId = "EXP_TAIL_WHIP" }),
  LEER = M("LEER", 0, T.NORMAL, "status", 100, 30, { effectId = "EXP_LEER" }),
  HARDEN = M("HARDEN", 0, T.NORMAL, "status", 100, 30, { effectId = "EXP_HARDEN" }),
  CALM_MIND = M("CALM_MIND", 0, T.PSYCHIC, "status", 0, 20, { effectId = "EXP_CALM_MIND", effect = EffectIds.CALM_MIND }),
  BULK_UP = M("BULK_UP", 0, T.FIGHTING, "status", 0, 20, { effectId = "EXP_BULK_UP", effect = EffectIds.BULK_UP }),
  DRAGON_DANCE = M("DRAGON_DANCE", 0, T.DRAGON, "status", 0, 20, { effectId = "EXP_DRAGON_DANCE", effect = EffectIds.DRAGON_DANCE }),
  SWORDS_DANCE = M("SWORDS_DANCE", 0, T.NORMAL, "status", 0, 30, { effectId = "EXP_SWORDS_DANCE" }),
  AGILITY = M("AGILITY", 0, T.PSYCHIC, "status", 0, 30, { effectId = "EXP_AGILITY" }),
  AMNESIA = M("AMNESIA", 0, T.PSYCHIC, "status", 0, 20, { effectId = "EXP_AMNESIA" }),
  SUNNY_DAY = M("SUNNY_DAY", 0, T.FIRE, "status", 0, 5, { effectId = "EXP_WEATHER_SUNNY", effect = EffectIds.SUNNY_DAY }),
  RAIN_DANCE = M("RAIN_DANCE", 0, T.WATER, "status", 0, 5, { effectId = "EXP_WEATHER_RAINY", effect = EffectIds.RAIN_DANCE }),
  SANDSTORM = M("SANDSTORM", 0, T.ROCK, "status", 0, 10, { effectId = "EXP_WEATHER_SANDSTORM", effect = EffectIds.SANDSTORM }),
  HAIL = M("HAIL", 0, T.ICE, "status", 0, 10, { effectId = "EXP_WEATHER_HAIL", effect = EffectIds.HAIL }),
  TOXIC = M("TOXIC", 0, T.POISON, "status", 85, 10, { effectId = "EXP_TOXIC_EFFECT" }),
  WILL_O_WISP = M("WILL_O_WISP", 0, T.FIRE, "status", 75, 15, { effectId = "EXP_BURN_EFFECT", effect = EffectIds.WILL_O_WISP }),
  THUNDER_WAVE = M("THUNDER_WAVE", 0, T.ELECTRIC, "status", 100, 20, { effectId = "EXP_PARALYZE_EFFECT" }),
  LEECH_SEED = M("LEECH_SEED", 0, T.GRASS, "status", 90, 10, { effectId = "EXP_LEECH_SEED_EFFECT", effect = EffectIds.LEECH_SEED }),
  SPIKES = M("SPIKES", 0, T.GROUND, "status", 0, 20, { effectId = "EXP_SPIKES_EFFECT", effect = EffectIds.SPIKES }),
  PROTECT = M("PROTECT", 0, T.NORMAL, "status", 0, 10, { effectId = "EXP_PROTECT_EFFECT", effect = EffectIds.PROTECT }),
  DETECT = M("DETECT", 0, T.FIGHTING, "status", 0, 5, { effectId = "EXP_PROTECT_EFFECT" }),
  REFLECT = M("REFLECT", 0, T.PSYCHIC, "status", 0, 20, { effectId = "EXP_REFLECT_EFFECT", effect = EffectIds.REFLECT }),
  LIGHT_SCREEN = M("LIGHT_SCREEN", 0, T.PSYCHIC, "status", 0, 30, { effectId = "EXP_LIGHT_SCREEN_EFFECT", effect = EffectIds.LIGHT_SCREEN }),
  SAFEGUARD = M("SAFEGUARD", 0, T.NORMAL, "status", 0, 25, { effectId = "EXP_SAFEGUARD_EFFECT", effect = EffectIds.SAFEGUARD }),
  RECOVER = M("RECOVER", 0, T.NORMAL, "status", 0, 20, { effectId = "EXP_RECOVER_EFFECT", effect = EffectIds.RECOVER }),
  SOFTBOILED = M("SOFTBOILED", 0, T.NORMAL, "status", 0, 10, { effectId = "EXP_SOFTBOILED_EFFECT", effect = EffectIds.SOFTBOILED }),
  FOCUS_ENERGY = M("FOCUS_ENERGY", 0, T.NORMAL, "status", 0, 30, { effectId = "EXP_FOCUS_ENERGY_EFFECT", effect = EffectIds.FOCUS_ENERGY }),
  YAWN = M("YAWN", 0, T.NORMAL, "status", 0, 10, { effectId = "EXP_YAWN_EFFECT", effect = EffectIds.YAWN }),
  TAUNT = M("TAUNT", 0, T.DARK, "status", 100, 20, { effectId = "EXP_TAUNT_EFFECT", effect = EffectIds.TAUNT }),
  MEAN_LOOK = M("MEAN_LOOK", 0, T.NORMAL, "status", 0, 5, { effectId = "EXP_MEAN_LOOK_EFFECT", effect = EffectIds.MEAN_LOOK }),
  INGRAIN = M("INGRAIN", 0, T.GRASS, "status", 0, 20, { effectId = "EXP_INGRAIN_EFFECT", effect = EffectIds.INGRAIN }),
  FURY_ATTACK = M("FURY_ATTACK", 15, T.NORMAL, "physical", 85, 20, { hits = { 2, 5 } }),
  DOUBLESLAP = M("DOUBLESLAP", 15, T.NORMAL, "physical", 85, 10, { hits = { 2, 5 } }),
  PIN_MISSILE = M("PIN_MISSILE", 14, T.BUG, "physical", 85, 20, { hits = { 2, 5 } }),
  COMET_PUNCH = M("COMET_PUNCH", 18, T.NORMAL, "physical", 85, 15, { hits = { 2, 5 } }),
  CUT = M("CUT", 50, T.NORMAL, "physical", 95, 30),
  FLY = M("FLY", 70, T.FLYING, "physical", 95, 15),
  STRENGTH = M("STRENGTH", 80, T.NORMAL, "physical", 100, 15),
  FLASH = M("FLASH", 0, T.NORMAL, "status", 100, 20),
  ROCK_SMASH = M("ROCK_SMASH", 20, T.FIGHTING, "physical", 100, 15),
  WHIRLPOOL = M("WHIRLPOOL", 15, T.WATER, "special", 70, 15),
  DIVE = M("DIVE", 60, T.WATER, "physical", 100, 10),
}

-- Numeric FRLG move id → curated name (for display / overlay).
Moves.BY_NUM = {
  [1] = "POUND", [2] = "KARATE_CHOP", [10] = "SCRATCH", [33] = "TACKLE",
  [39] = "TAIL_WHIP", [98] = "QUICK_ATTACK", [52] = "EMBER", [55] = "WATER_GUN",
  [22] = "VINE_WHIP", [84] = "THUNDERSHOCK", [85] = "THUNDERBOLT", [75] = "RAZOR_LEAF",
  [44] = "BITE", [16] = "GUST", [93] = "CONFUSION", [94] = "PSYCHIC",
  [58] = "ICE_BEAM", [53] = "FLAMETHROWER", [57] = "SURF", [89] = "EARTHQUAKE",
  [88] = "ROCK_THROW", [17] = "WING_ATTACK", [71] = "ABSORB", [72] = "MEGA_DRAIN",
  [202] = "GIGA_DRAIN", [163] = "SLASH", [34] = "BODY_SLAM", [38] = "DOUBLE_EDGE",
  [63] = "HYPER_BEAM", [280] = "BRICK_BREAK", [29] = "HEADBUTT", [127] = "WATERFALL",
  [45] = "GROWL", [43] = "LEER", [106] = "HARDEN", [347] = "CALM_MIND",
  [339] = "BULK_UP", [349] = "DRAGON_DANCE", [165] = "STRUGGLE",
  [14] = "SWORDS_DANCE", [97] = "AGILITY", [133] = "AMNESIA",
  [241] = "SUNNY_DAY", [240] = "RAIN_DANCE", [201] = "SANDSTORM", [258] = "HAIL",
  [92] = "TOXIC", [261] = "WILL_O_WISP", [86] = "THUNDER_WAVE",
  [73] = "LEECH_SEED", [191] = "SPIKES", [182] = "PROTECT", [197] = "DETECT",
  [115] = "REFLECT", [113] = "LIGHT_SCREEN", [219] = "SAFEGUARD",
  [105] = "RECOVER", [135] = "SOFTBOILED", [116] = "FOCUS_ENERGY",
  [281] = "YAWN", [269] = "TAUNT", [212] = "MEAN_LOOK", [275] = "INGRAIN",
  [31] = "FURY_ATTACK", [3] = "DOUBLESLAP", [42] = "PIN_MISSILE", [4] = "COMET_PUNCH",
  [15] = "CUT", [19] = "FLY", [70] = "STRENGTH", [148] = "FLASH",
  [249] = "ROCK_SMASH", [250] = "WHIRLPOOL", [291] = "DIVE",
}

local function load_lua(rel)
  local paths = { rel, "mods/Kanto-Reforged/" .. rel }
  for _, p in ipairs(paths) do
    local f = io.open(p, "rb")
    if f then
      local src = f:read("*a")
      f:close()
      local chunk = load(src, "@" .. rel, "t", {})
      if chunk then
        local ok, t = pcall(chunk)
        if ok then return t end
      end
    end
  end
  return nil
end

function Moves.loadRomPack(cache)
  Moves._romLoaded = true
  local root = (Extract.CACHE_ROOT or "data/generated/gba") .. "/pokemon/battle_moves.lua"
  if root:find("sevii", 1, true) then
    root = "data/generated/gba/pokemon/battle_moves.lua"
  end
  local pack
  if not cache or not cache.read then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.cache then
      cache = Dataset.cache()
    end
  end
  if cache and cache.read then
    local src = cache:read(root)
    if src then
      local chunk = load(src, "@" .. root, "t", {})
      if chunk then
        local ok, t = pcall(chunk)
        if ok then pack = t end
      end
    end
  end
  if not pack then pack = load_lua(root) end
  if pack and pack.moves then
    Moves._rom = pack.moves
    Moves._runReloadHooks()
    return true
  end
  Moves._rom = nil
  return false
end

Moves._reloadHooks = {}

function Moves.onReload(fn, key)
  if type(fn) ~= "function" then return function() end end
  local hooks = Moves._reloadHooks
  for i = #hooks, 1, -1 do
    local h = hooks[i]
    if h.fn == fn or (key ~= nil and h.key == key) then
      table.remove(hooks, i)
    end
  end
  local entry = { fn = fn, key = key }
  hooks[#hooks + 1] = entry
  return function()
    for i = #hooks, 1, -1 do
      if hooks[i] == entry then table.remove(hooks, i) end
    end
  end
end

function Moves._runReloadHooks()
  local snapshot = {}
  for i, h in ipairs(Moves._reloadHooks) do snapshot[i] = h end
  for _, h in ipairs(snapshot) do pcall(h.fn, Moves) end
end

function Moves.romReady()
  if not Moves._romLoaded then Moves.loadRomPack(nil) end
  return Moves._rom ~= nil
end

local function unwrap_move(moveId)
  if type(moveId) == "table" then
    return moveId.id or moveId.move or moveId.moveId or moveId.num or moveId.name or moveId[1]
  end
  return moveId
end

function Moves.normalizeId(moveId)
  moveId = unwrap_move(moveId)
  if moveId == nil or moveId == 0 or moveId == "" then return nil end
  if type(moveId) == "number" then
    return Moves.BY_NUM[moveId] or tostring(moveId)
  end
  if type(moveId) ~= "string" then return nil end
  local s = moveId:upper():gsub("%s+", "_"):gsub("-", "_")
  if s == "THUNDER_SHOCK" then return "THUNDERSHOCK" end
  if s == "WILLOWISP" then return "WILL_O_WISP" end
  if s == "DOUBLE_SLAP" then return "DOUBLESLAP" end
  return s
end

function Moves.numForName(name)
  name = unwrap_move(name)
  if not name then return nil end
  if type(name) == "number" then return name end
  local cleanName = tostring(name):upper():gsub("%s+", "_"):gsub("-", "_")
  if not Moves._numByName then
    Moves._numByName = {}
    for nid, n in pairs(Moves.BY_NUM) do
      Moves._numByName[n] = nid
    end
    local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
    if ok and Pokemon and Pokemon.moveName then
      for id = 1, 354 do
        local n = Pokemon.moveName(id)
        if n and n ~= "" and not n:match("^MOVE ") then
          local key = n:upper():gsub("%s+", "_"):gsub("-", "_")
          if not Moves._numByName[key] then
            Moves._numByName[key] = id
          end
        end
      end
    end
  end
  return Moves._numByName[cleanName] or Moves._numByName[name]
end

local function from_rom(numId)
  if not Moves.romReady() then return nil end
  local row = Moves._rom[numId]
  if not row then return nil end
  local name = Moves.BY_NUM[numId] or ("MOVE_" .. tostring(numId))
  local cat = Types.isPhysical(row.type) and "physical" or "special"
  if (row.power or 0) == 0 then cat = "status" end
  local effectId = EffectIds.STATUS_SETUP[row.effect]
  return {
    id = name,
    numId = numId,
    power = row.power,
    type = row.type,
    category = cat,
    accuracy = row.accuracy,
    pp = row.pp,
    effect = row.effect,
    secondaryChance = row.secondaryChance,
    target = row.target,
    priority = row.priority,
    flags = row.flags,
    effectId = effectId,
  }
end

function Moves.get(moveId)
  moveId = unwrap_move(moveId)
  local num = tonumber(moveId)
  if not num and type(moveId) == "string" then
    local norm = Moves.normalizeId(moveId)
    num = Moves.numForName(norm)
  end

  if num then
    local rom = from_rom(num)
    local name = Moves.BY_NUM[num]
    local curated = name and Moves.BY_ID[name]
    if rom and curated then
      -- ROM stats win; keep curated hits/afterHit/effectId overrides when useful.
      local m = {}
      for k, v in pairs(rom) do m[k] = v end
      if curated.hits then m.hits = curated.hits end
      if curated.afterHit then m.afterHit = curated.afterHit end
      if curated.effectId and not m.effectId then m.effectId = curated.effectId end
      m.id = curated.id
      return m
    end
    if rom then return rom end
    if curated then return curated end
    return M("MOVE_" .. tostring(num), 40, T.NORMAL, "physical", 100, 20)
  end

  local id = Moves.normalizeId(moveId) or "TACKLE"
  local curated = Moves.BY_ID[id]
  if curated then
    -- Prefer ROM row when we know the numeric id.
    for nid, n in pairs(Moves.BY_NUM) do
      if n == id then
        local rom = from_rom(nid)
        if rom then
          local m = {}
          for k, v in pairs(rom) do m[k] = v end
          if curated.hits then m.hits = curated.hits end
          if curated.afterHit then m.afterHit = curated.afterHit end
          if curated.effectId then m.effectId = curated.effectId end
          m.id = curated.id
          return m
        end
        break
      end
    end
    return curated
  end

  -- Fallback to ROM row by matching canonical move name from species/ROM data.
  local romNum = Moves.numForName(id)
  if romNum then
    local rom = from_rom(romNum)
    if rom then
      rom.id = id
      return rom
    end
  end

  return M(id, 40, T.NORMAL, "physical", 100, 20)
end

function Moves.displayName(moveId)
  moveId = unwrap_move(moveId)
  if not moveId or moveId == 0 or moveId == "" or moveId == "-------" then
    return "-------"
  end

  local num = tonumber(moveId)
  if not num and type(moveId) == "string" then
    local norm = Moves.normalizeId(moveId)
    num = Moves.numForName(norm)
  end

  if num then
    local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
    if ok and Pokemon and Pokemon.moveName then
      local n = Pokemon.moveName(num)
      if n and n ~= "" and not n:match("^MOVE ") then
        return n
      end
    end
  end

  local m = Moves.get(moveId)
  local id = m and m.id or Moves.normalizeId(moveId) or "TACKLE"
  if type(id) == "number" then return "MOVE " .. tostring(id) end
  return tostring(id):gsub("_", " ")
end

function Moves.priority(moveId)
  local m = Moves.get(moveId)
  return tonumber(m and m.priority) or 0
end

return Moves
