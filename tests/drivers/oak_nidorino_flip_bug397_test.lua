-- Manual check that Oak's NIDORINO keeps its mirrored front sprite across the
-- _OakSpeechText2A -> _OakSpeechText2B page break (#397).  OakSpeechText2 is one
-- PrintText over one flipped pic (pokered engine/movie/oak_speech/oak_speech.asm
-- :80-85, :172-177); advance() used to clear picFlip on the pic-less next step.
--   SHOT_DIR=/tmp/bug397 POKEPORT_DRIVER=tests/drivers/oak_nidorino_flip_bug397_test.lua POKEPORT_IDENTITY=bug397 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Do not set POKEPORT_SPEED: fast-forward desynchronizes the cry from the wipe.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function top() return game.stack:top() end
  local function isBox(s) return getmetatable(s) == TextBox end

  local function speechState()
    for _, s in ipairs(game.stack.states or {}) do
      if s.demoPic ~= nil or (s.steps and s.answers) then return s end
    end
  end

  local function boxText(s)
    if not isBox(s) then return "" end
    local out = {}
    for _, page in ipairs(s.pages or {}) do
      for _, line in ipairs(page) do out[#out + 1] = line end
    end
    return table.concat(out, " / ")
  end

  local function stepId(speech)
    local cur = speech.steps and speech.steps[speech.step]
    return cur and (cur.id or cur.kind) or "?"
  end

  -- boot flow: attract movie -> title -> menu.  With a save on disk NEW GAME is
  -- the second row, so land on it the same way silly_oak_intro_test does.
  U.wait(5)
  U.tap(game, "start")
  U.wait(15)
  U.tap(game, "a")
  U.wait(8)
  local ok, saved = pcall(function()
    return require("src.core.SaveData").load() ~= nil
  end)
  if ok and saved then
    U.tap(game, "down")
    U.wait(5)
  end
  U.tap(game, "a")
  U.wait(20)

  local speech
  for _ = 1, 90 do
    speech = speechState()
    if speech then break end
    U.wait(1)
  end
  if not check("NEW GAME entered Oak's speech", speech ~= nil) then
    U.log("top is", tostring(top()), "-- CONTINUE was picked instead")
    while true do coroutine.yield() end
  end

  local demoIdx
  for i, s in ipairs(speech.steps or {}) do
    if (s.kind or "say") == "demo" then demoIdx = i break end
  end
  check("the step list still has a demo beat", demoIdx ~= nil)
  check("the show-off front sprite loaded (" ..
        tostring(speech.demoSpecies) .. ")", speech.demoPic ~= nil)

  local vol = game.save and game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the NIDORINO cry will be silent, raise it in OPTION")
  else
    U.log("sfxVol", tostring(vol), "-- the cry plays as the sprite wipes in")
  end

  if not demoIdx then
    while true do coroutine.yield() end
  end

  -- mash only up to the demo beat, then let the wipe finish on its own
  for _ = 1, 300 do
    if speech.step >= demoIdx then break end
    U.tap(game, "a")
    U.wait(3)
  end
  for _ = 1, 180 do
    if speech.step == demoIdx and not speech.picReveal and isBox(top()) then
      break
    end
    U.wait(1)
  end

  check("_OakSpeechText2A is up on the demo beat",
        speech.step == demoIdx and isBox(top()))
  local textA = boxText(top())
  U.log("page A reads:", textA)
  check("the mirrored pic is on screen (picFlip set, demo pic)",
        speech.picFlip == true and speech.pic == speech.demoPic)
  U.shot(game, DIR .. "/oak_nido_2a.png")

  -- one A per page of 2A; picFlip must survive every one of them.  The page
  -- count is not fixed (an A during the typewriter only finishes the line), so
  -- keep turning until the step moves on rather than budgeting presses.
  local held = true
  for _ = 1, 60 do
    U.tap(game, "a")
    U.wait(12)
    if speech.picFlip ~= true or speech.pic ~= speech.demoPic then
      held = false
      break
    end
    if speech.step > demoIdx then break end
  end
  check("picFlip and pic unchanged after the page break", held)
  check("the speech moved on to the pic-less step (" .. stepId(speech) .. ")",
        speech.step > demoIdx)
  local textB = boxText(top())
  U.log("page B reads:", textB)
  check("a second page is up and it is not page A",
        isBox(top()) and textB ~= "" and textB ~= textA)
  U.shot(game, DIR .. "/oak_nido_2b.png")
  U.log("shots in", DIR)

  -- put the beat back so the page break can be watched live: pop the box and
  -- rewind the step counter.  The wipe and the cry are both skipped on the way
  -- back in -- the sprite is already standing there and it already called once,
  -- so replaying them reads as NIDORINO entering twice -- leaving just page A.
  for _ = 1, 8 do
    if top() == speech then break end
    game.stack:pop()
  end
  if top() == speech then
    local Sound = require("src.core.Sound")
    local realReveal, realCry = speech.revealPic, Sound.playCry
    speech.revealPic = function(self, _, next)
      self.picReveal = nil
      if next then next() end
    end
    Sound.playCry = function() end
    speech.step = demoIdx
    speech:runStep(speech.steps[demoIdx])
    speech.revealPic, Sound.playCry = realReveal, realCry
    U.wait(30)
  end

  U.log("NIDORINO is standing where the wipe left it, facing LEFT with its horn")
  U.log("toward screen-left, and page A is back up.  Press A to turn the page:")
  U.log("the sprite must not move or mirror, it stays facing left until the")
  U.log("screen fades to white for the naming beat.")

  while true do
    coroutine.yield()
  end
end
