#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Ops = require("src.core.game3.scripting.ops_a")
local Dex = require("src.core.game3.dex")
local Storage = require("src.core.game3.storage")

local store = Flags.newStore()
local keyText = setmetatable({}, {
  __index = function(_, key) return require("src.core.game3.scripting.text_ir").fromAscii(key) end,
})
package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  ensureBundle = function() return { text = keyText } end,
}

local function newCtx()
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  return ctx
end

local function session(tbl)
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return tbl end,
    isActive = function() return true end,
  }
  return tbl
end

local a = { log = function() end }
local function exec(ctx, row)
  return Ops.dispatch({ ctx = ctx, store = store, adapters = a, setPc = function() end }, row)
end
local function specialvar(ctx, dest, id)
  exec(ctx, { op = "specialvar", [1] = dest, [2] = id })
  return Flags.getVar(store, ctx, dest)
end
local function getVar(ctx, id) return Flags.getVar(store, ctx, id) end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

local function newDex(caught)
  local dex = Dex.new()
  for _, sp in ipairs(caught or {}) do Dex.setCaught(dex, sp) end
  return dex
end

print("[test] 1. GetPokedexCount fills VAR_0x8005 (seen) and VAR_0x8006 (caught)")
local s = session({
  name = "RED",
  gender = 0,
  money = 3000,
  trainerId = 4242,
  party = {},
  bag = require("src.core.game3.bag").new(),
  dex = newDex({ 1, 4, 7, 10, 13, 16, 19, 21, 25, 29, 32 }),
  map = "FR_ROUTE_2_EAST_BUILDING",
  x = 4,
  y = 7,
})
Dex.setSeen(s.dex, 41)
Dex.setSeen(s.dex, 43)
local ctx = newCtx()
setVar(ctx, 0x8004, 0) -- pokefirered/data/maps/Route2_EastBuilding/scripts.inc:13
local nat = specialvar(ctx, 0x800D, Std.SPECIAL.GetPokedexCount)
check(getVar(ctx, 0x8005) == 13, "VAR_0x8005 = 13 seen (got " .. tostring(getVar(ctx, 0x8005)) .. ")")
check(getVar(ctx, 0x8006) == 11, "VAR_0x8006 = 11 caught (got " .. tostring(getVar(ctx, 0x8006)) .. ")")
check(nat == 0, "VAR_RESULT = IsNationalPokedexEnabled = FALSE (got " .. tostring(nat) .. ")")

-- pokefirered/data/maps/Route2_EastBuilding/scripts.inc:12
local function aideBranch(dexTable)
  s.dex = dexTable
  local c = newCtx()
  local jumped = nil
  local vm = { ctx = c, store = store, adapters = a,
    setPc = function(_, key) jumped = key end }
  Ops.dispatch(vm, { op = "setvar", var = 0x8004, value = 0 })
  Ops.dispatch(vm, { op = "specialvar", [1] = 0x800D, [2] = Std.SPECIAL.GetPokedexCount })
  Ops.dispatch(vm, { op = "compare_var_to_value", var = 0x8006, value = 10 })
  Ops.dispatch(vm, { op = "goto_if", cond = 0, target = "Aide_HaventCaughtEnough" })
  return jumped, Flags.getVar(store, c, 0x8006)
end

print("[test] 2. the Route 2 aide branch clears REQUIRED_SEEN_MONS with 11 caught")
local jumped, caught = aideBranch(newDex({ 1, 4, 7, 10, 13, 16, 19, 21, 25, 29, 32 }))
check(caught == 11, "VAR_0x8006 = 11 at the gate (got " .. tostring(caught) .. ")")
check(jumped == nil, "no jump to Aide_HaventCaughtEnough, so HM05 is handed over")

print("[test] 3. only 9 caught keeps the aide's gift locked")
local jumped3, caught3 = aideBranch(newDex({ 1, 4, 7, 10, 13, 16, 19, 21, 25 }))
check(caught3 == 9, "VAR_0x8006 = 9 at the gate (got " .. tostring(caught3) .. ")")
check(jumped3 == "Aide_HaventCaughtEnough", "9 caught jumps to the refusal branch")

