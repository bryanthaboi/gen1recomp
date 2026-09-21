#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Storage = require("src.core.game3.storage")
local Party = require("src.core.game3.party")
local Flags = require("src.core.game3.scripting.flags")
local Queries = require("src.core.game3.scripting.natives_queries")
local Std = require("src.core.game3.scripting.stdscripts")

local VAR_PC_BOX_TO_SEND_MON = 0x4037
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843

local function new_session()
  local session = {
    party = {},
    store = Flags.newStore(),
    dex = { seen = {}, owned = {} },
  }
  Storage.ensure(session)
  return session
end

local function fill_box(session, boxId, count)
  local box = session.storage.boxes[boxId]
  for s = 1, count do
    box.mons[s] = { species = 19, speciesId = 19, level = 3, hp = 12, maxHp = 12 }
  end
end

local function mon()
  return { species = 16, speciesId = 16, level = 5, hp = 20, maxHp = 20 }
end

print("[test] 1. a send into the current box writes the 0-based box id")
local s1 = new_session()
s1.storage.currentBox = 1
local ok, bId, slot = Storage.sendMonToPC(s1, mon())
check(ok, "sendMonToPC succeeded")
eq(bId, 1, "landed in box 1 (1-based)")
eq(slot, 1, "in slot 1")
eq(Flags.getVar(s1.store, nil, VAR_PC_BOX_TO_SEND_MON), 0,
  "VAR_PC_BOX_TO_SEND_MON holds the cart's 0-based id")

print("[test] 2. box 3 writes 2, not 3")
local s2 = new_session()
s2.storage.currentBox = 3
local ok2, b2 = Storage.sendMonToPC(s2, mon())
check(ok2, "sendMonToPC succeeded")
eq(b2, 3, "landed in box 3 (1-based)")
eq(Flags.getVar(s2.store, nil, VAR_PC_BOX_TO_SEND_MON), 2, "the var holds 2")

print("[test] 3. the intended box is read back before the search")
local s3 = new_session()
s3.storage.currentBox = 1
Flags.setVar(s3.store, nil, VAR_PC_BOX_TO_SEND_MON, 7)
local ok3, b3, _, intended = Storage.sendMonToPC(s3, mon())
check(ok3, "sendMonToPC succeeded")
eq(intended, 7, "GetPCBoxToSendMon is the pre-search value")
eq(Queries.pcBoxToSendMon, 7, "and it is left on the Queries module for the reader")
eq(b3, 1, "the mon still went to the current box")
eq(Flags.getVar(s3.store, nil, VAR_PC_BOX_TO_SEND_MON), 0, "the var was updated to 0")

