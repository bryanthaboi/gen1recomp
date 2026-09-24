local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import_cart_save"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " import_cart_save failures=" .. failures)
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
  local SaveFileIO = require("src.import.SaveFileIO")
  local version = GameVersion.get()
  local cart = unrle(require("tests.fixture_data.gen3_saves").images.fr_rich_game)
  love.filesystem.write("picked_cart_2444.sav", cart)
  local ok, slotId, info = SaveFileIO.importToSlot("picked_cart_2444.sav", version)
  love.filesystem.remove("picked_cart_2444.sav")
  if not result(ok == true, "the FireRed cart imports into " .. version .. " (" .. tostring(slotId) .. ")") then
    return finish()
  end
  result(info == nil, "no confirm prompt and no fallback note")
  result(SaveData.activeSlot(version) == slotId, "the imported slot is active")

  game:_handleBootAction({ action = "continue" })
  local Runtime = require("src.core.game3.runtime")
  local s
  for _ = 1, 900 do
    s = Runtime.getSession()
    if s and game.phase ~= "quest_log" and game.phase ~= "boot" then break end
    if game.phase == "quest_log" then U.tap(game, "b") end
    U.wait(4)
  end
  U.wait(90)
  s = Runtime.getSession()
  if not result(s ~= nil, "CONTINUE reached the field") then return finish() end
  print(string.format("CONTINUE map=%s x=%s y=%s money=%s heal=%s %s,%s", tostring(s.map), tostring(s.x),
    tostring(s.y), tostring(s.money), tostring(s.healMap), tostring(s.healX), tostring(s.healY)))
  result(s.map == "FR_PLAYERS_HOUSE_2F" and s.x == 6 and s.y == 6, "continue lands in the bedroom at 6,6 like the cart")
  result(s.money == 123456, "money 123456")
  result(s.coins == 777, "coins 777")
  result(s.healMap == "FR_PLAYERS_HOUSE_1F", "whiteout spot is Mom's house")
  local want = { { 6, 36, "BLAZE" }, { 277, 10, "" }, { 172, 5, "EGG" }, { 201, 25, "" } }
  for i, w in ipairs(want) do
    local m = s.party[i] or {}
    result(m.species == w[1] and m.level == w[2] and m.nickname == w[3],
      ("party %d is species %d Lv%d (%s Lv%s %q)"):format(i, w[1], w[2], tostring(m.species), tostring(m.level), tostring(m.nickname)))
  end
  result(s.party[1].hp == 50 and s.party[1].status == "PSN", "Charizard keeps 50 HP and poison")
  local box = s.storage.boxes[2].mons[20]
  result(box and box.species == 150 and box.level == 70, "Mewtwo Lv70 in box 2 slot 20")
  result(s.dex.owned[277] == true, "Treecko caught in the dex")
  U.still(game, DIR .. "/2444_continue_bedroom.png")

  local StartMenu = require("src.ui.game3.start_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  U.tap(game, "start")
  U.wait(30)
  if not result(StartMenu.isOpen(), "start menu opened") then return finish() end
  local idx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "pokemon" then idx = i break end
  end
  if not result(idx ~= nil, "the start menu offers POKéMON") then return finish() end
  for _ = 1, 20 do
    if StartMenu.cursor == idx then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  for _ = 1, 120 do
    if PartyMenu.open then break end
    U.wait(2)
  end
  U.wait(60)
  if result(PartyMenu.open, "party screen opened") then
    U.still(game, DIR .. "/2444_party_screen.png")
  end
  for _ = 1, 60 do
    if not PartyMenu.open and not StartMenu.isOpen() then break end
    U.tap(game, "b")
    U.wait(6)
  end
  finish()
end
