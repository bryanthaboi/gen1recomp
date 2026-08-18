-- #1401: $d9/$da battlergfx loaded the wrong row count
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1401_test.lua love .

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

-- data/moves/animations.asm:1840 Growl, :3605 Icy Wind
local CASES = {
  { move = "GROWL", cmd = "battlergfx_2row", rows = 1, head = 7, feet = 6 },
  { move = "ICY_WIND", cmd = "battlergfx_1row", rows = 2, head = 14, feet = 12 },
}

local function sheet(runner, gfx)
  for _, entry in ipairs(runner.loaded or {}) do
    if entry.gfx == gfx then return entry end
  end
  return nil
end

local function liftedStrip(runner)
  local structs = runner.objects and runner.objects.structs or {}
  for slot = 1, #structs do
    local id = structs[slot].objectId
    if type(id) == "string" and id:match("PLAYERHEAD") then return id end
    if type(id) == "string" and id:match("ENEMYFEET") then return id end
  end
  return nil
end

return function(game)
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  game.save.party = { Mon.new(game.data, "CYNDAQUIL", 30) }
  assert(world:startBattle({ wild = Mon.new(game.data, "PIDGEY", 30) }),
    "startBattle failed")

  local battle
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  assert(battle and battle.battle, "battle screen is not on the stack")
  assert(battle.anims and battle.anims.scripts,
    "battle_anims.lua has no scripts -- re-import Gold")

  local failed = false
  for _, case in ipairs(CASES) do
    battle.anim = nil
    if not battle:animForMove(case.move, "player") then
      U.log("FAIL no animation for", case.move)
      failed = true
    else
      local head, feet
      for _ = 1, 400 do
        local runner = battle.anim
        if not runner then break end
        head = head or sheet(runner, "BATTLE_ANIM_GFX_PLAYERHEAD")
        feet = feet or sheet(runner, "BATTLE_ANIM_GFX_ENEMYFEET")
        U.wait(1)
      end
      if not (head and feet) then
        U.log("FAIL", case.move, "never loaded the battler sheets")
        failed = true
      else
        U.log(("%-9s %-16s rows=%d head=%d feet=%d (want rows=%d head=%d feet=%d)")
          :format(case.move, case.cmd, head.rows, head.tiles, feet.tiles,
            case.rows, case.head, case.feet))
        if head.rows ~= case.rows or head.tiles ~= case.head
          or feet.tiles ~= case.feet then
          U.log("FAIL", case.move, "loaded the wrong row count")
          failed = true
        end
      end
    end
  end

  U.log(failed and "FAIL #1401" or "PASS #1401 battlergfx rows follow the jumptable")

  U.log("look: Growl lifts ONE row of the Cyndaquil's own tiles, not two")
  battle.anim = nil
  battle:animForMove("GROWL", "player")
  for _ = 1, 400 do
    if not battle.anim then break end
    local strip = liftedStrip(battle.anim)
    if strip then
      U.log("parked on", strip)
      break
    end
    U.wait(1)
  end

  while true do
    coroutine.yield()
  end
end
