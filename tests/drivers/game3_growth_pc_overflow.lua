local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_growth_pc_overflow"

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
    print("PASS growth_pc_overflow")
    love.event.quit(0)
  else
    print("FAIL growth_pc_overflow failures=" .. failures)
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
  local Queries = require("src.core.game3.scripting.natives_queries")
  local Std = require("src.core.game3.scripting.stdscripts")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function getFlag(id) return Flags.getFlag(Space.store, ctx(), id) end

  session.party = {}
  for _ = 1, 6 do Party.giveMon(session, CHARMANDER, 8) end
  if not result(#session.party == 6, "the party is full (6)") then return finish() end

  local storage = Storage.ensure(session)
  storage.currentBox = 1
  for s = 1, Storage.IN_BOX_COUNT do
    local code = Party.giveMonToPlayer(session, PIDGEY, 3)
    if code ~= Party.MON_GIVEN_TO_PC then break end
  end
  result(Storage.countBoxMons(storage, 1) == Storage.IN_BOX_COUNT,
    "BOX 1 is full (" .. Storage.countBoxMons(storage, 1) .. "/" .. Storage.IN_BOX_COUNT .. ")")
  result(getVar(VAR_PC_BOX_TO_SEND_MON) == 0,
    "VAR_PC_BOX_TO_SEND_MON still points at BOX 1 (0-based 0)")
  Flags.setFlag(Space.store, ctx(), FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true)

  Bag.add(session.bag, ITEM_MASTER_BALL, 1)
  if not result(Bag.has(session.bag, ITEM_MASTER_BALL, 1), "the bag holds a MASTER BALL") then
    return finish()
  end

  local ok, err = BattleBridge.startWild(Runtime._mod, game,
    { species = MAGIKARP, level = 5 }, { fade = false })
  if not result(ok == true, "wild MAGIKARP battle started " .. tostring(err or "")) then
    return finish()
  end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local Message = require("src.ui.game3.message")
  local wanted = {
    { match = "caught", name = "02_caught", done = false },
    { match = "transferred", name = "03_sent_to_pc", done = false },
  }
  local pages, pageSeen = {}, {}
  local function shot_message()
    if not (Message.isOpen and Message.isOpen()) then return false end
    if Message.isTyping and Message.isTyping() then return false end
    local page = Message.currentPage() or ""
    if page ~= "" and not pageSeen[page] then
      pageSeen[page] = true
      pages[#pages + 1] = page
    end
    for _, w in ipairs(wanted) do
      if not w.done and page:find(w.match, 1, true) then
        w.done = true
        U.shot(game, DIR .. "/growth_pc_overflow_" .. w.name .. ".png")
        return true
      end
    end
    return false
  end

  local thrown = false
  local lastTap, f = 0, 0
  for _ = 1, 9000 do
    f = f + 1
    if not Battle.isActive() then break end
    if at_command() and not thrown then
      thrown = true
      U.shot(game, DIR .. "/growth_pc_overflow_01_command.png")
      U.tap(game, "right")
      U.wait(20)
      U.tap(game, "a")
      U.wait(90)
      local BagMenu = require("src.ui.game3.bag_menu")
      for _ = 1, 6 do
        if BagMenu.currentPocket() == "POKE_BALLS" then break end
        U.tap(game, "right")
        U.wait(40)
      end
      result(BagMenu.currentPocket() == "POKE_BALLS",
        "the bag menu reached the POKE BALLS pocket")
      U.tap(game, "a")
      U.wait(40)
      U.tap(game, "a")
      U.wait(40)
      lastTap = f
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    elseif shot_message() then
      U.wait(1)
    elseif f - lastTap >= 24 then
      lastTap = f
      U.tap(game, Battle._phase == "catch_nickname_prompt" and "b" or "a")
    else
      U.wait(1)
    end
  end
  for _, w in ipairs(wanted) do
    result(w.done, "the battle showed the '" .. w.match .. "' line")
  end
  result(not Battle.isActive(), "the battle ended")
  U.wait(120)

  result(#session.party == 6, "the party is still 6")
  result(Storage.countBoxMons(storage, 1) == Storage.IN_BOX_COUNT, "BOX 1 is still full")
  local boxed = storage.boxes[2] and storage.boxes[2].mons[1]
  result(boxed ~= nil and tonumber(boxed.species or boxed.speciesId) == MAGIKARP,
    "the caught MAGIKARP spilled over into BOX 2 slot 1")
  result(getVar(VAR_PC_BOX_TO_SEND_MON) == 1,
    "VAR_PC_BOX_TO_SEND_MON now names BOX 2 (0-based 1), was "
      .. tostring(getVar(VAR_PC_BOX_TO_SEND_MON)))
  -- pokefirered/src/field_specials.c:1991
  result(getFlag(FLAG_SHOWN_BOX_WAS_FULL_MESSAGE) == true,
    "Cmd_givecaughtmon spent ShouldShowBoxWasFullMessage and left the flag SET")
  result(Queries.pcBoxToSendMon == 0,
    "GetPCBoxToSendMon still names BOX 1, the box it was going to")

  local sentBox = Storage.getBox(storage, getVar(VAR_PC_BOX_TO_SEND_MON) + 1)
  local fullBox = Storage.getBox(storage, Queries.pcBoxToSendMon + 1)
  result(sentBox ~= nil and sentBox.name == "BOX 2",
    "BOX 2 is the box it went to (" .. tostring(sentBox and sentBox.name) .. ")")
  result(fullBox ~= nil and fullBox.name == "BOX 1",
    "and BOX 1 is the box that was full (" .. tostring(fullBox and fullBox.name) .. ")")

  local flat = {}
  for i, p in ipairs(pages) do flat[i] = (p:gsub("\n", " ")) end
  flat = table.concat(flat, " | ")
  local function battle_page(needle)
    for _, p in ipairs(pages) do
      if p:find(needle, 1, true) then return true end
    end
    return false
  end
  -- pokefirered/data/text/pc_transfer.inc:13
  result(battle_page("BOX “BOX 1” on\nSomeone's PC was full."),
    "the battle's box-was-full page names BOX 1: " .. flat)
  result(battle_page("MAGIKARP was transferred to\nBOX “BOX 2.”"),
    "and BOX 2 as where MAGIKARP went")
  local should = Queries.HANDLERS[Std.SPECIAL.ShouldShowBoxWasFullMessage]
  local _, v2 = should(ctx())
  result(v2 == 0, "and it only says so once")
  local again = Storage.pcTransferMessage(session, "MAGIKARP")
  result(again:find("was full", 1, true) == nil,
    "the next transfer says Someone's PC instead: " .. again:gsub("\n", " "):gsub("\f", " | "))

  finish()
end
