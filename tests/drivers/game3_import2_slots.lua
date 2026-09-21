local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import2_slots"

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
    print("PASS import2_slots")
    love.event.quit(0)
  else
    print("FAIL import2_slots failures=" .. failures)
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
    return finish()
  end
  U.wait(20)

  local icons, quads = SlotUi.iconSheet()
  if result(icons ~= nil, "the baked reel icon sheet loaded from the cache") then
    result(icons:getWidth() == 32, "the reel icon sheet is 32 wide, got " .. icons:getWidth())
    result(icons:getHeight() >= 32 * 7,
      "the reel icon sheet carries seven frames, got height " .. icons:getHeight())
    local n = 0
    for _ in pairs(quads or {}) do n = n + 1 end
    result(n >= 7, "the screen cut seven icon quads, got " .. n)
  end
  local bg = SlotUi.background()
  if result(bg ~= nil, "the baked machine frame loaded from the cache") then
    result(bg:getWidth() == 240 and bg:getHeight() == 160,
      string.format("the machine frame is 240x160, got %dx%d", bg:getWidth(), bg:getHeight()))
  end
  local clef = SlotUi.clefairySheet()
  result(clef ~= nil, "the baked Clefairy sheet loaded from the cache")
  U.shot(game, DIR .. "/import2_slots_01_machine_art.png")

  local st = SlotUi.state
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "down")
  U.wait(6)
  for _ = 1, 120 do
    if SlotUi.task ~= "bet" and SlotUi.task ~= "spin" then break end
    U.wait(2)
  end
  result(st ~= nil and st.bet == 3, "three coins are bet, got " .. tostring(st and st.bet))
  result(Slots.isReelSpinning(st, 0), "the reels are spinning on the baked icons")
  U.wait(20)
  U.shot(game, DIR .. "/import2_slots_02_reels_spinning.png")

  for reel = 0, 2 do
    for _ = 1, 40 do
      if not Slots.isReelSpinning(st, reel) then break end
      U.tap(game, "a")
      U.wait(6)
    end
  end
  for _ = 1, 120 do
    if SlotUi.task ~= "stopping" then break end
    U.wait(2)
  end
  result(not Slots.isReelSpinning(st, 2), "every reel stopped on a baked icon")
  local visible = Slots.visibleIcons(st)
  print(string.format("[driver] visible icons %d %d %d / %d %d %d / %d %d %d",
    visible[0], visible[3], visible[6], visible[1], visible[4], visible[7],
    visible[2], visible[5], visible[8]))
  U.shot(game, DIR .. "/import2_slots_03_reels_stopped.png")

  finish()
end
