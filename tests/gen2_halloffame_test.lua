-- The end of the game: the Hall of Fame roster, its induction and its viewer,
-- and the credits movie.
--   GOLD_CACHE="$HOME/Library/Application Support/LOVE/gold-dev/gold" \
--     luajit tests/gen2_halloffame_test.lua
--
-- Three things are asserted here and nowhere else:
--
--   the ROSTER FORMAT      one win count and up to six mons per row, newest
--                          first, thirty rows deep, and what survives a save
--                          round trip and a format-1 migration
--   the LAYOUTS            every hlcoord DisplayHOFMon and HOF_AnimatePlayerPic
--                          write to, as data, so a coordinate can be checked
--                          against engine/events/halloffame.asm without a
--                          graphics device
--   the CREDITS TIMING     that the scene script runs to CREDITS_END, at the
--                          13-frame pass the jumptable actually is, and that
--                          the tilemap only reaches the screen on `.wait`
--
-- What a test cannot say -- whether the induction LOOKS like Gold's -- is what
-- tests/drivers/gold_halloffame_shots.lua exists for.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 hall of fame")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

-- No font is loaded here, so Font.encode would warn once per unknown glyph.
require("src.core.Logger").warn = function() end

local Core = require("src.core.gen2.HallOfFame")
local Credits = require("src.ui.gen2.Credits")
local GameVersion = require("src.core.GameVersion")
local HallOfFame = require("src.ui.gen2.HallOfFame")
local Save = require("src.core.gen2.Save")
local Screens = require("src.ui.Screens")

local priorVersion = GameVersion.get()
GameVersion.set("gold")

-- ---- fixtures -------------------------------------------------------------

local POKEMON = {
  TYPHLOSION = { name = "TYPHLOSION", index = 157, dex = 157,
    spriteFront = "front/typhlosion.png", spriteBack = "back/typhlosion.png" },
  LANTURN = { name = "LANTURN", index = 171, dex = 171,
    spriteFront = "front/lanturn.png", spriteBack = "back/lanturn.png" },
  UMBREON = { name = "UMBREON", index = 197, dex = 197 },
}

local function mon(species, level, nickname, otId)
  return {
    species = species, level = level, nickname = nickname, otId = otId,
    dvs = { attack = 15, defense = 10, speed = 10, special = 10 },
    gender = "male",
  }
end

local function newSave()
  local save = Save.newGame({ playerName = "GOLD", trainerId = 12345 })
  save.playTime = { hours = 42, minutes = 7, seconds = 0, frames = 0 }
  save.party = {
    mon("TYPHLOSION", 55, "BLAZE", 12345),
    mon("LANTURN", 51, "SPARK", 12345),
  }
  return save
end

-- ---- constants ------------------------------------------------------------

-- constants/pokemon_data_constants.asm and constants/misc_constants.asm.
eq(Core.NUM_TEAMS, 30, "NUM_HOF_TEAMS")
eq(Core.PARTY_LENGTH, 6, "PARTY_LENGTH")
eq(Core.MON_LENGTH, 0x10, "HOF_MON_LENGTH")
eq(Core.LENGTH, 0x62, "HOF_LENGTH")
eq(Core.NAME_LENGTH, 10, "MON_NAME_LENGTH - 1, what the nickname copy takes")
eq(Core.MASTER_COUNT, 200, "HOF_MASTER_COUNT")

-- ---- the win counter ------------------------------------------------------

local save = newSave()
eq(Core.count(save), 0, "a fresh save has never been inducted")
eq(Core.hasEntered(save), false, "and STATUSFLAGS_HALL_OF_FAME_F is clear")
eq(Core.bumpCount(save), 1, "the first induction counts")
eq(Core.bumpCount(save), 2, "and the second")

-- `ld a, [hl] / cp HOF_MASTER_COUNT / jr nc, .ok / inc [hl]`: the test is on
-- the PRE-increment value, so the counter stops AT HOF_MASTER_COUNT.
save.hallOfFame.count = Core.MASTER_COUNT - 1
eq(Core.bumpCount(save), Core.MASTER_COUNT, "199 still counts")
eq(Core.bumpCount(save), Core.MASTER_COUNT, "200 does not")
eq(Core.bumpCount(save), Core.MASTER_COUNT, "and never will again")

-- ---- GetHallOfFameParty ---------------------------------------------------

