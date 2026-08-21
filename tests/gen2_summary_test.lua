-- The mon SUMMARY screen (engine/pokemon/stats_screen.asm) and the mon action
-- submenu it hangs off (engine/pokemon/mon_submenu.asm).
--
-- Every page of the summary is a tilemap, so what this suite asserts is the
-- tilemap: SummaryMenu builds each page as a list of { text, x, y } writes
-- before anything is drawn, and the coordinates below are the hlcoords the
-- ASM uses, checked one by one.  Nothing here draws -- what a test cannot say
-- (whether the pages LOOK like Gold's) is what
-- tests/drivers/gold_summary_shots.lua exists for.

package.path = "./?.lua;" .. package.path

-- The UI modules require love-side helpers at load time.  Stub the pieces they
-- touch during construction and logic; nothing here draws.
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
love.math = love.math or {
  random = function(a, b)
    if b then return a end
    return a and 1 or 0.5
  end,
}
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

-- No font is loaded here, so Font.encode would warn once per unknown glyph.
require("src.core.Logger").warn = function() end

local Mon = require("src.battle.gen2.Mon")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

-- ------------------------------------------------------------- fixture data

-- A cut-down data cache: one species with a known growth rate and base stats,
-- the four moves it carries, and one held item.  Everything the summary reads
-- comes off these three tables.
local DATA = {
  pokemon = {
    growthRates = {
      -- GROWTH_MEDIUM_SLOW: 6/5 n^3 - 15 n^2 + 100 n - 140.
      GROWTH_MEDIUM_SLOW = {
        numerator = 6, denominator = 5, squared = -15, linear = 100,
        constant = 140,
      },
    },
    CYNDAQUIL = {
      id = "CYNDAQUIL", name = "CYNDAQUIL", dex = 155, index = 155,
      growthRate = "GROWTH_MEDIUM_SLOW",
      -- data/pokemon/base_stats/cyndaquil.asm:10 GENDER_F12_5
      genderRatio = 31,
      types = { "FIRE", "FIRE" },
      baseStats = {
        hp = 39, attack = 52, defense = 43, speed = 65,
        specialAttack = 60, specialDefense = 50,
      },
    },
    TOTODILE = {
      id = "TOTODILE", name = "TOTODILE", dex = 158, index = 158,
      growthRate = "GROWTH_MEDIUM_SLOW",
      -- data/pokemon/base_stats/totodile.asm:10 GENDER_F12_5
      genderRatio = 31,
      types = { "WATER", "WATER" },
      baseStats = {
        hp = 50, attack = 65, defense = 64, speed = 43,
        specialAttack = 44, specialDefense = 48,
      },
    },
    GASTLY = {
      id = "GASTLY", name = "GASTLY", dex = 92, index = 92,
      growthRate = "GROWTH_MEDIUM_SLOW",
      types = { "GHOST", "POISON" },
      baseStats = {
        hp = 30, attack = 35, defense = 30, speed = 80,
        specialAttack = 100, specialDefense = 35,
      },
    },
  },
  moves = {
    TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35, power = 35,
      type = "NORMAL",
      description = "A physical attack<NEXT>using full body<NEXT>weight." },
    EMBER = { id = "EMBER", name = "EMBER", pp = 25, power = 40, type = "FIRE",
      description = "An attack that may<NEXT>inflict a burn." },
    -- A status move: PlaceMoveData prints String_MoveNoPower for power < 2.
    LEER = { id = "LEER", name = "LEER", pp = 30, power = 0, type = "NORMAL",
      description = "Lowers the foe's<NEXT>DEFENSE." },
    CUT = { id = "CUT", name = "CUT", pp = 30, power = 50, type = "NORMAL",
      description = "An attack with a<NEXT>sharp object." },
    SURF = { id = "SURF", name = "SURF", pp = 15, power = 95, type = "WATER",
      description = "A strong water-<NEXT>type attack." },
  },
  items = {
    BERRY = { id = "BERRY", name = "BERRY", pocket = "ITEM" },
    -- Mail lives in the ordinary ITEM pocket on the cart; what makes it mail
    -- is data/items/mail_items.asm's own list (src/core/gen2/Mail.lua), which
    -- is why this fixture names a real one instead of inventing a pocket.
    FLOWER_MAIL = { id = "FLOWER_MAIL", name = "FLOWER MAIL", pocket = "ITEM" },
  },
  gen2MenuGfx = {},
}

