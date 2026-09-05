-- pokeyellow scripts/PokemonFanClub.asm:36-60
-- data/pikachu/pikachu_emotions.asm:202
--   POKEPORT_IDENTITY=yellow-sep04 POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=tests/drivers/fanclub_pikachu_bug2190_test.lua \
--   POKEPORT_SHOT_DIR=/tmp/shots2190 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")
  local PF = require("src.world.PikachuFollower")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
                   or "/tmp/shots"

  local failures = 0
  local function check(label, ok, extra)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label, extra or "")
    return ok
  end

  local function finish()
    U.log(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("running as Yellow (needs POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    finish()
  end

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false
  game.save.pikachuMapScriptActive = nil
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.onBike = false
  game.save.player.name = "bryan"

  local wx, wy
  for _, w in ipairs(game.data.maps.VERMILION_CITY.warps or {}) do
    if w.destMap == "POKEMON_FAN_CLUB" then wx, wy = w.x, w.y end
  end
  if not check("Vermilion City has the Fan Club door", wx ~= nil) then finish() end

  U.teleport(game, "VERMILION_CITY", wx, wy + 1, "up")
  U.wait(20)
  for _ = 1, 300 do
    local ow = game.overworld
    if ow and ow.map and ow.map.id == "POKEMON_FAN_CLUB" then break end
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    coroutine.yield()
  end
  game.input.state.up = false
  for _ = 1, 240 do
    local ow = game.overworld
    if ow and ow.map and ow.map.id == "POKEMON_FAN_CLUB"
       and not ow.transitioning then
      break
    end
    coroutine.yield()
  end
  local ow = game.overworld
  if not check("walked into POKEMON_FAN_CLUB",
               ow.map and ow.map.id == "POKEMON_FAN_CLUB") then
    finish()
  end

  local npc = PF.current(ow)
  local p = ow.player
  if not check("the companion came in with the player", npc ~= nil) then
    finish()
  end

  check("spawns one cell right of the player",
        npc.cellX == p.cellX + 1 and npc.cellY == p.cellY,
        "player (" .. p.cellX .. "," .. p.cellY .. ") pika ("
        .. npc.cellX .. "," .. npc.cellY .. ")")

  local emote = ow.emote
  check("the scene opens on a bubble hold", emote ~= nil
        and type(emote.bubble) == "number")
  check("the bubble carries no framed pic yet", emote and not emote.pikaPic)
  check("and nothing is walking under it", not npc.moving)
  U.shot(game, SHOT_DIR .. "/2190_01_spawn_right_bang_bubble.png")

  local seen, walked, idle = {}, false, 0
  for _ = 1, 600 do
    if npc.moving then
      walked, idle = true, 0
      local f = npc.stepFrames
      if seen[#seen] ~= f then seen[#seen + 1] = f end
    elseif walked then
      idle = idle + 1
      if idle >= 8 then break end
    end
    coroutine.yield()
  end
  check("the companion walked the movement table", walked)
  check("the $26 slide opens the table at 32 frames", seen[1] == 32,
        "saw " .. table.concat(seen, ","))
  check("and the $20/$1e steps that follow cost 16", seen[2] == 16,
        "saw " .. table.concat(seen, ","))

  local slot3
  for _, other in ipairs(ow.npcs or {}) do
    if other.def and other.def.index == 3 then slot3 = other end
  end
  check("the map still has object 3", slot3 ~= nil)
  check("object 3 is the CLEFAIRY, not the Seel",
        slot3 and slot3.def.sprite == "SPRITE_CLEFAIRY",
        slot3 and tostring(slot3.def.sprite) or "")
  check("object 3 turned down to face Pikachu",
        slot3 and slot3.facing == "down" and slot3.movementStatus == 2)
  check("the walk ends directly below it",
        slot3 and npc.cellX == slot3.cellX and npc.cellY == slot3.cellY + 1,
        "pika (" .. npc.cellX .. "," .. npc.cellY .. ")")

  for _ = 1, 120 do
    if ow.emote then break end
    coroutine.yield()
  end
  emote = ow.emote
  check("emotion 29 raises the framed pic after the walk",
        emote ~= nil and emote.pikaPic ~= nil)
  check("and shows no bubble with it", emote and not emote.bubble)
  U.shot(game, SHOT_DIR .. "/2190_04_pic_after_walk.png")

  for _ = 1, 600 do
    if not ow.emote then break end
    coroutine.yield()
  end
  check("the map-script bit is set once the scene ends",
        game.save.pikachuMapScriptActive == true)
  U.wait(30)
  check("Pikachu is still drawn on the map after the scene",
        PF.at(ow, npc.cellX, npc.cellY) ~= nil)
  U.shot(game, SHOT_DIR .. "/2190_03_pika_at_clefairy.png")

  for _ = 1, 400 do
    if p.cellX >= npc.cellX and p.cellY <= npc.cellY + 1 then break end
    local dir = p.cellX < npc.cellX and "right" or "up"
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    coroutine.yield()
    game.input.state[dir] = false
  end
  U.wait(10)
  if p.cellY ~= npc.cellY + 1 or p.cellX ~= npc.cellX then
    U.hold(game, "up", 24)
    U.wait(10)
  end
  check("standing below the companion, facing it",
        p.cellX == npc.cellX and p.cellY == npc.cellY + 1
        and p.facing == "up",
        "player (" .. p.cellX .. "," .. p.cellY .. ") facing " .. p.facing)

  local facingBefore = npc.facing
  U.tap(game, "a")
  U.wait(4)
  emote = ow.emote
  check("the press answers with a bubble", emote ~= nil
        and type(emote.bubble) == "number")
  check("the heart bubble holds alone, no pic yet",
        emote and not emote.pikaPic)
  check("and the companion has not turned yet", npc.facing == facingBefore,
        "facing " .. tostring(npc.facing))
  U.shot(game, SHOT_DIR .. "/2190_05_heart_alone.png")

  for _ = 1, 240 do
    if ow.emote and ow.emote.pikaPic then break end
    coroutine.yield()
  end
  emote = ow.emote
  check("the bubble hands off to the framed pic",
        emote ~= nil and emote.pikaPic ~= nil)
  check("and pikaemotion_9 turned it toward the player",
        npc.facing == "down", "facing " .. tostring(npc.facing))
  U.shot(game, SHOT_DIR .. "/2190_06_turned_with_pic.png")

  finish()
end
