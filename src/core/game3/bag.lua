-- game3 bag: pret ItemSlot pockets (AddBagItem / CheckBagHasSpace).
-- Qty ≤ 999. Caps: ITEMS 42, KEY 30, BALLS 13, TMHM 58, BERRIES 43.

local Items = require("src.core.game3.items")
local ItemsData = require("src.core.game3.items_data")

local Bag = {}

local POCKET_KEYS = {
  "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH",
}

local function empty_pockets()
  local p = {}
  for _, k in ipairs(POCKET_KEYS) do
    p[k] = {}
  end
  return p
end

function Bag.new()
  return {
    pockets = empty_pockets(),
    -- Legacy mirror rebuilt on mutate for old UI / ferry code paths.
    stacks = {},
  }
end

local function slot_id_eq(a, b)
  if a == nil or b == nil then return false end
  local na, nb = ItemsData.toNumericId(a), ItemsData.toNumericId(b)
  if na and nb then return na == nb end
  return ItemsData.bagKey(a) == ItemsData.bagKey(b)
end

local function find_slot(slots, id)
  if not slots then return nil, nil end
  for i, slot in ipairs(slots) do
    if slot_id_eq(slot.id, id) then
      return i, slot
    end
  end
  return nil, nil
end

local function compact(slots)
  local out = {}
  if type(slots) ~= "table" then return out end
  for _, slot in ipairs(slots) do
    if slot.id and (tonumber(slot.qty) or 0) > 0 then
      out[#out + 1] = { id = slot.id, qty = tonumber(slot.qty) or 0 }
    end
  end
  return out
end

local function sort_tm_pocket(slots)
  -- pret SortPocketAndPlaceHMsFirst: HMs first, then TMs, stable-ish by id.
  table.sort(slots, function(a, b)
    local ah, bh = ItemsData.isHm(a.id), ItemsData.isHm(b.id)
    if ah ~= bh then return ah end
    local na = ItemsData.toNumericId(a.id) or 0
    local nb = ItemsData.toNumericId(b.id) or 0
    return na < nb
  end)
end

local function grant_key(bag, itemId)
  local keySlots = bag.pockets.KEY_ITEMS
  if not keySlots then return false end
  for _, slot in ipairs(keySlots) do
    if slot_id_eq(slot.id, itemId) then return true end
  end
  local cap = ItemsData.CAPACITY.KEY_ITEMS or 30
  if #keySlots >= cap then return false end
  keySlots[#keySlots + 1] = { id = itemId, qty = 1 }
  return true
end

local function sanitize_pockets(bag)
  if not bag or type(bag.pockets) ~= "table" then return end
  local misplaced = {}
  for _, k in ipairs(POCKET_KEYS) do
    local slots = bag.pockets[k] or {}
    local keep = {}
    for _, slot in ipairs(slots) do
      local correctPocket = ItemsData.pocketOf(slot.id)
      if correctPocket ~= k then
        misplaced[#misplaced + 1] = { id = slot.id, qty = tonumber(slot.qty) or 1, target = correctPocket }
      else
        keep[#keep + 1] = slot
      end
    end
    bag.pockets[k] = compact(keep)
  end

  for _, m in ipairs(misplaced) do
    local targetSlots = bag.pockets[m.target] or {}
    local idx, slot = find_slot(targetSlots, m.id)
    if slot then
      slot.qty = (tonumber(slot.qty) or 0) + m.qty
    else
      targetSlots[#targetSlots + 1] = { id = m.id, qty = m.qty }
    end
    bag.pockets[m.target] = compact(targetSlots)
  end

  if bag.pockets.TM_CASE and #bag.pockets.TM_CASE > 0 then
    sort_tm_pocket(bag.pockets.TM_CASE)
    grant_key(bag, ItemsData.ITEM_TM_CASE)
  end
  if bag.pockets.BERRY_POUCH and #bag.pockets.BERRY_POUCH > 0 then
    grant_key(bag, ItemsData.ITEM_BERRY_POUCH)
  end
end

local function rebuild_stacks(bag)
  bag.stacks = {}
  for _, k in ipairs(POCKET_KEYS) do
    for _, slot in ipairs(bag.pockets[k] or {}) do
      local id = slot.id
      local qty = tonumber(slot.qty) or 0
      if id and qty > 0 then
        local key = ItemsData.bagKey(id)
        bag.stacks[key] = (bag.stacks[key] or 0) + qty
        -- Also mirror host string if known
        local num = ItemsData.toNumericId(id)
        if num and Items.FRLG_TO_HOST[num] then
          bag.stacks[Items.FRLG_TO_HOST[num]] = bag.stacks[key]
        end
      end
    end
  end
end

local function ensure(bag)
  if not bag then return nil end
  if type(bag.pockets) ~= "table" then
    Bag.migrate(bag)
  end
  for _, k in ipairs(POCKET_KEYS) do
    bag.pockets[k] = bag.pockets[k] or {}
  end
  sanitize_pockets(bag)
  bag.stacks = bag.stacks or {}
  return bag
end

--- Migrate legacy { stacks } or schema { items=… } into pockets.
function Bag.migrate(bag)
  if not bag then return Bag.new() end
  if type(bag.pockets) == "table" and bag.pockets.ITEMS then
    ensure(bag)
    rebuild_stacks(bag)
    return bag
  end

  local fresh = Bag.new()
  local function absorb(id, qty)
    qty = tonumber(qty) or 0
    if qty > 0 and id ~= nil then
      Bag.add(fresh, id, qty)
    end
  end

  if type(bag.stacks) == "table" then
    for id, qty in pairs(bag.stacks) do
      absorb(id, qty)
    end
  end

  -- Schema newGame shape
  local map = {
    items = "ITEMS",
    keyItems = "KEY_ITEMS",
    pokeballs = "POKE_BALLS",
    berries = "BERRY_POUCH",
    tmsHms = "TM_CASE",
  }
  for field, _ in pairs(map) do
    local list = bag[field]
    if type(list) == "table" then
      for _, entry in ipairs(list) do
        if type(entry) == "table" then
          absorb(entry.id or entry.itemId or entry[1], entry.qty or entry.quantity or entry[2] or 1)
        elseif entry then
          absorb(entry, 1)
        end
      end
      -- also allow map form
      for id, qty in pairs(list) do
        if type(id) ~= "number" or type(qty) ~= "table" then
          if type(qty) == "number" then absorb(id, qty) end
        end
      end
    end
  end

  bag.pockets = fresh.pockets
  bag.stacks = fresh.stacks
  -- Drop legacy pocket table fields from schema shape if present
  return bag
end

function Bag.clear(bag)
  bag = ensure(bag)
  bag.pockets = empty_pockets()
  bag.stacks = {}
end

function Bag.get(bag, id)
  bag = ensure(bag)
  if not bag or id == nil then return 0 end
  local pocket = ItemsData.pocketOf(id)
  local slots = bag.pockets[pocket] or {}
  local _, slot = find_slot(slots, id)
  if slot then return tonumber(slot.qty) or 0 end
  -- stacks fallback
  return bag.stacks[ItemsData.bagKey(id)]
    or bag.stacks[tostring(id)]
    or 0
end

function Bag.has(bag, id, qty)
  qty = math.max(1, math.floor(tonumber(qty) or 1))
  return Bag.get(bag, id) >= qty
end

function Bag.canAdd(bag, id, qty)
  bag = ensure(bag)
  qty = math.max(1, math.floor(tonumber(qty) or 1))
  if not id then return false end
  local pocket = ItemsData.pocketOf(id)
  local cap = ItemsData.CAPACITY[pocket] or 42
  local slots = bag.pockets[pocket] or {}
  local _, slot = find_slot(slots, id)
  if slot then
    local have = tonumber(slot.qty) or 0
    return (have + qty) <= Items.GAME3_MAX_QTY
  end
  -- Need empty slot; TM Case / Berry Pouch auto-grant may need KEY slot too
  if #slots >= cap then return false end
  if pocket == "TM_CASE" and not Bag.has(bag, ItemsData.ITEM_TM_CASE, 1) then
    local keySlots = bag.pockets.KEY_ITEMS or {}
    if #keySlots >= (ItemsData.CAPACITY.KEY_ITEMS or 30) and not find_slot(keySlots, ItemsData.ITEM_TM_CASE) then
      return false
    end
  end
  if pocket == "BERRY_POUCH" and not Bag.has(bag, ItemsData.ITEM_BERRY_POUCH, 1) then
    local keySlots = bag.pockets.KEY_ITEMS or {}
    if #keySlots >= (ItemsData.CAPACITY.KEY_ITEMS or 30) and not find_slot(keySlots, ItemsData.ITEM_BERRY_POUCH) then
      return false
    end
  end
  return true
end


function Bag.add(bag, id, qty)
  bag = ensure(bag)
  qty = math.max(0, math.floor(tonumber(qty) or 1))
  if qty <= 0 or not id then return false, 0 end

  -- Prefer numeric FRLG id in slots
  local num = ItemsData.toNumericId(id)
  local storeId = num or id

  if not Bag.canAdd(bag, storeId, qty) then
    return false, 0
  end

  local pocket = ItemsData.pocketOf(storeId)

  if pocket == "TM_CASE" and not Bag.has(bag, ItemsData.ITEM_TM_CASE, 1) then
    if not grant_key(bag, ItemsData.ITEM_TM_CASE) then
      return false, 0
    end
  end
  if pocket == "BERRY_POUCH" and not Bag.has(bag, ItemsData.ITEM_BERRY_POUCH, 1) then
    if not grant_key(bag, ItemsData.ITEM_BERRY_POUCH) then
      return false, 0
    end
  end
  if num == ItemsData.ITEM_BERRY_POUCH or storeId == ItemsData.ITEM_BERRY_POUCH then
    -- Flag handled by scripting later; bag just stores the key item.
  end

  local slots = bag.pockets[pocket]
  local idx, slot = find_slot(slots, storeId)
  if slot then
    local have = tonumber(slot.qty) or 0
    local nextQty = Items.clampGame3(have + qty)
    local placed = nextQty - have
    slot.qty = nextQty
    rebuild_stacks(bag)
    return placed == qty, placed
  end

  slots[#slots + 1] = { id = storeId, qty = Items.clampGame3(qty) }
  if pocket == "TM_CASE" then
    sort_tm_pocket(slots)
  end
  rebuild_stacks(bag)
  return true, qty
end

function Bag.remove(bag, id, qty)
  bag = ensure(bag)
  qty = math.max(1, math.floor(tonumber(qty) or 1))
  if not id then return false end
  local num = ItemsData.toNumericId(id)
  local storeId = num or id
  local pocket = ItemsData.pocketOf(storeId)
  local slots = bag.pockets[pocket]
  local idx, slot = find_slot(slots, storeId)
  if not slot then return false end
  local have = tonumber(slot.qty) or 0
  if have < qty then return false end
  slot.qty = have - qty
  if slot.qty <= 0 then
    table.remove(slots, idx)
  end
  bag.pockets[pocket] = compact(slots)
  if pocket == "TM_CASE" then
    sort_tm_pocket(bag.pockets[pocket])
  end
  rebuild_stacks(bag)
  return true
end


function Bag.set(bag, id, qty)
  qty = Items.clampGame3(qty)
  local have = Bag.get(bag, id)
  if qty <= 0 then
    if have > 0 then Bag.remove(bag, id, have) end
    return 0
  end
  if have > qty then
    Bag.remove(bag, id, have - qty)
  elseif have < qty then
    Bag.add(bag, id, qty - have)
  end
  return Bag.get(bag, id)
end

--- Ordered list of { id, qty, name, info } for a pocket (bag UI).
function Bag.listPocket(bag, pocket)
  bag = ensure(bag)
  pocket = pocket or "ITEMS"
  local rows = {}
  for _, slot in ipairs(bag.pockets[pocket] or {}) do
    local qty = tonumber(slot.qty) or 0
    if slot.id and qty > 0 then
      rows[#rows + 1] = {
        id = slot.id,
        qty = qty,
        name = ItemsData.displayName(slot.id),
        info = ItemsData.info(slot.id),
        description = ItemsData.description(slot.id),
      }
    end
  end
  return rows
end

function Bag.mergeFromHost(bag, hostInventory)
  bag = ensure(bag)
  if type(hostInventory) ~= "table" then return end
  for id, qty in pairs(hostInventory) do
    if type(id) == "string" and not id:find("BADGE", 1, true) then
      local n = tonumber(qty) or 0
      if n > 0 then
        local num = ItemsData.toNumericId(id)
        if num or Items.isHostSafe(id) then
          Bag.add(bag, num or id, n)
        end
      end
    end
  end
end

function Bag.restoreSidecar(bag, sidecar)
  bag = ensure(bag)
  if type(sidecar) ~= "table" then return end
  local function absorb(tbl)
    if type(tbl) ~= "table" then return end
    for id, qty in pairs(tbl) do
      local n = tonumber(qty) or 0
      if n > 0 then Bag.add(bag, id, n) end
    end
  end
  absorb(sidecar.quarantine)
  absorb(sidecar.overflow)
  absorb(sidecar.bag)
  if type(sidecar.stacks) == "table" then absorb(sidecar.stacks) end
end

function Bag.splitForHost(bag, hostInventory)
  hostInventory = hostInventory or {}
  local hostWrites, quarantine, overflow = {}, {}, {}
  bag = ensure(bag)
  if not bag then return hostWrites, quarantine, overflow end
  -- Iterate pockets once (avoid double-count from stacks numeric+host mirrors).
  for _, pocket in ipairs(POCKET_KEYS) do
    for _, slot in ipairs(bag.pockets[pocket] or {}) do
      local qty = Items.clampGame3(slot.qty)
      if slot.id and qty > 0 then
        local num = ItemsData.toNumericId(slot.id)
        local hostId = (num and Items.FRLG_TO_HOST[num])
          or (type(slot.id) == "string" and not tonumber(slot.id) and slot.id)
          or nil
        if not hostId then
          local qkey = num and ("FRLG_" .. tostring(num)) or tostring(slot.id)
          quarantine[qkey] = (quarantine[qkey] or 0) + qty
        elseif not Items.isHostSafe(hostId) then
          quarantine[hostId] = (quarantine[hostId] or 0) + qty
        else
          local room = Items.HOST_MAX_QTY
          local placed = math.min(qty, room)
          if placed > 0 then
            hostWrites[hostId] = (hostWrites[hostId] or 0) + placed
          end
          local rem = qty - placed
          if rem > 0 then
            overflow[hostId] = (overflow[hostId] or 0) + rem
          end
        end
      end
    end
  end
  return hostWrites, quarantine, overflow
end

function Bag.applyHostWrites(save, hostWrites)
  if not save then return end
  save.inventory = save.inventory or {}
  local BagHost = require("src.inventory.Bag")
  for id, qty in pairs(hostWrites) do
    qty = math.min(Items.HOST_MAX_QTY, math.floor(tonumber(qty) or 0))
    if qty <= 0 then
      if BagHost.remove then
        local have = save.inventory[id] or 0
        if have > 0 then BagHost.remove(save, id, have) end
      else
        save.inventory[id] = nil
      end
    else
      save.inventory[id] = qty
      if BagHost.order then
        local order = BagHost.order(save)
        local found = false
        for _, oid in ipairs(order) do
          if oid == id then found = true break end
        end
        if not found then table.insert(order, id) end
      end
    end
  end
end

return Bag
