-- POKEPORT_GAME=gold POKEPORT_IDENTITY=gold-sep04 POKEPORT_DRIVER=tests/drivers/gold_import_scenes_bug2245.lua love .
local U = require("tests.drivers.util")
local Gen2Layout = require("src.save_convert.Gen2Layout")
local SaveConvert = require("src.save_convert.SaveConvert")

local SIZE = 32768

local function buildCart(maps)
  local L = Gen2Layout.goldSilver
  local b = {}
  for i = 0, SIZE - 1 do b[i] = 0 end
  local name = { 0x86, 0x8E, 0x8B, 0x83, 0x50 }
  for i, c in ipairs(name) do b[L.wPlayerName + i - 1] = c end
  local lab = assert(maps and maps.ELMS_LAB, "no ELMS_LAB in this cache")
  b[L.wMapGroup], b[L.wMapNumber] = lab.group, lab.map
  b[L.wXCoord], b[L.wYCoord] = 4, 8
  b[L.wPartySpecies] = 0xFF
  b[L.wItems], b[L.wKeyItems], b[L.wBalls] = 0xFF, 0xFF, 0xFF
  for _, base in ipairs(L.boxes) do b[base + 1] = 0xFF end
  -- engine/events/std_scripts.asm:557
  b[L.wEventFlags + 6] = 0x40
  -- maps/VictoryRoad.asm:58
  b[L.wEventFlags + 216] = 0x04
  -- data/maps/scenes.asm:7
  b[L.sceneVars.ELMS_LAB] = 2
  b[L.sceneVars.NEW_BARK_TOWN] = 1
  b[L.sceneVars.ROUTE_27] = 1
  b[L.sceneVars.VICTORY_ROAD] = 1
  b[L.sCheckValue1], b[L.sCheckValue2] = 0x63, 0x7F
  local sum = 0
  for i = L.sGameData, L.sGameDataEnd - 1 do sum = (sum + b[i]) % 65536 end
  b[L.sChecksum], b[L.sChecksum + 1] = sum % 256, math.floor(sum / 256)
  local out = {}
  for i = 0, SIZE - 1 do out[i + 1] = string.char(b[i]) end
  return table.concat(out)
end

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-import-scenes-2245"
  local failed = 0
  local function pass(ok, line)
    if not ok then failed = failed + 1 end
    U.log((ok and "PASS " or "FAIL ") .. line)
  end

  local function settle(world)
    for _ = 1, 240 do
      if not world:busy() then break end
      U.wait(1)
    end
    U.wait(30)
  end

  U.wait(45)
  local ok, err = pcall(function()
    assert(game.world and game.world.maps, "gold world did not boot")
    local save, why = SaveConvert.importSav(buildCart(game.world.maps), "gold", "gold")
    assert(save, "import failed: " .. tostring(why))
    pass(save.mapScenes and save.mapScenes.ELMS_LAB == 2, "2245 import carries ELMS_LAB scene 2")

    game:continueGame(save)
    U.wait(10)
    local world = assert(game.world and game.world.map and game.world, "CONTINUE did not boot a world")
    pass(world.map.id == "ELMS_LAB", "2245 continue lands in ELMS_LAB (got " .. tostring(world.map.id) .. ")")
    settle(world)
    pass(world:scene() == 2, "2245 ELMS_LAB scene is 2 (got " .. tostring(world:scene()) .. ")")
    pass(not world:scriptRunning(), "2245 Elm's intro does not replay")
    U.shot(game, out .. "/2245_01_elms_lab_no_intro.png")

    local stops = {
      { "NEW_BARK_TOWN", 1, 8, "left", 1, "2245_02_new_bark_no_teacher.png" },
      { "ROUTE_27", 18, 10, "left", 1, "2245_03_route27_no_fisher.png" },
      { "VICTORY_ROAD", 12, 8, "up", 1 },
    }
    for _, s in ipairs(stops) do
      local mapId, x, y, facing, want, shot = s[1], s[2], s[3], s[4], s[5], s[6]
      assert(world:setMap(mapId, x, y, facing), "setMap " .. mapId)
      settle(world)
      pass(world:scene() == want,
        ("2245 %s scene is %d (got %s)"):format(mapId, want, tostring(world:scene())))
      pass(not world:tryCoordScript(), "2245 " .. mapId .. " coord_event stays quiet")
      U.wait(30)
      pass(not world:scriptRunning(), "2245 " .. mapId .. " no script running")
      if mapId ~= "VICTORY_ROAD" then U.shot(game, out .. "/" .. shot) end
    end

    -- maps/VictoryRoad.asm:263
    local rival
    for _, obj in ipairs(world.map.def.objects or {}) do
      if obj.x == 18 and obj.y == 13 then rival = obj end
    end
    assert(rival, "no object at (18,13) in VICTORY_ROAD")
    local flagSet = world.events:get(rival.eventFlag)
    pass(flagSet, ("2245 VICTORY_ROAD rival flag %s is set (got %s)"):format(
      tostring(rival.eventFlag), tostring(flagSet)))
    assert(world:setMap("VICTORY_ROAD", 15, 11, "up"), "setMap VICTORY_ROAD recentre")
    settle(world)
    local npc = world:npcAt(18, 13)
    pass(npc == nil, "2245 VICTORY_ROAD no object sprite at (18,13) (got "
      .. tostring(npc and (npc.sprite or npc.name or "npc")) .. ")")
    U.shot(game, out .. "/2245_04_victory_road_rival_cell_empty.png")
  end)
  if not ok then
    failed = failed + 1
    U.log("FAIL 2245 driver error: " .. tostring(err))
  end
  U.log((failed == 0 and "PASS" or "FAIL") .. " gold_import_scenes_bug2245 shots in " .. out)
  love.event.quit(failed == 0 and 0 or 1)
end
