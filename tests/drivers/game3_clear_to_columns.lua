local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_clear_to_columns"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_clear_to_columns")
    love.event.quit(0)
  else
    print("FAIL game3_clear_to_columns failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return end

  -- pokefirered/src/strings.c:585
  local ListMenu = require("src.core.game3.scripting.natives_listmenu")
  local labels = ListMenu.labelsFor(ListMenu.LISTMENU_BERRY_POWDER)
  local got = {}
  for i = 1, 11 do got[i] = string.format("%X", type(labels[i]) == "table" and labels[i].clearTo or 0) end
  got = table.concat(got, ",")
  result(got == "74,74,74,6F,65,65,65,65,65,65,65",
    "berry powder price columns come from the ROM CLEAR_TO bytes (" .. got .. ")")
  result(labels[1].text == "ENERGYPOWDER" and labels[1].tail == "50"
    and labels[4].text == "REVIVAL HERB" and labels[4].tail == "300",
    "berry powder rows split at CLEAR_TO: " .. tostring(labels[1].text) .. " / " .. tostring(labels[1].tail))
  ListMenu.Menu.show(ListMenu.LISTMENU_BERRY_POWDER, 0, 0, function() end)
  U.wait(10)
  result(ListMenu.Menu.isOpen(), "berry powder list is open")
  U.shot(game, DIR .. "/clear_to_berry_powder_list.png")
  ListMenu.Menu.close()
  U.wait(4)

  -- pokefirered/src/strings.c:1335
  local EasyChat = require("src.ui.game3.easy_chat")
  local EasyChatText = require("src.core.game3.easy_chat_text")
  EasyChat.open({ type = 0, words = EasyChatText.DEFAULT_PROFILE, session = session })
  U.wait(10)
  local footer, xs = EasyChat.footerLabels()
  result(footer[1] == "DEL. ALL" and footer[2] == "CANCEL" and footer[3] == "OK",
    "easy chat footer labels are gText_DelAllCancelOk")
  result(xs[1] == 0 and xs[2] == 0x57 and xs[3] == 0xA4,
    "easy chat footer columns are its CLEAR_TO 0x57 / 0xA4 (" .. table.concat({ tostring(xs[1]), tostring(xs[2]), tostring(xs[3]) }, ",") .. ")")
  U.shot(game, DIR .. "/clear_to_easy_chat_footer.png")
  EasyChat.close(false)
  U.wait(10)

  -- pokefirered/src/strings.c:598
  local Records = require("src.ui.game3.trainer_tower_records")
  local headers, hx = Records.columnHeaders()
  result(headers[1] == "WIN" and headers[2] == "LOSE" and headers[3] == "DRAW",
    "battle record headers are gString_BattleRecords_ColumnHeaders")
  result(hx[1] == 0 and hx[2] == 0x30 and hx[3] == 0x60,
    "battle record header columns are its CLEAR_TO 0x30 / 0x60")
  Records.show({ kind = "link", session = session })
  for _ = 1, 60 do
    local Fade = require("src.ui.game3.fade")
    if not Fade.isActive() then break end
    U.wait(2)
  end
  U.wait(10)
  result(Records.isOpen() and Records.kind() == "link", "link battle records are open")
  U.shot(game, DIR .. "/clear_to_battle_records.png")
  Records.close()
  for _ = 1, 120 do
    if not Records.isOpen() then break end
    U.wait(2)
  end
  U.wait(10)

  local Dex = require("src.core.game3.dex")
  local Pokedex = require("src.ui.game3.pokedex")
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")
  local MACHOP, POLIWRATH = 66, 62
  for _, sp in ipairs({ POLIWRATH, MACHOP }) do
    Dex.registerEncounter(session.dex, sp, session)
    Dex.registerCapture(session.dex, sp, session)
  end
  local badges = {}
  local realBadge = PokedexChrome.drawTypeBadge
  PokedexChrome.drawTypeBadge = function(t, x, y)
    badges[#badges + 1] = tostring(t)
    return realBadge(t, x, y)
  end
  Pokedex.show(session.dex, { session = session, mode = "kanto" })
  U.wait(20)
  Pokedex.listScroll = 60
  Pokedex.listCursor = MACHOP
  U.wait(4)
  local function drawOnce()
    badges = {}
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.setCanvas(canvas)
    Pokedex.draw()
    love.graphics.setCanvas()
  end
  drawOnce()
  local list = table.concat(badges, ",")
  result(list == "11,1,1",
    "dex list draws POLIWRATH WATER/FIGHTING and MACHOP FIGHTING badges by type id (" .. list .. ")")
  U.shot(game, DIR .. "/clear_to_dex_list_fighting_badge.png")

  U.tap(game, "a")
  U.wait(20)
  result(Pokedex.screen == "data" and Pokedex.dataPage == 1 and Pokedex.selectedSpecies == MACHOP,
    "A on MACHOP opens its dex page")
  U.tap(game, "a")
  U.wait(20)
  result(Pokedex.screen == "data" and Pokedex.dataPage == 2, "A on the dex page opens the area page")
  drawOnce()
  result(badges[1] == "1", "dex area page draws MACHOP's FIGHTING badge by type id (" .. table.concat(badges, ",") .. ")")
  U.shot(game, DIR .. "/clear_to_dex_area_fighting_badge.png")
  PokedexChrome.drawTypeBadge = realBadge
  Pokedex.close()
  U.wait(10)
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver raised: " .. tostring(err)) end
  finish()
end
