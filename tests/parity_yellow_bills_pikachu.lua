-- Yellow starts Bill's House with Pikachu's confused reaction.  The map
-- script owns that one-shot, while PikachuFollower owns the movement.

package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("parity Yellow Bill's Pikachu")
local check = S.check

local entered = 0
local originalFollower = package.loaded["src.world.PikachuFollower"]
package.loaded["src.world.PikachuFollower"] = {
  onBillsHouseEnter = function()
    entered = entered + 1
  end,
}

local story = dofile("data/scripts/story.lua")
local game = { save = { flags = {} } }
story.BILLS_HOUSE.onEnter(game, {})
check(entered == 1,
  "entering Bill's House before meeting Bill starts Pikachu's reaction")

entered = 0
game.save.flags.EVENT_MET_BILL_2 = true
story.BILLS_HOUSE.onEnter(game, {})
check(entered == 0,
  "Pikachu's Bill reaction does not replay after Bill is met")

package.loaded["src.world.PikachuFollower"] = originalFollower

local GameVersion = require("src.core.GameVersion")
local PikachuFollower = require("src.world.PikachuFollower")
GameVersion.set("yellow")

local npc = {
  pikachuFollower = true, cellX = 3, cellY = 8, px = 48, py = 128,
  facing = "up",
  -- pokeyellow engine/pikachu/pikachu_follow.asm:26
  passable = true,
}
local Sound = require("src.core.Sound")
local realPikaCry = Sound.playPikaCry
local cry
Sound.playPikaCry = function(_, index) cry = index return true end

local moves = {}
local yellowGame = {
  save = { flags = {} },
  data = {
    pokemon = { PIKACHU = { spriteFront = "pikachu.png" } },
    field = { emotionBubbles = {
      bubbles = {
        { name = "QUESTION_BUBBLE" }, { name = "EXCLAMATION_BUBBLE" },
      },
    } },
  },
}
local ow = {
  map = { id = "BILLS_HOUSE" }, npcs = { npc }, entities = { npc },
  player = { cellX = 3, cellY = 7 },
  scriptMove = function(_, entity, dir, tiles, onDone)
    moves[#moves + 1] = { entity = entity, dir = dir, tiles = tiles,
                           onDone = onDone }
  end,
}

PikachuFollower.onBillsHouseEnter(yellowGame, ow)
check(ow.pikachuBillsScene and #moves == 1
      and moves[1].entity == npc and moves[1].dir == "right"
      and moves[1].tiles == 3,
  "Bill's House entry parks Pikachu and walks it to Bill")
moves[1].onDone()
check(#moves == 2 and moves[2].dir == "up" and moves[2].tiles == 1,
  "Pikachu finishes its cartridge entry route beside Bill")
moves[2].onDone()
check(ow.emote and ow.emote.bubble == 1 and ow.emote.frames == 60
      and not ow.emote.pikaPic,
  "Pikachu shows its confused reaction after reaching Bill")
-- emotion 23 -- engine/pikachu/pikachu_emotions.asm:14
check(npc.stepFrames == 16,
  "the scripted walk runs at the Pikachu movement step length")
ow.emote.onDone()
check(ow.emote and ow.emote.pikaPic and ow.emote.frames > 0
      and not ow.emote.skippable,
  "and the bubble hands off to the unskippable emotion animation")

