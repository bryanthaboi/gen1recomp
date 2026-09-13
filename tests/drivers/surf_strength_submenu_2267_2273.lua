--   POKEPORT_IDENTITY=red-sep04 POKEPORT_SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/surf_strength_submenu_2267_2273.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local PartyMenu = require("src.ui.PartyMenu")
  local Music = require("src.core.Music")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end

  local function giveMon(species, move)
    local mon = Pokemon.new(game.data, species, 30)
    mon.moves = { { id = move, pp = 15 } }
    game.save.party = { mon }
    return mon
  end

  local function openFieldMove(action)
    local pm = PartyMenu.new(game)
    game.stack:push(pm)
    U.wait(4)
    U.tap(game, "a")
    U.wait(4)
    for i, item in ipairs(pm.subItems or {}) do
      if item.action == action then pm.subIndex = i end
    end
    U.shot(game, DIR .. "/2273_00_" .. action .. "_submenu_open.png")
    U.tap(game, "a")
    return pm
  end

  local function drainText()
    for _ = 1, 400 do
      local top = game.stack:top()
      if top == game.overworld then return end
      U.tap(game, "a")
      U.wait(2)
    end
  end

  U.newGame(game)
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 5
  game.save.inventory.SOULBADGE = true
  game.save.inventory.RAINBOWBADGE = true
  game.save.inventory.BOULDERBADGE = true

  giveMon("MACHOP", "STRENGTH")
  U.teleport(game, "SEAFOAM_ISLANDS_1F", 17, 10, "right")
  local pmStr = openFieldMove("strength")
  U.wait(6)
  check(game.stack:top() ~= pmStr and not pmStr.submenu, "2273_strength_submenu_erased")
  U.shot(game, DIR .. "/2273_01_strength_text_no_options_box.png")
  drainText()
  U.wait(40)

  giveMon("PIKACHU", "FLASH")
  game.save.flashLit = false
  U.teleport(game, "ROCK_TUNNEL_1F", 15, 4, "down")
  local pmFlash = openFieldMove("flash")
  U.wait(6)
  check(game.stack:top() ~= pmFlash and not pmFlash.submenu, "2273_flash_submenu_erased")
  U.shot(game, DIR .. "/2273_02_flash_text_no_options_box.png")
  drainText()
  U.wait(40)

  giveMon("SQUIRTLE", "SURF")
  U.teleport(game, "PALLET_TOWN", 4, 13, "down")
  game.overworld.player.surfing = false
  local pmSurf = openFieldMove("surf")
  U.wait(6)
  check(game.stack:top() ~= pmSurf and not pmSurf.submenu, "2267_surf_submenu_erased")
  check(Music.current() == Music.special(game.data, "surf"), "2267_surf_music_with_got_on_text")
  U.shot(game, DIR .. "/2267_03_got_on_text_surf_music_no_options_box.png")
  drainText()
  U.wait(60)

  local function parkSurfing()
    U.teleport(game, "PALLET_TOWN", 4, 14, "up")
    local ow = game.overworld
    ow.player.surfing = true
    ow:syncSurfingPikachu()
    Music.playMap(game.data, ow.map.id, false, true)
    U.wait(30)
    return ow
  end

  local ow = parkSurfing()
  local startFrame, landFrame, swapFrame
  for _ = 1, 60 do
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    U.wait(1)
    local p = ow.player
    if not startFrame and p.moving then startFrame = U.frame() end
    if startFrame and not swapFrame and not p.surfing then swapFrame = U.frame() end
    if startFrame and not landFrame and p.cellY == 13 then landFrame = U.frame(); break end
  end
  game.input.state.up = false
  check(startFrame ~= nil and landFrame ~= nil, "2267_walk_off_step_ran")
  check(swapFrame ~= nil and startFrame ~= nil and swapFrame <= startFrame
        and (landFrame == nil or swapFrame < landFrame), "2267_walk_off_swap_before_landing")
  U.wait(30)

  ow = parkSurfing()
  local shotTaken = false
  for _ = 1, 60 do
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    U.wait(1)
    if ow.player.moving and not shotTaken then
      game.input.state.up = false
      check(not ow.player.surfing and ow.player.cellY == 14, "2267_walk_off_mid_step_walking")
      U.shot(game, DIR .. "/2267_04_walk_off_mid_step_walking_sprite.png")
      shotTaken = true
      break
    end
  end
  game.input.state.up = false
  check(shotTaken, "2267_walk_off_mid_step_shot")

  print(fails == 0 and "PASS surf_strength_submenu_2267_2273" or "FAIL surf_strength_submenu_2267_2273")
  love.event.quit(fails == 0 and 0 or 1)
end
