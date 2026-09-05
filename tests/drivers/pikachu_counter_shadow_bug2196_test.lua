-- pokeyellow engine/pikachu/pikachu_movement.asm:89,153
--   POKEPORT_IDENTITY=yellow-sep04 POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=tests/drivers/pikachu_counter_shadow_bug2196_test.lua \
--   POKEPORT_SHOT_DIR=/tmp/shots2196 love .
-- No POKEPORT_SPEED: it scales the logic clock only and skews the arc.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")
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

  game.save.player.name = "bryan"
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false
  game.save.usedPokecenter = false
  game.save.party = {
    Pokemon.new(game.data, "PIKACHU", 16),
    Pokemon.new(game.data, "PIDGEY", 12),
  }
  for _, mon in ipairs(game.save.party) do
    mon.hp = math.max(1, math.floor(mon.stats.hp / 3))
  end

  local function follower()
    local ow = game.overworld
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  local MAP = "VIRIDIAN_POKECENTER"
  U.teleport(game, MAP, 3, 6, "up")
  U.wait(20)
  local ow = game.overworld

  local nurse
  for _, n in ipairs(ow.npcs or {}) do
    local d = n.def
    if d and (d.sprite == "SPRITE_NURSE" or (d.name or ""):find("NURSE")) then
      nurse = n
      break
    end
  end
  if not check("nurse object loaded on " .. MAP, nurse ~= nil) then finish() end

  local stand
  for _, s in ipairs({ { 0, 1, "up" }, { 0, -1, "down" },
                       { 1, 0, "left" }, { -1, 0, "right" } }) do
    local cx, cy = nurse.cellX + s[1], nurse.cellY + s[2]
    local sx, sy = nurse.cellX + s[1] * 2, nurse.cellY + s[2] * 2
    if ow.map:inBounds(sx, sy) and ow.map:isWalkableCell(sx, sy)
       and ow.map:isCounterCell(cx, cy) and not ow:npcAtCell(sx, sy) then
      stand = { x = sx, y = sy, facing = s[3] }
      break
    end
  end
  if not check("found a counter cell to talk across", stand ~= nil) then
    finish()
  end

  local guard = 0
  while ow.player.cellY > stand.y and guard < 10 do
    U.hold(game, "up", 20)
    U.wait(6)
    guard = guard + 1
  end
  if ow.player.cellX ~= stand.x or ow.player.cellY ~= stand.y then
    U.teleport(game, MAP, stand.x, stand.y, stand.facing)
    U.wait(20)
    ow = game.overworld
  end
  ow.player.facing = stand.facing
  U.wait(10)
  local npc = follower()
  if not check("the follower is standing by for the hop", npc ~= nil) then
    finish()
  end
  check("the companion carries the shadow tile", npc.shadowImg ~= nil)

  U.tap(game, "a")
  U.wait(10)

  local slideShadow, hopShadow, groundOk, peak = 0, 0, true, 0
  local shotAir = false
  for _ = 1, 1500 do
    local cur = game.overworld
    local pika = follower()
    local h = cur.pikaHop and game.stack:top() == cur and cur.pikaHop or nil
    if h and pika then
      local leg = h.legs[h.leg]
      if pika.hopShadowY then
        if leg and leg.hop then
          hopShadow = hopShadow + 1
          local lift = pika.hopShadowY - pika.py
          if lift > peak then peak = lift end
          if lift <= 0 then groundOk = false end
          if not shotAir and lift >= 7 then
            shotAir = U.shot(game, SHOT_DIR .. "/2196_01_pika_airborne_shadow.png")
          end
        else
          slideShadow = slideShadow + 1
        end
      end
      U.wait(1)
    else
      local partyUp = #game.save.party > 0
      for _, mon in ipairs(game.save.party) do
        if mon.hp ~= mon.stats.hp then partyUp = false end
      end
      if partyUp and not cur.healAnim and not cur.emote
         and game.stack:top() == cur then
        break
      end
      U.tap(game, "a")
      U.wait(4)
    end
  end
  U.wait(30)

  ow = game.overworld
  npc = follower()
  check("the airborne leg published a shadow", hopShadow > 0,
        "frames " .. hopShadow)
  check("the slide leg never did", slideShadow == 0,
        "frames " .. slideShadow)
  check("the shadow stayed below the lifted sprite", groundOk)
  check("the arc peaked at the 8 px HOP_HEIGHT", peak == 8, "peak " .. peak)
  check("a mid-arc frame was captured", shotAir)
  check("the hop is over", ow.pikaHop == nil)
  check("and the shadow is cleared with it",
        npc ~= nil and npc.hopShadowY == nil)
  U.shot(game, SHOT_DIR .. "/2196_02_pika_on_counter_no_shadow.png")

  finish()
end
