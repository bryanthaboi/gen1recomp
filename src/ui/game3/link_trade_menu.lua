local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Strings = require("src.core.Strings")

local LinkTradeMenu = {}

-- pokefirered/src/trade.c:596 sWindowTemplates
LinkTradeMenu.MINE_TEMPLATE = Window.template(0, 0, 16, 9)
LinkTradeMenu.THEIRS_TEMPLATE = Window.template(0, 9, 16, 9)

LinkTradeMenu.open = false
LinkTradeMenu.side = "mine"
LinkTradeMenu.cursor = 1
LinkTradeMenu.theirCursor = 1
LinkTradeMenu.onCancelRow = false
LinkTradeMenu.confirming = false
LinkTradeMenu.confirmChoice = 1
LinkTradeMenu.message = nil

local function trade()
  return require("src.core.game3.link.trade")
end

local function link()
  return require("src.core.game3.link")
end

local function myParty()
  local s = link().session()
  return (s and s.party) or {}
end

function LinkTradeMenu.isOpen()
  return LinkTradeMenu.open and true or false
end

-- pokefirered/src/trade.c:821 CB2_StartCreateTradeMenu
function LinkTradeMenu.show()
  if LinkTradeMenu.open then return true end
  LinkTradeMenu.open = true
  LinkTradeMenu.side = "mine"
  LinkTradeMenu.cursor = 1
  LinkTradeMenu.theirCursor = 1
  LinkTradeMenu.onCancelRow = false
  LinkTradeMenu.confirming = false
  LinkTradeMenu.confirmChoice = 1
  LinkTradeMenu.message = nil
  Stack.push("link_trade", LinkTradeMenu, { hideBelow = true })
  return true
end

function LinkTradeMenu.close()
  if not LinkTradeMenu.open then return false end
  LinkTradeMenu.open = false
  LinkTradeMenu.message = nil
  Stack.pop("link_trade")
  return true
end

function LinkTradeMenu.reset()
  LinkTradeMenu.open = false
  LinkTradeMenu.side = "mine"
  LinkTradeMenu.cursor = 1
  LinkTradeMenu.theirCursor = 1
  LinkTradeMenu.onCancelRow = false
  LinkTradeMenu.confirming = false
  LinkTradeMenu.confirmChoice = 1
  LinkTradeMenu.message = nil
  Stack.pop("link_trade")
  return true
end

function LinkTradeMenu.monLabel(mon)
  if not mon then return "" end
  if mon.isEgg then return Strings("EGG") end
  local name = mon.nickname
  if type(name) ~= "string" or name == "" then
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    name = okP and Pokemon and Pokemon.speciesName
      and Pokemon.speciesName(tonumber(mon.species) or 0) or nil
  end
  return tostring(name or mon.species or "")
end

-- pokefirered/src/trade.c:2008 CB_ProcessConfirmTradeInput
function LinkTradeMenu.confirm()
  local LT = trade()
  if LinkTradeMenu.confirming then
    -- pokefirered/src/trade.c:1976 CommunicateWhetherMonCanBeTraded
    local yes = LinkTradeMenu.confirmChoice == 1
    LinkTradeMenu.confirming = false
    LT.confirm(yes)
    return true
  end
  if LinkTradeMenu.onCancelRow then
    -- pokefirered/src/trade.c:2043 CB_ProcessCancelTradeInput
    LT.cancelSelect()
    LinkTradeMenu.message = Strings("Waiting...")
    return true
  end
  if LinkTradeMenu.side ~= "mine" then return false end
  -- pokefirered/src/trade.c:1811 SetReadyToTrade
  local ok, code = LT.offer(LinkTradeMenu.cursor)
  if ok then
    LinkTradeMenu.message = Strings("Waiting...")
    return true
  end
  local okT, Trade = pcall(require, "src.core.game3.scripting.natives_trade")
  LinkTradeMenu.message = (okT and Trade and Trade.refusalText and Trade.refusalText(code))
    or Strings("That POKéMON can't be traded\nnow.")
  return false
end

function LinkTradeMenu.cancel()
  if LinkTradeMenu.confirming then
    LinkTradeMenu.confirmChoice = 2
    return LinkTradeMenu.confirm()
  end
  trade().cancelSelect()
  LinkTradeMenu.message = Strings("Waiting...")
  return true
end

local function move(delta)
  if LinkTradeMenu.side == "theirs" then
    local n = #(trade().peerParty or {})
    if n < 1 then return end
    LinkTradeMenu.theirCursor = math.max(1, math.min(n, LinkTradeMenu.theirCursor + delta))
    return
  end
  local n = #myParty()
  local next = LinkTradeMenu.cursor + delta
  if next > n then
    LinkTradeMenu.onCancelRow = true
    return
  end
  if LinkTradeMenu.onCancelRow and delta < 0 then
    LinkTradeMenu.onCancelRow = false
    LinkTradeMenu.cursor = math.max(1, n)
    return
  end
  LinkTradeMenu.onCancelRow = false
  LinkTradeMenu.cursor = math.max(1, math.min(math.max(1, n), next))
