-- The Viridian Trainer House (maps/TrainerHouseB1F.asm, plus the CAL arms of
-- engine/battle/read_trainer_party.asm).  ROM-free for the fixture half; the
-- second half runs the map's own extracted script and needs a cache:
--   GOLD_CACHE="$HOME/Library/Application Support/LOVE/gold-dev/gold" \
--     luajit tests/gen2_trainerhouse_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 trainer house")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Apricorns = require("src.core.gen2.Apricorns")
local Events = require("src.world.gen2.Events")
local Specials = require("src.script.gen2.Specials")
local TrainerHouse = require("src.world.gen2.TrainerHouse")
local Trainers = require("src.world.gen2.Trainers")
local Vm = require("src.script.gen2.Vm")

-- ---------------------------------------------------------------------------
-- sMysteryGiftTrainerHouseFlag, and the three routines that read it
-- ---------------------------------------------------------------------------

eq(TrainerHouse.CAL, 12, "CAL is trainer class 12")
eq(TrainerHouse.CAL2, 2, "CAL2 is the Mystery Gift visitor")
eq(TrainerHouse.CAL3, 3, "CAL3 is the house's own trainer")

do
  local empty = {}
  check(not TrainerHouse.hasCustomTrainer(empty),
    "with no Mystery Gift record the flag reads clear")
  check(not TrainerHouse.hasCustomTrainer(nil),
    "and a nil save is the same answer rather than an error")

  -- ReadTrainerParty's `.cal2` arm: the only redirect, and only for CAL2.
  eq(TrainerHouse.resolveMember(empty, TrainerHouse.CAL, TrainerHouse.CAL2),
    TrainerHouse.CAL3, "an unlinked cart answers a CAL2 lookup with CAL3")
  eq(TrainerHouse.resolveMember(empty, TrainerHouse.CAL, TrainerHouse.CAL1),
    TrainerHouse.CAL1, "CAL1 (Route 27) is left alone")
  eq(TrainerHouse.resolveMember(empty, TrainerHouse.CAL, TrainerHouse.CAL3),
    TrainerHouse.CAL3, "CAL3 is left alone")
  eq(TrainerHouse.resolveMember(empty, 13, 2), 2,
    "and member 2 of any OTHER class is left alone: the cart tests the "
    .. "class first")

  -- GetTrainerName's CAL arm falls through to the table when the flag is
  -- clear, which is what nil means here.
  eq(TrainerHouse.customName(empty, TrainerHouse.CAL), nil,
    "no custom name without a Mystery Gift partner")
  eq(TrainerHouse.customName(empty, 13), nil, "and never for another class")

  -- The one shape that would come back the day Mystery Gift lands.
  local gifted = { mysteryGift = { trainerHouse = true, partnerName = "KRIS" } }
  check(TrainerHouse.hasCustomTrainer(gifted), "a stored trade sets the flag")
  eq(TrainerHouse.resolveMember(gifted, TrainerHouse.CAL, TrainerHouse.CAL2),
    TrainerHouse.CAL2,
    "and then CAL2 is NOT redirected: the party comes from the trade")
  eq(TrainerHouse.customName(gifted, TrainerHouse.CAL), "KRIS",
    "sMysteryGiftPartnerName is the name")
end

-- `special TrainerHouse` is that same byte, so the two cannot disagree.
do
  local vm = { scriptVar = 7, specials = { save = function() return {} end } }
  Specials.ALL.TrainerHouse(vm)
  eq(vm.scriptVar, 0, "unlinked: wScriptVar FALSE, so the script picks CAL3")

  local gifted = { mysteryGift = { trainerHouse = true } }
  local vm2 = { scriptVar = 0, specials = { save = function() return gifted end } }
  Specials.ALL.TrainerHouse(vm2)
  eq(vm2.scriptVar, 1, "with a trade stored it answers TRUE, the CAL2 arm")

  local bare = { scriptVar = 3, specials = {} }
  Specials.ALL.TrainerHouse(bare)
  eq(bare.scriptVar, 0,
    "and with no save hook it still answers FALSE rather than leaving a "
    .. "stale wScriptVar to pick the arm")
end

-- ---------------------------------------------------------------------------
-- The once-a-day gate
-- ---------------------------------------------------------------------------

do
  eq(TrainerHouse.ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY, 86,
    "ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY is engine flag 86")
  local found
  for _, row in ipairs(Apricorns.DAILY_ENGINE_FLAGS) do
    if row.id == TrainerHouse.ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY then
      found = row
    end
  end
  check(found ~= nil, "and it is one of the wDailyFlags bits")
  eq(found and found.name, "ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY",
    "under that name")

  -- CheckDailyResetTimer wipes both daily bytes whole, which is the ONLY
  -- thing that lets you back into the hall.
  local save = { engineFlags = { [86] = true } }
  check(TrainerHouse.foughtToday(save), "the flag reads back set")
  Apricorns.dailyReset(save)
  check(not TrainerHouse.foughtToday(save),
    "and the daily rollover is what clears it")
