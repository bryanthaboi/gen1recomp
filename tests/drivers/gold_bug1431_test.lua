-- Driver: the shiny sparkle on a SENT OUT mon (#1431).
--
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1431_test.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1431   (default)
--
-- SendOutPlayerMon calls BattleCheckPlayerShininess and replays
-- ANIM_SEND_OUT_MON with wBattleAnimParam 1 -- the script's `.Shiny` arm --
-- between the plain animation and the cry (engine/battle/core.asm:3820-3837);
-- ShowSetEnemyMonAndSendOutAnimation does the same for every enemy send-out
-- (:3364-3383).  Only the wild-intro path (BattleStartMessage, :8701-8715) had
-- been ported, so a shiny lead-off, a shiny switch-in and a shiny enemy
-- replacement all came out silent.
--
-- Three send-outs to watch, none of them the wild intro: the player's lead-off,
-- the player's own switch, and the opponent's replacement after a faint.
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")
local GbcPalette = require("src.render.GbcPalette")

-- constants/battle_constants.asm: the DV pair BATTLETYPE_FORCESHINY forces.
local SHINY_DVS = { attack = 14, defense = 10, speed = 10, special = 10 }

local OUT = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1431"

local function tap(game, button, frames)
  game.input.pressQueue[#game.input.pressQueue + 1] = button
  game.input.state[button] = true
  U.wait(2)
  game.input.state[button] = false
  U.wait(frames or 6)
end

local function openBattle(game, opts)
  assert(game.world:startBattle(opts), "startBattle failed")
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then return top end
    U.wait(1)
  end
  error("battle screen never came up")
end

-- Stop on the frame the `.Shiny` arm is actually running: animId plus the
-- wBattleAnimParam the arm branches on (data/moves/animations.asm:414-417).
local function shinyArm(screen)
  local anim = screen.anim
  return anim ~= nil and anim.animId == "ANIM_SEND_OUT_MON"
    and anim.param == 1
end

local function watch(game, screen, label, frames)
  for _ = 1, (frames or 400) do
    if shinyArm(screen) then
      U.log("[driver] " .. label .. ": .Shiny arm running")
      U.shot(game, ("%s/%s.png"):format(OUT, label))
      return true
    end
    U.wait(1)
  end
  U.log("[driver] " .. label .. ": NO shiny arm seen")
  return false
end

return function(game)
  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  -- A shiny only reads as one in colour, and the sparkle rides the same anim.
  GbcPalette.setMode("gbc")

  local save = game.save
  save.inventory = {}
  local lead = Mon.new(game.data, "CYNDAQUIL", 40, { dvs = SHINY_DVS })
  local bench = Mon.new(game.data, "TOTODILE", 40, { dvs = SHINY_DVS })
  assert(lead.shiny and bench.shiny, "the FORCESHINY DVs did not take")
  local move = assert(game.data.moves.EMBER, "no EMBER in moves.lua")
  lead.moves = { { id = "EMBER", pp = move.pp, maxPp = move.pp } }
  save.party = { lead, bench }

  local entry = game.world:trainerParty(36, 1) -- BUG_CATCHER member 1
  assert(entry, "no BUG_CATCHER member 1 in trainers.lua")
  local Trainers = require("src.world.gen2.Trainers")
  entry.party = Trainers.party(game.data, entry)
  for _, mon in ipairs(entry.party) do mon.shiny = true end
  local screen = openBattle(game, { trainer = entry })

  ------------------------------------------------------------ enemy lead
  -- ShowSetEnemyMonAndSendOutAnimation, out of the opening sequence.
  watch(game, screen, "00-enemy-sendout", 900)

  ----------------------------------------------------------- player lead
  -- SendOutPlayerMon behind the "Go!" line: this is the one the report is
  -- about, and it never sparkled before the fix.
  local sawPlayer = watch(game, screen, "01-player-sendout", 900)

  for _ = 1, 600 do
    if screen.phase == "menu" then break end
    tap(game, "a", 2)
  end

  ---------------------------------------------------------- player switch
  -- The same routine again, this time as a voluntary mid-battle switch.
  local sawSwitch = false
  if screen.phase == "menu" and (screen.battle.party or {})[2] then
    screen:submit({ kind = "switch", index = 2 })
    sawSwitch = watch(game, screen, "02-player-switch", 900)
    for _ = 1, 600 do
      if screen.phase == "menu" or screen.battle.over then break end
      tap(game, "a", 2)
    end
  end

  ------------------------------------------------------ enemy replacement
  local sawReplace = false
  if #(screen.battle.enemyParty or {}) > 1 then
    for _ = 1, 600 do
      if screen.battle.over then break end
      if screen.phase == "menu" then
        local enemy = screen.battle.enemy
        if enemy then enemy.hp = 1 end
        screen:chooseMenu("fight")
        U.wait(2)
        screen:chooseMove(1)
        break
      end
      tap(game, "a", 2)
    end
    sawReplace = watch(game, screen, "03-enemy-replacement", 900)
  end

  U.log(("[driver] player lead-off %s, player switch %s, enemy replacement %s")
    :format(tostring(sawPlayer), tostring(sawSwitch), tostring(sawReplace)))
  U.log("[driver] shots in " .. OUT)
  U.log("[driver] every send-out of a shiny must flash, sparkle and chime")
  U.log("[driver] BEFORE its cry, not only the wild mon at battle start.")

  while true do
    coroutine.yield()
  end
end
