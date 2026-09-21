local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_route2_aide"

local BUILDING = "FR_ROUTE_2_EAST_BUILDING"
local AIDE_X, AIDE_Y = 4, 6
local ITEM_HM05 = 343 -- pokefirered/include/constants/items.h:354
local FLAG_GOT_HM05 = 571 -- pokefirered/data/maps/Route2_EastBuilding/scripts.inc:6

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/route2_aide.log", "a")
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
    say("PASS route2_aide")
    love.event.quit(0)
  else
    say("FAIL route2_aide failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Dex = require("src.core.game3.dex")
  local Bag = require("src.core.game3.bag")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Std = require("src.core.game3.scripting.stdscripts")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  session.dex = session.dex or Dex.new()
  session.dex.seen = session.dex.seen or {}
  session.dex.caught = session.dex.caught or {}
  session.dex.owned = session.dex.owned or session.dex.caught
  local NINE = { 1, 4, 7, 10, 13, 16, 19, 21, 23 }
  for _, sp in ipairs(NINE) do Dex.setCaught(session.dex, sp) end
  result(Dex.countCaught(session.dex, "kanto") == 9, "dex holds 9 caught mons, got "
    .. tostring(Dex.countCaught(session.dex, "kanto")))

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

  local seenVar, caughtVar = 0, 0
  local pages = {}
  local function pumpScript(frames, want, shotPath)
    local shot = false
    for _ = 1, frames do
      if not (Space.vm and Space.vm:isRunning()) then return true, shot end
      local sv, cv = getVar(0x8005), getVar(0x8006)
      if sv ~= 0 then seenVar = sv end
      if cv ~= 0 then caughtVar = cv end
      local page = Message.isOpen() and Message.currentPage() or nil
      if page and pages[#pages] ~= page then pages[#pages + 1] = page end
      local settled = Message.isWaiting and Message.isWaiting()
      if want and not shot and settled and page and page:find(want, 1, true) then
        shot = U.shot(game, shotPath)
        say("[driver] shot page: " .. page:gsub("\n", " / "))
      end
      if Choice.active or settled then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return not (Space.vm and Space.vm:isRunning()), shot
  end

  goTo(BUILDING, AIDE_X, AIDE_Y + 1, "up")
  local Objects = require("src.core.game3.objects")
  local aide = Objects.find and Objects.find(1)
  say(string.format("[driver] aide object localId 1 at (%s,%s) visible=%s, player at (%s,%s)",
    tostring(aide and aide.cellX), tostring(aide and aide.cellY),
    tostring(aide and aide.visible), tostring(Player.cellX), tostring(Player.cellY)))
  result(aide ~= nil and aide.cellX == AIDE_X and aide.cellY == AIDE_Y,
    "the aide is on the map in front of the player")
  U.shot(game, DIR .. "/route2_aide_01_aide.png")

  say("[driver] first visit: 9 caught, the aide should refuse")
  U.tap(game, "a")
  U.wait(30)
  for _ = 1, 40 do
    if Message.isOpen() then break end
    U.wait(6)
  end
  say("[driver] offer page: " .. tostring(Message.currentPage()))
  U.shot(game, DIR .. "/route2_aide_02_offer.png")
  -- pokefirered/data/maps/Route2_EastBuilding/scripts.inc:16
  local _, gotRefusal = pumpScript(200, "Uh-oh", DIR .. "/route2_aide_03_refused.png")
  U.wait(30)
  result(caughtVar == 9, "VAR_0x8006 = 9 on the refusal pass, got " .. tostring(caughtVar))
  result(not Bag.has(session.bag, ITEM_HM05, 1), "no HM05 in the bag yet")
  result(Flags.getFlag(Space.store, ctx(), FLAG_GOT_HM05) ~= true, "FLAG_GOT_HM05 still clear")
  result(gotRefusal, "photographed the refusal page")

  say("[driver] catching two more: the aide's gate is 10 caught")
  Dex.setCaught(session.dex, 25)
  Dex.setCaught(session.dex, 29)
  result(Dex.countCaught(session.dex, "kanto") == 11, "dex holds 11 caught mons, got "
    .. tostring(Dex.countCaught(session.dex, "kanto")))

  for _ = 1, 40 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    if Choice.active or (Message.isWaiting and Message.isWaiting()) then U.tap(game, "a") end
    U.wait(6)
  end
  U.wait(30)

  say("[driver] second visit: 11 caught, the aide should hand over HM05")
  seenVar, caughtVar = 0, 0
  pages = {}
  U.tap(game, "a")
  U.wait(30)
  -- pokefirered/data/maps/Route2_EastBuilding/text.inc:13
  local _, gotGift = pumpScript(300, "caught or owned", DIR .. "/route2_aide_04_got_hm05.png")
  U.wait(40)

  say(string.format("[driver] VAR_0x8005 = %s seen, VAR_0x8006 = %s caught",
    tostring(seenVar), tostring(caughtVar)))
  for i, p in ipairs(pages) do say("[driver] gift page " .. i .. ": " .. p:gsub("\n", " / ")) end
  result(caughtVar == 11, "VAR_0x8006 = 11 on the gift pass, got " .. tostring(caughtVar))
  result(seenVar == 11, "VAR_0x8005 = 11 seen on the gift pass, got " .. tostring(seenVar))
  result(Bag.has(session.bag, ITEM_HM05, 1), "HM05 FLASH is in the bag")
  result(Flags.getFlag(Space.store, ctx(), FLAG_GOT_HM05) == true, "FLAG_GOT_HM05 is set")
  result(gotGift, "photographed the HM05 hand-over")

  say(string.format("[driver] GetPokedexCount id = 0x%X", Std.SPECIAL.GetPokedexCount))
  result(Std.SPECIAL.GetPokedexCount == 0xD4, "GetPokedexCount is special 0xD4")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL route2_aide driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
