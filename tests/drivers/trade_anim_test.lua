-- Driver: NPC in-game trade cable animation (InternalClockTradeAnim).
-- Vermilion Trade House: SPEAROW -> FARFETCH'D (DUX).
--
--   POKEPORT_SHOT_DIR=/tmp/trade_shots POKEPORT_DRIVER=tests/drivers/trade_anim_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/trade_shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local TradeAnim = require("src.ui.TradeAnim")
  local TextBox = require("src.render.TextBox")
  local PartyMenu = require("src.ui.PartyMenu")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local function topIs(cls)
    return getmetatable(game.stack:top()) == cls
  end

  game.save.options.colors = "ogred"
  require("src.render.PaletteFX").setMode("ogred")

  -- engine/movie/trade.asm:186 -- wNameBuffer holds the SPECIES, so a
  -- nicknamed sender proves the dialog is not reading mon.nickname
  local sent = Pokemon.new(game.data, "SPEAROW", 10)
  sent.nickname = "CRINKLES"
  game.save.party = { sent }
  U.teleport(game, "VERMILION_TRADE_HOUSE", 3, 6, "up")
  U.wait(5)
  U.shot(game, DIR .. "/trade_00_house.png")

  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 200 do
    if topIs(ChoiceBox) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  U.shot(game, DIR .. "/trade_01_offer.png")
  U.tap(game, "a") -- YES
  U.wait(6)

  for _ = 1, 60 do
    if topIs(PartyMenu) then break end
    U.wait(1)
  end
  U.log("party menu:", topIs(PartyMenu))
  U.shot(game, DIR .. "/trade_02_party.png")
  U.tap(game, "a")
  U.wait(6)

  for _ = 1, 200 do
    if topIs(TradeAnim) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  local anim = game.stack:top()
  if getmetatable(anim) ~= TradeAnim then
    U.log("FAIL trade_anim_2278: TradeAnim never appeared")
    love.event.quit(1)
    return
  end
  U.log("TradeAnim phase:", anim.phase)

  local function ffUntil(phase, cap)
    for _ = 1, cap or 3000 do
      if anim.phase == phase or anim.phase == "done" then break end
      if anim.waitingText or topIs(TextBox) then
        U.wait(1)
      else
        anim:update(1 / 60)
      end
    end
    U.wait(1)
  end

  ffUntil("show_player", 1)
  -- engine/movie/trade.asm:245 -- rWX carries the info box in from the right
  -- while hSCX carries the mon in from the left
  while anim.phase == "show_player" and anim.sub == "slide" and anim.scx > 92 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/2278_01_box_enters_right.png")
  U.log("box enter scx=", anim.scx, "sub=", anim.sub)

  while anim.phase == "show_player" and anim.sub == "slide" and anim.scx > 60 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/2278_02_show_player_slide.png")
  U.log("slide scx=", anim.scx)

  while anim.phase == "show_player" and (anim.sub ~= "hold" or anim.scx > 0) do
    anim:update(1 / 60)
  end
  for _ = 1, 10 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_03_show_player.png")
  U.log("show_player sub=", anim.sub, "scx=", anim.scx)

  ffUntil("open_cable", 500)
  -- mid scroll-in
  while anim.phase == "open_cable" and anim.scx > 40 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/trade_04_open_cable.png")
  U.log("open_cable scx=", anim.scx)

  ffUntil("ball_enter", 200)
  while anim.phase == "ball_enter" and anim.ballX < 0x80 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/trade_05_ball_enter.png")
  U.log("ball at", anim.ballX, anim.ballY)

  ffUntil("transfer_lr", 400)
  for _ = 1, 24 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_06_transfer_lr.png")

  -- engine/movie/trade.asm:602
  anim.waitingText = true
  anim.cableFlash = false
  U.shot(game, DIR .. "/2278_07_bgp_normal.png")
  anim.cableFlash = true
  U.shot(game, DIR .. "/2278_07_bgp_flash.png")
  anim.cableFlash = false
  anim.waitingText = false

  ffUntil("went_to", 800)
  -- engine/movie/trade.asm:186 -- the dialog is TradeAnim's own box, not a
  -- TextBox on the stack, and it draws whole (no typewriter)
  for _ = 1, 400 do
    if anim.phase == "went_to" and anim.sub == "text" and anim.dialogText then
      break
    end
    U.wait(1)
  end
  U.shot(game, DIR .. "/2278_09_went_to_species.png")
  U.log("went-to text:", anim.dialogText and anim.dialogText:gsub("\n", " / "))

  for _ = 1, 600 do
    if anim.phase == "for_sends" and anim.sub == "sends_text"
       and anim.dialogText then
      break
    end
    U.wait(1)
  end
  U.shot(game, DIR .. "/2278_09_sends_species.png")
  U.log("sends text:", anim.dialogText and anim.dialogText:gsub("\n", " / "))

  ffUntil("transfer_rl", 2500)
  for _ = 1, 16 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_08_transfer_rl.png")

  ffUntil("show_enemy", 800)
  -- engine/movie/trade.asm:358
  while anim.phase == "show_enemy" and anim.sub ~= "ball_rest" do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/2278_10_ball_rest.png")
  U.log("ball_rest sub=", anim.sub, "box=", anim.boxVisible,
        "mon=", anim.monVisible, "t=", anim.t)

  -- engine/movie/trade.asm:361 -- the ball holds 60 frames on the box before
  -- the poof, so shoot the tail of the hold too
  while anim.phase == "show_enemy" and anim.sub == "ball_rest" and anim.t < 50 do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/2278_10_ball_rest_hold.png")
  U.log("ball_rest hold sub=", anim.sub, "t=", anim.t,
        "mon=", anim.monVisible)

  while anim.phase == "show_enemy" and anim.sub == "ball_rest" do
    anim:update(1 / 60)
  end
  U.wait(1)
  U.shot(game, DIR .. "/2278_10_poof.png")

  while anim.phase == "show_enemy" and not anim.monVisible do
    anim:update(1 / 60)
  end
  for _ = 1, 30 do anim:update(1 / 60) end
  U.wait(1)
  U.shot(game, DIR .. "/trade_09_show_enemy.png")

  for _ = 1, 5000 do
    if game.stack:top() == game.overworld then break end
    local top = game.stack:top()
    if getmetatable(top) == TradeAnim and not top.waitingText then
      top:update(1 / 60)
    end
    U.tap(game, "a")
    U.wait(1)
  end
  U.shot(game, DIR .. "/trade_10_done.png")
  local mon = game.save.party[1]
  U.log("party:", mon and mon.species, "nick:", mon and mon.nickname,
        "ot:", mon and mon.ot)
  local ok = mon ~= nil and mon.species == "FARFETCHD"
  U.log(ok and "PASS trade_anim_2278" or "FAIL trade_anim_2278")
  love.event.quit(ok and 0 or 1)
end
