-- Driver: the applying-attack shake pokered plays after a move's own
-- animation (#354).  PlayApplyingAttackAnimation dispatches wAnimationType
-- 1..6 through AnimationTypePointerTable (engine/battle/animations.asm:475);
-- only 1 (vertical shake) and 4 (blink the enemy pic) were wired, so an
-- added-effect move like BUBBLEBEAM blinked instead of shaking sideways and a
-- status move showed nothing.  Wiring half: tests/parity_applying_attack_anim.lua.
-- Never under POKEPORT_SPEED: fast-forward desynchronizes the damage sound.
--   POKEPORT_DRIVER=tests/drivers/battle_shake_bug354_test.lua POKEPORT_IDENTITY=bug354 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- pokered core.asm:3159 / effects.asm:1448: a player damaging move with an
  -- added effect is type 5, without one type 4, and a primary status effect
  -- that ends in PlayCurrentMoveAnimation2 is type 6.  `frames` counts only
  -- the frames the screen sits off-centre: b=2 out for 5 frames twice, and
  -- the slow creep's five off-centre steps of 2 frames, twice over.
  local MOVES = {
    { slot = 1, id = "BUBBLEBEAM", want = 5, peak = 2, frames = 10 },
    { slot = 4, id = "TACKLE",     want = 4 },
    { slot = 3, id = "GROWL",      want = 6, peak = 3, frames = 20 },
    { slot = 2, id = "HYPNOSIS",   want = 6, peak = 3, frames = 20 },
  }

  U.log("#354 applying-attack shake: machine checks")
  for _, m in ipairs(MOVES) do
    check(m.id .. " is in the move table", game.data.moves[m.id] ~= nil)
  end
  local anims = game.data.battle_anims and game.data.battle_anims.moveAnims
  check("battle_anims carries BUBBLEBEAM's own animation",
        anims ~= nil and anims.BUBBLEBEAM ~= nil)
  check("...and HYPNOSIS's", anims ~= nil and anims.HYPNOSIS ~= nil)
  check("BattleState:applyHitFx exists", type(BattleState.applyHitFx) == "function")
  check("animations are on in OPTIONS (a shake is gated on them)",
        game.save.options.animations ~= false)

  local vol = game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the damage thud under the shake will be SILENT,")
    U.log("raise it in OPTION before judging the sound")
  else
    U.log("sfxVol", tostring(vol), "-- the damage thud opens types 1, 2, 4 and 5;")
    U.log("types 3 and 6 (the slow creeps) are silent on purpose")
  end

  -- ---- fixture -----------------------------------------------------------
  local squirtle = Pokemon.new(game.data, "SQUIRTLE", 30)
  squirtle.moves = {}
  for _, m in ipairs(MOVES) do
    squirtle.moves[m.slot] = { id = m.id, pp = game.data.moves[m.id].pp }
  end
  game.save.party = { squirtle }
  game.save.player.name = "RED"

  -- data/generated/maps.lua ROUTE_1: (5, 5) is open walkable ground, and the
  -- battle is pushed straight in rather than encountered
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  if not ow.map:isWalkableCell(5, 5) then
    -- a map edit moved the path: take the nearest walkable cell instead
    local sx, sy
    for r = 1, 6 do
      for dy = -r, r do
        for dx = -r, r do
          if not sx and ow.map:isWalkableCell(5 + dx, 5 + dy) then
            sx, sy = 5 + dx, 5 + dy
          end
        end
      end
      if sx then break end
    end
    if sx then
      U.log("(5, 5) is blocked, standing on", sx, sy)
      U.teleport(game, "ROUTE_1", sx, sy, "down")
      U.wait(10)
      ow = game.overworld
    end
  end
  check("the overworld is up on ROUTE_1", ow ~= nil)

  local battle = BattleState.newWild(game, "PIDGEY", 20)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)

  -- a foe that survives four turns: every type needs its own turn to show
  battle.enemy.mon.stats.hp = 400
  battle.enemy.mon.hp = 400
  battle.enemy.shownHP = 400

  -- A PIDGEY that level knows WHIRLWIND, and in a wild battle that blows the
  -- player out of the fight (result "run") the moment the foe picks it, which
  -- takes the untested types down with it.  Drop it and the foe keeps the
  -- GUST / SAND-ATTACK / QUICK ATTACK the hand-off notes below describe.
  -- curMoves aliases mon.moves, so one pass covers both.
  for i = #battle.enemy.mon.moves, 1, -1 do
    local id = battle.enemy.mon.moves[i].id
    if id == "WHIRLWIND" or id == "ROAR" or id == "TELEPORT" then
      table.remove(battle.enemy.mon.moves, i)
    end
  end

  -- ---- watch the fx layer ------------------------------------------------
  -- one entry per applying-attack row, labelled with the move that queued it
  local rows, cur, using = {}, nil, nil
  local realPerform, realFx = battle.performMove, battle.applyHitFx
  battle.performMove = function(self, user, target, moveInst, ...)
    using = { id = moveInst and moveInst.id, isPlayer = user.isPlayer }
    return realPerform(self, user, target, moveInst, ...)
  end
  battle.applyHitFx = function(self, hit)
    cur = { move = using and using.id, isPlayer = using and using.isPlayer,
            animType = hit.animType, frames = 0, peakX = 0, peakY = 0 }
    rows[#rows + 1] = cur
    realFx(self, hit)
    -- a spent blink table stays on fx with frames = 0, so freshness matters
    local bl = self.fx and self.fx.blink
    cur.blinked = bl ~= nil and bl.frames > 0
  end

  local function sample()
    local fx = battle.fx
    if not (cur and fx) then return end
    local dx, dy = math.abs(fx.shakeX or 0), math.abs(fx.shakeY or 0)
    if dx > 0 or dy > 0 then
      cur.frames = cur.frames + 1
      cur.peakX = math.max(cur.peakX, dx)
      cur.peakY = math.max(cur.peakY, dy)
    end
  end

  -- step n frames, sampling every one, pressing A every `mash` frames -- but
  -- only while a box is up.  An A that lands on the FIGHT menu opens the move
  -- list and fires the highlighted move, so mashing past the end of a turn
  -- starts extra turns behind the driver's back and eventually ends the battle.
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

  -- a full turn is the player's announcement, animation and damage drain plus
  -- the foe's, so budget frames for the slowest of them rather than the typical
  -- one: a short budget hands the next move a battle still in `messages`
  local function toMenu()
    pump(1200, 6, function() return battle.phase == "menu" and #battle.queue == 0 end)
    return battle.phase == "menu"
  end

  -- The move list is a flat column in the classic layout, but the wide one
  -- lays the four slots out 2x2 (WideBattle.navigate): up/down swap rows and
  -- left/right swap columns, so walking down the list there never reaches
  -- slots 2 and 4.  Return the press that closes the gap in either layout.
  local function towardSlot(slot)
    if battle.moveIndex == slot then return nil end
    if battle:wideLayout() then
      local row, col = math.floor((battle.moveIndex - 1) / 2), (battle.moveIndex - 1) % 2
      local wantRow, wantCol = math.floor((slot - 1) / 2), (slot - 1) % 2
      if row ~= wantRow then return row < wantRow and "down" or "up" end
      return col < wantCol and "right" or "left"
    end
    return battle.moveIndex < slot and "down" or "up"
  end

  -- FIGHT is menuIndex 1 of the 2x2 grid; A opens moveSelect, where the presses
  -- above walk the slots.  A press that lands on a frame the battle is not
  -- reading input is simply lost, so every step retries instead of assuming.
  local function useMove(slot)
    for _ = 1, 80 do
      if battle.phase == "moveSelect" then break end
      if battle.phase == "menu" then
        if battle.menuIndex ~= 1 then
          U.tap(game, battle.menuIndex > 2 and "up" or "left")
        else
          U.tap(game, "a")
        end
      else
        -- the last turn's boxes are still up: keep turning pages
        U.tap(game, "a")
      end
      U.wait(4)
    end
    if battle.phase ~= "moveSelect" then return false end
    for _ = 1, 30 do
      local dir = towardSlot(slot)
      if not dir then break end
      U.tap(game, dir)
      U.wait(3)
    end
    if battle.moveIndex ~= slot then return false end
    for _ = 1, 20 do
      if battle.phase ~= "moveSelect" then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return false
  end

  local function lastRowFor(id)
    for i = #rows, 1, -1 do
      if rows[i].move == id and rows[i].isPlayer then return rows[i] end
    end
    return nil
  end

  local SHOTS = { BUBBLEBEAM = "bug354_bubblebeam_shake.png",
                  HYPNOSIS = "bug354_hypnosis_creep.png",
                  TACKLE = "bug354_tackle_blink.png" }

  check("the battle reached its FIGHT menu", toMenu())

  for _, m in ipairs(MOVES) do
    -- catch the shake mid-flight for the screenshot: the offset is live for
    -- only a couple of dozen frames
    local shotAt
    -- HYPNOSIS lands 6 times in 10 and TACKLE 19 in 20, and a miss plays no
    -- applying-attack animation at all, so give each move a few turns to
    -- connect instead of reading a whiffed one as a regression
    local sent, r
    for _ = 1, 8 do
      -- the foe leans on SAND-ATTACK, and stacked accuracy drops make even
      -- TACKLE whiff turn after turn, so hand the accuracy back each try
      battle.player.stages.accuracy = 0
      sent = useMove(m.slot)
      if not sent then break end
      -- A every 8 frames: the text box between the announcement and the
      -- animation waits on the button like any other
      pump(1200, 8, function()
        local live = battle.fx and (m.peak and (battle.fx.shakeX or 0) ~= 0
                                    or (not m.peak and battle.fx.blink
                                        and battle.fx.blink.frames > 0))
        if not shotAt and live and SHOTS[m.id] then
          shotAt = true
          U.shot(game, DIR .. "/" .. SHOTS[m.id])
        end
        local row = lastRowFor(m.id)
        -- back at the menu with the row in hand: the turn is over either way
        if row and battle.phase == "menu" and #battle.queue == 0 then return true end
        return row ~= nil and battle.fx.shakeProg == nil
               and (row.frames > 0 or row.blinked)
      end)
      toMenu()
      r = lastRowFor(m.id)
      if r then break end
      U.log("  " .. m.id .. " did not connect that turn; using it again")
    end
    check("chose " .. m.id .. " from the move menu", sent)
    if sent then
      check(m.id .. " queued an applying-attack row", r ~= nil)
      if r then
        check(("%s is animation type %d (got %s)")
                :format(m.id, m.want, tostring(r.animType)),
              r.animType == m.want)
        U.log(("  %s: %d frames off-centre, peak %dpx across / %dpx down, blink %s")
                :format(m.id, r.frames, r.peakX, r.peakY, tostring(r.blinked)))
        if m.peak then
          -- the exact frame count is pinned in the parity suite; sampling from
          -- a driver misses a frame whenever the logic step outruns the render
          check(("%s moved the screen %dpx sideways"):format(m.id, m.peak),
                r.peakX == m.peak)
          check(("%s held it off-centre (%d of the routine's %d frames)")
                  :format(m.id, r.frames, m.frames), r.frames > 0)
          check(m.id .. " did not blink the enemy pic instead (#354)",
                r.blinked == false)
        else
          check(m.id .. " still blinks the enemy pic and holds still",
                r.blinked == true and r.frames == 0)
        end
      end
      if SHOTS[m.id] and not shotAt and m.peak then
        U.log("  no off-centre frame to capture for " .. m.id)
      end
    end
  end

  -- the foe's own turns: a plain damaging move is type 1, one with an added
  -- effect type 2, SAND-ATTACK type 3
  local foe = {}
  for _, r in ipairs(rows) do
    if not r.isPlayer then
      foe[#foe + 1] = ("%s type %s (%d frames, %dpx across, %dpx down)")
                        :format(tostring(r.move), tostring(r.animType),
                                r.frames, r.peakX, r.peakY)
    end
  end
  U.log("the foe's rows so far: " .. (#foe > 0 and table.concat(foe, "; ")
                                      or "none yet"))
  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- hand off ----------------------------------------------------------
  U.log("The pad is yours at the FIGHT menu.  Slot 1 BUBBLEBEAM: after the")
  U.log("bubbles and their white flashes the whole screen -- field, HUD, text")
  U.log("box -- snaps 2px right and home four times, with the damage thud.")
  U.log("Slot 2 HYPNOSIS and slot 3 GROWL creep it 1px at a time out to 3px")
  U.log("and back, twice, in silence.  Slot 4 TACKLE is the control: the foe's")
  U.log("pic blinks and nothing moves.  Let the PIDGEY hit back too -- a plain")
  U.log("move drops the screen 8px vertically, SAND-ATTACK creeps it 6px across.")
  U.log("Reference: https://youtu.be/4aBT7rjZoIE at 1:19.")
  U.log("Screenshots: " .. DIR .. "/bug354_*.png")

  while true do
    coroutine.yield()
  end
end
