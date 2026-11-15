package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local home = os.getenv("HOME") or ""
local roots = {}
local identity = os.getenv("POKEPORT_IDENTITY")
if identity and identity ~= "" then
  roots[#roots + 1] = home .. "/Library/Application Support/LOVE/" .. identity .. "/emerald/"
  roots[#roots + 1] = home .. "/.local/share/love/" .. identity .. "/emerald/"
end
roots[#roots + 1] = home .. "/Library/Application Support/LOVE/pokemon-love2d/emerald/"

local ROOT
for _, r in ipairs(roots) do
  local f = io.open(r .. "data/generated/gba/pokemon/hoenn.lua", "rb")
  if f then
    f:close()
    ROOT = r
    break
  end
end
if not ROOT then
  local dir = require("tests.game3_cache").gameDir("emerald", "pokemon/hoenn.lua")
  ROOT = dir and dir .. "/"
end
if not ROOT then
  print("emerald_runtime_data_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end
print("emerald_runtime_data_test: cache " .. ROOT)

local fs = {}
function fs:read(rel)
  local f = io.open(ROOT .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
function fs:exists(rel) return self:read(rel) ~= nil end
package.loaded["src.core.game3.dataset"] = {
  cache = function() return fs end,
  mountExtractRoots = function() end,
}

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")

local session = { version = "emerald", party = {}, flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local C = require("src.core.game3.constants").of("emerald")

print("[test] species pack")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(fs)
local TREECKO = C:require("species", "SPECIES_TREECKO")
eq(TREECKO, 277, "SPECIES_TREECKO is internal 277")
eq(Pokemon.name(TREECKO), "TREECKO", "species 277 name")
eq(Pokemon.national(TREECKO), 252, "Treecko national 252")
eq(Pokemon.speciesFromNational(252), TREECKO, "national 252 -> 277")
eq(Pokemon.national(C:require("species", "SPECIES_ZIGZAGOON")), 263, "Zigzagoon national 263")

print("[test] Hoenn dex (pokeemerald/src/pokemon.c:5685)")
local Dex = require("src.core.game3.dex")
eq(Dex.regionalMax("emerald"), 202, "HOENN_DEX_COUNT 202")
eq(Pokemon.regional(TREECKO, "emerald"), 1, "Treecko Hoenn #1")
eq(Pokemon.regional(C:require("species", "SPECIES_POOCHYENA"), "emerald"), 10, "Poochyena Hoenn #10")
eq(Pokemon.regional(C:require("species", "SPECIES_ZIGZAGOON"), "emerald"), 12, "Zigzagoon Hoenn #12")
eq(Pokemon.regional(C:require("species", "SPECIES_WURMPLE"), "emerald"), 14, "Wurmple Hoenn #14")
eq(Pokemon.regional(C:require("species", "SPECIES_DEOXYS"), "emerald"), 202, "Deoxys Hoenn #202")
eq(Pokemon.regional(C:require("species", "SPECIES_BULBASAUR"), "emerald"), nil, "Bulbasaur is not in the Hoenn dex")
check(Dex.nationalInRegional(252, "emerald"), "national 252 is in the Hoenn dex")
check(not Dex.nationalInRegional(1, "emerald"), "national 1 is not")

print("[test] national unlock predicate (pokeemerald/src/event_data.c:74)")
local save = { version = "emerald", dex = { caught = { [TREECKO] = true, [1] = true } }, flags = {}, vars = {} }
eq(Dex.summaryCount(save), 1, "Hoenn count skips Bulbasaur")
save.flags[C:require("flags", "FLAG_SYS_NATIONAL_DEX")] = true
save.vars[C:require("vars", "VAR_NATIONAL_DEX")] = 0x302
check(not Dex.nationalEnabled(save), "flag + var without the magic is not enough")
Dex.enableNational(save)
check(Dex.nationalEnabled(save), "EnableNationalPokedex sets all three")
eq(Dex.summaryCount(save), 2, "national count includes Bulbasaur")

print("[test] items pack pockets")
local ItemsData = require("src.core.game3.items_data")
ItemsData.install(nil)
eq(ItemsData.pocketOf(C:require("items", "ITEM_POKE_BALL")), "POKE_BALLS", "Poke Ball pocket")
eq(ItemsData.pocketOf(C:require("items", "ITEM_TM01")), "TM_CASE", "TM01 -> TM_HM pocket")
eq(ItemsData.pocketOf(C:require("items", "ITEM_CHERI_BERRY")), "BERRY_POUCH", "Cheri -> BERRIES pocket")
eq(ItemsData.pocketOf(C:require("items", "ITEM_MAGMA_EMBLEM")), "KEY_ITEMS", "Magma Emblem key item")
eq(ItemsData.displayName(C:require("items", "ITEM_MAGMA_EMBLEM")), "MAGMA EMBLEM", "Magma Emblem name")
eq(ItemsData.info(C:require("items", "ITEM_MACH_BIKE")).fieldUseName, "ItemUseOutOfBattle_Bike", "Mach Bike field use")
eq(ItemsData.pocketResult(C:require("items", "ITEM_POKE_BALL")), 2, "POCKET_POKE_BALLS")
eq(ItemsData.CAPACITY.TM_CASE, 64, "TM_HM capacity")
local Bag = require("src.core.game3.bag")
local bag = Bag.new()
check(Bag.add(bag, C:require("items", "ITEM_POTION"), 120), "120 Potions")
eq(#bag.pockets.ITEMS, 2, "two Potion slots at 99 + 21")

print("[test] Route 101 wild table (pokeemerald/src/wild_encounter.c:422)")
local Encounters = require("src.core.game3.encounters")
Encounters.loadFromMod(nil)
local t = Encounters.tableFor("EM_ROUTE101")
check(t and t.land and #t.land.slots == 12, "Route 101 land table resolves")
eq(t and t.land.rate, 20, "Route 101 rate 20")
local rules = Encounters.rules()
local Rng = require("src.core.game3.rng")
local W, P, Z = C:require("species", "SPECIES_WURMPLE"), C:require("species", "SPECIES_POOCHYENA"),
  C:require("species", "SPECIES_ZIGZAGOON")
Rng.SeedRng(0x1234)
local first = rules.tryGenerate(t.land, "land", false, false)
Rng.SeedRng(0x1234)
local again = rules.tryGenerate(t.land, "land", false, false)
check(first.species == W or first.species == P or first.species == Z, "seed 0x1234 rolls a Route 101 mon")
eq(again.species, first.species, "same seed, same species")
eq(again.personality, first.personality, "same seed, same personality")
local counts = { [W] = 0, [P] = 0, [Z] = 0 }
local N = 20000
Rng.SeedRng(42)
for _ = 1, N do
  local e = rules.tryGenerate(t.land, "land", false, false)
  counts[e.species] = (counts[e.species] or 0) + 1
end
local function near(got, want) return math.abs(got / N - want) < 0.015 end
check(near(counts[W], 0.45), "Wurmple ~45% (" .. counts[W] .. ")")
check(near(counts[P], 0.45), "Poochyena ~45% (" .. counts[P] .. ")")
check(near(counts[Z], 0.10), "Zigzagoon ~10% (" .. counts[Z] .. ")")

print("[test] new game runs EventScript_ResetAllMapFlags from the bundle")
local Schema = require("src.core.game3.save_schema_firered")
local s = Schema.newGame({ version = "emerald", name = "BRENDAN", rngSeed = 1 })
local Flags = require("src.core.game3.scripting.flags")
check(Flags.getFlag(s, nil, C:require("flags", "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH")),
  "Birch hidden in his lab (pokeemerald/data/scripts/new_game.inc:120)")
check(Flags.getFlag(s, nil, C:require("flags", "FLAG_HIDE_SKY_PILLAR_TOP_RAYQUAZA_STILL")),
  "last setflag ran (new_game.inc:274)")
eq(s.map, "EM_INSIDE_OF_TRUCK", "truck start")

GameVersion.set(before)
T.finish("emerald_runtime_data_test")