local function newGame(save)
  return {
    input = newInput(),
    save = save,
    data = DATA,
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }
end

-- Every party member goes through the ONE Gen 2 builder; a mon that came out
-- of Gen 1's Pokemon.new would have no moves at all, because a Gen 2 moveset
-- is `levelMoves` and Gen 1 reads level1Moves / learnset.
local function mon(species, level, opts)
  opts = opts or {}
  -- engine/pokemon/mon_stats.asm:126 GetGender reads the Attack DV, so the
  -- gender a page prints follows the DVs, not a hand-set field
  local built = Mon.new(DATA, species, level, {
    dvs = opts.dvs
      or { attack = 15, defense = 15, speed = 15, special = 15 },
    moves = opts.moves,
  })
  for key, value in pairs(opts.fields or {}) do built[key] = value end
  return built
end

local CYNDA = mon("CYNDAQUIL", 12, {
  moves = {
    { id = "TACKLE", pp = 30, maxPp = 35 },
    { id = "EMBER", pp = 25, maxPp = 25 },
    { id = "LEER", pp = 7, maxPp = 30 },
  },
  fields = { nickname = "CYNDAQUIL", item = "BERRY",
    otName = "GOLD", otId = 12345 },
})
local TOTO = mon("TOTODILE", 10, {
  moves = { { id = "SURF", pp = 15, maxPp = 15 } },
  dvs = { attack = 0, defense = 15, speed = 15, special = 15 },
  fields = { nickname = "TOTODILE" },
})

local SAVE = { player = { name = "GOLD", id = 12345 }, party = { CYNDA, TOTO } }

local function newSummary(index)
  local game = newGame(SAVE)
  local screen = SummaryMenu.new(game, {
    party = SAVE.party, index = index or 1, save = SAVE,
  })
  return screen, game.input
end

local at = SummaryMenu.at

-- --------------------------------------------------------------- page cycle

-- StatsScreenInit enters on PINK_PAGE, and .d_right / .d_left wrap in both
-- directions (BLUE -> PINK and PINK -> BLUE).
local screen, input = newSummary()
check("opens on the pink page", screen.page, SummaryMenu.PINK_PAGE)
input:press("right")
screen:update(0)
check("right reaches the green page", screen.page, SummaryMenu.GREEN_PAGE)
input:press("right")
screen:update(0)
check("right reaches the blue page", screen.page, SummaryMenu.BLUE_PAGE)
input:press("right")
screen:update(0)
check("right wraps back to pink", screen.page, SummaryMenu.PINK_PAGE)
input:press("left")
screen:update(0)
check("left wraps to blue", screen.page, SummaryMenu.BLUE_PAGE)
input:press("left")
screen:update(0)
check("left steps back to green", screen.page, SummaryMenu.GREEN_PAGE)

-- .a_button falls THROUGH into .d_right on any page but the last, where it
-- quits instead.  Both halves of that fallthrough matter.
local closed = false
screen, input = newSummary()
screen.onClose = function() closed = true end
input:press("a")
screen:update(0)
check("a turns the page from pink", screen.page, SummaryMenu.GREEN_PAGE)
check("and does not close", closed, false)
input:press("a")
screen:update(0)
check("a turns the page from green", screen.page, SummaryMenu.BLUE_PAGE)
input:press("a")
screen:update(0)
check("a on the last page closes", closed, true)
check("and leaves the page alone", screen.page, SummaryMenu.BLUE_PAGE)

closed = false
screen, input = newSummary()
screen.onClose = function() closed = true end
input:press("b")
screen:update(0)
check("b closes from any page", closed, true)

-- The `down` and `.d_up` arms walk the party without wrapping, and the page
-- survives the switch (StatsScreenMain pushes bc and pops it back).
screen, input = newSummary()
screen.page = SummaryMenu.BLUE_PAGE
input:press("up")
screen:update(0)
check("up at the top of the party does nothing", screen.index, 1)
input:press("down")
screen:update(0)
check("down walks to the next mon", screen.index, 2)
check("and keeps the page", screen.page, SummaryMenu.BLUE_PAGE)
check("and swaps the mon", screen.mon.species, "TOTODILE")
input:press("down")
screen:update(0)
check("down at the end of the party does nothing", screen.index, 2)

