-- Gen 3 (FireRed) event, flag, and variable categorization for the save editor.
-- Slices the raw save.flags bitfield and save.vars space into clean categories:
-- Story flags, Trainers (0x500 + trainerId), Items taken, Object toggles,
-- System flags, and Script variables.

local FlagsTable = require("src.core.game3.scripting.flags_table")

local Gen3Flags = {}

local TRAINERS_CACHE = nil

local function readText(path)
  local fs = love and love.filesystem
  if fs and fs.read and fs.getInfo and fs.getInfo(path) then
    local ok, body = pcall(fs.read, path)
    if ok and body then return body end
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

-- Parse pokefirered/include/constants/opponents.h for all 742 TRAINER_ constants
local function loadTrainers()
  if TRAINERS_CACHE then return TRAINERS_CACHE end
  local trainers = {}
  local seen = {}
  local header = readText("pokefirered/include/constants/opponents.h")
  if header then
    for line in header:gmatch("[^\r\n]+") do
      local name, idStr = line:match("^%s*#define%s+(TRAINER_[%w_]+)%s+(%d+)")
      if name and idStr then
        local id = tonumber(idStr)
        if id and id > 0 and not seen[id] then
          seen[id] = true
          trainers[#trainers + 1] = {
            id = id,
            name = name,
            flagId = 0x500 + id,
            label = string.format("%s (0x%03X)", name, 0x500 + id),
          }
        end
      end
    end
  end

  -- Fallback if opponents.h wasn't reachable
  if #trainers == 0 then
    for id = 1, 742 do
      trainers[#trainers + 1] = {
        id = id,
        name = string.format("TRAINER_0x%03X", id),
        flagId = 0x500 + id,
        label = string.format("TRAINER_0x%03X (0x%03X)", id, 0x500 + id),
      }
    end
  end

  table.sort(trainers, function(a, b) return a.id < b.id end)
  TRAINERS_CACHE = trainers
  return trainers
end

Gen3Flags.loadTrainers = loadTrainers

-- Item Ball check (strict range 0x154..0x1FE, 0x1A6, 0x1BC..0x1FD)
local function isItemBallFlag(name, id)
  if id >= 0x154 and id <= 0x1FE then return true end
  if id == 0x1A6 or id == 0x1BC or id == 0x1BD or (id >= 0x1BE and id <= 0x1FD) then return true end
  return false
end

-- Hidden item check (strict range 0x3E8..0x4A6)
local function isHiddenItemFlag(name, id)
  if id >= 0x3E8 and id <= 0x4A6 then return true end
  if type(name) == "string" and name:find("^FLAG_HIDDEN_ITEM_") then return true end
  return false
end

-- System flags (0x800..0x8FF)
local function isSystemFlag(name, id)
  if id >= 0x800 and id <= 0x8FF then return true end
  if type(name) == "string" then
    if name:find("^FLAG_SYS_") or name:find("^FLAG_BADGE") or name:find("^FLAG_WORLD_MAP_") or name:find("^FLAG_ENABLE_SHIP_") then
      return true
    end
  end
  return false
end

-- Object hide/show toggles (0x028..0x0AE, plus non-item FLAG_HIDE_ flags)
local function isObjectToggleFlag(name, id)
  if isItemBallFlag(name, id) or isHiddenItemFlag(name, id) then return false end
  if id >= 0x028 and id <= 0x0AE then return true end
  if type(name) == "string" and name:find("^FLAG_HIDE_") then return true end
  return false
end

-- Boss clear flags (0x4B0..0x4BC)
local function isBossClearFlag(name, id)
  if id >= 0x4B0 and id <= 0x4BC then return true end
  if type(name) == "string" and name:find("^FLAG_DEFEATED_") then return true end
  return false
end

-- Story flags (0x230..0x3E7, boss clears, and story prefixes)
local function isStoryFlag(name, id)
  if isItemBallFlag(name, id) or isHiddenItemFlag(name, id) or isSystemFlag(name, id) or isObjectToggleFlag(name, id) then
    return false
  end
  if id >= 0x500 and id <= 0x7FF then return false end -- trainer flag
  if (id >= 0x230 and id <= 0x3E7) or isBossClearFlag(name, id) then return true end
  if type(name) == "string" then
    if name:find("^FLAG_GOT_") or name:find("^FLAG_RESCUED_") or name:find("^FLAG_HELPED_")
        or name:find("^FLAG_BEAT_") or name:find("^FLAG_CAN_") or name:find("^FLAG_CINNABAR_GYM_")
        or name:find("^FLAG_DID_") or name:find("^FLAG_FOUGHT_") or name:find("^FLAG_FOUND_")
        or name:find("^FLAG_LEARNED_") or name:find("^FLAG_MET_") or name:find("^FLAG_OPENED_")
        or name:find("^FLAG_REVIVED_") or name:find("^FLAG_RETURNED_") or name:find("^FLAG_TALKED_TO_")
        or name:find("^FLAG_USED_") or name:find("^FLAG_WOKE_UP_") or name:find("^FLAG_SHOWN_")
        or name:find("^MOD_") then
      return true
    end
  end
  return false
