-- Manual check that the elevator floor menu waits for the panel (#395).
-- pokered data/maps/objects/CeladonMartElevator.asm has it as `bg_event 3, 0,
-- TEXT_CELADONMARTELEVATOR`, and only that text reaches
-- DisplayElevatorFloorMenu (engine/events/elevator.asm), which rewrites the
-- car's warps and returns without moving the player.  No POKEPORT_SPEED here:
-- fast-forward desynchronizes the ride's audio.
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/elevator_panel_bug395_test.lua POKEPORT_IDENTITY=bug395 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local ListMenu = require("src.ui.ListMenu")
  local mapScripts = require("data.scripts.init")

  -- data/generated/maps.lua CELADON_MART_ELEVATOR: sign (3,0) is the panel,
  -- warp (1,3) is the arrival tile, row 0 is wall, so the panel is read from
  -- (3,1) facing up.  2F is the floor picked below.
  local MAP = "CELADON_MART_ELEVATOR"
  local TEXT = "TEXT_CELADONMARTELEVATOR"
  local ARRIVE = { x = 1, y = 3 }
  local PANEL = { x = 3, y = 0 }
  local STAND = { x = 3, y = 1, facing = "up" }
  local PICK = "CELADON_MART_2F"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local def = game.data.maps[MAP]
  local sign
  for _, s in ipairs(def.signs or {}) do
    if s.text == TEXT then sign = s end
  end
  check(TEXT .. " is a sign in the map data", sign ~= nil)
  if sign then
    check(("the panel sits at (%d,%d)"):format(PANEL.x, PANEL.y),
          sign.x == PANEL.x and sign.y == PANEL.y)
  end
  check("the panel text runs a script", type(mapScripts.talkScript(MAP, TEXT)) == "function")

  local vol = game.save.options and game.save.options.sfxVol
  if (vol or 0) == 0 then
    U.log("sfxVol is 0: the ride will be silent, raise it in OPTION first")
  else
    U.log("sfxVol", tostring(vol), "-- 100 collision thuds then the PA chime")
  end

  U.teleport(game, MAP, ARRIVE.x, ARRIVE.y, "up")
  U.wait(10)
  local ow = game.overworld
  check("no menu opened on arrival", getmetatable(game.stack:top()) ~= ListMenu)
  U.shot(game, DIR .. "/elev395_0_entered.png")

  local function facingThePanel()
    local fx, fy = ow.player:facingCell()
    return ow.map:signAtCell(fx, fy) ~= nil
  end

  -- walk over to the panel, one cell per hold
  U.hold(game, "right", 24)
  U.hold(game, "right", 24)
  U.hold(game, "up", 24)
  U.hold(game, "up", 24)
  U.wait(10)
  U.log("standing at", ow.player.cellX, ow.player.cellY, ow.player.facing)

  if not facingThePanel() and sign then
    -- a map edit moved the panel: stand on any walkable neighbour of it.
    -- {dx, dy, facing} is the offset from the panel plus the way back at it.
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = sign.x + s[1], sign.y + s[2]
      if ow.map:isWalkableCell(cx, cy) then
        U.log("panel moved; standing on", cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        ow = game.overworld
        break
      end
    end
  end
  check("the player is facing the panel", facingThePanel())

  U.tap(game, "a")
  U.wait(20)
  local menu = getmetatable(game.stack:top()) == ListMenu
  check("A on the panel opens the floor list", menu)
  if menu then
    local labels = {}
    for _, item in ipairs(game.stack:top().items or {}) do
      labels[#labels + 1] = item.label
    end
    U.log("floors listed:", table.concat(labels, " "))
  end
  U.shot(game, DIR .. "/elev395_1_menu.png")

  U.tap(game, "down") -- 1F -> 2F
  U.wait(2)
  U.tap(game, "a")
  -- 9 zero frames (Celadon farjps into ShakeElevator with no extra Delay3),
  -- then -1,-1,+1,+1 in 2-frame steps
  local trace = {}
  for _ = 1, 24 do
    trace[#trace + 1] = tostring(ow.bgShakeY or 0)
    U.wait(1)
  end
  U.log("bgShakeY after the pick:", table.concat(trace, ","))
  U.shot(game, DIR .. "/elev395_2_shake_a.png")
  U.shot(game, DIR .. "/elev395_3_shake_b.png") -- the other phase of the bounce

  local ElevatorShake = require("src.world.ElevatorShake")
  for _ = 1, 1200 do
    U.wait(1)
    if getmetatable(game.stack:top()) ~= ElevatorShake then break end
  end
  U.wait(20)
  check("the ride left the player in the car", ow.map.id == MAP)
  check("and standing where they read the panel",
        ow.player.cellX == STAND.x and ow.player.cellY == STAND.y)
  local dests = {}
  for _, w in ipairs(ow.map.def.warps) do dests[#dests + 1] = tostring(w.destMap) end
  U.log("car exit warps now point at:", table.concat(dests, " "))
  check("the exits were rewritten to " .. PICK, dests[1] == PICK)
  U.shot(game, DIR .. "/elev395_4_rode.png")

  U.log("The ride is over and the pad is yours: walk down and left onto the")
  U.log("door tile at (2,3) and you should come out on CELADON MART 2F.  The")
  U.log("panel is behind you -- A on it should reopen WHICH FLOOR?, and B out")
  U.log("of that list should leave you in the car with 2F still the exit.")
  U.log("Worth checking by hand: Silph Co (same panel cell, 11 floors) and the")
  U.log("Rocket car, whose panel is at (1,1) so you face LEFT from (2,1) and")
  U.log("with no LIFT KEY get \"It appears to need a key.\" and no list.")

  while true do
    coroutine.yield()
  end
end