print("[test] 4. national mode counts the whole national range")
s.dex = newDex({ 1, 4, 7 })
Dex.setCaught(s.dex, 300)
local ctx4 = newCtx()
setVar(ctx4, 0x8004, 1)
specialvar(ctx4, 0x800D, Std.SPECIAL.GetPokedexCount)
check(getVar(ctx4, 0x8006) == 4, "national caught = 4 (got " .. tostring(getVar(ctx4, 0x8006)) .. ")")
local ctx4b = newCtx()
setVar(ctx4b, 0x8004, 0)
specialvar(ctx4b, 0x800D, Std.SPECIAL.GetPokedexCount)
check(getVar(ctx4b, 0x8006) == 3, "kanto caught skips species 300 (got "
  .. tostring(getVar(ctx4b, 0x8006)) .. ")")

print("[test] 5. SetSeenMon registers the species in VAR_0x8004")
s.dex = newDex({})
local ctx5 = newCtx()
setVar(ctx5, 0x8004, 138) -- pokefirered/include/constants/species.h:142
Natives.special(ctx5, Std.SPECIAL.SetSeenMon, a)
check(Dex.isSeen(s.dex, 138), "species 138 is seen")
check(not Dex.isCaught(s.dex, 138), "SetSeenMon does not mark it caught")

print("[test] 6. SetHiddenItemFlag sets the flag id in VAR_0x8004")
local ctx6 = newCtx()
setVar(ctx6, 0x8004, 0x3E9)
Natives.special(ctx6, Std.SPECIAL.SetHiddenItemFlag, a)
check(Flags.getFlag(store, ctx6, 0x3E9) == true, "flag 0x3E9 is set")

print("[test] 7. party counts")
s.party = {
  { species = 1, hp = 20, otId = 4242, nickname = "BULBA", otName = "RED" },
  { species = 4, hp = 0, otId = 4242 },
  { species = 7, hp = 11, otId = 999, otName = "BLUE" },
  { species = 0, isEgg = true, hp = 5 },
}
s.party[4].species = 1
local ctx7 = newCtx()
check(specialvar(ctx7, 0x800D, Std.SPECIAL.CalculatePlayerPartyCount) == 4,
  "CalculatePlayerPartyCount = 4")
check(specialvar(ctx7, 0x800D, Std.SPECIAL.CountPartyNonEggMons) == 3,
  "CountPartyNonEggMons = 3")
setVar(ctx7, 0x8004, 0)
check(specialvar(ctx7, 0x800D, Std.SPECIAL.CountPartyAliveNonEggMons_IgnoreVar0x8004Slot) == 1,
  "alive non-egg mons ignoring slot 1 = 1")
setVar(ctx7, 0x8004, 2)
check(specialvar(ctx7, 0x800D, Std.SPECIAL.CountPartyAliveNonEggMons_IgnoreVar0x8004Slot) == 1,
  "alive non-egg mons ignoring slot 3 = 1")

print("[test] 8. species / OT / egg queries on the VAR_0x8004 slot")
local ctx8 = newCtx()
setVar(ctx8, 0x8004, 0)
check(specialvar(ctx8, 0x800D, Std.SPECIAL.GetPartyMonSpecies) == 1, "slot 1 species = 1")
setVar(ctx8, 0x8004, 3)
check(specialvar(ctx8, 0x800D, Std.SPECIAL.GetPartyMonSpecies) == 412,
  "the egg slot reads back SPECIES_EGG")
Natives.special(ctx8, Std.SPECIAL.IsSelectedMonEgg, a)
check(getVar(ctx8, 0x800D) == 1, "IsSelectedMonEgg = TRUE for the egg")
setVar(ctx8, 0x8004, 0)
Natives.special(ctx8, Std.SPECIAL.IsSelectedMonEgg, a)
check(getVar(ctx8, 0x800D) == 0, "IsSelectedMonEgg = FALSE for BULBASAUR")
check(specialvar(ctx8, 0x800D, Std.SPECIAL.IsMonOTNameNotPlayers) == 0,
  "own-OT mon: IsMonOTNameNotPlayers = FALSE")
