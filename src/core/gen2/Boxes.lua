-- Gen 2 storage system: 14 boxes of 20, the party<->box moves the PC does, and
-- the default BOX1..BOX14 names.
--
-- The save already carries `boxes`, `boxNames` and `currentBox`
-- (src/core/gen2/Save.lua); this is the logic that operates on them, kept out
-- of the UI so a deposit is testable without a screen.
--
-- Rules taken from engine/pokemon/bills_pc.asm:
--   * the PC cannot be opened with an empty party (.CheckCanUsePC)
--   * DEPOSIT refuses to send the last healthy party mon away, because a party
--     of nothing whites you out on the next step
--   * WITHDRAW refuses once the party is full
--   * a box holds MONS_PER_BOX and no more
--   * DEPOSIT refuses a mon holding MAIL, because sPartyMail has six slots and
--     a boxed mon has none of them (src/core/gen2/Mail.lua)

local Mail = require("src.core.gen2.Mail")
local Save = require("src.core.gen2.Save")

local Boxes = {}

Boxes.NUM_BOXES = Save.NUM_BOXES
Boxes.MONS_PER_BOX = Save.MONS_PER_BOX
Boxes.PARTY_SIZE = Save.PARTY_SIZE

-- SetDefaultBoxNames (engine/menus/intro_menu.asm): "BOX" then 1..14.
function Boxes.defaultName(index)
  return "BOX" .. tostring(index)
end

function Boxes.name(save, index)
  local names = save and save.boxNames
  local given = names and names[index]
  if type(given) == "string" and given ~= "" then return given end
  return Boxes.defaultName(index)
end

function Boxes.rename(save, index, name)
  if not save or not index then return false end
  if index < 1 or index > Boxes.NUM_BOXES then return false end
  save.boxNames = save.boxNames or {}
  save.boxNames[index] = name
  return true
end

-- The box's mon list, created on demand so a fresh save carries 14 empty
-- tables only once one is actually used.
function Boxes.box(save, index)
  if not save then return {} end
  index = index or save.currentBox or 1
  if index < 1 or index > Boxes.NUM_BOXES then return {} end
  save.boxes = save.boxes or {}
  save.boxes[index] = save.boxes[index] or {}
  return save.boxes[index]
end

function Boxes.count(save, index)
  return #Boxes.box(save, index)
end

function Boxes.isFull(save, index)
  return Boxes.count(save, index) >= Boxes.MONS_PER_BOX
end

function Boxes.setCurrent(save, index)
  if not save or index < 1 or index > Boxes.NUM_BOXES then return false end
  save.currentBox = index
  return true
end

-- How many party members could still fight.  DEPOSIT checks this, not the raw
-- party count: a party of one fainted mon plus one healthy one may not send
-- the healthy one to a box.
function Boxes.healthyCount(party)
  local n = 0
  for _, mon in ipairs(party or {}) do
    if (mon.hp or 0) > 0 then n = n + 1 end
  end
  return n
end

-- Returns true, or false plus a reason string the caller shows in a text box.
function Boxes.canDeposit(save, partyIndex, boxIndex)
  if not save then return false, "No save." end
  local mon = save.party and save.party[partyIndex]
  if not mon then return false, "There is no POKéMON there." end
  if Boxes.isFull(save, boxIndex) then
    return false, "The BOX is full."
  end
  if (mon.hp or 0) > 0 and Boxes.healthyCount(save.party) <= 1 then
    return false, "You can't deposit\nthe last POKéMON!"
  end
  -- BillsPC_CheckMon's .HasMail arm (engine/pokemon/bills_pc.asm), which reads
  -- the wBillsPC_MonHasMail byte PCMonInfo set while drawing the row.  It is
  -- checked AFTER the last-healthy rule and prints PCString_RemoveMail, which
  -- is one short line rather than a two-line refusal: a boxed mon's letter has
  -- nowhere to live, because sPartyMail is six structs keyed by party slot.
  if Mail.monHoldsMail(mon) then
    return false, "Remove MAIL."
  end
  return true
end

