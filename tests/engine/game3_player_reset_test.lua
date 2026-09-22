-- Player.reset must apply the state it is asked to reset to.
--
-- A1 regression: `reset(x, y, facing)` never assigned Player.facing, so every
-- non-seamless Map.load / warp / fly / syncFromSession left the avatar facing
-- whatever direction the previous map ended on -- and `Player.syncSavePosition`
-- then wrote that stale facing back into the save.
--
-- (N-A2, the transient surf flags, is covered by the same suite below.)
--   luajit tests/engine/game3_player_reset_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Player = require("src.core.game3.player")

-- A1: the facing argument is applied.
Player.facing = "down"
Player.reset(4, 5, "up")
eq(Player.facing, "up", "Player.reset applies its facing argument")

-- An invalid direction must not corrupt the facing.
Player.facing = "left"
Player.reset(4, 5, "sideways")
eq(Player.facing, "left", "an invalid facing argument leaves the facing unchanged")

-- A nil argument keeps the current facing (reset(x, y) callers).
Player.facing = "right"
Player.reset(4, 5)
eq(Player.facing, "right", "a nil facing argument keeps the current facing")

-- N-A2: transient surf state must not survive a reset.  A warp or whiteout while
-- surfing otherwise leaves Player.surfing set, and Collision.canEnter then
-- treats water as walkable on land maps and reads every step as a dismount.
Player.surfing, Player.surfHopping, Player.dismounting = true, true, true
Player.reset(4, 5, "down")
check(not Player.surfing, "Player.reset clears surfing")
check(not Player.surfHopping, "Player.reset clears surfHopping")
check(not Player.dismounting, "Player.reset clears dismounting")

-- The ordinary movement state reset is unchanged.
Player.biking, Player.running, Player.jumping, Player.moving = true, true, true, true
Player.reset(6, 7, "left")
check(not Player.biking, "bike state is still cleared")
check(not Player.running, "run state is still cleared")
check(not Player.jumping, "jump state is still cleared")
check(not Player.moving, "movement is still cleared")

T.finish("game3_player_reset_test")
