-- The Ruins of Alph: the sliding-panel puzzle, and everything about Unown that
-- is a FORM rather than a species.
--
-- ROM-free and draw-free.  The puzzle's board, cursor and solve check are pure
-- functions over a 36-cell array, so the whole screen can be driven from a
-- stub input; the letter maths (GetUnownLetter, CheckUnownLetter,
-- UpdateUnownDex) is pure to begin with.  What a test cannot say -- whether the
-- board LOOKS like the cart's -- is what a screenshot driver is for.

package.path = "./?.lua;" .. package.path
require("tests.fixture_data.gen2_engine_flags").bind("gold")

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

require("src.core.Logger").warn = function() end

local Mon = require("src.battle.gen2.Mon")
local Save = require("src.core.gen2.Save")
local Screens = require("src.ui.Screens")
local Unown = require("src.core.gen2.Unown")
local UnownPuzzle = require("src.ui.gen2.UnownPuzzle")

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

-- A scripted RNG in the src/battle/gen2 convention: `random(n)` is 0..n-1.
local function scripted(values)
  local i = 0
  return function(n)
    i = i + 1
    return (values[i] or 0) % (n or 256)
  end
end

-- ==================================================================== letters
--
-- GetUnownLetter (engine/gfx/load_pics.asm) packs the middle two bits of the
-- four DVs as atk/def/spd/spc, divides by 10 and adds one.  All-zero DVs are
-- letter A and all-15 DVs are the top of the range.
check("DVs 0/0/0/0 spell A",
  Unown.letterFromDVs({ attack = 0, defense = 0, speed = 0, special = 0 }), 1)
check("DVs 15/15/15/15 spell Z",
  Unown.letterFromDVs({ attack = 15, defense = 15, speed = 15, special = 15 }),
  26)
check("A is letter 1", Unown.name(1), "A")
check("Z is letter 26", Unown.name(26), "Z")
check("letter 27 is nothing", Unown.name(27), nil)
check('"C" indexes to 3', Unown.index("C"), 3)

-- The middle bits are bits 1 and 2 of each DV, so bit 0 and bit 3 change
-- nothing.  DVs 1 and 8 differ from 0 only outside the mask.
check("bit 0 of a DV is not part of the letter",
  Unown.letterFromDVs({ attack = 1, defense = 1, speed = 1, special = 1 }), 1)
check("bit 3 of a DV is not part of the letter",
  Unown.letterFromDVs({ attack = 8, defense = 8, speed = 8, special = 8 }), 1)

-- The packed value is atk in bits 6-7, so an Attack DV of 2 (middle bits = 1)
-- alone is 64, and 64 / 10 + 1 is letter 7 (G).
check("attack DV 2 alone is G",
  Unown.letterFromDVs({ attack = 2, defense = 0, speed = 0, special = 0 }), 7)

-- dvsForLetter is the inverse, so every letter round-trips.
for letter = 1, 26 do
  check("letter " .. letter .. " round-trips through its DVs",
    Unown.letterFromDVs(Unown.dvsForLetter(letter)), letter)
end

-- Mon.new stamps the form, and only on Unown.
local data = {
  pokemon = {
    UNOWN = { name = "UNOWN", index = 201, types = { "PSYCHIC" },
      baseStats = { hp = 48, attack = 72, defense = 48, speed = 48,
        specialAttack = 72, specialDefense = 48 },
      growthRate = "MEDIUM_FAST", genderRatio = 0xff, levelMoves = {},
      letters = {} },
    RATTATA = { name = "RATTATA", index = 19, types = { "NORMAL" },
      baseStats = { hp = 30, attack = 56, defense = 35, speed = 72,
        specialAttack = 25, specialDefense = 35 },
      growthRate = "MEDIUM_FAST", genderRatio = 0x7f, levelMoves = {} },
    growthRates = {},
  },
  moves = {},
}
for letter = 1, 26 do
  data.pokemon.UNOWN.letters[Unown.name(letter)] = {
    spriteFront = "front/unown_" .. Unown.name(letter):lower() .. ".png",
    spriteBack = "back/unown_" .. Unown.name(letter):lower() .. ".png",
  }
