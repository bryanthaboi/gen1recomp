-- Tests for 1:1 National Pokédex Gating, Systems, and Story Triggers matching pret pokefirered.

local Dex = require("src.core.game3.dex")
local PokedexData = require("src.core.game3.pokedex_data")
local Evolution = require("src.core.game3.evolution")
local ItemUse = require("src.core.game3.item_use")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")

print("=== [TEST 1] National Dex specials constants ===")
assert(Std.SPECIAL.EnableNationalPokedex == 0x179, "EnableNationalPokedex special constant must be 0x179")
assert(Std.SPECIAL.SetUnlockedPokedexFlags == 0x18B, "SetUnlockedPokedexFlags special constant must be 0x18B")
assert(Std.SPECIAL.IsNationalPokedexEnabled == 0x19D, "IsNationalPokedexEnabled special constant must be 0x19D")
print("[PASS] Special constants match pret specials.inc (0x179, 0x18B, 0x19D)")

print("=== [TEST 2] Script Special Execution & State Machine ===")
local store = Flags.newStore()
local Space = { store = store }
package.loaded["src.core.game3.scripting.space"] = Space

local session = {
  national_dex_unlocked = false,
  dex = Dex.new(),
  store = store,
}
local Runtime = {
  getSession = function() return session end,
}
package.loaded["src.core.game3.runtime"] = Runtime

-- 1. Check IsNationalPokedexEnabled before unlock (should be 0)
local ctx = {
  vars = {},
  setVar = function(self, varId, val) self.vars[varId] = val end,
  getVar = function(self, varId) return self.vars[varId] end,
}
Natives.special(ctx, Std.SPECIAL.IsNationalPokedexEnabled)
assert(ctx.vars[0x800D] == 0, "IsNationalPokedexEnabled should set VAR_RESULT to 0 before unlock")
assert(not PokedexData.isNationalUnlocked(session, session.dex), "isNationalUnlocked must return false before unlock")

-- 2. Execute EnableNationalPokedex
Natives.special(ctx, Std.SPECIAL.EnableNationalPokedex)
assert(Flags.getFlag(store, nil, 0x840) == true, "EnableNationalPokedex must set FLAG_SYS_NATIONAL_DEX (0x840)")
assert(Flags.getVar(store, nil, 0x404E) == 0x6258, "EnableNationalPokedex must set VAR_NATIONAL_DEX (0x404E) to 0x6258")
assert(session.national_dex_unlocked == true, "session.national_dex_unlocked must be true")
assert(session.dex.nationalUnlocked == true, "dex.nationalUnlocked must be true")

-- 3. Check IsNationalPokedexEnabled after unlock (should be 1)
Natives.special(ctx, Std.SPECIAL.IsNationalPokedexEnabled)
assert(ctx.vars[0x800D] == 1, "IsNationalPokedexEnabled should set VAR_RESULT to 1 after unlock")
assert(PokedexData.isNationalUnlocked(session, session.dex) == true, "isNationalUnlocked must return true after unlock")
print("[PASS] Script specials EnableNationalPokedex and IsNationalPokedexEnabled verified")

print("=== [TEST 3] Evolution Gating (pret evolution_scene.c:641) ===")
-- Reset national dex
session.national_dex_unlocked = false
session.dex.nationalUnlocked = false
Flags.setFlag(store, nil, 0x840, false)
Flags.setVar(store, nil, 0x404E, 0)

-- Golbat (42) evolving into Crobat (169) by friendship
local golbat = { species = 42, level = 50, friendship = 220 }
local crobatTarget = Evolution.levelTarget(golbat, session)
-- Should be blocked (nil) before National Dex
assert(crobatTarget == nil, "Golbat cannot evolve into Crobat (169 > 151) when National Dex is locked")

-- Onix (95) evolving into Steelix (208) with Metal Coat
local onix = { species = 95, level = 30 }
local steelixTarget = Evolution.itemTarget(onix, "ITEM_METAL_COAT", session)
assert(steelixTarget == nil, "Onix cannot evolve into Steelix (208 > 151) when National Dex is locked")

