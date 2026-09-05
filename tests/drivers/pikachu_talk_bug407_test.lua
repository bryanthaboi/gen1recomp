-- Manual check that the Yellow follower answers an A press (#407).
-- TalkToPikachu (pokeyellow engine/pikachu/pikachu_emotions.asm) picks an
-- emotion, plays its bubble + voiced clip and raises the framed pikapic;
-- the port's follower is a frame behind the player, so the old not-moving
-- gate in OverworldState:interact ate the press right after a step landed.
-- No POKEPORT_SPEED: it scales the logic clock only, and the cry runs on
-- the real-time audio accumulator, so a fast run desyncs what is judged.
--   POKEPORT_DRIVER=tests/drivers/pikachu_talk_bug407_test.lua POKEPORT_IDENTITY=bug407 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local failures = 0

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  local function idle()
    U.log(failures == 0 and "ALL PASS" or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  -- the Yellow cache is a separate mount; on Red/Blue there is no follower
  -- at all and every line below would fail for the wrong reason
  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    U.log("Red and Blue have no follower. Re-run with POKEPORT_VERSION=yellow.")
    idle()
  end

  -- ShouldPikachuSpawn's three inputs (pikachu_follow.asm): the lab gift
  -- happened, a healthy starter Pikachu is in the party, and the sprite
  -- exists in the cache.  Happiness/mood are left at their boot values
  -- (90 / 128, init_player_data.asm) so the mood matrix lands on the same
  -- cell a fresh save would pick.
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "bryan"
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false

  -- pokeyellow data/maps/objects/PalletTown.asm: the town's objects sit at
  -- (10,4), (3,8) and (11,14) and its warps at (5,5), (13,5), (12,11), so
  -- the road cells around (10,8) are clear of all of them.
  local MAP = "PALLET_TOWN"
  local START = { x = 10, y = 8, facing = "down" }

  U.teleport(game, MAP, START.x, START.y, START.facing)
  U.wait(10)

  local ow = game.overworld
  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  local npc = follower()
  if not check("follower is in ow.npcs with pikachuFollower set", npc ~= nil) then
    U.log("EVENT_GOT_STARTER:", tostring(game.save.flags.EVENT_GOT_STARTER),
          "party PIKACHU hp:",
          tostring(game.save.party[1] and game.save.party[1].hp),
          "SPRITE_PIKACHU:",
          tostring(game.data.sprites and game.data.sprites.SPRITE_PIKACHU ~= nil))
    idle()
  end

  -- one real step, so the follower trails onto the cell just vacated and
  -- the press lands in exactly the window #407 used to swallow.  A later
  -- map edit that walls (10,9) in degrades to any free neighbour instead
  -- of walking into a fence.
  local p = ow.player
  local DIRS = { { "down", 0, 1 }, { "up", 0, -1 },
                 { "left", -1, 0 }, { "right", 1, 0 } }
  local stepDir
  for _, d in ipairs(DIRS) do
    local cx, cy = p.cellX + d[2], p.cellY + d[3]
    if ow.map:inBounds(cx, cy) and ow.map:isWalkableCell(cx, cy)
       and not ow:npcAtCell(cx, cy) then
      stepDir = d[1]
      break
    end
  end
  if not check("a walkable neighbour to step into exists", stepDir ~= nil) then
    idle()
  end
  U.hold(game, stepDir, 24) -- 16 frame step plus the turn frame and slack
  U.wait(6)

  -- turn back the way we came: tryMove on a new facing only turns, so the
  -- tap cannot walk back onto the follower's cell
  U.tap(game, OPPOSITE[stepDir])
  U.wait(6)

  local function facingFollower()
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == npc
  end

  if not facingFollower() then
    -- the follower is somewhere else (a step it could not take, a mod):
    -- turn toward whichever neighbouring cell it actually occupies
    for _, d in ipairs(DIRS) do
      if npc.cellX == ow.player.cellX + d[2]
         and npc.cellY == ow.player.cellY + d[3] then
        U.log("follower is", d[1], "of the player, turning that way instead")
        U.tap(game, d[1])
        U.wait(6)
        break
      end
    end
  end
  check("player is facing the follower's cell", facingFollower())
  U.log("player at", ow.player.cellX, ow.player.cellY,
        "facing", ow.player.facing,
        "| follower at", npc.cellX, npc.cellY)

  -- a muted run sounds exactly like the bug, so say so before anyone
  -- listens for the clip (Sound.setVolumeLevel reads save.options.sfxVol)
  local sfxVol = game.save.options and game.save.options.sfxVol
  U.log("save.options.sfxVol:", tostring(sfxVol))
  if (sfxVol or 0) == 0 then
    U.log("WARNING sfx volume is 0: no cry can be heard whether or not one")
    U.log("WARNING plays. Raise it in OPTIONS before judging the sound half.")
  end

  -- record what the talk actually asked the mixer for: PCM clip, chip
  -- fallback, or nothing at all.  playCry calls Sound.playPikaCry through
  -- the table, so the wrapper sees the fallback too.
  local cries = {}
  local realPika, realChip = Sound.playPikaCry, Sound.playCry
  Sound.playPikaCry = function(data, n)
    local src = realPika(data, n)
    cries[#cries + 1] = { kind = "pcm clip", id = n, src = src }
    return src
  end
  Sound.playCry = function(data, species)
    local src = realChip(data, species)
    cries[#cries + 1] = { kind = "chip cry", id = species, src = src }
    return src
  end
  local function restoreSound()
    Sound.playPikaCry, Sound.playCry = realPika, realChip
  end

  -- data.field.emotionBubbles is the sheet TalkToPikachu's bubble index
  -- resolves against; an unbuilt Yellow cache carries only the three
  -- shared bubbles and the talk degrades to a silent hold
  local sheet = game.data.field and game.data.field.emotionBubbles
  local function bubbleReport(emote)
    if emote.bubble == false or emote.bubble == nil then
      U.log("this emotion has NO bubble: a cry and the framed pic are all it")
      U.log("puts on screen, which is correct behavior, not the bug")
      return true
    end
    local rect = sheet and sheet.bubbles and sheet.bubbles[emote.bubble]
    local ok = rect ~= nil and (sheet.path ~= nil)
    check("bubble index " .. tostring(emote.bubble) ..
          " resolves against the cache sheet", ok)
    if ok then
      U.log("bubble", rect.name or "?", "crop",
            rect.x, rect.y, rect.w, rect.h, "of", sheet.path)
    end
    return ok
  end

  local function reportCries(from)
    for i = #cries, 1, -1 do
      if i > from then
        U.log("cry:", cries[i].kind, tostring(cries[i].id),
              cries[i].src and "source created" or "NO SOURCE")
      end
    end
    return #cries > from
  end

  -- ---- press one: whatever the mood matrix picks on a boot-value save ----
  local before = #cries
  U.tap(game, "a")
  U.wait(6)

  local emote = ow.emote
  check("the A press reached the follower (ow.emote is set)",
        emote ~= nil and emote.npc == npc)
  if not emote then
    restoreSound()
    U.log("Nothing answered the press. That is #407 exactly: no bubble, no")
    U.log("cry, no framed picture, and the map keeps running underneath.")
    idle()
  end
  check("the framed pikapic path resolved",
        type(emote.pikaPic) == "string"
        and love.filesystem.getInfo(emote.pikaPic) ~= nil)
  check("a cry source was created", reportCries(before))
  -- the beat now runs the pikapic script's own pikapic_setduration, three
  -- 60Hz frames per tick, so even the shortest script (32 ticks) outlasts
  -- the 50 frame hold this port used to serve every emotion (#424)
  check("the hold runs the script's own duration, not a flat 50 frames",
        (emote.frames or 0) >= 80)
  bubbleReport(emote)
  U.log("happiness", tostring(game.save.pikachuHappiness or 90),
        "mood", tostring(game.save.pikachuMood or 128))
  U.log("on boot values (90 / 128) the matrix cell is emotion 5:")
  U.log("PCM clip 31 and no bubble at all, so sound with no bubble is right")
  if U.shot(game, SHOT_DIR .. "/bug407_talk_mood.png") then
    U.log("captured", SHOT_DIR .. "/bug407_talk_mood.png")
  end

  -- ---- press two: a scripted emotion that must show a bubble ----
  -- wPikachuEmotionModifier 5 is MapSpecificPikachuExpression's fifth
  -- entry, emotion 25: BOLT_BUBBLE plus PCM clip 35.  Forcing it takes the
  -- mood roll out of the picture, so a missing bubble here is a real fault.
  -- wait the pikapic beat out instead of counting frames: its length is the
  -- script's now, and an A press during it would only cut it short
  -- (PikaPicAnimTimerAndJoypad, #424)
  for _ = 1, 400 do
    if not ow.emote then break end
    U.wait(1)
  end
  U.wait(6)
  game.save.pikachuEmotionModifier = 5
  check("still facing the follower for the second press", facingFollower())
  before = #cries
  U.tap(game, "a")
  U.wait(6)

  emote = ow.emote
  check("emotion 25 (forced) answered the press", emote ~= nil)
  if emote then
    check("emotion 25 carries a bubble index", type(emote.bubble) == "number")
    bubbleReport(emote)
    -- engine/overworld/emotion_bubbles.asm:60
    check("the bubble holds before the cry", not emote.pikaPic)
    if U.shot(game, SHOT_DIR .. "/bug407_talk_bolt.png") then
      U.log("captured", SHOT_DIR .. "/bug407_talk_bolt.png")
    end
    for _ = 1, 240 do
      if ow.emote and ow.emote.pikaPic then break end
      U.wait(1)
    end
    check("emotion 25 played a cry once the bubble ended", reportCries(before))
    check("and the framed pic follows it",
          ow.emote ~= nil and ow.emote.pikaPic ~= nil)
    if U.shot(game, SHOT_DIR .. "/bug407_talk_bolt_pic.png") then
      U.log("captured", SHOT_DIR .. "/bug407_talk_bolt_pic.png")
    end
  end
  restoreSound()

  idle()
end
