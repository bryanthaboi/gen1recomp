-- SHADER FX preset examples on Crystal, including a stacked pair.
--
--   POKEPORT_IDENTITY=crystal-dev POKEPORT_GAME=crystal POKEPORT_TOUCH=0 \
--     POKEPORT_SHOT_DIR=/tmp/shaderfx \
--     POKEPORT_DRIVER=tests/drivers/crystal_shaderfx_shots.lua love .
--
-- Never run this under POKEPORT_SPEED: the shots are of a live frame.
local U = require("tests.drivers.util")
local ShaderFX = require("src.render.ShaderFX")

local WANT = {
  { file = "gameboy-color-dot-matrix.slangp", tag = "gbc-dot-matrix" },
  { file = "sameboy-lcd.slangp", tag = "sameboy-lcd" },
  { file = "crt-caligari.slangp", tag = "crt-caligari" },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shaderfx"

  U.wait(30)
  U.log(("bridge canConvert=%s"):format(tostring(ShaderFX.canConvert())))
  if not ShaderFX.canConvert() then
    U.log("FAIL no librashader bridge, nothing can be converted")
    return
  end

  local list = ShaderFX.list()
  U.log(("found %d presets"):format(#list))
  if #list == 0 then U.log("FAIL no presets on disk") return end

  local byName = {}
  for _, e in ipairs(list) do byName[e.name] = e end

  local ready = {}
  for _, want in ipairs(WANT) do
    local entry = byName[want.file]
    if not entry then
      U.log(("SKIP %s not in the preset set"):format(want.file))
    else
      local ok, err = true, nil
      if not entry.converted then ok, err = ShaderFX.convert(entry) end
      if ok then
        ready[#ready + 1] = { entry = entry, tag = want.tag }
        U.log(("PASS converted %s"):format(want.file))
      else
        U.log(("FAIL convert %s: %s"):format(want.file, tostring(err)))
      end
    end
  end
  if #ready == 0 then U.log("FAIL nothing converted") return end

  U.wait(60)
  local world = game.world
  if world and world.setMap then
    world:setMap("CHERRYGROVE_CITY", 21, 6, "down")
    U.wait(20)
  else
    U.log("note: no gen2 world yet, shooting whatever is on screen")
  end

  ShaderFX.deactivate("main")
  ShaderFX.deactivate("secondary")
  U.wait(20)
  U.shot(game, out .. "/00-none.png")
  U.log("shot: no shader")

  for i, r in ipairs(ready) do
    ShaderFX.deactivate("secondary")
    local ok, err = ShaderFX.activate("main", r.entry)
    U.wait(30)
    if ok then
      U.shot(game, ("%s/%02d-%s.png"):format(out, i, r.tag))
      U.log(("shot: %s"):format(r.tag))
    else
      U.log(("FAIL activate %s: %s"):format(r.tag, tostring(err)))
    end
  end

  if #ready >= 2 then
    local a, b = ready[1], ready[2]
    local okA = ShaderFX.activate("main", a.entry)
    local okB = ShaderFX.activate("secondary", b.entry)
    U.wait(30)
    if okA and okB then
      U.shot(game, ("%s/%02d-stacked-%s-over-%s.png"):format(out, #ready + 1, a.tag, b.tag))
      U.log(("shot: stacked %s + %s"):format(a.tag, b.tag))
    else
      U.log("FAIL could not stack two slots")
    end
  end

  U.log("done. the pad is yours; SHADER FX rows are in OPTIONS.")
  while true do coroutine.yield() end
end
