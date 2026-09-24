#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local log = {}
local Renderer = { canvas = {}, worldCanvas = nil }
function Renderer:init() end
function Renderer:setUISize() end
function Renderer:beginFrame(transparent) log[#log + 1] = { "begin", transparent } end
function Renderer:beginWorldPass() log[#log + 1] = { "world" } end
function Renderer:endWorldPass() end
function Renderer:worldViewSize() return 240, 160 end
function Renderer:endFrame() log[#log + 1] = { "end" } end
package.loaded["src.render.Renderer"] = Renderer
package.loaded["src.render.PaletteFX"] = { mode = "gbc" }
package.loaded["src.render.Tilt"] = { active = function() return false end }

local battle = false
package.loaded["src.core.game3.battle"] = {
  isActive = function() return battle end,
  draw = function() end,
}
local noop = function() end
package.loaded["src.core.game3.oam"] = {
  resetFrame = noop, setLayer = function() return "ui" end, animateSprites = noop,
  buildOamBuffer = noop, flush = noop, flushPriority = noop,
}
package.loaded["src.core.game3.bg"] = { hasVisible = function() return false end, flushPriority = noop }
package.loaded["src.ui.game3.help_system"] = { isOpen = function() return false end, draw = noop }
local fieldDraws = 0
package.loaded["src.core.game3.field_view"] = { draw = function() fieldDraws = fieldDraws + 1 end }

local Stack = require("src.ui.game3.stack")
local Display = require("src.core.game3.display")
Display.setUiRenderer(noop)
Display.mirrorFlatFrame = noop

local function frame()
  for i = #log, 1, -1 do log[i] = nil end
  fieldDraws = 0
  assert(Display.present(nil, 1024, 768))
  local began, world = nil, false
  for _, e in ipairs(log) do
    if e[1] == "begin" then began = e[2] end
    if e[1] == "world" then world = true end
  end
  return began, world
end

local mod = { draw = noop }

Stack.clear()
local transparent, world = frame()
check(transparent == true and world and fieldDraws == 1, "bare field: transparent UI plane over the world pass")

Stack.push("start", mod, { hideBelow = true })
transparent, world = frame()
check(not Stack.fullscreen() and world and fieldDraws == 1, "start menu is an overlay: world pass still runs")

Stack.push("party", mod, { hideBelow = true, fullscreen = true })
transparent, world = frame()
check(Stack.fullscreen(), "party layer reports fullscreen")
check(transparent == false and not world and fieldDraws == 0, "full-screen layer: opaque UI plane, no world pass")

Stack.push("pin", mod, { hideBelow = false, drawUnder = true })
check(Stack.fullscreen(), "a drawUnder overlay above a full-screen layer keeps it full-screen")
Stack.pop("pin")

Stack.push("save", mod, { hideBelow = true })
transparent, world = frame()
check(not Stack.fullscreen() and world, "a hideBelow overlay above it hides it: field shows again")
Stack.pop("save")

Stack.pop("party")
Stack.push("bag", mod, { hideBelow = true, fullscreen = function() return false end })
check(not Stack.fullscreen(), "fullscreen evaluates a function flag")
Stack.clear()

Stack.push("trainer", mod, { hideBelow = true, fullscreen = true })
battle = true
transparent, world = frame()
check(transparent == false and not world, "battle keeps its own path")
battle = false
Stack.clear()

for _, spec in ipairs({
  { "src/ui/game3/union_chat.lua", "UnionChat.LAYER" },
  { "src/ui/game3/trainer_card.lua", "\"trainer\"" },
  { "src/ui/game3/link_menu.lua", "\"wireless_status\"" },
  { "src/ui/game3/party_menu.lua", "\"party\"" },
  { "src/ui/game3/pokedex.lua", "\"pokedex\"" },
  { "src/ui/game3/summary_menu.lua", "\"summary\"" },
  { "src/ui/game3/bag_menu.lua", "\"bag\"" },
}) do
  local fh = io.open(spec[1], "rb")
  local src = fh and fh:read("*a") or ""
  if fh then fh:close() end
  local line = src:match("Stack%.push%(" .. spec[2]:gsub("%p", "%%%0") .. "[^\n]*")
  check(line and line:find("fullscreen", 1, true) ~= nil, spec[1] .. " pushes a fullscreen layer")
end

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return ({ gText_Yes = "YES", gText_No = "NO" })[key] or key end,
}
local Window = require("src.ui.game3.window")
local Choice = require("src.ui.game3.choice")
local calls = {}
Window.stdFrame = function(t) calls[#calls + 1] = { "frame", t.left or t.tilemapLeft, t.top or t.tilemapTop, t.w or t.width, t.h or t.height } end
Window.cursorPx = function(x, y) calls[#calls + 1] = { "cursor", x, y } end
Window.printPx = function(s, x, y) calls[#calls + 1] = { "print", x, y, s } end

local function drawYesNo(layout, move)
  for i = #calls, 1, -1 do calls[i] = nil end
  Choice.yesNo(noop, layout)
  if move then Choice.move(1) end
  Choice.draw()
  Choice.reset()
  return calls
end

-- pokefirered/src/new_menu_helpers.c:48
local c = drawYesNo(nil)
check(c[1][1] == "frame" and c[1][2] == 21 and c[1][3] == 9 and c[1][4] == 6 and c[1][5] == 4,
  ("default yes/no is sYesNo_WindowTemplate 21,9 6x4, got %s,%s %sx%s"):format(
    tostring(c[1][2]), tostring(c[1][3]), tostring(c[1][4]), tostring(c[1][5])))
-- pokefirered/src/menu.c:540
local cur, prints = nil, {}
for _, e in ipairs(c) do
  if e[1] == "cursor" then cur = e end
  if e[1] == "print" then prints[#prints + 1] = e end
end
check(cur and cur[2] == 168 and cur[3] == 74, "cursor on YES at the window's left edge, y=2")
check(#prints == 2 and prints[1][2] == 176 and prints[1][3] == 74 and prints[2][3] == 88,
  "YES/NO print 8 px in at y=2 and y=16 (FONT_NORMAL 14 px pitch)")
c = drawYesNo({ left = 21, top = 9 }, true)
for _, e in ipairs(c) do if e[1] == "cursor" then cur = e end end
check(cur and cur[3] == 88, "cursor on NO sits one 14 px row down")
c = drawYesNo({ left = 20, top = 8 })
check(c[1][2] == 20 and c[1][3] == 8 and c[1][4] == 6, "explicit left/top still honored with the 6-tile width")

print(("game3_fullscreen_display_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
