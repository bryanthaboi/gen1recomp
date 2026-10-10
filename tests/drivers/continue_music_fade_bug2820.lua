-- engine/menus/main_menu.asm:106-112, :171, home/overworld.asm:1979, home/fade_audio.asm:12-45
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SaveData = require("src.core.SaveData")
  local Music = require("src.core.Music")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots/2820"

  local fails = 0
  local function check(label, ok, detail)
    print((ok and "PASS " or "FAIL ") .. label
      .. (detail ~= nil and ("  " .. tostring(detail)) or ""))
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    print(fails == 0 and "PASS continue_music_fade_bug2820"
      or "FAIL continue_music_fade_bug2820")
    love.event.quit(fails == 0 and 0 or 1)
    while true do coroutine.yield() end
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 1800 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  if not check("new game reached the overworld", U.newGame(game)) then
    return finish()
  end
  U.teleport(game, "VIRIDIAN_FOREST", 16, 40, "down")
  local ow = game.overworld
  game.save.player.map = ow.map.id
  game.save.player.x, game.save.player.y = ow.player.cellX, ow.player.cellY
  game.save.player.facing = "down"
  check("save written", SaveData.save(game.save) ~= false)
  local forestSong = game.data.audio.mapSongs[ow.map.id]
  check("viridian forest has a map song", forestSong ~= nil, forestSong)

  game:returnToTitle()
  local title = game.stack:top()
  for _ = 1, 120 do
    title = game.stack:top()
    if title and title.screenId == "TitleState" and title.phase == "loop" then
      break
    end
    U.tap(game, "start")
    U.wait(10)
  end
  check("title reached its loop", title and title.phase == "loop")
  local titleSong
  check("title music playing", waitFor(function()
    titleSong = Music.current()
    return titleSong ~= nil and titleSong ~= forestSong
  end, 600), titleSong)

  U.tap(game, "start")
  check("main menu open", waitFor(function()
    local top = game.stack:top()
    return title.menuOpen and top ~= title
  end, 600))
  U.wait(4)
  local menu = game.stack:top()
  U.tap(game, "a")
  check("CONTINUE info window open", waitFor(function()
    local top = game.stack:top()
    return top ~= menu and top and top.titleUiBox and top.titleUiBox[1] == 4
  end, 300))
  U.wait(4)
  U.tap(game, "a")

  local trace = {}
  local whiteFrames, holdFrames, mapUpFrame, fadeStartFrame = 0, nil, nil, nil
  local whiteSongOk, whiteNoFade = true, true
  local levelFrames = {}
  local switchFrame, firstLevel = nil, nil
  local monotonic, lastLevel = true, 8
  local volsDrop, lastVol = true, nil
  local whiteShot = false
  for f = 1, 260 do
    local top = game.stack:top()
    local cur = Music.current()
    local level, pending, vol
    if Music.fadeLevel then level, pending, vol = Music.fadeLevel() end
    if top and top.screenId == "QuarantineReport" then
      table.insert(game.input.pressQueue, "a")
    end
    if not mapUpFrame and top ~= game.overworld and top and top.frames
       and top.t and top.onDone then
      whiteFrames = whiteFrames + 1
      holdFrames = top.frames
      if cur ~= titleSong then whiteSongOk = false end
      if level then whiteNoFade = false end
      if whiteFrames == 15 and not whiteShot then
        whiteShot = true
        U.still(game, SHOT_DIR .. "/2820_01_white_hold_title_playing.png")
      end
    end
    if not mapUpFrame and game.stack.states[1] == game.overworld then
      mapUpFrame = f
    end
    if level then
      if not fadeStartFrame then
        fadeStartFrame = f
        trace.topAtFade = top and (top.screenId or tostring(top)) or "nil"
        trace.stackAtFade = #game.stack.states
      end
      firstLevel = firstLevel or level
      if level > lastLevel then monotonic = false end
      lastLevel = level
      levelFrames[level] = (levelFrames[level] or 0) + 1
      if lastVol and vol and vol > lastVol + 1e-6 then volsDrop = false end
      lastVol = vol or lastVol
      if not trace.pending then trace.pending = pending end
      if not trace.firstCur then trace.firstCur = cur end
      if f == fadeStartFrame + 30 then
        U.still(game, SHOT_DIR .. "/2820_02_forest_shown_title_fading.png")
      end
    end
    if not switchFrame and cur == forestSong then switchFrame = f end
    if switchFrame and f > switchFrame + 5 then break end
    U.wait(1)
  end

  local top = game.stack:top()
  check("overworld on top after CONTINUE", top == game.overworld,
        top and (top.screenId or tostring(top)))
  check("white hold is 3 + 10 + 20 frames", holdFrames == 33, holdFrames)
  check("white screen seen for about 33 frames",
        whiteFrames >= 31 and whiteFrames <= 34, whiteFrames)
  check("title song keeps playing through the white hold", whiteSongOk)
  check("no fade during the white hold", whiteNoFade)
  check("map appears after the hold", mapUpFrame ~= nil
        and mapUpFrame > whiteFrames, mapUpFrame)
  U.log("top when the fade began:", tostring(trace.topAtFade),
        "stack depth", tostring(trace.stackAtFade))
  check("fade starts the frame the map is up",
        fadeStartFrame ~= nil and mapUpFrame ~= nil
        and fadeStartFrame == mapUpFrame,
        tostring(fadeStartFrame) .. " vs " .. tostring(mapUpFrame))
  check("title song still sounding while it fades",
        trace.firstCur == titleSong, trace.firstCur)
  check("fade queues the forest song", trace.pending == forestSong, trace.pending)
  check("fade starts at full volume level 7", firstLevel == 7, firstLevel)
  check("fade levels only step down", monotonic)
  local perLevel = {}
  local allEleven = true
  for level = 7, 0, -1 do
    perLevel[#perLevel + 1] = tostring(levelFrames[level] or 0)
    if levelFrames[level] ~= 11 then allEleven = false end
  end
  check("levels 6..0 each hold control + 1 = 11 frames",
        allEleven or ((levelFrames[7] == 10 or levelFrames[7] == 11)
          and levelFrames[6] == 11 and levelFrames[5] == 11
          and levelFrames[4] == 11 and levelFrames[3] == 11
          and levelFrames[2] == 11 and levelFrames[1] == 11
          and levelFrames[0] == 11),
        table.concat(perLevel, " "))
  check("source volume never rises during the fade", volsDrop)
  check("forest song starts 8 x 11 frames after the fade control is written",
        switchFrame ~= nil and fadeStartFrame ~= nil
        and switchFrame - fadeStartFrame >= 87
        and switchFrame - fadeStartFrame <= 88,
        switchFrame and fadeStartFrame and (switchFrame - fadeStartFrame))
  check("map song remembered", Music.mapSong() == forestSong, Music.mapSong())
  return finish()
end
