-- Gen 2 storage system: 14 boxes of 20, the party<->box moves the PC does,
-- and the rules that stop a deposit or withdrawal from breaking a save.
--   luajit tests/gen2_boxes_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 boxes")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Boxes = require("src.core.gen2.Boxes")
local TEXT = require("tests.fixture_data.gen2_rom_text_s7_e")
local DATA = { text = TEXT }

eq(Boxes.NUM_BOXES, 14, "14 boxes")
eq(Boxes.MONS_PER_BOX, 20, "20 per box")
eq(Boxes.PARTY_SIZE, 6, "6 party slots")

-- SetDefaultBoxNames
eq(Boxes.defaultName(1, DATA), TEXT["SetDefaultBoxNames.Box"] .. "1",
  "first default box name")
eq(Boxes.defaultName(14, DATA), TEXT["SetDefaultBoxNames.Box"] .. "14",
  "last default box name")
check(not pcall(Boxes.defaultName, 1, { text = {} }),
  "a cache without SetDefaultBoxNames.Box is an error")

local function mon(species, hp)
  return { species = species, name = species, level = 5,
    hp = hp == nil and 20 or hp, maxHp = 20 }
end

local function newSave(party)
  return { party = party or {}, boxes = {}, boxNames = {}, currentBox = 1 }
end

-- ---- names ----------------------------------------------------------------
local save = newSave()
eq(Boxes.name(save, 3, DATA), "BOX3", "unnamed box falls back to the default")
check(Boxes.rename(save, 3, "SAFARI"), "rename accepted")
eq(Boxes.name(save, 3, DATA), "SAFARI", "renamed box keeps its name")
check(not Boxes.rename(save, 15, "NOPE"), "box 15 does not exist")
check(not Boxes.rename(save, 0, "NOPE"), "box 0 does not exist")

-- ---- .CheckCanUsePC -------------------------------------------------------
local cantUse, cantUseReason = Boxes.canUsePc(newSave())
check(not cantUse, "an empty party cannot open the PC")
eq(cantUseReason, "_PCGottaHavePokemonText", "with .CheckCanUsePC's text")
eq(Boxes.reasonText(cantUseReason, DATA), "You gotta have\nPOKéMON to call!",
  "read from the cache, prompt marker dropped")
check(Boxes.canUsePc(newSave({ mon("TOTODILE") })), "a party of one can")

-- ---- deposit --------------------------------------------------------------
save = newSave({ mon("CYNDAQUIL"), mon("PIDGEY") })
local ok, moved = Boxes.deposit(save, 2, 1)
check(ok, "depositing the second mon works")
eq(moved.species, "PIDGEY", "the right mon moved")
eq(#save.party, 1, "party shrank")
eq(Boxes.count(save, 1), 1, "box 1 holds it")
eq(Boxes.box(save, 1)[1].species, "PIDGEY", "and it is the same mon")

-- The last healthy mon stays put, or the next step is a whiteout.
local blocked, reason = Boxes.canDeposit(save, 1, 1)
check(not blocked, "the last healthy party mon cannot be deposited")
eq(reason, "PCString_NoMoreUsablePKMN", "and the refusal says why")
eq(Boxes.reasonText(reason, DATA), TEXT.PCString_NoMoreUsablePKMN,
  "in the cache's own words")

-- A fainted mon is not what keeps you alive, so the healthy one is still last.
save = newSave({ mon("CYNDAQUIL"), mon("PIDGEY", 0) })
check(not Boxes.canDeposit(save, 1, 1),
  "a fainted second mon does not free the healthy one")
check(Boxes.deposit(save, 2, 1), "the fainted one can be deposited")

-- A full box refuses.
save = newSave({ mon("CYNDAQUIL"), mon("PIDGEY") })
for _ = 1, Boxes.MONS_PER_BOX do
  local box = Boxes.box(save, 1)
  box[#box + 1] = mon("RATTATA")
end
check(Boxes.isFull(save, 1), "box 1 is full at 20")
local full, fullReason = Boxes.canDeposit(save, 2, 1)
check(not full, "a full box refuses a deposit")
eq(fullReason, "PCString_BoxFull", "and says so")
-- ...but the next box has room.
check(Boxes.deposit(save, 2, 2), "box 2 takes it instead")
eq(Boxes.count(save, 2), 1, "box 2 now holds one")

-- ---- withdraw -------------------------------------------------------------
save = newSave({ mon("CYNDAQUIL") })
local box = Boxes.box(save, 1)
box[1] = mon("GEODUDE")
box[2] = mon("ZUBAT")
local took
ok, took = Boxes.withdraw(save, 1, 2)
check(ok, "withdrawing the second boxed mon works")
eq(took.species, "ZUBAT", "the right mon came out")
eq(#save.party, 2, "party grew")
eq(Boxes.count(save, 1), 1, "the box shrank")

-- A full party refuses.
save = newSave({ mon("A"), mon("B"), mon("C"), mon("D"), mon("E"), mon("F") })
Boxes.box(save, 1)[1] = mon("GEODUDE")
local noRoom, noRoomReason = Boxes.canWithdraw(save, 1, 1)
check(not noRoom, "a full party cannot withdraw")
eq(noRoomReason, "PCString_PartyFull", "and says so")
eq(Boxes.reasonText(noRoomReason, DATA), TEXT.PCString_PartyFull,
  "PCString_PartyFull out of the cache")
check(not pcall(Boxes.reasonText, noRoomReason, { text = {} }),
  "a cache without the label is an error")
check(not Boxes.canWithdraw(newSave({ mon("A") }), 1, 4),
  "an empty slot has nothing to withdraw")

-- ---- release / move -------------------------------------------------------
save = newSave({ mon("A") })
Boxes.box(save, 1)[1] = mon("GEODUDE")
ok, took = Boxes.release(save, 1, 1)
check(ok, "release takes the mon out of the box")
eq(took.species, "GEODUDE", "and hands it back")
eq(Boxes.count(save, 1), 0, "the box is empty")
check(not Boxes.release(save, 1, 1), "releasing an empty slot fails")

save = newSave({ mon("A") })
Boxes.box(save, 1)[1] = mon("ONIX")
check(not Boxes.move(save, 1, 1, 1), "moving a mon to its own box is refused")
ok = Boxes.move(save, 1, 1, 5)
check(ok, "moving to another box works")
eq(Boxes.count(save, 1), 0, "source box emptied")
eq(Boxes.count(save, 5), 1, "target box filled")
eq(Boxes.box(save, 5)[1].species, "ONIX", "with the same mon")

-- ---- current box ----------------------------------------------------------
save = newSave({ mon("A") })
check(Boxes.setCurrent(save, 7), "box 7 can be made current")
eq(save.currentBox, 7, "currentBox followed")
check(not Boxes.setCurrent(save, 0), "box 0 cannot")
check(not Boxes.setCurrent(save, 15), "box 15 cannot")
eq(save.currentBox, 7, "a rejected change leaves it alone")
-- Boxes.box with no index reads the current one.
Boxes.box(save)[1] = mon("SLOWPOKE")
eq(Boxes.count(save, 7), 1, "the default index is the current box")

S.finish()
