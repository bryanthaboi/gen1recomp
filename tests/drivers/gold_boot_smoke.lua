-- Smoke: the whole Gold boot chain, with no driver shortcut.
--
--   POKEPORT_GAME=gold POKEPORT_BOOT_CINEMA=1 \
--     POKEPORT_DRIVER=tests/drivers/gold_boot_smoke.lua love .
--
-- copyright -> GameFreak -> GS intro -> title -> intro menu -> NEW GAME ->
-- Oak speech -> name pick -> naming screen -> the bedroom.  Every step is
-- asserted by the class of the state on the stack, so a broken hand-off names
-- the screen it stalled on instead of just hanging.
local U = require("tests.drivers.util")

local CopyrightSplash = require("src.ui.gen2.CopyrightSplash")
local GameFreakPresents = require("src.ui.gen2.GameFreakPresents")
local GoldSilverIntro = require("src.ui.gen2.GoldSilverIntro")
local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")
local NamePick = require("src.ui.gen2.NamePick")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local StartMenu = require("src.ui.gen2.StartMenu")
local TitleState = require("src.ui.gen2.TitleState")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-boot"

  local function top()
    return game.stack:top()
  end

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

  -- Wait until `predicate` holds, or fail naming what was on screen instead.
  local function waitFor(label, predicate, frames)
    for _ = 1, frames or 900 do
      if predicate() then return end
      U.wait(1)
    end
    local state = top()
    error(("stalled waiting for %s (top is %s)"):format(
      label, tostring(state)))
  end

  -- Skip through anything that just waits for a button.
  local function press(times, button)
    for _ = 1, times or 1 do tap(button or "a", 3) end
  end

  -- The driver env normally boots straight to the world; this one asked for the
  -- cinema, so Game2 should have started at the copyright splash.
  U.wait(10)
  assert(isA(CopyrightSplash),
    "boot did not start at the copyright splash (top " .. tostring(top()) .. ")")
  U.shot(game, out .. "/01-copyright.png")

  waitFor("GameFreak presents", function() return isA(GameFreakPresents) end)
  U.shot(game, out .. "/02-gamefreak.png")

  waitFor("the GS intro", function() return isA(GoldSilverIntro) end)
  U.wait(240)
  U.shot(game, out .. "/03-intro.png")
  tap("start")  -- any button skips the movie

  waitFor("the title screen", function() return isA(TitleState) end)
  U.wait(60)
  U.shot(game, out .. "/04-title.png")
  press(3, "start")

  waitFor("the intro menu", function() return isA(MainMenu) end)
  U.shot(game, out .. "/05-mainmenu.png")

  -- OPTION and back, so the menu's own hand-off is exercised too.  Found by
  -- value, not by position: the port's EXIT GAME row sits after OPTION, so
  -- "the last item" is the one that quits the game.
  local menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "option" then menu.list.index = i end
  end
  tap("a")
  waitFor("the options screen", function() return isA(OptionsMenu) end)
  U.shot(game, out .. "/06-options.png")
  tap("b")
  waitFor("the intro menu again", function() return isA(MainMenu) end)

  -- NEW GAME.
  menu = top()
  for i, item in ipairs(menu.list.items) do
    if item.value == "new" then menu.list.index = i end
  end
  tap("a")

  -- `farcall InitClock` opens OakSpeech, so the clock screen is what NEW GAME
  -- lands on and Oak is underneath it.
  waitFor("the clock screen", function() return isA(InitClock) end, 300)
  -- ../pokecrystal/engine/rtc/timeset.asm:22, :42: PrintText is on the far side
  -- of RotateFourPalettesLeft and RotateFourPalettesRight.
  waitFor("the clock's fade in",
    function() return isA(InitClock) and top().fade == nil end, 200)
  U.wait(20)
  U.shot(game, out .. "/06b-initclock.png")
  for _ = 1, 60 do
    if isA(OakSpeech) then break end
    tap("a", 2)
  end
  waitFor("the Oak speech", function() return isA(OakSpeech) end, 300)
  -- Page through Oak until the name picker appears.
  for _ = 1, 400 do
    if isA(NamePick) then break end
    tap("a", 2)
  end
  assert(isA(NamePick), "Oak speech never reached the name picker")
  -- NamePlayer walks the player pic across before the menu box goes up, and
  -- that walk is a blocking DelayFrame loop on the cart -- so both the shot
  -- and the first button press have to wait it out.
  waitFor("the name menu to slide in",
    function() return top().slide == nil end, 120)
  U.shot(game, out .. "/07-namepick.png")

  -- NEW NAME opens the real Gen 2 keyboard.
  local pick = top()
  pick.cursor = 1 -- "NEW NAME"
  tap("a")
  waitFor("the naming screen", function() return isA(NamingScreen) end)
  local naming = top()
  -- Type "AB": A is at (0,0), B at (1,0).
  tap("a")
  tap("right")
  tap("a")
  assert(naming.text == "AB",
    "typed name is " .. tostring(naming.text) .. ", expected AB")
  U.shot(game, out .. "/08-naming.png")
  -- END: bottom row, third target.
  naming.row = naming:bottomRow()
  naming.col = 6
  tap("a")

  -- Back into Oak for the last text page and the shrink, then the world.  This
  -- one has to keep pressing A: the remaining pages are text boxes waiting on a
  -- button, so a passive wait would sit there forever.
  local shrinkShot = false
  for _ = 1, 500 do
    if game.phase == "play" and game.world and game.world.map then break end
    local state = top()
    if not shrinkShot and isA(OakSpeech) and state.shrinkText then
      shrinkShot = true
      local shown = table.concat(state.shrinkText, "|")
      assert(not shown:find("DONE", 1, true),
        "shrink page prints the text terminator: " .. shown)
      U.wait(6)
      U.shot(game, out .. "/08b-shrink.png")
    end
    tap("a", 2)
  end
  assert(shrinkShot, "never saw the ShrinkPlayer page of _OakText7")
  assert(game.phase == "play" and game.world and game.world.map,
    "never reached the overworld (top is " .. tostring(top()) .. ")")
  assert(game.save.player.name == "AB",
    "player name is " .. tostring(game.save.player.name))
  assert(game.world.map.id == "PLAYERS_HOUSE_2F",
    "new game started on " .. tostring(game.world.map.id)
      .. ", expected the bedroom")
  U.wait(20)
  U.shot(game, out .. "/09-bedroom.png")

  -- START opens the Gen 2 start menu from the overworld.
  tap("start")
  waitFor("the start menu", function() return isA(StartMenu) end)
  U.shot(game, out .. "/10-startmenu.png")
  tap("b")
  waitFor("the overworld again", function() return top() == nil end)

  print("[driver] PASS gold boot chain in " .. out)
end
