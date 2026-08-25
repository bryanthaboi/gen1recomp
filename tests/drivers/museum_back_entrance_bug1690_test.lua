-- Manual check of the Pewter museum clerk's back-entrance branches (#1690).
-- scripts/Museum1F.asm:45 reads wYCoord/wXCoord before the ticket flag, so
-- (13,4) and (12,3) behind the counter get the AMBER question and row 4 in
-- front of it gets the ¥50 ask.  This walks all three by itself.
-- Do not add POKEPORT_SPEED: fast-forward scales only the logic clock, and
-- what is being judged here is page order and the choice box timing.
--   POKEPORT_DRIVER=tests/drivers/museum_back_entrance_bug1690_test.lua POKEPORT_TOUCH=0 POKEPORT_VERSION=red POKEPORT_IDENTITY=bug1690 SHOT_DIR=/tmp/museum1690 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local MAP = "MUSEUM_1F"
  local CLERK_TEXT = "TEXT_MUSEUM1F_SCIENTIST1"
  -- pokered data/maps/objects/Museum1F.asm: MUSEUM1F_SCIENTIST1 at (12,4),
  -- counter column x==11, back door warps in at (16,7)/(17,7)
  local BEHIND_EAST = { x = 13, y = 4, facing = "left" }
  local BEHIND_NORTH = { x = 12, y = 3, facing = "down" }
  local IN_FRONT = { x = 10, y = 4, facing = "right" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- every one of these failing looks exactly like the bug on screen: a
  -- missing string, a renamed key or an unwalkable cell all end in silence
  local t = game.data.text or {}
  for _, key in ipairs({
    "_Museum1FScientist1DoYouKnowWhatAmberIsText",
    "_Museum1FScientist1TheresALabSomewhereText",
    "_Museum1FScientist1AmberIsFossilizedTreeSapText",
    "_Museum1FScientist1GoToOtherSideText",
    "_Museum1FScientist1WouldYouLikeToComeInText",
  }) do
    check(key .. " is in the text catalog",
          type(t[key]) == "string" and t[key] ~= "")
  end

  local function clerkIn(ow)
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.def and n.def.text == CLERK_TEXT then return n end
    end
    return nil
  end

  local function boxText(box)
    local shown = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    return table.concat(shown, " / ")
  end

  -- talking works either straight at the clerk or across the counter tile
  local function facingTheClerk()
    local ow = game.overworld
    local clerk = clerkIn(ow)
    if not clerk then return false end
    local fx, fy = ow.player:facingCell()
    if ow:npcAtCell(fx, fy) == clerk then return true end
    if ow.map:isCounterCell(fx, fy) then
      local Collision = require("src.world.Collision")
      local bx, by = Collision.target(fx, fy, ow.player.facing)
      return ow:npcAtCell(bx, by) == clerk
    end
    return false
  end

  -- teleport to `spot`, and if a map edit moved the counter fall back to any
  -- free walkable neighbour of the clerk so this degrades instead of parking
  -- the player at a wall
  local function standAt(spot, label)
    U.teleport(game, MAP, spot.x, spot.y, spot.facing)
    U.wait(10)
    if facingTheClerk() then return check(label .. ": in position", true) end
    local ow = game.overworld
    local clerk = clerkIn(ow)
    if clerk then
      local sides = {
        { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
      }
      for _, s in ipairs(sides) do
        local cx, cy = clerk.cellX + s[1], clerk.cellY + s[2]
        if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
          U.log(("(%d,%d) does not reach the clerk, standing on")
                  :format(spot.x, spot.y), cx, cy, "facing", s[3])
          U.teleport(game, MAP, cx, cy, s[3])
          U.wait(10)
          break
        end
      end
    end
    return check(label .. ": in position", facingTheClerk())
  end

  -- press A and wait for the dialogue box to actually mount
  local function talk()
    U.tap(game, "a")
    for _ = 1, 60 do
      local top = game.stack:top()
      if getmetatable(top) == TextBox then return top end
      U.wait(1)
    end
    return nil
  end

  -- page through until the YES/NO box pops (the clerk's question is two
  -- pages, so one A press sits between the box opening and the choice)
  local function toChoice()
    for _ = 1, 20 do
      if getmetatable(game.stack:top()) == ChoiceBox then
        return game.stack:top()
      end
      U.tap(game, "a")
      U.wait(20)
    end
    return getmetatable(game.stack:top()) == ChoiceBox and game.stack:top() or nil
  end

  -- ChoiceBox starts on YES; NO is one step down
  local function answer(yes)
    if not yes then U.tap(game, "down") U.wait(10) end
    U.tap(game, "a")
    for _ = 1, 60 do
      local top = game.stack:top()
      if getmetatable(top) == TextBox then return top end
      U.wait(1)
    end
    return nil
  end

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = nil
  standAt(BEHIND_EAST, "east of the clerk (13,4)")

  local box = talk()
  if check("A behind the counter opens a box", box ~= nil) then
    U.log("box reads:", boxText(box))
    check("it is the can't-sneak-in-the-back-way line",
          boxText(box):find("sneak", 1, true) ~= nil)
    check("no money window rides along with it", box.money == nil)
    U.shot(game, SHOT_DIR .. "/bug1690_a_sneak.png")
  end

  local choice = toChoice()
  if check("the AMBER question offers YES/NO", choice ~= nil) then
    U.shot(game, SHOT_DIR .. "/bug1690_b_amber_choice.png")
    local answered = answer(true)
    if check("YES opens a follow-up box", answered ~= nil) then
      U.log("YES reads:", boxText(answered))
      check("YES is the resurrection lab line",
            boxText(answered):find("lab", 1, true) ~= nil)
      U.shot(game, SHOT_DIR .. "/bug1690_c_lab.png")
    end
  end

  -- with the ticket already bought the coordinate check still wins: a
  -- ticket holder round the back is told off, not thanked (asm:45 runs
  -- before the CheckEvent at asm:59)
  game.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
  standAt(BEHIND_NORTH, "north of the clerk (12,3), ticket in hand")
  box = talk()
  if check("A north of the clerk opens a box", box ~= nil) then
    U.log("box reads:", boxText(box))
    check("a ticket holder round the back still gets told off",
          boxText(box):find("sneak", 1, true) ~= nil)
    U.shot(game, SHOT_DIR .. "/bug1690_d_ticket_holder_sneak.png")
  end
  choice = toChoice()
  if check("it still offers YES/NO", choice ~= nil) then
    local answered = answer(false)
    if check("NO opens a follow-up box", answered ~= nil) then
      U.log("NO reads:", boxText(answered))
      check("NO is the fossilized tree sap line",
            boxText(answered):find("tree sap", 1, true) ~= nil)
      U.shot(game, SHOT_DIR .. "/bug1690_e_tree_sap.png")
    end
  end

  -- the control case: the public side of the counter is untouched
  game.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = nil
  game.save.money = 3000
  standAt(IN_FRONT, "in front of the counter (10,4)")
  box = talk()
  if check("A across the counter opens a box", box ~= nil) then
    U.log("box reads:", boxText(box))
    check("the front of the counter is still the ¥50 ticket ask",
          boxText(box):find("50", 1, true) ~= nil)
    check("and it still raises the money window", box.money ~= nil)
    U.shot(game, SHOT_DIR .. "/bug1690_f_ticket_ask.png")
  end

  U.log("shots are in " .. SHOT_DIR .. ", in the order they were taken.")
  U.log("behind the counter the clerk should say \"You can't sneak in the back")
  U.log("way!\", then \"Oh, whatever! Do you know what AMBER is?\" with YES/NO,")
  U.log("and never a money window. YES talks about a lab resurrecting ancient")
  U.log("POKeMON, NO says AMBER is fossilized tree sap. The box left on screen")
  U.log("now is the last case: standing at (10,4) with no ticket, which must")
  U.log("still be the ¥50 ask with the money window in the corner.")
  U.log("the near misses to watch for: a money window sitting behind the AMBER")
  U.log("question, or \"Take your time, and enjoy it all!\" at (12,3) once the")
  U.log("ticket flag is set, which would mean the ticket check ran first.")
  U.log("Yellow shares this script, so POKEPORT_VERSION=yellow should read")
  U.log("exactly the same at all three spots.")

  while true do
    coroutine.yield()
  end
end
