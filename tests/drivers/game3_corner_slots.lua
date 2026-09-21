local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_corner_slots"

local CORNER = "FR_CELADON_CITY_GAME_CORNER"
-- pokefirered/include/constants/flags.h:604
local FLAG_GOT_COIN_CASE = 0x243

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS corner_slots")
    love.event.quit(0)
  else
    print("FAIL corner_slots failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Bag = require("src.core.game3.bag")
  local Slots = require("src.core.game3.slot_machine")
  local SlotUi = require("src.ui.game3.slot_machine")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function coins() return Bag.Coins.get(session) end

  Flags.setFlag(Space.store, ctx(), FLAG_GOT_COIN_CASE, true)
  Bag.Coins.set(session, 120)

  Map.load(nil, game, CORNER, { x = 1, y = 7, facing = "left" })
  Player.cellX, Player.cellY = 1, 7
  Player.px, Player.py = 16, 7 * 16
  Player.targetX, Player.targetY = 1, 7
  Player.facing = "left"
  if game.session then
    game.session.x, game.session.y, game.session.facing = 1, 7, "left"
  end
  U.wait(90)
  result(Space.mapId == CORNER, "standing in the Celadon Game Corner, map=" .. tostring(Space.mapId))
  U.shot(game, DIR .. "/corner_slots_01_game_corner.png")

  -- pokefirered/data/maps/CeladonCity_GameCorner/scripts.inc:243
  U.tap(game, "a")
  U.wait(20)
  for _ = 1, 80 do
    if SlotUi.isOpen() then break end
    if Message.isOpen() or Choice.active or (Space.vm and Space.vm:isRunning()) then
      U.tap(game, "a")
    end
    U.wait(10)
  end
  if not result(SlotUi.isOpen(), "the slot machine sign opened the machine") then
    print("[driver] vm running=" .. tostring(Space.vm and Space.vm:isRunning()) ..
      " message=" .. tostring(Message.isOpen()))
    return finish()
  end
  local st = SlotUi.state
  result(st ~= nil and st.machineIdx >= 0 and st.machineIdx < Slots.NUM_MACHINE_CLASSES,
    "GetRandomSlotMachineId chose luck class " .. tostring(st and st.machineIdx))
  -- pokefirered/src/slot_machine.c:2087
  result(not SlotUi.fadeActive() and (SlotUi._fadeY or 0) == 0,
    "the machine faded in from black, fade=" .. tostring(SlotUi._fadeY))
  U.wait(20)
  U.shot(game, DIR .. "/corner_slots_02_machine_open.png")

  -- pokefirered/src/slot_machine.c:993
  U.tap(game, "right")
  for _ = 1, 60 do
    if SlotUi.helpPhase == "shown" then break end
    U.wait(2)
  end
  result(SlotUi.task == "help" and SlotUi.helpPhase == "shown",
    "DPAD_RIGHT slid the payout help panel in, task=" .. tostring(SlotUi.task))
  U.wait(10)
  U.shot(game, DIR .. "/corner_slots_03_payout_help.png")
  -- pokefirered/src/slot_machine.c:1089
  U.tap(game, "left")
  for _ = 1, 60 do
    if SlotUi.task == "bet" then break end
    U.wait(2)
  end
  result(SlotUi.task == "bet" and (SlotUi.helpX or 0) == 0,
    "DPAD_LEFT slid it back out, task=" .. tostring(SlotUi.task))

  local function spinOnce()
    local before = coins()
    U.tap(game, "down")
    U.wait(6)
    U.tap(game, "down")
    U.wait(6)
    local betTwo = st.bet
    U.tap(game, "down")
    U.wait(6)
    local bet = st.bet
    local afterBet = coins()
    for _ = 1, 120 do
      if SlotUi.task ~= "bet" and SlotUi.task ~= "spin" then break end
      U.wait(2)
    end
    return before, betTwo, bet, afterBet
  end

  local before, betTwo, bet, afterBet = spinOnce()
  result(betTwo == 2, "two presses of DOWN bet two coins, got " .. tostring(betTwo))
  result(bet == 3, "a third press bets the maximum of three, got " .. tostring(bet))
  result(afterBet == before - 3, string.format("the bet debited three coins (%d to %d)", before, afterBet))
  result(SlotUi.task == "stopping", "the reels are spinning, task=" .. tostring(SlotUi.task))
  result(Slots.isReelSpinning(st, 0) and Slots.isReelSpinning(st, 1) and Slots.isReelSpinning(st, 2),
    "all three reels spin at once")
  U.wait(20)
  U.shot(game, DIR .. "/corner_slots_04_reels_spinning.png")

  local function stopAllReels()
    for reel = 0, 2 do
      for _ = 1, 40 do
        if not Slots.isReelSpinning(st, reel) then break end
        U.tap(game, "a")
        U.wait(6)
      end
      result(not Slots.isReelSpinning(st, reel), "reel " .. reel .. " stopped on the A press")
    end
    for _ = 1, 120 do
      if SlotUi.task ~= "stopping" then break end
      U.wait(2)
    end
  end

  stopAllReels()
  result(SlotUi.task == "win" or SlotUi.task == "lose",
    "the machine scored the spin, task=" .. tostring(SlotUi.task))
  local icons = Slots.visibleIcons(st)
  print(string.format("[driver] reels %d %d %d / %d %d %d / %d %d %d rank=%s payout=%s",
    icons[0], icons[3], icons[6], icons[1], icons[4], icons[7], icons[2], icons[5], icons[8],
    tostring(st.slotRewardClass), tostring(st.payout)))
  U.shot(game, DIR .. "/corner_slots_05_reels_stopped.png")

  local Audio = require("src.core.game3.audio")
  local sawFanfare = false
  local wonPayout, wonCoinsBefore = nil, nil
  if SlotUi.task == "win" then
    -- pokefirered/src/slot_machine.c:1177
    sawFanfare = not Audio.isFanfareFinished()
    wonPayout, wonCoinsBefore = st.payout, coins()
  end

  local plays = 1
  while wonPayout == nil and plays < 24 and coins() >= 3 do
    for _ = 1, 200 do
      if SlotUi.task == "bet" then break end
      U.wait(2)
    end
    if SlotUi.task ~= "bet" then break end
    plays = plays + 1
    spinOnce()
    stopAllReels()
    if SlotUi.task == "win" then
      sawFanfare = not Audio.isFanfareFinished()
      wonPayout, wonCoinsBefore = st.payout, coins()
    end
  end
  print("[driver] plays=" .. plays .. " payout=" .. tostring(wonPayout))

  if result(wonPayout ~= nil and wonPayout > 0,
      "a paying line landed within " .. plays .. " plays") then
    result(sawFanfare, "the win started the payout fanfare")
    U.shot(game, DIR .. "/corner_slots_06_payout.png")
    -- pokefirered/src/slot_machine.c:1199
    for _ = 1, 400 do
      if st.payout == 0 or (SlotUi._winPhase == 2 and Audio.isFanfareFinished()) then break end
      U.wait(2)
    end
    print("[driver] payout left when the fanfare ended: " .. tostring(st.payout))
    if st.payout > 0 then
      U.tap(game, "start")
      result(Audio.isFanfareFinished(), "START is only taken once the fanfare is over")
    end
    for _ = 1, 400 do
      if st.payout == 0 then break end
      U.wait(3)
    end
    result(st.payout == 0, "the payout counter emptied, left=" .. tostring(st.payout))
    result(coins() == wonCoinsBefore + wonPayout,
      string.format("the win paid %d coins (%d to %d)", wonPayout, wonCoinsBefore, coins()))
    U.shot(game, DIR .. "/corner_slots_07_paid.png")
  end

  for _ = 1, 200 do
    if SlotUi.task == "bet" then break end
    U.wait(2)
  end
  local coinsAtQuit = coins()
  U.tap(game, "b")
  U.wait(20)
  U.shot(game, DIR .. "/corner_slots_08_quit_prompt.png")
  U.tap(game, "a")
  U.wait(30)
  result(not SlotUi.isOpen(), "answering YES closed the machine")
  result(coins() == coinsAtQuit, "quitting kept the purse intact")

  for _ = 1, 120 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    U.wait(5)
  end
  result(not (Space.vm and Space.vm:isRunning()), "the script resumed and released the player")
  result(Space.mapId == CORNER, "the player is back in the Game Corner")
  U.wait(30)
  U.shot(game, DIR .. "/corner_slots_09_back_in_corner.png")

  finish()
end
