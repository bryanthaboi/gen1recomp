-- pokered/engine/movie/oak_speech/oak_speech.asm:70-108,191-209
-- pokered/home/fade.asm:26-62
--   POKEPORT_DRIVER=tests/drivers/intro_fades_2188.lua \
--     POKEPORT_IDENTITY=red-sep04 POKEPORT_VERSION=red \
--     POKEPORT_TOUCH=0 POKEPORT_SHOT_DIR=<dir> love .
local U = require("tests.drivers.util")

local OakSpeech = require("src.ui.OakSpeech")
local GameVersion = require("src.core.GameVersion")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  os.execute('mkdir -p "' .. out .. '" 2>/dev/null')
  local log = io.open(out .. "/driver.log", "w")

  local function say(line)
    print("[driver] " .. line)
    if log then log:write(line .. "\n"); log:flush() end
  end

  local function bail(reason)
    say("FAIL " .. reason)
    if log then log:close() end
    love.event.quit(1)
    error(reason, 0)
  end

  local function speechUp()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == OakSpeech then return s end
    end
    return nil
  end

  local function whiteOut()
    local top = game.stack:top()
    if top and top.bgpByte then return top end
    return nil
  end

  local function row(t, step)
    return math.floor((math.max(1, t) - 1) / step) + 1
  end

  local function tap()
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    game.input.state.a = true
    U.wait(1)
    game.input.state.a = false
    U.wait(2)
  end

  local function shoot(name, label)
    if not U.shot(game, out .. "/" .. name) then bail("no shot " .. name) end
    say("OK " .. label .. " -> " .. name)
  end

  say("version=" .. tostring(GameVersion.get()))

  U.wait(5)
  game.input.pressQueue[#game.input.pressQueue + 1] = "start"
  U.wait(10)
  for _ = 1, 200 do
    if speechUp() then break end
    tap()
  end
  local speech = speechUp()
  if not speech then bail("never reached Oak's speech") end
  say("OK the speech is up")

  local shot = {}
  local fadeIns, fadeOuts = 0, 0
  local hadReveal, hadFade = false, false

  for _ = 1, 4000 do
    speech = speechUp()
    if not speech then break end

    local r = speech.picReveal
    if r and not r.bgp then r = nil end
    if r and not hadReveal then fadeIns = fadeIns + 1 end
    hadReveal = r ~= nil

    local w = whiteOut()
    if w and not hadFade then
      fadeOuts = fadeOuts + 1
      if w.bytes[1] ~= 0x90 or w.bytes[2] ~= 0x40 or w.bytes[3] ~= 0x00 then
        bail("GBFadeOutToWhite is not FadePal6/7/8")
      end
      if #w.bytes * w.step ~= 24 then bail("GBFadeOutToWhite is not 3 x 8") end
    end
    hadFade = w ~= nil

    if r and r.kind == "fade" and fadeIns == 1 and not shot[1] then
      if #r.bgp * r.step ~= 60 then bail("FadeInIntroPic is not 6 x 10") end
      if row(r.t, r.step) >= 2 then
        shot[1] = true
        shoot("2188_01_oak_row2_a8.png", "Oak, IntroFadePalettes row 2 (0xA8)")
      else
        U.wait(1)
      end
    elseif w and fadeOuts == 1 and not shot[2] then
      if row(w.t, w.step) >= 1 and w.t >= 2 then
        shot[2] = true
        shoot("2188_02_oak_fadeout_row1.png",
          "OakSpeechText1 -> GBFadeOutToWhite row 1 (0x90), box still up")
      else
        U.wait(1)
      end
    elseif w and fadeOuts == 2 and not shot[3] then
      if row(w.t, w.step) >= 3 then
        shot[3] = true
        shoot("2188_03_world_fadeout_row3.png",
          "OakSpeechText2 -> GBFadeOutToWhite row 3 (0x00)")
      else
        U.wait(1)
      end
    elseif r and r.kind == "fade" and fadeIns == 2 and not shot[4] then
      if row(r.t, r.step) >= 3 then
        shot[4] = true
        shoot("2188_04_rival_row3_fc.png",
          "the rival, IntroFadePalettes row 3 (0xFC)")
      else
        U.wait(1)
      end
    elseif r and r.kind == "fade_white_in" and not shot[5] then
      if #r.bgp * r.step ~= 24 then bail("GBFadeInFromWhite is not 3 x 8") end
      if row(r.t, r.step) >= 2 then
        shot[5] = true
        shoot("2188_05_player2_fadein_row2.png",
          "the player pic, GBFadeInFromWhite row 2 (0x90)")
      else
        U.wait(1)
      end
    elseif r or w or speech.shrink then
      U.wait(1)
    else
      tap()
    end

    if shot[5] then break end
  end

  for i, label in ipairs({ "Oak's fade in", "Oak's fade out",
                           "the world spiel's fade out", "the rival's fade in",
                           "the player pic's fade in from white" }) do
    if not shot[i] then bail("never saw " .. label) end
  end

  for _ = 1, 900 do
    if game.overworld and game.stack:top() == game.overworld then break end
    local sp = speechUp()
    if sp and (sp.shrink or sp.picReveal or whiteOut()) then
      U.wait(1)
    else
      tap()
    end
  end
  if not (game.overworld and game.stack:top() == game.overworld) then
    bail("the speech never handed over to the overworld")
  end
  say("OK reached " .. tostring(game.overworld.map and game.overworld.map.id))

  say("PASS intro_fades_2188 in " .. out)
  if log then log:close() end
  love.event.quit(0)
end
