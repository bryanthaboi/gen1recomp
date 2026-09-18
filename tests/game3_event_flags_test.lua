-- Unit tests for Game3 Event Flags, Story Progression, and Badge Tracking.

local Flags = require("src.core.game3.scripting.flags")
local FlagsTable = require("src.core.game3.scripting.flags_table")
local FlagsExtract = require("src.import.gba.flags_extract")
local FieldMoves = require("src.core.game3.field_moves")
local Space = require("src.core.game3.scripting.space")
local Ctx = require("src.core.game3.scripting.ctx")

print("=== [TEST 1] Flags table completeness and integrity ===")
assert(FlagsTable.FLAGS.FLAG_BADGE01_GET == 0x820, "BADGE01_GET should be 0x820")
assert(FlagsTable.FLAGS.FLAG_BADGE08_GET == 0x827, "BADGE08_GET should be 0x827")
assert(FlagsTable.FLAGS.FLAG_SYS_POKEDEX_GET == 0x829, "SYS_POKEDEX_GET should be 0x829")
assert(FlagsTable.FLAGS.FLAG_SYS_B_DASH == 0x82F, "SYS_B_DASH should be 0x82F")
assert(FlagsTable.FLAGS.FLAG_SYS_NATIONAL_DEX == 0x840, "SYS_NATIONAL_DEX should be 0x840")
assert(FlagsTable.FLAGS.FLAG_HIDE_OAK_IN_HIS_LAB == 0x02B, "HIDE_OAK_IN_HIS_LAB should be 0x2B")
assert(FlagsTable.VARS.VAR_MAP_SCENE_PALLET_TOWN_OAK == 0x4050, "MAP_SCENE_PALLET_TOWN_OAK should be 0x4050")
assert(FlagsTable.VARS.VAR_STARTER_MON == 0x4031, "STARTER_MON should be 0x4031")
assert(#FlagsTable.NEW_GAME_HIDE_FLAGS == 49, "Should contain exactly 49 new game hide flags from EventScript_ResetAllMapFlags")
local f = io.open("pokefirered/include/constants/flags.h", "r")
if f then
  f:close()
  local extracted = FlagsExtract.extract()
  assert(extracted.flags.FLAG_BADGE01_GET == 0x820, "BADGE01_GET should be 0x820")
  assert(#extracted.newGameHideFlags == 49, "49 new game hide flags")
end
print("[PASS] Flags & vars table matches 1:1")

print("=== [TEST 2] Flags IDS and aliases ===")
assert(Flags.IDS.FLAG_BADGE01_GET == 0x820, "FLAG_BADGE01_GET in IDS")
assert(Flags.IDS.BADGE01_GET == 0x820, "BADGE01_GET stripped alias in IDS")
assert(Flags.IDS.FLAG_SYS_POKEDEX_GET == 0x829, "FLAG_SYS_POKEDEX_GET in IDS")
assert(Flags.IDS.SYS_POKEDEX_GET == 0x829, "SYS_POKEDEX_GET alias in IDS")
assert(Flags.IDS.FLAG_SYS_B_DASH == 0x82F, "FLAG_SYS_B_DASH in IDS")
assert(Flags.IDS.SYS_B_DASH == 0x82F, "SYS_B_DASH alias in IDS")
assert(Flags.IDS.FLAG_SYS_NATIONAL_DEX == 0x840, "FLAG_SYS_NATIONAL_DEX in IDS")
assert(Flags.IDS.SYS_NATIONAL_DEX == 0x840, "SYS_NATIONAL_DEX alias in IDS")
assert(Flags.IDS.FLAG_HIDE_OAK_IN_HIS_LAB == 0x02B, "FLAG_HIDE_OAK_IN_HIS_LAB in IDS")
assert(Flags.IDS.HIDE_OAK_IN_HIS_LAB == 0x02B, "HIDE_OAK_IN_HIS_LAB in IDS")

assert(Flags.VAR_IDS.VAR_MAP_SCENE_PALLET_TOWN_OAK == 0x4050, "VAR_MAP_SCENE_PALLET_TOWN_OAK in VAR_IDS")
assert(Flags.VAR_IDS.MAP_SCENE_PALLET_TOWN_OAK == 0x4050, "MAP_SCENE_PALLET_TOWN_OAK alias in VAR_IDS")
assert(Flags.VAR_IDS.VAR_STARTER_MON == 0x4031, "VAR_STARTER_MON in VAR_IDS")
assert(Flags.VAR_IDS.STARTER_MON == 0x4031, "STARTER_MON alias in VAR_IDS")

assert(Flags.nameFor(0x820) == "FLAG_BADGE01_GET", "nameFor(0x820) resolves")
assert(Flags.nameFor(0x829) == "FLAG_SYS_POKEDEX_GET", "nameFor(0x829) resolves")
assert(Flags.varNameFor(0x4050) == "VAR_MAP_SCENE_PALLET_TOWN_OAK", "varNameFor(0x4050) resolves")
print("[PASS] Flags & VAR IDS, aliases, and name resolvers match")

print("=== [TEST 3] New Game hide flags and reset ===")
local store = Flags.newStore()
Flags.applyNewGameHideFlags(store)

assert(Flags.getFlag(store, nil, 0x02B) == true, "Lab Oak initially hidden (0x2B / 43)")
assert(Flags.getFlag(store, nil, 0x02C) == true, "Pallet Oak initially hidden (0x2C / 44)")
assert(Flags.getFlag(store, nil, 0x092) == true, "Pewter running shoes guy initially hidden (0x92 / 146)")
assert(Flags.getFlag(store, nil, 0x033) == true, "Bill human sea cottage initially hidden (0x33 / 51)")
assert(Flags.getFlag(store, nil, 0x035) == true, "Pokehouse Fuji initially hidden (0x35 / 53)")
assert(Flags.getFlag(store, nil, 0x0AE) == true, "Sabrina journals initially hidden (0xAE / 174)")
assert(Flags.getVar(store, nil, Flags.VAR_IDS.VAR_MASSAGE_COOLDOWN_STEP_COUNTER) == 500, "Massage cooldown step counter = 500")
print("[PASS] New game hide flags and initial vars apply correctly")

print("=== [TEST 4] Temporary flags and variables on map load ===")
Flags.setFlag(store, nil, Flags.IDS.SYS_POKEDEX_GET, true)
Flags.setFlag(store, nil, Flags.IDS.BADGE01_GET, true)
Flags.setFlag(store, nil, 0x01, true) -- FLAG_TEMP_1
Flags.setFlag(store, nil, 0x0A, true) -- FLAG_TEMP_A
Flags.setFlag(store, nil, 0x1F, true) -- FLAG_TEMP_1F

Flags.setVar(store, nil, Flags.VAR_IDS.VAR_STARTER_MON, 2) -- Charmander
Flags.setVar(store, nil, 0x4000, 42) -- VAR_TEMP_0
Flags.setVar(store, nil, 0x400F, 99) -- VAR_TEMP_F

Flags.onMapLoad(store)

assert(Flags.getFlag(store, nil, 0x01) == false, "FLAG_TEMP_1 wiped")
assert(Flags.getFlag(store, nil, 0x0A) == false, "FLAG_TEMP_A wiped")
assert(Flags.getFlag(store, nil, 0x1F) == false, "FLAG_TEMP_1F wiped")
assert(Flags.getVar(store, nil, 0x4000) == 0, "VAR_TEMP_0 wiped")
assert(Flags.getVar(store, nil, 0x400F) == 0, "VAR_TEMP_F wiped")

assert(Flags.getFlag(store, nil, Flags.IDS.SYS_POKEDEX_GET) == true, "Pokédex flag preserved")
assert(Flags.getFlag(store, nil, Flags.IDS.BADGE01_GET) == true, "Badge 1 preserved")
assert(Flags.getVar(store, nil, Flags.VAR_IDS.VAR_STARTER_MON) == 2, "Starter mon preserved")
print("[PASS] Map load wipes temp flags/vars and preserves permanent state")

print("=== [TEST 5] Badge helpers and bitmasks ===")
local bstore = Flags.newStore()
assert(Flags.countBadges(bstore) == 0, "0 badges initially")
assert(Flags.getBadgesMask(bstore) == 0, "mask is 0 initially")
assert(Flags.hasBadge(bstore, 1) == false, "no badge 1")
assert(Flags.hasBadge(bstore, "BOULDER") == false, "no Boulder badge")
assert(Flags.hasBadge(bstore, "FLASH") == false, "no Flash badge")

Flags.setBadge(bstore, 1, true)
Flags.setBadge(bstore, "CASCADE", true)

assert(Flags.hasBadge(bstore, 1) == true, "has badge 1")
assert(Flags.hasBadge(bstore, 2) == true, "has badge 2")
assert(Flags.hasBadge(bstore, "BOULDER") == true, "has Boulder badge")
assert(Flags.hasBadge(bstore, "CASCADE") == true, "has Cascade badge")
assert(Flags.hasBadge(bstore, "FLASH") == true, "has Flash permission (Badge 1)")
assert(Flags.hasBadge(bstore, "CUT") == true, "has Cut permission (Badge 2)")
assert(Flags.hasBadge(bstore, 3) == false, "no badge 3")
assert(Flags.countBadges(bstore) == 2, "2 badges obtained")
assert(Flags.getBadgesMask(bstore) == 3, "mask is 0b00000011 = 3")

Flags.setBadgesMask(bstore, 0xFF)
assert(Flags.countBadges(bstore) == 8, "all 8 badges obtained")
assert(Flags.getBadgesMask(bstore) == 255, "mask is 255")
for i = 1, 8 do
  assert(Flags.hasBadge(bstore, i) == true, "badge " .. i .. " is set")
end

Flags.setBadge(bstore, 4, false)
assert(Flags.hasBadge(bstore, 4) == false, "badge 4 cleared")
assert(Flags.countBadges(bstore) == 7, "7 badges remaining")
assert(Flags.getBadgesMask(bstore) == 255 - 8, "mask updated (247)")
print("[PASS] Badge counting, bitmasks, and name lookups work 1:1")

print("=== [TEST 6] Field moves badge gating ===")
local fstore = Flags.newStore()
local fctx = { store = fstore, ctx = Ctx.new() }

assert(FieldMoves.hasBadge(fctx, "FLASH") == false, "Flash requires badge 1")
assert(FieldMoves.hasBadge(fctx, "CUT") == false, "Cut requires badge 2")
assert(FieldMoves.hasBadge(fctx, "FLY") == false, "Fly requires badge 3")
assert(FieldMoves.hasBadge(fctx, "STRENGTH") == false, "Strength requires badge 4")
assert(FieldMoves.hasBadge(fctx, "SURF") == false, "Surf requires badge 5")
assert(FieldMoves.hasBadge(fctx, "ROCK_SMASH") == false, "Rock Smash requires badge 6")
assert(FieldMoves.hasBadge(fctx, "WATERFALL") == false, "Waterfall requires badge 7")

Flags.setBadge(fstore, 1, true)
assert(FieldMoves.hasBadge(fctx, "FLASH") == true, "Flash unlocked with Boulder Badge")
assert(FieldMoves.hasBadge(fctx, "CUT") == false, "Cut still locked")

Flags.setBadge(fstore, 2, true)
assert(FieldMoves.hasBadge(fctx, "CUT") == true, "Cut unlocked with Cascade Badge")

Flags.setBadge(fstore, 5, true)
assert(FieldMoves.hasBadge(fctx, "SURF") == true, "Surf unlocked with Soul Badge")
print("[PASS] Field moves correctly gate on corresponding badges")

print("=== [TEST 7] Story progression simulation ===")
local pstore = Flags.newStore()
Flags.applyNewGameHideFlags(pstore)

-- Step 1: Pallet Town Oak
assert(Flags.getVar(pstore, nil, Flags.VAR_IDS.MAP_SCENE_PALLET_TOWN_OAK) == 0, "Scene Oak = 0")
assert(Flags.getFlag(pstore, nil, Flags.IDS.HIDE_OAK_IN_PALLET_TOWN) == true, "Pallet Oak hidden")

Flags.setVar(pstore, nil, Flags.VAR_IDS.MAP_SCENE_PALLET_TOWN_OAK, 1)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_OAK_IN_PALLET_TOWN, false)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_OAK_IN_HIS_LAB, false)
assert(Flags.getFlag(pstore, nil, Flags.IDS.HIDE_OAK_IN_HIS_LAB) == false, "Oak visible in lab")

