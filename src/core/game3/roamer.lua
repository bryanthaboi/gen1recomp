-- Roaming Legendary Beast system matching pokefirered (src/roamer.c)
-- Raikou, Entei, and Suicune in Kanto.

local Rng = require("src.core.game3.rng")
local Pokemon = require("src.core.game3.pokemon")

local Roamer = {}

Roamer.SPECIES_RAIKOU = 243
Roamer.SPECIES_ENTEI = 244
Roamer.SPECIES_SUICUNE = 245
Roamer.ROAMER_LEVEL = 50

-- include/constants/vars.h:47
local VAR_REPEL_STEP_COUNT = 0x4020
local VAR_STARTER_MON = 0x4031

-- pokefirered/src/roamer.c:19 sRoamerLocations (Kanto routes)
Roamer.LOCATIONS = {
  "FR_ROUTE_1",
  "FR_ROUTE_2",
  "FR_ROUTE_3",
  "FR_ROUTE_4",
  "FR_ROUTE_5",
  "FR_ROUTE_6",
  "FR_ROUTE_7",
  "FR_ROUTE_8",
  "FR_ROUTE_9",
  "FR_ROUTE_10",
  "FR_ROUTE_11",
  "FR_ROUTE_12",
  "FR_ROUTE_13",
  "FR_ROUTE_14",
  "FR_ROUTE_15",
  "FR_ROUTE_16",
  "FR_ROUTE_17",
  "FR_ROUTE_18",
  "FR_ROUTE_19",
  "FR_ROUTE_20",
  "FR_ROUTE_21_NORTH",
  "FR_ROUTE_21_SOUTH",
  "FR_ROUTE_24",
  "FR_ROUTE_25",
}

-- Adjacency table matching pokefirered/src/roamer.c:30 sRoamerLocationHistory
Roamer.ADJACENCY = {
  ["FR_ROUTE_1"] = { "FR_ROUTE_2", "FR_ROUTE_21_NORTH", "FR_ROUTE_21_SOUTH" },
  ["FR_ROUTE_2"] = { "FR_ROUTE_1", "FR_ROUTE_3", "FR_ROUTE_22" },
  ["FR_ROUTE_3"] = { "FR_ROUTE_2", "FR_ROUTE_4" },
  ["FR_ROUTE_4"] = { "FR_ROUTE_3", "FR_ROUTE_9", "FR_ROUTE_24" },
  ["FR_ROUTE_5"] = { "FR_ROUTE_6", "FR_ROUTE_7", "FR_ROUTE_8", "FR_ROUTE_24" },
  ["FR_ROUTE_6"] = { "FR_ROUTE_5", "FR_ROUTE_7", "FR_ROUTE_8", "FR_ROUTE_11" },
  ["FR_ROUTE_7"] = { "FR_ROUTE_5", "FR_ROUTE_6", "FR_ROUTE_8", "FR_ROUTE_16" },
  ["FR_ROUTE_8"] = { "FR_ROUTE_5", "FR_ROUTE_6", "FR_ROUTE_7", "FR_ROUTE_10", "FR_ROUTE_12" },
  ["FR_ROUTE_9"] = { "FR_ROUTE_4", "FR_ROUTE_10", "FR_ROUTE_24" },
  ["FR_ROUTE_10"] = { "FR_ROUTE_8", "FR_ROUTE_9", "FR_ROUTE_12" },
  ["FR_ROUTE_11"] = { "FR_ROUTE_6", "FR_ROUTE_12" },
  ["FR_ROUTE_12"] = { "FR_ROUTE_8", "FR_ROUTE_10", "FR_ROUTE_11", "FR_ROUTE_13" },
  ["FR_ROUTE_13"] = { "FR_ROUTE_12", "FR_ROUTE_14" },
  ["FR_ROUTE_14"] = { "FR_ROUTE_13", "FR_ROUTE_15" },
  ["FR_ROUTE_15"] = { "FR_ROUTE_14", "FR_ROUTE_18" },
  ["FR_ROUTE_16"] = { "FR_ROUTE_7", "FR_ROUTE_17" },
  ["FR_ROUTE_17"] = { "FR_ROUTE_16", "FR_ROUTE_18" },
  ["FR_ROUTE_18"] = { "FR_ROUTE_15", "FR_ROUTE_17", "FR_ROUTE_19" },
  ["FR_ROUTE_19"] = { "FR_ROUTE_18", "FR_ROUTE_20" },
  ["FR_ROUTE_20"] = { "FR_ROUTE_19", "FR_ROUTE_21_SOUTH" },
  ["FR_ROUTE_21_NORTH"] = { "FR_ROUTE_1", "FR_ROUTE_21_SOUTH" },
  ["FR_ROUTE_21_SOUTH"] = { "FR_ROUTE_20", "FR_ROUTE_21_NORTH" },
  ["FR_ROUTE_24"] = { "FR_ROUTE_4", "FR_ROUTE_5", "FR_ROUTE_9", "FR_ROUTE_25" },
  ["FR_ROUTE_25"] = { "FR_ROUTE_24" },
}

