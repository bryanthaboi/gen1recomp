package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TouchSkin = require("src.core.TouchSkin")
local FaithfulRes = require("src.core.FaithfulRes")
local Renderer = require("src.render.Renderer")
local Zoom = require("src.render.Zoom")
local Game = require("src.core.Game")
local TitleState = require("src.ui.TitleState")
local IntroMovie = require("src.ui.IntroMovie")

local function setWindow(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local function cfg(viewport)
  local vp = viewport and ('overlay0_viewport = "%s"\n'):format(viewport) or ""
  return ([[
overlays = 1
overlay0_name = "bezel"
overlay0_full_screen = true
overlay0_normalized = true
%soverlay0_descs = 1
overlay0_desc0 = "nul,0.5,0.5,rect,0.02,0.02"
]]):format(vp)
end

local function useSkin(viewport)
  local skin = assert(TouchSkin.parse(cfg(viewport)))
  TouchSkin.setActive(skin)
  TouchSkin.setOverlayLive(false)
  return skin
end

local title = setmetatable({}, { __index = TitleState })
local intro = setmetatable({}, { __index = IntroMovie })
local function stack(...) return { states = { ... } } end

TouchSkin.setActive(nil)
FaithfulRes.locked = false
eq(TitleState.wantsFillScale(nil), true, "no skin, no lock: the title fills")
eq(IntroMovie.wantsFillScale(nil), true, "no skin, no lock: the intro fills")

useSkin("0.15,0.08,0.7,0.84")
eq(TitleState.wantsFillScale(nil), false, "a skin with a cutout: the title stays integer")
eq(IntroMovie.wantsFillScale(nil), false, "a skin with a cutout: the intro stays integer")
eq(Game.fillScaleInStack(stack(title, {})), false,
  "a menu over the title inside a skin does not fill")

useSkin(nil)
eq(TitleState.wantsFillScale(nil), false, "a full-window bezel: the title stays integer")
eq(IntroMovie.wantsFillScale(nil), false, "a full-window bezel: the intro stays integer")

TouchSkin.setActive(nil)
eq(TitleState.wantsFillScale(nil), true, "clearing the skin restores the title fill")
eq(IntroMovie.wantsFillScale(nil), true, "clearing the skin restores the intro fill")

FaithfulRes.locked = true
eq(title:wantsFillScale(), false, "FAITHFUL RATIO locked: the title stays integer")
eq(intro:wantsFillScale(), false, "FAITHFUL RATIO locked: the intro stays integer")
check(FaithfulRes.scaleCap() == nil,
  "and that holds where scaleCap is nil (desktop / linux handheld)")
FaithfulRes.locked = false

local function frame(states, worldActive)
  Renderer.uiFill = Game.fillScaleInStack(stack(unpack(states)))
  Renderer.uiCentered = true
  Renderer.worldActive = worldActive
  return Renderer:frameRects()
end

setWindow(1024, 768)
Zoom.offset = 0
useSkin("0.15,0.08,0.7,0.84")
Renderer:init()
Renderer:setUISize(160, 144)
local tr = frame({ title }, false)
local ir = frame({ intro }, false)
local mr = frame({ title, {} }, false)
local ow = frame({ {} }, true)
eq(tr.cut, true, "1024x768 with a bezel cutout")
eq(tr.Up, Renderer:fitScale(), "title inside the bezel draws at the integer fit")
eq(tr.Up, math.floor(tr.Up), "and that scale is whole")
eq(ir.Up, ow.Up, "intro matches the overworld scale inside the bezel")
eq(tr.Up, ow.Up, "title matches the overworld scale inside the bezel")
eq(mr.Up, ow.Up, "main menu over the title matches the overworld scale")
check(tr.uvph <= tr.vuh and tr.uvpw <= tr.vuw, "title leaves a margin inside the cutout")

useSkin(nil)
local br = frame({ title }, false)
local bw = frame({ {} }, true)
eq(br.Up, bw.Up, "full-window bezel: title matches the overworld scale")

TouchSkin.setActive(nil)
local nr = frame({ title }, false)
local nw = frame({ {} }, true)
eq(nw.Up, 5, "no skin at 1024x768: the overworld fits 5x")
check(nr.Up > Renderer:fitScale(), "no skin: the title still fills past the integer fit")

FaithfulRes.locked = true
local lr = frame({ title }, false)
eq(lr.Up, 5, "FAITHFUL RATIO on a fixed linux panel: title back to whole pixels")
FaithfulRes.locked = false

T.finish("title_fill_skin_lock")
