local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local StartMenu = require("src.ui.game3.start_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local TrainerCard = require("src.ui.game3.trainer_card")
  local FrlgFont = require("src.ui.game3.frlg_font")

  local store = Space.getStore()
  result(store ~= nil, "2405 live flag store present")
  if not store then love.event.quit(1) return end
  Flags.setBadge(store, 1, true)
  Flags.setBadge(store, 2, true)

  local drawn = {}
  local realDraw = FrlgFont.draw
  FrlgFont.draw = function(text, x, y, opts)
    drawn[#drawn + 1] = { text = text, x = x, y = y }
    return realDraw(text, x, y, opts)
  end
  local function valueAt(y)
    for i = #drawn, 1, -1 do
      local s = drawn[i]
      if s.y == y and s.x > 1 * 8 + 4 then return s.text end
    end
  end
  local function labelY(label)
    for i = #drawn, 1, -1 do
      local s = drawn[i]
      if s.text == label and s.x == 1 * 8 + 4 then return s.y end
    end
  end

  local function openSave()
    U.tap(game, "start")
    U.wait(30)
    for _ = 1, 12 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "save" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(40)
    return SaveMenu.isOpen()
  end

  local function closeSave()
    for _ = 1, 4 do
      if not SaveMenu.isOpen() and not StartMenu.isOpen() then break end
      U.tap(game, "b")
      U.wait(20)
    end
  end

  result(openSave(), "2405 START > SAVE opened the save stats window")
  drawn = {}
  U.wait(2)
  result(valueAt(1 * 8 + 32) == "2", "2405 save stats BADGES reads 2 (" .. tostring(valueAt(1 * 8 + 32)) .. ")")
  result(labelY("POKéDEX") == nil, "2405 no POKéDEX row before FLAG_SYS_POKEDEX_GET")
  result(labelY("TIME") == 1 * 8 + 46, "2405 TIME sits on the POKéDEX row (" .. tostring(labelY("TIME")) .. ")")
  U.shot(game, DIR .. "/2405_01_save_stats_two_badges_no_dex.png")
  result(TrainerCard.countBadges() == 2 or TrainerCard.countBadges(require("src.core.game3.runtime").getSession()) == 2,
    "2405 trainer card agrees on 2 badges")
  closeSave()

  Flags.setFlag(store, nil, Flags.IDS.SYS_POKEDEX_GET or 0x829, true)
  Flags.setBadge(store, 3, true)
  result(openSave(), "2405 START > SAVE reopened with the POKéDEX flag")
  drawn = {}
  U.wait(2)
  result(valueAt(1 * 8 + 32) == "3", "2405 save stats BADGES reads 3 (" .. tostring(valueAt(1 * 8 + 32)) .. ")")
  result(labelY("POKéDEX") == 1 * 8 + 46, "2405 POKéDEX row drawn once the dex is obtained")
  result(labelY("TIME") == 1 * 8 + 60, "2405 TIME drops below the POKéDEX row (" .. tostring(labelY("TIME")) .. ")")
  U.shot(game, DIR .. "/2405_02_save_stats_three_badges_with_dex.png")
  closeSave()

  FrlgFont.draw = realDraw
  love.event.quit(fails == 0 and 0 or 1)
end
