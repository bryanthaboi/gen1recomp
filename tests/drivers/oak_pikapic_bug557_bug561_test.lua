-- pokeyellow engine/battle/core.asm:6390
-- pokeyellow engine/battle/core.asm:2109-2121
-- pokeyellow engine/items/item_effects.asm:148
-- pokeyellow engine/pikachu/pikachu_follow.asm:1
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local BattleState = require("src.battle.BattleState")
  local Sprites = require("src.pokemon.Sprites")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local PROF_BACK = "assets/generated/battle/profoakb.png"
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

  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    finish()
  end

  local oakPicOk = love.filesystem.getInfo(PROF_BACK) ~= nil
  check("Oak's back pic is in the cache (" .. PROF_BACK .. ")", oakPicOk)

  local pikapicFound = {}
  for script = 1, 28 do
    local path = "assets/generated/pikachu/pikapic_" .. script .. ".png"
    if love.filesystem.getInfo(path) then
      pikapicFound[#pikapicFound + 1] = script
    end
  end
  local pikapicOk = #pikapicFound > 0
  check("the pikapic base frames are in the cache (assets/generated/pikachu/)",
        pikapicOk)
  U.log("found base frames for scripts:", table.concat(pikapicFound, " "))

  U.teleport(game, "PALLET_TOWN", 9, 7, "up")
  U.wait(10)
  game.save.player.name = "bryan"

  local backPath = Sprites.playerPath(game.data, "back",
    { kind = "battle", demo = true, oakDemo = true })
  U.log("the demo resolves its back pic to:", tostring(backPath))
  check("it is Oak's pic, not the old man's", backPath == PROF_BACK)

  local battle = BattleState.newWild(game, "PIKACHU", 5)
  battle:makeOldManDemo("oak")
  check("the thrower is named PROF.OAK", battle.demoName == "PROF.OAK")
  check("the battle asks for the BATTLE_TYPE_PIKACHU back pic",
        battle.oakDemo == true)

  local said = {}
  for _, name in ipairs({ "say", "sayAuto", "sayNext", "sayNextAuto" }) do
    local real = battle[name]
    battle[name] = function(self, text, ...)
      said[#said + 1] = tostring(text)
      return real(self, text, ...)
    end
  end

  game.stack:push(battle)
  U.wait(10)

  for _ = 1, 90 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  if not check("the demo battle reached its scripted menu",
               battle.phase == "menu") then
    U.log("phase is", tostring(battle.phase))
    finish()
  end
  U.wait(20)
  U.still(game, SHOT_DIR .. "/557_01_oak_back_pic.png")

  -- pokeyellow data/text_boxes.asm:31
  local options = game.save.options or {}
  U.log("battle layout option:", tostring(options.battleLayout or "classic"))
  check("the layout on screen leaves the scripted menu unnamed",
        not battle:isWideBattleLayout())

  local function thrownLine()
    for _, text in ipairs(said) do
      if text:find("POK", 1, true) and text:find("PROF.OAK", 1, true) then
        return text
      end
    end
    return nil
  end
  for _ = 1, 600 do
    if thrownLine() then break end
    U.wait(1)
  end
  local line = thrownLine()
  check("the throw is announced under PROF.OAK's name", line ~= nil)
  if line then U.log("the box reads:", (line:gsub("\n", " / "))) end
  U.wait(80)
  U.still(game, SHOT_DIR .. "/557_02_prof_oak_used_poke_ball.png")

  if not pikapicOk then finish() end

  local function stackHas(state)
    for _, s in ipairs(game.stack.states) do
      if s == state then return true end
    end
    return false
  end
  for _ = 1, 3000 do
    if not stackHas(battle) then break end
    if battle.msgPrompt or battle.msgWaiting then U.tap(game, "a") end
    U.wait(2)
  end
  check("the demo battle ended", not stackHas(battle))

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false
  U.teleport(game, "PALLET_TOWN", 9, 7, "down")
  U.wait(12)

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
    if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
      dir, dx, dy = d[1], d[2], d[3]
      break
    end
  end
  if not check("a walkable neighbour for the follower exists", dir ~= nil) then finish() end

  npc.cellX, npc.cellY = p.cellX + dx, p.cellY + dy
  npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
  npc.targetX, npc.targetY, npc.goalX, npc.goalY = nil, nil, nil, nil
  npc.moving, npc.idle = false, nil
  p.facing = dir
  ow.pikachuTrail = { x = p.cellX, y = p.cellY }
  local fx, fy = p:facingCell()
  check("player is facing the follower", ow:npcAtCell(fx, fy) == npc)

  U.tap(game, "a")
  local emote
  for _ = 1, 600 do
    emote = ow.emote
    if emote and emote.pikaPic then break end
    U.wait(1)
  end
  if not check("the A press raised a portrait", emote ~= nil and emote.pikaPic ~= nil) then
    finish()
  end
  U.log("the frame is drawing:", tostring(emote.pikaPic))
  check("it is this script's own base frame, not the battle front pic",
        tostring(emote.pikaPic):find("pikachu/pikapic_", 1, true) ~= nil)
  U.still(game, SHOT_DIR .. "/561_01_pikachu_portrait.png")

  finish()
end
