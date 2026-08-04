-- Manual check that the save editor's item lists scroll under the wheel (#595).
-- The ADD ITEM picker lists every non-badge id in pokered constants/item_constants.asm,
-- which is far more than one screenful, and typing a query used to be the only way
-- past the first page.  This is the editor app, not the game, so there is no
-- POKEPORT_DRIVER hook: this file runs itself, checks the seams, seeds a save with
-- a stocked bag and PC, then opens the real editor on it.  Do not set POKEPORT_SPEED.
--   luajit tests/drivers/item_picker_wheel_bug595_test.lua

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

love = require("tests.love_stub")

local Kit = require("Kit")
local App = require("App")
local Ops = require("Ops")
local SaveData = require("src.core.SaveData")

-- unbuffered, or a redirected run would show the editor's own output before
-- the checks that were printed ahead of it
io.stdout:setvbuf("line")

local function log(...) print("[driver]", ...) end

local fails = 0
local function check(label, ok)
  if not ok then fails = fails + 1 end
  log(ok and "PASS" or "FAIL", label)
  return ok
end

-- ------------------------------------------------------------------ Kit seam
-- Kit.scroll is the whole fix; every panel rule below is a consequence of it.
check("Kit.scroll exists", type(Kit.scroll) == "function")

Kit.beginFrame(50, 50, false, -1)
check("a notch inside a list body advances three rows",
      Kit.scroll(0, 0, 100, 100, 0, 250, 10) == 3)
check("and is consumed, so a second list cannot eat the same notch",
      Kit.wheelY == 0)
Kit.endFrame()

Kit.beginFrame(50, 50, false, -1)
check("the last page is the floor",
      Kit.scroll(0, 0, 100, 100, 245, 250, 10) == 240)
Kit.endFrame()

Kit.beginFrame(500, 500, false, -1)
check("a list the pointer is not over ignores the wheel",
      Kit.scroll(0, 0, 100, 100, 0, 250, 10) == 0)
Kit.endFrame()

Kit.beginFrame(50, 50, false, -1)
Kit.blockClicks = true
check("the species-picker modal shield stops the wheel like it stops a click",
      Kit.scroll(0, 0, 100, 100, 0, 250, 10) == 0)
Kit.blockClicks = false
Kit.endFrame()

-- ------------------------------------------------------------- seeded save
-- A save with one page of items proves nothing: stock the bag to its cap and
-- push a couple of pages into PC storage so both pagers have somewhere to go.
local SEED_DIR = (os.getenv("TMPDIR") or "/tmp/"):gsub("/*$", "/") .. "pokeport-bug595"
local SEED = SEED_DIR .. "/save.lua"
os.execute('mkdir -p "' .. SEED_DIR .. '" 2>/dev/null')

local seedFile = io.open(SEED, "wb")
if seedFile then
  seedFile:write(SaveData.encode(SaveData.newGame()))
  seedFile:close()
end
check("a scratch save was written to " .. SEED, seedFile ~= nil)

local ok, err = pcall(App.load, SEED, { version = "red" })
check("the editor loads it headless (data/generated present): " .. tostring(err), ok)

