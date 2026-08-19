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
      if not slot and row.timeGroup and encounters and encounters.timeFishGroups then
        local tg = encounters.timeFishGroups[row.timeGroup]
        slot = tg and tg[todKey]
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

-- A cache built before the extractor carried the two swarm rows has no such
-- group at all, and Fish on a missing group is a bite of nothing; falling back
-- to the map's own group keeps those rods rolling their ordinary list.
function Encounter.fishGroupFor(encounters, group, fishSwarm)
  local swap = FISH_SWARM_GROUPS[fishSwarm or Encounter.FISHSWARM_NONE]
  local swarmed = swap and swap[group]
  if not swarmed then return group end
  local groups = encounters and encounters.fishGroups
  if not (groups and groups[swarmed]) then return group end
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

-- A headbutt on the tree at (cx, cy).  Whether the COMMON or the RARE list is
-- rolled comes from the tree's own coordinates on the cart -- GetTreeMons
-- hashes them so the same tree always behaves the same way -- which is what
-- keeps a player from re-rolling one tree for a rare mon.
function Encounter.treeIsRare(cx, cy)
  return ((cx or 0) * 5 + (cy or 0) * 7) % 10 < 1
end

function Encounter.treeSlot(encounters, mapId, cx, cy, random)
  local setName = Encounter.treeSet(encounters, mapId)
  if not setName then return nil end
  local set = encounters and encounters.treeSets and encounters.treeSets[setName]
  if not set then return nil end
  local list = Encounter.treeIsRare(cx, cy) and set.rare or set.common
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

return Encounter
