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

local store = { flags = {}, vars = {} }
local session = { store = store, map = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F", party = {} }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Events = require("src.core.game3.scripting.natives_events")
local Flags = require("src.core.game3.scripting.flags")

local function newCtx()
  return { specialVars = {} }
end

local function getVar(ctx, id) return Flags.getVar(store, ctx, id) end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

print("[test] 1. natives_*.lua auto-discovery")
local names = Natives.MODULE_NAMES
check(type(names) == "table" and #names >= 3, "MODULE_NAMES lists the topic modules")
local sorted = true
for i = 2, #names do
  if names[i - 1] > names[i] then sorted = false end
end
check(sorted, "MODULE_NAMES is sorted so a later module overrides an earlier id")
local seen = {}
for _, n in ipairs(names) do seen[n] = true end
check(seen["natives_events"], "discovery found natives_events")
check(seen["natives_queries"], "discovery found natives_queries")
check(seen["natives_seagallop"], "discovery found natives_seagallop")
local merged = true
for _, n in ipairs(names) do
  local mod = Natives.MODULES[n]
  for id in pairs((mod and mod.HANDLERS) or {}) do
    if Natives.ALLOW["special:" .. id] == nil then
      merged = false
      print("  missing merged id " .. string.format("0x%X", id) .. " from " .. n)
    end
  end
end
check(merged, "every discovered module's HANDLERS are merged into Natives.ALLOW")
check(Natives.Queries ~= nil and Natives.Seagallop ~= nil,
  "the legacy Natives.Queries / Natives.Seagallop handles still resolve")

local roster = {}
for _, n in ipairs(Natives.KNOWN_MODULES or {}) do roster[n] = true end
local onDisk, listed = {}, false
local pipe = io.popen('ls -1 "' .. Natives.MODULE_DIR .. '" 2>/dev/null')
if pipe then
  for line in pipe:lines() do
    local base = line:match("^(natives_[%w_]+)%.lua$")
    if base then
      listed = true
      onDisk[#onDisk + 1] = base
    end
  end
  pipe:close()
end
check(listed, "the scripting directory listing found natives_*.lua modules to check")
local complete = true
for _, base in ipairs(onDisk) do
  if not roster[base] then
    complete = false
    print("  " .. base .. " is missing from Natives.KNOWN_MODULES")
  end
end
check(complete, "every natives_*.lua on disk is in the known-name fallback roster")
local bound = true
for _, base in ipairs(Natives.KNOWN_MODULES or {}) do
  local okMod, mod = pcall(require, "src.core.game3.scripting." .. base)
  if okMod and type(mod) == "table" then
    for id in pairs(mod.HANDLERS or {}) do
      if Natives.ALLOW["special:" .. id] == nil then
        bound = false
        print("  " .. base .. " id " .. string.format("0x%X", id) .. " is unbound")
      end
    end
  end
end
check(bound, "every roster module's handlers are bound, listing or no listing")

print("[test] 2. ids match the 0-based def_special index of pokefirered/data/specials.inc")
local EXPECTED = {
  ShowFieldMessageStringVar4 = 0x8D,
  DrawWholeMapView = 0x8E,
  RockSmashWildEncounter = 0xAB,
  EnterSafariMode = 0xCD,
  ExitSafariMode = 0xCE,
  InitRoamer = 0x129,
  SetIcefallCaveCrackedIceMetatiles = 0x135,
  ShakeScreen = 0x136,
  SetPostgameFlagsUnusedSlot = 0x155,
  ForcePlayerOntoBike = 0x157,
  SampleResortGorgeousMonAndReward = 0x15D,
  ForcePlayerToStartSurfing = 0x161,
  DisableMsgBoxWalkaway = 0x171,
  SetPostgameFlags = 0x19A,
  DoDeoxysTriangleInteraction = 0x1AB,
  SetDeoxysTrianglePalette = 0x1AC,
  UpdateLoreleiDollCollection = 0x1B9,
  CreateEnemyEventMon = 0x1BB,
}
for name, id in pairs(EXPECTED) do
  eq(Std.SPECIAL[name], id, "Std.SPECIAL." .. name)
  check(Events.HANDLERS[id] ~= nil, name .. " has a handler")
end

print("[test] 3. no id collides with another Std.SPECIAL name")
local byId = {}
local collisions = 0
for name, id in pairs(Std.SPECIAL) do
  if byId[id] then
    collisions = collisions + 1
    print("  0x" .. string.format("%X", id) .. " claimed by " .. byId[id] .. " and " .. name)
  end
  byId[id] = name
end
eq(collisions, 0, "distinct id per special name")

print("[test] 4. no registered event special logs as unknown")
Natives.resetLog()
local logs = {}
local quietAdapters = { log = function(m) logs[#logs + 1] = m end }
for id in pairs(Events.HANDLERS) do
  local ctx = newCtx()
  local _, _, known = Natives.special(ctx, id, quietAdapters)
  check(known, string.format("special 0x%X dispatches to a handler", id))
end
eq(#logs, 0, "nothing reached the unknown-special log")

print("[test] 5. DrawWholeMapView forces the field redraw")
local FieldView = package.loaded["src.core.game3.field_view"]
if not FieldView then
  FieldView = { _nativeDirty = false }
  package.loaded["src.core.game3.field_view"] = FieldView
end
FieldView._nativeDirty = false
Events.HANDLERS[Std.SPECIAL.DrawWholeMapView](newCtx(), {})
check(FieldView._nativeDirty == true, "DrawWholeMapView marks the view dirty")

print("[test] 6. CreateEnemyEventMon stages the event mon for StartLegendaryBattle")
local Encounters = require("src.core.game3.encounters")
Encounters.takePendingWild()
local ctx6 = newCtx()
-- pokefirered/include/constants/species.h:256
setVar(ctx6, 0x8004, 249)
setVar(ctx6, 0x8005, 70)
setVar(ctx6, 0x8006, 0)
eq(Events.HANDLERS[Std.SPECIAL.CreateEnemyEventMon](ctx6, {}), false,
  "CreateEnemyEventMon does not yield")
local staged = Encounters.takePendingWild()
check(staged ~= nil, "a wild is pending after CreateEnemyEventMon")
eq(staged and staged.species, 249, "staged species")
eq(staged and staged.level, 70, "staged level")
eq(staged and staged.item, nil, "ITEM_NONE stages no held item")
check(staged and staged.fatefulEncounter == true, "the event mon is a fateful encounter")

local ctx6b = newCtx()
-- pokefirered/include/constants/species.h:419
setVar(ctx6b, 0x8004, 410)
setVar(ctx6b, 0x8005, 30)
setVar(ctx6b, 0x8006, 175)
Events.HANDLERS[Std.SPECIAL.CreateEnemyEventMon](ctx6b, {})
local staged2 = Encounters.takePendingWild()
eq(staged2 and staged2.item, 175, "a non-zero item is staged as the held item")

print("[test] 7. StartLegendaryBattle now finds the event mon")
local ctx7 = newCtx()
setVar(ctx7, 0x8004, 249)
setVar(ctx7, 0x8005, 70)
setVar(ctx7, 0x8006, 0)
Events.HANDLERS[Std.SPECIAL.CreateEnemyEventMon](ctx7, {})
local startedWith
local adapters7 = {
  startWildBattle = function(foe, cb, opts)
    startedWith = { foe = foe, opts = opts }
    cb("win")
  end,
}
Natives.special(ctx7, Std.SPECIAL.StartLegendaryBattle, adapters7)
check(startedWith ~= nil, "StartLegendaryBattle started a battle")
eq(startedWith and startedWith.foe.species, 249, "the legendary battle uses the event mon")
check(startedWith and startedWith.opts.legendary == true, "battle flagged legendary")

print("[test] 8. SetIcefallCaveCrackedIceMetatiles restores only cracked tiles")
local Field = require("src.core.game3.field")
check(type(Field.setMetatile) == "function", "Field.setMetatile is the real entry point")
local realSetMetatile = Field.setMetatile
local writes = {}
Field.setMetatile = function(x, y, mid, impassable)
  writes[#writes + 1] = { x = x, y = y, mid = mid, impassable = impassable }
end
store.flags = {}
local ctx8 = newCtx()
Events.HANDLERS[Std.SPECIAL.SetIcefallCaveCrackedIceMetatiles](ctx8, {})
eq(#writes, 0, "no cracked ice with no temp flags set")
Flags.setFlag(store, ctx8, 1, true)
Flags.setFlag(store, ctx8, 4, true)
Events.HANDLERS[Std.SPECIAL.SetIcefallCaveCrackedIceMetatiles](ctx8, {})
eq(#writes, 2, "two cracked ice tiles restored")
eq(writes[1] and writes[1].x, 8, "first cracked tile x")
eq(writes[1] and writes[1].y, 3, "first cracked tile y")
eq(writes[2] and writes[2].x, 8, "fourth cracked tile x")
eq(writes[2] and writes[2].y, 9, "fourth cracked tile y")
eq(writes[1] and writes[1].mid, 0x35A, "METATILE_SeafoamIslands_CrackedIce")
eq(writes[1] and writes[1].impassable, false, "cracked ice is not written impassable")
Field.setMetatile = realSetMetatile
store.flags = {}

print("[test] 9. ForcePlayerOntoBike / ForcePlayerToStartSurfing set avatar state")
local Player = require("src.core.game3.player")
Player.biking, Player.surfing, Player.surfHopping = false, false, false
Events.HANDLERS[Std.SPECIAL.ForcePlayerOntoBike](newCtx(), {})
check(Player.biking == true, "ForcePlayerOntoBike mounts the bike")
Events.HANDLERS[Std.SPECIAL.ForcePlayerToStartSurfing](newCtx(), {})
check(Player.surfing == true, "ForcePlayerToStartSurfing puts the player on the water")
check(Player.biking == false, "surfing clears the bike")
check(Player.surfHopping == false, "the forced transition skips the hop")
Player.biking, Player.surfing = false, false
Player.surfing = true
Events.HANDLERS[Std.SPECIAL.ForcePlayerOntoBike](newCtx(), {})
check(Player.biking == false, "a surfing player is not forced onto the bike")
Player.surfing = false

print("[test] 10. RockSmashWildEncounter")
local ctx10 = newCtx()
local savedRollRocks = Encounters.rollRocks
Encounters.rollRocks = nil
Events.HANDLERS[Std.SPECIAL.RockSmashWildEncounter](ctx10, {})
eq(getVar(ctx10, 0x800D), 0, "no rollRocks means VAR_RESULT stays FALSE")
local askedMap
Encounters.rollRocks = function(mapId)
  askedMap = mapId
  return { species = 74, level = 15 }
end
local rockFoe
local adapters10 = {
  startWildBattle = function(foe, cb) rockFoe = foe; cb("win") end,
}
local ctx10b = newCtx()
Events.HANDLERS[Std.SPECIAL.RockSmashWildEncounter](ctx10b, adapters10)
eq(askedMap, session.map, "rollRocks is asked about the current map")
eq(getVar(ctx10b, 0x800D), 1, "a rolled encounter sets VAR_RESULT to TRUE")
check(rockFoe ~= nil and rockFoe.wildScripted == true, "the rock smash battle is a scripted wild")
local ctx10c = newCtx()
Encounters.rollRocks = function() return nil end
Events.HANDLERS[Std.SPECIAL.RockSmashWildEncounter](ctx10c, adapters10)
eq(getVar(ctx10c, 0x800D), 0, "an empty roll sets VAR_RESULT to FALSE")
Encounters.rollRocks = savedRollRocks

print("[test] 11. Safari specials drive game3/safari.lua when it exists")
local savedSafari = package.loaded["src.core.game3.safari"]
local calls = {}
package.loaded["src.core.game3.safari"] = {
  enter = function() calls[#calls + 1] = "enter" end,
  exit = function() calls[#calls + 1] = "exit" end,
}
Events.HANDLERS[Std.SPECIAL.EnterSafariMode](newCtx(), {})
Events.HANDLERS[Std.SPECIAL.ExitSafariMode](newCtx(), {})
eq(table.concat(calls, ","), "enter,exit", "EnterSafariMode / ExitSafariMode call Safari")
package.loaded["src.core.game3.safari"] = { }
local okNoApi = pcall(function()
  Events.HANDLERS[Std.SPECIAL.EnterSafariMode](newCtx(), {})
  Events.HANDLERS[Std.SPECIAL.ExitSafariMode](newCtx(), {})
end)
check(okNoApi, "the safari seam is safe while game3/safari.lua has no enter/exit")
package.loaded["src.core.game3.safari"] = savedSafari

print("[test] 12. SetPostgameFlags")
session.gcnLinkFlags = 0
session.specialSaveWarpFlags = 0
Events.HANDLERS[Std.SPECIAL.SetPostgameFlags](newCtx(), {})
eq(session.gcnLinkFlags, 0x800E, "gcnLinkFlags bits 1,2,3,15")
eq(session.specialSaveWarpFlags, 0x80, "CHAMPION_SAVEWARP")
Events.HANDLERS[Std.SPECIAL.SetPostgameFlagsUnusedSlot](newCtx(), {})
eq(session.gcnLinkFlags, 0x800E, "the duplicate def_special slot runs the same handler")

print("[test] 13. cited no-ops return without yielding")
local NOOPS = {
  "ShowFieldMessageStringVar4", "ShakeScreen", "InitRoamer",
  "SampleResortGorgeousMonAndReward", "DisableMsgBoxWalkaway",
  "UpdateLoreleiDollCollection",
}
for _, name in ipairs(NOOPS) do
  local ctx = newCtx()
  local yield = Events.HANDLERS[Std.SPECIAL[name]](ctx, {})
  eq(yield, false, name .. " does not yield")
  eq(getVar(ctx, 0x800D), 0, name .. " leaves VAR_RESULT at 0")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