end

-- ---------------------------------------------------------------------------
-- The map's own script, out of a real cache
-- ---------------------------------------------------------------------------

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local mapsPath = cache .. "/data/generated/maps.lua"
local mf = io.open(mapsPath, "r")
if not mf then
  check(true, "gold cache absent : fixture checks only (SKIP cache facts)")
  S.finish()
  return
end
mf:close()

local maps = assert(loadfile(mapsPath))()
local scripts = assert(loadfile(cache .. "/data/generated/scripts.lua"))()
local text = assert(loadfile(cache .. "/data/generated/text.lua"))()
local constants = assert(loadfile(cache .. "/data/generated/constants.lua"))()
local trainerData = assert(loadfile(cache .. "/data/generated/trainers.lua"))()

-- CAL's three rows.  CAL (2) is dead data on the cart -- ReadTrainerParty
-- branches into SRAM before it indexes the table -- and the redirect above is
-- what stops the port fielding it.
do
  local cal = trainerData.classes and trainerData.classes.CAL
  check(cal ~= nil, "the cache carries the CAL class")
  eq(cal and cal.index, TrainerHouse.CAL, "at class index 12")
  local three = Trainers.lookup(trainerData, TrainerHouse.CAL,
    TrainerHouse.CAL3)
  check(three ~= nil, "CAL3 is in the table")
  eq(three and three.name, "CAL", "named CAL")
  local roster = {}
  for _, row in ipairs((three and three.roster) or {}) do
    roster[#roster + 1] = string.format("%s@%d", tostring(row.species),
      row.level)
  end
  eq(table.concat(roster, " "), "MEGANIUM@50 TYPHLOSION@50 FERALIGATR@50",
    "the default opponent is the three fully evolved starters at 50")

  local redirected = TrainerHouse.lookup(trainerData, {}, TrainerHouse.CAL,
    TrainerHouse.CAL2)
  eq(redirected and redirected.id, "CAL3",
    "and a CAL2 lookup lands on that same row rather than on the level 30 "
    .. "one no cartridge fields")
  eq(TrainerHouse.name(trainerData, {}, TrainerHouse.CAL, TrainerHouse.CAL2),
    "CAL", "gettrainername answers CAL either way")
end

local map = maps.TRAINER_HOUSE_B1F
check(map ~= nil, "the cache carries TRAINER_HOUSE_B1F")

