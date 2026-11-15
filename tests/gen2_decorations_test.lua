-- Decorations: owning them, setting them up, and the two PLAYERS_HOUSE_2F map
-- callbacks that put the room together (engine/overworld/decorations.asm, with
-- data/decorations/attributes.asm and decorations.asm beside it).
--
-- ROM-free: `luajit tests/gen2_decorations_test.lua`.  The cache section at the
-- bottom SKIPs when no Gold cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 decorations")
local check, eq = S.check, S.eq

local Decorations = require("src.core.gen2.Decorations")
local Events = require("src.world.gen2.Events")
local Vm = require("src.script.gen2.Vm")

local TEXT = require("tests.fixture_data.gen2_rom_text_s7_g").text()
Decorations.useRegistry({ text = TEXT })
local function rom(label, ...)
  local args, i = { ... }, 0
  local body = TEXT[label]:gsub("{STRBUF}", function() i = i + 1 return args[i] end)
  return (body:gsub("{PROMPT}", ""):gsub("{DONE}", ""))
end

-- constants/deco_constants.asm, the handful this file names.
local BEDS, DECO_FEATHERY_BED, DECO_PINK_BED = 1, 2, 3
local DECO_RED_CARPET = 7
local DECO_TOWN_MAP, DECO_PIKACHU_POSTER = 16, 17
local DECO_FAMICOM = 21
local DECO_BIG_SNORLAX_DOLL = 26
local DOLLS, DECO_PIKACHU_DOLL, DECO_CLEFAIRY_DOLL = 29, 30, 32
local DECO_GOLD_TROPHY_DOLL, DECO_SILVER_TROPHY_DOLL = 51, 52

-- ---- the attributes table -------------------------------------------------
-- Its length is asserted in the asm as NUM_DECOS + NUM_DECO_CATEGORIES + 1 =
-- 45 + 7 + 1, and row 0 is the CANCEL row every category menu ends on.
do
  local rows = 0
  for _ in pairs(Decorations.ATTRIBUTES) do rows = rows + 1 end
  eq(rows, 53, "DecorationAttributes is 53 rows, row 0 included")
  eq(Decorations.name(0), TEXT["DecorationNames#1"], "row 0 is CANCEL")
  check(Decorations.ATTRIBUTES[0].action == nil,
    "and DecoAction_nothing, so it does nothing at all")
  eq(Decorations.name(BEDS), TEXT["DecorationNames#2"],
    "the category row is the PUT IT AWAY one")
  eq(Decorations.ATTRIBUTES[BEDS].action, "PUT_AWAY_BED",
    "and it puts away that category's slot")
end

-- ---- GetDecoName ----------------------------------------------------------
do
  eq(Decorations.name(DECO_FEATHERY_BED), "FEATHERY BED", "a bed appends BED")
  eq(Decorations.name(DECO_RED_CARPET), "RED CARPET", "a carpet appends CARPET")
  eq(Decorations.name(DECO_PIKACHU_DOLL), "PIKACHU DOLL", "a doll appends DOLL")
  eq(Decorations.name(DECO_BIG_SNORLAX_DOLL), "BIG SNORLAX",
    "a big doll PREPENDS BIG , it does not append DOLL")
  eq(Decorations.name(DECO_PIKACHU_POSTER), "PIKACHU POSTER",
    "a poster appends POSTER")
  -- Both of these are DECO_PLANT rows precisely so that nothing is appended.
  eq(Decorations.name(DECO_TOWN_MAP), "TOWN MAP",
    "the TOWN MAP poster is a DecorationNames string, not a mon plus POSTER")
  eq(Decorations.name(DECO_GOLD_TROPHY_DOLL), "GOLD TROPHY",
    "and so is the trophy")

  local respelled = {}
  for label, body in pairs(TEXT) do respelled[label] = body end
  respelled["DecorationNames#19"] = "COZY"
  respelled["DecorationNames#14"] = " FUTON"
  respelled["DecorationNames#18"] = "HUGE "
  Decorations.useRegistry({ text = respelled })
  eq(Decorations.name(DECO_FEATHERY_BED), "COZY FUTON",
    "GetDecoName reads the colour and the kind out of DecorationNames")
  eq(Decorations.name(DECO_BIG_SNORLAX_DOLL), "HUGE SNORLAX",
    "and the BIG_ prefix too")
  Decorations.useRegistry({ text = {} })
  check(not pcall(Decorations.name, DECO_FEATHERY_BED),
    "a dataset without DecorationNames is an error")
  Decorations.useRegistry({ text = TEXT })
