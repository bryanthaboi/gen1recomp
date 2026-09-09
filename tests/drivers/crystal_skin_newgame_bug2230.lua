-- NEW GAME with a touch skin active, from the intro menu to the bedroom (#2230).
-- ../pokecrystal/engine/menus/init_gender.asm:23
-- ../pokecrystal/engine/menus/intro_menu.asm:80
--
--   POKEPORT_VERSION=crystal POKEPORT_IDENTITY=<sandbox> POKEPORT_TOUCH=1 \
--     POKEPORT_BOOT_CINEMA=1 POKEPORT_SKIN=<skin id> POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/crystal_skin_newgame_bug2230.lua love .
local U = require("tests.drivers.util")
local TouchSkin = require("src.core.TouchSkin")
local TouchControls = require("src.core.TouchControls")
local Playfield = require("src.render.Playfield")
local MainMenu = require("src.ui.gen2.MainMenu")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local InitClock = require("src.ui.gen2.InitClock")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local NamePick = require("src.ui.gen2.NamePick")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2230] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end
  local function top() return game.stack:top() end
  local function isA(class) return top() ~= nil and getmetatable(top()) == class end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function waitFor(label, predicate, frames, spam)
    for _ = 1, frames or 900 do
      if predicate() then return true end
      if spam then tap(spam, 2) else U.wait(1) end
    end
    ok(false, "stalled waiting for " .. label .. " (top is " .. tostring(top()) .. ")")
    U.shot(game, SHOT_DIR .. "/2230_stall.png")
    return false
  end

  -- Counts the non-white, non-black pixels inside the skin's screen cutout:
  -- a GB page that actually painted there has plenty, a page clipped away
  -- leaves only the letterbox fill.
  local function paintedInCutout(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local image = love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    local w, h = love.graphics.getDimensions()
    local cx, cy, cw, ch = Playfield.cutout(w, h)
    if not cx then cx, cy, cw, ch = 0, 0, w, h end
    local sx = image:getWidth() / w
    local painted = 0
    for y = cy, cy + ch - 1, 4 do
      for x = cx, cx + cw - 1, 4 do
        local r, g, b = image:getPixel(math.floor(x * sx), math.floor(y * sx))
        local lit = r > 0.05 or g > 0.05 or b > 0.05
        local white = r > 0.95 and g > 0.95 and b > 0.95
        if lit and not white then painted = painted + 1 end
      end
    end
    return painted
  end

  local skins = TouchSkin.list()
  local want = os.getenv("POKEPORT_SKIN")
  if not want or want == "" then want = skins[1] and skins[1].id end
  ok(want ~= nil, "a skin is installed to select")
  if not want then return end
  local controls = game.touchControls or TouchControls
  local skin, err = controls:selectSkin(want)
  ok(skin ~= nil, "selected skin " .. tostring(want) .. " " .. tostring(err or ""))
  ok(TouchSkin.drawable(), "the skin is live, so Playfield cuts the screen out")

  if not waitFor("the intro menu", function() return isA(MainMenu) end, 2400, "start") then return end
  local menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "new" then menu.list.index = i end
  end
  tap("a")

  if not waitFor("the gender menu",
      function() return isA(GenderSelect) and top():menuOpen() end, 900) then return end
  U.wait(5)
  local genderShot = SHOT_DIR .. "/2230_01_gender_in_cutout.png"
  U.shot(game, genderShot)
  local painted = paintedInCutout(genderShot)
  ok(painted and painted > 200,
    ("the gender page painted inside the cutout (%s coloured samples)"):format(tostring(painted)))
  tap("a")

  if not waitFor("the clock", function() return isA(InitClock) end, 900) then return end
  U.shot(game, SHOT_DIR .. "/2230_02_clock.png")
  if not waitFor("Oak", function() return isA(OakSpeech) end, 1200, "a") then return end
  U.wait(30)
  U.shot(game, SHOT_DIR .. "/2230_03_oak.png")
  if not waitFor("the name picker", function() return isA(NamePick) end, 1500, "a") then return end
  U.wait(60)
  top().cursor = 2
  tap("a")
  if not waitFor("the bedroom", function()
      return game.phase == "play" and game.world and game.world.map ~= nil
    end, 2400, "a") then return end
  ok(game.world.map.id == "PLAYERS_HOUSE_2F", "new game landed in the bedroom under the skin")
  U.wait(30)
  U.shot(game, SHOT_DIR .. "/2230_04_bedroom.png")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  say("2230_01_gender_in_cutout.png should show the boy/girl prompt inside the")
  say("skin's screen window. an empty white window there, or a lua error after")
  say("the name picker, is the bug.")
  love.event.quit(fails == 0 and 0 or 1)
end
