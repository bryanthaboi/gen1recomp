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

local Natives = require("src.core.game3.scripting.natives")
local Std = require("src.core.game3.scripting.stdscripts")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")

local SPECIAL_SET_TRASH_CANS = 347
local VAR_SWITCH1, VAR_SWITCH2 = 0x8004, 0x8005
local VAR_TEMP_0, VAR_TEMP_1 = 0x4000, 0x4001
local FLAG_TEMP_1 = 0x01
local FLAG_FOUND_BOTH = 0x264

print("[test] 1. the special id is the pret specials.inc index")
check(Std.SPECIAL.SetVermilionTrashCans == SPECIAL_SET_TRASH_CANS,
  "Std.SPECIAL.SetVermilionTrashCans == 347")
check(type(Natives.ALLOW["special:" .. SPECIAL_SET_TRASH_CANS]) == "function",
  "special 347 has a handler in Natives.ALLOW")

print("[test] 2. every (first, roll) pair matches pokefirered/src/field_specials.c:552")
local function expected(first, roll)
  local second = first
  local n, pick
  if first == 1 then
    n = 2; pick = { 1, 5 }
  elseif first >= 2 and first <= 4 then
    n = 3; pick = { 1, 5, -1 }
  elseif first == 5 then
    n = 2; pick = { 5, -1 }
  elseif first == 6 then
    n = 3; pick = { -5, 1, 5 }
  elseif first >= 7 and first <= 9 then
    n = 4; pick = { -5, 1, 5, -1 }
  elseif first == 10 then
    n = 3; pick = { -5, 5, -1 }
  elseif first == 11 then
    n = 2; pick = { -5, 1 }
  elseif first >= 12 and first <= 14 then
    n = 3; pick = { -5, 1, -1 }
  else
    n = 2; pick = { -5, -1 }
  end
  second = (second + pick[(roll % n) + 1]) % 65536
  if second > 15 then
    if first % 5 == 1 then
      second = first + 1
    elseif first % 5 == 0 then
      second = first - 1
    else
      second = first + 1
    end
  end
  return second, n
end

local rollTrashCans = Natives.setVermilionTrashCans
if type(rollTrashCans) ~= "function" then
  failed = failed + 1
  print("[FAIL] Natives.setVermilionTrashCans is missing")
  rollTrashCans = function() return 0, 0 end
end

local bad = 0
local covered = 0
for first = 1, 15 do
  local _, n = expected(first, 0)
  for roll = 0, n - 1 do
    local calls = 0
    local function fakeRandom()
      calls = calls + 1
      if calls == 1 then return first - 1 end
      return roll
    end
    local gotFirst, gotSecond = rollTrashCans(fakeRandom)
    local wantSecond = expected(first, roll)
    covered = covered + 1
    if gotFirst ~= first or gotSecond ~= wantSecond then
      bad = bad + 1
      print(string.format("  [diff] first=%d roll=%d got=(%s,%s) want=(%d,%d)",
        first, roll, tostring(gotFirst), tostring(gotSecond), first, wantSecond))
    end
  end
end
check(covered == 44, "all 15 cases and every neighbour roll exercised (" .. covered .. ")")
check(bad == 0, "the port reproduces the C switch on every pair")

print("[test] 3. both switch cans are always real, distinct, adjacent cans")
local outOfRange, sameCan, notAdjacent = 0, 0, 0
for first = 1, 15 do
  local _, n = expected(first, 0)
  for roll = 0, n - 1 do
    local calls = 0
    local a, b = rollTrashCans(function()
      calls = calls + 1
      if calls == 1 then return first - 1 end
      return roll
    end)
    if b < 1 or b > 15 then outOfRange = outOfRange + 1 end
    if a == b then sameCan = sameCan + 1 end
    local d = math.abs(a - b)
    if d ~= 1 and d ~= 5 then notAdjacent = notAdjacent + 1 end
  end
end
check(outOfRange == 0, "the second can is always in 1..15")
check(sameCan == 0, "the second can is never the first can")
check(notAdjacent == 0, "the second can is always one step away in the 5x3 grid")

