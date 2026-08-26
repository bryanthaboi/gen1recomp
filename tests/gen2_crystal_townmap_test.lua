-- The wall map, the printed diploma and the memory game: the three specials
-- both Gen 2 carts carry that had no port half (engine/events/specials.asm:100
-- OverworldTownMap, :448 PrintDiploma, :207 UnusedMemoryGame).
--
-- OverworldTownMap has two callers.  TownMapScript
-- (engine/events/std_scripts.asm:145) is registered but no map jumpstd's it on
-- either cart; DecorationDesc_TownMapPoster
-- (engine/overworld/decorations.asm:1005) is the live one, and InitDecorations
-- (engine/overworld/decorations.asm:1, run from
-- engine/menus/intro_menu.asm:133) hangs DECO_TOWN_MAP on the bedroom wall at
-- new game, so a silent no-op here is a dead end in the room the player starts
-- in.
--   luajit tests/gen2_crystal_townmap_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal town map")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Events = require("src.world.gen2.Events")
local Pokegear = require("src.ui.gen2.Pokegear")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")

local H = Specials.HANDLERS

local function fakeInput()
  local pressed = {}
  return {
    press = function(_self, button) pressed[button] = true end,
    wasPressed = function(_self, button)
      if pressed[button] then
        pressed[button] = nil
        return true
      end
      return false
    end,
  }
end

-- landmarks.lua's shape.  ../pokecrystal/constants/landmark_constants.asm:34
-- inserts LANDMARK_BATTLE_TOWER, so every index from ROUTE_40 up is one higher
-- than pokegold/constants/landmark_constants.asm gives it; both index spaces
-- are built here because the two limit registers are read out of this table.
local function landmarkTable(rows)
  local out = { landmarks = {}, order = {} }
  for id, index in pairs(rows) do
    out.landmarks[id] = {
      id = id, index = index,
      name = id:gsub("^LANDMARK_", ""):gsub("_", " "), x = 8, y = 8,
    }
    out.order[index + 1] = id
  end
  return out
end

local GOLD_LANDMARKS = landmarkTable({
  LANDMARK_NEW_BARK_TOWN = 0x01,
  LANDMARK_ROUTE_29 = 0x02,
  LANDMARK_SILVER_CAVE = 0x2d,
  LANDMARK_PALLET_TOWN = 0x2e,
  LANDMARK_VICTORY_ROAD = 0x57,
  LANDMARK_ROUTE_28 = 0x5d,
  LANDMARK_FAST_SHIP = 0x5e,
})

local CRYSTAL_LANDMARKS = landmarkTable({
  LANDMARK_NEW_BARK_TOWN = 0x01,
  LANDMARK_ROUTE_29 = 0x02,
  LANDMARK_BATTLE_TOWER = 0x1d,
  LANDMARK_SILVER_CAVE = 0x2e,
  LANDMARK_PALLET_TOWN = 0x2f,
  LANDMARK_VICTORY_ROAD = 0x58,
  LANDMARK_ROUTE_28 = 0x5e,
  LANDMARK_FAST_SHIP = 0x5f,
})

local function townMapScreen(opts)
  opts = opts or {}
  local input = fakeInput()
  local save = opts.save or {}
  local popped = 0
  local game = {
    input = input,
    save = save,
    stack = { pop = function() popped = popped + 1 end },
  }
  local closed = 0
  local screen = Pokegear.new(game, {
    save = save,
    landmarks = opts.landmarks or CRYSTAL_LANDMARKS,
    currentLandmark = opts.currentLandmark or "LANDMARK_NEW_BARK_TOWN",
    townMap = true,
    onClose = function() closed = closed + 1 end,
  })
  return screen, input,
    function() return closed end, function() return popped end
end

