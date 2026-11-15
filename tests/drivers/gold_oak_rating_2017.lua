--   POKEPORT_IDENTITY=gold-aug30 POKEPORT_GAME=gold \
--     POKEPORT_DRIVER=tests/drivers/gold_oak_rating_2017.lua \
--     POKEPORT_SHOT_DIR=/tmp/oak-rating-2017 \
-- (data/text/common_2.asm:942), whose third line is a `cont`
-- (home/text.asm:442 _ContTextNoPause) -- shots 04 and 05 are the two halves
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/oak-rating-2017"
  local fails = 0

  local function ok(cond, msg)
    if cond then print("[oakrating] ok   " .. msg)
    else fails = fails + 1 print("[oakrating] FAIL " .. msg) end
    return cond
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
    local top = game.stack:top()
    for _ = 1, 600 do
      if not (top and top.typer and not top.typer:done()) then break end
      U.wait(1)
    end
  end

  U.wait(45)
  local w = game.world
  assert(w and w.map, "gold world did not boot")
  local save = game.save

  local Mon = require("src.battle.gen2.Mon")
  save.party = { Mon.new(game.data, "CYNDAQUIL", 10) }
  save.pokedex = { seen = {}, caught = {} }
  for i = 1, 205 do
    save.pokedex.seen["DEX" .. i] = true
    save.pokedex.caught["DEX" .. i] = true
  end
  w:setEngineFlag(require("src.ui.gen2.CenterPcMenu").ENGINE_POKEDEX, true)

  local function topId()
    local top = game.stack:top()
    return top and top.screenId or nil
  end

  assert(w:setMap("CHERRYGROVE_POKECENTER_1F", 4, 4, "up"),
    "setMap CHERRYGROVE_POKECENTER_1F failed")
  U.wait(5)
  local pcX, pcY
  for cy = 0, w.map.heightCells - 1 do
    for cx = 0, w.map.widthCells - 1 do
      if w.map:cellCollision(cx, cy) == 0x93 then pcX, pcY = cx, cy end
    end
  end
  assert(pcX, "no COLL_PC tile in the Pokecenter")
  assert(w:setMap("CHERRYGROVE_POKECENTER_1F", pcX, pcY + 1, "up"),
    "setMap onto the PC tile failed")
  U.wait(5)

  tap("a", 8)
  ok(topId() == "Gen2CenterPcMenu",
    "A at the Pokecenter PC opens the whose-PC menu (top: "
      .. tostring(topId()) .. ")")
  tap("a", 4)
  local pc = game.stack:top()
  ok(pc and pc.entries and pc.entries[3] and pc.entries[3].id == "oaks",
    "the #DEX flag puts PROF.OAK's PC on the list")

  tap("down", 4)
  tap("down", 4)
  tap("a", 4)
  tap("a", 4)
  tap("a", 6)
  ok(pc and pc.confirm ~= nil, "_OakPCText1 asks for the yes/no")
  U.shot(game, out .. "/01-rated-prompt.png")
  tap("a", 6)

  local shot = 1
  local seen = {}
  for _ = 1, 10 do
    if not (pc and pc.message) then break end
    local page = pc.message.pages[pc.message.page]
    ok(#page <= 2, "page " .. pc.message.page .. " is at most two lines ("
      .. table.concat(page, " / ") .. ")")
    seen[#seen + 1] = table.concat(page, " / ")
    shot = shot + 1
    U.shot(game, out .. ("/%02d-page%d.png"):format(shot, pc.message.page))
    tap("a", 6)
  end

  ok(seen[4] == "Wow! You've hit / 200! Your POKéDEX",
    "205 caught reaches _OakRating15 (" .. tostring(seen[4]) .. ")")
  ok(seen[5] == "200! Your POKéDEX / is looking great!",
    "and its cont scrolls rather than adding a third line ("
      .. tostring(seen[5]) .. ")")

  print(("[oakrating] %d failures"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
