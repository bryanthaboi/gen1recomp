local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_link_counter"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local COLOSSEUM_2P = "FR_BATTLE_COLOSSEUM_2P"
-- pokefirered/include/constants/flags.h:1375 FLAG_SYS_POKEDEX_GET
local FLAG_SYS_POKEDEX_GET = 0x829
-- pokefirered/include/constants/vars.h:328
local VAR_RESULT = 0x800D

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS link_counter")
    love.event.quit(0)
  else
    print("FAIL link_counter failures=" .. failures)
    love.event.quit(1)
  end
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Link = require("src.core.game3.link")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function mapId() return Space.mapId end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(90)
  end

  local function busy()
    return (Space.vm and Space.vm:isRunning())
      or (Message.isOpen and Message.isOpen())
      or Choice.active or SaveMenu.isOpen()
  end

  local function advance(frames)
    local ticks = 0
    while ticks < (frames or 300) do
      if Choice.active or SaveMenu.isOpen() then return end
      if not busy() then return end
      U.tap(game, "a")
      U.wait(10)
      ticks = ticks + 10
    end
  end

  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  goTo(CENTER_2F, 10, 4, "up")
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  U.shot(game, DIR .. "/link_counter_01_cable_club_counter.png")

  local function talkToAttendant()
    place(10, 4, "up")
    U.wait(12)
    U.tap(game, "a")
    U.wait(30)
    return busy()
  end

  local spoke = talkToAttendant()
  if not result(spoke, "the cable club attendant answers") then
    U.shot(game, DIR .. "/link_counter_99_no_answer.png")
    return finish()
  end

  advance(400)
  local sawRoomChoice = Choice.active and true or false
  result(sawRoomChoice, "IsWirelessAdapterConnected routed the player into the wired cable club menu")
  U.shot(game, DIR .. "/link_counter_02_service_menu.png")

  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "a")
  U.wait(40)
  advance(300)
  local sawModeChoice = Choice.active and true or false
  result(sawModeChoice, "the colosseum battle mode menu opened")
  U.tap(game, "a")
  U.wait(60)

  local promptFrames = 0
  while promptFrames < 600 and not SaveMenu.isOpen() do
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(10)
    promptFrames = promptFrames + 10
  end
  if not result(SaveMenu.isOpen(), "Field_AskSaveTheGame put the save prompt up") then
    U.shot(game, DIR .. "/link_counter_98_no_save_prompt.png")
    return finish()
  end
  U.wait(20)
  U.shot(game, DIR .. "/link_counter_03_save_prompt.png")

  U.tap(game, "b")
  U.wait(40)
  result(not SaveMenu.isOpen(), "answering NO closed the save prompt")
  result(getVar(VAR_RESULT) == 0, "the script saw FALSE, which aborts the link")
  U.wait(60)
  result(Message.isOpen and Message.isOpen(),
    "CloseLink ran and the attendant is turning the player away")
  U.shot(game, DIR .. "/link_counter_04_link_aborted.png")
  result(Link.link == nil, "no link session was left open")
  advance(400)
  U.wait(60)

  local spokeAgain = talkToAttendant()
  if not result(spokeAgain, "the counter can be used again after an abort") then
    return finish()
  end
  advance(400)
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "a")
  U.wait(40)
  advance(300)
  U.tap(game, "a")
  U.wait(60)

  promptFrames = 0
  while promptFrames < 600 and not SaveMenu.isOpen() do
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(10)
    promptFrames = promptFrames + 10
  end
  if not result(SaveMenu.isOpen(), "the save prompt came back on the second run") then
    return finish()
  end
  U.tap(game, "a")
  U.wait(30)
  U.shot(game, DIR .. "/link_counter_05_save_overwrite.png")
  U.tap(game, "a")
  U.wait(60)
  U.tap(game, "a")
  U.wait(40)
  result(getVar(VAR_RESULT) == 1, "saving reported TRUE, so the link may continue")

  local waited = 0
  while waited < 900 and mapId() == CENTER_2F do
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(15)
    waited = waited + 15
  end
  U.wait(60)
  local warped = mapId() == COLOSSEUM_2P
  local dyn = session.dynamicWarp
  print("[driver] after the club warp: map=" .. tostring(mapId()) ..
    " return=" .. tostring(dyn and dyn.map) .. " warpId=" .. tostring(dyn and dyn.warpId))
  if warped then
    result(true, "SetCableClubWarp / DoCableClubWarp put the player in the colosseum")
    result(dyn ~= nil and dyn.map == CENTER_2F,
      "the return warp points back at the Pokemon Center 2F")
    U.shot(game, DIR .. "/link_counter_06_colosseum.png")
  else
    result(busy(), "the colosseum entry is waiting on the link-up rather than dead")
    -- pokefirered/src/cable_club.c:222 CreateLinkupTask
    local LinkMenu = require("src.ui.game3.link_menu")
    local LB = require("src.core.game3.link.battle")
    local opened = 0
    while opened < 300 and not LinkMenu.isOpen() do
      U.wait(10)
      opened = opened + 10
    end
    result(LinkMenu.isOpen(),
      "and the counter put the HOST / JOIN screen up so a player can get a cable")
    U.shot(game, DIR .. "/link_counter_06_awaiting_linkup.png")
    result(LB.linkup == 0, "the linkup reports LINKUP_ONGOING, not LINKUP_FAILED")
    local hosting = 0
    while hosting < 300 and LinkMenu.stage ~= "hosting" do
      U.tap(game, "a")
      U.wait(20)
      hosting = hosting + 20
    end
    print("[driver] connect screen: stage=" .. tostring(LinkMenu.stage)
      .. " transport=" .. tostring(LinkMenu._transport ~= nil) .. " link=" .. tostring(Link.link ~= nil))
    U.shot(game, DIR .. "/link_counter_07_hosting.png")
    -- pokefirered/src/link.c:386 OpenLink
    result(LinkMenu.stage == "hosting", "HOST A GAME opens the port and waits for the other GBA")
    result(LinkMenu._transport ~= nil and Link.link == nil,
      "and a real host transport is open, waiting for the other GBA to pair")
    local closing = 0
    while closing < 180 and LinkMenu.isOpen() do
      U.tap(game, "b")
      U.wait(20)
      closing = closing + 20
    end
    result(not LinkMenu.isOpen(), "B backs out of the connect screen")
  end

  -- data/scripts/cable_club.inc:306
  local settle = 0
  while settle < 600 and busy() do
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(10)
    settle = settle + 10
  end
  goTo(CENTER_2F, 9, 2, "up")
  local hideKey, hideIdx
  for key, rows in pairs(Space.vm and Space.vm.scripts or {}) do
    for i, row in ipairs(rows) do
      local nxt = rows[i + 1]
      local warpsAfter = false
      for j = i + 1, i + 8 do
        if rows[j] and rows[j].op == "warp" then warpsAfter = true end
      end
      if row.op == "hideobjectat" and tonumber(row.localId or row[1]) == 0xFF
          and nxt and nxt.op == "closedoor" and warpsAfter then
        hideKey, hideIdx = key, i
        break
      end
    end
    if hideKey then break end
  end
  if result(hideKey ~= nil, "found the cable club hideobjectat LOCALID_PLAYER / closedoor rows") then
    local vctx = Space.vm.ctx
    vctx.mode = "bytecode"
    vctx.status = "running"
    vctx.stack = {}
    Space.vm:setPc(hideKey, hideIdx)
    Space.vm:resume()
    local hiddenAtDoor = mapId() == CENTER_2F and not Player.isVisible()
    result(hiddenAtDoor, "hideobjectat LOCALID_PLAYER hid the player before the door closed")
    U.wait(6)
    if mapId() == CENTER_2F then
      U.shot(game, DIR .. "/link_counter_08_player_hidden_door_close.png")
    end
    local after = 0
    while after < 900 and busy() do
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(10)
      after = after + 10
    end
    U.wait(60)
    print("[driver] after the hidden door close: map=" .. tostring(mapId()))
    result(Player.isVisible(), "the player is visible again once the door-close script is done")
  end

  finish()
end
