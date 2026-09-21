local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuif_naming_pc"

local CHARMANDER, MAGIKARP = 4, 129
local ITEM_MASTER_BALL = 1

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchuif_naming_pc")
    love.event.quit(0)
  else
    print("FAIL stitchuif_naming_pc failures=" .. failures)
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
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Naming = require("src.ui.game3.naming")
  local BagMenu = require("src.ui.game3.bag_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  for _ = 1, 6 do Party.giveMon(session, CHARMANDER, 8) end
  if not result(#session.party == 6, "the party is full (6)") then return finish() end
  local storage = Storage.ensure(session)
  storage.currentBox = 1

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

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = MAGIKARP, level = 5 },
    { fade = false })
  if not result(ok == true, "a wild MAGIKARP battle started") then return finish() end

  local seenPages = {}
  local typedName = ""
  local thrown, typed, shotDone, closed = false, false, false, false
  local lastTap, f = 0, 0
  for _ = 1, 14000 do
    f = f + 1
    if not Battle.isActive() then break end
    if at_command() and not thrown then
      thrown = true
      throw_master_ball()
      lastTap = f
    elseif Naming.isOpen() then
      local st = Naming._state
      if st and st.pcPages then
        if not shotDone then
          shotDone = true
          U.shot(game, DIR .. "/stitchuif_naming_pc_02_transfer_message.png")
          local page = st.pcPages[st.pcPage] or ""
          result(page:find("transferred to", 1, true) ~= nil,
            "the naming screen prints the transfer line (" .. page .. ")")
          result(typedName ~= "" and page:find(typedName, 1, true) ~= nil,
            "and it uses the nickname that was just typed (" .. typedName .. ")")
          U.tap(game, "a")
          U.wait(20)
          local page2 = (Naming._state and Naming._state.pcPages
            and Naming._state.pcPages[Naming._state.pcPage]) or ""
          result(page2:find("BOX", 1, true) ~= nil,
            "the second page names the box (" .. page2 .. ")")
          U.shot(game, DIR .. "/stitchuif_naming_pc_03_box_page.png")
          U.tap(game, "a")
          U.wait(20)
          closed = not Naming.isOpen()
          result(closed, "A on the last page closed the naming screen")
        else
          U.wait(1)
        end
      elseif not typed then
        typed = true
        U.wait(20)
        for _ = 1, 3 do
          U.tap(game, "a")
          U.wait(12)
        end
        U.shot(game, DIR .. "/stitchuif_naming_pc_01_keyboard.png")
        typedName = (Naming._state and Naming._state.name) or ""
        U.tap(game, "start")
        U.wait(20)
        U.tap(game, "a")
        U.wait(20)
      else
        U.wait(1)
      end
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    else
      if Message.isOpen() and not Message.isTyping() then
        local page = Message.currentPage() or ""
        if page ~= "" then seenPages[#seenPages + 1] = page end
      end
      if f - lastTap >= 24 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
  end

  result(typed, "the naming keyboard opened and OK was pressed")
  result(shotDone, "the sent-to-PC message appeared on the naming screen")
  result(not Battle.isActive(), "the battle ended")

  local leaked = nil
  for _, p in ipairs(seenPages) do
    if p:find("transferred", 1, true) then leaked = p end
  end
  result(leaked == nil,
    "the battle text box never printed the transfer line (" .. tostring(leaked) .. ")")

  local boxed = storage.boxes[1] and storage.boxes[1].mons[1]
  result(boxed ~= nil and tonumber(boxed.species or boxed.speciesId) == MAGIKARP,
    "the MAGIKARP reached BOX 1 slot 1")
  result(boxed ~= nil and type(boxed.nickname) == "string" and #boxed.nickname > 0,
    "and kept the typed nickname (" .. tostring(boxed and boxed.nickname) .. ")")

  U.wait(90)
  finish()
end
