#!/usr/bin/env luajit
-- Gen 3 Party Item Use, TM Confirmation & Evolution Chaining Test Suite

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_item_use_party_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Pokemon = require("src.core.game3.pokemon")
local Evolution = require("src.core.game3.evolution")
local ItemUse = require("src.core.game3.item_use")
local PartyMenu = require("src.ui.game3.party_menu")
local Bag = require("src.core.game3.bag")
local Message = require("src.ui.game3.message")

print("=== [TEST 1] Rare Candy Gating (Lv 100 Cap & 0 HP Protection) ===")
do
  local bag = Bag.new()
  Bag.add(bag, 68, 5) -- 5 Rare Candies (id 68)
  local session = { bag = bag }

  -- 1. Lv 100 Pokémon
  local mon100 = { species = 1, speciesId = 1, level = 100, hp = 200, maxHp = 200 }
  local ok, reason, msgText = ItemUse.useRareCandy(session, mon100)
  check(ok == false, "Rare Candy rejected on Lv 100 mon")
  check(mon100.level == 100, "level remained 100")
  check(Bag.get(bag, 68) == 5, "Rare Candy count not decremented (still 5)")

  -- 2. 0 HP Fainted Pokémon
  local monFainted = { species = 1, speciesId = 1, level = 16, hp = 0, maxHp = 40 }
  local okFaint, reasonFaint, msgFaint = ItemUse.useRareCandy(session, monFainted)
  check(okFaint == false, "Rare Candy rejected on 0 HP fainted mon")
  check(monFainted.level == 16, "fainted mon level unchanged")
  check(Bag.get(bag, 68) == 5, "Rare Candy count not decremented (still 5)")
end

print("=== [TEST 2] Rare Candy HP Delta & Stat Recalculation on Living Mon ===")
do
  local bag = Bag.new()
  Bag.add(bag, 68, 5)
  local session = { bag = bag }

  local monAlive = {
    species = 1, speciesId = 1, level = 16,
    hp = 15, maxHp = 40,
    iv = { 15, 15, 15, 15, 15, 15 }, ev = { 0, 0, 0, 0, 0, 0 }
  }
  local ok, reason, msgText = ItemUse.useRareCandy(session, monAlive)
  check(ok == true, "Rare Candy accepted on living mon")
  check(monAlive.level == 17, "level increased to 17")
  check(monAlive.maxHp > 40, "maxHp increased on level up")
  local delta = monAlive.maxHp - 40
  check(monAlive.hp == 15 + delta, "current HP gained exact maxHp delta (" .. tostring(monAlive.hp) .. ")")
end

print("=== [TEST 3] TM Pre-Flight Checks & Known Move / Incompatibility Rejections ===")
do
  -- Bulbasaur (species 1): can learn TM06 (Toxic / 294), cannot learn TM47 (Steel Wing / 335)
  -- Bulbasaur knows Tackle (33)
  local bulbasaur = {
    species = 1, speciesId = 1, level = 10,
    moves = { 33 }, -- Tackle
  }

  -- Test with real TM item: TM06 (Toxic)
  local statusOk, prompt, moveId, moveName = ItemUse.checkTmPreflight(bulbasaur, 294) -- TM06 Toxic
  check(statusOk == "ok", "Bulbasaur compatible with TM06 (Toxic)")
  check(prompt == nil, "a mon with a free move slot learns without a prompt (party_menu.c:4786)")

  -- Teach Toxic to Bulbasaur
  bulbasaur.moves[#bulbasaur.moves + 1] = moveId
  local statusKnows, msgKnows = ItemUse.checkTmPreflight(bulbasaur, 294)
  check(statusKnows == "knows", "attempting to teach already known move returns 'knows'")
  check(msgKnows:find("already knows", 1, true) ~= nil, "message states mon already knows move")

  -- Test incompatible TM (e.g. TM47 Steel Wing / 335 on Bulbasaur)
  local statusIncompat, msgIncompat = ItemUse.checkTmPreflight(bulbasaur, 335) -- TM47 Steel Wing
  check(statusIncompat == "incompatible", "Bulbasaur incompatible with TM47 (Steel Wing)")
  check(msgIncompat:find("are not compatible", 1, true) ~= nil, "message is gText_PkmnCantLearnMove")
end

print("=== [TEST 4] PartyMenu TM Teach With A Free Slot ===")
do
  local bag = Bag.new()
  Bag.add(bag, 294, 1) -- 1 TM06 (Toxic)
  local party = {
    {
      species = 1, speciesId = 1, level = 10,
      moves = { 33 }, -- Tackle (1/4 slots)
      hp = 30, maxHp = 30,
    }
  }
  local session = { party = party, bag = bag }

  -- Show PartyMenu in "use" mode for TM06
  PartyMenu.show(party, nil, {
    session = session,
    bag = bag,
    item = 294,
    mode = "use",
  })
  check(PartyMenu.mode == "use", "PartyMenu opened in 'use' mode")

  -- Press A on Bulbasaur
  local mockInputA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }
  PartyMenu.handleInput(mockInputA)
  check(PartyMenu.mode ~= "yesno", "a free move slot teaches with no Yes/No (party_menu.c:4785)")
  check(Pokemon.knowsMove(party[1], 92), "Bulbasaur learned Toxic (move 92)")
  check(Bag.get(bag, 294) == 0, "TM06 consumed from bag on successful teach")
  check(PartyMenu.mode == "message", "PartyMenu showed learned message")

  -- Dismiss message
  PartyMenu.handleInput(mockInputA)
  check(PartyMenu.isOpen() == false, "PartyMenu closed after single-use TM was taught")
