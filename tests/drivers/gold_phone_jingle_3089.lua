-- tools/run_driver.sh gold <identity> tests/drivers/gold_phone_jingle_3089.lua [shotdir]
local U = require("tests.drivers.util")
local Sound = require("src.core.Sound")
local Phone = require("src.core.gen2.Phone")

local JOEY = 15

return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    love.event.quit(failures == 0 and 0 or 1)
  end
  local function boxText(top)
    if not (top and top.pages) then return "" end
    local out = {}
    for _, page in ipairs(top.pages) do
      out[#out + 1] = type(page) == "table" and table.concat(page, " ") or tostring(page)
    end
    return table.concat(out, " ")
  end

  U.wait(45)
  local world = game.world
  local save = game.save
  if not check(world and world.map, "3089 gold world booted") then return finish() end
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold_phone_jingle_3089"

  Phone.removeContact(save, JOEY)
  local rematch = Phone.rematchEvent(JOEY)
  -- pokegold constants/event_flags.asm:287-288
  world.events:set(rematch, false)
  world.events:set(rematch - 1, false)
  world.noWildEncounters = true

  world:warpToMapId("ROUTE_30", 7, 29, "left")
  U.wait(20)
  local def = world.map and world.map.def
  for _, obj in pairs(def and def.objects or {}) do
    if obj.x == 6 and obj.y == 29 and obj.eventFlag and obj.eventFlag ~= 0xFFFF then
      world.events:set(obj.eventFlag, false)
    end
  end
  world:warpToMapId("ROUTE_30", 7, 29, "left")
  U.wait(20)
  world.noWildEncounters = true

  local joey
  for _, npc in ipairs(world.npcs or {}) do
    if npc.cellX == 6 and npc.cellY == 29 and npc.def and npc.def.trainer then joey = npc end
  end
  if not check(joey ~= nil, "3089 joey on route 30") then return finish() end
  world.events:set(joey.def.trainer.event, true)
  world.player.facing = "left"

  local log = {}
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    local src = realPlay(data, name, ...)
    log[#log + 1] = { name = name, started = src ~= nil, frame = U.frame(),
      text = boxText(game.stack:top()) }
    return src
  end

  local choice
  for _ = 1, 400 do
    local top = game.stack:top()
    if top and top.labels and top.onChoose then choice = top break end
    U.tap(game, "a")
    U.wait(3)
  end
  if not check(choice ~= nil, "3089 yes/no for the number is up") then
    Sound.play = realPlay
    return finish()
  end
  choice.index = 1
  game.input.state.a = true
  for _ = 1, 90 do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    coroutine.yield()
    if game.stack:top() and boxText(game.stack:top()):find("registered") then break end
  end
  game.input.state.a = false

  local jingle
  for _ = 1, 240 do
    for _, row in ipairs(log) do
      if row.name == "Sfx_RegisterPhoneNumber" then jingle = row end
    end
    if jingle then break end
    U.wait(1)
  end
  Sound.play = realPlay

  check(Phone.hasContact(save, JOEY), "3089 joey number registered")
  check(jingle ~= nil and jingle.started, "3089 jingle starts under the registered line")
  check(jingle ~= nil and jingle.text:find("registered") ~= nil, "3089 jingle plays with the registered text up")
  for _, row in ipairs(log) do
    print(("[3089] f=%d %s started=%s"):format(row.frame, tostring(row.name), tostring(row.started)))
  end
  local top = game.stack:top()
  check(top and boxText(top):find("registered") ~= nil and Sound.sfxBusy(),
    "3089 box holds through the jingle")
  U.wait(20)
  check(U.still(game, dir .. "/3089_01_registered_jingle.png"), "3089 registered shot")
  finish()
end
