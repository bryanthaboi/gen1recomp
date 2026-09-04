-- engine/pikachu/pikachu_movement.asm:88
-- EmotionBubble (engine/overworld/emotion_bubbles.asm:60)
-- (engine/pikachu/pikachu_emotions.asm:14)
-- BillsHouseScript0 actually runs.  No POKEPORT_SPEED: it scales the logic
--   POKEPORT_DRIVER=tests/drivers/bills_pikachu_bug2165_test.lua POKEPORT_IDENTITY=bug2165 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function idle()
    while true do coroutine.yield() end
  end

  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    U.log("Re-run with POKEPORT_VERSION=yellow.")
    idle()
  end

  local MAP, STAND = "BILLS_HOUSE", { x = 3, y = 6, facing = "up" }

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "bryan"
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.flags.EVENT_MET_BILL = nil
  game.save.flags.EVENT_MET_BILL_2 = nil
  game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = nil
  game.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = nil
  game.save.pikachuMapScriptActive = nil

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)

  local ow = game.overworld
  if not check("Bill's House loaded", ow ~= nil and ow.map
               and ow.map.id == MAP) then
    idle()
  end

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  local npc = follower()
  if not check("the follower spawned", npc ~= nil) then idle() end
  check("the confused beat started", ow.pikachuBillsScene == true)
  check("the follower never rolls its own facing (#2117 pin)",
        npc.wanders == false)
  check("the scripted walk uses the 16-frame Pikachu step",
        npc.stepFrames == 16)

  for frame = 0, 64, 16 do
    U.shot(game, SHOT_DIR .. "/bug2165_walk_" .. frame .. ".png")
    U.wait(15)
  end

  local sawBubble = false
  for _ = 1, 240 do
    if ow.emote and ow.emote.bubble and not ow.emote.pikaPic then
      sawBubble = true
      break
    end
    U.wait(1)
  end
  check("the silent 60-frame question bubble comes up first", sawBubble)
  if sawBubble then
    U.shot(game, SHOT_DIR .. "/bug2165_bubble.png")
  end

  local sawPic = false
  for _ = 1, 240 do
    if ow.emote and ow.emote.pikaPic then sawPic = true break end
    U.wait(1)
  end
  check("the emotion animation follows it", sawPic)
  if sawPic then
    check("and it is the emotion's own pikapic, not the battle front pic",
          ow.emote.pikaPic:find("pikachu/pikapic_", 1, true) ~= nil)
    check("a scripted emotion cannot be mashed away",
          ow.emote.skippable ~= true)
    U.shot(game, SHOT_DIR .. "/bug2165_pikapic.png")
  end
  U.log("listen for PikachuCry19 under the box; shots in", SHOT_DIR)

  idle()
end
