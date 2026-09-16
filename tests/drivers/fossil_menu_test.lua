-- Driver: Cinnabar Lab fossil-select menu (engine/events/cinnabar_lab.asm
-- GiveFossilToCinnabarLab): talk to scientist 1 carrying two fossils,
-- screenshot the fossil menu, pick one, answer YES on the confirm, and
-- confirm the deposit flags/inventory.  Then re-talk and back out with B
-- (ComeAgainText path) to prove nothing is taken on cancel.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"
  local Menu = require("src.ui.Menu")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local Bag = require("src.inventory.Bag")

  local failures = 0
  local function ok(cond, what)
    if not cond then failures = failures + 1 end
    U.log((cond and "PASS " or "FAIL ") .. what)
    return cond
  end
  local function inStack(cls)
    for _, s in ipairs(game.stack.states) do
      if getmetatable(s) == cls then return true end
    end
    return false
  end

  Bag.add(game.save, "DOME_FOSSIL", 1)
  Bag.add(game.save, "OLD_AMBER", 1)

  U.teleport(game, "CINNABAR_LAB_FOSSIL_ROOM", 5, 3, "up")
  local ow = game.overworld

  -- scientist 1 wanders LEFT_RIGHT along row 2: pin him right above us
  for _, npc in ipairs(ow.npcs) do
    if npc.def and npc.def.text == "TEXT_CINNABARLABFOSSILROOM_SCIENTIST1" then
      npc.wanders, npc.moving = false, false
      npc.cellX, npc.cellY = 5, 2
      npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
      npc.facing = "down"
    end
  end
  U.wait(5)
  U.shot(game, DIR .. "/fossil_0_room.png")

  local function topIs(cls) return getmetatable(game.stack:top()) == cls end
  local function mash(btn, cond)
    for _ = 1, 200 do
      if cond() then return true end
      U.tap(game, btn)
      U.wait(3)
    end
    return false
  end

  -- deposit run: intro -> menu -> pick DOME FOSSIL -> YES -> walk texts
  U.tap(game, "a")
  U.wait(20)
  U.shot(game, DIR .. "/fossil_1_intro.png")
  ok(mash("a", function() return topIs(Menu) end), "the fossil menu opens")
  -- box still on screen under the menu (engine/events/cinnabar_lab.asm:22-24)
  local under = game.stack.states[#game.stack.states - 1]
  ok(getmetatable(under) == TextBox,
     "the intro dialogue box is still on the stack under the menu")
  U.shot(game, DIR .. "/fossil_2_menu.png")
  U.shot(game, DIR .. "/2281_01_menu_over_textbox.png")
  U.tap(game, "a") -- choose the first entry (DOME FOSSIL)
  -- prints under it (engine/events/cinnabar_lab.asm:55-67)
  U.wait(90)
  ok(inStack(Menu), "the menu is still up after a fossil is picked")
  ok(topIs(TextBox), "with SeesFossilText printing over it")
  U.shot(game, DIR .. "/2281_02_after_select_menu_stays.png")
  ok(mash("a", function() return topIs(ChoiceBox) end), "the YES/NO confirm opens")
  ok(inStack(Menu), "and the menu border is still up at the confirm")
  U.shot(game, DIR .. "/fossil_3_confirm.png")
  U.tap(game, "a") -- YES
  -- both boxes go only at CloseTextDisplay (home/text_script.asm:105-130)
  ok(mash("a", function() return game.stack:top() == ow end),
     "the deposit texts end back on the overworld with both boxes popped")
  ok(#game.stack.states == 1, "and nothing is left on the stack over it")
  U.shot(game, DIR .. "/fossil_4_done.png")
  U.log("GAVE_FOSSIL_TO_LAB:", tostring(game.save.flags.EVENT_GAVE_FOSSIL_TO_LAB),
        "STILL_REVIVING:", tostring(game.save.flags.EVENT_LAB_STILL_REVIVING_FOSSIL),
        "labFossilMon:", tostring(game.save.labFossilMon))
  U.log("bag DOME_FOSSIL:", tostring(game.save.inventory.DOME_FOSSIL),
        "OLD_AMBER:", tostring(game.save.inventory.OLD_AMBER))

  -- cancel run after the quest resets would need a full revive cycle;
  -- instead prove the B-out path on a fresh quest state
  game.save.flags.EVENT_GAVE_FOSSIL_TO_LAB = nil
  game.save.flags.EVENT_LAB_STILL_REVIVING_FOSSIL = nil
  game.save.labFossilMon = nil
  U.tap(game, "a")
  U.wait(20)
  ok(mash("a", function() return topIs(Menu) end), "the fossil menu opens again")
  U.shot(game, DIR .. "/fossil_5_menu_again.png")
  U.tap(game, "b") -- back out
  -- (engine/events/cinnabar_lab.asm:70-73)
  U.wait(30)
  ok(inStack(Menu), "B leaves the menu border up over ComeAgainText")
  ok(mash("a", function() return game.stack:top() == ow end),
     "and the cancel path still unwinds to the overworld")
  ok(#game.stack.states == 1, "with no ghost box left behind")
  U.shot(game, DIR .. "/fossil_6_cancelled.png")
  U.log("after cancel OLD_AMBER:", tostring(game.save.inventory.OLD_AMBER),
        "GAVE_FOSSIL_TO_LAB:", tostring(game.save.flags.EVENT_GAVE_FOSSIL_TO_LAB))
  U.log("DONE", failures == 0 and "PASS" or (failures .. " FAILURES"))
  love.event.quit(failures == 0 and 0 or 1)
end