print("[test] 4. the special writes VAR_0x8004 / VAR_0x8005")
local Rng = require("src.core.game3.rng")
Rng._value = 0
local seenFirst = {}
for i = 1, 200 do
  local ctx = Ctx.new and Ctx.new() or { specialVars = {} }
  ctx.specialVars = ctx.specialVars or {}
  Natives.special(ctx, SPECIAL_SET_TRASH_CANS)
  local a = Flags.getVar(nil, ctx, VAR_SWITCH1)
  local b = Flags.getVar(nil, ctx, VAR_SWITCH2)
  if a < 1 or a > 15 or b < 1 or b > 15 or a == b then
    check(false, string.format("roll %d produced (%s,%s)", i, tostring(a), tostring(b)))
    break
  end
  seenFirst[a] = true
end
local distinct = 0
for _ in pairs(seenFirst) do distinct = distinct + 1 end
check(distinct >= 10,
  "200 rolls through the game3 RNG cover most of the 15 cans (" .. distinct .. ")")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua")
if not cacheRoot then
  print("[skip] game3_vermilion_trash_cans_test: " .. tostring(Cache.reason))
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local ExtractScripts = require("src.import.gba.extract_scripts")
local Space = require("src.core.game3.scripting.space")
local Objects = require("src.core.game3.objects")
local Field = require("src.core.game3.field")

Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })
check(Space.bundle ~= nil, "script bundle loads")

local GYM = "FR_VERMILION_CITY_GYM"
local gym = Space.bundle.events[GYM]
check(gym ~= nil, "the gym is in the event bundle")

print("[test] 5. the gym carries both of its map scripts")
local ms = gym and gym.mapScripts or {}
check(type(ms.onTransition) == "string", "MAP_SCRIPT_ON_TRANSITION survived import")
check(type(ms.onLoad) == "string", "MAP_SCRIPT_ON_LOAD survived import")

print("[test] 6. ON_TRANSITION really calls special 347")
local function scriptCalls347(key, depth)
  depth = (depth or 0) + 1
  if depth > 6 or type(key) ~= "string" then return false end
  local rows = Space.bundle.scripts[key]
  if not rows then return false end
  for _, row in ipairs(rows) do
    if row.op == "special" and tonumber(row.id or row[1]) == SPECIAL_SET_TRASH_CANS then
      return true
    end
    local k = row.target or row.script
    if type(k) == "string" and k:sub(1, 3) == "g3:" and scriptCalls347(k, depth) then
      return true
    end
  end
  return false
end
check(scriptCalls347(ms.onTransition), "the ON_TRANSITION chain reaches special 347")

local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Collision = require("src.core.game3.collision")

local CITY = "FR_VERMILION_CITY"
local game = { data = {} }
Dataset.hydrate(game)
check(game.data.maps and game.data.maps[GYM] and game.data.maps[GYM].midLayout ~= nil,
  "the hydrated gym carries its native layout")

local draws = 0
local realRandom = Rng.Random
Rng.Random = function(...)
  draws = draws + 1
  return realRandom(...)
end

local session
local function startSession(mapId, x, y, reason)
  if Runtime.isActive() then
    Runtime.stop(nil, game)
  end
  session = { map = mapId, x = x, y = y, facing = "up", flags = {}, vars = {} }
  game.session = session
  Map._announced = nil
  Runtime.start(nil, game, session, { reason = reason })
end
local function warpTo(mapId, x, y)
  Map.load(nil, game, mapId, { x = x, y = y, facing = "up" })
  for _ = 1, 256 do
    if not Space.vm:isRunning() then break end
    Space.vm:tick()
  end
end
local function enterGym()
  warpTo(CITY, 12, 20)
  warpTo(GYM, 5, 18)
end
startSession(CITY, 12, 20, "new_game")

local function getFlag(id)
  return Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, id) and true or false
end
local function setFlag(id, on)
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, id, on and true or false)
end
local function getVar(id)
  return Flags.getVar(Space.store, Space.vm and Space.vm.ctx, id)
end

print("[test] 7. entering the gym rolls the two switch cans into VAR_TEMP_0/1")
enterGym("FR_VERMILION_CITY")
local s1, s2 = getVar(VAR_TEMP_0), getVar(VAR_TEMP_1)
check(s1 >= 1 and s1 <= 15, "VAR_TEMP_0 holds a real can id, got " .. tostring(s1))
check(s2 >= 1 and s2 <= 15, "VAR_TEMP_1 holds a real can id, got " .. tostring(s2))
check(s1 ~= s2, "the two switch cans differ")

print("[test] 8. pressing the two switch cans opens the beams")
local canScript = {}
for i, bg in ipairs(gym.bgEvents or {}) do
  if i >= 3 and i <= 17 then canScript[i - 2] = bg.scriptKey end
