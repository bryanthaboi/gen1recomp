-- pokefirered/src/script_menu.c:1027
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local FLAG_SYS_POKEMON_GET = 0x828 -- pokefirered/include/constants/flags.h:1374
local FLAG_SYS_NOT_SOMEONES_PC = 0x834 -- pokefirered/include/constants/flags.h:1386
local PC_X, PC_Y = 11, 2

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
    print("PASS game3_bills_pc_label_bug2404")
    love.event.quit(0)
  else
    print("FAIL game3_bills_pc_label_bug2404 failures=" .. failures)
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

local function drawnStorageRow()
  local Window = require("src.ui.game3.window")
  local real = Window.printPx
  local rows = {}
  Window.printPx = function(text, ...)
    rows[#rows + 1] = text
    return real(text, ...)
  end
  local ok = pcall(PcMenu().draw)
  Window.printPx = real
  return ok and rows[1] or nil
end

local function openRoot(game)
  U.tap(game, "a")
  for _ = 1, 8 do
    U.wait(20)
    local M = PcMenu()
    if M and M.isOpen and M.isOpen() and M.mode == "root" then break end
    U.tap(game, "a")
  end
  U.wait(10)
  local M = PcMenu()
  return M and M.isOpen and M.isOpen() and M.mode == "root"
end

local function logOff(game)
  local M = PcMenu()
  for _ = 1, 5 do
    if M.cursor == 5 then break end
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  local Message = package.loaded["src.ui.game3.message"]
  return waitFor(function()
    local S = Space()
    local running = S and S.vm and S.vm.isRunning and S.vm:isRunning()
    return not M.isOpen() and not running and not (Message and Message.isOpen and Message.isOpen())
  end, 180)
end

local function checkLabel(game, want, tag)
  local M = PcMenu()
  local row = drawnStorageRow()
  result(M.storageLabel and M.storageLabel(M._session or game.session) == want and row == want,
    string.format("%s: root menu first row is %s (got %s)", tag, want, tostring(row)))
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)
  local Map = require("src.core.game3.map")
  local Flags = require("src.core.game3.scripting.flags")
  Map.load(nil, game, "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", { x = PC_X, y = PC_Y, facing = "up" })
  game.session.x, game.session.y, game.session.facing = PC_X, PC_Y, "up"
  U.wait(90)

  local store = Space() and Space().store
  if not result(store ~= nil, "FireRed script flag store is live") then return finish() end
  Flags.setFlag(store, nil, FLAG_SYS_POKEMON_GET, true)
  Flags.setFlag(store, nil, FLAG_SYS_NOT_SOMEONES_PC, false)

  if not result(openRoot(game), "before Bill: Center PC opens the root menu") then return finish() end
  checkLabel(game, "SOMEONE'S PC", "before Bill (starter flag 0x828 set)")
  U.shot(game, DIR .. "/2404_01_someones_pc_before_bill.png")
  result(logOff(game), "before Bill: LOG OFF releases the player")

  Flags.setFlag(Space().store, nil, FLAG_SYS_NOT_SOMEONES_PC, true)
  U.wait(10)
  if not result(openRoot(game), "after Bill: Center PC opens the root menu") then return finish() end
  checkLabel(game, "BILL'S PC", "after Bill (0x834 set)")
  U.shot(game, DIR .. "/2404_02_bills_pc_after_sea_cottage.png")
  result(logOff(game), "after Bill: LOG OFF releases the player")

  local S = Space()
  S.persistSession(nil, game)
  local live = S.store
  S.store = nil
  local M = PcMenu()
  local label = M.storageLabel and M.storageLabel(game.session)
  S.store = live
  result(label == "BILL'S PC",
    string.format("saved session snapshot still reads BILL'S PC (got %s)", tostring(label)))

  finish()
end
