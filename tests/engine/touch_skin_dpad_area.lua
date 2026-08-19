-- RetroArch dpad_area / abxy_area descs (#1533): one hitbox whose fired
-- input is resolved by the angle of the touch from the area centre, and
-- range_mod growing a hitbox only while it is held.  The cfg below is the
-- reporter's GBA skin, trimmed to the d-pad and face buttons.
--   luajit tests/engine/touch_skin_dpad_area.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local TouchSkin = require("src.core.TouchSkin")
local TouchControls = require("src.core.TouchControls")
local Input = require("src.core.Input")

local CFG = [[
overlays = 2

overlay0_name = "portrait"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_range_mod = 1.5
overlay0_alpha_mod = 1
overlay0_aspect_ratio = 0.45
overlay0_descs = 13
overlay0_desc0 = "select,0.41944,0.58793,radial,0.06667,0.03"
overlay0_desc0_overlay = p-btn-select.png
overlay0_desc0_reach_x = 1.25
overlay0_desc0_reach_y = 1.25
overlay0_desc1 = "start,0.58056,0.58793,radial,0.06667,0.03"
overlay0_desc1_overlay = p-btn-start.png
overlay0_desc1_reach_x = 1.25
overlay0_desc1_reach_y = 1.25
overlay0_desc2 = "up,0.25,0.6625,radial,0.07778,0.035"
overlay0_desc2_overlay = p-btn-dpad-up.png
overlay0_desc2_reach_x = 0
overlay0_desc3 = "left,0.12222,0.72,radial,0.07778,0.035"
overlay0_desc3_overlay = p-btn-dpad-left.png
overlay0_desc3_reach_x = 0
overlay0_desc4 = "right,0.37778,0.72,radial,0.07778,0.035"
overlay0_desc4_overlay = p-btn-dpad-right.png
overlay0_desc4_reach_x = 0
overlay0_desc5 = "down,0.25,0.7775,radial,0.07778,0.035"
overlay0_desc5_overlay = p-btn-dpad-down.png
overlay0_desc5_reach_x = 0
overlay0_desc6 = "up|left,0.11644,0.6599,radial,0.01667,0.0075"
overlay0_desc6_overlay = p-btn-corner.png
overlay0_desc6_reach_x = 0
overlay0_desc7 = "up|right,0.38356,0.6599,radial,0.01667,0.0075"
overlay0_desc7_overlay = p-btn-corner.png
overlay0_desc7_reach_x = 0
overlay0_desc8 = "down|left,0.11644,0.7801,radial,0.01667,0.0075"
overlay0_desc8_overlay = p-btn-corner.png
overlay0_desc8_reach_x = 0
overlay0_desc9 = "down|right,0.38356,0.7801,radial,0.01667,0.0075"
overlay0_desc9_overlay = p-btn-corner.png
overlay0_desc9_reach_x = 0
overlay0_desc10 = "dpad_area,0.25,0.72,radial,0.22778,0.1025"
overlay0_desc10_overlay = p-area-dpad.png
overlay0_desc10_reach_x = 1.25
overlay0_desc10_reach_y = 1.25
overlay0_desc11 = "a,0.84382,0.69563,radial,0.09722,0.04375"
overlay0_desc11_overlay = p-btn-act2-a.png
overlay0_desc11_reach_x = 1.25
overlay0_desc11_reach_y = 1.25
overlay0_desc12 = "b,0.65618,0.74438,radial,0.09722,0.04375"
overlay0_desc12_overlay = p-btn-act2-b.png
overlay0_desc12_reach_x = 1.25
overlay0_desc12_reach_y = 1.25

overlay1_name = "areas"
overlay1_full_screen = true
overlay1_normalized = true
overlay1_descs = 2
overlay1_desc0 = "dpad_area,0.25,0.5,rect,0.2,0.2"
overlay1_desc0_up = "start"
overlay1_desc0_down = "select"
overlay1_desc0_left = "nul"
overlay1_desc1 = "abxy_area,0.75,0.5,rect,0.2,0.2"
]]

local skin = assert(TouchSkin.parse(CFG))
local page = skin.pages[1]

eq(#page.controls, 12 + 1 + 8, "the dpad_area expands into eight sector controls")
local sectors = {}
for _, ctl in ipairs(page.controls) do
  if ctl.sector then sectors[ctl.sector] = ctl end
end
eq(#sectors, 8, "eight sectors, one per direction")
eq(sectors[1].spec, "right", "sector 1 is right")
eq(sectors[2].spec, "right|down", "sector 2 is the down-right diagonal")
eq(sectors[3].spec, "down", "sector 3 is down, y growing downwards")
eq(sectors[7].spec, "up", "sector 7 is up")
eq(sectors[1].x, 0.25, "every sector keeps the area centre")
eq(sectors[5].y, 0.72, "on both axes")
eq(sectors[3].rangeX, 0.22778, "and the whole area range")
eq(sectors[3].shape, "radial", "and the declared hitbox shape")

local art = page.controls[11]
eq(art.imagePath, "p-area-dpad.png", "the area art rides a decorative desc")
check(art.decorative, "which presses nothing")

TouchControls:init()
TouchControls.active = true
TouchControls.enabled = true
TouchSkin.setOverlayLive(true)
TouchSkin.setActive(skin)
Input:init()

local W, H = 720, 1600
TouchSkin.setSurface(0, 0, W, H)
eq(TouchSkin.page().name, "portrait", "the portrait page is live at 720x1600")

local BUTTONS = { "up", "down", "left", "right", "a", "b", "start", "select" }
local function heldNow()
  local out = {}
  for _, btn in ipairs(BUTTONS) do
    if Input:isDown(btn) then out[#out + 1] = btn end
  end
  return table.concat(out, "+")
end

local function press(nx, ny)
  TouchControls:touchpressed("f1", nx * W, ny * H)
  local got = heldNow()
  TouchControls:touchreleased("f1", nx * W, ny * H)
  return got
end

local function fires(nx, ny, want, why)
  eq(press(nx, ny), want, why)
end

fires(0.25, 0.6625, "up", "the d-pad up arrow fires up alone")
fires(0.12222, 0.72, "left", "the left arrow fires left alone")
fires(0.37778, 0.72, "right", "the right arrow fires right alone")
fires(0.25, 0.7775, "down", "the down arrow fires down alone")
fires(0.11644, 0.6599, "up+left", "the up-left corner fires both, and only both")
fires(0.38356, 0.7801, "down+right", "as does the down-right corner")

fires(0.32, 0.77, "down+right",
      "a spot inside the area but off every arrow resolves by angle: "
      .. "(50.4, 80) pixels out is 57.8 degrees, the down-right sector")

fires(0.84382, 0.69563, "a", "A fires alone")
fires(0.65618, 0.74438, "b", "B fires alone: the 1.5x range_mod does not grow the resting d-pad area over it")
fires(0.58056, 0.58793, "start", "START fires alone")
fires(0.41944, 0.58793, "select", "SELECT fires alone, with no phantom direction")
fires(0.5, 0.3, "", "the screen area presses nothing")

TouchControls:touchpressed("f2", 0.25 * W, 0.6625 * H)
eq(heldNow(), "up", "slide starts on up")
TouchControls:touchmoved("f2", 0.37778 * W, 0.72 * H)
eq(heldNow(), "right", "sliding across the area swaps direction")
TouchControls:touchmoved("f2", 0.38356 * W, 0.7801 * H)
eq(heldNow(), "down+right", "and picks up the diagonal")
TouchControls:touchmoved("f2", 0.5 * W, 0.3 * H)
eq(heldNow(), "", "sliding out of the area releases it")
TouchControls:touchreleased("f2", 0.5 * W, 0.3 * H)

local area = sectors[1]
local bx = 0.65618 * W
local by = 0.74438 * H
check(not TouchSkin.hits(page, area, W, H, bx, by, 0, 0, false),
      "at rest the area hitbox stops short of B")
check(TouchSkin.hits(page, area, W, H, bx, by, 0, 0, true),
      "a held area grows over B so the finger keeps its direction")
TouchControls:touchpressed("f3", 0.37778 * W, 0.72 * H)
TouchControls:touchmoved("f3", bx, by)
eq(heldNow(), "right+b", "sliding from the held area onto B keeps right held")
TouchControls:touchreleased("f3", bx, by)
eq(heldNow(), "", "and lifting clears both")

TouchSkin.autoOrient = false
TouchSkin.setPage("areas")
eq(TouchSkin.page().name, "areas", "second page is live")

W, H = 1000, 1000
TouchSkin.setSurface(0, 0, W, H)

fires(0.25, 0.35, "start", "_up rebinds the up sector of a dpad_area")
fires(0.25, 0.65, "select", "_down rebinds the down sector")
fires(0.12, 0.5, "", "_left = nul makes that sector inert")
fires(0.38, 0.5, "right", "an unset side keeps the d-pad default")

fires(0.88, 0.5, "a", "abxy_area right is GB A")
fires(0.75, 0.62, "b", "abxy_area down is GB B")
fires(0.88, 0.62, "a+b", "the down-right sector fires both")
fires(0.75, 0.38, "", "RetroPad X has no GB button, so up is inert")
fires(0.94, 0.68, "a+b", "a rect area still hits inside its corner")
fires(0.75, 0.75, "", "and nothing past its edge")

TouchSkin.setSurface(nil)
TouchSkin.setActive(nil)
TouchSkin.autoOrient = true

T.finish("touch_skin_dpad_area")
