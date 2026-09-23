local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_trainer_card_pages"

local FLAG_BADGE01_GET = 0x820
local FLAG_SYS_POKEDEX_GET = 0x829
local VAR_TRAINER_CARD_MON_ICON_1 = 0x4043
local VAR_HOF_BRAG_STATE = 0x4049
local VAR_EGG_BRAG_STATE = 0x404A
local VAR_LINK_WIN_BRAG_STATE = 0x404B

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS trainer_card_pages")
    love.event.quit(0)
  else
    print("FAIL trainer_card_pages failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local StartMenu = require("src.ui.game3.start_menu")
  local TrainerCard = require("src.ui.game3.trainer_card")
  local Stack = require("src.ui.game3.stack")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setFlag(id, on) Flags.setFlag(Space.store, ctx(), id, on ~= false) end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end

  local function closeCard()
    for _ = 1, 40 do
      if not TrainerCard.isOpen() then break end
      U.tap(game, "b")
      U.wait(8)
    end
    while Stack.depth() > 0 do Stack.pop() end
    U.wait(6)
  end

  local function openViaStartMenu()
    closeCard()
    U.tap(game, "start")
    U.wait(20)
    if not StartMenu.isOpen or not StartMenu.isOpen() then
      StartMenu.show({ session = session })
      U.wait(10)
    end
    for _ = 1, 10 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor or 1]
      if e and e.id == "trainer" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(30)
    return TrainerCard.isOpen()
  end

  local function shot(name)
    U.wait(4)
    U.shot(game, DIR .. "/" .. name .. ".png")
  end

  local function toBack()
    U.tap(game, "a")
    for _ = 1, 40 do
      U.wait(1)
      if TrainerCard.side == "back" and not TrainerCard._flip then break end
    end
  end

  session.money = 0
  session.dex = { seen = {}, caught = {} }
  session.playtime = { hours = 0, minutes = 0, seconds = 0 }
  session.playTimeHours, session.playTimeMinutes = 0, 0
  result(openViaStartMenu(), "START menu opened the trainer card")
  result(TrainerCard.side == "front", "the card opens on the front")
  local c = TrainerCard._card
  result(c.stars == 0, "a fresh save is a 0-star card, got " .. tostring(c.stars))
  result(c.hasPokedex == false, "POKeDEX line hidden before FLAG_SYS_POKEDEX_GET")
  shot("tc_01_front_fresh")

  toBack()
  result(TrainerCard.side == "back", "A flipped to the back")
  local back0 = TrainerCard.backTexts(TrainerCard._card)
  result(#back0 == 1, "an all-zero back prints only the name, got " .. #back0 .. " lines")
  shot("tc_02_back_all_zero")

  -- src/trainer_card.c:604 A on the back exits the card
  U.tap(game, "a")
  U.wait(20)
  result(not TrainerCard.isOpen(), "A on the back closed the card")
  closeCard()

  for i = 0, 7 do setFlag(FLAG_BADGE01_GET + i) end
  setFlag(FLAG_SYS_POKEDEX_GET)
  session.money = 123456
  session.playtime = { hours = 72, minutes = 5, seconds = 0 }
  session.playTimeHours, session.playTimeMinutes = 72, 5
  for sp = 1, 60 do session.dex.caught[sp] = true; session.dex.seen[sp] = true end
  result(openViaStartMenu(), "reopened the card with a full badge set")
  c = TrainerCard._card
  result(TrainerCard.countBadges(session) == 8, "all 8 badges read back")
  result(c.hasPokedex == true, "POKeDEX line shows once the flag is set")
  result(c.caughtMonsCount == 60, "dex count is 60, got " .. tostring(c.caughtMonsCount))
  shot("tc_03_front_8badges_dex_money_time")
  closeCard()

  -- src/trainer_card.c:866
  local function starState(n)
    session.hofDebutHours, session.hofDebutMinutes, session.hofDebutSeconds = 0, 0, 0
    session.berriesPicked, session.jumpsInRow = 0, 0
    session.dex = { seen = {}, caught = {} }
    for sp = 1, 60 do session.dex.caught[sp] = true end
    if n >= 1 then
      session.hofDebutHours, session.hofDebutMinutes, session.hofDebutSeconds = 31, 22, 14
    end
    if n >= 2 then
      for sp = 1, 150 do session.dex.caught[sp] = true end
    end
    if n >= 3 then
      for sp = 152, 248 do session.dex.caught[sp] = true end
      for sp = 252, 384 do session.dex.caught[sp] = true end
    end
    if n >= 4 then
      session.berriesPicked, session.jumpsInRow = 200, 200
    end
  end

  for n = 0, 4 do
    starState(n)
    result(openViaStartMenu(), "opened the card for star level " .. n)
    result(TrainerCard._card.stars == n,
      string.format("star level %d, got %s", n, tostring(TrainerCard._card.stars)))
    shot(string.format("tc_04_front_stars_%d", n))
    closeCard()
  end

  starState(2)
  result(openViaStartMenu(), "opened the card for the flip animation")
  U.tap(game, "a")
  U.wait(5)
  result(TrainerCard._flip ~= nil, "the flip animation is running")
  shot("tc_05_flip_midway")
  for _ = 1, 40 do
    U.wait(1)
    if not TrainerCard._flip then break end
  end
  closeCard()

  if type(session.gameStats) ~= "table" then session.gameStats = {} end
  session.gameStats.linkBattleWins = 1234
  session.gameStats.linkBattleLosses = 7
  session.gameStats[21] = 42
  session.gameStats[50] = 19
  session.gameStats[51] = 8801
  -- src/field_specials.c:1710 UpdateTrainerCardPhotoIcons
  local roster = { 3, 6, 9, 25, 143, 149 }
  for i = 1, 6 do setVar(VAR_TRAINER_CARD_MON_ICON_1 + i - 1, roster[i]) end
  setVar(VAR_HOF_BRAG_STATE, 1)
  setVar(VAR_EGG_BRAG_STATE, 2)
  setVar(VAR_LINK_WIN_BRAG_STATE, 3)
  result(openViaStartMenu(), "opened the card with every back stat set")
  toBack()
  local backFull = TrainerCard.backTexts(TrainerCard._card)
  result(#backFull == 14, "a full back prints all six lines, got " .. #backFull .. " entries")
  result(TrainerCard._card.monSpecies[6] == 149, "the sixth photo icon slot is filled")
  shot("tc_06_back_all_stats")
  closeCard()

  session.gender = "male"
  result(openViaStartMenu(), "opened the male card")
  result(TrainerCard._card.female == false, "male card")
  shot("tc_07_front_male")
  closeCard()

  session.gender = "female"
  result(openViaStartMenu(), "opened the female card")
  result(TrainerCard._card.female == true, "female card")
  shot("tc_08_front_female")
  toBack()
  shot("tc_09_back_female")
  closeCard()

  finish()
end
