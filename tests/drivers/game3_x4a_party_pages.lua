local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_x4a_party_pages"

local CHARMANDER, PIDGEY, MAGIKARP = 4, 16, 129
-- pokefirered/include/constants/items.h:305
local ITEM_TM06 = 294
-- pokefirered/include/constants/items.h:49
local ITEM_SACRED_ASH = 45
local ITEM_MASTER_BALL = 1
-- pokefirered/include/constants/vars.h:105
local VAR_PC_BOX_TO_SEND_MON = 0x4037
-- pokefirered/include/constants/flags.h:1401
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS x4a_party_pages")
    love.event.quit(0)
  else
    print("FAIL x4a_party_pages failures=" .. failures)
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
  local Pokemon = require("src.core.game3.pokemon")
  local Bag = require("src.core.game3.bag")
  local Storage = require("src.core.game3.storage")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Flags = require("src.core.game3.scripting.flags")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function waitFor(fn, budget)
    for _ = 1, (budget or 600) do
      if fn() then return true end
      U.wait(1)
    end
    return fn() and true or false
  end

  session.party = {}
  local _, _, lead = Party.giveMon(session, CHARMANDER, 12)
  lead.moves = { lead.moves[1] }
  Party.giveMon(session, PIDGEY, 5)
  Party.giveMon(session, PIDGEY, 5)

  Bag.add(session.bag, ITEM_TM06, 1)
  PartyMenu.show(session.party, nil, { session = session, bag = session.bag, item = ITEM_TM06, mode = "use" })
  U.wait(30)
  U.tap(game, "a")
  U.wait(10)
  result(PartyMenu.mode == "message", "TM06 on a mon with a free slot goes straight to a message, mode="
    .. tostring(PartyMenu.mode))
  local learned = PartyMenu._messageText or ""
  result(learned:find("learned", 1, true) ~= nil and learned:find("TOXIC", 1, true) ~= nil,
    "gText_PkmnLearnedMove3: " .. learned)
  result(Pokemon.knowsMove(lead, 92), "CHARMANDER knows TOXIC")
  U.wait(30)
  U.shot(game, DIR .. "/x4a_tm_learned_no_yesno.png")
  U.tap(game, "a")
  waitFor(function() return not PartyMenu.isOpen() end, 120)
  result(not PartyMenu.isOpen(), "the party menu closed after the TM was taught")
  U.wait(20)

  for i = 2, 3 do session.party[i].hp = 0 end
  Bag.add(session.bag, ITEM_SACRED_ASH, 1)
  PartyMenu.show(session.party, nil, { session = session, bag = session.bag, item = ITEM_SACRED_ASH, mode = "use" })
  U.wait(30)
  U.tap(game, "a")
  waitFor(function() return PartyMenu.mode == "message" end, 300)
  local page1 = PartyMenu._messageText or ""
  result(PartyMenu.mode == "message" and page1:find("\f", 1, true) == nil and page1:find("PIDGEY", 1, true) ~= nil,
    "Sacred Ash page 1 is one mon's line: " .. page1)
  U.wait(20)
  U.shot(game, DIR .. "/x4a_sacred_ash_page1.png")
  U.tap(game, "a")
  U.wait(10)
  local page2 = PartyMenu._messageText or ""
  result(PartyMenu.mode == "message" and page2:find("PIDGEY", 1, true) ~= nil,
    "A pages to the second revived mon: " .. page2)
  U.wait(20)
  U.shot(game, DIR .. "/x4a_sacred_ash_page2.png")
  U.tap(game, "a")
  waitFor(function() return not PartyMenu.isOpen() end, 120)
  result(not PartyMenu.isOpen(), "the last page closes the party menu")
  result(session.party[2].hp > 0 and session.party[3].hp > 0, "both PIDGEY were revived")
  U.wait(20)

  local Battle = require("src.core.game3.battle")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Naming = require("src.ui.game3.naming")
  local BagMenu = require("src.ui.game3.bag_menu")

  while #session.party < 6 do Party.giveMon(session, PIDGEY, 5) end
  local storage = Storage.ensure(session)
  storage.currentBox = 1
  for s = 1, Storage.IN_BOX_COUNT do
    storage.boxes[1].mons[s] = { species = PIDGEY, speciesId = PIDGEY, level = 5, hp = 19, maxHp = 19 }
  end
  local store = require("src.core.game3.scripting.space").store or session.store
  Flags.setVar(store, nil, VAR_PC_BOX_TO_SEND_MON, 0)
  Flags.setFlag(store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
  result(Storage.countTotalMons(storage) == Storage.IN_BOX_COUNT, "BOX 1 is full")

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = MAGIKARP, level = 5 }, { fade = false })
  if not result(ok == true, "a wild MAGIKARP battle started") then return finish() end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local thrown, typed, shotDone = false, false, false
  local lastTap, f = 0, 0
  for _ = 1, 14000 do
    f = f + 1
    if not Battle.isActive() then break end
    if at_command() and not thrown then
      thrown = true
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
      lastTap = f
    elseif Naming.isOpen() then
      local st = Naming._state
      if st and st.pcPages then
        if not shotDone then
          shotDone = true
          U.wait(30)
          local p1 = st.pcPages[1] or ""
          local p2 = st.pcPages[2] or ""
          result(#st.pcPages == 2, "the sent-to-PC text has two pages (" .. #st.pcPages .. ")")
          -- pokefirered/src/naming_screen.c:745
          -- pokefirered/src/field_specials.c:1999
          result(p1:find("was full", 1, true) ~= nil and p1:find("BOX 1", 1, true) ~= nil,
            "page 1 blames the full BOX 1 the send target pointed at: " .. p1:gsub("\n", " "))
          U.shot(game, DIR .. "/x4a_naming_box_full_page1.png")
          U.tap(game, "a")
          U.wait(30)
          result(p2:find("transferred to", 1, true) ~= nil and p2:find("BOX 2", 1, true) ~= nil,
            "page 2 names the box it went to: " .. p2:gsub("\n", " "))
          U.shot(game, DIR .. "/x4a_naming_box_full_page2.png")
          U.tap(game, "a")
          U.wait(20)
        else
          U.wait(1)
        end
      elseif not typed then
        typed = true
        U.wait(20)
        U.tap(game, "a")
        U.wait(12)
        U.tap(game, "start")
        U.wait(20)
        U.tap(game, "a")
        U.wait(20)
      else
        U.wait(1)
      end
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    elseif f - lastTap >= 24 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  result(shotDone, "the naming screen showed the sent-to-PC pages")
  local landed = storage.boxes[2] and storage.boxes[2].mons[1]
  result(landed ~= nil and tonumber(landed.species or landed.speciesId) == MAGIKARP,
    "the named MAGIKARP landed in BOX 2 slot 1")
  finish()
end
