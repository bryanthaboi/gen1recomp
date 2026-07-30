-- Manual check that STRENGTH / SURF / FLASH print their message over the
-- party menu and only then blink it away (#385).  pokered
-- engine/menus/start_sub_menus.asm .flash/.strength/.surf all run PrintText
-- -> GBPalWhiteOutWithDelay3 -> jp .goBackToMap, so the menu is the backdrop
-- of the text and the blink is the menu closing.  No POKEPORT_SPEED here:
--   POKEPORT_DRIVER=tests/drivers/field_move_layer_bug385_test.lua POKEPORT_IDENTITY=bug385 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local PartyMenu = require("src.ui.PartyMenu")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(ok, msg)
    U.log(ok and "PASS" or "FAIL", msg)
    if not ok then fails = fails + 1 end
    return ok
  end

  U.newGame(game)
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 5 -- SLOW: the shot lands while it types
  local vol = game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the STRENGTH cry will be silent, turn SFX up in OPTION")
  else
    U.log("sfxVol =", tostring(vol), "-- STRENGTH plays the mon's cry over the text")
  end

  -- every badge the three field moves are gated on at list time
  game.save.inventory.BOULDERBADGE = true
  game.save.inventory.SOULBADGE = true
  game.save.inventory.RAINBOWBADGE = true

  for _, key in ipairs({ "_UsedStrengthText", "_CanMoveBouldersText",
                         "_SurfingGotOnText", "_FlashLightsAreaText" }) do
    local t = game.data.text[key]
    check(type(t) == "string" and t ~= "", key .. " extracted from the ROM")
  end

  local function giveMon(species, move)
    local mon = Pokemon.new(game.data, species, 30)
    mon.moves = { { id = move, pp = 15 } }
    game.save.party = { mon }
    return mon
  end

  -- park on `cell` if it is free, else on any walkable neighbour of the
  -- target that looks back at it (a map edit or a mod moves objects)
  local function stand(mapId, cell, target)
    U.teleport(game, mapId, cell.x, cell.y, cell.facing)
    local ow = game.overworld
    if ow.map:isWalkableCell(cell.x, cell.y) and not ow:npcAtCell(cell.x, cell.y) then
      return ow
    end
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = target.x + s[1], target.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(cell.x, cell.y),
              cx, cy, "facing", s[3])
        U.teleport(game, mapId, cx, cy, s[3])
        return game.overworld
      end
    end
    return ow
  end

  -- START -> POKéMON -> the mon -> the field-move row, by looking the rows
  -- up rather than counting presses (a mod can insert either list)
  local function openFieldMove(action)
    U.tap(game, "start")
    U.wait(12)
    local menu = game.stack:top()
    local row
    for i, it in ipairs(menu and menu.items or {}) do
      if tostring(it.label):upper():find("MON", 1, true) then row = i break end
    end
    if not check(row ~= nil, "START menu lists POKéMON") then return nil end
    for _ = 2, row do U.tap(game, "down"); U.wait(2) end
    U.tap(game, "a")
    U.wait(12)
    local pm = game.stack:top()
    if not check(getmetatable(pm) == PartyMenu, "POKéMON opens the party menu") then
      return nil
    end
    U.tap(game, "a") -- A on the mon builds the field-move submenu
    U.wait(8)
    local sub
    for i, it in ipairs(pm.subItems or {}) do
      if it.action == action then sub = i break end
    end
    if not check(sub ~= nil, action:upper() .. " is listed in the submenu") then
      return nil
    end
    for _ = 2, sub do U.tap(game, "down"); U.wait(2) end
    U.tap(game, "a")
    return pm
  end

  -- the state the compositor starts from (StateStack:draw walks up from the
  -- highest opaque state): what is actually behind the message
  local function backdrop()
    return game.stack.states[game.stack:visibleBase()]
  end
  local function textIsUp()
    local top = game.stack:top()
    return top ~= nil and top.pages ~= nil
  end
  local function drainText()
    for _ = 1, 400 do
      if not textIsUp() then break end
      U.tap(game, "a")
      U.wait(3)
    end
  end

  -- ---------------------------------------------------------------- STRENGTH
  -- pokered data/maps/objects/SeafoamIslands1F.asm: BOULDER1 at (18, 10),
  -- so the floor to its west is the approach cell
  giveMon("MACHOP", "STRENGTH")
  local ow = stand("SEAFOAM_ISLANDS_1F", { x = 17, y = 10, facing = "right" },
                   { x = 18, y = 10 })
  check(ow:npcAtCell(18, 10) ~= nil, "the Seafoam boulder is loaded at (18,10)")
  local pmStr = openFieldMove("strength")
  U.wait(6)
  check(textIsUp(), "STRENGTH puts a message up")
  check(backdrop() == pmStr, "the party menu is the backdrop of the STRENGTH text")
  U.shot(game, DIR .. "/bug385_strength.png")
  drainText()
  U.wait(60)

  -- ---------------------------------------------------------------- SURF
  -- pokered data/maps/objects/PalletTown.asm has no object on the south
  -- shore; (4, 13) is the land cell above the water at (4, 14)
  giveMon("SQUIRTLE", "SURF")
  ow = stand("PALLET_TOWN", { x = 4, y = 13, facing = "down" }, { x = 4, y = 13 })
  ow.player.surfing = false
  check(ow:useSurfFieldMove() == "ok", "(4,13) faces surfable water")
  local pmSurf = openFieldMove("surf")
  U.wait(6)
  check(textIsUp(), "SURF puts the got-on message up")
  check(backdrop() == pmSurf, "the party menu is the backdrop of the got-on text")
  U.shot(game, DIR .. "/bug385_surf.png")
  drainText()
  U.wait(60)
  U.shot(game, DIR .. "/bug385_surf_after.png")
  ow.player.surfing = false

  -- ---------------------------------------------------------------- FLASH
  -- pokered data/maps/objects/RockTunnel1F.asm: warp 1 is (15, 3), so
  -- (15, 4) is a real walkable cell just inside the entrance
  game.save.flashLit = false
  giveMon("PIKACHU", "FLASH")
  ow = stand("ROCK_TUNNEL_1F", { x = 15, y = 4, facing = "down" }, { x = 15, y = 3 })
  check(ow.dark == true, "ROCK_TUNNEL_1F is dark before FLASH")
  local pmFlash = openFieldMove("flash")
  U.wait(6)
  check(textIsUp(), "FLASH puts a message up")
  check(backdrop() == pmFlash, "the party menu is the backdrop of the FLASH text")
  check(ow.dark == true, "the tunnel is still dark while the FLASH text is up")
  U.shot(game, DIR .. "/bug385_flash_text.png")
  drainText()
  U.wait(40)
  check(ow.dark == false, "the tunnel is lit once the blink hands the map back")
  U.shot(game, DIR .. "/bug385_flash_after.png")

  U.log(fails == 0 and "all machine checks passed" or (fails .. " machine checks failed"))
  U.log("shots in", DIR)

  -- hand the pad back on a dark tunnel with FLASH still unused
  game.save.flashLit = false
  giveMon("PIKACHU", "FLASH")
  stand("ROCK_TUNNEL_1F", { x = 15, y = 4, facing = "down" }, { x = 15, y = 3 })

  U.log("You are in the dark tunnel with an unused FLASH: START, POKéMON, A, FLASH.")
  U.log("The message should read over the six-row party list, not a white screen,")
  U.log("and the tunnel should only be lit after the blink closes the menu.")
  U.log("Same for SURF and STRENGTH in the shots: party list behind the text,")
  U.log("one short blink, then the map.")

  while true do
    coroutine.yield()
  end
end
