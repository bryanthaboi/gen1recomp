-- maps/Route29.asm:432
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_battle_layout_wide_bug1709_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-battle-wide love .
local U = require("tests.drivers.util")

local Chrome = require("src.ui.gen2.Chrome")
local Mon = require("src.battle.gen2.Mon")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Permissions = require("src.world.gen2.Permissions")
local WideBattle = require("src.ui.gen2.WideBattle")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-battle-wide"
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("[wide] ok   " .. label)
    else
      failures = failures + 1
      print("[wide] FAIL " .. label .. " " .. tostring(detail))
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

  local layoutRow
  for _, row in ipairs(OptionsMenu.ROWS) do
    if row.label == "BATTLE LAYOUT" then layoutRow = row end
  end
  ok("OPTION carries a BATTLE LAYOUT row", layoutRow ~= nil, layoutRow)
  if layoutRow then
    ok("and WIDE is on its ladder", layoutRow.display.wide == "WIDE",
      layoutRow.display.wide)
  end
  ok("the wide surface is 304x144",
    WideBattle.WIDTH == 304 and WideBattle.HEIGHT == 144, WideBattle.WIDTH)

  if love.window and love.window.setMode then
    love.window.setMode(1280, 840, { resizable = true })
    U.wait(6)
  end
  local winW, winH = love.graphics.getDimensions()
  local wideScale = Chrome.fitScaleFor(winW, winH, WideBattle.TILES_W,
    WideBattle.TILES_H)
  local ox, oy = Chrome.fitOriginFor(winW, winH, wideScale,
    WideBattle.TILES_W, WideBattle.TILES_H)
  ok(("the wide panel fits (%dx%d, at %d,%d x%d)")
    :format(winW, winH, ox, oy, wideScale), ox >= 0 and oy >= 0,
    ox .. "," .. oy)

  local player = Mon.new(game.data, "CYNDAQUIL", 12)
  local wild = Mon.new(game.data, "PIDGEY", 4)
  ok("CYNDAQUIL builds from the extracted tables",
    player ~= nil and #player.moves > 0, player and #player.moves)
  game.save.party = { player }
  game.save.inventory = { POKE_BALL = 5, POTION = 3 }

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
    and "[wide] preflight PASS -- the shots below are worth looking at"
    or ("[wide] preflight FAIL (%d) -- fix these before judging a pixel")
      :format(failures))

  game.options.battleLayout = "wide"
  U.wait(6)

  assert(world:startBattle({ wild = wild }), "startBattle failed")
  local battle
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  ok("the battle screen came up after the transition", battle ~= nil, battle)
  if not battle then
    print(("[wide] FAIL no battle to shoot (%d)"):format(failures))
    while true do coroutine.yield() end
  end
  ok("and it reports the wide layout", battle:wideLayout() == true,
    battle:wideLayout())
  local pw, ph = battle:panelSize()
  ok("composing on 304x144", pw == 304 and ph == 144, pw .. "x" .. ph)

  for _ = 1, 150 do
    if battle.phase == "menu" then break end
    tap("a", 2)
  end
  ok("the battle reached the FIGHT menu", battle.phase == "menu", battle.phase)
  U.wait(10)

  U.log("00: the command menu on WIDE. the field (both pics, the grass, the")
  U.log("bases) is the cart's 160x144 picture, centred, untouched. the foe's")
  U.log("HP bar sits out in the LEFT margin at its cart tiles, yours out in")
  U.log("the RIGHT one. the message box and the FIGHT/PKMN/PACK/RUN window")
  U.log("run the full 38 tiles across the bottom, and the four labels are")
  U.log("hard against the right edge. anything clipped at 160 is the")
  U.log("surface push being wrong.")
  shot(out .. "/00-wide-menu.png")

  local function pointAt(index)
    tap("left", 3)
    tap("up", 3)
    if index == 2 or index == 4 then tap("right", 3) end
    if index == 3 or index == 4 then tap("down", 3) end
    return battle.menuIndex == index
  end

  ok("the cursor is on FIGHT", pointAt(1), battle.menuIndex)
  tap("a", 14)
  ok("the move list opened", battle.phase == "moves", battle.phase)
  U.log("01: the FIGHT list on WIDE. the name list stretches to the right")
  U.log("edge; MoveInfoBox (TYPE/ and the PP) stays where the cart puts it,")
  U.log("bottom left, unmoved.")
  shot(out .. "/01-wide-moves.png")
  tap("a", 30)

  U.log("02: a move going off. the FIELD shakes and flashes; the two HUD")
  U.log("blocks out in the margins must hold perfectly still, and the ▼")
  U.log("prompt must sit in the bottom-right corner of the WIDE message box,")
  U.log("not 18 tiles in.")
  shot(out .. "/02-wide-anim.png")
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    tap("a", 3)
  end

  ok("back at the menu", battle.phase == "menu", battle.phase)
  ok("the cursor is on PKMN", pointAt(2), battle.menuIndex)
  tap("a", 12)
  U.log("03: the party list over the wide battle. it is a 160-wide screen and")
  U.log("must land CENTRED in the 304 surface, on the same pixel grid -- not")
  U.log("hard left, not at a different scale.")
  shot(out .. "/03-party-over-wide.png")
  tap("b", 12)
  for _ = 1, 20 do
    if battle.phase == "menu" then break end
    tap("b", 4)
  end

  game.options.battleFit = "fill"
  U.wait(8)
  U.log("04: WIDE + BATTLE SIZE on FILL. the 304 surface stretches to the")
  U.log("window, still whole-grid, nothing cut off either side.")
  shot(out .. "/04-wide-fill.png")
  game.options.battleFit = "fixed"
  U.wait(8)

  game.options.battleBg = "black"
  U.wait(8)
  U.log("05: WIDE + BATTLE BG on BLACK. the bars must hug the 304 rect, not")
  U.log("the 160 one -- black creeping over the margins where the HUDs live")
  U.log("is the surround reading the wrong panel size.")
  shot(out .. "/05-wide-black.png")

  ok("the cursor is on PKMN under BLACK", pointAt(2), battle.menuIndex)
  tap("a", 12)
  U.log("05b: the party list over a WIDE + BLACK battle. the black must still")
  U.log("hug the 304 rect -- side bands intact, no white void left on any")
  U.log("edge. the list itself lands centred on the 160 grid.")
  shot(out .. "/05b-party-over-wide-black.png")
  tap("b", 12)
  for _ = 1, 20 do
    if battle.phase == "menu" then break end
    tap("b", 4)
  end

  game.options.battleBg = "world"
  U.wait(8)
  U.log("06: WIDE + WORLD. Route 29 dimmed around the whole wide rect. note")
  U.log("the known cosmetic: during a per-scanline BGP effect the margins")
  U.log("stay paper while the 160 field flashes.")
  shot(out .. "/06-wide-world.png")
  game.options.battleBg = "white"
  U.wait(8)

  game.options.battleLayout = "og"
  U.wait(10)
  ok("OG reads og again", battle:wideLayout() == false, battle:wideLayout())
  local ogW = select(1, battle:panelSize())
  ok("and composes on 160 again", ogW == 160, ogW)
  U.log("07: the same battle back on OG. this must be pixel-for-pixel the")
  U.log("screen the port shipped before this change -- HUDs at their cart")
  U.log("tiles, 20-tile message box, ▼ at (18,17).")
  shot(out .. "/07-og-unchanged.png")

  game.options.battleLayout = "wide"
  U.wait(8)

  print(failures == 0 and "[wide] PASS gold_battle_layout_wide_bug1709"
    or ("[wide] FAIL gold_battle_layout_wide_bug1709 (%d)"):format(failures))
  U.log("the battle is still up on WIDE and the controls are yours.")

  while true do coroutine.yield() end
end
