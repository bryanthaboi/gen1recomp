local Collision = require("src.core.game3.collision")
local ForcedMovement = require("src.core.game3.forced_movement")

local Steps = {}

local function player()
  return package.loaded["src.core.game3.player"] or require("src.core.game3.player")
end

local function constants()
  return require("src.core.game3.constants").active()
end

local function metatile(name)
  return constants():require("metatile_labels", "METATILE_" .. name)
end

local function varId(name)
  return constants():require("vars", name)
end

local function store()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.store, Space and Space.vm and Space.vm.ctx or nil
end

local function getVar(name)
  local st, ctx = store()
  if not st then return 0 end
  return tonumber(require("src.core.game3.scripting.flags").getVar(st, ctx, varId(name))) or 0
end

local function setVar(name, value)
  local st, ctx = store()
  if not st then return end
  require("src.core.game3.scripting.flags").setVar(st, ctx, varId(name), value)
end

local function playSe(name)
  pcall(function()
    local id = require("src.core.game3.se_ids")[name]
    if id then require("src.core.game3.audio").playSe(id) end
  end)
end

-- pokeemerald/src/field_player_avatar.c:1141 PlayerGetDestCoords
local function destCoords()
  local P = player()
  if P.moving and P.targetX then return P.targetX, P.targetY end
  return P.cellX, P.cellY
end

local function behaviorAt(x, y)
  return Collision.behavior(x, y)
end

-- pokeemerald/src/fieldmap.c:337 MapGridGetMetatileIdAt
function Steps.metatileAt(x, y)
  local def = Collision._mapDef
  local layout = def and def.midLayout
  if not (layout and layout.midAt) then return nil end
  return layout:midAt(x, y)
end

-- pokeemerald/src/fieldmap.c:357 MapGridSetMetatileIdAt
function Steps.setMetatile(x, y, id)
  require("src.core.game3.field").setMetatile(x, y, id, false)
end

-- pokeemerald/src/field_tasks.c:748 AshGrassPerStepCallback
local function ashGrass(_game, data)
  local x, y = destCoords()
  local pending = data.ash
  if pending then
    for i = #pending, 1, -1 do
      local a = pending[i]
      a.delay = a.delay - 1
      if a.delay == 0 then
        -- pokeemerald/src/field_effect_helpers.c:966 UpdateAshFieldEffect_Show
        Steps.setMetatile(a.x, a.y, a.metatile)
        local FieldEffects = package.loaded["src.core.game3.field_effects"]
        if FieldEffects and FieldEffects.startAsh then FieldEffects.startAsh(a.x, a.y) end
        -- pokeruby/src/field_effect_helpers.c:922
        local px, py = destCoords()
        if FieldEffects and FieldEffects.tallGrassAt and Collision.isGrass and Collision.isGrass(px, py) then
          FieldEffects.tallGrassAt(px, py, true)
        end
        table.remove(pending, i)
      end
    end
  end
  if x == data.prevX and y == data.prevY then return false end
  data.prevX, data.prevY = x, y
  if not Collision.isAshGrass(behaviorAt(x, y)) then return false end
  local target = Steps.metatileAt(x, y) == metatile("Fallarbor_AshGrass")
    and metatile("Fallarbor_NormalGrass") or metatile("Lavaridge_NormalGrass")
  data.ash = data.ash or {}
  -- pokeemerald/src/field_effect_helpers.c:915 StartAshFieldEffect
  table.insert(data.ash, { x = x, y = y, metatile = target, delay = 4 })
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local Bag = require("src.core.game3.bag")
  if session and session.bag and Bag.has(session.bag, constants():require("items", "ITEM_SOOT_SACK"), 1) then
    local count = getVar("VAR_ASH_GATHER_COUNT")
    if count < 9999 then setVar("VAR_ASH_GATHER_COUNT", count + 1) end
  end
  return false
end

local function tryLowerFortreeBridge(x, y)
  if (tonumber(player().elevation) or 0) % 2 ~= 0 then return end
  local mid = Steps.metatileAt(x, y)
  if mid == metatile("Fortree_BridgeOverGrass_Raised") then
    Steps.setMetatile(x, y, metatile("Fortree_BridgeOverGrass_Lowered"))
  elseif mid == metatile("Fortree_BridgeOverTrees_Raised") then
    Steps.setMetatile(x, y, metatile("Fortree_BridgeOverTrees_Lowered"))
  end
