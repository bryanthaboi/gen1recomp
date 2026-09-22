-- Parity: Rocket3 in the Hideout B4F engages on sight, and the LIFT KEY
-- still drops after a sight-triggered battle (#1814).
--
-- RocketHideout4TrainerHeader2 is `trainer EVENT_..., 1, ...`
-- (scripts/RocketHideoutB4F.asm:95-96) and the `trainer` macro stores arg 2
-- as `db \2 << 4` (macros/scripts/maps.asm:107-127), so CheckSpriteCanSeePlayer
-- (engine/overworld/trainer_sight.asm:257-262) engages him from one tile away
-- through SCRIPT_ROCKETHIDEOUTB4F_DEFAULT (asm:42, home/trainers.asm:129).
-- The port used to skip any trainer with a hand-ported talk script; only an
-- explicit `noSight` opt-out may do that now.  His LIFT KEY lives in
-- Rocket3AfterBattleText (asm:189-199), i.e. the next talk, so a sight battle
-- does not lose it.
--
-- Self-contained; run via `luajit tests/parity_rocket3_sight_bug1814.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity rocket3 sight")
local check, eq = S.check, S.eq

local MAP = "ROCKET_HIDEOUT_B4F"
local TEXT = "TEXT_ROCKETHIDEOUTB4F_ROCKET3"

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local headers = Data.trainer_headers
local h = headers.RocketHideoutB4F and headers.RocketHideoutB4F[4]
check(h ~= nil, "RocketHideoutB4F header 4 is extracted")
eq(h and h.range, 1, "Rocket3's view range is one tile")

local maps = Data.maps
local rocket3
for _, o in ipairs(maps[MAP].objects or {}) do
  if o.text == TEXT then rocket3 = o end
end
check(rocket3 ~= nil, "Rocket3 is object " .. TEXT)
eq(rocket3 and rocket3.index, 4, "he is object index 4, the header's row")
check(rocket3 and rocket3.trainerClass ~= nil, "and he is a trainer sprite")
eq(rocket3 and rocket3.movement, "STAY", "he holds his tile")
eq(rocket3 and rocket3.range, "DOWN", "facing down, so the sight line is below him")
eq(rocket3 and rocket3.x, 11, "standing at x 11")
eq(rocket3 and rocket3.y, 2, "standing at y 2")

-- the gate the fix uses: having a talk script is NOT an opt-out; only an
-- explicit noSight set is
local story3 = dofile("data/scripts/story3.lua")
local hideout = story3[MAP]
check(hideout ~= nil and hideout.talk[TEXT] ~= nil,
      "Rocket3 still has his hand-ported talk script")
check(hideout.noSight == nil or hideout.noSight[TEXT] ~= true,
      "and he is not opted out of CheckFightingMapTrainers")

-- the LIFT KEY half: after the battle -- however it started -- the next talk
-- reveals the ball
-- put the real module back at the bottom: the tier dofiles every parity file
-- into one process, so a stub left behind here breaks every later suite
local realTextBox = package.loaded["src.render.TextBox"]
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { text = text, done = done } end,
  soundOpts = function() return nil end,
  substitute = function(_, t) return t end,
}
local pushed
local game = {
  data = { text = { _RocketHideoutB4FRocket3AfterBattleText = "Oh no!" } },
  save = { flags = {} },
  stack = { push = function(_, box) pushed = box end },
}
local ow = {
  map = { id = MAP, def = { objects = {} } },
  npcs = {}, entities = {},
  trainerDefeated = function() return true end,
}
local finished = false
hideout.talk[TEXT](game, ow, { def = rocket3 }, function() finished = true end)
check(pushed ~= nil, "talking after the win prints the after-battle text")
if pushed and pushed.done then pushed.done() end
check(game.save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY == true,
      "EVENT_ROCKET_DROPPED_LIFT_KEY is set")
local toggles = game.save.objectToggles and game.save.objectToggles[MAP]
check(toggles and toggles.ROCKETHIDEOUTB4F_LIFT_KEY == true,
      "the LIFT KEY ball is shown")
check(finished, "and the talk hands control back")

package.loaded["src.render.TextBox"] = realTextBox

S.finish()