save = newSave()
save.hallOfFame.count = 3
save.party = {
  mon("TYPHLOSION", 55, "BLAZE", 12345),
  { species = "EGG", level = 5, isEgg = true },
  mon("LANTURN", 51, "SPARKLE-TOO-LONG", 12345),
}
local entry = Core.buildParty(save, save.party)
eq(entry.winCount, 3, "the row opens with wHallOfFameCount")
eq(#entry.mons, 2, "and an EGG is skipped rather than stored")
eq(entry.mons[1].species, "TYPHLOSION", "slot 1")
eq(entry.mons[2].species, "LANTURN", "the mon behind the egg keeps its own data")
eq(entry.mons[2].nickname, "SPARKLE-TO",
  "a nickname is cut to MON_NAME_LENGTH - 1")
eq(entry.mons[1].level, 55, "the level is stored")
eq(entry.mons[1].otId, 12345, "so is MON_OT_ID")
check(entry.mons[1].dvs ~= nil, "and MON_DVS")

-- PARTY_LENGTH is the cap even if something upstream handed over more.
save.party = {}
for index = 1, 9 do save.party[index] = mon("UMBREON", index, "U" .. index, 1) end
eq(#Core.buildParty(save, save.party).mons, Core.PARTY_LENGTH,
  "a row never holds more than PARTY_LENGTH mons")

-- ---- AddHallOfFameEntry ---------------------------------------------------

save = newSave()
for index = 1, Core.NUM_TEAMS + 5 do
  Core.addEntry(save, { winCount = index, mons = { mon("UMBREON", index) } })
end
eq(#save.hallOfFame.teams, Core.NUM_TEAMS,
  "the roster is capped at NUM_HOF_TEAMS")
eq(save.hallOfFame.teams[1].winCount, Core.NUM_TEAMS + 5,
  "newest first: the last row added is row 1")
eq(save.hallOfFame.teams[Core.NUM_TEAMS].winCount, 6,
  "and the five oldest fell off the end")

-- LoadHOFTeam's two ways of saying "stop".
eq(Core.team(save, 0), nil, "there is no team 0")
eq(Core.team(save, Core.NUM_TEAMS + 1), nil, "nor one past NUM_HOF_TEAMS")
eq(Core.teamCount(save), Core.NUM_TEAMS, "every slot is filled")
save.hallOfFame.teams[3].winCount = 0
eq(Core.team(save, 3), nil, "a row whose win count is zero reads as absent")
eq(Core.teamCount(save), 2, "and the PC's master loop stops there")

-- ---- the induction --------------------------------------------------------

save = newSave()
local saved = false
local row, wasEntered = Core.induct(save, save.party, {
  saveFn = function() saved = true end,
})
eq(wasEntered, false, "the first champion had not entered before")
eq(Core.hasEntered(save), true, "STATUSFLAGS_HALL_OF_FAME_F is set")
eq(Core.count(save), 1, "the counter moved")
eq(save.spawnAfterChampion, Core.SPAWN_LANCE, "wSpawnAfterChampion = SPAWN_LANCE")
eq(saved, true, "and the game was saved")
eq(#save.hallOfFame.teams, 1, "one row on the roster")
eq(save.hallOfFame.teams[1], row, "and it is the row that was returned")
eq(row.winCount, 1, "whose win count is the POST-increment counter")
eq(#row.mons, 2, "carrying the party that walked in")
eq(row.mons[1].nickname, "BLAZE", "with its nicknames")

local _, second = Core.induct(save, save.party)
eq(second, true, "a repeat champion HAD entered before")
eq(Core.count(save), 2, "and the counter moved again")
eq(#save.hallOfFame.teams, 2, "with a second row in front of the first")
eq(save.hallOfFame.teams[2].winCount, 1, "the first induction slid back one")

-- ---- the post-game continue -----------------------------------------------

eq(Core.consumePostGameSpawn(save), "SPAWN_NEW_BARK",
  "CONTINUE after the champion starts at New Bark Town")
eq(save.spawnAfterChampion, nil, "PostCreditsSpawn clears the byte")
eq(Core.consumePostGameSpawn(save), nil, "so the next load is ordinary")

Core.markRedCredits(save)
eq(save.spawnAfterChampion, Core.SPAWN_RED, "RedCredits sets SPAWN_RED")
eq(Core.consumePostGameSpawn(save), "SPAWN_MT_SILVER",
  "and that continue starts at Mt. Silver")

-- ---- the save round trip --------------------------------------------------

save = newSave()
Core.induct(save, save.party)
save.hallOfFame.teams[1].mons[1].nickname = "BLAZE"
check(Save.save(save), "the save is written")
local loaded, recovered, err = Save.load("gold")
eq(err, nil, "and reads back")
eq(recovered, nil, "off the main file")
eq(Core.count(loaded), 1, "the win count survived")
eq(#loaded.hallOfFame.teams, 1, "so did the roster")
eq(loaded.hallOfFame.teams[1].mons[1].species, "TYPHLOSION", "and the row")
eq(loaded.hallOfFame.teams[1].mons[1].nickname, "BLAZE", "with its nickname")
eq(loaded.hallOfFame.teams[1].mons[1].level, 55, "and its level")
eq(loaded.spawnAfterChampion, Core.SPAWN_LANCE,
  "the pending post-game spawn survives the save that the induction writes")

-- ---- the migration --------------------------------------------------------

-- A save written before the endgame existed has no roster at all; normalize
-- and migrate both have to leave one behind rather than an index error.
local old = Save.migrate({ format = 1, version = "gold" })
eq(old.format, Save.FORMAT, "a format-1 save migrates to the current format")
eq(old.hallOfFame.count, 0, "with an empty Hall of Fame")
eq(#old.hallOfFame.teams, 0, "and no roster")
eq(old.spawnAfterChampion, nil, "and no pending warp on the next load")
eq(Core.hasEntered(old), false, "it has never been inducted")

local bare = Save.normalize({ version = "gold" })
check(bare.hallOfFame ~= nil, "normalize fills the block in too")
eq(Core.count(bare), 0, "at zero")

-- A corrupt file with more rows than SRAM could hold is trimmed, the same way
-- an over-long party is.
local overfull = { version = "gold", hallOfFame = { count = 1, teams = {} } }
for index = 1, Core.NUM_TEAMS + 4 do
  overfull.hallOfFame.teams[index] = { winCount = index, mons = {} }
end
Save.normalize(overfull)
eq(#overfull.hallOfFame.teams, Core.NUM_TEAMS, "the roster is trimmed on load")

-- ---- DisplayHOFMon's layout -----------------------------------------------

local at = HallOfFame.at
local hofMon = {
  species = "TYPHLOSION", nickname = "BLAZE", level = 55, otId = 12345,
  gender = "male",
}
local placements = HallOfFame.monPlacements(hofMon, POKEMON.TYPHLOSION)
eq(at(placements, 1, 13), "№.", "hlcoord 1,13 is '№' then '.'")
eq(at(placements, 3, 13), "157", "hlcoord 3,13 is the dex number, 3 digits")
eq(at(placements, 7, 13), "TYPHLOSION", "hlcoord 7,13 is GetBasePokemonName")
eq(at(placements, 18, 13), "♂", "hlcoord 18,13 is the gender")
eq(at(placements, 8, 14), "/", "hlcoord 8,14 is a bare '/'")
eq(at(placements, 9, 14), "BLAZE", "so the nickname starts at 9,14")
eq(at(placements, 1, 16), "<LV>55", "hlcoord 1,16 is PrintLevel")
eq(at(placements, 7, 16), "<ID>№/", "hlcoord 7,16 is three single tiles")
eq(at(placements, 10, 16), "12345", "hlcoord 10,16 is the ID, 5 digits")

-- PRINTNUM_LEADINGZEROS on both numeric fields.
local lowIds = HallOfFame.monPlacements(
  { species = "UMBREON", nickname = "U", level = 5, otId = 7 }, POKEMON.UMBREON)
eq(at(lowIds, 10, 16), "00007", "a low ID keeps its leading zeros")
eq(at(lowIds, 3, 13), "197", "and so does the dex number")

-- A genderless species writes a space, which is nothing to print.
local nogender = HallOfFame.monPlacements(
  { species = "UMBREON", nickname = "U", level = 5, otId = 1 }, POKEMON.UMBREON)
eq(at(nogender, 18, 13), nil, "a genderless mon gets no symbol")

-- `.print_id_no` is jumped to for an EGG: only the ID line prints.
local egg = HallOfFame.monPlacements({ species = "EGG", otId = 1 }, nil)
eq(at(egg, 1, 13), nil, "an EGG skips the species block")
eq(at(egg, 7, 16), "<ID>№/", "but still prints its ID")

-- ---- the two header lines -------------------------------------------------

local induct = HallOfFame.headerPlacements("induct", 1)
eq(at(induct, 1, 2), HallOfFame.NEW_FAMER, "the induction says New Hall of Famer!")
eq(HallOfFame.NEW_FAMER, "New Hall of Famer!", ".String_NewHallOfFamer")

local viewed = HallOfFame.headerPlacements("view", 12)
eq(at(viewed, 1, 2), "    -Time Famer", ".TimeFamer, spaces and all")
eq(at(viewed, 2, 2), " 12", "and PrintNum writes over them at hlcoord 2,2")

-- BUG (docs/bugs_and_glitches.md): the counter stops at HOF_MASTER_COUNT and
-- the title needs HOF_MASTER_COUNT + 1, so "HOF Master!" is unreachable.
eq(at(HallOfFame.headerPlacements("view", Core.MASTER_COUNT), 1, 2),
  "    -Time Famer", "200 wins is still a -Time Famer")
eq(at(HallOfFame.headerPlacements("view", Core.MASTER_COUNT + 1), 1, 2),
  "    HOF Master!", "and only an impossible 201 reaches the title")

-- ---- HOF_AnimatePlayerPic's layout ----------------------------------------

save = newSave()
local card = HallOfFame.playerPlacements(save)
eq(at(card, 2, 4), "GOLD", "hlcoord 2,4 is wPlayerName")
eq(at(card, 1, 6), "<ID>№/", "hlcoord 1,6 is the ID caption")
eq(at(card, 4, 6), "12345", "hlcoord 4,6 is wPlayerID, 5 digits")
eq(at(card, 1, 8), "PLAY TIME", ".PlayTime")
eq(at(card, 3, 9), " 42", "hlcoord 3,9 is the hours in three columns")
eq(at(card, 6, 9), ":", "then HALLOFFAME_COLON")
eq(at(card, 7, 9), "07", "then the minutes with a leading zero")

-- ---- the induction cinematic ----------------------------------------------

save = newSave()
row = Core.induct(save, save.party)
local finished = false
local screen = HallOfFame.new({ data = { pokemon = POKEMON } }, {
  save = save, entry = row, onDone = function() finished = true end,
})
eq(screen.mode, "induct", "the default mode is the induction")
eq(screen.phase, "backpic", "which opens on AnimateHOFMonEntrance")
eq(screen.scx, HallOfFame.BACKPIC_SCX_START, "hSCX starts at $90")
eq(screen.scy, HallOfFame.SCY_START, "hSCY at $d0")

-- HOF_SlideBackpic adds 4 a frame until hSCX READS $70, which from $90 is the
-- long way round the byte: 56 frames, not 8.
local frames = 0
while screen.phase == "backpic" and frames < 200 do
  screen:step()
  frames = frames + 1
end
eq(frames, 56, "the backpic sweep is 56 frames")
eq(screen.scx, HallOfFame.BACKPIC_SCX_END, "and ends with hSCX at $70")
eq(screen.scy, 0, "with hSCY zeroed for the frontpic")

-- HOF_SlideFrontpic takes 2 off a frame from $70 down to 0.
frames = 0
while screen.phase == "frontpic" and frames < 200 do
  screen:step()
  frames = frames + 1
end
eq(frames, 56, "the frontpic slide is 56 frames")
eq(screen.scx, 0, "and lands on hSCX 0")
eq(screen.phase, "display", "then the mon is displayed")

-- `ld c, 180 / call DelayFrames`.
frames = 0
while screen.phase == "display" and frames < 400 do
  screen:step()
  frames = frames + 1
end
eq(frames, HallOfFame.FAMER_FRAMES, "each Hall of Famer holds for 180 frames")
eq(screen.index, 2, "and the counter moves to the next party slot")

-- Run the rest: the second mon, then HOF_AnimatePlayerPic.
frames = 0
while not screen.done and frames < 5000 do
  screen:step()
  frames = frames + 1
end
check(screen.done, "the induction reaches the end")
eq(finished, true, "and calls onDone")
-- 292 frames a mon (56 + 56 + 180), then 56 + 96 + 8 for the player card.
eq(frames, 292 + 56 + 96 + HallOfFame.END_FRAMES,
  "the whole cinematic is the sum of its DelayFrames")

-- ---- the PC's viewer ------------------------------------------------------

save = newSave()
Core.induct(save, save.party)
local closed = false
local input = { pressed = {} }
function input:press(button) self.pressed[button] = true end
function input:wasPressed(button)
  if self.pressed[button] then
    self.pressed[button] = nil
    return true
  end
  return false
end
function input:isDown() return false end

local viewer = HallOfFame.new({ data = { pokemon = POKEMON }, input = input }, {
  mode = "view", save = save, onDone = function() closed = true end,
})
eq(viewer.phase, "display", "the viewer opens straight on a mon")
eq(viewer.team, 1, "on the newest team")
eq(viewer.index, 1, "and its first mon")
input:press("a")
viewer:update(0)
eq(viewer.index, 2, "A is the next mon")
-- The team holds two, so the next A runs off the end and onto team 2, which
-- does not exist -- LoadHOFTeam returns carry and the screen closes.
input:press("a")
viewer:update(0)
eq(closed, true, "and running off the roster ends the viewer")

closed = false
viewer = HallOfFame.new({ data = { pokemon = POKEMON }, input = input }, {
  mode = "view", save = save, onDone = function() closed = true end,
})
input:press("b")
viewer:update(0)
eq(closed, true, "B backs out at once")

-- An empty roster has nothing to show, and the callback is deferred to the
-- first update so it cannot pop a state that has not been pushed.
closed = false
local empty = HallOfFame.new({ data = {}, input = input }, {
  mode = "view", save = newSave(), onDone = function() closed = true end,
})
eq(closed, false, "an empty roster does not call onDone during construction")
empty:update(0)
eq(closed, true, "it calls it on the first update instead")

-- ---- the credits: the script ----------------------------------------------

eq(Credits.END, 0xff, "CREDITS_END")
eq(Credits.WAIT, 0xfe, "CREDITS_WAIT")
eq(Credits.SCENE, 0xfd, "CREDITS_SCENE")
eq(Credits.CLEAR, 0xfc, "CREDITS_CLEAR")
eq(Credits.MUSIC, 0xfb, "CREDITS_MUSIC")
eq(Credits.WAIT2, 0xfa, "CREDITS_WAIT2")
eq(Credits.THEEND, 0xf9, "CREDITS_THEEND")
eq(Credits.PASS_FRAMES, 13, "Credits_Jumptable is 13 entries, one a frame")

-- The strings the two comparisons in ParseCredits key off.
check(Credits.STAFF < Credits.COPYRIGHT,
  "COPYRIGHT sits above STAFF, as in credits_constants.asm")
check(Credits.ID.BRYANTHABOI < Credits.STAFF,
  "and every person string sits below it")

local movie = Credits.new({ data = {} }, {})
eq(movie.step, 0, "the jumptable starts at ParseCredits")
eq(movie.borderFrame, 0xff, "with the banner blanked")
eq(movie.timer, 0, "and the timer out, so the first pass parses")

local ranFor = movie:runToEnd(60000)
check(ranFor ~= nil, "the scene script runs to CREDITS_END")
eq(movie.exiting, true, "which sets JUMPTABLE_EXIT_F")
eq(movie.scene, 3, "after four CREDITS_SCENE changes")
check(movie.passes > 300, "over more than 300 passes of the jumptable")
-- 13 frames a pass is the whole point of the cadence.
eq(ranFor > movie.passes * (Credits.PASS_FRAMES - 1), true,
  "and roughly 13 frames apiece")

-- "THE END" is written by CREDITS_THEEND and survives the blank ParseCredits
-- runs immediately before CREDITS_END, because CREDITS_END never pushes the
-- tilemap to the screen.
eq(#movie.shown, 1, "one thing is on screen at the end")
eq(movie.shown[1].theEnd, true, "and it is THE END")
eq(movie.shown[1].x, 6, "at hlcoord 6, 8")
eq(movie.shown[1].y, 8, "the coordinate Credits_TheEnd writes")

-- ---- the credits: the parse arms ------------------------------------------

-- A hand-built script exercising each command on its own.
local probe = Credits.new({ data = {} }, {
  script = {
    Credits.SCENE, 2,
    Credits.ID.DIRECTOR, 0,
    Credits.ID.BRYANTHABOI, 1,
    Credits.WAIT, 3,
    Credits.ID.PRODUCER, 2,
    Credits.WAIT2, 1,
    Credits.CLEAR,
    Credits.WAIT, 1,
    Credits.END,
  },
})
probe:parse()
eq(probe.scene, 2, "CREDITS_SCENE picks the banner mon")
eq(probe.borderFrame, 0, "and resets its animation frame")
eq(#probe.shown, 2, "CREDITS_WAIT pushes the tilemap")
eq(probe.shown[1].y, Credits.TEXT_FIRST_ROW, "line 0 is row 6")
eq(probe.shown[2].y, Credits.TEXT_FIRST_ROW + Credits.LINE_SPACING,
  "line 1 is row 8, two rows on")
eq(probe.shown[1].x, 0, "and both start at column 0")
eq(probe.timer, 3, "the wait is three passes")

-- Three passes of nothing, then the next parse.
probe:parse(); probe:parse(); probe:parse()
eq(probe.timer, 0, "the timer runs out")
probe:parse()
eq(#probe.shown, 2,
  "CREDITS_WAIT2 leaves the previous screen up rather than pushing")
eq(#probe.pending, 1, "even though a new line was written into the tilemap")
probe:parse() -- burn the one-pass wait CREDITS_WAIT2 set
probe:parse()
eq(probe.borderFrame, 0xff, "CREDITS_CLEAR blanks the banner")
eq(#probe.shown, 0, "and the wait behind it pushes the cleared tilemap")

-- The multi-line strings step by <NEXT>, which is two rows.
local multi = Credits.new({ data = {} }, {
  script = { Credits.ID.STAFF, 0, Credits.WAIT, 1, Credits.END },
})
multi:parse()
eq(#multi.shown, 3, "the STAFF heading is three lines")
eq(multi.shown[1].y, 6, "at rows 6,")
eq(multi.shown[2].y, 8, "8")
eq(multi.shown[3].y, 10, "and 10")

-- COPYRIGHT is the one string with an hlcoord of its own.
local copy = Credits.new({ data = {} }, {
  script = { Credits.COPYRIGHT, 0, Credits.WAIT, 1, Credits.END },
})
copy:parse()
eq(copy.shown[1].x, 2, "Credits_Copyright prints at hlcoord 2, 6")
eq(copy.shown[1].y, 6, "on row 6")

-- ---- the credits: the banner and the border -------------------------------

local banner = Credits.new({ data = {} }, {})
eq(banner:borderGraphic(), nil, "a cleared banner has no graphic")
banner.borderFrame = 0
banner.scene = 0
eq(banner:borderGraphic(), 1, "Bellossom frame 0 is its first graphic")
banner:advanceBorder()
eq(banner:borderGraphic(), 2, "frame 1 the second")
banner:advanceBorder()
eq(banner:borderGraphic(), 1, "frame 2 repeats the first, as .Frames does")
banner:advanceBorder()
eq(banner:borderGraphic(), 3, "and frame 3 the third")
banner:advanceBorder()
eq(banner.borderFrame, 0, "then the frame wraps")
banner.scene = 3
eq(banner:borderGraphic(), 1, "Sentret is the one mon with four distinct frames")
banner.borderFrame = 2
eq(banner:borderGraphic(), 3, "so its frame 2 is its own graphic")
banner.borderFrame = 0xff
banner:advanceBorder()
eq(banner.borderFrame, 0xff, "a blanked banner stays blanked")

eq(banner.lyOverride, 0, "wCreditsLYOverride starts at zero")
banner:advanceLY()
eq(banner.lyOverride, 2, "and gains two a pass")

-- Four scene palettes, straight off gfx/credits/credits.pal.  GetCreditsPalette
-- masks the scene with %11, so there are exactly four and no fifth.
check(Credits.PALETTES[3] ~= nil, "four palettes, indexed from zero")
eq(Credits.PALETTES[4], nil, "and nothing past the %11 mask")
eq(Credits.PALETTES[0][1][1], 255, "colour 0 is white")
eq(Credits.PALETTES[0][4][1], 58, "and colour 3 the near-black RGB 07,07,07")

-- ---- the credits: gfx/credits/ --------------------------------------------

-- RomExtractorGen2:extractCredits puts the real sheets in the cache as
-- data.gen2Credits, and every one of them has to beat the mon-icon fallback.
local GFX = {
  border = "assets/generated/credits/border.png",
  borderTiles = 9,
  borderTopTile = 5,
  borderBottomTile = 1,
  borderFillTile = 9,
  theEnd = "assets/generated/credits/theend.png",
  theEndX = 6, theEndY = 8, theEndWidth = 8,
  scenes = {
    { species = "BELLOSSOM", image = "a.png", frames = 3, width = 32, height = 32 },
    { species = "TOGEPI", image = "b.png", frames = 3, width = 32, height = 32 },
    { species = "ELEKID", image = "c.png", frames = 3, width = 32, height = 32 },
    { species = "SENTRET", image = "d.png", frames = 4, width = 32, height = 32 },
  },
  palettes = {
    { { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 }, { 4, 4, 4 } },
    { { 5, 5, 5 }, { 6, 6, 6 }, { 7, 7, 7 }, { 8, 8, 8 } },
    { { 9, 9, 9 }, { 10, 10, 10 }, { 11, 11, 11 }, { 12, 12, 12 } },
    { { 13, 13, 13 }, { 14, 14, 14 }, { 15, 15, 15 }, { 16, 16, 16 } },
    { { 17, 17, 17 }, { 18, 18, 18 }, { 19, 19, 19 }, { 20, 20, 20 } },
    { { 21, 21, 21 }, { 22, 22, 22 }, { 23, 23, 23 }, { 24, 24, 24 } },
  },
}

local withGfx = Credits.new({ data = { gen2Credits = GFX } }, {})
local _, sheet = withGfx:sceneSheet()
eq(sheet and sheet.species, "BELLOSSOM", "scene 0 is the Bellossom sheet")
withGfx.scene = 3
local sentretImage, sentret = withGfx:sceneSheet()
eq(sentret.frames, 4, "and Sentret is the four-frame one")
-- Three of the four sheets only hold three blocks and .Frames never asks them
-- for a fourth, but a clamp is cheaper than trusting that from the draw path.
withGfx.scene = 0
local bellossomImage, bellossom = withGfx:sceneSheet()
local quad = withGfx:sheetQuad(bellossomImage, bellossom, 4)
eq(quad.y, 2 * 32, "a fourth frame on a three-frame sheet clamps to the third")
eq(withGfx:sheetQuad(sentretImage, sentret, 4).y, 3 * 32,
  "while Sentret's fourth block is its own")
eq(withGfx:sheetQuad(bellossomImage, bellossom, 1).y, 0, "frame 1 is block 0")

-- CreditsPalettes wins over the transcribed table, and the %11 mask still
-- picks the same four sets it always did.
eq(withGfx:palette()[1][1], 1, "scene 0 takes the first extracted set")
withGfx.scene = 3
eq(withGfx:palette()[1][1], 13, "scene 3 the fourth")
eq(Credits.new({ data = {} }, {}):palette()[1][1], 255,
  "and a cache without the table keeps the transcribed one")

-- DrawCreditsBorder starts at $24 on row 4 and $20 on row 13, so the two
-- strips are DIFFERENT quarters of the 9-tile block.
check(GFX.borderTopTile ~= GFX.borderBottomTile,
  "the two border rows do not share a start tile")
local borderImage = withGfx:image(GFX.border)
eq(withGfx:borderQuad(borderImage, 5).x, 4 * 8, "tile 5 is the fifth column")
eq(withGfx:borderQuad(borderImage, 1).x, 0, "and tile 1 the first")

check(withGfx:theEndImage() ~= nil, "TheEndGFX replaces the printed words")
eq(Credits.new({ data = {} }, {}):theEndImage(), nil,
  "and is absent from a cache without it")

-- ---- the credits: skipping ------------------------------------------------

-- Credits_HandleBButton: nothing happens without ALLOW_SKIPPING_CREDITS_F,
-- which HallOfFame:: only passes on when the player HAD entered before.
local held = { down = { b = true } }
function held:isDown(button) return self.down[button] end
function held:wasPressed() return false end

local firstTime = Credits.new({ data = {} }, { allowSkip = false })
firstTime.timer = 5
firstTime.pos = 40
firstTime:handleB(held)
eq(firstTime.timer, 5, "a first-time champion cannot hurry the credits")

local repeatWin = Credits.new({ data = {} }, { allowSkip = true })
repeatWin.timer = 5
repeatWin.pos = 40
repeatWin:handleB(held)
eq(repeatWin.timer, 4, "a repeat champion takes an extra tick off per frame")

-- ...but not before wCreditsPos has passed $d.
repeatWin.pos = 3
repeatWin.timer = 5
repeatWin:handleB(held)
eq(repeatWin.timer, 5, "and not in the first thirteen script bytes")

-- Credits_HandleAButton: A only leaves once the exit flag is up.
local aHeld = { down = { a = true } }
function aHeld:isDown(button) return self.down[button] end
function aHeld:wasPressed() return false end
local running = Credits.new({ data = {} }, {})
eq(running:handleA(aHeld), false, "A does nothing while the script is running")
running.exiting = true
eq(running:handleA(aHeld), true, "and leaves once CREDITS_END has been read")

-- ---- the Screens ids ------------------------------------------------------

-- Every Gold screen is reached through a src/ui/Screens.lua id so a mod can
-- replace it, and the "Gen2" prefix is what keeps Gold's credits and Hall of
-- Fame separate from the Gen 1 screens of the same module name.
local registered = {}
for _, id in ipairs(Screens.GEN2_IDS) do registered[id] = true end
for _, id in ipairs({ "Gen2HallOfFame", "Gen2Credits", "Gen2CardFlip",
    "Gen2ContestMenu", "Gen2DayCareMenu",
    "Gen2SlotMachine" }) do
  eq(registered[id], true, "the id list carries " .. id)
end
-- The Game Corner PRIZE COUNTERS are map script on the cart, not a screen, so
-- the one id that would only ever have been resolved by a mod is gone.
eq(registered["Gen2PrizeMenu"], nil,
  "and does not carry a prize counter the VM runs as script")
Screens.invalidate()
eq(Screens.get({}, "Gen2HallOfFame"), HallOfFame,
  "Gen2HallOfFame resolves to src/ui/gen2/HallOfFame.lua")
eq(Screens.get({}, "Gen2Credits"), Credits,
  "Gen2Credits resolves to src/ui/gen2/Credits.lua")
eq(Screens.get({}, "HallOfFame"), require("src.ui.HallOfFame"),
  "and the un-prefixed id is still Gen 1's")
eq(Screens.get({}, "Credits"), require("src.ui.Credits"),
  "for both of them")
Screens.invalidate()

-- ---- the script seam ------------------------------------------------------

-- The screens and the roster above are only reachable if the `halloffame`
-- ($9f) and `credits` ($a0) COMMANDS find a hook: Vm.lua guards both on
-- self.hallOfFameFn / self.creditsFn and returns out of the script either way,
-- so a missing hook is a silent skip of the whole ending rather than a crash.
-- This batch shipped the model, the two screens and the ids with nothing on
-- the World supplying those hooks, which made the ending unreachable; assert
-- the wire, not just the parts.
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")

local seen = {}
local endingVm = Vm.new({
  generation = 2,
  ["s:champion"] = { { op = "halloffame" }, { op = "setevent", event = 7 } },
  ["s:red"] = { { op = "credits" }, { op = "setevent", event = 8 } },
}, {}, Events.new(), {
  hallOfFame = function(onDone) seen[#seen + 1] = "halloffame" onDone() end,
  credits = function(onDone) seen[#seen + 1] = "credits" onDone() end,
})
endingVm:start("s:champion")
eq(seen[1], "halloffame", "the halloffame command reaches the hook")
eq(endingVm:running(), false, "and ReturnFromCredits ends the script")
eq(endingVm.events:get(7), false,
  "so nothing after it in the list runs (Script_endall, MAPSTATUS_DONE)")
endingVm:start("s:red")
eq(seen[2], "credits", "the credits command reaches the hook")
eq(endingVm.events:get(8), false, "and ends the script the same way")

-- The World is what supplies them.  Required last so the two screens above are
-- resolved from the registry rather than from World's own require chain.
local World = require("src.world.gen2.World")
eq(type(World.hallOfFame), "function", "World:hallOfFame backs the command")
eq(type(World.credits), "function", "World:credits backs the command")

-- HallOfFame.induct answers the PRE-induction flag second, because Credits'
-- ALLOW_SKIPPING_CREDITS_F is read off the copy HallOfFame:: pushed before it
-- set the bit.  A first-time champion must NOT be able to skip.
local fresh = Save.newGame({ name = "GOLD" })
fresh.party = { { species = 155, level = 40, hp = 60, maxHp = 60 } }
local _, wasEntered = Core.induct(fresh, fresh.party)
eq(wasEntered, false, "a first champion has no HALL_OF_FAME flag yet")
eq(Core.hasEntered(fresh), true, "and the induction sets it")
local _, again = Core.induct(fresh, fresh.party)
eq(again, true, "so a repeat champion may fast-forward the credits")

-- ---- the real cache: data/generated/credits.lua ---------------------------
--
-- Written by RomExtractorGen2:extractCredits, so a cache imported before that
-- landed has no file and this block is a skip rather than a failure.

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local creditsPath = cache .. "/data/generated/credits.lua"
local cf = io.open(creditsPath, "r")
if not cf then
  check(true, "credits.lua absent : re-import needed (SKIP cache facts)")
else
  cf:close()
  local creditsData = assert(loadfile(creditsPath))()
  eq(creditsData.borderTiles, 9, "CreditsBorderGFX is nine tiles")
  eq(#creditsData.scenes, 4, "four mon sheets, one per scene")
  for index, entry in ipairs(creditsData.scenes) do
    eq(entry.species, Credits.SCENE_SPECIES[index - 1],
      "scene " .. (index - 1) .. " is " .. tostring(entry.species))
    -- .Frames only reaches +48 tiles for Sentret; the other three stop at +32.
    eq(entry.frames, (entry.species == "SENTRET") and 4 or 3,
      "its block count is what .Frames offsets into")
  end
  eq(#creditsData.palettes, 6, "credits.pal is six four-colour sets")
  eq(creditsData.palettes[1][1][1], 255, "and set 1 colour 0 is white")
end

GameVersion.set(priorVersion)

S.finish()
