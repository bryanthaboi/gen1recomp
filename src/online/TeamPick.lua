local GameVersion = require("src.core.GameVersion")
local Protocol = require("src.link.Protocol")
local SaveData = require("src.core.SaveData")

local TeamPick = {}

local function generationOf(version, save)
  if type(save) == "table" and tonumber(save.generation) then
    return tonumber(save.generation)
  end
  return GameVersion.generation(version)
end

local function readCartSource(cartId, slotId)
  local registered = false
  for _, row in ipairs(SaveData.listCartSlots(cartId)) do
    if row.id == slotId then registered = row.exists end
  end
  if not registered then return nil, "no save in that slot" end
  local body = SaveData.readCartSlotSource(cartId, slotId)
  if type(body) == "string" and body ~= "" then return body end
  return nil, "no save in that slot"
end

local function readSource(version, slotId, cartId)
  if cartId then return readCartSource(cartId, slotId) end
  return SaveData.readSlotSource(version, slotId)
end

function TeamPick.readSlot(version, slotId, cartId)
  if not GameVersion.VERSIONS[version] then return nil, "unknown game" end
  if type(slotId) ~= "string" or slotId == "" then return nil, "no slot chosen" end
  if cartId and SaveData.slotSealBroken(cartId, slotId) then
    return nil, "this save's seal is broken"
  end
  local ok, source, err = pcall(readSource, version, slotId, cartId)
  if not ok then return nil, tostring(source) end
  if type(source) ~= "string" then
    return nil, tostring(err or "no save in that slot")
  end
  local decoded, save = pcall(SaveData.decode, source)
  if not decoded or type(save) ~= "table" then
    return nil, "that save can't be read"
  end
  local name, meta = SaveData.slotSummary(save)
  return {
    save = save,
    party = type(save.party) == "table" and save.party or {},
    trainerName = name,
    badges = (meta and meta.badges) or 0,
    generation = generationOf(version, save),
  }
end

-- engine/pokemon/bills_pc.asm
local GEN1_BOXES, GEN2_BOXES = 12, 14

local function boxName(save, generation, index)
  if generation == 2 then
    local names = type(save) == "table" and save.boxNames or nil
    local given = type(names) == "table" and names[index] or nil
    if type(given) == "string" and given ~= "" then return given end
    return "BOX" .. tostring(index)
  end
  return "BOX " .. tostring(index)
end

TeamPick.boxName = boxName

function TeamPick.refKey(ref)
  if type(ref) == "number" then return "party|" .. tostring(ref) end
  if type(ref) ~= "table" then return "?" end
  if ref.where == "box" then
    return ("box|%s|%s"):format(tostring(ref.box), tostring(ref.index))
  end
  return "party|" .. tostring(ref.index)
end

function TeamPick.sameRef(a, b)
  return TeamPick.refKey(a) == TeamPick.refKey(b)
end

local function slotOf(source)
  if type(source) ~= "table" then return { party = {} } end
  if type(source.party) == "table" then return source end
  return { party = source }
end

TeamPick.slotOf = slotOf

local function boxesOf(slot)
  local save = type(slot.save) == "table" and slot.save or nil
  if save and type(save.boxes) == "table" then return save.boxes end
  if type(slot.boxes) == "table" then return slot.boxes end
  return nil
end

function TeamPick.monAt(source, ref)
  local slot = slotOf(source)
  if type(ref) == "number" then ref = { where = "party", index = ref } end
  if type(ref) ~= "table" then return nil end
  local index = tonumber(ref.index)
  if not index or index < 1 or index ~= math.floor(index) then return nil end
  if ref.where == "box" then
    local boxes = boxesOf(slot)
    if type(boxes) ~= "table" then return nil end
    local list = boxes[tonumber(ref.box) or 0]
    if type(list) ~= "table" then return nil end
    local mon = list[index]
    return type(mon) == "table" and mon or nil
  end
  local mon = (slot.party or {})[index]
  return type(mon) == "table" and mon or nil
end