local S = ok and App.getState() or nil
if S then
  S.tab = "items"
  local stocked, pcKinds = 0, 0
  S.save.pcItems = S.save.pcItems or {}
  for _, id in ipairs(S.cat.items) do
    if not Ops.isBadgeId(id) then
      stocked = stocked + 1
      if stocked <= 20 then
        S.save.inventory[id] = 3
      elseif pcKinds < 30 then
        pcKinds = pcKinds + 1
        S.save.pcItems[id] = 5
      end
    end
  end
  local out = io.open(SEED, "wb")
  if out then out:write(SaveData.encode(S.save)) out:close() end
  App.load(SEED, { version = "red" })
  S = App.getState()
  S.tab = "items"

  -- The panel is layout over Ops, so its rects are not written down anywhere:
  -- read them back off the Kit.scroll calls the draw makes, which is also the
  -- only honest way to point the fake mouse at the right list.  If a rect goes
  -- missing the hand-off below still happens, with the count in the log.
  local rects = {}
  local realScroll = Kit.scroll
  Kit.scroll = function(x, y, w, h, offset, total, perPage)
    rects[#rects + 1] = { x = x, y = y, w = w, h = h, total = total }
    return realScroll(x, y, w, h, offset, total, perPage)
  end
  local fields = {}
  local realField = Kit.textfield
  Kit.textfield = function(id, x, y, w, h, value, placeholder)
    fields[id] = { x = x, y = y, w = w, h = h }
    return realField(id, x, y, w, h, value, placeholder)
  end
  local counters = {}
  local realRight = Kit.textRight
  Kit.textRight = function(name, str, ...)
    counters[#counters + 1] = tostring(str)
    return realRight(name, str, ...)
  end

  App.draw()
  check("the Items tab hands three lists to Kit.scroll (picker, bag, PC)",
        #rects == 3)
  local pick, bag, pc = rects[1], rects[2], rects[3]

  local function pointAt(r)
    love.mouse.getPosition = function() return r.x + r.w / 2, r.y + r.h / 2 end
  end
  local function counterLine()
    for _, str in ipairs(counters) do
      if str:match("^%d+%-%d+ of %d+$") then return str end
    end
    return nil
  end

  if pick then
    check("the picker caption carries a position counter, not a +N more",
          counterLine() ~= nil)
    log("the picker counter reads", tostring(counterLine()),
        "over a catalog of " .. tostring(pick.total) .. " ids")

    pointAt(pick)
    counters = {}
    App.wheelmoved(0, -1)
    App.draw()
    check("one notch over the picker advances it three rows",
          S.itemPickOffset == 3)
    check("and neither the bag nor the PC column moved with it",
          S.bagOffset == 0 and S.pcOffset == 0)
    log("the counter now reads", tostring(counterLine()))
  end

  if bag then
    pointAt(bag)
    local before = S.itemPickOffset
    App.wheelmoved(0, -1)
    App.draw()
    check("a notch over the BAG column moves the bag pager's own offset",
          S.bagOffset > 0)
    check("and leaves the picker where it was", S.itemPickOffset == before)
  end

  if pc then
    pointAt(pc)
    local before = S.bagOffset
    App.wheelmoved(0, -1)
    App.draw()
    check("a notch over PC STORAGE moves the PC list", S.pcOffset > 0)
    check("and leaves the bag where it was", S.bagOffset == before)
  end

  -- Typing has to rewind the view: a query that matches ids near the top of a
  -- catalog the view had already scrolled past would otherwise show an empty
  -- body over a non-zero offset, which reads exactly like "no item matches".
  local field = fields["item-query"]
  if pick and field then
    pointAt(pick)
    for _ = 1, 12 do
      App.wheelmoved(0, -1)
      App.draw()
    end
    local deep = S.itemPickOffset
    love.mouse.getPosition = function() return field.x + 4, field.y + 4 end
    App.mousepressed(field.x + 4, field.y + 4, 1)
    App.draw()
    App.textinput("P")
    App.draw()
    check("a keystroke in the search box rewinds the deep-scrolled list to the top",
          deep > 0 and S.itemQuery == "P" and S.itemPickOffset == 0)
  end

  -- The map tab spends the wheel on zoom and must keep it.
  S.tab = "items"
  local zoom = S.mapZoom
  App.wheelmoved(0, -1)
  App.draw()
  check("a notch outside the Map tab leaves the map camera alone", S.mapZoom == zoom)
  S.tab = "map"
  App.wheelmoved(0, 1)
  check("the Map tab still zooms on the wheel", S.mapZoom > zoom)

  Kit.scroll, Kit.textfield, Kit.textRight = realScroll, realField, realRight
  App.unload()
end

log(fails == 0 and "all seam checks passed" or (fails .. " seam checks failed"))

-- --------------------------------------------------------------- hand-off
log("Opening the editor on that seeded save. Click the Items tab, put the pointer")
log("over the ADD ITEM list and roll the wheel: rows step three at a time and the")
log("counter on the caption line tracks them, stopping on the last page; clicking a")
log("row still picks it for the two add buttons. Over BAG or PC STORAGE the wheel")
log("moves the same rows the Prev/Next pager does and the pager label keeps up.")
log("The near miss to watch for is both columns jumping on one notch, or the panel")
log("scrolling underneath the species picker while that modal is open on Party.")

local love_bin = os.getenv("LOVE") or "love"
os.execute(love_bin .. ' . --editor --save "' .. SEED .. '"')

log("Editor closed. Reopen it on the same stocked save any time with:")
log("  " .. love_bin .. ' . --editor --save "' .. SEED .. '"')

-- Park rather than exit: the driver is never the thing that ends the session,
-- so the terminal stays put until the reader Ctrl-Cs it.
while true do
  os.execute("sleep 3600")
end
