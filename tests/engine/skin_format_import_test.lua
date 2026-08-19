package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local TouchSkin = require("src.core.TouchSkin")
local DeltaSkin = require("src.core.DeltaSkin")
local Json = require("src.link.Json")

local function near(got, want, msg)
  return check(type(got) == "number" and math.abs(got - want) < 1e-6,
    ("%s (got %s, want %s)"):format(msg, tostring(got), tostring(want)))
end

local function hasWarning(skin, fragment)
  for _, w in ipairs(skin.warnings or {}) do
    if tostring(w):find(fragment, 1, true) then return true end
  end
  return false
end

local function unzip(bytes)
  local out, i = {}, 1
  while bytes:sub(i, i + 3) == "PK\3\4" do
    local function u16(off)
      local a, b = bytes:byte(i + off, i + off + 1)
      return a + b * 256
    end
    local function u32(off)
      local a, b, c, d = bytes:byte(i + off, i + off + 3)
      return a + b * 256 + c * 65536 + d * 16777216
    end
    local size, nameLen, extraLen = u32(18), u16(26), u16(28)
    local name = bytes:sub(i + 30, i + 29 + nameLen)
    local start = i + 30 + nameLen + extraLen
    out[name] = bytes:sub(start, start + size - 1)
    out[#out + 1] = name
    i = start + size
  end
  return out
end

local function readBytes(path)
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local GAMEBOY_CFG = [[
overlays = 4

overlay0_name = "landscape"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_range_mod = 1.5
overlay0_alpha_mod = 2.0
overlay0_aspect_ratio = 2.22222222222222
overlay0_descs = 13
overlay0_desc0 = "nul,0.0985,0.6825,rect,0.0525,0.0875"
overlay0_desc0_overlay = img/dpad.png
overlay0_desc1 = "up,0.0985,0.5950,rect,0.0175,0.0292"
overlay0_desc2 = "down,0.0985,0.7700,rect,0.0175,0.0292"
overlay0_desc3 = "left,0.0460,0.6825,rect,0.0175,0.0292"
overlay0_desc4 = "right,0.1510,0.6825,rect,0.0175,0.0292"
overlay0_desc5 = "left|up,0.0460,0.5950,rect,0.0175,0.0292"
overlay0_desc6 = "right|up,0.1510,0.5950,rect,0.0175,0.0292"
overlay0_desc7 = "left|down,0.0460,0.7700,rect,0.0175,0.0292"
overlay0_desc8 = "right|down,0.1510,0.7700,rect,0.0175,0.0292"
overlay0_desc9 = "a,0.8975,0.6300,radial,0.0525,0.0875"
overlay0_desc9_overlay = img/a.png
overlay0_desc10 = "b,0.8100,0.7350,radial,0.0525,0.0875"
overlay0_desc10_overlay = img/b.png
overlay0_desc11 = "start,0.5500,0.9000,rect,0.0500,0.0400"
overlay0_desc12 = "select,0.4500,0.9000,rect,0.0500,0.0400"

overlay1_name = "portrait"
overlay1_full_screen = true
overlay1_normalized = true
overlay1_aspect_ratio = 0.45
overlay1_descs = 2
overlay1_desc0 = "a,0.8975,0.6300,radial,0.0875,0.0525"
overlay1_desc1 = "b,0.8100,0.7350,radial,0.0875,0.0525"

overlay2_name = "menu"
overlay2_full_screen = true
overlay2_normalized = true
overlay2_descs = 1
overlay2_desc0 = "menu_toggle,0.5,0.5,rect,0.1,0.1"

overlay3_name = "hide"
overlay3_full_screen = true
overlay3_normalized = true
overlay3_descs = 1
overlay3_desc0 = "overlay_next,0.95,0.05,radial,0.04,0.04"
overlay3_desc0_next_target = "landscape"
]]

local gameboy = assert(TouchSkin.parse(GAMEBOY_CFG))
eq(#gameboy.pages, 4, "the canonical gameboy overlay has four pages")
eq(gameboy.pages[1].orient, "landscape", "page 1 auto-rotates landscape")
eq(gameboy.pages[2].orient, "portrait", "page 2 auto-rotates portrait")
check(TouchSkin.hasOrientPair(gameboy), "so it is an auto-rotate overlay")
eq(gameboy.pages[3].orient, nil, "the menu page is not part of the pair")
eq(#gameboy.pages[1].controls, 13, "every landscape desc parsed")
check(gameboy.pages[1].controls[1].decorative, "the d-pad art desc binds nothing")
eq(gameboy.pages[1].controls[1].imagePath, "img/dpad.png", "and carries the art")
eq(gameboy.pages[1].imagePath, nil, "the overlay ships no page background")
eq(gameboy.pages[4].controls[1].nextTarget, "landscape", "hide jumps back by name")
local named = {}
for _, ctl in ipairs(gameboy.pages[1].controls) do
  for _, btn in ipairs(ctl.buttons) do named[btn] = true end
end
for _, btn in ipairs({ "a", "b", "start", "select", "up", "down", "left", "right" }) do
  check(named[btn], "landscape binds GB " .. btn)
end
eq(#gameboy.warnings, 0, "a well-formed overlay warns about nothing")

local SPACED_CFG = [[
overlays = 1
overlay0_name = "spaced"
overlay0_normalized = true
overlay0_descs = 2
overlay0_desc0 = "a 0.5 0.5 rect 0.05 0.05"
overlay0_desc0_saturate_pct = 0.6
overlay0_desc0_exclusive = true
overlay0_desc0_movable = true
overlay0_desc1 = b,0.25,0.5,radial,0.05,0.05
]]
local spaced = assert(TouchSkin.parse(SPACED_CFG))
near(spaced.pages[1].controls[1].saturatePct, 0.6, "_saturate_pct is parsed")
check(spaced.pages[1].controls[1].exclusive, "_exclusive is parsed")
check(spaced.pages[1].controls[1].movable, "_movable is parsed on a plain desc")
eq(spaced.pages[1].controls[2].exclusive, nil, "and is not inherited")
eq(#spaced.pages[1].controls, 2, "a space-separated desc still parses")
eq(spaced.pages[1].controls[1].buttons[1], "a", "space-separated bind")
near(spaced.pages[1].controls[1].x, 0.5, "space-separated position")
eq(spaced.pages[1].controls[2].buttons[1], "b", "an unquoted desc parses too")
eq(spaced.pages[1].controls[2].shape, "radial", "and keeps its hitbox shape")

local SHORT_CFG = [[
overlays = 1
overlay0_name = "short"
overlay0_normalized = true
overlay0_descs = 2
overlay0_desc0 = "a,0.5,0.5,rect,0.05,0.05"
]]
local short = assert(TouchSkin.parse(SHORT_CFG))
eq(#short.pages[1].controls, 1, "a missing desc is skipped, not faked")
check(hasWarning(short, "missing desc 1"), "and the importer says so")

eq(select(1, TouchSkin.parse("overlay0_descs = 1\n")), nil,
   "a cfg without the overlays key is refused")

local AREA_CFG = [[
overlays = 1
overlay0_name = "portrait"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_descs = 3
overlay0_desc0 = "dpad_area,0.2,0.7,rect,0.15,0.1"
overlay0_desc0_overlay = img/dpad.png
overlay0_desc0_reach_x = 1.5
overlay0_desc0_movable = true
overlay0_desc1 = "abxy_area,0.8,0.7,radial,0.12,0.08"
overlay0_desc1_up = "start"
overlay0_desc2 = "analog_left,0.2,0.3,radial,0.1,0.1"
overlay0_desc2_saturate_pct = 0.6
overlay0_desc2_exclusive = true
]]
local area = assert(TouchSkin.parse(AREA_CFG))
local ap = area.pages[1]
near(ap.aspect, 0.5625, "a portrait-named overlay defaults to 9:16")
check(not ap.aspectFromCfg, "and that default is not a cfg aspect lock")
eq(#ap.controls, 1 + 8 + 8 + 8, "each area desc expands into eight hitboxes")

local art = ap.controls[1]
check(art.decorative, "the dpad_area art is carried by a decoration")
eq(art.imagePath, "img/dpad.png", "with the desc's own overlay image")
near(art.rangeX, 0.15, "sized like the area it replaces")

local sectorE = ap.controls[2]
eq(sectorE.spec, "right", "the first sector is the one pointing right")
near(sectorE.x, 0.2, "every sector sits on the area centre")
near(sectorE.y, 0.7, "on both axes")
near(sectorE.rangeX, 0.15, "and covers the whole area, not a ninth of it")
near(sectorE.reachLeft, 1.5, "the desc reach_x rides onto the sectors as it is")
near(sectorE.reachRight, 1.5, "on both sides")
eq(sectorE.sector, 1, "the sector index is kept for the hit test")
eq(ap.controls[3].spec, "right|down", "the next sector is the lower-right corner")
eq(ap.controls[4].spec, "down", "then straight down, y growing downwards")
eq(ap.controls[8].spec, "up", "and straight up seven sectors along")
check(ap.controls[1].movable, "_movable is parsed")

local abxy = ap.controls[10]
eq(abxy.spec, "a", "abxy right is RetroPad a, which is GB A")
eq(abxy.buttons[1], "a", "and reaches that GB button")
eq(ap.controls[16].spec, "start", "abxy_area honours an _up override")
eq(ap.controls[15].spec, "y|start", "the up-left sector combines both sides")
check(ap.controls[15].exclusive == nil, "and inherits nothing the desc did not set")
check(ap.controls[14].decorative, "RetroPad Y has no GB button, so that sector is inert")
eq(abxy.shape, "radial", "a radial area keeps its ellipse")

eq(ap.controls[18].spec, "right", "analog_left degrades to a directional pad")
check(ap.controls[18].exclusive, "_exclusive rides onto the expanded sectors")
eq(ap.controls[23].spec, "left|up", "with all eight sectors")
near(ap.controls[18].rangeX, 0.1, "analog sectors share the whole stick area")

local sq = { x = 0.5, y = 0.5, rangeX = 0.25, rangeY = 0.25, shape = "rect",
             rangeMod = 1, alphaMod = 1,
             reachUp = 1, reachDown = 1, reachLeft = 1, reachRight = 1 }
local sectors = TouchSkin.expandSectors(sq, TouchSkin.AREA_DEFAULTS.dpad_area)
eq(#sectors, 8, "a dpad area expands into eight sector hitboxes")
local page = { rect = { x = 0, y = 0, w = 1, h = 1 }, fullScreen = true,
               aspect = 1, controls = sectors }
local function hitSpecs(px, py)
  local out = {}
  for _, ctl in ipairs(sectors) do
    if TouchSkin.hits(page, ctl, 100, 100, px, py, 0, 0) then out[#out + 1] = ctl.spec end
  end
  return table.concat(out, "+")
end
eq(hitSpecs(50, 50), "right", "the exact centre still fires a direction: no dead zone")
eq(hitSpecs(60, 50), "right", "a touch to the right of centre is right")
eq(hitSpecs(50, 60), "down", "a touch below centre is down, y growing downwards")
eq(hitSpecs(50, 40), "up", "a touch above centre is up")
eq(hitSpecs(40, 40), "left|up", "a diagonal touch fires both directions")
eq(hitSpecs(58, 52), "right", "17 degrees off the axis is still a pure direction")
eq(hitSpecs(55, 53), "right|down", "and 31 degrees is the diagonal, not a grid corner")
eq(hitSpecs(50, 80), "", "outside the area nothing fires")

local PIXEL_NO_IMAGE = [[
overlays = 1
overlay0_name = "pixels"
overlay0_descs = 1
overlay0_desc0 = "a,120,80,rect,20,10"
]]
local noImage = assert(TouchSkin.parse(PIXEL_NO_IMAGE))
check(hasWarning(noImage, "no base image"),
      "pixel coords without a base image are called out")
check(noImage.pages[1].pixelCoords == false,
      "and read as normalized rather than dividing by nothing")

love.filesystem.write("skins/px/overlay.cfg", [[
overlays = 1
overlay0_name = "px"
overlay0_overlay = img/base.png
overlay0_full_screen = true
overlay0_descs = 2
overlay0_desc0 = "a,4,4,rect,2,1"
overlay0_desc1 = "b,6,2,rect,1,1"
overlay0_desc1_normalized = true
]])
local px = assert(TouchSkin.load("skins/px", "px"))
local pxPage = px.pages[1]
check(pxPage.image ~= nil, "the base overlay image loads")
local iw, ih = pxPage.image:getDimensions()
near(pxPage.controls[1].x, 4 / iw, "pixel x is divided by the base image width")
near(pxPage.controls[1].y, 4 / ih, "pixel y is divided by the base image height")
near(pxPage.controls[1].rangeX, 2 / iw, "and so are the half extents")
near(pxPage.controls[2].x, 6, "a per-desc normalized flag opts that desc out")
check(pxPage.pixelCoords == false, "the page is normalized once converted")

love.filesystem.write("skins/pxbad/overlay.cfg", [[
overlays = 1
overlay0_name = "pxbad"
overlay0_overlay = img/broken.png
overlay0_descs = 1
overlay0_desc0 = "a,4,4,rect,2,1"
]])
local savedNewImage = love.graphics.newImage
love.graphics.newImage = function() error("unreadable image") end
local badPx, badPxErr = TouchSkin.load("skins/pxbad", "pxbad")
love.graphics.newImage = savedNewImage
eq(badPx, nil, "a skin whose pixel coordinates have no base image fails to load")
check(tostring(badPxErr):find("img/broken.png", 1, true) ~= nil,
      "and the error names the image it could not read")

local DELTA_JSON = [[
{
  "name": "Test GBC",
  "identifier": "com.example.gbc.test",
  "gameTypeIdentifier": "com.rileytestut.delta.game.gbc",
  "debug": false,
  "representations": {
    "iphone": {
      "edgeToEdge": {
        "portrait": {
          "assets": { "small": "p_small.png", "medium": "p_medium.png",
                      "large": "p_large.png" },
          "items": [
            { "inputs": ["a"], "frame": {"x":240,"y":320,"width":64,"height":64},
              "mask": "circle" },
            { "inputs": ["b"], "frame": {"x":160,"y":360,"width":64,"height":64},
              "extendedEdges": {"right":16} },
            { "inputs": {"up":"up","down":"down","left":"left","right":"right"},
              "frame": {"x":16,"y":320,"width":96,"height":96} },
            { "inputs": ["start","select"],
              "frame": {"x":128,"y":448,"width":64,"height":32} },
            { "inputs": ["menu"], "frame": {"x":0,"y":0,"width":32,"height":32} },
            { "inputs": ["quickSave"],
              "frame": {"x":288,"y":0,"width":32,"height":32} }
          ],
          "mappingSize": {"width":320,"height":480},
          "extendedEdges": {"top":8,"bottom":8,"left":8,"right":8},
          "translucent": false,
          "screens": [{ "inputFrame": {"x":0,"y":0,"width":160,"height":144},
                        "outputFrame": {"x":0,"y":32,"width":320,"height":288} }]
        }
      },
      "standard": {
        "portrait": { "items": [], "mappingSize": {"width":320,"height":480} }
      }
    }
  }
}
]]

local delta = assert(TouchSkin ~= nil and DeltaSkin.parse(DELTA_JSON))
eq(delta.format, "delta", "a .deltaskin parses into the native model")
eq(delta.name, "Test GBC", "info.json name")
eq(delta.system, "gbc", "gbc covers both GB and GBC")
eq(#delta.pages, 1, "only the orientations present become pages")
local dp = delta.pages[1]
eq(dp.name, "portrait", "the page is named for its orientation")
eq(dp.orient, "portrait", "and locked to it")
eq(dp.imagePath, "p_large.png", "the PNG ladder picks the largest for a phone")
check(dp.fullScreen, "Delta stretches its skin over the whole surface")
check(not dp.aspectFromCfg, "so nothing letterboxes it")
near(dp.aspect, 320 / 480, "the page aspect is the mappingSize aspect")
eq(#dp.controls, 13, "edgeToEdge wins over standard, so all six items parsed")

local dA = dp.controls[1]
eq(dA.buttons[1], "a", "an inputs array binds its button")
eq(dA.shape, "radial", 'mask "circle" becomes a radial hitbox')
near(dA.x, 0.85, "frame top-left plus half width is the native centre")
near(dA.y, 352 / 480, "and the same for y")
near(dA.rangeX, 0.1, "frame width halves into the native half extent")
near(dA.reachLeft, 1.25, "orientation extendedEdges become reach")

local dB = dp.controls[2]
near(dB.reachRight, 1.5, "a per-item extendedEdges key overrides that side")
near(dB.reachLeft, 1.25, "and leaves the others inherited")

eq(dp.controls[3].spec, "left|up", "a dpad input object expands to a 3x3 grid")
near(dp.controls[3].x, 0.1, "dpad top-left cell x")
near(dp.controls[3].rangeX, 0.05, "dpad cells are a third of the frame")
near(dp.controls[3].reachLeft, 1.5, "with the extended edge re-scaled onto them")
eq(dp.controls[4].spec, "up", "dpad top-centre cell")
eq(dp.controls[10].spec, "right|down", "dpad bottom-right cell")

eq(dp.controls[11].spec, "start|select", "a multi-input item fires both")
eq(dp.controls[12].hotkeys[1], "menu", "the Delta menu button becomes a hotkey")
check(dp.controls[13].decorative,
      "quickSave has no engine hotkey, so it is inert rather than a game button")

check(dp.viewport ~= nil, "screens[] places the emulator picture")
near(dp.viewport.y, 32 / 480, "outputFrame y normalizes by mappingSize")
near(dp.viewport.h, 288 / 480, "outputFrame height normalizes by mappingSize")

local bx, by, bw, bh = TouchSkin.pageBox(dp, 1000, 500)
eq(bx, 0, "delta page box x") eq(by, 0, "delta page box y")
eq(bw, 1000, "delta page box fills the width")
eq(bh, 500, "delta page box fills the height")

local DECK_JSON = [[
{ "name": "Deck", "gameTypeIdentifier": "com.rileytestut.delta.game.gbc",
  "representations": { "iphone": { "standard": { "portrait": {
    "assets": { "large": "deck.png" },
    "mappingSize": {"width":320,"height":240},
    "items": [ { "inputs": ["a"], "frame": {"x":240,"y":60,"width":64,"height":64} } ]
  } } } } }
]]
local deck = assert(DeltaSkin.parse(DECK_JSON))
local deckPage = deck.pages[1]
check(deckPage.aspectFromCfg, "a portrait deck without screens keeps mapping aspect")
eq(deckPage.anchor, "bottom", "and sits at the bottom of the window")
eq(deckPage.screenFit, "remainder", "with the leftover given to the GB picture")
eq(deckPage.viewport, nil, "no screens[] means no baked cutout")
local dbx, dby, dbw, dbh = TouchSkin.pageBox(deckPage, 1080, 1920)
eq(dbx, 0, "deck overlay is full width")
eq(dbw, 1080, "deck overlay width")
near(dbh, 1080 * 240 / 320, "deck overlay height is mapping aspect")
near(dby, 1920 - dbh, "pinned to the bottom, not stretched")
local vx, vy, vw, vh = TouchSkin.pageViewport(deckPage, 1080, 1920)
eq(vx, 0, "screen leftover x") eq(vy, 0, "screen leftover y")
eq(vw, 1080, "screen leftover is full width")
near(vh, dby, "and fills everything above the overlay")
check(vh > dbh, "there is more room for the picture than for the pad")

local LEGACY_SCREEN = [[
{ "gameTypeIdentifier": "public.aoshuang.game.gbc",
  "representations": { "iphone": { "standard": { "landscape": {
    "mappingSize": {"width":640,"height":320},
    "gameScreenFrame": {"x":160,"y":0,"width":320,"height":288},
    "translucent": true,
    "items": [ { "inputs": {"up":"analogStickUp","down":"analogStickDown",
                            "left":"analogStickLeft","right":"analogStickRight"},
                 "frame": {"x":0,"y":0,"width":120,"height":120} } ] } } } } }
]]
local legacy = assert(DeltaSkin.parse(LEGACY_SCREEN))
eq(legacy.system, "gbc", "the Manic public.aoshuang prefix is accepted")
eq(#legacy.pages, 1, "landscape only")
eq(legacy.pages[1].orient, "landscape", "orientation key drives the lock")
near(legacy.pages[1].viewport.x, 0.25, "gameScreenFrame is the legacy screen rect")
near(legacy.pages[1].alphaMod, 0.7, "translucent dims the controls")
eq(#legacy.pages[1].controls, 8, "a thumbstick degrades to a directional pad")
eq(legacy.pages[1].controls[1].spec, "left|up", "with the analog names mapped")

local snes = assert(DeltaSkin.parse([[
{ "gameTypeIdentifier": "com.rileytestut.delta.game.snes",
  "representations": { "iphone": { "standard": { "portrait": {
    "mappingSize": {"width":320,"height":480}, "items": [] } } } } }
]]))
check(hasWarning(snes, "not Game Boy"), "a non Game Boy skin warns")
eq(#snes.pages, 1, "but still imports")

eq(select(1, DeltaSkin.parse([[
{ "name": "old", "gameTypeIdentifier": "com.rileytestut.GBA4iOS.gba",
  "representations": { "iphone": { "portrait": { "assets": {} } } } }
]])), nil, "a GBA4iOS skin is refused")
local _, gbaErr = DeltaSkin.parse([[
{ "gameTypeIdentifier": "com.rileytestut.GBA4iOS.gbc", "representations": {} }
]])
check(tostring(gbaErr):find("GBA4iOS", 1, true) ~= nil,
      "and the message names the old format")

local _, noTypeErr = DeltaSkin.parse('{ "representations": {} }')
check(tostring(noTypeErr):find("gameTypeIdentifier", 1, true) ~= nil,
      "info.json without a gameTypeIdentifier is refused by name")
eq(select(1, DeltaSkin.parse("not json at all")), nil, "garbage is refused")
eq(select(1, DeltaSkin.parse([[
{ "gameTypeIdentifier": "com.rileytestut.delta.game.gbc", "representations": {} }
]])), nil, "an empty representations tree is refused")

local PDF_JSON = [[
{ "name": "Vector", "gameTypeIdentifier": "com.rileytestut.delta.game.gbc",
  "representations": { "iphone": { "standard": { "portrait": {
    "assets": { "resizable": "iphone_portrait.pdf" },
    "mappingSize": {"width":320,"height":480},
    "items": [ { "inputs": ["a"], "frame": {"x":0,"y":0,"width":32,"height":32} } ]
  } } } } }
]]
local pdf = assert(DeltaSkin.parse(PDF_JSON))
eq(pdf.pages[1].imagePath, nil, "a PDF asset is not pretended to be art")
eq(pdf.pages[1].pdfPath, "iphone_portrait.pdf",
   "but the PDF path is kept so load can extract a JPEG from it")
local convert = DeltaSkin.needsConversion(pdf)
check(convert ~= nil, "PDF-only skins report that they need conversion")
if convert then
  check(convert.pdfOnly, "the report is flagged pdfOnly")
  eq(convert.files[1], "iphone_portrait.pdf", "and names the file to convert")
end
eq(DeltaSkin.needsConversion(delta), nil, "a PNG skin needs no conversion")

local mixed = assert(DeltaSkin.parse([[
{ "gameTypeIdentifier": "com.rileytestut.delta.game.gb",
  "representations": { "iphone": { "standard": { "portrait": {
    "assets": { "resizable": "art.pdf", "medium": "art.png" },
    "mappingSize": {"width":320,"height":480}, "items": [] } } } } }
]]))
eq(mixed.pages[1].imagePath, "art.png", "a raster asset beats the PDF")
eq(DeltaSkin.needsConversion(mixed), nil, "so no conversion is needed")

eq(DeltaSkin.pickAsset({ small = "s.png" }, { targetWidth = 1080 }, {}), "s.png",
   "the ladder falls back to the largest shipped asset")
eq(DeltaSkin.pickAsset({ small = "s.png", medium = "m.png", large = "l.png" },
                       { targetWidth = 640 }, {}), "s.png",
   "a small target takes the small asset")
eq(DeltaSkin.pickAsset({ normal = "n.png" }, { targetWidth = 640 }, {}), "n.png",
   'the Manic "normal" alias is accepted')

love.filesystem.write("skins/wrapped.deltaskin/MySkin/info.json", [[
{ "name": "Wrapped", "gameTypeIdentifier": "com.rileytestut.delta.game.gbc",
  "representations": { "iphone": { "standard": { "portrait": {
    "assets": { "large": "Portrait.PNG" },
    "mappingSize": {"width":320,"height":480},
    "items": [ { "inputs": ["a"], "frame": {"x":0,"y":0,"width":64,"height":64} } ]
  } } } } }
]])
love.filesystem.write("skins/wrapped.deltaskin/MySkin/portrait.png", "\137PNG\r\n\26\n")

local wrappedId, wrappedErr = TouchSkin.installArchive("wrapped.deltaskin", "PK\3\4stub")
eq(wrappedId, "wrapped", "a .deltaskin installs under its bare name: " .. tostring(wrappedErr))
local wrapped = assert(TouchSkin.load("skins/_mounted/wrapped", "wrapped"))
eq(wrapped.format, "delta", "the mounted archive is recognised as a Delta skin")
eq(wrapped.name, "Wrapped", "and its name comes from info.json")
eq(wrapped.pages[1].imagePath, "MySkin/portrait.png",
   "the wrapping folder is prefixed onto assets and the real file name wins")
eq(#wrapped.pages[1].controls, 1, "the wrapped items parsed")

love.filesystem.write("skins/vector.deltaskin/info.json", PDF_JSON)
local vectorId, vectorErr = TouchSkin.installArchive("vector.deltaskin", "PK\3\4stub")
eq(vectorId, nil, "a PDF-only skin is refused instead of installing invisible")
check(tostring(vectorErr):find("PDF artwork", 1, true) ~= nil,
      "with the message that asks for a PNG version")
eq(love.filesystem.read("skins/vector.deltaskin"), nil,
   "and the refused archive is not left behind")

local PdfImage = require("src.core.PdfImage")
local function unhex(s)
  return (s:gsub("..", function(cc)
    return string.char(tonumber(cc, 16))
  end))
end
-- 1x1 JFIF JPEG, so extract tests do not need a file on disk.
local TINY_JPEG = unhex(
  "ffd8ffe000104a46494600010100000100010000ffdb0043000806060706050807070709" ..
  "09080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c283729" ..
  "2c30313434341f27393d38323c2e333432ffc0000b080001000101011100ffc400140001" ..
  "0000000000000000000000000000000008ffc40014100100000000000000000000000000" ..
  "00000000ffda0008010100003f007f3fffd9")
local function jpegPdf(jpeg, w, h)
  return "%PDF-1.7\n3 0 obj\n<< /Type /XObject /Subtype /Image /Width "
    .. tostring(w) .. " /Height " .. tostring(h)
    .. " /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /DCTDecode /Length "
    .. tostring(#jpeg) .. " >>\nstream\n" .. jpeg .. "\nendstream\nendobj\n%%EOF\n"
end
local extracted = assert(PdfImage.extract(jpegPdf(TINY_JPEG, 1, 1)))
eq(extracted.ext, "jpg", "a JPEG-in-PDF yields a jpg")
eq(extracted.data, TINY_JPEG, "and the JPEG body is recovered byte for byte")
eq(extracted.width, 1, "width comes from the Image XObject")
eq(extracted.height, 1, "and so does height")

local indirect = "%PDF-1.7\n3 0 obj\n<< /Type /XObject /Subtype /Image /Width 1"
  .. " /Height 1 /Filter /DCTDecode /Length 5 0 R >>\nstream\n" .. TINY_JPEG
  .. "\nendstream\nendobj\n5 0 obj\n" .. tostring(#TINY_JPEG) .. "\nendobj\n%%EOF\n"
local fromRef = assert(PdfImage.extract(indirect))
eq(fromRef.data, TINY_JPEG,
   "an indirect /Length (the 3-Heights Image-to-PDF layout) still extracts")

eq(select(1, PdfImage.extract("%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n")),
   nil, "a vector PDF with no image is not pretended to be art")
eq(select(1, PdfImage.extract("not a pdf")), nil, "and neither is garbage")

love.filesystem.write("skins/pikapdf.deltaskin/info.json", PDF_JSON)
love.filesystem.write("skins/pikapdf.deltaskin/iphone_portrait.pdf",
                      jpegPdf(TINY_JPEG, 1, 1))
local pikaId, pikaErr = TouchSkin.installArchive("pikapdf.deltaskin", "PK\3\4stub")
eq(pikaId, "pikapdf", "a Delta skin whose PDF wraps a JPEG installs: "
  .. tostring(pikaErr))
local pika = assert(TouchSkin.load("skins/_mounted/pikapdf", "pikapdf"))
check(pika.pages[1].rasterData == TINY_JPEG,
      "load recovers the JPEG from the PDF")
check(pika.pages[1].image ~= nil, "and LOVE gets an image from those bytes")
eq(DeltaSkin.needsConversion(pika), nil,
   "so the skin no longer reports that it needs conversion")

eq(select(1, TouchSkin.installArchive("skin.gbcskin", "PK\3\4stub")), nil,
   "a GBA4iOS .gbcskin is refused at the door")
local _, legacyErr = TouchSkin.installArchive("skin.gbaskin", "PK\3\4stub")
check(tostring(legacyErr):find("GBA4iOS", 1, true) ~= nil,
      "with a message that names the format")
eq(select(1, TouchSkin.installArchive("skin.rar", "PK\3\4stub")), nil,
   "an unknown archive extension is refused")
eq(TouchSkin.archiveId("pad.deltaskin"), "pad", "archiveId strips .deltaskin")
eq(TouchSkin.archiveId("pad.zip"), "pad", "archiveId strips .zip")
eq(TouchSkin.archiveId("pad"), nil, "a bare name is not an archive")

local AUTHORED = [[
return { name = "Authored", pages = {
  { name = "portrait", orient = "portrait", fullScreen = true,
    viewport = { x = 0, y = 0, w = 1, h = 0.5 },
    controls = {
      { bind = "a", x = 0.8, y = 0.75, w = 0.2, h = 0.1, shape = "radial" },
      { bind = "b", x = 0.6, y = 0.8, w = 0.2, h = 0.1, shape = "radial",
        reachRight = 1.5 },
      { bind = "start", x = 0.5, y = 0.95, w = 0.1, h = 0.04 },
      { bind = "menu_toggle", x = 0.05, y = 0.05, w = 0.08, h = 0.04 },
      { bind = "nul", x = 0.2, y = 0.7, w = 0.3, h = 0.2, image = "img/dpad.png" },
    } },
  { name = "landscape", orient = "landscape", fullScreen = true,
    controls = {
      { bind = "a", x = 0.9, y = 0.8, w = 0.1, h = 0.15, shape = "radial" },
    } },
} }
]]
local authored = assert(TouchSkin.parseNative(AUTHORED))
authored.id = "authored"
authored.root = "skins/authored"

local cfgText = TouchSkin.toRetroArchConfig(authored)
check(cfgText:find("overlays = 2", 1, true) ~= nil, "the cfg declares its overlays")
local reparsed = assert(TouchSkin.parse(cfgText))
eq(#reparsed.pages, 2, "the generated cfg round-trips both pages")
eq(reparsed.pages[1].name, "portrait", "and their names")
eq(#reparsed.pages[1].controls, 5, "and every desc")
eq(reparsed.pages[1].controls[1].spec, "a", "binds survive the round trip")
near(reparsed.pages[1].controls[1].x, 0.8, "centres survive the round trip")
near(reparsed.pages[1].controls[1].rangeX, 0.1, "half extents survive")
eq(reparsed.pages[1].controls[1].shape, "radial", "hitbox shape survives")
near(reparsed.pages[1].controls[2].reachRight, 1.5, "per-side reach survives")
eq(reparsed.pages[1].controls[4].hotkeys[1], "menu", "hotkeys survive")
check(reparsed.pages[1].controls[5].decorative, "decoration stays decoration")
eq(reparsed.pages[1].controls[5].imagePath, "img/dpad.png", "and keeps its art")
near(reparsed.pages[1].viewport.h, 0.5, "the screen cutout survives")
eq(reparsed.pages[1].orient, "portrait", "the orientation lock survives by name")

local KEY_SKIN = [[
return { name = "Keys", pages = {
  { name = "portrait", fullScreen = true, controls = {
      { bind = "key:escape", x = 0.5, y = 0.5, w = 0.1, h = 0.1 },
    } },
} }
]]
local keySkin = assert(TouchSkin.parseNative(KEY_SKIN))
local keyCfg = TouchSkin.toRetroArchConfig(keySkin)
check(keyCfg:find("retrok_escape", 1, true) ~= nil,
      "a key bind exports in the grammar RetroArch understands")
check(keyCfg:find("key:escape", 1, true) == nil, "and not in the native spelling")
eq(assert(TouchSkin.parse(keyCfg)).pages[1].controls[1].keys[1], "escape",
   "which this importer still reads back as the same key")

local areaCfg = TouchSkin.toRetroArchConfig({ pages = area.pages })
local areaBack = assert(TouchSkin.parse(areaCfg))
eq(#areaBack.pages[1].controls, #ap.controls,
   "an area desc exports as one desc, not eight overlapping ones")
check(areaCfg:find("dpad_area", 1, true) ~= nil, "the area kind is written back")
check(areaCfg:find('_up = "start"', 1, true) ~= nil, "with its output override")
eq(areaBack.pages[1].controls[16].spec, "start", "which survives the round trip")

local areaInfo = assert(DeltaSkin.build({ id = "area", pages = area.pages }))
local areaRep = areaInfo.representations.iphone.edgeToEdge.portrait
local dpadItem
for _, item in ipairs(areaRep.items) do
  if not dpadItem and type(item.inputs) == "table" and item.inputs.up then
    dpadItem = item
  end
end
check(dpadItem ~= nil, "the same area exports to Delta as one d-pad item")
eq(dpadItem.inputs.left, "left", "carrying each direction")
eq(#areaRep.items, 3, "one per area desc, not eight stacked on one another")

local raPath = os.tmpname() .. "-ra.zip"
local raWritten, raMissing = TouchSkin.exportRetroArch(authored, raPath)
eq(raWritten, raPath, "exportRetroArch writes where it was told")
eq(raMissing[1], "img/dpad.png", "and reports art it could not find")
local raZip = unzip(readBytes(raPath))
eq(raZip[1], "overlay.cfg", "the RetroArch zip leads with overlay.cfg")
check(raZip["overlay.cfg"] ~= nil, "and the entry has bytes")
check(TouchSkin.parse(raZip["overlay.cfg"]) ~= nil, "which RetroArch grammar accepts")
os.remove(raPath)

local dsPath = os.tmpname() .. ".deltaskin"
local dsWritten, _, dsWarnings = TouchSkin.exportDelta(authored, { path = dsPath })
eq(dsWritten, dsPath, "exportDelta writes where it was told")
check(#dsWarnings > 0, "and warns that per-button art has nowhere to go")
local dsZip = unzip(readBytes(dsPath))
eq(dsZip[1], "info.json", "the .deltaskin leads with info.json")
local info = assert(Json.decode(dsZip["info.json"]))
eq(info.gameTypeIdentifier, "com.rileytestut.delta.game.gbc",
   "the export claims the GBC game type")
eq(info.name, "Authored", "and carries the skin name")
check(info.identifier:find("authored", 1, true) ~= nil, "identifier names the skin")
local rep = info.representations.iphone.edgeToEdge.portrait
check(rep ~= nil, "an iPhone edgeToEdge portrait representation is emitted")
eq(info.representations.iphone.standard.portrait.mappingSize.width, 1080,
   "standard portrait maps 1080 wide")
eq(rep.mappingSize.height, 1920, "portrait maps 1920 tall")
eq(#rep.items, 4, "only bound controls become Delta items")
eq(rep.items[1].inputs[1], "a", "the first item is A")
eq(rep.items[1].mask, "circle", "a radial hitbox exports as a circle mask")
eq(rep.items[1].frame.x, 756, "frame x is top-left, not centre")
eq(rep.items[1].frame.width, 216, "frame width is the full extent")
eq(rep.items[2].extendedEdges.right, 54, "reach exports as extendedEdges")
eq(rep.items[4].inputs[1], "menu", "the menu hotkey exports as a Delta host input")
eq(rep.screens[1].inputFrame.width, 160, "the screen crop is a full GB frame")
eq(rep.screens[1].outputFrame.height, 960, "and the output frame follows the viewport")
eq(info.representations.iphone.edgeToEdge.landscape.mappingSize.width, 1920,
   "the landscape page maps 1920 wide")

local back = assert(DeltaSkin.parse(dsZip["info.json"]))
eq(#back.pages, 2, "the exported skin re-imports both orientations")
local bp = back.pages[1]
eq(#bp.controls, 4, "with every bound control")
near(bp.controls[1].x, 0.8, "and the same centres it started with")
near(bp.controls[1].rangeX, 0.1, "and the same half extents")
eq(bp.controls[1].shape, "radial", "and the same hitbox shape")
near(bp.controls[2].reachRight, 1.5, "and the same reach")
near(bp.viewport.h, 0.5, "and the same screen cutout")
os.remove(dsPath)

love.filesystem.write("skins/collide/overlay.cfg", [[
overlays = 1
overlay0_name = "collide"
overlay0_descs = 1
overlay0_desc0 = "a,0.5,0.5,rect,0.05,0.05"
]])
local collide = assert(TouchSkin.load("skins/collide", "collide"))
local defaultDelta = assert(TouchSkin.exportDelta(collide))
eq(defaultDelta, "skins/_export/collide.deltaskin",
   "a default export lands outside the folder the skin list scans")
local listedRoot, listedExport
for _, entry in ipairs(TouchSkin.list()) do
  if entry.id == "collide" then listedRoot = entry.root end
  if entry.id == "_export" then listedExport = true end
end
eq(listedRoot, "skins/collide", "so the export cannot shadow the skin it came from")
check(not listedExport, "and the export folder is not a skin of its own")

T.finish("skin_format_import")
