-- Driver: Pokémon Center nurse heal + Mom home heal.
-- Logs frames between healAnim end and the fighting-fit / looking-great text.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local COLORS = os.getenv("HEAL_COLORS")
  if COLORS then
    require("src.render.PaletteFX").setMode(COLORS)
    U.log("COLORS mode:", COLORS)
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local TextBox = require("src.render.TextBox")
  local mon = Pokemon.new(game.data, "CHARMANDER", 12)
  mon.hp = 3
  table.insert(game.save.party, mon)
  local mon2 = Pokemon.new(game.data, "PIDGEY", 8)
  mon2.hp = 1
  table.insert(game.save.party, mon2)
  U.teleport(game, "VIRIDIAN_POKECENTER", 3, 3, "up")
  local ow = game.overworld

  local function mashUntil(cond)
    for _ = 1, 400 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return false
  end

  local function topIsText()
    return getmetatable(game.stack:top()) == TextBox
  end

  -- -------- Poké Center --------
  U.tap(game, "a") -- talk to the nurse
  U.wait(30)
  U.shot(game, DIR .. "/heal_00_welcome.png")
  U.log("choice reached:", mashUntil(function()
    return getmetatable(game.stack:top()) == ChoiceBox
  end))
  U.shot(game, DIR .. "/heal_01_choice.png")
  U.tap(game, "a") -- YES
  U.log("machine started:", mashUntil(function()
    return ow.healAnim ~= nil
  end))
  U.shot(game, DIR .. "/heal_02_ball1.png")
  U.wait(28)
  U.shot(game, DIR .. "/heal_03_ball2.png")
  game:zoomStep(-1); game:zoomStep(-1)
  U.wait(3)
  U.shot(game, DIR .. "/heal_03z_zoomed.png")
  local Zoom = require("src.render.Zoom")
  Zoom.reset()
  U.wait(3)
  U.wait(35)
  U.shot(game, DIR .. "/heal_04_flash_a.png")
  U.wait(10)
  U.shot(game, DIR .. "/heal_05_flash_b.png")
  U.wait(10)
  U.shot(game, DIR .. "/heal_06_flash_c.png")

  local animEndFrame, fitFrame
  for _ = 1, 400 do
    if ow.healAnim == nil and not animEndFrame then
      animEndFrame = U.frame()
      if topIsText() then fitFrame = animEndFrame end
      U.shot(game, DIR .. "/heal_06b_anim_end.png")
      if fitFrame then break end
    end
    if animEndFrame and topIsText() and not fitFrame then
      fitFrame = U.frame()
      break
    end
    U.wait(1)
  end
  U.shot(game, DIR .. "/heal_07_fit.png")
  U.log("pc anim_end_frame:", animEndFrame, "fit_frame:", fitFrame,
        "gap_anim_to_text:",
        (fitFrame and animEndFrame) and (fitFrame - animEndFrame) or "n/a")
  U.log("farewell reached:", mashUntil(function()
    return game.stack:top() == ow
  end))
  U.shot(game, DIR .. "/heal_08_end.png")

  -- -------- Mom (Reds House) --------
  local SUSPEND = os.getenv("HEAL_SUSPEND")
  if SUSPEND then
    require("src.core.ChipAudio").setSuspended(true)
    U.log("audio suspended before the Mom heal")
  end
  require("src.script.Flags").set(game.save, "EVENT_GOT_STARTER")
  for _, m in ipairs(game.save.party) do
    m.hp = 1
  end
  -- stand below Mom (5,4) facing up
  U.teleport(game, "REDS_HOUSE_1F", 5, 5, "up")
  ow = game.overworld
  U.tap(game, "a")
  U.wait(20)
  U.shot(game, DIR .. "/heal_mom_00_rest.png")
  U.log("mom fade started:", mashUntil(function()
    return ow.fadeOverlay ~= nil
  end))
  local fadeStart = U.frame()
  U.shot(game, DIR .. "/heal_mom_01_fade.png")
  local Music = require("src.core.Music")
  local sawJingle, jingleDoneFrame, fadeGone, greatFrame = false
  for _ = 1, SUSPEND and 1200 or 600 do
    if Music.oneShotPlaying() then sawJingle = true end
    if sawJingle and not Music.oneShotPlaying() and not jingleDoneFrame then
      jingleDoneFrame = U.frame()
    end
    if ow.fadeOverlay == nil and fadeStart and not fadeGone
       and U.frame() > fadeStart + 5 then
      fadeGone = U.frame()
    end
    if fadeGone and topIsText() then
      greatFrame = U.frame()
      break
    end
    U.wait(1)
  end
  U.shot(game, DIR .. "/heal_mom_02_great.png")
  if SUSPEND then
    U.shot(game, DIR .. "/2246_01_heal_completes_with_audio_suspended.png")
  end
  U.log("mom saw_jingle:", sawJingle,
        "jingle_done_frame:", jingleDoneFrame,
        "fade_gone_frame:", fadeGone,
        "great_frame:", greatFrame,
        "gap_fade_to_text:",
        (greatFrame and fadeGone) and (greatFrame - fadeGone) or "n/a")
  mashUntil(function()
    return game.stack:top() == ow
  end)
  U.shot(game, DIR .. "/heal_mom_03_end.png")
  U.log("2246 heal driver PASS:", greatFrame ~= nil)
  love.event.quit(greatFrame and 0 or 1)
end

