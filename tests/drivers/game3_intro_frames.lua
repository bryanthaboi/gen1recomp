local U = require("tests.drivers.util")
local IntroMovie = require("src.ui.game3.intro_movie")
local Title = require("src.ui.game3.title_screen")
local Audio = require("src.core.game3.audio")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_intro_frames"

local INTRO_SHOTS = {
  { 8, "copyright_fadein" }, { 100, "copyright" }, { 160, "copyright_fadeout" },
  { 176, "gf_window_open" }, { 215, "gf_star" }, { 290, "gf_sparkles" },
  { 400, "gf_text_blend" }, { 520, "gf_logo_blend" }, { 640, "gf_logo_hold" },
  { 700, "gf_blend_out" }, { 690, "gf_blend_out_early" },
}

return function(game)
  local log = {}
  local function mark(what)
    local m = game.boot and game.boot.introMovie
    local line = string.format("f=%s %s", m and m.frames or "-", what)
    log[#log + 1] = line
    print("[timeline] " .. line)
  end
  local setCB = IntroMovie.setCB
  IntroMovie.setCB = function(self, name)
    setCB(self, name)
    mark("cb " .. name)
  end
  local playSong = Audio.playSong
  Audio.playSong = function(id, opts)
    mark("song " .. tostring(id))
    return playSong(id, opts)
  end
  local playCry = Audio.playCry
  Audio.playCry = function(sp, mode, pan)
    mark("cry " .. tostring(sp) .. " mode " .. tostring(mode))
    return playCry(sp, mode, pan)
  end

  local function movie() return game.boot and game.boot.introMovie end
  local function freezeShot(obj, name)
    local keep = obj.accum
    obj.accum = -1e9
    U.shot(game, DIR .. "/" .. name .. ".png")
    obj.accum = keep
  end

  local function waitFrame(n)
    for _ = 1, 20000 do
      local m = movie()
      if not m or m.frames >= n then return m end
      U.wait(1)
    end
  end

  local function waitCb(name, extra)
    for _ = 1, 20000 do
      local m = movie()
      if not m then return nil end
      if m.ptr and m.ptr.cb == name and (not extra or extra(m)) then return m end
      U.wait(1)
    end
  end

  table.sort(INTRO_SHOTS, function(a, b) return a[1] < b[1] end)
  for _, s in ipairs(INTRO_SHOTS) do
    local m = waitFrame(s[1])
    if m then freezeShot(m, string.format("i%04d_%s", m.frames, s[2])) end
  end

  local function cbShot(cb, state, timer, name)
    local m = waitCb(cb, function(mm)
      return mm.ptr.state >= state and (timer == nil or (mm.ptr.timer or 0) >= timer)
    end)
    if m then freezeShot(m, string.format("i%04d_%s", m.frames, name)) end
  end

  cbShot("Scene1", 3, nil, "scene1_fadein")
  cbShot("Scene1", 4, 22, "scene1_zoom")
  cbShot("Scene2", 3, nil, "scene2_fadein")
  cbShot("Scene2", 4, 40, "scene2_wide")
  cbShot("Scene2", 6, 30, "scene2_close")
  cbShot("Scene3_Entrance", 3, 3, "scene3_entrance_win0")
  cbShot("Scene3_Entrance", 3, 20, "scene3_entrance_grass")
  cbShot("Scene3_Fight", 2, nil, "scene3_cry")
  cbShot("Scene3_Fight", 4, nil, "scene3_gengar_attack")
  cbShot("Scene3_Fight", 5, nil, "scene3_recoil")
  cbShot("Scene3_Fight", 10, nil, "scene3_nido_attack")
  cbShot("Scene3_Fight", 12, 60, "scene3_white_bg")
  cbShot("Scene3_Fight", 13, 3, "scene3_zoom_mid")
  cbShot("Scene3_Fight", 13, 8, "scene3_zoom_full")
  cbShot("Scene3_Fight", 14, nil, "scene3_black_fade")
  mark("waiting for title")

  for _ = 1, 3000 do
    if game.boot.title and game.boot.title.running then break end
    U.wait(1)
  end
  mark("title running")
  local T = game.boot.title
  local function titleShot(pred, name)
    for _ = 1, 3000 do
      if pred(T) then break end
      U.wait(1)
    end
    freezeShot(T, string.format("t%04d_%s", T.vblanks, name))
  end
  titleShot(function(t) return t.scene == Title.SCENE.FLASHSPRITE and t.band and t.band < 100 end, "flash_band")
  titleShot(function(t) return t.scene == Title.SCENE.FADEIN and t.sceneState == 2 and t.pal.fade and t.pal.fade.y <= 8 end, "gray_fadein")
  titleShot(function(t) return t.scene == Title.SCENE.FADEIN and t.sceneState == 4 and t.win0 and t.win0.x >= 120 end, "border_wipe_flash")
  titleShot(function(t) return t.scene == Title.SCENE.FADEIN and t.win0 and t.win0.mode == "copyright" and t.win0.x <= 120 end, "copyright_slide")
  titleShot(function(t) return t.scene == Title.SCENE.FADEIN and t.sceneState == 9 end, "logo_white")
  titleShot(function(t) return t.scene == Title.SCENE.RUN and t.slash end, "run")
  T.slash.data[2] = 2
  titleShot(function(t) return t.slash.data[1] == 1 and t.slash.x >= 100 end, "run_slash")
  titleShot(function(t) return t.pressStartHidden end, "run_press_hidden")
  mark("done")
  love.event.quit(0)
end
