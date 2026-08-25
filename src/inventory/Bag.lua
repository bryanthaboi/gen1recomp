-- Gen 2 keeps FOUR pockets, not Gen 1's single bag (item_data_constants.asm):
-- Items 20, Balls 12, Key Items 25, TM/HM 57.  A distinct item id occupies one
-- slot of ITS OWN pocket regardless of quantity, and a pocket fills
-- independently -- which is exactly why the cart can hold every TM, every key
-- item AND still pick up an HM.  Modelling all four as one 20-slot list filled
-- the bag with TMs and key items by the Ice Path and refused HM07 WATERFALL.
-- Badges live in the inventory table but are not bag items.  save.bagOrder
-- keeps acquisition order like wBagItems (SELECT can reorder it).

local Bag = {}

-- MAX_ITEMS / MAX_BALLS / MAX_KEY_ITEMS, and the TM/HM pocket holds one of
-- every TM plus the seven HMs (NUM_TMS + NUM_HMS -- ram/wram.asm:2421 is
-- `wTMsHMs:: ds NUM_TMS + NUM_HMS`, 57 bytes).  A `mods` bagSize override
-- replaces the ITEM pocket only, the way the Gen 1 single-bag config did.
local POCKET_CAPACITY = {
  ITEM = 20,
  BALL = 12,
  KEY_ITEM = 25,
  TM_HM = 57,
}
local DEFAULT_CAPACITY = 20

local function isBadge(id)
  return id:find("BADGE", 1, true) ~= nil
end

-- Which pocket an id belongs to.  Unknown ids (a stale cache, a mod that did
-- not declare a pocket) fall to ITEM, the Gen 1 behaviour.
local function pocketOf(id, data)
  data = data or require("src.core.Data")
  local def = data and data.items and data.items[id]
  return (def and def.pocket) or "ITEM"
end
Bag.pocketOf = pocketOf

-- `data` is injectable for the save editor and headless mod tests.  Normal
-- gameplay may omit it because the loader merges mods into the Data
-- singleton before any item can be added.  A pocket argument gives that
-- pocket's cap; omitting it keeps the old single-number ITEM answer so
-- existing callers (and the mod bagSize override) are unchanged.
function Bag.capacity(data, pocket)
  data = data or require("src.core.Data")
  if pocket and pocket ~= "ITEM" then
    return POCKET_CAPACITY[pocket] or DEFAULT_CAPACITY
  end
  local configured = data and data.constants and data.constants.bagSize
  if type(configured) == "number" and configured >= 1 then
    return math.floor(configured)
  end
  return POCKET_CAPACITY.ITEM
end

-- exported so item lists that share save.inventory (e.g. the PC deposit
-- menu) can exclude badges the same way the bag does
Bag.isBadge = isBadge

-- Occupied slots, of one pocket when named or of the whole inventory when not.
function Bag.slots(save, data, pocket)
  local n = 0
  for id in pairs(save.inventory) do
    if not isBadge(id)
        and (not pocket or pocketOf(id, data) == pocket) then
      n = n + 1
    end
  end
  return n
end

-- Acquisition-ordered id list (wBagItems).  Rebuilt sorted once for
-- saves from before the order existed, then maintained incrementally.
function Bag.order(save, data)
  local order = save.bagOrder
  if not order then
    local items = (data or require("src.core.Data")).items
    order = {}
    for id in pairs(save.inventory) do
      if not isBadge(id) then table.insert(order, id) end
    end
    table.sort(order, function(a, b)
      local ia = (items and items[a] and items[a].index) or math.huge
      local ib = (items and items[b] and items[b].index) or math.huge
      if ia ~= ib then return ia < ib end
      return a < b
    end)
    save.bagOrder = order
  end
  -- drop stale ids, append unknown ones (defensive against direct
  -- inventory writes)
  local seen = {}
  for i = #order, 1, -1 do
    local id = order[i]
    if not save.inventory[id] or seen[id] then
      table.remove(order, i)
    else
      seen[id] = true
    end
  end
  for id in pairs(save.inventory) do
    if not isBadge(id) and not seen[id] then table.insert(order, id) end
  end
  return order
end

-- engine/items/switch_items.asm:38 SwitchItemsInBag .below / .above -- the
-- rotate the PACK's SELECT performs, over the rows of ONE pocket.
function Bag.move(save, id, pocket, toIndex, data)
  local order = Bag.order(save, data)
  local slots, ids = {}, {}
  for i = 1, #order do
    if pocketOf(order[i], data) == pocket then
      slots[#slots + 1] = i
      ids[#ids + 1] = order[i]
    end
  end
  local from
  for i = 1, #ids do
    if ids[i] == id then from = i break end
  end
  if not from then return false end
  local to = math.max(1, math.min(math.floor(tonumber(toIndex) or from), #ids))
  if to == from then return false end
  table.insert(ids, to, table.remove(ids, from))
  for i = 1, #slots do order[slots[i]] = ids[i] end
  return true
end

-- Add qty of an item; returns false (and adds nothing) when a new slot
-- is needed and the bag is full, or when the stack would pass 99
-- (AddItemToInventory's per-slot quantity cap).
function Bag.add(save, id, qty, data)
  local inv = save.inventory
  -- Only the item's OWN pocket has to have room -- a full ITEM pocket does not
  -- keep a KEY_ITEM or an HM out, which is the whole point of pockets.
  local pocket = pocketOf(id, data)
  if not inv[id] and not isBadge(id)
      and Bag.slots(save, data, pocket) >= Bag.capacity(data, pocket) then
    return false
  end
  if not isBadge(id) and (inv[id] or 0) + (qty or 1) > 99 then
    return false
  end
  -- Insert into the order BEFORE the inventory write: Bag.order's defensive
  -- append reads save.inventory, so writing first made it add the id and the
  -- table.insert below add it again -- one pickup, two bag rows, until the
  -- next order() pass deduped it (and a save taken in between kept both).
  local isNew = not inv[id]
  if isNew and not isBadge(id) then
    table.insert(Bag.order(save), id)
  end
  inv[id] = (inv[id] or 0) + (qty or 1)
  return true
end

-- Remove qty (default 1); clears the slot and its order entry at zero.
function Bag.remove(save, id, qty)
  local inv = save.inventory
  inv[id] = (inv[id] or 0) - (qty or 1)
  if inv[id] <= 0 then
    inv[id] = nil
    local order = save.bagOrder
    if order then
      for i, oid in ipairs(order) do
        if oid == id then table.remove(order, i) break end
      end
    end
  end
end

return Bag
