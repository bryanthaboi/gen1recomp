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

local function session()
  Studio.skin = TouchSkin.newSkin("t")
  Studio.skinIdField = "t"
  Studio.pageIndex = 1
  Studio.selected = nil
  Studio.canvasIndex = 1
  Studio.aspectLock = true
  Studio.drag = nil
  Studio.dirty = false
  Studio.images = {}
  Studio.thumbs = {}
  Studio.available = {}
  Studio.availableMeta = {}
  Studio.undoStack, Studio.redoStack = {}, {}
  Studio.undoTag, Studio.undoAt = nil, nil
  Studio.modal, Studio.confirm = nil, nil
  Studio.status, Studio.statusErr = nil, false
  Studio.imageTarget = "idle"
  return Studio.skin
end

session()
check(not Studio.canUndo(), "a fresh session has nothing to undo")
Studio.addControl()
eq(#Studio.page().controls, 1, "a control was added")
check(Studio.canUndo(), "adding a control is undoable")
Studio.undo()
eq(#Studio.page().controls, 0, "undo takes the control back off")
check(Studio.canRedo(), "and offers a redo")
Studio.redo()
eq(#Studio.page().controls, 1, "redo puts it back")
check(not Studio.canRedo(), "the redo stack is spent")

Studio.addControl()
check(not Studio.canRedo(), "a fresh edit clears the redo stack")

session()
Studio.addControl()
local before = Studio.page().controls[1]
Studio.pushUndo()
before.x = 0.9
Studio.undo()
check(Studio.page().controls[1] ~= before,
      "undo restores a copy, not the edited table")
near(Studio.page().controls[1].x, 0.5, 1e-6, "with the pre-edit position")

session()
for _ = 1, Studio.UNDO_CAP + 10 do Studio.pushUndo() end
eq(#Studio.undoStack, Studio.UNDO_CAP, "the undo stack is capped")

session()
check(not Studio.undo(), "undo on an empty stack reports nothing to do")
check(not Studio.redo(), "and so does redo")

local realIsDown = love.keyboard and love.keyboard.isDown
love.keyboard = love.keyboard or {}
local held = {}
love.keyboard.isDown = function(...)
  for _, k in ipairs({ ... }) do if held[k] then return true end end
  return false
end
session()
Studio.addControl()
Studio.addControl()
held.lctrl = true
Studio.keypressed("z")
eq(#Studio.page().controls, 1, "ctrl+Z undoes one step")
Studio.keypressed("z")
eq(#Studio.page().controls, 0, "and again")
held.lshift = true
Studio.keypressed("z")
eq(#Studio.page().controls, 1, "ctrl+shift+Z redoes instead of undoing further")
held.lshift = nil
Studio.keypressed("y")
eq(#Studio.page().controls, 2, "and ctrl+Y redoes as well")
held.lctrl = nil
if realIsDown then love.keyboard.isDown = realIsDown end

session()
local ran = 0
check(Studio.guard("lose it?", function() ran = ran + 1 end),
      "a clean skin runs the action straight away")
eq(ran, 1, "and does not prompt")
check(Studio.confirm == nil, "no prompt is left up")

Studio.dirty = true
check(not Studio.guard("lose it?", function() ran = ran + 1 end),
      "a dirty skin defers the action")
eq(ran, 1, "the action has not run yet")
check(Studio.confirm ~= nil, "and a prompt is up")
Studio.confirmNo()
eq(ran, 1, "cancelling drops the action")
check(Studio.confirm == nil, "and closes the prompt")

Studio.guard("lose it?", function() ran = ran + 1 end)
Studio.confirmYes()
eq(ran, 2, "confirming runs it")
check(Studio.confirm == nil, "and closes the prompt")

session()
Studio.dirty = true
Studio.openLoadPicker()
check(Studio.confirm ~= nil, "Load prompts over unsaved work")
check(Studio.modal == nil, "and does not open the picker yet")
Studio.confirmYes()
check(Studio.modal ~= nil and Studio.modal.kind == "open",
      "confirming opens the picker")
Studio.closeModal()

eq(Studio.toggleBindPart("nul", "left"), "left",
   "a bind starts from decoration")
eq(Studio.toggleBindPart("left", "up"), "left|up",
   "directions combine in the canonical order")
eq(Studio.toggleBindPart("up", "left"), "left|up",
   "and the order does not depend on which was added first")
eq(Studio.toggleBindPart("left|up", "up"), "left",
   "toggling a part off removes it")
eq(Studio.toggleBindPart("left", "left"), "nul",
   "removing the last part leaves decoration")
eq(Studio.toggleBindPart("a", "b"), "a|b", "buttons combine as well")
check(Studio.hasBindPart("left|down", "down"), "hasBindPart finds a part")
check(not Studio.hasBindPart("left|down", "up"), "and misses one that is absent")

session()
check(not Studio.openBindPicker(), "the bind picker needs a selected control")
check(Studio.statusErr, "and says so as an error")
Studio.addControl()
check(Studio.openBindPicker(), "with a control selected it opens")
eq(Studio.modal.kind, "bind", "as the bind modal")
Studio.setBindSpec("start")
eq(Studio.selectedControl().spec, "start", "picking a bind writes the spec")
eq(Studio.selectedControl().buttons[1], "start", "and reparses it")
Studio.undo()
eq(Studio.selectedControl().spec, "a", "the bind change is undoable")
Studio.closeModal()

Studio.toggleSelectedBindPart("b")
eq(Studio.selectedControl().spec, "a|b", "the combine chips build a pipe bind")
eq(#Studio.selectedControl().buttons, 2, "which fires both buttons")

local specs = {}
for _, group in ipairs(Studio.BIND_GROUPS) do
  check(#group.specs > 0, group.title .. " lists at least one bind")
  for _, spec in ipairs(group.specs) do specs[spec] = true end
end
check(specs["a"] and specs["start"], "the GB buttons are reachable")
check(specs["overlay_previous"], "overlay_previous is reachable at last")
check(specs["pause_toggle"] and specs["exit_emulator"],
      "so are the hotkeys the old cycle could not reach")
check(specs["key:escape"], "and a keyboard bind can be picked")
check(specs["nul"], "decoration is still an option")

session()
Studio.addControl()
Studio.addControl()
Studio.selected = 1
local first = Studio.page().controls[1]
check(Studio.moveControlOrder(1), "bring forward moves the control up")
eq(Studio.selected, 2, "and follows it with the selection")
check(Studio.page().controls[2] == first, "the control really moved")
check(not Studio.moveControlOrder(1), "the front control cannot go further")
check(Studio.moveControlOrder(-1), "send back moves it down again")
eq(Studio.selected, 1, "selection follows back")
check(not Studio.moveControlOrder(-1), "and the back control stays put")

session()
Studio.addControl()
local ctl = Studio.selectedControl()
local canvas = Studio.canvas()
local startX, startY = ctl.x, ctl.y
Studio.nudge(1, 0)
near(ctl.x, startX + 1 / canvas.w, 1e-9, "an arrow moves one canvas pixel")
Studio.nudge(0, 1, true)
near(ctl.y, startY + 10 / canvas.h, 1e-9, "shift moves ten")
Studio.undo()
near(Studio.selectedControl().x, startX, 1e-9, "nudging is undoable")
Studio.selected = nil
check(not Studio.nudge(1, 0), "nothing selected, nothing nudged")

check(Studio.NUDGES.up[2] == -1 and Studio.NUDGES.down[2] == 1,
      "up is negative y on the canvas")
check(Studio.NUDGES.left[1] == -1 and Studio.NUDGES.right[1] == 1,
      "and left is negative x")

local off, line = Studio.snapOffset({ 100, 150, 200 }, { 152, 400 }, 4)
near(off, 2, 1e-9, "an edge within tolerance snaps to the guide")
near(line, 152, 1e-9, "and reports the line it snapped to")
off, line = Studio.snapOffset({ 100 }, { 400 }, 4)
eq(off, 0, "a line out of range does not move anything")
eq(line, nil, "and reports no guide")
off = Studio.snapOffset({ 100, 200 }, { 203, 101 }, 4)
near(off, 1, 1e-9, "the nearest candidate wins")

session()
Studio.addControl()
local r = { x = 0, y = 0, w = 1000, h = 1000 }
local xs, ys = Studio.snapLines(Studio.page(), r, nil)
check(#xs >= 6 and #ys >= 6,
      "snap lines cover the page box and every other control")
local skipped = select(1, Studio.snapLines(Studio.page(), r, 1))
eq(#skipped, 3, "the dragged control is not a guide for itself")

session()
Studio.addControl()
Studio.page().controls[1].x = 0.25
Studio.addControl()
Studio.selected = 2
local moving = Studio.selectedControl()
moving.x = 0.6
local target = Studio.page().controls[1]
local bx, by, bw, bh = 0, 0, 0, 0
local cx, cy, hw, hh = TouchSkin.controlGeometry(Studio.page(), moving,
  r.w, r.h, r.x, r.y)
bx, by, bw, bh = cx - hw, cy - hh, hw * 2, hh * 2
local tcx = select(1, TouchSkin.controlGeometry(Studio.page(), target,
  r.w, r.h, r.x, r.y))
Studio.drag = { kind = "control-move", mx = 0, my = 0,
                bx = bx, by = by, bw = bw, bh = bh }
Studio.updateDrag((tcx - cx) + 3, 0, r)
local cx2 = select(1, TouchSkin.controlGeometry(Studio.page(), moving,
  r.w, r.h, r.x, r.y))
near(cx2, tcx, 1e-6, "a near miss snaps onto the other control's centre")
check(Studio.guides ~= nil and Studio.guides.x ~= nil,
      "and a guide line is recorded for the canvas to draw")
Studio.drag = nil

session()
Studio.addPage()
Studio.addPage()
eq(#Studio.skin.pages, 3, "three pages")
check(Studio.setPage(1), "setPage jumps to a page by index")
eq(Studio.pageIndex, 1, "and lands there")
check(not Studio.setPage(9), "an index past the end is refused")
Studio.nextPage()
eq(Studio.pageIndex, 2, "next page still cycles")
local name, detail = Studio.pageLabel(2)
eq(name, "page2", "the page list shows the page name")
check(detail:find("controls", 1, true) ~= nil, "and what is on it")

check(Studio.renamePage("landscape"), "a page can be renamed")
eq(Studio.page().name, "landscape", "and keeps the new name")
check(not Studio.renamePage("  "), "an empty name is refused")
Studio.undo()
eq(Studio.page().name, "page2", "renaming is undoable")

Studio.pageIndex = 2
check(Studio.deletePage(2), "a page can be deleted")
eq(#Studio.skin.pages, 2, "and the skin loses it")
Studio.deletePage(1)
check(not Studio.deletePage(1), "the last page cannot be deleted")
check(Studio.statusErr, "and the studio says why")

session()
check(not Studio.openImagePicker("idle"), "art needs a selected control")
Studio.addControl()
check(Studio.openImagePicker("idle"), "with one selected the grid opens")
eq(Studio.modal.kind, "image", "as the image modal")
eq(Studio.imageTarget, "idle", "aimed at the idle art")
check(Studio.openImagePicker("bezel"), "the bezel needs no selection")
eq(Studio.currentImagePath(), nil, "a new page has no bezel yet")
Studio.imageTarget = "idle"
Studio.selectedControl().imagePath = "img/a.png"
eq(Studio.currentImagePath(), "img/a.png", "the picker marks the current art")
Studio.chooseImage(nil)
eq(Studio.selectedControl().imagePath, nil, "picking (none) clears the art")
eq(Studio.modal, nil, "and closes the picker")
Studio.undo()
eq(Studio.selectedControl().imagePath, "img/a.png", "clearing art is undoable")

session()
Studio.setStatus("boom", true)
check(Studio.statusErr, "an error status is flagged")
Studio.addControl()
eq(Studio.status, "boom", "a later edit does not wipe the error off the footer")
Studio.setStatus("fine")
Studio.addControl()
eq(Studio.status, nil, "an ordinary status still clears on the next edit")
Studio.setStatus("boom", true)
Studio.statusAt = -1000
Studio.expireStatus()
eq(Studio.status, nil, "and an error clears itself after a few seconds")

local ids = {}
for _, spec in ipairs(Studio.EXPORTS) do ids[spec.id] = spec.label end
check(ids.native and ids.retroarch and ids.delta,
      "the export menu offers all three formats")

session()
Studio.skinIdField = "uxtest"
local nativePath = Studio.exportAs("native")
check(nativePath ~= nil and nativePath:match("%.zip$") ~= nil,
      "the native export writes a .zip")
local raPath = Studio.exportAs("retroarch")
check(raPath ~= nil and raPath:match("%.zip$") ~= nil,
      "the RetroArch export writes a .zip")
local deltaPath = Studio.exportAs("delta")
check(deltaPath ~= nil and deltaPath:match("%.deltaskin$") ~= nil,
      "the Delta export writes a .deltaskin")
check(love.filesystem.read(deltaPath) ~= nil, "and the archive is on disk")
eq(Studio.lastExport, deltaPath, "the last export is remembered for Show file")

eq(Studio.skinFormat({ format = "retroarch" }), "RetroArch",
   "a format badge reads in words")
eq(Studio.skinFormat({ format = "delta" }), "Delta", "Delta included")

love.graphics.getDimensions = love.graphics.getDimensions
  or function() return 1280, 720 end
session()
Studio.addControl()
for _, kind in ipairs({ "bind", "image", "open", "page", "export" }) do
  Studio.openModal(kind)
  check(pcall(Studio.draw), "the studio draws with the " .. kind .. " modal up")
end
Studio.closeModal()
Studio.ask("sure?", function() end)
check(pcall(Studio.draw), "and with the confirm prompt up")
Studio.confirmNo()

Studio.openModal("bind")
Studio.lastCanvas = { x = 0, y = 0, w = 100, h = 100 }
Studio.mousepressed(50, 50, 1)
eq(Studio.drag, nil, "a click under an open modal does not grab a control")
Studio.closeModal()

T.finish("skin_studio_ux")
