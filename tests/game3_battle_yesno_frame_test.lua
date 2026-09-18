package.path = "./?.lua;./?/init.lua;" .. package.path

local calls = {}
package.loaded["src.ui.game3.window"] = {
  OPTION_HEIGHT = 15,
  CURSOR_WIDTH = 8,
  template = function(left, top, width, height)
    return { left = left, top = top, w = width, h = height }
  end,
  stdFrame = function(tpl)
    calls[#calls + 1] = { kind = "std", tpl.left, tpl.top, tpl.w, tpl.h }
  end,
  userFrame = function(tpl, frameType)
    calls[#calls + 1] = { kind = "user", tpl.left, tpl.top, tpl.w, tpl.h, frameType = frameType }
  end,
  menuRowPx = function(topPx, i) return topPx + (i - 1) * 15 end,
  cursorPx = function(px, py) calls[#calls + 1] = { kind = "cursor", px, py } end,
  printPx = function(lab, px, py) calls[#calls + 1] = { kind = "print", px, py, lab = lab } end,
}
local Runtime = { session = nil }
function Runtime.getSession() return Runtime.session end
package.loaded["src.core.game3.runtime"] = Runtime

local Choice = require("src.ui.game3.choice")

local fails, oks = 0, 0
local function check(cond, label)
  if cond then
    oks = oks + 1
    print("ok   " .. label)
  else
    fails = fails + 1
    print("FAIL " .. label)
  end
end

local function drawYesNo(layout)
  for i = #calls, 1, -1 do calls[i] = nil end
  Choice.yesNo(function() end, layout)
  Choice.draw()
  Choice.active = false
  return calls
end

local BATTLE = { left = 24, top = 9, style = "battle" }

for _, ft in ipairs({ 0, 3, 9 }) do
  Runtime.session = { options = { frameType = ft } }
  local c = drawYesNo(BATTLE)
  local f = c[1]
  local frames = 0
  for _, e in ipairs(c) do
    if e.kind == "user" or e.kind == "std" then frames = frames + 1 end
  end
  check(frames == 1 and f.kind == "user", ("battle yes/no frame %d uses the user frame, not std"):format(ft))
  check(f and f[1] == 24 and f[2] == 9 and f[3] == 5 and f[4] == 4,
    ("battle yes/no frame %d content rect 24,9 5x4 (cart 23..29 x 8..13)"):format(ft))
  check(f and f.frameType == ft, ("battle yes/no follows options.frameType %d"):format(ft))
end

Runtime.session = { options = { frameType = 0 } }
do
  local c = drawYesNo(BATTLE)
  local cursor, prints = nil, {}
  for _, e in ipairs(c) do
    if e.kind == "cursor" then cursor = e end
    if e.kind == "print" then prints[#prints + 1] = e end
  end
  check(cursor and cursor[1] == 24 * 8 and cursor[2] == 9 * 8,
    "battle yes/no cursor sits on tile row 9 at column 24 (no pixel offset)")
  check(#prints == 2 and prints[1][2] == 9 * 8 + 2 and prints[2][2] == 11 * 8 + 2,
    "battle yes/no labels print at y=2 inside rows 9 and 11")
  for i = #calls, 1, -1 do calls[i] = nil end
  Choice.yesNo(function() end, BATTLE)
  Choice.move(1)
  Choice.draw()
  Choice.active = false
  local c2
  for _, e in ipairs(calls) do
    if e.kind == "cursor" then c2 = e end
  end
  check(c2 and c2[2] == 11 * 8, "battle yes/no cursor on No sits on tile row 11")
end

Runtime.session = nil
do
  local f = drawYesNo(BATTLE)[1]
  check(f and f.kind == "user" and f.frameType == 0, "battle yes/no with no session falls back to frame 0")
end

Runtime.session = { options = { frameType = 5 } }
do
  local f = drawYesNo({ left = 22, top = 8 })[1]
  check(f and f.kind == "std", "field yes/no keeps the std frame")
end

do
  local src = io.open("src/ui/game3/evolution_scene.lua", "rb")
  local text = src and src:read("*a") or ""
  if src then src:close() end
  check(text:find('Choice.yesNo%(function%(yes%).-end, { left = 24, top = 9, style = "battle" }%)') ~= nil,
    "evolution scene yes/no uses the battle window layout")
end

if fails > 0 then
  print(("[test] %d failed, %d ok"):format(fails, oks))
  os.exit(1)
end
print(("[test] all passed (%d ok)"):format(oks))