-- ---------------------------------------------------------- the upper half

-- StatsScreen_InitUpperHalf.  Drawn once for every page, which is why it is
-- built apart from them.
screen = newSummary()
local upper = screen:upperPlacements()
check("№. at hlcoord 8,0", at(upper, 8, 0), "№.")
check("dex number at hlcoord 10,0", at(upper, 10, 0), "155")
check("level at hlcoord 14,0", at(upper, 14, 0), "<LV>12")
check("nickname at hlcoord 8,2", at(upper, 8, 2), "CYNDAQUIL")
check("gender at hlcoord 18,0", at(upper, 18, 0), "♂")
check("the species slash at hlcoord 9,4", at(upper, 9, 4), "/")
check("species name at hlcoord 10,4", at(upper, 10, 4), "CYNDAQUIL")

-- PrintLevel writes <LV> then two left-aligned digits, but a three-digit level
-- does `dec hl` first so the digits land on the <LV> and the field still
-- starts at the same column.
check("a two-digit level keeps its <LV>", SummaryMenu.levelText(12), "<LV>12")
check("a one-digit level keeps its <LV>", SummaryMenu.levelText(5), "<LV>5")
check("level 100 overwrites the <LV>", SummaryMenu.levelText(100), "100")

-- A female mon writes the other glyph; a genderless one writes nothing.
local female = newSummary(2)
check("a female mon gets ♀", at(female:upperPlacements(), 18, 0), "♀")
local genderless = newSummary()
genderless.mon = mon("GASTLY", 20, { fields = { gender = "unknown" } })
check("a genderless mon gets no glyph",
  at(genderless:upperPlacements(), 18, 0), nil)

-- ------------------------------------------------------------- pink page

screen = newSummary()
local pink = screen:pinkPlacements()
-- DrawPlayerHP's `bccoord 1, 1, 0` from the bar's own (0,9).
check("current HP at hlcoord 1,10", at(pink, 1, 10),
  ("%3d"):format(CYNDA.hp))
check("the HP slash at hlcoord 4,10", at(pink, 4, 10), "/")
check("max HP at hlcoord 5,10", at(pink, 5, 10),
  ("%3d"):format(CYNDA.maxHp))
-- .Status_Type joins its two lines with <NEXT>, which is TWO rows down.
check("STATUS/ at hlcoord 0,12", at(pink, 0, 12), "STATUS/")
check("TYPE/ two rows below it, not one", at(pink, 0, 14), "TYPE/")
check("nothing sits between them", at(pink, 0, 13), nil)
check("a healthy mon reads OK at hlcoord 6,13", at(pink, 6, 13), "OK")
-- PrintMonTypes writes type 2 two rows down, and LoadPinkPage then copies row
-- 17 up onto row 16 -- so the second type ends one row under the first.
check("type 1 at hlcoord 1,15", at(pink, 1, 15), "FIRE")
check("a single-typed mon has no second type", at(pink, 1, 16), nil)
check("EXP POINTS at hlcoord 10,9", at(pink, 10, 9), "EXP POINTS")
check("LEVEL UP at hlcoord 10,12", at(pink, 10, 12), "LEVEL UP")
check("TO at hlcoord 14,14", at(pink, 14, 14), "TO")
-- The level beside TO is the NEXT one.
check("the next level at hlcoord 17,14", at(pink, 17, 14), "<LV>13")

-- The exp numbers are seven-column fields at 13,10 and 13,13.
local growth = DATA.pokemon.growthRates.GROWTH_MEDIUM_SLOW
local expNow = Mon.experienceForLevel(growth, 12)
local expNext = Mon.experienceForLevel(growth, 13)
check("exp points at hlcoord 13,10", at(pink, 13, 10),
  ("%7d"):format(expNow))
check("exp to the next level at hlcoord 13,13", at(pink, 13, 13),
  ("%7d"):format(expNext - expNow))
