-- Eye/ear check on which animation BIDE plays when (#375).  BideEffect ends on
-- `add XSTATITEM_ANIM / jp PlayBattleAnimation2` (engine/battle/effects.asm:
-- 764-789), so the storing turn is the silent X-item spiral; BIDE's own row
-- (sound Battle_18) belongs to .UnleashEnergy (engine/battle/core.asm:3501-3529).
--   POKEPORT_DRIVER=tests/drivers/bide_anim_bug375_test.lua POKEPORT_IDENTITY=bug375 POKEPORT_TOUCH=0 love .
-- No POKEPORT_SPEED: fast-forward scales the logic clock only and desyncs audio.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local ChipAudio = require("src.core.ChipAudio")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- data/generated/maps.lua ROUTE_1: the open path south of the first grass
  -- patch, and pokered data/maps/objects/Route1.asm parks its youngsters at
  -- (5, 24) and (15, 13), so nobody is standing here or watching.
  local MAP = "ROUTE_1"
  local STAND = { x = 5, y = 5, facing = "down" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the ear and eye cannot check ---------------------------------
  local opts = game.save.options or {}
  local sfxVol = opts.sfxVol or 7
  if sfxVol == 0 then
    U.log("FAIL sfx volume is 0: the release hit plays no sound at all, so")
    U.log("     the half of this that is audible cannot be judged. Set SFX")
    U.log("     to 7 in OPTION first.")
  end
  check(("sfx volume %d"):format(sfxVol), sfxVol > 0)
  if opts.animations == false then
    U.log("FAIL OPTION has animations off, which skips every queued anim row")
    U.log("     (BattleState:animationsOn). Turn ANIMATION on first.")
  end
  check("battle animations are on", opts.animations ~= false)

  local moveDef = game.data.moves.BIDE
  check("BIDE is in the move table", moveDef ~= nil)
  local anims = (game.data.battle_anims or {}).moveAnims or {}
  check("BIDE has an animation", anims.BIDE ~= nil)
  check("XSTATITEM_ANIM has an animation", anims.XSTATITEM_ANIM ~= nil)
  check("XSTATITEM_DUPLICATE_ANIM has an animation",
        anims.XSTATITEM_DUPLICATE_ANIM ~= nil)
  -- the row's sound byte is a move id; playAnimSound resolves it through
  -- moves.lua, which is where the actual sfx program name lives
  local sfxName = moveDef and moveDef.anim and moveDef.anim.sound
  check("BIDE's animation names a sound (" .. tostring(sfxName) .. ")",
        sfxName ~= nil)
  if sfxName then
    local src = ((game.data.audio or {}).sfx or {})[sfxName]
        and ChipAudio.newSfx(game.data, sfxName) or nil
    local secs = src and src:getDuration() or 0
    check(("%s synthesizes (%.2fs)"):format(sfxName, secs), secs > 0)
  end

  -- ---- a BIDE user, parked on Route 1 ------------------------------------
  local lead = Pokemon.new(game.data, "CHARMANDER", 20)
  lead.moves = { { id = "BIDE", pp = 10 } }
  game.save.party = { lead }

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(15)
  local ow = game.overworld
  if not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit or a mod blocked the cell: take any free neighbour
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y), cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(15)
        ow = game.overworld
        break
      end
    end
  end
  check("standing on " .. MAP, ow.map.id == MAP)

  -- Every anim row this battle queues, in order.  Polling the queue catches
  -- the announcement-time row performMove inserts directly as well as the
  -- ones animNext adds, which is the whole difference the fix makes.
  local function watchAnims(battle)
    local seen, mark, types = {}, {}, {}
    return seen, function()
      for _, row in ipairs(battle.queue) do
        if row.anim and not mark[row] then
          mark[row] = true
          seen[#seen + 1] = row.anim
          types[row.anim] = row.hit and row.hit.animType or false
        end
      end
    end, types
  end

  -- engine/battle/animations.asm:427-437
  local function rideAndSample(battle, poll, frames, shotPath)
    local peak, shot = 0, false
    for i = 1, frames do
      poll()
      if i % 6 == 0 then U.tap(battle.game, "a") end
      local fx = battle.fx
      if fx and fx.shakeX and not battle.animPlaying then
        local dx = math.abs(fx.shakeX)
        if dx > peak then peak = dx end
        if dx > 0 and not shot then
          shot = true
          U.shot(battle.game, shotPath)
        end
      end
      U.wait(1)
    end
    return peak
  end

  local function listOf(seen)
    return #seen > 0 and table.concat(seen, ", ") or "(none)"
  end

  local function has(seen, name)
    for _, n in ipairs(seen) do
      if n == name then return true end
    end
    return false
  end

  -- Mash A while polling, so a row that comes and goes inside the wait is
  -- still recorded.
  local function mash(battle, poll, taps, gap)
    for _ = 1, taps do
      U.tap(battle.game, "a")
      for _ = 1, gap do poll() U.wait(1) end
    end
  end

  -- the wipe and the send-out chain hold the battle in "intro" for a while,
  -- and the send-out text needs the A presses to advance
  local function waitPhase(battle, phase, tries, poll)
    for _ = 1, tries do
      if battle.phase == phase then return true end
      mash(battle, poll, 1, 6)
    end
    return battle.phase == phase
  end

  -- FIGHT then the only move in the list
  local function pickBide(battle, poll)
    U.tap(battle.game, "a")
    if not waitPhase(battle, "moveSelect", 10, poll) then return false end
    U.tap(battle.game, "a")
    return true
  end

  -- ---- player side -------------------------------------------------------
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  local seen, poll, types = watchAnims(battle)
  check("the battle reached the menu", waitPhase(battle, "menu", 60, poll))
  check("BIDE is the move on the list", pickBide(battle, poll))
  for _ = 1, 20 do poll() U.wait(1) end
  U.shot(game, DIR .. "/bug375_store_spiral.png")

  local peak = rideAndSample(battle, poll, 180,
                             DIR .. "/bug1564_store_shake.png")
  U.shot(game, DIR .. "/bug375_store_text.png")

  check("the storing turn queued XSTATITEM_ANIM", has(seen, "XSTATITEM_ANIM"))
  check("and not BIDE's hit animation: " .. listOf(seen), not has(seen, "BIDE"))
  check("BIDE locked in for " .. tostring(battle.player.bideTurns) .. " turns",
        battle.player.bideTurns ~= nil)
  check("the storing spiral carries wAnimationType 6 (#1564)",
        types["XSTATITEM_ANIM"] == 6)
  check(("the screen shook, peak dx = %d px (want 3)"):format(peak), peak == 3)

  -- ride out the locked turns: the storing text needs A presses and the menu
  -- never comes back until BIDE unleashes
  local released = false
  for _ = 1, 220 do
    U.tap(game, "a")
    for _ = 1, 6 do poll() U.wait(1) end
    if has(seen, "BIDE") then
      released = true
      break
    end
    if game.stack:top() ~= battle or battle.player.mon.hp <= 0 then break end
  end
  U.shot(game, DIR .. "/bug375_release.png")
  check("the release queued BIDE's own animation: " .. listOf(seen), released)
  for _ = 1, 60 do poll() U.wait(1) end

  -- ---- enemy side --------------------------------------------------------
  -- PlayBattleAnimation2 adds hWhoseTurn, so the foe's storing turn is
  -- XSTATITEM_DUPLICATE_ANIM (AttackAnimationPointers[174]), never the
  -- player row.
  for _ = 1, 8 do
    if game.stack:top() == ow then break end
    game.stack:pop()
  end
  lead.hp = lead.stats.hp
  local foeBattle = BattleState.newWild(game, "RATTATA", 8)
  foeBattle.onFinish = function() end
  foeBattle.enemy.mon.moves = { { id = "BIDE", pp = 10 } }
  foeBattle.enemy.curMoves = foeBattle.enemy.mon.moves
  ow:pushBattle(foeBattle)
  local foeSeen, foePoll, foeTypes = watchAnims(foeBattle)
  check("the foe's battle reached the menu",
        waitPhase(foeBattle, "menu", 60, foePoll))
  pickBide(foeBattle, foePoll) -- ours does not matter here, the foe's does
  for _ = 1, 60 do
    if has(foeSeen, "XSTATITEM_DUPLICATE_ANIM") then break end
    U.tap(game, "a")
    for _ = 1, 6 do foePoll() U.wait(1) end
  end
  U.shot(game, DIR .. "/bug375_enemy_store.png")
  check("the foe's storing turn queued XSTATITEM_DUPLICATE_ANIM: "
          .. listOf(foeSeen), has(foeSeen, "XSTATITEM_DUPLICATE_ANIM"))

  local foePeak = rideAndSample(foeBattle, foePoll, 180,
                                DIR .. "/bug1564_enemy_store_shake.png")
  check("the foe's spiral carries wAnimationType 3 (#1564)",
        foeTypes["XSTATITEM_DUPLICATE_ANIM"] == 3)
  check(("the foe's shake peaked at %d px (want 6)"):format(foePeak),
        foePeak == 6)

  U.log("The pad is yours in a battle where both sides know only BIDE, so")
  U.log("pick FIGHT then BIDE and watch turn one: the screen palette flashes")
  U.log("white and balls spiral inward, silently. Then, still in silence, the")
  U.log("whole battle screen creeps sideways 1 px at a time out to 3 px and")
  U.log("back, twice, and only then does it say storing energy. On the foe's")
  U.log("turn the same creep goes out to 6 px and takes twice as long.")
  U.log("No flash on the RATTATA and no BIDE thud until the turn it")
  U.log("unleashes, where the thud and its animation come after the text and")
  U.log("before the enemy HP bar slides down. The foe's spiral looks the same.")

  while true do
    coroutine.yield()
  end
end
