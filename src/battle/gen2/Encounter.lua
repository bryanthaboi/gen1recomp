-- Gen 2 wild encounters (engine/overworld/wildmons.asm).
--
-- The Gen 2 mechanic Gen 1 does not have: a grass table holds three separate
-- seven-slot lists, one per time of day, plus a per-time encounter *rate*.  So
-- the same patch of grass on Route 29 gives Pidgey in the morning and Hoothoot
-- at night, and the clock that decides which is the same one that decides the
-- palette -- see src/world/gen2/Palettes.lua.
--
-- Slot probabilities are Gen 2's ProbabilityTable (data/wild/probabilities.asm):
-- 30, 30, 20, 10, 5, 4, 1 percent across the seven slots, cumulative.

local Encounter = {}

-- data/wild/probabilities.asm, cumulative out of 100.
Encounter.GRASS_SLOT_CHANCES = { 30, 60, 80, 90, 95, 99, 100 }
-- Water has three slots: 60, 30, 10.
Encounter.WATER_SLOT_CHANCES = { 60, 90, 100 }

local function roll(random, n)
  if random then return random(n) end
  if love and love.math and love.math.random then
    return love.math.random(n) - 1
  end
  return math.random(n) - 1
end

-- Which slot a 0..99 roll lands in.
local function slotFor(chances, value)
  for index, cumulative in ipairs(chances) do
    if value < cumulative then return index end
  end
  return #chances
end

-- Does a step in grass start a battle?  The map's rate is out of 256
-- (`db 2 percent`), and the cart compares one random byte against it.
function Encounter.triggers(rate, random)
  if not rate or rate <= 0 then return false end
  return roll(random, 256) < rate
end

-- The grass encounter for a map at a time of day, or nil when that map has
-- none.  `daytime` is "MORN"/"DAY"/"NITE"/"DARK"; DARK reuses the night list,
-- since the cart only stores three (wildmons.asm masks the palette daytime down
-- to three when indexing).
function Encounter.grassSlot(encounters, mapId, daytime, random)
  local entry = encounters and encounters.grass and encounters.grass[mapId]
  if not entry then return nil end
  local key = (daytime == "DARK") and "NITE" or (daytime or "DAY")
  local slots = entry.slots and (entry.slots[key] or entry.slots.DAY)
  if not slots then return nil end
  local index = slotFor(Encounter.GRASS_SLOT_CHANCES, roll(random, 100))
  local slot = slots[index]
  if not slot or not slot.species then return nil end
  return { species = slot.species, level = slot.level, slot = index }
end

function Encounter.grassRate(encounters, mapId, daytime)
  local entry = encounters and encounters.grass and encounters.grass[mapId]
  if not entry then return 0 end
  local key = (daytime == "DARK") and "NITE" or (daytime or "DAY")
  return (entry.rates and (entry.rates[key] or entry.rates.DAY)) or 0
end

function Encounter.waterSlot(encounters, mapId, random)
  local entry = encounters and encounters.water and encounters.water[mapId]
  if not entry or not entry.slots then return nil end
  local index = slotFor(Encounter.WATER_SLOT_CHANCES, roll(random, 100))
  local slot = entry.slots[index]
  if not slot or not slot.species then return nil end
  return { species = slot.species, level = slot.level, slot = index }
end

function Encounter.waterRate(encounters, mapId)
  local entry = encounters and encounters.water and encounters.water[mapId]
  return (entry and entry.rate) or 0
end

-- Fishing: a rod's list is (cumulative chance, species, level) rows out of 256,
-- ending at 100%.  A roll past the group's own `chance` is a bite of nothing.
-- Rows with `day` and `nite` sub-slots (from TimeFishGroups) resolve based on
-- `daytime` ("MORN"/"DAY" vs "NITE"/"DARK").
function Encounter.fish(encounters, fishGroup, rod, daytime, random)
  if type(daytime) == "function" and random == nil then
    random = daytime
    daytime = nil
  end
  local group = encounters and encounters.fishGroups
    and encounters.fishGroups[fishGroup]
  if not group then return nil end
  local list = group[rod or "old"]
  if not list or #list == 0 then return nil end
  local value = roll(random, 256)
  local isNight = (daytime == "DARK" or daytime == "NITE")
  local todKey = isNight and "nite" or "day"
  for _, row in ipairs(list) do
    if value < (row.chance or 0) then
      local slot = row[todKey]
      if not slot and row.timeGroup then
        local groups = encounters.timeFishGroups
        if type(groups) ~= "table" then
          error("encounters.lua has no timeFishGroups")
        end
        local tg = groups[row.timeGroup]
        slot = tg and tg[todKey]
        if not slot then
          error("encounters.lua has no time fish group " .. tostring(row.timeGroup))
        end
      end
      slot = slot or row
      if not slot.species or slot.species == 0 or slot.species == "NO_ITEM" then return nil end
      return { species = slot.species, level = slot.level }
    end
  end
  return nil
end

-- GetFishGroupIndex (engine/events/fish.asm), the fishing half of a swarm:
-- Fish calls it before it indexes FishGroups, and it swaps FISHGROUP_QWILFISH
-- for FISHGROUP_QWILFISH_SWARM (and FISHGROUP_REMORAID for
-- FISHGROUP_REMORAID_SWARM) while wFishingSwarmFlag names that swarm.  Nothing
-- else is substituted: FISHGROUP_QWILFISH_NO_SWARM is a map header value of its
-- own and never becomes a swarm group.  `fishSwarm` is the FISHSWARM_* byte
-- (constants/script_constants.asm), which the port keeps in
-- save.dailyFlags.fishingSwarm and reads back through Roamers.Swarm.fishing.
Encounter.FISHSWARM_NONE = 0
Encounter.FISHSWARM_QWILFISH = 1
Encounter.FISHSWARM_REMORAID = 2