setVar(ctx8, 0x8004, 2)
check(specialvar(ctx8, 0x800D, Std.SPECIAL.IsMonOTNameNotPlayers) == 1,
  "traded mon: IsMonOTNameNotPlayers = TRUE")
check(ctx8.stringVars[1] == "BLUE", "the OT name landed in STR_VAR_1")

print("[test] 9. species-in-party queries")
local ctx9 = newCtx()
setVar(ctx9, 0x8004, 7)
check(specialvar(ctx9, 0x800D, Std.SPECIAL.DoesPlayerPartyContainSpecies) == 1,
  "DoesPlayerPartyContainSpecies = TRUE for SQUIRTLE")
check(specialvar(ctx9, 0x800D, Std.SPECIAL.PlayerPartyContainsSpeciesWithPlayerID) == 0,
  "the SQUIRTLE is traded, so the player-ID form is FALSE")
setVar(ctx9, 0x8004, 1)
check(specialvar(ctx9, 0x800D, Std.SPECIAL.PlayerPartyContainsSpeciesWithPlayerID) == 1,
  "the own-OT BULBASAUR answers the player-ID form")
setVar(ctx9, 0x8004, 25)
check(specialvar(ctx9, 0x800D, Std.SPECIAL.DoesPlayerPartyContainSpecies) == 0,
  "no PIKACHU in the party")

print("[test] 10. money")
local ctx10 = newCtx()
setVar(ctx10, 0x8005, 3000)
check(specialvar(ctx10, 0x800D, Std.SPECIAL.IsEnoughForCostInVar0x8005) == 1,
  "3000 covers a 3000 cost")
setVar(ctx10, 0x8005, 3001)
check(specialvar(ctx10, 0x800D, Std.SPECIAL.IsEnoughForCostInVar0x8005) == 0,
  "3000 does not cover 3001")
setVar(ctx10, 0x8005, 1200)
Natives.special(ctx10, Std.SPECIAL.SubtractMoneyFromVar0x8005, a)
check(s.money == 1800, "money is 1800 after the 1200 charge (got " .. tostring(s.money) .. ")")

print("[test] 11. HasAllKantoMons / HasAllMons exclude Mew")
local full = Dex.new()
for sp = 1, 150 do Dex.setCaught(full, sp) end
s.dex = full
local ctx11 = newCtx()
check(specialvar(ctx11, 0x800D, Std.SPECIAL.HasAllKantoMons) == 1,
  "1..150 caught is HasAllKantoMons = TRUE without Mew")
check(specialvar(ctx11, 0x800D, Std.SPECIAL.HasAllMons) == 0,
  "HasAllMons still wants the Johto and Hoenn ranges")
Dex.setCaught(full, 149)
full.caught[150] = nil
full.owned[150] = nil
check(specialvar(ctx11, 0x800D, Std.SPECIAL.HasAllKantoMons) == 0,
  "one missing Kanto mon makes it FALSE")

print("[test] 12. GetStarterSpecies maps VAR_STARTER_MON")
local ctx12 = newCtx()
Flags.setVar(store, ctx12, 0x4031, 0)
check(specialvar(ctx12, 0x800D, Std.SPECIAL.GetStarterSpecies) == 1, "starter 0 = BULBASAUR")
Flags.setVar(store, ctx12, 0x4031, 1)
check(specialvar(ctx12, 0x800D, Std.SPECIAL.GetStarterSpecies) == 7, "starter 1 = SQUIRTLE")
Flags.setVar(store, ctx12, 0x4031, 2)
check(specialvar(ctx12, 0x800D, Std.SPECIAL.GetStarterSpecies) == 4, "starter 2 = CHARMANDER")
Flags.setVar(store, ctx12, 0x4031, 9)
check(specialvar(ctx12, 0x800D, Std.SPECIAL.GetStarterSpecies) == 1,
  "an out-of-range index falls back to index 0")

