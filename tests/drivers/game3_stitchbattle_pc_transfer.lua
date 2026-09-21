local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchbattle_pc_transfer"

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
    print("PASS stitchbattle_pc_transfer")
    love.event.quit(0)
  else
    print("FAIL stitchbattle_pc_transfer failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Bag = require("src.core.game3.bag")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Naming = require("src.ui.game3.naming")
  local BagMenu = require("src.ui.game3.bag_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  session.party = {}
  for _ = 1, 6 do Party.giveMon(session, CHARMANDER, 8) end
  if not result(#session.party == 6, "the party is full (6)") then return finish() end

  local storage = Storage.ensure(session)
  storage.currentBox = 1
  for _ = 1, Storage.IN_BOX_COUNT do
    if Party.giveMonToPlayer(session, PIDGEY, 3) ~= Party.MON_GIVEN_TO_PC then break end
  end
  if not result(Storage.countBoxMons(storage, 1) == Storage.IN_BOX_COUNT,
    "BOX 1 is full (" .. Storage.countBoxMons(storage, 1) .. "/" .. Storage.IN_BOX_COUNT .. ")") then
    return finish()
  end
  Flags.setFlag(Space.store, ctx(), FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
  Flags.setVar(Space.store, ctx(), VAR_PC_BOX_TO_SEND_MON, 0)

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
    result(BagMenu.currentPocket() == "POKE_BALLS", "the bag reached the POKE BALLS pocket")
    U.tap(game, "a")
    U.wait(40)
    U.tap(game, "a")
    U.wait(40)
  end

  -- pokefirered/data/battle_scripts_2.s:87
  local okA = BattleBridge.startWild(Runtime._mod, game, { species = MAGIKARP, level = 5 },
    { fade = false })
  if not result(okA == true, "wild MAGIKARP battle started for the decline pass") then
    return finish()
  end

  local wantedA = {
    { match = "was full", name = "01_box_was_full", done = false },
    { match = "transferred to", name = "02_transferred_to_box2", done = false },
  }
  local seenA = {}
  local function watch_a()
    if not Message.isOpen() then return false end
    if Message.isTyping() then return false end
    local page = Message.currentPage() or ""
    if page ~= "" then seenA[#seenA + 1] = page end
    for _, w in ipairs(wantedA) do
      if not w.done and page:find(w.match, 1, true) then
        w.done = true
        U.shot(game, DIR .. "/stitchbattle_pc_transfer_" .. w.name .. ".png")
        return true
      end
    end
    return false
  end

  local thrown, lastTap, f = false, 0, 0
  for _ = 1, 9000 do
    f = f + 1
    if not Battle.isActive() then break end
    if at_command() and not thrown then
      thrown = true
      throw_master_ball()
      lastTap = f
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    elseif watch_a() then
      U.wait(1)
    elseif f - lastTap >= 24 then
      lastTap = f
      U.tap(game, Battle._phase == "catch_nickname_prompt" and "b" or "a")
    else
      U.wait(1)
    end
  end
  for _, w in ipairs(wantedA) do
    result(w.done, "the declined-nickname catch showed a page matching '" .. w.match .. "'")
  end
  result(not Battle.isActive(), "the decline-pass battle ended")

  local hitGeneric = false
  for _, p in ipairs(seenA) do
    if p:find("to the PC.", 1, true) then hitGeneric = true end
  end
  result(not hitGeneric, "the hand-written 'was transferred to the PC.' page never appeared")
  local boxedA = storage.boxes[2] and storage.boxes[2].mons[1]
  result(boxedA ~= nil and tonumber(boxedA.species or boxedA.speciesId) == MAGIKARP,
    "the MAGIKARP spilled over into BOX 2 slot 1")
  result(getVar(VAR_PC_BOX_TO_SEND_MON) == 1, "VAR_PC_BOX_TO_SEND_MON now names BOX 2")
  U.wait(120)

  -- pokefirered/src/battle_script_commands.c:9853
  local okB = BattleBridge.startWild(Runtime._mod, game, { species = MAGIKARP, level = 6 },
    { fade = false })
  if not result(okB == true, "wild MAGIKARP battle started for the nickname pass") then
    return finish()
  end

  local seenB, namePages = {}, {}
  local named, thrownB, shotPc = false, false, false
  lastTap, f = 0, 0
  for _ = 1, 12000 do
    f = f + 1
    if not Battle.isActive() then break end
    if at_command() and not thrownB then
      thrownB = true
      throw_master_ball()
      lastTap = f
    elseif Naming.isOpen() then
      if not named then
        named = true
        for _ = 1, 3 do
          U.tap(game, "a")
          U.wait(12)
        end
        U.shot(game, DIR .. "/stitchbattle_pc_transfer_03_naming.png")
        U.tap(game, "start")
        U.wait(20)
        U.tap(game, "a")
        U.wait(40)
      else
        -- pokefirered/src/naming_screen.c:732
        local nst = Naming._state
        local page = nst and nst.pcPages and nst.pcPages[nst.pcPage or 1]
        if page and page ~= "" then
          namePages[#namePages + 1] = page
          if not shotPc then
            shotPc = true
            U.shot(game, DIR .. "/stitchbattle_pc_transfer_04_naming_sent_to_pc.png")
          end
        end
        U.tap(game, "a")
        U.wait(16)
      end
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    else
      if Message.isOpen() and not Message.isTyping() then
        local page = Message.currentPage() or ""
        if page ~= "" then seenB[#seenB + 1] = page end
      end
      if f - lastTap >= 24 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
  end
  result(named, "the naming keyboard opened and was confirmed")
  result(not Battle.isActive(), "the nickname-pass battle ended")

  local leaked = nil
  for _, p in ipairs(seenB) do
    if p:find("transferred", 1, true) then leaked = p end
  end
  result(leaked == nil,
    "no transfer page is printed once a nickname is typed (" .. tostring(leaked) .. ")")

  local boxedB = storage.boxes[2] and storage.boxes[2].mons[2]
  result(boxedB ~= nil and tonumber(boxedB.species or boxedB.speciesId) == MAGIKARP,
    "the nicknamed MAGIKARP still reached BOX 2 slot 2")
  local nick = boxedB and boxedB.nickname
  result(type(nick) == "string" and nick ~= "",
    "and it kept the typed nickname (" .. tostring(nick) .. ")")

  local namedTransfer = nil
  for _, p in ipairs(namePages) do
    if p:find("transferred", 1, true) then namedTransfer = p end
  end
  -- pokefirered/src/naming_screen.c:696
  result(namedTransfer ~= nil,
    "the naming screen printed the sent-to-PC page (" .. tostring(namedTransfer) .. ")")
  -- pokefirered/src/naming_screen.c:739
  result(namedTransfer ~= nil and nick ~= nil and nick ~= ""
    and namedTransfer:find(nick, 1, true) ~= nil,
    "and it names the typed nickname " .. tostring(nick))
  result(shotPc, "shot the naming screen's sent-to-PC page")

  U.wait(120)
  finish()
end
