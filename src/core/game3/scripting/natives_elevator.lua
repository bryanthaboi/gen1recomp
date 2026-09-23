local RomText = require("src.core.game3.rom_text")
local Std = require("src.core.game3.scripting.stdscripts")

local Elevator = {}

local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321
local VAR_ELEVATOR_FLOOR = 0x403A -- pokefirered/include/constants/vars.h:108

local SE_ELEVATOR = 82 -- pokefirered/include/constants/songs.h:86
local SE_DING_DONG = 66 -- pokefirered/include/constants/songs.h:70

-- pokefirered/src/field_specials.c:836 GetElevatorFloor
local FLOOR_BY_MAP = {
  FR_ROCKET_HIDEOUT_B4F = 0,
  FR_ROCKET_HIDEOUT_B2F = 2,
  FR_ROCKET_HIDEOUT_B1F = 3,
  FR_TRAINER_TOWER_LOBBY = 3,
  FR_SILPH_CO_1F = 4,
  FR_SILPH_CO_2F = 5,
  FR_SILPH_CO_3F = 6,
  FR_SILPH_CO_4F = 7,
  FR_SILPH_CO_5F = 8,
  FR_SILPH_CO_6F = 9,
  FR_SILPH_CO_7F = 10,
  FR_SILPH_CO_8F = 11,
  FR_SILPH_CO_9F = 12,
  FR_SILPH_CO_10F = 13,
  FR_SILPH_CO_11F = 14,
  FR_CELADON_CITY_DEPARTMENT_STORE_1F = 4,
  FR_CELADON_CITY_DEPARTMENT_STORE_2F = 5,
  FR_CELADON_CITY_DEPARTMENT_STORE_3F = 6,
  FR_CELADON_CITY_DEPARTMENT_STORE_4F = 7,
  FR_CELADON_CITY_DEPARTMENT_STORE_5F = 8,
  FR_TRAINER_TOWER_1F = 15,
  FR_TRAINER_TOWER_2F = 15,
  FR_TRAINER_TOWER_3F = 15,
  FR_TRAINER_TOWER_4F = 15,
  FR_TRAINER_TOWER_5F = 15,
  FR_TRAINER_TOWER_6F = 15,
  FR_TRAINER_TOWER_7F = 15,
  FR_TRAINER_TOWER_8F = 15,
  FR_TRAINER_TOWER_ROOF = 15,
}
Elevator.FLOOR_BY_MAP = FLOOR_BY_MAP

-- pokefirered/src/field_specials.c:836
local DEFAULT_FLOOR = 4

-- pokefirered/src/field_specials.c:931 InitElevatorFloorSelectMenuPos
local MENU_POS_BY_MAP = {
  FR_SILPH_CO_11F = { 0, 0 },
  FR_SILPH_CO_10F = { 0, 1 },
  FR_SILPH_CO_9F = { 0, 2 },
  FR_SILPH_CO_8F = { 0, 3 },
  FR_SILPH_CO_7F = { 0, 4 },
  FR_SILPH_CO_6F = { 1, 4 },
  FR_SILPH_CO_5F = { 2, 4 },
  FR_SILPH_CO_4F = { 3, 4 },
  FR_SILPH_CO_3F = { 4, 4 },
  FR_SILPH_CO_2F = { 5, 4 },
  FR_SILPH_CO_1F = { 5, 5 },
  FR_ROCKET_HIDEOUT_B1F = { 0, 0 },
  FR_ROCKET_HIDEOUT_B2F = { 0, 1 },
  FR_ROCKET_HIDEOUT_B4F = { 0, 2 },
  FR_CELADON_CITY_DEPARTMENT_STORE_5F = { 0, 0 },
  FR_CELADON_CITY_DEPARTMENT_STORE_4F = { 0, 1 },
  FR_CELADON_CITY_DEPARTMENT_STORE_3F = { 0, 2 },
  FR_CELADON_CITY_DEPARTMENT_STORE_2F = { 0, 3 },
  FR_CELADON_CITY_DEPARTMENT_STORE_1F = { 0, 4 },
  FR_TRAINER_TOWER_1F = { 0, 0 },
  FR_TRAINER_TOWER_2F = { 0, 0 },
  FR_TRAINER_TOWER_3F = { 0, 0 },
  FR_TRAINER_TOWER_4F = { 0, 0 },
  FR_TRAINER_TOWER_5F = { 0, 0 },
  FR_TRAINER_TOWER_6F = { 0, 0 },
  FR_TRAINER_TOWER_7F = { 0, 0 },
  FR_TRAINER_TOWER_8F = { 0, 0 },
  FR_TRAINER_TOWER_ROOF = { 0, 0 },
  FR_TRAINER_TOWER_LOBBY = { 0, 1 },
}
Elevator.MENU_POS_BY_MAP = MENU_POS_BY_MAP

-- pokefirered/src/field_specials.c:812 sElevatorAnimationDuration
local ELEVATOR_ANIM_DURATION = { [0] = 8, 16, 24, 32, 38, 46, 53, 56, 57 }
-- pokefirered/src/field_specials.c:824 sElevatorWindowAnimDuration
local WINDOW_ANIM_DURATION = { [0] = 3, 6, 9, 12, 15, 18, 21, 24, 27 }

