-- pokeyellow data/pikachu/pikachu_pic_animation.asm:77
-- pokeyellow data/pikachu/pikachu_pic_objects.asm:130
-- pokeyellow data/pikachu/pikachu_pic_tilemaps.asm:143
-- pokeyellow data/pikachu/pikachu_emotions.asm:69
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local PikachuFollower = require("src.world.PikachuFollower")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local failures = 0

  local function check(label, ok, detail)
    U.log(ok and "PASS" or "FAIL", label, detail and ("(" .. tostring(detail) .. ")") or "")
    if not ok then failures = failures + 1 end
    return ok
  end

  local function finish()
    U.log(failures == 0 and "ALL PASS" or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("running the Yellow cache", GameVersion.isYellow()) then finish() end

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "bryan"
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)
  local ow = game.overworld
  local npc
  for _, n in ipairs(ow.npcs or {}) do
    if n.pikachuFollower then npc = n end
  end
  if not check("the follower spawned", npc ~= nil) then finish() end

  local p = ow.player
  local dir, dx, dy
  for _, d in ipairs({ { "right", 1, 0 }, { "left", -1, 0 }, { "up", 0, -1 }, { "down", 0, 1 } }) do
    local cx, cy = p.cellX + d[2], p.cellY + d[3]
    if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
      dir, dx, dy = d[1], d[2], d[3]
      break
    end
  end
  if not check("a clear cell beside the player", dir ~= nil) then finish() end

  local function place()
    npc.cellX, npc.cellY = p.cellX + dx, p.cellY + dy
    npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
    npc.targetX, npc.targetY, npc.goalX, npc.goalY = nil, nil, nil, nil
    npc.moving, npc.idle = false, nil
    npc.facing = OPPOSITE[dir]
    p.facing = dir
    ow.pikachuTrail = { x = p.cellX, y = p.cellY }
  end

  local function waitEmote(limit)
    for _ = 1, limit or 3000 do
      if not ow.emote then return true end
      U.wait(1)
    end
    return false
  end

  local function picName()
    local path = PikachuFollower.picFrame(ow.emote)
    return path and path:match("([^/]+)%.png$")
  end

  local function waitPic(name, limit)
    for _ = 1, limit or 600 do
      if ow.emote and ow.emote.pikaSeq and picName() == name then return true end
      U.wait(1)
    end
    return false
  end

  local function beat(happy, mood, script, tilemap, n, stillLabel, twitchLabel, what)
    game.save.pikachuHappiness, game.save.pikachuMood = happy, mood
    place()
    U.tap(game, "a")
    local base, twitch = "pikapic_" .. script, "pikapic_" .. script .. "_" .. tilemap
    local sawBase = waitPic(base)
    check("2822 pikapic " .. script .. " opens on its base frame", sawBase, picName())
    if sawBase then
      U.still(game, ("%s/2822_%02d_%s.png"):format(SHOT_DIR, n, stillLabel))
    end
    local sawTwitch = waitPic(twitch)
    check("2822 " .. what .. " (" .. twitch .. ")", sawTwitch, picName())
    if sawTwitch then
      U.still(game, ("%s/2822_%02d_%s.png"):format(SHOT_DIR, n + 1, twitchLabel))
    end
    check("2822 and twitches back", waitPic(base))
    check("the beat ends", waitEmote())
  end

  beat(90, 128, 5, 18, 3, "pikapic5_ear_still", "pikapic5_ear_twitch",
    "low happiness twitches the ear")

  game.save.pikachuHappiness, game.save.pikachuMood = 90, 100
  place()
  U.tap(game, "a")
  local away
  for _ = 1, 400 do
    U.wait(1)
    if npc.facing == dir and not (ow.emote and ow.emote.pikaPic) then away = true break end
  end
  check("2822 emotion 9 turns the follower away from the player", away, npc.facing)
  if away then U.still(game, SHOT_DIR .. "/2822_05_pika_faces_away.png") end
  check("2822 the pic box turns it back", waitPic("pikapic_9") and npc.facing == OPPOSITE[dir],
    npc.facing)
  local sawTail = waitPic("pikapic_9_22")
  check("2822 no happiness twitches the tail (pikapic_9_22)", sawTail, picName())
  if sawTail then U.still(game, SHOT_DIR .. "/2822_06_pikapic9_tail_twitch.png") end
  check("the no-happiness beat ends", waitEmote())

  finish()
end
