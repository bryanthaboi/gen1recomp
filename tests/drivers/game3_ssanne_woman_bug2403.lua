local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bug2403"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_ssanne_woman_bug2403")
    love.event.quit(0)
  else
    print("FAIL game3_ssanne_woman_bug2403 failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Objects = require("src.core.game3.objects")
  local Field = require("src.core.game3.field")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}
  Party.giveMon(session, 7, 30)

  local engaged = {}
  local origEngage = TrainerSight.engage
  TrainerSight.engage = function(g, eo, dist)
    engaged[#engaged + 1] = eo and eo.localId
    return origEngage(g, eo, dist)
  end

  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local mapId = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine("SSAnne_1F_Room2"))
    or "FR_SSANNE_1F_ROOM2"
  local function place(x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    game.session.x, game.session.y, game.session.facing = x, y, facing
    U.wait(30)
  end

  local function vmBusy()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning()
  end
  local function msgOpen()
    return Message.isOpen and Message.isOpen()
  end

  place(2, 5, "down")
  local woman = Objects.find(3)
  if not result(woman ~= nil, "SS Anne 1F Room2 Woman (localId 3) loaded") then return finish() end
  result(tonumber(woman.trainerType) == 0 and tonumber(woman.sight) == 1,
    "Woman carries TRAINER_TYPE_NONE with leftover sight 1 (type=" .. tostring(woman.trainerType)
      .. " sight=" .. tostring(woman.sight) .. ")")

  U.tap(game, "a")
  local opened = false
  for _ = 1, 120 do
    if msgOpen() then opened = true break end
    U.wait(1)
  end
  if not result(opened, "talking to the Woman opens her line") then return finish() end
  U.wait(20)
  result(woman.facing == "up", "Woman turned to face the player (facing=" .. tostring(woman.facing) .. ")")
  result(U.shot(game, DIR .. "/2403_01_woman_cruising_text.png"), "screenshot 2403_01_woman_cruising_text")

  for _ = 1, 300 do
    if not msgOpen() and not vmBusy() and not Field.locked then break end
    if msgOpen() then U.tap(game, "a") end
    U.wait(3)
  end
  result(not msgOpen() and not vmBusy(), "Woman's msgbox closed and the VM went idle")

  local looped, reopened, locked = false, false, false
  for _ = 1, 240 do
    U.wait(1)
    if #engaged > 0 then looped = true end
    if msgOpen() then reopened = true end
    if Field.locked then locked = true end
  end
  result(not looped, "Woman never engages as a trainer after her line (engages=" .. #engaged .. ")")
  result(not reopened, "her line does not reopen on its own")
  result(not locked, "field stays unlocked for 240 frames after the text")
  result(woman.facing == "up" and Objects.find(3) == woman, "Woman still faces the player one tile away")
  result(U.shot(game, DIR .. "/2403_02_after_text_no_loop.png"), "screenshot 2403_02_after_text_no_loop")

  engaged = {}
  place(5, 5, "up")
  local lass = Objects.find(1)
  if not result(lass ~= nil and TrainerSight.isTrainerType(lass), "Lass Ann (localId 1) is a TRAINER_TYPE_NORMAL") then
    return finish()
  end
  lass.facing = "down"
  local spotted = false
  for _ = 1, 300 do
    if #engaged > 0 then spotted = true break end
    U.wait(1)
  end
  result(spotted and engaged[1] == 1, "control: Lass Ann still spots the player 2 tiles below her")
  if spotted then
    U.wait(20)
    result(U.shot(game, DIR .. "/2403_03_lass_ann_spots_player.png"), "screenshot 2403_03_lass_ann_spots_player")
  end

  return finish()
end