-- RestorePPOfDepositedPokemon (engine/pokemon/move_mon.asm:711-773): every
-- slot back to GetMaxPPOfMove, which already carries its own PP Up count.
function Boxes.restorePP(mon)
  for _, move in ipairs((mon and mon.moves) or {}) do
    if type(move) == "table" then move.pp = move.maxPp or move.pp end
  end
end

-- box_struct has no MON_STATUS and no MON_HP (macros/ram.asm:7-26), so
-- CalcTempmonStats refills a BOXMON from MAXHP (engine/pokemon/tempmon.asm:56-83).
function Boxes.enterBox(mon)
  if not mon then return mon end
  Boxes.restorePP(mon)
  mon.status = nil
  mon.statusTurns = nil
  mon.hp = mon.isEgg and 0 or (mon.maxHp or mon.hp)
  return mon
end

function Boxes.deposit(save, partyIndex, boxIndex)
  local ok, reason = Boxes.canDeposit(save, partyIndex, boxIndex)
  if not ok then return false, reason end
  local mon = table.remove(save.party, partyIndex)
  -- RemoveMonFromPartyOrBox's "Mail time!" tail: sPartyMail is keyed by SLOT,
  -- so every letter after the departing mon moves up one.  The mon leaving
  -- here never has mail of its own (canDeposit just refused that), but the
  -- ones behind it may.
  Mail.removeSlot(save, partyIndex)
  local box = Boxes.box(save, boxIndex)
  box[#box + 1] = mon
  -- SendGetMonIntoFromBox's PC_DEPOSIT arm ends in RestorePPOfDepositedPokemon
  -- (engine/pokemon/move_mon.asm:633-635, :696-700).
  Boxes.enterBox(mon)
  return true, mon
end

function Boxes.canWithdraw(save, boxIndex, slot)
  if not save then return false, "No save." end
  local box = Boxes.box(save, boxIndex)
  if not box[slot] then return false, "There is no POKéMON there." end
  if #(save.party or {}) >= Boxes.PARTY_SIZE then
    return false, "You can't take\nany more POKéMON."
  end
  return true
end

function Boxes.withdraw(save, boxIndex, slot)
  local ok, reason = Boxes.canWithdraw(save, boxIndex, slot)
  if not ok then return false, reason end
  local mon = table.remove(Boxes.box(save, boxIndex), slot)
  -- The `get mon into Party` arm alone heals: status cleared and MON_MAXHP
  -- copied over MON_HP, an egg's staying 0 (move_mon.asm:666-693).
  mon.status = nil
  mon.statusTurns = nil
  if mon.isEgg then
    mon.hp = 0
  else
    mon.hp = mon.maxHp or mon.hp
  end
  save.party = save.party or {}
  save.party[#save.party + 1] = mon
  return true, mon
end

-- RELEASE from a box.  The cart lets you release anything in storage; the
-- party's last-healthy rule does not apply because a boxed mon is never in it.
function Boxes.release(save, boxIndex, slot)
  local box = Boxes.box(save, boxIndex)
  if not box[slot] then return false, "There is no POKéMON there." end
  return true, table.remove(box, slot)
end

-- RELEASE off the DEPOSIT screen, whose list is the party: it is
-- RemoveMonFromPartyOrBox's REMOVE_PARTY arm (bills_pc.asm:204-207).
function Boxes.releaseFromParty(save, slot)
  local party = (save and save.party) or {}
  if not party[slot] then return false, "There is no POKéMON there." end
  local mon = table.remove(party, slot)
  Mail.removeSlot(save, slot)
  return true, mon
end

-- Move a boxed mon to another box (MOVE PKMN W/O MAIL's box-to-box case).
function Boxes.move(save, fromBox, slot, toBox)
  if fromBox == toBox then return false, "It's already there." end
  local source = Boxes.box(save, fromBox)
  if not source[slot] then return false, "There is no POKéMON there." end
  if Boxes.isFull(save, toBox) then return false, "The BOX is full." end
  local mon = table.remove(source, slot)
  local target = Boxes.box(save, toBox)
  target[#target + 1] = mon
  return true, mon
end

-- .CheckCanUsePC: "You'll need a POKéMON to call with."
function Boxes.canUsePc(save)
  if not (save and save.party and #save.party > 0) then
    return false, "You'll need a\nPOKéMON to call\nwith."
  end
  return true
end

return Boxes