end

print("=== [TEST 5] Rare Candy Multi-Use Persistence vs Empty Bag Close ===")
do
  local bag = Bag.new()
  Bag.add(bag, 68, 2) -- 2 Rare Candies
  local party = {
    {
      species = 19, speciesId = 19, level = 5, -- Rattata Lv 5 (evolves at 20)
      hp = 20, maxHp = 20,
      moves = { 33 },
    }
  }
  local session = { party = party, bag = bag }

  PartyMenu.show(party, nil, {
    session = session,
    bag = bag,
    item = 68,
    mode = "use",
  })

  local mockInputA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }

  -- Use 1st Rare Candy (count: 2 -> 1)
  PartyMenu.handleInput(mockInputA)
  check(party[1].level == 6, "Rattata leveled up to 6")
  check(Bag.get(bag, 68) == 1, "Rare Candy count decremented to 1")

  -- Complete HP anim if active, then verify stat_growth mode
  if PartyMenu._hpAnim then PartyMenu.handleInput(mockInputA) end
  check(PartyMenu.mode == "stat_growth", "PartyMenu showing stat growth window")
  check(PartyMenu._statGrowthPage == 1, "stat growth on page 1 (deltas)")

  -- Advance to Page 2 (totals)
  PartyMenu.handleInput(mockInputA)
  check(PartyMenu._statGrowthPage == 2, "stat growth on page 2 (totals)")

  -- Advance out of stat growth to next item use
  PartyMenu.handleInput(mockInputA)
  check(PartyMenu.mode == "use", "PartyMenu persisted in 'use' mode for multi-item usage (1 candy left)")
  check(PartyMenu.isOpen() == true, "PartyMenu remained open")

  -- Use 2nd Rare Candy (count: 1 -> 0)
  PartyMenu.handleInput(mockInputA)
  check(party[1].level == 7, "Rattata leveled up to 7")
  check(Bag.get(bag, 68) == 0, "Rare Candy count decremented to 0")

  -- Complete HP anim if active, then advance stat growth pages
  if PartyMenu._hpAnim then PartyMenu.handleInput(mockInputA) end
  check(PartyMenu.mode == "stat_growth", "PartyMenu showing stat growth window for 2nd candy")
  PartyMenu.handleInput(mockInputA) -- Page 1 -> Page 2
  PartyMenu.handleInput(mockInputA) -- Page 2 -> Move learn queue
  -- Dismiss learned move message (Quick Attack at Lv 7)
  if PartyMenu.mode == "message" then PartyMenu.handleInput(mockInputA) end
  check(PartyMenu.isOpen() == false, "PartyMenu closed when item count reached 0")
end