end

local unown = Mon.new(data, "UNOWN", 5, { dvs = Unown.dvsForLetter(9) })
check("a built Unown carries its letter", unown.unownLetter, 9)
check("and Unown.monLetter reads it back", Unown.monLetter(unown), 9)
local ratty = Mon.new(data, "RATTATA", 5)
check("nothing else carries one", ratty.unownLetter, nil)
check("and monLetter refuses it", Unown.monLetter(ratty), nil)

check("the form picks its own pic",
  Unown.formSprite(data.pokemon, 9, false), "front/unown_i.png")
check("and its own back pic",
  Unown.formSprite(data.pokemon, 9, true), "back/unown_i.png")

-- ============================================================== the four sets
--
-- data/wild/unlocked_unowns.asm: A-K, L-R, S-W, X-Z, one ENGINE_* flag each,
-- and the runs are uneven because they were cut to the four chamber puzzles.
check("four unlock sets", #Unown.UNLOCK_SETS, 4)
check("A-K is eleven letters",
  Unown.UNLOCK_SETS[1].last - Unown.UNLOCK_SETS[1].first + 1, 11)
check("L-R is seven",
  Unown.UNLOCK_SETS[2].last - Unown.UNLOCK_SETS[2].first + 1, 7)
check("S-W is five",
  Unown.UNLOCK_SETS[3].last - Unown.UNLOCK_SETS[3].first + 1, 5)
check("X-Z is three",
  Unown.UNLOCK_SETS[4].last - Unown.UNLOCK_SETS[4].first + 1, 3)
check("the four sets cover all 26 letters",
  Unown.UNLOCK_SETS[4].last, 26)
check("ENGINE_UNLOCKED_UNOWNS_A_TO_K is Gold flag 42",
  require("src.core.gen2.EngineFlags").id(Unown.UNLOCK_SETS[1].name), 42)
check("ENGINE_UNOWN_DEX is flag 12", Unown.ENGINE_UNOWN_DEX, 12)

-- Each chamber's .PuzzleComplete arm sets exactly one of them.
check("Kabuto unlocks A-K", Unown.PUZZLES[0].flag, Unown.UNLOCK_SETS[1].name)
check("Omanyte unlocks L-R", Unown.PUZZLES[1].flag, Unown.UNLOCK_SETS[2].name)
check("Aerodactyl unlocks S-W", Unown.PUZZLES[2].flag, Unown.UNLOCK_SETS[3].name)
check("Ho-Oh unlocks X-Z", Unown.PUZZLES[3].flag, Unown.UNLOCK_SETS[4].name)

local flags = {}
check("nothing is unlocked on a fresh file", Unown.anyUnlocked(flags), false)
check("and no letter passes CheckUnownLetter",
  Unown.letterUnlocked(1, flags), false)
flags[42] = true
check("solving Kabuto unlocks something", Unown.anyUnlocked(flags), true)
check("A is now legal", Unown.letterUnlocked("A", flags), true)
check("K is now legal", Unown.letterUnlocked("K", flags), true)
check("L is still locked", Unown.letterUnlocked("L", flags), false)
check("eleven letters are reachable", #Unown.unlockedLetters(flags), 11)
flags[45] = true
check("Ho-Oh adds three more", #Unown.unlockedLetters(flags), 14)
check("X is legal", Unown.letterUnlocked("X", flags), true)
check("W is not", Unown.letterUnlocked("W", flags), false)

-- LoadEnemyMon's .GenerateDVs loop rerolls a locked letter.  Feed a DV source
-- that would produce Z first and then A: only the second survives when just
-- A-K is open.
local onlyAK = { [42] = true }
local queue = { Unown.dvsForLetter(26), Unown.dvsForLetter(3) }
local at = 0
local rolled = Unown.wildDVs(onlyAK, function()
  at = at + 1
  return queue[at] or Unown.dvsForLetter(1)
end)
check("a locked letter is rerolled", Unown.letterFromDVs(rolled), 3)
check("and it took exactly two rolls", at, 2)

-- With nothing unlocked at all the reroll does not run: ChooseWildEncounter
-- has already refused the encounter, so there is no legal letter to find and
-- the cart would spin.
local anyDVs = Unown.wildDVs({}, function() return Unown.dvsForLetter(26) end)
check("with no puzzle solved the roll is taken as-is",
  Unown.letterFromDVs(anyDVs), 26)

-- ================================================================ the #DEX
--
-- UpdateUnownDex appends a NEW form to the first free slot and returns at once
-- for one already listed, so the list is catching order without duplicates.
local save = Save.newGame({ playerName = "GOLD" })
check("a new file has an empty form list", Unown.count(save), 0)
check("registering C appends it", Unown.updateDex(save, 3), true)
check("registering A appends it", Unown.updateDex(save, 1), true)
check("registering C again does not", Unown.updateDex(save, 3), false)
check("two forms recorded", Unown.count(save), 2)
check("in catching order, C first", Unown.dex(save)[1], 3)
check("then A", Unown.dex(save)[2], 1)
check("Unown.caught knows C", Unown.caught(save, "C"), true)
check("and does not know B", Unown.caught(save, "B"), false)

-- registerCatch is the AddPartyMon / SendMonIntoBox entry: it takes a MON and
-- falls through for anything that is not an Unown.
check("registerCatch ignores a Rattata", Unown.registerCatch(save, ratty),
  false)
check("registerCatch records an Unown", Unown.registerCatch(save, unown), true)
check("three forms now", Unown.count(save), 3)
check("the newest is I", Unown.dex(save)[3], 9)

-- data/pokemon/unown_words.asm, one word per form.  X really is "XXXXX".
check("26 words", #Unown.WORDS, 26)
check("A is ANGRY", Unown.word(1), "ANGRY")
check("R is REASSURE", Unown.word("R"), "REASSURE")
check("X is XXXXX", Unown.word("X"), "XXXXX")
check("Z is ZOOM", Unown.word(26), "ZOOM")

-- Save.normalize keeps the list and trims a corrupt one.
local grown = Save.newGame({ playerName = "GOLD" })
for i = 1, 40 do grown.unownDex[i] = 1 end
Save.normalize(grown)
check("normalize trims the form list to NUM_UNOWN", #grown.unownDex, 26)

-- ================================================================ the board
--
-- .PuzzlePieceInitialPositions: sixteen ring cells, and the deal fills every
-- one of them exactly once.
check("sixteen start cells", #UnownPuzzle.START_CELLS, 16)
check("36 cells on the board", UnownPuzzle.CELLS, 36)
check("PUZZLE_BORDER is $ee", UnownPuzzle.BORDER_TILE, 0xee)
check("PUZZLE_VOID is $ef", UnownPuzzle.VOID_TILE, 0xef)

local board = UnownPuzzle.deal(scripted({ 0, 1, 2, 3, 4, 5, 6, 7,
  8, 9, 10, 11, 12, 13, 14, 15 }))
local placed, onRing = 0, true
for cell = 1, UnownPuzzle.CELLS do
  if board[cell] ~= 0 then
    placed = placed + 1
    local ring = false
    for _, start in ipairs(UnownPuzzle.START_CELLS) do
      if start == cell - 1 then ring = true end
    end
    if not ring then onRing = false end
  end
end
check("a deal places sixteen panels", placed, 16)
check("all of them on the ring", onRing, true)
check("a fresh board is not solved", UnownPuzzle.isSolved(board), false)

-- Even a degenerate RNG deals a legal board rather than spinning: every roll
-- lands on the same start cell and the fallback probes for the next free one.
local stuck = UnownPuzzle.deal(function() return 0 end)
local stuckPlaced = 0
for cell = 1, UnownPuzzle.CELLS do
  if stuck[cell] ~= 0 then stuckPlaced = stuckPlaced + 1 end
end
check("a fixed RNG still deals sixteen", stuckPlaced, 16)

check("the solved configuration is the solved configuration",
  UnownPuzzle.isSolved(UnownPuzzle.SOLVED), true)
-- One panel out of place is not solved.
local nearly = {}
for i = 1, UnownPuzzle.CELLS do nearly[i] = UnownPuzzle.SOLVED[i] end
nearly[8], nearly[9] = nearly[9], nearly[8]
check("two swapped panels are not solved", UnownPuzzle.isSolved(nearly), false)

-- =============================================================== the cursor
--
-- The board is NOT a rectangle: row 5 has only its two end cells, because the
-- START>CANCEL box sits in the middle of it.
local pc = UnownPuzzle.puzcoord
check("up from row 0 is refused", UnownPuzzle.moveCursor(pc(0, 3), "up"), nil)
check("up from row 1 lands on row 0",
  UnownPuzzle.moveCursor(pc(1, 3), "up"), pc(0, 3))
check("down from row 4 column 2 is refused",
  UnownPuzzle.moveCursor(pc(4, 2), "down"), nil)
check("down from row 4 column 0 reaches START",
  UnownPuzzle.moveCursor(pc(4, 0), "down"), pc(5, 0))
check("down from row 4 column 5 reaches CANCEL",
  UnownPuzzle.moveCursor(pc(4, 5), "down"), pc(5, 5))
check("down from row 5 is refused",
  UnownPuzzle.moveCursor(pc(5, 0), "down"), nil)
check("left from column 0 is refused",
  UnownPuzzle.moveCursor(pc(2, 0), "left"), nil)
check("left from cell 0 is refused", UnownPuzzle.moveCursor(0, "left"), nil)
check("right from column 5 is refused",
  UnownPuzzle.moveCursor(pc(2, 5), "right"), nil)
check("left from CANCEL jumps to START",
  UnownPuzzle.moveCursor(pc(5, 5), "left"), pc(5, 0))
check("right from START jumps to CANCEL",
  UnownPuzzle.moveCursor(pc(5, 0), "right"), pc(5, 5))
check("right along row 2 steps by one",
  UnownPuzzle.moveCursor(pc(2, 2), "right"), pc(2, 3))

-- The cells the cursor can reach: the 6x6 grid minus row 5's four middle
-- cells, which no rule ever produces.
local reachable = { [0] = true }
local frontier = { 0 }
while #frontier > 0 do
  local at = table.remove(frontier)
  for _, direction in ipairs({ "up", "down", "left", "right" }) do
    local to = UnownPuzzle.moveCursor(at, direction)
    if to and not reachable[to] then
      reachable[to] = true
      frontier[#frontier + 1] = to
    end
  end
end
local count = 0
for _ in pairs(reachable) do count = count + 1 end
check("32 cells are reachable", count, 32)
for col = 1, 4 do
  check("row 5 column " .. col .. " is not reachable",
    reachable[pc(5, col)], nil)
end

-- UnownPuzzleCoordData's tilemap column: cell i sits at (1 + 3c, 3r), and the
-- interior 4x4 clears to PUZZLE_VOID while the ring clears to PUZZLE_BORDER.
local tx, ty = UnownPuzzle.cellTile(0)
check("cell 0 is at tile (1,0) x", tx, 1)
check("cell 0 is at tile (1,0) y", ty, 0)
tx, ty = UnownPuzzle.cellTile(pc(1, 1))
check("cell (1,1) is at tile (4,3) x", tx, 4)
check("cell (1,1) is at tile (4,3) y", ty, 3)
tx = UnownPuzzle.cellTile(pc(5, 5))
check("cell (5,5) is at tile x 16", tx, 16)
check("the interior clears to VOID",
  UnownPuzzle.vacantTile(pc(2, 2)), UnownPuzzle.VOID_TILE)
check("the ring clears to BORDER",
  UnownPuzzle.vacantTile(pc(0, 0)), UnownPuzzle.BORDER_TILE)
check("row 5 clears to BORDER",
  UnownPuzzle.vacantTile(pc(5, 0)), UnownPuzzle.BORDER_TILE)

-- ================================================================ the screen
--
-- A stub input: `press` queues one frame of button presses.
local input = { pressed = {} }
function input:wasPressed(button) return self.pressed[button] == true end
function input:isDown(button) return self.pressed[button] == true end

love.graphics.newQuad = function(x, y, w, h)
  local quad = {}
  function quad.setViewport(_, nx, ny, nw, nh) x, y, w, h = nx, ny, nw, nh end
  function quad.getViewport() return x, y, w, h end
  return quad
end
love.graphics.newImage = function(path)
  if tostring(path):find("unloadable", 1, true) then return nil end
  local w, h = 96, 96
  if tostring(path):find("chrome", 1, true) then w, h = 152, 8 end
  return { getDimensions = function() return w, h end,
    getWidth = function() return w end, getHeight = function() return h end,
    setFilter = function() end }
end

local closed = { count = 0 }
local function newPuzzle(puzzleId)
  input.pressed = {}
  closed.count, closed.solved = 0, nil
  return UnownPuzzle.new({ input = input, data = { gen2MenuGfx = {
    unownPuzzle = require("tests.fixture_data.gen2_unown_puzzle_gfx_s7_f2") } } }, {
    puzzle = puzzleId or 0,
    random = scripted({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }),
    onClose = function(solved)
      closed.count = closed.count + 1
      closed.solved = solved
    end,
  })
end

local function press(screen, button)
  input.pressed = { [button] = true }
  screen:update(1 / 60)
  input.pressed = {}
end

local screen = newPuzzle(0)

-- _CGB_UnownPuzzle (engine/gfx/cgb_layouts.asm) fills all four BG palettes from
-- PalPacket_UnownPuzzle, which is PREDEFPAL_UNOWN_PUZZLE four times, and then
-- WipeAttrmap puts every tile on palette 0: the board is BROWN, and the `ld a,
-- $e4` after it is the identity reorder of that palette rather than a grey
-- ramp.
local function rgb(colors, index)
  local c = colors and colors[index]
  return c and (c[1] .. "," .. c[2] .. "," .. c[3]) or "nil"
end
check("BG colour 1 is the tan of PREDEFPAL_UNOWN_PUZZLE",
  rgb(screen.palette, 2), "197,165,90")
check("BG colour 2 is its dark brown", rgb(screen.palette, 3), "148,107,90")
check("BG colour 0 is white", rgb(screen.palette, 1), "255,255,255")
check("BG colour 3 is black", rgb(screen.palette, 4), "0,0,0")
-- wOBPals1 colour 0 is overwritten with `palred 31`, and `ld a, $24` reorders
-- OBJ pal 0 to entries 0, 1, 2, 0, so both of the cursor sheet's colours are it.
check("OBJ colour 0 is pure red", rgb(screen.cursorPalette, 1), "255,0,0")
check("and colour 3 is the same red", rgb(screen.cursorPalette, 4), "255,0,0")
check("the palettes are menu_gfx.lua's",
  screen.palette == require("tests.fixture_data.gen2_unown_puzzle_gfx_s7_f2").palette, true)
check("a menu_gfx.lua without unownPuzzle is an error",
  pcall(UnownPuzzle.new, { input = input, data = { gen2MenuGfx = {} } }, {}), false)
local noChrome = {}
for key, value in pairs(require("tests.fixture_data.gen2_unown_puzzle_gfx_s7_f2")) do
  noChrome[key] = value
end
noChrome.chrome = nil
check("and so is one without the caption tiles",
  pcall(UnownPuzzle.new, { input = input,
    data = { gen2MenuGfx = { unownPuzzle = noChrome } } }, {}), false)

check("a new board starts on cell 0", screen.cursor, 0)
check("nothing is held", screen.holding, false)
check("and it is not solved", screen.solved, false)

-- A on an occupied cell picks the panel up; a second A on the same cell is
-- refused, because the cell it came from is now empty and A with a panel held
-- only ever puts it DOWN.
local piece = screen:occupant(0)
press(screen, "a")
check("A picks the panel up", screen.holding, true)
check("and the panel is the one that was there", screen.held, piece)
check("leaving the cell empty", screen:occupant(0), 0)
press(screen, "a")
check("A puts it straight back", screen.holding, false)
check("and the cell holds it again", screen:occupant(0), piece)

-- The cursor moves, and a refused move does not.
press(screen, "right")
check("right steps along row 0", screen.cursor, 1)
press(screen, "up")
check("up from row 0 does nothing", screen.cursor, 1)

-- START quits with wSolvedUnownPuzzle still clear.
press(screen, "start")
check("START closes the screen", closed.count, 1)
check("reporting unsolved", closed.solved, false)
press(screen, "start")
check("and it only closes once", closed.count, 1)

-- The solve: put the board one move from done and make that move.
screen = newPuzzle(2)
check("the picture id is kept", screen.puzzle, 2)
for cell = 1, UnownPuzzle.CELLS do
  screen.pieces[cell] = UnownPuzzle.SOLVED[cell]
end
-- Lift panel 16 out of its home and drop it on the ring, which is the board
-- one A-press from solved once it is picked back up.
local home = pc(4, 4)
screen.pieces[home + 1] = 0
screen.pieces[pc(0, 0) + 1] = 16
screen.cursor = pc(0, 0)
press(screen, "a")
check("the stray panel is in hand", screen.held, 16)
screen.cursor = home
press(screen, "a")
check("dropping it home solves the puzzle", screen.solved, true)
check("the screen holds on the fanfare", screen.waiting, true)
check("and has not closed yet", closed.count, 0)
press(screen, "a")
check("A after the fanfare closes it", closed.count, 1)
check("reporting solved", closed.solved, true)

-- WaitPlaySFX (home/audio.asm:220)
do
  local Sound = require("src.core.Sound")
  local realPlay, realWait = Sound.play, Sound.waitSfxDone
  local log = {}
  Sound.play = function(_data, name) log[#log + 1] = name end
  Sound.waitSfxDone = function() log[#log + 1] = "wait" end

  screen = newPuzzle(2)
  for cell = 1, UnownPuzzle.CELLS do
    screen.pieces[cell] = UnownPuzzle.SOLVED[cell]
  end
  screen.pieces[pc(4, 4) + 1] = 0
  screen.pieces[pc(0, 0) + 1] = 16
  screen.cursor = pc(0, 0)
  press(screen, "a")
  screen.cursor = pc(4, 4)
  press(screen, "a")

  check("the solve drains the channels before the fanfare",
    table.concat(log, ","),
    "wait,Sfx_MegaKick,wait,Sfx_PlacePuzzlePieceDown,wait,Sfx_1stPlace")
  check("and the board really is solved", screen.solved, true)

  -- UnownPuzzle_InvalidAction (unown_puzzle.asm:339)
  log = {}
  screen = newPuzzle(2)
  screen.pieces[pc(0, 0) + 1] = 0
  screen.cursor = pc(0, 0)
  press(screen, "a")
  check("a refused click is not stopped on the frame it starts",
    table.concat(log, ","), "wait,Sfx_Wrong")

  log = {}
  screen.pieces[pc(0, 0) + 1] = 16
  press(screen, "a")
  press(screen, "right")
  check("nor is the pickup, and the move click drains before it",
    table.concat(log, ","), "wait,Sfx_MegaKick,wait,Sfx_MovePuzzlePiece")

  Sound.play, Sound.waitSfxDone = realPlay, realWait
end

-- A panel cannot be dropped on an occupied cell.
screen = newPuzzle(0)
screen.cursor = 0
press(screen, "a")
check("a panel is held", screen.holding, true)
local occupied = nil
for cell = 0, UnownPuzzle.CELLS - 1 do
  if screen:occupant(cell) ~= 0 then occupied = cell break end
end
screen.cursor = occupied
press(screen, "a")
check("dropping onto an occupied cell is refused", screen.holding, true)

screen = newPuzzle(0)
local caption = {}
local realDraw = screen.chrome.draw
screen.chrome.draw = function(sheet, tile, tx, ty)
  if ty == 16 then caption[#caption + 1] = tile end
  return realDraw(sheet, tile, tx, ty)
end
local drewOk = pcall(function() screen:drawPanel() end)
check("the board draws", drewOk, true)
check("START>CANCEL is the ten caption tiles, last over the box",
  table.concat(caption, ",", #caption - 9), "246,247,248,249,250,251,252,253,254,255")
screen.chrome.draw = realDraw
screen.holding = true
screen.held = 4
drewOk = pcall(function() screen:drawPanel() end)
check("and so does one with a panel in hand", drewOk, true)
screen.holding = false
screen.solved = true
drewOk = pcall(function() screen:drawPanel() end)
check("and so does a solved one", drewOk, true)
screen.solved = false
screen.chrome.loaded = false
check("a chrome sheet that will not load is an error, not font text",
  pcall(function() screen:drawPanel() end), false)
screen = newPuzzle(0)
check("a tile the chrome sheet does not hold is an error, not a filled square",
  pcall(screen.drawTile, screen, 0x10, 0, 0), false)

local function gfxWith(key, value)
  local gfx = {}
  for k, v in pairs(require("tests.fixture_data.gen2_unown_puzzle_gfx_s7_f2")) do gfx[k] = v end
  gfx[key] = value
  return UnownPuzzle.new({ input = input, data = { gen2MenuGfx = { unownPuzzle = gfx } } },
    { puzzle = 0 })
end
check("a picture that will not load is an error, not numbered panels",
  pcall(gfxWith, "pictures", { "unloadable_kabuto.png" }), false)
check("a cache without the pictures is an error", pcall(gfxWith, "pictures", nil), false)
check("a cursor sheet that will not load is an error, not a drawn square",
  pcall(gfxWith, "cursor", "unloadable_cursor.png"), false)

-- ================================================================ the special
--
-- `setval UNOWNPUZZLE_* / special UnownPuzzle / iftrue` -- the id goes IN
-- through wScriptVar and the answer comes back out through it.
local Vm = require("src.script.gen2.Vm")
local opened = {}
local vm = Vm.new({}, {}, {}, {
  specialOrder = { [42] = "UnownPuzzle" },
  specials = {
    unownPuzzle = function(puzzleId, done)
      opened[#opened + 1] = puzzleId
      done(opened.answer)
    end,
  },
})
vm.scriptVar = 2
vm:runSpecial(41)
check("the special reads the picture id out of wScriptVar", opened[1], 2)
check("and an unsolved puzzle answers 0", vm.scriptVar, 0)
opened.answer = true
vm.scriptVar = 3
vm:runSpecial(41)
check("Ho-Oh's id reaches the screen", opened[2], 3)
check("and a solved puzzle answers 1", vm.scriptVar, 1)

-- A VM with no hook at all still answers, rather than leaving a stale
-- wScriptVar for the `iftrue` two commands later.
local bare = Vm.new({}, {}, {},
  { specialOrder = { [42] = "UnownPuzzle" }, specials = {} })
bare.scriptVar = 3
bare:runSpecial(41)
check("no hook answers unsolved", bare.scriptVar, 0)

-- UnownPuzzle is no longer a stub.
local Specials = require("src.script.gen2.Specials")
check("UnownPuzzle has a handler", Specials.HANDLERS.UnownPuzzle ~= nil, true)
check("and is not also stubbed", Specials.STUBS.UnownPuzzle, nil)

-- The screen goes through the registry, like every other Gold screen.
local registered = false
for _, id in ipairs(Screens.GEN2_IDS) do
  if id == "Gen2UnownPuzzle" then registered = true end
end
check("Gen2UnownPuzzle is a screen id", registered, true)

-- ================================================= Crystal's flag skew (#1834)
--
-- pokecrystal constants/engine_flags.asm:25 ENGINE_MOBILE_SYSTEM shifts the
-- unlock flags to 43-46 (:57-60); pokegold keeps 42-45 (:56-59).
do
  local World = require("src.world.gen2.World")
  local EngineFlagsFixture = require("tests.fixture_data.gen2_engine_flags")
  local function stubWorld(engineFlags)
    return setmetatable({
      game = { save = { engineFlags = engineFlags } },
    }, { __index = World })
  end

  EngineFlagsFixture.bind("crystal")
  local rawCrystal = { [43] = true, [44] = true, [45] = true, [46] = true }
  local resolved = Unown.unlockedLetters(stubWorld(rawCrystal):unownUnlockFlags())
  check("Crystal's 43-46 unlock all 26", #resolved, 26)
  check("A included", resolved[1], 1)

  math.randomseed(1)
  local function roll()
    return { attack = math.random(0, 15), defense = math.random(0, 15),
      speed = math.random(0, 15), special = math.random(0, 15) }
  end
  local seen = {}
  for _ = 1, 4000 do
    seen[Unown.letterFromDVs(Unown.wildDVs(rawCrystal, roll))] = true
  end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  check("Crystal's flags roll all 26", count, 26)

  local kabuto = Unown.unlockedLetters(stubWorld({ [43] = true }):unownUnlockFlags())
  check("Crystal flag 43 is A-K", #kabuto, 11)
  check("starting at A", kabuto[1], 1)

  check("Crystal flag 42 unlocks nothing", Unown.anyUnlocked(
    stubWorld({ [42] = true }):unownUnlockFlags()), false)

  EngineFlagsFixture.bind("gold")
  local gold = Unown.unlockedLetters(stubWorld({ [42] = true }):unownUnlockFlags())
  check("Gold flag 42 stays A-K", #gold, 11)
end

-- ============================================= the letters table's keys (#1834)
--
-- RomExtractorGen2 keys `letters` by "A".."Z"; monLetter answers a number, so
-- the anim lookup must convert or every letter animates as A.
do
  local BattleState = require("src.ui.gen2.BattleState")
  local SummaryMenu = require("src.ui.gen2.SummaryMenu")
  local animA = { sheet = "sheet-a", tiles = 5 }
  local animI = { sheet = "sheet-i", tiles = 5 }
  data.pokemon.UNOWN.anim = animA
  data.pokemon.UNOWN.letters.I.anim = animI
  local screen = { pokemon = data.pokemon }
  check("animData picks the mon's own letter",
    BattleState.animData(screen, unown), animI)
  local plain = Mon.new(data, "UNOWN", 5, { dvs = Unown.dvsForLetter(2) })
  check("a letter with no anim row falls back to the species'",
    BattleState.animData(screen, plain), animA)
  -- StatsScreen_PlaceFrontpic reads the same letter row
  -- (../pokecrystal/engine/pokemon/stats_screen.asm:889-901)
  local asked
  local summary = { mon = unown, pokemon = data.pokemon,
    picImage = function(_, sheet) asked = sheet return nil end }
  SummaryMenu.startPicAnim(summary)
  check("the summary menu reads the same letter row", asked, "sheet-i")
end

print(("gen2 unown: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an exit
-- here would take the whole tier down and silently skip every suite after it.
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
