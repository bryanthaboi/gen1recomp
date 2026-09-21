local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchscript_seams"

local RUBY_PATH = "FR_MT_EMBER_RUBY_PATH_B5F"
local BRAILLE_XY = { 7, 3 }
local ROUTE4_PC = "FR_ROUTE_4_POKEMON_CENTER_1F"
local SALESMAN_XY = { 1, 4 }
local SPECIES_MAGIKARP = 129

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchscript_seams")
    love.event.quit(0)
  else
    print("FAIL stitchscript_seams failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Braille = require("src.ui.game3.braille")
  local Naming = require("src.ui.game3.naming")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function scriptRunning()
    return (Space.vm and Space.vm.isRunning and Space.vm:isRunning()) or false
  end
  local function message()
    return package.loaded["src.ui.game3.message"]
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  local function talkUntil(pred)
    for _ = 1, 24 do
      if pred() then return true end
      U.tap(game, "a")
      U.wait(12)
    end
    return pred()
  end

  local function pressUntil(pred)
    for _ = 1, 6 do
      if pred() then return true end
      U.tap(game, "a")
      for _ = 1, 120 do
        if pred() then return true end
        U.wait(1)
      end
    end
    return pred()
  end

  goTo(RUBY_PATH, BRAILLE_XY[1], BRAILLE_XY[2], "up")
  result(pressUntil(function() return scriptRunning() or Braille.isOpen() end),
    "the Ruby Path braille wall answers")

  local cursorSeen, pagesWithCursor = nil, 0
  for _ = 1, 400 do
    if Braille.isOpen() and Braille.cursor() then break end
    U.wait(4)
  end
  cursorSeen = Braille.cursor()
  local firstPage = (message() and message().currentPage and message().currentPage()) or ""
  result(cursorSeen ~= nil, "BrailleCursorToggle put a cursor on the first braille page")
  result(Braille.width(firstPage) / Braille.GLYPH_WIDTH == 10,
    "the first page is the ten glyph EVERYTHING, got " ..
    tostring(Braille.width(firstPage) / Braille.GLYPH_WIDTH) .. " glyphs")
  if cursorSeen then
    -- pokefirered/src/field_specials.c:2478
    result(cursorSeen.y == 130,
      "y is VAR_0x8005 from the map script, got " .. tostring(cursorSeen.y))
    local expectX = Braille.width(firstPage) + 27
    result(cursorSeen.x == expectX,
      "x is the braille string width plus 27, got " .. tostring(cursorSeen.x) ..
      " want " .. tostring(expectX))
  end
  U.shot(game, DIR .. "/stitchscript_seams_01_braille_cursor.png")

  local pagesSeen, lastPage = 0, nil
  for _ = 1, 900 do
    if not (scriptRunning() or Braille.isOpen()) then break end
    local M = message()
    local page = (M and M.currentPage and M.currentPage()) or ""
    if page ~= "" and page ~= lastPage then
      lastPage = page
      pagesSeen = pagesSeen + 1
      for _ = 1, 40 do
        if Braille.cursor() or not (scriptRunning() or Braille.isOpen()) then break end
        U.wait(2)
      end
      if not Braille.cursor() then break end
      pagesWithCursor = pagesWithCursor + 1
      U.tap(game, "a")
      U.wait(16)
    else
      U.wait(2)
    end
  end
  result(pagesSeen == 8, "the wall printed all eight pages, got " .. tostring(pagesSeen))
  result(pagesWithCursor == 7,
    "all seven braillemessage_wait pages carried the cursor, got " .. tostring(pagesWithCursor))
  result(Braille.cursor() == nil,
    "the last page, which pret prints without the wait macro, has no cursor")
  U.shot(game, DIR .. "/stitchscript_seams_02_braille_last_page.png")

  for _ = 1, 60 do
    if not (scriptRunning() or Braille.isOpen()) then break end
    U.tap(game, "a")
    U.wait(6)
  end

  for _ = 1, 6 do
    if #session.party >= 6 then break end
    Party.giveMonToPlayer(session, 19, 5)
  end
  session.money = 5000
  Storage.ensure(session)
  result(#session.party == 6, "the party is full, " .. tostring(#session.party) .. " mons")

  goTo(ROUTE4_PC, SALESMAN_XY[1], SALESMAN_XY[2], "up")
  result(talkUntil(function()
    local M = message()
    return scriptRunning() or (M and M.isOpen and M.isOpen())
  end), "the Magikarp salesman answers")

  local Choice = require("src.ui.game3.choice")
  local answers, named = 0, false
  for _ = 1, 1200 do
    if Naming.isOpen() then
      if not named then
        named = true
        U.shot(game, DIR .. "/stitchscript_seams_03_box_nickname.png")
        for _ = 1, 3 do
          U.tap(game, "a")
          U.wait(12)
        end
        U.tap(game, "start")
        U.wait(20)
        U.tap(game, "a")
        U.wait(40)
      else
        U.wait(2)
      end
    elseif Choice.active then
      answers = answers + 1
      U.tap(game, "a")
      U.wait(12)
    else
      local M = message()
      local page = (M and M.currentPage and M.currentPage()) or ""
      if named and page:find("transferred") then break end
      if M and M.isOpen and M.isOpen() then U.tap(game, "a") end
      U.wait(6)
    end
  end
  result(answers >= 2, "both yes / no boxes were answered yes, " .. tostring(answers))
  result(named, "the naming keyboard opened for the boxed MAGIKARP")

  local boxed = session.storage.boxes[1].mons[1]
  result(boxed ~= nil and (boxed.speciesId or boxed.species) == SPECIES_MAGIKARP,
    "the MAGIKARP is in box 1 slot 1")
  -- pokefirered/src/field_specials.c:1647
  local nick = boxed and boxed.nickname
  result(type(nick) == "string" and nick ~= "" and nick ~= "MAGIKARP",
    "SetBoxMonNickAt renamed the boxed mon, got " .. tostring(nick))
  result(session.monBoxId == 0 and session.monBoxPos == 0,
    "it renamed the mon at monBoxId/monBoxPos, " ..
    tostring(session.monBoxId) .. "/" .. tostring(session.monBoxPos))
  local partyRenamed = false
  for _, mon in ipairs(session.party) do
    if mon.nickname == nick then partyRenamed = true end
  end
  result(not partyRenamed, "no party mon was renamed instead")
  U.wait(20)
  U.shot(game, DIR .. "/stitchscript_seams_04_transfer_after_naming.png")

  finish()
end
