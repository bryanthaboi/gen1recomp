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

local function checkEq(got, expected, msg)
  if got == expected then
    print(string.format("[ok] %s (got %s)", msg, tostring(got)))
  else
    failed = failed + 1
    print(string.format("[FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(got)))
  end
end

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")
local Schema = require("src.core.game3.save_schema_firered")

local A = { log = function() end }

print("=== 1. all 22 specials of the wave are declared and bound ===")
local WANT = {
  "ChooseMonForWirelessMinigame", "IsPokemonJumpSpeciesInParty",
  "ShowPokemonJumpRecords", "ShowDodrioBerryPickingRecords",
  "DisplayBerryPowderVendorMenu", "RemoveBerryPowderVendorMenu",
  "Script_HasEnoughBerryPowder", "Script_TakeBerryPowder",
  "PrintPlayerBerryPowderAmount", "ShowBerryCrushRankings",
  "DoCredits", "ShowDiploma", "DoSSAnneDepartureCutscene",
  "DoPokemonLeagueLightingEffect", "LoopWingFlapSound",
  "OpenMuseumFossilPic", "CloseMuseumFossilPic",
  "BufferEReaderTrainerName", "BufferEReaderTrainerGreeting",
  "SetEReaderTrainerGfxId",
  "Script_FacePlayer", "Script_ClearHeldMovement",
}
for _, name in ipairs(WANT) do
  local id = Std.SPECIAL[name]
  check(id ~= nil, name .. " is declared in Std.SPECIAL")
  if id then
    check(Natives.ALLOW["special:" .. id] ~= nil,
      string.format("%s (0x%X) has a handler", name, id))
  end
end

print("=== 2. berry powder: enough / take bookkeeping ===")
local session = Schema.newGame({ name = "RED" })
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
local ctx = {
  session = session,
  flags = session.flags,
  vars = session.vars,
  stringVars = session.stringVars,
  specialVars = session.specialVars,
}

session.berryPowder = 100
Flags.setVar(nil, ctx, 0x8004, 60)
local _, v1 = Natives.special(ctx, Std.SPECIAL.Script_HasEnoughBerryPowder, A)
checkEq(v1, 1, "60 <= 100 answers TRUE")
checkEq(Flags.getVar(nil, ctx, 0x800D), 1, "VAR_RESULT mirrors the answer")
Flags.setVar(nil, ctx, 0x8004, 120)
local _, v2 = Natives.special(ctx, Std.SPECIAL.Script_HasEnoughBerryPowder, A)
checkEq(v2, 0, "120 > 100 answers FALSE")

Flags.setVar(nil, ctx, 0x8004, 60)
local _, t1 = Natives.special(ctx, Std.SPECIAL.Script_TakeBerryPowder, A)
checkEq(t1, 1, "taking 60 succeeds")
checkEq(session.berryPowder, 40, "100 - 60 = 40")
Flags.setVar(nil, ctx, 0x8004, 50)
local _, t2 = Natives.special(ctx, Std.SPECIAL.Script_TakeBerryPowder, A)
checkEq(t2, 0, "cannot take 50 from 40")
checkEq(session.berryPowder, 40, "balance unchanged after a refused take")

print("=== 3. vendor window pair records open/close ===")
local yDisp = Natives.special(ctx, Std.SPECIAL.DisplayBerryPowderVendorMenu, A)
checkEq(yDisp, false, "Display does not yield")
check(ctx.berryPowderVendorOpen == true, "vendor window marked open")
local yPrint = Natives.special(ctx, Std.SPECIAL.PrintPlayerBerryPowderAmount, A)
checkEq(yPrint, false, "Print is a bound no-op")
Natives.special(ctx, Std.SPECIAL.RemoveBerryPowderVendorMenu, A)
check(ctx.berryPowderVendorOpen ~= true, "Remove clears the vendor window state")

print("=== 4. e-Reader fallbacks ===")
Natives.special(ctx, Std.SPECIAL.SetEReaderTrainerGfxId, A)
checkEq(Flags.getVar(session, ctx, 0x4010), 18,
  "VAR_OBJ_GFX_ID_0 = OBJ_EVENT_GFX_YOUNGSTER (18)")

-- scripts.inc:88, scripts.inc:18-19
Natives.special(ctx, Std.SPECIAL.BufferEReaderTrainerName, A)
check(type(ctx.stringVars[1]) == "string" and #ctx.stringVars[1] > 0,
  "STR_VAR_1 holds a fallback name with no card")
Natives.special(ctx, Std.SPECIAL.BufferEReaderTrainerGreeting, A)
check(type(ctx.stringVars[4]) == "string" and #ctx.stringVars[4] > 0,
  "STR_VAR_4 holds a fallback greeting with no card")

session.ereaderTrainer = { name = "ALPHA", party = { { species = 141 } } }
Natives.special(ctx, Std.SPECIAL.BufferEReaderTrainerName, A)
checkEq(ctx.stringVars[1], "ALPHA", "STR_VAR_1 = the visiting trainer's name")
Natives.special(ctx, Std.SPECIAL.BufferEReaderTrainerGreeting, A)
check(ctx.stringVars[4] ~= nil and #ctx.stringVars[4] > 0,
  "greeting buffered from the record too")
session.ereaderTrainer = nil

print("=== 5. cable-club object specials ===")
local faced
Flags.setVar(nil, ctx, 0x800F, 3)
local yFace = Natives.special(ctx, Std.SPECIAL.Script_FacePlayer, {
  log = A.log,
  facePlayer = function(lid) faced = lid end,
})
checkEq(yFace, false, "Script_FacePlayer does not yield")
checkEq(faced, 3, "the attendant turns toward VAR_LAST_TALKED = 3")
local yClear = Natives.special(ctx, Std.SPECIAL.Script_ClearHeldMovement, A)
checkEq(yClear, false, "Script_ClearHeldMovement is a bound no-op")

print("=== 6. wireless fallbacks answer instead of staying unbound ===")
Natives.special(ctx, Std.SPECIAL.IsPokemonJumpSpeciesInParty, A)
checkEq(Flags.getVar(nil, ctx, 0x800D), 0,
  "no Pokemon Jump minigame: FALSE routes to NoEligiblePkmn")
Flags.setVar(nil, ctx, 0x8004, 0)
local yWireless = Natives.special(ctx, Std.SPECIAL.ChooseMonForWirelessMinigame, A)
checkEq(yWireless, false, "the wireless picker does not yield")
check((Flags.getVar(nil, ctx, 0x8004) or 0) >= 6,
  "VAR_0x8004 >= PARTY_SIZE takes AbortMinigame")
for _, name in ipairs({
  "ShowPokemonJumpRecords", "ShowDodrioBerryPickingRecords",
  "ShowBerryCrushRankings", "DoCredits", "ShowDiploma",
  "DoPokemonLeagueLightingEffect",
}) do
  checkEq(Natives.special(ctx, Std.SPECIAL[name], A), false,
    name .. " completes its waitstate")
end

print("=== 7. museum fossil pic: state only, dex flags untouched ===")
local store = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = store }
Flags.setVar(nil, ctx, 0x8004, 141)
Flags.setVar(nil, ctx, 0x8005, 10)
Flags.setVar(nil, ctx, 0x8006, 3)
local yOpen = Natives.special(ctx, Std.SPECIAL.OpenMuseumFossilPic, A)
checkEq(yOpen, false, "OpenMuseumFossilPic does not yield")
check(ctx.museumFossilPic and ctx.museumFossilPic.species == 141,
  "fossil pic opens for SPECIES_KABUTOPS at (10, 3)")
check(Flags.getFlag(store, nil, 0x829) ~= true,
  "FLAG_SYS_POKEDEX_GET stays clear")
Natives.special(ctx, Std.SPECIAL.CloseMuseumFossilPic, A)
check(ctx.museumFossilPic == nil, "CloseMuseumFossilPic clears the pic")
Flags.setVar(nil, ctx, 0x8004, 25)
Natives.special(ctx, Std.SPECIAL.OpenMuseumFossilPic, A)
check(ctx.museumFossilPic == nil,
  "a non-fossil species leaves the pic closed (pret returns FALSE)")

print("=== 8. scene audio: wing flaps and the SS Anne horn ===")
local horn
Natives.special(ctx, Std.SPECIAL.DoSSAnneDepartureCutscene, {
  log = A.log,
  playSe = function(id) horn = id end,
})
checkEq(horn, 249, "SS Anne departure toots SE_SS_ANNE_HORN (249)")

local flaps = {}
local function capture(id) flaps[#flaps + 1] = id end
Flags.setVar(nil, ctx, 0x8004, 2)
Flags.setVar(nil, ctx, 0x8005, 1)
Natives.special(ctx, Std.SPECIAL.LoopWingFlapSound, { log = A.log, playSe = capture })
checkEq(flaps[1], 150, "first flap plays SE_M_WING_ATTACK (150) immediately")
local okT, Task = pcall(require, "src.core.game3.task")
if okT and Task then
  for _ = 1, 4 do Task.update(1 / 60) end
  -- field_specials.c:2553
  checkEq(#flaps, 2, "loops=2 plays exactly 2 total flaps (pret parity)")
  Task.clear()
else
  check(false, "src.core.game3.task is loadable")
end

print(string.format("\nTotal: %d checks, %d failed", 0, failed))
if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