-- ================================================= 1. the screen's own mode
--
-- _TownMap (engine/pokegear/pokegear.asm:1709) reuses PokegearMap for the art
-- and nothing else off the card: no strip, no ENGINE_MAP_CARD test.
do
  local screen = townMapScreen()
  eq(#screen.cards, 1, "the poster is one screen, not the card strip")
  eq(screen.mode, "card", "and it opens straight onto the map")
  eq(screen:card().id, "map", "on the MAP card's own art")
  eq(screen.fly, nil, "and it is not the fly picker")
end

-- The card gate is _FlyMap's absence, not the gear's: a player who has never
-- met the Guide Gent still reads the poster in their bedroom.
do
  local screen = townMapScreen({ save = { engineFlags = {} } })
  eq(#screen.cards, 1, "no ENGINE_MAP_CARD is needed to open it")
end

-- ================================================= 2. the joypad
--
-- `.loop` (engine/pokegear/pokegear.asm:1783): PAD_B returns, PAD_UP and
-- PAD_DOWN walk wTownMapCursorLandmark, and nothing else is read at all.
do
  local screen, input, closed, popped = townMapScreen()
  local first = CRYSTAL_LANDMARKS.landmarks.LANDMARK_NEW_BARK_TOWN.index
  local last = CRYSTAL_LANDMARKS.landmarks.LANDMARK_SILVER_CAVE.index
  eq(screen:mapCursorIndex(), first, "the cursor starts on the player's own")

  input:press("up")
  screen:update(0)
  eq(screen:mapCursorIndex(), first + 1, "UP steps to the next landmark")
  input:press("down")
  screen:update(0)
  eq(screen:mapCursorIndex(), first, "DOWN steps back")

  -- `cp e / jr nz, .wrap_around_down`: only the first landmark wraps.
  input:press("down")
  screen:update(0)
  eq(screen:mapCursorIndex(), last, "and wraps off the first onto the last")
  -- `cp d / jr c, .wrap_around_up`.
  input:press("up")
  screen:update(0)
  eq(screen:mapCursorIndex(), first, "and off the last back onto the first")

  -- Left, right and A are never read by _TownMap's loop.
  local held = screen:mapCursorIndex()
  for _, button in ipairs({ "left", "right", "a", "start", "select" }) do
    input:press(button)
    screen:update(0)
  end
  eq(screen:mapCursorIndex(), held, "no other button moves the cursor")
  eq(closed(), 0, "and none of them leaves the map")

  input:press("b")
  screen:update(0)
  eq(closed(), 1, "B returns from the map")
  eq(popped(), 1, "and the screen the special pushed comes back off the stack")

  -- The pop already happened; a second B must not take the overworld with it.
  input:press("b")
  screen:update(0)
  eq(popped(), 1, "a second B pops nothing")
end

-- ================================================= 3. the limit registers
--
-- `ld d, KANTO_LANDMARK - 1 / ld e, 1` for Johto and
-- TownMap_GetKantoLandmarkLimits (engine/pokegear/pokegear.asm:714) for Kanto.
-- Both are LANDMARK indices, and Crystal's are not Gold's.
do
  local crystal = townMapScreen({ landmarks = CRYSTAL_LANDMARKS })
  local last, first = crystal:cursorLimits()
  eq(first, 0x01, "Johto's e is NEW BARK TOWN either way round")
  eq(last, 0x2e, "and its d is Crystal's own SILVER CAVE, not Gold's $2d")

  local gold = townMapScreen({ landmarks = GOLD_LANDMARKS })
  local goldLast = gold:cursorLimits()
  eq(goldLast, 0x2d, "a Gold landmark table still answers $2d")

  -- A dataset with no landmark records at all keeps the pokegold numbers.
  local bare = townMapScreen({ landmarks = { landmarks = {}, order = {} } })
  local bareLast, bareFirst = bare:cursorLimits()
  eq(bareLast, 0x2d, "and so does a dataset with no records")
  eq(bareFirst, 0x01, "with NEW BARK TOWN still the floor")
end

-- `cp KANTO_LANDMARK` is the region test, and KANTO_LANDMARK is PALLET_TOWN's
-- own index: $2e on Gold, $2f on Crystal.  The byte $2e therefore reads as
-- Kanto on one cart and Johto (SILVER CAVE) on the other.
do
  local silver = townMapScreen({
    landmarks = CRYSTAL_LANDMARKS, currentLandmark = "LANDMARK_SILVER_CAVE",
  })
  eq(silver:region(), "johto", "Crystal's $2e is SILVER CAVE, so Johto")
  local pallet = townMapScreen({
    landmarks = CRYSTAL_LANDMARKS, currentLandmark = "LANDMARK_PALLET_TOWN",
  })
  eq(pallet:region(), "kanto", "and its $2f is PALLET TOWN, so Kanto")
  local goldPallet = townMapScreen({
    landmarks = GOLD_LANDMARKS, currentLandmark = "LANDMARK_PALLET_TOWN",
  })
  eq(goldPallet:region(), "kanto", "Gold's PALLET TOWN is Kanto at $2e")
  -- LANDMARK_FAST_SHIP sits past every Kanto landmark and is still Johto.
  local ship = townMapScreen({
    landmarks = CRYSTAL_LANDMARKS, currentLandmark = "LANDMARK_FAST_SHIP",
  })
  eq(ship:region(), "johto", "and the S.S. Aqua stays Johto at $5f")
end

-- Kanto's pair, with and without the Hall of Fame on the record.
do
  local before = townMapScreen({
    landmarks = CRYSTAL_LANDMARKS, currentLandmark = "LANDMARK_PALLET_TOWN",
    save = { flags = {} },
  })
  local lastB, firstB = before:cursorLimits()
  eq(firstB, 0x58, "before the Hall of Fame Kanto starts at VICTORY ROAD")
  eq(lastB, 0x5e, "and ends at ROUTE 28")
  local after = townMapScreen({
    landmarks = CRYSTAL_LANDMARKS, currentLandmark = "LANDMARK_PALLET_TOWN",
    save = { flags = { HALL_OF_FAME = true } },
  })
  local _, firstA = after:cursorLimits()
  eq(firstA, 0x2f, "and afterwards the whole region opens at PALLET TOWN")
end

-- ================================================= 4. the tilemap frame
--
-- _TownMap.InitTilemap (engine/pokegear/pokegear.asm:1843): the rule turns down
-- at (7,0) and runs back out along row 2, which is what boxes the name plate
-- into the top right corner with no card strip above it.
do
  local screen = townMapScreen()
  local laid = {}
  screen.tile = function(_self, id, tx, ty)
    laid[tx .. "," .. ty] = id
  end
  screen:drawTownMapRule()

  eq(laid["0,0"], 0x06, "$06 caps the rule at (0,0)")
  local run = true
  for x = 1, 6 do run = run and laid[x .. ",0"] == 0x07 end
  check(run, "$07 runs (1,0) to (6,0), the `ld bc, 6` ByteFill")
  eq(laid["7,0"], 0x17, "$17 turns it down at (7,0)")
  eq(laid["7,1"], 0x16, "$16 carries it through (7,1)")
  eq(laid["7,2"], 0x26, "$26 turns it back out at (7,2)")
  local tail = true
  for x = 8, 18 do tail = tail and laid[x .. ",2"] == 0x07 end
  check(tail, "$07 runs (8,2) to (18,2), the NAME_LENGTH ByteFill")
  eq(laid["19,2"], 0x17, "$17 caps it at (19,2)")
  eq(laid["8,1"], nil, "and nothing is laid inside the name plate")

  -- The MAP card's own rule is the other shape: a full-width bar under the
  -- two-row card strip.  The poster must not draw that.
  local card = Pokegear.new({ input = fakeInput(), save = {} }, {
    save = { pokegearFlags = { map = true } },
    landmarks = CRYSTAL_LANDMARKS,
    currentLandmark = "LANDMARK_NEW_BARK_TOWN",
  })
  eq(card.townMap, nil, "the POKeGEAR card is not in town-map mode")
  check(#card.cards > 1, "and it keeps its card strip")
end

-- Drawing with no town-map art at all: a crash check on the unstyled fallback.
do
  local screen = townMapScreen()
  check(not screen:styled(), "this harness has no gear sheet")
  check(pcall(function() screen:draw() end), "the poster still draws")
end

-- ================================================= 5. the specials
--
-- World:specialHooks, stubbed down to what these two reach for.
local function newHooks(opts)
  opts = opts or {}
  local log = { pushed = {}, diploma = 0 }
  local hooks = {
    log = log,
    save = function() return opts.save or {} end,
    data = function() return {} end,
    party = function() return {} end,
  }
  if not opts.noScreens then
    hooks.pushScreen = function(id, screenOpts)
      log.pushed[#log.pushed + 1] = { id = id, opts = screenOpts }
      if opts.pushFails then return false end
      log.pending = screenOpts.onClose
      if not opts.hold and screenOpts.onClose then screenOpts.onClose() end
      return true
    end
    hooks.showDiploma = function(onDone)
      log.diploma = log.diploma + 1
      log.pending = onDone
      if not opts.hold and onDone then onDone() end
    end
  end
  return hooks
end

local function newVm(hooks, scriptVar)
  local vm = Vm.new({}, {}, Events.new(), { specials = hooks })
  vm.showTextFn = function() end
  vm.scriptVar = scriptVar or 0
  return vm
end

-- Run a handler to its first park (or to the end), the way the VM runs it.
local function run(vm, handler)
  local co = coroutine.create(function() handler(vm) end)
  vm.co = co
  local ok, req = coroutine.resume(co)
  if not ok then error(req, 0) end
  return co, req
end

-- ---- OverworldTownMap ------------------------------------------------------

check(H.OverworldTownMap ~= nil, "OverworldTownMap has a handler")
eq(Specials.STUBS.OverworldTownMap, nil, "and is no longer a stub")
check(Specials.SUPERSEDED_STUBS.OverworldTownMap ~= nil,
  "its old reason moved to the superseded ledger")

do
  local hooks = newHooks()
  local vm = newVm(hooks, 7)
  local co = run(vm, H.OverworldTownMap)
  eq(coroutine.status(co), "dead", "an answering screen runs it straight out")
  eq(#hooks.log.pushed, 1, "one screen is pushed")
  eq(hooks.log.pushed[1].id, "Gen2Pokegear", "which is the POKeGEAR's own map")
  eq(hooks.log.pushed[1].opts.townMap, true, "in _TownMap's chrome-free mode")
  -- FadeToMenu / farcall _TownMap / ExitAllMenus writes no wScriptVar, and the
  -- callers' next op is a bare `closetext`.
  eq(vm.scriptVar, 7, "and wScriptVar is left exactly as `special` found it")
end

-- The block is real: the coroutine parks until the screen answers.
do
  local hooks = newHooks({ hold = true })
  local vm = newVm(hooks, 0)
  local co = run(vm, H.OverworldTownMap)
  eq(coroutine.status(co), "suspended", "the script waits on the map")
  hooks.log.pending()
  eq(coroutine.status(co), "dead", "and only B off the map resumes it")
end

-- A run with no screen to push (a headless probe) must still not fall through
-- into the next command with a stale wScriptVar.
do
  local hooks = newHooks({ pushFails = true })
  local vm = newVm(hooks, 3)
  local co = run(vm, H.OverworldTownMap)
  eq(coroutine.status(co), "dead", "a refused push does not hang the script")
  eq(vm.scriptVar, 3, "and still leaves wScriptVar alone")
end
do
  local hooks = newHooks({ noScreens = true })
  local vm = newVm(hooks, 3)
  local co = run(vm, H.OverworldTownMap)
  eq(coroutine.status(co), "dead", "and neither does no pushScreen hook")
  eq(vm.scriptVar, 3, "with wScriptVar untouched")
end

-- ---- PrintDiploma ----------------------------------------------------------

check(H.PrintDiploma ~= nil, "PrintDiploma has a handler")
eq(Specials.STUBS.PrintDiploma, nil, "and is no longer a stub")
check(Specials.SUPERSEDED_STUBS.PrintDiploma ~= nil,
  "its printer reason moved to the superseded ledger")

do
  local hooks = newHooks()
  local vm = newVm(hooks, 5)
  local co = run(vm, H.PrintDiploma)
  eq(coroutine.status(co), "dead", "the page runs out")
  eq(hooks.log.diploma, 1, "PlaceDiplomaOnScreen is the routine's first act")
  eq(vm.scriptVar, 5, "and _PrintDiploma writes no wScriptVar either")
end

do
  local hooks = newHooks({ hold = true })
  local vm = newVm(hooks, 0)
  local co = run(vm, H.PrintDiploma)
  eq(coroutine.status(co), "suspended", "the script waits on the page")
  hooks.log.pending()
  eq(coroutine.status(co), "dead", "and the dismissal resumes it")
end

do
  local hooks = newHooks({ noScreens = true })
  local vm = newVm(hooks, 4)
  local co = run(vm, H.PrintDiploma)
  eq(coroutine.status(co), "dead", "no diploma hook is not a hang")
  eq(vm.scriptVar, 4, "and wScriptVar survives")
end

-- ---- UnusedMemoryGame ------------------------------------------------------
--
-- DELIBERATELY UNREACHABLE, and not a Crystal gap: `add_special
-- UnusedMemoryGame ; unused` is the row in BOTH carts
-- (pokegold data/events/special_pointers.asm:63,
-- ../pokecrystal/data/events/special_pointers.asm:58) and no script bytecode
-- in either ROM points at it.  _MemoryGame (engine/games/memory_game.asm) is a
-- 590-line Game Corner screen with its own board, cursor sprite anim and coin
-- payout, so porting it would be a whole new screen reachable by nobody.
-- UnusedDummySpecial next to it is a bare `ret` and IS ported, because that
-- costs one line; this one is not, and stays a stub with its reason recorded.
check(Specials.STUBS.UnusedMemoryGame ~= nil,
  "UnusedMemoryGame stays a stub: no cart script reaches it")
check(type(Specials.STUB_REASONS.UnusedMemoryGame) == "string",
  "and it still says why")
-- engine/events/specials.asm:207 is CheckCoinsAndCoinCase then
-- StartGameCornerGame, neither of which writes wScriptVar.
do
  local vm = newVm(newHooks(), 9)
  Specials.STUBS.UnusedMemoryGame(vm)
  eq(vm.scriptVar, 9, "and leaves wScriptVar alone, as the routine does")
end

S.finish()
