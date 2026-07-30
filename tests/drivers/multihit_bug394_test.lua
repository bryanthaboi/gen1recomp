-- Driver: a multi-hit move must step the enemy HP bar down once per strike
-- (#394), not empty it on hit 1 and freeze for the rest.  pokered
-- ApplyDamageToEnemyPokemon (engine/battle/core.asm:4684-4727) subtracts
-- wDamage then runs UpdateHPBar2 inside the wNumAttacksLeft loop.  Machine
-- half: tests/engine/multihit_hp_drain.lua.  Never under POKEPORT_SPEED:
-- fast-forward desynchronizes the per-strike damage sound from the bar.
--   POKEPORT_DRIVER=tests/drivers/multihit_bug394_test.lua POKEPORT_IDENTITY=bug394 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local MOVE = "DOUBLESLAP"
  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local moveDef = game.data.moves[MOVE]
  check(MOVE .. " resolves in the move table", moveDef ~= nil)
  check("...as a 2-to-5 strike move",
        moveDef ~= nil and moveDef.effect == "TWO_TO_FIVE_ATTACKS_EFFECT")
  check("SNORLAX resolves (a big HP pool, so each strike is visible)",
        game.data.pokemon.SNORLAX ~= nil)
  check("the damage sound is in the generated audio",
        game.data.audio and game.data.audio.sfx
        and game.data.audio.sfx.Damage ~= nil)

  local vol = game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the per-strike damage hits will be SILENT,",
          "raise it in OPTION first")
  else
    U.log("sfxVol", tostring(vol), "-- expect one damage hit per strike")
  end

  -- :L50 so a SNORLAX counterattack cannot end the run before the handoff
  local lead = Pokemon.new(game.data, "BULBASAUR", 50)
  lead.moves = { { id = MOVE, pp = 10, maxPP = 10 } } -- one slot, no mis-pick
  game.save.party = { lead }

  -- offscreen scratch battle: the queue a multi-hit turn builds, with no
  -- animation timing in the way.  Each drain row has to name its target and
  -- carry the HP left after its own strike; unpinned rows were the bug.
  do
    local seqIndex = 0
    local scratch = BattleState.newWild(game, "SNORLAX", 30)
    scratch.onFinish = function() end
    scratch.rng = function(_, hi) -- 5 hits, hit, no crit, max damage roll
      seqIndex = seqIndex + 1
      local scripted = ({ 7, 0, 255, 255 })[seqIndex]
      return scripted ~= nil and scripted or hi
    end
    local startHP = scratch.enemy.mon.hp
    scratch:performMove(scratch.player, scratch.enemy, { id = MOVE, pp = 10 })
    local stops, anims = {}, 0
    for _, row in ipairs(scratch.queue) do
      if row.drain then stops[#stops + 1] = row
      elseif row.anim == MOVE then anims = anims + 1 end
    end
    check(("%d strikes queued %d animations"):format(#stops, anims),
          #stops > 1 and anims == #stops)
    local stepped, named = true, true
    local prev = startHP
    local shownStops = {}
    for _, row in ipairs(stops) do
      named = named and row.battler == scratch.enemy
      stepped = stepped and type(row.stopAt) == "number" and row.stopAt < prev
      prev = row.stopAt or prev
      shownStops[#shownStops + 1] = tostring(row.stopAt)
    end
    check("every drain row names the enemy", named)
    check("and stops on its own strike's HP, one step at a time", stepped)
    check("the last stop is the post-turn HP", prev == scratch.enemy.mon.hp)
    U.log(("enemy HP %d -> stops: %s"):format(startHP,
          table.concat(shownStops, ", ")))
  end

  -- ROUTE_1 is open field (data/generated/maps.lua ROUTE_1); the cell is read
  -- off the loaded map so a map edit degrades to another walkable cell
  -- instead of a wall.
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local map = game.overworld.map
  if not map:isWalkableCell(5, 5) then
    local fx, fy
    for cy = 0, map.heightCells - 1 do
      for cx = 0, map.widthCells - 1 do
        if map:isWalkableCell(cx, cy) then fx, fy = cx, cy break end
      end
      if fx then break end
    end
    if fx then
      U.teleport(game, "ROUTE_1", fx, fy, "down")
      U.wait(10)
    end
  end
  local ow = game.overworld
  check("player stands on a walkable ROUTE_1 cell",
        ow.map:isWalkableCell(ow.player.cellX, ow.player.cellY))

  local function mashUntil(cond, max)
    for _ = 1, max or 120 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return cond()
  end

  local function newFight()
    local battle = BattleState.newWild(game, "SNORLAX", 30)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    U.wait(220) -- the send-out intro plays before the menu is reachable
    mashUntil(function() return battle.phase == "menu" end)
    return battle
  end

  -- ---- scripted run: watch the bar across the strikes ---------------------
  local battle = newFight()
  check("the wild battle reached its FIGHT menu", battle.phase == "menu")
  U.shot(game, DIR .. "/bug394_menu.png")

  U.tap(game, "a") -- FIGHT
  U.wait(16)
  U.tap(game, "a") -- the only move slot
  U.wait(8)

  -- sample on the falling edge of battle.draining, a frame at a time: a
  -- coarser poll can miss a strike's drain entirely and read the next one's
  -- rest twice.  Rows that leave the enemy bar where it was (the foe's own
  -- turn drains the player bar) and the full-bar reset a finished battle
  -- does are skipped.  A is tapped only every eighth frame, to walk the
  -- queue's text rows without eating a whole drain.
  local seen, wasDraining = {}, false
  local lastShown = battle.enemy.shownHP or battle.enemy.mon.hp
  for frame = 1, 2400 do
    local draining = battle.draining ~= nil
    if wasDraining and not draining then
      local shown = battle.enemy.shownHP or battle.enemy.mon.hp
      if shown < lastShown - 0.5 then
        lastShown = shown
        seen[#seen + 1] = shown
        U.shot(game, DIR .. ("/bug394_hit%d.png"):format(#seen))
        U.log(("after strike %d the enemy bar rests on %.0f HP, model HP %d")
                :format(#seen, shown, battle.enemy.mon.hp))
      end
    end
    wasDraining = draining
    if not draining and battle.phase == "menu" and #battle.queue == 0 then break end
    if not draining and frame % 8 == 0 then U.tap(game, "a") end
    U.wait(1)
  end
  local rests = {}
  for i, hp in ipairs(seen) do rests[i] = ("%.0f"):format(hp) end
  U.log(("enemy bar rests: %s"):format(table.concat(rests, ", ")))
  check(("more than one strike moved the enemy bar (%d)"):format(#seen), #seen > 1)
  check("the first strike did not drain the whole turn's damage (#394)",
        #seen > 1 and seen[1] > seen[#seen])

  U.log(("machine checks: %d passed, %d failed"):format(pass, fail))

  -- ---- re-arm and hand the pad over --------------------------------------
  lead.hp = lead.stats.hp
  lead.status = nil
  lead.moves[1].pp = lead.moves[1].maxPP
  local handoff = newFight()
  U.log("A fresh SNORLAX is waiting on FIGHT with DOUBLESLAP in the only slot.")
  U.log("Press A twice and watch the enemy bar: it should tick down a bit on")
  U.log("every strike, in step with the replayed slap and its damage hit, with")
  U.log("the HP number dropping each time. Before #394 the whole bar emptied on")
  U.log("slap one and then sat frozen for the rest.")
  if handoff.phase ~= "menu" then
    U.log("(the menu did not come back on its own: mash A to reach FIGHT)")
  end

  while true do
    coroutine.yield()
  end
end