local FISH_SWARM_GROUPS = {
  [Encounter.FISHSWARM_QWILFISH] = {
    FISHGROUP_QWILFISH = "FISHGROUP_QWILFISH_SWARM",
  },
  [Encounter.FISHSWARM_REMORAID] = {
    FISHGROUP_REMORAID = "FISHGROUP_REMORAID_SWARM",
  },
}

-- engine/events/fish.asm:92 GetFishGroupIndex
function Encounter.fishGroupFor(encounters, group, fishSwarm)
  local swap = FISH_SWARM_GROUPS[fishSwarm or Encounter.FISHSWARM_NONE]
  local swarmed = swap and swap[group]
  if not swarmed then return group end
  local groups = encounters and encounters.fishGroups
  if not (groups and groups[swarmed]) then
    error("encounters.lua has no fish group " .. swarmed)
  end
  return swarmed
end

-- Which fish group a MAP belongs to lives on the map record, so a caller with
-- a map id and a rod does not have to know about groups at all.
function Encounter.fishSlot(encounters, mapId, rod, random, maps, fishSwarm, daytime)
  local map = maps and maps[mapId]
  local group = map and map.fishGroup
  if not group then
    -- Callers that already hold the map (the World does) pass it in; without
    -- it, fall back to the pond, which is what an unlisted map fishes.
    group = "FISHGROUP_POND"
  end
  group = Encounter.fishGroupFor(encounters, group, fishSwarm)
  local key = rod
  if rod == "OLD_ROD" then key = "old"
  elseif rod == "GOOD_ROD" then key = "good"
  elseif rod == "SUPER_ROD" then key = "super" end
  return Encounter.fish(encounters, group, key or "old", daytime, random)
end

-- Headbutt trees: TreeMonMaps says which set a map uses and TreeMons holds
-- that set's two lists.  The rows are cumulative percentages ending at -1, the
-- same shape as the fishing lists.
function Encounter.treeSet(encounters, mapId)
  return encounters and encounters.trees and encounters.trees[mapId] or nil
end

-- ../pokecrystal/engine/events/treemons.asm:199 GetTreeScore
Encounter.TREEMON_SCORE_BAD = 0
Encounter.TREEMON_SCORE_GOOD = 1
Encounter.TREEMON_SCORE_RARE = 2

-- ../pokecrystal/engine/overworld/player_object.asm:102 RefreshPlayerCoords
function Encounter.treeScore(cx, cy, otId)
  local d = ((cx or 0) + 4) % 256
  local e = ((cy or 0) + 4) % 256
  local coord = math.floor(((e * (d + 1) + d) % 65536) / 5) % 10
  local ot = math.floor(otId or 0) % 10
  local diff = (coord - ot) % 10
  if diff == 0 then return Encounter.TREEMON_SCORE_RARE end
  if diff < 5 then return Encounter.TREEMON_SCORE_GOOD end
  return Encounter.TREEMON_SCORE_BAD
end

-- ../pokegold/engine/events/treemons.asm:94 GetTreeMons
local GS_DEAD_SETS = {
  TREEMON_SET_NONE = true,
  TREEMON_SET_UNUSED = true,
  TREEMON_SET_CITY = true,
}

-- ../pokecrystal/engine/events/treemons.asm:96 GetTreeMons
function Encounter.treeSetUsable(setName, engine)
  if not setName or setName == "TREEMON_SET_NONE" then return false end
  if engine == "gs" and GS_DEAD_SETS[setName] then return false end
  return true
end

-- ../pokecrystal/engine/events/treemons.asm:126 GetTreeMon
function Encounter.treeSlot(encounters, mapId, cx, cy, random, opts)
  opts = opts or {}
  local setName = Encounter.treeSet(encounters, mapId)
  if not Encounter.treeSetUsable(setName, opts.engine) then return nil end
  local sets = encounters and encounters.treeSets
  if type(sets) ~= "table" then error("encounters.lua has no treeSets") end
  local set = sets[setName]
  if type(set) ~= "table" then
    error("encounters.lua has no tree set " .. tostring(setName))
  end
  local score = Encounter.treeScore(cx, cy, opts.otId)
  local list, gate = set.common, 1
  if score == Encounter.TREEMON_SCORE_GOOD then
    gate = 5
  elseif score == Encounter.TREEMON_SCORE_RARE then
    list, gate = set.rare, 8
  end
  if roll(random, 10) >= gate then return nil end
  if not list or #list == 0 then return nil end
  local value = roll(random, 100)
  local total = 0
  for _, row in ipairs(list) do
    total = total + (row.chance or 0)
    if value < total then
      if not row.species then return nil end
      return { species = row.species, level = row.level }
    end
  end
  return nil
end

-- ../pokecrystal/constants/battle_constants.asm:15 TREEMON_SLEEP_TURNS
Encounter.TREEMON_SLEEP_TURNS = 7

-- ../pokecrystal/engine/battle/core.asm:6422 CheckSleepingTreeMon
function Encounter.treeMonAsleep(species, daytime, engine, encounters)
  if engine ~= "crystal" then return false end
  daytime = daytime or "DAY"
  local extracted = encounters and encounters.treeMonsAsleep
  if type(extracted) ~= "table" then
    error("encounters.lua has no treeMonsAsleep")
  end
  local key = (daytime == "MORN" and "MORN") or (daytime == "DAY" and "DAY")
    or "NITE"
  local list = extracted[key]
  if type(list) ~= "table" then
    error("encounters.lua has no treeMonsAsleep." .. key)
  end
  for _, name in ipairs(list) do
    if name == species then return true end
  end
  return false
end

return Encounter
