-- home/pokemon.asm:246
-- engine/items/item_effects.asm:1967-2006
-- engine/pokemon/learn_move.asm:119-181
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Bag = require("src.inventory.Bag")
  local PartyMenu = require("src.ui.PartyMenu")
  local MoveSelectMenu = require("src.ui.MoveSelectMenu")
  local MoveLearnMenu = require("src.ui.MoveLearnMenu")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local TextBox = require("src.render.TextBox")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots2320"
  local fail = 0

  local function check(label, ok)
    if not ok then fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function top() return game.stack:top() end
  local function isBox(s) return getmetatable(s) == TextBox end
  local function isParty(s) return getmetatable(s) == PartyMenu end
  local function isMoveMenu(s) return getmetatable(s) == MoveSelectMenu end
  local function isLearn(s) return getmetatable(s) == MoveLearnMenu end
  local function find(pred)
    for _, s in ipairs(game.stack.states or {}) do
      if pred(s) then return s end
    end
  end
  local function boxText(b)
    local out = {}
    for _, page in ipairs((b and b.pages) or {}) do
      for _, l in ipairs(page) do out[#out + 1] = tostring(l) end
    end
    return table.concat(out, " ")
  end
  local function waitFor(pred, n)
    for _ = 1, n or 240 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function cursorTo(menu, want)
    for _ = 1, 40 do
      if menu.index == want then return true end
      U.tap(game, menu.index < want and "down" or "up")
      U.wait(3)
    end
    return menu.index == want
  end

  local gengar = Pokemon.new(game.data, "GENGAR", 30)
  gengar.moves = {
    { id = "LICK", pp = 30 }, { id = "CONFUSE_RAY", pp = 10 },
    { id = "NIGHT_SHADE", pp = 15 }, { id = "HYPNOSIS", pp = 20 },
  }
  local nido = Pokemon.new(game.data, "NIDOKING", 40)
  nido.moves = {
    { id = "SURF", pp = 15 }, { id = "HORN_ATTACK", pp = 25 },
    { id = "POISON_STING", pp = 35 }, { id = "LEER", pp = 30 },
  }
  game.save.party = { gengar, nido }
  game.save.player.name = "RED"
  game.save.inventory = {}
  Bag.add(game.save, "PP_UP", 5, game.data)
  Bag.add(game.save, "TM_MEGA_PUNCH", 1, game.data)
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  local function openPicker(id)
    while #game.stack.states > 1 do game.stack:pop() end
    U.wait(2)
    local bag = Screens.push(game, "BagMenu", {})
    U.wait(12)
    local row
    for i, r in ipairs(bag.items or {}) do
      if r.value == id then row = i break end
    end
    if not row or not cursorTo(bag, row) then return nil end
    U.tap(game, "a")
    U.wait(12)
    local ut = top()
    if ut and ut.items and ut.items[1] and ut.items[1].label == "USE" then
      cursorTo(ut, 1)
      U.tap(game, "a")
      U.wait(4)
    end
    if not waitFor(function()
      if isParty(top()) then return true end
      local t = top()
      if isBox(t) and (t.done or t.waiting) then U.tap(game, "a") end
      if getmetatable(t) == ChoiceBox then U.tap(game, "a") end
      return false
    end, 600) then return nil end
    return top()
  end

  local function pickMon(picker, slot)
    cursorTo(picker, slot)
    U.tap(game, "a")
  end

  U.log("======== pass 1: timing, no shots ========")
  local picker = openPicker("PP_UP")
  if check("PP UP party picker opened", picker ~= nil) then
    pickMon(picker, 1)
    local promptBox = top()
    check("A on GENGAR: a text box is on top, not the move box", isBox(promptBox))
    local mm = find(isMoveMenu)
    check("the move menu waits underneath, not ready", mm ~= nil and not mm.ready)
    check("the chosen arrow is hollow", picker.chosenHollow == true)
    check("the prompt is still typing", isBox(promptBox) and not promptBox.done)
    local frames = 0
    while not (isMoveMenu(top()) and top().ready) and frames < 400 do
      U.wait(1)
      frames = frames + 1
    end
    U.log("prompt frames before the move box:", frames)
    check("the move box waited for the typed prompt (" .. frames .. " frames)",
          frames >= 10 and frames < 400)
    U.tap(game, "b")
    U.wait(4)
    check("B returns to the party menu", isParty(top()))
    U.wait(2)
    check("the party arrow is filled again", not picker.chosenHollow)
  end

  U.log("======== pass 2: PP UP with shots ========")
  picker = openPicker("PP_UP")
  if check("PP UP party picker opened again", picker ~= nil) then
    pickMon(picker, 1)
    U.wait(3)
    U.shot(game, DIR .. "/2320_01_prompt_typing_hollow_arrow.png")
    check("move box ready after the prompt",
          waitFor(function() return isMoveMenu(top()) and top().ready end, 400))
    local mm = top()
    U.wait(2)
    U.shot(game, DIR .. "/2320_02_move_box_over_textbox.png")
    cursorTo(mm, 1)
    U.tap(game, "a")
    check("the result box opened",
          waitFor(function() return isBox(top()) end, 30))
    local res = top()
    check("result reads PP increased", boxText(res):find("increased") ~= nil)
    check("the move box is held under the result", mm.held == true and find(isMoveMenu) == mm)
    check("the party arrow is still hollow", picker.chosenHollow == true)
    waitFor(function() return res.done end, 240)
    U.shot(game, DIR .. "/2320_03_result_keeps_move_box.png")
    waitFor(function()
      if isBox(top()) then U.tap(game, "a") end
      return not find(isParty)
    end, 120)
    check("dismissing closes both the move box and the picker",
          not find(isParty) and not find(isMoveMenu))
    check("LICK got one PP Up", (gengar.moves[1].ppUps or 0) == 1)
  end

  U.log("======== PP UP on a maxed move reprompts ========")
  gengar.moves[1].ppUps = 3
  local before = game.save.inventory.PP_UP
  picker = openPicker("PP_UP")
  if check("PP UP party picker opened for the maxed move", picker ~= nil) then
    pickMon(picker, 1)
    waitFor(function() return isMoveMenu(top()) and top().ready end, 400)
    local mm = top()
    cursorTo(mm, 1)
    U.tap(game, "a")
    waitFor(function() return isBox(top()) end, 30)
    local res = top()
    check("maxed out text prints", boxText(res):find("maxed out") ~= nil)
    waitFor(function() return res.done end, 240)
    U.shot(game, DIR .. "/2320_04_pp_maxed_out.png")
    U.tap(game, "a")
    U.wait(2)
    check("the prompt types again", isBox(top()) and find(isMoveMenu) == mm and not mm.ready)
    check("the move box comes back",
          waitFor(function() return top() == mm and mm.ready end, 400))
    U.wait(2)
    U.shot(game, DIR .. "/2320_05_maxed_reprompt.png")
    check("no PP UP was spent", game.save.inventory.PP_UP == before)
    U.tap(game, "b")
    U.wait(4)
    U.tap(game, "b")
    U.wait(8)
  end

  U.log("======== TM on a full moveset ========")
  picker = openPicker("TM_MEGA_PUNCH")
  if check("TM party picker opened", picker ~= nil) then
    pickMon(picker, 2)
    local learn
    local ok = waitFor(function()
      learn = find(isLearn)
      local t = top()
      if learn and isBox(t) and boxText(t):find("forgotten") then return true end
      if getmetatable(t) == ChoiceBox then U.tap(game, "a")
      elseif isBox(t) and (t.done or t.waiting) then U.tap(game, "a") end
      return false
    end, 900)
    check("Which move should be forgotten? types first", ok and learn and not learn.selecting)
    U.wait(3)
    U.shot(game, DIR .. "/2320_06_forget_prompt_typing.png")
    check("the forget box follows the text",
          waitFor(function() return learn and top() == learn and learn.selecting end, 400))
    U.wait(2)
    U.shot(game, DIR .. "/2320_07_forget_box_over_textbox.png")
    cursorTo(learn, 1)
    U.tap(game, "a")
    U.wait(2)
    check("SURF is refused and the forget box is gone",
          isBox(top()) and boxText(top()):find("HM") ~= nil and not learn.selecting)
    waitFor(function() return top().done end, 240)
    U.shot(game, DIR .. "/2320_08_hm_refused_no_box.png")
    U.tap(game, "a")
    check("the forget prompt retypes, then the box returns",
          waitFor(function() return top() == learn and learn.selecting end, 400))
    cursorTo(learn, 2)
    U.tap(game, "a")
    U.wait(2)
    check("the forget box is gone for 1, 2 and... Poof!", not find(isLearn))
    waitFor(function()
      local t = top()
      if isBox(t) and (t.done or t.waiting) then U.tap(game, "a") end
      return not find(isParty)
    end, 900)
    local knows = false
    for _, mv in ipairs(nido.moves) do if mv.id == "MEGA_PUNCH" then knows = true end end
    check("NIDOKING learned MEGA PUNCH", knows)
  end

  U.log(fail == 0 and "PASS pp_up_move_box_2320" or ("FAIL pp_up_move_box_2320 (" .. fail .. ")"))
  love.event.quit(fail == 0 and 0 or 1)
end
