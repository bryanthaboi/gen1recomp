-- data/maps/flypoints.asm:1, engine/pokegear/pokegear.asm:2203
local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")

return function(game)
  local deadline = love.timer.getTime() + 60
  local speed, volume = game.speedOverride, love.audio.getVolume()
  local writes = {}
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do
    writes[key] = rawget(game, key)
    game[key] = function() end
  end
  local fails = 0
  local function label(ok, name, detail)
    if not ok then fails = fails + 1 end
    print((ok and "PASS " or "FAIL ") .. name
      .. (detail ~= nil and (" (" .. tostring(detail) .. ")") or ""))
    return ok
  end
  local function check()
    assert(love.timer.getTime() < deadline, "60 second driver deadline")
  end
  local function wait(n) for _ = 1, n do check(); U.wait(1) end end
  local function settle(predicate, what)
    for _ = 1, 3600 do
      check()
      if predicate() then return end
      wait(1)
    end
    error("bounded settle failed: " .. what)
  end
  local function tap(key) check(); U.tap(game, key); wait(2) end
  local function top() return game.stack:top() end
  local function id() return top() and top().screenId end

  local ok, err = xpcall(function()
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "POKEPORT_SHOT_DIR required")
    love.audio.setVolume(0)
    game.speedOverride = 200
    settle(function()
      return game.world and game.world.map and not top()
        and not game.world:busy()
    end, "field ready")

    local FieldMoves = require("src.world.gen2.FieldMoves")
    local Mon = require("src.battle.gen2.Mon")
    local save, world = game.save, game.world

    local files = {
      ["mods/flyprobe/manifest.json"] = '{"id":"flyprobe","name":"flyprobe",'
        .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
      ["mods/flyprobe/main.lua"] = [[local mod = ...
local c = mod.content
c.landmarks:register("LANDMARK_MOD_SPOT", { name = "MOD\nSPOT", index = 96, x = 124, y = 92 })
c.spawns:register("SPAWN_MOD_SPOT", { map = "ROUTE_29", x = 48, y = 3 })
c.fly_points:register("SPAWN_MOD_SPOT", { landmark = "LANDMARK_MOD_SPOT", region = "johto", order = 1 })
c.spawns:patch("SPAWN_VIOLET", { x = 30 })]],
    }
    local loader = Loader.new({ fs = Sdk.memfs(files), generation = 2,
      version = game.save.version, dev = true })
    loader.game = game
    local data = {}
    for key, value in pairs(game.data) do data[key] = value end
    for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
    loader:load(data)
    FieldMoves.bindFlypoints(world.landmarks.flypoints, world.landmarks.spawns)
    local index
    for i, row in ipairs(FieldMoves.FLYPOINTS) do
      if row.spawn == "SPAWN_MOD_SPOT" then index = i end
    end
    assert(label(not loader.mods.flyprobe.failed and index ~= nil, "3092_registered",
      loader.mods.flyprobe.failed and loader.mods.flyprobe.error))

    save.player.badges = save.player.badges or {}
    save.player.badges.STORM = true
    save.engineFlags = save.engineFlags or {}
    for _, row in ipairs(FieldMoves.FLYPOINTS) do
      if row.flag then save.engineFlags[row.flag] = true end
    end
    save.visitedSpawns = nil
    local flyer = assert(Mon.new(game.data, "PIDGEOTTO", 24))
    table.remove(flyer.moves, 1)
    Mon.learnMove(flyer, "FLY", game.data)
    save.party = { flyer }
    label(not FieldMoves.hasVisitedSpawn(save, "SPAWN_MOD_SPOT"),
      "3092_not_visited_before_entry")

    world:warpToMapId("ROUTE_29", 40, 8, "down")
    settle(function()
      return world.map.id == "ROUTE_29" and not world:busy() and not top()
    end, "Route 29")
    label(FieldMoves.hasVisitedSpawn(save, "SPAWN_MOD_SPOT"), "3092_visited_on_entry")

    world:warpToMapId("VIOLET_CITY", 31, 26, "down")
    settle(function()
      return world.map.id == "VIOLET_CITY" and not world:busy() and not top()
    end, "Violet City")

    game:openStartMenuItem("pokemon")
    settle(function() return id() == "Gen2PartyMenu" end, "party menu")
    tap("a")
    local sub = assert(top().submenu, "action submenu")
    local row
    for n, item in ipairs(sub.items) do
      if item.id == "FLY" then row = n end
    end
    assert(row, "FLY action")
    for _ = 1, #sub.items do
      if sub.index == row then break end
      tap("down")
    end
    tap("a")
    settle(function() return id() == "Gen2Pokegear" and top().fly end, "fly picker")
    local picker = top()
    local spawns = {}
    local at
    for n, r in ipairs(picker.fly) do
      spawns[n] = r.spawn
      if r.spawn == "SPAWN_MOD_SPOT" then at = n end
    end
    label(at ~= nil and spawns[at - 1] == "SPAWN_CHERRYGROVE"
      and spawns[at + 1] == "SPAWN_VIOLET", "3092_listed_in_johto",
      table.concat(spawns, ","))
    picker.flyIndex = at or 1
    game.speedOverride = speed
    wait(12)
    label(U.still(game, out .. "/3092_01_fly_map_mod_spot.png"), "3092_fly_map_shot")
    game.speedOverride = 200
    tap("a")
    settle(function()
      return world.map.id == "ROUTE_29" and not world:busy() and not top()
        and not world.mapSetup
    end, "fly to mod spot")
    label(world.player.cellX == 48 and world.player.cellY == 3, "3092_landed",
      tostring(world.player.cellX) .. "," .. tostring(world.player.cellY))

    assert(world:flyTo("SPAWN_VIOLET", flyer), "fly to Violet")
    settle(function()
      return world.map.id == "VIOLET_CITY" and not world:busy() and not top()
        and not world.mapSetup
    end, "fly to Violet")
    label(world.player.cellX == 30, "3092_patched_landing", world.player.cellX)

    save.blackoutMap = "ROUTE_29"
    local heal = world:healPoint()
    label(heal and heal.spawn == "SPAWN_MOD_SPOT", "3092_whiteout_point",
      heal and heal.spawn)
  end, debug.traceback)

  game.speedOverride = speed
  love.audio.setVolume(volume)
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do
    game[key] = writes[key]
  end
  if not ok then
    fails = fails + 1
    print("FAIL driver_error " .. tostring(err))
  end
  print(fails == 0 and "PASS gen2_mod_fly_point_3092"
    or ("FAIL gen2_mod_fly_point_3092 " .. fails .. " failures"))
  love.event.quit(fails == 0 and 0 or 1)
  while true do coroutine.yield() end
end