-- BillsHouseScript3 seeds hl with ..._EnterCellSeparatorDown and only swaps
-- in ..._EnterCellSeparatorNotDown on the facing-down fallthrough, so the
-- table names are inverted relative to the branch that picks them: facing
-- down takes the five-step detour, every other facing walks straight up
-- (pokeyellow scripts/BillsHouse.asm:100-133) (#455).
ow.player.facing = "down"
PikachuFollower.onBillEnteredMachine(yellowGame, ow)
check(#moves == 3 and moves[3].dir == "up" and moves[3].tiles == 1,
  "facing down, Pikachu starts the long way round the cell separator")
moves[3].onDone()
check(#moves == 4 and moves[4].dir == "left" and moves[4].tiles == 1,
  "the detour steps aside before climbing")
moves[4].onDone()
check(#moves == 5 and moves[5].dir == "up" and moves[5].tiles == 2,
  "the detour climbs past the separator")
moves[5].onDone()
check(#moves == 6 and moves[6].dir == "right" and moves[6].tiles == 1,
  "the detour steps back in beside it")
moves[6].onDone()
-- InitializePikachuTextID -- scripts/BillsHouse.asm:100
check(ow.emote and ow.emote.bubble == false and ow.emote.pikaPic
      and npc.facing == "up",
  "Pikachu looks up at the cell separator with no bubble, just the emotion")

-- the other branch: any non-down facing takes the straight three-step route
local before = #moves
ow.player.facing = "up"
PikachuFollower.onBillEnteredMachine(yellowGame, ow)
check(#moves == before + 1 and moves[before + 1].dir == "up"
      and moves[before + 1].tiles == 3,
  "facing up, Pikachu walks straight to the cell separator")
moves[before + 1].onDone()

npc.goalX, npc.goalY = 9, 9
PikachuFollower.update(yellowGame, ow)
check(npc.goalX == 9 and npc.goalY == 9,
  "Pikachu stays parked in Bill's House during the scene")

PikachuFollower.onBillExitedMachine(yellowGame, ow)
check(ow.emote and ow.emote.bubble == 2 and ow.emote.frames == 60
      and npc.facing == "left",
  "Pikachu reacts when Bill comes back out")
ow.emote.onDone()
check(ow.emote and ow.emote.pikaPic,
  "and emotion 27 plays behind that bubble")

-- BillsHousePikachuWatchPlayer (scripts/BillsHouse_2.asm:133-156) is the
-- other side of BillsHouseScript2: it only runs while Pikachu still follows
-- the player, and TryApplyPikachuMovementData keys each table on
-- GetPikachuFacingDirectionAndReturnToE, which is Pikachu's position
-- relative to the player rather than its facing byte, so WatchPlayer1 wants
-- Pikachu above the player and WatchPlayer2 wants it level and east (#455).
local function placePikachu(cx, cy)
  npc.cellX, npc.cellY, npc.facing = cx, cy, "down"
end

ow.pikachuBillsScene = nil
moves = {}
placePikachu(ow.player.cellX, ow.player.cellY - 1)
PikachuFollower.onBillWalksAroundPlayer(yellowGame, ow)
check(#moves == 1 and moves[1].dir == "left" and moves[1].tiles == 1,
  "a Pikachu standing above the player steps aside for Bill's detour")
moves[1].onDone()
check(#moves == 2 and moves[2].dir == "down" and moves[2].tiles == 1,
  "the watch route drops clear of Bill's detour")
moves[2].onDone()
check(npc.facing == "right", "PIKAMOVEMENT_LOOK_RIGHT watches the player")

moves = {}
placePikachu(ow.player.cellX + 1, ow.player.cellY)
PikachuFollower.onBillWalksAroundPlayer(yellowGame, ow)
check(#moves == 1 and moves[1].dir == "up" and moves[1].tiles == 1,
  "level with and east of the player takes the longer WatchPlayer2 route")
moves[1].onDone()
check(#moves == 2 and moves[2].dir == "left" and moves[2].tiles == 2,
  "WatchPlayer2 crosses two cells west")
moves[2].onDone()
check(#moves == 3 and moves[3].dir == "down" and moves[3].tiles == 1,
  "WatchPlayer2 drops back level with the player")
moves[3].onDone()
check(npc.facing == "right", "WatchPlayer2 ends watching the player too")

-- below the player is SPRITE_FACING_DOWN and west of it is
-- SPRITE_FACING_LEFT, and neither call asks for those
moves = {}
placePikachu(ow.player.cellX, ow.player.cellY + 1)
PikachuFollower.onBillWalksAroundPlayer(yellowGame, ow)
check(#moves == 0, "a Pikachu trailing from the south has no watch route")

placePikachu(ow.player.cellX - 1, ow.player.cellY)
PikachuFollower.onBillWalksAroundPlayer(yellowGame, ow)
check(#moves == 0, "nor does one already standing west of the player")

-- ApplyPikachuMovementData_ finishes a table before the second
-- TryApplyPikachuMovementData reads the geometry again, but WatchPlayer1
-- lands on (playerX - 1, playerY), so WatchPlayer2 can never chain onto it
moves = {}
placePikachu(ow.player.cellX, ow.player.cellY - 1)
PikachuFollower.onBillWalksAroundPlayer(yellowGame, ow)
moves[1].onDone()
moves[2].onDone()
placePikachu(ow.player.cellX - 1, ow.player.cellY)
moves = {}
PikachuFollower.onBillWalksAroundPlayer(yellowGame, ow)
check(#moves == 0, "the two tables stay mutually exclusive by geometry")

-- the parked Pikachu of the confused beat is the not-following side of
-- CheckPikachuFollowingPlayer, so it never watches
ow.pikachuBillsScene = true
placePikachu(ow.player.cellX, ow.player.cellY - 1)
PikachuFollower.onBillWalksAroundPlayer(yellowGame, ow)
check(#moves == 0, "the parked Pikachu of the confused beat stays put")

-- BillsHouseScript0 skips the whole entry beat for a statused starter
-- (CheckPikachuStatusCondition, scripts/BillsHouse.asm:45-46)
ow.pikachuBillsScene = nil
yellowGame.save.pikachuMapScriptActive = nil
moves = {}
yellowGame.save.party = { { species = "PIKACHU", hp = 12, status = "PAR" } }
PikachuFollower.onBillsHouseEnter(yellowGame, ow)
check(not ow.pikachuBillsScene and #moves == 0,
  "a statused starter keeps following instead of walking over to Bill")
yellowGame.save.party = nil

-- of the starter-status and mood fallbacks -- scripts/BillsHouse_2.asm:88
npc.facePlayer = function(self) self.facing = "up" end
ow.player.facing = "down"

ow.pikachuBillsScene = true
PikachuFollower.talk(yellowGame, ow, npc)
check(cry == 19, "talking during the confused beat picks emotion 23")

ow.pikachuBillsScene = nil
PikachuFollower.talk(yellowGame, ow, npc)
check(cry == 26, "before Bill is met again it is emotion 32")

yellowGame.save.flags.EVENT_MET_BILL_2 = true
PikachuFollower.talk(yellowGame, ow, npc)
check(cry == 19, "and emotion 31 once EVENT_MET_BILL_2 is set")

yellowGame.save.party = { { species = "PIKACHU", hp = 12, status = "SLP" } }
PikachuFollower.talk(yellowGame, ow, npc)
check(cry == 19, "the map check still wins over a statused starter")
yellowGame.save.party = nil
yellowGame.save.flags.EVENT_MET_BILL_2 = nil
Sound.playPikaCry = realPikaCry

-- CheckPikachuFollowingPlayer is one flag, and CollisionCheckOnLand blocks
-- the player outright while it is set (home/overworld.asm:1238-1240).  All
-- three scenes that call DisablePikachuFollowingPlayer must park a solid
-- companion: scripts/BillsHouse_2.asm:121, PokemonFanClub.asm:60,
-- PewterPokecenter_2.asm:67.
for _, scene in ipairs({ "pikachuBillsScene", "pikachuFanClubScene",
                         "pikachuPewterSleepScene" }) do
  -- update() drops the follower once shouldSpawn goes false, so re-seed it
  ow.npcs, ow.entities = { npc }, { npc }
  npc.passable = true
  ow[scene] = true
  PikachuFollower.update(yellowGame, ow)
  check(not npc.passable, scene .. " parks a solid companion")
  ow[scene] = nil
  PikachuFollower.update(yellowGame, ow)
  check(npc.passable, scene .. " ending lets the player walk through again")
end

-- The other two states of CollisionCheckOnLand's Pikachu branch
-- (home/overworld.asm:1234-1252): B held walks straight through, and
-- wPikachuCollisionCounter is a soft 8-count bump seeded on a direction
-- change (:189) and cleared with no d-pad held (:130) or once a step
-- commits (:242).
local held = {}
yellowGame.input = { isDown = function(_, b) return held[b] == true end }
local cp = ow.player
cp.cellX, cp.cellY, cp.facing, cp.moving = 3, 7, "up", false
npc.cellX, npc.cellY = 3, 6

local function tick()
  ow.npcs, ow.entities = { npc }, { npc }
  PikachuFollower.update(yellowGame, ow)
end

held = {}
tick()
check(npc.passable and ow.pikachuCollisionCounter == 0,
  "no d-pad held clears the counter and the companion is walk-through")

held = { up = true }
tick()
check(ow.pikachuCollisionCounter == 8 and not npc.passable,
  "turning to a new direction seeds the 8-count bump")

local blocked = 0
for _ = 1, 8 do
  tick()
  if not npc.passable then blocked = blocked + 1 end
end
check(blocked == 7,
  "the bump blocks seven pushes and then yields, like dec [hl] / jr nz")
check(npc.passable and ow.pikachuCollisionCounter == 0,
  "the drained counter leaves the companion passable")

held = {}
tick()
held = { up = true }
tick()
check(ow.pikachuCollisionCounter == 0,
  "re-pressing the same direction after a release does not re-seed")

held = {}
tick()
held = { left = true }
tick()
check(ow.pikachuCollisionCounter == 8, "a new direction seeds again")
held = { left = true, b = true }
tick()
check(npc.passable, "holding B walks straight through the bump")

held = { left = true }
cp.moving = true
tick()
check(ow.pikachuCollisionCounter == 0 and npc.passable,
  "a committed step clears the counter")
cp.moving = false
held = {}
tick()
yellowGame.input = nil

-- CalculatePikachuPlacementCoords never leaves the companion on the
-- player's own cell (engine/pikachu/pikachu_follow.asm:59), so
-- BillsHousePikachuConfused's three STEP_RIGHTs start one cell east of the
-- door and land it directly below Bill.
local emergeMoves = {}
local emergeOw = {
  map = {
    id = "BILLS_HOUSE",
    def = { tileset = "INTERIOR" },
    inBounds = function() return true end,
    isWalkableCell = function() return true end,
    isWaterCell = function() return false end,
    cellTile = function() return 0 end,
  },
  npcs = {}, entities = {},
  player = { cellX = 2, cellY = 7, facing = "up" },
  scriptMove = function(_, entity, dir, tiles, onDone)
    emergeMoves[#emergeMoves + 1] = { dir = dir, tiles = tiles, onDone = onDone }
  end,
}
local emergeNpc = {
  pikachuFollower = true, cellX = 2, cellY = 7, px = 32, py = 112,
  facing = "up", passable = true,
}
emergeOw.npcs[1], emergeOw.entities[1] = emergeNpc, emergeNpc
yellowGame.save.flags = {}
yellowGame.save.pikachuMapScriptActive = nil
PikachuFollower.onBillsHouseEnter(yellowGame, emergeOw)
check(#emergeMoves == 1 and emergeMoves[1].dir == "right"
      and emergeMoves[1].tiles == 1,
  "a companion still stacked on the player steps off before the walk")
emergeNpc.cellX = 3
emergeMoves[1].onDone()
check(#emergeMoves == 2 and emergeMoves[2].dir == "right"
      and emergeMoves[2].tiles == 3,
  "then runs PikachuMovement_Confused's three STEP_RIGHTs")

GameVersion.set("red")
S.finish()