function TeamPick.candidates(source)
  local slot = slotOf(source)
  local out = {}
  for index, mon in ipairs(slot.party or {}) do
    out[#out + 1] = { where = "party", index = index, mon = mon,
                      source = "Party" }
  end
  local boxes = boxesOf(slot)
  if type(boxes) ~= "table" then return out end
  local generation = tonumber(slot.generation) or 1
  local last = (generation == 2) and GEN2_BOXES or GEN1_BOXES
  for index in pairs(boxes) do
    local n = tonumber(index)
    if n and n > last then last = n end
  end
  for box = 1, last do
    local list = boxes[box]
    if type(list) == "table" then
      local name = boxName(slot.save, generation, box)
      for index, mon in ipairs(list) do
        if type(mon) == "table" then
          out[#out + 1] = { where = "box", box = box, index = index,
                            mon = mon, source = name }
        end
      end
    end
  end
  return out
end

function TeamPick.validate(source, team, rule)
  local slot = slotOf(source)
  rule = type(rule) == "table" and rule or {}
  if type(team) ~= "table" then return false, "pick a team first" end
  local want = tonumber(rule.partySize) or #team
  if #team ~= want then
    return false, ("this arena needs %d Pokemon."):format(want)
  end
  local seen = {}
  for _, ref in ipairs(team) do
    local key = TeamPick.refKey(ref)
    local mon = TeamPick.monAt(slot, ref)
    if not mon then return false, "that's not in this save." end
    if seen[key] then return false, "no doubles allowed." end
    seen[key] = true
    if mon.isEgg then return false, "an EGG can't battle." end
    if not rule.forceLevel then
      local level = tonumber(mon.level) or 0
      local min, max = tonumber(rule.minLevel), tonumber(rule.maxLevel)
      if min and level < min then
        return false, ("every Pokemon must be\nLv%d or higher."):format(min)
      end
      if max and level > max then
        return false, ("every Pokemon must be\nLv%d or lower."):format(max)
      end
    end
  end
  return true
end

TeamPick.GEN3_OFFLINE = "FireRed and LeafGreen can't join online rooms yet."

function TeamPick.pack(source, team, generation)
  local slot = slotOf(source)
  team = type(team) == "table" and team or {}
  if tonumber(generation) == 3 or tonumber(slot.generation) == 3 then
    return nil, TeamPick.GEN3_OFFLINE
  end
  local gen2 = tonumber(generation) == 2
  local mons = {}
  for _, ref in ipairs(team) do
    local mon = TeamPick.monAt(slot, ref)
    if mon then
      mons[#mons + 1] = gen2 and Protocol.packMon2(mon) or Protocol.packMon(mon)
    end
  end
  return mons
end

-- engine/link/time_capsule.asm:41
function TeamPick.convert(source, toGeneration, fromData, toData)
  local Convert = require("src.online.Convert")
  toGeneration = tonumber(toGeneration) or 1
  local list = TeamPick.candidates(source)
  local mons = {}
  for i, row in ipairs(list) do mons[i] = row.mon end
  local _, results
  if toGeneration == 1 then
    _, results = Convert.partyToGen1(mons, fromData, toData)
  else
    _, results = Convert.partyToGen2(mons, fromData, toData)
  end
  local byKey, rows, refusals = {}, {}, {}
  for index, row in ipairs(results or {}) do
    local ref = list[index]
    local key = ref and TeamPick.refKey(ref) or tostring(index)
    row.ref, row.key = ref, key
    rows[key] = row
    if row.ok then
      byKey[key] = row.mon
    else
      refusals[key] = row.reason or "refused"
    end
  end
  return byKey, rows, refusals, list
end

function TeamPick.packConverted(converted, team, generation)
  converted = type(converted) == "table" and converted or {}
  team = type(team) == "table" and team or {}
  if tonumber(generation) == 3 then return nil, TeamPick.GEN3_OFFLINE end
  local mons = {}
  for _, ref in ipairs(team) do
    local mon = converted[TeamPick.refKey(ref)]
    if type(mon) ~= "table" then
      return nil, "that Pokemon cannot cross generations."
    end
    mons[#mons + 1] = (tonumber(generation) == 2)
      and Protocol.packMon2(mon) or Protocol.packMon(mon)
  end
  return mons
end

return TeamPick