end

-- ---- owning ---------------------------------------------------------------
do
  local events = Events.new()
  check(not Decorations.owns(events, DECO_PINK_BED), "a new game owns no beds")
  Decorations.give(events, DECO_PINK_BED)
  check(Decorations.owns(events, DECO_PINK_BED), "give sets the DECOATTR flag")
  check(not Decorations.owns(events, DECO_FEATHERY_BED),
    "and only that one -- the flags are one bit each")

  -- SetSpecificDecorationFlag names its decoration by DECOFLAG_*, which is a
  -- DecorationIDs index and NOT the DECO_* the attributes table is keyed by.
  eq(Decorations.idForFlag(Decorations.DECOFLAG_GOLD_TROPHY_DOLL),
    DECO_GOLD_TROPHY_DOLL, "DECOFLAG_GOLD_TROPHY_DOLL is DECO_GOLD_TROPHY_DOLL")
  eq(Decorations.idForFlag(Decorations.DECOFLAG_SILVER_TROPHY_DOLL),
    DECO_SILVER_TROPHY_DOLL, "and the silver one likewise")
  eq(Decorations.idForFlag(0), DECO_FEATHERY_BED,
    "DECOFLAG_* is a const_def block, so flag 0 is the first bed")

  local boxed = Events.new()
  Decorations.giveFlag(boxed, Decorations.DECOFLAG_SILVER_TROPHY_DOLL)
  check(Decorations.owns(boxed, DECO_SILVER_TROPHY_DOLL),
    "the NORMAL BOX's trophy arrives through the DECOFLAG path")
end

