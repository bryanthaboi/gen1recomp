local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_encounters_dark_cave"

local ROCK_TUNNEL = "FR_ROCK_TUNNEL_1F"
local ROCK_TUNNEL_B1F = "FR_ROCK_TUNNEL_B1F"
local ROUTE_10 = "FR_ROUTE_10"
-- pokefirered/include/constants/flags.h:1364
local FLAG_BADGE01_GET = 0x820
-- pokefirered/include/constants/flags.h:1333
local FLAG_SYS_FLASH_ACTIVE = 0x806
-- pokefirered/include/constants/moves.h:152
local MOVE_FLASH = 148
local ENTRY_X, ENTRY_Y = 17, 3

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS encounters_dark_cave")
      love.event.quit(0)
    else
      print("FAIL encounters_dark_cave failures=" .. fails)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local StartMenu = require("src.ui.game3.start_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local FieldView = require("src.core.game3.field_view")
  local FieldEffects = require("src.core.game3.field_effects")
  local Field = require("src.core.game3.field")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end

  session.party = {}
  Party.giveMon(session, 25, 20)
  local lead = session.party[1]
  lead.moves = { MOVE_FLASH }
  lead.pp = { 20 }
  lead.maxPp = { 20 }
  Flags.setFlag(Space.store, ctx(), FLAG_BADGE01_GET, true)

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(90)
  end

  local function flashActive()
    return Flags.getFlag(Space.store, ctx(), FLAG_SYS_FLASH_ACTIVE) == true
  end

  placeAt(ROCK_TUNNEL, ENTRY_X, ENTRY_Y, "down")
  local def = game.data and game.data.maps and game.data.maps[ROCK_TUNNEL]
  result(def ~= nil and (tonumber(def.cave) or 0) == 1,
    "Rock Tunnel 1F carries requires_flash in its map header")
  result(not flashActive(), "FLAG_SYS_FLASH_ACTIVE is clear on arrival")
  result(FieldView.getFlashLevel() == 4,
    "the cave loads at gMaxFlashLevel (" .. tostring(FieldView.getFlashLevel()) .. ")")
  result(FieldView.flashRadius() == 24, "the visible window is a 24px radius")
  U.shot(game, DIR .. "/dark_cave_01_dark.png")

  U.tap(game, "start")
  U.wait(30)
  if not result(StartMenu.isOpen(), "start menu opened") then return finish() end
  local pokeIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "pokemon" then pokeIdx = i end
  end
  for _ = 1, 20 do
    if StartMenu.cursor == pokeIdx then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(60)
  if not result(PartyMenu.isOpen and PartyMenu.isOpen(), "party menu opened") then
    return finish()
  end
  U.tap(game, "a")
  U.wait(30)
  local flashIdx
  for i, act in ipairs(PartyMenu.ACTIONS or {}) do
    if act == "FLASH" then flashIdx = i end
  end
  U.log("party actions: " .. table.concat(PartyMenu.ACTIONS or {}, ", "))
  if not result(flashIdx ~= nil, "FLASH is offered on the lead's action menu") then
    return finish()
  end
  for _ = 1, 20 do
    if PartyMenu.actionCursor == flashIdx then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(40)

  local txt = Message.currentPage and Message.currentPage()
  if type(txt) == "string" and txt ~= "" then
    U.log("dialog: " .. txt:gsub("\n", " / "))
  end
  result(flashActive(), "using Flash set FLAG_SYS_FLASH_ACTIVE")

  local grew = false
  local last = FieldView.flashRadius() or 0
  local unlockedEarly = false
  for _ = 1, 30 do
    U.wait(4)
    local r = FieldView.flashRadius()
    if r == nil or r > last then grew = true end
    if r then last = r end
    if r and not Field.locked then unlockedEarly = true end
    if r and r > 90 then break end
  end
  result(grew, "the lit radius is opening out (" .. tostring(last) .. "px)")
  -- pokefirered/src/field_screen_effect.c:202
  result(not unlockedEarly, "the player stays locked while the circle is opening")
  U.shot(game, DIR .. "/dark_cave_02_opening.png")

  for _ = 1, 120 do
    if FieldView.getFlashLevel() == 0 and FieldView.flashRadius() == nil then break end
    U.wait(4)
  end
  result(FieldView.getFlashLevel() == 0, "AnimateFlash ended on flash level 0")
  result(FieldView.flashRadius() == nil, "nothing is masked any more")
  U.wait(10)
  result(not Field.locked, "and control comes back when the animation ends")
  U.wait(30)
  U.shot(game, DIR .. "/dark_cave_03_lit.png")

  placeAt(ROCK_TUNNEL_B1F, 5, 5, "down")
  result(FieldView.getFlashLevel() == 0,
    "B1F stays lit while FLAG_SYS_FLASH_ACTIVE is set")

  placeAt(ROUTE_10, 11, 19, "down")
  U.wait(60)
  result(FieldView.getFlashLevel() == 0, "Route 10 is never masked")
  result(not flashActive(), "ClearTempFieldEventData drops the flag outdoors")

  placeAt(ROCK_TUNNEL, ENTRY_X, ENTRY_Y, "down")
  result(FieldView.getFlashLevel() == 4, "walking back in is dark again")

  -- pokefirered/src/field_effect.c:1258
  FieldEffects.startLandingShake()
  local pans, zero = {}, false
  for _ = 1, 16 do
    pans[#pans + 1] = FieldView.cameraPanY
    U.wait(1)
  end
  for _ = 1, 30 do
    if FieldView.cameraPanY == 0 then zero = true break end
    U.wait(1)
  end
  local shook = false
  for _, p in ipairs(pans) do
    if p ~= 0 then shook = true end
  end
  U.log("camera pan samples: " .. table.concat(pans, ","))
  result(shook, "the fall landing shakes the camera")
  result(zero, "and the camera settles back at 0")

  finish()
end
