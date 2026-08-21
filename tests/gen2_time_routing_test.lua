-- One clock, read everywhere.
--
-- The cart has exactly one time: UpdateTime (home/time.asm) reads the RTC,
-- FixTime adds the save's wStartHour / wStartMinute base, and hHours is what
-- GetTimeOfDay, CheckObjectTime, VAR_HOUR, the Pokegear card and the intro
-- menu's clock box all read back.  src/core/gen2/Clock.lua is that base and
-- World:hour is that read, so nothing may reach around either of them to
-- os.date -- a port with two clocks paints a daylit map while the hour-window
-- NPCs have already gone home.
--
-- This file pins the four seams that read the hour:
--   World:applyPalettes / the daytime the map is lit by
--   World:pollTimeOfDay's hour-window respawn (and its busy() retry)
--   MainMenu / Pokegear clockParts
--   the New Game anchor, so an unanchored save cannot exist in play
--
-- setMap's HandleNewMap vs HandleContinueMap split rides here too: it is the
-- other half of "which map load is this", decided in the same World:load.
--
--   luajit tests/gen2_time_routing_test.lua
--
-- ROM-free: the maps are fixtures written into the love stub's filesystem.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 time routing")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

-- No font is loaded here, so Font.encode would warn per unknown glyph.
require("src.core.Logger").warn = function() end

local Clock = require("src.core.gen2.Clock")
local MainMenu = require("src.ui.gen2.MainMenu")
local Palettes = require("src.world.gen2.Palettes")
local Pokegear = require("src.ui.gen2.Pokegear")
local Save = require("src.core.gen2.Save")
local Vm = require("src.script.gen2.Vm")
local World = require("src.world.gen2.World")

-- An hour whose daytime is NOT the host's, so "the palette followed the game
-- clock" cannot pass by accident on a machine that happens to agree.
local HOST_DAYTIME = Palettes.clockDaytime()
local function hourUnlikeHost()
  for _, hour in ipairs({ 2, 7, 13, 21 }) do
    if Palettes.clockDaytime(hour) ~= HOST_DAYTIME then return hour end
  end
  return 2
end

local function worldWithSave(save)
  local world = World.new({ data = {}, save = save })
  world.map = { id = "TEST_MAP",
    def = { id = "TEST_MAP", palette = "PALETTE_AUTO", environment = "TOWN",
      group = 1 } }
  return world
end

-- ---- the palette follows the GAME clock ------------------------------------
do
  local save = {}
  local hour = hourUnlikeHost()
  Clock.setTime(save, hour, 0)
  local world = worldWithSave(save)

  eq(world:hour(), hour, "World:hour reads the base the player set")
  world:applyPalettes()
  eq(world.daytime, Palettes.clockDaytime(hour),
    "and the map is lit by that hour, not by the host clock")
  check(world.daytime ~= HOST_DAYTIME,
    "which is a different daytime from the host's right now")
  -- wTimeOfDay and wObjectMasks' MORN/DAY/NITE bit are the same read, so
  -- VAR_TIMEOFDAY and CheckObjectTime cannot disagree with the light.
  eq(Palettes.DAYTIME_ID[world.daytime] - 1, world:timeOfDayId(),
    "VAR_TIMEOFDAY answers the same daytime")
  local MASK = { MORN = 1, DAY = 2, NITE = 4, DARK = 4 }
  eq(world:clockTimeMask(), MASK[world.daytime],
    "and the object hour mask agrees with it")

  -- Walk both directions across the TimesOfDay rows through the real base.
  for _, pair in ipairs({ { 2, "NITE" }, { 6, "MORN" }, { 13, "DAY" },
      { 19, "NITE" } }) do
    Clock.setTime(save, pair[1], 0)
    world:applyPalettes()
    eq(world.daytime, pair[2],
      ("%02d:00 on the game clock lights the map %s"):format(pair[1], pair[2]))
  end
end

-- POKEPORT_GOLD_HOUR still wins outright: World.clockHour is the pin, and it
-- has to move the palette AND the hour windows together.
do
  local save = {}
  Clock.setTime(save, 13, 0)
  local world = worldWithSave(save)
  world.clockHour = 21
  world:applyPalettes()
  eq(world:hour(), 21, "the pinned hour is what World:hour answers")
  eq(world.daytime, "NITE", "and the pin lights the map, not the stored base")
  eq(world:clockTimeMask(), 4, "with the NITE object mask to match")
