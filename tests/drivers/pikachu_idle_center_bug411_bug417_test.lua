-- Two Yellow companion beats you have to watch rather than assert: the idle
-- animations Pikachu plays while you stand still (#411, pokeyellow
-- engine/pikachu/pikachu_follow.asm Func_fc803) and its hop onto the Poke
-- Center counter when the heal is accepted (#417, engine/pikachu/
-- pikachu_emotions.asm PikachuWalksToNurseJoy).  Do not add POKEPORT_SPEED:
-- it scales the logic clock only while audio keeps its own real-time
-- accumulator, which desynchronizes exactly the timing being judged.
--   POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=tests/drivers/pikachu_idle_center_bug411_bug417_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local shots = {}
  local ok = true

  local function check(label, pass)
    if not pass then ok = false end
    U.log(pass and "PASS" or "FAIL", label)
    return pass
  end

  local function shot(name)
    local path = SHOT_DIR .. "/" .. name .. ".png"
    if U.shot(game, path) then
      shots[#shots + 1] = path .. " @f" .. U.frame()
      return true
    end
    return false
  end

  -- Yellow only: the follower, the counter hop and the pikapic box are all
  -- behind GameVersion.isYellow(), so a Red boot would silently show none of
  -- this and every look-at-it line below would be a lie.
  if not check("running the Yellow cache", GameVersion.isYellow()) then
    U.log("re-run with POKEPORT_VERSION=yellow; nothing else here applies.")
    while true do coroutine.yield() end
  end
  check("SPRITE_PIKACHU is in the extracted sprite set",
        game.data.sprites and game.data.sprites.SPRITE_PIKACHU ~= nil)

  -- ShouldPikachuSpawn wants the lab gift flag and a healthy party Pikachu;
  -- the second mon is here so the heal has something to visibly restore.
  game.save.player.name = "bryan"
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.usedPokecenter = false -- BIT_USED_POKECENTER: get the full prompt
  game.save.party = {
    Pokemon.new(game.data, "PIKACHU", 16),
    Pokemon.new(game.data, "PIDGEY", 12),
  }
  -- hurt but not poisoned: a poisoned 1 HP Pikachu faints on the walk over
  -- and ShouldPikachuSpawn would despawn the follower mid-driver
  for _, mon in ipairs(game.save.party) do
    mon.hp = math.max(1, math.floor(mon.stats.hp / 3))
  end

  local function follower()
    local ow = game.overworld
    for _, n in ipairs(ow and ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end

  -- one step in dir, reporting whether the player's cell actually changed;
  -- lets the walks below route around a map edit instead of shoving at a wall
  local function walk(dir)
    local ow = game.overworld
    local x, y = ow.player.cellX, ow.player.cellY
    U.hold(game, dir, 20)
    U.wait(6)
    return ow.player.cellX ~= x or ow.player.cellY ~= y
  end

  -- ------------------------------------------------------------ #411 idle
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)
  check("follower spawned on the map", follower() ~= nil)

  -- a couple of steps first: the follower has to be trailing a cell behind
  -- before standing still means anything
  local walked = 0
  for _, dir in ipairs({ "left", "left", "down", "right" }) do
    if walk(dir) then walked = walked + 1 end
    if walked >= 2 then break end
  end
  check("player took at least two steps before standing still", walked >= 2)
  U.wait(30)

  local npc = follower()
  local IDLE_FRAMES = 540
  local poses, order = {}, {}
  local kinds, kindOrder = {}, {}
  local facings, facingOrder = {}, {}
  local moved, sawIdleRecord = false, false
  local idleStart = U.frame()
  local shotFrames = {}

  if npc then
    for i = 1, IDLE_FRAMES do
      if npc.moving then moved = true end
      local idle = npc.idle
      local kind = idle and idle.kind or "none"
      if idle then sawIdleRecord = true end
      if not kinds[kind] then
        kinds[kind] = 0
        kindOrder[#kindOrder + 1] = kind
      end
      kinds[kind] = kinds[kind] + 1
      if not facings[npc.facing] then
        facings[npc.facing] = true
        facingOrder[#facingOrder + 1] = npc.facing
      end
      -- the pose a human can see: the countdown inside idle is deliberately
      -- left out, since a frozen follower would still tick it down and make
      -- "something changed" true for free
      local pose = string.format("%s|%s|%d,%d|%s", kind, tostring(npc.facing),
                                 math.floor(npc.px - npc.cellX * 16),
                                 math.floor(npc.py - npc.cellY * 16),
                                 tostring(npc.stepFlip))
      if not poses[pose] then
        poses[pose] = true
        order[#order + 1] = pose
      end
      -- five stills spread across the sample, far enough apart to catch a
      -- glance or a bounce between them
      if i % 108 == 0 then
        shotFrames[#shotFrames + 1] = U.frame()
        shot(string.format("bug411_idle_%d", i / 108))
      else
        U.wait(1)
      end
    end
  end

  check("follower stayed put for the whole idle sample", npc ~= nil and not moved)
  check("the follower's idle state exists at all", sawIdleRecord)
  check("its visible pose changed while standing still", #order > 1)
  U.log(("idle sample: %d frames from f%d, %d distinct poses")
          :format(IDLE_FRAMES, idleStart, #order))
  local kindLine = {}
  for _, k in ipairs(kindOrder) do
    kindLine[#kindLine + 1] = k .. "x" .. kinds[k]
  end
  U.log("idle kinds seen:", table.concat(kindLine, " "))
  U.log("facings seen:", table.concat(facingOrder, " "))
  for i = 1, math.min(#order, 8) do U.log("  pose", order[i]) end
  U.log("idle shots at frames:", table.concat(shotFrames, " "))

  -- -------------------------------------------------- #417 Poke Center hop
  -- pokeyellow data/maps/objects/ViridianPokecenter.asm: the nurse is
  -- object 1 at (3, 1), the counter tile is (3, 2) and the player talks to
  -- her from (3, 3) facing up.  Positions below are derived from the loaded
  -- object rather than typed in, so a re-extract or a mod that shifts her
  -- still lands the player at the counter.
  local MAP = "VIRIDIAN_POKECENTER"
  U.teleport(game, MAP, 3, 6, "up")
  U.wait(20)
  local ow = game.overworld

  local nurse
  for _, n in ipairs(ow.npcs or {}) do
    local d = n.def
    if d and (d.sprite == "SPRITE_NURSE" or (d.name or ""):find("NURSE")) then
      nurse = n
      break
    end
  end
  check("nurse object loaded on " .. MAP, nurse ~= nil)
  if nurse then
    local entry = game.data:textEntry(ow.map.def.label, nurse.def.text)
    check("her text entry is the TX_SCRIPT nurse marker",
          entry ~= nil and not not entry.nurse)
  end

  -- stand two cells off the nurse with a counter tile between us: that is
  -- the geometry OverworldState:interact reaches across, and the same
  -- p.facing == "up" + isCounterCell test PikachuFollower.hopToCounter makes
  local stand
  if nurse then
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local counterX, counterY = nurse.cellX + s[1], nurse.cellY + s[2]
      local sx, sy = nurse.cellX + s[1] * 2, nurse.cellY + s[2] * 2
      if ow.map:inBounds(sx, sy) and ow.map:isWalkableCell(sx, sy)
         and ow.map:isCounterCell(counterX, counterY)
         and not ow:npcAtCell(sx, sy) then
        stand = { x = sx, y = sy, facing = s[3] }
        break
      end
    end
  end
  check("found a counter cell to talk across", stand ~= nil)

  if stand then
    -- walk there rather than teleport, so the follower trails in behind and
    -- is standing where the hop actually starts from
    local guard = 0
    while (ow.player.cellY > stand.y) and guard < 8 do
      if not walk("up") then break end
      guard = guard + 1
    end
    while (ow.player.cellX < stand.x) and guard < 12 do
      if not walk("right") then break end
      guard = guard + 1
    end
    while (ow.player.cellX > stand.x) and guard < 12 do
      if not walk("left") then break end
      guard = guard + 1
    end
    while (ow.player.cellY > stand.y) and guard < 16 do
      if not walk("up") then break end
      guard = guard + 1
    end
    if ow.player.cellX ~= stand.x or ow.player.cellY ~= stand.y then
      U.log("walk did not reach the counter, teleporting to",
            stand.x, stand.y)
      U.teleport(game, MAP, stand.x, stand.y, stand.facing)
      U.wait(20)
      ow = game.overworld
    end
    ow.player.facing = stand.facing
    U.wait(10)
  end

  local fx, fy = ow.player:facingCell()
  check("player is at the counter facing the nurse",
        ow.map:isCounterCell(fx, fy) and ow.player.facing == "up")
  check("follower survived the walk over", follower() ~= nil)
  shot("bug417_at_counter")

  -- talk, say YES, and mash through the whole sequence; stop the moment the
  -- overworld is back on top so the last A cannot re-open the nurse
  local hurt = 0
  for _, mon in ipairs(game.save.party) do
    if mon.hp < mon.stats.hp then hurt = hurt + 1 end
  end
  check("the party is hurt going in, so the heal check means something",
        hurt == #game.save.party)

  U.tap(game, "a")
  U.wait(10)
  local sawHop, sawMachine, hopFrames = false, false, 0
  local shotHop, shotMachine, shotLeg, shotBack, shotBow = false, false, false, false, false
  local overlapFrames, hopLegs = 0, 0
  local runs = {}
  local sawBowFrame, bowSheetOk = false, false
  local function noteFacing(phase)
    if not nurse then return end
    local last = runs[#runs]
    if last and last.facing == nurse.facing and last.phase == phase then
      last.n = last.n + 1
    else
      runs[#runs + 1] = { facing = nurse.facing, phase = phase, n = 1 }
    end
  end
  local phase = "talk"
  for _ = 1, 800 do
    local cur = game.overworld
    local pika = follower()
    if cur.pikaHop then
      sawHop = true
      hopFrames = hopFrames + 1
      -- engine/pikachu/pikachu_emotions.asm:460
      if pika then
        local p = cur.player
        local cx, cy = pika.px + 8, pika.py + 8
        if cx >= p.px and cx < p.px + 16 and cy >= p.py and cy < p.py + 16 then
          overlapFrames = overlapFrames + 1
        end
      end
      if cur.pikaHop.leg and cur.pikaHop.leg > hopLegs then
        hopLegs = cur.pikaHop.leg
        if hopLegs == 2 and not shotLeg then shotLeg = shot("bug2123_hop_leg2") end
      end
      if not shotHop and hopFrames > 48 then
        shotHop = shot("bug417_hop")
      end
    end
    if cur.healAnim then
      phase = "machine"
      sawMachine = true
      if not shotMachine then shotMachine = shot("bug417_machine") end
    elseif phase == "machine" and not cur.healAnim then
      phase = "after"
    elseif phase == "talk" and cur.emote and game.stack:top() == cur then
      phase = "before"
    end
    if phase ~= "talk" then noteFacing(phase) end
    if nurse and phase == "before" and nurse.facing == "up" and not shotBack then
      shotBack = shot("bug2123_nurse_back")
    end
    if nurse and nurse.frameOverride == 3 then
      sawBowFrame = true
      bowSheetOk = nurse.sprite and nurse.sprite.frames and nurse.sprite.frames[3] ~= nil
      if not shotBow then shotBow = shot("bug2123_nurse_bow") end
    end
    -- the hop deliberately runs with the overworld back on top (both text
    -- boxes have popped themselves by then), so "overworld is top" alone is
    -- not the end of the sequence -- wait for the party to be healed and
    -- both held animations to be over
    local partyUp = #game.save.party > 0
    for _, mon in ipairs(game.save.party) do
      if mon.hp ~= mon.stats.hp then partyUp = false end
    end
    if partyUp and not cur.pikaHop and not cur.healAnim and not cur.emote
       and game.stack:top() == cur then
      break
    end
    U.tap(game, "a")
    U.wait(4)
  end
  U.wait(30)

  check("the heal script ran back out to the overworld",
        game.stack:top() == game.overworld)
  check("Pikachu hopped to the counter (#417)", sawHop)
  check("Pikachu went around the player, never through him (#2123)",
        sawHop and overlapFrames == 0)
  check("the hop from behind the player is two legs (#2123)", hopLegs == 2)
  U.log(("hop: %d frames, %d legs, %d frames overlapping the player")
          :format(hopFrames, hopLegs, overlapFrames))
  check("the healing machine ran", sawMachine)
  local seq = {}
  for _, r in ipairs(runs) do seq[#seq + 1] = r.phase .. ":" .. tostring(r.facing) .. "x" .. r.n end
  U.log("nurse facing runs (samples of 5 frames):", table.concat(seq, " "))
  local function run(phaseName, facing, index)
    local seen = 0
    for _, r in ipairs(runs) do
      if r.phase == phaseName and r.facing == facing then
        seen = seen + 1
        if seen == index then return r end
      end
    end
    return nil
  end
  local backBefore = run("before", "up", 1)
  check("she shows her back before turning to the machine (#2123)",
        backBefore ~= nil and backBefore.n >= 10)
  local leftBefore = run("before", "left", 1)
  check("then turns left for the machine", leftBefore ~= nil)
  local backAfter = run("after", "up", 1)
  check("she shows her back again after the machine (#2123)",
        backAfter ~= nil and backAfter.n >= 10)
  local downAfter = run("after", "down", 1)
  check("then faces the player before fighting fit", downAfter ~= nil)
  check("the bow uses the 4th sheet frame (#2123)", sawBowFrame)
  check("the Yellow nurse sheet has that 4th frame", bowSheetOk)
  local healed = #game.save.party > 0
  for _, mon in ipairs(game.save.party) do
    if mon.hp ~= mon.stats.hp or mon.status ~= nil then healed = false end
  end
  check("the party is actually healed", healed)
  local pika = follower()
  check("follower is back on screen after the heal", pika ~= nil)
  if pika then
    U.log(("follower rests at cell (%d, %d) facing %s")
            :format(pika.cellX, pika.cellY, tostring(pika.facing)))
  end
  shot("bug417_after_heal")

  U.log(ok and "ALL PASS" or "SOME CHECKS FAILED")
  for _, s in ipairs(shots) do U.log("shot", s) end

  U.log("Standing still with Pikachu right behind you, all it should do is")
  U.log("glance around: pikachu_follow.asm only rolls the bounce/spin/shuffle")
  U.log("animations when the follower is 2+ cells adrift, so at a normal one")
  U.log("cell gap the facing changes ARE the whole idle behaviour.  A sprite")
  U.log("frozen one way for the whole sample is the bug.  To see the livelier")
  U.log("animations, strand it first -- hop a ledge or cut through a door so")
  U.log("it falls behind, then stand still before it catches up.")
  U.log("You are parked at the Viridian counter facing the nurse: press A and")
  U.log("say YES to watch Pikachu jump up onto the counter again.")

  while true do
    coroutine.yield()
  end
end
