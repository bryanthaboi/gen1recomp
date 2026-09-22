local Copy = require("src.mods.Merge").deepCopy
local Items = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local Mons = require("src.core.game3.save_mon")

local M = {}
local pockets = { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }
M.PC_ITEMS_COUNT = 30 -- include/constants/global.h:35

function M.itemId(data, id)
  local def = data and data.items and data.items[id]
  return tonumber(def and def.itemId) or Items.toNumericId(id) or id
end

function M.key(data, id)
  return tostring(M.itemId(data, id))
end

local function equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function M.ensureStorage(save)
  local legacy = type(save.storage) ~= "table"
  local source = legacy and Storage.restore(nil, save.pc, save.pcItems or save.pc_items) or save.storage
  local storage = {}
  for k, v in pairs(source) do storage[k] = v end
  storage.boxes, storage.items = {}, source.items or {}
  local boxes = {}
  local available = {}
  for b = 1, 14 do
    local original = source.boxes and source.boxes[b] or { name = "BOX " .. b, wallpaper = ((b - 1) % 16) + 1 }
    local box = {}
    for k, v in pairs(original) do box[k] = v end
    box.mons = {}
    for s, mon in pairs(original.mons or {}) do
      box.mons[s] = mon
      available[#available + 1] = { mon = mon }
    end
    storage.boxes[b], boxes[b] = box, box.mons
  end
  for b, box in pairs(save.boxes or {}) do
    for s, mon in pairs(type(box) == "table" and box or {}) do
      if type(s) == "number" and type(mon) == "table" then
        local mirrored = false
        for _, entry in ipairs(available) do
          if not entry.used and equal(entry.mon, mon) then entry.used = true; mirrored = true; break end
        end
        if not mirrored then
          local targetB, targetS
          if boxes[b] and s >= 1 and s <= 30 and s == math.floor(s) and not boxes[b][s] then
            targetB, targetS = b, s
          else
            targetB, targetS = Storage.findOpenSlot(storage)
          end
          if not targetB then error("Cannot preserve legacy box Pokemon: native storage is full") end
          boxes[targetB][targetS] = mon
        end
      end
    end
  end
  save.storage = storage
  if legacy and type(save.pc) == "table" then save.pc.mons, save.pc.items = nil, nil end
  save.boxes = boxes
  save.currentBox = math.max(1, math.min(14, tonumber(storage.currentBox) or 1))
  return boxes
end

local function project(data, slots, out, order)
  for _, slot in ipairs(slots or {}) do
    if slot.id ~= nil and (tonumber(slot.qty) or 0) > 0 then
      local key = M.key(data, slot.id)
      if not out[key] and order then order[#order + 1] = key end
      out[key] = (out[key] or 0) + slot.qty
    end
  end
end

function M.project(data, save)
  local inv, order, pc = {}, {}, {}
  for _, pocket in ipairs(pockets) do project(data, save.bag.pockets[pocket], inv, order) end
  project(data, save.storage.items, pc)
  save.inventory, save.bagOrder, save.pcItems = inv, order, pc
  save.bag.stacks = Copy(inv)
end

function M.hydrate(data, save)
  M.ensureStorage(save)
  if type(save.bag) ~= "table" then save.bag = Copy(save.inventory or {}) end
  if type(save.bag.pockets) ~= "table" then
    local source = save.bag
    if not source.stacks and not source.items then source = { stacks = source } end
    save.bag = Bag.migrate(Copy(source))
  end
  M.project(data, save)
end

function M.export(save)
  local out = Copy(save)
  M.ensureStorage(out)
  Mons.each(out, Mons.normalize)
  out.inventory = Copy(out.bag)
  out.boxes, out.pcItems, out.bagOrder = nil, nil, nil
  return out
end

local function locate(data, slots, id)
  for i, slot in ipairs(slots) do
    if M.key(data, slot.id) == M.key(data, id) then return i, slot end
  end
end

function M.quantity(data, save, pc, id)
  local key = M.key(data, id)
  return tonumber((pc and save.pcItems or save.inventory or {})[key]) or 0
end

local function set(data, save, pc, id, qty)
  if type(qty) ~= "number" or qty ~= math.floor(qty) or qty < 0 or qty > 999 then return false end
  id = M.itemId(data, id)
  local slots, cap
  if pc then
    slots, cap = save.storage.items, M.PC_ITEMS_COUNT
  else
    for _, p in ipairs(pockets) do
      local list = save.bag.pockets[p]
      if list and locate(data, list, id) then slots = list; break end
    end
    local pocket = Items.pocketOf(id)
    slots = slots or save.bag.pockets[pocket]
    if not slots then slots = {}; save.bag.pockets[pocket] = slots end
    cap = Items.CAPACITY[pocket] or 42
  end
  local lists = pc and { slots } or {}
  if not pc then for _, p in ipairs(pockets) do lists[#lists + 1] = save.bag.pockets[p] or {} end end
  local found = false
  for _, list in ipairs(lists) do
    local i = 1
    while i <= #list do
      local slot = list[i]
      if M.key(data, slot.id) == M.key(data, id) then
        if not found and qty > 0 then
          slot.qty = qty
          found = true
          i = i + 1
        else
          found = true
          table.remove(list, i)
        end
      else i = i + 1 end
    end
  end
  if found then
    return true
  elseif qty > 0 then
    if #slots >= cap then return false end
    if not pc then
      local pocket = Items.pocketOf(id)
      local container = pocket == "TM_CASE" and Items.ITEM_TM_CASE or pocket == "BERRY_POUCH" and Items.ITEM_BERRY_POUCH
      if container and not locate(data, save.bag.pockets.KEY_ITEMS or {}, container) then
        if not set(data, save, false, container, 1) then return false end
      end
    end
    slots[#slots + 1] = { id = id, qty = qty }
  end
  return true
end

function M.change(data, save, pc, changes)
  local staged = { bag = pc and save.bag or Copy(save.bag), storage = save.storage }
  if pc then
    staged.storage = {}
    for k, value in pairs(save.storage) do staged.storage[k] = value end
    staged.storage.items = Copy(save.storage.items)
  end
  for _, change in ipairs(changes) do
    if not set(data, staged, pc, change.id, change.qty) then return false end
  end
  save.bag, save.storage = staged.bag, staged.storage
  M.ensureStorage(save)
  M.project(data, save)
  return true
end

-- src/item_menu.c:2004 Task_TryDoItemDeposit / src/item.c:385 AddPCItem
function M.transfer(data, save, toPc, id, qty)
  if type(qty) ~= "number" or qty <= 0 or qty ~= math.floor(qty) then return false end
  local fromQty = M.quantity(data, save, not toPc, id)
  local toQty = M.quantity(data, save, toPc, id)
  if qty > fromQty or toQty + qty > 999 then return false end
  local staged = { bag = Copy(save.bag), storage = {} }
  for k, value in pairs(save.storage) do staged.storage[k] = value end
  staged.storage.items = Copy(save.storage.items)
  if not set(data, staged, toPc, id, toQty + qty) then return false end
  if not set(data, staged, not toPc, id, fromQty - qty) then return false end
  save.bag, save.storage = staged.bag, staged.storage
  M.ensureStorage(save)
  M.project(data, save)
  return true
end

return M
