-- Driver: Oak's intro white field must reach the dialogue box.
--
-- The speech fills white over the 160x144 UI canvas, but TextBox docks to the
-- WINDOW's bottom edge (Renderer:setUIAnchor).  In a letterboxed window that
-- left black between the bottom of the white and the top of the box.
-- OakSpeech.letterboxWhite fills the voids with the paper shade instead.
--
-- Needs a window that actually letterboxes -- an exact multiple of 160x144
-- has no voids to get wrong -- so it resizes before shooting.
--   POKEPORT_DRIVER=tests/drivers/oak_speech_letterbox_test.lua lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local OakSpeech = require("src.ui.OakSpeech")

  local function speechUp()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == OakSpeech then return s end
    end
    return nil
  end

  -- 1000x700 is not a multiple of 160x144, so the UI blits at 4x (640x576)
  -- with real bars above/below -- exactly where the seam shows
  love.window.setMode(1000, 700)
  U.wait(30)

  U.wait(5)
  U.tap(game, "start") -- skip the intro movie
  U.wait(20)
  U.tap(game, "a")     -- title -> menu
  U.wait(20)
  U.tap(game, "a")     -- NEW GAME
  U.wait(30)

  local speech
  for _ = 1, 600 do
    speech = speechUp()
    if speech then break end
    U.wait(2)
  end
  if not speech then
    U.log("FAIL never reached Oak's speech")
    return
  end
  U.log("Oak speech is up; letterboxWhite =", tostring(OakSpeech.letterboxWhite))

  -- page through, shooting a few beats: the pic + box together is the shot
  -- that shows whether the white reaches the box
  for i = 1, 4 do
    for _ = 1, 200 do
      local top = game.stack:top()
      if top and top ~= speech and top.done then break end
      U.tap(game, "a")
      U.wait(2)
      if not speechUp() then break end
    end
    if not speechUp() then break end
    U.wait(20)
    U.shot(game, DIR .. ("/oak_%d.png"):format(i))
    U.tap(game, "a")
    U.wait(20)
  end

  U.log("done")
  U.wait(30)
end
