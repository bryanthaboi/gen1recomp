#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = { plain = function(key) return key end, box = function(key) return key end }

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

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] " .. tostring(Cache.reason))
  os.exit(0)
end

local Dataset = require("src.core.game3.dataset")
local DEFS = Dataset.buildMaps()
local MAPS = {
  PalletTown = DEFS.FR_PALLET_TOWN,
  PalletTown_PlayersHouse_1F = DEFS.FR_PLAYERS_HOUSE_1F,
  ViridianForest = DEFS.FR_VIRIDIAN_FOREST,
  MtMoon_1F = DEFS.FR_MT_MOON_1F,
  RockTunnel_1F = DEFS.FR_ROCK_TUNNEL_1F,
}
for name, def in pairs(MAPS) do
  if not def then
    print("[skip] the cache has no live map def for " .. name)
    os.exit(0)
  end
end

-- pokefirered/src/item_use.c:614
print("[test] 0. the live map def carries both header fields")
check(MAPS.MtMoon_1F.cave == 0, "dataset.lua puts Mt Moon's requires_flash on the def")
check(MAPS.MtMoon_1F.allowEscaping == 1, "and its allow_escaping too")

local currentMap = MAPS.PalletTown
package.loaded["src.core.game3.map"] = {
  currentDef = function() return currentMap end,
}
package.loaded["src.core.game3.collision"] = {
  isWater = function() return false end,
  isGrass = function() return false end,
  behavior = function() return 0 end,
}
package.loaded["src.core.game3.objects"] = {
  at = function() return nil end,
}
package.loaded["src.core.game3.scripting.space"] = { store = nil }

local executed = nil
package.loaded["src.core.game3.field"] = {
  executeFieldMove = function(payload) executed = payload end,
}

local PartyMenu = require("src.ui.game3.party_menu")
local FieldMoves = require("src.core.game3.field_moves")

local seenCtx = nil
local realFromMenu = FieldMoves.fromMenu
FieldMoves.fromMenu = function(moveId, ctx)
  seenCtx = ctx
  return realFromMenu(moveId, ctx)
end

local function make_input(pressed)
  return {
    wasPressed = function(_, key) return pressed[key] == true end,
    isDown = function(_, key) return pressed[key] == true end,
  }
end

local function press(key)
  PartyMenu.handleInput(make_input({ [key] = true }))
end

local function make_mon(moves)
  return {
    species = 6,
    level = 40,
    hp = 100,
    maxHp = 100,
    stats = { hp = 100 },
    moves = moves,
    pp = { 10, 10, 10, 10 },
  }
end

local function use_field_move(mapDef, moveName, badges)
  currentMap = mapDef
  seenCtx, executed = nil, nil
  PartyMenu.show({ make_mon({ moveName }) }, nil, {
    session = { badges = badges or {} },
  })
  press("a")
  local target = nil
  for i, label in ipairs(PartyMenu.ACTIONS) do
    if label == moveName:gsub("_", " ") then target = i end
  end
  if not target then
    PartyMenu.close()
    return nil, nil, "no action row for " .. moveName
  end
  while PartyMenu.actionCursor ~= target do
    press("down")
  end
  press("a")
  local refusal = PartyMenu._messageText
  local ctx = seenCtx
  local ran = executed
  if PartyMenu.open then PartyMenu.close() end
  return ctx, ran, refusal
end

print("[test] 1. the field-move context carries the map header fields")
local ctx = use_field_move(MAPS.PalletTown, "FLY", { FLY = true })
eq(ctx and ctx.mapType, 1, "PalletTown ctx.mapType is MAP_TYPE_TOWN")
check(ctx and ctx.mapType ~= nil, "ctx.mapType is not nil (mapDef.mapType, not mapDef.type)")
eq(ctx and ctx.isCave, false, "PalletTown ctx.isCave is false")
eq(ctx and ctx.canEscapeRope, false, "PalletTown ctx.canEscapeRope is false")

ctx = use_field_move(MAPS.RockTunnel_1F, "DIG", {})
eq(ctx and ctx.mapType, 4, "RockTunnel ctx.mapType is MAP_TYPE_UNDERGROUND")
eq(ctx and ctx.isCave, true, "RockTunnel ctx.isCave is read out of header.json")
eq(ctx and ctx.canEscapeRope, true, "RockTunnel ctx.canEscapeRope is read out of header.json")

ctx = use_field_move(MAPS.ViridianForest, "DIG", {})
eq(ctx and ctx.canEscapeRope, true, "ViridianForest ctx.canEscapeRope is true (allowEscaping 1)")

print("[test] 2. Fly is accepted outdoors and refused indoors")
local _, ran, refusal = use_field_move(MAPS.PalletTown, "FLY", { FLY = true })
eq(ran and ran.action, "fly", "FLY outdoors reaches Field.executeFieldMove")
eq(refusal, nil, "FLY outdoors prints no refusal")

