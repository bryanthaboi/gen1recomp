-- Tests for 1:1 Pret Pokédex Ordering, Filtering, and Habitat Presentation.
local Dex = require("src.core.game3.dex")
local PokedexData = require("src.core.game3.pokedex_data")

print("=== Running Game3 Pokédex Sorting & Presentation Parity Tests ===")

-- 1. Initialize Pokedex Data
PokedexData.init()
assert(PokedexData._orders ~= nil, "Orders loaded")
assert(PokedexData._categories ~= nil, "Categories loaded")

-- 2. Setup Dex state:
-- Mark seen: Bulbasaur (1), Charmander (4), Pikachu (25), Mew (151), Chikorita (152), Celebi (251)
-- Mark caught: Bulbasaur (1), Pikachu (25), Celebi (251)
local dex = Dex.new()
Dex.setSeen(dex, 1)
Dex.setCaught(dex, 1)
Dex.setSeen(dex, 4)
Dex.setSeen(dex, 25)
Dex.setCaught(dex, 25)
Dex.setSeen(dex, 151)
Dex.setSeen(dex, 152)
Dex.setSeen(dex, 251)
Dex.setCaught(dex, 251)

-- 3. Test Numerical Kanto:
-- Highest seen Kanto is Mew (151). List must have length 151.
local kantoList = PokedexData.getOrderList("numerical_kanto", dex)
assert(#kantoList == 151, string.format("Numerical Kanto list length must be highest seen (151), got %d", #kantoList))
assert(kantoList[1] == 1, "Slot 1 is Bulbasaur")
assert(kantoList[4] == 4, "Slot 4 is Charmander")
assert(kantoList[25] == 25, "Slot 25 is Pikachu")
assert(kantoList[151] == 151, "Slot 151 is Mew")
print("[PASS] Numerical Kanto mode lists entries 1..151 (highest seen Kanto)")

-- Test Numerical Kanto with max seen Pikachu (25):
local dexEarly = Dex.new()
Dex.setSeen(dexEarly, 1)
Dex.setSeen(dexEarly, 25)
local earlyList = PokedexData.getOrderList("numerical_kanto", dexEarly)
assert(#earlyList == 25, string.format("Numerical Kanto early list length must be 25, got %d", #earlyList))
print("[PASS] Numerical Kanto early list truncates at highest seen (25)")

-- 4. Test Numerical National:
-- Highest seen National in `dex` is Celebi (251).
local natList = PokedexData.getOrderList("numerical_national", dex)
assert(#natList == 251, string.format("Numerical National list length must be highest seen (251), got %d", #natList))
assert(natList[1] == 1, "Slot 1 is 1")
assert(natList[251] == 251, "Slot 251 is 251")
print("[PASS] Numerical National mode lists entries 1..251 (highest seen National)")

-- 5. Test A to Z Mode:
-- When National Dex is NOT unlocked, maxN is 151 (4 seen Kanto species: 1, 4, 25, 151).
local atozListKanto = PokedexData.getOrderList("atoz", dex)
assert(#atozListKanto == 4, string.format("A to Z list without national dex must contain 4 Kanto species, got %d", #atozListKanto))

-- Unlock National Dex:
dex.nationalUnlocked = true

-- Now A to Z includes all 6 seen species (1, 4, 25, 151, 152, 251).
local atozList = PokedexData.getOrderList("atoz", dex)
assert(#atozList == 6, string.format("A to Z list with national dex must contain all 6 seen species, got %d", #atozList))
for _, sp in ipairs(atozList) do
  assert(Dex.isSeen(dex, sp), string.format("Species %d in A-Z list must be seen", sp))
end
print("[PASS] A to Z mode contains only seen species without dashes")

-- 6. Test Type Mode:
-- Must include ONLY caught species (1, 25, 251 = 3 species).
local typeList = PokedexData.getOrderList("type", dex)
assert(#typeList == 3, string.format("Type mode list must contain only caught species (3), got %d", #typeList))
for _, sp in ipairs(typeList) do
  assert(Dex.isCaught(dex, sp), string.format("Species %d in Type list must be caught", sp))
end
print("[PASS] Type mode contains only caught species without dashes")

-- 7. Test Lightest Mode:
-- Must include ONLY caught species (1, 25, 251 = 3 species).
local lightList = PokedexData.getOrderList("lightest", dex)
assert(#lightList == 3, string.format("Lightest mode list must contain only caught species (3), got %d", #lightList))
for _, sp in ipairs(lightList) do
  assert(Dex.isCaught(dex, sp), string.format("Species %d in Lightest list must be caught", sp))
end
print("[PASS] Lightest mode contains only caught species without dashes")

-- 8. Test Smallest Mode:
-- Must include ONLY caught species (1, 25, 251 = 3 species).
local smallList = PokedexData.getOrderList("smallest", dex)
assert(#smallList == 3, string.format("Smallest mode list must contain only caught species (3), got %d", #smallList))
for _, sp in ipairs(smallList) do
  assert(Dex.isCaught(dex, sp), string.format("Species %d in Smallest list must be caught", sp))
end
print("[PASS] Smallest mode contains only caught species without dashes")

-- 9. Test Habitat Category Pages:
-- In Grassland, only Bulbasaur (1) and Pikachu (25) are seen.
-- Page 11 has Pikachu (25 is in page 7 or similar? Let's verify):
local grassUnlocked = PokedexData.getUnlockedCategoryPages("grassland", dex)
assert(#grassUnlocked > 0, "Grassland has unlocked pages")
for _, p in ipairs(grassUnlocked) do
  assert(#p.mons >= 1 and #p.mons <= 4, "Unlocked page has 1..4 seen mons")
  for _, sp in ipairs(p.mons) do
    assert(Dex.isSeen(dex, sp), string.format("Habitat page mon %d must be seen", sp))
  end
end
print("[PASS] Habitat category unlocked pages contain only seen species and correct pagination")

print("=== ALL POKÉDEX SORTING & PRESENTATION TESTS PASSED (100%) ===")