end

-- pokefirered/src/trade.c:1830 CB_ProcessMenuInput
function LinkTradeMenu.handleInput(input)
  if not (input and LinkTradeMenu.open) then return end
  if LinkTradeMenu.message and input:wasPressed("a") then
    LinkTradeMenu.message = nil
    return
  end
  if LinkTradeMenu.message then return end
  if LinkTradeMenu.confirming then
    if input:wasPressed("up") or input:wasPressed("down") then
      LinkTradeMenu.confirmChoice = LinkTradeMenu.confirmChoice == 1 and 2 or 1
    elseif input:wasPressed("a") then
      LinkTradeMenu.confirm()
    elseif input:wasPressed("b") then
      LinkTradeMenu.confirmChoice = 2
      LinkTradeMenu.confirm()
    end
    return
  end
  if input:wasPressed("up") then move(-1)
  elseif input:wasPressed("down") then move(1)
  elseif input:wasPressed("right") then
    if #(trade().peerParty or {}) > 0 then LinkTradeMenu.side = "theirs" end
  elseif input:wasPressed("left") then LinkTradeMenu.side = "mine"
  elseif input:wasPressed("a") then LinkTradeMenu.confirm()
  elseif input:wasPressed("b") then LinkTradeMenu.cancel()
  end
end

-- pokefirered/src/trade.c:1939 CB_ShowTradeMonSummaryScreen
function LinkTradeMenu.update(_dt)
  if not LinkTradeMenu.open then return end
  local LT = trade()
  if LT.state == "confirm" and not LinkTradeMenu.confirming then
    LinkTradeMenu.confirming = true
    LinkTradeMenu.confirmChoice = 1
    LinkTradeMenu.message = nil
  elseif LT.state == "menu" and LinkTradeMenu.message == Strings("Waiting...") then
    LinkTradeMenu.message = nil
  end
  if LT.state ~= "menu" and LT.state ~= "ready_wait" and LT.state ~= "confirm"
      and LT.state ~= "confirm_wait" then
    LinkTradeMenu.close()
  end
end

function LinkTradeMenu.draw()
  if not (LinkTradeMenu.open and love and love.graphics) then return end
  local mine = LinkTradeMenu.MINE_TEMPLATE
  local theirs = LinkTradeMenu.THEIRS_TEMPLATE
  Window.stdFrame(mine)
  Window.stdFrame(theirs)
  local LT = trade()
  for i, mon in ipairs(myParty()) do
    local ty = Window.menuRowY(mine.top, i)
    if LinkTradeMenu.side == "mine" and not LinkTradeMenu.onCancelRow
        and i == LinkTradeMenu.cursor then
      Window.cursor(mine.left, ty)
    end
    Window.print(LinkTradeMenu.monLabel(mon), Window.labelTx(mine.left), ty)
  end
  local cancelY = Window.menuRowY(mine.top, #myParty() + 1)
  if LinkTradeMenu.onCancelRow then Window.cursor(mine.left, cancelY) end
  Window.print(Strings("CANCEL"), Window.labelTx(mine.left), cancelY)
  for i, mon in ipairs(LT.peerParty or {}) do
    local ty = Window.menuRowY(theirs.top, i)
    if LinkTradeMenu.side == "theirs" and i == LinkTradeMenu.theirCursor then
      Window.cursor(theirs.left, ty)
    end
    Window.print(LinkTradeMenu.monLabel(mon), Window.labelTx(theirs.left), ty)
  end
  if LinkTradeMenu.confirming then
    -- pokefirered/src/trade.c:2008 CB_ProcessConfirmTradeInput
    local mineMon = myParty()[(LT.cursor or 0) + 1]
    local theirMon = (LT.peerParty or {})[(LT.partnerCursor or 0) + 1]
    Window.print(Strings("Trade %s for %s?",
      LinkTradeMenu.monLabel(mineMon), LinkTradeMenu.monLabel(theirMon)),
      Window.labelTx(mine.left), theirs.top - 2)
    Window.print(LinkTradeMenu.confirmChoice == 1 and Strings("> YES  NO")
      or Strings("  YES > NO"), Window.labelTx(mine.left), theirs.top - 1)
  elseif LinkTradeMenu.message then
    Window.print(LinkTradeMenu.message, Window.labelTx(mine.left), theirs.top - 2)
  end
end

return LinkTradeMenu
