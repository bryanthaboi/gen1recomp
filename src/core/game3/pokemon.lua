-- Runtime FRLG species names / menu icons / types (extracted pack).
local CachePaths = require("src.core.game3.cache_paths")
local PokemonExtract = require("src.import.gba.pokemon_extract")
local Versions = require("src.import.gba.versions")
local ModRuntime = require("src.mods.Runtime")

local Pokemon = {}

Pokemon._cache = nil
Pokemon._names = nil
Pokemon._types = nil
Pokemon._national = nil
Pokemon._manifest = nil
Pokemon._byName = nil -- normalized host/FRLG name → internal SPECIES
Pokemon._icons = {} -- [species] = { image, w, h }
Pokemon._front = {} -- [species] = { image, w, h }
Pokemon._stats = nil
Pokemon._abilities = nil
Pokemon._abilityNames = nil
Pokemon._speciesMeta = nil
Pokemon._moveNames = nil
-- The ROM's English move and ability names, copied at install before a mod
-- renames entries of _moveNames/_abilityNames in place.  Anything keyed by
-- the English name (the summary's descriptions) reads these.
Pokemon._romMoveNames = nil
Pokemon._romAbilityNames = nil
Pokemon._learnsets = nil
Pokemon._eggMoves = nil
Pokemon._evolutions = nil
Pokemon._tmhm = nil
Pokemon._dex = nil
Pokemon._battleMoves = nil
Pokemon._logged = false

local ROOT = (CachePaths.CACHE_ROOT or "data/generated/gba") .. "/pokemon"

local function log(msg)
  if Pokemon._logged then return end
  Pokemon._logged = true
  print("[game3/pokemon] " .. tostring(msg))
end

local function resolve_cache(cache)
  if cache and cache.read then return cache end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local c = Dataset.cache()
    if c then return c end
  end
  return {
    read = function(_, rel)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.readActive then
        local data = CacheFs.readActive(rel)
        if data then return data end
      end
      local f = io.open(rel, "rb") or io.open("data/generated/gba/" .. rel, "rb")
      if f then
        local data = f:read("*a")
        f:close()
        return data
      end
      return nil
    end,
  }
end

local function copy_names(names)
  if type(names) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(names) do out[k] = v end
  return out
end

local pkLoadWarned = false
local function load_lua(cache, rel)
  cache = resolve_cache(cache)
  local src = cache:read(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok then return t end
  if not pkLoadWarned then
    pkLoadWarned = true
    print("[game3/pokemon] load failed for " .. tostring(rel) .. ": " .. tostring(t))
  end
  return nil
end

--- Normalize host id / FRLG display name for reverse lookup.
-- "KYOGRE" / "NIDORAN_F" / "FARFETCH'D" / "HO-OH" / "MR. MIME"
local function norm_key(s)
  if s == nil then return nil end
  s = tostring(s):upper()
  -- Common host aliases before stripping.
  s = s:gsub("NIDORAN_F", "NIDORANF"):gsub("NIDORAN_M", "NIDORANM")
  s = s:gsub("MR_MIME", "MRMIME"):gsub("MIME_JR", "MIMEJR")
  s = s:gsub("FARFETCH[_']?D", "FARFETCHD")
  s = s:gsub("HO[_%-]?OH", "HOOH")
  s = s:gsub("NIDORAN♀", "NIDORANF"):gsub("NIDORAN♂", "NIDORANM")
  s = s:gsub("FARFETCH'D", "FARFETCHD")
  s = s:gsub("MR%.%s*MIME", "MRMIME"):gsub("MR%.", "MR")
  s = s:gsub("HO%-OH", "HOOH")
  s = s:gsub("[^A-Z0-9]", "")
  return s
end

local function build_name_index(names)
  local by = {}
  if type(names) ~= "table" then return by end
  for id, name in pairs(names) do
    if type(id) == "number" and type(name) == "string" and name ~= "" then
      local k = norm_key(name)
      if k and k ~= "" and not by[k] then
        by[k] = id
      end
      -- Extra keys for gendered / punctuated FRLG glyphs.
      if name:find("♀", 1, true) then
        by["NIDORANF"] = by["NIDORANF"] or id
      end
      if name:find("♂", 1, true) then
        by["NIDORANM"] = by["NIDORANM"] or id
      end
    end
  end
  return by
end

function Pokemon.install(cache)
  Pokemon._cache = resolve_cache(cache)
  Pokemon._spinda = nil
  Pokemon._spindaPics = nil
  Pokemon._names = nil
  Pokemon._types = nil
  Pokemon._national = nil
  Pokemon._manifest = nil
  Pokemon._byName = nil
  Pokemon._stats = nil
  Pokemon._abilities = nil
  Pokemon._abilityNames = nil
  Pokemon._speciesMeta = nil
  Pokemon._moveNames = nil
  Pokemon._romMoveNames = nil
  Pokemon._romAbilityNames = nil
  Pokemon._learnsets = nil
  Pokemon._eggMoves = nil
  Pokemon._evolutions = nil
  Pokemon._tmhm = nil
  Pokemon._dex = nil
  Pokemon._battleMoves = nil
  Pokemon._icons = {}
  Pokemon._front = {}
  Pokemon._logged = false
  local root = (CachePaths.CACHE_ROOT or "data/generated/gba") .. "/pokemon"
  local c = Pokemon._cache
  Pokemon._manifest = load_lua(c, root .. "/manifest.lua")
  Pokemon._names = load_lua(c, root .. "/names.lua")
  Pokemon._types = load_lua(c, root .. "/types.lua")
  Pokemon._national = load_lua(c, root .. "/national.lua")
  Pokemon._stats = load_lua(c, root .. "/stats.lua")
  Pokemon._abilities = load_lua(c, root .. "/abilities.lua")
  Pokemon._abilityNames = load_lua(c, root .. "/ability_names.lua")
  Pokemon._speciesMeta = load_lua(c, root .. "/meta.lua")
  Pokemon._moveNames = load_lua(c, root .. "/move_names.lua")
  Pokemon._romMoveNames = copy_names(Pokemon._moveNames)
  Pokemon._romAbilityNames = copy_names(Pokemon._abilityNames)
  Pokemon._learnsets = load_lua(c, root .. "/learnsets.lua")
  Pokemon._eggMoves = load_lua(c, root .. "/egg_moves.lua")
  Pokemon._evolutions = load_lua(c, root .. "/evolutions.lua")
  Pokemon._tmhm = load_lua(c, root .. "/tmhm.lua")
  Pokemon._dex = load_lua(c, root .. "/dex.lua")
  local battlePack = load_lua(c, root .. "/battle_moves.lua")
  Pokemon._battleMoves = battlePack and battlePack.moves or nil
  Pokemon._byName = build_name_index(Pokemon._names)
  if Pokemon._names then
    log("species pack ready (" .. tostring(Pokemon._manifest and Pokemon._manifest.numSpecies) .. ")")
  else
    log("species pack missing — re-import FireRed ROM")
  end
  Pokemon._runReloadHooks()
end

Pokemon._reloadHooks = {}

function Pokemon.onReload(fn, key)
  if type(fn) ~= "function" then return function() end end
  local hooks = Pokemon._reloadHooks
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

function Pokemon._runReloadHooks()
  local snapshot = {}
  for i, h in ipairs(Pokemon._reloadHooks) do snapshot[i] = h end
  for _, h in ipairs(snapshot) do
    local ok, err = pcall(h.fn, Pokemon)
    if not ok then log("onReload callback failed: " .. tostring(err)) end
  end
end

function Pokemon.invalidate()
  Pokemon._icons = {}
  Pokemon._front = {}
  Pokemon._back = nil
  Pokemon._names = nil
  Pokemon._types = nil
  Pokemon._national = nil
  Pokemon._manifest = nil
  Pokemon._installTried = nil
  Pokemon._installWarned = nil
  Pokemon._byName = nil
  Pokemon._stats = nil
  Pokemon._abilities = nil
  Pokemon._abilityNames = nil
  Pokemon._speciesMeta = nil
  Pokemon._moveNames = nil
  Pokemon._romMoveNames = nil
  Pokemon._romAbilityNames = nil
  Pokemon._learnsets = nil
  Pokemon._eggMoves = nil
  Pokemon._evolutions = nil
  Pokemon._tmhm = nil
  Pokemon._dex = nil
  Pokemon._battleMoves = nil
  Pokemon._logged = false
end

function Pokemon.ready()
  if Pokemon._names then return true end
  local cache = Pokemon._cache
  return PokemonExtract.ready(cache, CachePaths.CACHE_ROOT)
    or load_lua(cache, ROOT .. "/names.lua") ~= nil
end

--- Internal FRLG SPECIES id → display name.
function Pokemon.name(species)
  species = tonumber(species)
  if not species or species < 1 then return "?????" end
  if not Pokemon._names then Pokemon.install(Pokemon._cache) end
  local n = Pokemon._names and Pokemon._names[species]
  if n and n ~= "" then return n end
  error("no ROM species name for species " .. species, 2)
end

function Pokemon.keyName(species)
  species = tonumber(species)
  if not species or species < 1 then return nil end
  if not Pokemon._names then Pokemon.install(Pokemon._cache) end
  local n = Pokemon._names and Pokemon._names[species]
  if type(n) ~= "string" or n == "" or n == "??????????" then return nil end
  n = n:upper()
  n = n:gsub("♀", "_F"):gsub("♂", "_M")
  n = n:gsub("[%.']", "")
  n = n:gsub("[%s%-]+", "_")
  return n
end

function Pokemon.speciesFromName(name)
  if name == nil then return nil end
  if not Pokemon._byName then Pokemon.install(Pokemon._cache) end
  local k = norm_key(name)
  if not k then return nil end
  return Pokemon._byName and Pokemon._byName[k]
end

--- National dex number → internal SPECIES (when pack present).
function Pokemon.speciesFromNational(nat)
  nat = tonumber(nat)
  if not nat or nat < 1 then return nil end
  if not Pokemon._national then Pokemon.install(Pokemon._cache) end
  local t = Pokemon._national
  if t and t.toSpecies and t.toSpecies[nat] then
    return t.toSpecies[nat]
  end
  if nat <= 251 then return nat end
  return nil
end

function Pokemon.national(species)
  species = tonumber(species)
  if not species or species < 1 then return nil end
  if not Pokemon._national then Pokemon.install(Pokemon._cache) end
  local t = Pokemon._national
  if t and t.toNational then return t.toNational[species] end
  if species <= 251 then return species end
  return nil
end

function Pokemon.types(species)
  species = tonumber(species)
  if not species then return { 0, 0 } end
  if not Pokemon._types then Pokemon.install(Pokemon._cache) end
  local t = Pokemon._types and Pokemon._types[species]
  if t then return { t[1] or 0, t[2] or 0 } end
  return { 0, 0 }
end

--- Base stats table { hp, atk, def, spe, spa, spd } or nil.
function Pokemon.stats(species)
  species = tonumber(species)
  if not species then return nil end
  if not Pokemon._stats then Pokemon.install(Pokemon._cache) end
  return Pokemon._stats and Pokemon._stats[species]
end

--- Ability ids { ability1, ability2 }.
function Pokemon.abilities(species)
  species = tonumber(species)
  if not species then return { 0, 0 } end
  if not Pokemon._abilities then Pokemon.install(Pokemon._cache) end
  local a = Pokemon._abilities and Pokemon._abilities[species]
  if a then return { a[1] or 0, a[2] or 0 } end
  return { 0, 0 }
end

function Pokemon.abilityName(abilityId)
  abilityId = tonumber(abilityId)
  if not abilityId or abilityId < 1 then return "-------" end
  if not Pokemon._abilityNames then Pokemon.install(Pokemon._cache) end
  local n = Pokemon._abilityNames and Pokemon._abilityNames[abilityId]
  if n and n ~= "" then return n end
  error("no ROM ability name for ability " .. abilityId, 2)
end

function Pokemon.speciesMeta(species)
  species = tonumber(species)
  if not species then return nil end
  if not Pokemon._speciesMeta then Pokemon.install(Pokemon._cache) end
  return Pokemon._speciesMeta and Pokemon._speciesMeta[species]
end

--- ROM BaseStats.expYield (species meta from extract).
function Pokemon.expYield(species)
  local meta = Pokemon.speciesMeta(species)
  return (meta and tonumber(meta.expYield)) or 0
end

--- ROM BaseStats.growthRate — pret GROWTH_* index into gExperienceTables.
function Pokemon.growthRate(species)
  local meta = Pokemon.speciesMeta(species)
  return (meta and tonumber(meta.growthRate) or 0) % 6
end

-- Gen3 genderRatio specials (match pret constants/pokemon.h).
Pokemon.GENDER_MALE = 0x00
Pokemon.GENDER_FEMALE = 0xFE
Pokemon.GENDER_GENDERLESS = 0xFF

-- Nature → { atk, def, spe, spa, spd } deltas (+1 / −1 / 0).
local NATURE_DELTAS = {
  [0] = { 0, 0, 0, 0, 0 },   -- Hardy
  [1] = { 1, -1, 0, 0, 0 },  -- Lonely
  [2] = { 1, 0, -1, 0, 0 },  -- Brave
  [3] = { 1, 0, 0, -1, 0 },  -- Adamant
  [4] = { 1, 0, 0, 0, -1 },  -- Naughty
  [5] = { -1, 1, 0, 0, 0 },  -- Bold
  [6] = { 0, 0, 0, 0, 0 },   -- Docile
  [7] = { 0, 1, -1, 0, 0 },  -- Relaxed
  [8] = { 0, 1, 0, -1, 0 },  -- Impish
  [9] = { 0, 1, 0, 0, -1 },  -- Lax
  [10] = { -1, 0, 1, 0, 0 }, -- Timid
  [11] = { 0, -1, 1, 0, 0 }, -- Hasty
  [12] = { 0, 0, 0, 0, 0 },  -- Serious
  [13] = { 0, 0, 1, -1, 0 }, -- Jolly
  [14] = { 0, 0, 1, 0, -1 }, -- Naive
  [15] = { -1, 0, 0, 1, 0 }, -- Modest
  [16] = { 0, -1, 0, 1, 0 }, -- Mild
  [17] = { 0, 0, -1, 1, 0 }, -- Quiet
  [18] = { 0, 0, 0, 0, 0 },  -- Bashful
  [19] = { 0, 0, 0, 1, -1 }, -- Rash
  [20] = { -1, 0, 0, 0, 1 }, -- Calm
  [21] = { 0, -1, 0, 0, 1 }, -- Gentle
  [22] = { 0, 0, -1, 0, 1 }, -- Sassy
  [23] = { 0, 0, 0, -1, 1 }, -- Careful
  [24] = { 0, 0, 0, 0, 0 },  -- Quirky
}

function Pokemon.natureId(personality)
  return (tonumber(personality) or 0) % 25
end

function Pokemon.gender(species, personality)
  species = tonumber(species)
  personality = tonumber(personality) or 0
  local meta = Pokemon.speciesMeta(species)
  local ratio = meta and meta.genderRatio
  if ratio == nil then return "U" end
  if ratio == Pokemon.GENDER_MALE then return "M" end
  if ratio == Pokemon.GENDER_FEMALE then return "F" end
  if ratio == Pokemon.GENDER_GENDERLESS then return "U" end
  if ratio > (personality % 256) then return "F" end
  return "M"
end

--- Ability id for species + personality (ability1 vs ability2).
function Pokemon.abilityId(species, personality)
  species = tonumber(species)
  personality = tonumber(personality) or 0
  local pair = Pokemon.abilities(species)
  local a1, a2 = pair[1] or 0, pair[2] or 0
  if a2 ~= 0 and (personality % 2) == 1 then
    return a2
  end
  return a1
end

local function nature_mul(nature, statIndex)
  -- statIndex: 1=atk 2=def 3=spe 4=spa 5=spd
  local d = NATURE_DELTAS[nature % 25]
  if not d then return 1 end
  local delta = d[statIndex] or 0
  if delta > 0 then return 1.1 end
  if delta < 0 then return 0.9 end
  return 1
end

--- Gen3 CalculateMonStats → { maxHp, attack, defense, speed, spAtk, spDef }.
function Pokemon.calcStats(species, level, ivs, evs, personality)
  species = tonumber(species)
  level = tonumber(level) or 1
  ivs = ivs or {}
  evs = evs or {}
  local base = Pokemon.stats(species)
  if not base then
    return {
      maxHp = 15 + level * 2,
      attack = 10, defense = 10, speed = 10, spAtk = 10, spDef = 10,
    }
  end
  local nature = Pokemon.natureId(personality)
  local function iv(k) return tonumber(ivs[k]) or 0 end
  local function ev(k) return tonumber(evs[k]) or 0 end

  local maxHp
  if species == 303 then -- pokefirered/src/pokemon.c:2124 SPECIES_SHEDINJA
    maxHp = 1
  else
    maxHp = math.floor(((2 * base.hp + iv("hp") + math.floor(ev("hp") / 4)) * level) / 100)
      + level + 10
  end

  local function other(baseStat, ivKey, evKey, natureIdx)
    local n = math.floor(((2 * baseStat + iv(ivKey) + math.floor(ev(evKey) / 4)) * level) / 100) + 5
    return math.floor(n * nature_mul(nature, natureIdx))
  end

  return {
    maxHp = maxHp,
    attack = other(base.atk, "atk", "atk", 1),
    defense = other(base.def, "def", "def", 2),
    speed = other(base.spe, "spe", "spe", 3),
    spAtk = other(base.spa, "spa", "spa", 4),
    spDef = other(base.spd, "spd", "spd", 5),
  }
end

--- Fill battle/display stats on an opaque mon (mutates and returns mon).
function Pokemon.applyStats(mon)
  if type(mon) ~= "table" then return mon end
  local species = tonumber(mon.species or mon.speciesId) or 1
  local level = tonumber(mon.level) or 5
  local ivs = mon.ivs or {}
  local evs = mon.evs or {}
  local personality = mon.personality or 0
  local st = Pokemon.calcStats(species, level, ivs, evs, personality)
  mon.maxHp = st.maxHp
  if mon.hp == nil or mon.hp < 0 or mon.hp > st.maxHp then
    mon.hp = st.maxHp
  end
  mon.attack = st.attack
  mon.defense = st.defense
  mon.speed = st.speed
  mon.spAtk = st.spAtk
  mon.spDef = st.spDef
  -- Aliases used by some battle paths.
  mon.atk = st.attack
  mon.def = st.defense
  mon.spe = st.speed
  mon.spa = st.spAtk
  mon.spd = st.spDef
  return mon
end

-- pokefirered/include/constants/pokemon.h:215
Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL = 0
Pokemon.FRIENDSHIP_EVENT_VITAMIN = 1
Pokemon.FRIENDSHIP_EVENT_BATTLE_ITEM = 2
Pokemon.FRIENDSHIP_EVENT_LEAGUE_BATTLE = 3
Pokemon.FRIENDSHIP_EVENT_LEARN_TMHM = 4
Pokemon.FRIENDSHIP_EVENT_WALKING = 5
Pokemon.FRIENDSHIP_EVENT_MASSAGE = 6
Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL = 7
Pokemon.FRIENDSHIP_EVENT_FAINT_OUTSIDE_BATTLE = 8
Pokemon.FRIENDSHIP_EVENT_FAINT_LARGE = 9

-- pokefirered/include/constants/pokemon.h:226,233
Pokemon.MAX_FRIENDSHIP = 255
Pokemon.MAX_PER_STAT_EVS = 255
Pokemon.MAX_TOTAL_EVS = 510
Pokemon.EV_ITEM_RAISE_LIMIT = 100

Pokemon.SPECIES_EGG = 412
local ITEM_LUXURY_BALL = 11 -- pokefirered/include/constants/items.h:15
local HOLD_EFFECT_MACHO_BRACE = 24 -- pokefirered/include/constants/hold_effects.h:28
local HOLD_EFFECT_FRIENDSHIP_UP = 27 -- pokefirered/include/constants/hold_effects.h:31

-- pokefirered/src/pokemon.c:1618 sFriendshipEventDeltas
local FRIENDSHIP_DELTAS = {
  [0] = { 5, 3, 2 },
  [1] = { 5, 3, 2 },
  [2] = { 1, 1, 0 },
  [3] = { 3, 2, 1 },
  [4] = { 1, 1, 0 },
  [5] = { 1, 1, 1 },
  [6] = { 3, 3, 3 },
  [7] = { -1, -1, -1 },
  [8] = { -5, -5, -10 },
  [9] = { -5, -5, -10 },
}

-- pokefirered/include/constants/pokemon.h:166
local EV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
local EV_YIELD_KEYS = { "evHp", "evAtk", "evDef", "evSpe", "evSpa", "evSpd" }
Pokemon.EV_KEYS = EV_KEYS

-- pokefirered/include/pokemon.h:229
function Pokemon.baseFriendship(species)
  local meta = Pokemon.speciesMeta(species)
  local v = meta and tonumber(meta.friendship)
  if v then return v end
  return 70
end

-- pokefirered/include/pokemon.h:219
function Pokemon.evYield(species)
  if type(species) == "table" then
    species = tonumber(species.species or species.speciesId)
  end
  local meta = Pokemon.speciesMeta(species)
  local out = {}
  for i = 1, 6 do
    out[EV_KEYS[i]] = (meta and tonumber(meta[EV_YIELD_KEYS[i]])) or 0
  end
  return out
end

-- pokefirered/src/pokemon.c:1815
function Pokemon.friendshipOf(mon)
  if type(mon) ~= "table" then return 0 end
  local v = tonumber(mon.friendship or mon.happiness)
  if v then return v end
  return Pokemon.baseFriendship(tonumber(mon.species or mon.speciesId))
end

function Pokemon.setFriendship(mon, value)
  if type(mon) ~= "table" then return 0 end
  value = math.floor(tonumber(value) or 0)
  if value < 0 then value = 0 end
  if value > Pokemon.MAX_FRIENDSHIP then value = Pokemon.MAX_FRIENDSHIP end
  mon.friendship = value
  mon.happiness = value
  return value
end

function Pokemon.evsOf(mon)
  if type(mon) ~= "table" then return {} end
  local evs = mon.evs
  if type(evs) ~= "table" then
    evs = {}
    mon.evs = evs
  end
  for i = 1, 6 do
    local k = EV_KEYS[i]
    evs[k] = math.max(0, math.min(Pokemon.MAX_PER_STAT_EVS, math.floor(tonumber(evs[k]) or 0)))
  end
  return evs
end

-- pokefirered/src/pokemon.c:5597 GetMonEVCount
function Pokemon.evCount(mon)
  local evs = Pokemon.evsOf(mon)
  local count = 0
  for i = 1, 6 do
    count = count + (tonumber(evs[EV_KEYS[i]]) or 0)
  end
  return count
end

local function hold_effect_of(mon)
  local ok, HeldItems = pcall(require, "src.core.game3.battle.held_items")
  if not ok or not HeldItems or not HeldItems.effectOf then return 0 end
  local effect = HeldItems.effectOf(mon and (mon.item or mon.heldItem))
  return tonumber(effect) or 0
end

-- pokefirered/src/pokemon.c:5630 CheckPartyPokerus
function Pokemon.hasPokerus(mon)
  return (tonumber(mon and mon.pokerus) or 0) % 16 ~= 0
end

-- pokefirered/src/pokemon.c:5646 CheckPartyHasHadPokerus
function Pokemon.hasHadPokerus(mon)
  return (tonumber(mon and mon.pokerus) or 0) ~= 0
end

function Pokemon.checkPartyPokerus(party, selection)
  if type(party) ~= "table" then return 0 end
  if not selection or selection == 0 then
    return Pokemon.hasPokerus(party[1]) and 1 or 0
  end
  local retVal, curBit, index = 0, 1, 1
  while selection ~= 0 do
    if selection % 2 == 1 and Pokemon.hasPokerus(party[index]) then
      retVal = retVal + curBit
    end
    index = index + 1
    curBit = curBit * 2
    selection = math.floor(selection / 2)
  end
  return retVal
end

function Pokemon.checkPartyHasHadPokerus(party, selection)
  if type(party) ~= "table" then return 0 end
  if not selection or selection == 0 then
    return Pokemon.hasHadPokerus(party[1]) and 1 or 0
  end
  local retVal, curBit, index = 0, 1, 1
  while selection ~= 0 do
    if selection % 2 == 1 and Pokemon.hasHadPokerus(party[index]) then
      retVal = retVal + curBit
    end
    index = index + 1
    curBit = curBit * 2
    selection = math.floor(selection / 2)
  end
  return retVal
end

-- pokefirered/src/pokemon.c:5612, :5676, :5682 (all stubbed in FRLG)
function Pokemon.randomlyGivePartyPokerus(_) end
function Pokemon.updatePartyPokerusTime(_) end
function Pokemon.partySpreadPokerus(_) end

-- pokefirered/src/pokemon.c:5512 MonGainEVs
function Pokemon.gainEVs(mon, defeatedSpecies)
  if type(mon) ~= "table" then return nil end
  local evs = Pokemon.evsOf(mon)
  local cur, total = {}, 0
  for i = 1, 6 do
    cur[i] = tonumber(evs[EV_KEYS[i]]) or 0
    total = total + cur[i]
  end
  local yield = Pokemon.evYield(defeatedSpecies)
  local multiplier = Pokemon.hasHadPokerus(mon) and 2 or 1
  local macho = hold_effect_of(mon) == HOLD_EFFECT_MACHO_BRACE
  local gained = 0
  for i = 1, 6 do
    if total >= Pokemon.MAX_TOTAL_EVS then break end
    local inc = (tonumber(yield[EV_KEYS[i]]) or 0) * multiplier
    if macho then inc = inc * 2 end
    if total + inc > Pokemon.MAX_TOTAL_EVS then
      inc = Pokemon.MAX_TOTAL_EVS - total
    end
    if cur[i] + inc > Pokemon.MAX_PER_STAT_EVS then
      inc = Pokemon.MAX_PER_STAT_EVS - cur[i]
    end
    cur[i] = cur[i] + inc
    total = total + inc
    gained = gained + inc
    evs[EV_KEYS[i]] = cur[i]
  end
  return gained
end

-- pokefirered/src/overworld.c:1265 GetCurrentRegionMapSectionId
function Pokemon.currentMapSec(session)
  session = session or {}
  local sec = tonumber(session.regionMapSectionId or session.mapSec)
  if sec then return sec end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local def = session.map and game and game.data and game.data.maps and game.data.maps[session.map]
  return def and tonumber(def.regionMapSectionId) or nil
end

local function player_identity(player)
  player = player or {}
  local id = player.trainerId or player.id or player.playerId
  local name = player.name or player.playerName or player.otName
  if id == nil or name == nil then
    local Runtime = package.loaded["src.core.game3.runtime"]
    local ok, sess = pcall(function()
      return Runtime and Runtime.getSession and Runtime.getSession()
    end)
    if ok and sess then
      id = id or sess.trainerId or sess.id or sess.playerId
      name = name or sess.name or sess.playerName
    end
  end
  return tonumber(id), name
end

-- pokefirered/src/pokemon.c:5974 IsOtherTrainer
function Pokemon.isOtherTrainer(otId, otName, player)
  local playerId, playerName = player_identity(player)
  if playerId == nil then return false end
  if tonumber(otId) ~= playerId then return true end
  local mine = tostring(playerName or "")
  local theirs = tostring(otName or "")
  for i = 1, #theirs do
    if theirs:sub(i, i) ~= mine:sub(i, i) then return true end
  end
  return false
end

-- pokefirered/src/pokemon.c:5965 IsTradedMon
function Pokemon.isTradedMon(mon, player)
  if type(mon) ~= "table" or mon.otId == nil then return false end
  return Pokemon.isOtherTrainer(mon.otId, mon.otName or mon.ot, player)
end

local function friendship_bonuses(mon, friendship, ctx)
  if (tonumber(mon.pokeball or mon.ball) or 0) == ITEM_LUXURY_BALL then
    friendship = friendship + 1
  end
  local sec = ctx and tonumber(ctx.mapSec)
  local met = tonumber(mon.metLocation)
  if sec and met and met == sec then
    friendship = friendship + 1
  end
  return friendship
end

-- pokefirered/include/constants/trainers.h:267
Pokemon.LEAGUE_TRAINER_CLASSES = { [84] = true, [87] = true, [90] = true }

-- pokefirered/src/pokemon.c:5480
function Pokemon.isLeagueTrainerClass(trainerClass)
  local cls = tonumber(trainerClass)
  return (cls ~= nil) and Pokemon.LEAGUE_TRAINER_CLASSES[cls] == true
end

-- pokefirered/src/pokemon.c:5440 AdjustFriendship
function Pokemon.adjustFriendship(mon, event, ctx)
  if type(mon) ~= "table" then return false end
  ctx = ctx or {}
  local species = tonumber(mon.species or mon.speciesId) or 0
  if species == 0 or species == Pokemon.SPECIES_EGG or mon.isEgg or mon.egg then
    return false
  end
  local deltas = FRIENDSHIP_DELTAS[tonumber(event)]
  if not deltas then return false end

  local friendship = Pokemon.friendshipOf(mon)
  local tier = 1
  if friendship >= 100 then tier = tier + 1 end
  if friendship >= 200 then tier = tier + 1 end

  if event == Pokemon.FRIENDSHIP_EVENT_WALKING then
    local okR, Rng = pcall(require, "src.core.game3.rng")
    if okR and Rng and Rng.Random and Rng.Random() % 2 == 1 then return false end
  end
  if event == Pokemon.FRIENDSHIP_EVENT_LEAGUE_BATTLE and not ctx.leagueBattle then
    return false
  end

  local delta = deltas[tier]
  if delta > 0 and hold_effect_of(mon) == HOLD_EFFECT_FRIENDSHIP_UP then
    delta = math.floor(150 * delta / 100)
  end
  friendship = friendship + delta
  if delta > 0 then
    friendship = friendship_bonuses(mon, friendship, ctx)
  end
  Pokemon.setFriendship(mon, friendship)
  return true
end

-- pokefirered/src/battle_util2.c:78 AdjustFriendshipOnBattleFaint
function Pokemon.adjustFriendshipOnBattleFaint(mon, faintedLevel, opposingLevel, ctx)
  faintedLevel = tonumber(faintedLevel) or 1
  opposingLevel = tonumber(opposingLevel) or 1
  local event = Pokemon.FRIENDSHIP_EVENT_FAINT_SMALL
  if opposingLevel > faintedLevel and opposingLevel - faintedLevel > 29 then
    event = Pokemon.FRIENDSHIP_EVENT_FAINT_LARGE
  end
  return Pokemon.adjustFriendship(mon, event, ctx)
end

-- pokefirered/src/pokemon.c:3976 UPDATE_FRIENDSHIP_FROM_ITEM
function Pokemon.itemFriendship(mon, lowMidHigh, ctx)
  if type(mon) ~= "table" or type(lowMidHigh) ~= "table" then return false end
  local friendship = Pokemon.friendshipOf(mon)
  local change
  if friendship < 100 then
    change = tonumber(lowMidHigh[1])
  elseif friendship < 200 then
    change = tonumber(lowMidHigh[2])
  else
    change = tonumber(lowMidHigh[3])
  end
  if not change or change == 0 then return false end
  if change > 0 and hold_effect_of(mon) == HOLD_EFFECT_FRIENDSHIP_UP then
    friendship = friendship + math.floor(150 * change / 100)
  else
    friendship = friendship + change
  end
  if change > 0 then
    friendship = friendship_bonuses(mon, friendship, ctx)
  end
  Pokemon.setFriendship(mon, friendship)
  return true
end

-- pokefirered/src/data/pokemon/item_effects.h:163 VITAMIN_FRIENDSHIP_CHANGE
Pokemon.VITAMIN_FRIENDSHIP_CHANGE = { 5, 3, 2 }
-- pokefirered/src/data/pokemon/item_effects.h:225 STAT_BOOST_FRIENDSHIP_CHANGE
Pokemon.STAT_BOOST_FRIENDSHIP_CHANGE = { 1, 1, 0 }

-- pokefirered/src/pokemon.c:4229
function Pokemon.raiseEvFromItem(mon, statKey, amount)
  local evs = Pokemon.evsOf(mon)
  if evs[statKey] == nil then return nil end
  local evCount = Pokemon.evCount(mon)
  if evCount >= Pokemon.MAX_TOTAL_EVS then return nil end
  local data = tonumber(evs[statKey]) or 0
  if data >= Pokemon.EV_ITEM_RAISE_LIMIT then return nil end
  amount = math.floor(tonumber(amount) or 0)
  local delta = amount
  if data + amount > Pokemon.EV_ITEM_RAISE_LIMIT then
    delta = Pokemon.EV_ITEM_RAISE_LIMIT - data
  end
  if evCount + delta > Pokemon.MAX_TOTAL_EVS then
    delta = Pokemon.MAX_TOTAL_EVS - evCount
  end
  evs[statKey] = data + delta
  -- pokefirered/src/pokemon.c:2155
  local oldMaxHp = tonumber(mon.maxHp) or 0
  local oldHp = tonumber(mon.hp) or 0
  Pokemon.applyStats(mon)
  local newMaxHp = tonumber(mon.maxHp) or oldMaxHp
  if oldHp ~= 0 or oldMaxHp ~= 0 then
    mon.hp = math.max(0, math.min(newMaxHp, oldHp + (newMaxHp - oldMaxHp)))
  end
  return delta
end

-- The ROM's English name for a move or ability number, whatever a mod renamed
-- it to; nil when the pack has none.
function Pokemon.romMoveName(num)
  num = tonumber(num)
  if not num then return nil end
  if not Pokemon._moveNames then Pokemon.install(Pokemon._cache) end
  return Pokemon._romMoveNames and Pokemon._romMoveNames[num]
end

function Pokemon.romAbilityName(abilityId)
  abilityId = tonumber(abilityId)
  if not abilityId then return nil end
  if not Pokemon._abilityNames then Pokemon.install(Pokemon._cache) end
  return Pokemon._romAbilityNames and Pokemon._romAbilityNames[abilityId]
end

function Pokemon.moveName(moveId)
  if type(moveId) == "table" then
    moveId = moveId.id or moveId.move or moveId.moveId or moveId.num or moveId.name or moveId[1]
  end
  local num = tonumber(moveId)
  if not num and type(moveId) == "string" then
    local Moves = package.loaded["src.core.game3.battle.moves"]
    if Moves and Moves.numForName then
      num = Moves.numForName(moveId)
    end
    if not num then
      if moveId ~= "" and moveId ~= "-------" then
        return tostring(moveId):gsub("_", " "):upper()
      end
    end
  end
  if not num or num < 1 then return "-------" end
  if not Pokemon._moveNames then Pokemon.install(Pokemon._cache) end
  local n = Pokemon._moveNames and Pokemon._moveNames[num]
  if n and n ~= "" then return n end
  local okB, BuiltinMoves = pcall(require, "src.core.game3.battle.builtin_moves")
  if okB and BuiltinMoves and BuiltinMoves[num] and BuiltinMoves[num].name then
    return BuiltinMoves[num].name
  end
  return "MOVE " .. tostring(num)
end

function Pokemon.learnset(species)
  if type(species) == "table" then species = Pokemon.speciesOf(species) end
  if type(species) == "string" then species = Pokemon.speciesFromName(species) or tonumber(species) end
  species = tonumber(species)
  if not species then return {} end
  if not Pokemon._learnsets then Pokemon.install(Pokemon._cache) end
  return (Pokemon._learnsets and Pokemon._learnsets[species]) or {}
end

--- Egg move ids for a species (FRLG gEggMoves), or nil when it has none.
--- Mirrors Pokemon.learnset's species coercion so mods can pass either form.
function Pokemon.eggMoves(species)
  if type(species) == "table" then species = Pokemon.speciesOf(species) end
  if type(species) == "string" then species = Pokemon.speciesFromName(species) or tonumber(species) end
  species = tonumber(species)
  if not species then return nil end
  if not Pokemon._eggMoves then Pokemon.install(Pokemon._cache) end
  local list = Pokemon._eggMoves and Pokemon._eggMoves[species]
  if type(list) ~= "table" or #list == 0 then return nil end
  return list
end

function Pokemon.evolutions(species)
  if type(species) == "table" then species = Pokemon.speciesOf(species) end
  if type(species) == "string" then species = Pokemon.speciesFromName(species) or tonumber(species) end
  species = tonumber(species)
  if not species then return {} end
  if not Pokemon._evolutions then Pokemon.install(Pokemon._cache) end
  return (Pokemon._evolutions and Pokemon._evolutions[species]) or {}
end

function Pokemon.dexEntry(species)
  if type(species) == "table" then species = Pokemon.speciesOf(species) end
  if type(species) == "string" then species = Pokemon.speciesFromName(species) or tonumber(species) end
  species = tonumber(species)
  if not species then return nil end
  if not Pokemon._dex then Pokemon.install(Pokemon._cache) end
  local nat = Pokemon.national(species)
  if not nat or not Pokemon._dex then return nil end
  return Pokemon._dex[nat]
end

function Pokemon.battleMove(moveId)
  moveId = tonumber(moveId)
  if not moveId then return nil end
  if not Pokemon._battleMoves then Pokemon.install(Pokemon._cache) end
  if Pokemon._battleMoves and Pokemon._battleMoves[moveId] then
    return Pokemon._battleMoves[moveId]
  end
  local okB, BuiltinMoves = pcall(require, "src.core.game3.battle.builtin_moves")
  if okB and BuiltinMoves and BuiltinMoves[moveId] then
    return BuiltinMoves[moveId]
  end
  return nil
end

function Pokemon.movePp(moveId)
  moveId = tonumber(moveId)
  if not moveId or moveId < 1 then return 5 end
  local row = Pokemon.battleMove(moveId)
  return (row and tonumber(row.pp)) or 5
end
Pokemon.moveMaxPp = Pokemon.movePp

--- FRLG GiveBoxMonInitialMoveset: learn all ≤ level; if full, drop first; avoid duplicates.
function Pokemon.movesAtLevel(species, level)
  if type(species) == "table" then species = Pokemon.speciesOf(species) end
  if type(species) == "string" then species = Pokemon.speciesFromName(species) or tonumber(species) end
  species = tonumber(species)
  level = tonumber(level) or 1
  local set = Pokemon.learnset(species)
  local moves = {}
  local pp = {}
  local maxPp = {}

  local function giveMove(moveId)
    if not moveId or moveId <= 0 then return end
    for i = 1, #moves do
      if moves[i] == moveId then
        return -- already knows this move (pret GiveMoveToBoxMon)
      end
    end
    local mpp = Pokemon.movePp(moveId)
    if #moves < 4 then
      moves[#moves + 1] = moveId
      pp[#pp + 1] = mpp
      maxPp[#maxPp + 1] = mpp
    else
      table.remove(moves, 1)
      table.remove(pp, 1)
      table.remove(maxPp, 1)
      moves[4] = moveId
      pp[4] = mpp
      maxPp[4] = mpp
    end
  end

  for _, e in ipairs(set) do
    local lv = e[1] or e.level or 0
    local mv = tonumber(e[2] or e.move) or 0
    if lv > level then
      break
    end
    giveMove(mv)
  end

  return moves, pp, maxPp
end

--- Moves learned at exactly `level` (ROM learnset). Order preserved.
function Pokemon.movesLearnedAt(species, level)
  if type(species) == "table" then species = Pokemon.speciesOf(species) end
  if type(species) == "string" then species = Pokemon.speciesFromName(species) or tonumber(species) end
  species = tonumber(species)
  level = tonumber(level) or 0
  local out = {}
  if not species or level < 1 then return out end
  for _, e in ipairs(Pokemon.learnset(species)) do
    local lv = e[1] or e.level or 0
    local mv = tonumber(e[2] or e.move) or 0
    if lv == level and mv > 0 then
      out[#out + 1] = mv
    elseif lv > level then
      break
    end
  end
  return out
end

function Pokemon.moveIdAt(mon, slot)
  if not mon or not mon.moves then return nil end
  local entry = mon.moves[slot]
  if type(entry) == "table" then return tonumber(entry.id or entry.move) end
  return tonumber(entry)
end

function Pokemon.knowsMove(mon, moveId)
  moveId = tonumber(moveId)
  if not mon or not moveId then return false end
  for i = 1, 4 do
    if Pokemon.moveIdAt(mon, i) == moveId then return true end
  end
  return false
end

function Pokemon.moveSlotCount(mon)
  local n = 0
  for i = 1, 4 do
    local id = Pokemon.moveIdAt(mon, i)
    if id and id > 0 then n = n + 1 end
  end
  return n
end

-- FRLG HM move IDs (cannot forget).
local HM_MOVES = {
  [15] = true,  -- CUT
  [19] = true,  -- FLY
  [57] = true,  -- SURF
  [70] = true,  -- STRENGTH
  [148] = true, -- FLASH
  [249] = true, -- ROCK SMASH
  [127] = true, -- WATERFALL
  [291] = true, -- DIVE
}

function Pokemon.isHmMove(moveId)
  return HM_MOVES[tonumber(moveId) or 0] == true
end

--- Item id 289 (TM01) … 346 (HM08) → battle move id via extracted sTMHMMoves.
function Pokemon.moveFromTmItem(itemId)
  local num = tonumber(itemId)
  if not num then
    local ItemsData = require("src.core.game3.items_data")
    num = ItemsData.toNumericId(itemId)
  end
  if not num or num < 289 or num > 346 then return nil end
  if not Pokemon._tmhm then Pokemon.install(Pokemon._cache) end
  local machines = Pokemon._tmhm and Pokemon._tmhm.machines
  if not machines then return nil end
  local tmIndex = num - 289 -- 0-based TM01
  return tonumber(machines[tmIndex])
end

--- Can this species learn TM/HM machine index (0..57)?
function Pokemon.canLearnTmIndex(species, tmIndex)
  species = tonumber(species)
  tmIndex = tonumber(tmIndex)
  if not species or not tmIndex or tmIndex < 0 or tmIndex > 57 then return false end
  if not Pokemon._tmhm then Pokemon.install(Pokemon._cache) end
  local row = Pokemon._tmhm and Pokemon._tmhm.learnsets and Pokemon._tmhm.learnsets[species]
  if not row then return false end
  local lo = tonumber(row.lo) or 0
  local hi = tonumber(row.hi) or 0
  if tmIndex < 32 then
    return math.floor(lo / (2 ^ tmIndex)) % 2 == 1
  end
  return math.floor(hi / (2 ^ (tmIndex - 32))) % 2 == 1
end

function Pokemon.canLearnTmItem(species, itemId)
  local num = tonumber(itemId)
  if not num then
    local ItemsData = require("src.core.game3.items_data")
    num = ItemsData.toNumericId(itemId)
  end
  if not num or num < 289 or num > 346 then return false end
  return Pokemon.canLearnTmIndex(species, num - 289)
end

local function move_max_pp(moveId)
  local row = Pokemon.battleMove(moveId)
  return (row and tonumber(row.pp)) or 5
end

--- Teach move into first empty slot. Returns true if taught.
function Pokemon.teachMove(mon, moveId)
  moveId = tonumber(moveId)
  if not mon or not moveId or moveId < 1 then return false end
  if Pokemon.knowsMove(mon, moveId) then return false end
  mon.moves = mon.moves or {}
  mon.pp = mon.pp or {}
  mon.maxPp = mon.maxPp or {}
  for i = 1, 4 do
    local id = Pokemon.moveIdAt(mon, i)
    if not id or id == 0 then
      mon.moves[i] = moveId
      local max = move_max_pp(moveId)
      mon.pp[i] = max
      mon.maxPp[i] = max
      -- pokefirered/src/pokemon.c:2208
      if ModRuntime.wants("pokemon.move_learned") then
        ModRuntime.emit("pokemon.move_learned", {
          mon = mon, moveId = require("src.mods.Gen3Compat").moveName(moveId),
          moveNum = moveId, slot = i,
        })
      end
      return true, i
    end
  end
  return false
end

--- Replace move at 1-based slot. Returns forgotten move id.
function Pokemon.replaceMove(mon, slot, newMoveId)
  slot = tonumber(slot)
  newMoveId = tonumber(newMoveId)
  if not mon or not slot or slot < 1 or slot > 4 or not newMoveId then return nil end
  local old = Pokemon.moveIdAt(mon, slot)
  if Pokemon.isHmMove(old) then return nil, "hm" end
  mon.moves = mon.moves or {}
  mon.pp = mon.pp or {}
  mon.maxPp = mon.maxPp or {}
  mon.moves[slot] = newMoveId
  local max = move_max_pp(newMoveId)
  mon.pp[slot] = max
  mon.maxPp[slot] = max
  -- pokefirered/src/pokemon.c:2248
  if ModRuntime.wants("pokemon.move_learned") then
    local G3 = require("src.mods.Gen3Compat")
    ModRuntime.emit("pokemon.move_learned", {
      mon = mon, moveId = G3.moveName(newMoveId), moveNum = newMoveId, slot = slot,
      forgotten = G3.moveName(old), forgottenNum = tonumber(old),
    })
  end
  return old
end

-- An egg reads as the language's own EGG whatever its nickname holds: pret's
-- GetMonData(MON_DATA_NICKNAME) returns gText_EggNickname for any egg
-- (pokefirered/src/pokemon.c:3020).  The stored nickname is only a placeholder
-- -- the cart's daycare writes タマゴ (daycare.c:1100), this engine "EGG".
local function eggName(mon)
  if Pokemon.isEgg(mon) then return require("src.core.game3.rom_text").plain("gText_EggNickname") end
end

function Pokemon.displayMonName(mon)
  if not mon then return "POKéMON" end
  local egg = eggName(mon)
  if egg then return egg end
  local nick = mon.nickname
  if type(nick) == "string" and nick ~= "" then return nick end
  if mon.name and mon.name ~= "" then return mon.name end
  local sp = Pokemon.speciesOf(mon)
  return (sp and Pokemon.name(sp)) or "POKéMON"
end

--- Atomically swap two move slots on a Pokémon, keeping move ID, PP, and PP bonuses in sync.
--- Solves the PP Swap Trap.
function Pokemon.swapMoves(mon, slotA, slotB)
  if not mon or not slotA or not slotB then return false end
  slotA = tonumber(slotA)
  slotB = tonumber(slotB)
  if not slotA or not slotB or slotA < 1 or slotA > 4 or slotB < 1 or slotB > 4 then
    return false
  end
  if slotA == slotB then return true end

  -- 1. If mon.moves is an array of tables: { id = ..., pp = ..., ppBonuses = ... }
  if type(mon.moves) == "table" then
    local entryA = mon.moves[slotA]
    local entryB = mon.moves[slotB]
    mon.moves[slotA] = entryB
    mon.moves[slotB] = entryA
  end

  -- 2. If parallel array mon.moveIds exists
  if type(mon.moveIds) == "table" then
    local idA = mon.moveIds[slotA]
    mon.moveIds[slotA] = mon.moveIds[slotB]
    mon.moveIds[slotB] = idA
  end

  -- 3. If parallel array mon.pp exists
  if type(mon.pp) == "table" then
    local ppA = mon.pp[slotA]
    mon.pp[slotA] = mon.pp[slotB]
    mon.pp[slotB] = ppA
  end

  -- 4. If parallel array mon.ppBonuses / mon.ppBonus / mon.ppUp exists
  if type(mon.ppBonuses) == "table" then
    local bA = mon.ppBonuses[slotA]
    mon.ppBonuses[slotA] = mon.ppBonuses[slotB]
    mon.ppBonuses[slotB] = bA
  end
  if type(mon.ppBonus) == "table" then
    local bA = mon.ppBonus[slotA]
    mon.ppBonus[slotA] = mon.ppBonus[slotB]
    mon.ppBonus[slotB] = bA
  end
  if type(mon.ppUp) == "table" then
    local bA = mon.ppUp[slotA]
    mon.ppUp[slotA] = mon.ppUp[slotB]
    mon.ppUp[slotB] = bA
  end

  -- 5. If PP bonuses are stored as packed bits (Gen 3 BoxMon / Pokemon: 2 bits per slot)
  if type(mon.ppBonusesPacked) == "number" then
    local packed = mon.ppBonusesPacked
    local shiftA = (slotA - 1) * 2
    local shiftB = (slotB - 1) * 2
    local bonusA = bit.band(bit.rshift(packed, shiftA), 3)
    local bonusB = bit.band(bit.rshift(packed, shiftB), 3)
    packed = bit.band(packed, bit.bnot(bit.bor(bit.lshift(3, shiftA), bit.lshift(3, shiftB))))
    packed = bit.bor(packed, bit.lshift(bonusA, shiftB), bit.lshift(bonusB, shiftA))
    mon.ppBonusesPacked = packed
  end

  -- 6. If an active overlay exists on the mon (e.g. party menu overlay)
  if type(mon.overlay) == "table" then
    local ovA = mon.overlay[slotA]
    mon.overlay[slotA] = mon.overlay[slotB]
    mon.overlay[slotB] = ovA
  end

  return true
end

function Pokemon.isEgg(mon)
  if not mon then return false end
  return (mon.isEgg == true) or (mon.egg == true) or (mon.species == 412)
end

-- pokefirered/src/pokemon.c:3245 MON_DATA_SPECIES_OR_EGG: an egg's menu icon is
-- SPECIES_EGG's, not the species it will hatch into (party_menu.c:2655).
function Pokemon.speciesOrEgg(mon)
  if Pokemon.isEgg(mon) then return Pokemon.SPECIES_EGG end
  return Pokemon.speciesOf(mon)
end

local SPECIES_UNOWN = 201
local SPECIES_UNOWN_B = 413

-- pokefirered/src/pokemon_icon.c:1080
function Pokemon.unownLetter(personality)
  local p = (tonumber(personality) or 0) % 4294967296
  if p == 0 then return 0 end
  local function bits(shift) return math.floor(p / 2 ^ shift) % 4 end
  return (bits(24) * 64 + bits(16) * 16 + bits(8) * 4 + bits(0)) % 28
end

-- pokefirered/src/decompress.c:85, src/pokemon_icon.c:1056
function Pokemon.picSpecies(species, personality)
  species = tonumber(species)
  if species ~= SPECIES_UNOWN then return species end
  local letter = Pokemon.unownLetter(personality)
  if letter == 0 then return SPECIES_UNOWN end
  return SPECIES_UNOWN_B + letter - 1
end

-- pokefirered/src/pokemon.c:6062
function Pokemon.isShiny(mon)
  if not mon then return false end
  if mon.isShiny ~= nil then return not not mon.isShiny end
  local p = (tonumber(mon.personality) or 0) % 4294967296
  local tid = (tonumber(mon.otId or mon.trainerId) or 0) % 65536
  local sid = (tonumber(mon.otSecretId) or 0) % 65536
  local value = bit.bxor(bit.bxor(tid, sid), bit.bxor(math.floor(p / 65536), p % 65536))
  return value < 8
end

function Pokemon.monPicSpecies(mon)
  if Pokemon.isEgg(mon) then return Pokemon.SPECIES_EGG end
  return Pokemon.picSpecies(Pokemon.speciesOf(mon), mon and mon.personality)
end

function Pokemon.monFrontPic(mon, form)
  return Pokemon.frontPic(Pokemon.monPicSpecies(mon), form, Pokemon.isShiny(mon), mon and mon.personality)
end

function Pokemon.monBackPic(mon, form)
  return Pokemon.backPic(Pokemon.monPicSpecies(mon), form, Pokemon.isShiny(mon))
end

-- pokefirered/src/pokemon_icon.c:1116
function Pokemon.monIcon(mon)
  return Pokemon.icon(Pokemon.monPicSpecies(mon))
end

local function read_rgba(species)
  local cache = resolve_cache(Pokemon._cache)
  local root = (CachePaths.CACHE_ROOT or "data/generated/gba") .. "/pokemon"
  local rel = root .. "/icons/" .. species .. ".rgba"
  local d = cache:read(rel)
  if type(d) == "string" and #d > 0 then return d end
  return nil
end

local function image_from_rgba(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then
    imageData = love.image.newImageData(w, h)
    local i = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        imageData:setPixel(x, y,
          (rgba:byte(i) or 0) / 255,
          (rgba:byte(i + 1) or 0) / 255,
          (rgba:byte(i + 2) or 0) / 255,
          (rgba:byte(i + 3) or 0) / 255)
        i = i + 4
      end
    end
  end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

--- Love Image for menu icon, or nil.
function Pokemon.icon(species)
  species = tonumber(species)
  if not species or species < 1 then return nil end
  if Pokemon._icons[species] then return Pokemon._icons[species] end
  local w = (Pokemon._manifest and Pokemon._manifest.iconW) or Versions.MON_ICON_W or 32
  local h = (Pokemon._manifest and Pokemon._manifest.iconH) or Versions.MON_ICON_H or 32
  local rgba = read_rgba(species)
  if not rgba then return nil end
  local actualH = (#rgba >= w * (h * 2) * 4) and (h * 2) or h
  local image = image_from_rgba(rgba, w, actualH)
  if not image then return nil end
  local frames = math.max(1, math.floor(actualH / h))
  local quads = {}
  for f = 0, frames - 1 do
    quads[f] = love.graphics.newQuad(0, f * h, w, h, w, actualH)
  end
  local entry = { image = image, w = w, h = h, sheetH = actualH, frames = frames, quads = quads }
  Pokemon._icons[species] = entry
  return entry
end

local function read_pic(rel)
  local cache = resolve_cache(Pokemon._cache)
  local d = cache and cache.read and cache:read(rel)
  if type(d) == "string" and #d >= 64 * 64 * 4 then return d end
  return nil
end

local SPECIES_CASTFORM = 385

local function form_of(species, form)
  form = tonumber(form) or 0
  if species ~= SPECIES_CASTFORM or form < 1 or form > 3 then return 0 end
  return form
end

local function pic_rel(kind, species, form)
  local root = (CachePaths.CACHE_ROOT or "data/generated/gba") .. "/pokemon/" .. kind .. "/"
  if form > 0 then return root .. species .. "_" .. form .. ".rgba" end
  return root .. species .. ".rgba"
end

local function pic_entry(store, key, rgba)
  local image = image_from_rgba(rgba, 64, 64)
  if not image then return nil end
  local entry = { image = image, w = 64, h = 64 }
  store[key] = entry
  return entry
end

-- pokefirered/src/data/pokemon_graphics/shiny_palette_table.h:415
local function pic(store, kind, species, form, shiny)
  species = tonumber(species)
  if not species or species < 1 then return nil end
  form = form_of(species, form)
  if shiny and species ~= Pokemon.SPECIES_EGG then kind = kind .. "_shiny" end
  local key = form > 0 and (species .. "_" .. form) or species
  if kind:find("_shiny", 1, true) then key = "shiny:" .. key end
  if store[key] then return store[key] end
  return pic_entry(store, key, read_pic(pic_rel(kind, species, form)))
end

local SPECIES_SPINDA = 308
local SPINDA_ROOT = "/pokemon/spinda/"

local function spinda_file(name)
  local cache = resolve_cache(Pokemon._cache)
  return cache and cache.read and cache:read((CachePaths.CACHE_ROOT or "data/generated/gba") .. SPINDA_ROOT .. name)
end

local function spinda_data()
  if Pokemon._spinda then return Pokemon._spinda end
  local tiles, normal, shinyPal, spots = spinda_file("front.4bpp"), spinda_file("normal.gbapal"),
    spinda_file("shiny.gbapal"), spinda_file("spots.bin")
  if not (tiles and #tiles >= 2048 and normal and #normal >= 32 and shinyPal and #shinyPal >= 32
      and spots and #spots >= 144) then
    return nil
  end
  Pokemon._spinda = { tiles = tiles, normal = normal, shiny = shinyPal, spots = spots }
  return Pokemon._spinda
end

-- pokefirered/src/pokemon.c:5276
function Pokemon.drawSpindaSpots(buf, spots, personality)
  local p = (tonumber(personality) or 0) % 4294967296
  for i = 0, 3 do
    local base = i * 36
    local x = (spots:byte(base + 1) + (p % 16) - 8) % 256
    local y = (spots:byte(base + 2) + (math.floor(p / 16) % 16) - 8) % 256
    for row = 0, 15 do
      local bits = spots:byte(base + 3 + row * 2) + spots:byte(base + 4 + row * 2) * 256
      for column = x, x + 15 do
        local off = math.floor(column / 8) * 32 + math.floor((column % 8) / 2)
          + math.floor(y / 8) * 256 + (y % 8) * 4
        if bits % 2 == 1 then
          local b = buf[off] or 0
          if column % 2 == 1 then
            local hi = math.floor(b / 16)
            if hi >= 1 and hi <= 3 then buf[off] = b + 64 end
          else
            local lo = b % 16
            if lo >= 1 and lo <= 3 then buf[off] = b + 4 end
          end
        end
        bits = math.floor(bits / 2)
      end
      y = (y + 1) % 256
    end
    p = math.floor(p / 256)
  end
  return buf
end

local function spinda_rgba(personality, shiny)
  local d = spinda_data()
  if not d then return nil end
  local buf = {}
  for i = 0, 2047 do buf[i] = d.tiles:byte(i + 1) end
  Pokemon.drawSpindaSpots(buf, d.spots, personality)
  local pal = shiny and d.shiny or d.normal
  local rgb = {}
  for c = 0, 15 do
    local v = pal:byte(c * 2 + 1) + pal:byte(c * 2 + 2) * 256
    rgb[c] = string.char(math.floor((v % 32) * 255 / 31 + 0.5),
      math.floor((math.floor(v / 32) % 32) * 255 / 31 + 0.5),
      math.floor((math.floor(v / 1024) % 32) * 255 / 31 + 0.5), 255)
  end
  local out = {}
  local clear = string.char(0, 0, 0, 0)
  for ty = 0, 7 do
    for tx = 0, 7 do
      local tileOff = (ty * 8 + tx) * 32
      for row = 0, 7 do
        for bx = 0, 3 do
          local b = buf[tileOff + row * 4 + bx]
          local x0 = tx * 8 + bx * 2
          local i0 = (ty * 8 + row) * 64 + x0 + 1
          local lo, hi = b % 16, math.floor(b / 16)
          out[i0] = lo == 0 and clear or rgb[lo]
          out[i0 + 1] = hi == 0 and clear or rgb[hi]
        end
      end
    end
  end
  return table.concat(out)
end
Pokemon.spindaRgba = spinda_rgba

-- pokefirered/src/decompress.c:105, src/pokemon.c:5339
local function spinda_pic(personality, shiny)
  local p = (tonumber(personality) or 0) % 4294967296
  local key = (shiny and "spinda_shiny:" or "spinda:") .. p
  Pokemon._spindaPics = Pokemon._spindaPics or {}
  if Pokemon._spindaPics[key] then return Pokemon._spindaPics[key] end
  return pic_entry(Pokemon._spindaPics, key, spinda_rgba(p, shiny))
end

-- pokefirered/src/battle_gfx_sfx_util.c:354
function Pokemon.frontPic(species, form, shiny, personality)
  if tonumber(species) == SPECIES_SPINDA then return spinda_pic(personality, shiny) end
  return pic(Pokemon._front, "front", species, form, shiny)
end

-- pokefirered/src/pokedex_screen.c:2212
function Pokemon.dexFrontPic(species, personality)
  local p = (tonumber(personality) or 0) % 4294967296
  -- include/constants/pokemon.h:185
  local shiny = Pokemon.isShiny({ personality = p, otId = 8, otSecretId = 0 })
  return Pokemon.frontPic(Pokemon.picSpecies(species, p), 0, shiny, p)
end

-- pokefirered/src/pokedex_screen.c:3058
function Pokemon.dexIcon(species, personality)
  return Pokemon.icon(Pokemon.picSpecies(species, personality))
end
Pokemon.frontSprite = Pokemon.frontPic

function Pokemon.backPic(species, form, shiny)
  Pokemon._back = Pokemon._back or {}
  return pic(Pokemon._back, "back", species, form, shiny)
end

-- pokefirered/src/battle_gfx_sfx_util.c:422
function Pokemon.ghostPic()
  if Pokemon._front.ghost then return Pokemon._front.ghost end
  return pic_entry(Pokemon._front, "ghost", read_pic(pic_rel("front", "ghost", 0)))
end

Pokemon.NUMBERING_INTERNAL = "internal"
Pokemon.NUMBERING_NATIONAL = "national"

-- pokefirered/src/data/text/species_names.h:254
function Pokemon.isInternalSpecies(n)
  n = tonumber(n)
  if not n or n < 1 then return false end
  if not Pokemon._names then Pokemon.install(Pokemon._cache) end
  local name = Pokemon._names and Pokemon._names[n]
  if type(name) ~= "string" or name == "" then return false end
  return name:match("^%?+$") == nil
end

function Pokemon.numberingOf(mon)
  if type(mon) ~= "table" then return nil end
  local tag = mon.speciesNumbering
  if tag == Pokemon.NUMBERING_INTERNAL or tag == Pokemon.NUMBERING_NATIONAL then return tag end
  return nil
end

function Pokemon.tagNumbering(mon, kind)
  if type(mon) ~= "table" then return mon end
  if kind ~= Pokemon.NUMBERING_NATIONAL then kind = Pokemon.NUMBERING_INTERNAL end
  mon.speciesNumbering = kind
  return mon
end

--- Resolve display species for a host/opaque mon table.
-- Host mons use string ids ("KYOGRE"); FRLG scripts use internal SPECIES ints.
function Pokemon.speciesOf(mon)
  if not mon then return nil end
  local raw = mon.species or mon.speciesId or mon.id
  if raw == nil then return nil end

  if type(raw) == "string" then
    local byName = Pokemon.speciesFromName(raw)
    if byName then return byName end
    local n = tonumber(raw)
    if n then raw = n else return nil end
  end

  local n = tonumber(raw)
  if not n or n < 1 then return nil end

  local numbering = Pokemon.numberingOf(mon)
  if numbering == Pokemon.NUMBERING_NATIONAL then
    return Pokemon.speciesFromNational(n) or n
  end
  if numbering == Pokemon.NUMBERING_INTERNAL then return n end

  if Pokemon.isInternalSpecies(n) then return n end
  return Pokemon.speciesFromNational(n) or n
end

function Pokemon.displayName(mon)
  if not mon then return "?????" end
  local egg = eggName(mon)
  if egg then return egg end
  if mon.nickname and mon.nickname ~= "" then return tostring(mon.nickname) end
  -- Prefer pack name over host species string when we can resolve.
  local sp = Pokemon.speciesOf(mon)
  if sp then return Pokemon.name(sp) end
  if mon.name and mon.name ~= "" then return tostring(mon.name) end
  if type(mon.species) == "string" then return mon.species end
  return "?????"
end

-- pokefirered/src/trade.c:2391
-- pokefirered/src/pokemon.c:1809
function Pokemon.savedName(mon)
  if type(mon) ~= "table" then return nil end
  local nick = mon.nickname
  if type(nick) == "string" and nick ~= "" then return nick end
  if Pokemon.isEgg(mon) then return nil end
  local name = mon.name
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

return Pokemon
