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
  local bgpSeq, poseSeq, doneSeq, frames = {}, {}, {}, 0
  local prebolt = 0
  local function poseName(e)
    local path, lift = PikachuFollower.picFrame(e)
    if (lift or 0) ~= 0 then return "lifted" end
    return path and path:match("([^/]+)%.png$") or false
  end
  local PROBE = (os.getenv("TMPDIR") or "/tmp/") .. "2347_probe.png"
  local function drawnShade()
    U.still(game, PROBE)
    os.remove(PROBE)
    return PaletteFX.shadeMap()
  end
  local darkDuringPre, whiteDrawn, litTail
  while ow.emote == emote and frames < 1500 do
    U.wait(1)
    frames = frames + 1
    if ow.emote ~= emote then break end
    bgpSeq[#bgpSeq + 1] = emote.bgp or false
    poseSeq[#bgpSeq] = poseName(emote)
    doneSeq[#bgpSeq] = emote.boltDone and true or false
    if not emote.bgp then prebolt = prebolt + 1 end
    local k = (emote.boltT or 0) - emote.boltAt - 2
    if darkDuringPre == nil and not emote.bgp and frames > 10 then
      darkDuringPre = isDarkMap(drawnShade())
    elseif whiteDrawn == nil and emote.bgp == 0xC0 then
      whiteDrawn = isBoltMap(drawnShade())
    elseif litTail == nil and k >= 81 and not emote.boltDone then
      litTail = drawnShade() == nil
    end
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
  check("2347_talk1_prebolt_dark", darkDuringPre == true)
  check("2347_talk1_strobe_white_drawn", whiteDrawn == true)
  check("2347_talk1_lit_tail_while_box_up", litTail == true)
  local boltPose, sawE7863, blank = first ~= nil, false, 0
  for i = 1, #poseSeq do
    if poseSeq[i] == "gfx_e7863" then sawE7863 = true end
    if first and i >= first then
      if poseSeq[i] == false then blank = blank + 1
      elseif blank > 0 or poseSeq[i] ~= "gfx_e79f3" then boltPose = false end
    end
  end
  U.log("pose at strobe start", tostring(first and poseSeq[first]), "blank close frames", blank)
  check("2347_talk1_e7863_before_bolt", sawE7863)
  check("2347_talk1_bolt_pose", boltPose)
  local closeSeq = {}
  for i = 1, #poseSeq do
    if doneSeq[i] then closeSeq[#closeSeq + 1] = tostring(poseSeq[i]) end
  end
  U.log("close frames", table.concat(closeSeq, ","))
  check("2347_talk1_empty_box_at_close",
        table.concat(closeSeq, ",") == "gfx_e79f3,gfx_e79f3,gfx_e79f3,false,false,false")
  check("2347_talk1_thunderbolt_sound", moveSounds[1] == "Battle_2F")
  check("2347_talk1_music_muted", ducks == 1)
  U.wait(6)
  check("2347_talk1_dark_after_close", ow.emote == nil and isDarkMap(drawnShade()))
  check("2347_modifier_survives_talk", game.save.pikachuEmotionModifier == 5)

  if not check("2347_talk2_emote", startTalk("2347_talk2")) then quit() end
  U.still(game, SHOT_DIR .. "/2347_02_bolt_bubble.png")
  for _ = 1, 200 do
    if ow.emote and ow.emote.pikaPic then break end
    U.wait(1)
  end
  emote = ow.emote
  check("2347_talk2_replays_bolt", emote and emote.boltAt ~= nil)
  U.wait(20)
  U.still(game, SHOT_DIR .. "/2347_03_pikapic_prebolt.png")
  for _ = 1, 200 do
    if emote.bgp == 0xC0 then break end
    U.wait(1)
  end
  local function drawn()
    return tostring(ow.pikaPicDrawn):match("([^/]+)%.png$")
  end
  U.still(game, SHOT_DIR .. "/2347_04_strobe_white.png")
  check("2347_talk2_c0_draws_e79f3", emote.bgp == 0xC0 and drawn() == "gfx_e79f3")
  for _ = 1, 200 do
    if emote.bgp == 0xE4 then break end
    U.wait(1)
  end
  U.still(game, SHOT_DIR .. "/2347_05_strobe_lit.png")
  check("2347_talk2_e4_draws_e79f3", emote.bgp == 0xE4 and drawn() == "gfx_e79f3")
  for _ = 1, 400 do
    if (emote.boltT or 0) - emote.boltAt > 2 + 80 or ow.emote ~= emote then break end
    U.wait(1)
  end
  if ow.emote == emote and not emote.boltDone then
    U.still(game, SHOT_DIR .. "/2347_06_lit_tail.png")
    check("2347_talk2_tail_draws_e79f3", drawn() == "gfx_e79f3")
  end
  for _ = 1, 1500 do
    if ow.emote ~= emote then break end
    U.wait(1)
  end
  U.wait(10)
  U.still(game, SHOT_DIR .. "/2347_07_after_close_dark.png")

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
  U.still(game, SHOT_DIR .. "/2347_08_after_steps_mood_talk.png")
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
      local tiles = ow.map.renderer
      local darkAtlas = tiles.image
      local function atlasFor(byte)
        local imgs = tiles.bgpImages or {}
        return imgs[byte] and tiles.image == imgs[byte] and tiles.curBgp == byte
               and tiles.baseImage == darkAtlas
      end
      local shotC0, shotE4 = false, false
      local litOnE4, c0Atlas, veilOnC0 = true, true, false
      for _ = 1, 1500 do
        if ow.emote ~= emote then break end
        U.wait(1)
        if ow.emote ~= emote then break end
        if emote.bgp == 0xC0 and not shotC0 then
          shotC0 = true
          U.still(game, SHOT_DIR .. "/2347_09_baked_strobe_white.png")
          local v = game.renderer and game.renderer.screenVeil
          if v then veilOnC0 = true end
          if not atlasFor(0xC0) then c0Atlas = false end
          check("2347_baked_c0_draws_e79f3", drawn() == "gfx_e79f3")
        elseif emote.bgp == 0xE4 and shotC0 and not shotE4 then
          shotE4 = true
          U.still(game, SHOT_DIR .. "/2347_10_baked_strobe_lit.png")
          if not atlasFor(0xE4) then litOnE4 = false end
          check("2347_baked_e4_draws_e79f3", drawn() == "gfx_e79f3")
        end
      end
      check("2347_baked_strobe_seen", shotC0 and shotE4)
      check("2347_baked_lit_atlas", shotE4 and litOnE4)
      check("2347_baked_c0_atlas", shotC0 and c0Atlas)
      check("2347_baked_no_white_veil", shotC0 and not veilOnC0)
      U.wait(10)
      U.still(game, SHOT_DIR .. "/2347_11_baked_after_close_dark.png")
      check("2347_baked_dark_after_close", ow.emote == nil and tiles.image == darkAtlas
            and tiles.curBgp == nil and tiles.baseImage == nil and ow.dark == true)
    end
  else
    U.log("SKIP 2347_baked (no gbc atlas in this cache)")
  end

  if PaletteFX.mode == "redpp" then
    U.teleport(game, "PALLET_TOWN", 11, 11, "down")
    U.wait(20)
    ow = game.overworld
    npc = follower()
    local tiles = ow.map.renderer
    local renderers = { tiles }
    for _, nb in ipairs(ow.neighbors or {}) do
      if nb.map.renderer and nb.map.renderer.gbcAtlas then
        renderers[#renderers + 1] = nb.map.renderer
      end
    end
    check("2347_outdoor_lit", ow.dark ~= true and ow:bakedWorldColors())
    check("2347_outdoor_neighbors_baked", #renderers >= 2)
    local animated = 0
    for _, a in ipairs(tiles.anims or {}) do
      if a.spec then animated = animated + 1 end
    end
    check("2347_outdoor_water_flower_anims", animated >= 2)
    local function allOn(byte)
      for _, r in ipairs(renderers) do
        local img = r.bgpImages and r.bgpImages[byte]
        if not (img and r.image == img and r.curBgp == byte) then return false end
        for _, a in ipairs(r.anims or {}) do
          if a.spec and not (a.bgpTextures and a.textures == a.bgpTextures[byte]) then
            return false
          end
        end
      end
      return true
    end
    local function allBase()
      for _, r in ipairs(renderers) do
        if r.curBgp ~= nil or r.baseImage ~= nil then return false end
        for _, a in ipairs(r.anims or {}) do
          if a.baseTextures then return false end
          for _, t in pairs(a.bgpTextures or {}) do
            if a.textures == t then return false end
          end
        end
      end
      return true
    end
    PikachuFollower.onMoveLearned(game.save, pika, "THUNDERBOLT")
    if npc then PikachuFollower.talk(game, ow, npc, function() end) end
    for _ = 1, 200 do
      if ow.emote and ow.emote.pikaPic then break end
      U.wait(1)
    end
    emote = ow.emote
    if check("2347_outdoor_emote", emote ~= nil) then
      local onC0, onE4, sawC0, sawE4 = nil, nil, 0, 0
      local last
      for _ = 1, 2000 do
        if ow.emote ~= emote then break end
        U.wait(1)
        if ow.emote ~= emote then break end
        local bgp = emote.bgp
        if bgp ~= last and (bgp == 0xC0 and sawC0 < 3 or bgp == 0xE4 and sawE4 < 3) then
          if bgp == 0xC0 then
            sawC0 = sawC0 + 1
            U.still(game, SHOT_DIR .. "/2347_12_outdoor_strobe_white_" .. sawC0 .. ".png")
            onC0 = (onC0 ~= false) and allOn(0xC0)
          else
            sawE4 = sawE4 + 1
            U.still(game, SHOT_DIR .. "/2347_13_outdoor_strobe_lit_" .. sawE4 .. ".png")
            onE4 = (onE4 ~= false) and allBase()
          end
        end
        last = bgp
      end
      check("2347_outdoor_strobe_seen", sawC0 == 3 and sawE4 == 3)
      check("2347_outdoor_c0_every_renderer_and_anim", onC0 == true)
      check("2347_outdoor_e4_lit_base", onE4 == true)
      U.wait(6)
      U.still(game, SHOT_DIR .. "/2347_14_outdoor_after_close.png")
      check("2347_outdoor_base_after_close", ow.emote == nil and allBase())
    end
  end

  Sound.playMove, Music.duckForFanfare = realPlayMove, realDuck
  quit()
end
