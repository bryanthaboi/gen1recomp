-- engine/events/overworld.asm:595-608

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local World = require("src.world.gen2.World")

-- engine/sprite_anims/functions.asm:1389
do
  local flat = { viewW = 160, viewH = 144 }
  local sox, soy = World.gbScreenOrigin(flat)
  eq(sox, 0, "a 160-wide view has the GB window at x 0")
  eq(soy, 0, "and at y 0")

  local wide = { viewW = 320, viewH = 288 }
  local wox, woy = World.gbScreenOrigin(wide)
  eq(wox, 80, "a doubled view centres the GB window horizontally")
  eq(woy, 72, "and vertically")

  local leaf = { x = 90, y = 0x40, xoff = 0 }
  local lx, ly = World.leafScreenPos(leaf)
  check(lx >= 0 and lx <= 184, "the raw sweep is LCD pixels")
  local cx, cy = lx + wox, ly + woy
  check(cx > wide.viewW / 2 - 80 and cx < wide.viewW / 2 + 80,
    "offset by the GB origin a mid-sweep leaf is beside the centred player")
  check(cy > woy and cy < woy + 144, "and inside the GB window vertically")

  local first = World.leafScreenPos({ x = 0, y = 0x40, xoff = 0 }) + wox
  check(first > 0, "even the spawn column is off the left edge of the window")
end

local function flyWorld()
  local world = World.new({ data = {}, save = { player = {} } })
  world.player = { px = 64, py = 64, facing = "down" }
  world.landmarks = { spawns = { SPAWN_NEW_BARK = {
    map = "NEW_BARK_TOWN", x = 5, y = 5,
  } } }
  world.maps = { NEW_BARK_TOWN = { id = "NEW_BARK_TOWN" } }
  world.setMap = function(self) self.map = { id = "NEW_BARK_TOWN" } return true end
  world.applyPlayerState = function() end
  world.playSfxNamed = function() end
  return world
end

local function drainFadeOut(world)
  local guard = 0
  while world.mapSetup and world.mapSetup.phase == "out" and guard < 4000 do
    world:updateMapSetup()
    guard = guard + 1
  end
  return guard < 4000
end

local function drainMapSetup(world)
  local guard = 0
  while world.mapSetup and guard < 4000 do
    world:updateMapSetup()
    guard = guard + 1
  end
  return guard < 4000
end

-- engine/events/field_moves.asm:390
do
  local world = flyWorld()
  check(world:flyTo("SPAWN_NEW_BARK", { species = "PIKACHU" }),
    "the fly runs with no icon to animate")
  check(world.flyAnim == nil, "with no bird")
  eq(world.flyHidden, "from", "and everyone hidden over the departure map")
  check(drainFadeOut(world), "the white fade out drains")
  eq(world.flyHidden, "to", "the load moved the hide to the arrival side")
  local hideAll, hidePlayer = world:flyHides()
  check(hideAll, "SkipUpdateMapSprites keeps the objects out of OAM")
  check(hidePlayer, "and the player with them")
  check(drainMapSetup(world), "the fade in drains")
  eq(world.flyHidden, nil, ".ReturnFromFly respawns him")
  local allB, playerB = world:flyHides()
  check(not allB and not playerB, "and nothing is hidden any more")
end

-- engine/events/field_moves.asm:300
do
  local world = flyWorld()
  world.flyIconFor = function() return { draw = function() end } end
  check(world:flyTo("SPAWN_NEW_BARK", { species = "PIKACHU" }),
    "the fly starts")
  eq(world.flyHidden, "from", "everyone is hidden over the departure map")
  local hideAll = world:flyHides()
  check(hideAll, "HideSprites clears the whole draw list")
  check(world.flyAnim ~= nil and world.flyAnim.phase == "from",
    "FlyFromAnim is up")

  local guard = 0
  while world.flyAnim and guard < 4000 do
    world:stepFlyAnim()
    guard = guard + 1
  end
  check(guard < 4000, "FlyFromAnim finishes")
  check(world.mapSetup ~= nil, "and hands over to the teleport fade")
  eq(world.flyHidden, "from", "the departure map stays empty through the fade")
  check(drainFadeOut(world), "the white fade out drains")
  eq(world.flyHidden, "to", "the load side keeps the hide up")
  local allMid, playerMid = world:flyHides()
  check(allMid, "nothing is drawn through the fade in")
  check(playerMid, "the player included")

  local hiddenEveryFrame = true
  guard = 0
  while world.mapSetup and guard < 4000 do
    world:updateMapSetup()
    local a, p = world:flyHides()
    if not (a and p) then hiddenEveryFrame = false end
    guard = guard + 1
  end
  check(guard < 4000, "the fade in drains")
  check(world.flyAnim ~= nil and world.flyAnim.phase == "to",
    "FlyToAnim takes over")
  eq(world.flyHidden, "to", "and the player is still hidden under the bird")
  guard = 0
  while world.flyAnim and guard < 4000 do
    world:stepFlyAnim()
    if world.flyAnim then
      local a, p = world:flyHides()
      if not (a and p) then hiddenEveryFrame = false end
    end
    guard = guard + 1
  end
  check(guard < 4000, "FlyToAnim finishes")
  check(hiddenEveryFrame, "everything stays hidden until the bird lands")
  eq(world.flyHidden, nil, "and .ReturnFromFly clears the hide")
  local allEnd, playerEnd = world:flyHides()
  check(not allEnd and not playerEnd, "then everyone is drawn again")
end

do
  local world = flyWorld()
  world.runMapSetup = function(_, _, load) load() return true end
  check(world:flyTo("SPAWN_NEW_BARK", { species = "PIKACHU" }),
    "the fly still lands")
  eq(world.flyHidden, nil, "with no fade to clear it, the hide is dropped")
end

-- engine/events/overworld.asm:607
do
  local MAPSETUP_WARP = 0xf1
  local world = flyWorld()
  check(world:flyTo("SPAWN_NEW_BARK", { species = "PIKACHU" }),
    "the fly runs with no icon to animate")
  check(drainFadeOut(world), "the white fade out drains")
  eq(world.flyHidden, "to", "the player is hidden over the arrival map")
  world:runMapSetup(MAPSETUP_WARP, function() return true end)
  eq(world.flyHidden, nil,
    "a map-setup chain that replaces the fly's own unhides him")
  local allW, playerW = world:flyHides()
  check(not allW and not playerW, "so nothing is left invisible")

  local mid = flyWorld()
  check(mid:flyTo("SPAWN_NEW_BARK", { species = "PIKACHU" }), "a second fly")
  eq(mid.flyHidden, "from", "hides the departure map")
  mid:runMapSetup(MAPSETUP_WARP, function() return true end)
  eq(mid.flyHidden, nil, "and a replacement chain clears that arm too")
end

do
  local world = flyWorld()
  world.flyIconFor = function() return { draw = function() end } end
  check(world:flyTo("SPAWN_NEW_BARK", { species = "PIKACHU" }),
    "the fly starts with a bird")
  eq(world.flyHidden, "from", "everyone is hidden")
  local guard = 0
  while world.flyAnim and guard < 4000 do
    world:stepFlyAnim()
    guard = guard + 1
  end
  check(guard < 4000, "FlyFromAnim finishes")
  eq(world.flyHidden, "from",
    "the fly's own teleport chain never clears its own hide")
  check(drainFadeOut(world), "the white fade out drains")
  eq(world.flyHidden, "to", "and the load side still hands over to the player arm")
end

T.finish("gen2 fly leaves + player hide bug1960")
