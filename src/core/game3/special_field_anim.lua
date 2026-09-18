-- ROM-derived Special Field Animations matching pret pokefirered (special_field_anim.c).
-- Handles escalator metatile cycling and teleporter animations.

local SpecialFieldAnim = {}

local ESCALATOR_STAGES = 3
local LAST_ESCALATOR_STAGE = ESCALATOR_STAGES - 1

-- Metatile IDs from constants/metatile_labels.h matching pokefirered/src/special_field_anim.c:
-- Standard ordering: [0] = Normal, [1] = Transition1, [2] = Transition2
local sEscalatorMetatiles_BottomNextRail = { [0] = 0x2D0, [1] = 0x30A, [2] = 0x308 }
local sEscalatorMetatiles_BottomRail     = { [0] = 0x2D1, [1] = 0x30B, [2] = 0x309 }
local sEscalatorMetatiles_BottomNext     = { [0] = 0x2D8, [1] = 0x312, [2] = 0x310 }
local sEscalatorMetatiles_Bottom         = { [0] = 0x2D9, [1] = 0x313, [2] = 0x311 }

local sEscalatorMetatiles_TopNext        = { [0] = 0x2E3, [1] = 0x316, [2] = 0x314 }
local sEscalatorMetatiles_Top            = { [0] = 0x2E4, [1] = 0x317, [2] = 0x315 }
local sEscalatorMetatiles_TopNextRail    = { [0] = 0x2EB, [1] = 0x31E, [2] = 0x31C }

SpecialFieldAnim._active = false
SpecialFieldAnim._layout = nil
SpecialFieldAnim._playerX = 0
SpecialFieldAnim._playerY = 0
SpecialFieldAnim._goingUp = false
SpecialFieldAnim._state = 0
SpecialFieldAnim._transitionStage = 0
SpecialFieldAnim._drawingEscalator = false
SpecialFieldAnim._originalMids = {}

--- SetEscalatorMetatile (pokefirered special_field_anim.c)
local function setEscalatorMetatile(layout, px, py, stage, goingUp, ids)
  if not layout then return end
  local x = px - 1
  local y = py - 1
  for i = 0, 2 do
    for j = 0, 2 do
      local cellX = x + j
      local cellY = y + i
      local curMid = layout:midAt(cellX, cellY)
      if goingUp then
        -- Moving UP: 0 (Normal) -> 1 (T1) -> 2 (T2) -> 0 (Normal)
        if curMid == ids[0] then
          layout:applyOverride(cellX, cellY, ids[1], layout:collAt(cellX, cellY), layout:elevAt(cellX, cellY))
        elseif curMid == ids[1] then
          layout:applyOverride(cellX, cellY, ids[2], layout:collAt(cellX, cellY), layout:elevAt(cellX, cellY))
        elseif curMid == ids[2] then
          layout:applyOverride(cellX, cellY, ids[0], layout:collAt(cellX, cellY), layout:elevAt(cellX, cellY))
        end
      else
        -- Moving DOWN: 0 (Normal) -> 2 (T2) -> 1 (T1) -> 0 (Normal)
        if curMid == ids[0] then
          layout:applyOverride(cellX, cellY, ids[2], layout:collAt(cellX, cellY), layout:elevAt(cellX, cellY))
        elseif curMid == ids[2] then
          layout:applyOverride(cellX, cellY, ids[1], layout:collAt(cellX, cellY), layout:elevAt(cellX, cellY))
        elseif curMid == ids[1] then
          layout:applyOverride(cellX, cellY, ids[0], layout:collAt(cellX, cellY), layout:elevAt(cellX, cellY))
        end
      end
    end
  end
end

