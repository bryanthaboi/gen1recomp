local U = require("tests.drivers.util")
local Tilt = require("src.render.Tilt")
local TouchControls = require("src.core.TouchControls")
local TouchSkin = require("src.core.TouchSkin")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2120] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  local tiltRow
  for _, row in ipairs(OptionsMenu.ROWS) do
    if row.key == "tilt" then tiltRow = row break end
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the gen 2 world did not boot")
    love.event.quit(1)
    return
  end

  local function keepSkin()
    game.options.touchControls = game.options.touchControls or {}
    game.options.touchControls.enabled = true
    game.options.touchControls.skin = "gb_anim"
    return TouchControls:selectSkin("gb_anim")
  end

  local skin, err = keepSkin()
  ok(skin ~= nil, "gb_anim skin " .. tostring(err or ""))
  ok(TouchSkin.active ~= nil, "gb_anim is live")

  world:warpToMapId("NEW_BARK_TOWN", 6, 6, "down")
  U.wait(45)
  game.options.tilt = 0
  Tilt.setLevel(0)
  U.wait(30)
  U.shot(game, SHOT_DIR .. "/2120_00_skin_flat.png")

  game.options.tilt = 3
  game.options.performance = "balanced"
  keepSkin()
  game:applyOptions()
  keepSkin()
  for _ = 1, 20 do Tilt.update(0.05) end
  ok(not Tilt.active(), "balanced_clamp")
  U.shot(game, SHOT_DIR .. "/2120_01_options_close_balanced.png")

  if tiltRow then tiltRow.cycle(game.options, 1) end
  keepSkin()
  game:applyOptions()
  keepSkin()
  ok(game.options.performance == "high", "cycle_promotes_high")
  ok(game.options.tilt == 1, "first_enable_is_15")
  ok(Tilt.active(), "options_cycle_tilt")

  game.options.performance = "high"
  Tilt.setLevel(1)
  U.wait(60)
  U.shot(game, SHOT_DIR .. "/2120_02_high_tilt15.png")
  ok(Tilt.active() and Tilt.level == 1, "live_tilt_at_15")

  local r15, g15, b15
  local shot15 = io.open(SHOT_DIR .. "/2120_02_high_tilt15.png", "rb")
  if shot15 then
    local bytes = shot15:read("*a")
    shot15:close()
    local okData, data = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    end)
    if okData and data then
      local pr, pg, pb = data:getPixel(512, 180)
      r15 = math.floor(pr * 255 + 0.5)
      g15 = math.floor(pg * 255 + 0.5)
      b15 = math.floor(pb * 255 + 0.5)
    end
  end
  local brown = r15 and math.abs(r15 - 18) < 8 and math.abs(g15 - 13) < 8
    and math.abs(b15 - 5) < 8
  ok(r15 ~= nil and not brown,
    string.format("high_tilt15_shows_new_bark (%s,%s,%s)",
      tostring(r15), tostring(g15), tostring(b15)))

  local a = io.open(SHOT_DIR .. "/2120_01_options_close_balanced.png", "rb")
  local b = io.open(SHOT_DIR .. "/2120_02_high_tilt15.png", "rb")
  local same = false
  if a and b then
    same = a:read("*a") == b:read("*a")
    a:close()
    b:close()
  end
  ok(not same, "high_tilt15 differs from the clamped flat shot")

  Tilt.setLevel(2)
  U.wait(60)
  U.shot(game, SHOT_DIR .. "/2120_03_high_tilt35.png")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
  while true do coroutine.yield() end
end
