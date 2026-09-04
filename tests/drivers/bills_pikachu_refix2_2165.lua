-- #2165 refix 2: home/overworld.asm:1234-1252 (the B bypass and the
-- wPikachuCollisionCounter soft bump), engine/pikachu/pikachu_follow.asm:59
-- (the companion never starts the confused walk on the player's cell) and
-- engine/events/hidden_events/bills_house_pc.asm:14-40 (268 delay frames plus
-- five WaitForSoundToFinish drains).  Self-terminating: it quits LOVE with 0
-- on all-PASS and 1 otherwise.  No POKEPORT_SPEED -- it scales the logic
-- clock only and desyncs the cries against the walk.
--
--   SHOT_DIR=/tmp/shots2165b POKEPORT_SHOT_DIR=/tmp/shots2165b \
--   POKEPORT_DRIVER=tests/drivers/bills_pikachu_refix2_2165.lua \
--   POKEPORT_IDENTITY=yellow-sep04 POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots2165b"
  local failures = 0

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  local function finish()
    U.log(failures == 0 and "DONE all checks passed"
                        or ("DONE " .. failures .. " check(s) failed"))
    U.log("shots in", SHOT_DIR)
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    finish()
  end

  local MAP = "BILLS_HOUSE"

  local function resetSave()
    game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
    game.save.player.name = "bryan"
    game.save.options = game.save.options or {}
    game.save.options.textSpeed = 1
    game.save.flags = game.save.flags or {}
    game.save.flags.EVENT_GOT_STARTER = true
    game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
    game.save.flags.EVENT_MET_BILL = nil
    game.save.flags.EVENT_MET_BILL_2 = nil
    game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = nil
    game.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = nil
    game.save.pikachuMapScriptActive = nil
  end

  local ow
  local function follower()
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  local function objectAt(name)
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local function press(dir, frames)
    for _ = 1, frames do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
    end
  end

  local function release(...)
    for _, b in ipairs({ ... }) do game.input.state[b] = false end
    U.wait(1)
  end

  -- walk the player exactly one cell: hold until the cell index changes,
  -- release, then let the in-flight step land
  local function step(dir)
    local p0 = ow.player
    local sx, sy = p0.cellX, p0.cellY
    for _ = 1, 60 do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
      if p0.cellX ~= sx or p0.cellY ~= sy then break end
    end
    game.input.state[dir] = false
    for _ = 1, 40 do
      if not p0.moving then break end
      coroutine.yield()
    end
    U.wait(2)
  end

  -- =====================================================================
  -- A. the soft bump and the B bypass, both of which only exist while
  --    following is ENABLED -- home/overworld.asm:1240-1252
  -- =====================================================================
  resetSave()
  game.save.flags.EVENT_MET_BILL_2 = true -- BillsHouseScript0 stays asleep
  U.teleport(game, MAP, 3, 6, "up")
  U.wait(30)
  ow = game.overworld
  if not check("Bill's House loaded", ow and ow.map and ow.map.id == MAP) then
    finish()
  end
  check("the confused beat did not run with EVENT_MET_BILL_2 set",
        ow.pikachuBillsScene ~= true)

  -- take a step so the companion trails onto the cell behind the player
  step("up")
  U.wait(20)
  local npc = follower()
  if not check("the follower spawned and trailed", npc ~= nil) then finish() end
  check("a following companion is walk-through when nothing is pressed",
        npc.passable == true and (ow.pikachuCollisionCounter or 0) == 0)

  local p = ow.player
  local backDir = (npc.cellY > p.cellY and "down")
                  or (npc.cellY < p.cellY and "up")
                  or (npc.cellX > p.cellX and "right") or "left"
  U.log(string.format("A player=(%d,%d)%s pika=(%d,%d) push=%s",
        p.cellX, p.cellY, p.facing, npc.cellX, npc.cellY, backDir))

  local startX, startY = p.cellX, p.cellY
  local seeded, blockedTicks, movedAt = 0, 0, nil
  for i = 1, 40 do
    table.insert(game.input.pressQueue, backDir)
    game.input.state[backDir] = true
    coroutine.yield()
    seeded = math.max(seeded, ow.pikachuCollisionCounter or 0)
    if p.cellX ~= startX or p.cellY ~= startY or p.moving then
      movedAt = i
      break
    end
    if p.facing == backDir and npc.passable == false then
      blockedTicks = blockedTicks + 1
    end
  end
  release(backDir)
  U.log("A seeded=" .. seeded .. " blockedTicks=" .. blockedTicks
        .. " movedAt=" .. tostring(movedAt))
  check("turning toward the companion seeds the 8-count bump", seeded == 8)
  check("the bump holds the player for several frames, then yields",
        blockedTicks >= 4 and movedAt ~= nil)

  U.wait(20)
  npc = follower()
  p = ow.player
  backDir = (npc.cellY > p.cellY and "down") or (npc.cellY < p.cellY and "up")
            or (npc.cellX > p.cellX and "right") or "left"
  startX, startY = p.cellX, p.cellY
  local bWalkedThrough = false
  game.input.state.b = true
  for _ = 1, 40 do
    table.insert(game.input.pressQueue, "b")
    table.insert(game.input.pressQueue, backDir)
    game.input.state[backDir] = true
    coroutine.yield()
    if p.cellX ~= startX or p.cellY ~= startY or p.moving then
      bWalkedThrough = true
      break
    end
  end
  release(backDir, "b")
  check("holding B walks straight through the companion", bWalkedThrough)

  -- =====================================================================
  -- B. the confused walk lands directly below Bill
  --    (scripts/BillsHouse_2.asm:125 from the emerged cell)
  -- =====================================================================
  resetSave()
  U.teleport(game, MAP, 2, 7, "up")
  U.wait(20)
  ow = game.overworld
  npc = follower()
  if not check("the follower spawned for the confused beat", npc ~= nil) then
    finish()
  end
  check("the confused beat started", ow.pikachuBillsScene == true)
  check("the scripted walk uses the 16-frame Pikachu step",
        npc.stepFrames == 16)

  for _ = 1, 600 do
    if ow.emote and ow.emote.pikaPic then break end
    U.wait(1)
  end
  for _ = 1, 900 do
    if not ow.emote then break end
    U.wait(1)
  end
  U.wait(10)

  local bill = objectAt("BILLSHOUSE_BILL_POKEMON")
  npc = follower()
  U.log(string.format("B pika=(%d,%d) bill=(%s,%s)",
        npc.cellX, npc.cellY,
        bill and bill.cellX or "?", bill and bill.cellY or "?"))
  check("the confused walk ends directly below Bill (6,6)",
        npc.cellX == 6 and npc.cellY == 6)
  check("which is Bill's own column, one row south",
        bill ~= nil and npc.cellX == bill.cellX and npc.cellY == bill.cellY + 1)
  U.shot(game, SHOT_DIR .. "/01_confused_walk_ends_below_bill.png")

  -- =====================================================================
  -- C. the parked companion is solid -- home/overworld.asm:1238-1240
  -- =====================================================================
  p = ow.player
  for _ = 1, 4 do step("right") end
  U.wait(10)
  U.log(string.format("C player=(%d,%d)%s pika=(%d,%d) passable=%s",
        p.cellX, p.cellY, p.facing, npc.cellX, npc.cellY,
        tostring(npc.passable)))
  check("the player reached the cell south of the companion",
        p.cellX == 6 and p.cellY == 7)
  check("and following is still disabled, so the companion is solid",
        npc.passable == false)
  startX, startY = p.cellX, p.cellY
  press("up", 60)
  release("up")
  check("pushing north into the parked companion never moves the player",
        p.cellX == startX and p.cellY == startY)
  U.shot(game, SHOT_DIR .. "/02_solid_companion_blocks_player.png")

  -- =====================================================================
  -- D. the cell separator runs the cartridge's 268 delay frames plus five
  --    WaitForSoundToFinish drains -- bills_house_pc.asm:14-40, :51-63
  -- =====================================================================
  game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = true
  game.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = nil
  U.teleport(game, MAP, 1, 5, "up")
  U.wait(20)
  ow = game.overworld
  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 200 do -- type + prompt-button the initiated text away
    U.tap(game, "a")
    U.wait(2)
    if ow.runner and ow.runner:isRunning() then break end
    if #(ow.pendingScripts or {}) > 0 then break end
  end

  local chainFrames, shot = 0, false
  for _ = 1, 1200 do
    if game.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL then break end
    chainFrames = chainFrames + 1
    U.wait(1)
    if not shot and chainFrames == 150 then
      shot = true
      U.shot(game, SHOT_DIR .. "/03_cell_separator_running.png")
    end
  end
  -- 268 asm delay frames less the handful the text-box drain eats before
  -- this loop starts; the pre-fix chain was 222 and measures ~218 here
  U.log("D chainFrames=" .. chainFrames .. " (asm budget 268 + five SFX)")
  check("the separator chain runs the cartridge's ~268 delay frames",
        chainFrames >= 255)
  check("and it sets EVENT_USED_CELL_SEPARATOR_ON_BILL only at the end",
        game.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL == true)

  for _ = 1, 600 do
    if objectAt("BILLSHOUSE_BILL1") then break end
    U.wait(1)
  end
  U.wait(30)
  check("Bill steps out of the machine when the chain ends",
        objectAt("BILLSHOUSE_BILL1") ~= nil)
  U.shot(game, SHOT_DIR .. "/04_bill_out_of_the_machine.png")

  finish()
end
