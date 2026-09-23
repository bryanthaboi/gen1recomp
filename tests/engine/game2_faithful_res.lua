package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local FaithfulRes = require("src.core.FaithfulRes")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Save = require("src.core.gen2.Save")
local Playfield = require("src.render.Playfield")

local g = love.graphics
local realDims, realPixelDims = g.getDimensions, g.getPixelDimensions
love.system = love.system or {}
local realOS = love.system.getOS
local realWindow = love.window

local function pose(w, h, osName)
  love.system.getOS = function() return osName end
  g.getDimensions = function() return w, h end
  g.getPixelDimensions = function() return w, h end
end

local function reset()
  FaithfulRes.locked, FaithfulRes.prevSize = false, nil
  FaithfulRes.mobileScale = 0
end

local calls = {}
local function stubWindow(w, h)
  local cur = { w = w, h = h, flags = { resizable = true } }
  love.window = setmetatable({
    getMode = function() return cur.w, cur.h, cur.flags end,
    setMode = function(nw, nh, flags)
      calls[#calls + 1] = { w = nw, h = nh, flags = flags }
      cur.w, cur.h, cur.flags = nw, nh, flags
      return true
    end,
  }, { __index = realWindow })
end

local rowAt, row
for i, r in ipairs(OptionsMenu.ROWS) do
  if r.key == "faithfulRes" then rowAt, row = i, r end
end
check(row ~= nil, "Gen 2 OPTIONS has a FAITHFUL RATIO row")
eq(row and row.label, "FAITHFUL RATIO", "labelled as on Gen 1 and Gen 3")
eq(OptionsMenu.ROWS[rowAt - 1].key, "videoMode", "right after VIDEO MODE")
eq(OptionsMenu.ROWS[rowAt + 1].key, "screenPos", "and ahead of SCREEN POS")
eq(Save.DEFAULT_OPTIONS.faithfulRes, 0, "defaults to OFF")

do
  reset()
  pose(800, 720, "OS X")
  stubWindow(800, 720)
  calls = {}
  local options = Save.defaultOptions()
  eq(row.text(options), "OFF", "reads OFF by default")
  local seen = {}
  for _ = 1, 5 do
    row.cycle(options, 1)
    seen[#seen + 1] = row.text(options)
  end
  eq(table.concat(seen, ","), "1X,2X,3X,4X,OFF", "cycles the desktop ladder")
  row.cycle(options, -1)
  eq(options.faithfulRes, 4, "stepping back from OFF lands on 4X")
  local last = calls[#calls]
  eq(last and last.w, 640, "4X locks the window to 640 wide")
  eq(last and last.h, 576, "and 576 tall")
  eq(FaithfulRes.locked, true, "the row applies the lock live")
  row.cycle(options, 1)
  eq(FaithfulRes.locked, false, "OFF releases it")
  reset()
end

do
  local files = {}
  local fs = {
    write = function(p, c) files[p] = c return true end,
    read = function(p) return files[p] end,
    remove = function(p) files[p] = nil return true end,
    getInfo = function(p) return files[p] ~= nil and { type = "file" } or nil end,
  }
  local options = Save.defaultOptions()
  options.faithfulRes = 3
  Save.saveOptions(options, fs)
  local SaveData = require("src.core.SaveData")
  local flat = SaveData.loadOptions(fs)
  eq(flat and flat.faithfulRes, 3, "persists on the flat key Gen 1 and Gen 3 read")
  eq(flat and flat.gold and flat.gold.faithfulRes, nil, "not inside the gold block")
  eq(Save.loadOptions(fs).faithfulRes, 3, "and Gen 2 reads it back")
  flat.faithfulRes = 2
  SaveData.saveOptions(flat, fs)
  eq(Save.loadOptions(fs).faithfulRes, 2, "a Gen 1 edit carries into Gen 2")
end

local Game2 = require("src.core.Game2")

do
  reset()
  pose(800, 720, "OS X")
  stubWindow(800, 720)
  calls = {}
  local seen
  local real = FaithfulRes.applyOptions
  FaithfulRes.applyOptions = function(opts)
    seen = opts and opts.faithfulRes
    return real(opts)
  end
  local fake = setmetatable({ options = Save.defaultOptions() }, Game2)
  fake.options.faithfulRes = 2
  local ok, err = pcall(Game2.applyOptions, fake)
  FaithfulRes.applyOptions = real
  check(ok, "Game2:applyOptions runs headless: " .. tostring(err))
  eq(seen, 2, "Game2:applyOptions pushes faithfulRes into FaithfulRes")
  eq(FaithfulRes.locked, true, "so a boot restores the lock")
  eq(calls[#calls] and calls[#calls].w, 320, "at 2X")
  FaithfulRes.apply(0)
  reset()
end

do
  reset()
  pose(1080, 2400, "Android")
  eq(Game2.faithfulBox(1080, 2400), nil, "no box while the lock is off")
  FaithfulRes.apply(1)
  local x, y, w, h = Game2.faithfulBox(1080, 2400)
  eq(w, 960, "the mobile lock clips Gen 2 to a whole 6x multiple wide")
  eq(h, 864, "and 10:9 tall")
  eq(x, 60, "centred across")
  eq(y, 768, "and down")

  local drawn
  local fake = setmetatable({}, Game2)
  fake.drawScene = function(_, sw, sh)
    local dw, dh = Playfield.dimensions()
    drawn = { w = sw, h = sh, dw = dw, dh = dh }
  end
  fake:drawContained(1080, 2400)
  eq(drawn and drawn.w, 960, "drawScene is handed the locked width")
  eq(drawn and drawn.h, 864, "and height")
  eq(drawn and drawn.dw, 960, "the world sizes its view off the locked box")
  eq(drawn and drawn.dh, 864, "on both axes")
  eq(Playfield.entered, false, "and the playfield is released afterwards")

  FaithfulRes.apply(0)
  fake:drawContained(1080, 2400)
  eq(drawn and drawn.w, 1080, "OFF draws edge to edge again")
  reset()
end

do
  pose(800, 720, "OS X")
  local LauncherSettings = require("src.import.LauncherSettings")
  for _, version in ipairs({ "gold", "silver", "crystal" }) do
    local model = LauncherSettings.open({}, version)
    local found, prev
    for _, section in ipairs(model.sections) do
      for _, r in ipairs(section.rows) do
        if r.label == "FAITHFUL RATIO" then found = r end
        if not found then prev = r.label end
      end
    end
    check(found ~= nil, version .. " launcher gear offers FAITHFUL RATIO")
    eq(prev, "VIDEO MODE", version .. " next to VIDEO MODE")
    if found then
      local before = found.value()
      found.step(1)
      check(found.value() ~= before, version .. " launcher row steps")
    end
  end
end

g.getDimensions, g.getPixelDimensions = realDims, realPixelDims
love.system.getOS = realOS
love.window = realWindow
reset()
T.finish("game2 faithful res")