_, ran, refusal = use_field_move(MAPS.PalletTown_PlayersHouse_1F, "FLY", { FLY = true })
eq(ran, nil, "FLY indoors does not execute")
check(refusal ~= nil, "FLY indoors prints a refusal (" .. tostring(refusal) .. ")")

print("[test] 3. Teleport is accepted outdoors and refused indoors")
_, ran, refusal = use_field_move(MAPS.PalletTown, "TELEPORT", {})
eq(ran and ran.action, "teleport", "TELEPORT outdoors reaches Field.executeFieldMove")

_, ran, refusal = use_field_move(MAPS.PalletTown_PlayersHouse_1F, "TELEPORT", {})
eq(ran, nil, "TELEPORT indoors does not execute")
check(refusal ~= nil, "TELEPORT indoors prints a refusal")

print("[test] 4. Dig follows the map header, not a nil map type")
_, ran, refusal = use_field_move(MAPS.MtMoon_1F, "DIG", {})
eq(ran and ran.action, "dig", "DIG in Mt Moon reaches Field.executeFieldMove")

_, ran, refusal = use_field_move(MAPS.PalletTown_PlayersHouse_1F, "DIG", {})
eq(ran, nil, "DIG indoors (allowEscaping 0) does not execute")
check(refusal ~= nil, "DIG indoors prints a refusal")

_, ran, refusal = use_field_move(MAPS.PalletTown, "DIG", {})
eq(ran, nil, "DIG in Pallet Town (allowEscaping 0) does not execute")

-- pokefirered/src/item_use.c:614
print("[test] 4b. the ctx reads the def only, never header.json")
local stripped = {}
for k, v in pairs(MAPS.RockTunnel_1F) do stripped[k] = v end
stripped.cave, stripped.allowEscaping = nil, nil
ctx = use_field_move(stripped, "DIG", {})
eq(ctx and ctx.isCave, false, "a def with no cave field reads false, not the cached header")
eq(ctx and ctx.canEscapeRope, false, "and no allowEscaping field reads false too")
eq(stripped.cave, nil, "the def is not stamped from header.json")
eq(stripped.allowEscaping, nil, "neither field is stamped")

print("[test] 5. an accepted field move tears the start menu down too")
-- pokefirered/src/party_menu.c:3958
local StartMenu = require("src.ui.game3.start_menu")
currentMap = MAPS.PalletTown
local function via_start_menu(moveName, badges)
  seenCtx, executed = nil, nil
  local session = { badges = badges or {}, party = { make_mon({ moveName }) } }
  StartMenu.show({ session = session })
  for _ = 1, #StartMenu.ENTRIES do
    local e = StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "pokemon" then break end
    StartMenu.move(1)
  end
  StartMenu.confirm()
  press("a")
  local target = nil
  for i, label in ipairs(PartyMenu.ACTIONS) do
    if label == moveName then target = i end
  end
  while target and PartyMenu.actionCursor ~= target do
    press("down")
  end
  press("a")
end

via_start_menu("TELEPORT", {})
eq(executed and executed.action, "teleport", "TELEPORT from the start menu executes")
eq(StartMenu.isOpen(), false, "the start menu is gone when the move runs")
eq(PartyMenu.isOpen(), false, "the party menu is gone when the move runs")

via_start_menu("FLY", {})
eq(executed, nil, "FLY without the Thunder Badge is refused")
eq(StartMenu.isOpen(), true, "a refusal leaves the start menu underneath")
if PartyMenu.open then PartyMenu.close() end
if StartMenu.isOpen() then StartMenu.close(true) end

print("[test] 6. a cancelled fly map comes back to the party menu")
-- pokefirered/src/region_map.c:4019
do
  local RegionMap = require("src.ui.game3.region_map")
  currentMap = MAPS.PalletTown
  local _, ran = use_field_move(MAPS.PalletTown, "FLY", { FLY = true })
  eq(ran and ran.action, "fly", "FLY was accepted, so the party menu closed for the fly map")
  eq(PartyMenu.isOpen(), false, "the party menu is closed while the fly map is up")
  RegionMap.show({ mode = "fly", mapType = 1, session = { map = "PALLET_TOWN" } })
  RegionMap.handleInput({
    wasPressed = function(_, k) return k == "b" end,
    isDown = function() return false end,
  })
  eq(RegionMap.isOpen(), false, "B closed the fly map")
  eq(PartyMenu.isOpen(), true, "B on the fly map lands back in the party menu")
  PartyMenu.close()

  local _, ran2 = use_field_move(MAPS.PalletTown, "FLY", { FLY = true })
  eq(ran2 and ran2.action, "fly", "FLY accepted a second time")
  RegionMap.show({ mode = "fly", mapType = 1, session = { map = "PALLET_TOWN" } })
  RegionMap.close(true)
  eq(PartyMenu.isOpen(), false, "a picked destination does not reopen the party menu")
end

FieldMoves.fromMenu = realFromMenu

if failed > 0 then
  print(string.format("\n%d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("\nALL PARTY FIELD-MOVE CONTEXT TESTS PASSED")