print("[test] 13. GetRandomSlotMachineId stays inside the cart table")
local Rng = require("src.core.game3.rng")
Rng.SeedRng(0x1234)
local ctx13 = newCtx()
local seen = {}
for _ = 1, 200 do
  local id = specialvar(ctx13, 0x800D, Std.SPECIAL.GetRandomSlotMachineId)
  seen[id] = (seen[id] or 0) + 1
  if id < 0 or id > 5 then
    check(false, "slot machine id out of range: " .. tostring(id))
    break
  end
end
check(seen[0] and seen[0] > 0, "id 0 is the most common draw (11 of 22 table slots)")
check((seen[5] or 0) < (seen[0] or 0), "id 5 is rarer than id 0")

print("[test] 14. BufferBigGuyOrBigGirlString follows the player's gender")
local ctx14 = newCtx()
s.gender = 0
Natives.special(ctx14, Std.SPECIAL.BufferBigGuyOrBigGirlString, a)
check(ctx14.stringVars[1] == "gText_BigGuy", "boy: STR_VAR_1 = gText_BigGuy (got "
  .. tostring(ctx14.stringVars[1]) .. ")")
s.gender = 1
Natives.special(ctx14, Std.SPECIAL.BufferBigGuyOrBigGirlString, a)
check(ctx14.stringVars[1] == "gText_BigGirl", "girl: STR_VAR_1 = gText_BigGirl (got "
  .. tostring(ctx14.stringVars[1]) .. ")")
s.gender = 0

print("[test] 15. position queries")
local ctx15 = newCtx()
s.map, s.x = "FR_VERMILION_CITY", 23
check(specialvar(ctx15, 0x800D, Std.SPECIAL.IsPlayerLeftOfVermilionSailor) == 1,
  "x = 23 in Vermilion is left of the sailor")
s.x = 24
check(specialvar(ctx15, 0x800D, Std.SPECIAL.IsPlayerLeftOfVermilionSailor) == 0,
  "x = 24 is not")
s.map = "FR_ONE_ISLAND_HARBOR"
check(specialvar(ctx15, 0x800D, Std.SPECIAL.IsPlayerLeftOfVermilionSailor) == 0,
  "another harbour is not Vermilion")
check(specialvar(ctx15, 0x800D, Std.SPECIAL.IsPlayerNotInTrainerTowerLobby) == 1,
  "outside the tower lobby = TRUE")
s.map = "FR_TRAINER_TOWER_LOBBY"
check(specialvar(ctx15, 0x800D, Std.SPECIAL.IsPlayerNotInTrainerTowerLobby) == 0,
  "inside the tower lobby = FALSE")
s.map = "FR_ROUTE_2_EAST_BUILDING"

print("[test] 16. IsThereRoomInAnyBoxForMorePokemon walks all 14 boxes")
s.storage = Storage.new()
local ctx16 = newCtx()
check(specialvar(ctx16, 0x800D, Std.SPECIAL.IsThereRoomInAnyBoxForMorePokemon) == 1,
  "an empty PC has room")
for b = 1, Storage.TOTAL_BOXES_COUNT do
  for slot = 1, Storage.IN_BOX_COUNT do
    s.storage.boxes[b].mons[slot] = { species = 16, level = 5 }
  end
end
check(specialvar(ctx16, 0x800D, Std.SPECIAL.IsThereRoomInAnyBoxForMorePokemon) == 0,
  "420 boxed mons leaves no room")
s.storage.boxes[14].mons[30] = nil
check(specialvar(ctx16, 0x800D, Std.SPECIAL.IsThereRoomInAnyBoxForMorePokemon) == 1,
  "one free slot in the last box is enough")

print("[test] 17. berry queries")
local Bag = require("src.core.game3.bag")
local ctx17 = newCtx()
check(specialvar(ctx17, 0x800D, Std.SPECIAL.HasAtLeastOneBerry) == 0,
  "no Berry Pouch means no berries")
Bag.add(s.bag, 365, 1) -- pokefirered/include/constants/items.h:437
check(specialvar(ctx17, 0x800D, Std.SPECIAL.HasAtLeastOneBerry) == 0,
  "an empty Berry Pouch is still FALSE")
