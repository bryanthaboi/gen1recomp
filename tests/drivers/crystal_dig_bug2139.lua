-- ../pokecrystal/engine/battle/effect_commands.asm:1546
-- ../pokecrystal/engine/battle/effect_commands.asm:5475
-- ../pokecrystal/data/moves/effects.asm:1011
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-dig-2139"
  os.execute("mkdir -p '" .. out .. "'")
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[dig-2139] " .. (cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")

  local lead = Mon.new(game.data, "ALAKAZAM", 50)
  assert(lead, "could not build an ALAKAZAM")
  lead.moves = {
    { id = "REFLECT", pp = 20, maxPp = 20 },
    { id = "RECOVER", pp = 20, maxPp = 20 },
    { id = "EARTHQUAKE", pp = 10, maxPp = 10 },
    { id = "ICE_PUNCH", pp = 15, maxPp = 15 },
  }
  game.save.party = { lead }
  game.save.inventory = { POKE_BALL = 5 }

  local wild = Mon.new(game.data, "HITMONTOP", 30)
  assert(wild, "could not build a wild HITMONTOP")
  wild.moves = { { id = "DIG", pp = 10, maxPp = 10 } }
  wild.stats.speed = 1
  wild.hp = wild.maxHp or wild.hp

  assert(world:startBattle({ wild = wild }), "startBattle failed")
  local screen
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  assert(screen and screen.battle, "battle screen never came up")

  local messages = {}
  local realPush = screen.pushAll
  screen.pushAll = function(self, events)
    for _, event in ipairs(events or {}) do
      if event.kind == "message" and event.text then
        messages[#messages + 1] = event.text
      end
    end
    return realPush(self, events)
  end
  local function sawText(needle)
    for _, text in ipairs(messages) do
      if text:find(needle, 1, true) then return true end
    end
    return false
  end

  local function toMenu(tag)
    for _ = 1, 900 do
      if screen.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(2)
    end
    ok(screen.phase == "menu", tag .. ": reached the battle menu")
  end

  local function pickMove(index)
    U.tap(game, "a")
    U.wait(4)
    for _ = 1, 8 do
      local at = screen.moveIndex or 1
      if at == index then break end
      U.tap(game, at < index and "down" or "up")
      U.wait(2)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if screen.phase ~= "menu" then break end
      U.wait(1)
    end
  end

  local enemy = screen.battle.enemy
  local enemyVol = screen.battle:volatile(enemy)

  toMenu("turn1")
  pickMove(1)
  local shotDuringPlayerMove, boxUpDuringPlayerMove = false, true
  local sawCharge = false
  for tick = 1, 900 do
    if screen.phase == "menu" or game.stack:top() ~= screen then break end
    if not sawCharge and enemyVol.vanished then
      if screen.vanishSeen and screen.vanishSeen.enemy then
        sawCharge = true
      elseif screen.anim or (screen.message and
          tostring(screen.message):find("REFLECT", 1, true)) then
        if screen:picBoxCleared("enemy") or screen:isUnderground("enemy") then
          boxUpDuringPlayerMove = false
        end
        if not shotDuringPlayerMove then
          shotDuringPlayerMove = true
          U.shot(game, ("%s/2139_fix_turn1_t%03d.png"):format(out, tick))
        end
      end
    end
    if (screen.messageTimer or 0) > 0 then U.tap(game, "a") end
    U.wait(1)
  end
  ok(shotDuringPlayerMove, "turn1: the player's move was replayed with the flag up")
  ok(boxUpDuringPlayerMove,
    "turn1: the enemy's pic box stayed on screen during the player's move")
  ok(sawCharge, "turn1: the charge event was replayed")
  toMenu("turn1-end")
  ok(enemyVol.vanished == true, "turn1: HITMONTOP is underground after the turn")
  ok(screen:isUnderground("enemy"), "turn1: and its box is now empty")
  ok(not sawText("attack missed"), "turn1: Reflect did not print 'attack missed!'")
  ok((screen.battle.screens.player.reflect or 0) > 0, "turn1: Reflect is up")
  U.shot(game, out .. "/2139_fix_turn1_end.png")

  messages = {}
  lead.hp = math.max(1, math.floor((lead.maxHp or lead.hp) / 2))
  local hpBefore = lead.hp
  pickMove(2)
  for _ = 1, 900 do
    if screen.phase == "menu" or game.stack:top() ~= screen then break end
    if (screen.messageTimer or 0) > 0 then U.tap(game, "a") end
    U.wait(1)
  end
  toMenu("turn2")
  ok(not sawText("attack missed"), "turn2: Recover did not print 'attack missed!'")
  ok(lead.hp > hpBefore, "turn2: Recover healed while the target was underground")
  ok(enemyVol.vanished == nil or enemyVol.vanished == false,
    "turn2: the stored Dig came out")
  ok(not screen:isUnderground("enemy") and not screen.picHidden.enemy,
    "turn2: the enemy's box is back")
  U.shot(game, out .. "/2139_fix_turn2_end.png")

  messages = {}
  enemyVol.vanished = true
  enemyVol.chargeMove = "DIG"
  local enemyHp = enemy.hp
  pickMove(3)
  for _ = 1, 900 do
    if screen.phase == "menu" or game.stack:top() ~= screen then break end
    if (screen.messageTimer or 0) > 0 then U.tap(game, "a") end
    U.wait(1)
  end
  ok(enemy.hp < enemyHp, "turn3: Earthquake damaged the dug-in HITMONTOP")
  ok(not sawText("attack missed"), "turn3: and did not miss")
  U.shot(game, out .. "/2139_fix_turn3_end.png")

  print("[dig-2139] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")))
  love.event.quit(fails == 0 and 0 or 1)
end