end

-- A save with no base at all is the pre-Clock file: it reads the host clock
-- straight through, and the palette still comes off that same read.
do
  local world = worldWithSave({})
  check(not Clock.isSet({}), "an unanchored save has no base")
  world:applyPalettes()
  eq(world.daytime, HOST_DAYTIME, "so it is lit by the host clock")
end

-- ---- a pinned palette lights the room, it does not stop the clock (#1557) ---
-- timeofday_pals.asm:114 and :5-11, checktime.asm:2, data/maps/maps.asm:427
do
  local save = {}
  Clock.setTime(save, 21, 0)
  local world = worldWithSave(save)
  world.map.def.palette = "PALETTE_DAY"
  world.map.def.environment = "INDOOR"
  world:applyPalettes()
  eq(world.daytime, "DAY", "the pinned room is still lit like day at 21:00")
  eq(world.tod, "NITE", "but the world clock knows it is night")
  eq(world:timeOfDayId(), 2, "and wTimeOfDay answers NITE_F")

  -- Script_checktime: CheckTime's bit for wTimeOfDay ANDed with the mask.
  local function checktime(mask)
    local scripts = { generation = 2,
      ["s:t"] = { { op = "checktime", args = { mask } } } }
    local vm = Vm.new(scripts, {}, world.events,
      { getTimeOfDay = function() return world:timeOfDayId() end })
    vm:start("s:t")
    for _ = 1, 100 do
      if not vm:running() then break end
      vm:update()
    end
    return vm.scriptVar
  end
  eq(checktime(4), 1, "checktime NITE is TRUE inside the PALETTE_DAY room")
  eq(checktime(2), 0, "and checktime DAY is FALSE there")

  -- the two out-of-World consumers read wTimeOfDay too (#1557)
  local Pokegear = require("src.ui.gen2.Pokegear")
  eq(Pokegear.timeOfDayIndex({ game = { world = world } }), 2,
    "the radio's program pick answers NITE, not the pin (pokegear.asm:1456)")
  local Specials = require("src.script.gen2.Specials")
  local buffer
  local pvm = { curPhoneCaller = 1,
    setStringBuffer = function(_, name) buffer = name end,
    specials = { world = {
      tod = world.tod, daytime = world.daytime,
      encounters = { grass = { PLAYERS_HOUSE_1F = { slots = {
        NITE = { { species = "NITEMON" }, { species = "NITEMON" },
                 { species = "NITEMON" }, { species = "NITEMON" } },
        DAY = { { species = "DAYMON" }, { species = "DAYMON" },
                { species = "DAYMON" }, { species = "DAYMON" } },
      } } } },
    } } }
  Specials.ALL.RandomPhoneWildMon(pvm)
  eq(buffer, "NITEMON",
    "RandomPhoneWildMon reads the NITE column (wildmons.asm:861)")
end

-- ---- the hour-window respawn is not eaten by a busy frame -------------------
-- UpdateTimePals runs every second; the port rides that poll to redo what a
-- map load would (wObjectMasks).  A rollover that lands on a busy frame has to
-- wait for a free one, because it is the only edge that hour has.
do
  local world = worldWithSave({})
  world.clockHour = 9
  world.applyPalettes = function() return false end
  local rebuilds = 0
  world.rebuildPeople = function() rebuilds = rebuilds + 1 end

  local function poll(times)
    for _ = 1, (times or 1) * 60 do world:pollTimeOfDay() end
  end

  poll(1)
  eq(world.lastMaskHour, 9, "the first poll arms the latch on 09:00")
  eq(rebuilds, 0, "and rebuilds nothing")

  -- A text box is up when the hour rolls: World:busy is true.
  world.clockHour = 10
  world.textbox = {}
  poll(5)
  eq(rebuilds, 0, "a rollover under a text box rebuilds nothing yet")
  eq(world.lastMaskHour, 9,
    "and the latch stays on 09:00 so the edge is not consumed")

  world.textbox = nil
  poll(1)
  eq(rebuilds, 1, "the first free poll does the rebuild")
  eq(world.lastMaskHour, 10, "and only then advances the latch")
  poll(3)
  eq(rebuilds, 1, "later polls in the same hour do nothing")
end

-- ---- HandleNewMap vs HandleContinueMap --------------------------------------
-- data/maps/setup_scripts.asm: every setup script runs HandleNewMap except
-- MapSetupScript_Continue, which enters at HandleContinueMap -- one label below
-- ResetMapBufferEventFlags (home/map.asm:216-228).  Flags 0-7 live in SRAM, so
-- continuing a file keeps whatever the save was holding.
local function bufferWorld()
  local world = World.new({ data = {}, save = { party = {}, inventory = {} } })
  world.maps = {
    TEST_MAP = { id = "TEST_MAP", group = 1, map = 2, width = 2, height = 2,
      blocks = { 1, 2, 3, 4 }, objects = {}, warps = {}, tileset = "TEST" },
  }
  world.tilesets = { TEST = {} }
  world.scripts = {}
  world.vm = Vm.new(world.scripts, {}, world.events, {})
  world.imageFor = function() return true end
  world.rebuildNeighbors = function() end
  world.rebuildPeople = function() end
  world.applyPalettes = function() end
  for id = 0, 8 do world.events:set(id, true) end
  return world
end

do
  local world = bufferWorld()
  check(world:setMap("TEST_MAP", 0, 0, "down", { continue = true }),
    "the continue load reaches the map")
  for id = 0, 7 do
    check(world.events:get(id),
      ("continuing keeps temporary flag %d"):format(id))
  end
end

do
  local world = bufferWorld()
  check(world:setMap("TEST_MAP", 0, 0, "down"), "an ordinary load reaches it")
  for id = 0, 7 do
    check(not world.events:get(id),
      ("a new map load still clears temporary flag %d"):format(id))
  end
  check(world.events:get(8), "and leaves flag 8, the next byte, alone")
end

-- Which of the two World:load picks, driven through the real World:load with
-- the cache faked into the love stub's filesystem.
do
  love.filesystem.write("data/generated/maps.lua", [[
return {
  PLAYERS_HOUSE_2F = { id = "PLAYERS_HOUSE_2F", group = 1, map = 1, width = 2,
    height = 2, blocks = { 1, 2, 3, 4 }, objects = {}, warps = {},
    tileset = "TEST" },
  TEST_MAP = { id = "TEST_MAP", group = 1, map = 2, width = 2, height = 2,
    blocks = { 1, 2, 3, 4 }, objects = {}, warps = {}, tileset = "TEST" },
}
]])
  love.filesystem.write("data/generated/tilesets.lua", "return { TEST = {} }")
  love.filesystem.write("data/generated/landmarks.lua", [[
return { spawns = { SPAWN_NEW_BARK = { map = "TEST_MAP", x = 1, y = 1 } } }
]])

  local function entryMethod(save)
    local world = World.new({ data = {}, save = save })
    local seen
    world.setMap = function(_self, mapId, _x, _y, _facing, opts)
      seen = opts or {}
      world.map = { id = mapId }
      return true
    end
    check(world:load(), "World:load reaches setMap (" ..
      tostring(world.status) .. ")")
    return seen and seen.continue and true or false
  end

  check(entryMethod({ party = {}, inventory = {},
    position = { map = "TEST_MAP", x = 1, y = 1, facing = "down" } }),
    "a file with a recorded position loads as MAPSETUP_CONTINUE")
  check(not entryMethod({ party = {}, inventory = {} }),
    "a New Game is the SPAWN_HOME warp, so it takes HandleNewMap")
  -- SpawnAfterE4 / PostCreditsSpawn set MAPSETUP_WARP, not CONTINUE.
  check(not entryMethod({ party = {}, inventory = {},
    spawnAfterChampion = "SPAWN_LANCE",
    position = { map = "PLAYERS_HOUSE_2F", x = 1, y = 1, facing = "down" } }),
    "and the post-credits spawn is a warp even though a position exists")

  love.filesystem.remove("data/generated/maps.lua")
  love.filesystem.remove("data/generated/tilesets.lua")
  love.filesystem.remove("data/generated/landmarks.lua")
end

-- ---- the two clock faces ----------------------------------------------------
-- MainMenu_PrintCurrentTimeAndDay's .PlaceTime and the Pokegear's clock card
-- both read hHours after UpdateTime, so both are the game clock.
do
  local save = Save.newGame()
  Clock.setTime(save, 3, 15)
  Clock.setWeekday(save, 3)

  local menu = MainMenu.new({ data = {} }, { save = save, hasSave = true })
  local hour, minute, weekday = menu:clockParts()
  eq(hour, 3, "the intro menu's clock box reads the save's base")
  eq(minute, 15, "minutes and all")
  eq(MainMenu.DAYS[weekday], "WEDNESDAY", "and the weekday it was set to")

  local gear = Pokegear.new({ data = {}, save = save }, { save = save })
  local gearHour, gearMinute, gearDay = gear:clockParts()
  eq(gearHour, 3, "the Pokegear clock card reads the same base")
  eq(gearMinute, 15, "minutes and all")
  eq(gearDay, weekday, "and the same weekday as the intro menu")
  -- GetWeekday is SUNDAY 0, which is what the radio's TextCommand_DAY wants.
  eq(gear:radioWeekday(), 3, "and the radio hears WEDNESDAY, not the host's day")
end

-- Opened over a live world, the gear shows exactly what the overworld is on --
-- including a driver's POKEPORT_GOLD_HOUR pin.
do
  local save = Save.newGame()
  Clock.setTime(save, 3, 15)
  local world = worldWithSave(save)
  world.clockHour = 21
  world.clockDay = 5
  local gear = Pokegear.new({ data = {}, save = save, world = world },
    { save = save })
  local hour, _, weekday = gear:clockParts()
  eq(hour, 21, "the gear reads the world's pinned hour")
  eq(weekday, 6, "and its pinned day, 1-based for the DAYS table")
  eq(gear:radioWeekday(), 5, "with the radio back on GetWeekday's numbering")
end

-- An explicit opts.clock still pins both faces outright (driver screenshots).
do
  local pinned = MainMenu.new({ data = {} },
    { hasSave = false, save = false, clock = { hour = 0, minute = 0,
      weekday = 1 } })
  local hour, minute, weekday = pinned:clockParts()
  eq(hour, 0, "a pinned clock box keeps its hour")
  eq(minute, 0, "its minutes")
  eq(MainMenu.DAYS[weekday], "SUNDAY", "and its day")
end

-- ---- New Game anchors the clock in every run mode --------------------------
-- engine/menus/intro_menu.asm NewGame -> OakSpeech -> `farcall InitClock`, so
-- there is no such thing as a new game whose base is unset.  A driver that
-- skips the cinema never reaches that screen, and an unanchored save reads the
-- host clock: the same run is MORN in the morning and NITE at night, which
-- changes which mon a patch of grass rolls.
do
  local fresh = Save.newGame()
  check(not Clock.isSet(fresh), "Save.newGame itself writes no base")

  local Game2 = require("src.core.Game2")
  local anchored = Save.newGame()
  check(Game2.anchorNewGameClock(anchored),
    "the New Game path anchors it")
  check(Clock.isSet(anchored), "so Clock.isSet is true before the world loads")
  eq(Clock.hour(anchored), Clock.DEFAULT_HOUR,
    "on InitClock's own 10 AM default")
  eq(Clock.minute(anchored), Clock.DEFAULT_MINUTE, "and no minutes")

  -- Idempotent: the InitClock screen's own answer must not be overwritten by a
  -- later pass through the same path.
  Clock.setTime(anchored, 6, 30)
  check(not Game2.anchorNewGameClock(anchored),
    "an already-answered clock is left alone")
  eq(Clock.hour(anchored), 6, "with the player's hour intact")
  eq(Clock.minute(anchored), 30, "and their minutes")

  -- The whole point: a world built on an anchored save is lit by that hour and
  -- stays there run to run.
  local world = worldWithSave(anchored)
  world:applyPalettes()
  eq(world.daytime, Palettes.clockDaytime(6), "and the map follows it")
end

S.finish()
