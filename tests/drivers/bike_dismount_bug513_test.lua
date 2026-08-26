-- Manual check that the BICYCLE refuses to come off on the Cycling Road (#513).
-- pokered gates this in StartMenu_Item .useOrTossItem (engine/menus/
-- start_sub_menus.asm): with BIT_ALWAYS_ON_BIKE set it prints
-- _CannotGetOffHereText and `jp ItemMenuLoop`, so the bag stays open and
-- ItemUseBicycle never runs.  Do not add POKEPORT_SPEED: it scales only the
-- logic clock, and the menu/text ordering under test is what is being judged.
--   POKEPORT_DRIVER=tests/drivers/bike_dismount_bug513_test.lua POKEPORT_IDENTITY=bug513 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end

  -- pokered data/maps/force_bike_surf.asm: ROUTE_16 (17,10) and (17,11) are
  -- the two cells you land on walking out of the Route 16 gate's south door,
  -- and they are what arms BIT_ALWAYS_ON_BIKE.  Landing there by warp is the
  -- real path, and setMap runs checkForcedMovement on entry, so a teleport
  -- onto the cell arms the flag exactly like the warp does.
  local FORCE_MAP, FORCE_X, FORCE_Y = "ROUTE_16", 17, 11
  -- the walking exit from the stretch (FieldDefaults forcedMovement.clearMaps,
  -- from scripts/Route16Gate1F.asm `res BIT_ALWAYS_ON_BIKE`)
  local GATE_MAP = "ROUTE_16_GATE_1F"
  -- pokered data/maps/objects/Route17.asm: the topmost bikers stand at
  -- (11,16), (12,19) and (4,18), so the y 8-14 stretch is the open top of the
  -- road with nobody's line of sight crossing it.  Route 17 is 20x144 cells,
  -- and the bike rolls south on its own, so start high enough that the roll
  -- below cannot carry the player into BIKER2's row.
  local ROAD_MAP, ROAD_X, ROAD_Y = "ROUTE_17", 11, 9

  local cannot = game.data.text._CannotGetOffHereText
  check("_CannotGetOffHereText was extracted",
        type(cannot) == "string" and cannot:find("get off", 1, true) ~= nil)
  local fm = game.data.field.forcedMovement
  local forced = fm and fm.tiles and fm.tiles[FORCE_MAP]
  check("the Route 16 forced-bike cells are in field.forcedMovement",
        type(forced) == "table" and #forced > 0)
  check("BICYCLE exists as an item", game.data.items.BICYCLE ~= nil)

  game.save.player.name = "SEBAS"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.inventory.BICYCLE = 1
  game.save.forcedBike = nil
  game.save.onBike = false

  -- arm the flag the way the game does, by arriving on the forced cell
  U.teleport(game, FORCE_MAP, FORCE_X, FORCE_Y, "down")
  U.wait(20)
  check("stepping off the Route 16 gate mounts the BICYCLE", game.save.onBike == true)
  check("and sets the forced-bike flag", game.save.forcedBike == true)

  -- the release half: the gate map has to clear it again, or the fix would
  -- trap the player on the bike forever, which reads on screen exactly like
  -- the refusal working
  -- pokered data/maps/objects/Route16Gate1F.asm: the warps sit on x 0 and 7,
  -- the guard on (4,5), so (3,6) is plain floor inside the gate
  U.teleport(game, GATE_MAP, 3, 6, "up")
  U.wait(20)
  check("walking into the Route 16 gate clears the flag again",
        game.save.forcedBike == nil or game.save.forcedBike == false)

  -- back out onto the road, then down to Route 17 where the report's
  -- screenshot was taken
  game.save.onBike = false
  U.teleport(game, FORCE_MAP, FORCE_X, FORCE_Y, "down")
  U.wait(20)
  U.teleport(game, ROAD_MAP, ROAD_X, ROAD_Y, "down")

  -- Route 17 is a slopeMap: with no button held the bike rolls south every
  -- frame the player is standing still (handleInput's simulated PAD_DOWN),
  -- and OverworldLoop only looks at START between steps.  Holding B is the
  -- brake the Route 17 sign describes, so hold it while waiting, exactly
  -- like a player coming to a stop before opening the menu (#255).
  local function brake(frames)
    for _ = 1, frames do
      game.input.state.b = true
      coroutine.yield()
    end
    game.input.state.b = false
  end
  brake(30)

  local ow = game.overworld
  local function freeCell(x, y)
    if not (ow and ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y)) then
      return false
    end
    if ow:npcAtCell(x, y) then return false end
    for _, n in ipairs(ow.npcs or {}) do
      if math.abs(n.cellX - x) + math.abs(n.cellY - y) <= 3 then return false end
    end
    return true
  end
  if ow and not freeCell(ROAD_X, ROAD_Y) then
    -- a map edit or a mod moved the road: take any open cell in the top
    -- stretch rather than parking the player inside the guard rail
    local found
    for y = 8, 30 do
      for x = 0, 19 do
        if freeCell(x, y) then found = { x, y } break end
      end
      if found then break end
    end
    if found then
      U.log(("(%d,%d) is blocked, standing at"):format(ROAD_X, ROAD_Y),
            found[1], found[2])
      U.teleport(game, ROAD_MAP, found[1], found[2], "down")
      brake(30)
      ow = game.overworld
    else
      check("found an open cell on the Route 17 top stretch", false)
    end
  end
  check("on Route 17, still riding, flag still armed",
        game.overworld and game.overworld.map.id == ROAD_MAP
        and game.save.onBike == true and game.save.forcedBike == true)

  -- open START -> ITEM -> BICYCLE -> USE for real, row by row, so a menu
  -- that reorders itself shows up as a FAIL instead of a silent misclick
  local function stepTo(state, wants, what)
    for _ = 1, 20 do
      if wants(state) then return true end
      U.tap(game, "down")
      U.wait(6)
    end
    check("found " .. what .. " in the menu", false)
    return false
  end

  -- brake into a standstill first, then press START on a frame where the
  -- player is between no steps at all, or handleInput drops it
  for _ = 1, 90 do
    game.input.state.b = true
    if not (game.overworld and game.overworld.player.moving) then break end
    coroutine.yield()
  end
  table.insert(game.input.pressQueue, "start")
  U.wait(1)
  game.input.state.start = false
  game.input.state.b = false
  U.wait(20)
  local menu = game.stack:top()
  local Strings = require("src.core.Strings")
  local ITEM = Strings("ITEM")
  if check("START opened a menu", menu and menu.items ~= nil) then
    if stepTo(menu, function(m) return m.items[m.index].label == ITEM end, "ITEM") then
      U.tap(game, "a")
      U.wait(20)
    end
  end

  local bag = game.stack:top()
  local isBag = bag and bag.items and bag.items[1] and bag.items[1].value ~= nil
  if check("the bag opened", isBag) then
    if stepTo(bag, function(b) return b.items[b.index].value == "BICYCLE" end,
              "BICYCLE") then
      -- the BICYCLE skips USE/TOSS (start_sub_menus.asm:340-342)
      U.tap(game, "a")
      U.wait(30)
    end
  end

  local top = game.stack:top()
  local box = getmetatable(top) == TextBox and top or nil
  if check("using the BICYCLE printed something", box ~= nil) then
    local lines = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    local said = table.concat(lines, " / ")
    U.log("the box reads:", said)
    check("it is the refusal, not the dismount message",
          said:find("get off", 1, true) ~= nil
          and said:find("BICYCLE", 1, true) == nil)
  end
  check("the player is still on the BICYCLE", game.save.onBike == true)
  -- pokered jumps back to ItemMenuLoop rather than closing the menu, so the
  -- bag list must still be underneath the box
  local bagStillUp = false
  for _, s in ipairs(game.stack.states) do
    if s == bag then bagStillUp = true end
  end
  check("the bag list is still open under the box", bagStillUp)

  U.wait(90) -- let the box finish typing, or the shot catches half a word
  local shotPath = SHOT_DIR .. "/bug513_bike_refusal.png"
  check("screenshot reached disk", U.shot(game, shotPath))

  U.log("")
  if ok then
    U.log("the BICYCLE has already been used once on Route 17; the box on")
    U.log("screen is that refusal. it should read \"You can't get off / here.\"")
    U.log("and B should drop you back into the bag list with the sprite still")
    U.log("on the bike, never onto your feet. shot saved to " .. shotPath)
    U.log("press B twice and try it again as often as you like. the road")
    U.log("rolls you south whenever you let go, so hold A or B to stop.")
    U.log("then ride north off Route 17 and into the Route 16 gate, where")
    U.log("USE should print \"SEBAS got off the BICYCLE.\" and put you on")
    U.log("foot -- if it refuses in there too, the guard never releases the")
    U.log("flag and the fix went a step too far.")
  else
    U.log("a check above failed, so nothing on screen is worth reading yet.")
  end

  while true do
    coroutine.yield()
  end
end
