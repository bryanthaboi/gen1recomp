-- engine/items/item_effects.asm:1954
-- engine/battle/core.asm:2520
-- Not under POKEPORT_SPEED: SFX_HEAL_AILMENT rides the real-time audio clock.
--   POKEPORT_DRIVER=tests/drivers/pp_restore_menu_2155_2158.lua \
--     POKEPORT_IDENTITY=pp2155 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots2155 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local ItemEffects = require("src.inventory.ItemEffects")
  local PartyMenu = require("src.ui.PartyMenu")
  local MoveSelectMenu = require("src.ui.MoveSelectMenu")
  local TextBox = require("src.render.TextBox")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function top() return game.stack:top() end
  local function isPicker(s)
    return s ~= nil and (s.screenId == "PartyMenu" or getmetatable(s) == PartyMenu)
  end
  local function isMoveMenu(s) return getmetatable(s) == MoveSelectMenu end
  local function isBox(s) return getmetatable(s) == TextBox end
  local function inStack(pred)
    for _, s in ipairs(game.stack.states or {}) do
      if pred(s) then return true end
    end
    return false
  end

  U.log("======== #2155/#2158 PP restore: machine checks ========")
  for _, id in ipairs({ "ELIXER", "MAX_ELIXER", "ETHER", "MAX_ETHER", "PP_UP" }) do
    check(id .. " keeps the party menu drawn",
          ItemEffects.keepsPartyMenuOpen(id) == true)
    check(id .. " resolves in the item table", game.data.items[id] ~= nil)
  end
  check("MoveSelectMenu draws", type(MoveSelectMenu.draw) == "function")

  local lead = Pokemon.new(game.data, "CHARIZARD", 50)
  local topped = Pokemon.new(game.data, "SNORLAX", 40)
  for _, mv in ipairs(lead.moves) do mv.pp = 1 end
  game.save.party = { lead, topped }
  game.save.player.name = "RED"
  for _, id in ipairs({ "ELIXER", "MAX_ELIXER", "ETHER", "MAX_ETHER" }) do
    Bag.add(game.save, id, 5)
  end
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  local function cursorTo(menu, want)
    for _ = 1, 40 do
      if not menu or menu.index == want then return menu and menu.index == want end
      U.tap(game, menu.index < want and "down" or "up")
      U.wait(3)
    end
    return menu.index == want
  end

  local function openPickerFor(id)
    U.tap(game, "start")
    U.wait(10)
    local menu = top()
    if not (menu and menu.screenId == "StartMenu") then
      return nil, "start menu never opened"
    end
    local itemRow
    for i, it in ipairs(menu.items or {}) do
      if it.label == "ITEM" then itemRow = i break end
    end
    if not itemRow or not cursorTo(menu, itemRow) then return nil, "no ITEM row" end
    U.tap(game, "a")
    U.wait(10)
    local bag = top()
    if not (bag and bag.screenId == "BagMenu") then return nil, "bag never opened" end
    local bagRow
    for i, r in ipairs(bag.items or {}) do
      if r.value == id then bagRow = i break end
    end
    if not bagRow or not cursorTo(bag, bagRow) then return nil, id .. " not in bag" end
    U.tap(game, "a")
    U.wait(10)
    local ut = top()
    if ut and ut.items and ut.items[1] and ut.items[1].label == "USE" then
      if not cursorTo(ut, 1) then return nil, "USE row unreachable" end
      U.tap(game, "a")
      U.wait(10)
    end
    local picker = top()
    if not isPicker(picker) then return nil, "party picker never opened" end
    return picker
  end

  local function backToOverworld()
    for _ = 1, 30 do
      if top() == game.overworld then return true end
      U.tap(game, "b")
      U.wait(6)
    end
    return top() == game.overworld
  end

  local function dismiss()
    for _ = 1, 30 do
      if not inStack(isPicker) then break end
      U.tap(game, "a")
      U.wait(8)
    end
  end

  local function waitForBag()
    for _ = 1, 60 do
      local t = top()
      if t ~= nil and t.screenId == "BagMenu" then break end
      U.wait(1)
    end
  end

  U.log("======== #2155 ELIXER: SFX_HEAL_AILMENT over a live party menu ========")
  local picker, why = openPickerFor("ELIXER")
  check("party picker opened for ELIXER" .. (why and (" (" .. why .. ")") or ""),
        picker ~= nil)
  if picker then
    check("keepOpen is set for the ELIXERs", picker.keepOpen == true)
    cursorTo(picker, 1)
    U.tap(game, "a")
    U.wait(6)
    check("the party menu is still on the stack after the pick", inStack(isPicker))
    -- engine/items/item_effects.asm:2022
    check("the cursor is still drawn", picker.cursorsErased ~= true)
    for _ = 1, 60 do
      if isBox(top()) then break end
      U.wait(1)
    end
    check("the PP restored box opened", isBox(top()))
    check("...over the STILL-drawn party menu", inStack(isPicker))
    check("every slot came back up", lead.moves[1].pp > 1)
    U.log("LISTEN", "SFX_HEAL_AILMENT should have played as the box opened")
    U.wait(60)
    U.shot(game, DIR .. "/pp2155_elixir_message_over_party.png")
    dismiss()
    check("the picker is gone once the message is dismissed", not inStack(isPicker))
    -- pokered engine/items/item_effects.asm:1244
    waitForBag()
    check("and we are back on the ITEM list",
          top() ~= nil and top().screenId == "BagMenu")
  end
  backToOverworld()

  U.log("======== #2155 MAX ELIXER refusal prints over the party menu ========")
  local refuse = openPickerFor("MAX_ELIXER")
  if check("party picker opened for MAX ELIXER", refuse ~= nil) then
    cursorTo(refuse, 2) -- the untouched SNORLAX
    U.tap(game, "a")
    U.wait(6)
    for _ = 1, 60 do
      if isBox(top()) then break end
      U.wait(1)
    end
    check("the no-effect box opened", isBox(top()))
    check("...over the STILL-drawn party menu", inStack(isPicker))
    U.wait(60)
    U.shot(game, DIR .. "/pp2155_max_elixir_no_effect.png")
    dismiss()
  end
  backToOverworld()

  U.log("======== #2158 ETHER: wMoveMenuType 2 window over the party menu ========")
  for _, mv in ipairs(lead.moves) do mv.pp = 1 end
  local ether = openPickerFor("ETHER")
  if check("party picker opened for ETHER", ether ~= nil) then
    check("keepOpen is set for the ETHERs", ether.keepOpen == true)
    cursorTo(ether, 1)
    U.tap(game, "a")
    U.wait(8)
    check("the move window is the top state", isMoveMenu(top()))
    check("...with the party menu still drawn underneath", inStack(isPicker))
    U.wait(20)
    U.shot(game, DIR .. "/pp2158_ether_move_window.png")

    -- engine/items/item_effects.asm:1985
    U.tap(game, "b")
    U.wait(8)
    check("B goes back to the party menu", isPicker(top()))
    U.tap(game, "a")
    U.wait(8)
    check("and the move window opens again", isMoveMenu(top()))

    local before = lead.moves[1].pp
    U.tap(game, "a")
    U.wait(6)
    for _ = 1, 60 do
      if isBox(top()) then break end
      U.wait(1)
    end
    check("the PP restored box opened", isBox(top()))
    check("...over the STILL-drawn party menu", inStack(isPicker))
    check("the picked move gained PP", lead.moves[1].pp > before)
    U.log("LISTEN", "SFX_HEAL_AILMENT should have played for the ETHER too")
    U.wait(60)
    U.shot(game, DIR .. "/pp2158_ether_message_over_party.png")
    dismiss()
    -- pokered engine/items/item_effects.asm:1244
    waitForBag()
    check("back on the ITEM list", top() ~= nil and top().screenId == "BagMenu")
  end
  backToOverworld()

  U.log("======== #2158 MAX ETHER refusal keeps both windows up ========")
  local maxEther = openPickerFor("MAX_ETHER")
  if check("party picker opened for MAX ETHER", maxEther ~= nil) then
    cursorTo(maxEther, 2) -- the untouched SNORLAX
    U.tap(game, "a")
    U.wait(8)
    check("the move window opened", isMoveMenu(top()))
    U.tap(game, "a")
    U.wait(6)
    for _ = 1, 60 do
      if isBox(top()) then break end
      U.wait(1)
    end
    check("the no-effect box opened", isBox(top()))
    check("...over the STILL-drawn party menu", inStack(isPicker))
    U.wait(60)
    U.shot(game, DIR .. "/pp2158_max_ether_no_effect.png")
    dismiss()
  end
  backToOverworld()

  U.log(("======== PP restore driver: %d passed, %d failed ========")
          :format(pass, fail))
  U.log(fail == 0 and "DRIVER PASS" or "DRIVER FAIL")

  for _, mv in ipairs(lead.moves) do mv.pp = 1 end
  local handoff = openPickerFor("ETHER")
  if handoff then
    cursorTo(handoff, 1)
    U.tap(game, "a")
    U.wait(8)
  end
  U.log("The ETHER move window is open over the party menu. Compare it with")
  U.log("shots/issue_2158_1.png: a 16x6 box at tile 4,7, four names single")
  U.log("spaced with '-' for empty slots, no PP column, cursor at column 5,")
  U.log("and 'Restore PP of / which technique?' in the bottom box. B returns")
  U.log("to the party menu; A restores PP with the Heal_Ailment jingle.")

  while true do
    coroutine.yield()
  end
end
