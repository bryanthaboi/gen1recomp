-- BATTLE BG on Gold (#1709): the one battle-surround setting Gold's renderer
-- can honour.  This covers the wiring a screenshot cannot -- the default key,
-- the OPTION row and its ladder, the launcher gear row, the mod-facing member
-- table -- plus the band geometry Game2 paints, asserted as rectangles rather
-- than as pixels.
--
-- What colour those bands actually come out is not a claim this file makes;
-- tests/drivers/gold_battle_bg_bug1709_test.lua is where a human judges that.

package.path = "./?.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or { random = function(a, b) return b and a or 0.5 end }
love.image = love.image or {}
love.timer = love.timer or { getTime = function() return 0 end }
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
require("src.core.Logger").warn = function() end

local BattleState = require("src.ui.gen2.BattleState")
local Chrome = require("src.ui.gen2.Chrome")
local Game2 = require("src.core.Game2")
local Gen2Compat = require("src.mods.Gen2Compat")
local LauncherSettings = require("src.import.LauncherSettings")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Save = require("src.core.gen2.Save")
local ScreenPosition = require("src.core.ScreenPosition")

local checks, failures = 0, 0
local function check(label, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(label, tostring(got),
      tostring(want)))
  end
end

-- --------------------------------------------------------------- the key

check("the default surround is the cart's paper white",
  Save.DEFAULT_OPTIONS.battleBg, "white")
check("and a fresh options table carries it",
  Save.defaultOptions().battleBg, "white")

-- --------------------------------------------------------------- the row

local function rowNamed(label)
  for i, row in ipairs(OptionsMenu.ROWS) do
    if row.label == label then return i, row end
  end
end

local bgIndex, bgRow = rowNamed("BATTLE BG")
check("OPTION has a BATTLE BG row", bgRow ~= nil, true)
if bgRow then
  check("it edits battleBg", bgRow.key, "battleBg")
  check("it is a port row, not one of the cart's seven", bgRow.port, true)
  check("WHITE and BLACK are the whole ladder", #bgRow.values, 2)
  check("stored lowercase, shown WHITE", bgRow.display.white, "WHITE")
  check("and BLACK", bgRow.display.black, "BLACK")
  -- Appended at the tail, so nothing the other suites index by position moves.
  check("it follows MAX FPS", OptionsMenu.ROWS[bgIndex - 1].label, "MAX FPS")
  check("and CANCEL still ends the list",
    OptionsMenu.ROWS[bgIndex + 1].cancel, true)
  check("CANCEL is last", bgIndex + 1, #OptionsMenu.ROWS)
end
check("the cart's rows are unmoved", OptionsMenu.ROWS[7].key, "frame")
check("the rebind screen is unmoved", OptionsMenu.ROWS[8].id, "controls")
check("the port's audio group is unmoved", OptionsMenu.ROWS[9].key, "musicVol")

-- The screen is built from ROWS, so the row has to survive buildRows too.
local menu = OptionsMenu.new({ options = Save.defaultOptions() },
  { options = Save.defaultOptions() })
local built
for _, row in ipairs(menu.rows) do
  if row.key == "battleBg" then built = row end
end
check("buildRows keeps it", built ~= nil, true)
if built then
  check("and gives it the mod-facing id battleBg", built.id, "battleBg")
  check("the menu starts on WHITE", menu.options.battleBg, "white")
  menu:cycle(built, 1)
  check("right stores black, not the display string",
    menu.options.battleBg, "black")
  menu:cycle(built, 1)
  check("right again wraps to white", menu.options.battleBg, "white")
  menu:cycle(built, -1)
  check("left walks the ladder the other way", menu.options.battleBg, "black")
  menu:cycle(built, -1)
  check("and back", menu.options.battleBg, "white")
end

-- ------------------------------------------------------ the launcher gear

local model = LauncherSettings.open(nil, "gold")
local gearRow
for _, section in ipairs(model.sections) do
  for _, row in ipairs(section.rows) do
    if row.label == "BATTLE BG" then gearRow = row end
  end
end
check("the gold gear offers BATTLE BG", gearRow ~= nil, true)
if gearRow then
  model.opts.gold.battleBg = nil
  check("an options.lua with no battleBg reads WHITE", gearRow.value(), "WHITE")
  gearRow.step(1)
  check("stepping writes the gold block, not the flat Gen 1 one",
    model.opts.gold.battleBg, "black")
  check("and the row reads BLACK", gearRow.value(), "BLACK")
  gearRow.step(1)
  check("stepping again returns to white", model.opts.gold.battleBg, "white")
end

-- ---------------------------------------------------------- the battle end

local bgMode = BattleState.bgMode
check("the Gold battle screen answers bgMode", type(bgMode), "function")
if type(bgMode) == "function" then
  check("black when the option says so",
    bgMode({ game = { options = { battleBg = "black" } } }), "black")
  check("white when it says white",
    bgMode({ game = { options = { battleBg = "white" } } }), "white")
  check("white on an options table that predates the key",
    bgMode({ game = { options = {} } }), "white")
  check("white with no game at all", bgMode({}), "white")
  -- Gen 1's third mode leaves the battle non-opaque so the map shows through;
  -- Gold has no such path, so an options.lua carried over from Red must not
  -- switch the Gold battle to a mode nothing paints.
  check("Gen 1's WORLD degrades to white here",
    bgMode({ game = { options = { battleBg = "world" } } }), "white")
end

check("and mods are told bgMode is backed on this side",
  Gen2Compat.memberStatus("src.battle.BattleState", "bgMode"), "backed")

-- ------------------------------------------------------------- the bands
--
-- Game2 paints the surround, not the battle screen: the widescreen layer
-- resolves to the TOP state, so a party menu or text box opened over the
-- battle would otherwise repaint the void white under itself.

local G = love.graphics
local realRect, realSetColor = G.rectangle, G.setColor
local painter = Game2.paintBattleSurround
check("Game2 owns the surround repaint", type(painter), "function")

local function paint(states, w, h)
  if type(painter) ~= "function" then return {} end
  local rects, pen = {}, { 1, 1, 1, 1 }
  G.setColor = function(r, g, b, a)
    pen = { r or 0, g or 0, b or 0, a or 1 }
  end
  G.rectangle = function(_, x, y, rw, rh)
    rects[#rects + 1] = { x = x, y = y, w = rw, h = rh, pen = pen }
  end
  local ok, err = pcall(painter, { stack = { states = states } }, w, h)
  G.rectangle, G.setColor = realRect, realSetColor
  if not ok then
    check("paintBattleSurround ran: " .. tostring(err), false, true)
  end
  return rects
end

local blackBattle = { bgMode = function() return "black" end }
local whiteBattle = { bgMode = function() return "white" end }
local plainMenu = {}
local overworld = {}

check("BLACK paints the four bands", #paint({ blackBattle }, 1024, 768), 4)
check("WHITE paints nothing at all", #paint({ whiteBattle }, 1024, 768), 0)
check("the overworld alone paints nothing",
  #paint({ overworld, plainMenu }, 1024, 768), 0)

-- A menu over the battle keeps the battle's void: the walk goes down the
-- stack past states that have no bgMode of their own.
check("a party menu over the battle still finds the battle's mode",
  #paint({ overworld, blackBattle, plainMenu }, 1024, 768), 4)

local function panelSafe(states, w, h, label)
  local scale = Chrome.fitScale(w, h)
  local ox, oy = Chrome.fitOrigin(w, h, scale)
  local pw, ph = 160 * scale, 144 * scale
  local rects = paint(states, w, h)
  local covered, overlap, offColour = 0, 0, 0
  for _, r in ipairs(rects) do
    covered = covered + r.w * r.h
    if r.pen[1] ~= 0 or r.pen[2] ~= 0 or r.pen[3] ~= 0 then
      offColour = offColour + 1
    end
    local ix = math.max(0, math.min(r.x + r.w, ox + pw) - math.max(r.x, ox))
    local iy = math.max(0, math.min(r.y + r.h, oy + ph) - math.max(r.y, oy))
    overlap = overlap + ix * iy
  end
  -- The band maths has to tile the void exactly: any overlap with the panel is
  -- a black frame eating the HUD or the message box, and any shortfall is a
  -- strip of white left behind on one edge.
  check(label .. ": no band touches the battle panel", overlap, 0)
  check(label .. ": the void is covered edge to edge", covered, w * h - pw * ph)
  check(label .. ": every band is black", offColour, 0)
end

for _, size in ipairs({ { 1024, 768 }, { 1280, 840 }, { 1920, 1080 },
    { 800, 600 }, { 1366, 768 } }) do
  panelSafe({ blackBattle }, size[1], size[2],
    ("%dx%d"):format(size[1], size[2]))
end

-- SCREEN POS lifts the panel off centre, which is the other way the four
-- bands can stop agreeing with where the panel actually landed.
for _, mode in ipairs({ "center", "upper", "top" }) do
  ScreenPosition.setMode(mode)
  panelSafe({ blackBattle, plainMenu }, 1280, 840, "screen pos " .. mode)
end
ScreenPosition.setMode("center")

-- A window smaller than the GB screen has no void to paint; the bands must
-- not wrap around to the far edge on the negative origin.
check("nothing to paint under 160x144", #paint({ blackBattle }, 100, 90), 0)

-- ----------------------------------------------------- the call site
--
-- Constructing a Game2 needs love, so where the paint is called from is read
-- out of the source, the way the other Gen 2 suites check this file.  It has
-- to run right after the widescreen layer has painted its white surround and
-- before the letterbox, or there is nothing to repaint over.
local handle = io.open("src/core/Game2.lua", "r")
local source = handle and handle:read("*a")
if handle then handle:close() end
check("Game2's source is readable", source ~= nil, true)
if source then
  check("drawScene repaints straight after the widescreen layer",
    source:find("wide:drawWidescreen%(w, h%)%s*self:paintBattleSurround%(w, h%)")
      ~= nil, true)
end

print(("gen2 battle options: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
