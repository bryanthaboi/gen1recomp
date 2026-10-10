local U = require("tests.drivers.util")
return function(game)
  local deadline = love.timer.getTime() + 25
  local speed, volume = game.speedOverride, love.audio.getVolume()
  local writes = {}
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do
    writes[key] = rawget(game, key)
    game[key] = function() error("driver attempted persistent write") end
  end
  local function check() assert(love.timer.getTime() < deadline, "25 second driver deadline") end
  local function wait(n) for _ = 1, n do check(); U.wait(1) end end
  local function settle(predicate, label)
    for _ = 1, 1800 do check(); if predicate() then return end; wait(1) end
    error("bounded settle failed: " .. label)
  end
  local function top() return game.stack:top() end
  local function id() return top() and top().screenId end
  local out
  local results = {}
  local function result(ok, label)
    results[#results + 1] = (ok and "PASS " or "FAIL ") .. label
    return ok
  end
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY")
    assert(identity and identity ~= "pokemon-love2d", "isolated identity required")
    out = assert(os.getenv("POKEPORT_SHOT_DIR"), "explicit screenshot directory required")
    assert(require("src.core.GameVersion").get() == "crystal", "Crystal only")
    love.audio.setVolume(0); game.speedOverride = 200
    settle(function() return game.world and game.world.map and not top() and not game.world:busy() end,
      "native field ready")
    local Phone = require("src.core.gen2.Phone")
    local world, save = game.world, game.save
    save.engineFlags = save.engineFlags or {}
    save.engineFlags[2] = true
    local ERIN = 36
    Phone.addContact(save, ERIN)
    world:warpToMapId("GOLDENROD_CITY", 15, 28, "down")
    settle(function() return world.map.id == "GOLDENROD_CITY" and not world:busy() and not top() end,
      "Goldenrod City")
    local flag = world:engineFlagId("ENGINE_ERIN_READY_FOR_REMATCH")
    assert(flag, "ENGINE_ERIN_READY_FOR_REMATCH id")
    world:setEngineFlag(flag, true)
    local seen = {}
    local vm = world.vm
    local oldShow = vm.showTextFn
    vm.showTextFn = function(body, ...)
      seen[#seen + 1] = tostring(body)
      return oldShow(body, ...)
    end
    game:openStartMenuItem("pokegear")
    settle(function() return id() == "Gen2Pokegear" end, "Pokegear")
    local gear = top()
    for _ = 1, #gear.cards do
      if gear:card().id == "phone" then break end
      U.tap(game, "right"); wait(2)
    end
    assert(gear:card().id == "phone", "phone card")
    wait(4)
    gear:callContact(ERIN)
    local found
    for _ = 1, 1200 do
      check()
      for _, s in ipairs(seen) do
        if s:find("waiting on") then found = s end
      end
      if found then break end
      if top() ~= gear then U.tap(game, "a") end
      wait(3)
    end
    vm.showTextFn = oldShow
    assert(found, "Erin's come-battle page never printed")
    wait(30)
    U.tap(game, "a")
    wait(40)
    U.still(game, out .. "/2832_01_erin_names_route46_from_goldenrod.png")
    local flat = found:gsub("\n", " ")
    result(flat:find("ROUTE 46") ~= nil, "crystal_phone_rematch_landmark_bug2832 Erin names ROUTE 46")
    result(flat:find("GOLDENROD") == nil, "crystal_phone_rematch_landmark_bug2832 not the player's GOLDENROD CITY")
    print("[2832] page: " .. flat)
  end, debug.traceback)
  game.speedOverride = speed; love.audio.setVolume(volume)
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do game[key] = writes[key] end
  local pass = ok
  for _, line in ipairs(results) do
    print(line)
    if line:sub(1, 4) == "FAIL" then pass = false end
  end
  if not ok then print("FAIL crystal_phone_rematch_landmark_bug2832 " .. tostring(err)) end
  love.event.quit(pass and 0 or 1)
  while true do coroutine.yield() end
end