print("=== [TEST 6] Rare Candy Evolution Chaining & Post-Evolution Return Mode ===")
do
  local bag = Bag.new()
  Bag.add(bag, 68, 1) -- 1 Rare Candy
  local party = {
    {
      species = 19, speciesId = 19, level = 19, -- Rattata Lv 19 -> evolves to Raticate 20 at Lv 20
      hp = 45, maxHp = 45,
      moves = { 33 },
    }
  }
  local session = { party = party, bag = bag }

  PartyMenu.show(party, nil, {
    session = session,
    bag = bag,
    item = 68,
    mode = "use",
  })

  local mockInputA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }

  -- Use Rare Candy
  PartyMenu.handleInput(mockInputA)
  check(party[1].level == 20, "Rattata reached Lv 20")

  -- Complete HP anim and advance stat growth pages
  if PartyMenu._hpAnim then PartyMenu.handleInput(mockInputA) end
  check(PartyMenu.mode == "stat_growth", "PartyMenu showing stat growth window")
  PartyMenu.handleInput(mockInputA) -- Page 1 -> Page 2
  PartyMenu.handleInput(mockInputA) -- Page 2 -> Move learn queue
  -- Dismiss learned move message (Focus Energy at Lv 20) -> triggers EvolutionScene
  if PartyMenu.mode == "message" then PartyMenu.handleInput(mockInputA) end
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  check(EvolutionScene.isOpen() == true, "EvolutionScene opened on Rare Candy level-up to threshold")

  -- Advance EvolutionScene animation to completion
  for _ = 1, 800 do
    EvolutionScene.update(1 / 60)
    local SummaryMenu = require("src.ui.game3.summary_menu")
    if SummaryMenu.isOpen() then
      SummaryMenu.handleInput(mockInputA)
    elseif EvolutionScene._state == "congrats" or EvolutionScene._state == "learn_moves" then
      local Choice = require("src.ui.game3.choice")
      if Choice.active then
        Choice.confirm()
      end
      EvolutionScene.handleInput(mockInputA)
    end
  end

  check(party[1].species == 20, "mon evolved into Raticate (species 20)")
  check(EvolutionScene.isOpen() == false, "EvolutionScene closed after evolution")
  check(PartyMenu.mode == "list", "PartyMenu returned to 'list' mode after evolution (exited multi-use)")
  PartyMenu.close()
end

print("=== [TEST 7] Chrome Isolation (No Overworld Message.isOpen Leaks) ===")
do
  local bag = Bag.new()
  Bag.add(bag, 13, 2) -- Potion
  local party = {
    { species = 1, speciesId = 1, level = 10, hp = 10, maxHp = 30 }
  }
  local session = { party = party, bag = bag }

  -- Verify Message is initially closed
  Message.close()
  check(Message.isOpen() == false, "overworld Message is closed before party item use")

  PartyMenu.show(party, nil, {
    session = session,
    bag = bag,
    item = 13,
    mode = "use",
  })

  local mockInputA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }
  PartyMenu.handleInput(mockInputA)
  if PartyMenu._hpAnim then PartyMenu.handleInput(mockInputA) end

  check(Message.isOpen() == false, "overworld Message remained closed during PartyMenu item use (no double chrome)")
  check(PartyMenu.mode == "message", "PartyMenu is handling its own message internally")
  PartyMenu.close()
end