check("and the field is seven columns wide", #at(pink, 13, 10), 7)

-- A dual-typed mon prints both names, on consecutive rows.
local dual = newSummary()
dual.mon = mon("GASTLY", 20, { fields = { gender = "male" } })
local dualPink = dual:pinkPlacements()
check("type 1 of a dual-type", at(dualPink, 1, 15), "GHOST")
check("type 2 one row below it", at(dualPink, 1, 16), "POISON")

-- Status and fainting go through PlaceStatusString, which reads FNT off the
-- HP rather than off the status byte.
local sick = newSummary()
sick.mon = mon("TOTODILE", 10, { fields = { status = "psn" } })
check("a poisoned mon reads PSN", at(sick:pinkPlacements(), 6, 13), "PSN")
local fainted = newSummary()
fainted.mon = mon("TOTODILE", 10, { fields = { hp = 0, status = nil } })
check("a fainted mon reads FNT", at(fainted:pinkPlacements(), 6, 13), "FNT")

-- wTempMonPokerusStatus: low nibble infected, high nibble immune-forever.
local pkrs = newSummary()
pkrs.mon = mon("TOTODILE", 10, { fields = { pokerus = 0x34 } })
local pkrsPink = pkrs:pinkPlacements()
check("an infected mon shows POKéRUS at hlcoord 1,13",
  at(pkrsPink, 1, 13), "POKéRUS")
check("and no status string", at(pkrsPink, 6, 13), nil)
local cured = newSummary()
cured.mon = mon("TOTODILE", 10, { fields = { pokerus = 0x30 } })
local curedPink = cured:pinkPlacements()
check("a cured mon shows the dot at hlcoord 8,8", at(curedPink, 8, 8), ".")
check("and is otherwise OK", at(curedPink, 6, 13), "OK")

-- ------------------------------------------------------------ green page

screen = newSummary()
local green = screen:greenPlacements()
check("ITEM at hlcoord 0,8", at(green, 0, 8), "ITEM")
check("the held item at hlcoord 6,8", at(green, 6, 8), "BERRY")
check("MOVE at hlcoord 0,10", at(green, 0, 10), "MOVE")
-- ListMoves runs at (8,10) with wListMovesLineSpacing = SCREEN_WIDTH * 2.
check("move 1 at hlcoord 8,10", at(green, 8, 10), "TACKLE")
check("move 2 two rows down", at(green, 8, 12), "EMBER")
check("move 3 two rows down again", at(green, 8, 14), "LEER")
check("an empty slot is a dash", at(green, 8, 16), "-")
-- ListMovePP runs at (12,11): the PP label, then `inc hl` three times.
check("the PP label at hlcoord 12,11", at(green, 12, 11), "PP")
check("current PP at hlcoord 15,11", at(green, 15, 11), "30")
check("the PP slash at hlcoord 17,11", at(green, 17, 11), "/")
check("max PP at hlcoord 18,11", at(green, 18, 11), "35")
check("PP of the third move", at(green, 15, 15), " 7")
check("an empty slot's PP label is two dashes", at(green, 12, 17), "--")
check("and it prints no numbers", at(green, 15, 17), nil)

local noItem = newSummary(2)
check("no held item prints .ThreeDashes",
  at(noItem:greenPlacements(), 6, 8), "---")

-- ------------------------------------------------------------- blue page

screen = newSummary()
local blue = screen:bluePlacements()
-- IDNoString is "<ID>№." -- three single tiles, not the six letters it looks
-- like -- and both it and OTString are placed at column 0.
check("<ID>№. at hlcoord 0,9", at(blue, 0, 9), "<ID>№.")
check("the ID number at hlcoord 2,10", at(blue, 2, 10), "12345")
check("OT/ at hlcoord 0,12", at(blue, 0, 12), "OT/")
-- .PlaceOTInfo pads an ordinary name by two columns.
check("the OT name at hlcoord 2,13", at(blue, 2, 13), "GOLD")
check("a 4-char name pads by 2", SummaryMenu.otColumn("GOLD"), 2)
check("an 8-char name still pads by 2", SummaryMenu.otColumn("ABCDEFGH"), 2)
check("a 9-char name pads by 1", SummaryMenu.otColumn("ABCDEFGHI"), 1)
check("a 10-char name pads by 0", SummaryMenu.otColumn("ABCDEFGHIJ"), 0)

-- PrintTempMonStats: labels down column 11 two rows apart, values in the
-- three columns ending at 19, starting one row below the first label.
local labels = { "ATTACK", "DEFENSE", "SPCL.ATK", "SPCL.DEF", "SPEED" }
for i, label in ipairs(labels) do
  check(("stat label %s at hlcoord 11,%d"):format(label, 8 + (i - 1) * 2),
    at(blue, 11, 8 + (i - 1) * 2), label)
end
-- ...and the numbers really are this mon's, off the one Gen 2 builder.
local stats = CYNDA.stats
check("ATTACK at hlcoord 17,9", at(blue, 17, 9),
  ("%3d"):format(stats.attack))
check("DEFENSE at hlcoord 17,11", at(blue, 17, 11),
  ("%3d"):format(stats.defense))
check("SPCL.ATK at hlcoord 17,13", at(blue, 17, 13),
  ("%3d"):format(stats.specialAttack))
check("SPCL.DEF at hlcoord 17,15", at(blue, 17, 15),
  ("%3d"):format(stats.specialDefense))
check("SPEED at hlcoord 17,17", at(blue, 17, 17),
  ("%3d"):format(stats.speed))
-- The fixture's stats are the cart's formula, not whatever the screen felt
-- like: a level 12 Cyndaquil with 15s across the board.
check("the fixture's ATTACK is the Gen 2 formula", stats.attack,
  math.floor(((52 * 2 + 15 * 2) * 12) / 100) + 5)
check("HP uses the HP-DV-from-the-others rule", CYNDA.maxHp,
  math.floor(((39 * 2 + 15 * 2) * 12) / 100) + 12 + 10)

-- `placements` glues the upper half onto whichever page is up.
screen = newSummary()
screen.page = SummaryMenu.BLUE_PAGE
local whole = screen:placements()
check("a page carries the upper half too", at(whole, 8, 2), "CYNDAQUIL")
check("and its own rows", at(whole, 0, 12), "OT/")

-- ------------------------------------------------------- move description

-- SELECT opens PlaceMoveData's screen off the move page, and only off it.
screen, input = newSummary()
input:press("select")
screen:update(0)
check("select does nothing on the pink page", screen.moveDetail, false)
screen.page = SummaryMenu.GREEN_PAGE
input:press("select")
screen:update(0)
check("select opens the move detail on the green page",
  screen.moveDetail, true)

local detail = screen:moveDetailPlacements()
check("the nickname at hlcoord 5,1", at(detail, 5, 1), "CYNDAQUIL")
-- PlaceString leaves bc one past the string, and that is popped into hl for
-- PrintLevel -- so the level butts against the name rather than sitting in a
-- fixed column.
check("the level right after it", at(detail, 5 + 9, 1), "<LV>12")
check("move 1 at hlcoord 2,3", at(detail, 2, 3), "TACKLE")
check("move 2 at hlcoord 2,5", at(detail, 2, 5), "EMBER")
check("the PP label at hlcoord 10,4", at(detail, 10, 4), "PP")
check("current PP at hlcoord 13,4", at(detail, 13, 4), "30")
check("the PP slash at hlcoord 15,4", at(detail, 15, 4), "/")
check("max PP at hlcoord 16,4", at(detail, 16, 4), "35")
check("the type plaque's top at hlcoord 0,10", at(detail, 0, 10), "┌─────┐")
check("its bottom at hlcoord 0,11", at(detail, 0, 11), "│TYPE/└")
check("the move's type at hlcoord 2,12", at(detail, 2, 12), "NORMAL")
check("ATTK/ at hlcoord 11,12", at(detail, 11, 12), "ATTK/")
check("the move's power at hlcoord 16,12", at(detail, 16, 12), " 35")
-- PrintMoveDescription writes at (1,14) and its lines join with <NEXT>, which
-- is two rows down -- so line two is on row 16, not row 15.
check("the description at hlcoord 1,14", at(detail, 1, 14),
  "A physical attack")
check("nothing on row 15", at(detail, 1, 15), nil)
check("its second line on row 16", at(detail, 1, 16), "using full body")

-- Up and down pick the move the description belongs to.
input:press("down")
screen:update(0)
check("down picks the next move", screen.moveIndex, 2)
detail = screen:moveDetailPlacements()
check("the description follows the cursor", at(detail, 1, 14),
  "An attack that may")
check("and so does the type", at(detail, 2, 12), "FIRE")
input:press("down")
screen:update(0)
detail = screen:moveDetailPlacements()
check("a 0-power move prints ---", at(detail, 16, 12), "---")
check("with its own description", at(detail, 1, 14), "Lowers the foe's")
input:press("down")
screen:update(0)
check("down wraps within the known moves", screen.moveIndex, 1)

-- B backs out to the page it came from rather than closing the screen.
closed = false
screen.onClose = function() closed = true end
input:press("b")
screen:update(0)
check("b leaves the move detail", screen.moveDetail, false)
check("without closing the summary", closed, false)
check("and lands back on the move page", screen.page, SummaryMenu.GREEN_PAGE)

-- MoveScreenLoop's .d_right / .d_left walk the party, not the page.
screen.moveDetail = true
input:press("right")
screen:update(0)
check("right in the move detail walks the party", screen.index, 2)
check("and repoints the move list", screen.moveIndex, 1)
detail = screen:moveDetailPlacements()
check("at the new mon's move", at(detail, 2, 3), "SURF")
check("and its description", at(detail, 1, 14), "A strong water-")

-- ------------------------------------------------------------ mon submenu

-- GetMonSubmenuItems: field moves first, then STATS, SWITCH, MOVE, ITEM, and
-- CANCEL only while the list is under NUM_MONMENU_ITEMS.
local game = newGame(SAVE)
local party = PartyMenu.new(game, { party = SAVE.party, submenu = true })
local items = party:submenuItems(CYNDA)
local labels2 = {}
for i, entry in ipairs(items) do labels2[i] = entry.id end
check("no field moves means STATS is first", labels2[1], "STATS")
check("then SWITCH", labels2[2], "SWITCH")
check("then MOVE", labels2[3], "MOVE")
check("then ITEM", labels2[4], "ITEM")
check("then CANCEL", labels2[5], "CANCEL")
check("five rows in all", #items, 5)

-- A mon with a field move gets it above the fixed rows, named after the move.
local cutter = mon("TOTODILE", 10, {
  moves = { { id = "CUT", pp = 30, maxPp = 30 },
            { id = "SURF", pp = 15, maxPp = 15 } },
})
local cutterItems = party:submenuItems(cutter)
check("CUT leads the list", cutterItems[1].id, "CUT")
check("and is labelled with the move name", cutterItems[1].label, "CUT")
check("SURF follows it in table order", cutterItems[2].id, "SURF")
check("STATS comes after the field moves", cutterItems[3].id, "STATS")

-- Mail replaces the ITEM row.
local mailed = mon("TOTODILE", 10, { fields = { item = "FLOWER_MAIL" } })
local mailedItems = party:submenuItems(mailed)
check("a mail holder gets MAIL instead of ITEM", mailedItems[4].id, "MAIL")

-- .GetTopCoord grows the box upward from a fixed bottom, and PopulateMonMenu
-- writes two rows and two columns inside the corner.
check("a 5-row submenu starts at row 6", PartyMenu.submenuTop(5), 6)
check("a 4-row submenu starts at row 8", PartyMenu.submenuTop(4), 8)
local lx, ly = PartyMenu.submenuLabelCoord(5, 1)
check("the first label's column", lx, 8)
check("the first label's row", ly, 8)
local _, ly5 = PartyMenu.submenuLabelCoord(5, 5)
check("the last of five labels sits on row 16", ly5, 16)

-- A on the field list opens the submenu instead of answering; A on STATS
-- pushes the summary over the party list (OpenPartyStats).
local answered = nil
game = newGame(SAVE)
party = PartyMenu.new(game, {
  party = SAVE.party, submenu = true,
  onChoose = function(i) answered = i end,
})
game.input:press("a")
party:update(0)
check("a opens the submenu", party.submenu ~= nil, true)
check("and does not answer yet", answered, nil)
check("the cursor starts on the first row", party.submenu.index, 1)
game.input:press("a")
party:update(0)
check("a on STATS closes the submenu", party.submenu, nil)
check("and pushes a screen", #game.stack._items, 1)
local pushed = game.stack:top()
check("which is the summary", pushed.page, SummaryMenu.PINK_PAGE)
check("opened on the chosen mon", pushed.mon.species, "CYNDAQUIL")

-- B backs out of the submenu without touching the list (CancelPokemonAction).
game = newGame(SAVE)
party = PartyMenu.new(game, { party = SAVE.party, submenu = true })
game.input:press("a")
party:update(0)
game.input:press("b")
party:update(0)
check("b closes the submenu", party.submenu, nil)
check("and leaves the row alone", party.index, 1)
check("and pushes nothing", #game.stack._items, 0)

-- Every other flavour of the party list answers straight away, the way the
-- item and battle callers need it to.
answered = nil
game = newGame(SAVE)
party = PartyMenu.new(game, {
  party = SAVE.party, prompt = "useItem",
  onChoose = function(i) answered = i end,
})
game.input:press("a")
party:update(0)
check("a list without the submenu answers directly", answered, 1)
check("and opens no submenu", party.submenu, nil)

-- ------------------------------------------------------------- the EGG page
--
-- EggStatsScreen's pic (engine/pokemon/stats_screen.asm:786) is EggPic, which
-- the extractor writes as menu_gfx.eggHatch.egg -- and every cache imported
-- before that stage has no such entry, which is the whole of "the summary
-- shows no egg picture": the 7x7 block was left empty and nothing said why.
-- ICON_EGG has been in icons.lua since the party list existed
-- (ReadMonMenuIcon's `cp EGG / jr z, .egg`, engine/gfx/mon_icons.asm), so it
-- stands in and the page is never blank.
do
  local Assets = require("src.render.Assets")
  local realImage = Assets.image
  local realDraw = love.graphics.draw
  local asked, drawn = {}, 0
  Assets.image = function(path)
    asked[#asked + 1] = path
    if path == "egg-pic.png" then
      return { getWidth = function() return 40 end,
               getHeight = function() return 40 end }
    end
    if path == "egg-icon.png" then
      return { getWidth = function() return 16 end,
               getHeight = function() return 32 end }
    end
    return nil
  end
  love.graphics.draw = function() drawn = drawn + 1 end

  local egg = { species = "CYNDAQUIL", nickname = "EGG", isEgg = true,
    eggSteps = 20, level = 5, hp = 10, maxHp = 10 }
  local icons = { icons = { ICON_EGG = { image = "egg-icon.png", frames = 2,
    width = 16, height = 32 } } }

  -- A cache with EggPic in it draws EggPic and never looks at the icon.
  local screen = SummaryMenu.new(newGame(SAVE), { mon = egg, save = SAVE,
    menuGfx = { eggHatch = { egg = "egg-pic.png" } }, icons = icons })
  screen:drawEggPic()
  check("the EGG page draws its pic", drawn, 1)
  check("straight off menu_gfx.eggHatch.egg", asked[1], "egg-pic.png")
  check("and asks for nothing else", #asked, 1)

  -- A cache from before that stage: the page still shows an egg.
  asked, drawn = {}, 0
  screen = SummaryMenu.new(newGame(SAVE), { mon = egg, save = SAVE,
    menuGfx = {}, icons = icons })
  screen:drawEggPic()
  check("a cache with no EggPic still draws an egg", drawn, 1)
  check("falling back to ICON_EGG", asked[#asked], "egg-icon.png")

  -- Neither: nothing is drawn and nothing raises.
  asked, drawn = {}, 0
  screen = SummaryMenu.new(newGame(SAVE), { mon = egg, save = SAVE,
    menuGfx = {}, icons = {} })
  local ok = pcall(function() screen:drawEggPic() end)
  check("no egg art at all is survivable", ok, true)
  check("and draws nothing", drawn, 0)

  Assets.image = realImage
  love.graphics.draw = realDraw
end

print(("gen2 summary: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an
-- exit here takes the whole tier down with it and silently skips every
-- suite listed after this one (see tests/harness.lua's T.suite note).
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
