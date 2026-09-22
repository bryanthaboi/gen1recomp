-- pokeyellow engine/menus/save.asm:260
-- pokeyellow engine/pikachu/pikachu_pic_animation.asm:1
-- pokeyellow engine/events/poison.asm:137
--   POKEPORT_DRIVER=tests/drivers/pikachu_mood_import_bug2344_test.lua POKEPORT_IDENTITY=bug2344 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local SaveConvert = require("src.save_convert.SaveConvert")
  local GenSave = require("src.save_convert.GenSave")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local failures = 0

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  local function quit()
    U.log(failures == 0 and "ALL PASS" or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("2344_yellow_cache", GameVersion.isYellow()) then quit() end

  game.save.player.name = "bryan"
  local pika = Pokemon.new(game.data, "PIKACHU", 12)
  BattleState.stampOT(game.save, pika)
  game.save.party = { pika }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false
  game.save.pikachuHappiness = 120
  game.save.pikachuMood = 0x6c
  game.save.pikachuEmotionModifier = nil

  local bytes, err = SaveConvert.exportSav(game.save, "yellow")
  if not check("2344_export_ok", bytes ~= nil) then
    U.log("export error:", tostring(err))
    quit()
  end
  check("2344_export_mood_byte", bytes:byte(GenSave.OFFSETS.pikachuMood + 1) == 0x6c)
  local imported, ierr = SaveConvert.importSav(bytes, nil, "yellow")
  if not check("2344_import_ok", imported ~= nil) then
    U.log("import error:", tostring(ierr))
    quit()
  end
  check("2344_import_mood", imported.pikachuMood == 0x6c)
  check("2344_import_happiness", imported.pikachuHappiness == 120)
  U.teleport(game, "ROUTE_1", 5, 20, "up")
  U.wait(20)
  local ow = game.overworld

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end
  local npc = follower()
  if not check("2344_follower_spawned", npc ~= nil) then quit() end

  local DIRS = { { "up", 0, -1 }, { "left", -1, 0 },
                 { "right", 1, 0 }, { "down", 0, 1 } }
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

  local stepDir
  for _, d in ipairs(DIRS) do
    local cx, cy = ow.player.cellX + d[2], ow.player.cellY + d[3]
    if ow.map:inBounds(cx, cy) and ow.map:isWalkableCell(cx, cy)
       and not ow:npcAtCell(cx, cy) then
      stepDir = d[1]
      break
    end
  end
  if not check("2344_step_room", stepDir ~= nil) then quit() end
  local function stepAndBack()
    U.hold(game, stepDir, 24)
    U.wait(6)
    U.tap(game, OPPOSITE[stepDir])
    U.wait(6)
  end

  local function talk(wantPic, shotName)
    if not faceFollower() then
      check("2344_facing_follower_" .. wantPic, false)
      return
    end
    for _ = 1, 5 do
      U.tap(game, "a")
      for _ = 1, 60 do
        if ow.emote then break end
        U.wait(1)
      end
      if ow.emote then break end
    end
    for _ = 1, 300 do
      if ow.emote and ow.emote.pikaPic then break end
      U.wait(1)
    end
    local pic = ow.emote and ow.emote.pikaPic or ""
    U.log("pikapic:", pic)
    check("2344_pic_" .. wantPic, pic:find(wantPic, 1, true) ~= nil)
    U.wait(20)
    U.shot(game, SHOT_DIR .. "/" .. shotName)
    for _ = 1, 600 do
      if not ow.emote then break end
      U.wait(1)
    end
    U.wait(10)
  end

  stepAndBack()
  game.save.pikachuHappiness = imported.pikachuHappiness
  game.save.pikachuMood = imported.pikachuMood
  game.save.pikachuEmotionModifier = imported.pikachuEmotionModifier
  U.log("imported happiness", tostring(imported.pikachuHappiness),
        "mood", tostring(imported.pikachuMood))
  talk("pikapic_3.png", "2344_01_mood_low_frown.png")
  check("2344_mood_untouched_by_talk", game.save.pikachuMood == 0x6c)

  game.save.pikachuMood = 128
  talk("pikapic_1.png", "2344_02_mood_neutral_smile.png")

  game.save.pikachuMood = 0x81
  game.save.pikachuEmotionModifier = 2
  talk("pikapic_21.png", "2344_03_fishing_modifier.png")
  check("2344_modifier_survives_talk", game.save.pikachuEmotionModifier == 2)
  stepAndBack()
  check("2344_modifier_clears_at_128",
        game.save.pikachuMood == 128 and game.save.pikachuEmotionModifier == nil)

  quit()
end
