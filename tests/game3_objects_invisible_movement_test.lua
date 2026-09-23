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

local Objects = require("src.core.game3.objects")

local MAP = "FR_VERMILION_CITY_POKEMON_CENTER_1F"
local INVISIBLE = 0x4C

local function pcDef()
  return {
    midLayout = { width = 15, height = 9 },
    objects = {
      { localId = 1, graphicsId = 64, x = 7, y = 2, movementType = 8 },
      { localId = 6, graphicsId = 0, x = 2, y = 1, movementType = INVISIBLE, scriptKey = "J1" },
      { localId = 7, graphicsId = 0, x = 3, y = 1, movementType = INVISIBLE, scriptKey = "J2" },
    },
  }
end

local function has(list, lid)
  for _, v in ipairs(list) do
    if v == lid or (type(v) == "table" and v.localId == lid) then return true end
  end
  return false
end

print("[test] 1. MOVEMENT_TYPE_INVISIBLE objects are never drawn")
Objects.reset()
Objects.loadMap(nil, MAP, pcDef())
local draw = Objects.forDraw()
check(has(draw, 1), "the nurse is drawn")
check(not has(draw, 6), "journal 6 is not drawn")
check(not has(draw, 7), "journal 7 is not drawn")

print("[test] 2. they stay solid and talkable")
local j = Objects.find(6)
check(j ~= nil and j.visible and not j.hidden, "journal 6 is live")
check(has(Objects.listActive(), 6) and has(Objects.listActive(), 7), "journals are in listActive")
check(Objects.at(2, 1) == j, "Objects.at finds the journal for talk")
check(Objects.blocks(3, 1), "the journal cell blocks movement")

print("[test] 3. ghost pools skip them too")
local pool = Objects.spawnFromDefs(pcDef().objects, pcDef())
local pdraw = Objects.poolForDraw(pool)
check(has(pdraw, 1), "pool draws the nurse")
check(not has(pdraw, 6) and not has(pdraw, 7), "pool skips the journals")

print("[test] 4. addobject respawn keeps it invisible")
Objects.removeObject(6)
Objects.addObject(6)
check(not has(Objects.forDraw(), 6), "respawned journal is still not drawn")
check(has(Objects.listActive(), 6), "respawned journal is live")

print("[test] 5. switching a live object to the invisible type hides its sprite")
Objects.setTrainerMovementType(1, INVISIBLE)
check(not has(Objects.forDraw(), 1), "nurse no longer drawn")
check(has(Objects.listActive(), 1), "nurse still live")

print("[test] 6. respawn from the template drops a live-only invisible flag")
Objects.removeObject(1)
Objects.addObject(1)
check(has(Objects.forDraw(), 1), "respawned nurse drawn again")
Objects.setTrainerMovementType(1, INVISIBLE)
Objects.removeObject(1)
Objects.syncFlagVisibility(0, false)
Objects.addObject(1)
check(has(Objects.forDraw(), 1), "addobject after removeobject respawns the nurse visible")

print("[test] 7. a template override away from the invisible type spawns drawn")
Objects.reset()
Objects.loadMap(nil, MAP, pcDef())
Objects.overrideTemplateMovementType(6, 8)
Objects.loadMap(nil, MAP, pcDef())
check(has(Objects.forDraw(), 6), "journal 6 with an overridden template type is drawn")
check(not has(Objects.forDraw(), 7), "journal 7 still invisible")
Objects.reset()

print("[test] 8. addobject on a live invisible object leaves it invisible")
Objects.loadMap(nil, MAP, pcDef())
Objects.addObject(6)
check(not has(Objects.forDraw(), 6), "journal 6 still not drawn")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
