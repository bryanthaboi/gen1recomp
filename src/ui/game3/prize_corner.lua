-- pokefirered/src/script_menu.c:713

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")

local PrizeCorner = {}

-- pokefirered/include/constants/menu.h:21
PrizeCorner.LIST_POKEMON_PRIZES = 14
PrizeCorner.LIST_COIN_PURCHASE = 27
PrizeCorner.LIST_TM_PRIZES = 30
PrizeCorner.LIST_BATTLE_ITEM_PRIZES = 41

-- pokefirered/include/constants/menu.h:4
PrizeCorner.SCR_MENU_CANCEL = 127

-- pokefirered/src/strings.c:425
PrizeCorner.COLUMNS = {
  [PrizeCorner.LIST_POKEMON_PRIZES] = { 0x55, 0x55, 0x4B, 0x4B, 0x4B },
  [PrizeCorner.LIST_COIN_PURCHASE] = { 0x45, 0x40 },
  [PrizeCorner.LIST_TM_PRIZES] = { 0x48, 0x48, 0x48, 0x48, 0x48 },
  [PrizeCorner.LIST_BATTLE_ITEM_PRIZES] = { 0x5A, 0x50, 0x50, 0x50, 0x50 },
}

-- pokefirered/src/strings.c:425
PrizeCorner.NAME_SMALL = {
  [PrizeCorner.LIST_COIN_PURCHASE] = true,
}

-- pokefirered/src/script_menu.c:754
PrizeCorner.WINDOW_HEIGHT = { [0] = 1, 2, 4, 6, 7, 9, 11, 13, 14 }

-- pokefirered/src/script_menu.c:745
PrizeCorner.TEXT_OX = 8
PrizeCorner.TEXT_OY = 2
PrizeCorner.ROW_PITCH = 14

PrizeCorner.open = false
PrizeCorner.listId = nil
PrizeCorner.rows = nil
PrizeCorner.cursor = 1
PrizeCorner.wrapAround = false
PrizeCorner.ignoreBPress = false

function PrizeCorner.isPrizeList(listId)
  return PrizeCorner.COLUMNS[tonumber(listId) or -1] ~= nil
end

local function starts_amount(token)
  if token == nil or token == "" then return false end
  local b = token:byte(1)
  if b >= 0x30 and b <= 0x39 then return true end
  return token:sub(1, 2) == "\194\165"
end

