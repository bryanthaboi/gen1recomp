-- ../pokecrystal/home/fade.asm:35-62
-- ../pokecrystal/engine/battle/core.asm DrawEnemyHUDBorder / DrawPlayerHUDBorder
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-hud-fade"
  os.execute("mkdir -p '" .. out .. "'")
  local shotN = 0
  local function shot(tag)
    shotN = shotN + 1
    game.capturePath = string.format("%s/%03d_%s.png", out, shotN, tag)
  end
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[hud-fade] " .. (cond and "PASS " or "FAIL ") .. msg)
    return cond
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")
  local save, data = game.save, game.data
  save.party = { Mon.new(data, "CYNDAQUIL", 12) }

  local wild = Mon.new(data, "SENTRET", 3)
  ok(world:startBattle({ wild = wild }), "a wild battle starts")
  local screen
  for _ = 1, 600 do
    U.wait(1)
    local top = game.stack:top()
    if top and top.battle then screen = top break end
  end
  ok(screen ~= nil, "the battle screen is up")
  for _ = 1, 900 do
    if screen.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(2)
  end
  ok(screen.phase == "menu", "reached the battle menu")
  U.wait(20)
  shot("hud_before_fade")
  U.wait(6)

  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "right")
  U.wait(4)
  U.tap(game, "a")

  local rows, taken = {}, {}
  for _ = 1, 900 do
    if game.stack:top() ~= screen then break end
    if screen.phase == "fadeout" then
      local row = screen:exitFadeBgp()
      if row and not taken[row] then
        taken[row] = true
        rows[#rows + 1] = row
        shot(("hud_fade_row_%02x"):format(row))
      end
    elseif (screen.messageTimer or 0) > 0 then
      U.tap(game, "a")
    end
    U.wait(1)
  end
  local rowText = {}
  for _, row in ipairs(rows) do rowText[#rowText + 1] = ("%02x"):format(row) end
  ok(table.concat(rowText, ",") == "90,40,00",
    "shot every fade row (" .. table.concat(rowText, ",") .. ")")

  print("[hud-fade] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")) .. " -- " .. shotN .. " shots in " .. out)
  love.event.quit(fails == 0 and 0 or 1)
end