end

local function tryRaiseFortreeBridge(x, y)
  if (tonumber(player().elevation) or 0) % 2 ~= 0 then return end
  local mid = Steps.metatileAt(x, y)
  if mid == metatile("Fortree_BridgeOverGrass_Lowered") then
    Steps.setMetatile(x, y, metatile("Fortree_BridgeOverGrass_Raised"))
  elseif mid == metatile("Fortree_BridgeOverTrees_Lowered") then
    Steps.setMetatile(x, y, metatile("Fortree_BridgeOverTrees_Raised"))
  end
end
Steps.tryLowerFortreeBridge = tryLowerFortreeBridge
Steps.tryRaiseFortreeBridge = tryRaiseFortreeBridge

-- pokeemerald/src/field_tasks.c:490 FortreeBridgePerStepCallback
local function fortreeBridge(_game, data)
  local x, y = destCoords()
  local state = data.state or 0
  if state == 0 then
    data.prevX, data.prevY = x, y
    if Collision.isFortreeBridge(behaviorAt(x, y)) then tryLowerFortreeBridge(x, y) end
    data.state = 1
    return false
  end
  if state == 1 then
    local prevX, prevY = data.prevX, data.prevY
    if x == prevX and y == prevY then return false end
    local cur = Collision.isFortreeBridge(behaviorAt(x, y))
    local prev = Collision.isFortreeBridge(behaviorAt(prevX, prevY))
    local onBridgeElevation = (tonumber(player().elevation) or 0) % 2 == 0
    if onBridgeElevation and (cur or prev) then playSe("SE_BRIDGE_WALK") end
    if prev then
      tryRaiseFortreeBridge(prevX, prevY)
      tryLowerFortreeBridge(x, y)
    end
    data.oldX, data.oldY = prevX, prevY
    data.prevX, data.prevY = x, y
    if not prev then return false end
    data.bounce = 16
    data.state = 2
  end
  data.bounce = data.bounce - 1
  if data.bounce % 7 == 4 then
    tryLowerFortreeBridge(data.oldX, data.oldY)
    data.bounced = true
  elseif data.bounce % 7 == 0 and data.bounced then
    tryRaiseFortreeBridge(data.oldX, data.oldY)
    data.bounced = false
  end
  if data.bounce == 0 then data.state = 1 end
  return false
end

-- pokeemerald/src/field_tasks.c:78 sHalfSubmergedBridgeMetatileOffsets
-- pokeruby/src/field_tasks.c:151
local LOG_OFFSETS = {
  { { 0, 0, "VerticalTop", "Vertical0" }, { 0, 1, "VerticalBottom", "Vertical1" } },
  { { 0, -1, "VerticalTop", "Vertical0" }, { 0, 0, "VerticalBottom", "Vertical1" } },
  { { 0, 0, "HorizontalLeft", "Horizontal0" }, { 1, 0, "HorizontalRight", "Horizontal1" } },
  { { -1, 0, "HorizontalLeft", "Horizontal0" }, { 0, 0, "HorizontalRight", "Horizontal1" } },
}

-- pokeemerald/src/field_tasks.c:240 GetPacifidlogBridgeMetatileOffsets
local function logOffsets(beh)
  if Collision.isPacifidlogVerticalLogTop(beh) then return LOG_OFFSETS[1] end
  if Collision.isPacifidlogVerticalLogBottom(beh) then return LOG_OFFSETS[2] end
  if Collision.isPacifidlogHorizontalLogLeft(beh) then return LOG_OFFSETS[3] end
  if Collision.isPacifidlogHorizontalLogRight(beh) then return LOG_OFFSETS[4] end
  return nil
end

-- pokeemerald/src/field_tasks.c:254 TrySetPacifidlogBridgeMetatiles
local function setLogs(stage, x, y)
  local offsets = logOffsets(behaviorAt(x, y))
  if not offsets then return end
  local C = constants()
  for _, o in ipairs(offsets) do
    local prefix = "Pacifidlog_" .. stage .. "_"
    Steps.setMetatile(x + o[1], y + o[2],
      C:id("metatile_labels", "METATILE_" .. prefix .. o[3]) or metatile(prefix .. o[4]))
  end