-- ---- the category and item lists ------------------------------------------
do
  local events = Events.new()
  eq(#Decorations.ownedCategories(events), 0,
    "with nothing owned there is not a single category")
  Decorations.give(events, DECO_PIKACHU_DOLL)
  local cats = Decorations.ownedCategories(events)
  eq(#cats, 1, "one doll shows one category")
  eq(cats[1].id, DOLLS, "and it is the ornament menu")

  local rows = Decorations.rows(events, cats[1])
  eq(#rows, 3, "the list is the doll, PUT IT AWAY and CANCEL")
  eq(rows[1], DECO_PIKACHU_DOLL, "the owned decoration first")
  eq(rows[2], DOLLS, "then the category's own row")
  eq(rows[3], 0, "then row 0, which is CANCEL")

  -- The trophies live in the ornament list, past the twenty-one dolls.
  local trophies = Events.new()
  Decorations.give(trophies, DECO_GOLD_TROPHY_DOLL)
  eq(Decorations.ownedCategories(trophies)[1].id, DOLLS,
    "a trophy is an ornament")
end

-- ---- DoDecorationAction2 --------------------------------------------------
do
  local state = { }
  local changed, pages = Decorations.apply(state, DECO_FEATHERY_BED)
  check(changed, "setting up an empty slot changes the room")
  eq(state.bed, DECO_FEATHERY_BED, "and fills wDecoBed")
  eq(pages[1], rom("_SetUpTheDecoText", "FEATHERY BED"), "SetUpTheDecoText")

  changed, pages = Decorations.apply(state, DECO_FEATHERY_BED)
  check(not changed, ".alreadythere writes nothing")
  eq(pages[1], rom("_AlreadySetUpText"), "AlreadySetUpText")

  changed, pages = Decorations.apply(state, DECO_PINK_BED)
  check(changed, "a second bed replaces the first")
  eq(state.bed, DECO_PINK_BED, "the slot holds ONE thing")
  eq(#pages, 2, "PutAwayAndSetUpText is two pages")
  eq(pages[1] .. "\f" .. pages[2],
    rom("_PutAwayAndSetUpText", "FEATHERY BED", "PINK BED"),
    "the old one is named first, then the new one")

  -- The PUT IT AWAY row, whose action is the category's put-away half.
  changed, pages = Decorations.apply(state, BEDS)
  check(changed, "putting a bed away changes the room too")
  eq(state.bed, 0, "and empties the slot")
  eq(pages[1], rom("_PutAwayTheDecoText", "PINK BED"),
    "the text names what WAS out, not the row that was picked")

  changed, pages = Decorations.apply(state, BEDS)
  check(not changed, "an empty slot has nothing to put away")
  eq(pages[1], rom("_NothingToPutAwayText"), "NothingToPutAwayText")

  Decorations.useRegistry({ text = {} })
  check(not pcall(Decorations.apply, {}, DECO_FEATHERY_BED),
    "a dataset without _SetUpTheDecoText is an error")
  Decorations.useRegistry({ text = TEXT })
end

-- ---- the two ornament sides -----------------------------------------------
do
  local state = {}
  local changed = Decorations.apply(state, DECO_PIKACHU_DOLL, nil)
  check(not changed, "no side chosen is DecoAction_AskWhichSide's cancel")
  eq(state.leftOrnament, nil, "and neither side is touched")

  Decorations.apply(state, DECO_PIKACHU_DOLL, "right")
  eq(state.rightOrnament, DECO_PIKACHU_DOLL, "RIGHT SIDE fills wDecoRightOrnament")
  Decorations.apply(state, DECO_CLEFAIRY_DOLL, "left")
  eq(state.leftOrnament, DECO_CLEFAIRY_DOLL, "LEFT SIDE fills the other")

  -- .getwhichside: there is only one of each doll, so putting the Pikachu on
  -- the left takes it off the right.
  Decorations.apply(state, DECO_PIKACHU_DOLL, "left")
  Decorations.clearOtherSide(state, DECO_PIKACHU_DOLL, "left")
  eq(state.leftOrnament, DECO_PIKACHU_DOLL, "the doll moved to the left")
  eq(state.rightOrnament, 0, "and is gone from the right")
end

-- ---- ToggleDecorationsVisibility ------------------------------------------
do
  local state = {}
  local rows = Decorations.visibility(state)
  eq(#rows, 4, "four objects hang off the room: console, two dolls, big doll")
  for _, row in ipairs(rows) do
    check(row.hidden, "an empty slot SETS the object's flag, which hides it")
  end
  eq(rows[1].flag, 1857, "EVENT_PLAYERS_HOUSE_2F_CONSOLE")
  eq(rows[4].flag, 1860, "EVENT_PLAYERS_HOUSE_2F_BIG_DOLL")
  eq(rows[1].sprite, 0, "and the slots are SPRITE_VARS-relative")
  eq(rows[4].sprite, 3, "SPRITE_BIG_DOLL is the fourth")

  state.console = DECO_FAMICOM
  state.bigDoll = DECO_BIG_SNORLAX_DOLL
  rows = Decorations.visibility(state)
  check(not rows[1].hidden, "a filled slot CLEARS the flag")
  eq(rows[1].byte, 0x5c, "and writes SPRITE_FAMICOM into wVariableSprites")
  eq(rows[4].byte, 0x33, "SPRITE_BIG_SNORLAX for the big doll")
  check(rows[2].hidden, "the two ornaments are still empty")
end

-- ---- ToggleMaptileDecorations ---------------------------------------------
do
  local state = {}
  eq(#Decorations.tiles(state), 0,
    "SetDecorationTile's `and a / ret z`: an empty slot paints nothing")
  check(not Decorations.posterVisible(state),
    "and a bare wall is not readable")

  state.bed = DECO_FEATHERY_BED
  state.poster = DECO_TOWN_MAP
  state.carpet = DECO_RED_CARPET
  local tiles = Decorations.tiles(state)
  local function blockAt(x, y)
    for _, tile in ipairs(tiles) do
      if tile.x == x and tile.y == y then return tile.block end
    end
    return nil
  end
  -- The asm's coordinates are CELLS and PadCoords_de/GetBlockLocation halve
  -- them, the same way `changeblock` does.
  eq(blockAt(0, 2), 0x1b, "bed cell (0,4) is block (0,2)")
  eq(blockAt(3, 0), 0x1f, "poster cell (6,0) is block (3,0)")
  eq(blockAt(0, 0), 0x08, "carpet top-left")
  eq(blockAt(0, 1), 0x09, "carpet bottom row is +1")
  eq(blockAt(1, 1), 0x0a, "+2")
  eq(blockAt(2, 1), 0x09, "and +1 again")
  check(Decorations.posterVisible(state), "a poster on the wall is readable")
end

-- ---- the state on the save ------------------------------------------------
do
  local save = {}
  local state = Decorations.state(save)
  -- InitDecorations, farcall'd from intro_menu.asm at New Game.
  eq(state.bed, DECO_FEATHERY_BED, "a new game starts with the feathery bed")
  eq(state.poster, DECO_TOWN_MAP, "and the TOWN MAP on the wall")
  state.bed = DECO_PINK_BED
  eq(Decorations.state(save).bed, DECO_PINK_BED,
    "and the state lives on the save, not in the module")
end

-- ---- describedecoration, through the VM -----------------------------------
-- Script_describedecoration is a ScriptJump: the arm hands back a script and
-- the command never returns.  Which script depends on what is standing there.
do
  local scripts = {
    ["09:718b"] = { { op = "writetext", text = "t:bare" }, { op = "end" } },
    ["09:7000"] = { { op = "writetext", text = "t:map" }, { op = "end" } },
    ["09:71a8"] = { { op = "writetext", text = "t:doll" }, { op = "end" } },
  }
  local TEXTS = {
    ["t:bare"] = "bare wall", ["t:map"] = "TOWN MAP", ["t:doll"] = "adorable",
  }
  local decorations = {
    DECODESC_POSTER = { script = "09:718b", posters = {
      { decoration = DECO_TOWN_MAP, script = "09:7000" },
    } },
    DECODESC_LEFT_DOLL = { script = "09:71a8" },
  }
  local function run(descName, slotFn)
    local shown = {}
    scripts.generation = 2
    scripts["s:t"] = { { op = "describedecoration", args = { 0 },
      decorationName = descName } }
    local vm = Vm.new(scripts, TEXTS, Events.new(), {
      decorationSlot = slotFn,
      eventTables = { decorations = decorations },
      showText = function(text, done) shown[#shown + 1] = text; done() end,
    })
    vm:start("s:t")
    return shown, vm
  end

  local shown = run("DECODESC_POSTER", function() return 0, nil end)
  eq(shown[1], "bare wall",
    "no poster placed falls to DecorationDesc_NullPoster")

  shown = run("DECODESC_POSTER", function() return DECO_TOWN_MAP, nil end)
  eq(shown[1], "TOWN MAP",
    "IsInArray finds the placed poster and jumps to ITS script")

  local _, vm = run("DECODESC_LEFT_DOLL", function()
    return DECO_PIKACHU_DOLL, "PIKACHU DOLL"
  end)
  eq(vm.stringBuffer, "PIKACHU DOLL",
    "the ornament arm puts the name in wStringBuffer3 for the text to print")
end

-- ---- the cache ------------------------------------------------------------
-- Same default every other gen2 suite uses, so a run with no GOLD_CACHE set
-- (tests/run_tests.lua) still reads the cache instead of skipping silently.
local cache = os.getenv("GOLD_CACHE")
  or ((os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/gold-dev/gold")
local function loadCache(name)
  if not cache then return nil end
  local chunk = loadfile(cache .. "/data/generated/" .. name .. ".lua")
  return chunk and chunk() or nil
end

local events = loadCache("events")
if not events then
  check(true, "no GOLD_CACHE: the extracted arms and flags are not checked (SKIP)")
else
  -- Every DECODESC_* the cache knows has a slot here, or describedecoration
  -- would read a wDeco* byte that does not exist.
  for _, name in ipairs(events.decorationOrder or {}) do
    check(Decorations.DESC_SLOTS[name] ~= nil,
      ("%s names a wDeco* slot"):format(name))
  end
  -- The poster arm's table is the four posters, and each of their DECO_* ids
  -- is a real attributes row of the poster category.
  local poster = (events.decorations or {}).DECODESC_POSTER
  eq(#((poster and poster.posters) or {}), 4, "four posters can hang there")
  for _, row in ipairs((poster and poster.posters) or {}) do
    local attr = Decorations.attributes(row.decoration)
    check(attr ~= nil and attr.action == "SET_UP_POSTER",
      ("poster %d is a poster row here too"):format(row.decoration))
  end
end

local initial = loadCache("initial_events")
if not initial then
  check(true, "no GOLD_CACHE: InitializeEventsScript's flags are not checked (SKIP)")
else
  -- PlayersHouse2FInitializeRoomCallback ends in `jumpstd InitializeEventsScript`,
  -- and that script is where the room's four objects are hidden and the two
  -- decorations the player starts with are marked owned.
  local set = {}
  for _, flag in ipairs(initial.flags or {}) do set[flag] = true end
  for _, row in ipairs(Decorations.OBJECT_SLOTS) do
    check(set[row.flag], ("object flag %d starts SET, i.e. hidden"):format(row.flag))
  end
  check(set[Decorations.attributes(DECO_FEATHERY_BED).flag],
    "and the feathery bed starts owned")
  check(set[Decorations.attributes(DECO_TOWN_MAP).flag],
    "as does the TOWN MAP poster")
end

S.finish()