-- coord_event 7, 3, SCENE_TRAINERHOUSEB1F_ASK_BATTLE: the doorway cell, not an
-- object, which is why the receptionist is never talked to.
do
  local ce = (map.coordEvents or {})[1]
  check(ce ~= nil, "one coord event")
  eq(ce and ce.x, 7, "at x 7")
  eq(ce and ce.y, 3, "y 3")
  eq(ce and ce.sceneId, 0, "on SCENE_TRAINERHOUSEB1F_ASK_BATTLE")
  check(ce and ce.scriptKey and scripts[ce.scriptKey] ~= nil,
    "and it names a script body the cache carries")
  -- object_const_def is const_def 2, so TRAINERHOUSEB1F_CHRIS is script id 3
  -- and the second extracted object.
  eq(#(map.objects or {}), 2, "two objects: the receptionist and CAL")
  eq(map.objects[2].sprite, "SPRITE_CHRIS",
    "the second is the one setlasttalked 3 names")
  eq(#(map.warps or {}), 1, "one warp, back up to the ground floor")
  eq(map.warps[1].destMap, "TRAINER_HOUSE_1F", "to TRAINER_HOUSE_1F")
end

-- Run the receptionist's script for each of its three arms.  The hooks are a
-- log rather than a World, so this checks the SCRIPT against the port's
-- commands: the wiring is World's own (World:trainerParty, and the coord event
-- World:checkCoordEvents takes on the step onto the cell).
local function runScript(opts)
  opts = opts or {}
  local save = { engineFlags = {} }
  if opts.foughtToday then
    save.engineFlags[TrainerHouse.ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY] = true
  end
  if opts.gift then save.mysteryGift = { trainerHouse = true } end
  local log, moves, battles = {}, {}, {}
  local vm = Vm.new(scripts, text, Events.new(), {
    specialOrder = constants.specialOrder,
    specials = { save = function() return save end },
    showText = function(body, onDone)
      log[#log + 1] = body
      onDone()
    end,
    yesorno = function(onChoose) onChoose(opts.accept and true or false) end,
    applyMovement = function(object, bytes, onDone)
      moves[#moves + 1] = { object = object, steps = #bytes }
      onDone()
    end,
    turnObject = function(object, facing)
      log.turned = { object = object, facing = facing }
    end,
    getEngineFlag = function(flag) return save.engineFlags[flag] end,
    setEngineFlag = function(flag, value)
      save.engineFlags[flag] = value or nil
    end,
    getTrainerName = function(class, member)
      return TrainerHouse.name(trainerData, save, class, member)
    end,
    lookupTrainer = function(class, member)
      return TrainerHouse.lookup(trainerData, save, class, member)
    end,
    startBattle = function(trainer, _wild, onDone)
      battles[#battles + 1] = trainer
      onDone(opts.lose and "lose" or "win")
    end,
    reloadMap = function() log.reloaded = (log.reloaded or 0) + 1 end,
  })
  local started = vm:start(map.coordEvents[1].scriptKey)
  local parkedAfterReload = log.reloaded and vm.busy and #moves == 1
  for _ = 1, 4 do vm:update() end
  return {
    started = started, busy = vm.busy, log = log, moves = moves,
    parkedAfterReload = parkedAfterReload,
    battles = battles, save = save,
  }
end

local function saw(log, needle)
  for _, body in ipairs(log) do
    if body:find(needle, 1, true) then return true end
  end
  return false
end

do -- the first visit of the day, accepted
  local run = runScript({ accept = true })
  check(run.started, "the script starts")
  check(run.parkedAfterReload,
    "reloadmapafterbattle parks the script for the map setup")
  check(not run.busy, "then it runs to completion")
  eq(run.log.turned and run.log.turned.facing, "up",
    "turnobject PLAYER, UP squares the player up to the desk")
  check(saw(run.log, "TRAINING HALL"), "the welcome")
  check(saw(run.log, "is your"), "the {STRBUF} opponent line")
  eq(run.log[2], "CAL is your\nopponent today.",
    "and gettrainername filled it with CAL")
  check(saw(run.log, "Would you like to"), "the question")
  check(saw(run.log, "Please go right"), "the go-ahead")
  check(saw(run.log, "I traveled out"), "CAL's own line inside the room")
  check(run.save.engineFlags[86] == true,
    "setflag ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY is taken")
  eq(#run.battles, 1, "exactly one battle")
  eq(run.battles[1] and run.battles[1].id, "CAL3", "against CAL3")
  eq(#run.moves, 2, "walked in and walked back out")
  eq(run.moves[1].steps, 14, "Movement_EnterTrainerHouseBattleRoom")
  eq(run.moves[2].steps, 14, "Movement_ExitTrainerHouseBattleRoom")
  eq(run.log.reloaded, 1, "reloadmapafterbattle, once")
end

do -- with a Mystery Gift trade stored, the CAL2 arm is the one taken
  local run = runScript({ accept = true, gift = true })
  eq(#run.battles, 1, "still one battle")
  eq(run.battles[1] and run.battles[1].id, "CAL2",
    "special TrainerHouse TRUE routes the script to CAL2")
end

do -- declined
  local run = runScript({ accept = false })
  check(saw(run.log, "Sorry. Only those"), "the polite refusal")
  eq(#run.battles, 0, "no battle")
  check(run.save.engineFlags[86] == nil,
    "and the daily flag is NOT set: a declined offer costs you nothing")
  eq(#run.moves, 1, "one movement, the step back off the cell")
  eq(run.moves[1].steps, 3, "Movement_TrainerHouseTurnBack")
end

do -- already fought today
  local run = runScript({ accept = true, foughtToday = true })
  check(saw(run.log, "second time today"), "the second-challenge refusal")
  eq(#run.log, 1, "and nothing else is said")
  eq(#run.battles, 0, "no battle")
  eq(#run.moves, 1, "just the step back off the cell")
  eq(run.moves[1].steps, 3, "Movement_TrainerHouseTurnBack")
end

do -- losing ends the run, and ends the SCRIPT, before the walk back out
  local run = runScript({ accept = true, lose = true })
  eq(#run.battles, 1,
    "a loss takes reloadmapafterbattle's iffalse arm: one battle, not two")
  -- One movement, not two: the walk in, and nothing after it.
  --
  -- This expected 2 while a lost battle still fell through
  -- `reloadmapafterbattle` and ran the rest of the winner's script -- the bug
  -- tests/gen2_battle_loss_test.lua now pins. On the cart that command reads
  -- wBattleResult and, on LOSE, does `jp ScriptJump` into Script_BattleWhiteout
  -- (engine/overworld/scripting.asm:1080); it never returns, so TrainerHouseB1F
  -- never reaches `.End: applymovement PLAYER,
  -- Movement_ExitTrainerHouseBattleRoom`. You wake up in a Pokecenter, not
  -- politely walked back out of the battle room.
  eq(#run.moves, 1, "and the script is over: no walk back out after a whiteout")
end

S.finish()