-- Step 2: Starter chosen
Flags.setVar(pstore, nil, Flags.VAR_IDS.VAR_STARTER_MON, 1)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_SQUIRTLE_BALL, true)
assert(Flags.getFlag(pstore, nil, Flags.IDS.HIDE_SQUIRTLE_BALL) == true, "Squirtle ball picked")

-- Step 3: Pokédex delivery
Flags.setFlag(pstore, nil, Flags.IDS.SYS_POKEDEX_GET, true)
assert(Flags.getFlag(pstore, nil, Flags.IDS.SYS_POKEDEX_GET) == true, "Pokédex obtained")

-- Step 4: Pewter Brock & Running Shoes
Flags.setBadge(pstore, 1, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM39_FROM_BROCK, true)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_PEWTER_CITY_RUNNING_SHOES_GUY, false)
assert(Flags.getFlag(pstore, nil, Flags.IDS.HIDE_PEWTER_CITY_RUNNING_SHOES_GUY) == false, "Running shoes guy visible")
Flags.setFlag(pstore, nil, Flags.IDS.SYS_B_DASH, true)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_PEWTER_CITY_RUNNING_SHOES_GUY, true)
assert(Flags.getFlag(pstore, nil, Flags.IDS.SYS_B_DASH) == true, "Running Shoes B-Dash enabled")

