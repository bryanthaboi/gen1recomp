local U = require("tests.drivers.util")
local D = require("tests.drivers.em_fc_util").new("em_tm_move_name_3116")

local function flat(s)
  return (tostring(s or ""):gsub("[\n\f]", " "))
end

local function runScript(game, start, wants, noPattern)
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local pages, hit = {}, {}
  if not start() then return pages, hit end
  for _ = 1, 1500 do
    local running = Space.vm and Space.vm:isRunning()
    if not running and not Message.isOpen() then break end
    if Message.isOpen() and not Message.isTyping() then
      local page = flat(Message.currentPage())
      if pages[#pages] ~= page then pages[#pages + 1] = page end
      for i, w in ipairs(wants) do
        if not hit[i] and page:find(w.text, 1, true) then
          hit[i] = true
          if w.shot then D.shot(game, w.shot, true) end
        end
      end
      U.tap(game, (noPattern and page:find(noPattern, 1, true)) and "b" or "a")
    end
    U.wait(3)
  end
  return pages, hit
end

local function report(label, pages, hit, wants)
  print("INFO " .. label .. "_pages=" .. table.concat(pages, " | "))
  for i, w in ipairs(wants) do D.check(hit[i] == true, w.label) end
end

return function(game)
  if not D.boot(game) then return D.finish() end
  D.haltVm()
  D.givePartyAndRepel()
  local Space = require("src.core.game3.scripting.space")
  local C = require("src.core.game3.constants").of("emerald")

  -- pokeemerald/data/scripts/item_ball_scripts.inc:61
  D.check(D.goTo(game, "EM_ROUTE111", 33, 105, "up"), "route111_loaded")
  local ballKey = Space.bundle.labels.Route111_EventScript_ItemTMSandstorm
  -- pokeemerald/data/event_scripts.s:942
  local ballWants = {
    { text = "BRENDAN found one TM37 SANDSTORM!", label = "tm_ball_found_one_tm37_sandstorm",
      shot = "3116_01_tm_ball_found_tm37_sandstorm.png" },
    { text = "put away the TM37", label = "tm_ball_put_away_rebuffers_item_name",
      shot = "3116_02_tm_ball_put_away_tm37.png" },
  }
  local pages, hit = runScript(game, function()
    return D.check(ballKey and Space.startScript(ballKey, 18, 2), "tm_ball_script_started")
  end, ballWants)
  report("tm_ball", pages, hit, ballWants)
  D.check(D.flags().get("FLAG_ITEM_ROUTE_111_TM_SANDSTORM"), "tm_ball_flag_set")

  -- pokeemerald/data/scripts/obtain_item.inc:157
  D.check(D.goTo(game, "EM_ROUTE113", 22, 6, "up"), "route113_loaded")
  local Field = require("src.core.game3.field")
  local hiddenWants = {
    { text = "BRENDAN found one TM32 DOUBLE TEAM!", label = "hidden_found_one_tm32_double_team",
      shot = "3116_03_hidden_tm32_double_team.png" },
  }
  pages, hit = runScript(game, function()
    local hidden = {
      item = C:require("items", "ITEM_TM32"),
      flag = C:require("flags", "FLAG_HIDDEN_ITEM_ROUTE_113_TM_DOUBLE_TEAM"),
    }
    return D.check(Field.pickUpHiddenItem(game, hidden), "hidden_tm_script_started")
  end, hiddenWants)
  report("hidden_tm", pages, hit, hiddenWants)

  -- pokeemerald/data/maps/MauvilleCity_GameCorner/scripts.inc:272
  D.check(D.goTo(game, "EM_MAUVILLE_CITY_GAME_CORNER", 13, 7, "right"), "game_corner_loaded")
  local cornerKey = Space.bundle.labels.MauvilleCity_GameCorner_EventScript_TMIceBeam
  -- pokeemerald/data/maps/MauvilleCity_GameCorner/scripts.inc:666
  local cornerWants = {
    { text = "So your choice is the TM13 ICE BEAM?", label = "game_corner_choice_tm13_ice_beam",
      shot = "3116_04_game_corner_tm13_ice_beam.png" },
  }
  pages, hit = runScript(game, function()
    return D.check(cornerKey and Space.startScript(cornerKey, nil, 4), "game_corner_script_started")
  end, cornerWants, "So your choice is")
  report("game_corner", pages, hit, cornerWants)

  D.finish()
end
