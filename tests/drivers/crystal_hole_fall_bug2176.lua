local U = require("tests.drivers.util")
local Permissions = require("src.world.gen2.Permissions")

local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

-- ../pokecrystal/maps/IcePathB1F.asm:82-85
local MAP = "ICE_PATH_B1F"
local BELOW = "ICE_PATH_B2F_MAHOGANY_SIDE"
local HOLES = { { 11, 2 }, { 4, 7 }, { 5, 12 }, { 12, 13 } }
local STEP = {
  down = { 0, -1, "down" }, up = { 0, 1, "up" },
  left = { 1, 0, "left" }, right = { -1, 0, "right" },
}

return function(game)
  local fails = 0
  local function say(line) print("[hole2176] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end

  world:warpToMapId(MAP, HOLES[1][1], HOLES[1][2], "down")
  U.wait(60)
  ok(world.map and world.map.id == MAP, "arrived at " .. MAP)
  world.noWildEncounters = true

  local hx, hy, dir
  for _, hole in ipairs(HOLES) do
    for name, d in pairs(STEP) do
      local nx, ny = hole[1] + d[1], hole[2] + d[2]
      if Permissions.isWalkable(world.map:cellCollision(nx, ny)) then
        hx, hy, dir = nx, ny, name
        break
      end
    end
    if dir then break end
  end
  ok(dir ~= nil, "found a walkable cell beside a COLL_PIT")
  if not dir then love.event.quit(1) return end

  world:warpToMapId(MAP, hx, hy, dir)
  U.wait(60)
  U.shot(game, "/tmp/pokeport-shots/hole2176_before.png")

  U.tap(game, dir)
  local sawLoad, maskedThroughFadeIn, shotFadeIn = false, true, false
  for _ = 1, 300 do
    local ms = world.mapSetup
    if ms and ms.phase == "in" then
      sawLoad = true
      if not world.playerMasked then maskedThroughFadeIn = false end
      if not shotFadeIn and not world.fadeHold and (world.fadeLevel or 1) <= 0.5 then
        shotFadeIn = true
        U.shot(game, SHOTS .. "/2193_01_fade_in_no_player.png")
      end
    elseif sawLoad and not ms then
      break
    end
    U.wait(1)
  end
  ok(sawLoad, "the FALL map setup loaded the floor below")
  ok(maskedThroughFadeIn,
    "ResetPlayerObjectAction: no player sprite anywhere during the fade-in")
  ok(shotFadeIn, "and the empty landing cell was captured mid-ramp")
  for _ = 1, 240 do
    if world.skyfall then break end
    U.wait(1)
  end
  ok(world.skyfall ~= nil, "the fall animation armed after the load")
  ok(world.map and world.map.id == BELOW, "landed on " .. BELOW)
  ok(world:busy(), "and the applymovement holds the overworld")
  U.shot(game, "/tmp/pokeport-shots/hole2176_hidden.png")
  U.wait(20)
  U.shot(game, "/tmp/pokeport-shots/hole2176_falling.png")
  ok(world.skyfall and world.skyfall.phase == "fall",
    "the sprite only reappears once it is dropping")
  ok((world.player.spriteYOffset or 0) < 0, "from above the landing cell")
  U.shot(game, SHOTS .. "/2193_02_falling.png")

  for _ = 1, 120 do
    if not world.skyfall then break end
    U.wait(1)
  end
  ok(world.shake ~= nil, "earthquake 16 fires on the landing")
  ok(world.shake and world.shake.amplitude == 1, "one pixel of it")
  U.shot(game, "/tmp/pokeport-shots/hole2176_landed.png")
  U.wait(30)
  ok((world.player.spriteYOffset or 0) == 0, "the sprite is back on its tile")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
