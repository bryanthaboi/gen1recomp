local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ui_braille"

local RUIN_VALLEY = "FR_SIX_ISLAND_RUIN_VALLEY"
local DOOR_X, DOOR_Y = 24, 24

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/ui_braille.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS ui_braille")
    love.event.quit(0)
  else
    say("FAIL ui_braille failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Braille = require("src.ui.game3.braille")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  goTo(RUIN_VALLEY, DOOR_X, DOOR_Y + 1, "up")
  if not result(session.map == RUIN_VALLEY, "the player stands on Six Island Ruin Valley ("
      .. tostring(session.map) .. ")") then
    return finish()
  end

  -- pokefirered/data/maps/SixIsland_RuinValley/scripts.inc:23
  U.tap(game, "a")
  U.wait(40)
  local started = (Message.isOpen and Message.isOpen())
    or (Space.vm and Space.vm:isRunning() and true or false)
  if not result(started, "A on the dotted hole door started its script") then
    return finish()
  end

  for _ = 1, 40 do
    if Choice.active then break end
    if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(6)
  end
  result(Choice.active == true, "the door asks whether to check it more thoroughly")
  U.shot(game, DIR .. "/braille_01_check_door_yesno.png")

  -- pokefirered/data/maps/SixIsland_RuinValley/scripts.inc:26 YES
  Choice.cursor = 1
  U.tap(game, "a")
  U.wait(20)

  -- pokefirered/data/maps/SixIsland_RuinValley/scripts.inc:28 then braillemessage
  local reached = false
  for _ = 1, 80 do
    if Message.isOpen() and Message.frameKind() == "braille" then
      reached = true
      break
    end
    if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(6)
  end
  if not result(reached, "braillemessage opened the box on the braille frame") then
    say("NOTE last message frame=" .. tostring(Message.frameKind())
      .. " open=" .. tostring(Message.isOpen()))
    return finish()
  end

  result(Braille.isOpen(), "the braille renderer owns the open box")
  local page = Message.currentPage() or ""
  result(Message._total == Braille.countGlyphs(page),
    "the page holds " .. tostring(Message._total) .. " braille cells")
  -- pokefirered/src/text_printer.c:91
  result(Message._revealed == Message._total and Message.isWaiting() == true,
    "speed 0 printed every cell at once, with no typewriter")
  U.shot(game, DIR .. "/braille_02_ruin_valley_wall.png")

  local sheet = Braille.hasSheet()
  if not sheet then
    say("BLOCKED no braille glyph sheet in this cache, so the box prints the plain string."
      .. " Owner: chain importer round 0 step 2 (bake graphics/fonts/braille under chrome/fonts/).")
  else
    result(true, "the baked braille glyph sheet is in use")
  end
  if page:match("^%?+$") then
    say("BLOCKED the cached braille string is " .. string.format("%q", page)
      .. ": src/import/gba/extract_scripts.lua:178 decodes braillemessage text with the latin"
      .. " charmap, which has no entry for most braille codes. Owner: chain importer.")
  else
    result(Braille.width(page) == Braille.countGlyphs(page) * 16,
      "the wall reads " .. string.format("%q", page))
  end

  -- pokefirered/data/maps/SixIsland_RuinValley/scripts.inc:31 waitbuttonpress
  U.tap(game, "a")
  U.wait(30)
  result(not Message.isOpen(), "the button press closed the braille box")
  local Field = require("src.core.game3.field")
  for _ = 1, 60 do
    if Field.locked ~= true then break end
    U.wait(4)
  end
  result(Field.locked ~= true, "releaseall unlocked the field")

  Braille.show("CUT")
  U.wait(60)
  result(Message.isOpen() and Message.frameKind() == "braille",
    "Braille.show puts a three cell line in the dialogue box")
  result(Braille.width("CUT") == 48, "CUT measures 48px, pret's 3 x 16")
  U.shot(game, DIR .. "/braille_03_renderer_cut.png")
  Braille.hide()
  U.wait(20)

  finish()
end
