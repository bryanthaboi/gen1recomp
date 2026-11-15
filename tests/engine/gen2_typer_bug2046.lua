-- ../pokecrystal/home/print_text.asm:1 PrintLetterDelay
-- ../pokecrystal/engine/menus/save.asm:346 SavingDontTurnOffThePower

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq, check = T.eq, T.check
love = love or require("tests.love_stub")

require("src.core.Logger").warn = function() end

local Typer = require("src.ui.gen2.Typer")
local CenterPcMenu = require("src.ui.gen2.CenterPcMenu")
local SaveMenu = require("src.ui.gen2.SaveMenu")
local Save = require("src.core.gen2.Save")

local function newInput()
  local input = { pressed = {}, held = {} }
  function input:press(button) self.pressed[button] = true end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown(button) return self.held[button] == true end
  return input
end

local function newGame(speed)
  local input = newInput()
  local save = Save.newGame({ playerName = "GOLD", trainerId = 1 })
  save.options = save.options or {}
  save.options.textSpeed = speed
  return { input = input, save = save, data = { audio = {}, items = {},
    text = require("tests.fixture_data.gen2_rom_text_s7_c").text(
      require("tests.fixture_data.gen2_rom_text_s7_f1").text()) } },
    input, save
end


do
  local game = newGame("SLOW")
  local typer = Typer.new(game)
  typer:start({ "ABCDE" })
  eq(typer.total, 5, "five glyphs on the page")
  eq(typer.shown, 0, "nothing is up on the frame it starts")
  for _ = 1, 4 do typer:tick() end
  eq(typer.shown, 0, "SLOW holds the first glyph back for four frames")
  typer:tick()
  eq(typer.shown, 1, "and lands it on the fifth")
  eq(typer:lines()[1], "A", "the box holds exactly that prefix")
end

do
  local game = newGame("FAST")
  local typer = Typer.new(game)
  typer:start({ "ABCDE" })
  typer:tick()
  eq(typer.shown, 1, "FAST is one glyph a frame")
  typer:tick()
  eq(typer.shown, 2, "and keeps up that rate")
end

do
  local game = newGame("MID")
  local typer = Typer.new(game)
  typer:start({ "ABCDE" })
  for _ = 1, 3 do typer:tick() end
  eq(typer.shown, 1, "MID is one glyph every three frames")
end

do
  local game, input = newGame("SLOW")
  input.held.a = true
  local typer = Typer.new(game)
  typer:start({ "ABCDE" })
  typer:tick()
  eq(typer.shown, 1, "a held A prints one glyph a frame whatever the OPTION")
end

-- ../pokecrystal/engine/events/pokecenter_pc.asm:314 NO_TEXT_SCROLL
do
  local game = newGame("SLOW")
  local typer = Typer.new(game, { instant = true })
  typer:start({ "ABCDE" })
  eq(typer.shown, 5, "a NO_TEXT_SCROLL page is whole on the frame it opens")
  check(typer:done(), "and needs no ticks")
end

do
  local game = newGame("FAST")
  local typer = Typer.new(game, { speed = "MID" })
  typer:start({ "ABCDE" })
  typer:tick()
  typer:tick()
  eq(typer.shown, 0, "TEXT_DELAY_MED overrides a FAST option")
  typer:tick()
  eq(typer.shown, 1, "and lands the first glyph on frame three")
end


do
  local game = newGame("FAST")
  local typer = Typer.new(game)
  typer:start({ "#MON" })
  eq(typer.total, 7, "# expands to POKé, so #MON counts seven glyphs")
  typer:tick()
  local first = typer:lines()[1]
  check(first ~= "" and #first >= 1, "and the first cut is a whole glyph")
end

do
  local game = newGame("FAST")
  local typer = Typer.new(game, { expand = function(line)
    return (line:gsub("{PLAYER}", "GOLD"))
  end })
  typer:start({ "{PLAYER} turned on" })
  eq(typer.total, #"GOLD turned on",
    "the count is taken after the name is folded in")
  for _ = 1, typer.total do typer:tick() end
  eq(typer:lines()[1], "GOLD turned on", "and so is the finished line")
end


do
  local game = newGame("FAST")
  local typer = Typer.new(game)
  typer:start({ "AB", "CD" })
  eq(typer.total, 4, "both rows count")
  typer:tick()
  typer:tick()
  eq(typer:lines()[1], "AB", "row one fills first")
  eq(typer:lines()[2], "", "row two is still empty")
  typer:tick()
  eq(typer:lines()[2], "C", "then row two starts")
end


do
  local game, input, save = newGame("MID")
  save.party[1] = { species = "CYNDAQUIL", nickname = "CYNDA", hp = 5,
    maxHp = 5, level = 5 }
  local pc = CenterPcMenu.new(game, { save = save, onClose = function() end })
  local function frame()
    pc:update(0)
    input.pressed = {}
  end
  check(pc.typer ~= nil, "the turn-on line goes through the typewriter")
  check(not pc.typer:done(), "and is not up on the frame the PC boots")
  eq(pc.booted, false, "so .TopMenu is not loaded yet")

  input:press("a")
  frame()
  check(pc.message ~= nil,
    "A while it is printing does not turn the page")
  check(not pc.typer:done(),
    "and does not dump the rest of the page either")
  check(pc.typer.shown <= 1,
    "a press buys at most the held-button glyph, not the whole line")

  local before = pc.typer.shown
  input.held.a = true
  local held = 0
  for _ = 1, 400 do
    if pc.typer:done() then break end
    frame()
    held = held + 1
  end
  input.held.a = false
  check(pc.typer:done(), "holding A prints the rest of the line")
  eq(held, pc.typer.total - before, "at one glyph a frame, no faster")

  input:press("a")
  frame()
  eq(pc.message, nil, "the press after the line is up clears it")
  eq(pc.booted, true, "and LoadMenuHeader puts .TopMenu up")
end


do
  local game, input, save = newGame("FAST")
  local menu = SaveMenu.new(game, { save = save, existed = false,
    writer = function() return true end })
  menu:update(0)
  eq(menu.typedPhase, "confirm", "the confirm prompt starts typing on frame 1")
  for _ = 1, 400 do
    if menu.typer:done() then break end
    menu:update(0)
  end
  check(menu.typer:done(), "and finishes")

  input:press("a")
  menu:update(0)
  eq(menu.phase, "saving", "YES starts the write sequence")
  eq(menu.typer.speed, "MID",
    "the SAVING page is pinned to TEXT_DELAY_MED, not the FAST option")
  eq(menu.timer, 0, "and DelayFrames has not started counting yet")

  menu:update(0)
  menu:update(0)
  eq(menu.timer, 0, "the 16-frame wait comes AFTER the line is printed")
  for _ = 1, 600 do
    if menu.phase ~= "saving" then break end
    menu:update(0)
  end
  eq(menu.phase, "done", "then the write lands and the saved line comes up")
  eq(menu.typer.speed, "MID", "which is pinned to MED as well")
end

T.finish("gen2_typer_bug2046")
