-- pokefirered/src/field_specials.c:1094

local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")

local ElevatorWindow = {}

-- pokefirered/src/field_specials.c:727
ElevatorWindow.LEFT = 22
ElevatorWindow.TOP = 1
ElevatorWindow.WIDTH = 7
ElevatorWindow.HEIGHT = 4

-- pokefirered/src/field_specials.c:1108
ElevatorWindow.LABEL_RIGHT = 56

local TEMPLATE = Window.template(ElevatorWindow.LEFT, ElevatorWindow.TOP,
  ElevatorWindow.WIDTH, ElevatorWindow.HEIGHT)

ElevatorWindow.visible = false
ElevatorWindow._label = nil
ElevatorWindow._owner = nil

local function fieldOwner()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.vm or nil
end

-- pokefirered/src/field_specials.c:1102
function ElevatorWindow.show(floorLabel)
  ElevatorWindow.visible = true
  ElevatorWindow._label = floorLabel and tostring(floorLabel) or nil
  ElevatorWindow._owner = fieldOwner()
  return true
end

-- pokefirered/src/field_specials.c:1113
function ElevatorWindow.hide()
  ElevatorWindow.visible = false
  ElevatorWindow._label = nil
  ElevatorWindow._owner = nil
  return true
end

ElevatorWindow.reset = ElevatorWindow.hide

function ElevatorWindow.isVisible()
  if ElevatorWindow.visible and ElevatorWindow._owner ~= fieldOwner() then
    ElevatorWindow.hide()
  end
  return ElevatorWindow.visible
end

function ElevatorWindow.label()
  return ElevatorWindow._label
end

-- pokefirered/src/field_specials.c:1107
function ElevatorWindow.labelX()
  local label = ElevatorWindow._label
  if not label then return ElevatorWindow.LEFT * 8 end
  local w = (FrlgFont.measure and FrlgFont.measure(label)) or (6 * #label)
  return ElevatorWindow.LEFT * 8 + ElevatorWindow.LABEL_RIGHT - w
end

function ElevatorWindow.draw()
  if not ElevatorWindow.visible then return end
  local left, top = TEMPLATE.tilemapLeft, TEMPLATE.tilemapTop
  Window.stdFrame(TEMPLATE)
  -- pokefirered/src/field_specials.c:1105
  Window.printPx(RomText.plain("gText_NowOn"), left * 8, top * 8 + 2)
  local label = ElevatorWindow._label
  if label then
    -- pokefirered/src/field_specials.c:1108
    Window.printPx(label, ElevatorWindow.labelX(), top * 8 + 16)
  end
end

return ElevatorWindow
