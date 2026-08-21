package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local Kit = require("src.ui.kit.Kit")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local function window(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local function pointer(x, y)
  love.mouse.getPosition = function() return x, y end
end

eq(Kit.scrollExtent(800, 500), 300, "the extent is exactly the overflow")
eq(Kit.scrollExtent(400, 500), 0, "content that fits has no extent")
eq(Kit.scrollExtent(400, -50), 400, "a negative viewport is no room, not more")
eq(Kit.scrollExtent(nil, nil), 0, "an unmeasured region has no extent")

eq(Kit.scrollClamp(-10, 300), 0, "an offset above the top clamps to it")
eq(Kit.scrollClamp(5000, 300), 300, "an offset past the end clamps to it")
eq(Kit.scrollClamp(120, 0), 0, "a region with no travel sits at the top")

local at, left = Kit.scrollHandoff(0, 300, 120)
eq(at, 120, "a move inside the extent is taken in full")
eq(left, 0, "and hands nothing on")
at, left = Kit.scrollHandoff(250, 300, 120)
eq(at, 300, "a move past the end stops at the end")
eq(left, 70, "and hands the remainder to whatever is behind it")
at, left = Kit.scrollHandoff(0, 300, -80)
eq(at, 0, "a move above the top stops at the top")
eq(left, -80, "and hands that remainder on with its sign")

local function wheelCase(offset, maxScroll, wheel, mx, my)
  Kit.blockClicks = false
  Kit.mouseX, Kit.mouseY = mx, my
  Kit.wheelY = wheel
  Kit._clipRect = nil
  local moved, took = Kit.scrollWheel(offset, maxScroll, 0, 0, 100, 100, 50)
  return moved, took, Kit.wheelY
end

local moved, took, leftWheel = wheelCase(0, 300, -1, 50, 50)
eq(moved, 50, "a notch over the region moves it by one step")
eq(took, true, "and reports the region took it")
eq(leftWheel, 0, "so nothing reaches the surface behind it")

moved, took, leftWheel = wheelCase(300, 300, -1, 50, 50)
eq(moved, 300, "a region already at its bottom does not move")
eq(took, false, "and does not claim the notch")
eq(leftWheel, -1, "which is what lets the page scroll take over")

moved, took, leftWheel = wheelCase(0, 300, 1, 50, 50)
eq(moved, 0, "a region at the top ignores an upward notch")
eq(leftWheel, 1, "and passes it on")

moved, took, leftWheel = wheelCase(0, 300, -1, 400, 400)
eq(took, false, "a notch outside the region is not the region's")
eq(leftWheel, -1, "and stays queued")

Kit.blockClicks = true
Kit.mouseX, Kit.mouseY, Kit.wheelY = 50, 50, -1
moved, took = Kit.scrollWheel(0, 300, 0, 0, 100, 100, 50)
eq(took, false, "a shielded frame (modal up) leaves the region alone")
eq(Kit.wheelY, -1, "so the modal's own scroller still sees the notch")
Kit.blockClicks = false

local function skinLauncher(count)
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.tab = "skins"
  local skins = {}
  for i = 1, count do
    skins[i] = { id = "skin" .. i, source = "user", controls = 8, pages = 1 }
  end
  imp._skins = skins
  imp._ensureSkins = function() return skins end
  return imp
end

window(360, 780)
local imp = skinLauncher(12)
LauncherView.draw(imp)
LauncherView.draw(imp)
local rect = imp._tabRegionRect
check(rect ~= nil, "the panel publishes the rect its region occupies")
check((imp._tabScrollMax.skins or 0) > 0,
  "a panel with more rows than its viewport scrolls")
eq(imp._tabScroll.skins, 0, "a freshly drawn panel sits at the top")
check(imp._tabContentH.skins > rect.h,
  "the region's content is taller than the viewport it is clipped to")

pointer(rect.x + 10, rect.y + 10)
imp._wheelY = -1
LauncherView.draw(imp)
local step = math.floor(48 * Kit.scale)
eq(imp._tabScroll.skins, step, "one notch scrolls the panel by one step")
eq(imp._pageScroll, 0,
  "and the page under it does not move while the panel still can")

for _ = 1, 30 do
  imp._wheelY = -1
  LauncherView.draw(imp)
end
eq(imp._tabScroll.skins, imp._tabScrollMax.skins,
  "held down, the panel reaches its own bottom")
eq(imp._pageScroll, imp._pageScrollMax,
  "and only then does the leftover scroll the page")

for _ = 1, 40 do
  imp._wheelY = 1
  LauncherView.draw(imp)
end
eq(imp._tabScroll.skins, 0, "scrolling back up returns the panel to the top")
eq(imp._pageScroll, 0, "and the page with it")

imp._wheelY = -1
LauncherView.draw(imp)
local parked = imp._tabScroll.skins
check(parked > 0, "the skins panel is parked mid-scroll")
imp:_switchTab("red")
LauncherView.draw(imp)
eq(imp._tabScroll.red or 0, 0, "the game tab has its own offset")
eq(imp._tabScroll.skins, parked, "and the skins offset survives the switch")
imp:_switchTab("skins")
LauncherView.draw(imp)
eq(imp._tabScroll.skins, parked, "coming back lands where the player left")

imp._skins = {}
imp._ensureSkins = function() return {} end
LauncherView.draw(imp)
LauncherView.draw(imp)
eq(imp._tabScrollMax.skins, 0, "a panel that now fits has no travel")
eq(imp._tabScroll.skins, 0, "and its offset comes back with it")

local mods = {}
for i = 1, 60 do
  mods[#mods + 1] = {
    id = "mod" .. i, name = "Mod " .. i, version = "1.0.0",
    status = "ok", badge = "gameplay", description = "a mod",
    enabledByVersion = { red = true },
  }
end
window(360, 780)
local modImp = RomImporter.new(function() end, { launcher = true })
modImp.tab = "mods"
modImp.mods = mods
modImp._ensureMods = function() return mods end
LauncherView.draw(modImp)
LauncherView.draw(modImp)
local reg = modImp._tabRegionRect
check((modImp._tabScrollMax.mods or 0) > reg.h,
  "60 installed mods are ONE continuous list: the region's travel spans "
  .. "the whole list, not one page of it")
eq(modImp._pages.mods, nil, "and no page state is ever minted for it")
pointer(reg.x + 10, reg.y + 40)
modImp._wheelY = -1
LauncherView.draw(modImp)
check((modImp._tabScroll.mods or 0) > 0,
  "a notch over the region scrolls the list like any other tab")
eq(modImp._pageScroll, 0, "without reaching the page behind it")

modImp._tabScroll.mods = modImp._tabScrollMax.mods
LauncherView.draw(modImp)
pointer(reg.x + 10, reg.y + reg.h * 0.5)
modImp._wheelY = -1
LauncherView.draw(modImp)
eq(modImp._pages.mods, nil,
  "bottoming the list out never auto-advances any pager")
eq(modImp._tabScroll.mods, modImp._tabScrollMax.mods,
  "the list just rests at its end")

modImp._modActions = "mod1"
local shieldedAt = modImp._tabScroll.mods
modImp._wheelY = -1
LauncherView.draw(modImp)
eq(modImp._tabScroll.mods, shieldedAt,
  "a shielded mod list ignores the notch under the scrim")
modImp._modActions = nil
modImp._wheelY = 0
LauncherView.draw(modImp)

window(360, 780)
local gameImp = RomImporter.new(function() end, { launcher = true })
gameImp.tab = "red"
gameImp.ready = { red = true }
gameImp.slots = { red = {} }
for i = 1, 8 do
  gameImp.slots.red[i] = { id = "slot" .. i, name = "Slot " .. i }
end
gameImp._ensureSlots = function() end
LauncherView.draw(gameImp)
LauncherView.draw(gameImp)
check((gameImp._tabScrollMax.red or 0) > 0,
  "a game tab whose cart and slots outgrow the viewport scrolls too")
check(gameImp._tabContentH.red > gameImp._tabRegionRect.h,
  "because it reports its NATURAL height, not the height it was given")
pointer(gameImp._tabRegionRect.x + 10, gameImp._tabRegionRect.y + 10)
gameImp._wheelY = -1
LauncherView.draw(gameImp)
check((gameImp._tabScroll.red or 0) > 0, "and a notch over it moves it")

window(360, 780)
local touchImp = skinLauncher(12)
LauncherView.draw(touchImp)
LauncherView.draw(touchImp)
local treg = touchImp._tabRegionRect
local tmax = touchImp._tabScrollMax.skins
check(tmax > 0, "the touched panel has travel")
LauncherView.touchpressed(touchImp, 1, treg.x + 20, treg.y + 40)
LauncherView.touchmoved(touchImp, 1, treg.x + 20, treg.y + 40 - 200)
eq(touchImp._tabScroll.skins, math.min(200, tmax),
  "dragging up scrolls the panel by the finger's travel")
eq(touchImp._pageScroll, 0, "while the panel still has travel, the page waits")
LauncherView.touchmoved(touchImp, 1, treg.x + 20, treg.y + 40 - 200 - tmax * 2)
eq(touchImp._tabScroll.skins, tmax, "a longer drag reaches the panel's bottom")
check((touchImp._pageScroll or 0) > 0, "and spills into the page from there")
LauncherView.touchreleased(touchImp, 1, treg.x + 20, treg.y - 400)

window(360, 780)
local dragMods = RomImporter.new(function() end, { launcher = true })
dragMods.tab = "mods"
dragMods.mods = mods
dragMods._ensureMods = function() return mods end
LauncherView.draw(dragMods)
LauncherView.draw(dragMods)
local dreg = dragMods._tabRegionRect
local dRegionMax = dragMods._tabScrollMax.mods
check(dRegionMax > 0, "the mods region scrolls its overscan like any tab")
LauncherView.touchpressed(dragMods, 7, dreg.x + 20, dreg.y + 30)
LauncherView.touchmoved(dragMods, 7, dreg.x + 20, dreg.y + 30 - 60)
eq(dragMods._tabScroll.mods, math.min(60, dRegionMax),
  "a drag moves the region by the finger's travel")
LauncherView.touchmoved(dragMods, 7, dreg.x + 20,
  dreg.y + 30 - 60 - dRegionMax * 2)
eq(dragMods._tabScroll.mods, dRegionMax, "carrying on saturates the region")
check((dragMods._pageScroll or 0) > 0, "and only then reaches the page")
LauncherView.touchreleased(dragMods, 7, dreg.x + 20, dreg.y - 900)

dragMods._skins = { { id = "s1", source = "user", controls = 8, pages = 1 } }
for i = 2, 12 do
  dragMods._skins[i] = { id = "s" .. i, source = "user", controls = 8, pages = 1 }
end
dragMods._ensureSkins = function() return dragMods._skins end
local heldModsPage = dragMods._pages.mods or 1
local heldModsAt = dragMods._tabScroll.mods
local overList = dreg.y + 60
dragMods:_switchTab("skins")
LauncherView.draw(dragMods)
LauncherView.draw(dragMods)
local sreg = dragMods._tabRegionRect
check((dragMods._tabScrollMax.skins or 0) > 0, "the skins tab has travel")
LauncherView.touchpressed(dragMods, 9, sreg.x + 20, overList)
LauncherView.touchmoved(dragMods, 9, sreg.x + 20, overList - 200)
check((dragMods._tabScroll.skins or 0) > 0,
  "a drag on the skins tab scrolls the skins tab")
eq(dragMods._pages.mods or 1, heldModsPage,
  "and leaves the mod list on the page the player parked it")
eq(dragMods._tabScroll.mods, heldModsAt,
  "with its region offset held for the return trip")
LauncherView.touchreleased(dragMods, 9, sreg.x + 20, sreg.y - 400)

love.graphics.polygon = love.graphics.polygon or function() end
window(360, 780)
local padImp = skinLauncher(12)
LauncherView.draw(padImp)
LauncherView.draw(padImp)
local preg = padImp._tabRegionRect
padImp._padCursorActive = true
padImp._padCursor = { x = preg.x + 10, y = preg.y + preg.h - 4 }
LauncherView.wheelmoved(padImp, 0, -1)
LauncherView.draw(padImp)
check((padImp._tabScroll.skins or 0) > 0,
  "the pad's synthesized wheel scrolls the region its cursor sits in")
eq(padImp._pageScroll, 0, "and not the page behind it")

window(1280, 720)
local edgeImp = skinLauncher(40)
LauncherView.draw(edgeImp)
LauncherView.draw(edgeImp)
local ereg = edgeImp._tabRegionRect
check((edgeImp._tabScrollMax.skins or 0) > 0, "the wide window still overflows")
eq(edgeImp._pageScrollMax, 0, "with no page scroll left to catch the notch")
check(ereg.y + ereg.h < 720, "and a region that ends above the safe area")
edgeImp._padCursorActive = true
edgeImp._padCursor = { x = ereg.x + 20, y = 719 }
edgeImp._padDir = {}
pointer(ereg.x + 20, 719)
edgeImp:gamepadaxis(nil, "lefty", 1)
edgeImp:_updatePadCursor(0.5)
eq(edgeImp._wheelY or 0, 0,
  "an axis that has never read under the deadzone cannot edge-scroll")
edgeImp._padCursor = { x = ereg.x + 20, y = 719 }
edgeImp:gamepadaxis(nil, "lefty", 0)
edgeImp:gamepadaxis(nil, "lefty", 1)
edgeImp:_updatePadCursor(0.5)
check((edgeImp._wheelY or 0) < 0, "the edge push synthesizes a notch")
LauncherView.draw(edgeImp)
check((edgeImp._tabScroll.skins or 0) > 0,
  "which reaches the tab region even though the cursor is below it")

Kit.blockClicks = false
Kit._clipRect = nil
Kit.wheelY = 0
Kit.mouseX, Kit.mouseY = 400, 400
Kit.dragBegin(50, 50)
Kit.dragAdd(120)
local pg = Kit.wheelPage(0, 0, 100, 100, 1, 100, 10)
eq(pg, 3, "a drag that crossed two half-heights turns two pages")
eq(Kit.dragAccum, 20, "and keeps the remainder for the next flip")
Kit.dragAdd(-140)
pg = Kit.wheelPage(0, 0, 100, 100, pg, 100, 10)
eq(pg, 1, "dragging back down returns those pages")
eq(Kit.dragAccum, -20, "with the remainder's sign preserved")
Kit.dragAdd(-80)
pg = Kit.wheelPage(0, 0, 100, 100, pg, 100, 10)
eq(pg, 1, "a drag past the first page clamps to it")
eq(Kit.dragAccum, 0, "and drops the pile-up so reversing is instant")
Kit.dragAdd(200)
pg = Kit.wheelPage(200, 200, 100, 100, pg, 100, 10)
eq(pg, 1, "a drag that began outside the list is not the list's")
eq(Kit.dragAccum, 200, "and its travel stays queued")
Kit.dragEnd()
eq(Kit.dragAccum, 0, "releasing the button retires the gesture")

window(360, 780)
local mouseImp = skinLauncher(12)
LauncherView.draw(mouseImp)
LauncherView.draw(mouseImp)
local mreg = mouseImp._tabRegionRect
local mmax = mouseImp._tabScrollMax.skins
check(mmax > 0, "the mouse-dragged panel has travel")
local mdown = false
love.mouse.isDown = function() return mdown end

pointer(mreg.x + 20, mreg.y + 40)
mdown = true
LauncherView.update(mouseImp, 0.016)
check(mouseImp._clickPt == nil,
  "a press over a scrollable region mints no click")
check(mouseImp._mouseAt ~= nil, "it arms a drag instead")
pointer(mreg.x + 20, mreg.y + 40 - 200)
LauncherView.update(mouseImp, 0.016)
eq(mouseImp._tabScroll.skins, math.min(200, mmax),
  "dragging the held mouse scrolls the panel by its travel")
eq(mouseImp._pageScroll or 0, 0,
  "while the panel still has travel, the page waits")
pointer(mreg.x + 20, mreg.y + 40 - 200 - mmax * 2)
LauncherView.update(mouseImp, 0.016)
eq(mouseImp._tabScroll.skins, mmax,
  "a longer mouse drag reaches the panel's bottom")
check((mouseImp._pageScroll or 0) > 0, "and spills into the page from there")
mdown = false
LauncherView.update(mouseImp, 0.016)
check(mouseImp._clickPt == nil, "a released drag is not a click")
check(mouseImp._mouseAt == nil, "and the gesture is retired")

pointer(mreg.x + 20, mreg.y + 40)
mdown = true
LauncherView.update(mouseImp, 0.016)
check(mouseImp._clickPt == nil, "a fresh press still holds its click back")
mdown = false
LauncherView.update(mouseImp, 0.016)
check(mouseImp._clickPt ~= nil,
  "press and release without travel is still a tap, on release")
mouseImp._clickPt = nil

LauncherView.draw(gameImp)
LauncherView.draw(gameImp)
check((gameImp._noDragN or 0) > 0, "the game tab publishes its cartridge rect")
local cart = gameImp._noDragRects[1]
pointer(cart.x + cart.w / 2, cart.y + cart.h / 2)
mdown = true
LauncherView.update(gameImp, 0.016)
check(gameImp._clickPt ~= nil,
  "a press on the cartridge clicks at once so its own spin-drag still owns "
    .. "the gesture")
check(gameImp._mouseAt == nil, "and never arms the scroll drag")
gameImp._clickPt = nil
mdown = false
LauncherView.update(gameImp, 0.016)
love.mouse.isDown = nil

-- Opening or relisting MODS is display work only. Release checks are an
-- explicit action, otherwise each installed GitHub mod creates background
-- work exactly when the player starts scrolling the panel.
do
  local savedMods = package.loaded["src.mods.LauncherMods"]
  local savedSaveData = package.loaded["src.core.SaveData"]
  local listCalls, updateCalls = 0, 0
  package.loaded["src.mods.LauncherMods"] = {
    list = function()
      listCalls = listCalls + 1
      return { { id = "test", github = "owner/repo" } }
    end,
  }
  package.loaded["src.core.SaveData"] = {
    loadOptions = function() return {} end,
    isSafeMode = function() return false end,
  }
  local refreshImp = setmetatable({
    modStraysChecked = true,
    _syncModUpdateInfo = function() updateCalls = updateCalls + 1 end,
  }, RomImporter)
  refreshImp:_refreshMods()
  eq(listCalls, 1, "relisting MODS still obtains its installed rows")
  eq(updateCalls, 0,
    "relisting MODS does not start release checks without the explicit button")
  package.loaded["src.mods.LauncherMods"] = savedMods
  package.loaded["src.core.SaveData"] = savedSaveData
end

local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

local view = read("src/import/LauncherView.lua")
check(view:find("Kit.scrollBegin(", 1, true) ~= nil,
  "the panel dispatch opens a scroll region")
check(view:find("Kit.scrollEnd(", 1, true) ~= nil, "and closes it")
check(view:find("modListWantsWheel", 1, true) == nil,
  "no nested list steals the wheel from the region any more")
check(view:find("start.region", 1, true) ~= nil,
  "a touch drag that began in the region scrolls the region")
check(view:find("Kit.scrollGutter(", 1, true) ~= nil,
  "the panels lay out inside a gutter, so the thumb covers no control")
check(view:find("Kit.scrollHandoff(tabScrollAt(imp)", 1, true) ~= nil,
  "and hands its leftover to the page, like the wheel does")

local kit = read("src/ui/kit/Kit.lua")
check(kit:find("function Kit.scrollWheel", 1, true) ~= nil,
  "the kit owns the wheel rule, so no panel hand-rolls a fifth copy")

T.finish("launcher scroll regions")