print("=== [TEST 8] String Species Mon & 4-Move Replace Flow into Evolution ===")
do
  local bag = Bag.new()
  Bag.add(bag, 68, 1) -- 1 Rare Candy
  local party = {
    {
      species = "RATTATA", -- String species name format from save/world
      level = 19,
      hp = 45, maxHp = 45,
      moves = { 33, 39, 98, 158 }, -- 4 moves: Tackle, Tail Whip, Quick Attack, Hyper Fang
    }
  }
  local session = { party = party, bag = bag }

  PartyMenu.show(party, nil, {
    session = session,
    bag = bag,
    item = 68,
    mode = "use",
  })

  local mockInputA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }

  -- 1. Use Rare Candy
  PartyMenu.handleInput(mockInputA)
  check(party[1].level == 20, "String species Rattata reached Lv 20")

  -- 2. Fast forward HP anim & advance stat growth pages
  if PartyMenu._hpAnim then PartyMenu.handleInput(mockInputA) end
  check(PartyMenu.mode == "stat_growth", "PartyMenu showing stat growth window")
  PartyMenu.handleInput(mockInputA) -- Page 1 -> Page 2
  PartyMenu.handleInput(mockInputA) -- Page 2 -> Move learn queue

  -- 3. Learn move page 1: "Rattata wants to learn the move Focus Energy."
  check(PartyMenu.mode == "message", "PartyMenu showing 4-move learn move message page 1")
  PartyMenu.handleInput(mockInputA)

  -- 4. Learn move page 2: "However, Rattata already knows four moves."
  check(PartyMenu.mode == "message", "PartyMenu showing 4-move learn move message page 2")
  PartyMenu.handleInput(mockInputA)

  -- 5. Delete prompt: "Should a move be deleted and replaced with Focus Energy?" (yes/no)
  check(PartyMenu.mode == "yesno", "PartyMenu showing delete move yes/no prompt")
  PartyMenu.handleInput(mockInputA) -- choose YES

  -- 6. SummaryMenu opened in select_move mode for move replacement
  local SummaryMenu = require("src.ui.game3.summary_menu")
  check(SummaryMenu.isOpen() == true, "SummaryMenu opened for move selection")
  check(SummaryMenu._mode == "select_move", "SummaryMenu mode is select_move")
  SummaryMenu.handleInput(mockInputA) -- choose Move 1 (Tackle) to replace

  -- 7. Poof messages: "1, 2, and... Poof!"
  check(PartyMenu.mode == "message", "PartyMenu showing Poof message")
  PartyMenu.handleInput(mockInputA)

  -- 8. Forgot message: "Rattata forgot how to use Tackle."
  check(PartyMenu.mode == "message", "PartyMenu showing forgot old move message")
  PartyMenu.handleInput(mockInputA)

  -- 9. And... message
  check(PartyMenu.mode == "message", "PartyMenu showing And... message")
  PartyMenu.handleInput(mockInputA)

  -- 10. Learned message: "Rattata learned Focus Energy!"
  check(PartyMenu.mode == "message", "PartyMenu showing learned new move message")
  PartyMenu.handleInput(mockInputA)

  -- 11. Chaining into EvolutionScene!
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  check(EvolutionScene.isOpen() == true, "EvolutionScene opened for string species Rattata at Lv 20")

  -- Advance EvolutionScene animation to completion
  for _ = 1, 800 do
    EvolutionScene.update(1 / 60)
    if SummaryMenu.isOpen() then
      SummaryMenu.handleInput(mockInputA)
    elseif EvolutionScene._state == "congrats" or EvolutionScene._state == "learn_moves" then
      local Choice = require("src.ui.game3.choice")
      if Choice.active then
        Choice.confirm()
      end
      EvolutionScene.handleInput(mockInputA)
    end
  end

  check(party[1].species == 20 or party[1].speciesId == 20, "mon evolved into Raticate (species 20)")
  check(EvolutionScene.isOpen() == false, "EvolutionScene closed after evolution")
  check(PartyMenu.mode == "list", "PartyMenu returned to 'list' mode after evolution")
  PartyMenu.close()
end