print("[test] 4. the flag is cleared when the box changed")
local s4 = new_session()
s4.storage.currentBox = 1
Flags.setVar(s4.store, nil, VAR_PC_BOX_TO_SEND_MON, 5)
Flags.setFlag(s4.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
Storage.sendMonToPC(s4, mon())
eq(Flags.getFlag(s4.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE), false,
  "FLAG_SHOWN_BOX_WAS_FULL_MESSAGE was cleared on the box change")

print("[test] 5. the flag survives when the box did not change")
local s5 = new_session()
s5.storage.currentBox = 1
Flags.setVar(s5.store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
Flags.setFlag(s5.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
Storage.sendMonToPC(s5, mon())
eq(Flags.getFlag(s5.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE), true,
  "the flag is untouched when the box is the same")

print("[test] 6. spillover to the next box updates the var to that box")
local s6 = new_session()
s6.storage.currentBox = 2
fill_box(s6, 2, Storage.IN_BOX_COUNT)
Flags.setVar(s6.store, nil, VAR_PC_BOX_TO_SEND_MON, 1)
Flags.setFlag(s6.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
local ok6, b6, sl6, intended6 = Storage.sendMonToPC(s6, mon())
check(ok6, "sendMonToPC spilled over")
eq(b6, 3, "the mon went to box 3")
eq(sl6, 1, "slot 1 of box 3")
eq(intended6, 1, "the intended box was still box 2 (0-based 1)")
eq(Flags.getVar(s6.store, nil, VAR_PC_BOX_TO_SEND_MON), 2, "the var now holds 2")
eq(Flags.getFlag(s6.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE), false,
  "the flag was cleared because the box changed")

print("[test] 7. gSpecialVar_MonBoxId / MonBoxPos are 0-based")
eq(s6.monBoxId, 2, "session.monBoxId")
eq(s6.monBoxPos, 0, "session.monBoxPos")

print("[test] 8. the ShouldShowBoxWasFullMessage reader agrees with the writer")
local Runtime = require("src.core.game3.runtime")
local prevSession = Runtime.getSession and Runtime.getSession() or nil
local s8 = new_session()
s8.storage.currentBox = 2
fill_box(s8, 2, Storage.IN_BOX_COUNT)
Flags.setVar(s8.store, nil, VAR_PC_BOX_TO_SEND_MON, 1)
Runtime.session = s8
local ctx8 = { specialVars = {} }
Storage.sendMonToPC(s8, mon())
local handler = Queries.HANDLERS and Queries.HANDLERS[Std.SPECIAL.ShouldShowBoxWasFullMessage]
if handler then
  local _, v = handler(ctx8)
  eq(v, 1, "the box was full, so the message should show")
  local _, v2 = handler(ctx8)
  eq(v2, 0, "and only once")
else
  check(false, "Queries exposes the ShouldShowBoxWasFullMessage handler")
end
local getBox = Queries.HANDLERS and Queries.HANDLERS[Std.SPECIAL.GetPCBoxToSendMon]
local _, boxVal = getBox(ctx8)
eq(boxVal, 1, "GetPCBoxToSendMon still reports the box it was going to")
Runtime.session = prevSession

print("[test] 9. depositCaught routes through sendMonToPC")
local s9 = new_session()
s9.storage.currentBox = 4
local okD, bD, slD = Storage.depositCaught(s9, mon())
check(okD, "depositCaught succeeded")
eq(bD, 4, "box 4")
eq(slD, 1, "slot 1")
eq(Flags.getVar(s9.store, nil, VAR_PC_BOX_TO_SEND_MON), 3, "the var holds 3")

print("[test] 10. a completely full PC gives back the intended box and no write")
local s10 = new_session()
s10.storage.currentBox = 1
for b = 1, Storage.TOTAL_BOXES_COUNT do fill_box(s10, b, Storage.IN_BOX_COUNT) end
Flags.setVar(s10.store, nil, VAR_PC_BOX_TO_SEND_MON, 9)
local okF, bF, slF, intF = Storage.sendMonToPC(s10, mon())
check(okF == false, "sendMonToPC refused")
check(bF == nil and slF == nil, "no box or slot came back")
eq(intF, 9, "the intended box is reported")
eq(Flags.getVar(s10.store, nil, VAR_PC_BOX_TO_SEND_MON), 9, "the var was not moved")
local okDC, reason = Storage.depositCaught(s10, mon())
check(okDC == false and reason == "storage_full", "depositCaught reports storage_full")

print("[test] 11. Party.giveMonToPlayer overflows into the PC and returns MON_GIVEN_TO_PC")
local s11 = new_session()
s11.storage.currentBox = 1
for i = 1, 6 do
  local codeG = Party.giveMonToPlayer(s11, 1, 5)
  eq(codeG, Party.MON_GIVEN_TO_PARTY, "slot " .. i .. " is MON_GIVEN_TO_PARTY")
end
eq(#s11.party, 6, "the party is full")
local codeP, monP, boxP, slotP = Party.giveMonToPlayer(s11, 25, 10)
eq(codeP, Party.MON_GIVEN_TO_PC, "it is MON_GIVEN_TO_PC")
eq(#s11.party, 6, "the party did not grow")
eq(boxP, 1, "it landed in box 1")
eq(slotP, 1, "slot 1")
check(s11.storage.boxes[1].mons[1] == monP, "the returned mon is the boxed mon")
eq(tonumber(monP.species), 25, "and it is the right species")
eq(s11.dex.owned[25], true, "the dex was still marked owned")
eq(Flags.getVar(s11.store, nil, VAR_PC_BOX_TO_SEND_MON), 0, "the var was written")

print("[test] 12. MON_CANT_GIVE when party and PC are both full")
local s12 = new_session()
for i = 1, 6 do Party.giveMonToPlayer(s12, 1, 5) end
for b = 1, Storage.TOTAL_BOXES_COUNT do fill_box(s12, b, Storage.IN_BOX_COUNT) end
local codeC, monC = Party.giveMonToPlayer(s12, 25, 10)
eq(codeC, Party.MON_CANT_GIVE, "the code is MON_CANT_GIVE")
check(monC == nil, "no mon came back")
check(s12.dex.owned[25] == nil, "the dex was not marked for a mon that was never given")

print("[test] 13. giveEggToPlayer marks the egg wherever it landed")
local s13 = new_session()
for i = 1, 6 do Party.giveMonToPlayer(s13, 1, 5) end
local codeE, egg = Party.giveEggToPlayer(s13, 4)
eq(codeE, Party.MON_GIVEN_TO_PC, "the egg went to the PC")
check(egg ~= nil and egg.isEgg == true, "the boxed egg is flagged isEgg")
check(s13.storage.boxes[s13.storage.currentBox].mons[1] == egg,
  "and it is the mon sitting in the box, not a party mon")
check(s13.party[6].isEgg ~= true, "the last party mon was not mislabelled as the egg")

print("[test] 14. a caller that cannot report MON_GIVEN_TO_PC keeps the mon out of the PC")
local s14 = new_session()
for i = 1, 6 do Party.giveMon(s14, 1, 5) end
eq(#s14.party, 6, "the party is full")
local ok14, code14, mon14 = Party.giveMon(s14, 25, 10)
check(ok14 == false, "the plain giveMon refused")
eq(code14, Party.MON_CANT_GIVE, "the code is MON_CANT_GIVE")
check(mon14 == nil, "no mon came back")
eq(Storage.countTotalMons(s14.storage), 0, "and nothing reached the PC")
check(s14.dex.owned[25] == nil, "the dex was not marked")
local okO, codeO, monO = Party.giveMon(s14, 25, 10, nil, { toPC = true })
check(okO, "the same call with toPC gives the mon")
eq(codeO, Party.MON_GIVEN_TO_PC, "and reports MON_GIVEN_TO_PC")
check(s14.storage.boxes[1].mons[1] == monO, "the mon is in box 1")

print("[test] 15. the PC transfer message picks pret's four strings")
local Runtime15 = require("src.core.game3.runtime")
local prev15 = Runtime15.getSession and Runtime15.getSession() or nil
local s15 = new_session()
s15.storage.currentBox = 1
Runtime15.session = s15
Party.giveMonToPlayer(s15, 25, 10)
local plain = Storage.pcTransferMessage(s15, "PIKACHU")
check(plain:find("PIKACHU was transferred to\nSomeone's PC.", 1, true) ~= nil,
  "someone's PC: " .. plain:gsub("\n", " "):gsub("\f", " | "))
check(plain:find("BOX “BOX 1.”", 1, true) ~= nil, "and it names the box it was placed in")
Flags.setFlag(s15.store, nil, 0x834, true)
local bills = Storage.pcTransferMessage(s15, "PIKACHU")
check(bills:find("BILL'S PC.", 1, true) ~= nil,
  "FLAG_SYS_NOT_SOMEONES_PC swaps in BILL'S PC")
Flags.setFlag(s15.store, nil, 0x834, false)

print("[test] 16. a spillover names the full box and the box it went to, once")
local s16 = new_session()
s16.storage.currentBox = 1
for _ = 1, 6 do Party.giveMon(s16, 1, 5) end
fill_box(s16, 1, Storage.IN_BOX_COUNT)
Runtime15.session = s16
Flags.setVar(s16.store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
Flags.setFlag(s16.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
local code16 = Party.giveMonToPlayer(s16, 25, 10)
eq(code16, Party.MON_GIVEN_TO_PC, "the mon spilled over")
local full16 = Storage.pcTransferMessage(s16, "PIKACHU")
check(full16:find("BOX “BOX 1” on\nSomeone's PC was full.", 1, true) ~= nil,
  "box was full: " .. full16:gsub("\n", " "):gsub("\f", " | "))
check(full16:find("PIKACHU was transferred to\nBOX “BOX 2.”", 1, true) ~= nil,
  "and it went to BOX 2")
local again16 = Storage.pcTransferMessage(s16, "PIKACHU")
check(again16:find("was full", 1, true) == nil,
  "the box-was-full line is only shown once: " .. again16:gsub("\n", " "):gsub("\f", " | "))
check(again16:find("PIKACHU was transferred to\nSomeone's PC.", 1, true) ~= nil,
  "the plain line follows")

print("[test] 17. IsDestinationBoxFull answers the naming screen")
local s17 = new_session()
s17.storage.currentBox = 1
for _ = 1, 6 do Party.giveMon(s17, 1, 5) end
fill_box(s17, 1, Storage.IN_BOX_COUNT)
Runtime15.session = s17
Flags.setVar(s17.store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
Flags.setFlag(s17.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)
Party.giveMonToPlayer(s17, 25, 10)
local battleLine = Storage.pcTransferMessage(s17, "PIKACHU")
check(battleLine:find("BOX “BOX 1” on", 1, true) ~= nil, "the battle line named the full box")
local full17 = Storage.isDestinationBoxFull(s17)
check(full17 == false, "the naming screen does not repeat it, the battle already showed it")
eq(Flags.getVar(s17.store, nil, VAR_PC_BOX_TO_SEND_MON), 1, "and the var still names BOX 2")
local named = Storage.pcTransferMessage(s17, "PIKACHU", full17)
check(named:find("PIKACHU was transferred to\nSomeone's PC.", 1, true) ~= nil,
  "so the naming screen prints the plain line: " .. named:gsub("\n", " "):gsub("\f", " | "))
Flags.setFlag(s17.store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
local forced = Storage.isDestinationBoxFull(s17)
check(forced == true, "with the flag clear it answers yes")
local quirk = Storage.pcTransferMessage(s17, "PIKACHU", forced)
check(quirk:find("BOX “BOX 2” on\nSomeone's PC was full.", 1, true) ~= nil,
  "and names the box it went to twice, as the cart does: "
  .. quirk:gsub("\n", " "):gsub("\f", " | "))
local s18 = new_session()
s18.storage.currentBox = 1
Runtime15.session = s18
check(Storage.isDestinationBoxFull(s18) == false, "an empty current box is never full")
Runtime15.session = prev15

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
