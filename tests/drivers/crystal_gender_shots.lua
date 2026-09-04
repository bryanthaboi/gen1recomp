-- Crystal's InitGender screen, end to end, and the six things that follow from
-- the answer.  POKEPORT_GENDER picks the arm: "girl", "boy" or "none" (Gold,
-- which must never see the screen at all).
--
--   POKEPORT_IDENTITY=<sandbox> POKEPORT_GAME=crystal POKEPORT_BOOT_CINEMA=1 \
--     POKEPORT_GENDER=girl POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/crystal_gender_shots.lua love .
local U = require("tests.drivers.util")

local GenderSelect = require("src.ui.gen2.GenderSelect")
local InitClock = require("src.ui.gen2.InitClock")
local MainMenu = require("src.ui.gen2.MainMenu")
local NamePick = require("src.ui.gen2.NamePick")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OakSpeech = require("src.ui.gen2.OakSpeech")
local TrainerCard = require("src.ui.gen2.TrainerCard")

local FieldMoves = require("src.world.gen2.FieldMoves")
local GameVersion = require("src.core.GameVersion")
local Screens = require("src.ui.Screens")

return function(game)
  local want = os.getenv("POKEPORT_GENDER") or "girl"
  local out = os.getenv("POKEPORT_SHOT_DIR") or ("/tmp/crystal-gender-" .. want)
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

  local function eq(got, wanted, label)
    if got ~= wanted then
      bail(("%s: got %s, want %s"):format(label, tostring(got),
        tostring(wanted)))
    end
    say("OK " .. label .. " = " .. tostring(got))
  end

  say("version=" .. tostring(GameVersion.get())
    .. " engine=" .. tostring(GameVersion.engine())
    .. " gender=" .. want)

  -- Straight to the intro menu; the boot chain itself is crystal_boot_smoke's.
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

  if want == "none" then
    -- Gold and Silver: PlayerProfileSetup has no InitGender to farcall.
    waitFor("the clock screen", function() return isA(InitClock) end, 400)
    if isA(GenderSelect) then bail("Gold put up the gender screen") end
    say("OK no gender screen; NEW GAME went straight to the clock")
    for _ = 1, 200 do
      if isA(OakSpeech) then break end
      tap("a", 2)
    end
    waitFor("the Oak speech", function() return isA(OakSpeech) end, 400)
    local speech = top()
    for _, step in ipairs(speech.steps or {}) do
      if step.kind == "gender" then bail("Gold's speech grew a gender beat") end
    end
    eq(speech.steps and speech.steps[1] and speech.steps[1].id, "init_clock",
      "the first beat")
    -- ../pokecrystal/engine/menus/intro_menu.asm:629-635
    waitFor("the clock hand-off rotations",
      function() return top().fade == nil end, 200)
    U.wait(40)
    U.shot(game, out .. "/01-oak.png")
    eq(game.save.player.gender, "male", "save.player.gender")
    say("PASS gold has no gender prompt")
    if log then log:close() end
    love.event.quit(0)
    return
  end

  waitFor("the gender screen", function() return isA(GenderSelect) end, 600)
  local gender = top()
  U.wait(20)
  say("OK gender screen, cursor = " .. tostring(gender.cursor))
  U.shot(game, out .. "/01-genderselect.png")
  if want == "girl" then
    tap("down")
    U.wait(10)
    U.shot(game, out .. "/02-genderselect-girl.png")
  else
    U.shot(game, out .. "/02-genderselect-boy.png")
  end
  tap("a")

  waitFor("the clock screen", function() return isA(InitClock) end, 400)
  eq(game.save.player.gender, want == "girl" and "female" or "male",
    "wPlayerGender after the answer")
  eq(game.save.player.name, want == "girl" and "KRIS" or "CHRIS",
    "NamePlayer's InitName default")
  -- ../pokecrystal/engine/rtc/timeset.asm:22-32, :42-43: PrintText only runs
  -- once RotateFourPalettesRight is done, so wait the rotation out.
  waitFor("the clock's fade in",
    function() return isA(InitClock) and top().fade == nil end, 200)
  U.wait(20)
  U.shot(game, out .. "/02b-initclock.png")

  local shotDemo = false
  for _ = 1, 200 do
    if isA(OakSpeech) then break end
    tap("a", 2)
  end
  waitFor("the Oak speech", function() return isA(OakSpeech) end, 400)
  local speech = top()
  eq(speech.steps[1].id, "gender_select", "the beat the speech opened on")

  local shotPic = false
  for _ = 1, 500 do
    if isA(NamePick) then break end
    -- ../pokecrystal/engine/menus/intro_menu.asm:875
    if not shotDemo and isA(OakSpeech) and top().pic == top().marillPic then
      U.wait(6)
      U.shot(game, out .. "/02c-demowipe.png")
      shotDemo = true
    end
    if not shotPic and isA(OakSpeech) then
      local at = top().steps and top().steps[top().step]
      if at and at.id == "ask_player_name" then
        U.wait(45)
        local wanted = (want == "girl") and top().playerPicFemale
          or top().playerPic
        if top().pic ~= wanted then
          bail("DrawIntroPlayerPic put up the wrong pic")
        end
        U.shot(game, out .. "/03-intropic.png")
        shotPic = true
      end
    end
    tap("a", 2)
  end
  waitFor("the name picker", function() return isA(NamePick) end, 200)
  waitFor("the name menu to slide in",
    function() return top().slide == nil end, 240)
  local picker = top()
  eq(picker.items[2], want == "girl" and "KRIS" or "CHRIS", "preset row 1")
  eq(picker.items[3], want == "girl" and "AMANDA" or "MAT", "preset row 2")
  U.shot(game, out .. "/04-namepick.png")

  picker.cursor = 1
  tap("a")
  waitFor("the naming screen", function() return isA(NamingScreen) end)
  local naming = top()
  eq(naming.gender, want == "girl" and "female" or "male",
    "the keyboard's header icon gender")
  U.wait(20)
  U.shot(game, out .. "/05-naming.png")
  naming.row = naming:bottomRow()
  naming.col = 6
  tap("a")

  for _ = 1, 700 do
    if game.phase == "play" and game.world and game.world.map then break end
    tap("a", 2)
  end
  if not (game.phase == "play" and game.world and game.world.map) then
    bail("never reached the overworld (top is " .. tostring(top()) .. ")")
  end
  eq(game.world.map.id, "PLAYERS_HOUSE_2F", "the bedroom")
  eq(game.save.player.name, want == "girl" and "KRIS" or "CHRIS",
    "the name that reached the save")
  local sprite = game.world.player and game.world.player.spriteDef
  eq(sprite and sprite.id, FieldMoves.playerSprite(game.save.player.gender),
    "the overworld sheet")
  U.wait(20)
  U.shot(game, out .. "/06-bedroom.png")

  -- Walk a step so the sheet is seen mid-stride rather than only standing.
  U.hold(game, "down", 20)
  U.wait(20)
  U.shot(game, out .. "/07-bedroom-walk.png")

  -- The card, opened directly: the START-menu route is Gen2StartMenu's and is
  -- already covered by crystal_boot_smoke.
  game.save.player.badges = { ZEPHYR = true, HIVE = true }
  local card = Screens.push(game, "Gen2TrainerCard",
    { save = game.save, onClose = function() end })
  if getmetatable(card) ~= TrainerCard then bail("the card did not open") end
  eq(card.female, want == "girl", "GetCardPic picked KrisCardPic")
  U.wait(30)
  U.shot(game, out .. "/08-trainercard.png")
  tap("right")
  U.wait(20)
  U.shot(game, out .. "/09-trainercard-badges.png")
  game.stack:pop()

  local gear = Screens.push(game, "Gen2Pokegear", { save = game.save })
  U.wait(30)
  local pals = gear.pals and gear:pals()
  local femalePals = gear.gfx and gear.gfx.palettesFemale
  if want == "girl" and femalePals and pals ~= femalePals then
    bail("the gear kept MalePokegearPals for Kris")
  end
  if want == "boy" and femalePals and pals == femalePals then
    bail("the gear took FemalePokegearPals for Chris")
  end
  say("OK pokegear palettes = " .. (pals == femalePals and "female" or "male"))
  U.shot(game, out .. "/10-pokegear.png")
  game.stack:pop()

  say("PASS crystal gender run (" .. want .. ") in " .. out)
  if log then log:close() end
  love.event.quit(0)
end
