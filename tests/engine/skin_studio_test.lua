-- Skin Studio model layer (#1386): canvas presets, control editing, the
-- drag/resize math and the pixel coordinate fields.  Drawing is exercised by
-- tests/drivers/skin_studio_shot.lua; this pins the state machine underneath.
--   luajit tests/engine/skin_studio_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local TouchSkin = require("src.core.TouchSkin")
local Studio = require("src.ui.SkinStudio")

local function near(a, b, tol, msg)
  check(math.abs(a - b) <= (tol or 1e-6), msg .. " (got " .. tostring(a) ..
        ", want " .. tostring(b) .. ")")
end

-- a studio session without touching options or the filesystem
local function session()
  Studio.skin = TouchSkin.newSkin("t")
  Studio.pageIndex = 1
  Studio.selected = nil
  Studio.canvasIndex = 1
  Studio.viewZoom = 1
  Studio.aspectLock = true
  Studio.drag = nil
  Studio.dirty = false
  Studio.images = {}
  return Studio.skin
end

-- ------------------------------------------------------------- new skin

session()
eq(#Studio.skin.pages, 1, "a new skin starts with one page")
eq(#Studio.page().controls, 0, "and no controls")
check(Studio.page().viewport ~= nil, "and a screen cutout to place")
check(Studio.selectedControl() == nil, "nothing selected yet")

-- ------------------------------------------------------------- controls

Studio.addControl()
eq(#Studio.page().controls, 1, "addControl appends")
eq(Studio.selected, 1, "and selects what it added")
check(Studio.dirty, "editing marks the skin dirty")
local ctl = Studio.selectedControl()
eq(ctl.spec, "a", "new controls default to GB a")
eq(ctl.buttons[1], "a", "and carry the parsed bind")

Studio.cycleBind(1)
check(ctl.spec ~= "a", "cycleBind moves off the current bind")
check(#ctl.buttons + #ctl.hotkeys + #ctl.keys > 0 or ctl.decorative,
      "cycleBind reparses the bind")
Studio.cycleBind(-1)
eq(ctl.spec, "a", "cycleBind is reversible")

Studio.duplicateControl()
eq(#Studio.page().controls, 2, "duplicate adds a second control")
eq(Studio.selected, 2, "and selects the copy")
check(Studio.page().controls[2] ~= Studio.page().controls[1],
      "the copy is a separate table")
near(Studio.page().controls[2].x, Studio.page().controls[1].x + 0.04, 1e-6,
     "the copy is offset so it is visible")

Studio.deleteControl()
eq(#Studio.page().controls, 1, "delete removes it")
Studio.deleteControl()
eq(#Studio.page().controls, 0, "delete works down to empty")
eq(Studio.selected, nil, "and clears the selection")

-- ------------------------------------------------------- canvas presets

local ids = {}
for _, c in ipairs(Studio.CANVASES) do
  if c.live then
    check(c.id == "this_device", "the live preset is this screen")
  else
    check(c.w > 0 and c.h > 0, c.id .. " has real pixel dimensions")
  end
  check(not ids[c.id], c.id .. " appears once")
  ids[c.id] = true
end
check(ids.phone_portrait, "a phone portrait preset exists")
check(ids.this_device, "a this-screen live preset exists")
check(ids.desktop_1080, "a desktop preset exists")
check(ids.ultrawide, "an ultrawide preset exists")
check(ids.sgb_border, "a Super Game Boy border preset exists")

session()
local sgbIndex
for i, c in ipairs(Studio.CANVASES) do
  if c.id == "sgb_border" then sgbIndex = i end
end
Studio.setCanvas(sgbIndex)
local canvas = Studio.canvas()
eq(canvas.w, 256, "SGB canvas is 256 wide")
eq(canvas.h, 224, "SGB canvas is 224 tall")
local vp = Studio.page().viewport
near(vp.x * 256, 48, 1e-6, "SGB screen sits 48px from the left")
near(vp.y * 224, 40, 1e-6, "SGB screen sits 40px from the top")
near(vp.w * 256, 160, 1e-6, "SGB screen is 160px wide")
near(vp.h * 224, 144, 1e-6, "SGB screen is 144px tall")

-- the locked preset refuses to let the cutout be moved or removed
Studio.toggleViewport()
check(Studio.page().viewport ~= nil, "the SGB cutout cannot be toggled off")

-- presets wrap rather than running off the end of the list
Studio.setCanvas(#Studio.CANVASES + 1)
eq(Studio.canvasIndex, 1, "canvas selection wraps")

-- the preview must lay the page out the way the game will, so a preset never
-- overwrites the aspect the bezel art (or a cfg) already fixed
session()
local art = Studio.page()
art.aspect, art.aspectFromImage = 0.5625, true
Studio.setCanvas(1)
near(art.aspect, 0.5625, 1e-9, "bezel art keeps its own aspect on a preset switch")
local deckW, deckH = 900, 1700
local _, dby, _, dbh = TouchSkin.pageBox(art, deckW, deckH)
check(dby > 0 and math.abs(dby + dbh - deckH) < 1e-6,
      "so a preset taller than the art pins the deck low, as gameplay does")

session()
local plain = Studio.page()
plain.aspect, plain.aspectFromImage, plain.aspectFromCfg = nil, nil, nil
Studio.setCanvas(1)
near(plain.aspect, Studio.canvas().w / Studio.canvas().h, 1e-9,
     "a page with no art of its own still takes the preset's aspect")

Studio.setCanvas(1)
Studio.viewZoom = 1
local cx, cy, cw, ch = Studio.canvasRect(0, 0, 800, 600)
near(cw / ch, Studio.canvas().w / Studio.canvas().h, 1e-6,
     "the mock device keeps its aspect")
check(cw <= 800 + 1e-6 and ch <= 600 + 1e-6, "and fits inside the workspace")
near(cx + cw / 2, 400, 1e-6, "centred horizontally")
near(cy + ch / 2, 300, 1e-6, "centred vertically")

eq(Studio.zoomOut(), 0.75, "zoom out steps to 75%")
local zx, zy, zw, zh = Studio.canvasRect(0, 0, 800, 600)
near(zw, cw * 0.75, 1e-6, "zoom out shrinks the mock device")
near(zh, ch * 0.75, 1e-6, "on both axes")
near(zx + zw / 2, 400, 1e-6, "and stays centred")
near(zw / zh, cw / ch, 1e-6, "keeping the same aspect")
check(zw < cw, "so there is margin around the device for a larger screen hole")
eq(Studio.zoomIn(), 1, "zoom in restores fit")
eq(Studio.zoomOut(), 0.75)
eq(Studio.zoomOut(), 0.5)
eq(Studio.zoomOut(), 0.35)
eq(Studio.zoomOut(), 0.35, "zoom out stops at the smallest level")
eq(Studio.zoomFit(), 1, "fit snaps back to contain")

local oldDims = love.graphics.getDimensions
love.graphics.getDimensions = function() return 1170, 2532 end
session()
local live = Studio.detectDeviceCanvas()
eq(live.id, "this_device", "detect this screen selects the live canvas")
eq(live.w, 1170, "at the window width")
eq(live.h, 2532, "and the window height")
eq(Studio.canvas().w / Studio.canvas().h, 1170 / 2532,
   "so the mock device is this screen's form factor")
Studio.matchOrient = true
Studio.syncCanvasToPage()
eq(Studio.canvas().id, "this_device",
   "Match canvas leaves the live screen selected")
love.graphics.getDimensions = oldDims

-- ----------------------------------------------------------- touch bridge

session()
Studio.lastCanvas = { x = 0, y = 0, w = 100, h = 100 }
Studio.touchpressed("finger", 50, 50)
eq(Studio.touchId, "finger", "the first finger owns the Studio gesture")
check(Studio.pointerDown, "a touch is tracked as a held editor pointer")
Studio.touchmoved("finger", 60, 50)
Studio.touchreleased("finger", 60, 50)
eq(Studio.touchId, nil, "lifting clears the captured finger")
check(not Studio.pointerDown, "and releases the editor pointer")

-- ---------------------------------------------------------------- drag

session()
Studio.addControl()
ctl = Studio.selectedControl()
local r = { x = 0, y = 0, w = 1000, h = 1000 }
local startX, startY = ctl.x, ctl.y

Studio.drag = { kind = "control-move", mx = 500, my = 500,
                bx = 420, by = 455, bw = 160, bh = 90 }
Studio.updateDrag(600, 500, r)
near(ctl.x, startX + 0.1, 1e-6, "dragging right moves the control right")
near(ctl.y, startY, 1e-6, "and leaves y alone")

Studio.drag = { kind = "control-resize", handle = "se", mx = 500, my = 500,
                bx = 400, by = 400, bw = 100, bh = 100 }
Studio.updateDrag(600, 600, r)
near(ctl.rangeX * 2 * r.w, 200, 1e-6, "the se handle widens the control")
near(ctl.rangeY * 2 * r.h, 200, 1e-6, "and heightens it")

-- the viewport keeps the Game Boy's 10:9 while the lock is on
Studio.aspectLock = true
Studio.selected = nil
Studio.drag = { kind = "viewport-resize", handle = "se", mx = 0, my = 0,
                bx = 0, by = 0, bw = 400, bh = 400 }
Studio.updateDrag(100, 0, r)
local v = Studio.page().viewport
near(v.w / v.h, 160 / 144, 1e-6, "10:9 lock holds the screen aspect")

Studio.aspectLock = false
Studio.drag = { kind = "viewport-resize", handle = "se", mx = 0, my = 0,
                bx = 0, by = 0, bw = 400, bh = 400 }
Studio.updateDrag(100, 200, r)
v = Studio.page().viewport
near(v.w * r.w, 500, 1e-6, "unlocked, width follows the pointer")
near(v.h * r.h, 600, 1e-6, "and height is free")

Studio.drag = { kind = "viewport-move", mx = 0, my = 0,
                bx = 0, by = 0, bw = 100, bh = 100 }
Studio.updateDrag(-250, 1100, r)
v = Studio.page().viewport
check(v.x < 0, "a screen anchor can move past the left canvas edge")
check(v.y > 1, "a screen anchor can move past the bottom canvas edge")

-- controls never escape the canvas
Studio.selected = 1
Studio.drag = { kind = "control-move", mx = 0, my = 0,
                bx = 0, by = 0, bw = 100, bh = 100 }
Studio.updateDrag(-100000, -100000, r)
check(ctl.x >= 0 and ctl.y >= 0, "a control cannot be dragged off the top-left")
Studio.updateDrag(100000, 100000, r)
check(ctl.x <= 1 and ctl.y <= 1, "or off the bottom-right")

-- ------------------------------------------------------- pixel fields

session()
Studio.addControl()
ctl = Studio.selectedControl()
canvas = Studio.canvas()
eq(canvas.w, 1080, "phone portrait is 1080 wide")

Studio.commitField("numW", "216")
near(ctl.rangeX * 2 * canvas.w, 216, 1e-6, "W is typed in canvas pixels")
Studio.commitField("numX", "100")
near((ctl.x - ctl.rangeX) * canvas.w, 100, 1e-4, "X is the left edge in pixels")
Studio.commitField("numH", "180")
near(ctl.rangeY * 2 * canvas.h, 180, 1e-6, "H is typed in canvas pixels")
Studio.commitField("numY", "640")
near((ctl.y - ctl.rangeY) * canvas.h, 640, 1e-4, "Y is the top edge in pixels")
-- X must not have drifted when the later fields were set
near((ctl.x - ctl.rangeX) * canvas.w, 100, 1e-4, "X survives edits to the others")

local keptX = ctl.x
Studio.commitField("numX", "not a number")
near(ctl.x, keptX, 1e-9, "garbage in a field is ignored")

-- ---------------------------------------------------------------- pages

session()
Studio.addPage()
eq(#Studio.skin.pages, 2, "addPage appends a page")
eq(Studio.pageIndex, 2, "and switches to it")
eq(Studio.page().name, "page2", "the new page is named in sequence")
Studio.addControl()
eq(#Studio.skin.pages[2].controls, 1, "controls land on the active page")
eq(#Studio.skin.pages[1].controls, 0, "and not on the other one")

-- page orientation lock follows the canvas when Match canvas is on (#1503)
session()
Studio.canvasIndex = 1
Studio.matchOrient = true
eq(Studio.cyclePageOrient(1), "portrait", "cycle starts at portrait from unlocked")
eq(Studio.page().orient, "portrait", "and stores the lock on the page")
eq(Studio.page().name, "portrait", "a generic page is renamed so play can auto-rotate")
eq(Studio.canvas().id, "phone_portrait", "and the canvas stays portrait")

Studio.addPage()
eq(Studio.cyclePageOrient(1), "portrait", "the new page starts unlocked, first lock is portrait")
Studio.cyclePageOrient(1)
eq(Studio.page().orient, "landscape", "second cycle is landscape")
eq(Studio.canvas().id, "phone_landscape", "Match canvas flips the mock device with the page")

Studio.pageIndex = 1
Studio.syncCanvasToPage()
eq(Studio.canvas().id, "phone_portrait", "switching back to the portrait page restores portrait canvas")

Studio.setCanvas(2)
eq(Studio.pageIndex, 2, "picking a landscape canvas selects the landscape page")

Studio.matchOrient = false
Studio.pageIndex = 1
Studio.setCanvas(2)
eq(Studio.pageIndex, 1, "Match canvas off leaves the page when the device changes")
eq(Studio.canvas().id, "phone_landscape", "and still honours the canvas click")

-- a RetroArch overlay that already auto-rotates locks itself on open (#1503)
session()
Studio.matchOrient = false
Studio.canvasIndex = 2
Studio.skin = assert(TouchSkin.parse([[
overlays = 2
overlay0_name = "portrait"
overlay0_full_screen = true
overlay0_descs = 1
overlay0_desc0 = "a,0.5,0.5,radial,0.05,0.05"
overlay1_name = "landscape"
overlay1_full_screen = true
overlay1_descs = 1
overlay1_desc0 = "a,0.5,0.5,radial,0.05,0.05"
]]))
Studio.pageIndex = 1
check(Studio.applyImportedOrient(), "import of a portrait/landscape pair is automatic")
check(Studio.matchOrient, "and turns Match canvas on")
eq(Studio.page().name, "landscape", "keeping the landscape canvas already on screen")
eq(Studio.page().orient, "landscape", "with the page already locked")

-- --------------------------------------------------------------- clone

local source = TouchSkin.load("assets/skins/gb_anim", "gb_anim")
check(source ~= nil, "bundled skin loads for cloning")
if source then
  local copy = TouchSkin.clone(source)
  eq(#copy.pages, #source.pages, "clone keeps every page")
  eq(#copy.pages[1].controls, #source.pages[1].controls, "and every control")
  check(copy.pages[1] ~= source.pages[1], "pages are fresh tables")
  check(copy.pages[1].controls[1] ~= source.pages[1].controls[1],
        "controls are fresh tables")
  eq(copy.pages[1].image, source.pages[1].image, "loaded images are shared, not reloaded")
  copy.pages[1].controls[1].x = 0.123
  check(source.pages[1].controls[1].x ~= 0.123,
        "editing the clone does not touch the loaded skin")
end

-- ------------------------------------------------------------ play handoff

-- Play used to call the host handler straight out of the Kit button, which
-- unloaded the studio inside its own draw pass; the rest of that frame then
-- indexed a nil skin and took the app down.  The handoff is deferred to
-- update, and a torn-down studio has to survive a draw either way.
session()
Studio.available, Studio.images = {}, {}
Studio.skinIdField, Studio.onClose = "t", function() end
local fired, gotVersion = 0, nil
Studio.version = "red"
Studio.onPlay = function(v)
  fired = fired + 1
  gotVersion = v
  Studio.unload()
end

Studio.play()
check(Studio.pendingPlay, "play queues the handoff")
eq(fired, 0, "play does not hand off during the click")
check(Studio.skin ~= nil, "and leaves the skin alive for the rest of the frame")
check(pcall(Studio.draw), "the frame that queued play still draws")

Studio.update()
eq(fired, 1, "update performs the handoff")
eq(gotVersion, "red", "and passes the launcher tab through")
eq(Studio.skin, nil, "the studio is unloaded by then")
check(pcall(Studio.draw), "a torn-down studio still survives a draw")

Studio.update()
eq(fired, 1, "the handoff does not repeat")

-- unload must clear a queued handoff, or closing then reopening would boot
session()
Studio.onPlay = function() fired = fired + 1 end
Studio.play()
check(Studio.pendingPlay, "queued again")
Studio.unload()
check(not Studio.pendingPlay, "unload drops a queued handoff")
Studio.update()
eq(fired, 1, "closing the studio does not start the game")

-- the studio is a desktop workspace; the launcher only offers it there
check(type(Studio.available_desktop) == "function", "desktop gate is exported")
check(Studio.available_desktop(), "headless/desktop reports available")

T.finish("skin_studio")