-- pokefirered/include/constants/metatile_labels.h:215
local WINDOW_UP = {
  { 0x2E8, 0x2E9, 0x2EA },
  { 0x2F0, 0x2F1, 0x2F2 },
  { 0x2F8, 0x2F9, 0x2FA },
}
local WINDOW_DOWN = {
  { 0x2E8, 0x2EA, 0x2E9 },
  { 0x2F0, 0x2F2, 0x2F1 },
  { 0x2F8, 0x2FA, 0x2F9 },
}

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function scriptStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf()
  return (Space and Space.store) or (session and session.store) or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(), ctx, id, tonumber(value) or 0)
end

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

-- pokefirered/src/overworld.c:605 SetDynamicWarpWithCoords
function Elevator.dynamicWarpMap()
  local session = sessionOf()
  if not session then return nil end
  local dw = session.dynamicWarp
  if type(dw) == "table" then
    local id = dw.map or dw.mapId or dw.destMap
    if type(id) == "string" then return id end
  elseif type(dw) == "string" then
    return dw
  end
  if type(session.dynamicWarpMap) == "string" then return session.dynamicWarpMap end
  return nil
end

-- pokefirered/src/field_specials.c:836
function Elevator.floorFor(mapId)
  return FLOOR_BY_MAP[mapId or ""] or DEFAULT_FLOOR
end

-- pokefirered/src/field_specials.c:931
function Elevator.menuPosFor(mapId)
  local pos = MENU_POS_BY_MAP[mapId or ""]
  if not pos then return 0, 0 end
  return pos[1], pos[2]
end

local function fieldView()
  return package.loaded["src.core.game3.field_view"]
end

local function setMetatile(x, y, mid)
  local okF, Field = pcall(require, "src.core.game3.field")
  if okF and Field and Field.setMetatile then
    pcall(Field.setMetatile, x, y, mid, true)
  end
end

-- pokefirered/src/field_specials.c:1132 Task_AnimateElevatorWindowView
local function windowViewStep(step, direction)
  local table3 = (direction == 0) and WINDOW_UP or WINDOW_DOWN
  local col = (step % 3) + 1
  for i = 1, 3 do
    for j = 1, 3 do
      setMetatile(j, i - 1, table3[i][col])
    end
  end
  local FieldView = fieldView()
  if FieldView then FieldView._nativeDirty = true end
end

-- pokefirered/src/field_specials.c:1119 AnimateElevatorWindowView
function Elevator.windowTask(nfloors, direction)
  local steps = WINDOW_ANIM_DURATION[nfloors] or 0
  local frame, count = 0, 0
  return function()
    if count >= steps then return true end
    frame = frame + 1
    if frame % 7 == 0 then
      count = count + 1
      windowViewStep(count, direction)
    end
    return count >= steps
  end
end

-- pokefirered/src/field_specials.c:1049 AnimateElevator + Task_ElevatorShake
function Elevator.animationTask(from, to)
  local nfloors, direction
  if from > to then
    nfloors, direction = from - to, 1
  else
    nfloors, direction = to - from, 0
  end
  if nfloors > 8 then nfloors = 8 end
  local shakeSteps = ELEVATOR_ANIM_DURATION[nfloors]
  local window = Elevator.windowTask(nfloors, direction)
  local frame, shakeCount, pan = 0, 0, 1
  se(SE_ELEVATOR)
  return function()
    frame = frame + 1
    if frame % 3 == 0 and shakeCount < shakeSteps then
      shakeCount = shakeCount + 1
      pan = -pan
      local FieldView = fieldView()
      if FieldView then FieldView.cameraPanY = pan end
    end
    if window and window() then window = nil end
    if shakeCount < shakeSteps then return false end
    local FieldView = fieldView()
    if FieldView then FieldView.cameraPanY = 0 end
    se(SE_DING_DONG)
    if window then
      local okT, Task = pcall(require, "src.core.game3.task")
      if okT and Task and Task.spawn then Task.spawn(window) end
      window = nil
    end
    return true
  end
end

Elevator.HANDLERS = {
  -- pokefirered/src/field_specials.c:836
  [Std.SPECIAL.GetElevatorFloor] = function(ctx)
    varSet(ctx, VAR_ELEVATOR_FLOOR, Elevator.floorFor(Elevator.dynamicWarpMap()))
    return false
  end,
  -- pokefirered/src/field_specials.c:931
  [Std.SPECIAL.InitElevatorFloorSelectMenuPos] = function(ctx)
    local scroll, cursor = Elevator.menuPosFor(Elevator.dynamicWarpMap())
    local ListMenu = require("src.core.game3.scripting.natives_listmenu")
    ListMenu.elevatorScroll = scroll
    ListMenu.elevatorCursorPos = cursor
    return false, cursor
  end,
  -- pokefirered/src/field_specials.c:1094
  [Std.SPECIAL.DrawElevatorCurrentFloorWindow] = function(ctx, adapters)
    -- pokefirered/src/field_specials.c:737
    local key = RomText.key("sFloorNamePointers", varGet(ctx, VAR_0x8005))
    if not RomText.has(key) then return false end
    if adapters and adapters.elevatorWindow then
      pcall(adapters.elevatorWindow, RomText.plain(key))
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:1113
  [Std.SPECIAL.CloseElevatorCurrentFloorWindow] = function(_, adapters)
    if adapters and adapters.elevatorWindowClose then
      pcall(adapters.elevatorWindowClose)
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:1049
  [Std.SPECIAL.AnimateElevator] = function(ctx)
    local Natives = require("src.core.game3.scripting.natives")
    Natives.awaitState(ctx, Elevator.animationTask(varGet(ctx, VAR_0x8005), varGet(ctx, VAR_0x8006)))
    return false
  end,
}

return Elevator
