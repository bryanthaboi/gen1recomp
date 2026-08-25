-- Smoke: the whole Crystal boot chain, with no driver shortcut.
--
--   POKEPORT_GAME=crystal POKEPORT_BOOT_CINEMA=1 \
--     POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/crystal_boot_smoke.lua love .
--
-- copyright -> GameFreak -> Crystal intro -> title -> intro menu -> NEW GAME
-- -> clock -> Oak speech -> name pick -> naming screen -> the bedroom ->
-- start menu -> outdoors -> a wild battle.  Every step is asserted by the
-- class of the state on the stack, so a broken hand-off names the screen it
-- stalled on instead of just hanging.
local U = require("tests.drivers.util")

local CopyrightSplash = require("src.ui.gen2.CopyrightSplash")
local CrystalIntro = require("src.ui.gen2.CrystalIntro")
local GameFreakPresents = require("src.ui.gen2.GameFreakPresents")
local GenderSelect = require("src.ui.gen2.GenderSelect")
local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")
local NamePick = require("src.ui.gen2.NamePick")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local StartMenu = require("src.ui.gen2.StartMenu")
local TitleState = require("src.ui.gen2.TitleState")

local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-boot"
  local log = io.open(os.getenv("POKEPORT_BOOT_LOG")
    or (out .. "/boot.log"), "w")

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

  local function waitFor(label, predicate, frames)
    for _ = 1, frames or 900 do
      if predicate() then return end
      U.wait(1)
    end
    bail(("stalled waiting for %s (top is %s)"):format(label, tostring(top())))
  end

  local function pick(menu, value)
    for i, item in ipairs(menu.list.items) do
      if item.value == value then menu.list.index = i end
    end
  end

  if GameVersion.get() ~= "crystal" then
    bail("booted " .. tostring(GameVersion.get()) .. ", not crystal")
  end
  if GameVersion.engine() ~= "crystal" then
    bail("engine lineage is " .. tostring(GameVersion.engine()))
  end
  say("version=" .. GameVersion.get() .. " engine=" .. GameVersion.engine())

  U.wait(10)
  if not isA(CopyrightSplash) then
    bail("boot did not start at the copyright splash (top "
      .. tostring(top()) .. ")")
  end
  say("OK copyright")
  U.shot(game, out .. "/01-copyright.png")

  waitFor("GameFreak presents", function() return isA(GameFreakPresents) end)
  U.wait(90)
  say("OK gamefreak")
  U.shot(game, out .. "/02-gamefreak.png")

  -- ../pokecrystal/engine/movie/intro.asm:1
  waitFor("the Crystal intro", function() return isA(CrystalIntro) end)
  U.wait(240)
  say("OK crystal intro")
  U.shot(game, out .. "/03-intro.png")
  U.wait(240)
  U.shot(game, out .. "/03b-intro.png")
  tap("start")

  waitFor("the title screen", function() return isA(TitleState) end)
  U.wait(90)
  say("OK title")
  U.shot(game, out .. "/04-title.png")
  for _ = 1, 3 do tap("start", 3) end

  waitFor("the intro menu", function() return isA(MainMenu) end)
  say("OK main menu")
  U.shot(game, out .. "/05-mainmenu.png")

  local menu = top()
  pick(menu, "option")
  tap("a")
  waitFor("the options screen", function() return isA(OptionsMenu) end)
  U.shot(game, out .. "/06-options.png")
  tap("b")
  waitFor("the intro menu again", function() return isA(MainMenu) end)

  menu = top()
  pick(menu, "new")
  U.shot(game, out .. "/07-newgame.png")
  tap("a")

  -- ../pokecrystal/engine/menus/init_gender.asm:23 InitGender, which
  -- PlayerProfileSetup runs first (engine/menus/intro_menu.asm:80-84).
  waitFor("the gender screen", function() return isA(GenderSelect) end, 300)
  say("OK gender select")
  U.shot(game, out .. "/07b-gender.png")
  tap("a")

  -- ../pokecrystal/engine/menus/intro_menu.asm:628
  waitFor("the clock screen", function() return isA(InitClock) end, 300)
  say("OK init clock")
  U.shot(game, out .. "/08-initclock.png")
  for _ = 1, 60 do
    if isA(OakSpeech) then break end
    tap("a", 2)
  end
  waitFor("the Oak speech", function() return isA(OakSpeech) end, 300)
  local oak = top()
  say("OK oak speech, demo mon = " .. tostring(oak.demoSpecies))
  if oak.demoSpecies ~= "WOOPER" then
    bail("Oak's demo mon is " .. tostring(oak.demoSpecies)
      .. ", Crystal's is WOOPER")
  end
  U.wait(60)
  U.shot(game, out .. "/09-oak.png")

  local shotDemo = false
  for _ = 1, 400 do
    if isA(NamePick) then break end
    if not shotDemo and isA(OakSpeech) and top().pic == top().marillPic then
      U.wait(45)
      U.shot(game, out .. "/10-wooper.png")
      shotDemo = true
    end
    tap("a", 2)
  end
  if not isA(NamePick) then
    bail("Oak speech never reached the name picker (top "
      .. tostring(top()) .. ")")
  end
  say("OK name pick" .. (shotDemo and " (demo pic captured)" or ""))
  -- ../pokecrystal/engine/menus/intro_menu.asm:738 NamePlayer
  waitFor("the name menu to slide in",
    function() return top().slide == nil end, 240)
  U.shot(game, out .. "/11-namepick.png")

  local picker = top()
  picker.cursor = 1
  tap("a")
  waitFor("the naming screen", function() return isA(NamingScreen) end)
  local naming = top()
  tap("a")
  tap("right")
  tap("a")
  if naming.text ~= "AB" then
    bail("typed name is " .. tostring(naming.text) .. ", expected AB")
  end
  say("OK naming screen")
  U.shot(game, out .. "/12-naming.png")
  naming.row = naming:bottomRow()
  naming.col = 6
  tap("a")

  for _ = 1, 600 do
    if game.phase == "play" and game.world and game.world.map then break end
    tap("a", 2)
  end
  if not (game.phase == "play" and game.world and game.world.map) then
    bail("never reached the overworld (top is " .. tostring(top()) .. ")")
  end
  if game.save.player.name ~= "AB" then
    bail("player name is " .. tostring(game.save.player.name))
  end
  if game.world.map.id ~= "PLAYERS_HOUSE_2F" then
    bail("new game started on " .. tostring(game.world.map.id)
      .. ", expected the bedroom")
  end
  say("OK overworld, map = " .. game.world.map.id
    .. ", name = " .. tostring(game.save.player.name))
  U.wait(20)
  U.shot(game, out .. "/13-bedroom.png")

  tap("start")
  waitFor("the start menu", function() return isA(StartMenu) end)
  say("OK start menu")
  U.shot(game, out .. "/14-startmenu.png")
  tap("b")
  waitFor("the overworld again", function() return top() == nil end)

  if not game.world:setMap("NEW_BARK_TOWN", 13, 6, "down") then
    bail("could not load NEW_BARK_TOWN")
  end
  U.wait(30)
  if game.world.map.id ~= "NEW_BARK_TOWN" then
    bail("setMap landed on " .. tostring(game.world.map.id))
  end
  local tileset = game.world.map.tileset or {}
  say("OK outdoors, tileset = " .. tostring(tileset.id)
    .. ", tilePalettes = " .. tostring(#(tileset.tilePalettes or {})))
  U.shot(game, out .. "/15-newbark.png")

  local player = Mon.new(game.data, "CYNDAQUIL", 12)
  if not (player and #player.moves > 0) then
    bail("could not build a CYNDAQUIL from the Crystal pokemon.lua")
  end
  local wild = Mon.new(game.data, "WOOPER", 5)
  if not wild then bail("could not build a wild WOOPER") end
  game.save.party = { player }
  if not game.world:startBattle({ wild = wild }) then
    bail("startBattle failed")
  end
  U.wait(240)
  say("OK battle, " .. player.species .. " L" .. player.level
    .. " vs " .. wild.species .. " L" .. wild.level)
  U.shot(game, out .. "/16-battle.png")

  say("PASS crystal boot chain in " .. out)
  if log then log:close() end
  love.event.quit(0)
end
