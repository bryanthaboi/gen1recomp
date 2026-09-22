-- pokeyellow engine/pokemon/evos_moves.asm:366
-- pokeyellow data/pikachu/pikachu_pic_animation.asm:281
-- pokeyellow engine/pikachu/pikachu_pic_animation.asm:790
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local PikachuFollower = require("src.world.PikachuFollower")
  local PaletteFX = require("src.render.PaletteFX")
  local Sound = require("src.core.Sound")
  local Music = require("src.core.Music")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local failures = 0

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  local startMode = PaletteFX.mode
  local function quit()
    if PaletteFX.mode ~= startMode then PaletteFX.setMode(startMode) end
    U.log(failures == 0 and "ALL PASS" or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("2347_yellow_cache", GameVersion.isYellow()) then quit() end
  if PaletteFX.usesGbcPack() then PaletteFX.setMode("gbc") end

  local moveSounds, ducks = {}, 0
  local realPlayMove, realDuck = Sound.playMove, Music.duckForFanfare
  Sound.playMove = function(data, anim)
    moveSounds[#moveSounds + 1] = anim and anim.sound or "?"
    return realPlayMove(data, anim)
  end
  Music.duckForFanfare = function(src)
    ducks = ducks + 1
    return realDuck(src)
  end

  game.save.player.name = "bryan"
  local pika = Pokemon.new(game.data, "PIKACHU", 30)
  BattleState.stampOT(game.save, pika)
  pika.moves = {
    { id = "THUNDERSHOCK", pp = 30 }, { id = "GROWL", pp = 40 },
    { id = "THUNDER_WAVE", pp = 20 }, { id = "QUICK_ATTACK", pp = 30 },
  }
  game.save.party = { pika }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false
  game.save.pikachuHappiness = 120
  game.save.pikachuMood = 128
  game.save.pikachuEmotionModifier = nil
  game.save.flashLit = nil
  game.save.repelSteps = 250

  U.teleport(game, "ROCK_TUNNEL_1F", 19, 6, "right")
  U.wait(20)
  local ow = game.overworld
  check("2347_rock_tunnel_dark", ow.dark == true)

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end
  local npc = follower()
  if not check("2347_follower_spawned", npc ~= nil) then quit() end

  local DIRS = { { "up", 0, -1 }, { "left", -1, 0 },
                 { "right", 1, 0 }, { "down", 0, 1 } }
  local function freeDir()
    for _, d in ipairs({ { "left", -1, 0 }, { "right", 1, 0 },
                         { "up", 0, -1 }, { "down", 0, 1 } }) do
      local cx, cy = ow.player.cellX + d[2], ow.player.cellY + d[3]
      if ow.map:inBounds(cx, cy) and ow.map:isWalkableCell(cx, cy)
         and not ow:npcAtCell(cx, cy) then
        return d[1]
      end
    end
    return nil
  end
  local function walk(dir)
    local sx, sy = ow.player.cellX, ow.player.cellY
    for _ = 1, 60 do
      U.hold(game, dir, 1)
      if ow.player.cellX ~= sx or ow.player.cellY ~= sy then break end
    end
    for _ = 1, 40 do
      if not ow.player.moving then break end
      U.wait(1)
    end
    U.wait(4)
    return ow.player.cellX ~= sx or ow.player.cellY ~= sy
  end
  if not check("2347_step_room", freeDir() ~= nil) then quit() end
  local function stepAndBack()
    local dir = freeDir()
    if not dir then return false end
    local out = walk(dir)
    local back = walk(OPPOSITE[dir])
    return out and back
  end
  local function faceFollower()
    for _, d in ipairs(DIRS) do
      if npc.cellX == ow.player.cellX + d[2]
         and npc.cellY == ow.player.cellY + d[3] then
        if ow.player.facing ~= d[1] then
          U.tap(game, d[1])
          U.wait(6)
        end
        break
      end
    end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == npc
  end

  stepAndBack()
  U.shot(game, SHOT_DIR .. "/2347_01_dark_before.png")

  pika.moves[4] = { id = "THUNDERBOLT", pp = 15 }
  PikachuFollower.onMoveLearned(game.save, pika, "THUNDERBOLT")
  check("2347_learn_arms_modifier", game.save.pikachuEmotionModifier == 5
        and game.save.pikachuMood == 0x85)

  local function startTalk(tag)
    if not check(tag .. "_facing_follower", faceFollower()) then return false end
    for _ = 1, 5 do
      U.tap(game, "a")
      for _ = 1, 60 do
        if ow.emote then break end
        U.wait(1)
      end
      if ow.emote then break end
    end
    return ow.emote ~= nil
  end

  local function isBoltMap(m)
    return m and m[0] == 0 and m[1] == 0 and m[2] == 0 and m[3] == 3
  end
  local function isDarkMap(m)
    return m and m[0] == 2 and m[1] == 3 and m[2] == 3 and m[3] == 3
  end

  moveSounds, ducks = {}, 0
  if not check("2347_talk1_emote", startTalk("2347_talk1")) then quit() end
  check("2347_talk1_bolt_bubble", ow.emote.bubble and not ow.emote.pikaPic and true or false)
  for _ = 1, 200 do
    if ow.emote and ow.emote.pikaPic then break end
    U.wait(1)
  end
  local pic = ow.emote and ow.emote.pikaPic or ""
  check("2347_talk1_pikapic_25", pic:find("pikapic_25", 1, true) ~= nil)
  local emote = ow.emote
  check("2347_talk1_bolt_spec", emote and emote.boltAt == 45)
  local bgpSeq, shadeSeq, frames = {}, {}, 0
  local prebolt = 0
  while ow.emote == emote and frames < 900 do
    U.wait(1)
    frames = frames + 1
    if ow.emote ~= emote then break end
    bgpSeq[#bgpSeq + 1] = emote.bgp or false
    shadeSeq[#bgpSeq] = PaletteFX.shadeMap() or false
    if not emote.bgp then prebolt = prebolt + 1 end
  end
  local strobeOk, seen = true, 0
  local first
  for i, b in ipairs(bgpSeq) do
    if b then first = first or i end
  end
  if first then
    for row = 1, 20 do
      local want = (row % 2 == 1) and 0xC0 or 0xE4
      for f = 1, 4 do
        local i = first + (row - 1) * 4 + f - 1
        if bgpSeq[i] ~= want then strobeOk = false end
        seen = seen + 1
      end
    end
  end
  U.log("prebolt frames", prebolt, "strobe start", tostring(first), "total", frames)
  check("2347_talk1_strobe_alternates_4f", first ~= nil and strobeOk and seen == 80)
  local whiteDrawn, darkDuringPre = false, false
  for i = 1, #bgpSeq do
    if isBoltMap(shadeSeq[i]) then whiteDrawn = true end
    if first and i < first and isDarkMap(shadeSeq[i]) then darkDuringPre = true end
  end
  check("2347_talk1_prebolt_dark", darkDuringPre)
  check("2347_talk1_strobe_white_drawn", whiteDrawn)
  local litTail = first and #bgpSeq > first + 82
  if litTail then
    for i = first + 82, #bgpSeq do
      if shadeSeq[i] then litTail = false end
    end
  end
  check("2347_talk1_lit_tail_while_box_up", litTail and true or false)
  check("2347_talk1_thunderbolt_sound", moveSounds[1] == "Battle_2F")
  check("2347_talk1_music_muted", ducks == 1)
  U.wait(6)
  check("2347_talk1_dark_after_close", isDarkMap(PaletteFX.shadeMap()))
  check("2347_modifier_survives_talk", game.save.pikachuEmotionModifier == 5)

  if not check("2347_talk2_emote", startTalk("2347_talk2")) then quit() end
  U.shot(game, SHOT_DIR .. "/2347_02_bolt_bubble.png")
  for _ = 1, 200 do
    if ow.emote and ow.emote.pikaPic then break end
    U.wait(1)
  end
  emote = ow.emote
  check("2347_talk2_replays_bolt", emote and emote.boltAt ~= nil)
  U.wait(20)
  U.shot(game, SHOT_DIR .. "/2347_03_pikapic_prebolt.png")
  for _ = 1, 200 do
    if emote.bgp == 0xC0 then break end
    U.wait(1)
  end
  U.shot(game, SHOT_DIR .. "/2347_04_strobe_white.png")
  for _ = 1, 200 do
    if emote.bgp == 0xE4 then break end
    U.wait(1)
  end
  U.shot(game, SHOT_DIR .. "/2347_05_strobe_lit.png")
  for _ = 1, 400 do
    if emote.boltDone or ow.emote ~= emote then break end
    U.wait(1)
  end
  if ow.emote == emote then U.shot(game, SHOT_DIR .. "/2347_06_lit_tail.png") end
  for _ = 1, 200 do
    if ow.emote ~= emote then break end
    U.wait(1)
  end
  U.wait(10)
  U.shot(game, SHOT_DIR .. "/2347_07_after_close_dark.png")

  for _ = 1, 3 do
    stepAndBack()
    U.log("step", ow.player.cellX, ow.player.cellY, "mood",
          tostring(game.save.pikachuMood), "modifier", tostring(game.save.pikachuEmotionModifier))
  end
  check("2347_modifier_clears_after_steps", game.save.pikachuEmotionModifier == nil
        and game.save.pikachuMood == 128)
  moveSounds = {}
  if not check("2347_talk3_emote", startTalk("2347_talk3")) then quit() end
  for _ = 1, 200 do
    if ow.emote and ow.emote.pikaPic then break end
    U.wait(1)
  end
  U.wait(20)
  U.shot(game, SHOT_DIR .. "/2347_08_after_steps_mood_talk.png")
  check("2347_talk3_no_bolt", ow.emote and ow.emote.pikaPic and not ow.emote.boltAt
        and true or false)
  for _ = 1, 600 do
    if not ow.emote then break end
    U.wait(1)
  end
  check("2347_talk3_no_sound", #moveSounds == 0)

  PaletteFX.setMode("redpp")
  U.wait(10)
  ow = game.overworld
  npc = follower() or npc
  stepAndBack()
  if ow:bakedWorldColors() then
    PikachuFollower.onMoveLearned(game.save, pika, "THUNDERBOLT")
    if startTalk("2347_baked") then
      for _ = 1, 200 do
        if ow.emote and ow.emote.pikaPic then break end
        U.wait(1)
      end
      emote = ow.emote
      local veiled = false
      for _ = 1, 400 do
        if ow.emote ~= emote then break end
        U.wait(1)
        local v = game.renderer and game.renderer.screenVeil
        if emote.bgp == 0xC0 and v and v[1] == 1 then
          if not veiled then U.shot(game, SHOT_DIR .. "/2347_09_baked_strobe_white.png") end
          veiled = true
        end
      end
      check("2347_baked_white_veil", veiled)
    end
  else
    U.log("SKIP 2347_baked (no gbc atlas in this cache)")
  end

  Sound.playMove, Music.duckForFanfare = realPlayMove, realDuck
  quit()
end