end

-- pokeemerald/src/field_tasks.c:289 ShouldRaisePacifidlogLogs
local function shouldRaise(newX, newY, oldX, oldY)
  local old = behaviorAt(oldX, oldY)
  if Collision.isPacifidlogVerticalLogTop(old) then return not (newY > oldY) end
  if Collision.isPacifidlogVerticalLogBottom(old) then return not (newY < oldY) end
  if Collision.isPacifidlogHorizontalLogLeft(old) then return not (newX > oldX) end
  if Collision.isPacifidlogHorizontalLogRight(old) then return not (newX < oldX) end
  return true
end

-- pokeemerald/src/field_tasks.c:328 ShouldSinkPacifidlogLogs
local function shouldSink(newX, newY, oldX, oldY)
  local new = behaviorAt(newX, newY)
  if Collision.isPacifidlogVerticalLogTop(new) then return not (newY < oldY) end
  if Collision.isPacifidlogVerticalLogBottom(new) then return not (newY > oldY) end
  if Collision.isPacifidlogHorizontalLogLeft(new) then return not (newX < oldX) end
  if Collision.isPacifidlogHorizontalLogRight(new) then return not (newX > oldX) end
  return true
end

-- pokeemerald/src/field_tasks.c:366 PacifidlogBridgePerStepCallback
local function pacifidlogBridge(_game, data)
  local x, y = destCoords()
  local state = data.state or 0
  if state == 0 then
    data.prevX, data.prevY = x, y
    setLogs("SubmergedLogs", x, y)
    data.state = 1
  elseif state == 1 then
    if x == data.prevX and y == data.prevY then return false end
    if shouldRaise(x, y, data.prevX, data.prevY) then
      setLogs("HalfSubmergedLogs", data.prevX, data.prevY)
      data.raiseX, data.raiseY = data.prevX, data.prevY
      data.state, data.delay = 2, 8
    else
      data.raiseX, data.raiseY = nil, nil
    end
    if shouldSink(x, y, data.prevX, data.prevY) then
      setLogs("HalfSubmergedLogs", x, y)
      data.state, data.delay = 2, 8
    end
    data.prevX, data.prevY = x, y
    if Collision.isPacifidlogLog(behaviorAt(x, y)) then playSe("SE_PUDDLE") end
  elseif state == 2 then
    data.delay = data.delay - 1
    if data.delay == 0 then
      setLogs("SubmergedLogs", x, y)
      if data.raiseX then setLogs("FloatingLogs", data.raiseX, data.raiseY) end
      data.state = 1
    end
  end
  return false
end

-- pokeemerald/src/field_tasks.c:600 ICE_PUZZLE_L
local ICE_PUZZLE_L, ICE_PUZZLE_R, ICE_PUZZLE_T, ICE_PUZZLE_B = 3, 13, 6, 19
-- pokeemerald/src/field_tasks.c:106 sSootopolisGymIceRowVars
local ICE_ROW_VARS = {
  [6] = "VAR_TEMP_1", [7] = "VAR_TEMP_2", [8] = "VAR_TEMP_3", [9] = "VAR_TEMP_4",
  [12] = "VAR_TEMP_5", [13] = "VAR_TEMP_6", [14] = "VAR_TEMP_7",
  [17] = "VAR_TEMP_8", [18] = "VAR_TEMP_9", [19] = "VAR_TEMP_A",
}
Steps.ICE_ROW_VARS = ICE_ROW_VARS

-- pokeemerald/src/field_tasks.c:608 CoordInIcePuzzleRegion
local function inIcePuzzle(x, y)
  return x >= ICE_PUZZLE_L and x <= ICE_PUZZLE_R and y >= ICE_PUZZLE_T and y <= ICE_PUZZLE_B
    and ICE_ROW_VARS[y] ~= nil
end

local function bit(x) return 2 ^ (x - ICE_PUZZLE_L) end

