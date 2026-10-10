-- engine/menus/main_menu.asm:106-112, home/fade_audio.asm:12-45
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SaveData = require("src.core.SaveData")
  local Music = require("src.core.Music")
  local ChipAudio = require("src.core.ChipAudio")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots/2844"

  local fails = 0
  local function check(label, ok, detail)
    print((ok and "PASS " or "FAIL ") .. label
      .. (detail ~= nil and ("  " .. tostring(detail)) or ""))
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    print(fails == 0 and "PASS continue_fade_no_jump_bug2844"
      or "FAIL continue_fade_no_jump_bug2844")
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

  local mixCalls = 0
  local realMix = love.audio.setMixWithSystem
  love.audio.setMixWithSystem = function(mix)
    mixCalls = mixCalls + 1
    love.event.push("audioreset")
    if realMix then return realMix(mix) end
    return true
  end

  if not check("new game reached the overworld", U.newGame(game)) then
    return finish()
  end
  local ow = game.overworld
  game.save.player.map = ow.map.id
  game.save.player.x, game.save.player.y = ow.player.cellX, ow.player.cellY
  check("save written", SaveData.save(game.save) ~= false)
  local mapSong = game.data.audio.mapSongs[ow.map.id]

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
    return titleSong ~= nil and titleSong ~= mapSong
      and ChipAudio.currentSource() ~= nil
  end, 600), titleSong)

  U.tap(game, "start")
  check("main menu open", waitFor(function()
    return title.menuOpen and game.stack:top() ~= title
  end, 600))
  U.wait(4)
  local menu = game.stack:top()
  U.tap(game, "a")
  check("CONTINUE info window open", waitFor(function()
    local top = game.stack:top()
    return top ~= menu and top and top.titleUiBox and top.titleUiBox[1] == 4
  end, 300))
  U.wait(4)

  local titleSource = ChipAudio.currentSource()
  mixCalls = 0
  U.tap(game, "a")

  local fadeFrames, swapped, rose, lastVol = 0, false, false, nil
  local switchFrame, shot = nil, false
  for f = 1, 300 do
    local top = game.stack:top()
    if top and top.screenId == "QuarantineReport" then
      table.insert(game.input.pressQueue, "a")
    end
    local cur = Music.current()
    local level, _, vol
    if Music.fadeLevel then level, _, vol = Music.fadeLevel() end
    if level and cur == titleSong then
      fadeFrames = fadeFrames + 1
      if ChipAudio.currentSource() ~= titleSource then swapped = true end
      local live = ChipAudio.currentSource()
      local ok, v = pcall(function() return live:getVolume() end)
      v = ok and v or vol
      if lastVol and v and v > lastVol + 1e-6 then rose = true end
      lastVol = v or lastVol
      if fadeFrames == 30 and not shot then
        shot = true
        U.still(game, SHOT_DIR .. "/2844_01_overworld_title_fading.png")
      end
    end
    if not switchFrame and cur == mapSong then switchFrame = f end
    if switchFrame and f > switchFrame + 5 then break end
    U.wait(1)
  end

  check("CONTINUE sends no setMixWithSystem (no audioreset)", mixCalls == 0,
        mixCalls)
  check("title fade ran", fadeFrames >= 80, fadeFrames)
  check("title keeps its queued stream through the fade (no position jump)",
        not swapped)
  check("source volume never rises during the fade", not rose)
  check("map song takes over after the fade", switchFrame ~= nil, switchFrame)
  love.audio.setMixWithSystem = realMix
  return finish()
end
