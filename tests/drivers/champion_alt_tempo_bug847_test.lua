-- Driver for #847: slowed Cities1 (scripts/ChampionsRoom.asm:112 farcall
-- Music_Cities1AlternateTempo, audio/alternate_tempo.asm), the scripted walk
-- over the rival (home/overworld.asm CollisionCheckOnLand) and the back-pic
-- sweep (engine/movie/hall_of_fame.asm HoFShowMonOrPlayer).  Never add
-- POKEPORT_SPEED here: it scales the logic clock only and audio is the test.
--   POKEPORT_DRIVER=tests/drivers/champion_alt_tempo_bug847_test.lua POKEPORT_IDENTITY=hof847 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Sprites = require("src.pokemon.Sprites")
  local Music = require("src.core.Music")
  local ChipSynth = require("src.core.ChipSynth")
  local Commands = require("src.script.Commands")
  local HallOfFame = require("src.ui.HallOfFame")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- audio/music/cities1.asm: Music_Cities1_Ch1 opens `tempo 144`, the
  -- Music_Cities1_Ch1_AlternateTempo stub `tempo 232` (macros/scripts/audio.asm
  -- emits db HIGH(x), LOW(x), so these are the literal engine values).
  local NORMAL_TEMPO, ALT_TEMPO = 144, 232
  local SONG = "Music_Cities1"

  -- ---------------------------------------------------------------
  -- party + options
  -- ---------------------------------------------------------------
  local SPECIES = { "CHARIZARD", "SNORLAX", "PIKACHU" }
  game.save.party = {}
  for i, name in ipairs(SPECIES) do
    game.save.party[i] = Pokemon.new(game.data, name, 100 - (i - 1) * 27)
  end
  game.save.player.name = "BRYAN"
  local options = game.save.options
  check("sfxVol is non-zero, so the cries are audible", (options.sfxVol or 0) > 0)
  check("musicVol is non-zero, so the tempo swap is audible",
        (options.musicVol or 0) > 0)

  -- ---------------------------------------------------------------
  -- machine checks: the parts an ear cannot separate from a bad build
  -- ---------------------------------------------------------------
  -- read the live registry, so a mod's map_scripts contribution is inspected
  local mapScripts = require("data.scripts.init")
  local champ = mapScripts.get("CHAMPIONS_ROOM")
  local rows = champ and champ.talk and champ.talk.TEXT_CHAMPIONSROOM_RIVAL
  check("CHAMPIONS_ROOM keeps its rival script", type(rows) == "table")
  rows = rows or {}

  local iFade, iWait, iCue, iWalk, iWarp, cueOpts
  for i, row in ipairs(rows) do
    if row[1] == "fade_music" and not iFade then
      iFade = i
    elseif row[1] == "wait" and iFade and not iWait then
      iWait = i
    elseif row[1] == "play_music" and row[2] == SONG and not iCue then
      iCue, cueOpts = i, row[3]
    elseif row[1] == "move_player" and row[2] == "up" and not iWarp then
      iWalk = i
    elseif row[1] == "warp" and row[2] == "HALL_OF_FAME" then
      iWarp = iWarp or i
    end
  end
  check("the script fades the battle theme out before Cities1 (#847)",
        iFade ~= nil and iCue ~= nil and iFade < iCue)
  check("it waits out the fade, like the ld c, 100 / call DelayFrames",
        iWait ~= nil and iWait > iFade and iWait < iCue
        and (rows[iWait or 1][2] or 0) >= 100)
  check("the Cities1 cue carries the alternate tempo " .. ALT_TEMPO,
        type(cueOpts) == "table" and cueOpts.tempo == ALT_TEMPO)
  check("it still walks the player out before the warp (#704)",
        iWalk ~= nil and iWarp ~= nil and iWalk < iWarp)
  check("Commands.fade_music exists for that first row",
        type(Commands.fade_music) == "function")

  -- the tempo has to survive the song's own `tempo` command: without the
  -- override the body's 144 wins and Cities1 plays as the ordinary town theme
  local def = game.data.audio and game.data.audio.songs
              and game.data.audio.songs[SONG]
  check(SONG .. " is in the extracted song table", type(def) == "table")
  if type(def) == "table" then
    local slowed = {}
    for k, v in pairs(def) do slowed[k] = v end
    slowed.tempo = ALT_TEMPO
    local okAlt, alt = pcall(ChipSynth.newEngine, game.data, slowed,
                             { allowLoops = true })
    local okPlain, plain = pcall(ChipSynth.newEngine, game.data, def,
                                 { allowLoops = true })
    check("an overridden song header starts locked at " .. ALT_TEMPO,
          okAlt and alt and alt.tempo == ALT_TEMPO and alt.tempoLocked == true)
    check("a plain header is left unlocked, free to take its own tempo "
          .. NORMAL_TEMPO,
          okPlain and plain and not plain.tempoLocked)
  end

  -- HoFShowMonOrPlayer loads a back pic for every party member and for the
  -- player; a missing key would silently draw nothing during the sweep
  for _, name in ipairs(SPECIES) do
    local path = Sprites.path(game.data, name, "back", { kind = "hof" })
    check(name .. " resolves a back pic for the induction",
          type(path) == "string" and path ~= "")
  end
  local playerBack = Sprites.playerPath(game.data, "back", { kind = "hof" })
  check("the player resolves RedPicBack for the closing sweep",
        type(playerBack) == "string" and playerBack ~= "")

  -- ---------------------------------------------------------------
  -- stand where ChampionsRoomPlayerEntersScript leaves the player
  -- ---------------------------------------------------------------
  -- pokered data/maps/objects/ChampionsRoom.asm: CHAMPIONSROOM_RIVAL at (4,2),
  -- both HALL_OF_FAME warps on row 0, and RivalEntrance_RLEMovement (up 1,
  -- right 1, up 3) from warp 1 lands the player at (4,3), facing the rival.
  local STAND = { x = 4, y = 3 }
  U.teleport(game, "CHAMPIONS_ROOM", STAND.x, STAND.y, "up")
  U.wait(20)
  local ow = game.overworld
  local rival
  for _, npc in ipairs(ow and ow.npcs or {}) do
    if npc.def and npc.def.name == "CHAMPIONSROOM_RIVAL" then rival = npc end
  end
  check("the rival object is on the map", rival ~= nil)
  if rival and (ow.player.cellX ~= rival.cellX
                or ow.player.cellY ~= rival.cellY + 1) then
    -- a map edit or a mod moved the object: stand on any free walkable
    -- neighbour instead of facing a wall.  {dx, dy, facing} is the offset from
    -- the rival to the stand cell plus the direction that looks back at him.
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = rival.cellX + s[1], rival.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is not free; standing on"):format(STAND.x, STAND.y),
              cx, cy, "facing", s[3])
        U.teleport(game, "CHAMPIONS_ROOM", cx, cy, s[3])
        U.wait(10)
        ow = game.overworld
        for _, npc in ipairs(ow.npcs or {}) do
          if npc.def and npc.def.name == "CHAMPIONSROOM_RIVAL" then
            rival = npc
          end
        end
        break
      end
    end
  end

  -- run the tail of the script, from after the rival battle, so nobody has to
  -- win OPP_RIVAL3 to hear this.  Only rows before that point carry jump
  -- targets, so the slice needs no reindexing -- assert that.
  local from
  for i, row in ipairs(rows) do
    if row[1] == "show_text"
       and row[2] == "_ChampionsRoomRivalAfterBattleText" then
      from = i
      break
    end
  end
  check("found the post-battle row to start from", from ~= nil)
  local slice, jumpy = {}, false
  for i = from or 1, #rows do
    local row = rows[i]
    if row[1] == "jump" or row[1] == "jump_if_true"
       or row[1] == "jump_if_false" then
      jumpy = true
    end
    slice[#slice + 1] = row
  end
  check("the tail of the script has no jump targets to reindex", not jumpy)

  if failures > 0 then
    U.log("stopping before the cutscene:", failures,
          "check(s) failed above, so what you would hear means nothing")
    while true do coroutine.yield() end
  end

  -- watch the cues the script actually issues: on speakers a dedupe that ate
  -- the restart and a fade that never fired sound like the same nothing
  local realPlay, realFade = Music.play, Music.fadeOut
  local cues, faded = {}, false
  Music.play = function(data, song, loop, ctx)
    cues[#cues + 1] = { song = song, tempo = ctx and ctx.tempo }
    return realPlay(data, song, loop, ctx)
  end
  Music.fadeOut = function(control)
    faded = true
    return realFade(control)
  end

  ow:queueScript(slice, { npc = rival })

  -- ---------------------------------------------------------------
  -- the walk out, over the rival's cell
  -- ---------------------------------------------------------------
  local startY = ow.player.cellY
  local minY, sharedCell, walkShot = startY, false, false
  local hof
  for i = 1, 6000 do
    local top = game.stack:top()
    if getmetatable(top) == HallOfFame or (top and top.drawMonInfo) then
      hof = top
      break
    end
    local w = game.overworld
    if w and w.map and w.map.id == "CHAMPIONS_ROOM" and rival then
      local px, py = w.player.cellX, w.player.cellY
      if py < minY then minY = py end
      if px == rival.cellX and py == rival.cellY then
        sharedCell = true
        if not walkShot then
          walkShot = U.shot(game, DIR .. "/bug847_over_rival.png")
        end
      end
    end
    if i % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  Music.play, Music.fadeOut = realPlay, realFade

  check("the battle theme was faded, not cut", faded)
  local altCue
  for _, c in ipairs(cues) do
    if c.song == SONG and c.tempo == ALT_TEMPO then altCue = c end
  end
  check("Cities1 was restarted at the alternate tempo, not deduped away",
        altCue ~= nil)
  check("the player walked out of the room before the warp (#704)",
        minY < startY)
  -- CollisionCheckOnLand skips its checks while wSimulatedJoypadStatesIndex is
  -- non-zero, so passing through (4,2) is the original behavior, not a clip
  check("the scripted walk passed through the rival's cell (#847, not a bug)",
        sharedCell)
  check("walk-over screenshot", walkShot)
  check("the induction started", hof ~= nil)
  if not hof then
    while true do coroutine.yield() end
  end

  -- ---------------------------------------------------------------
  -- the back-pic sweep ahead of the first front pic
  -- ---------------------------------------------------------------
  for _ = 1, 300 do
    if hof.phase ~= "intro" then break end
    U.wait(1)
  end
  check("the induction opens on the back pic sweep, at the right edge",
        hof.phase == "back" and (hof.scrollX or 0) > 96)
  local sweepShot = false
  for _ = 1, 400 do
    if hof.phase ~= "back" then break end
    if not sweepShot and (hof.scrollX or 0) <= 56 then
      sweepShot = U.shot(game, DIR .. "/bug847_back_sweep.png")
    end
    U.wait(1)
  end
  check("back sweep screenshot", sweepShot)
  check("the front pic phase follows the sweep, entering from the left",
        hof.phase == "mons" and (hof.scrollX or 0) < 0)
  for _ = 1, 200 do
    if (hof.scrollX or 96) > 8 then break end
    U.wait(1)
  end
  check("front scroll screenshot", U.shot(game, DIR .. "/bug847_front.png"))
  for _ = 1, 400 do
    if hof.phase == "mons" and (hof.scrollX or 0) >= 96 then break end
    U.wait(1)
  end
  check("the front pic settles at hlcoord (12,5)", (hof.scrollX or 0) == 96)

  U.log(failures == 0 and "all checks passed" or ("FAILURES: " .. failures))
  U.log("input is yours now; the rest of the party and the player's own page")
  U.log("follow on their own, so just watch and listen.")
  U.log("after the rival's last line the battle music should fade out over")
  U.log("about a second, go quiet for another second and a half, and then")
  U.log("Pewter City comes back noticeably slower and heavier than it sounds")
  U.log("in town -- and it stays that slow across the warp until the hall of")
  U.log("fame theme takes over.  For each mon a back sprite sweeps right to")
  U.log("left low on the screen, then the front sprite slides in from the")
  U.log("left and only cries once it stops.")
  U.log("the near miss to listen for: Cities1 at its ordinary town tempo, or")
  U.log("cutting in with no gap -- that is the old behavior, not the fix.")
  U.log("the other near miss: a cry that fires while a sprite is still moving.")

  while true do
    coroutine.yield()
  end
end
