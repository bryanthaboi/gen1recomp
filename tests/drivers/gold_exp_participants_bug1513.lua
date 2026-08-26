-- #1513: exp credit has to be per THIS appearance of the enemy's active mon.
-- ResetBattleParticipants falls through into AddBattleParticipant
-- (engine/battle/core.asm:3033 and :3037), and AI_Switch farcalls it right
-- after EnemySwitch (engine/battle/ai/items.asm:697), so the moment the rival
-- rotates, the only mon still credited is the one the player has on the field.
--
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 POKEPORT_IDENTITY=gold-dev \
--     POKEPORT_DRIVER=tests/drivers/gold_exp_participants_bug1513.lua love .
--
-- What to look for, in order:
--   00  CYNDAQUIL is out against JOEY's GEODUDE.
--   01  TOTODILE has been switched in through the real party menu, so BOTH
--       party mons have now "met" GEODUDE.
--   02  "JOEY withdrew GEODUDE!" -- the rotation the ticket is about.
--   03  the exp lines for the KO of the mon that came IN (PIDGEY).  Only
--       TOTODILE may be named here.  A "CYNDAQUIL gained N EXP. Points!" line
--       in this shot is the bug.
--   04  the party screen: CYNDAQUIL's level and EXP bar are pixel-identical to
--       shot 01's, TOTODILE's have moved.
--   05  GEODUDE comes back out and is KO'd.  CYNDAQUIL still gains nothing --
--       that half is correct cart behavior (ram/wram.asm:775-776, "All bits
--       cleared if the enemy faints") and must NOT be "fixed".
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

local function runToPhase(game, screen, phase, frames)
  for _ = 1, (frames or 600) do
    if screen.phase == phase then return true end
    if screen.battle.over then return false end
    U.tap(game, "a")
    U.wait(3)
  end
  return false
end

-- Page the queue out, shooting the first box that carries `needle`.
local function pageUntilMenu(game, screen, out, needles)
  local shot = {}
  for _ = 1, 1200 do
    local message = screen.message
    if message then
      for needle, path in pairs(needles) do
        if not shot[needle] and message:find(needle, 1, true) then
          U.shot(game, out .. "/" .. path)
          shot[needle] = message
        end
      end
    end
    if screen.phase == "menu" or screen.phase == "done"
        or screen.battle.over then
      break
    end
    U.tap(game, "a")
    U.wait(3)
  end
  return shot
end

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1513"
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  local failures = {}
  local function check(ok, what)
    print((ok and "[ok] " or "[FAIL] ") .. what)
    if not ok then failures[#failures + 1] = what end
  end

  local lead = Mon.new(game.data, "CYNDAQUIL", 20)
  lead.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local bench = Mon.new(game.data, "TOTODILE", 20)
  bench.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  game.save.party = { lead, bench }

  local foe1 = Mon.new(game.data, "GEODUDE", 8)
  foe1.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local foe2 = Mon.new(game.data, "PIDGEY", 8)
  foe2.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  -- attributes[6] is the low byte of TRNATTR_AI_ITEM_SWITCH: OFTEN
  -- (src/battle/gen2/Ai.lua:1307).  The real Rival1 class is SWITCH_SOMETIMES
  -- (pokegold:data/trainers/attributes.asm), the same path at a lower roll.
  assert(world:startBattle({ trainer = { class = "YOUNGSTER", name = "JOEY",
    party = { foe1, foe2 }, attributes = { 0, 0, 0, 0, 0, 0x01, 0 } } }),
    "trainer startBattle failed")
  local screen = battleScreen(game)
  assert(runToPhase(game, screen, "menu", 400), "never reached the menu")
  U.shot(game, out .. "/00-lead-out.png")

  ------------------------------------------------- the player's own switch
  -- Through the real party menu, so the human sees the same path they used.
  screen:chooseMenu("party")
  for _ = 1, 240 do
    if screen.battle.player == bench then break end
    local top = game.stack:top()
    if top ~= screen then
      U.tap(game, "down")
      U.wait(3)
      U.tap(game, "a")
      U.wait(6)
      U.tap(game, "a")
      U.wait(6)
    else
      U.wait(2)
    end
  end
  check(screen.battle.player == bench, "TOTODILE was switched in")
  check(screen.battle.participants[1] and screen.battle.participants[2],
    "both party mons are credited against GEODUDE")
  pageUntilMenu(game, screen, out, {})
  U.shot(game, out .. "/01-switched.png")
  print(("[driver] before the rotation: cyndaquil %d totodile %d")
    :format(lead.experience, bench.experience))
  local leadExp = lead.experience
  local benchExp = bench.experience

  ------------------------------------------------------- the AI's rotation
  -- Perish Song at one turn left is CheckAbleToSwitch's maximum score, the
  -- cheapest way to make the AI commit to the rotation on demand.
  screen.battle:volatile(screen.battle.enemy).perish = 1
  screen:submit({ kind = "move", move = "TACKLE" })
  local seen = pageUntilMenu(game, screen, out, {
    ["withdrew"] = "02-rival-withdrew.png",
    ["gained"] = "03-exp-lines.png",
  })
  check(seen["withdrew"] ~= nil, "JOEY withdrew GEODUDE")
  check(screen.battle.enemy == foe2, "and sent PIDGEY out")
  check(screen.battle.participants[1] == nil,
    "CYNDAQUIL lost its credit when the rival rotated")
  check(screen.battle.participants[2] == true,
    "and TOTODILE, the mon on the field, kept it")

  ------------------------------------------------------------ the KO payout
  if not screen.battle.over and (foe2.hp or 0) > 0 then
    if screen.phase ~= "menu" then
      runToPhase(game, screen, "menu", 400)
    end
    foe2.hp = 1
    screen:submit({ kind = "move", move = "TACKLE" })
    local paid = pageUntilMenu(game, screen, out, {
      ["gained"] = "03-exp-lines.png",
    })
    if paid["gained"] then print("[driver] exp box: " .. paid["gained"]) end
  end
  print(("[driver] after the PIDGEY KO: cyndaquil %d totodile %d")
    :format(lead.experience, bench.experience))
  check(lead.experience == leadExp,
    "CYNDAQUIL earned NOTHING from the mon it never faced")
  check(bench.experience > benchExp, "TOTODILE was paid for it")

  if screen.phase == "menu" then
    screen:chooseMenu("party")
    U.wait(20)
    U.shot(game, out .. "/04-party-exp.png")
    U.tap(game, "b")
    U.wait(10)
    if game.stack:top() ~= screen then
      U.tap(game, "b")
      U.wait(10)
    end
  end

  ------------------------------------------- GEODUDE comes back and faints
  -- Correct cart behavior: no residual credit for a previous appearance.
  leadExp = lead.experience
  benchExp = bench.experience
  if not screen.battle.over then
    runToPhase(game, screen, "menu", 600)
    if screen.phase == "menu" and screen.battle.enemy == foe1 then
      foe1.hp = 1
      screen:submit({ kind = "move", move = "TACKLE" })
      pageUntilMenu(game, screen, out, { ["gained"] = "05-geodude-ko.png" })
      print(("[driver] after the GEODUDE KO: cyndaquil %d totodile %d")
        :format(lead.experience, bench.experience))
      check(lead.experience == leadExp,
        "CYNDAQUIL still earns nothing when GEODUDE comes back (correct)")
      check(bench.experience > benchExp, "and TOTODILE takes the whole share")
    else
      print("[driver] GEODUDE never came back out; second half skipped")
    end
  end

  if #failures > 0 then
    error(#failures .. " exp participant checks failed")
  end
  print("[driver] #1513 fixed; shots in " .. out)
end
