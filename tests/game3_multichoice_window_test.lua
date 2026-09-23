package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = (function()
  local en = { gText_Yes = "YES", gText_No = "NO", gText_BattleYesNoChoice = "Yes\nNo" }
  local function plain(key) return en[key] or key end
  return {
    plain = plain, box = plain, ascii = plain, has = function() return true end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end)()

local frames = {}
package.loaded["src.ui.game3.window"] = {
  OPTION_HEIGHT = 16,
  CURSOR_WIDTH = 8,
  template = function(left, top, width, height)
    return { left = left, top = top, w = width, h = height }
  end,
  stdFrame = function(tpl)
    frames[#frames + 1] = { tpl.left, tpl.top, tpl.w, tpl.h }
  end,
  menuRowPx = function(topPx, i) return topPx + (i - 1) * 16 end,
  cursorPx = function() end,
  printPx = function() end,
}
package.loaded["src.ui.game3.hud"] = { ensure = function() end }
package.loaded["src.core.game3.runtime"] = { isActive = function() return true end }
package.loaded["src.core.game3.scripting.multichoice"] = {
  resolve = function(listId)
    if listId == 99 then
      return { "TRADE CENTER", "EXIT" }, { left = 22, top = 8 }
    end
    return { "ONE", "TWO", "EXIT" }, { left = 22, top = 8 }
  end,
}

local Choice = require("src.ui.game3.choice")
local Adapters = require("src.core.game3.scripting.adapters")

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

local adapters = Adapters.host(nil, nil, nil)

local function frameFor(row)
  for i = #frames, 1, -1 do frames[i] = nil end
  Choice.active = false
  adapters.multichoice(row, function() end)
  Choice.draw()
  local f = frames[#frames]
  Choice.active = false
  return f
end

local function expectFrame(row, ex, ey, label)
  local f = frameFor(row)
  check(f ~= nil and f[1] == ex and f[2] == ey,
    ("%s: window content at tiles (%d,%d), got (%s,%s)"):format(label, ex, ey,
      tostring(f and f[1]), tostring(f and f[2])))
end

expectFrame({ op = "multichoice", 0, 0, 5, 0 }, 1, 1, "multichoice 0,0")
expectFrame({ op = "multichoice", 20, 8, 10, 0 }, 21, 9, "multichoice 20,8")
expectFrame({ op = "multichoicedefault", 11, 0, 4, 1, 0 }, 12, 1, "multichoicedefault 11,0")
expectFrame({ op = "multichoicegrid", 11, 0, 3, 0, 2 }, 12, 1, "multichoicegrid 11,0")

do
  local f = frameFor({ op = "multichoice", 20, 8, 99, 0 })
  check(f ~= nil and f[1] + f[3] == 29 and f[2] == 9,
    ("multichoice 20,8 wide list clamped to right edge 29, got x=%s w=%s"):format(
      tostring(f and f[1]), tostring(f and f[3])))
  local g = frameFor({ op = "multichoicegrid", 20, 8, 99, 0, 1 })
  check(g ~= nil and g[1] == 21,
    ("multichoicegrid 20,8 not clamped, got x=%s"):format(tostring(g and g[1])))
end

for i = #frames, 1, -1 do frames[i] = nil end
Choice.yesNo(function() end, { left = 22, top = 8 })
Choice.draw()
Choice.active = false
local yn = frames[#frames]
check(yn ~= nil and yn[1] == 22, "yes/no after multichoice keeps its own left (22)")

for i = #frames, 1, -1 do frames[i] = nil end
Choice.multi({ "A", "B" }, 0, function() end, { left = 14, top = 2 })
Choice.draw()
Choice.active = false
local f = frames[#frames]
check(f ~= nil and f[1] == 14 and f[2] == 2, "non-script Choice.multi layout left unshifted at (14,2)")

if fails > 0 then
  print(("[test] %d failed, %d ok"):format(fails, oks))
  os.exit(1)
end
print(("[test] all passed (%d ok)"):format(oks))
