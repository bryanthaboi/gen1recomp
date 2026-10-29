package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")

local printed, cursorAt, arrowAt
Chrome.print = function(text, tx, ty)
  printed[#printed + 1] = { text = tostring(text), x = tx, y = ty }
  return 0
end
Chrome.cursor = function(tx, ty) cursorAt = { x = tx, y = ty } end
Chrome.clear = function() end
Chrome.textbox = function() end
Font.drawCode = function(code, px, py)
  if code == Chrome.DOWN_ARROW then arrowAt = { x = px / 8, y = py / 8 } end
end

local function newStack()
  local stack = { items = {} }
  function stack:push(s) self.items[#self.items + 1] = s end
  function stack:pop() return table.remove(self.items) end
  function stack:top() return self.items[#self.items] end
  return stack
end

local function valued(row)
  return row.frame or row.text or row.values or type(row.value) == "function"
end

local function mixedView(rows)
  for _, row in ipairs(rows) do
    if not row.cancel and not valued(row) then return true end
  end
  return false
end

local function draw(menu)
  printed, cursorAt, arrowAt = {}, nil, nil
  menu:drawPanel()
  return printed
end

local function inspect(menu, tag)
  local rows = menu:visible()
  local mixed = mixedView(rows)
  draw(menu)
  local labels, byLine = {}, {}
  for _, p in ipairs(printed) do
    byLine[p.y] = byLine[p.y] or {}
    table.insert(byLine[p.y], p)
    if p.x == 2 then labels[#labels + 1] = p end
    check(p.y >= 1 and p.y <= 16, tag .. ": '" .. p.text .. "' inside the box rows (y=" .. p.y .. ")")
    check(p.x >= 1 and p.x + #p.text - 1 <= 18,
      tag .. ": '" .. p.text .. "' inside the box columns (x=" .. p.x .. ")")
  end
  for y, line in pairs(byLine) do
    for a = 1, #line do
      for b = a + 1, #line do
        local p, q = line[a], line[b]
        local apart = p.x + #p.text <= q.x or q.x + #q.text <= p.x
        check(apart, tag .. ": '" .. p.text .. "' and '" .. q.text .. "' overlap on row " .. y)
      end
    end
  end
  table.sort(labels, function(a, b) return a.y < b.y end)
  for n, label in ipairs(labels) do
    check(not (byLine[label.y - 1] and byLine[label.y - 1][1].x == 2),
      tag .. ": label '" .. label.text .. "' has no label directly above it")
    if mixed and n > 1 then
      check(byLine[label.y - 1] == nil,
        tag .. ": the line above '" .. label.text .. "' (row " .. label.y
        .. ") is blank, nothing from the row before touches it")
    end
  end
  if not mixed then
    for n, label in ipairs(labels) do
      eq(label.y, 2 + (n - 1) * 2, tag .. ": all-value page keeps the StringOptions pitch")
    end
  end
  check(cursorAt ~= nil, tag .. ": cursor drawn for row " .. menu.index)
  if cursorAt then
    eq(cursorAt.x, 1, tag .. ": cursor in column 1")
    local onLabel = false
    for _, label in ipairs(labels) do
      if label.y == cursorAt.y then onLabel = true end
    end
    check(onLabel, tag .. ": cursor sits on a label row (y=" .. cursorAt.y .. ")")
    check(not (arrowAt and arrowAt.x == cursorAt.x and arrowAt.y == cursorAt.y),
      tag .. ": cursor and down arrow never share a cell")
  end
  if arrowAt then
    check(byLine[arrowAt.y] == nil or byLine[arrowAt.y][1].x > arrowAt.x,
      tag .. ": down arrow cell is free")
  end
  return labels
end

local realGetOS = love.system.getOS
local realGetenv = os.getenv

local function withPlatform(osName, touchEnv, fn)
  love.system.getOS = function() return osName end
  os.getenv = function(k)
    if k == "POKEPORT_TOUCH" then return touchEnv end
    return realGetenv(k)
  end
  local ok, err = pcall(fn)
  love.system.getOS = realGetOS
  os.getenv = realGetenv
  if not ok then error(err, 0) end
end

local platforms = {
  { "OS X", "0" }, { "OS X", "1" }, { "Android", nil }, { "iOS", nil },
}

for _, p in ipairs(platforms) do
  withPlatform(p[1], p[2], function()
    for _, version in ipairs({ "gold", "silver", "crystal" }) do
      GameVersion.set(version)
      local tag = version .. " " .. p[1] .. " touch=" .. tostring(p[2])
      local game = { data = { audio = { sfx = {} } }, options = {},
                     stack = newStack(),
                     input = { wasPressed = function() return false end } }
      local menu = OptionsMenu.new(game, { options = game.options })
      game.stack:push(menu)
      local view = menu:visible()

      menu.index, menu.scroll = 1, 0
      menu:ensureVisible()
      local first = inspect(menu, tag .. " top page 1")
      local names = {}
      for _, l in ipairs(first) do names[#names + 1] = l.text end
      local joined = table.concat(names, ",")
      check(joined:find("PERFORMANCE", 1, true) ~= nil, tag .. ": PERFORMANCE on page 1 (" .. joined .. ")")
      check(joined:find("BATTLE OPTIONS", 1, true) ~= nil, tag .. ": BATTLE OPTIONS still on page 1 (" .. joined .. ")")

      local seen = {}
      for i = 1, #view do
        menu.index = i
        menu:ensureVisible()
        inspect(menu, tag .. " top cursor " .. i)
        seen[i] = cursorAt ~= nil
      end
      for i = #view, 1, -1 do
        menu.index = i
        menu:ensureVisible()
        inspect(menu, tag .. " top cursor up " .. i)
      end
      for i = 1, #view do check(seen[i], tag .. ": row " .. i .. " reachable on screen") end

      for i, row in ipairs(view) do
        if row.group then
          menu.index = i
          row.activate(game)
          local page = game.stack:top()
          check(page ~= menu, tag .. " " .. row.id .. ": page opened")
          for k = 1, #page:visible() do
            page.index = k
            page:ensureVisible()
            inspect(page, tag .. " " .. row.id .. " cursor " .. k)
          end
          game.stack:pop()
        end
      end
    end
  end)
end

T.finish()
