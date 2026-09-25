local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import_dex_count_2461"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " import_dex_count_2461 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  local GameVersion = require("src.core.GameVersion")
  local SaveData = require("src.core.SaveData")
  local SaveSerializer = require("src.core.SaveSerializer")
  local SaveFileIO = require("src.import.SaveFileIO")
  local Boot = require("src.ui.game3.boot")
  local Dex = require("src.core.game3.dex")
  local version = GameVersion.get()
  local cart = unrle(require("tests.fixture_data.gen3_saves").images.fr_rich_game)
  love.filesystem.write("picked_cart_2461.sav", cart)
  local ok, slotId = SaveFileIO.importToSlot("picked_cart_2461.sav", version)
  love.filesystem.remove("picked_cart_2461.sav")
  if not result(ok == true, "the FireRed cart imports into " .. version .. " (" .. tostring(slotId) .. ")") then
    return finish()
  end

  local meta
  for _, row in ipairs(SaveData.listSlots(version)) do
    if row.id == slotId then meta = row.meta end
  end
  print("launcher meta dexCount=" .. tostring(meta and meta.dexCount) .. " badges=" .. tostring(meta and meta.badges)
    .. " time=" .. tostring(meta and meta.timeText))
  result(meta and meta.dexCount == 5, "launcher card shows 5 caught for the fresh import")
  result(meta and meta.badges == 2, "launcher card shows 2 badges")

  local raw = SaveSerializer.decode(SaveData.readSlotSource(version, slotId) or "")
  local info = raw and Boot.continueInfoFromSave(raw)
  result(info and info.dexCount == 5, "CONTINUE window counts 5 caught before the first load")
  if info then
    Boot.setHasContinue(game.boot, true)
    Boot.setContinueInfo(game.boot, info)
  end

  local function phase() return game.boot and game.boot.phase end
  local n = 0
  while phase() ~= "title" and n < 1200 do
    U.tap(game, "start")
    U.wait(30)
    n = n + 30
  end
  for _ = 1, 20 do
    if phase() ~= "title" then break end
    U.wait(60)
    U.tap(game, "start")
    U.wait(2)
  end
  for _ = 1, 600 do
    if phase() == "menu" and (game.boot.fadeT or 0) == 0 then break end
    U.wait(1)
  end
  U.wait(4)
  print("boot phase=" .. tostring(phase()) .. " game.phase=" .. tostring(game.phase))
  if result(phase() == "menu", "main menu with CONTINUE is up") then
    U.still(game, DIR .. "/2461_continue_dex_5.png")
  end

  game:_handleBootAction({ action = "continue" })
  local Runtime = require("src.core.game3.runtime")
  local s
  for _ = 1, 900 do
    s = Runtime.getSession()
    if s and game.phase ~= "quest_log" and game.phase ~= "boot" then break end
    if game.phase == "quest_log" then U.tap(game, "b") end
    U.wait(4)
  end
  s = Runtime.getSession()
  if not result(s ~= nil, "CONTINUE reached the field") then return finish() end
  result(Dex.countCaught(s.dex, "kanto") == 5, "in-game Kanto dex count is 5 (matches the launcher)")
  finish()
end
