-- Driver: shoots the bundled RetroArch-format touch skin (assets/skins/gb_anim)
-- over a live overworld in a portrait window, idle and with A/DOWN held.
--   SHOT_DIR=/tmp/skin POKEPORT_TOUCH=1 POKEPORT_DRIVER=tests/drivers/touch_skin_shot.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TouchControls = require("src.core.TouchControls")
  local TouchSkin = require("src.core.TouchSkin")
  local Pokemon = require("src.pokemon.Pokemon")

  local dir = os.getenv("SHOT_DIR") or "/tmp/skin"
  local skinId = os.getenv("SKIN") or "gb_anim"

  local shotW = tonumber(os.getenv("SHOT_W")) or 432
  local shotH = tonumber(os.getenv("SHOT_H")) or 768
  love.window.setMode(shotW, shotH, { resizable = true, highdpi = true })
  U.wait(2)

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.player.name = "bryan"
  if os.getenv("SKIN") == "none" then skinId = nil end
  game.save.options.touchControls = { enabled = true, skin = skinId }
  game.save.options.tilt = 0
  game.save.options.zoom = 0
  game.save.options.pipelines = {}
  game:applyOptions()

  U.log("skins on disk:")
  for _, entry in ipairs(TouchSkin.list()) do
    U.log("  ", entry.id, entry.source, entry.root)
  end
  U.log("active:", tostring(TouchControls.skinId), "err:", tostring(TouchControls.skinError))
  local page = TouchSkin.page()
  U.log("page:", page and page.name, "controls:", page and #page.controls)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  local R = game.renderer
  local pw, ph = love.graphics.getPixelDimensions()
  U.log("pixel dims:", pw, ph)
  U.log("skin viewport:", TouchSkin.viewport(pw, ph))
  U.log("hasViewport:", TouchSkin.hasViewport(), "fitScale:", R:fitScale())
  U.log("worldViewSize:", R:worldViewSize())
  U.log("worldOverride:", tostring(R.worldOverride), "worldActive:", tostring(R.worldActive))
  U.shot(game, dir .. "/skin_idle.png")

  local ww, wh = love.graphics.getDimensions()
  local function centerFor(button)
    local current = TouchSkin.page()
    for _, ctl in ipairs(current and current.controls or {}) do
      for _, bind in ipairs(ctl.buttons or {}) do
        if bind == button then
          local x, y = TouchSkin.controlGeometry(current, ctl, ww, wh)
          return x, y
        end
      end
      for _, hotkey in ipairs(ctl.hotkeys or {}) do
        if hotkey == button then
          local x, y = TouchSkin.controlGeometry(current, ctl, ww, wh)
          return x, y
        end
      end
    end
  end

  TouchControls:touchpressed("t1", centerFor("a"))
  TouchControls:touchpressed("t2", centerFor("down"))
  U.wait(4)
  U.log("held:", (function()
    local out = {}
    for btn in pairs(TouchControls.held or {}) do out[#out + 1] = btn end
    table.sort(out)
    return table.concat(out, ",")
  end)())
  U.shot(game, dir .. "/skin_pressed.png")
  TouchControls:touchreleased("t1", centerFor("a"))
  TouchControls:touchreleased("t2", centerFor("down"))
  U.wait(4)

  TouchControls:touchpressed("t3", centerFor("overlay_next"))
  TouchControls:touchreleased("t3", centerFor("overlay_next"))
  U.wait(6)
  U.log("page after overlay_next:", TouchSkin.page() and TouchSkin.page().name)
  U.shot(game, dir .. "/skin_page2.png")

  U.log("done")
  love.event.quit()
  while true do coroutine.yield() end
end
