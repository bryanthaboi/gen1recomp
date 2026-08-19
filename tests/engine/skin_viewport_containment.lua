package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TouchSkin = require("src.core.TouchSkin")
local Playfield = require("src.render.Playfield")
local Renderer = require("src.render.Renderer")
local Chrome = require("src.ui.gen2.Chrome")
local Zoom = require("src.render.Zoom")

local EPS = 1e-6

local function setWindow(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local function cfg(viewport, extra)
  return ([[
overlays = 1
overlay0_name = "bezel"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_viewport = "%s"
%s
overlay0_descs = 1
overlay0_desc0 = "nul,0.5,0.5,rect,0.02,0.02"
]]):format(viewport, extra or "")
end

local function useSkin(viewport, extra)
  local skin = assert(TouchSkin.parse(cfg(viewport, extra)))
  TouchSkin.setActive(skin)
  TouchSkin.setOverlayLive(false)
  return skin
end

local function inside(x, y, w, h, bx, by, bw, bh)
  return x >= bx - EPS and y >= by - EPS
    and x + w <= bx + bw + EPS and y + h <= by + bh + EPS
end

setWindow(640, 576)
TouchSkin.setActive(nil)
Renderer:init()
local plain = Renderer:frameRects()
eq(plain.cut, false, "no skin: no cutout")
eq(plain.vux, 0, "no skin: the picture starts at the window origin")
eq(plain.vuw, 640, "no skin: the picture is the whole window")
eq(plain.Sp, 4, "no skin: 640x576 fits four whole GB pixels")
eq(plain.uox, 0, "no skin: the UI letterbox fills the window")
eq(select(3, Playfield.rect(640, 576)), 640, "no skin: the playfield is the window")
eq(Chrome.fitScale(640, 576), 4, "no skin: Gold fits the window the same way")

local WINDOWS = {
  { 640, 576 }, { 1280, 720 }, { 1920, 1080 },
  { 800, 480 }, { 480, 800 }, { 360, 640 },
}
local VIEWPORTS = {
  "0.2335,0.0855,0.5335,0.830",
  "0.2,0.15,0.6,0.5",
  "0.05,0.05,0.9,0.35",
  "0.3,0.1,0.4,0.8",
}
local UI_SIZES = { { 160, 144 }, { 304, 144 } }

local escapes, uncut, cases = 0, 0, 0
for _, win in ipairs(WINDOWS) do
  setWindow(win[1], win[2])
  for _, vp in ipairs(VIEWPORTS) do
    useSkin(vp)
    Renderer:init()
    for _, size in ipairs(UI_SIZES) do
      Renderer:setUISize(size[1], size[2])
      for off = -8, 8 do
        Zoom.offset = off
        for _, fill in ipairs({ false, true }) do
          for _, centered in ipairs({ true, false }) do
            Renderer.uiFill = fill
            Renderer.uiCentered = centered
            Renderer.worldActive = true
            cases = cases + 1
            local r = Renderer:frameRects()
            local ux, uy, uw, uh = Renderer.clipToView(r, r.uox, r.uoy,
              r.uvpw, r.uvph)
            if not inside(ux, uy, uw, uh, r.vux, r.vuy, r.vuw, r.vuh) then
              escapes = escapes + 1
            end
            if uw < r.uvpw - EPS or uh < r.uvph - EPS then uncut = uncut + 1 end
            local vw, vh = Renderer:worldViewSize()
            local sp = Zoom.scale(r.Sp)
            if vw * sp > r.vuw + 2 * sp + EPS
              or vh * sp > r.vuh + 2 * sp + EPS then
              escapes = escapes + 1
            end
          end
        end
      end
    end
  end
end
check(cases > 1000, "the sweep covers every window x cutout x zoom x layout")
eq(escapes, 0, "no zoom, battle surface or UI layout puts a rect past the cutout")
eq(uncut, 0, "and the UI was sized to fit, so the clip never has to cut it")

setWindow(1280, 720)
useSkin("0.25,0.1,0.5,0.6")
Renderer:init()
Renderer:setUISize(160, 144)
Renderer.uiFill, Renderer.uiCentered = false, true
Zoom.offset = 0
local r = Renderer:frameRects()
eq(r.cut, true, "the skin's cutout is folded into the frame")
eq(r.vux, 320, "cutout x")
eq(r.vuy, 72, "cutout y")
eq(r.vuw, 640, "cutout width")
eq(r.vuh, 432, "cutout height")
eq(r.Sp, 3, "the fit is measured against the cutout, not the window")
check(inside(r.uox, r.uoy, r.uvpw, r.uvph, r.vux, r.vuy, r.vuw, r.vuh),
  "the UI letterbox sits inside the cutout")
check(inside(r.ox, r.oy, r.vpw, r.vph, r.vux, r.vuy, r.vuw, r.vuh),
  "so does the world letterbox")

local lo, hi = Zoom.offsetRange(r.Sp)
for off = lo, hi do
  Zoom.offset = off
  local z = Renderer:frameRects()
  check(inside(z.uox, z.uoy, z.uvpw, z.uvph, z.vux, z.vuy, z.vuw, z.vuh),
    "zoom " .. Zoom.offsetLabel(off) .. " keeps the UI in the cutout")
  local vw, vh = Renderer:worldViewSize()
  local sp = Zoom.scale(z.Sp)
  check(vw * sp <= z.vuw + 2 * sp and vh * sp <= z.vuh + 2 * sp,
    "zoom " .. Zoom.offsetLabel(off) .. " keeps the world pass capped")
end
Zoom.offset = 0

local capped = select(1, Renderer:worldViewSize())
useSkin("0.25,0.1,0.5,0.6", "overlay0_viewport_expand = true")
local expanded = select(1, Renderer:worldViewSize())
check(expanded > capped,
  "viewport_expand lets the survey world fill the cutout instead of the GB box")
useSkin("0.25,0.1,0.5,0.6")

setWindow(480, 800)
useSkin("0.3,0.1,0.4,0.3")
Renderer:init()
Renderer:setUISize(304, 144)
Renderer.uiFill, Renderer.uiCentered = false, true
local tight = Renderer:frameRects()
check(tight.vuw < 304, "the cutout cannot hold the WIDE battle at 1x")
check(inside(tight.uox, tight.uoy, tight.uvpw, tight.uvph,
  tight.vux, tight.vuy, tight.vuw, tight.vuh),
  "so the surface is scaled down to the cutout rather than over the bezel")
Renderer:setUISize(160, 144)

setWindow(1280, 720)
useSkin("0.25,0.1,0.5,0.6")
local px, py, pw, ph, active = Playfield.rect(1280, 720)
eq(active, true, "Gold sees the cutout too")
eq(pw, 480, "the playfield is a whole multiple of 160")
eq(ph, 432, "and of 144")
check(inside(px, py, pw, ph, 320, 72, 640, 432),
  "centred inside the cutout")
eq(Chrome.fitScale(1280, 720), 3, "Chrome fits the playfield")
local cox, coy = Chrome.fitOrigin(1280, 720)
eq(cox, px, "and centres the panel on it")
eq(coy, py, "on both axes")

useSkin("0.25,0.1,0.5,0.6", "overlay0_viewport_expand = true")
local ex, ey, ew, eh = Playfield.rect(1280, 720)
eq(ew, 640, "expand hands the picture the full cutout width")
eq(eh, 432, "and its full height")
eq(ex, 320, "at the cutout origin")
eq(ey, 72, "on both axes")
useSkin("0.25,0.1,0.5,0.6")

local ew2, eh2, ex2, ey2, act2 = Playfield.push(1280, 720)
eq(act2, true, "push reports the frame is contained")
eq(ex2, px, "push translates to the playfield origin")
eq(ey2, py, "on both axes")
eq(ew2, pw, "and hands the scene the playfield size")
eq(Playfield.cutout(ew2, eh2), nil, "inside the frame there is no cutout left")
eq(select(3, Playfield.rect(ew2, eh2)), pw, "so the playfield is the surface")
eq(Chrome.fitScale(ew2, eh2), 3, "and Chrome fits it without re-applying")
eq(select(1, Chrome.fitOrigin(ew2, eh2)), 0, "at a local origin")
eq(select(1, Playfield.dimensions()), pw, "screens read the playfield as the display")
Playfield.pop()
eq(Playfield.entered, false, "pop leaves the frame")
eq(select(1, Playfield.cutout(1280, 720)), 320, "and the cutout is visible again")

useSkin("0.4,0.4,0.1,0.1")
local sx, sy, sw, sh = Playfield.rect(1280, 720)
check(inside(sx, sy, sw, sh, 512, 288, 128, 72),
  "a cutout smaller than 160x144 still bounds the playfield")
check(sw <= 128 and sh <= 72, "the playfield never exceeds the cutout")

TouchSkin.setActive(nil)
eq(Playfield.cutout(1280, 720), nil, "no skin, no cutout")
eq(select(3, Playfield.rect(1280, 720)), 1280, "and the playfield is the window")
local saved = TouchSkin.viewport
TouchSkin.viewport = function() error("boom") end
eq(Playfield.cutout(1280, 720), nil, "a throwing viewport is no cutout")
TouchSkin.viewport = function() return 10, 10, 0, 0 end
eq(Playfield.cutout(1280, 720), nil, "a zero-sized cutout is no cutout")
TouchSkin.viewport = function() return -50, -50, 200, 200 end
eq(select(1, Playfield.cutout(1280, 720)), 0, "a cutout off the surface is clamped")
eq(select(3, Playfield.cutout(1280, 720)), 150, "to what is left of it")
TouchSkin.viewport = saved
TouchSkin.setActive(nil)
setWindow(640, 576)

T.finish("skin_viewport_containment")
