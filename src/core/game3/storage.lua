-- Gen 3 (FRLG) Pokémon Storage System & Player PC (pret pokemon_storage_system.c).
--
-- 14 Boxes × 30 Slots = 420 Pokémon Capacity.
-- 50 Unique Item Slots in Player's PC.
-- Includes PC Heal Exploit, Circular Spillover, Sparse Serialization, and Bag-Full Guard.

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Strings = require("src.core.Strings")

local Storage = {}

Storage.TOTAL_BOXES_COUNT = 14
Storage.IN_BOX_COUNT = 30
Storage.TOTAL_BOX_MONS = 420
Storage.PC_ITEMS_COUNT = 50
Storage.MAX_ITEM_QTY = 999

local VAR_PC_BOX_TO_SEND_MON = 0x4037 -- pokefirered/include/constants/vars.h:105
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843 -- pokefirered/include/constants/flags.h:1401
local FLAG_SYS_NOT_SOMEONES_PC = 0x834 -- pokefirered/include/constants/flags.h:1386

local function script_store(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  return (Space and Space.store) or (session and session.store) or nil
end

Storage.WALLPAPERS = {
  [1] = "Forest",
  [2] = "City",
  [3] = "Desert",
  [4] = "Savanna",
  [5] = "Crag",
  [6] = "Volcano",
  [7] = "Snow",
  [8] = "Cave",
  [9] = "Beach",
  [10] = "Seafloor",
  [11] = "River",
  [12] = "Sky",
  [13] = "Stars",
  [14] = "Pokecenter",
  [15] = "Tiles",
  [16] = "Simple",
}

--- Create a fresh Storage instance (14 boxes, 30 slots each, 50-item PC).
function Storage.new()
  local storage = {
    currentBox = 1,
    boxes = {},
    items = { { id = 13, qty = 1 } }, -- 50-slot Player PC item storage (starts with 1 POTION, pokefirered/src/player_pc.c:100)
  }
  for b = 1, Storage.TOTAL_BOXES_COUNT do
    storage.boxes[b] = {
      name = string.format("BOX %d", b),
      wallpaper = ((b - 1) % 16) + 1,
      mons = {}, -- 1..30 slots (nil = empty)
    }
  end
  return storage
end

--- Ensure session has storage initialized.
function Storage.ensure(session)
  if not session then return nil end
  if not session.storage then
    session.storage = Storage.new()
  end
  if not session.storage.boxes or #session.storage.boxes < Storage.TOTAL_BOXES_COUNT then
    local fresh = Storage.new()
    fresh.currentBox = session.storage.currentBox or 1
    fresh.items = session.storage.items or fresh.items
    for b = 1, Storage.TOTAL_BOXES_COUNT do
      if session.storage.boxes and session.storage.boxes[b] then
        fresh.boxes[b] = session.storage.boxes[b]
      end
    end
    session.storage = fresh
  end
  if not session.storage.items then
    session.storage.items = { { id = 13, qty = 1 } }
  end
  return session.storage
end

--- The "PC Heal" Exploit: Fully heals HP, restores all move PPs, and clears status ailments.
function Storage.fullHealMon(mon)
  if not mon or type(mon) ~= "table" then return mon end
  -- Restore HP
  if mon.maxHp and mon.maxHp > 0 then
    mon.hp = mon.maxHp
  elseif mon.hp then
    mon.hp = mon.maxHp or mon.hp
  end
  -- Restore move PPs
  if type(mon.moves) == "table" then
    for _, move in ipairs(mon.moves) do
      if type(move) == "table" then
        if move.maxPp and move.maxPp > 0 then
          move.pp = move.maxPp
        elseif move.pp then
          move.pp = move.maxPp or move.pp or 35
        end
      end
    end
  end
  -- Clear all non-volatile & volatile statuses
  mon.status = nil
  mon.statusAilment = nil
  mon.sleepTurns = nil
  mon.fainted = false
  return mon
end

--- Get Box table by ID (1..14).
function Storage.getBox(storage, boxId)
  if not storage or not storage.boxes then return nil end
  return storage.boxes[boxId]
end

--- Get Pokémon in a specific box slot (1..30).
function Storage.getBoxMon(storage, boxId, slotIdx)
  local box = Storage.getBox(storage, boxId)
  return box and box.mons and box.mons[slotIdx]
end

--- Count Pokémon in a specific box.
function Storage.countBoxMons(storage, boxId)
  if not storage or not storage.boxes or not storage.boxes[boxId] then return 0 end
  local count = 0
  for slot = 1, Storage.IN_BOX_COUNT do
    if storage.boxes[boxId].mons[slot] ~= nil then
      count = count + 1
    end
  end
  return count
end

--- Count total Pokémon across all 14 boxes.
function Storage.countTotalMons(storage)
  if not storage or not storage.boxes then return 0 end
  local count = 0
  for b = 1, Storage.TOTAL_BOXES_COUNT do
    count = count + Storage.countBoxMons(storage, b)
  end
  return count
end

--- Find the first open slot starting from currentBox, iterating circularly through all 14 boxes.
-- Returns: boxId, slotIdx (or nil, nil if completely full).
function Storage.findOpenSlot(storage)
  if not storage then return nil, nil end
  local cur = storage.currentBox or 1
  for offset = 0, Storage.TOTAL_BOXES_COUNT - 1 do
    local b = ((cur - 1 + offset) % Storage.TOTAL_BOXES_COUNT) + 1
    local box = storage.boxes[b]
    if box then
      for s = 1, Storage.IN_BOX_COUNT do
        if box.mons[s] == nil then
          return b, s
        end
      end
    end
  end
  return nil, nil
end

--- Deposit a Pokémon from party into a box.
-- Performs the authentic Gen 3 "PC Heal".
-- Returns: success (bool), boxId, slotIdx / error_reason.
function Storage.deposit(session, partyIdx, targetBoxId, targetSlotIdx)
  if not session or not session.party or not session.party[partyIdx] then
    return false, "invalid_party_mon"
  end
  if #session.party <= 1 then
    return false, "last_pokemon"
  end
  local storage = Storage.ensure(session)
  local bId = targetBoxId or storage.currentBox or 1
  local box = storage.boxes[bId]
  if not box then return false, "invalid_box" end

  local slot = targetSlotIdx
  if not slot or box.mons[slot] ~= nil then
    -- Find first open slot in target box
    for s = 1, Storage.IN_BOX_COUNT do
      if box.mons[s] == nil then
        slot = s
        break
      end
    end
  end
  if not slot then
    return false, "box_full"
  end

  local mon = table.remove(session.party, partyIdx)
  Storage.fullHealMon(mon)
  box.mons[slot] = mon
  require("src.core.game3.quest_log_recorder").event(session,"DepositedMonInPC",
    {D0=require("src.core.game3.pokemon").displayMonName(mon),D1=box.name})
  return true, bId, slot
end

--- Withdraw a Pokémon from a box into the party.
-- Returns: success (bool), partyIdx / error_reason.
function Storage.withdraw(session, boxId, slotIdx)
  if not session then return false, "no_session" end
  session.party = session.party or {}
  if #session.party >= 6 then
    return false, "party_full"
  end
  local storage = Storage.ensure(session)
  local box = storage.boxes[boxId]
  if not box or not box.mons[slotIdx] then
    return false, "empty_slot"
  end

  local mon = box.mons[slotIdx]
  box.mons[slotIdx] = nil
  session.party[#session.party + 1] = mon
  require("src.core.game3.quest_log_recorder").event(session,"WithdrewMonFromPC",
    {D0=box.name,D1=require("src.core.game3.pokemon").displayMonName(mon)})
  return true, #session.party
end

--- Move / Swap Pokémon between locations (party <-> party, party <-> box, box <-> box).
-- Handles PC heal if moving into a box.
-- srcLoc/destLoc: "party" | "box"
function Storage.moveMon(session, srcLoc, srcIdx, destLoc, destIdx, srcBox, destBox)
  if not session then return false, "no_session" end
  local storage = Storage.ensure(session)
  session.party = session.party or {}

  local srcMon, destMon

  if srcLoc == "party" then
    srcMon = session.party[srcIdx]
  elseif srcLoc == "box" then
    local box = storage.boxes[srcBox or storage.currentBox]
    srcMon = box and box.mons[srcIdx]
  end

  if destLoc == "party" then
    destMon = session.party[destIdx]
  elseif destLoc == "box" then
    local box = storage.boxes[destBox or storage.currentBox]
    destMon = box and box.mons[destIdx]
  end

  if not srcMon then return false, "src_empty" end

  -- Cannot leave party empty if withdrawing/moving away
  if srcLoc == "party" and destLoc == "box" and not destMon and #session.party <= 1 then
    return false, "last_pokemon"
  end

  -- Apply PC heal to any mon landing in a box
  if destLoc == "box" then Storage.fullHealMon(srcMon) end
  if srcLoc == "box" and destMon then Storage.fullHealMon(destMon) end

  -- Assign to dest
  if destLoc == "party" then
    session.party[destIdx] = srcMon
  elseif destLoc == "box" then
    local box = storage.boxes[destBox or storage.currentBox]
    box.mons[destIdx] = srcMon
  end

  -- Assign to src
  if srcLoc == "party" then
    session.party[srcIdx] = destMon
    -- Clean up trailing nils in party array if moved without swap
    if not destMon and srcIdx > #session.party then
      -- compact party
      local newParty = {}
      for _, m in pairs(session.party) do
        if m then newParty[#newParty + 1] = m end
      end
      session.party = newParty
    end
  elseif srcLoc == "box" then
    local box = storage.boxes[srcBox or storage.currentBox]
    box.mons[srcIdx] = destMon
  end

  local Q=require("src.core.game3.quest_log_recorder")
  local Pokemon=require("src.core.game3.pokemon")
  local srcName=Pokemon.displayMonName(srcMon)
  local dstName=destMon and Pokemon.displayMonName(destMon)
  local srcBoxName=storage.boxes[srcBox or storage.currentBox].name
  local dstBoxName=storage.boxes[destBox or storage.currentBox].name
  if srcLoc=="party" and destLoc=="party" then
    Q.event(session,"SwitchMon1WithMon2",{srcName,dstName})
  elseif srcLoc=="box" and destLoc=="box" then
    local same=(srcBox or storage.currentBox)==(destBox or storage.currentBox)
    local key=destMon and (same and "SwitchedMonsWithinBox" or "SwitchedMonsBetweenBoxes")
      or (same and "MovedMonWithinBox" or "MovedMonToNewBox")
    Q.event(session,key,{D0=srcBoxName,D1=srcName,D2=destMon and (same and dstName or dstBoxName) or dstBoxName,D3=dstName})
  elseif destMon then
    Q.event(session,"SwitchedPartyMonForPCMon",{D0=srcLoc=="box" and srcBoxName or dstBoxName,
      D1=srcLoc=="box" and srcName or dstName,D2=srcLoc=="party" and srcName or dstName})
  elseif srcLoc=="party" then
    Q.event(session,"DepositedMonInPC",{D0=srcName,D1=dstBoxName})
  else Q.event(session,"WithdrewMonFromPC",{D0=srcBoxName,D1=srcName}) end
  return true
end

--- Release a Pokémon from a box slot.
function Storage.releaseMon(session, boxId, slotIdx)
  local storage = Storage.ensure(session)
  local box = storage.boxes[boxId]
  if not box or not box.mons[slotIdx] then
    return nil, "empty_slot"
  end
  local mon = box.mons[slotIdx]
  box.mons[slotIdx] = nil
  return mon
end

-- pokefirered/src/pokemon.c:3708
function Storage.sendMonToPC(session, mon)
  if not session or not mon then return false, nil, nil, nil end
  local storage = Storage.ensure(session)
  local Flags = require("src.core.game3.scripting.flags")
  local Queries = require("src.core.game3.scripting.natives_queries")
  local store = script_store(session)
  Queries.setPCBoxToSendMon(Flags.getVar(store, nil, VAR_PC_BOX_TO_SEND_MON))
  local intended = tonumber(Queries.pcBoxToSendMon) or 0

  Storage.fullHealMon(mon)
  local bId, slot = Storage.findOpenSlot(storage)
  if not bId or not slot then
    return false, nil, nil, intended
  end
  storage.boxes[bId].mons[slot] = mon
  if (bId - 1) ~= intended then
    Flags.setFlag(store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
  end
  Flags.setVar(store, nil, VAR_PC_BOX_TO_SEND_MON, bId - 1)
  session.monBoxId = bId - 1
  session.monBoxPos = slot - 1
  return true, bId, slot, intended
end

local function box_name(storage, zeroBased)
  local box = Storage.getBox(storage, (tonumber(zeroBased) or 0) + 1)
  return (box and box.name) or ""
end

-- pokefirered/src/field_specials.c:1985
local function should_show_box_was_full()
  local Queries = require("src.core.game3.scripting.natives_queries")
  local Std = require("src.core.game3.scripting.stdscripts")
  local handler = Queries.HANDLERS and Queries.HANDLERS[Std.SPECIAL.ShouldShowBoxWasFullMessage]
  if not handler then return false end
  local _, v = handler(nil)
  return (tonumber(v) or 0) ~= 0
end

-- pokefirered/src/field_specials.c:1995
function Storage.isDestinationBoxFull(session)
  local storage = Storage.ensure(session)
  local Flags = require("src.core.game3.scripting.flags")
  local Queries = require("src.core.game3.scripting.natives_queries")
  local store = script_store(session)
  Queries.setPCBoxToSendMon(Flags.getVar(store, nil, VAR_PC_BOX_TO_SEND_MON))
  local bId = Storage.findOpenSlot(storage)
  if not bId then return false end
  if (bId - 1) ~= (tonumber(Queries.pcBoxToSendMon) or 0) then
    Flags.setFlag(store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
  end
  Flags.setVar(store, nil, VAR_PC_BOX_TO_SEND_MON, bId - 1)
  return should_show_box_was_full()
end

-- pokefirered/src/battle_script_commands.c:9617
function Storage.pcTransferMessage(session, name, boxWasFull)
  local storage = Storage.ensure(session)
  local Flags = require("src.core.game3.scripting.flags")
  local Queries = require("src.core.game3.scripting.natives_queries")
  local store = script_store(session)
  name = tostring(name or "")
  local sent = box_name(storage, Flags.getVar(store, nil, VAR_PC_BOX_TO_SEND_MON))
  local shown = boxWasFull
  if shown == nil then shown = should_show_box_was_full() end
  local bills = Flags.getFlag(store, nil, FLAG_SYS_NOT_SOMEONES_PC) and true or false
  if not shown then
    -- pokefirered/data/text/pc_transfer.inc:1
    if bills then
      return Strings("%s was transferred to\nBILL'S PC.\fIt was placed in \nBOX “%s.”", name, sent)
    end
    return Strings("%s was transferred to\nSomeone's PC.\fIt was placed in \nBOX “%s.”", name, sent)
  end
  -- pokefirered/data/text/pc_transfer.inc:13
  local full = box_name(storage, Queries.pcBoxToSendMon)
  if bills then
    return Strings("BOX “%s” on\nBILL'S PC was full.\f%s was transferred to\nBOX “%s.”",
      full, name, sent)
  end
  return Strings("BOX “%s” on\nSomeone's PC was full.\f%s was transferred to\nBOX “%s.”",
    full, name, sent)
end

--- Automatic Spillover Capture Storage: Stores a caught Pokémon across 14 boxes.
function Storage.depositCaught(session, mon)
  if not session or not mon then return false, "invalid_mon" end
  local ok, bId, slot, intended = Storage.sendMonToPC(session, mon)
  if not ok then
    return false, "storage_full"
  end
  return true, bId, slot, intended
end

--- Player PC Item Storage (50 unique items capacity).
function Storage.depositItem(session, bagPocket, bagIdx, qty)
  if not session or not session.bag then return false, "no_bag" end
  local storage = Storage.ensure(session)
  qty = math.max(1, math.floor(tonumber(qty) or 1))

  local items = Bag.listPocket(session.bag, bagPocket)
  local slot = items and items[bagIdx]
  if not slot or (tonumber(slot.qty) or 0) < qty then
    return false, "insufficient_bag_qty"
  end

  local itemId = slot.id
  -- Check if item already exists in PC items
  local foundIdx = nil
  for i, entry in ipairs(storage.items) do
    if entry.id == itemId then
      foundIdx = i
      break
    end
  end

  if foundIdx then
    local curQty = storage.items[foundIdx].qty or 0
    storage.items[foundIdx].qty = math.min(Storage.MAX_ITEM_QTY, curQty + qty)
  else
    if #storage.items >= Storage.PC_ITEMS_COUNT then
      return false, "pc_items_full"
    end
    storage.items[#storage.items + 1] = { id = itemId, qty = qty }
  end

  Bag.remove(session.bag, itemId, qty)
  require("src.core.game3.quest_log_recorder").event(session,"StoredItemInPC",
    {require("src.core.game3.items").displayName(itemId)})
  return true
end

--- Withdraw item from Player PC to Bag.
function Storage.withdrawItem(session, pcIdx, qty)
  if not session or not session.bag then return false, "no_bag" end
  local storage = Storage.ensure(session)
  qty = math.max(1, math.floor(tonumber(qty) or 1))

  local entry = storage.items[pcIdx]
  if not entry or (tonumber(entry.qty) or 0) < qty then
    return false, "insufficient_pc_qty"
  end

  if not Bag.canAdd(session.bag, entry.id, qty) then
    return false, "bag_full"
  end

  local ok = Bag.add(session.bag, entry.id, qty)
  if not ok then return false, "bag_full" end

  require("src.core.game3.quest_log_recorder").event(session,"WithdrewItemFromPC",
    {require("src.core.game3.items").displayName(entry.id)})
  entry.qty = entry.qty - qty
  if entry.qty <= 0 then
    table.remove(storage.items, pcIdx)
  end
  return true
end

--- Toss item from Player PC.
function Storage.tossItem(session, pcIdx, qty)
  local storage = Storage.ensure(session)
  qty = math.max(1, math.floor(tonumber(qty) or 1))
  local entry = storage.items[pcIdx]
  if not entry or (tonumber(entry.qty) or 0) < qty then
    return false, "insufficient_pc_qty"
  end
  entry.qty = entry.qty - qty
  if entry.qty <= 0 then
    table.remove(storage.items, pcIdx)
  end
  return true
end

--- Move Items Mode: Detach held item from Pokémon and send to Bag with Bag-Full pre-check.
function Storage.detachHeldItem(session, mon)
  if not session or not session.bag or not mon then return false, "invalid_args" end
  local itemId = mon.heldItem or mon.item
  if not itemId or itemId == 0 then return false, "no_item" end

  if not Bag.canAdd(session.bag, itemId, 1) then
    return false, "bag_full"
  end

  local ok = Bag.add(session.bag, itemId, 1)
  if not ok then return false, "bag_full" end

  mon.heldItem = nil
  mon.item = nil
  return true, itemId
end

--- Sparse Serialization: Encodes only non-empty boxes and slots for minimal disk footprint.
function Storage.serialize(storage)
  if not storage then return nil end
  local data = {
    currentBox = storage.currentBox or 1,
    boxes = {},
    items = {},
  }
  -- Only serialize non-empty items
  for _, item in ipairs(storage.items or {}) do
    if item and item.id and (tonumber(item.qty) or 0) > 0 then
      data.items[#data.items + 1] = { id = item.id, qty = item.qty }
    end
  end
  -- Only serialize non-empty boxes & slots
  for b = 1, Storage.TOTAL_BOXES_COUNT do
    local box = storage.boxes and storage.boxes[b]
    if box then
      local boxData = {
        name = box.name,
        wallpaper = box.wallpaper,
        mons = {},
      }
      local hasMon = false
      for s = 1, Storage.IN_BOX_COUNT do
        if box.mons[s] ~= nil then
          boxData.mons[s] = box.mons[s]
          hasMon = true
        end
      end
      if hasMon or box.name ~= string.format("BOX %d", b) or box.wallpaper ~= (((b - 1) % 16) + 1) then
        data.boxes[b] = boxData
      end
    end
  end
  return data
end

--- Sparse Deserialization: Restores full 14-box structure from sparse save data.
function Storage.deserialize(data)
  local storage = Storage.new()
  if not data then return storage end
  storage.currentBox = tonumber(data.currentBox) or 1
  if data.items ~= nil then
    storage.items = {}
    for _, item in ipairs(data.items) do
      if item and item.id and (tonumber(item.qty) or 0) > 0 then
        storage.items[#storage.items + 1] = { id = item.id, qty = item.qty }
      end
    end
  end
  for b = 1, Storage.TOTAL_BOXES_COUNT do
    local bData = data.boxes and data.boxes[b]
    if bData then
      if bData.name then storage.boxes[b].name = tostring(bData.name) end
      if bData.wallpaper then storage.boxes[b].wallpaper = tonumber(bData.wallpaper) or 1 end
      if type(bData.mons) == "table" then
        for s = 1, Storage.IN_BOX_COUNT do
          if bData.mons[s] ~= nil then
            storage.boxes[b].mons[s] = bData.mons[s]
          end
        end
      end
    end
  end
  return storage
end

function Storage.restore(data, legacyPc, pcItems)
  local hasData = type(data) == "table"
  local hasPc = type(legacyPc) == "table"
  local hasPcItems = type(pcItems) == "table"
  if not hasData and not hasPc and not hasPcItems then
    return Storage.new()
  end
  local storage = Storage.deserialize(hasData and data or nil)
  if hasPc then
    if not hasData then
      storage.items = {}
      for _, it in ipairs(legacyPc.items or {}) do
        local id = type(it) == "table" and tonumber(it.id or it.itemId)
        local qty = type(it) == "table" and (tonumber(it.qty or it.quantity) or 0) or 0
        if id and qty > 0 and #storage.items < Storage.PC_ITEMS_COUNT then
          storage.items[#storage.items + 1] = { id = id, qty = math.min(Storage.MAX_ITEM_QTY, qty) }
        end
      end
    end
    if Storage.countTotalMons(storage) == 0 then
      for _, mon in ipairs(legacyPc.mons or {}) do
        local b, s = Storage.findOpenSlot(storage)
        if not b then break end
        storage.boxes[b].mons[s] = mon
      end
    end
  elseif not hasData and hasPcItems then
    storage.items = {}
    for k, v in pairs(pcItems) do
      local id = nil
      local qty = 0
      if type(k) == "number" and type(v) == "table" then
        id = tonumber(v.id or v.itemId)
        qty = tonumber(v.qty or v.quantity or v.count) or 0
      elseif type(k) == "string" and type(v) == "number" then
        id = ItemsData.toNumericId(k)
        qty = v
      elseif type(k) == "number" and type(v) == "number" then
        id = k
        qty = v
      end
      if id and qty > 0 and #storage.items < Storage.PC_ITEMS_COUNT then
        storage.items[#storage.items + 1] = { id = id, qty = math.min(Storage.MAX_ITEM_QTY, qty) }
      end
    end
  end
  return storage
end

return Storage
