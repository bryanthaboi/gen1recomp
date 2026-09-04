-- #2171: the intro's palette rotations and ShrinkPlayer's player icon.
-- ../pokecrystal/home/fade.asm:22-101
-- ../pokecrystal/engine/menus/intro_menu.asm:627-700, :802-950
--
--   POKEPORT_DRIVER=tests/drivers/gen2_intro_fades_2171.lua \
--     POKEPORT_IDENTITY=crystal-sep04 POKEPORT_VERSION=crystal \
--     POKEPORT_TOUCH=0 POKEPORT_SHOT_DIR=<dir> love .
local U = require("tests.drivers.util")

local GenderSelect = require("src.ui.gen2.GenderSelect")
local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")
local NamePick = require("src.ui.gen2.NamePick")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OakSpeech = require("src.ui.gen2.OakSpeech")

local GameVersion = require("src.core.GameVersion")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/2171-fades"
  local log = io.open(out .. "/driver.log", "w")

  local function say(line)
    print("[driver] " .. line)
    if log then log:write(line .. "\n"); log:flush() end
  end

  local function bail(reason)
    say("FAIL " .. reason)
    if log then log:close() end
    love.event.quit(1)
    error(reason, 0)
  end

  local function top() return game.stack:top() end
  local function isA(class)
    local state = top()
    return state ~= nil and getmetatable(state) == class
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function waitFor(label, predicate, frames)
    for _ = 1, frames or 900 do
      if predicate() then return end
      U.wait(1)
    end
    bail(("stalled waiting for %s (top is %s)"):format(label, tostring(top())))
  end

  -- The fades block input, so the frame counter is deterministic: wait for the
  -- rotation to reach `at`, then shoot.  U.shot costs a couple of logic ticks
  -- of its own, which is why nothing here counts frames across a shot.
  local function shootFade(class, kind, at, name, label)
    waitFor(("%s %s frame %d"):format(label, kind, at), function()
      if not isA(class) then return false end
      local f = top().fade
      return f ~= nil and f.kind == kind and f.frame >= at
    end, 900)
    if not U.shot(game, out .. "/" .. name) then bail("no shot " .. name) end
    say("OK " .. label .. " -> " .. name)
  end

  local version = tostring(GameVersion.get())
  say("version=" .. version .. " engine=" .. tostring(GameVersion.engine()))

  for _ = 1, 900 do
    if isA(MainMenu) then break end
    tap("start", 2)
  end
  if not isA(MainMenu) then
    for _ = 1, 400 do
      if isA(MainMenu) then break end
      tap("a", 2)
    end
  end
  waitFor("the intro menu", function() return isA(MainMenu) end)
  local menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "new" then menu.list.index = i end
  end
  tap("a")

  -- --------------------------------------------------- the NEW GAME seam
  U.wait(4)
  if isA(GenderSelect) then
    -- Crystal: InitGender answers, and InitClock's RotateFourPalettesLeft runs
    -- with the gender screen still on the LCD.
    waitFor("the gender prompt to finish typing",
      function() return top().typer == nil or top().typer:done() end, 300)
    tap("a")
    shootFade(GenderSelect, "outBlack", 20,
      "2171_04_gender_to_clock_mid.png", "gender -> clock, half faded out")
    waitFor("the clock screen", function() return isA(InitClock) end, 300)
    shootFade(InitClock, "inBlack", 22,
      "2171_04_clock_fadein_mid.png", "the clock coming back from black")
  else
    -- Gold and Silver: NewGame_ClearTilemapEtc blanked the screen first, so
    -- RotateFourPalettesLeft runs over a cleared tilemap and has nothing on it
    -- to photograph; the rotation coming back is the judgeable half.
    waitFor("the clock screen", function() return isA(InitClock) end, 300)
    waitFor("RotateFourPalettesLeft over the cleared tilemap", function()
      return isA(InitClock) and top().blank and top().fade
        and top().fade.kind == "outBlack"
    end, 300)
    shootFade(InitClock, "inBlack", 22,
      "2171_05_newgame_to_clock_mid.png", "NEW GAME -> clock, back from black")
  end

  waitFor("the clock screen to settle",
    function() return isA(InitClock) and top().fade == nil end, 300)

  -- --------------------------------------------------- the clock -> Oak seam
  for _ = 1, 120 do
    if not isA(InitClock) or top().fade then break end
    tap("a", 3)
  end
  if not isA(InitClock) then bail("the clock left before its fade") end
  shootFade(InitClock, "outBlack", 14,
    "2171_03_clock_to_oak_mid.png", "clock -> Oak, half faded out")

  waitFor("the Oak speech", function() return isA(OakSpeech) end, 400)
  say("OK the speech is up")

  -- --------------------------------------------------- the shrink
  local shotShrink, shotWhite = false, false
  for _ = 1, 900 do
    if game.phase == "play" then break end
    if isA(NamePick) and top().slide == nil then
      top().cursor = 1
      tap("a")
      waitFor("the naming screen", function() return isA(NamingScreen) end, 240)
      local naming = top()
      naming.row = naming:bottomRow()
      naming.col = 6
      tap("a")
    elseif isA(OakSpeech) then
      local speech = top()
      if not shotShrink and speech.shrink
          and speech.shrink.frame >= OakSpeech.SHRINK_ICON + 12 then
        if not U.shot(game, out .. "/2171_07_shrink_player_icon.png") then
          bail("no shrink shot")
        end
        say("OK Intro_PlacePlayerSprite -> 2171_07_shrink_player_icon.png")
        shotShrink = true
      elseif shotShrink and not shotWhite and speech.fade
          and speech.fade.kind == "outWhite" and speech.fade.frame >= 10 then
        if not U.shot(game, out .. "/2171_08_post_shrink_fade.png") then
          bail("no post-shrink shot")
        end
        say("OK RotateThreePalettesRight -> 2171_08_post_shrink_fade.png")
        shotWhite = true
      elseif speech.shrink == nil and speech.fade == nil then
        tap("a", 2)
      else
        U.wait(1)
      end
    else
      tap("a", 2)
    end
  end

  if not shotShrink then bail("the shrink never put the player icon up") end
  if not shotWhite then bail("the shrink never faded out to white") end
  waitFor("the overworld", function()
    return game.phase == "play" and game.world and game.world.map
  end, 600)
  say("OK reached " .. tostring(game.world.map.id))

  say("PASS gen2 intro fades (" .. version .. ") in " .. out)
  if log then log:close() end
  love.event.quit(0)
end
