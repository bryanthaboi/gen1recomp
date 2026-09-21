local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuif_boxsend"

local CENTER = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
-- pokefirered/include/constants/metatile_behaviors.h:135
local MB_PC = 0x83
-- pokefirered/include/constants/vars.h:105
local VAR_PC_BOX_TO_SEND_MON = 0x4037
-- pokefirered/include/constants/flags.h:1401
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843

local CHARMANDER, MAGIKARP, PIDGEY = 4, 129, 16
local ITEM_MASTER_BALL = 1

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchuif_boxsend")
    love.event.quit(0)
  else
    print("FAIL stitchuif_boxsend failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Bag = require("src.core.game3.bag")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Collision = require("src.core.game3.collision")
  local PcMenu = require("src.ui.game3.pc_menu")
  local BoxStorageUI = require("src.ui.game3.box_storage_ui")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local BagMenu = require("src.ui.game3.bag_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function getFlag(id) return Flags.getFlag(Space.store, ctx(), id) and true or false end

  session.party = {}
  for _ = 1, 6 do Party.giveMon(session, CHARMANDER, 8) end
  local storage = Storage.ensure(session)
  storage.currentBox = 2
  for _ = 1, Storage.IN_BOX_COUNT do
    if Party.giveMonToPlayer(session, PIDGEY, 3) ~= Party.MON_GIVEN_TO_PC then break end
  end
  storage.currentBox = 1
  if not result(Storage.countBoxMons(storage, 2) == Storage.IN_BOX_COUNT,
    "BOX 2 is full (" .. Storage.countBoxMons(storage, 2) .. "/" .. Storage.IN_BOX_COUNT .. ")") then
    return finish()
  end
  Flags.setVar(Space.store, ctx(), VAR_PC_BOX_TO_SEND_MON, 0)
  Flags.setFlag(Space.store, ctx(), FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)

  Map.load(nil, game, CENTER, { x = 3, y = 4, facing = "down" })
  session.x, session.y, session.facing = 3, 4, "down"
  Player.cellX, Player.cellY = 3, 4
  Player.px, Player.py = 3 * 16, 4 * 16
  Player.targetX, Player.targetY = 3, 4
  U.wait(120)

  local px, py
  local def = Map.currentDef and Map.currentDef()
  local layout = def and def.midLayout
  for cy = 0, (layout and layout.height or 0) - 1 do
    for cx = 0, (layout and layout.width or 0) - 1 do
      if Collision.behavior(cx, cy) == MB_PC then px, py = cx, cy end
    end
  end
  if not result(px ~= nil, "the Pokemon Center has an MB_PC tile") then return finish() end
  U.log(string.format("[driver] PC tile at (%d,%d)", px, py))

  Player.cellX, Player.cellY = px, py + 1
  Player.px, Player.py = px * 16, (py + 1) * 16
  Player.targetX, Player.targetY = px, py + 1
  Player.facing = "up"
  session.x, session.y, session.facing = px, py + 1, "up"
  U.wait(60)

  local opened = false
  for _ = 1, 14 do
    U.tap(game, "a")
    U.wait(30)
    if PcMenu.isOpen and PcMenu.isOpen() then opened = true break end
  end
  if not result(opened, "talking to the PC opened the PC menu") then return finish() end
  U.wait(20)
  U.shot(game, DIR .. "/stitchuif_boxsend_01_pc_menu.png")

  -- pokefirered/src/pokemon_storage_system_tasks.c:426
  U.tap(game, "a")
  U.wait(30)
  result(PcMenu.mode == "storage_menu", "SOMEONE'S PC opened the storage menu")
  for _ = 1, 2 do
    U.tap(game, "down")
    U.wait(12)
  end
  U.tap(game, "a")
  U.wait(40)
  if not result(BoxStorageUI.isOpen(), "the box screen opened") then return finish() end
  result(storage.currentBox == 1, "the box screen opened on BOX 1")

  U.tap(game, "up")
  U.wait(24)
  result(BoxStorageUI.cursorSlot == 0, "the cursor reached the box title header")
  U.tap(game, "right")
  U.wait(30)
  result(storage.currentBox == 2, "the header arrow scrolled to the full BOX 2")
  result(getVar(VAR_PC_BOX_TO_SEND_MON) == 0,
    "the send target is still BOX 1 while the screen is up")
  U.shot(game, DIR .. "/stitchuif_boxsend_02_box2_full.png")

  U.tap(game, "b")
  U.wait(40)
  result(not BoxStorageUI.isOpen(), "B left the box screen")
  result(getVar(VAR_PC_BOX_TO_SEND_MON) == 1,
    "leaving on BOX 2 moved the send target (got " .. getVar(VAR_PC_BOX_TO_SEND_MON) .. ")")
  result(getFlag(FLAG_SHOWN_BOX_WAS_FULL_MESSAGE) == false,
    "and cleared FLAG_SHOWN_BOX_WAS_FULL_MESSAGE")

  for _ = 1, 10 do
    if not (PcMenu.isOpen and PcMenu.isOpen()) then break end
    U.tap(game, "b")
    U.wait(24)
  end
  for _ = 1, 20 do
    if not Message.isOpen() then break end
    U.tap(game, "a")
    U.wait(20)
  end
  U.wait(60)

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = MAGIKARP, level = 5 },
    { fade = false })
  if not result(ok == true, "a wild MAGIKARP battle started") then return finish() end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function throw_master_ball()
    Bag.add(session.bag, ITEM_MASTER_BALL, 1)
    U.tap(game, "right")
    U.wait(20)
    U.tap(game, "a")
    U.wait(90)
    for _ = 1, 6 do
      if BagMenu.currentPocket() == "POKE_BALLS" then break end
      U.tap(game, "right")
      U.wait(40)
    end
    U.tap(game, "a")
    U.wait(40)
    U.tap(game, "a")
    U.wait(40)
  end

  local wanted = { match = "was full", done = false }
  local seen = {}
  local thrown, lastTap, f = false, 0, 0
  for _ = 1, 12000 do
    f = f + 1
    if not Battle.isActive() then break end
    if at_command() and not thrown then
      thrown = true
      throw_master_ball()
      lastTap = f
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    else
      if Message.isOpen() and not Message.isTyping() then
        local page = Message.currentPage() or ""
        if page ~= "" then
          seen[#seen + 1] = page
          if not wanted.done and page:find(wanted.match, 1, true) then
            wanted.done = true
            U.shot(game, DIR .. "/stitchuif_boxsend_03_box2_was_full.png")
            result(page:find("BOX 2", 1, true) ~= nil,
              "the full box named on screen is BOX 2 (" .. page .. ")")
            result(page:find("BOX 1", 1, true) == nil,
              "the empty BOX 1 is not blamed")
          end
        end
      end
      if f - lastTap >= 24 then
        lastTap = f
        U.tap(game, Battle._phase == "catch_nickname_prompt" and "b" or "a")
      else
        U.wait(1)
      end
    end
  end

  result(wanted.done, "the catch printed a box-was-full page")
  local placed = nil
  for _, p in ipairs(seen) do
    if p:find("transferred to", 1, true) then placed = p end
  end
  result(placed ~= nil and placed:find("BOX 3", 1, true) ~= nil,
    "the MAGIKARP is announced into BOX 3 (" .. tostring(placed) .. ")")
  local boxed = storage.boxes[3] and storage.boxes[3].mons[1]
  result(boxed ~= nil and tonumber(boxed.species or boxed.speciesId) == MAGIKARP,
    "and it really landed in BOX 3 slot 1")

  U.wait(90)
  finish()
end