local function normalize_map_id(mapId)
  if type(mapId) ~= "string" then return nil end
  local s = tostring(mapId):upper()

  -- Check MapCatalog if available
  local ok, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if ok and MapCatalog and MapCatalog.resolve then
    local res = MapCatalog.resolve(s)
    if res then s = tostring(res):upper() end
  end

  if s:find("ROUTE_?21_?NORTH") or s:find("ROUTE_?21_?SOUTH") then
    if s:find("SOUTH") then return "FR_ROUTE_21_SOUTH" end
    return "FR_ROUTE_21_NORTH"
  end
  if s == "FR_ROUTE21" or s == "ROUTE_21" or s == "FR_ROUTE_21" or s == "ROUTE21" then
    return "FR_ROUTE_21_NORTH"
  end

  local num = s:match("ROUTE_?(%d+)")
  if num then
    local target = "FR_ROUTE_" .. num
    for _, loc in ipairs(Roamer.LOCATIONS) do
      if loc == target then return target end
    end
  end

  for _, loc in ipairs(Roamer.LOCATIONS) do
    if s == loc or s == loc:gsub("^FR_", "") or s == loc:gsub("_", "") or s == ("FR_" .. s:gsub("_", "")) then
      return loc
    end
  end
  return s
end
Roamer.normalizeMapId = normalize_map_id

--- Determine species based on starter:
--- Bulbasaur (0) -> Entei (244)
--- Squirtle (1) -> Raikou (243)
--- Charmander (2) -> Suicune (245)
function Roamer.speciesForStarter(starter)
  starter = tonumber(starter) or 0
  if starter == 1 then
    return Roamer.SPECIES_RAIKOU
  elseif starter == 2 then
    return Roamer.SPECIES_SUICUNE
  else
    return Roamer.SPECIES_ENTEI
  end
end

local function random_32bit()
  local hi = Rng.Random() % 65536
  local lo = Rng.Random() % 65536
  return hi * 65536 + lo
end

--- Generates standard 0-31 IV block (fixing the vanilla Gen 3 hardware truncation bug)
function Roamer.generateMon(species, level)
  level = level or Roamer.ROAMER_LEVEL
  local pid = random_32bit()
  local ivs = {
    hp = Rng.Random() % 32,
    attack = Rng.Random() % 32,
    defense = Rng.Random() % 32,
    speed = Rng.Random() % 32,
    spAtk = Rng.Random() % 32,
    spDef = Rng.Random() % 32,
  }

  local moves, pp = nil, nil
  if Pokemon and Pokemon.movesAtLevel then
    moves, pp = Pokemon.movesAtLevel(species, level)
  end

  local hpBase = (species == Roamer.SPECIES_RAIKOU and 90)
    or (species == Roamer.SPECIES_ENTEI and 115)
    or (species == Roamer.SPECIES_SUICUNE and 100) or 100
  local maxHp = math.floor(((2 * hpBase + ivs.hp) * level) / 100) + level + 10

  return {
    species = species,
    speciesId = species,
    level = level,
    hp = maxHp,
    maxHp = maxHp,
    status = 0,
    statusNum = 0,
    pid = pid,
    ivs = ivs,
    moves = moves or {},
    pp = pp or {},
  }
end

