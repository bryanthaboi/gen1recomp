-- pokeyellow engine/pikachu/pikachu_follow.asm:436
-- pokeyellow engine/pikachu/pikachu_follow.asm:544
-- pokeyellow engine/pikachu/pikachu_follow.asm:1389
-- pokeyellow data/pikachu/pikachu_emotions.asm:54
-- pokeyellow engine/pikachu/pikachu_pic_animation.asm:782
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local CLOCKWISE = { down = "left", left = "up", up = "right", right = "down" }
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
  local DIRS = { { "left", -1, 0 }, { "right", 1, 0 }, { "up", 0, -1 }, { "down", 0, 1 } }
  local dir, dx, dy
  for _, d in ipairs(DIRS) do
    local cx, cy = p.cellX + d[2], p.cellY + d[3]
    local bx, by = p.cellX - d[2], p.cellY - d[3]
    if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy)
       and ow.map:isWalkableCell(bx, by) and not ow:npcAtCell(bx, by) then
      dir, dx, dy = d[1], d[2], d[3]
      break
    end
  end
  if not check("a clear row to work in", dir ~= nil) then finish() end

  local function place(facing)
    npc.cellX, npc.cellY = p.cellX + dx, p.cellY + dy
    npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
    npc.targetX, npc.targetY, npc.goalX, npc.goalY = nil, nil, nil, nil
    npc.moving, npc.idle = false, nil
    npc.facing = facing
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

  game.save.pikachuHappiness, game.save.pikachuMood = 140, 180
  place(dir)
  U.tap(game, "a")
  U.wait(2)
  check("2818 the follower turns to face the player on A", npc.facing == OPPOSITE[dir],
    npc.facing)
  U.still(game, SHOT_DIR .. "/2818_01_pika_faces_player.png")
  check("the talk beat ends", waitEmote())

  local startAt = U.frame()
  local last, glanceAt
  for _ = 1, 800 do
    U.wait(1)
    local idle = npc.idle
    local now = idle and idle.kind == "wait" and idle.frames
    if now and last and now > last then glanceAt = U.frame() - startAt break end
    last = now or last
  end
  check("2819 the first idle glance waits about 8.5 seconds", glanceAt and glanceAt >= 505
    and glanceAt <= 520, glanceAt)

  place(OPPOSITE[dir])
  local fromX, fromY = p.cellX, p.cellY
  U.wait(4)
  local bumped = 0
  for _ = 1, 80 do
    if p.moving then break end
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    coroutine.yield()
    bumped = bumped + 1
  end
  game.input.state[dir] = false
  U.log("held", dir, "for", bumped, "frames before the step committed")
  U.wait(30)
  check("2824 the player walked onto the follower's cell",
    p.cellX == fromX + dx and p.cellY == fromY + dy)
  check("2824 the follower swapped into the vacated cell",
    npc.cellX == fromX and npc.cellY == fromY, npc.cellX .. "," .. npc.cellY)
  check("2824 and keeps watching the player", npc.facing == dir, npc.facing)
  U.still(game, SHOT_DIR .. "/2824_01_pika_watches_after_swap.png")

  p.facing = OPPOSITE[dir]
  U.tap(game, OPPOSITE[dir])
  U.wait(4)
  dx, dy = -dx, -dy
  dir = OPPOSITE[dir]
  game.save.pikachuHappiness, game.save.pikachuMood = 40, 128
  place(dir)
  U.tap(game, "a")
  U.wait(8)
  check("2822 no happiness turns the follower one step from the player",
    npc.facing == CLOCKWISE[OPPOSITE[dir]], npc.facing)
  U.still(game, SHOT_DIR .. "/2822_01_pika_turns_from_player.png")
  local skull
  for _ = 1, 200 do
    U.wait(1)
    if ow.emote and ow.emote.bubble and ow.emote.bubble ~= false then skull = true break end
  end
  check("2822 the skull bubble follows the turn", skull)
  if skull then U.still(game, SHOT_DIR .. "/2822_02_skull_while_turned.png") end
  check("the no-happiness beat ends", waitEmote())

  local cries = {}
  local realPika = Sound.playPikaCry
  Sound.playPikaCry = function(data, n)
    cries[#cries + 1] = n
    return realPika(data, n)
  end
  game.save.pikachuHappiness, game.save.pikachuMood = 90, 140
  place(dir)
  U.tap(game, "a")
  U.wait(3)
  check("2823 the lab mood plays PikaPicAnimScript12's PikachuCry25", cries[1] == 25,
    tostring(cries[1]))
  check("2823 the pic box is up while the sigh plays",
    ow.emote and ow.emote.pikaPic ~= nil)
  U.still(game, SHOT_DIR .. "/2823_01_pikapic12_sigh.png")
  check("the sigh beat ends", waitEmote())
  Sound.playPikaCry = realPika

  finish()
end
