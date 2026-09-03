-- scripts/ViridianCity.asm:245; scripts/ViridianMart.asm:64
--   POKEPORT_DRIVER=tests/drivers/oldman_yellow_bug2122_test.lua \
--     POKEPORT_VERSION=yellow POKEPORT_IDENTITY=yellow-sep02 POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapScripts = require("data.scripts.init")
  local GameVersion = require("src.core.GameVersion")
  local TextBox = require("src.render.TextBox")
  local Pokemon = require("src.pokemon.Pokemon")

  local CITY = "VIRIDIAN_CITY"
  local MART = "VIRIDIAN_MART"
  local ROUTE = "ROUTE_1"
  local OLD_MAN = "VIRIDIANCITY_OLD_MAN"
  local OLD_MAN2 = "VIRIDIANCITY_OLD_MAN2"
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local APPROACHES = {
    { 19, 10, "up" }, { 19, 8, "down" }, { 20, 9, "left" },
  }
  local LOOKOUTS = {
    { 19, 7, "up" }, { 19, 8, "up" }, { 18, 7, "up" }, { 20, 6, "left" },
  }

  local fails = 0
  local function check(label, ok)
    if not ok then fails = fails + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function shot(name)
    local path = SHOT_DIR .. "/" .. name
    if U.shot(game, path) then U.log("captured", path) end
  end

  local function npcNamed(name)
    local ow = game.overworld
    for _, n in ipairs((ow and ow.npcs) or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local function mapId()
    local ow = game.overworld
    return ow and ow.map and ow.map.id
  end

  local function cityToggles()
    local t = game.save.objectToggles or {}
    return t[CITY] or {}
  end

  local function topIsBattle()
    local top = game.stack:top()
    return (top and top.demo and top.demoName) and top or nil
  end

  local function pageThrough(frames)
    for _ = 1, frames do
      local top = game.stack:top()
      if getmetatable(top) == TextBox then U.tap(game, "a") end
      U.wait(3)
    end
  end

  check("booted on Yellow", GameVersion.get() == "yellow")

  local cityHooks = mapScripts.get(CITY)
  check(CITY .. " has an onEnter hook",
        type(cityHooks) == "table" and type(cityHooks.onEnter) == "function")
  check(CITY .. " has Yellow TEXT_VIRIDIANCITY_OLD_MAN rows",
        type(cityHooks) == "table" and type(cityHooks.talk) == "table"
        and type(cityHooks.talk.TEXT_VIRIDIANCITY_OLD_MAN) == "table")
  local martHooks = mapScripts.get(MART)
  check(MART .. " has an onEnter hook",
        type(martHooks) == "table" and type(martHooks.onEnter) == "function")
  for _, label in ipairs({ "_ViridianCityOldManWantMeToShowYouAgainText",
                           "_ViridianCityOldManWatchCloselyText",
                           "_ViridianCityOldManNotGoodEnoughForYouText" }) do
    check(label .. " resolves", type(game.data.text[label]) == "string")
  end

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 6) }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_GOT_OAKS_PARCEL = true
  game.save.flags.EVENT_OAK_GOT_PARCEL = true
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.flags.EVENT_COMPLETED_CATCH_TRAINING = nil
  game.save.flags.EVENT_SPAWNED_OLD_MAN_1 = nil
  game.save.objectToggles = {}

  local stand
  U.teleport(game, CITY, APPROACHES[1][1], APPROACHES[1][2], "up")
  U.wait(20)
  local ow = game.overworld
  check("the tutorial old man (OLD_MAN2) is on the map", npcNamed(OLD_MAN2) ~= nil)
  check("the roaming old man (OLD_MAN) is not", npcNamed(OLD_MAN) == nil)
  for _, a in ipairs(APPROACHES) do
    if ow and ow.map:isWalkableCell(a[1], a[2]) and not ow:npcAtCell(a[1], a[2]) then
      stand = a
      break
    end
  end
  check("a free cell next to (19,9) to walk in from", stand ~= nil)
  stand = stand or APPROACHES[1]
  if stand ~= APPROACHES[1] then
    U.teleport(game, CITY, stand[1], stand[2], stand[3])
    U.wait(15)
  end

  local battle
  for _ = 1, 40 do
    U.hold(game, stand[3], 6)
    U.wait(4)
    battle = topIsBattle()
    if battle then break end
    if getmetatable(game.stack:top()) == TextBox then
      U.tap(game, "a")
      U.wait(6)
    end
  end
  if not battle then
    for _ = 1, 200 do
      battle = topIsBattle()
      if battle then break end
      if getmetatable(game.stack:top()) == TextBox then U.tap(game, "a") end
      U.wait(6)
    end
  end
  check("stepping onto (19,9) opened the catch demo", battle ~= nil)
  local function stackHas(state)
    for _, s in ipairs(game.stack.states) do
      if s == state then return true end
    end
    return false
  end
  if battle then
    for _ = 1, 3000 do
      if not stackHas(battle) then break end
      local top = game.stack:top()
      if top == battle then
        if battle.msgPrompt or battle.msgWaiting then U.tap(game, "a") end
      elseif getmetatable(top) == TextBox then
        U.tap(game, "a")
      end
      U.wait(2)
    end
  end
  check("the demo battle ended", battle ~= nil and not stackHas(battle))

  local gone = false
  for _ = 1, 600 do
    if npcNamed(OLD_MAN2) == nil then gone = true break end
    if getmetatable(game.stack:top()) == TextBox then U.tap(game, "a") end
    U.wait(3)
  end
  pageThrough(20)
  check("EVENT_COMPLETED_CATCH_TRAINING is set",
        game.save.flags.EVENT_COMPLETED_CATCH_TRAINING == true)
  check("OLD_MAN2 walked off and hid", gone)
  check("the toggle store says OLD_MAN2 is hidden", cityToggles()[OLD_MAN2] == false)
  shot("bug2122_after_tutorial.png")

  U.teleport(game, ROUTE, 10, 2, "up")
  U.wait(15)
  ow = game.overworld
  local col
  for x = 0, (ow and ow.map.widthCells or 20) - 1 do
    if ow and ow.map:isWalkableCell(x, 0) and ow.map:isWalkableCell(x, 1)
       and ow.map:isWalkableCell(x, 2) then
      col = x
      break
    end
  end
  check("a walkable column at the top of ROUTE_1", col ~= nil)
  col = col or 10
  U.teleport(game, ROUTE, col, 2, "up")
  U.wait(15)
  for _ = 1, 60 do
    if mapId() == CITY then break end
    U.hold(game, "up", 8)
    U.wait(2)
  end
  U.wait(20)
  check("walked across the Route 1 seam into Viridian City", mapId() == CITY)
  check("seam re-entry: OLD_MAN2 stays hidden", npcNamed(OLD_MAN2) == nil)
  check("seam re-entry: OLD_MAN not spawned before the Mart", npcNamed(OLD_MAN) == nil)
  ow = game.overworld
  check("seam re-entry: (18,9) is free", ow and ow:npcAtCell(18, 9) == nil)
  shot("bug2122_reenter_from_route1.png")

  U.teleport(game, CITY, 19, 10, "up")
  U.wait(20)
  check("door re-entry: OLD_MAN2 stays hidden", npcNamed(OLD_MAN2) == nil)
  check("door re-entry: OLD_MAN still hidden", npcNamed(OLD_MAN) == nil)

  U.teleport(game, MART, 3, 7, "up")
  U.wait(30)
  pageThrough(10)
  check("inside the Mart: EVENT_SPAWNED_OLD_MAN_1 set",
        game.save.flags.EVENT_SPAWNED_OLD_MAN_1 == true)
  check("inside the Mart: OLD_MAN toggled on", cityToggles()[OLD_MAN] == true)
  check("inside the Mart: OLD_MAN2 toggled off", cityToggles()[OLD_MAN2] == false)
  shot("bug2122_in_mart.png")

  local look
  U.teleport(game, CITY, LOOKOUTS[1][1], LOOKOUTS[1][2], LOOKOUTS[1][3])
  U.wait(20)
  ow = game.overworld
  for _, l in ipairs(LOOKOUTS) do
    if ow and ow.map:isWalkableCell(l[1], l[2]) and not ow:npcAtCell(l[1], l[2]) then
      look = l
      break
    end
  end
  look = look or LOOKOUTS[1]
  if look ~= LOOKOUTS[1] then
    U.teleport(game, CITY, look[1], look[2], look[3])
    U.wait(20)
  end
  local man = npcNamed(OLD_MAN)
  check("back in the city: OLD_MAN2 is gone", npcNamed(OLD_MAN2) == nil)
  check("back in the city: the roaming OLD_MAN is on the map", man ~= nil)
  check("he is on row 5 near (17,5)",
        man ~= nil and man.cellY == 5 and math.abs(man.cellX - 17) <= 3)
  if man then U.log(("OLD_MAN stands at (%d,%d)"):format(man.cellX, man.cellY)) end
  shot("bug2122_roaming_old_man.png")

  U.teleport(game, ROUTE, col, 2, "up")
  U.wait(15)
  for _ = 1, 60 do
    if mapId() == CITY then break end
    U.hold(game, "up", 8)
    U.wait(2)
  end
  U.wait(20)
  check("second seam re-entry: OLD_MAN2 still gone", npcNamed(OLD_MAN2) == nil)
  check("second seam re-entry: OLD_MAN still roaming", npcNamed(OLD_MAN) ~= nil)
  check("second seam re-entry: EVENT_SPAWNED_OLD_MAN_1 still set",
        game.save.flags.EVENT_SPAWNED_OLD_MAN_1 == true)

  U.teleport(game, CITY, look[1], look[2], look[3])
  U.wait(20)
  shot("bug2122_final.png")

  if fails > 0 then
    U.log(fails, "check(s) above say FAIL; the screen is not worth watching yet.")
  end
  U.log(("you are on (%d,%d) in Viridian City. The old man should be walking")
          :format(look[1], look[2]))
  U.log("left and right on row 5 above the girl, and (18,9) next to her should")
  U.log("be empty. Talk to him: he asks to show you how to catch POKEMON again.")

  while true do
    coroutine.yield()
  end
end
