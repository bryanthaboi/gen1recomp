-- Driver: watch the Route 22 rival leave without clipping the cliff (#236).
-- scripts/Route22.asm keys the ambush on which coord you stepped on: (29,4)
-- parks him at (29,5) with ExitMovementData1, (29,5) at (28,5) with ...Data2.
--   POKEPORT_DRIVER=tests/drivers/route22_rival_exit_bug236_test.lua \
--     POKEPORT_IDENTITY=bug236 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .   (BUG236_TILE=5 runs the other tile)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Flags = require("src.script.Flags")
  local TextBox = require("src.render.TextBox")
  local mapScripts = require("data.scripts.init")

  local MAP = "ROUTE_22"
  local TILE_Y = tonumber(os.getenv("BUG236_TILE") or "4")
  if TILE_Y ~= 4 and TILE_Y ~= 5 then TILE_Y = 4 end
  local TRIG_X = 29
  -- what pokered does on this tile
  local WANT = (TILE_Y == 4)
    and { rx = 29, ry = 5, rivalFacing = "up", playerFacing = "down",
          -- Route22Rival1ExitMovementData1
          dirs = { "right", "right", "down", "down", "down", "down", "down" },
          endX = 31, endY = 10 }
     or { rx = 28, ry = 5, rivalFacing = "right", playerFacing = "left",
          -- Route22Rival1ExitMovementData2
          dirs = { "up", "right", "right", "right",
                   "down", "down", "down", "down", "down", "down" },
          endX = 31, endY = 10 }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- a party that ends OPP_RIVAL1 in one turn --------------------------
  -- the walk-off only exists after a win, and the fight is not under test
  local tank = Pokemon.new(game.data, "MEWTWO", 100)
  tank.moves = {
    { id = "PSYCHIC_M", pp = 99 },
    { id = "THUNDERBOLT", pp = 99 },
    { id = "ICE_BEAM", pp = 99 },
    { id = "RECOVER", pp = 99 },
  }
  game.save.party = { tank }
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"
  game.save.player.rival = game.save.player.rival or "BLUE"
  game.save.defeatedTrainers = {}
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles[MAP] = nil
  -- the window Route22DefaultScript arms: Pokedex in hand, Brock not yet
  -- beaten, this rival not yet fought
  Flags.set(game.save, "EVENT_CHOSE_SQUIRTLE")
  Flags.set(game.save, "EVENT_GOT_POKEDEX")
  Flags.clear(game.save, "EVENT_BEAT_BROCK")
  Flags.clear(game.save, "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE")
  Flags.clear(game.save, "EVENT_BEAT_GIOVANNI")
  Flags.clear(game.save, "EVENT_BEAT_ROUTE22_RIVAL_2ND_BATTLE")

  -- ---- park one cell west of the trigger ---------------------------------
  -- rows 4 and 5 are open path from x=24 to x=33; row 3 above them is the
  -- cliff the buggy exit walked into
  U.teleport(game, MAP, TRIG_X - 1, TILE_Y, "right")
  U.wait(10)
  local ow = game.overworld

  -- ---- preconditions -----------------------------------------------------
  -- a missing text entry, a moved object and an onStep that never fires all
  -- look like a movement bug on screen: nothing happens
  local t = game.data.text
  for _, key in ipairs({ "_Route22RivalBeforeBattleText1",
                         "_Route22Rival1DefeatedText",
                         "_Route22RivalAfterBattleText1" }) do
    check(key .. " resolves to a string",
          type(t[key]) == "string" and t[key] ~= "")
  end

  local spawn
  for _, o in ipairs(game.data.maps[MAP].objects or {}) do
    if o.name == "ROUTE22_RIVAL1" then spawn = o end
  end
  check("ROUTE22_RIVAL1 has an object_event", spawn ~= nil)
  check("it spawns on (25,5) as in data/maps/objects/Route22.asm",
        spawn ~= nil and spawn.x == 25 and spawn.y == 5)
  check("ROUTE_22 (28,3) is solid cliff (the cell #236 walked into)",
        not ow.map:isWalkableCell(28, 3))

  -- Dry-run the scene on a throwaway overworld so the exit list can be walked
  -- against real collision before anything happens on screen.  Music.play is
  -- silenced or the rival sting fires the scene early.
  local Music = require("src.core.Music")
  local realPlay = Music.play
  Music.play = function() end
  local rows, probeFacing
  do
    local probe = {
      runner = { isRunning = function() return false end,
                 run = function(_, r) rows = r end },
      player = { facing = "down" },
      npcByIndex = function() return { def = { name = "X" } } end,
    }
    local script = mapScripts.get(MAP)
    check("ROUTE_22 has an onStep hook", script ~= nil and script.onStep ~= nil)
    if script and script.onStep then
      check(("onStep fires on the ambush tile (%d,%d)"):format(TRIG_X, TILE_Y),
            script.onStep(game, probe, TRIG_X, TILE_Y) == true)
    end
    probeFacing = probe.player.facing
  end
  Music.play = realPlay

  local moveTo, face, walk
  for _, r in ipairs(rows or {}) do
    if r[1] == "move_npc_to" then moveTo = r end
    if r[1] == "face_object" then face = r end
    if r[1] == "walk_npc" then walk = r end
  end
  check("the scene carries move/face/walk rows",
        moveTo ~= nil and face ~= nil and walk ~= nil)
  if moveTo and face and walk then
    U.log(("plan: rival to (%d,%d) facing %s, player turned %s, exit %s")
            :format(moveTo[3], moveTo[4], tostring(face[3]),
                    tostring(probeFacing), table.concat(walk[3], ", ")))
    check(("rival parks on (%d,%d), where Route22MoveRivalRightScript leaves him")
            :format(WANT.rx, WANT.ry),
          moveTo[3] == WANT.rx and moveTo[4] == WANT.ry)
    check("rival faces " .. WANT.rivalFacing .. " at the player",
          face[3] == WANT.rivalFacing)
    check("player is turned " .. WANT.playerFacing .. " at the rival",
          probeFacing == WANT.playerFacing)
    local same = #walk[3] == #WANT.dirs
    for i = 1, #WANT.dirs do
      if walk[3][i] ~= WANT.dirs[i] then same = false end
    end
    check("exit list is " .. table.concat(WANT.dirs, ", "), same)
    -- replay it cell by cell against the real map: this is the assertion the
    -- cliff clip failed
    local D = { up = { 0, -1 }, down = { 0, 1 },
                left = { -1, 0 }, right = { 1, 0 } }
    local x, y, clean = moveTo[3], moveTo[4], true
    for i, d in ipairs(walk[3]) do
      x, y = x + D[d][1], y + D[d][2]
      if not ow.map:isWalkableCell(x, y) then
        clean = false
        U.log(("  exit step %d (%s) walks into solid ground at (%d,%d)")
                :format(i, d, x, y))
      end
      if x == TRIG_X and y == TILE_Y then
        clean = false
        U.log(("  exit step %d (%s) walks through the player on (%d,%d)")
                :format(i, d, x, y))
      end
    end
    check("every exit cell is walkable and none is the player's", clean)
    check(("the exit ends on (%d,%d), off the bottom of the screen")
            :format(WANT.endX, WANT.endY),
          x == WANT.endX and y == WANT.endY)
  end

  if U.shot(game, DIR .. "/bug236_0_before.png") then
    U.log("captured", DIR .. "/bug236_0_before.png")
  end

  -- ---- step onto the ambush tile -----------------------------------------
  U.hold(game, "right", 24)

  local function boxText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local parts = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  local function rivalNpc()
    for _, n in ipairs(game.overworld.npcs or {}) do
      if n.def and n.def.name and n.def.name:find("RIVAL") then return n end
    end
  end

  -- wait for the approach walk to finish: he is on his mark when the script
  -- moves drain and the pre-battle box is up
  local parked
  for _ = 1, 400 do
    local r = rivalNpc()
    if r and #ow.scriptMoves == 0 and not r.moving and boxText() ~= "" then
      parked = r
      break
    end
    U.wait(2)
  end
  check("the rival showed up and stopped walking", parked ~= nil)
  if parked then
    U.log(("rival parked on (%d,%d) facing %s; player on (%d,%d) facing %s")
            :format(parked.cellX, parked.cellY, tostring(parked.facing),
                    ow.player.cellX, ow.player.cellY, tostring(ow.player.facing)))
    check(("he is on (%d,%d) live, not just on paper"):format(WANT.rx, WANT.ry),
          parked.cellX == WANT.rx and parked.cellY == WANT.ry)
    check("he is not standing on top of the player",
          not (parked.cellX == ow.player.cellX and parked.cellY == ow.player.cellY))
  end
  if U.shot(game, DIR .. "/bug236_1_ambush.png") then
    U.log("captured", DIR .. "/bug236_1_ambush.png")
  end

  -- ---- fight it for the human --------------------------------------------
  -- FIGHT + first move every prompt; PSYCHIC one-shots the level 5-9 party.
  local sawBattle = false
  for f = 1, 4000 do
    local top = game.stack:top()
    if top and top.phase then
      sawBattle = true
      if top.phase == "menu" then top.menuIndex = 1
      elseif top.phase == "moveSelect" then top.moveIndex = 1 end
      U.tap(game, "a")
      if f > 2400 and top.onFinish then
        -- safety valve: never leave the run wedged in a stalled battle
        U.log("force-finishing a stalled battle")
        top.onFinish("win")
        if game.stack:top() == top then game.stack:pop() end
      end
    elseif sawBattle then
      break
    elseif top ~= ow then
      U.tap(game, "a") -- pre-battle dialogue
    end
    U.wait(2)
  end
  check("the battle ran and ended", sawBattle)
  check("EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE is set",
        game.save.flags.EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE == true)

  -- ---- stop on the LAST post-battle box ----------------------------------
  local after = t._Route22RivalAfterBattleText1 or ""
  local needle = after:match("dawdling") and "dawdling" or "LEAGUE"
  local onLastBox = false
  for _ = 1, 600 do
    if boxText():find(needle, 1, true) then onLastBox = true break end
    if game.stack:top() ~= ow then U.tap(game, "a") end
    U.wait(3)
  end
  check("the last post-battle box is on screen", onLastBox)
  U.wait(20)
  if U.shot(game, DIR .. "/bug236_2_lastbox.png") then
    U.log("captured", DIR .. "/bug236_2_lastbox.png")
  end

  -- ---- hand off ----------------------------------------------------------
  local r = rivalNpc()
  U.log(("BLUE is beaten on the (%d,%d) ambush tile and the box on screen is")
          :format(TRIG_X, TILE_Y))
  U.log("his last line.  Press A and watch him leave: that walk is #236.  He")
  U.log("must not clip the cliff at the top, step on your cell, or vanish")
  U.log("before he is off the bottom of the screen.")
  if r then
    U.log(("He is standing on (%d,%d); you are on (%d,%d)."):format(
            r.cellX, r.cellY, ow.player.cellX, ow.player.cellY))
  end
  if TILE_Y == 4 then
    U.log("Expect two steps right, then five straight down.")
  else
    U.log("Expect one step up around you, three right, then six down.")
  end

  while true do
    coroutine.yield()
  end
end