-- pokeemerald/src/field_tasks.c:618 MarkIcePuzzleCoordVisited
function Steps.markIceVisited(x, y)
  if not inIcePuzzle(x, y) then return end
  local v = getVar(ICE_ROW_VARS[y])
  if math.floor(v / bit(x)) % 2 == 0 then setVar(ICE_ROW_VARS[y], v + bit(x)) end
end

-- pokeemerald/src/field_tasks.c:624 IsIcePuzzleCoordVisited
function Steps.isIceVisited(x, y)
  if not inIcePuzzle(x, y) then return false end
  return math.floor(getVar(ICE_ROW_VARS[y]) / bit(x)) % 2 == 1
end

-- pokeemerald/src/field_tasks.c:637 SetSootopolisGymCrackedIceMetatiles
function Steps.setSootopolisGymCrackedIceMetatiles()
  local def = Collision._mapDef
  local layout = def and def.midLayout
  if not layout then return 0 end
  local n = 0
  for x = 0, (layout.trueWidth or layout.width) - 1 do
    for y = 0, (layout.trueHeight or layout.height) - 1 do
      if Steps.isIceVisited(x, y) then
        Steps.setMetatile(x, y, metatile("SootopolisGym_Ice_Cracked"))
        n = n + 1
      end
    end
  end
  return n
end

-- pokeemerald/src/field_tasks.c:659 SootopolisGymIcePerStepCallback
local function sootopolisIce(_game, data)
  local state = data.state or 0
  if state == 0 then
    data.prevX, data.prevY = destCoords()
    data.state = 1
  elseif state == 1 then
    local x, y = destCoords()
    if x == data.prevX and y == data.prevY then return false end
    data.prevX, data.prevY = x, y
    local beh = behaviorAt(x, y)
    if Collision.isThinIce(beh) then
      setVar("VAR_ICE_STEP_COUNT", getVar("VAR_ICE_STEP_COUNT") + 1)
      data.delay, data.state, data.iceX, data.iceY = 4, 2, x, y
    elseif Collision.isCrackedIce(beh) then
      setVar("VAR_ICE_STEP_COUNT", 0)
      data.delay, data.state, data.iceX, data.iceY = 4, 3, x, y
    end
  elseif data.delay ~= 0 then
    data.delay = data.delay - 1
  elseif state == 2 then
    playSe("SE_ICE_CRACK")
    Steps.setMetatile(data.iceX, data.iceY, metatile("SootopolisGym_Ice_Cracked"))
    Steps.markIceVisited(data.iceX, data.iceY)
    data.state = 1
  else
    playSe("SE_ICE_BREAK")
    Steps.setMetatile(data.iceX, data.iceY, metatile("SootopolisGym_Ice_Broken"))
    data.state = 1
  end
  return false
end

-- pokeruby/src/field_tasks.c:665
local RS_CRACKED = { floor = 0x22F, hole = 0x206, pillarHole = 0x237 }

function Steps.crackedIds(C)
  C = C or constants()
  if C.game == "ruby" then return RS_CRACKED end
  -- pokeemerald/src/field_tasks.c:787
  return {
    floor = C:require("metatile_labels", "METATILE_Cave_CrackedFloor"),
    hole = C:require("metatile_labels", "METATILE_Cave_CrackedFloor_Hole"),
    pillarHole = C:require("metatile_labels", "METATILE_Pacifidlog_SkyPillar_CrackedFloor_Hole"),
  }
end

-- pokeemerald/src/field_tasks.c:785 SetCrackedFloorHoleMetatile
local function setCrackedFloorHole(x, y)
  local ids = Steps.crackedIds()
  Steps.setMetatile(x, y, Steps.metatileAt(x, y) == ids.floor and ids.hole or ids.pillarHole)
end

