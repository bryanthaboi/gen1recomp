-- The OPTION screen's grouped pages and its scrolling text.
--
-- The flat row list outgrew the four-box viewport, so the battle, audio,
-- video and speed rows collapse into one opener each.  Grouping happens after
-- the ui.options.rows hook and only builds self.view, so self.rows stays the
-- flat list a mod reads and edits.
--
-- Text longer than its line used to run off the 160px panel with no clipping
-- (COLORS showed "1-A (Default) (B"); the highlighted row now scrolls instead.
--   luajit tests/engine/options_submenu_marquee_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local OptionsMenu = require("src.ui.OptionsMenu")
local Marquee = require("src.ui.Marquee")

local function stubGame()
  local stack = { items = {} }
  function stack:push(s) self.items[#self.items + 1] = s; return s end
  function stack:pop() self.items[#self.items] = nil end
  function stack:top() return self.items[#self.items] end
  return {
    data = { rulesets = { gen1_faithful = { name = "GEN 1" } }, constants = {} },
    save = { options = {} },
    stack = stack,
    modStatus = { available = {} },
  }
end

local function ids(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.id end
  return table.concat(out, ",")
end

local function find(rows, id)
  for i, row in ipairs(rows) do if row.id == id then return row, i end end
end

-- ------------------------------------------------------------- grouping

local game = stubGame()
local menu = OptionsMenu.new(game)

T.check(find(menu.rows, "battleBg"), "self.rows keeps the flat list for mods")
T.check(find(menu.rows, "musicVol"), "self.rows keeps the audio rows too")
for _, id in ipairs({ "battleBg", "speedMenu", "uiLayout", "tilt", "zoom",
                      "voidFill", "colors", "shaderfx", "shaderfx2",
                      "musicVol", "videoMode" }) do
  T.check(not find(menu.view, id), id .. " moved onto a page")
end

for _, spec in ipairs({
  { "group.battle", 6 }, { "group.audio", 3 }, { "group.video", 5 },
  { "group.speed", 4 }, { "group.graphics", 4 }, { "group.extras", 3 },
}) do
  local row = find(menu.view, spec[1])
  T.check(row, spec[1] .. " has an opener row")
  T.eq(row.group, true, spec[1] .. " is marked as a group")
end

-- Six battle rows on this build (PIKACHU VOL is Yellow-only, so AUDIO is 3).
T.eq(select(1, find(menu.view, "group.battle")).value(game), "6 OPTIONS",
  "BATTLE OPTIONS counts its six rows")

-- The top level is explicitly ordered, groups and singles interleaved.
T.eq(ids(menu.view):gsub("group%.", ""),
  "speed,video,graphics,audio,performance,ruleset,battle,extras,mods," ..
  "controls,dateFormat,timeFormat",
  "the top level reads in the order ORDER names")
T.check(not find(menu.view, "textSpeed"), "TEXT SPEED moved onto the SPEED page")
T.check(#menu.view < #menu.rows, "the view is shorter than the flat list")

-- A row in no group is untouched and keeps its order.
T.check(find(menu.view, "ruleset"), "RULESET stays on the top level")
T.check(find(menu.view, "performance"), "so does PERFORMANCE")
T.check(find(menu.view, "mods"), "and MODS")

-- ------------------------------------------------------------- submenus

local graphics = find(menu.view, "group.graphics")
graphics.activate(game)
T.eq(ids(game.stack:top().view), "colors,uiLetterbox,shaderfx,shaderfx2",
  "GRAPHICS carries COLORS, UI LETTERBOX and both SHADER FX slots")
game.stack:pop()

local extras = find(menu.view, "group.extras")
extras.activate(game)
T.eq(ids(game.stack:top().view), "tilt,zoom,voidFill",
  "EXTRAS carries TILT, ZOOM and VOID FILL")
game.stack:pop()

local video = find(menu.view, "group.video")
video.activate(game)
T.eq(ids(game.stack:top().view):match("^uiLayout"), "uiLayout",
  "UI LAYOUT heads the VIDEO page")
game.stack:pop()

local speed = find(menu.view, "group.speed")
speed.activate(game)
T.eq(ids(game.stack:top().view),
  "textSpeed,speedOverworld,speedBattle,speedMenu",
  "TEXT SPEED heads the SPEED page")
game.stack:pop()

local battle, at = find(menu.view, "group.battle")
menu.index = at
battle.activate(game)
local sub = game.stack:top()
T.check(sub ~= menu, "opening a group pushes a screen")
T.eq(ids(sub.view),
  "animations,battleStyle,battleLayout,battleFit,battleHud,battleBg",
  "the page carries exactly its six battle rows, in order")
T.eq(sub.sub, true, "the page knows it is a submenu")
T.eq(sub.onCancel, nil, "BACK out of a page never fires the caller's close hook")

-- focusRow reaches a grouped row by opening its page.
local game2 = stubGame()
local menu2 = OptionsMenu.new(game2)
local landed = menu2:focusRow("battleHud")
T.check(landed and landed ~= menu2, "focusRow opens the page a grouped row lives on")
T.eq(landed.view[landed.index].id, "battleHud", "and lands the cursor on it")
T.eq(menu2:focusRow("ruleset"), menu2, "an ungrouped row focuses in place")
T.eq(menu2.view[menu2.index].id, "ruleset", "on the row asked for")
T.eq(menu2:focusRow("nope"), nil, "an unknown id focuses nothing")

-- ------------------------------------------------------------- marquee

-- 16 characters fit beside a value's x=24 before the box frame at x=152;
-- the label's x=16 fits 17.
local long = "1-A (Default) (BGB)"
T.check(#long > 16, "the COLORS value really is too long for the line")

-- 19 characters, 16 fit: three steps of overflow.  Hold 1.0s, one char per
-- 0.25s, hold 1.0s on the tail, then repeat -- a 2.75s cycle.
T.eq(Marquee.at(long, 16, 0), long:sub(1, 16), "it holds at the start")
T.eq(Marquee.at(long, 16, 1.3), long:sub(2, 17), "then steps one char")
T.eq(Marquee.at(long, 16, 1.6), long:sub(3, 18), "then another")
T.eq(Marquee.at(long, 16, 2.4), long:sub(4, 19), "then holds on the tail")
T.eq(Marquee.at(long, 16, 2.8), long:sub(1, 16), "before wrapping back")
T.eq(Marquee.at(long, 16, 2.4):sub(-4), "BGB)",
  "so the tail the panel used to clip becomes readable")
for _, at2 in ipairs({ 0, 1.3, 1.6, 2.4, 2.8 }) do
  T.eq(#Marquee.at(long, 16, at2), 16,
    "every frame fills the line exactly")
end

T.eq(Marquee.at("SHORT", 16, 2.0), "SHORT",
  "text that fits is never scrolled")

T.finish("options submenu + marquee")
