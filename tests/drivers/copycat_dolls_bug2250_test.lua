-- data/maps/objects/CopycatsHouse2F.asm:22-23
-- engine/overworld/movement.asm:193,262-267,406
--   POKEPORT_SHOT_DIR=/tmp/shots POKEPORT_VERSION=red \
--     POKEPORT_DRIVER=tests/drivers/copycat_dolls_bug2250_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
                   or "/tmp/shots"
  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end
  local function quit()
    U.wait(2)
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local MAP = "COPYCATS_HOUSE_2F"

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "bryan"
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1

  local function findDoll(ow, textConst)
    for _, npc in ipairs(ow.npcs) do
      if npc.def and npc.def.text == textConst then return npc end
    end
  end

  local function talkFromSide(label, textConst, px, py, pface, toward, pin)
    U.teleport(game, MAP, px, py, pface)
    U.wait(10)
    local ow = game.overworld
    if not check(label .. ": room loaded", ow and ow.map and ow.map.id == MAP) then
      return
    end
    local p = ow.player
    p.cellX, p.cellY = px, py
    p.px, p.py = px * 16, py * 16
    p.facing = pface
    U.wait(2)
    local npc = findDoll(ow, textConst)
    if not check(label .. ": doll present", npc ~= nil) then return end
    check(label .. ": doll spawns on its pin " .. pin, npc.facing == pin)

    local opened = false
    for _ = 1, 6 do
      U.tap(game, "a")
      for _ = 1, 20 do
        U.wait(1)
        if game.stack:top() ~= ow then opened = true break end
      end
      if opened then break end
    end
    check(label .. ": text box opened", opened)
    check(label .. ": doll turned " .. toward .. " to the player",
          npc.facing == toward)
    U.shot(game, SHOT_DIR .. "/2250_" .. label .. "_1_turned_to_player.png")

    for _ = 1, 120 do
      if game.stack:top() == ow then break end
      U.tap(game, "a")
      U.wait(3)
    end
    if not check(label .. ": text box closed", game.stack:top() == ow) then
      return
    end

    local back
    for i = 1, 140 do
      U.wait(1)
      if npc.facing == pin then back = i break end
    end
    U.log(label, "frames until the pin came back:", tostring(back))
    check(label .. ": doll returned to " .. pin .. " within 130 frames",
          back ~= nil and back <= 130)
    U.shot(game, SHOT_DIR .. "/2250_" .. label .. "_2_back_on_pin.png")

    U.wait(300)
    check(label .. ": doll holds its pin afterwards", npc.facing == pin)
  end

  talkFromSide("bird", "TEXT_COPYCATSHOUSE2F_BIRD", 3, 0, "left", "right", "down")
  talkFromSide("fairy", "TEXT_COPYCATSHOUSE2F_FAIRY", 1, 5, "down", "up", "right")

  quit()
end
