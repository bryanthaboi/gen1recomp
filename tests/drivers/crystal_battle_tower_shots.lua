-- The Battle Tower lobby, driven in a real game.
--
--   POKEPORT_IDENTITY=lead-card POKEPORT_GAME=crystal POKEPORT_VERSION=crystal \
--     POKEPORT_SHOT_DIR=/tmp/tower \
--     POKEPORT_DRIVER=tests/drivers/crystal_battle_tower_shots.lua love .
--
-- Three sections, all on maps/BattleTower1F.asm's own extracted script:
--   A  an illegal party, so _CheckForBattleTowerRules prints its refusals
--   B  a legal party through Menu_ChallengeExplanationCancel and the room menu
--   C  the walk to the elevator the chosen room starts
--
-- Section B overrides the TryQuickSave stub for the length of the run:
-- src/script/gen2/Specials.lua:2516 answers 0, and BattleTower1F.asm:84-85
-- backs out of the whole challenge on that, so the desk cannot be walked
-- past without it.
local U = require("tests.drivers.util")

local BattleTower = require("src.core.gen2.BattleTower")
local BattleTowerMenu = require("src.ui.gen2.BattleTowerMenu")
local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local ScriptMenu = require("src.ui.gen2.ScriptMenu")
local Vm = require("src.script.gen2.Vm")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-tower"
  local fails, shots = 0, 0

  local function say(line) print("[driver] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "OK   " or "FAIL ") .. line)
  end
  local function shot(name)
    shots = shots + 1
    U.shot(game, ("%s/%02d-%s.png"):format(out, shots, name))
  end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end
  local function top() return game.stack:top() end
  local function isMenu() return getmetatable(top()) == ScriptMenu end
  local function isRoomMenu() return getmetatable(top()) == BattleTowerMenu end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")
  say("version=" .. GameVersion.get() .. " engine=" .. GameVersion.engine())

  local function party(spec)
    local list = {}
    for _, row in ipairs(spec) do
      local m = Mon.new(game.data, row[1], row[2])
      m.item = row[3]
      list[#list + 1] = m
    end
    game.save.party = list
  end

  local function enterLobby()
    while top() do tap("b", 2) end
    assert(world:setMap("BATTLE_TOWER_1F", 7, 7, "up"), "no BATTLE_TOWER_1F")
    U.wait(40)
  end

  -- maps/BattleTower1F.asm:55-73: A through the welcome, NO to the
  -- explanation offer, and the menu is the next command.
  local function talkToMenu(limit)
    for _ = 1, limit or 200 do
      if isMenu() then return true end
      if world.choicebox then tap("b", 4) else tap("a", 4) end
    end
    return false
  end

  say("--- A: an illegal party at the desk")
  party({ { "TYPHLOSION", 20 } })
  enterLobby()
  shot("lobby")
  ok(talkToMenu(), "the receptionist reaches Menu_ChallengeExplanationCancel")
  shot("challenge-menu")
  ok(isMenu() and #top().items == 3, "three rows: Challenge/Explanation/Cancel")
  tap("a", 6)

  local pages = {}
  for _ = 1, 40 do
    local body = world.lastText
    if type(body) == "string" and body ~= "" and pages[#pages] ~= body then
      pages[#pages + 1] = body
      shot("rules-" .. #pages)
    end
    if not world:busy() and top() == nil then break end
    tap("a", 4)
  end
  local joined = table.concat(pages, " | ")
  say("pages: " .. joined)
  ok(joined:find("You're not ready", 1, true) ~= nil,
    "_ExcuseMeYoureNotReadyText printed")
  ok(joined:find("Only three", 1, true) ~= nil,
    "_OnlyThreeMonMayBeEnteredText printed")
  ok(joined:find("Please return when", 1, true) ~= nil,
    "_BattleTowerReturnWhenReadyText printed")

  say("--- B: a legal party, the room menu, the walk out")
  local savedQuickSave = Vm.SPECIALS.TryQuickSave
  Vm.SPECIALS.TryQuickSave = function(vm) vm.scriptVar = 1 end

  party({ { "TYPHLOSION", 20 }, { "FERALIGATR", 20, "BERRY" },
    { "MEGANIUM", 20, "GOLD_BERRY" } })
  enterLobby()
  ok(talkToMenu(), "the desk reaches the menu again")
  tap("a", 6)

  local sawSavePrompt = false
  for _ = 1, 120 do
    if isRoomMenu() then break end
    if world.choicebox then
      sawSavePrompt = true
      shot("save-prompt")
      tap("a", 6)
    else
      tap("a", 4)
    end
  end
  ok(sawSavePrompt, "Text_SaveBeforeEnteringBattleRoom asked first")
  ok(isRoomMenu(), "special BattleTowerRoomMenu pushed Gen2BattleTowerMenu")
  shot("room-menu")

  if isRoomMenu() then
    local screen = top()
    ok(#screen.rows == BattleTower.PRE_HOF_LEVEL_GROUPS,
      "no Hall of Fame, so four rooms are offered")
    -- L:10 with an L20 party is the refusal at mobile_46.asm:3915-3917.
    tap("a", 6)
    ok(screen.phase == "message", "picking L:10 prints the level refusal")
    shot("tops-this-level")
    for _ = 1, 150 do
      if screen.phase == "pick" then break end
      U.wait(1)
    end
    ok(screen.phase == "pick", "and the menu comes back after the hold")
    tap("up", 6)
    shot("room-menu-l20")
    tap("a", 6)
  end

  for _ = 1, 240 do
    if not world:busy() and top() == nil then break end
    tap("a", 4)
  end
  local tower = BattleTower.state(game.save)
  ok(tower.levelGroup ~= nil, "the level group survived the menu")
  say("levelGroup=" .. tostring(game.world.vm and game.world.vm.btLevelGroup)
    .. " reward=" .. tostring(tower.reward)
    .. " challenge=" .. tostring(tower.challenge)
    .. " map=" .. tostring(world.map and world.map.id))
  ok(tower.reward ~= nil,
    "BATTLETOWERACTION_CHOOSEREWARD banked a prize on the way out")
  shot("after-desk")

  U.wait(180)
  shot("elevator-or-hallway")
  say("map after the walk: " .. tostring(world.map and world.map.id))

  Vm.SPECIALS.TryQuickSave = savedQuickSave

  say(fails == 0 and "PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