end

function Gen3Flags.categories(extraDirs)
  local trainers = loadTrainers()

  local story = {}
  local items = {}
  local toggles = {}
  local system = {}
  local vars = {}

  local seenStory = {}
  local seenItems = {}
  local seenToggles = {}
  local seenSystem = {}

  local flagsTable = FlagsTable.FLAGS or {}

  -- 1. Classify all known flags in FlagsTable
  for name, id in pairs(flagsTable) do
    if type(name) == "string" and type(id) == "number" then
      if isHiddenItemFlag(name, id) or isItemBallFlag(name, id) then
        if not seenItems[name] then
          seenItems[name] = true
          items[#items + 1] = { name = name, id = id, label = string.format("%s (0x%03X)", name, id) }
        end
      elseif isSystemFlag(name, id) then
        if not seenSystem[name] then
          seenSystem[name] = true
          system[#system + 1] = { name = name, id = id, label = string.format("%s (0x%03X)", name, id) }
        end
      elseif isObjectToggleFlag(name, id) then
        if not seenToggles[name] then
          seenToggles[name] = true
          toggles[#toggles + 1] = { name = name, id = id, label = string.format("%s (0x%03X)", name, id) }
        end
      elseif isStoryFlag(name, id) then
        if not seenStory[name] then
          seenStory[name] = true
          story[#story + 1] = { name = name, id = id, label = string.format("%s (0x%03X)", name, id) }
        end
      end
    end
  end

  -- Scrape mod flags into story
  local Catalog = require("Catalog")
  local modFlags = Catalog.scrapeEvents(nil, nil, nil, extraDirs)
  for _, name in ipairs(modFlags) do
    if not seenStory[name] then
      seenStory[name] = true
      story[#story + 1] = { name = name, id = name, label = name }
    end
  end

  -- 2. Variables (0x4000..0x40FF)
  local seenVars = {}
  for name, id in pairs(FlagsTable.VARS or {}) do
    if type(name) == "string" and type(id) == "number" and id >= 0x4000 and id <= 0x41FF then
      if not seenVars[id] then
        seenVars[id] = true
        vars[#vars + 1] = {
          name = name,
          id = id,
          label = string.format("%s (0x%04X)", name, id),
        }
      end
    end
  end
  for id, name in pairs(FlagsTable.VARS_BY_ID or {}) do
    if type(id) == "number" and id >= 0x4000 and id <= 0x41FF then
      if not seenVars[id] then
        seenVars[id] = true
        vars[#vars + 1] = {
          name = name,
          id = id,
          label = string.format("%s (0x%04X)", name, id),
        }
      end
    end
  end

  -- Sort lists by ID / label
  local function sortById(a, b)
    local aid = type(a.id) == "number" and a.id or 999999
    local bid = type(b.id) == "number" and b.id or 999999
    if aid ~= bid then return aid < bid end
    return tostring(a.name) < tostring(b.name)
  end

  table.sort(story, sortById)
  table.sort(items, sortById)
  table.sort(toggles, sortById)
  table.sort(system, sortById)
  table.sort(vars, sortById)

  return {
    story = story,
    trainers = trainers,
    items = items,
    toggles = toggles,
    system = system,
    vars = vars,
  }
end

-- Sets / lists of all flag IDs for bulk operations
function Gen3Flags.allTrainerFlagIds()
  local trainers = loadTrainers()
  local ids = {}
  for _, t in ipairs(trainers) do
    ids[#ids + 1] = t.flagId
  end
  return ids
end

function Gen3Flags.allItemFlagIds()
  local cats = Gen3Flags.categories()
  local ids = {}
  for _, it in ipairs(cats.items) do
    ids[#ids + 1] = it.id
  end
  return ids
end

function Gen3Flags.allToggleFlagIds()
  local cats = Gen3Flags.categories()
  local ids = {}
  for _, tg in ipairs(cats.toggles) do
    ids[#ids + 1] = tg.id
  end
  return ids
end

return Gen3Flags
