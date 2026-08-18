-- RetroArch-format touch skins (#1386): .cfg parsing, hitboxes, the press /
-- hotkey path through TouchControls, and the screen viewport the renderer
-- fits the Game Boy picture into.
--   luajit tests/engine/touch_skin_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local TouchSkin = require("src.core.TouchSkin")
local TouchControls = require("src.core.TouchControls")
local Input = require("src.core.Input")

local CFG = [[
overlays = 2

overlay0_name = "shell"
overlay0_overlay = img/back.png
overlay0_full_screen = true
overlay0_normalized = true
overlay0_alpha_mod = 0.001
overlay0_range_mod = 1.5
overlay0_viewport = "0.0,0.0,1.0,0.5"
overlay0_viewport_fill = true

overlay0_descs = 7
overlay0_desc0 = "a,0.80,0.75,radial,0.10,0.05"
overlay0_desc0_overlay = img/a.png
overlay0_desc1 = "left|down,0.20,0.90,rect,0.05,0.05"
overlay0_desc2 = "nul,0.20,0.75,rect,0.15,0.10"
overlay0_desc2_overlay = img/dpad.png
overlay0_desc3 = "overlay_next,0.95,0.55,radial,0.03,0.02"
overlay0_desc3_next_target = "second"
overlay0_desc4 = "hold_fast_forward,0.05,0.55,radial,0.03,0.02"
overlay0_desc5 = "reset,0.50,0.98,rect,0.04,0.02"
overlay0_desc6 = "key:f5,0.10,0.98,rect,0.04,0.02"

overlay1_name = "second"
overlay1_full_screen = true
overlay1_normalized = true
overlay1_descs = 1
overlay1_desc0 = "start,0.50,0.50,rect,0.10,0.10"
]]

local skin = assert(TouchSkin.parse(CFG))
eq(#skin.pages, 2, "two overlay pages parsed")

local page = skin.pages[1]
eq(page.name, "shell", "page name")
eq(page.imagePath, "img/back.png", "page background path")
check(page.fullScreen, "full_screen parsed")
check(not page.aspectFromCfg, "a cfg without aspect_ratio does not lock aspect")
eq(page.alphaMod, 0.001, "overlay alpha_mod parsed")
eq(#page.controls, 7, "seven descs parsed")

check(page.viewport ~= nil, "viewport parsed")
eq(page.viewport.h, 0.5, "viewport height")
check(page.viewportFill, "viewport_fill parsed")

local a, diag, decor, nextBtn, ff, reset, keyBtn = unpack(page.controls)
eq(a.buttons[1], "a", "desc0 binds GB a")
eq(a.shape, "radial", "desc0 is radial")
eq(a.alphaMod, 0.001, "desc inherits the overlay alpha_mod")
eq(a.rangeMod, 1.5, "desc inherits the overlay range_mod")
eq(table.concat(diag.buttons, "+"), "left+down", "pipe-separated binds are one control")
check(decor.decorative, "nul desc is decoration only")
eq(decor.imagePath, "img/dpad.png", "decoration still carries art")
eq(nextBtn.hotkeys[1], "overlay_next", "overlay_next mapped")
eq(nextBtn.nextTarget, "second", "next_target parsed")
eq(ff.hotkeys[1], "fast_forward_hold", "hold_fast_forward mapped")
eq(reset.hotkeys[1], "soft_reset", "reset mapped")
eq(keyBtn.keys[1], "f5", "key: binds a keyboard key")

-- geometry: x/y are the centre, range_x/range_y are half extents, both
-- normalized to the window when full_screen is set
local W, H = 400, 800
local cx, cy, halfW, halfH = TouchSkin.controlGeometry(page, a, W, H)
eq(cx, 320, "control centre x")
eq(cy, 600, "control centre y")
eq(halfW, 40, "control half width")
eq(halfH, 40, "control half height")

-- range_mod 1.5 widens the hitbox but not the art
check(TouchSkin.hits(page, a, W, H, 320, 600), "centre hits")
check(TouchSkin.hits(page, a, W, H, 320 + 55, 600), "inside range_mod hits")
check(not TouchSkin.hits(page, a, W, H, 320 + 65, 600), "past range_mod misses")
-- radial, so the corner of the bounding box is outside
check(not TouchSkin.hits(page, a, W, H, 320 + 55, 600 + 55), "radial corner misses")
-- rect hitbox does take its corner
check(TouchSkin.hits(page, diag, W, H, 80 + 19, 720 + 19), "rect corner hits")

-- ---------------------------------------------------------------- runtime

TouchControls:init()
TouchControls.active = true
TouchControls.enabled = true
TouchSkin.setOverlayLive(true)
TouchSkin.setActive(skin)
Input:init()

local ww, wh = love.graphics.getDimensions()
local function at(nx, ny) return nx * ww, ny * wh end

check(TouchSkin.hasViewport(), "active skin reports a viewport")

-- the renderer fits the Game Boy picture into this rect instead of the window
local sx, sy, sw, sh, fill = TouchSkin.viewport(W, H)
eq(sx, 0, "viewport x") eq(sy, 0, "viewport y")
eq(sw, 400, "viewport w") eq(sh, 400, "viewport h")
check(fill, "viewport fill flag returned")
eq(TouchSkin.viewport(W, H), 0, "without a locked aspect, viewport tracks the window")

check(TouchControls:touchpressed("f1", at(0.80, 0.75)), "press on A is captured")
check(Input:isDown("a"), "skin A presses GB a")
TouchControls:touchreleased("f1", at(0.80, 0.75))
check(not Input:isDown("a"), "lifting releases GB a")

-- one finger inside a combined desc holds both directions
TouchControls:touchpressed("f2", at(0.20, 0.90))
check(Input:isDown("left") and Input:isDown("down"), "combined desc holds both buttons")
-- sliding onto the decoration drops them without capturing anything new
TouchControls:touchmoved("f2", at(0.20, 0.75))
check(not Input:isDown("left") and not Input:isDown("down"),
      "sliding off a control releases it")
TouchControls:touchreleased("f2", at(0.20, 0.75))

check(TouchControls:touchpressed("f3", at(0.20, 0.75)) == nil,
      "a press on decoration alone is not captured")

-- hotkeys reach the host once per press edge and once per release
local fired = {}
TouchControls:setHotkeyHandler(function(action, pressed)
  fired[#fired + 1] = action .. ":" .. tostring(pressed)
end)
TouchControls:touchpressed("f4", at(0.05, 0.55))
eq(fired[1], "fast_forward_hold:true", "held hotkey fires on press")
TouchControls:touchreleased("f4", at(0.05, 0.55))
eq(fired[2], "fast_forward_hold:false", "held hotkey fires on release")

-- a stranded finger unwinds through reset, not just through touchreleased
fired = {}
TouchControls:touchpressed("f5", at(0.05, 0.55))
TouchControls:touchpressed("f6", at(0.80, 0.75))
check(Input:isDown("a"), "second finger holds A")
TouchControls:reset()
eq(fired[2], "fast_forward_hold:false", "reset releases held hotkeys")
check(not Input:isDown("a"), "reset releases held buttons")

-- overlay_next swaps the page, and the new page's controls are what hit
eq(TouchSkin.page().name, "shell", "starts on page 1")
TouchControls:touchpressed("f7", at(0.95, 0.55))
eq(TouchSkin.page().name, "second", "overlay_next honours next_target")
TouchControls:touchreleased("f7", at(0.95, 0.55))
TouchControls:touchpressed("f8", at(0.50, 0.50))
check(Input:isDown("start"), "page 2 control presses GB start")
TouchControls:touchreleased("f8", at(0.50, 0.50))
TouchSkin.setPage("shell")

-- ------------------------------------------------------------ persistence

local cfg = TouchControls.normalizeConfig({ enabled = true, skin = "gb_anim" })
eq(cfg.skin, "gb_anim", "normalizeConfig keeps the skin id")
eq(TouchControls.normalizeConfig({ skin = "" }).skin, nil, "empty skin id drops")
eq(TouchControls.normalizeConfig({ skin = 7 }).skin, nil, "non-string skin id drops")

TouchControls.skinId = "gb_anim"
eq(TouchControls:config().skin, "gb_anim", "config() round-trips the skin id")

-- ----------------------------------------------- screen-hole detection

-- Border art usually ships with a transparent screen hole and no viewport
-- key.  Detection is verified against real art by
-- tests/drivers/tv_skin_shot.lua; here it only has to fail safely.
eq(TouchSkin.detectViewport("assets/skins/tv_crt", nil), nil,
   "no bezel path detects nothing")
eq(TouchSkin.detectViewport("assets/skins/tv_crt", ""), nil,
   "empty bezel path detects nothing")
eq(TouchSkin.detectViewport("assets/skins/tv_crt", "img/does_not_exist.png"), nil,
   "a missing bezel detects nothing")

-- --------------------------------------------------------- bundled skin

local bundled = TouchSkin.load("assets/skins/gb_anim", "gb_anim")
check(bundled ~= nil, "bundled gb_anim skin loads")
if bundled then
  eq(#bundled.pages, 2, "gb_anim has a DMG and a Color page")
  eq(bundled.pages[1].name, "GameBoy", "gb_anim page 1")
  check(bundled.pages[1].viewport ~= nil, "gb_anim declares a screen viewport")
  eq(bundled.pages[1].imagePath, "img/gb_back.png", "gb_anim bezel art")
  local named = {}
  for _, ctl in ipairs(bundled.pages[1].controls) do
    for _, btn in ipairs(ctl.buttons) do named[btn] = true end
  end
  for _, btn in ipairs({ "a", "b", "start", "select", "up", "down", "left", "right" }) do
    check(named[btn], "gb_anim binds GB " .. btn)
  end
  check(not TouchSkin.hasOrientPair(bundled),
        "gb_anim is not a portrait/landscape auto-rotate overlay")
end

local tv = TouchSkin.load("assets/skins/tv_crt", "tv_crt")
check(tv ~= nil, "bundled tv_crt desktop bezel loads")
if tv then
  eq(#tv.pages, 1, "tv_crt is a single page")
  eq(#tv.pages[1].controls, 0, "tv_crt binds nothing: it is a frame")
  check(tv.pages[1].viewport ~= nil, "tv_crt names the tube as its viewport")
  eq(tv.pages[1].imagePath, "img/tv-integer.png", "tv_crt bezel art")
  TouchSkin.setActive(tv)
  TouchSkin.setOverlayLive(false)
  check(TouchSkin.decorativeOnly(), "tv_crt counts as decoration")
  check(TouchSkin.drawable(), "so it draws on a desktop window")
end

-- ------------------------------------------- decorative desktop bezels

-- A skin whose page binds nothing is a frame, not a pad: it draws where the
-- touch overlay does not (desktop), and a gamepad must not hide it.
local BEZEL = [[
overlays = 1
overlay0_name = "tv"
overlay0_overlay = img/tv.png
overlay0_full_screen = true
overlay0_normalized = true
overlay0_descs = 1
overlay0_desc0 = "nul,0.5,0.5,rect,0.5,0.5"
overlay0_viewport = "0.2,0.1,0.6,0.8"
]]
local bezel = assert(TouchSkin.parse(BEZEL))
TouchSkin.setActive(bezel)

TouchSkin.setOverlayLive(false)
check(TouchSkin.decorativeOnly(), "a descs-only-nul skin is decoration")
check(TouchSkin.drawable(), "a decorative skin draws with the overlay off (desktop)")
check(TouchSkin.hasViewport(), "and its viewport still places the picture")
TouchControls.active = false
TouchControls.enabled = true
TouchControls.controllerHidden = true
check(TouchControls:visible(), "a gamepad does not hide a decorative bezel")

-- a skin that binds buttons keeps following the mobile / POKEPORT_TOUCH gate
TouchSkin.setActive(skin)
TouchSkin.setOverlayLive(false)
check(not TouchSkin.decorativeOnly(), "a skin with binds is not decoration")
check(not TouchSkin.drawable(), "and it does not draw where the overlay is off")
check(not TouchSkin.hasViewport(), "so it cannot shrink the picture either")
check(not TouchControls:visible(), "nor draw over a desktop window")
TouchSkin.setOverlayLive(true)
check(TouchSkin.drawable(), "with the overlay live it draws again")
TouchControls.active = true
TouchControls.controllerHidden = false

-- ------------------------------------------------------- native format

local native = TouchSkin.serialize(skin)
check(native:find("^return {"), "serialize emits a Lua data chunk")
local back, nerr = TouchSkin.parseNative(native)
check(back ~= nil, "native round-trip parses: " .. tostring(nerr))
if back then
  eq(#back.pages, #skin.pages, "round-trip keeps the page count")
  local bp, sp = back.pages[1], skin.pages[1]
  eq(#bp.controls, #sp.controls, "round-trip keeps the control count")
  eq(bp.controls[1].spec, sp.controls[1].spec, "round-trip keeps binds")
  eq(bp.controls[1].rangeX, sp.controls[1].rangeX, "round-trip keeps half extents")
  eq(bp.controls[1].shape, sp.controls[1].shape, "round-trip keeps the hitbox shape")
  eq(bp.viewport.h, sp.viewport.h, "round-trip keeps the viewport")
  check(bp.viewportFill, "round-trip keeps viewport_fill")
  eq(bp.alphaMod, sp.alphaMod, "round-trip keeps alpha_mod")
  eq(bp.controls[3].decorative, true, "round-trip keeps decoration")
  eq(bp.controls[4].nextTarget, "second", "round-trip keeps next_target")
end

-- the native format carries the separate pressed image a .cfg cannot
local twoState = assert(TouchSkin.parseNative([[
return { pages = { { name = "p", controls = {
  { bind = "a", x = 0.5, y = 0.5, w = 0.2, h = 0.2, shape = "radial",
    image = "up.png", imagePressed = "down.png" },
} } } }
]]))
eq(twoState.pages[1].controls[1].imagePath, "up.png", "native idle image")
eq(twoState.pages[1].controls[1].pressedImagePath, "down.png", "native pressed image")
eq(twoState.pages[1].controls[1].rangeX, 0.1, "native w is a full width, not a range")

check(TouchSkin.parseNative("return 5") == nil, "a non-table skin.lua is rejected")
check(TouchSkin.parseNative("return { pages = {} }") == nil, "a pageless skin.lua is rejected")
check(TouchSkin.parseNative("this is not lua") == nil, "a broken skin.lua is rejected")
-- skins are third-party data: the chunk must not see the host globals
check(TouchSkin.parseNative("return { pages = { { controls = {} } }, hit = love ~= nil }")
      ~= nil, "skin.lua loads in an empty environment")

-- --------------------------------------------------------------- export

local SkinZip = require("src.core.SkinZip")
local blob = SkinZip.encode({
  { name = "skin.lua", data = "return {}\n" },
  { name = "img/a.png", data = "\137PNG\r\n\26\n binary \0 bytes" },
})
eq(blob:sub(1, 4), "PK\3\4", "zip starts with a local file header")
check(blob:find("PK\5\6", 1, true) ~= nil, "zip ends with a central directory record")
check(blob:find("img/a.png", 1, true) ~= nil, "zip carries the entry name")
check(blob:find("binary", 1, true) ~= nil, "stored entries keep their bytes verbatim")

local bundledSkin = TouchSkin.load("assets/skins/gb_anim", "gb_anim")
if bundledSkin then
  eq(#TouchSkin.assetPaths(bundledSkin), 17, "gb_anim names 17 distinct images")
  local tmp = os.tmpname() .. ".zip"
  local path, missing = TouchSkin.export(bundledSkin, tmp)
  eq(path, tmp, "export writes to the requested path")
  eq(#missing, 0, "every gb_anim image was found")
  local f = io.open(tmp, "rb")
  check(f ~= nil, "exported zip reached disk")
  if f then
    local bytes = f:read("*a")
    f:close()
    eq(bytes:sub(1, 4), "PK\3\4", "exported file is a zip")
    check(bytes:find("skin.lua", 1, true) ~= nil, "export includes the native skin.lua")
    check(bytes:find("img/gb_back.png", 1, true) ~= nil, "export includes the bezel")
    check(bytes:find("overlay.cfg", 1, true) ~= nil,
          "a .cfg-sourced skin also exports its original config")
    os.remove(tmp)
  end
end

TouchSkin.setActive(nil)
TouchControls:setHotkeyHandler(nil)

-- ------------------------------------------ auto-rotate (#1503)

-- RetroArch overlays name a portrait page and a landscape page and wire
-- overlay_next between them.  Play has to pick the one that matches the
-- window, or landscape stretches the portrait ranges into wide ovals.
local ORIENT_CFG = [[
overlays = 2
overlay0_name = "portrait"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_aspect_ratio = 0.45
overlay0_descs = 1
overlay0_desc0 = "a,0.84382,0.69563,radial,0.09722,0.04375"

overlay1_name = "landscape"
overlay1_full_screen = true
overlay1_normalized = true
overlay1_aspect_ratio = 2.22222222222222
overlay1_descs = 1
overlay1_desc0 = "a,0.8307031248,0.8614400000,radial,0.0364168752,0.0813300000"
]]
local orient = assert(TouchSkin.parse(ORIENT_CFG))
check(orient.pages[1].aspectFromCfg, "portrait page locks the cfg aspect_ratio")
check(orient.pages[2].aspectFromCfg, "landscape page locks the cfg aspect_ratio")
eq(orient.pages[1].orient, "portrait", "a portrait page name locks on import")
eq(orient.pages[2].orient, "landscape", "a landscape page name locks on import")
check(TouchSkin.hasOrientPair(orient), "the pair is an auto-rotate overlay")
TouchSkin.setActive(orient)
TouchSkin.autoOrient = true

local PW, PH = 720, 1600
TouchSkin.setSurface(0, 0, PW, PH)
eq(TouchSkin.page().name, "portrait", "a tall window picks the portrait page")
local _, _, pHalfW, pHalfH =
  TouchSkin.controlGeometry(TouchSkin.page(), TouchSkin.page().controls[1], PW, PH)
eq(math.floor(pHalfW + 0.5), 70, "portrait A half-width follows range_x")
eq(math.floor(pHalfH + 0.5), 70, "portrait A half-height follows range_y")

local LW, LH = 1600, 720
TouchSkin.setSurface(0, 0, LW, LH)
eq(TouchSkin.page().name, "landscape", "a wide window picks the landscape page")
local _, _, lHalfW, lHalfH =
  TouchSkin.controlGeometry(TouchSkin.page(), TouchSkin.page().controls[1], LW, LH)
eq(math.floor(lHalfW + 0.5), 58, "landscape A half-width follows the landscape range")
eq(math.floor(lHalfH + 0.5), 59, "landscape A half-height follows the landscape range")
check(math.abs(lHalfW - lHalfH) < 2, "landscape A stays round instead of stretching")

-- 16:9 is not the overlay's 20:9.  Letterbox to aspect_ratio so A stays round
-- instead of filling the window and turning into a tall oval (#1503).
TouchSkin.setSurface(0, 0, 1920, 1080)
eq(TouchSkin.page().name, "landscape", "16:9 still picks landscape")
local _, _, boxW, boxH = TouchSkin.pageBox(TouchSkin.page(), 1920, 1080)
eq(math.floor(boxW + 0.5), 1920, "letterbox keeps the 16:9 width")
eq(math.floor(boxH + 0.5), 864, "and the overlay's 20:9 height")
local _, _, sHalfW, sHalfH =
  TouchSkin.controlGeometry(TouchSkin.page(), TouchSkin.page().controls[1], 1920, 1080)
check(math.abs(sHalfW - sHalfH) < 2, "A stays round on a 16:9 window")

local nativeOrient = TouchSkin.parseNative(TouchSkin.serialize(orient))
check(nativeOrient and nativeOrient.pages[2].aspectFromCfg,
      "native export keeps the aspect lock")

-- an explicit lock wins over the page name, so a studio-authored "main"
-- page can still auto-rotate in play
local LOCK_CFG = [[
overlays = 2
overlay0_name = "main"
overlay0_full_screen = true
overlay0_descs = 1
overlay0_desc0 = "a,0.5,0.5,radial,0.05,0.05"
overlay1_name = "wide"
overlay1_full_screen = true
overlay1_descs = 1
overlay1_desc0 = "a,0.5,0.5,radial,0.05,0.05"
]]
local locked = assert(TouchSkin.parse(LOCK_CFG))
locked.pages[1].orient = "portrait"
locked.pages[2].orient = "landscape"
TouchSkin.setActive(locked)
TouchSkin.setSurface(0, 0, 1600, 720)
eq(TouchSkin.page().name, "wide", "orient lock auto-rotates a page not named landscape")
local roundTrip = TouchSkin.parseNative(TouchSkin.serialize(locked))
eq(roundTrip.pages[1].orient, "portrait", "native export keeps a portrait lock")
eq(roundTrip.pages[2].orient, "landscape", "and a landscape lock")

TouchSkin.setActive(orient)
TouchSkin.autoOrient = false
TouchSkin.pageIndex = 1
eq(TouchSkin.page().name, "portrait",
   "the studio can keep a portrait page on a landscape canvas")
TouchSkin.autoOrient = true
TouchSkin.setSurface(nil)

-- pages that are not a portrait/landscape pair (gb_anim) stay put
TouchSkin.setActive(skin)
TouchSkin.setSurface(0, 0, LW, LH)
eq(TouchSkin.page().name, "shell", "a non-oriented skin does not auto-rotate")
TouchSkin.setSurface(nil)
TouchSkin.setActive(nil)

T.finish("touch_skin")
