#!/usr/bin/env luajit
-- pokefirered/src/item_use.c:614 CanUseEscapeRopeOnCurrMap
-- pokefirered/src/item_use.c:337 FieldUseFunc_CoinCase
-- pokefirered/src/item_use.c:348 FieldUseFunc_PowderJar
-- pokefirered/src/party_menu.c:1511 GetMonNickname

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

local function finish()
  if failed > 0 then
    print(failed .. " CHECK(S) FAILED")
    os.exit(1)
  end
  print("ALL STITCHMAP ITEM TESTS PASSED")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
Cache.mountOrSkip("stitchmap item + field-move seams", "map_tree/census.json")

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local ItemsData = require("src.core.game3.items_data")
local ItemUse = require("src.core.game3.item_use")
local Bag = require("src.core.game3.bag")
local Party = require("src.core.game3.party")
local Pokemon = require("src.core.game3.pokemon")
local FieldMoves = require("src.core.game3.field_moves")
local Runtime = require("src.core.game3.runtime")

local ITEM_ESCAPE_ROPE = 85
local ITEM_COIN_CASE = 260 -- pokefirered/include/constants/items.h:271
local ITEM_POWDER_JAR = 372 -- pokefirered/include/constants/items.h:444
local ITEM_MACH_BIKE = 259 -- pokefirered/include/constants/items.h:270
local ITEM_ACRO_BIKE = 272 -- pokefirered/include/constants/items.h:283
local ITEM_POKEBLOCK_CASE = 273 -- pokefirered/include/constants/items.h:284
local ITEM_BICYCLE = 360 -- pokefirered/include/constants/items.h:432

local game = { data = {} }
Dataset.hydrate(game)
Runtime._game = game
Runtime._mod = nil

local MAPS = {
  { pret = "PalletTown", escape = false, bike = true },
  { pret = "PalletTown_PlayersHouse_1F", escape = false, bike = false },
  { pret = "Route1", escape = false, bike = true },
  { pret = "ViridianCity_PokemonCenter_1F", escape = false, bike = false },
  { pret = "ViridianCity_Gym", escape = false, bike = false },
  { pret = "PewterCity_Museum_1F", escape = false, bike = false },
  { pret = "CeladonCity_GameCorner", escape = false, bike = false },
  { pret = "SafariZone_Center", escape = false, bike = true },
  { pret = "MtMoon_1F", escape = true, bike = true },
  { pret = "RockTunnel_1F", escape = true, bike = true },
  { pret = "ViridianForest", escape = true, bike = true },
  { pret = "SaffronCity_Gym", escape = true, bike = false },
  { pret = "SilphCo_1F", escape = true, bike = false },
  { pret = "SeafoamIslands_B4F", escape = true, bike = true },
  { pret = "VictoryRoad_1F", escape = true, bike = true },
  { pret = "PokemonTower_1F", escape = true, bike = false },
}

print("[test] 1. the map header carries pret's allow_escaping and allow_cycling")
local resolved = 0
for _, row in ipairs(MAPS) do
  local id = MapCatalog.pretToEngine(row.pret)
  local def = id and game.data.maps[id]
  if not def then
    check(false, row.pret .. " resolves to a map the cache has")
  else
    resolved = resolved + 1
    row.id = id
    eq((tonumber(def.allowEscaping) or 0) ~= 0, row.escape, row.pret .. ".allowEscaping")
    eq((tonumber(def.bikingAllowed) or 0) ~= 0, row.bike, row.pret .. ".bikingAllowed")
  end
