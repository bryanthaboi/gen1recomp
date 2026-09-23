-- pokefirered/data/scripts/pc.inc:1
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local PC_X, PC_Y = 11, 2
local SE_PC_LOGIN, SE_PC_OFF, SE_PC_ON, SE_SELECT = 2, 3, 4, 5 -- include/constants/songs.h:6

local failures = 0
local function result(ok, label)
  if ok then
    print("PASS " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
  end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_pc_se_2415")
    love.event.quit(0)
  else
    print("FAIL game3_pc_se_2415 failures=" .. failures)
    love.event.quit(1)
  end
end

local function waitFor(pred, n)
  for _ = 1, n do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

local function PcMenu() return package.loaded["src.ui.game3.pc_menu"] end
local function Space() return package.loaded["src.core.game3.scripting.space"] end
local function Message() return package.loaded["src.ui.game3.message"] end
local function menuOpen()
  local M = PcMenu()
  return M and M.isOpen and M.isOpen() and M.mode == "root"
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", { x = PC_X, y = PC_Y, facing = "up" })
  game.session.x, game.session.y, game.session.facing = PC_X, PC_Y, "up"
  U.wait(90)

  local Audio = require("src.core.game3.audio")
  local orig = Audio.playSe
  local log = {}
  Audio.playSe = function(id, ...)
    log[#log + 1] = id
    print("SE " .. tostring(id))
    return orig(id, ...)
  end
  local function since(n)
    local t = {}
    for i = n + 1, #log do t[#t + 1] = tostring(log[i]) end
    return table.concat(t, ",")
  end

  U.tap(game, "a")
  local booted = waitFor(function()
    local Msg = Message()
    return Msg and Msg.isOpen and Msg.isOpen()
  end, 60)
  U.wait(10)
  result(booted, "interact opens the booted-up message")
  result(log[1] == SE_PC_ON and #log == 1,
    "SE_PC_ON (4) plays on interact before the menu (got " .. since(0) .. ")")
  U.shot(game, DIR .. "/2415_01_booted_up_pc.png")

  local mark = #log
  for _ = 1, 8 do
    if menuOpen() then break end
    U.tap(game, "a")
    U.wait(20)
  end
  if not result(menuOpen(), "Center PC opens the root menu") then return finish() end
  result(since(mark) == "", "root menu open plays no SE (got " .. since(mark) .. ")")

  mark = #log
  U.tap(game, "a")
  U.wait(20)
  result(since(mark) == SE_SELECT .. "," .. SE_PC_LOGIN,
    "SOMEONE'S PC selection plays SE_SELECT then SE_PC_LOGIN (got " .. since(mark) .. ")")
  U.shot(game, DIR .. "/2415_02_storage_menu_after_login.png")

  local M = PcMenu()
  local function advanceUntil(pred, n)
    for _ = 1, n do
      if pred() then return true end
      local Msg = Message()
      local page = Msg and Msg.isOpen() and tostring(Msg.currentPage() or ""):gsub("[\n\f]", " ") or ""
      if Msg and Msg.isOpen() and Msg.isWaiting() and not page:find("Which PC", 1, true) then
        U.tap(game, "a")
      end
      U.wait(1)
    end
    return pred()
  end
  local function released()
    local S = Space()
    local running = S and S.vm and S.vm.isRunning and S.vm:isRunning()
    local Msg = Message()
    return not M.isOpen() and not running and not (Msg and Msg.isOpen and Msg.isOpen())
  end
  local function waitReleased(n)
    for _ = 1, n do
      if released() then return true end
      U.wait(1)
    end
    return released()
  end

  if not result(advanceUntil(function() return M.isOpen() and M.mode == "storage_menu" end, 600),
    "storage system menu opens") then return finish() end
  mark = #log
  U.tap(game, "b")
  if not result(advanceUntil(menuOpen, 600), "B out of storage reshows the PC menu") then return finish() end
  result(since(mark) == tostring(SE_SELECT),
    "B out of storage plays SE_SELECT only (got " .. since(mark) .. ")")
  local rows = M._rootEntries()
  local ids = {}
  for _, r in ipairs(rows) do ids[#ids + 1] = r.id end
  result(table.concat(ids, ",") == "storage,player,quit",
    "new game root menu has 3 rows (got " .. table.concat(ids, ",") .. ")")
  for _ = 1, #rows + 1 do
    if rows[M.cursor] and rows[M.cursor].id == "quit" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  mark = #log
  U.tap(game, "a")
  result(waitReleased(180), "LOG OFF releases the player")
  result(since(mark) == SE_SELECT .. "," .. SE_PC_OFF,
    "LOG OFF plays SE_SELECT then SE_PC_OFF once (got " .. since(mark) .. ")")

  U.wait(30)
  U.tap(game, "a")
  if not result(advanceUntil(menuOpen, 600), "Center PC reopens the root menu") then return finish() end
  mark = #log
  U.tap(game, "b")
  result(waitReleased(180), "B on the PC menu releases the player")
  result(since(mark) == SE_SELECT .. "," .. SE_PC_OFF,
    "B on the PC menu plays SE_SELECT then SE_PC_OFF once (got " .. since(mark) .. ")")

  Map.load(nil, game, "FR_PLAYERS_HOUSE_2F", { x = 1, y = 2, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 1, 2, "up"
  U.wait(90)
  mark = #log
  U.tap(game, "a")
  if not result(advanceUntil(function() return M.isOpen() and M.mode == "player_pc" end, 600),
    "bedroom PC opens the player PC menu") then return finish() end
  result(since(mark) == tostring(SE_PC_ON), "bedroom PC plays SE_PC_ON (got " .. since(mark) .. ")")
  U.shot(game, DIR .. "/2415_03_bedroom_pc_menu.png")
  for _ = 1, 4 do
    if M.cursor == #M.TOP_ACTIONS then break end
    U.tap(game, "down")
    U.wait(8)
  end
  mark = #log
  U.tap(game, "a")
  result(waitReleased(180), "bedroom TURN OFF releases the player")
  result(since(mark) == SE_SELECT .. "," .. SE_PC_OFF,
    "bedroom TURN OFF plays SE_SELECT then SE_PC_OFF once (got " .. since(mark) .. ")")

  U.wait(30)
  U.tap(game, "a")
  if not result(advanceUntil(function() return M.isOpen() and M.mode == "player_pc" end, 600),
    "bedroom PC reopens") then return finish() end
  mark = #log
  U.tap(game, "b")
  result(waitReleased(180), "bedroom B releases the player")
  result(since(mark) == SE_SELECT .. "," .. SE_PC_OFF,
    "bedroom B plays SE_SELECT then SE_PC_OFF once (got " .. since(mark) .. ")")

  Audio.playSe = orig
  finish()
end
