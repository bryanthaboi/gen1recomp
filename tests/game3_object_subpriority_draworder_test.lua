-- scrcmd.c:1130, src/event_object_movement.c:8379-8387, src/event_object_movement.c:8424-8429, src/event_object_movement.c:2089-2101, src/event_object_movement.c:2104-2116, src/scrcmd.c:1122-1140

local Objects = require("src.core.game3.objects")
local FieldView = require("src.core.game3.field_view")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local eo = {
  localId = 3,
  def = { x = 4, y = 4, elevation = 0 },
  cellX = 4, cellY = 4, px = 4 * 16, py = 4 * 16,
  elevation = 0,
}
Objects._byId[3] = eo

local function makeActor(e)
  return {
    kind = "npc",
    i = e.localId,
    obj = e.def,
    eventObject = e,
    elevation = e.elevation,
    x = e.px or 0, y = e.py or 0,
    sortY = e.py or 0,
  }
end

print("[test] 1. baseline: no freeze -> dynamic class, no capture")
do
  local under, over = FieldView.applyDrawOrder({ makeActor(eo) })
  check(#over == 0 and #under == 1, "elevation 0 lands in the under list")
  check(under[1].priority == 2, "dynamic class 2 from ELEVATION_TO_PRIORITY[0]")
  check(under[1].subpriority == nil, "no subpriority on an unfrozen actor")
  check(eo.fixedClass == nil, "no capture before any freeze is set")
end

print("[test] 2. set stores the record with the +83 script bias")
do
  local scriptPriority = 0 -- scrcmd.c:1130
  local ok = Objects.setSubpriority(3, nil, nil, scriptPriority + 83)
  check(ok == true, "setSubpriority resolves the current-map object")
  check(eo.fixedPriority == true, "fixedPriority flag set")
  check(eo.subpriority == 83, "subpriority carries the +83 bias (0 + 83)")
end

print("[test] 3. set -> draw freezes the class at first observation")
do
  local under = FieldView.applyDrawOrder({ makeActor(eo) })
  check(eo.fixedClass == 2, "fixedClass captured on first observation (class 2)")
  check(under[1].priority == 2, "frozen priority = fixedClass")
  check(under[1].subpriority == 83, "+83 bias survives the round trip as the sort key")
end

print("[test] 4. freeze holds across an elevation change (pret early-return)")
do
  eo.elevation = 13
  local under, over = FieldView.applyDrawOrder({ makeActor(eo) })
  check(under[1].priority == 2, "priority stays at fixedClass (2), not ELEVATION_TO_PRIORITY[13]=0")
  check(eo.fixedClass == 2, "fixedClass captured once, not re-derived")
  check(#over == 0, "frozen actor does not move to the over list")
end

print("[test] 5. frozen actor sorts by subpriority; neighbour keeps pixel-Y")
do
  local neighbour = {
    kind = "npc", i = 9, obj = { elevation = 3 }, elevation = 3,
    x = 16, y = 100, sortY = 100,
  }
  local under = FieldView.applyDrawOrder({ neighbour, makeActor(eo) })
  check(#under == 2, "both actors share the under list")
  check(under[1].eventObject == eo, "frozen actor (83) sorts before the neighbour (sortY 100)")
  check(under[2].priority == 2, "unfrozen neighbour still follows ELEVATION_TO_PRIORITY[3]=2")
  check(under[2].subpriority == nil, "unfrozen neighbour keeps the pixel-Y key")

  local near = {
    kind = "npc", i = 8, obj = { elevation = 3 }, elevation = 3,
    x = 32, y = 10, sortY = 10,
  }
  local under2 = FieldView.applyDrawOrder({ near, makeActor(eo) })
  check(under2[1] == near, "pixel-Y 10 still sorts before subpriority 83")
  check(under2[2].eventObject == eo, "frozen actor falls behind the nearer neighbour")
end

print("[test] 6. reset resumes the dynamic path with no stale capture")
do
  local ok = Objects.resetSubpriority(3, nil, nil)
  check(ok == true, "resetSubpriority resolves the current-map object")
  check(eo.fixedPriority == nil and eo.subpriority == nil,
    "reset clears the record (pret ResetObjectSubpriority does not restore)")
  eo.elevation = 13
  local under, over = FieldView.applyDrawOrder({ makeActor(eo) })
  check(#over == 1 and #under == 0, "dynamic path resumed: class 0 -> over list")
  check(over[1].priority == 0, "priority follows ELEVATION_TO_PRIORITY[13] = 0 again")
  check(over[1].subpriority == nil, "sort key back to pixel-Y")
  check(eo.fixedClass == nil, "no stale fixedClass survives the reset")

  Objects.setSubpriority(3, nil, nil, 5 + 83)
  local under2, over2 = FieldView.applyDrawOrder({ makeActor(eo) })
  check(#under2 == 0, "fresh capture at class 0 keeps the actor out of the under list")
  check(eo.fixedClass == 0, "re-freeze re-captures at the current class (0 at elevation 13)")
  check(over2[1] ~= nil and over2[1].priority == 0, "re-frozen priority uses the fresh capture")
  check(over2[1].subpriority == 88, "new bias (5 + 83) replaces the old sort key")
end

done()
