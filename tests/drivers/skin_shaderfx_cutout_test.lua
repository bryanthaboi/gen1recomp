-- A touch skin's screen cutout with a SHADER FX preset on, both generations.
--
--   POKEPORT_TOUCH=1 POKEPORT_SKIN=gb_anim POKEPORT_VERSION=red POKEPORT_IDENTITY=<id> \
--     POKEPORT_SHOT_DIR=<dir> POKEPORT_DRIVER=tests/drivers/skin_shaderfx_cutout_test.lua love .
--
-- The identity needs the game's cache and a shaders/ library (copy both from
-- pokemon-love2d). Never run under POKEPORT_SPEED: the shots are live frames.
local U = require("tests.drivers.util")
local ShaderFX = require("src.render.ShaderFX")
local TouchControls = require("src.core.TouchControls")
local Playfield = require("src.render.Playfield")
local GameVersion = require("src.core.GameVersion")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[skinfx] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  local function litRows(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local w, h = love.graphics.getDimensions()
    local cx, cy, cw, ch = Playfield.cutout(w, h)
    if not cx then return nil end
    local sx = image:getWidth() / w
    local lit = {}
    for _, frac in ipairs({ 0.1, 0.5, 0.9 }) do
      local y = math.floor((cy + ch * frac) * sx)
      local n = 0
      for x = cx, cx + cw - 1, 4 do
        local r, g, b = image:getPixel(math.floor(x * sx), y)
        if r > 0.05 or g > 0.05 or b > 0.05 then n = n + 1 end
      end
      lit[#lit + 1] = n
    end
    return lit
  end

  love.window.setMode(460, 950)
  local want = os.getenv("POKEPORT_SKIN") or "gb_anim"
  local skin, err = (game.touchControls or TouchControls):selectSkin(want)
  ok(skin ~= nil, "selected skin " .. want .. " " .. tostring(err or ""))
  local entry
  for _, e in ipairs(ShaderFX.list()) do
    if e.converted or ShaderFX.convert(e) then entry = e break end
  end
  ok(entry ~= nil, "a shader preset is available to activate")
  if not (skin and entry) then love.event.quit(1) return end

  U.wait(60)
  if GameVersion.generation() == 2 then
    game.world:warpToMapId("NEW_BARK_TOWN", 6, 6, "down")
  else
    U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  end
  U.wait(60)
  local tag = tostring(GameVersion.get())
  U.shot(game, SHOT_DIR .. "/skinfx_" .. tag .. "_01_cutout_plain.png")

  local on, aerr = ShaderFX.activate("main", entry)
  ok(on, "activated " .. tostring(entry.name or entry.id) .. " " .. tostring(aerr or ""))
  U.wait(30)
  local shot = SHOT_DIR .. "/skinfx_" .. tag .. "_02_cutout_shader.png"
  U.shot(game, shot)
  local lit = litRows(shot)
  ok(lit ~= nil, "the shot reads back with a live cutout")
  if lit then
    ok(lit[1] > 20 and lit[2] > 20 and lit[3] > 20,
      ("the shaded picture fills the cutout top to bottom (%d/%d/%d lit samples)")
        :format(lit[1], lit[2], lit[3]))
  end
  ShaderFX.deactivate("main")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  say("02_cutout_shader should be the same town as 01, shaded, inside the")
  say("skin's screen window. a black top half with a strip of town at the")
  say("bottom is the bug.")
  love.event.quit(fails == 0 and 0 or 1)
end