-- pokefirered/src/strings.c:425
function PrizeCorner.splitLabel(label)
  label = tostring(label or "")
  local tokens, starts = {}, {}
  local at = 1
  while true do
    local s, e = label:find("%S+", at)
    if not s then break end
    tokens[#tokens + 1] = label:sub(s, e)
    starts[#starts + 1] = s
    at = e + 1
  end
  local cut = nil
  for i = #tokens, 1, -1 do
    if starts_amount(tokens[i]) then
      cut = i
      break
    end
  end
  if not cut or cut == 1 then return label, nil end
  local name = label:sub(1, starts[cut] - 1):gsub("%s+$", "")
  return name, label:sub(starts[cut])
end

-- pokefirered/src/script_menu.c:745
function PrizeCorner.buildRows(listId, labels)
  local columns = PrizeCorner.COLUMNS[tonumber(listId) or -1]
  if not columns then return nil end
  local small = PrizeCorner.NAME_SMALL[tonumber(listId)] and true or false
  local rows = {}
  for i, entry in ipairs(labels or {}) do
    local given = (type(entry) == "table") and entry or nil
    local label = given and given.label or entry
    local column = given and tonumber(given.stop) or columns[i]
    local name, amount
    if given and given.name then
      name, amount = given.name, given.amount
    else
      name, amount = PrizeCorner.splitLabel(label)
    end
    if not column then
      name, amount = tostring(label or ""), nil
    end
    rows[i] = {
      label = tostring(label or ""),
      name = name,
      amount = amount,
      column = column,
      nameSmall = (given and given.small ~= nil) and (given.small and true or false) or small,
      amountSmall = true,
    }
  end
  return rows
end

-- pokefirered/src/text.c:1123
function PrizeCorner.rowWidth(row)
  if not row then return 0 end
  local width = FrlgFont.measure(row.name, { small = row.nameSmall })
  if row.column and row.amount then
    if row.column > width then width = row.column end
    width = width + FrlgFont.measure(row.amount, { small = row.amountSmall })
  end
  return width
end

-- pokefirered/src/script_menu.c:736
function PrizeCorner.layout(listId, rows, left, top)
  local widest = 0
  for _, row in ipairs(rows or {}) do
    local w = PrizeCorner.rowWidth(row)
    if w > widest then widest = w end
  end
  local width = math.floor((widest + 9) / 8) + 1
  left = tonumber(left) or 0
  if left + width > 28 then left = 28 - width end
  local count = #(rows or {})
  local height = PrizeCorner.WINDOW_HEIGHT[count] or 1
  return {
    left = left,
    top = tonumber(top) or 0,
    width = width,
    height = height,
    -- pokefirered/src/script_menu.c:1195
    tileX = left + 1,
    tileY = (tonumber(top) or 0) + 1,
  }
end

-- pokefirered/src/script_menu.c:799
function PrizeCorner.wrapsAround(count)
  return (tonumber(count) or 0) > 3
end

function PrizeCorner.isOpen()
  return PrizeCorner.open and true or false
end

function PrizeCorner.show(opts)
  opts = opts or {}
  local listId = tonumber(opts.listId)
  local rows = PrizeCorner.buildRows(listId, opts.labels)
  if not rows or #rows == 0 then return false end
  PrizeCorner.open = true
  PrizeCorner.listId = listId
  PrizeCorner.rows = rows
  PrizeCorner.geom = PrizeCorner.layout(listId, rows, opts.left, opts.top)
  PrizeCorner._tpl = Window.template(PrizeCorner.geom.tileX, PrizeCorner.geom.tileY,
    PrizeCorner.geom.width, PrizeCorner.geom.height)
  PrizeCorner.cursor = (tonumber(opts.default) or 0) + 1
  if PrizeCorner.cursor < 1 or PrizeCorner.cursor > #rows then PrizeCorner.cursor = 1 end
  PrizeCorner.wrapAround = PrizeCorner.wrapsAround(#rows)
  PrizeCorner.ignoreBPress = opts.ignoreBPress and true or false
  PrizeCorner._done = opts.onChoose
  Stack.push("prize_corner", PrizeCorner, { hideBelow = false, drawUnder = true })
  return true
end

local function finish(result)
  local cb = PrizeCorner._done
  PrizeCorner._done = nil
  PrizeCorner.open = false
  PrizeCorner.rows = nil
  Stack.pop("prize_corner")
  if cb then cb(result) end
end

local function se()
  pcall(function() require("src.core.game3.audio").playSe(5) end)
end

-- pokefirered/src/script_menu.c:818
function PrizeCorner.move(delta)
  if not (PrizeCorner.open and PrizeCorner.rows) then return end
  local n = #PrizeCorner.rows
  if n < 1 or delta == 0 then return end
  local next1 = PrizeCorner.cursor + delta
  if PrizeCorner.wrapAround then
    next1 = ((next1 - 1) % n) + 1
  elseif next1 < 1 or next1 > n then
    return
  end
  if next1 ~= PrizeCorner.cursor then
    PrizeCorner.cursor = next1
    se()
  end
end

function PrizeCorner.confirm()
  if not PrizeCorner.open then return end
  se()
  finish(PrizeCorner.cursor - 1)
end

-- pokefirered/src/script_menu.c:828
function PrizeCorner.cancel()
  if not PrizeCorner.open then return end
  if PrizeCorner.ignoreBPress then return end
  se()
  finish(PrizeCorner.SCR_MENU_CANCEL)
end

function PrizeCorner.handleInput(input)
  if not (PrizeCorner.open and input) then return end
  if input:wasPressed("up") then
    PrizeCorner.move(-1)
  elseif input:wasPressed("down") then
    PrizeCorner.move(1)
  elseif input:wasPressed("a") then
    PrizeCorner.confirm()
  elseif input:wasPressed("b") then
    PrizeCorner.cancel()
  end
end

function PrizeCorner.rowPx(index1)
  local g = PrizeCorner.geom
  if not g then return 0, 0 end
  return g.tileX * 8, g.tileY * 8 + PrizeCorner.TEXT_OY + (index1 - 1) * PrizeCorner.ROW_PITCH
end

function PrizeCorner.draw()
  if not (PrizeCorner.open and PrizeCorner.rows and PrizeCorner.geom) then return end
  if not (love and love.graphics) then return end
  local g = PrizeCorner.geom
  Window.stdFrame(PrizeCorner._tpl or Window.template(g.tileX, g.tileY, g.width, g.height))
  for i, row in ipairs(PrizeCorner.rows) do
    local baseX, y = PrizeCorner.rowPx(i)
    if i == PrizeCorner.cursor then
      Window.cursorPx(baseX, y)
    end
    Window.printPx(row.name, baseX + PrizeCorner.TEXT_OX, y, { small = row.nameSmall })
    if row.column and row.amount then
      Window.printPx(row.amount, baseX + PrizeCorner.TEXT_OX + row.column, y,
        { small = row.amountSmall })
    end
  end
end

function PrizeCorner.reset()
  PrizeCorner.open = false
  PrizeCorner.rows = nil
  PrizeCorner.geom = nil
  PrizeCorner._tpl = nil
  PrizeCorner._done = nil
  PrizeCorner.cursor = 1
  Stack.pop("prize_corner")
  return true
end

return PrizeCorner
