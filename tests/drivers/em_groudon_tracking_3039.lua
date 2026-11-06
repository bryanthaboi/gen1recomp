local U = require("tests.drivers.util")
local D = require("tests.drivers.em_fc_util").new("em_groudon_tracking_3039")

return function(game)
  if not D.boot(game) then return D.finish() end
  if not D.check(not game.mods or #(game.mods.loaded or {}) == 0, "vanilla_no_loaded_mods") then
    return D.finish()
  end
  D.haltVm()
  D.givePartyAndRepel()
  local Space = require("src.core.game3.scripting.space")
  local Weather = require("src.core.game3.weather")
  local Effect = require("src.core.game3.field_weather_rse")
  local F = D.flags()
  F.set("FLAG_SYS_GAME_CLEAR", true)
  F.set("FLAG_RECEIVED_CASTFORM", true)
  F.set("FLAG_DEFEATED_GROUDON", false)
  F.set("FLAG_DEFEATED_KYOGRE", true)
  F.setVar("VAR_SHOULD_END_ABNORMAL_WEATHER", 0)
  F.setVar("VAR_ABNORMAL_WEATHER_STEP_COUNTER", 0)
  if not D.check(D.goTo(game, "EM_ROUTE119_WEATHER_INSTITUTE_2F", 18, 7, "up"),
      "weather_institute_loaded") then return D.finish() end
  F.set("FLAG_TEMP_2", false)
  local key = Space.bundle.labels.Route119_WeatherInstitute_2F_EventScript_WeatherScientist
  if not D.check(key and Space.startScript(key, nil, 2), "scientist_cached_script_started") then
    return D.finish()
  end
  local Message = require("src.ui.game3.message")
  local pages, shotDrought = {}, false
  for _ = 1, 1200 do
    if not Space.vm:isRunning() then break end
    if Message.isOpen() and Message.isWaiting() then
      local page = (tostring(Message.currentPage() or ""):gsub("[\n\f]", " "))
      if pages[#pages] ~= page then pages[#pages + 1] = page end
      if not shotDrought and page:find("drought has been recorded", 1, true) then
        shotDrought = D.shot(game, "3116_scientist_drought_recorded_in_route.png", true)
      end
    end
    U.tap(game, "a")
    U.wait(3)
  end
  if not D.check(not Space.vm:isRunning(), "scientist_script_completed") then return D.finish() end
  local chosen = F.var("VAR_ABNORMAL_WEATHER_LOCATION")
  if not D.check(chosen >= 1 and chosen <= 8, "scientist_selected_terra_location") then return D.finish() end
  print("INFO selected_location=" .. chosen)
  print("INFO scientist_pages=" .. table.concat(pages, " | "))
  -- pokeemerald/src/field_specials.c:3472
  local routeNames = { "ROUTE 114", "ROUTE 114", "ROUTE 115", "ROUTE 115",
    "ROUTE 116", "ROUTE 116", "ROUTE 118", "ROUTE 118" }
  local want = routeNames[chosen]
  local recorded, near = false, false
  for _, page in ipairs(pages) do
    if page:find("drought has been recorded in " .. want .. ".", 1, true) then recorded = true end
    if page:find("somewhere near " .. want, 1, true) then near = true end
  end
  D.check(recorded, "scientist_drought_recorded_in_route_name")
  D.check(near, "scientist_somewhere_near_route_name")
  D.check(shotDrought, "scientist_drought_text_shot")

  local locations = {
    { "EM_ROUTE114", 7, 7 }, { "EM_ROUTE114", 6, 48 },
    { "EM_ROUTE115", 21, 8 }, { "EM_ROUTE115", 36, 12 },
    { "EM_ROUTE116", 59, 15 }, { "EM_ROUTE116", 79, 8 },
    { "EM_ROUTE118", 42, 8 }, { "EM_ROUTE118", 9, 8 },
  }
  local function enter(location)
    local row = locations[location]
    return D.goTo(game, row[1], row[2], row[3], "up", { keepScripts = true })
  end
  local function checkDrought(label)
    for _ = 1, 400 do
      local s = Effect.snapshot()
      if s.curr == Weather.DROUGHT and s.colorMapIndex < 0 then break end
      U.wait(1)
    end
    local s = Effect.snapshot()
    print(string.format("INFO %s saved=%s curr=%s next=%s map=%s stage=%s initialized=%s steps=%s", label,
      tostring(Weather.get()), tostring(s.curr), tostring(s.next), tostring(s.colorMapIndex),
      tostring(s.droughtStage), tostring(s.initialized),
      tostring(F.var("VAR_ABNORMAL_WEATHER_STEP_COUNTER"))))
    D.check(Weather.get() == Weather.DROUGHT and s.curr == Weather.DROUGHT
      and s.colorMapIndex < 0 and s.initialized, label .. "_route_activates_drought")
    local stages = {}
    for _ = 1, 180 do
      stages[Effect.snapshot().droughtStage] = true
      U.wait(1)
    end
    local count = 0
    for _ in pairs(stages) do count = count + 1 end
    D.check(count > 1, label .. "_drought_cycles")
  end
  D.check(enter(chosen), "scientist_selected_route_loaded")
  checkDrought("scientist")
  D.check(D.shot(game, "3039_scientist_selected_route_drought.png", true), "scientist_drought_shot")

  local first = locations[chosen]
  D.check(enter(chosen <= 2 and 3 or 1), "nonmatching_route_loaded")
  U.wait(120)
  D.check(F.var("VAR_ABNORMAL_WEATHER_LOCATION") == chosen
    and Effect.snapshot().curr ~= Weather.DROUGHT, "nonmatching_route_has_no_drought")
  F.setVar("VAR_ABNORMAL_WEATHER_LOCATION", 0)
  D.check(enter(chosen), "same_route_clear_loaded")
  U.wait(120)
  D.check(Effect.snapshot().curr ~= Weather.DROUGHT, "no_event_restores_route_weather")
  D.check(D.shot(game, "3039_same_route_clear.png", true), "same_route_clear_shot")
  F.setVar("VAR_ABNORMAL_WEATHER_LOCATION", chosen)
  D.check(enter(chosen), "same_route_drought_loaded")
  checkDrought("revisit")
  D.check(D.shot(game, "3039_same_route_drought.png", true), "same_route_drought_shot")
  print("INFO compared_map=" .. first[1])

  for location = 1, 8 do
    F.setVar("VAR_ABNORMAL_WEATHER_LOCATION", location)
    F.setVar("VAR_ABNORMAL_WEATHER_STEP_COUNTER", 0)
    D.check(enter(location), "fixture_location_" .. location .. "_loaded")
    checkDrought("fixture_location_" .. location)
  end
  D.finish()
end
