-- Driver: the Pewter JIGGLYPUFF sings AND dances (#249).
-- scripts/PewterPokecenter.asm PewterPokecenterJigglypuffText: stop the music,
-- DelayFrames 32, MUSIC_JIGGLYPUFF_SONG, then a clockwise quarter turn every 24
-- frames until the song ends, 48 more frames, PlayDefaultMusic.  TextScriptEnd
-- is the only thing that closes the box.  Not under POKEPORT_SPEED.
--   POKEPORT_DRIVER=tests/drivers/jigglypuff_bug249_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local mapScripts = require("data.scripts.init")
  local TextBox = require("src.render.TextBox")
  local Music = require("src.core.Music")

  local MAP = "PEWTER_POKECENTER"
  local NPC = "PEWTERPOKECENTER_JIGGLYPUFF"
  local TEXT = "TEXT_PEWTERPOKECENTER_JIGGLYPUFF"
  local SONG, MAP_SONG = "Music_JigglypuffSong", "Music_Pokecenter"
  -- scripts/PewterPokecenter.asm .FacingDirections, in order
  local RING = { "down", "left", "up", "right" }
  local SILENCE, STEP, TAIL = 32, 24, 48 -- the three DelayFrames counts

  local failures = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  local function nextInRing(dir)
    for i, d in ipairs(RING) do
      if d == dir then return RING[i % #RING + 1] end
    end
    return nil
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- A missing handler, text entry or song def all look the same on screen: a
  -- JIGGLYPUFF that just stands there.
  local handler = mapScripts.talkScript(MAP, TEXT)
  check(MAP .. "/" .. TEXT .. " has a talk handler",
        type(handler) == "function")

  local line = game.data.text and game.data.text._PewterPokecenterJigglypuffText
  check("_PewterPokecenterJigglypuffText resolves to a string",
        type(line) == "string" and line ~= "")
  if type(line) == "string" then
    U.log("the box should read:", (line:gsub("\n", " / ")))
  end

  -- Music.playOnce returns false on a missing def, and the dance then skips
  -- straight to its 48-frame tail with no spin at all.
  local songs = game.data.audio and game.data.audio.songs
  check("audio.songs." .. SONG .. " resolves (PlayMusic MUSIC_JIGGLYPUFF_SONG)",
        songs ~= nil and songs[SONG] ~= nil)
  check("audio.songs." .. MAP_SONG .. " resolves (PlayDefaultMusic comes back to it)",
        songs ~= nil and songs[MAP_SONG] ~= nil)
  local mapSong = game.data.audio and game.data.audio.mapSongs
                  and game.data.audio.mapSongs[MAP]
  check("the Center's map theme is " .. MAP_SONG, mapSong == MAP_SONG)

  -- SPRITE_FAIRY has to be a walker or three of the four facings have no
  -- frames to draw and the "turn" is invisible even when it happens
  local fairy = game.data.sprites and game.data.sprites.SPRITE_FAIRY
  check("SPRITE_FAIRY renders all four facings",
        fairy ~= nil and fairy.walker == true and (fairy.frames or 0) >= 4)

  local opts = game.save.options or {}
  U.log("audio device present:", love.audio ~= nil,
        "  MUSIC VOL (0-7):", tostring(opts.musicVol),
        "  SFX VOL (0-7):", tostring(opts.sfxVol))
  if not love.audio or opts.musicVol == 0 then
    U.log("WARNING: music output is off, so the cut to silence and the song",
          "itself will not be audible; raise MUSIC VOL in OPTION first")
  end

  -- ---- park the player against the JIGGLYPUFF -----------------------------
  -- data/maps/objects/PewterPokecenter.asm: object_event 1, 3, SPRITE_FAIRY.
  -- It sits against the west wall, so approach from the floor to its east.
  local STAND = { x = 2, y = 3, facing = "left" }
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  local function puffIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == NPC then return n end
    end
    return nil
  end

  -- re-reads game.overworld every call: the fallback below teleports again,
  -- which rebuilds the state and its npc list
  local function facingThePuff()
    local ow = game.overworld
    local puff = ow and puffIn(ow)
    if not puff then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == puff
  end

  local ow = game.overworld
  local puff = ow and puffIn(ow)
  check("JIGGLYPUFF object loaded on " .. MAP, puff ~= nil)

  if puff and not facingThePuff() then
    -- Approach cell is blocked (map edit, or a mod moved the object): take any
    -- free neighbour instead.  {dx, dy, facing} is the offset from the fairy
    -- plus the direction that looks back at it, so +1 on x means facing left.
    local sides = {
      { 1, 0, "left" }, { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = puff.cellX + s[1], puff.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("approach cell (%d, %d) is blocked, standing on")
                :format(STAND.x, STAND.y), cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
    puff = game.overworld and puffIn(game.overworld)
  end
  check("player is standing against the JIGGLYPUFF", facingThePuff())

  -- ---- one frame, sampling everything at once ----------------------------
  local function boxOnTop()
    local top = game.stack:top()
    if getmetatable(top) == TextBox then return top end
    return nil
  end

  local function sample(pressA)
    if pressA then U.tap(game, "a") else U.wait(1) end
    local box = boxOnTop()
    return {
      box = box ~= nil,
      typed = box ~= nil and box.done == true,
      tick = box ~= nil and box.auto ~= nil and type(box.auto.tick) == "function",
      facing = puff and puff.facing or nil,
      song = Music.oneShotPlaying(),
    }
  end

  -- ---- 1. talk to it and watch the whole dance, mashing A throughout -----
  U.log("--- run 1: the full dance, with A held down on it ---------------")
  local before = puff and puff.facing
  U.tap(game, "a")
  U.wait(2)
  local box = boxOnTop()
  check("pressing A opened a text box", box ~= nil)
  if box then
    U.log("the JIGGLYPUFF turned to face the player:",
          tostring(before), "->", tostring(puff.facing))
    check("the box carries an auto.tick hook (the per-frame dance driver)",
          box.auto ~= nil and type(box.auto.tick) == "function")
    check("the box is an auto box, so no blinking arrow and no A dismissal",
          box.auto ~= nil)
  end

  -- Mash A every 3rd frame for the whole run; in the original the box cannot
  -- be dismissed at all, so this must change nothing.
  local log, turns = {}, {}
  local typedAt, songAt, songEnd, closedAt = nil, nil, nil, nil
  local last = puff and puff.facing
  for i = 1, 3000 do
    log[i] = sample(i % 3 == 0)
    if not typedAt and log[i].typed then typedAt = i end
    if not songAt and log[i].song then songAt = i end
    if songAt and not songEnd and not log[i].song then songEnd = i end
    if log[i].facing and log[i].facing ~= last then
      turns[#turns + 1] = { at = i, from = last, to = log[i].facing }
      last = log[i].facing
    end
    if not log[i].box then closedAt = i break end
  end

  U.log(("frames: text finished typing at %s, song started at %s, song ended " ..
         "at %s, box closed at %s")
          :format(tostring(typedAt), tostring(songAt), tostring(songEnd),
                  tostring(closedAt)))
  for n, t in ipairs(turns) do
    U.log(("  turn %d on frame %d: %s -> %s"):format(n, t.at, tostring(t.from),
                                                     tostring(t.to)))
  end

  if check("the song played", songAt ~= nil) then
    -- SFX_STOP_ALL_MUSIC, DelayFrames 32, PlayMusic
    local gap = songAt - (typedAt or 1)
    U.log(("silence between the text finishing and the song starting: %d frames " ..
           "(pokered waits %d)"):format(gap, SILENCE))
    check(("that silence is about %d frames"):format(SILENCE),
          gap >= SILENCE - 4 and gap <= SILENCE + 8)
  end

  check("the JIGGLYPUFF turned at least 14 quarter turns (about four spins)", #turns >= 14)
  local ringOk, spacingOk = true, true
  for n, t in ipairs(turns) do
    if t.to ~= nextInRing(t.from) then
      ringOk = false
      U.log(("     turn %d is not a clockwise quarter turn: %s -> %s (expected %s)")
              :format(n, tostring(t.from), tostring(t.to),
                      tostring(nextInRing(t.from))))
    end
    if n > 1 then
      local d = t.at - turns[n - 1].at
      if d < STEP - 6 or d > STEP + 6 then
        spacingOk = false
        U.log(("     turn %d came %d frames after the last one (expected %d)")
                :format(n, d, STEP))
      end
    end
  end
  check("every turn is one clockwise quarter turn (DOWN->LEFT->UP->RIGHT)",
        ringOk and #turns >= 14)
  check(("the turns are %d frames apart"):format(STEP),
        spacingOk and #turns >= 2)

  -- not just "it eventually closed": an A-dismissable box closes too, only far
  -- too early, and that is the bug
  check("mashing A never closed the box early",
        (closedAt or #log) >= SILENCE + 14 * STEP)
  if check("the box closed itself with no button press", closedAt ~= nil) then
    check("it stayed up for the whole song, A mashing and all",
          songEnd ~= nil and closedAt > songEnd)
    if songEnd then
      local tail = closedAt - songEnd
      U.log(("the box lingered %d frames after the song (pokered waits %d, " ..
             "plus the box's own pop delay)"):format(tail, TAIL))
      check(("that tail is about %d frames"):format(TAIL),
            tail >= TAIL - 6 and tail <= TAIL + 20)
    end
  end

  U.log("--- run 2: screenshots ----------------------------------------")
  U.wait(30)
  puff = game.overworld and puffIn(game.overworld)
  check("still standing against the JIGGLYPUFF", facingThePuff())
  U.tap(game, "a")
  U.wait(2)
  U.shot(game, DIR .. "/bug249_0_box.png")

  local shots, seen = 0, puff and puff.facing
  for _ = 1, 600 do
    U.wait(1)
    if not boxOnTop() then break end
    if puff and puff.facing ~= seen then
      seen = puff.facing
      shots = shots + 1
      -- U.shot costs a frame or two, which is why run 1 did the timing
      local path = ("%s/bug249_%d_%s.png"):format(DIR, shots, seen)
      if U.shot(game, path) then U.log("captured", path) end
      if shots >= 4 then break end
    end
  end
  check("captured four quarter turns", shots >= 4)

  U.log(failures == 0 and "ALL PASS" or ("DONE " .. failures .. " check(s) failed"))
  love.event.quit(failures == 0 and 0 or 1)
  while true do
    coroutine.yield()
  end
end
