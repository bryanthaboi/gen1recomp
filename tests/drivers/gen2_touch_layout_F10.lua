local U = require("tests.drivers.util")

local SaveData = require("src.core.SaveData")
local Save = require("src.core.gen2.Save")
local TouchControls = require("src.core.TouchControls")
local Editor = require("src.ui.TouchControlsEditor")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/F10"
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("PASS " .. label)
    else
      failures = failures + 1
      print("FAIL " .. label .. " " .. tostring(detail))
    end
  end

  U.wait(45)
  if not (game.world and game.world.map) then
    print("FAIL gen2_touch_layout_F10 (gold world did not boot)")
    love.event.quit(1)
    return
  end

  local gen1 = { x = 0.12, y = 0.8 }
  local opts = SaveData.loadOptions()
  opts.touchControls = {
    enabled = true,
    layouts = {
      portrait = { positions = { dpad = gen1 }, scale = 1 },
      landscape = { positions = { dpad = gen1 }, scale = 1 },
    },
  }
  if type(opts.gold) == "table" then opts.gold.touchControls = nil end
  SaveData.saveOptions(opts)

  Editor.load({ version = game.version or "gold" })
  local ox, oy, sw, sh = require("src.core.SafeArea").windowRect()
  local d = TouchControls:layout().dpad
  local want = { x = ox + sw * 0.5, y = oy + sh * 0.45 }
  TouchControls:setControlCenter("dpad", want.x, want.y)
  d = TouchControls:layout().dpad
  want.x, want.y = d.cx, d.cy
  Editor.keypressed("escape")

  game.options = Save.loadOptions()
  game:applyOptions()
  U.wait(4)
  local after = TouchControls:layout().dpad
  ok("gold_layout_edit_shows_after_reload",
    math.abs(after.cx - want.x) < 1 and math.abs(after.cy - want.y) < 1,
    ("got %.1f,%.1f want %.1f,%.1f"):format(after.cx, after.cy, want.x, want.y))
  local flat = SaveData.loadOptions().touchControls
  local fp = TouchControls.normalizeConfig(flat).layouts[TouchControls.orientation].positions
  ok("gen1_layout_untouched", fp and fp.dpad
    and math.abs(fp.dpad.x - gen1.x) < 1e-6 and math.abs(fp.dpad.y - gen1.y) < 1e-6)
  if TouchControls:visible() then
    U.still(game, out .. "/F10_01_gold_dpad_centre_after_reload.png")
  end

  local gear = SaveData.loadOptions()
  gear.touchControls.enabled = false
  SaveData.saveOptions(gear)
  game.options = Save.loadOptions()
  game:applyOptions()
  ok("touch_pad_off_reaches_gold_with_gold_layout", TouchControls.enabled == false)
  gear.touchControls.enabled = true
  SaveData.saveOptions(gear)
  game.options = Save.loadOptions()
  game:applyOptions()
  ok("touch_pad_on_again", TouchControls.enabled == true)

  print(failures == 0 and "PASS gen2_touch_layout_F10"
    or ("FAIL gen2_touch_layout_F10 (%d)"):format(failures))
  love.event.quit(failures == 0 and 0 or 1)
end
