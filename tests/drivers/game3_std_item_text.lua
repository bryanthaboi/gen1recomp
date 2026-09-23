-- pokefirered/data/scripts/obtain_item.inc:10
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_std_item_text"

local ITEM_POTION = 13 -- include/constants/items.h:17

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_std_item_text")
    love.event.quit(0)
  else
    print("FAIL game3_std_item_text failures=" .. failures)
    love.event.quit(1)
  end
end

local function flat(s)
  return (tostring(s or ""):gsub("[\n\f]", " "))
end

local function waitPage(game, pattern, frames)
  local Message = require("src.ui.game3.message")
  local seen = {}
  for _ = 1, frames do
    if Message.isOpen() then
      local page = flat(Message.currentPage())
      if page:find(pattern, 1, true) then
        while not Message.isWaiting() do U.wait(1) end
        return true, page
      end
      if Message.isWaiting() then
        if seen[#seen] ~= page then seen[#seen + 1] = page end
        U.tap(game, "a")
      end
    end
    U.wait(1)
  end
  return false, table.concat(seen, " | ")
end

local function shootPrinted(game, pattern, frames, path)
  local Message = require("src.ui.game3.message")
  for _ = 1, frames do
    if Message.isOpen() and flat(Message.currentPage()):find(pattern, 1, true) then
      local lastGlyph = (Message._revealed or 0) == (Message._total or 0) - 1 and (Message._delay or 0) == 0
      if lastGlyph and not Message._waiting then
        U.shot(game, path)
        return true, flat(Message.currentPage())
      end
    end
    U.wait(1)
  end
  return false, flat(Message.currentPage())
end

local function waitIdle(game, frames)
  local Message = require("src.ui.game3.message")
  local Space = require("src.core.game3.scripting.space")
  for _ = 1, frames do
    local running = Space.vm and Space.vm:isRunning()
    if not running and not Message.isOpen() then return true end
    if Message.isWaiting() then U.tap(game, "a") end
    U.wait(1)
  end
  return false
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
  local MapCatalog = require("src.import.gba.map_catalog")
  local Space = require("src.core.game3.scripting.space")
  local Bag = require("src.core.game3.bag")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local MT_MOON = MapCatalog.pretToEngine("MtMoon_1F")
  if not result(type(MT_MOON) == "string", "Mt Moon 1F resolves to a cache map id") then
    return finish()
  end
  Map.load(nil, game, MT_MOON, { x = 11, y = 36, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 11, 36, "up"
  U.wait(90)

  U.tap(game, "a")
  local ok, page = waitPage(game, "found a TM09! It contains BULLET SEED.", 600)
  result(ok, "TM ball: \"RED found a TM09! It contains BULLET SEED.\" (got " .. page .. ")")
  if ok then U.shot(game, DIR .. "/txt_tm09_found_contains_move.png") end
  U.tap(game, "a")
  ok, page = waitPage(game, "RED put the TM09 in the TM CASE.", 600)
  result(ok, "TM ball: \"RED put the TM09 in the TM CASE.\" (got " .. page .. ")")
  if ok then U.shot(game, DIR .. "/txt_tm09_put_in_tm_case.png") end
  waitIdle(game, 300)

  Space.vm.scripts.Driver_GiveItem = {
    { op = "setorcopyvar", [1] = 0x8000, [2] = ITEM_POTION },
    { op = "setorcopyvar", [1] = 0x8001, [2] = 1 },
    { op = "callstd", std = 0 },
    { op = "end" },
  }
  local before = Bag.get(session.bag, ITEM_POTION) or 0
  Space.startScript("Driver_GiveItem")
  ok, page = shootPrinted(game, "Obtained the POTION!", 600, DIR .. "/txt_giveitem_obtained_the_potion.png")
  result(ok, "giveitem: \"Obtained the POTION!\" fully printed (got " .. page .. ")")
  ok, page = waitPage(game, "RED put the POTION in the ITEMS POCKET.", 600)
  result(ok, "giveitem: \"RED put the POTION in the ITEMS POCKET.\" (got " .. page .. ")")
  if ok then U.shot(game, DIR .. "/txt_giveitem_put_in_items_pocket.png") end
  waitIdle(game, 300)
  result((Bag.get(session.bag, ITEM_POTION) or 0) == before + 1, "giveitem added one POTION")

  finish()
end
