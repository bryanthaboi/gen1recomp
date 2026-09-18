-- Field money HUD (pret DrawMoneyBox / showmoneybox). Tile coords from script.

local Window = require("src.ui.game3.window")

local MoneyBox = {}

MoneyBox.visible = false
MoneyBox.x = 19
MoneyBox.y = 1
MoneyBox._amount = 0

local function session_money()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  return tonumber(session and session.money) or 0
end

function MoneyBox.show(x, y, amount)
  MoneyBox.visible = true
  MoneyBox.x = tonumber(x) or 19
  MoneyBox.y = tonumber(y) or 1
  if amount ~= nil then
    MoneyBox._amount = math.max(0, math.floor(tonumber(amount) or 0))
  else
    MoneyBox._amount = session_money()
  end
end

function MoneyBox.hide()
  MoneyBox.visible = false
end

function MoneyBox.update(amount)
  if not MoneyBox.visible then return end
  if amount ~= nil then
    MoneyBox._amount = math.max(0, math.floor(tonumber(amount) or 0))
  else
    MoneyBox._amount = session_money()
  end
end

function MoneyBox.isVisible()
  return MoneyBox.visible
end

local FrlgFont = require("src.ui.game3.frlg_font")

function MoneyBox.draw()
  if not MoneyBox.visible then return end
  local x, y = MoneyBox.x, MoneyBox.y
  -- pret DrawMoneyBox: template = (x + 1, y + 1, 8, 3)
  local left = x + 1
  local top = y + 1
  Window.stdFrame(Window.template(left, top, 8, 3))
  Window.printPx("MONEY", left * 8, top * 8)
  local moneyStr = string.format("¥%d", MoneyBox._amount)
  local mw = (FrlgFont.measure and FrlgFont.measure(moneyStr, { small = true })) or (6 * #moneyStr)
  Window.printPx(moneyStr, math.max(left * 8, (left + 8) * 8 - mw), top * 8 + 12, { small = true })
end

return MoneyBox