Bag.add(s.bag, 133, 1) -- pokefirered/include/constants/items.h:137
check(specialvar(ctx17, 0x800D, Std.SPECIAL.HasAtLeastOneBerry) == 1,
  "a CHERI BERRY answers TRUE")
check(specialvar(ctx17, 0x800D, Std.SPECIAL.DoesPartyHaveEnigmaBerry) == 0,
  "nobody is holding an ENIGMA BERRY")
s.party[1].heldItem = 175
check(specialvar(ctx17, 0x800D, Std.SPECIAL.DoesPartyHaveEnigmaBerry) == 1,
  "a held ENIGMA BERRY answers TRUE")
s.party[1].heldItem = nil

print("[test] 18. IsDodrioInParty and IsBadEggInParty")
local ctx18 = newCtx()
check(specialvar(ctx18, 0x800D, Std.SPECIAL.IsDodrioInParty) == 0, "no DODRIO in the party")
s.party[2].species = 85
check(specialvar(ctx18, 0x800D, Std.SPECIAL.IsDodrioInParty) == 1, "a DODRIO answers TRUE")
s.party[2].species = 4
check(specialvar(ctx18, 0x800D, Std.SPECIAL.IsBadEggInParty) == 0, "no bad egg")

print("[test] 19. ShouldShowBoxWasFullMessage only fires on a box change")
local ctx19 = newCtx()
s.storage.currentBox = 1
Flags.setVar(store, ctx19, 0x4037, 0) -- pokefirered/include/constants/vars.h:105
check(specialvar(ctx19, 0x800D, Std.SPECIAL.ShouldShowBoxWasFullMessage) == 0,
  "same box: no box-was-full message")
s.storage.currentBox = 3
check(specialvar(ctx19, 0x800D, Std.SPECIAL.ShouldShowBoxWasFullMessage) == 1,
  "the mon spilled into another box: message shown once")
check(Flags.getFlag(store, ctx19, 0x843) == true, "FLAG_SHOWN_BOX_WAS_FULL_MESSAGE is set")
check(specialvar(ctx19, 0x800D, Std.SPECIAL.ShouldShowBoxWasFullMessage) == 0,
  "the flag keeps it from firing twice")

