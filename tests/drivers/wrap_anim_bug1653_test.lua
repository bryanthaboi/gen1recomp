-- Driver: Wrap's animation length and the blank tile-load beat that opens every
-- subanimation row (#1653).  PlayAnimation calls LoadMoveAnimationTiles once per
-- row (engine/battle/animations.asm:252) and CopyVideoData blocks c/8 + 1 frames
-- (home/copy2.asm:62), so WrapAnim's three rows (data/moves/animations.asm:401)
-- cost 3 x 10 blank frames on top of the 30 the port already played.
-- No POKEPORT_SPEED: it scales only the logic clock while audio runs real-time,
-- which desyncs the sfx-against-pulse ordering this driver exists to judge.
--   POKEPORT_DRIVER=tests/drivers/wrap_anim_bug1653_test.lua POKEPORT_VERSION=red POKEPORT_TOUCH=0 POKEPORT_IDENTITY=bug1653 SHOT_DIR=/tmp/wrap love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local AnimPlayer = require("src.battle.AnimPlayer")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the eye and ear cannot check ---------------------------------
  U.log("#1653 Wrap animation length: machine checks")

  local ba = game.data.battle_anims
  check("battle_anims is in the cache", ba ~= nil)
  local anims = (ba or {}).moveAnims or {}
  check("WRAP is in the move table", game.data.moves.WRAP ~= nil)
  check("WRAP has an animation", anims.WRAP ~= nil)

  -- anim_tileset 79 / 79 / 64 (engine/battle/animations.asm:383): 79 tiles is
  -- nine 8-tile chunks plus the tail frame, so tileset 0 blocks 10 frames
  local sheet0 = (ba or {}).tilesheets and ba.tilesheets[0]
  check(("tileset 0 declares %s tiles (anim_tileset 79)")
          :format(tostring(sheet0 and sheet0.tiles)),
        sheet0 ~= nil and sheet0.tiles == 79)

  -- WrapAnim is three identical rows: SUBANIM_0_BIND on tileset 0, delay 4
  local seq = (anims.WRAP or {}).seq or {}
  check(("WRAP is %d subanimation rows (want 3)"):format(#seq), #seq == 3)
  local rowsOk = #seq == 3
  for _, row in ipairs(seq) do
    rowsOk = rowsOk and row.effect == nil and row.tileset == 0
             and row.delay == 4 and row.sound == "WRAP"
  end
  check("every WRAP row is a tileset-0 subanimation with sound WRAP", rowsOk)

  -- The move id in the row resolves to a real sfx program through moves.lua
  local sfxName = (game.data.moves.WRAP or {}).anim
                  and game.data.moves.WRAP.anim.sound
  check("WRAP's row sound resolves to a program (" .. tostring(sfxName) .. ")",
        sfxName ~= nil and ((game.data.audio or {}).sfx or {})[sfxName] ~= nil)

  -- ---- the compiled timeline ---------------------------------------------
  local function compile(move)
    if not (ba and anims[move]) then return nil end
    local p = AnimPlayer.new(ba)
    local ok = pcall(p.start, p, move, false)
    if not ok then return nil end
    return p
  end

  local function total(p)
    local n = 0
    for _, s in ipairs(p.steps) do n = n + s.dur end
    return n
  end

  local function shapeOf(p)
    local out = {}
    for _, s in ipairs(p.steps) do
      out[#out + 1] = ("%d/%d"):format(s.dur, #s.sprites)
    end
    return table.concat(out, " ")
  end

  -- which step is on screen at `elapsed`, mirroring AnimPlayer:update
  local function stepAt(p, elapsed)
    local acc = 0
    for _, s in ipairs(p.steps) do
      acc = acc + s.dur
      if elapsed < acc then return s end
    end
    return nil
  end

  local wrap = compile("WRAP")
  check("WRAP compiles into a timeline", wrap ~= nil)

  if wrap then
    U.log("  WRAP steps: " .. shapeOf(wrap))
    check(("WRAP is %d frames long (want 60, half-length bug gives 30)")
            :format(total(wrap)), total(wrap) == 60)
    check(("WRAP compiles to %d steps (want 9: three rows of load + 2 blocks)")
            :format(#wrap.steps), #wrap.steps == 9)

    local shapeOk = #wrap.steps == 9
    for i = 1, 9 do
      local s = wrap.steps[i]
      if not s then shapeOk = false break end
      if i % 3 == 1 then
        shapeOk = shapeOk and s.dur == 10 and #s.sprites == 0
      else
        shapeOk = shapeOk and s.dur == 5 and #s.sprites == 8
      end
    end
    check("steps 1, 4 and 7 are 10 blank frames and the other six are 5 frames "
            .. "of 8 sprites", shapeOk)

    -- Near-miss guard.  Paying the 10 frames AFTER a row's blocks also totals
    -- 60, but it opens on sprites and ends on a blank tail, and every sound
    -- lands 10 frames early.
    local first, last = wrap.steps[1], wrap.steps[#wrap.steps]
    check("the blank beat OPENS the animation (step 1 is blank, 10 frames)",
          first ~= nil and #first.sprites == 0 and first.dur == 10)
    check("...and does not close it (the last step draws sprites)",
          last ~= nil and #last.sprites > 0)

    local sounds = {}
    for _, ev in ipairs(wrap.events) do
      if ev.sound then sounds[#sounds + 1] = ev end
    end
    check(("WRAP queues %d row sounds (want 3)"):format(#sounds), #sounds == 3)
    local want = { 10, 30, 50 }
    for i = 1, 3 do
      local ev = sounds[i]
      check(("sound %d fires at frame %s (want %d, after that row's tile load)")
              :format(i, ev and tostring(ev.frame) or "nil", want[i]),
            ev ~= nil and ev.frame == want[i] and ev.sound == "WRAP")
      if ev then
        local st = stepAt(wrap, ev.frame)
        check(("sound %d lands on a frame with sprites on screen, not on the "
                 .. "blank beat"):format(i),
              st ~= nil and #st.sprites > 0)
      end
    end
  end

  -- ---- the same load, elsewhere: this was never Wrap-specific ------------
  -- POUND is one tileset-0 row, so it gains the same 10 frames.
  local pound = compile("POUND")
  if pound then
    local s = pound.steps[1]
    check(("POUND also opens on a 10-frame blank load (%s)")
            :format(s and ("%d/%d"):format(s.dur, #s.sprites) or "nil"),
          s ~= nil and s.dur == 10 and #s.sprites == 0)
  end

  -- Tileset 2 declares 64 tiles, which is eight chunks plus the tail: 9 frames.
  local ball = compile("TRADE_BALL_DROP_ANIM")
  if ball then
    local s = ball.steps[1]
    check(("a tileset-2 animation opens on 9 blank frames instead of 10 (%s)")
            :format(s and ("%d/%d"):format(s.dur, #s.sprites) or "nil"),
          s ~= nil and s.dur == 9 and #s.sprites == 0)
  end

  -- Control: TACKLE's animation is two special-effect rows and no subanimation,
  -- so PlayAnimation never reaches LoadMoveAnimationTiles and nothing changes.
  local tackle = compile("TACKLE")
  if tackle then
    check(("TACKLE, which has no subanimation row, is still %d frames "
             .. "(the load is not charged blindly)"):format(total(tackle)),
          total(tackle) == 6)
  end

  -- ---- options that would fake a failure ---------------------------------
  local opts = game.save.options or {}
  check("battle animations are on in OPTION", opts.animations ~= false)
  if opts.animations == false then
    U.log("  ANIMATION is off, which skips the whole queued row: turn it on")
    U.log("  in OPTION before judging anything below")
  end
  local vol = opts.sfxVol
  if vol == 0 then
    U.log("  sfxVol is 0: all three WRAP sfx will be SILENT, which sounds")
    U.log("  exactly like the bug. Raise SFX in OPTION before listening")
  else
    U.log("  sfxVol " .. tostring(vol) .. ", so the three squeezes should be audible")
  end

  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))
  if fail > 0 then
    U.log("something above says FAIL, so do not spend time watching the screen")
  end
  if not game.data.moves.WRAP then
    U.log("no WRAP in the move table, so there is nothing to put on screen")
    while true do coroutine.yield() end
  end

  -- ---- put a Wrap on screen ----------------------------------------------
  -- data/generated/maps.lua ROUTE_1 is 10x18 blocks of open route, and pokered
  -- data/maps/objects/Route1.asm parks its two youngsters at (5, 24) and
  -- (15, 13), so the north end is empty.  (5, 5) sits in the fence line in the
  -- current cache, so the neighbour fallback below is the one that runs; the
  -- battle is pushed straight in either way.
  local MAP, SX, SY = "ROUTE_1", 5, 5

  local ekans = Pokemon.new(game.data, "EKANS", 30)
  ekans.moves = { { id = "WRAP", pp = game.data.moves.WRAP.pp } }
  game.save.party = { ekans }
  game.save.player.name = "RED"

  U.teleport(game, MAP, SX, SY, "down")
  U.wait(12)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(SX, SY) then
    -- a map edit blocked the cell: take the nearest free neighbour instead
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = SX + d[1], SY + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on %d, %d"):format(SX, SY, cx, cy))
        U.teleport(game, MAP, cx, cy, "down")
        U.wait(12)
        ow = game.overworld
        break
      end
    end
  end
  check("the overworld is up on " .. MAP, ow ~= nil and ow.map.id == MAP)

  local battle = BattleState.newWild(game, "PIDGEY", 20)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)

  -- a foe that survives the wrap chain, so the animation can repeat
  battle.enemy.mon.stats.hp = 500
  battle.enemy.mon.hp = 500
  battle.enemy.shownHP = 500
  -- a wild PIDGEY that knows WHIRLWIND ends the fight the moment it picks it
  for i = #battle.enemy.mon.moves, 1, -1 do
    local id = battle.enemy.mon.moves[i].id
    if id == "WHIRLWIND" or id == "ROAR" or id == "TELEPORT" then
      table.remove(battle.enemy.mon.moves, i)
    end
  end

  -- ---- watch the live playback -------------------------------------------
  -- every frame the player is playing, record whether sprites are on screen,
  -- so the blank load beats show up as runs in the trace
  local runs, cur = {}, nil
  if battle.animPlayer then
    local realStart = battle.animPlayer.start
    battle.animPlayer.start = function(self, moveId, isPlayer, o)
      local r = realStart(self, moveId, isPlayer, o)
      cur = { move = moveId, marks = {} }
      runs[#runs + 1] = cur
      return r
    end
  end

  -- U.shot spins frames of its own, which would punch a hole in the trace, so
  -- the measuring turn runs with `shooting` off and a later turn takes the shot
  local shooting, shot = false, false
  local function sample()
    if not (battle.animPlaying and cur and battle.animPlayer) then return end
    local ap = battle.animPlayer
    local st = ap.steps[ap.stepIndex]
    if not st then return end
    local lit = #st.sprites > 0
    cur.marks[#cur.marks + 1] = lit and 1 or 0
    if shooting and not shot and lit and cur.move == "WRAP" then
      shot = true
      U.shot(game, DIR .. "/bug1653_wrap_squeeze.png")
    end
  end

  local function runLengths(marks)
    local out, run, val = {}, 0, nil
    for _, m in ipairs(marks) do
      if m ~= val then
        if val ~= nil then
          out[#out + 1] = ("%s %d"):format(val == 1 and "sprites" or "blank", run)
        end
        val, run = m, 0
      end
      run = run + 1
    end
    if val ~= nil then
      out[#out + 1] = ("%s %d"):format(val == 1 and "sprites" or "blank", run)
    end
    return table.concat(out, ", ")
  end

  -- step n frames, sampling each one, pressing A only while a box is up: an A
  -- on the FIGHT menu opens the move list and fires a move behind our back
  local function pump(n, mash, stop)
    for i = 1, n do
      if mash and i % mash == 0 and battle.phase == "messages" then
        table.insert(game.input.pressQueue, "a")
      end
      U.wait(1)
      game.input.state.a = false
      sample()
      if stop and stop() then return end
    end
  end

  local function toMenu()
    pump(1200, 6, function() return battle.phase == "menu" and #battle.queue == 0 end)
    return battle.phase == "menu"
  end

  -- FIGHT is menuIndex 1 of the 2x2 grid, and WRAP is the only move on the list
  local function useWrap()
    for _ = 1, 80 do
      if battle.phase == "moveSelect" then break end
      if battle.phase == "menu" then
        if battle.menuIndex ~= 1 then
          U.tap(game, battle.menuIndex > 2 and "up" or "left")
        else
          U.tap(game, "a")
        end
      else
        U.tap(game, "a")
      end
      for _ = 1, 3 do U.wait(1) sample() end
    end
    if battle.phase ~= "moveSelect" then return false end
    for _ = 1, 20 do
      if battle.phase ~= "moveSelect" then return true end
      U.tap(game, "a")
      for _ = 1, 3 do U.wait(1) sample() end
    end
    return false
  end

  -- the foe animates too, so pick the player's WRAP row out of the list
  local function wrapRun()
    for i = #runs, 1, -1 do
      if runs[i].move == "WRAP" and #runs[i].marks > 0 then return runs[i] end
    end
    return nil
  end

  check("the battle reached its FIGHT menu", toMenu())

  local sent = false
  for _ = 1, 6 do
    -- WRAP is 85% accurate and the foe leans on SAND-ATTACK, so hand the
    -- accuracy back each try rather than reading a whiff as a regression
    battle.player.stages.accuracy = 0
    sent = useWrap()
    if not sent then break end
    pump(900, 8, function()
      return wrapRun() ~= nil and not battle.animPlaying
    end)
    if wrapRun() then break end
    U.log("  WRAP did not connect that turn; using it again")
    toMenu()
  end
  check("chose WRAP from the move menu", sent)

  local played = wrapRun()
  check("WRAP's animation actually played on screen", played ~= nil)
  if played then
    U.log(("  live playback: %d frames, %s")
            :format(#played.marks, runLengths(played.marks)))
    -- the sampler runs once per fixed step and can slip a frame against the
    -- battle's own update, so the compiled timeline above is the exact
    -- authority; this only has to rule out the 30-frame version
    check(("live playback is around 60 frames, not 30 (measured %d)")
            :format(#played.marks), #played.marks >= 50)
  end
  -- WRAP traps the foe, so the next turn replays it: measurement is done, so
  -- now let the sampler stop and catch a squeeze mid-coil for the record
  shooting = true
  for _ = 1, 4 do
    if shot then break end
    if battle.phase == "menu" then
      battle.player.stages.accuracy = 0
      if not useWrap() then break end
    end
    pump(600, 8, function() return shot end)
  end
  if not shot then U.log("  no lit WRAP frame to capture") end
  U.shot(game, DIR .. "/bug1653_wrap_after.png")

  -- ---- hand off ----------------------------------------------------------
  U.log("the pad is yours in a battle where the EKANS knows only WRAP (#1653),")
  U.log("so pick FIGHT then WRAP and watch. the coils should squeeze the PIDGEY")
  U.log("three separate times, each squeeze about a sixth of a second, with a")
  U.log("clear blank beat of the same length before each one -- roughly a second")
  U.log("end to end. the old bug ran the three squeezes together as one half-")
  U.log("second smear with no gaps.")
  U.log("listen as well as look: each of the three WRAP sfx should land as the")
  U.log("coils appear. an sfx that fires while the screen is still blank, with")
  U.log("the pause moved to the end of the animation, is the near miss that")
  U.log("still measures 60 frames.")
  U.log("wrap traps the foe, so the animation repeats over the next few turns")
  U.log("and you can watch it more than once. any other move works the same")
  U.log("way: every animation in the game now opens on that blank beat.")
  U.log("screenshots: " .. DIR .. "/bug1653_*.png")

  while true do
    coroutine.yield()
  end
end