function SpecialFieldAnim.startEscalator(layout, playerX, playerY, goingUp)
  SpecialFieldAnim._active = true
  SpecialFieldAnim._layout = layout
  SpecialFieldAnim._playerX = playerX or 0
  SpecialFieldAnim._playerY = playerY or 0
  SpecialFieldAnim._goingUp = goingUp and true or false
  SpecialFieldAnim._state = 0
  SpecialFieldAnim._transitionStage = 0
  SpecialFieldAnim._drawingEscalator = true

  -- Store original metatiles to restore when stopped
  SpecialFieldAnim._originalMids = {}
  if layout then
    local x = SpecialFieldAnim._playerX - 1
    local y = SpecialFieldAnim._playerY - 1
    for i = 0, 2 do
      for j = 0, 2 do
        local cellX = x + j
        local cellY = y + i
        local mid = layout:midAt(cellX, cellY)
        SpecialFieldAnim._originalMids[cellY * 1024 + cellX] = mid
      end
    end
  end

  -- Initial tick (pokefirered CreateEscalatorTask calls Task_DrawEscalator once)
  SpecialFieldAnim.update()
end

function SpecialFieldAnim.stopEscalator()
  if not SpecialFieldAnim._active then return end
  SpecialFieldAnim._active = false
  SpecialFieldAnim._drawingEscalator = false
  -- Restore original metatiles
  if SpecialFieldAnim._layout and SpecialFieldAnim._originalMids then
    for key, origMid in pairs(SpecialFieldAnim._originalMids) do
      local cellX = key % 1024
      local cellY = math.floor(key / 1024)
      SpecialFieldAnim._layout:applyOverride(cellX, cellY, origMid,
        SpecialFieldAnim._layout:collAt(cellX, cellY),
        SpecialFieldAnim._layout:elevAt(cellX, cellY))
    end
  end
  SpecialFieldAnim._originalMids = {}

  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
end

function SpecialFieldAnim.isActive()
  return SpecialFieldAnim._active and true or false
end

function SpecialFieldAnim.isEscalatorMoving()
  if not SpecialFieldAnim._active then return false end
  if not SpecialFieldAnim._drawingEscalator then
    return SpecialFieldAnim._transitionStage ~= LAST_ESCALATOR_STAGE
  end
  return true
end

--- Task_DrawEscalator (pokefirered special_field_anim.c)
function SpecialFieldAnim.update()
  if not SpecialFieldAnim._active or not SpecialFieldAnim._layout then return end

  SpecialFieldAnim._drawingEscalator = true
  local layout = SpecialFieldAnim._layout
  local px = SpecialFieldAnim._playerX
  local py = SpecialFieldAnim._playerY
  local stage = SpecialFieldAnim._transitionStage
  local goingUp = SpecialFieldAnim._goingUp

  -- Pret Task_DrawEscalator: cycle through sections on each state (0..6)
  local state = SpecialFieldAnim._state
  if state == 0 then
    setEscalatorMetatile(layout, px, py, stage, goingUp, sEscalatorMetatiles_BottomNextRail)
  elseif state == 1 then
    setEscalatorMetatile(layout, px, py, stage, goingUp, sEscalatorMetatiles_BottomRail)
  elseif state == 2 then
    setEscalatorMetatile(layout, px, py, stage, goingUp, sEscalatorMetatiles_BottomNext)
  elseif state == 3 then
    setEscalatorMetatile(layout, px, py, stage, goingUp, sEscalatorMetatiles_Bottom)
  elseif state == 4 then
    setEscalatorMetatile(layout, px, py, stage, goingUp, sEscalatorMetatiles_TopNext)
  elseif state == 5 then
    setEscalatorMetatile(layout, px, py, stage, goingUp, sEscalatorMetatiles_Top)
  elseif state == 6 then
    setEscalatorMetatile(layout, px, py, stage, goingUp, sEscalatorMetatiles_TopNextRail)
  end

  SpecialFieldAnim._state = (SpecialFieldAnim._state + 1) % 8
  if SpecialFieldAnim._state == 0 then
    -- Reached end of state cycle (DrawWholeMapView)
    SpecialFieldAnim._transitionStage = (SpecialFieldAnim._transitionStage + 1) % ESCALATOR_STAGES
    SpecialFieldAnim._drawingEscalator = false
    local FieldView = package.loaded["src.core.game3.field_view"]
    if FieldView then FieldView._nativeDirty = true end
  end
end

return SpecialFieldAnim
