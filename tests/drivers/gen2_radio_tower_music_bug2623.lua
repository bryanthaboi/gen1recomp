local U = require("tests.drivers.util")
local Music = require("src.core.Music")
local FlagIds = require("src.core.gen2.FlagIds")

return function(game)
  U.wait(60)
  local world = game.world
  local failures = 0
  local function check(ok, label)
    if not ok then failures = failures + 1 end
    print((ok and "PASS " or "FAIL ") .. label)
  end
  if not (world and world.map) then
    print("FAIL 2623 gen2 world did not boot")
    return love.event.quit(1)
  end
  check(game.mods and game.mods.safeMode == true, "2623 mods disabled before boot")
  world.checkTrainerBattle = function() return false end
  local tower = world:engineFlagId("ENGINE_ROCKETS_IN_RADIO_TOWER", 18)
  local mahogany = world:engineFlagId("ENGINE_ROCKETS_IN_MAHOGANY", 22)
  check(type(tower) == "number" and type(mahogany) == "number",
    "2623 Rocket engine flags resolve")
  if not (tower and mahogany) then return love.event.quit(1) end
  local events = FlagIds.events(game.data.gen2Constants)
  world.events:set(events.EVENT_RADIO_TOWER_ROCKET_TAKEOVER, false)
  world.events:set(events.EVENT_RADIO_TOWER_CIVILIANS_AFTER, true)
  world.mapScenes.RADIO_TOWER_5F = 2
  world.mapScenes.MAHOGANY_MART_1F = 0
  local dir = os.getenv("POKEPORT_SHOT_DIR")
  local function enter(mapId, x, y)
    if not world:warpToMapId(mapId, x, y, "up") then
      check(false, "2623 load " .. mapId)
      return false
    end
    U.wait(120)
    check(world.map.id == mapId, "2623 entered " .. mapId)
    return world.map.id == mapId
  end

  world:setEngineFlag(tower, true)
  if not enter("GOLDENROD_CITY", 5, 10) then return love.event.quit(1) end
  check(Music.current() == "Music_GoldenrodCity", "2623 ordinary Goldenrod music")
  for floor = 1, 5 do
    local mapId = "RADIO_TOWER_" .. floor .. "F"
    world:setEngineFlag(tower, true)
    if not enter(mapId, 2, 6) then return love.event.quit(1) end
    print("2623 " .. mapId .. " flag=" .. tower
      .. " active=" .. tostring(world:engineFlag(tower))
      .. " resolved=" .. tostring(world:mapMusicSong(mapId))
      .. " playing=" .. tostring(Music.current()))
    check(world:engineFlag(tower), "2623 takeover active " .. mapId)
    check(Music.current() == "Music_RocketTheme", "2623 rocket_music_floor_" .. floor)
    if dir then U.still(game, dir .. "/2623_radio_tower_" .. floor .. "f_takeover.png") end
    world:setEngineFlag(tower, false)
    world:playMapMusic()
    U.wait(120)
    check(Music.current() == "Music_GoldenrodCity", "2623 cleared_music_floor_" .. floor)
  end

  world:setEngineFlag(mahogany, true)
  if not enter("MAHOGANY_MART_1F", 2, 6) then return love.event.quit(1) end
  check(world:engineFlag(mahogany), "2623 Mahogany Rockets active")
  check(Music.current() == "Music_RocketHideout", "2623 mahogany_rocket_music")
  if dir then U.still(game, dir .. "/2623_mahogany_mart_rocket_music.png") end
  world:setEngineFlag(mahogany, false)
  world:playMapMusic()
  U.wait(120)
  check(Music.current() == "Music_CherrygroveCity", "2623 mahogany_cleared_music")
  print("RESULT 2623 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end
