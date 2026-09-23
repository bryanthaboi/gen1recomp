local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bug2440"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " hof_continue_2440 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Message = require("src.ui.game3.message")
  local HallOfFame = require("src.ui.game3.hall_of_fame")
  local SaveData = require("src.core.SaveData")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field reached") then return finish() end

  local hof = "FR_POKEMON_LEAGUE_HALL_OF_FAME"
  Map.load(nil, game, hof, { x = 5, y = 12, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 5, 12, "up"

  local sawHof = false
  for _ = 1, 3000 do
    if HallOfFame.open then sawHof = true break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
  if not result(sawHof, "HoF induction screen opened from the room script") then return finish() end
  for _ = 1, 6000 do
    if not HallOfFame.open then break end
    U.tap(game, "a")
    U.wait(4)
  end
  result(not HallOfFame.open, "HoF screen closed")
  U.wait(30)

  local okL, save = pcall(SaveData.load)
  save = okL and save or {}
  local w = type(save.continueGameWarp) == "table" and save.continueGameWarp or {}
  print(string.format("SAVED map=%s x=%s y=%s flags=%s warp=%s %s,%s", tostring(save.map), tostring(save.x),
    tostring(save.y), tostring(save.specialSaveWarpFlags), tostring(w.map), tostring(w.x), tostring(w.y)))
  result((tonumber(save.specialSaveWarpFlags) or 0) % 2 == 1, "save carries CONTINUE_GAME_WARP")
  result(w.map == "FR_PALLET_TOWN" and w.x == 6 and w.y == 8, "continue warp is Pallet Town 6,8")

  local Credits = require("src.ui.game3.credits")
  if Credits.open then pcall(Credits.reset) end
  game.softResetRequested = true
  U.wait(60)
  game:_handleBootAction({ action = "continue" })
  local s2
  for _ = 1, 900 do
    s2 = Runtime.getSession()
    if s2 and game.phase ~= "quest_log" then break end
    if game.phase == "quest_log" then U.tap(game, "b") end
    U.wait(4)
  end
  print("PHASE " .. tostring(game.phase))
  U.wait(60)
  print(string.format("CONTINUE map=%s x=%s y=%s", tostring(s2 and s2.map), tostring(s2 and s2.x), tostring(s2 and s2.y)))
  result(s2 and s2.map == "FR_PALLET_TOWN" and s2.x == 6 and s2.y == 8, "continue lands in Pallet Town 6,8")
  local reran = false
  for _ = 1, 200 do
    local p = string.upper(Message.currentPage and Message.currentPage() or "")
    if p:find("CONGRATULATIONS", 1, true) or p:find("HALL OF", 1, true) then reran = true break end
    U.wait(2)
  end
  U.shot(game, DIR .. "/2440_after_continue_pallet.png")
  result(not reran, "Oak's HoF congratulation script did not re-run after continue")
  finish()
end