-- Step 5: Cerulean Misty & S.S. Ticket
Flags.setBadge(pstore, 2, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM03_FROM_MISTY, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_SS_TICKET, true)
assert(Flags.hasBadge(pstore, "CASCADE") == true, "Cascade Badge obtained")

-- Step 6: Vermilion Lt. Surge & Bike Voucher
Flags.setBadge(pstore, 3, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM34_FROM_SURGE, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_BIKE_VOUCHER, true)
assert(Flags.hasBadge(pstore, "THUNDER") == true, "Thunder Badge obtained")

-- Step 7: Celadon Erika & Rocket Hideout
Flags.setBadge(pstore, 4, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM19_FROM_ERIKA, true)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_LIFT_KEY, true)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_SILPH_SCOPE, true)
assert(Flags.hasBadge(pstore, "RAINBOW") == true, "Rainbow Badge obtained")

-- Step 8: Fuchsia Koga
Flags.setBadge(pstore, 5, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM06_FROM_KOGA, true)
assert(Flags.hasBadge(pstore, "SOUL") == true, "Soul Badge obtained")

-- Step 9: Saffron Sabrina & Silph Co.
Flags.setBadge(pstore, 6, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM04_FROM_SABRINA, true)
assert(Flags.hasBadge(pstore, "MARSH") == true, "Marsh Badge obtained")

