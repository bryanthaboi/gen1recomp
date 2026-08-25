-- #1709: BATTLE BG on Gold, the WHITE / BLACK void around the battle screen,
-- and whether it survives a menu opened over the battle.  The cart has no such
-- setting; maps/Route29.asm:432 is only where this parks the player.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_battle_bg_bug1709_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-battle-bg love .
--
-- No POKEPORT_SPEED: the shots land a fixed number of frames after a
-- transition, and a logic clock running ahead of the render moves them.
local U = require("tests.drivers.util")

local Chrome = require("src.ui.gen2.Chrome")
local Mon = require("src.battle.gen2.Mon")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Permissions = require("src.world.gen2.Permissions")
local Save = require("src.core.gen2.Save")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-battle-bg"
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("[battlebg] ok   " .. label)
    else
      failures = failures + 1
      print("[battlebg] FAIL " .. label .. " " .. tostring(detail))
    end
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  local function shot(path)
    if not U.shot(game, path) then failures = failures + 1 end
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  -- ---- what the eye cannot check -----------------------------------------
  -- Each of these fails the same way the bug did: the void just stays white.
  ok("battleBg has a default in the Gold options table",
    Save.DEFAULT_OPTIONS.battleBg == "white", Save.DEFAULT_OPTIONS.battleBg)

  local bgRow
  for i, row in ipairs(OptionsMenu.ROWS) do
    if row.label == "BATTLE BG" then bgRow = i end
  end
  ok("OPTION carries a BATTLE BG row", bgRow ~= nil, bgRow)
  if bgRow then
    ok("and it is the last row before CANCEL",
      OptionsMenu.ROWS[bgRow + 1] and OptionsMenu.ROWS[bgRow + 1].cancel == true,
      bgRow)
  end

  local battleModule = require("src.ui.gen2.BattleState")
  ok("the Gold battle screen answers bgMode",
    type(battleModule.bgMode) == "function", type(battleModule.bgMode))
  ok("and Game2 owns the repaint, not the battle screen",
    type(game.paintBattleSurround) == "function",
    type(game.paintBattleSurround))

  -- At the letterbox size there is no void, so nothing below would show.
  if love.window and love.window.setMode then
    love.window.setMode(1280, 840, { resizable = true })
    U.wait(6)
  end
  local winW, winH = love.graphics.getDimensions()
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  ok(("the window leaves a void to look at (%dx%d, panel at %d,%d x%d)")
    :format(winW, winH, ox, oy, scale), ox > 8 and oy > 8, ox .. "," .. oy)

  local player = Mon.new(game.data, "CYNDAQUIL", 12)
  local wild = Mon.new(game.data, "PIDGEY", 4)
  ok("CYNDAQUIL builds from the extracted tables",
    player ~= nil and #player.moves > 0, player and #player.moves)
  ok("and so does the wild PIDGEY", wild ~= nil and #wild.moves > 0,
    wild and #wild.moves)
  game.save.party = { player }
  game.save.inventory = { POKE_BALL = 5, POTION = 3 }

  -- maps/Route29.asm:432, the teacher's WALK_LEFT_RIGHT lane, so (15,11) and
  -- its neighbours are floor; a map edit that moves it falls back below.
  assert(world:setMap("ROUTE_29", 15, 11, "down"), "setMap ROUTE_29 failed")
  U.wait(8)
  if not Permissions.isWalkable(world:playerCollision()) then
    for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 2, 0 }, { -2, 0 } }) do
      if world:setMap("ROUTE_29", 15 + step[1], 11 + step[2], "down")
          and Permissions.isWalkable(world:playerCollision()) then
        break
      end
    end
    U.wait(8)
  end
  ok("the player is standing on floor, not in a wall",
    Permissions.isWalkable(world:playerCollision()),
    tostring(world:playerCollision()))

  print(failures == 0
    and "[battlebg] preflight PASS -- the shots below are worth looking at"
    or ("[battlebg] preflight FAIL (%d) -- fix these before judging a pixel")
      :format(failures))

  -- ---- the run -----------------------------------------------------------
  -- Start from WHITE whatever the gold-dev identity was left on, so the first
  -- half of the run is the same every time.
  game.options.battleBg = "white"
  shot(out .. "/00-route29.png")

  -- OPTION, walked to off the START menu the way a player gets there.
  tap("start")
  local startMenu = game.stack:top()
  ok("START opened the menu", startMenu ~= nil and startMenu.items ~= nil,
    startMenu)
  if startMenu and startMenu.list then
    for _ = 1, #startMenu.items do
      local item = startMenu.items[startMenu.list.index]
      if item and item.value == "option" then break end
      tap("down", 3)
    end
    local landed = startMenu.items[startMenu.list.index]
    ok("the cursor found OPTION", landed and landed.value == "option",
      landed and landed.value)
  end
  tap("a", 10)

  local options = game.stack:top()
  ok("the OPTION screen is up", options ~= nil and options.rows ~= nil, options)
  if options then
    -- UP from the first row wraps onto CANCEL, so BATTLE BG is two presses
    -- away however many rows the build has.
    for _ = 1, #options.rows do
      if options:row() and options:row().key == "battleBg" then break end
      tap("up", 3)
    end
    local row = options:row()
    ok("the cursor is on BATTLE BG", row and row.key == "battleBg",
      row and row.label)
    U.log("01: the OPTION screen, cursor on BATTLE BG. it should read WHITE,")
    U.log("sitting under MAX FPS and above CANCEL.")
    shot(out .. "/01-option-white.png")
    tap("right", 6)
    ok("right stored black", game.options.battleBg == "black",
      game.options.battleBg)
    U.log("02: same row after one press right. it should read BLACK, and no")
    U.log("other row on screen should have changed.")
    shot(out .. "/02-option-black.png")
  end
  -- Gold plays with an empty stack: the world is not a state, so "back on the
  -- map" is nothing on top rather than the overworld being on top.
  tap("b", 10)
  for _ = 1, 20 do
    if game.stack:top() == nil then break end
    tap("b", 4)
  end
  ok("the menus closed", game.stack:top() == nil, game.stack:top())

  U.log("03: Route 29 with BATTLE BG on BLACK. the overworld is not a battle,")
  U.log("so there must be NO black bars here -- the surround around the map is")
  U.log("whatever VOID FILL draws, exactly as it was before.")
  shot(out .. "/03-route29-black-set.png")

  -- ---- the battle --------------------------------------------------------
  assert(world:startBattle({ wild = wild }), "startBattle failed")
  local battle
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  ok("the battle screen came up after the transition", battle ~= nil, battle)
  if not battle then
    print(("[battlebg] FAIL no battle to shoot (%d)"):format(failures))
    while true do coroutine.yield() end
  end
  for _ = 1, 150 do
    if battle.phase == "menu" then break end
    tap("a", 2)
  end
  ok("the battle reached the FIGHT menu", battle.phase == "menu", battle.phase)
  ok("and it reports the black surround",
    battle:bgMode() == "black", battle:bgMode())
  U.wait(10)

  U.log("04: the battle on BLACK. the void on all four sides of the GB screen")
  U.log("is solid black; the battle's own field, HUD and message box stay")
  U.log("white. black creeping over the panel edge -- a dark frame eating a")
  U.log("row of the HUD or the box border -- is the band maths being wrong.")
  shot(out .. "/04-battle-black.png")

  -- The 2x2 is FIGHT, <PK><MN> / PACK, RUN.  Clamp onto FIGHT first and step
  -- from there: one cell off is RUN, which ends the battle instead of a menu.
  local function pointAt(index)
    tap("left", 3)
    tap("up", 3)
    if index == 2 or index == 4 then tap("right", 3) end
    if index == 3 or index == 4 then tap("down", 3) end
    return battle.menuIndex == index
  end

  ok("the cursor is on PKMN", pointAt(2), battle.menuIndex)
  tap("a", 12)
  ok("the party list opened over the battle", battle.phase == "submenu",
    battle.phase)
  U.log("05: the party list over the same battle. this is the one that used to")
  U.log("go wrong: the surround must still be black. white returning the")
  U.log("instant the list goes up means the repaint is on the wrong layer.")
  shot(out .. "/05-party-over-black.png")
  tap("b", 12)

  ok("the cursor is on PACK", pointAt(3), battle.menuIndex)
  tap("a", 14)
  U.log("06: the PACK over the battle, same rule -- still black behind it.")
  shot(out .. "/06-pack-over-black.png")
  tap("b", 12)
  for _ = 1, 20 do
    if battle.phase == "menu" then break end
    tap("b", 4)
  end

  -- SCREEN POS moves the panel off centre, which is the other way the bands
  -- can stop lining up with where the panel actually landed.
  local positions = {
    { 7, "upper", "the panel sits high, so the black above it is thin and",
      "the band below is deep. both stop dead at the panel edge." },
    { 8, "top", "the panel is flush with the top, so there is no black",
      "above it at all. a band up there means the lift was ignored." },
  }
  for _, pos in ipairs(positions) do
    game.options.screenPos = pos[2]
    game:applyOptions()
    U.wait(8)
    local px, py = Chrome.fitOrigin(love.graphics.getDimensions())
    U.log(("0%d: SCREEN POS %s, panel at %d,%d."):format(
      pos[1], pos[2], px, py))
    U.log(pos[3])
    U.log(pos[4])
    shot(out .. ("/0%d-screenpos-%s.png"):format(pos[1], pos[2]))
  end
  game.options.screenPos = "center"
  game:applyOptions()
  U.wait(8)

  -- The no-regression half: WHITE has to look exactly like it always did.
  game.options.battleBg = "white"
  U.wait(6)
  ok("and back to white", battle:bgMode() == "white", battle:bgMode())
  U.log("09: the same battle flipped back to WHITE. paper white all the way to")
  U.log("the window edge, no seam where the panel ends -- compare it with 04.")
  shot(out .. "/09-battle-white.png")

  ok("back on PKMN for the white pair", pointAt(2), battle.menuIndex)
  tap("a", 12)
  U.log("10: the party list over the white battle, for the same comparison.")
  shot(out .. "/10-party-over-white.png")
  tap("b", 12)

  game.options.battleBg = "black"
  U.wait(6)

  print(failures == 0 and "[battlebg] PASS gold_battle_bg_bug1709"
    or ("[battlebg] FAIL gold_battle_bg_bug1709 (%d)"):format(failures))
  U.log("the battle is still up on BLACK and the controls are yours. leaving")
  U.log("the OPTION screen wrote BLACK into the gold-dev options.lua, so the")
  U.log("next boot starts there; set it back from OPTION if you want white.")

  while true do coroutine.yield() end
end
