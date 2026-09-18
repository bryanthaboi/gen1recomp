local U = require("tests.drivers.util")
local Scene = require("src.ui.game3.new_game_scene")
local Audio = require("src.core.game3.audio")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_oak_frames"

return function(game)
  local names = {}
  for k, v in pairs(Scene) do
    if type(v) == "function" then names[v] = k end
  end
  local function scene() return game.boot and game.boot.newGame end
  local function fname()
    local s = scene()
    if not s then return "-" end
    for _, t in ipairs(s.tasks) do
      if names[t.func] and names[t.func]:find("^Task_") then return names[t.func] end
    end
    return s.naming and ("naming:" .. s.naming.stage) or "?"
  end
  local lastF
  local function mark(what)
    local s = scene()
    print(string.format("[oak] f=%s %s", s and s.frames or "-", what))
  end
  local playSong, playSe, playCry = Audio.playSong, Audio.playSe, Audio.playCry
  Audio.playSong = function(id, o) mark("song " .. tostring(id)) return playSong(id, o) end
  Audio.playSe = function(id, o) mark("se " .. tostring(id)) return playSe(id, o) end
  Audio.playCry = function(sp, m, p) mark("cry " .. tostring(sp)) return playCry(sp, m, p) end
  local fadeOut = Audio.fadeOutBgm
  Audio.fadeOutBgm = function(sp) mark("fadeOutBgm " .. tostring(sp)) return fadeOut(sp) end

  local function tick(n)
    for _ = 1, n or 1 do
      local f = fname()
      if f ~= lastF then
        mark("task " .. f)
        lastF = f
      end
      U.wait(1)
    end
  end
  local shotN = 0
  local function shot(name)
    local s = scene()
    if not s then return end
    local keep = s.accum
    s.accum = -1e9
    shotN = shotN + 1
    U.shot(game, string.format("%s/%02d_f%05d_%s.png", DIR, shotN, s.frames, name))
    s.accum = keep
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 3000 do
      if pred() then return true end
      tick(1)
    end
    print("[oak] TIMEOUT waiting in " .. fname())
    return false
  end
  local function waitTask(name, limit) return waitFor(function() return fname() == name end, limit) end
  local function press(k) U.tap(game, k) tick(1) end

  for _ = 1, 600 do
    if game.boot and game.boot.phase == "intro" then press("start") end
    if game.boot and game.boot.phase == "title" then break end
    tick(1)
  end
  for _ = 1, 600 do
    if game.boot.phase == "title" then press("a") tick(2) end
    if game.boot.phase == "menu" then break end
    tick(1)
  end
  waitFor(function() return game.boot.phase == "menu" and (game.boot.fadeT or 0) == 0 end, 600)
  tick(10)
  press("a")
  waitFor(function() return scene() ~= nil end, 600)

  waitTask("Task_ControlsGuide_HandleInput")
  tick(8)
  shot("controls_fadein")
  waitFor(function() return not scene():fadeActive() end)
  shot("controls_p1")
  press("a")
  tick(4)
  shot("controls_fade_to_blue")
  waitFor(function() return scene().currentPage == 2 and not scene():fadeActive() end)
  shot("controls_p2")
  press("a")
  waitFor(function() return scene().currentPage == 3 and not scene():fadeActive() end)
  shot("controls_p3")
  press("a")
  tick(12)
  shot("controls_fade_black")
  waitTask("Task_PikachuIntro_HandleInput")
  tick(20)
  shot("pika_fadein")
  waitFor(function() return not scene():fadeActive() end)
  tick(2)
  shot("pika_p1")
  press("a")
  tick(3)
  shot("pika_crossfade")
  tick(20)
  press("a")
  tick(20)
  press("a")
  tick(10)
  shot("pika_exit_hold")
  waitTask("Task_OakSpeech_WelcomeToTheWorld")
  tick(20)
  shot("oak_fadein")
  waitTask("Task_OakSpeech_ThisWorld")
  tick(30)
  shot("welcome_text")
  local function advanceUntil(name, limit)
    return waitFor(function()
      if fname() == name then return true end
      local s = scene()
      if s and s.printer and s.printer.state == "clear" then press("a") end
      return false
    end, limit or 4000)
  end
  advanceUntil("Task_OakSpeech_IsInhabitedFarAndWide")
  tick(33)
  shot("ball_open")
  tick(6)
  shot("ball_release_mid")
  tick(14)
  shot("ball_release_late")
  advanceUntil("Task_OakSpeech_TellMeALittleAboutYourself")
  tick(40)
  shot("nidoran_return")
  tick(20)
  shot("nidoran_return_rise")
  advanceUntil("Task_OakSpeech_AskPlayerGender")
  tick(24)
  shot("oak_blend_out")
  waitTask("Task_OakSpeech_HandleGenderInput")
  shot("gender_menu")
  press("down")
  press("down")
  press("up")
  press("a")
  waitTask("Task_OakSpeech_YourNameWhatIsIt")
  tick(10)
  shot("player_blend_in")
  advanceUntil("Task_OakSpeech_DoNamingScreen")
  waitFor(function() return scene().naming and scene().naming.stage == "input" end)
  shot("naming")
  press("start")
  press("a")
  waitTask("Task_OakSpeech_HandleConfirmNameInput")
  shot("confirm_player")
  press("a")
  tick(30)
  shot("player_blend_out")
  waitTask("Task_OakSpeech_MoveRivalDisplayNameOptions")
  advanceUntil("Task_OakSpeech_HandleRivalNameInput")
  shot("rival_list")
  press("down")
  press("a")
  waitTask("Task_OakSpeech_HandleConfirmNameInput")
  shot("confirm_rival")
  press("a")
  advanceUntil("Task_OakSpeech_LetsGo")
  tick(5)
  shot("player_back")
  advanceUntil("Task_OakSpeech_ShrinkPlayerPic")
  tick(30)
  shot("shrink_1")
  tick(50)
  shot("shrink_3")
  tick(25)
  shot("shrink_final")
  tick(40)
  shot("fade_black")
  waitFor(function() return game.phase == "field" end, 1000)
  tick(6)
  U.shot(game, DIR .. "/99_field_fadein.png")
  tick(30)
  U.shot(game, DIR .. "/99_field.png")
  mark("done")
  love.event.quit(0)
end