-- Kanto evolution (Bulbasaur 1 -> Ivysaur 2) is allowed
local bulbasaur = { species = 1, level = 16 }
local ivysaurTarget = Evolution.levelTarget(bulbasaur, session)
assert(ivysaurTarget == 2, "Kanto evolutions (1 -> 2) must remain allowed when National Dex is locked")

-- Now unlock National Dex: Golbat -> Crobat must be allowed
session.national_dex_unlocked = true
Flags.setFlag(store, nil, 0x840, true)
local crobatUnlocked = Evolution.levelTarget(golbat, session)
assert(crobatUnlocked == 169, "Golbat must evolve into Crobat (169) once National Dex is unlocked")
print("[PASS] Evolution gating before/after National Dex verified")

print("=== [TEST 4] Capture Registration Gating ===")
local lockedStore = Flags.newStore()
Space.store = lockedStore
local lockedDex = Dex.new()
local lockedSession = { national_dex_unlocked = false, dex = lockedDex, store = lockedStore }
Runtime.getSession = function() return lockedSession end

-- Try to register non-Kanto species (169 = Crobat, 252 = Treecko) before National Dex
Dex.registerEncounter(lockedDex, 169, lockedSession)
Dex.registerCapture(lockedDex, 169, lockedSession)
assert(not Dex.isSeen(lockedDex, 169), "Crobat should NOT be marked seen in locked Kanto Dex")
assert(not Dex.isCaught(lockedDex, 169), "Crobat should NOT be marked caught in locked Kanto Dex")

-- Kanto species (19 = Rattata) registers normally
Dex.registerEncounter(lockedDex, 19, lockedSession)
Dex.registerCapture(lockedDex, 19, lockedSession)
assert(Dex.isSeen(lockedDex, 19) == true, "Rattata must be marked seen in locked Kanto Dex")
assert(Dex.isCaught(lockedDex, 19) == true, "Rattata must be marked caught in locked Kanto Dex")

-- Unlock National Dex: Crobat now registers normally
local unlockedDex = Dex.new()
unlockedDex.nationalUnlocked = true
local unlockedSession = { national_dex_unlocked = true, dex = unlockedDex, store = Flags.newStore() }
Flags.setFlag(unlockedSession.store, nil, 0x840, true)
Runtime.getSession = function() return unlockedSession end

Dex.registerEncounter(unlockedDex, 169, unlockedSession)
Dex.registerCapture(unlockedDex, 169, unlockedSession)
assert(Dex.isSeen(unlockedDex, 169) == true, "Crobat MUST be marked seen in unlocked National Dex")
assert(Dex.isCaught(unlockedDex, 169) == true, "Crobat MUST be marked caught in unlocked National Dex")
print("=== [TEST 5] Pokédex Top Menu Mode Gating ===")
local Pokedex = require("src.ui.game3.pokedex")
Pokedex.show(lockedDex, { session = lockedSession })
local lockedModes = Pokedex.MODES
local hasNationalMode = false
local hasSearch = false
for _, m in ipairs(lockedModes) do
  if m.id == "numerical_national" then hasNationalMode = true end
  if m.id == "atoz" or m.id == "type" then hasSearch = true end
end
assert(not hasNationalMode, "Locked Pokédex must NOT have NUMERICAL MODE: NATIONAL")
assert(not hasSearch, "Locked Pokédex must NOT have SEARCH section")
assert(Pokedex.maxSpecies() == 151, "Locked Pokédex maxSpecies must be 151")

-- Open with unlocked National Dex
Pokedex.show(unlockedDex, { session = unlockedSession })
local unlockedModes = Pokedex.MODES
local hasKantoMode = false
local hasNatMode = false
local hasAtoZ = false
for _, m in ipairs(unlockedModes) do
  if m.id == "numerical_kanto" then hasKantoMode = true end
  if m.id == "numerical_national" then hasNatMode = true end
  if m.id == "atoz" then hasAtoZ = true end
end
assert(hasKantoMode, "Unlocked Pokédex must have NUMERICAL MODE: KANTO")
assert(hasNatMode, "Unlocked Pokédex must have NUMERICAL MODE: NATIONAL")
assert(hasAtoZ, "Unlocked Pokédex must have SEARCH section with A TO Z MODE")
print("[PASS] Pokédex top menu modes before/after National Dex unlock verified")

print("=== ALL NATIONAL DEX GATING TESTS PASSED! ===")
