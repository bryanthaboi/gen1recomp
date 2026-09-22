-- scripts/MtMoonB2F.asm:225
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local TextBox = require("src.render.TextBox")
  local GameVersion = require("src.core.GameVersion")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR")
              or "/tmp/shots/2340"
  pcall(function() io.stdout:setvbuf("no") end)

  local MAP = "MT_MOON_B2F"
  local TRIGGER = { x = 3, y = 5 }
  local JESSIE, JAMES = "MTMOONB2F_JESSIE", "MTMOONB2F_JAMES"
  local BEAT = "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES"
  local failed = false

  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end

  local function finish()
    print(failed and "FAIL 2340 overall" or "PASS 2340 overall")
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local function npcNamed(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local function autoBox(delay)
    local top = game.stack:top()
    if getmetatable(top) == TextBox and top.auto and top.auto.delay == delay then
      return top
    end
    return nil
  end

  if not check("2340 running Yellow", GameVersion.isYellow()) then finish() end

  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "TACKLE", pp = 35 } }
  game.save.party = { mon }
  game.save.flags[BEAT] = nil
  game.save.flags.EVENT_GOT_HELIX_FOSSIL = true

  local ow
  local approaches = {
    { TRIGGER.x, TRIGGER.y - 1, "down" },
    { TRIGGER.x + 1, TRIGGER.y, "left" },
    { TRIGGER.x - 1, TRIGGER.y, "right" },
    { TRIGGER.x, TRIGGER.y + 1, "up" },
  }
  local before
  for _, a in ipairs(approaches) do
    U.teleport(game, MAP, a[1], a[2], a[3])
    ow = game.overworld
    if ow.map:isWalkableCell(a[1], a[2]) and not ow:npcAtCell(a[1], a[2]) then
      U.hold(game, a[3], 20)
      U.wait(2)
      if ow.runner:isRunning() then before = a[3] break end
    end
  end
  if not check("2340 the ambush fired on (3,5)", ow.runner:isRunning()) then
    finish()
  end
  U.log("pre-trigger facing", before)

  local box
  for _ = 1, 300 do
    box = autoBox(91)
    if box then break end
    U.wait(1)
  end
  if not check("2340 motto box is armed no-wait (auto delay 91)", box ~= nil) then
    finish()
  end
  for _ = 1, 300 do
    if box.done then break end
    U.wait(1)
  end
  local typedAt = U.frame()
  U.shot(game, DIR .. "/2340_01_motto_typed_no_arrow.png")
  check("2340 motto box shows no blinking arrow", not box:arrowVisible())

  local sawBubble, bubbleFacingOk, bubbleShot = false, true, false
  local sawTurnUnderBox, turnShot = false, false
  local poppedAt
  for _ = 1, 400 do
    if game.stack:top() ~= box then poppedAt = U.frame() break end
    if ow.emote and ow.emote.npc == ow.player then
      sawBubble = true
      if ow.player.facing ~= before then bubbleFacingOk = false end
      if not bubbleShot then
        bubbleShot = true
        U.shot(game, DIR .. "/2340_02_bubble_over_motto_box.png")
      end
    elseif sawBubble and ow.player.facing == "up" then
      sawTurnUnderBox = true
      if not turnShot then
        turnShot = true
        U.shot(game, DIR .. "/2340_03_bubble_gone_facing_up_box_up.png")
      end
    end
    U.wait(1)
  end
  check("2340 motto box closed with no button press", poppedAt ~= nil)
  local held = poppedAt and (poppedAt - typedAt) or -1
  U.log("motto box held", held, "frames after typing")
  check("2340 motto box held ~91 frames after typing (got " .. held .. ")",
        held >= 85 and held <= 100)
  check("2340 exclamation bubble shown over the player while the box is up",
        sawBubble)
  check("2340 player keeps facing " .. tostring(before) .. " under the bubble",
        bubbleFacingOk)
  check("2340 player turns up after the bubble, box still up", sawTurnUnderBox)

  local jessie, james = npcNamed(ow, JESSIE), npcNamed(ow, JAMES)
  if not check("2340 both of the duo are on the map", jessie and james) then
    finish()
  end

  local jStart, jEnd, mStart, mEnd
  local midShot = false
  local facedDownOk, jessieArrived = true, false
  local challenge
  for _ = 1, 900 do
    local top = game.stack:top()
    if getmetatable(top) == TextBox then
      challenge = top
      if mStart and not mEnd and not james.moving
         and james.cellX == TRIGGER.x + 1 then
        mEnd = U.frame()
      end
      break
    end
    if jessie.moving and not jStart then jStart = U.frame() end
    if jStart and not jEnd and not jessie.moving and jessie.cellX == TRIGGER.x then
      jEnd = U.frame()
      jessieArrived = true
    end
    if james.moving and not mStart then mStart = U.frame() end
    if mStart and not mEnd and not james.moving and james.cellX == TRIGGER.x + 1 then
      mEnd = U.frame()
    end
    if jessieArrived and jessie.facing ~= "down" then facedDownOk = false end
    if jStart and not jEnd and not midShot and jessie.cellX <= 6 then
      midShot = true
      U.shot(game, DIR .. "/2340_04_jessie_mid_walk.png")
    end
    U.wait(1)
  end
  local jFrames = (jStart and jEnd) and (jEnd - jStart) or -1
  local mFrames = (mStart and mEnd) and (mEnd - mStart) or -1
  U.log("jessie walk", jFrames, "james walk", mFrames)
  check("2340 Jessie's six steps take ~96 frames (got " .. jFrames .. ")",
        jFrames >= 90 and jFrames <= 104)
  check("2340 James's five steps take ~80 frames (got " .. mFrames .. ")",
        mFrames >= 74 and mFrames <= 88)
  check("2340 Jessie faces down from arrival to the challenge line", facedDownOk)
  check("2340 the challenge box opened", challenge ~= nil)
  if challenge then
    check("2340 Jessie still faces down under the challenge box",
          jessie.facing == "down")
    for _ = 1, 300 do
      if challenge.done then break end
      U.wait(1)
    end
    U.shot(game, DIR .. "/2340_06_challenge_box.png")
  end

  local battle
  for _ = 1, 3000 do
    local top = game.stack:top()
    if getmetatable(top) == BattleState then battle = top end
    if battle and autoBox(64) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  local parting = autoBox(64)
  check("2340 the parting box is armed no-wait (auto delay 64)", parting ~= nil)
  if parting then
    check("2340 Jessie faces down for the parting line", jessie.facing == "down")
    check("2340 James faces down for the parting line", james.facing == "down")
    local closed, partingShot, partingTyped, sawCont = false, false, nil, false
    for _ = 1, 1500 do
      if game.stack:top() ~= parting then closed = true break end
      if parting.waiting and not parting.done and not sawCont
         and (parting.preWait or 0) <= 0 and not parting:sfxHeld() then
        sawCont = true
        U.shot(game, DIR .. "/2340_07_parting_box_cont_wait.png")
        U.tap(game, "a")
      end
      if parting.done and not partingTyped then partingTyped = U.frame() end
      if parting.done and not partingShot then
        partingShot = true
        U.shot(game, DIR .. "/2340_08_parting_last_page_no_arrow.png")
      end
      U.wait(1)
    end
    local partHeld = (closed and partingTyped) and (U.frame() - partingTyped) or -1
    U.log("parting box held", partHeld, "frames after the last page typed")
    check("2340 the parting box waits for A at its cont", sawCont)
    check("2340 the parting box closes with no press after the last page", closed)
    check("2340 parting box held ~64 frames after typing (got " .. partHeld .. ")",
          partHeld >= 58 and partHeld <= 72)
  end

  local settled = false
  for _ = 1, 1200 do
    if game.stack:top() == ow and not ow.runner:isRunning()
       and #ow.scriptMoves == 0 and game.save.flags[BEAT] then
      settled = true
      break
    end
    U.wait(1)
  end
  check("2340 the scene ran to its end", settled)
  check("2340 the duo are gone",
        npcNamed(ow, JESSIE) == nil and npcNamed(ow, JAMES) == nil)
  finish()
end
