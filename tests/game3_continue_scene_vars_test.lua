#!/usr/bin/env luajit
-- A continued save's first map load places scene objects before the script
-- store exists, from the session alone.  A save table loaded from disk keys
-- its vars by string; one started in this run keys them by number.  Both
-- must read the same scene.

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

local Runtime = require("src.core.game3.runtime")
local Objects = require("src.core.game3.objects")

local VAR_SIGN_LADY = 0x4070
local VAR_OAKS_LAB = 0x4055
local VAR_STARTER = 0x4031
local VAR_TEMP_2 = 0x4002

local function key(id, asString)
  if asString then return tostring(id) end
  return id
end

-- The pre-store path is the one under test: hold any store and session a
-- shared process already has, and put them back at the end.
local Space = package.loaded["src.core.game3.scripting.space"]
local heldStore, heldSession = Space and Space.store, Runtime.session
if Space then Space.store = nil end

local function load(mapId, session, objects)
  Runtime.session = session
  Objects.reset()
  Objects.loadMap(nil, mapId, { objects = objects })
end

local function palletObjects()
  return { { localId = 1, x = 3, y = 10, elevation = 3, movementType = 2, rangeX = 1, rangeY = 4 } }
end

local function labObjects()
  return {
    { localId = 4, x = 6, y = 11, elevation = 3, movementType = 8 },
    { localId = 8, x = 5, y = 10, elevation = 3, movementType = 7 },
  }
end

for _, asString in ipairs({ true, false }) do
  local form = asString and "string-keyed" or "number-keyed"

  -- Sign lady scene finished: she stays where the map puts her and the scene is not armed again.
  local done = {
    vars = { [key(VAR_SIGN_LADY, asString)] = 2 },
    flags = { [key(0x291, asString)] = true, [key(0x83E, asString)] = true },
    party = { { species = 4 } },
  }
  load("FR_PALLET_TOWN", done, palletObjects())
  local lady = Objects.find(1)
  check(lady ~= nil, form .. " finished scene: sign lady spawned")
  if lady then
    check(lady.cellX == 3 and lady.cellY == 10,
      string.format("%s finished scene: sign lady stays at her map position (got %s,%s)",
        form, tostring(lady.cellX), tostring(lady.cellY)))
  end
  check(done.vars[VAR_TEMP_2] == nil and done.vars[tostring(VAR_TEMP_2)] == nil,
    form .. " finished scene: the route-entrance trigger is not armed")
  check(done.flags[key(0x83E, asString)] == true, form .. " finished scene: the opened-menu flag is kept")

  -- Scene not played yet, starter in the party: she waits at the route entrance.
  local waiting = {
    vars = { [key(VAR_SIGN_LADY, asString)] = 0 },
    flags = { [key(0x291, asString)] = true },
    party = { { species = 4 } },
  }
  load("FR_PALLET_TOWN", waiting, palletObjects())
  lady = Objects.find(1)
  check(lady ~= nil and lady.cellX == 12 and lady.cellY == 2,
    form .. " unplayed scene: sign lady waits at the route entrance")
  check(waiting.vars[VAR_TEMP_2] == 1, form .. " unplayed scene: the route-entrance trigger is armed")

  -- Oak's lab after the starter was chosen: Oak by the table, the rival at his own ball.
  local lab = {
    vars = { [key(VAR_OAKS_LAB, asString)] = 3, [key(VAR_STARTER, asString)] = 2 },
    flags = {},
    party = { { species = 4 } },
  }
  load("FR_OAKS_LAB", lab, labObjects())
  local oak, rival = Objects.find(4), Objects.find(8)
  check(oak ~= nil and oak.cellX == 6 and oak.cellY == 3, form .. " lab scene 3: Oak stands by the table")
  check(rival ~= nil and rival.cellX == 9 and rival.cellY == 5,
    string.format("%s lab scene 3: the rival stands at his ball (got %s,%s)",
      form, tostring(rival and rival.cellX), tostring(rival and rival.cellY)))
end

Objects.reset()
Runtime.session = heldSession
if Space then Space.store = heldStore end

if failed > 0 then
  print(string.format("game3_continue_scene_vars_test: %d FAILED", failed))
  os.exit(1)
end
print("game3_continue_scene_vars_test: all passed")