-- pokeemerald/src/field_tasks.c:801 CrackedFloorPerStepCallback
local function crackedFloor(_game, data)
  local x, y = destCoords()
  local beh = behaviorAt(x, y)
  local f1, f2 = data.floor1, data.floor2
  if f1 and f1.delay ~= 0 then
    f1.delay = f1.delay - 1
    if f1.delay == 0 then setCrackedFloorHole(f1.x, f1.y) end
  end
  if f2 and f2.delay ~= 0 then
    f2.delay = f2.delay - 1
    if f2.delay == 0 then setCrackedFloorHole(f2.x, f2.y) end
  end
  if Collision.isCrackedFloorHole(beh) then setVar("VAR_ICE_STEP_COUNT", 0) end
  if x == data.prevX and y == data.prevY then return false end
  data.prevX, data.prevY = x, y
  if Collision.isCrackedFloor(beh) then
    local Bike = require("src.core.game3.bike").rse()
    local speed = Bike and Bike.playerSpeed() or 0
    if not (Bike and speed == Bike.SPEED.FASTEST) then setVar("VAR_ICE_STEP_COUNT", 0) end
    if not (data.floor1 and data.floor1.delay ~= 0) then
      data.floor1 = { delay = 3, x = x, y = y }
    elseif not (data.floor2 and data.floor2.delay ~= 0) then
      data.floor2 = { delay = 3, x = x, y = y }
    end
  end
  return false
end

-- pokeemerald/src/field_tasks.c:870 sMuddySlopeMetatiles
local SLOPE_FRAMES = { "Frame0", "Frame3", "Frame2", "Frame1" }
-- pokeemerald/src/field_tasks.c:877 SLOPE_ANIM_TIME
local SLOPE_ANIM_TIME = 32
local SLOPE_ANIM_STEP_TIME = SLOPE_ANIM_TIME / #SLOPE_FRAMES

Steps._slope = { mapId = nil, prevX = nil, prevY = nil, slots = {} }

-- metatile ids per constants object: Ruby/Sapphire and Emerald differ, and
-- the game can be switched in-process, so the cache follows constants().
local slopeIds = setmetatable({}, { __mode = "k" })

-- pokeemerald/src/field_tasks.c:880 SetMuddySlopeMetatile
local function setMuddySlopeMetatile(slot)
  slot.time = slot.time - 1
  local name = slot.time == 0 and "Frame0" or SLOPE_FRAMES[math.floor(slot.time / SLOPE_ANIM_STEP_TIME) + 1]
  local c = constants()
  local ids = slopeIds[c]
  if not ids then
    ids = {}
    slopeIds[c] = ids
  end
  local id = ids[name]
  if not id then
    id = c:require("metatile_labels", "METATILE_General_MuddySlope_" .. name)
    ids[name] = id
  end
  -- pret writes every frame, but the frame only changes every 8; skip a
  -- write that would leave the cell as it is (the layout revision bump and
  -- view invalidation are the cost)
  local Field = package.loaded["src.core.game3.field"]
  local mapId = Field and Field._session and Field._session.map
  local bucket = mapId and Field.metatileOverrides[mapId]
  local cur = bucket and bucket[slot.y * 1024 + slot.x]
  if cur and cur.metatile == id and not cur.impassable then return end
  Steps.setMetatile(slot.x, slot.y, id)
end

-- pokeemerald/src/field_tasks.c:893 Task_MuddySlope
function Steps.muddySlopeTask(_game)
  local T = Steps._slope
  local Map = package.loaded["src.core.game3.map"]
  local mapId = Map and Map.current
  local x, y = destCoords()
  if T.mapId ~= mapId then
    T.mapId, T.prevX, T.prevY, T.slots = mapId, x, y, {}
    return
  end
  if T.prevX ~= x or T.prevY ~= y then
    T.prevX, T.prevY = x, y
    if Collision.isMuddySlope(behaviorAt(x, y)) then
      for i = 1, 4 do
        local slot = T.slots[i]
        if not slot or slot.time == 0 then
          T.slots[i] = { time = SLOPE_ANIM_TIME, x = x, y = y }
          break
        end
      end
    end
  end
  for i = 1, 4 do
    local slot = T.slots[i]
    if slot and slot.time > 0 then setMuddySlopeMetatile(slot) end
  end
end

Steps.CALLBACKS = {
  ash = ashGrass,
  fortreeBridge = fortreeBridge,
  pacifidlogBridge = pacifidlogBridge,
  sootopolisIce = sootopolisIce,
  crackedFloor = crackedFloor,
}

for name, fn in pairs(Steps.CALLBACKS) do
  ForcedMovement.registerStepCallback(name, fn)
end

return Steps
