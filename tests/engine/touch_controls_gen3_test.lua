package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TouchControls = require("src.core.TouchControls")
local TouchSkin = require("src.core.TouchSkin")
local DeltaSkin = require("src.core.DeltaSkin")
local Input = require("src.core.Input")
local Playfield = require("src.render.Playfield")
local Display = require("src.core.game3.display")

-- ---------------------------------------------------------------------------
-- 1. Generation awareness in TouchControls
-- ---------------------------------------------------------------------------
TouchControls:init()
TouchControls:applyOptions({ generation = 1 })
eq(#TouchControls:buttons(), 4, "Gen 1 only has 4 face/menu buttons")
eq(TouchControls.shoulders, false, "Gen 1 shoulders disabled")

TouchControls:applyOptions({ generation = 3 })
eq(#TouchControls:buttons(), 6, "Gen 3 has 6 buttons (including L and R)")
eq(TouchControls.shoulders, true, "Gen 3 shoulders enabled")

local btns = TouchControls:buttons()
local hasL, hasR = false, false
for _, b in ipairs(btns) do
  if b == "l" then hasL = true end
  if b == "r" then hasR = true end
end
check(hasL and hasR, "L and R are in the active button set for Gen 3")

-- ---------------------------------------------------------------------------
-- 2. Layout & Hitbox checks (Portrait & Landscape)
-- ---------------------------------------------------------------------------
-- Landscape (1920x1080)
local landL = TouchControls.defaultLayout(1920, 1080, 0, 0, 1.0, true)
check(landL.l ~= nil and landL.r ~= nil, "Landscape layout includes L and R")
eq(landL.l.shape, "squircle", "L has squircle shape")
eq(landL.r.shape, "squircle", "R has squircle shape")
check(landL.l.cy < landL.dpad.cy and landL.l.cy > 400, "Landscape L floats above D-pad")
check(landL.r.cy < landL.a.cy and landL.r.cy > 400, "Landscape R floats above A/B cluster")
eq(landL.l.cy, landL.r.cy, "Landscape L and R share identical horizontal baseline")

-- Portrait (1080x1920)
local portL = TouchControls.defaultLayout(1080, 1920, 0, 0, 1.0, true)
check(portL.l ~= nil and portL.r ~= nil, "Portrait layout includes L and R")
check(portL.l.cy < portL.dpad.cy - portL.dpad.w * 0.5, "Portrait L is well above D-pad to prevent Up-press bleed")
check(portL.r.cy < portL.a.cy, "Portrait R is above A/B cluster")

-- ---------------------------------------------------------------------------
-- 3. Touch hit testing and input edge routing
-- ---------------------------------------------------------------------------
Input:init()
TouchControls:init()
TouchControls.active = true
TouchControls.enabled = true
TouchControls.img = { a = {}, b = {}, l = {}, r = {}, start = {}, select = {}, dpad = {} }
TouchControls:applyOptions({ generation = 3 })
local curL = TouchControls:layout()

-- Hit test
eq(TouchControls:hitTest(curL.l.cx, curL.l.cy), "l", "hitTest on L center returns 'l'")
eq(TouchControls:hitTest(curL.r.cx, curL.r.cy), "r", "hitTest on R center returns 'r'")

-- Touch events
Input:reset()
check(TouchControls:touchpressed("touch1", curL.l.cx, curL.l.cy), "touchpressed on L captures touch")
Input:step()
check(Input:isDown("l"), "Input reflects L is down")
check(Input:wasPressed("l"), "Input registers L wasPressed edge")

TouchControls:touchreleased("touch1", curL.l.cx, curL.l.cy)
Input:step()
check(not Input:isDown("l"), "Input reflects L released")

-- Press R
TouchControls:touchpressed("touch2", curL.r.cx, curL.r.cy)
Input:step()
check(Input:isDown("r"), "Input reflects R is down")
check(Input:wasPressed("r"), "Input registers R wasPressed edge")
TouchControls:touchreleased("touch2", curL.r.cx, curL.r.cy)
Input:step()
check(not Input:isDown("r"), "Input reflects R released")

-- ---------------------------------------------------------------------------
-- 4. RetroArch GBA Alias Parsing in TouchSkin
-- ---------------------------------------------------------------------------
local retroarchGbaCfg = [[
overlays = 1
overlay0_name = "gba_test"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_descs = 6
overlay0_desc0 = "l,0.1,0.1,radial,0.05,0.05"
overlay0_desc1 = "r,0.9,0.1,radial,0.05,0.05"
overlay0_desc2 = "l1,0.1,0.2,radial,0.05,0.05"
overlay0_desc3 = "r1,0.9,0.2,radial,0.05,0.05"
overlay0_desc4 = "trigger_l,0.1,0.3,radial,0.05,0.05"
overlay0_desc5 = "trigger_r,0.9,0.3,radial,0.05,0.05"
]]

local skin = assert(TouchSkin.parse(retroarchGbaCfg))
eq(#skin.pages[1].controls, 6, "All 6 GBA shoulder control descriptions parsed")
eq(skin.pages[1].controls[1].buttons[1], "l", "desc0 maps 'l' to button 'l'")
eq(skin.pages[1].controls[2].buttons[1], "r", "desc1 maps 'r' to button 'r'")
eq(skin.pages[1].controls[3].buttons[1], "l", "desc2 maps 'l1' alias to button 'l'")
eq(skin.pages[1].controls[4].buttons[1], "r", "desc3 maps 'r1' alias to button 'r'")
eq(skin.pages[1].controls[5].buttons[1], "l", "desc4 maps 'trigger_l' alias to button 'l'")
eq(skin.pages[1].controls[6].buttons[1], "r", "desc5 maps 'trigger_r' alias to button 'r'")

-- ---------------------------------------------------------------------------
-- 5. Delta GBA Skin info.json parsing
-- ---------------------------------------------------------------------------
local deltaGbaJson = [[{
  "name": "Test GBA Skin",
  "identifier": "com.test.skin.gba",
  "gameTypeIdentifier": "com.rileytestut.delta.game.gba",
  "representations": {
    "iphone": {
      "standard": {
        "portrait": {
          "mappingSize": { "width": 1080, "height": 1920 },
          "items": [
            {
              "inputs": ["l"],
              "frame": { "x": 50, "y": 100, "width": 120, "height": 80 }
            },
            {
              "inputs": ["r"],
              "frame": { "x": 910, "y": 100, "width": 120, "height": 80 }
            }
          ]
        }
      }
    }
  }
}]]

local deltaSkin = assert(DeltaSkin.parse(deltaGbaJson))
eq(deltaSkin.system, "gba", "DeltaSkin parses gba system identifier")
eq(#deltaSkin.warnings, 0, "No unsupported system warnings for GBA")
local deltaPage = deltaSkin.pages[1]
eq(#deltaPage.controls, 2, "Delta GBA controls parsed")
eq(deltaPage.controls[1].buttons[1], "l", "Delta 'l' mapped to button 'l'")
eq(deltaPage.controls[2].buttons[1], "r", "Delta 'r' mapped to button 'r'")

-- ---------------------------------------------------------------------------
-- 6. Game 3 Display Viewport Cutout Integration
-- ---------------------------------------------------------------------------
local savedViewport = TouchSkin.viewport
-- Simulate a skin with a 960x640 (3:2) screen cutout at (120, 80) inside a 1200x800 window
TouchSkin.viewport = function(w, h)
  return 120, 80, 960, 640
end

local scaleX, ox, oy, pw, ph, scaleY = Display.fit(1200, 800)
eq(scaleX, 4, "Integer scale factor of 4 fits 240x160 into 960x640 cutout")
eq(pw, 960, "Fitted width matches 240 * 4")
eq(ph, 640, "Fitted height matches 160 * 4")
eq(ox, 120, "Screen X origin centered inside cutout")
eq(oy, 80, "Screen Y origin centered inside cutout")

TouchSkin.viewport = savedViewport

-- ---------------------------------------------------------------------------
-- 7. TouchControlsEditor with Game 3 (moving L and R)
-- ---------------------------------------------------------------------------
local TouchControlsEditor = require("src.ui.TouchControlsEditor")
local SaveData = require("src.core.SaveData")

-- Load editor with Game 3
TouchControlsEditor.load({ version = "emerald" })
check(TouchControls.shoulders, "Editor loaded for Emerald has shoulders enabled")
local editorL = TouchControls:layout()
check(editorL.l ~= nil and editorL.r ~= nil, "Editor layout has L and R zones")

-- Simulate dragging custom L button
local origLx, origLy = editorL.l.cx, editorL.l.cy
TouchControls:setControlCenter("l", origLx + 50, origLy + 50)
local updatedL = TouchControls:layout()
eq(updatedL.l.cx, origLx + 50, "Custom L button position was moved in editor")
eq(updatedL.l.cy, origLy + 50, "Custom L button Y was moved in editor")

-- Simulate dragging custom R button
local origRx, origRy = editorL.r.cx, editorL.r.cy
TouchControls:setControlCenter("r", origRx - 30, origRy + 20)
local updatedR = TouchControls:layout()
eq(updatedR.r.cx, origRx - 30, "Custom R button X was moved in editor")
eq(updatedR.r.cy, origRy + 20, "Custom R button Y was moved in editor")

TouchControlsEditor.unload()

-- ---------------------------------------------------------------------------
-- 8. Bundled GBA Skin (gba_purple) Hit Mapping
-- ---------------------------------------------------------------------------
local purpleSkin = TouchSkin.load("assets/skins/gba_purple", "gba_purple")
check(purpleSkin ~= nil, "gba_purple skin loads from assets/skins/gba_purple")
eq(purpleSkin.pages[1].controls[1].buttons[1], "l", "gba_purple ctl 1 binds l")
eq(purpleSkin.pages[1].controls[2].buttons[1], "r", "gba_purple ctl 2 binds r")
eq(purpleSkin.pages[1].controls[9].buttons[1], "a", "gba_purple ctl 9 binds a")
eq(purpleSkin.pages[1].controls[10].buttons[1], "b", "gba_purple ctl 10 binds b")

TouchControls:init()
TouchControls.active = true
TouchControls.enabled = true
TouchSkin.setActive(purpleSkin)
TouchControls.skinId = "gba_purple"
love.graphics.getDimensions = function() return 1920, 1080 end

-- Test hit detection across all controls on gba_purple with a 1920x1080 surface
local W, H = 1920, 1080
local _, lCtl = TouchControls:hitTest(0.10 * W, 0.05 * H)
check(lCtl and lCtl.buttons and lCtl.buttons[1] == "l", "L shoulder hit test maps to 'l'")

local _, rCtl = TouchControls:hitTest(0.90 * W, 0.05 * H)
check(rCtl and rCtl.buttons and rCtl.buttons[1] == "r", "R shoulder hit test maps to 'r'")

local _, aCtl = TouchControls:hitTest(0.96 * W, 0.42 * H)
check(aCtl and aCtl.buttons and aCtl.buttons[1] == "a", "A button hit test maps to 'a'")

local _, bCtl = TouchControls:hitTest(0.86 * W, 0.48 * H)
check(bCtl and bCtl.buttons and bCtl.buttons[1] == "b", "B button hit test maps to 'b'")

local _, startCtl = TouchControls:hitTest(0.15 * W, 0.73 * H)
check(startCtl and startCtl.buttons and startCtl.buttons[1] == "start", "Start button hit test maps to 'start'")

local _, selectCtl = TouchControls:hitTest(0.15 * W, 0.85 * H)
check(selectCtl and selectCtl.buttons and selectCtl.buttons[1] == "select", "Select button hit test maps to 'select'")

local _, leftCtl = TouchControls:hitTest(0.02 * W, 0.44 * H)
check(leftCtl and leftCtl.buttons and leftCtl.buttons[1] == "left", "D-pad Left hit test maps to 'left'")

local _, upCtl = TouchControls:hitTest(0.08 * W, 0.34 * H)
check(upCtl and upCtl.buttons and upCtl.buttons[1] == "up", "D-pad Up hit test maps to 'up'")

TouchSkin.setActive(nil)

T.finish("touch_controls_gen3")

