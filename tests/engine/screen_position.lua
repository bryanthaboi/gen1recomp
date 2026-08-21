package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local ScreenPosition = require("src.core.ScreenPosition")
local TouchSkin = require("src.core.TouchSkin")
local Renderer = require("src.render.Renderer")
local Chrome = require("src.ui.gen2.Chrome")
local Zoom = require("src.render.Zoom")

eq(ScreenPosition.normalize(nil), "center", "no setting is CENTER")
eq(ScreenPosition.normalize("junk"), "center", "garbage degrades to CENTER")
eq(ScreenPosition.normalize("top"), "top", "top passes through")
eq(ScreenPosition.label("upper"), "UPPER", "upper reads UPPER")

local seen, v = {}, "center"
for _ = 1, 3 do
  seen[#seen + 1] = ScreenPosition.label(v)
  v = ScreenPosition.cycle(v, 1)
end
eq(table.concat(seen, ","), "CENTER,UPPER,TOP", "the row cycles CENTER,UPPER,TOP")
eq(ScreenPosition.cycle("top", 1), "center", "and wraps back to CENTER")
eq(ScreenPosition.cycle("center", -1), "top", "stepping back lands on TOP")

ScreenPosition.setMode("center")
eq(ScreenPosition.lift(640, 288), 0, "CENTER never lifts")

ScreenPosition.setMode("top")
eq(ScreenPosition.lift(640, 288), 176, "TOP lifts the centered origin to 0")
eq(ScreenPosition.lift(288, 288), 0, "no slack, no lift")
eq(ScreenPosition.lift(144, 288), 0, "negative slack, no lift")
eq(ScreenPosition.lift(640, 288, 40), 136, "TOP stops at the safe-area inset")
eq(ScreenPosition.lift(640, 288, 999), 0,
  "a safe inset past center degrades to centered")

ScreenPosition.setMode("upper")
eq(ScreenPosition.lift(640, 288), 88, "UPPER lands halfway between")
eq(ScreenPosition.lift(640, 288, 40), 88, "a small inset leaves UPPER alone")
eq(ScreenPosition.lift(640, 288, 120), 56, "a large inset pushes UPPER down")

ScreenPosition.applyOptions({ screenPos = "top" })
eq(ScreenPosition.mode, "top", "applyOptions takes the stored key")
ScreenPosition.applyOptions(nil)
eq(ScreenPosition.mode, "center", "applyOptions without options is CENTER")

local function setWindow(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

setWindow(360, 640)
TouchSkin.setActive(nil)
Renderer:init()
Zoom.offset = 0

ScreenPosition.setMode("center")
local r = Renderer:frameRects()
eq(r.Sp, 2, "360x640 fits two whole GB pixels")
eq(r.lift, 0, "CENTER: no lift")
eq(r.oy, 176, "CENTER: the letterbox is centered")
local _, vhCenter = Renderer:worldViewSize()

ScreenPosition.setMode("top")
r = Renderer:frameRects()
eq(r.lift, 176, "TOP: the full centered slack lifts away")
eq(r.oy, 0, "TOP: the letterbox sits at the top edge")
eq(r.uoy, 0, "TOP: the UI letterbox follows")
eq(r.ox, math.floor((360 - 320) / 2), "TOP: horizontal centering is untouched")
local _, vhTop = Renderer:worldViewSize()
eq(vhTop, vhCenter + 2 * math.ceil(176 / 2),
  "TOP: the world canvas grows to keep the bottom covered")

ScreenPosition.setMode("upper")
r = Renderer:frameRects()
eq(r.oy, 88, "UPPER: the letterbox centers in the upper half")

ScreenPosition.setMode("top")
local ox, oy = Chrome.fitOrigin(360, 640)
eq(oy, 0, "TOP: Gold's letterbox sits at the top edge")
eq(ox, math.floor((360 - 320) / 2), "TOP: Gold's horizontal centering is untouched")
ScreenPosition.setMode("center")
local _, cy = Chrome.fitOrigin(360, 640)
eq(cy, 176, "CENTER: Gold's letterbox is centered")

ScreenPosition.setMode("top")
local skin = assert(TouchSkin.parse([[
overlays = 1
overlay0_name = "bezel"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_viewport = "0.1,0.1,0.8,0.4"
overlay0_descs = 1
overlay0_desc0 = "nul,0.5,0.5,rect,0.02,0.02"
]]))
TouchSkin.setActive(skin)
TouchSkin.setOverlayLive(false)
r = Renderer:frameRects()
eq(r.cut, true, "the skin viewport cuts the playfield")
eq(r.lift, 0, "a skin viewport disables the lift")
eq(select(1, ScreenPosition.skinActive(360, 640)), true,
  "skinActive sees the viewport")
local _, sy = Chrome.fitOrigin(360, 640)
local _, cy2 = (function()
  ScreenPosition.setMode("center")
  return Chrome.fitOrigin(360, 640)
end)()
eq(sy, cy2, "with a skin the Gold origin ignores the mode")
TouchSkin.setActive(nil)
ScreenPosition.setMode("center")

-- A hand-rolled centre in drawWidescreen skips the lift and the playfield
-- rect that Chrome.fitOrigin carries.
local listing = assert(io.popen('grep -rln "drawWidescreen" src/ui/gen2'))
local offenders = {}
for path in listing:lines() do
  local f = assert(io.open(path, "r"))
  local body = f:read("*a")
  f:close()
  if body:find("winH %- %d+ %* scale")
    or body:find("winH %- SCREEN_H %* scale") then
    offenders[#offenders + 1] = path
  end
end
listing:close()
check(#offenders == 0, "no Gold screen centres its widescreen panel by hand: "
  .. table.concat(offenders, " "))

T.finish("screen_position")
