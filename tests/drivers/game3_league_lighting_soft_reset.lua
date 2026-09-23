local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_league_lighting_soft_reset"

local LORELEI = "FR_POKEMON_LEAGUE_LORELEIS_ROOM"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_league_lighting_soft_reset")
    love.event.quit(0)
  else
    print("FAIL game3_league_lighting_soft_reset failures=" .. failures)
    love.event.quit(1)
  end
end

local function waitBoot(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then return true end
    U.wait(1)
  end
  return false
end

local function run(game)
  waitBoot(game)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local NativeTileset = require("src.core.game3.tileset_native")
  local Lighting = require("src.core.game3.league_lighting")

  if not result(Runtime.getSession() ~= nil, "new game reached the field") then return end

  local function pumpUntil(frames, pred)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function slotPixels(ts)
    local pix = ts and ts.slotPix[7]
    if not (pix and #pix.under > 0) then return nil end
    local parts = {}
    for i = 1, #pix.under do
      local p = pix.under[i]
      local r, g, b = ts.imageData:getPixel(p[1], p[2])
      parts[#parts + 1] = string.format("%.3f%.3f%.3f", r, g, b)
    end
    return table.concat(parts)
  end

  -- pokefirered/data/scripts/pokemon_league.inc:10
  Flags.setVar(Space.store, nil, Flags.IDS.VAR_MAP_SCENE_POKEMON_LEAGUE, 0)
  Map.load(nil, game, LORELEI, { x = 6, y = 12, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 6, 12, "up"
  if not result(Map.current == LORELEI and Lighting.task ~= nil, "Lorelei's room started the lighting task") then return end
  local pair = Map.currentDef().pair
  local ts = NativeTileset.get(pair)
  local base = slotPixels(ts)
  pumpUntil(600, function() return Flags.getFlag(Space.store, nil, 0x2) end)
  pumpUntil(600, function() return Lighting.task and Lighting.task.index >= 3 end)
  local lit = slotPixels(ts)
  result(Lighting.task and Lighting.task.index >= 3 and base ~= nil and lit ~= base,
    "lighting cycled to palette " .. tostring(Lighting.task and Lighting.task.index))
  U.shot(game, DIR .. "/leag_soft_reset_before_lorelei_lit.png")

  game.softResetRequested = true
  U.wait(2)
  result(waitBoot(game), "soft reset returned to the title")
  result(Lighting.task == nil, "soft reset stopped the lighting task")
  result(not (ts.patchedSlots and ts.patchedSlots[7]), "soft reset cleared the slot 7 patch")
  result(slotPixels(ts) == base, "shared league atlas slot 7 back to the tileset palette")

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  result(Runtime.getSession() ~= nil, "new game after soft reset reached the field")
  U.wait(120)
  result(Lighting.task == nil, "lighting inactive in the new game")
  local ts2 = NativeTileset._pairs[pair]
  result(ts2 == nil or (not (ts2.patchedSlots and ts2.patchedSlots[7])),
    "league tileset palette normal in the new game")
  U.shot(game, DIR .. "/leag_soft_reset_new_game_field.png")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver error: " .. tostring(err)) end
  finish()
end