print("=== [TEST 9] 4-Move Replacement on Specific Slots & B-Cancel Refusal ===")
do
  local bag = Bag.new()
  Bag.add(bag, 68, 1) -- 1 Rare Candy
  local party = {
    {
      species = 19, -- Rattata
      level = 19,
      hp = 45, maxHp = 45,
      moves = { 33, 39, 98, 158 }, -- Tackle, Tail Whip, Quick Attack, Hyper Fang
    }
  }
  local session = { party = party, bag = bag }

  PartyMenu.show(party, nil, {
    session = session,
    bag = bag,
    item = 68,
    mode = "use",
  })

  local mockInputA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }
  local mockInputDown = {
    wasPressed = function(_, k) return k == "down" end,
    isDown = function() return false end,
  }

  -- Use candy to reach Lv 20
  PartyMenu.handleInput(mockInputA)
  if PartyMenu._hpAnim then PartyMenu.handleInput(mockInputA) end
  check(PartyMenu.mode == "stat_growth", "PartyMenu showing stat growth window for test 9")
  PartyMenu.handleInput(mockInputA) -- Page 1 -> Page 2
  PartyMenu.handleInput(mockInputA) -- Page 2 -> Move learn queue

  -- Dismiss "wants to learn" and "knows four moves"
  PartyMenu.handleInput(mockInputA)
  PartyMenu.handleInput(mockInputA)

  -- Should be at delete prompt (yes/no)
  check(PartyMenu.mode == "yesno", "at delete prompt")
  PartyMenu.handleInput(mockInputA) -- select YES

  -- Should be at SummaryMenu select_move prompt
  local SummaryMenu = require("src.ui.game3.summary_menu")
  check(SummaryMenu.isOpen() == true, "at SummaryMenu select_move prompt")
  check(SummaryMenu._mode == "select_move", "SummaryMenu mode is select_move")
  -- Navigate down to move 4 (Hyper Fang, slot 4)
  SummaryMenu.handleInput(mockInputDown)
  SummaryMenu.handleInput(mockInputDown)
  SummaryMenu.handleInput(mockInputDown)
  check(SummaryMenu._moveCursor == 4, "cursor at slot 4")

  -- Confirm replacing slot 4
  SummaryMenu.handleInput(mockInputA)
  check(party[1].moves[4] == 116, "slot 4 replaced with Focus Energy (116)")

  -- Dismiss Poof, forgot, And..., learned
  PartyMenu.handleInput(mockInputA)
  PartyMenu.handleInput(mockInputA)
  PartyMenu.handleInput(mockInputA)
  PartyMenu.handleInput(mockInputA)

  -- Verify EvolutionScene launched without softlock
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  local Stack = require("src.ui.game3.stack")
  check(EvolutionScene.isOpen() == true, "EvolutionScene opened after slot 4 learn")
  EvolutionScene.open = false
  Stack.pop("evolution_scene")
  PartyMenu.close()
end

print("=== [TEST 10] PartyMenu Cancel Button Navigation & Dismissal ===")
do
  local party = {
    { species = 1, speciesId = 1, level = 10, hp = 30, maxHp = 30 },
    { species = 4, speciesId = 4, level = 10, hp = 30, maxHp = 30 },
    { species = 7, speciesId = 7, level = 10, hp = 30, maxHp = 30 },
  }
  local closed = false
  PartyMenu.show(party, nil, {
    onClose = function() closed = true end,
  })
  check(PartyMenu.isOpen() == true, "PartyMenu is open")
  check(PartyMenu.cursor == 1, "Initial cursor at slot 1")

  local function press(btn)
    local inp = {
      wasPressed = function(_, k) return k == btn end,
      isDown = function() return false end,
    }
    PartyMenu.handleInput(inp)
  end

  -- UP from slot 1 wraps to slot 7 (Cancel)
  press("up")
  check(PartyMenu.cursor == 7, "UP from slot 1 moved to slot 7 (Cancel)")

  -- UP from slot 7 wraps to slot 3 (last party member)
  press("up")
  check(PartyMenu.cursor == 3, "UP from slot 7 moved to slot 3 (last mon)")

  -- DOWN from slot 3 moves to slot 7 (Cancel)
  press("down")
  check(PartyMenu.cursor == 7, "DOWN from slot 3 moved to slot 7 (Cancel)")

  -- DOWN from slot 7 wraps to slot 1
  press("down")
  check(PartyMenu.cursor == 1, "DOWN from slot 7 wrapped to slot 1")

  -- RIGHT from slot 1 moves to slot 2 (right column)
  press("right")
  check(PartyMenu.cursor == 2, "RIGHT from slot 1 moved to slot 2")

  -- LEFT from slot 2 moves to slot 1 (left column)
  press("left")
  check(PartyMenu.cursor == 1, "LEFT from slot 2 moved to slot 1")

  -- Move to Cancel and press A to close
  press("up")
  check(PartyMenu.cursor == 7, "At slot 7 (Cancel)")
  press("a")
  check(PartyMenu.isOpen() == false, "Pressing A on Cancel button closes PartyMenu")
  check(closed == true, "onClose callback invoked")
end

