package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local MB = require("src.core.game3.mb")
local Collision = require("src.core.game3.collision")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local session = { version = "emerald", map = "EM_SURF_TIMING", flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
package.loaded["src.core.game3.audio"] = { stopSurfMusic = function() end }
package.loaded["src.core.game3.bike"] = { rse = function() return nil end }
package.loaded["src.core.game3.field_effects"] = { leaveTallGrass = function() end, tallGrassAt = function() end }
package.loaded["src.core.game3.field"] = { locked = false }
package.loaded["src.core.game3.objects"] = { hasMap = function() return false end }
local Player = require("src.core.game3.player")
local Flags = require("src.core.game3.scripting.flags")
local game = { save = { position = {} } }
local function setup(version, surfing, underwater, shore)
  GameVersion.set(version)
  session.version = version
  local layout = { width = 4, height = 1, pair = "surf_timing" }
  function layout:collAt(x) return surfing and not (shore and x == 1) and 0x29 or 0 end
  function layout:elevAt(x) return surfing and not (shore and x == 1) and 1 or 3 end
  function layout:midAt(x) return x end
  function layout:collArray() return { self:collAt(0), self:collAt(1), self:collAt(2), self:collAt(3) } end
  Interaction.behaviors[layout.pair] = { [0] = MB.OCEAN_WATER, [1] = shore and MB.NORMAL or MB.OCEAN_WATER,
    [2] = MB.OCEAN_WATER, [3] = MB.OCEAN_WATER }
  Collision.bindMap(game, session.map, { midLayout = layout, pair = layout.pair, warps = {} })
  Player.reset(0, 0, "right")
  Player.surfing, Player.underwater = surfing, underwater
  Player.elevation, Player.currentElevation = surfing and 1 or 3, surfing and 1 or 3
end
local function measure(frames, label)
  local start = Player.px
  Player._onStepDone = function() end
  eq(Player.stepFrames, frames, label .. " selected duration")
  for frame = 1, frames do
    Player.tick(game)
    eq(Player.px - start, math.floor(frame * 16 / frames), label .. " pixel " .. frame)
    eq(Player.moving, frame < frames, label .. " completes exactly " .. frame)
  end
  eq(Player.cellX, 1, label .. " landing")
end
for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
  for _, b in ipairs({ false, true }) do
    for _, shoes in ipairs({ false, true }) do
      setup(version, true, false)
      local id = Flags.forVersion(version).IDS.FLAG_SYS_B_DASH
      Flags.setFlag(session, nil, id, shoes)
      local input = { isDown = function(_, key) return key == "right" or key == "b" and b end }
      Player.update(game, input)
      check(Player.moving, version .. " Surf input starts")
      measure(8, version .. " surf_B=" .. tostring(b) .. "_shoes=" .. tostring(shoes))
      check(Player.surfing and not Player.running, version .. " fast Surf keeps walking animation")
    end
  end
  setup(version, true, false)
  eq(Player.tryMove("right", game, false), "step", version .. " direct Surf step")
  measure(8, version .. " direct_surf_eight_frames")
  setup(version, false, false)
  eq(Player.tryMove("right", game, false), "step", version .. " foot walk")
  measure(16, version .. " foot_walk")
  setup(version, false, false)
  eq(Player.tryMove("right", game, true), "step", version .. " foot run")
  measure(8, version .. " foot_run")
  setup(version, true, false)
  check(Player.scriptStep("right", false), version .. " scripted Surf walk starts")
  measure(16, version .. " scripted_surf_walk")
  setup(version, true, true)
  eq(Player.tryMove("right", game, false), "step", version .. " underwater step")
  measure(16, version .. " underwater_walk")
  setup(version, true, false, true)
  eq(Player.tryMove("right", game, true), "step", version .. " Surf dismount")
  eq(Player.stepFrames, 32, version .. " dismount hop duration")
  check(Player.dismounting and Player.jumping, version .. " dismount semantics")
  setup(version, true, false)
  Player.surfHopping = true
  eq(Player.tryMove("right", game, false), "step", version .. " Surf mount")
  eq(Player.stepFrames, 32, version .. " mount hop duration")
  setup(version, true, false)
  check(Player.forcedStep("right", 4), version .. " explicit forced Surf step")
  eq(Player.stepFrames, 4, version .. " forced duration remains explicit")
end
T.finish("game3_surf_speed_2767")
