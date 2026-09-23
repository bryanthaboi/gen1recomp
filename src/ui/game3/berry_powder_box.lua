-- pokefirered/src/berry_powder.c:113

local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")

local BerryPowderBox = {}

-- pokefirered/src/berry_powder.c:13
BerryPowderBox.MAX_BERRY_POWDER = 99999

-- pokefirered/src/berry_powder.c:120
local TEMPLATE = Window.template(1, 1, 8, 3)

BerryPowderBox.visible = false
BerryPowderBox._amount = 0
BerryPowderBox._owner = nil

local function fieldOwner()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.vm or nil
end

local function clamp(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then return 0 end
  if n > BerryPowderBox.MAX_BERRY_POWDER then return BerryPowderBox.MAX_BERRY_POWDER end
  return n
end

-- pokefirered/src/berry_powder.c:90
local function sessionPowder()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  return clamp(session and session.berryPowder)
end

function BerryPowderBox.show(amount)
  BerryPowderBox.visible = true
  BerryPowderBox._owner = fieldOwner()
  BerryPowderBox._amount = clamp(amount ~= nil and amount or sessionPowder())
  return true
end

-- pokefirered/src/berry_powder.c:108
function BerryPowderBox.update(amount)
  if not BerryPowderBox.visible then return false end
  BerryPowderBox._amount = clamp(amount ~= nil and amount or sessionPowder())
  return true
end

-- pokefirered/src/berry_powder.c:128
function BerryPowderBox.hide()
  BerryPowderBox.visible = false
  BerryPowderBox._owner = nil
  return true
end

BerryPowderBox.reset = BerryPowderBox.hide

function BerryPowderBox.isVisible()
  if BerryPowderBox.visible and BerryPowderBox._owner ~= fieldOwner() then
    BerryPowderBox.hide()
  end
  return BerryPowderBox.visible
end

function BerryPowderBox.amount()
  return BerryPowderBox._amount
end

-- pokefirered/src/berry_powder.c:97
function BerryPowderBox.amountText(amount)
  return string.format("%5d", clamp(amount))
end

function BerryPowderBox.draw()
  if not BerryPowderBox.visible then return end
  local px, py = TEMPLATE.tilemapLeft * 8, TEMPLATE.tilemapTop * 8
  Window.stdFrame(TEMPLATE)
  -- pokefirered/src/berry_powder.c:104
  FrlgFont.draw(RomText.plain("gOtherText_Powder"), px, py, { small = true, colors = FrlgFont.COLOR.NORMAL })
  -- pokefirered/src/berry_powder.c:105
  FrlgFont.draw(BerryPowderBox.amountText(BerryPowderBox._amount), px + 39, py + 12,
    { small = true, colors = FrlgFont.COLOR.NORMAL })
end

return BerryPowderBox
