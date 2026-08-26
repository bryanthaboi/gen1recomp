-- BIDE on the real Gold battle screen: the PP counter in the move list, and
-- the lock that keeps a storing mon on the move it started (#1664, #1665).
--
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_bide_lock_bug1664_1665.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-bide love .
--
-- data/moves/effects.asm:795-800 puts `storeenergy` ahead of `doturn`, and
-- BattleCommand_DoTurn masks SUBSTATUS_BIDE out of the PP spend
-- (engine/battle/effect_commands.asm:977-979), so the whole three-turn Bide
-- costs the one PP the opening turn paid.  The shots are the point: the
-- number beside BIDE in the move list must read the same on 01, 02 and 03.
--
-- The lock is ParsePlayerAction's own arm (engine/battle/core.asm:569-576),
-- which sits INSIDE the FIGHT branch and skips MoveSelectionScreen only -- so
-- the 2x2 menu still opens, a switch is still legal, and using an item runs
-- .reset_bide (:627-629) and CANCELS the store.  Block 2 submits TACKLE in
-- the middle of a Bide on purpose: the engine has to answer with the Bide.
--
-- NOT covered here, and deliberately: src/ui/gen2/BattleState.lua still draws
-- the move list on a storing turn.  The cart jumps past it.  That half is a
-- screen change and is called out in the fix report rather than faked.
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")

local function battleScreen(game)
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then return top end
    U.wait(1)
  end
  error("battle screen never came up")
end

local function drain(game, screen, frames)
  for _ = 1, (frames or 400) do
    if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then
      return true
    end
    U.tap(game, "a")
    U.wait(3)
  end
  return false
end

local function giveMoves(mon, game, moves)
  mon.moves = {}
  for i, id in ipairs(moves) do
    local def = assert(game.data.moves[id], id .. " is not in moves.lua")
    mon.moves[i] = { id = id, pp = def.pp, maxPp = def.pp }
  end
  return mon
end

local function newWild(game, species, level, moves)
  local mon = Mon.new(game.data, species, level)
  if moves then giveMoves(mon, game, moves) end
  return mon
end

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bide"
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  local failures = {}
  local function check(ok, what)
    print((ok and "[ok] " or "[FAIL] ") .. what)
    if not ok then failures[#failures + 1] = what end
  end
  local function pp(mon, slot) return mon.moves[slot].pp end

  -- ------------------------------------------------------------------ 1
  -- One Bide, start to finish, with the move list open between turns.  The
  -- foe is a SPLASH-only RATTATA so nothing interrupts the store.
  local player = Mon.new(game.data, "SNORLAX", 40)
  giveMoves(player, game, { "BIDE", "TACKLE" })
  game.save.party = { player }
  game.save.inventory = { POTION = 5 }
  local foe = newWild(game, "RATTATA", 20, { "TACKLE" })
  assert(world:startBattle({ wild = foe }), "startBattle failed")
  local screen = battleScreen(game)
  drain(game, screen, 200)
  local opening = pp(player, 1)
  print(("[driver] BIDE opens at %d PP"):format(opening))

  screen:submit({ kind = "move", move = "BIDE" })
  drain(game, screen, 400)
  U.shot(game, out .. "/01-selected.png")
  local afterSelect = pp(player, 1)
  print(("[driver] after the SELECTION turn: %d PP"):format(afterSelect))
  check(afterSelect == opening - 1,
    "the opening turn pays its one PP through doturn")
  check(screen.battle:forcedMove(player) == "BIDE",
    "and ParsePlayerAction's bide arm holds the FIGHT choice")

  -- The middle of the store, with TACKLE deliberately submitted: the cart
  -- never re-reads the move list, so wCurPlayerMove is still the BIDE.
  local tackleBefore = pp(player, 2)
  screen:submit({ kind = "move", move = "TACKLE" })
  drain(game, screen, 400)
  U.shot(game, out .. "/02-storing.png")
  print(("[driver] after a STORING turn: BIDE %d PP, TACKLE %d PP")
    :format(pp(player, 1), pp(player, 2)))
  check(pp(player, 1) == afterSelect, "a storing turn spends no PP at all")
  check(pp(player, 2) == tackleBefore,
    "and the move the menu offered was never run")

  -- The release.  Whatever the roll, the store is two or three turns
  -- (UnleashEnergy's `BattleRandom / and 1 / inc a / inc a`,
  -- move_effects/bide.asm:88-92), so keep pressing FIGHT until it lets go.
  local foeBefore = foe.hp
  for _ = 1, 3 do
    if not screen.battle:forcedMove(player) then break end
    screen:submit({ kind = "move", move = "BIDE" })
    drain(game, screen, 400)
  end
  U.shot(game, out .. "/03-unleashed.png")
  print(("[driver] after the RELEASE: %d PP, foe %d -> %d HP")
    :format(pp(player, 1), foeBefore, foe.hp))
  check(pp(player, 1) == afterSelect,
    "the whole Bide cost exactly one PP, the way the cart charges it")
  check(screen.battle:forcedMove(player) == nil, "and the lock is released")
  for _ = 1, 400 do
    if not game.stack:top() or not game.stack:top().battle then break end
    U.tap(game, "a")
    U.wait(3)
  end
  U.wait(60)

  -- ------------------------------------------------------------------ 2
  -- .reset_bide: a nonzero wBattlePlayerAction that is not
  -- BATTLEPLAYERACTION_SWITCH clears SUBSTATUS_BIDE (core.asm:572-573,
  -- :627-629), so opening the PACK mid-store throws the stored damage away.
  local bider = Mon.new(game.data, "SNORLAX", 40)
  giveMoves(bider, game, { "BIDE", "TACKLE" })
  bider.hp = math.max(1, bider.hp - 30)
  game.save.party = { bider }
  game.save.inventory = { POTION = 5 }
  local foe2 = newWild(game, "RATTATA", 20, { "TACKLE" })
  assert(world:startBattle({ wild = foe2 }), "startBattle failed")
  screen = battleScreen(game)
  drain(game, screen, 200)
  screen:submit({ kind = "move", move = "BIDE" })
  drain(game, screen, 400)
  check(screen.battle:forcedMove(bider) == "BIDE", "the second Bide is up")
  screen:useItem("POTION")
  drain(game, screen, 400)
  U.shot(game, out .. "/04-item-cancelled.png")
  print("[driver] after the PACK: forcedMove="
    .. tostring(screen.battle:forcedMove(bider)))
  check(screen.battle:forcedMove(bider) == nil,
    "using an item cancels the Bide, as .reset_bide does")
  check(screen.battle:volatile(bider).bideStored == nil,
    "and the damage it had banked goes with it")
  for _ = 1, 400 do
    if not game.stack:top() or not game.stack:top().battle then break end
    U.tap(game, "a")
    U.wait(3)
  end

  print("[driver] NOTE: the move list is still drawn on a storing turn; the "
    .. "cart's bide arm skips MoveSelectionScreen and that half lives in "
    .. "src/ui/gen2/BattleState.lua")
  if #failures > 0 then
    for _, what in ipairs(failures) do print("[FAIL] " .. what) end
    error(#failures .. " bide checks failed")
  end
  print("[driver] all bide checks passed")
  print("[driver] shots in " .. out)
end