print("=== [TEST 11] Rare Candy Free-Slot Learn Move Dialog Persistence Across Frames ===")
do
  local bag = Bag.new()
  Bag.add(bag, 68, 1) -- 1 Rare Candy
  local party = {
    {
      species = 19, speciesId = 19, level = 6, -- Rattata Lv 6 -> 7 learns Quick Attack (98)
      hp = 20, maxHp = 20,
      moves = { 33 }, -- Tackle (1/4 slots)
    }
  }
  local session = { party = party, bag = bag }

  PartyMenu.show(party, nil, {
    session = session,
    bag = bag,
    item = 68,
    mode = "use",
  })

  local mockInputA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }

  -- Use Rare Candy
  PartyMenu.handleInput(mockInputA)
  check(party[1].level == 7, "Rattata leveled up to 7")

  -- Complete HP anim if active
  if PartyMenu._hpAnim then PartyMenu.handleInput(mockInputA) end
  check(PartyMenu.mode == "stat_growth", "PartyMenu showing stat growth window")
  check(PartyMenu._statGrowthPage == 1, "stat growth on page 1")

  -- Advance to Page 2
  PartyMenu.handleInput(mockInputA)
  check(PartyMenu._statGrowthPage == 2, "stat growth on page 2")

  -- Advance to Learn Move queue
  PartyMenu.handleInput(mockInputA)
  check(PartyMenu.mode == "message", "PartyMenu entered 'message' mode for learned move")
  check(PartyMenu._messageText ~= nil and PartyMenu._messageText:find("learned", 1, true) ~= nil,
    "PartyMenu showing learned move message text (got: " .. tostring(PartyMenu._messageText) .. ")")

  -- Simulate multiple update ticks (frames)
  for _ = 1, 60 do
    PartyMenu.update(1 / 60)
  end
  check(PartyMenu.mode == "message", "PartyMenu remained in 'message' mode across 60 update ticks")
  check(PartyMenu._messageText ~= nil and PartyMenu._messageText:find("learned", 1, true) ~= nil,
    "PartyMenu message text stayed on screen without being eaten")

  -- Now player presses A to dismiss
  PartyMenu.handleInput(mockInputA)
  check(PartyMenu.mode ~= "message", "Message dismissed after user presses A")
  check(Pokemon.knowsMove(party[1], 98), "Rattata knows Quick Attack")
  PartyMenu.close()
end

print("=== [TEST 12] Bag Menu List-Mode SELECT Shortcut Quick-Register & Overwrite ===")
do
  local BagMenu = require("src.ui.game3.bag_menu")
  local bag = Bag.new()
  Bag.add(bag, 361, 1) -- Town Map (Key Item 361, registrability = 1)
  Bag.add(bag, 360, 1) -- Bicycle (Key Item 360, registrability = 1)
  local session = { bag = bag, registeredItem = nil }

  BagMenu.show(session, {
    bag = bag,
    session = session,
    pocket = "KEY_ITEMS",
  })
  BagMenu.settle()
  check(BagMenu.isOpen() == true, "BagMenu is open in KEY_ITEMS pocket")
  check(BagMenu.currentPocket() == "KEY_ITEMS", "current pocket is KEY_ITEMS")

  local function press(btn)
    local inp = {
      wasPressed = function(_, k) return k == btn end,
      isDown = function() return false end,
    }
    BagMenu.handleInput(inp)
  end

  -- Cursor starts on item 1 (Bicycle or Town Map depending on alphabetical sort)
  local rows = BagMenu.list()
  check(#rows >= 2, "at least 2 key items in bag")
  local item1 = rows[1].id
  local item2 = rows[2].id

  -- 1. Press SELECT on item 1 -> registers item 1
  press("select")
  check(session.registeredItem == item1, "item 1 registered via SELECT (" .. tostring(item1) .. ")")

  -- 2. Move cursor down to item 2 and press SELECT -> OVERWRITES to item 2
  press("down")
  check(BagMenu.cursor == 2, "cursor moved to item 2")
  press("select")
  check(session.registeredItem == item2, "item 2 overwrote registered item (" .. tostring(item2) .. ")")

  -- 3. Press SELECT on item 2 again -> UNREGISTERS to nil
  press("select")
  check(session.registeredItem == nil, "pressing SELECT on already registered item unregisters to nil")

  BagMenu.close()
end

if failed > 0 then
  print(string.format("\n[FAILED] %d test(s) failed", failed))
  os.exit(1)
else
  print("\nALL PARTY ITEM USE & PARITY TESTS PASSED CLEANLY!")
end
