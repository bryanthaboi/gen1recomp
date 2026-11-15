-- Parity test for Yellow's Pallet Town intro (Oak stops the player,
-- catches a wild Pikachu, walks them to the lab). Drives the real
-- onStep closure in data/scripts/story2.lua through the real
-- StateStack/OverworldState, with no mocked battle or overworld, up
-- through the point Oak's Pikachu catch is armed: covers two of the
-- four fixes on this branch -- Music_MuseumGuy staying off in
-- Red/Blue, and the 2-frame hold before the Pikachu battle handing
-- off to BattleTransition rather than a bare push.
--
-- Deliberately stops there rather than also driving the demo battle
-- to completion to assert Music_MuseumGuy fires in Yellow (the third
-- fix): that would mean re-deriving frame budgets for the battle
-- menu/bag/throw sequence tests/parity_J.lua already exercises, on
-- top of everything already driven here, for one more assertion --
-- more coupling to unrelated timing than the fix is worth. That side
-- is manually verified instead (see the PR description).
--
-- Sources: scripts/PalletTown.asm, engine/overworld/auto_movement.asm,
-- home/overworld.asm, engine/battle/core.asm (see the commits on this
-- branch for the exact citations).
--   luajit tests/parity_yellow_pallet_pikachu.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local YELLOW_PALLET = {
  _PalletTownOakComeWithMe = "OAK: A POKéMON can\nappear anytime in\vtall grass.\fYou need your own\nPOKéMON for your\vprotection.\vI know!\fHere, come with\nme!{DONE}",
  _PalletTownOakThatWasCloseText = "OAK: That was\nclose!\fWild POKéMON live\nin tall grass!{DONE}",
  _PalletTownOakWhewText = "OAK: Whew...{DONE}",
}
for k, v in pairs(YELLOW_PALLET) do Data.text[k] = Data.text[k] or v end

local S = require("tests.harness").suite("parity Yellow Pallet Town Pikachu")
local check, eq = S.check, S.eq

local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local Game = require("src.core.Game")
local StateStack = require("src.core.StateStack")
local OverworldState = require("src.world.OverworldController")
local BattleTransition = require("src.render.BattleTransition")
local TextBox = require("src.render.TextBox")
local Music = require("src.core.Music")
local mapScripts = require("data.scripts.init")

local pallet = mapScripts.get("PALLET_TOWN")
check(pallet and pallet.onStep, "PALLET_TOWN exposes onStep")

local oldVersion = GameVersion.get()
local prevGame = { data = Game.data, save = Game.save, stack = Game.stack,
                   input = Game.input, renderer = Game.renderer,
                   overworld = Game.overworld }

local function freshGame(mapX, mapY)
  Game.data = Data
  Game.save = SaveData.newGame(Data)
  Game.save.player.name = "RED"
  StateStack:init()
  Game.stack = StateStack
  local pressed = {}
  Game.input = {
    isDown = function() return false end,
    wasPressed = function(_, b) return pressed[b] or false end,
    step = function() end, state = {}, pressQueue = {},
  }
  Game.renderer = {
    beginWorldPass = function() end, endWorldPass = function() end,
    beginUIPass = function() end, endUIPass = function() end,
    worldViewSize = function() return 160, 144 end,
    setSGBZones = function() end,
  }
  -- OverworldState is a singleton and :enter does not clear the movement
  -- latches, so a scenario that runs after a few thousand other checks can
  -- inherit a half-finished script and never walk.  Reset them here: this
  -- suite asserts a frame budget, so it has to start from a known state.
  OverworldState.scriptMoves = {}
  OverworldState.pendingScripts = {}
  OverworldState.emote = nil
  OverworldState.engaging = false
  OverworldState.teleportOut = nil
  OverworldState.transitioning = nil
  OverworldState.wildEncounterGraceSteps = 0
  StateStack:push(OverworldState, "PALLET_TOWN", mapX, mapY, "up")
  Game.overworld = OverworldState
  return pressed
end

-- mash "a" whenever anything but the overworld is on top (dismisses
-- text boxes; scriptMove/hold/BattleTransition/BattleState's own
-- scripted-menu phases all ignore it)
local function pump(pressed, n)
  for _ = 1, n do
    pressed.a = Game.stack:top() ~= OverworldState
    Game.stack:update(1 / 60)
  end
end

local function mashUntil(pressed, cond, cap)
  for _ = 1, cap do
    if cond() then return true end
    pressed.a = Game.stack:top() ~= OverworldState
    Game.stack:update(1 / 60)
  end
  return false
end

-- Every scenario mutates the Game/GameVersion/StateStack singletons the
-- rest of the aggregate tests/run_tests.lua run depends on; a genuine
-- error partway through (plausible -- this drives real scriptMove,
-- pathfinding, TextBox paging and BattleState code, not test doubles)
-- must not skip the restore, or it cascades into every later suite in
-- the same process. StateStack:init() leaves it empty rather than
-- pointed at this scenario's pushed OverworldState/TextBox/
-- BattleTransition instances.
local function scenario(fn)
  local ok, err = pcall(fn)
  GameVersion.set(oldVersion)
  for k, v in pairs(prevGame) do Game[k] = v end
  StateStack:init()
  if not ok then error(err, 0) end
