-- maps/Route29.asm:432
--   POKEPORT_IDENTITY=gold-sep04 POKEPORT_VERSION=gold POKEPORT_GAME=gold \
--     POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_battle_hud_extended_bug1709_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-battle-hud love .
local U = require("tests.drivers.util")

local Chrome = require("src.ui.gen2.Chrome")
local Mon = require("src.battle.gen2.Mon")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Permissions = require("src.world.gen2.Permissions")
local WideBattle = require("src.ui.gen2.WideBattle")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-battle-hud"
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("[hud] ok   " .. label)
    else
      failures = failures + 1
      print("[hud] FAIL " .. label .. " " .. tostring(detail))
    end
  end

  local function finish()
    print(failures == 0 and "[hud] PASS gold_battle_hud_extended_bug1709"
      or ("[hud] FAIL gold_battle_hud_extended_bug1709 (%d)"):format(failures))
    U.wait(2)
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
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

  local hudRow, hudIndex, layoutIndex
  for i, row in ipairs(OptionsMenu.ROWS) do
    if row.label == "BATTLE HUD" then hudRow, hudIndex = row, i end
    if row.label == "BATTLE LAYOUT" then layoutIndex = i end
  end
  ok("OPTION carries a BATTLE HUD row", hudRow ~= nil, hudRow)
  ok("straight after BATTLE LAYOUT", hudIndex and layoutIndex
    and hudIndex == layoutIndex + 1, tostring(hudIndex))
  if hudRow then
    ok("OG reads STANDARD whatever is stored",
      hudRow.text({ battleLayout = "og", battleHud = "extended" }) == "STANDARD",
      hudRow.text({ battleLayout = "og", battleHud = "extended" }))
    ok("WIDE + extended reads EXTENDED",
      hudRow.text({ battleLayout = "wide", battleHud = "extended" })
        == "EXTENDED", "text")
  end

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
    and "[hud] preflight PASS -- the shots below are worth looking at"
    or ("[hud] preflight FAIL (%d) -- fix these before judging a pixel")
      :format(failures))

  game.options.battleLayout = "wide"
  game.options.battleHud = "extended"
  game.options.battleFit = "fixed"
  game.options.battleBg = "white"
  U.wait(6)

  assert(world:startBattle({ wild = wild }), "startBattle failed")
  local battle
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  ok("the battle screen came up after the transition", battle ~= nil, battle)
  if not battle then finish() end
  ok("and it reports the wide layout", battle:wideLayout() == true,
    battle:wideLayout())
  ok("and the extended HUD", battle:extendedHUD() == true,
    battle:extendedHUD())

  for _ = 1, 150 do
    if battle.phase == "menu" then break end
    tap("a", 2)
  end
  ok("the battle reached the FIGHT menu", battle.phase == "menu", battle.phase)
  U.wait(10)

  U.log("00: FIXED + WHITE, EXTENDED. the field (both pics, grass, bases) is")
  U.log("centred exactly where WIDE puts it. the foe's name/level/HP block")
  U.log("is docked at the TOP edge of the window, same x as before. the")
  U.log("message box and FIGHT/PKMN/PACK/RUN window sit flush on the BOTTOM")
  U.log("edge, 38 tiles wide, and CYNDAQUIL's panel sits directly on top of")
  U.log("the menu box in the right margin. SCREEN POS moves the field, not")
  U.log("the docked blocks.")
  shot(out .. "/00-extended-white-menu.png")

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
  U.log("01: the FIGHT list docked with the bottom group; MoveInfoBox (TYPE/")
  U.log("and PP) rides with it at the bottom-left, not left behind on the")
  U.log("field.")
  shot(out .. "/01-extended-moves.png")
  tap("a", 30)

  U.log("02: a move going off. the FIELD shakes and flashes; the docked top")
  U.log("and bottom groups must hold perfectly still.")
  shot(out .. "/02-extended-anim.png")
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    tap("a", 3)
  end
  ok("back at the menu", battle.phase == "menu", battle.phase)

  battle.statsBoxMon = player
  battle.phase = "stats-box"
  U.wait(4)
  ok("the stats box undocks the HUDs", WideBattle.docked(battle) == false,
    WideBattle.docked(battle))
  U.log("03: the level-up stats box. the cart draws it over the player HUD")
  U.log("(hlcoord 9,0, 12 rows by 11 cols), so both HUDs fall back to their")
  U.log("WIDE places under it for as long as it is up; the box covers")
  U.log("CYNDAQUIL's panel the way it does on OG. nothing clipped.")
  shot(out .. "/03-extended-stats-box.png")
  battle.statsBoxMon = nil
  battle.phase = "menu"
  U.wait(4)

  ok("the cursor is on PKMN", pointAt(2), battle.menuIndex)
  tap("a", 12)
  U.log("04: the party list over it. the battle is no longer the top state,")
  U.log("so the HUDs fall back to their in-surface WIDE places; the list is")
  U.log("centred on the 160 grid.")
  shot(out .. "/04-party-over-extended.png")
  tap("b", 12)
  for _ = 1, 20 do
    if battle.phase == "menu" then break end
    tap("b", 4)
  end
  ok("back at the menu after the list", battle.phase == "menu", battle.phase)

  game.options.battleBg = "black"
  U.wait(8)
  ok("FIXED + BLACK still extends", battle:extendedBlackHUD() == true,
    battle:extendedBlackHUD())
  U.log("05: FIXED + BLACK. a paper column the composition's width runs the")
  U.log("full window height with the docked blocks on it; only the two side")
  U.log("bars are black, no black above or below the field.")
  shot(out .. "/05-extended-black.png")

  game.options.battleBg = "world"
  U.wait(8)
  ok("FIXED + WORLD still extends", battle:extendedWorldHUD() == true,
    battle:extendedWorldHUD())
  U.log("06: FIXED + WORLD. Route 29 UNDIMMED at the sides, the same paper")
  U.log("column through the middle.")
  shot(out .. "/06-extended-world.png")

  game.options.battleBg = "black"
  game.options.battleFit = "fill"
  U.wait(8)
  ok("FILL + EXTENDED forces a white bg", battle:bgMode() == "white",
    battle:bgMode())
  ok("and still extends", battle:extendedHUD() == true, battle:extendedHUD())
  U.log("07: FILL + EXTENDED with BLACK stored. the surround is WHITE")
  U.log("regardless; the 304 surface fills the window and the blocks dock to")
  U.log("its edges.")
  shot(out .. "/07-extended-fill.png")
  game.options.battleFit = "fixed"
  game.options.battleBg = "white"
  U.wait(8)

  if love.window and love.window.setMode then
    love.window.setMode(960, 540, { resizable = true })
    U.wait(8)
  end
  U.log("08: 960x540, FIXED + WHITE. a 16:9 window: the foe block at the top")
  U.log("edge, the bottom group on the bottom edge, the field between.")
  shot(out .. "/08-extended-960x540.png")
  if love.window and love.window.setMode then
    love.window.setMode(1280, 840, { resizable = true })
    U.wait(8)
  end

  game.options.battleHud = "standard"
  U.wait(8)
  ok("STANDARD stops extending", battle:extendedHUD() == false,
    battle:extendedHUD())
  U.log("09: back on STANDARD. the WIDE composition the port shipped before")
  U.log("this change: both HUDs back in the 304 surface's margins, the bottom")
  U.log("windows on the surface's own bottom row, nothing docked.")
  shot(out .. "/09-standard-unchanged.png")

  game.options.battleLayout = "og"
  game.options.battleHud = "extended"
  U.wait(10)
  ok("OG reads og again", battle:wideLayout() == false, battle:wideLayout())
  ok("and never extends", battle:extendedHUD() == false, battle:extendedHUD())
  if hudRow then
    ok("the row reads STANDARD under OG",
      hudRow.text(game.options) == "STANDARD", hudRow.text(game.options))
  end
  U.log("10: OG with extended still stored. the cart layout, untouched; the")
  U.log("OPTION row would read STANDARD.")
  shot(out .. "/10-og-unchanged.png")

  finish()
end
