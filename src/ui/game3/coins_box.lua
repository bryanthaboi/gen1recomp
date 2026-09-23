
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")

local CoinsBox = {}

-- pokefirered/include/constants/coins.h:4
CoinsBox.MAX_COINS = 9999

CoinsBox.visible = false
CoinsBox.x = 1
CoinsBox.y = 1
CoinsBox._amount = 0

local function session_coins()
  local okC, Coins = pcall(require, "src.core.game3.coins")
  if okC and type(Coins) == "table" and type(Coins.get) == "function" then
    local okG, n = pcall(Coins.get)
    if okG and tonumber(n) then return tonumber(n) end
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  return tonumber(session and session.coins) or 0
end

local function clamp(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then return 0 end
  if n > CoinsBox.MAX_COINS then return CoinsBox.MAX_COINS end
  return n
end

function CoinsBox.show(x, y, amount)
  CoinsBox.visible = true
  CoinsBox.x = tonumber(x) or 1
  CoinsBox.y = tonumber(y) or 1
  if amount ~= nil then
    CoinsBox._amount = clamp(amount)
  else
    CoinsBox._amount = clamp(session_coins())
  end
end

function CoinsBox.hide()
  CoinsBox.visible = false
end

function CoinsBox.update(amount)
  if not CoinsBox.visible then return end
  if amount ~= nil then
    CoinsBox._amount = clamp(amount)
  else
    CoinsBox._amount = clamp(session_coins())
  end
end

function CoinsBox.isVisible()
  return CoinsBox.visible
end

function CoinsBox.amount()
  return CoinsBox._amount
end

-- pokefirered/src/coins.c:52
function CoinsBox.countText(amount)
  return (RomText.plain("gText_Coins", { stringVars = { string.format("%4d", clamp(amount)) } }))
end

function CoinsBox.draw()
  if not CoinsBox.visible then return end
  -- pokefirered/src/coins.c:79
  local left = CoinsBox.x + 1
  local top = CoinsBox.y + 1
  Window.stdFrame(Window.template(left, top, 8, 3))
  Window.printPx(RomText.plain("gText_Coins_2"), left * 8, top * 8)
  local countStr = CoinsBox.countText(CoinsBox._amount)
  local cw = (FrlgFont.measure and FrlgFont.measure(countStr, { small = true })) or (6 * #countStr)
  -- pokefirered/src/coins.c:76
  FrlgFont.draw(countStr, math.max(left * 8, (left + 8) * 8 - cw), top * 8 + 12,
    { small = true, colors = FrlgFont.COLOR.NORMAL })
end

return CoinsBox