end

-- =====================================================================
-- (A) Red/Blue: MUSIC_MUSEUM_GUY must never play. Only "red" is driven
-- here -- story2.lua's onStep branches on GameVersion.isYellow() alone
-- and never calls isBlue(), so Red and Blue share this exact code path
-- and a separate Blue run would exercise nothing new. pokered's copy of
-- PalletMovementScript_OakMoveLeft only sets BIT_NO_MAP_MUSIC and never
-- calls PlayMusic -- MUSIC_MEET_PROF_OAK (started when Oak appears)
-- keeps running straight into the lab.
-- =====================================================================
scenario(function()
  -- The trigger tile is in Pallet's north grass, so the escort walk rolls for
  -- wild encounters as it goes.  Pin the stream: run standalone this suite got
  -- one draw sequence and run inside tests/run_tests.lua another, and one of
  -- them dropped a battle on top of the escort and ate the frame budget.
  math.randomseed(require("tests.harness").SEED)
  GameVersion.set("red")
  local pressed = freshGame(8, 2)
  local played = {}
  local origPlay = Music.play
  Music.play = function(data, song, ...)
    table.insert(played, song)
    return origPlay(data, song, ...)
  end
  local ok, err = pcall(function()
    local ow = OverworldState
    check(pallet.onStep(Game, ow, 8, 1) == true,
          "Red: onStep claims the trigger tile")
    -- HeyWaitDontGoOutText (auto) -> "!" bubble hold(50) -> Oak
    -- approaches -> "It's unsafe!" text -> escortToLab -> the walk to
    -- the lab door. 3000 frames (50s of game time) covers it; the
    -- negative Music_MuseumGuy checks below only mean something once
    -- the escort has actually finished, not merely started.
    pump(pressed, 3000)
    check(Game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB == true,
          "Red: the escort actually reaches the lab within the frame budget")
  end)
  Music.play = origPlay
  if not ok then error(err, 0) end
  local sawMuseumGuy = false
  for _, s in ipairs(played) do
    if s == "Music_MuseumGuy" then sawMuseumGuy = true end
  end
  check(not sawMuseumGuy, "Red/Blue: Music_MuseumGuy never plays for this escort")
  check(played[1] == "Music_MeetProfOak",
        "Red/Blue: Music_MeetProfOak is still the only cutscene cue played")
end)

-- =====================================================================
-- (B) Yellow: the turn-then-battle timing and the transition wipe.
-- =====================================================================
scenario(function()
  GameVersion.set("yellow")
  local pressed = freshGame(10, 1)
  local ok, err = pcall(function()
    local ow = OverworldState
    check(pallet.onStep(Game, ow, 10, 0) == true,
          "Yellow: onStep claims the north-exit tile")
    local heyWaitBox = Game.stack:top()
    check(getmetatable(heyWaitBox) == TextBox,
          "Yellow: onStep opens with a text box (HeyWaitDontGoOutText)")

    -- HeyWaitDontGoOutText (auto, ~20 frames) -> "!" bubble hold(50) ->
    -- Oak approaches (findPath(10,4,10,1): 3 steps) -> hold(6) -> the
    -- next real text box is ThatWasClose (button-dismissed, unlike the
    -- first).
    local sawThatWasClose = mashUntil(pressed, function()
      local top = Game.stack:top()
      return top ~= heyWaitBox and getmetatable(top) == TextBox
    end, 3000)
    check(sawThatWasClose, "Yellow: reaches the ThatWasClose text")

    local oak
    for _, n in ipairs(ow.npcs) do
      if n.def and n.def.name == "PALLETTOWN_OAK" then oak = n end
    end
    check(oak ~= nil, "Yellow: PALLETTOWN_OAK is spawned")

    -- dismiss ThatWasClose (a multi-page text: mash through the
    -- typewriter cadence and the page turn); oak.facing flips
    -- synchronously in the close callback (x == 10 -> "right"), then
    -- hold(2) starts
    local sawHold = mashUntil(pressed, function() return ow.emote ~= nil end, 2000)
    check(sawHold, "Yellow: ThatWasClose closes and the hold before battle arms")
    eq(oak and oak.facing, "right", "Oak turns to face the grass (x==10 -> right)")
    check(ow.emote ~= nil and ow.emote.frames == 2,
          "the hold before the battle is armed for exactly 2 frames")

    -- tick 1: 2 -> 1, battle not pushed yet
    Game.stack:update(1 / 60)
    check(getmetatable(Game.stack:top()) ~= BattleTransition,
          "1 frame in: the battle has not started yet")
    -- tick 2: 1 -> 0, the demo battle is pushed through the transition
    Game.stack:update(1 / 60)
    check(getmetatable(Game.stack:top()) == BattleTransition,
          "2 frames in: Oak's catch enters through BattleTransition, not a bare push")
  end)
  if not ok then error(err, 0) end
end)

S.finish()
