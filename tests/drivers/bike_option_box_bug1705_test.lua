-- Eye check that the BICYCLE never shows the USE/TOSS box (#1705).
-- StartMenu_Item .choseItem does `cp BICYCLE / jp z, .useOrTossItem` before
-- it loads USE_TOSS_MENU_TEMPLATE (engine/menus/start_sub_menus.asm:340-342),
-- so mount, dismount and the Cycling Road refusal all land on one A press.
-- No POKEPORT_SPEED: it scales only the logic clock, and the frame the box
-- would flash on is the whole point of this run.
--   POKEPORT_DRIVER=tests/drivers/bike_option_box_bug1705_test.lua POKEPORT_IDENTITY=bug1705 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local ListMenu = require("src.ui.ListMenu")
  local Menu = require("src.ui.Menu")
  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end

  -- pokered data/maps/objects/PalletTown.asm: the house doors sit at (5,5)
  -- and (13,5) and the lab's at (12,11), so (10,8) is open ground.  OVERWORLD
  -- tileset, so IsBikeRidingAllowed says yes here (home/overworld.asm).
  local TOWN, TOWN_X, TOWN_Y = "PALLET_TOWN", 10, 8
  -- pokered data/maps/force_bike_surf.asm: ROUTE_16 (17,11) is a landing cell
  -- out of the Route 16 gate's south door and arms BIT_ALWAYS_ON_BIKE.
  local FORCE_MAP, FORCE_X, FORCE_Y = "ROUTE_16", 17, 11
  -- pokered data/maps/objects/Route16Gate1F.asm: warps on x 0 and 7, the
  -- guard on (4,5), so (3,6) is plain floor -- and the gate script is what
  -- clears the flag again (scripts/Route16Gate1F.asm `res BIT_ALWAYS_ON_BIKE`)
  local GATE_MAP, GATE_X, GATE_Y = "ROUTE_16_GATE_1F", 3, 6

  -- a missing item def, an unextracted refusal line and a bag that never
  -- opens all look like the bug from the couch
  check("BICYCLE exists as an item", game.data.items.BICYCLE ~= nil)
  local cannot = game.data.text._CannotGetOffHereText
  check("_CannotGetOffHereText was extracted",
        type(cannot) == "string" and cannot:find("get off", 1, true) ~= nil)
  check("POTION exists as the control item", game.data.items.POTION ~= nil)
  check("renderer is up", game.renderer ~= nil)

  game.save.player.name = "SEBAS"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.BICYCLE = 1
  game.save.inventory.POTION = 3
  game.save.onBike = false
  game.save.forcedBike = nil

  local function stationary()
    for _ = 1, 90 do
      game.input.state.b = true
      if not (game.overworld and game.overworld.player.moving) then break end
      coroutine.yield()
    end
    game.input.state.b = false
  end

  -- START -> ITEM -> the bag, by real presses.  Route 16/17 roll the player
  -- south whenever nothing is held, so brake into a standstill first or
  -- handleInput eats the START.
  local function openBag(where)
    stationary()
    U.tap(game, "start")
    U.wait(20)
    local menu = game.stack:top()
    if getmetatable(menu) == Menu then
      local ITEM = Strings("ITEM")
      for _ = 1, 20 do
        if menu.items[menu.index].label == ITEM then break end
        U.tap(game, "down")
        U.wait(6)
      end
      U.tap(game, "a")
      U.wait(20)
    end
    local bag = game.stack:top()
    if getmetatable(bag) ~= ListMenu then
      -- a start menu that reordered itself would otherwise strand the run;
      -- say so, then get to the moment anyway
      U.log("START -> ITEM did not reach the bag on " .. where
            .. ", pushing BagMenu directly")
      bag = Screens.push(game, "BagMenu")
      U.wait(20)
    end
    return getmetatable(bag) == ListMenu and bag or nil
  end

  -- the cursor comes back on the last-used row (#1732), so walk to the top
  -- before walking down or a row above the saved one is unreachable
  local function cursorTo(bag, id)
    for _ = 1, #bag.items do
      if bag.index == 1 then break end
      U.tap(game, "up")
      U.wait(5)
    end
    for _ = 1, #bag.items do
      local row = bag.items[bag.index]
      if row and row.value == id then return true end
      U.tap(game, "down")
      U.wait(5)
    end
    return bag.items[bag.index] and bag.items[bag.index].value == id
  end

  -- StartMenu_Item keeps the START menu up behind the bag, and that is a
  -- Menu too, so only a Menu that was NOT already there counts as the
  -- option box
  local function menuSnapshot()
    local seen = {}
    for _, s in ipairs(game.stack.states) do seen[s] = true end
    return seen
  end

  local function newMenu(before)
    for _, s in ipairs(game.stack.states) do
      if getmetatable(s) == Menu and not before[s] then return true end
    end
    return false
  end

  -- press A and watch every frame after it: a USE/TOSS box that appears and
  -- is replaced two frames later is invisible in a still, and is the near
  -- miss this whole run exists to catch
  local function chooseAndWatch(frames)
    local before = menuSnapshot()
    U.tap(game, "a")
    local flashed = newMenu(before)
    for _ = 1, frames or 30 do
      if newMenu(before) then flashed = true end
      coroutine.yield()
    end
    return flashed, before
  end

  local function boxSays()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local lines = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return table.concat(lines, " / ")
  end

  local function dismissBox()
    for _ = 1, 8 do
      if getmetatable(game.stack:top()) ~= TextBox then break end
      U.tap(game, "b")
      U.wait(12)
    end
  end

  local function backToOverworld()
    for _ = 1, 10 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "b")
      U.wait(12)
    end
  end

  -- the control: an ordinary item DOES open the box, so a run where nothing
  -- ever appears cannot be mistaken for the fix working
  U.teleport(game, TOWN, TOWN_X, TOWN_Y, "down")
  U.wait(20)
  local bag = openBag("Pallet Town")
  if check("the bag opened in " .. TOWN, bag ~= nil) then
    if check("found the POTION row", cursorTo(bag, "POTION")) then
      U.tap(game, "a")
      U.wait(20)
      check("a POTION still opens USE/TOSS", getmetatable(game.stack:top()) == Menu)
      check("control shot reached disk",
            U.shot(game, SHOT_DIR .. "/bug1705_potion_usetoss.png"))
      U.tap(game, "b")
      U.wait(15)
    end
  end

  -- mount: one press, straight to the text
  if bag and check("found the BICYCLE row", cursorTo(bag, "BICYCLE")) then
    local flashed, before = chooseAndWatch(4)
    check("no option box in the first frames after A (mount)", not flashed)
    check("early shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1705_mount_first_frames.png"))
    U.wait(60)
    check("still no option box while the text types", not newMenu(before))
    local said = boxSays()
    U.log("the box reads:", tostring(said))
    check("the single press mounted the bike", game.save.onBike == true)
    check("and the line is the mount text",
          said ~= nil and said:find("got on", 1, true) ~= nil)
    check("mount shot reached disk", U.shot(game, SHOT_DIR .. "/bug1705_mount.png"))
  end
  dismissBox()
  backToOverworld()

  -- dismount: the same one press
  bag = openBag("Pallet Town (riding)")
  if bag and check("found the BICYCLE row again", cursorTo(bag, "BICYCLE")) then
    local flashed = chooseAndWatch(4)
    check("no option box in the first frames after A (dismount)", not flashed)
    U.wait(60)
    local said = boxSays()
    U.log("the box reads:", tostring(said))
    check("the single press dismounted", game.save.onBike == false)
    check("and the line is the dismount text",
          said ~= nil and said:find("got off", 1, true) ~= nil)
    check("dismount shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1705_dismount.png"))
  end
  dismissBox()
  backToOverworld()

  -- the Cycling Road refusal, armed the way the game arms it: by arriving on
  -- the forced-bike cell (setMap runs checkForcedMovement on entry)
  game.save.onBike = false
  U.teleport(game, FORCE_MAP, FORCE_X, FORCE_Y, "down")
  U.wait(25)
  check("stepping onto the Route 16 cell mounts the bike", game.save.onBike == true)
  check("and arms the forced-bike flag", game.save.forcedBike == true)
  bag = openBag("Route 16")
  if bag and check("found the BICYCLE row on the road", cursorTo(bag, "BICYCLE")) then
    local flashed = chooseAndWatch(4)
    check("no option box in the first frames after A (refusal)", not flashed)
    U.wait(60)
    local said = boxSays()
    U.log("the box reads:", tostring(said))
    check("the refusal printed, not the dismount",
          said ~= nil and said:find("get off", 1, true) ~= nil)
    check("the player is still riding", game.save.onBike == true)
    local stillUp = false
    for _, s in ipairs(game.stack.states) do
      if s == bag then stillUp = true end
    end
    check("and the bag list is still on the stack under the box (#513)", stillUp)
    check("refusal shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1705_forced_refusal.png"))
  end
  dismissBox()
  backToOverworld()

  -- walking into the gate releases the flag; the gate's tileset is not one of
  -- IsBikeRidingAllowed's (home/overworld.asm), so the map change dismounts on
  -- the way in and the release has to be shown back out on the road
  U.teleport(game, GATE_MAP, GATE_X, GATE_Y, "up")
  U.wait(25)
  check("the gate clears the forced-bike flag",
        game.save.forcedBike == nil or game.save.forcedBike == false)

  -- a plain Route 16 cell: walkable, nobody on it, and NOT one of the two
  -- forced-bike tiles, so nothing re-arms the flag when we land
  local function plainRoadCell()
    local ow = game.overworld
    local fm = game.data.field.forcedMovement
    local forced = {}
    for _, t in ipairs((fm and fm.tiles and fm.tiles[FORCE_MAP]) or {}) do
      forced[t.x .. "," .. t.y] = true
    end
    if not ow then return nil end
    for y = 0, 35 do
      for x = 0, 19 do
        if not forced[x .. "," .. y] and ow.map:inBounds(x, y)
           and ow.map:isWalkableCell(x, y) and not ow:npcAtCell(x, y) then
          return x, y
        end
      end
    end
    return nil
  end

  U.teleport(game, FORCE_MAP, FORCE_X, FORCE_Y - 3, "up")
  U.wait(20)
  local px, py = plainRoadCell()
  if px then
    U.teleport(game, FORCE_MAP, px, py, "up")
    U.wait(20)
  end
  check("back on Route 16, off the forced tiles, flag still clear",
        game.save.forcedBike == nil or game.save.forcedBike == false)

  -- with the flag released the bike answers again: mount, then get off, one
  -- press each, and the get-off is the very thing the road refused
  if not game.save.onBike then
    bag = openBag("Route 16 (released)")
    if bag and check("found the BICYCLE row to remount", cursorTo(bag, "BICYCLE")) then
      local flashed = chooseAndWatch(4)
      check("no option box on the remount", not flashed)
      U.wait(60)
      U.log("the box reads:", tostring(boxSays()))
      check("the remount worked", game.save.onBike == true)
    end
    dismissBox()
    backToOverworld()
  end

  bag = openBag("Route 16 (getting off)")
  if bag and check("found the BICYCLE row again on the road",
                   cursorTo(bag, "BICYCLE")) then
    local flashed = chooseAndWatch(4)
    check("no option box on the released dismount", not flashed)
    U.wait(60)
    local said = boxSays()
    U.log("the box reads:", tostring(said))
    check("the flag really is released: this one gets off",
          game.save.onBike == false)
    check("and the line is the dismount text, not the refusal",
          said ~= nil and said:find("got off", 1, true) ~= nil)
    check("released dismount shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1705_released_dismount.png"))
  end

  check("the BICYCLE was never consumed", (game.save.inventory.BICYCLE or 0) == 1)

  U.log("")
  if ok then
    U.log("the bike has been used five times for you: mounted and dismounted in")
    U.log("PALLET TOWN, refused on the Route 16 forced stretch, then mounted and")
    U.log("taken off again after the gate released the flag. every one of those")
    U.log("was a single A press on the BICYCLE row, with no USE/TOSS box.")
    U.log("shots are in " .. SHOT_DIR .. ": bug1705_potion_usetoss.png is the")
    U.log("control, the box a POTION still gets. bug1705_mount_first_frames.png")
    U.log("is two frames after the A press on the bike -- that one must show")
    U.log("the mount text or a bare map, never a small box in the lower right.")
    U.log("the near miss is a box that appears and is replaced before the text")
    U.log("types, which reads as a pass in every later shot.")
    U.log("you are on Route 16 with the bag closed; open it and try the bike as")
    U.log("often as you like. it also has no TOSS any more, since the box that")
    U.log("carried it is the one that no longer opens.")
    U.log("yellow shares this code path: rerun with POKEPORT_VERSION=yellow")
    U.log("and a yellow identity, and every beat should read the same.")
  else
    U.log("a check above failed, so nothing on screen is worth reading yet.")
  end

  while true do
    coroutine.yield()
  end
end
