-- scripts/PewterPokecenter_2.asm:10-68
-- engine/pikachu/pikachu_emotions.asm:318
-- engine/pikachu/pikachu_movement.asm:973
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local PikachuFollower = require("src.world.PikachuFollower")

  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local MAP = "PEWTER_POKECENTER"
  local PUFF = "PEWTERPOKECENTER_JIGGLYPUFF"
  local failures = 0

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  local function finish()
    U.log(failures == 0 and "ALL PASS" or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("2335_yellow_cache", GameVersion.isYellow()) then finish() end

  local starter = Pokemon.new(game.data, "PIKACHU", 12)
  require("src.battle.BattleState").stampOT(game.save, starter)
  game.save.party = { starter }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false

  U.teleport(game, MAP, 2, 3, "left")
  U.wait(20)
  local ow = game.overworld

  local function find(pred)
    for _, n in ipairs(ow.npcs or {}) do
      if pred(n) then return n end
    end
    return nil
  end
  local puff = find(function(n) return n.def and n.def.name == PUFF end)
  local pika = find(function(n) return n.pikachuFollower end)
  check("2335_puff_loaded", puff ~= nil)
  if not check("2335_follower_spawned", pika ~= nil) then finish() end
  U.log("player", ow.player.cellX, ow.player.cellY, "pikachu", pika.cellX, pika.cellY)

  local function facingNpc(n)
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == n
  end
  if not check("2335_facing_puff", facingNpc(puff)) then finish() end

  local function boxOnTop()
    local top = game.stack:top()
    if getmetatable(top) == TextBox then return top end
    return nil
  end

  U.tap(game, "a")
  U.wait(2)
  local box = boxOnTop()
  if not check("2335_dance_box_open", box ~= nil and box.auto ~= nil) then finish() end

  local turns, frames, last = 0, 0, puff.facing
  local shotStart, shotMid = false, false
  while boxOnTop() == box and frames < 1500 do
    U.wait(1)
    frames = frames + 1
    if puff.facing ~= last then
      turns = turns + 1
      last = puff.facing
      if turns == 1 and not shotStart then
        shotStart = true
        U.shot(game, DIR .. "/2335_01_song_first_turn.png")
      elseif turns == 8 and not shotMid then
        shotMid = true
        U.shot(game, DIR .. "/2335_02_mid_dance_still_boxed.png")
      end
    end
  end
  U.log("dance: turns", turns, "frames after open", frames)
  check("2335_box_closed_itself", boxOnTop() ~= box)
  check("2335_four_spins", turns >= 14)
  check("2335_sleep_flag_set", ow.pikachuPewterSleepScene == true)
  check("2335_following_disabled", PikachuFollower.isFollowingDisabled(ow))
  U.wait(4)
  U.shot(game, DIR .. "/2335_03_box_closed_pikachu_asleep.png")

  local function step(dir)
    local p = ow.player
    local x, y = p.cellX, p.cellY
    for _ = 1, 30 do
      U.hold(game, dir, 1)
      if p.moving then break end
    end
    for _ = 1, 40 do
      if not p.moving then break end
      U.wait(1)
    end
    U.wait(4)
    return p.cellX ~= x or p.cellY ~= y
  end

  local px, py = pika.cellX, pika.cellY
  local route = { "down", "down", "right", "right", "right" }
  local walked = 0
  for _, d in ipairs(route) do
    if step(d) then walked = walked + 1 end
  end
  U.log("walked", walked, "player", ow.player.cellX, ow.player.cellY,
        "pikachu", pika.cellX, pika.cellY)
  check("2335_player_walked_away", walked >= 4)
  check("2335_pikachu_stayed_put", pika.cellX == px and pika.cellY == py)
  U.shot(game, DIR .. "/2335_04_walked_away_pikachu_stays.png")

  local DIRS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }
  local function free(x, y)
    return ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y) and not ow:npcAtCell(x, y)
  end
  local function pathTo(goal)
    local sx, sy = ow.player.cellX, ow.player.cellY
    local key = function(x, y) return x .. "," .. y end
    local prev, queue, head = { [key(sx, sy)] = false }, { { sx, sy } }, 1
    while queue[head] do
      local c = queue[head]
      head = head + 1
      if goal(c[1], c[2]) then
        local path, k = {}, key(c[1], c[2])
        while prev[k] do
          table.insert(path, 1, prev[k].dir)
          k = prev[k].from
        end
        return path
      end
      for _, d in ipairs(DIRS) do
        local nx, ny = c[1] + d[2], c[2] + d[3]
        local nk = key(nx, ny)
        if prev[nk] == nil and free(nx, ny) then
          prev[nk] = { dir = d[1], from = key(c[1], c[2]) }
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
    return nil
  end
  local faceDir
  local path = pathTo(function(x, y)
    for _, d in ipairs(DIRS) do
      if x + d[2] == px and y + d[3] == py then faceDir = d[1] return true end
    end
    return false
  end)
  if path then
    for _, d in ipairs(path) do step(d) end
    if ow.player.facing ~= faceDir then U.tap(game, faceDir) U.wait(8) end
  end
  if not check("2335_facing_sleeping_pikachu", facingNpc(pika)) then
    U.log("player", ow.player.cellX, ow.player.cellY, ow.player.facing,
          "pikachu", pika.cellX, pika.cellY)
    finish()
  end
  check("2335_still_asleep_before_talk", ow.pikachuPewterSleepScene == true)

  U.tap(game, "a")
  local sawBubble, sawPic, picPath = false, false, nil
  for _ = 1, 600 do
    local e = ow.emote
    if e and e.bubble and not sawBubble then
      sawBubble = true
      U.shot(game, DIR .. "/2335_05_zzz_bubble.png")
    elseif e and e.pikaPic and not sawPic then
      sawPic, picPath = true, e.pikaPic
      U.wait(20)
      U.shot(game, DIR .. "/2335_06_pikapic_wake_face.png")
    end
    if sawPic and not ow.emote then break end
    U.wait(1)
  end
  U.log("pikapic:", tostring(picPath))
  check("2335_zzz_bubble_shown", sawBubble)
  check("2335_pikapic_26_shown", picPath ~= nil and picPath:find("pikapic_26", 1, true) ~= nil)
  U.wait(10)
  check("2335_sleep_flag_cleared", ow.pikachuPewterSleepScene == nil)
  check("2335_following_reenabled", not PikachuFollower.isFollowingDisabled(ow))

  local qx, qy = pika.cellX, pika.cellY
  local moved = 0
  for _, d in ipairs({ "down", "down" }) do
    if step(d) then moved = moved + 1 end
  end
  U.wait(20)
  U.log("after wake: player", ow.player.cellX, ow.player.cellY, "pikachu", pika.cellX, pika.cellY)
  check("2335_pikachu_follows_again",
        moved > 0 and (pika.cellX ~= qx or pika.cellY ~= qy))
  U.shot(game, DIR .. "/2335_07_pikachu_follows_again.png")

  finish()
end