end
eq(resolved, #MAPS, "every pret map in the table resolved")

print("[test] 2. ESCAPE ROPE is legal exactly where gMapHeader.allowEscaping is set")
for _, row in ipairs(MAPS) do
  if row.id then
    local session = {
      name = "RED", map = row.id, party = {}, flags = {}, vars = {},
      healMap = "FR_PLAYERS_HOUSE_1F", healX = 8, healY = 5,
      bag = Bag.new and Bag.new() or {},
    }
    Bag.add(session.bag, ITEM_ESCAPE_ROPE, 1)
    local before = Bag.get(session.bag, ITEM_ESCAPE_ROPE)
    local ok, kind = ItemUse.useField(session, session.bag, ITEM_ESCAPE_ROPE, nil)
    eq(kind, "escape", row.pret .. " routes ESCAPE ROPE to the escape handler")
    eq(ok == true, row.escape, row.pret .. " ESCAPE ROPE accepted")
    local after = Bag.get(session.bag, ITEM_ESCAPE_ROPE)
    eq(after, row.escape and (before - 1) or before,
      row.pret .. " ESCAPE ROPE consumed only when it was usable")
  end
end

do
  local session = {
    name = "RED", map = "FR_NOT_A_REAL_MAP", party = {}, flags = {}, vars = {},
    healMap = "FR_PLAYERS_HOUSE_1F", bag = Bag.new and Bag.new() or {},
  }
  Bag.add(session.bag, ITEM_ESCAPE_ROPE, 1)
  local ok = ItemUse.useField(session, session.bag, ITEM_ESCAPE_ROPE, nil)
  eq(ok, false, "a map with no header refuses ESCAPE ROPE")
end

print("[test] 3. the bike follows gMapHeader.bikingAllowed")
for _, row in ipairs(MAPS) do
  if row.id then
    local session = {
      name = "RED", map = row.id, party = {}, flags = {}, vars = {},
      bag = Bag.new and Bag.new() or {},
    }
    Bag.add(session.bag, ITEM_BICYCLE, 1)
    local ok, kind = ItemUse.useField(session, session.bag, ITEM_BICYCLE, nil)
    eq(kind, "bike", row.pret .. " routes the BICYCLE to the bike handler")
    eq(ok == true, row.bike, row.pret .. " BICYCLE accepted")
  end
end

print("[test] 4. COIN CASE and POWDER JAR are field-use items, not refused key items")
eq(ItemsData.fieldUseKind(ITEM_COIN_CASE), "coin_case", "COIN CASE field-use kind")
eq(ItemsData.fieldUseKind(ITEM_POWDER_JAR), "powder_jar", "POWDER JAR field-use kind")
eq(ItemsData.fieldUseKind(ITEM_MACH_BIKE), "bike", "MACH BIKE field-use kind")
eq(ItemsData.fieldUseKind(ITEM_ACRO_BIKE), "bike", "ACRO BIKE field-use kind")
eq(ItemsData.fieldUseKind(ITEM_BICYCLE), "bike", "BICYCLE field-use kind")
eq(ItemsData.fieldUseKind(ITEM_POKEBLOCK_CASE), "key",
  "the POKEBLOCK CASE leftover at 273 is still an unusable key item")
eq(ItemUse.needsPartyTarget(ITEM_COIN_CASE), false, "COIN CASE needs no party target")
eq(ItemUse.needsPartyTarget(ITEM_POWDER_JAR), false, "POWDER JAR needs no party target")

do
  local session = {
    name = "RED", map = MAPS[1].id, party = {}, flags = {}, vars = {},
    bag = Bag.new and Bag.new() or {},
  }
  Bag.add(session.bag, ITEM_COIN_CASE, 1)
  Bag.Coins.set(session, 1234)
  local ok, kind, text = ItemUse.useField(session, session.bag, ITEM_COIN_CASE, nil)
  check(ok == true, "COIN CASE is usable in the field")
  eq(kind, "coin_case", "COIN CASE reports its own kind")
  -- pokefirered/src/strings.c:193 gText_CoinCase
  check(type(text) == "string" and text:find("Your COINS:", 1, true) == 1,
    "the message is gText_CoinCase: " .. tostring(text))
  check(type(text) == "string" and text:find("1234", 1, true) ~= nil,
    "it prints the live coin count")
  eq(Bag.get(session.bag, ITEM_COIN_CASE), 1, "the COIN CASE is not consumed")

  Bag.Coins.set(session, 0)
  local _, _, zero = ItemUse.useField(session, session.bag, ITEM_COIN_CASE, nil)
  check(type(zero) == "string" and zero:find("0", 1, true) ~= nil,
    "zero coins print as 0, not blank: " .. tostring(zero))
end

do
  local session = {
    name = "RED", map = MAPS[1].id, party = {}, flags = {}, vars = {},
    bag = Bag.new and Bag.new() or {},
  }
  Bag.add(session.bag, ITEM_POWDER_JAR, 1)
  local ok, kind, text = ItemUse.useField(session, session.bag, ITEM_POWDER_JAR, nil)
  check(ok == true, "POWDER JAR is usable in the field")
  eq(kind, "powder_jar", "POWDER JAR reports its own kind")
  -- pokefirered/src/strings.c:202 gText_PowderQty
  check(type(text) == "string" and text:find("POWDER QTY:", 1, true) == 1,
    "the message is gText_PowderQty: " .. tostring(text))
  eq(Bag.get(session.bag, ITEM_POWDER_JAR), 1, "the POWDER JAR is not consumed")
end

print("[test] 5. field-move text names the mon Party.giveMon actually made")
do
  local session = { name = "RED", map = MAPS[1].id, party = {}, flags = {}, vars = {} }
  Party.giveMon(session, 1, 15)
  local mon = session.party[1]
  check(type(mon) == "table", "Party.giveMon put a mon in the party")
  eq(mon.nickname, "", "Party.giveMon leaves the nickname empty, as the engine does")

  local name = FieldMoves.getMonName(mon)
  check(name ~= "" and name ~= nil, "getMonName is not the empty string")
  eq(name, Pokemon.displayMonName(mon), "getMonName agrees with Pokemon.displayMonName")

  local flags = {}
  flags[FieldMoves.BADGE_FLAGS.ROCK_SMASH] = true
  local ctx = {
    session = { flags = flags },
    mon = mon,
    party = session.party,
    facingObject = { gfx = FieldMoves.GFX_IDS.ROCK_SMASH_ROCK },
  }
  local res = FieldMoves.rockSmashFromMenu(ctx)
  check(res.ok == true, "ROCK SMASH from the party menu is accepted")
  -- pokefirered/data/scripts/field_moves.inc:77 EventScript_FldEffRockSmash
  check(res.text == nil, "the party-menu ROCK SMASH prints no line")
  -- pokefirered/data/scripts/field_moves.inc:12
  local line = FieldMoves.monText("USED_MOVE", FieldMoves.getMonName(mon), FieldMoves.MOVES.ROCK_SMASH)
  check(line:find("^ used") == nil, "the line does not start with a blank name: " .. tostring(line))
  check(line:find(name, 1, true) == 1, "the line leads with the mon's name: " .. tostring(line))

  Party.giveMon(session, 4, 15, "SLUGGY")
  local nicked = session.party[2]
  eq(FieldMoves.getMonName(nicked), "SLUGGY", "a real nickname still wins")

  local cutFlags = {}
  cutFlags[FieldMoves.BADGE_FLAGS.CUT] = true
  local cut = FieldMoves.cutFromMenu({
    session = { flags = cutFlags },
    mon = mon,
    party = session.party,
    facingObject = { gfx = FieldMoves.GFX_IDS.CUT_TREE },
  })
  check(cut.ok == true, "CUT from the party menu is accepted")
  -- pokefirered/data/scripts/field_moves.inc:19 EventScript_FldEffCut
  check(cut.text == nil, "the party-menu CUT prints no line")
end

finish()