print("[test] 20. every new query is bound and nothing logs as unknown")
local unknown = {}
Natives.resetLog()
local logAdapter = { log = function(msg) unknown[#unknown + 1] = msg end }
local ids = {
  "GetPokedexCount", "SetSeenMon", "SetHiddenItemFlag", "CalculatePlayerPartyCount",
  "CountPartyNonEggMons", "CountPartyAliveNonEggMons_IgnoreVar0x8004Slot",
  "DoesPlayerPartyContainSpecies", "PlayerPartyContainsSpeciesWithPlayerID",
  "GetPartyMonSpecies", "IsSelectedMonEgg", "IsMonOTNameNotPlayers",
  "NameRaterWasNicknameChanged", "GetSelectedMonNicknameAndSpecies",
  "IsEnoughForCostInVar0x8005", "SubtractMoneyFromVar0x8005", "HasAllKantoMons",
  "HasAllMons", "GetStarterSpecies", "GetRandomSlotMachineId",
  "BufferBigGuyOrBigGirlString", "GetPlayerFacingDirection",
  "IsPlayerLeftOfVermilionSailor", "IsPlayerNotInTrainerTowerLobby",
  "IsBadEggInParty", "IsThereRoomInAnyBoxForMorePokemon", "IsDodrioInParty",
  "HasAtLeastOneBerry", "DoesPartyHaveEnigmaBerry", "ShouldShowBoxWasFullMessage",
  "GetPCBoxToSendMon", "BufferUnionRoomPlayerName",
}
for _, name in ipairs(ids) do
  local id = Std.SPECIAL[name]
  if not id then
    check(false, name .. " has no Std.SPECIAL id")
  else
    Natives.special(newCtx(), id, logAdapter)
  end
end
check(#unknown == 0, "no handler logged as unknown (got " .. tostring(#unknown) .. ")")
check(Std.SPECIAL.GetPokedexCount == 0xD4, "GetPokedexCount is special 0xD4")

print("[test] 21. a specialvar to another destination leaves VAR_RESULT alone")
-- pokefirered/src/scrcmd.c:109
local ctx21 = newCtx()
setVar(ctx21, 0x800D, 5)
setVar(ctx21, 0x8004, 25)
check(specialvar(ctx21, 0x8008, Std.SPECIAL.DoesPlayerPartyContainSpecies) == 0,
  "the answer lands in VAR_0x8008")
check(getVar(ctx21, 0x800D) == 5, "VAR_RESULT is untouched (got "
  .. tostring(getVar(ctx21, 0x800D)) .. ")")
-- pokefirered/src/party_menu_specials.c:102
setVar(ctx21, 0x8004, 3)
Natives.special(ctx21, Std.SPECIAL.IsSelectedMonEgg, a)
check(getVar(ctx21, 0x800D) == 1, "IsSelectedMonEgg still writes VAR_RESULT on its own")

-- pokefirered/data/scripts/pkmn_center_nurse.inc:31
print("[test] 22. the nurse rows after the heal stay out of the union-room branch")
local function nurseTail(mapId)
  s.map = mapId
  local c = newCtx()
  local jumped = nil
  local vm = { ctx = c, store = store, adapters = a,
    setPc = function(_, key) jumped = key end }
  Flags.setVar(store, c, 0x800D, 1)
  -- pokefirered/data/scripts/pkmn_center_nurse.inc:32
  Ops.dispatch(vm, { op = "specialvar", [1] = 0x800D,
    [2] = Std.SPECIAL.IsPlayerNotInTrainerTowerLobby })
  Ops.dispatch(vm, { op = "compare_var_to_value", var = 0x800D, value = 0 })
  Ops.dispatch(vm, { op = "goto_if", cond = 1, target = "ReturnPkmn" })
  if jumped then return jumped, Flags.getVar(store, c, 0x8008) end
  -- pokefirered/data/scripts/pkmn_center_nurse.inc:34
  Ops.dispatch(vm, { op = "specialvar", [1] = 0x800D,
    [2] = Std.SPECIAL.BufferUnionRoomPlayerName })
  Ops.dispatch(vm, { op = "copyvar", [1] = 0x8008, [2] = 0x800D })
  Ops.dispatch(vm, { op = "compare_var_to_value", var = 0x8008, value = 0 })
  Ops.dispatch(vm, { op = "goto_if", cond = 1, target = "ReturnPkmn" })
  Ops.dispatch(vm, { op = "compare_var_to_value", var = 0x8008, value = 1 })
  Ops.dispatch(vm, { op = "goto_if", cond = 1, target = "PlayerWaitingInUnionRoom" })
  return jumped, Flags.getVar(store, c, 0x8008)
end
local nurseJump, nurseVar = nurseTail("FR_VIRIDIAN_CITY_POKEMON_CENTER_1F")
check(nurseVar == 0, "VAR_0x8008 = FALSE with no union-room name buffered (got "
  .. tostring(nurseVar) .. ")")
check(nurseJump == "ReturnPkmn", "the nurse goes to ReturnPkmn (got "
  .. tostring(nurseJump) .. ")")
local lobbyJump = nurseTail("FR_TRAINER_TOWER_LOBBY")
check(lobbyJump == "ReturnPkmn", "the Trainer Tower lobby nurse also returns the mons (got "
  .. tostring(lobbyJump) .. ")")
s.map = "FR_ROUTE_2_EAST_BUILDING"

print("[test] 23. an unbound specialvar writes 0 instead of leaving the old value")
local ctx23 = newCtx()
setVar(ctx23, 0x800D, 1)
check(specialvar(ctx23, 0x800D, 0x182) == 0,
  "unbound special 0x182 leaves VAR_RESULT at 0 (got " .. tostring(getVar(ctx23, 0x800D)) .. ")")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