end
check(canScript[1] ~= nil and canScript[15] ~= nil, "all 15 trash can scripts resolve")

local function pressCan(id)
  local vm = Space.vm
  local wasActive = Runtime.active
  Runtime.active = false
  vm:start(canScript[id])
  for _ = 1, 512 do
    if not vm:isRunning() then break end
    vm:tick()
    if vm.ctx and vm.ctx.status == "waiting" and vm.ctx.mode == "native" then break end
  end
  if vm:isRunning() then vm:halt(true) end
  Runtime.active = wasActive
end

local function beamCellsTouched()
  local hit, n = {}, 0
  for y = 6, 7 do
    for x = 3, 7 do
      local o = Field.metatileOverrideAt and Field.metatileOverrideAt(GYM, x, y)
      if o then
        hit[x .. "," .. y] = o
        n = n + 1
      end
    end
  end
  return n, hit
end
local function gapOpen()
  return Collision.canEnter(game, 5, 6) == true and Collision.canEnter(game, 5, 7) == true
end
local layout = game.data.maps[GYM].midLayout
local sealedTop, sealedBottom = layout:midAt(5, 6), layout:midAt(5, 7)

local wrongCan = 1
while wrongCan == s1 or wrongCan == s2 do wrongCan = wrongCan + 1 end

pressCan(wrongCan)
local wrongN = beamCellsTouched()
check(wrongN == 0, "a non-switch can changes no beam metatile")
check(not getFlag(FLAG_TEMP_1), "FOUND_FIRST_SWITCH stays clear after a wrong can")
check(not gapOpen(), "the sealed beams block (5,6)/(5,7)")

pressCan(s1)
local firstN, firstHit = beamCellsTouched()
check(firstN == 10, "the first switch can rewrites all 10 beam cells, got " .. firstN)
check(getFlag(FLAG_TEMP_1), "FOUND_FIRST_SWITCH is set after the first switch can")
check(firstHit["5,6"] and firstHit["5,6"].impassable == true, "the half-on beam is still solid")
check(not gapOpen(), "one switch does not open (5,6)/(5,7)")
local halfTop = layout:midAt(5, 6)
check(halfTop ~= sealedTop, "the half-on metatile replaced the full beam at (5,6)")

print("[test] 8b. a wrong second can resets the locks and re-rolls")
local wrongSecond = 1
while wrongSecond == s1 or wrongSecond == s2 do wrongSecond = wrongSecond + 1 end
draws = 0
pressCan(wrongSecond)
check(not getFlag(FLAG_TEMP_1), "FOUND_FIRST_SWITCH is cleared by the wrong second can")
check(not getFlag(FLAG_FOUND_BOTH), "the both-switches flag stays clear")
check(draws == 2, "the reset re-rolled the cans with two Random draws, got " .. draws)
local n1, n2 = getVar(VAR_TEMP_0), getVar(VAR_TEMP_1)
check(n1 >= 1 and n1 <= 15 and n2 >= 1 and n2 <= 15 and n1 ~= n2,
  string.format("the re-rolled cans are real and distinct, got (%s,%s)", tostring(n1), tostring(n2)))
check(layout:midAt(5, 6) == sealedTop and layout:midAt(5, 7) == sealedBottom,
  "SetBeamsOn put the full beam metatiles back")
local _, onHit = beamCellsTouched()
check(onHit["5,6"] and onHit["5,6"].impassable == true, "the restored beam is solid in the store")
check(not gapOpen(), "the reset beams block (5,6)/(5,7)")
s1, s2 = n1, n2

pressCan(s1)
check(getFlag(FLAG_TEMP_1), "the re-rolled first switch can is found")
check(not gapOpen(), "one switch still does not open the gap")
pressCan(s2)
local secondN, secondHit = beamCellsTouched()
check(secondN == 10, "the store holds one entry per beam cell after the rewrite, got " .. secondN)
check(secondHit["5,6"] and secondHit["5,6"].impassable == false,
  "the second write superseded the solid half-on entry at (5,6)")
check(getFlag(FLAG_FOUND_BOTH), "FLAG_FOUND_BOTH_VERMILION_GYM_SWITCHES is set")
check(gapOpen(), "collision opens (5,6)/(5,7) once both switches are found")
check(Collision.canEnter(game, 3, 6) ~= true and Collision.canEnter(game, 7, 7) ~= true,
  "the outer off nodes stay solid")