--- Initialize roamer on Celio Ruby/Sapphire completion (special InitRoamer)
function Roamer.init(session, starterChoice)
  if not session then return false end
  local species = Roamer.speciesForStarter(starterChoice)
  local mon = Roamer.generateMon(species, Roamer.ROAMER_LEVEL)

  -- Initial location: pick random Kanto route
  local locIndex = (Rng.Random() % #Roamer.LOCATIONS) + 1
  local initialMap = Roamer.LOCATIONS[locIndex]

  session.roamer = {
    active = true,
    species = species,
    level = Roamer.ROAMER_LEVEL,
    hp = mon.hp or mon.maxHp,
    maxHp = mon.maxHp or mon.hp,
    status = mon.status or 0,
    statusNum = mon.statusNum or 0,
    pid = mon.pid,
    ivs = mon.ivs,
    moves = mon.moves,
    pp = mon.pp,
    map = initialMap,
  }

  return true
end

--- Jump roamer to a completely random Kanto route (Fly, Teleport, Escape Rope, Whiteout)
function Roamer.jump(session)
  if not (session and session.roamer and session.roamer.active) then return end
  local cur = session.roamer.map
  local locs = Roamer.LOCATIONS
  local pick
  for _ = 1, 10 do
    pick = locs[(Rng.Random() % #locs) + 1]
    if pick ~= cur then break end
  end
  session.roamer.map = pick or locs[1]
end

--- Step roamer across connected routes (on map transition)
function Roamer.move(session, reason)
  if not (session and session.roamer and session.roamer.active) then return end
  if reason == "warp_random" then
    Roamer.jump(session)
    return
  end

  local cur = session.roamer.map
  local adj = Roamer.ADJACENCY[cur]
  if not adj or #adj == 0 then
    Roamer.jump(session)
    return
  end

  -- ~16/256 chance to stay on same route, otherwise pick adjacent route
  if (Rng.Random() % 16) == 0 then
    return
  end

  local pick = adj[(Rng.Random() % #adj) + 1]
  session.roamer.map = pick or cur
end

--- Check party slot 1 level for Repel check (even if fainted!)
local function getLeadMonLevel(session)
  local party = session and session.party
  if type(party) ~= "table" then return 0 end
  for i = 1, #party do
    local mon = party[i]
    -- Eggs are ignored; fainted lead Pokémon in slot 1 IS evaluated by Repel!
    if type(mon) == "table" and not mon.isEgg and not mon.egg then
      return tonumber(mon.level) or tonumber(mon.lvl) or 1
    end
  end
  return 0
end

--- Intercept wild encounter if roamer is active on current map
function Roamer.tryEncounter(session, mapId, terrain)
  if not (session and session.roamer and session.roamer.active) then return nil end
  local roamer = session.roamer
  if roamer.hp <= 0 then return nil end

  local normMap = normalize_map_id(mapId)
  local roamerMap = normalize_map_id(roamer.map)
  if normMap ~= roamerMap then return nil end

  -- Only wild land/grass or surf water triggers
  if terrain ~= "land" and terrain ~= "grass" and terrain ~= "water" then
    return nil
  end

  -- Repel check (respects fainted slot-1 Pokémon level)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = (Space and Space.store) or session.store or session
  local Flags = require("src.core.game3.scripting.flags")
  local repelSteps = tonumber(Flags.getVar(store, nil, VAR_REPEL_STEP_COUNT)) or 0
  if repelSteps > 0 then
    local leadLv = getLeadMonLevel(session)
    if leadLv > roamer.level then
      return nil
    end
  end

  -- Construct wild foe encounter descriptor
  local foe = {
    species = roamer.species,
    speciesId = roamer.species,
    level = roamer.level,
    hp = roamer.hp,
    maxHp = roamer.maxHp,
    status = roamer.status,
    statusNum = roamer.statusNum,
    pid = roamer.pid,
    ivs = roamer.ivs,
    moves = roamer.moves,
    pp = roamer.pp,
    roamer = true,
  }

  return {
    species = roamer.species,
    level = roamer.level,
    roamer = true,
    foe = foe,
  }
end

--- Update roamer status and HP on battle completion
function Roamer.onBattleEnd(session, foeState, battleResult, endReason)
  if not (session and session.roamer and session.roamer.active) then return end
  local roamer = session.roamer

  if foeState then
    roamer.hp = math.max(0, tonumber(foeState.hp) or roamer.hp)
    roamer.status = foeState.status or roamer.status
    roamer.statusNum = foeState.statusNum or roamer.statusNum
  end

  -- Caught or defeated -> permanently deactivate
  if battleResult == "caught" or (foeState and foeState.hp and foeState.hp <= 0) then
    roamer.active = false
    return
  end

  -- If battle ended by fleeing, player running, or Roar/Whirlwind:
  -- Prevent Gen 3 Roar despawn bug: keep roamer alive and migrate to new location
  Roamer.jump(session)
end

return Roamer
