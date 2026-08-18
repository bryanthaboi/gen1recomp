-- Driver: nobody is caught mid-stride while a text box is up (#1435).
-- UpdatePlayerSprite and UpdateNPCSprite both jump to their standing frame
-- while BIT_FONT_LOADED is set (engine/overworld/movement.asm:57, :139), so a
-- box that opens on a walk frame freezes a standing sprite, never a leg out.
--
--   POKEPORT_DRIVER=tests/drivers/talk_pose_bug1435_test.lua \
--     POKEPORT_IDENTITY=bug1435 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Mom stands at (5,4) in Red's house (pokered
  -- data/maps/objects/RedsHouse1F.asm); park the player beside her and push
  -- into her so the walk-in-place cycle is running when the box opens.
  U.teleport(game, "REDS_HOUSE_1F", 6, 4, "down")
  U.wait(20)
  local ow = game.overworld
  local p = ow.player

  local walking = false
  for _ = 1, 90 do
    table.insert(game.input.pressQueue, "left")
    game.input.state.left = true
    coroutine.yield()
    if p:walkPhase() == 1 then walking = true break end
  end
  game.input.state.left = false
  check("bumping into MOM shows the walk frame", walking)
  U.shot(game, DIR .. "/bug1435_1_midstride.png")

  U.tap(game, "a")
  U.wait(4)
  check("talking to MOM opened a box over the overworld",
        game.stack:top() ~= ow)
  check("the walk clock is still mid-cycle underneath",
        (p.bumpFrames or 0) > 0 or p.moving)
  check("but the player is drawn standing", p:walkPhase() == 0)
  U.shot(game, DIR .. "/bug1435_2_talking.png")

  -- The same gate for an NPC caught mid-step: Pallet Town's wanderers walk
  -- on their own, so wait for one and open a box while it is between cells.
  U.teleport(game, "PALLET_TOWN", 8, 8, "down")
  U.wait(30)
  ow = game.overworld
  local mover
  for _ = 1, 900 do
    for _, npc in ipairs(ow.npcs) do
      if npc.moving and npc:walkPhase() == 1 then mover = npc break end
    end
    if mover then break end
    coroutine.yield()
  end
  if check("caught a Pallet Town NPC mid-step", mover ~= nil) then
    game.stack:push(TextBox.new(game, "TESTING THE POSE."))
    U.wait(4)
    check("the NPC is still mid-step underneath", mover.moving)
    check("but it is drawn standing too", mover:walkPhase() == 0)
    U.shot(game, DIR .. "/bug1435_3_npc.png")
  end

  U.log("Look at bug1435_2_talking.png and bug1435_3_npc.png: with the box")
  U.log("up, both sprites stand square on their feet.  A leg out, or the")
  U.log("split-stride frame held for the whole conversation, is the bug.")

  while true do coroutine.yield() end
end
