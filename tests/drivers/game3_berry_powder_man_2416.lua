local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bug2416"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_berry_powder_man_2416")
    love.event.quit(0)
  else
    print("FAIL game3_berry_powder_man_2416 failures=" .. failures)
    love.event.quit(1)
  end
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Bag = require("src.core.game3.bag")
  local Objects = require("src.core.game3.objects")
  local Field = require("src.core.game3.field")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  Bag.add(session.bag, 139, 1)
  result(Bag.has(session.bag, 365, 1), "ORAN BERRY auto-granted the BERRY POUCH")

  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local mapId = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine("CeruleanCity_House5"))
    or "FR_CERULEAN_CITY_HOUSE5"
  Map.load(nil, game, mapId, { x = 8, y = 4, facing = "left" })
  game.session.x, game.session.y, game.session.facing = 8, 4, "left"
  U.wait(30)

  result(Space.store and Flags.getFlag(Space.store, nil, 0x847) == true,
    "FLAG_SYS_GOT_BERRY_POUCH set in the house")
  local man = Objects.find(1)
  if not result(man ~= nil, "Berry Powder man (localId 1) loaded") then return finish() end

  local function vmBusy()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning()
  end
  local function page()
    return string.upper(Message.currentPage and Message.currentPage() or "")
  end

  U.tap(game, "a")
  local hit, liar = false, false
  for _ = 1, 400 do
    local p = page()
    if p:find("JUST THE THING", 1, true) then hit = true break end
    if p:find("LIE TO ME", 1, true) then liar = true break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(3)
  end
  result(not liar, "man did not take the NoBerries branch")
  if not result(hit, "man says he has just the thing") then return finish() end
  Message.skipReveal()
  U.wait(10)
  result(U.shot(game, DIR .. "/2416_powder_man_just_the_thing.png"), "screenshot 2416_powder_man_just_the_thing")

  for _ = 1, 400 do
    if not Message.isOpen() and not vmBusy() and not Field.locked then break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(3)
  end
  result(Bag.has(session.bag, 372, 1), "POWDER JAR landed in the bag")
  result(Flags.getFlag(Space.store, nil, "FLAG_GOT_POWDER_JAR") == true, "FLAG_GOT_POWDER_JAR set")

  local BerryPowderBox = require("src.ui.game3.berry_powder_box")
  local Records = require("src.ui.game3.minigame_records")
  local Choice = require("src.ui.game3.choice")
  local ListMenu = require("src.core.game3.scripting.natives_listmenu").Menu

  local function idle()
    return not Message.isOpen() and not vmBusy() and not Field.locked
      and not Choice.active and not ListMenu.isOpen() and not Records.isOpen()
  end

  session.berryPowder = 1234
  U.tap(game, "a")
  for _ = 1, 400 do
    if ListMenu.isOpen() then break end
    if Message.isOpen() and Message.isTyping() then
      Message.skipReveal()
    elseif Message.isOpen() and Message.isWaiting() and not Choice.active
        and not page():find("EXCHANGE IT", 1, true) then
      U.tap(game, "a")
    end
    U.wait(3)
  end
  if not result(ListMenu.isOpen(), "exchange list opened") then return finish() end
  result(BerryPowderBox.isVisible(), "POWDER box is up with the exchange list")
  result(BerryPowderBox.amount() == 1234, "POWDER box reads 1234 (got " .. tostring(BerryPowderBox.amount()) .. ")")
  U.wait(10)
  result(U.shot(game, DIR .. "/powd_box_with_exchange_list.png"), "screenshot powd_box_with_exchange_list")

  U.tap(game, "a")
  for _ = 1, 400 do
    if Choice.active then break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    U.wait(3)
  end
  if not result(Choice.active, "YES/NO for ENERGYPOWDER") then return finish() end
  result(BerryPowderBox.isVisible(), "POWDER box stays up through YES/NO")
  U.tap(game, "a")
  local traded = false
  for _ = 1, 600 do
    local p = page()
    if p:find("TRADE MORE", 1, true) then
      if Choice.active then traded = true break end
      if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    elseif Message.isOpen() and Message.isTyping() then
      Message.skipReveal()
    elseif Message.isOpen() and Message.isWaiting() and not Choice.active then
      U.tap(game, "a")
    end
    U.wait(3)
  end
  if not result(traded, "man asks to trade more") then return finish() end
  result(Bag.has(session.bag, 30, 1), "ENERGYPOWDER landed in the bag")
  result(session.berryPowder == 1184, "berryPowder 1234 - 50 = 1184")
  result(BerryPowderBox.amount() == 1184, "POWDER box reprinted 1184 (got " .. tostring(BerryPowderBox.amount()) .. ")")
  U.wait(10)
  result(U.shot(game, DIR .. "/powd_box_reprint_after_exchange.png"), "screenshot powd_box_reprint_after_exchange")

  U.tap(game, "b")
  for _ = 1, 400 do
    if idle() then break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(3)
  end
  result(idle(), "vendor script finished")
  result(not BerryPowderBox.isVisible(), "POWDER box removed after goodbye")

  local function readSign(label, mapName, x, y, kind, expect)
    local id = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine(mapName)) or mapName
    Map.load(nil, game, id, { x = x, y = y, facing = "up" })
    game.session.x, game.session.y, game.session.facing = x, y, "up"
    U.wait(30)
    U.tap(game, "a")
    for _ = 1, 120 do
      if Records.isOpen() then break end
      U.wait(1)
    end
    if not result(Records.isOpen() and Records.kind() == kind, label .. " window opened") then return end
    local text = {}
    for _, l in ipairs(Records.lines()) do text[#text + 1] = l.text end
    text = table.concat(text, "|")
    for _, want in ipairs(expect) do
      result(text:find(want, 1, true) ~= nil, label .. " shows '" .. want .. "'")
    end
    U.wait(10)
    result(vmBusy(), label .. " holds the script at waitstate")
    result(U.shot(game, DIR .. "/" .. label .. ".png"), "screenshot " .. label)
    U.tap(game, "a")
    for _ = 1, 120 do
      if idle() then break end
      U.wait(1)
    end
    result(not Records.isOpen() and idle(), label .. " closed on A and released the player")
  end

  readSign("powd_berry_crush_rankings", "CeruleanCity_House5", 3, 2, "berry_crush",
    { "BERRY CRUSH", "Pressing-Speed Rankings", "2 PLAYERS", "5 PLAYERS", "0.00 Times/sec." })
  -- data/maps/TwoIsland_JoyfulGameCorner/scripts.inc:29
  Flags.setVar(Space.store, Space.vm and Space.vm.ctx, 0x4079, 3)
  readSign("powd_pokemon_jump_records", "TwoIsland_JoyfulGameCorner", 1, 2, "pokemon_jump",
    { "JUMP RECORDS", "Jumps in a row:", "Best score:", "EXCELLENTS in a row:", "|0" })
  readSign("powd_dodrio_berry_picking_records", "TwoIsland_JoyfulGameCorner", 0, 2, "dodrio",
    { "DODRIO BERRY-PICKING RECORDS", "BERRIES picked:", "five players:", "|0" })

  return finish()
end
