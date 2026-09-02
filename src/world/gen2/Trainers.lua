-- Gen 2 overworld trainers: the `trainer` struct an object_event points at
-- (macros/scripts/maps.asm), the eyesight test from home/trainers.asm, and the
-- party build that turns trainers.lua's level/species rows into battle mons.
--
-- The extractor already has every class's members; this is the layer between
-- that table and a battle, so nothing here reads the ROM.

local Mon = require("src.battle.gen2.Mon")
local Map = require("src.world.gen2.Map")

local Trainers = {}

-- constants/script_constants.asm
Trainers.TEXT_SEEN, Trainers.TEXT_WIN, Trainers.TEXT_LOSS = 0, 1, 2
-- constants/misc_constants.asm
Trainers.RESET_FLAG, Trainers.SET_FLAG, Trainers.CHECK_FLAG = 0, 1, 2

-- trainers.lua keys classes by name; the `trainer` struct and `loadtrainer`
-- both carry the class's numeric constant, so index once per data table.
local function classIndex(trainerData)
  if not (trainerData and trainerData.classes) then return {} end
  local cache = rawget(trainerData, "_byIndex")
  if cache then return cache end
  cache = {}
  for id, class in pairs(trainerData.classes) do
    if type(class) == "table" and class.index then
      cache[class.index] = class
      class.id = class.id or id
    end
  end
  rawset(trainerData, "_byIndex", cache)
  return cache
end

Trainers.classIndex = classIndex

-- class constant + member number -> a flat record the battle screen can use.
-- `name` is the trainer's own name (JOEY), `className` the class's display
-- name (YOUNGSTER) -- the HUD wants "YOUNGSTER JOEY".
function Trainers.lookup(trainerData, class, member)
  local entry = classIndex(trainerData)[class]
  if not entry then return nil end
  local row = entry.trainers and entry.trainers[member]
  if not row then return nil end
  return {
    class = class,
    classId = entry.id,
    className = entry.name,
    member = member,
    id = row.id,
    name = row.name,
    trainerType = row.trainerType,
    roster = row.party or {},
    attributes = entry.attributes,
    -- TRNATTR_ITEM1/ITEM2: what AI_TryItem may reach for.  A copy, so using
    -- one up in a battle does not empty the class record for the next
    -- trainer of that class.
    items = (function()
      local out = {}
      for _, id in ipairs(entry.items or {}) do out[#out + 1] = id end
      return out
    end)(),
    baseMoney = entry.baseMoney,
  }
end

-- Build the battle party.  TRAINERTYPE_MOVES / _ITEM_MOVES rows carry an
-- explicit move list; the rest take whatever the species knows at that level,
-- which is what MakeTrainerPartyMon does via LearnLevelMoves.
function Trainers.party(data, entry)
  local party = {}
  for _, row in ipairs((entry and entry.roster) or {}) do
    local moves = nil
    if row.moves and #row.moves > 0 then
      moves = {}
      for _, id in ipairs(row.moves) do
        local def = data and data.moves and data.moves[id]
        moves[#moves + 1] = { id = id, pp = def and def.pp or 0,
          maxPp = def and def.pp or 0 }
      end
    end
    -- Trainer mons roll no DVs: the cart gives every one of them 9/8/8/8/8
    -- (wEnemyMonDVs is fixed in MakeTrainerPartyMon), which is why a trainer's
    -- Rattata is always the same Rattata.  A row MAY carry its own dvs block
    -- (mapamap's team editor synthesizes one to pin gender/shininess); it
    -- replaces the fixed byte exactly where the cart would have written it.
    local dvs = row.dvs or { attack = 9, defense = 8, speed = 8, special = 8 }
    local mon = Mon.new(data, row.species, row.level, {
      moves = moves,
      item = row.item,
      dvs = dvs,
    })
    if mon then party[#party + 1] = mon end
  end
  return party
end

-- FacingPlayerDistance (home/trainers.asm): the trainer must share a row or
-- column with the player, be facing along it, and the gap must be at least 1
-- and no more than its sight range.  Returns distance, direction.
function Trainers.sees(npc, player, sight)
  if not (npc and player) or (sight or 0) <= 0 then return nil end
  if npc.cellX == player.cellX then
    local d = player.cellY - npc.cellY
    if d == 0 then return nil end
    local dir = d > 0 and "down" or "up"
    d = math.abs(d)
    if npc.facing ~= dir or d > sight then return nil end
    return d, dir
  elseif npc.cellY == player.cellY then
    local d = player.cellX - npc.cellX
    if d == 0 then return nil end
    local dir = d > 0 and "right" or "left"
    d = math.abs(d)
    if npc.facing ~= dir or d > sight then return nil end
    return d, dir
  end
  return nil
end

-- TrainerWalkToPlayer: the trainer closes to one cell short of the player,
-- so a distance of 1 means it never moves.
function Trainers.approach(distance, dir)
  local steps = {}
  for _ = 1, math.max(0, (distance or 1) - 1) do
    steps[#steps + 1] = dir
  end
  return steps
end

Trainers.DELTA = Map.DELTA

return Trainers
