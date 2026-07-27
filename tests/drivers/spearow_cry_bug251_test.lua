-- Driver: issue #251 -- "Silent Speary the Spearow".  MANUAL LISTEN, not a
-- pass/fail run: the entire symptom is a missing sound, so nothing here can
-- assert it.  This only parks the player nose to beak with Speary, fires the
-- line once at real speed, and then hands the pad back.
--
-- pokered's ViridianNicknameHouseSpearowText (scripts/ViridianNicknameHouse.asm)
-- is a text_asm that PrintTexts "SPEARY: Tetweet!", then runs PlayCry with
-- SPEAROW and WaitForSoundToFinish before TextScriptEnd.  PrintText returns as
-- soon as the string is placed, so the cry starts only once the box has typed
-- out; and because ViridianNicknameHouse_Script is `jp EnableAutoTextBoxDrawing`
-- (AutoTextBoxDrawingCommon zeroes wDoNotWaitForButtonPressAfterDisplayingText,
-- home/window.asm), DisplayTextID still falls through AfterDisplayingTextID into
-- WaitForTextScrollButtonPress afterwards -- the box holds for A/B, it does not
-- pop itself.  The port's talk script carried no cry row at all, so Speary was
-- mute; the fix is the play_cry waitForButton form
-- (data/scripts/flavor/viridian_nickname_house.lua + TextBox's opts.auto.wait).
--
-- Do NOT run this under POKEPORT_SPEED.  The logic clock is what gets scaled,
-- the audio clock is not, so a fast-forwarded run desynchronises the exact
-- typing-then-cry ordering this driver exists to let a human judge.
return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- ViridianNicknameHouse_Object object 3 is SPRITE_BIRD at cell (5, 5)
  -- (pokered/data/maps/objects/ViridianNicknameHouse.asm).  (5, 6) is the
  -- floor cell directly below it, so facing up puts Speary in the cell
  -- OverworldState:interact reads for an A press (npcAtCell on facingCell).
  U.teleport(game, "VIRIDIAN_NICKNAME_HOUSE", 5, 6, "up")
  U.wait(30) -- let the map music settle before anything has to be heard over it

  -- That object_event is WALK / LEFT_RIGHT and NPC:update paces it with no
  -- range clamp, so left alone Speary strolls out from under the A press
  -- between listens.  Pin the wander rather than setting npc.frozen: talkTo
  -- freezes and unfreezes around the box, so a frozen flag would be cleared
  -- the moment the first listen ends.
  local speary
  for _, n in ipairs(game.overworld.npcs) do
    if n.def and n.def.name == "VIRIDIANNICKNAMEHOUSE_SPEAROW" then speary = n end
  end
  if speary then
    speary.wanders = false
  else
    U.log("WARNING: Speary is not on this map; check the object list.")
  end

  U.log("#251 Speary the Spearow -- this one is judged by ear, not by eye.")
  U.log("About to talk to Speary. The box types out \"SPEARY: Tetweet!\".")
  U.log("PASS: the moment the last letter lands, a short SPEAROW cry plays,")
  U.log("      and only after it finishes does the down arrow start blinking.")
  U.log("FAIL (the bug): dead silence. The arrow blinks the instant the text")
  U.log("      finishes and no cry is ever heard.")
  U.log("ALSO FAIL: the box closes itself when the cry ends, with no A press.")
  U.wait(90) -- a beat to read the above before the sound happens

  U.tap(game, "a")

  -- Call the moment out on the frame the typewriter finishes, which is where
  -- PrintText returns and PlayCry runs in the ROM.
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.pages and top.done then break end
    U.wait(1)
  end
  U.log(">>> NOW: the SPEAROW cry should be sounding. <<<")

  -- popup_fake_save hand-off: never touch input again, so real keyboard and
  -- controller play works from here on.
  U.log("Controls are yours. A closes the box; A again replays the line")
  U.log("(Speary is pinned in front of you, so it stays one button).")
  while true do
    coroutine.yield()
  end
end