print("[test] 8c. a rebind without a map load keeps the script-written cells")
Collision.bindMap(game, GYM, game.data.maps[GYM])
check(gapOpen(), "the gap survives a collision rebind (battle return)")
check(beamCellsTouched() == 10, "the store survives a collision rebind")

print("[test] 9. re-entry with both switches found re-opens the beams via ON_LOAD")
enterGym()
local reopenN, reopen = beamCellsTouched()
check(reopenN == 10, "ON_LOAD re-applied the beams-off metatiles on re-entry, got " .. reopenN)
check(reopen["5,6"] ~= nil and reopen["5,6"].impassable ~= true,
  "the middle beam cell (5,6) is walkable after ON_LOAD")
check(reopen["5,7"] ~= nil and reopen["5,7"].impassable ~= true,
  "the middle beam cell (5,7) is walkable after ON_LOAD")
check(getFlag(FLAG_FOUND_BOTH), "the both-switches flag survives the re-entry")
check(gapOpen(), "collision is open after re-entry")

print("[test] 9b. the gym's cells do not leak onto another map")
local OTHER = "FR_ROUTE_1"
warpTo(OTHER, 12, 20)
check(beamCellsTouched() == 0, "leaving the gym dropped its script-written cells")
local leaked = 0
for y = 6, 7 do
  for x = 3, 7 do
    local ok, why = Collision.canEnter(game, x, y)
    if not ok and why == "tile" and Collision.isWalkable(x, y) then leaked = leaked + 1 end
  end
end
check(leaked == 0, "the gym's solid cells do not block Route 1's walkable cells, leaked=" .. leaked)
Field.setMetatile(5, 6, game.data.maps[OTHER].midLayout:midAt(5, 6), true)
check(type(Field.metatileOverrideAt) == "function"
  and Field.metatileOverrideAt(GYM, 5, 6) == nil and Field.metatileOverrideAt(OTHER, 5, 6) ~= nil,
  "the store is keyed by the map that was written")

print("[test] 10. a new session in the same process sees a fresh, sealed gym")
startSession(CITY, 12, 20, "new_game")
draws = 0
enterGym()
local rerollN = beamCellsTouched()
check(rerollN == 0, "ON_LOAD leaves the beams sealed for an unsolved gym, got " .. rerollN)
check(layout:midAt(5, 6) == sealedTop, "the layout is fresh: (5,6) is the full beam again")
check(not gapOpen(), "the fresh gym blocks (5,6)/(5,7)")
check(not getFlag(FLAG_TEMP_1), "FOUND_FIRST_SWITCH is cleared by the map change")
check(draws == 2, "one gym entry rolls the cans with two Random draws, got " .. draws)
local r1, r2 = getVar(VAR_TEMP_0), getVar(VAR_TEMP_1)
check(r1 >= 1 and r1 <= 15 and r2 >= 1 and r2 <= 15 and r1 ~= r2,
  string.format("the switch cans were rolled again, got (%s,%s)", tostring(r1), tostring(r2)))

print("[test] 11. Continue inside the gym runs ON_TRANSITION / ON_LOAD once")
local Game3 = require("src.core.Game3")
local saved = { map = GYM, x = 5, y = 18, facing = "up", flags = {}, vars = {} }
Runtime.stop(nil, game)
local loads, rolls, rollDraws = 0, 0, 0
local realRunOnLoad = Space.runOnLoad
Space.runOnLoad = function(...)
  loads = loads + 1
  return realRunOnLoad(...)
end
local realRoll = Natives.setVermilionTrashCans
Natives.setVermilionTrashCans = function(random)
  rolls = rolls + 1
  local before = draws
  local a, b = realRoll(random)
  rollDraws = rollDraws + (draws - before)
  return a, b
end
local host = setmetatable({ data = game.data }, { __index = Game3 })
local okEnter, errEnter = pcall(Game3._enterField, host, saved, "continue")
Space.runOnLoad = realRunOnLoad
Natives.setVermilionTrashCans = realRoll
check(okEnter, "Game3:_enterField ran under the test host: " .. tostring(errEnter))
check(loads == 1, "Continue ran ON_LOAD once, ran " .. loads)
check(rolls == 1, "Continue rolled the trash cans once, rolled " .. rolls)
check(rollDraws == 2, "Continue spent two Random draws on the cans, got " .. rollDraws)
Rng.Random = realRandom

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