-- Step 10: Cinnabar Blaine & Sevii Map
Flags.setBadge(pstore, 7, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM38_FROM_BLAINE, true)
Flags.setFlag(pstore, nil, Flags.IDS.SYS_SEVII_MAP_123, true)
assert(Flags.hasBadge(pstore, "VOLCANO") == true, "Volcano Badge obtained")

-- Step 11: Viridian Giovanni
Flags.setBadge(pstore, 8, true)
Flags.setFlag(pstore, nil, Flags.IDS.FLAG_GOT_TM26_FROM_GIOVANNI, true)
Flags.setFlag(pstore, nil, Flags.IDS.HIDE_VIRIDIAN_GIOVANNI, true)
assert(Flags.hasBadge(pstore, "EARTH") == true, "Earth Badge obtained")
assert(Flags.countBadges(pstore) == 8, "All 8 Badges obtained")

-- Step 12: Hall of Fame Clear & National Dex
Flags.setFlag(pstore, nil, Flags.IDS.SYS_GAME_CLEAR, true)
Flags.setFlag(pstore, nil, Flags.IDS.SYS_NATIONAL_DEX, true)
Flags.setVar(pstore, nil, Flags.VAR_IDS.VAR_NATIONAL_DEX, 0x6258)
Flags.setFlag(pstore, nil, Flags.IDS.SYS_CAN_LINK_WITH_RS, true)
assert(Flags.getFlag(pstore, nil, Flags.IDS.SYS_GAME_CLEAR) == true, "Game clear recorded")
assert(Flags.getFlag(pstore, nil, Flags.IDS.SYS_NATIONAL_DEX) == true, "National Dex unlocked")
print("[PASS] Full story progression from Pallet to Hall of Fame & Postgame passed")

print("=== [TEST 8] Object visibility with flags ===")
local ostore = Flags.newStore()
local octx = Ctx.new()
Space.store = ostore
Space.vm = { ctx = octx }

local oakInLab = { flag = Flags.IDS.HIDE_OAK_IN_HIS_LAB }
local itemBall = { flag = Flags.IDS.HIDE_BULBASAUR_BALL }
local normalNpc = { flag = 0 }

assert(Space.objectVisible(oakInLab) == true, "Oak in lab initially visible when flag false")
assert(Space.objectVisible(itemBall) == true, "Item ball visible when flag false")
assert(Space.objectVisible(normalNpc) == true, "Normal NPC with flag 0 always visible")

Flags.setFlag(ostore, nil, Flags.IDS.HIDE_OAK_IN_HIS_LAB, true)
assert(Space.objectVisible(oakInLab) == false, "Oak in lab hidden when flag true")

Flags.setFlag(ostore, nil, Flags.IDS.HIDE_OAK_IN_HIS_LAB, false)
assert(Space.objectVisible(oakInLab) == true, "Oak in lab visible when flag cleared")
print("[PASS] Object visibility dynamically reflects flag state")

print("ALL GAME3 EVENT FLAGS & STORY PROGRESSION TESTS PASSED 100%!")
