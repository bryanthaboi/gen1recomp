-- maps/BattleTowerBattleRoom.asm's own loop, driven in a real game: the
-- opponent draw, the walk-in, the battle, and the counter the room script
-- reads back.
--
--   POKEPORT_IDENTITY=f1-tower POKEPORT_GAME=crystal POKEPORT_VERSION=crystal \
--     POKEPORT_SHOT_DIR=/tmp/tower-battle \
--     POKEPORT_DRIVER=tests/drivers/crystal_tower_battle_f1.lua love .
--
-- src/world/gen2/World.lua has no startTowerBattle / setObjectSprite hook and
-- World:startBattle does not forward `battleTower` into Battle.new, so the
-- three seams are shimmed here for the length of the run.  The bodies are
-- exactly what belongs in World:specialHooks and World:startBattle.
local U = require("tests.drivers.util")

local Battle = require("src.battle.gen2.Battle")
local BattleTower = require("src.core.gen2.BattleTower")
local Mon = require("src.battle.gen2.Mon")
local World = require("src.world.gen2.World")

-- The world exists before a POKEPORT_DRIVER chunk loads (main.lua:426-438),
-- so the seams go on the live instance.
local function shimWorldSeams(world)
  local towerBattle = false
  local baseNew = Battle.new
  Battle.new = function(opts)
    if towerBattle then opts.battleTower = true end
    return baseNew(opts)
  end

  local baseStartBattle = World.startBattle
  world.startBattle = function(self, opts, onDone)
    towerBattle = (opts and opts.battleTower) and true or false
    local started = baseStartBattle(self, opts, onDone)
    towerBattle = false
    return started
  end

  local hooks = world.vm.specials
  hooks.startTowerBattle = function(trainer, onDone)
    return world:startBattle({ trainer = trainer, battleTower = true }, onDone)
  end
  hooks.setObjectSprite = function(objectId, spriteName)
    local index = (objectId or 0) - 1
    local def = world.map and world.map.def
    local obj = def and def.objects and def.objects[index]
    local sheet = world.sprites and world.sprites[spriteName]
    if not (obj and sheet) then return false end
    obj.sprite = spriteName
    local npc = world:objectEntity(objectId)
    if npc and npc:setSpriteDef(sheet) then world:applySpritePalette(npc) end
    world:rebuildPeople({ seamless = true })
    return true
  end
end

-- ---- the run --------------------------------------------------------------

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-tower-battle"
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

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")

  shimWorldSeams(world)
  ok(type(world.vm.specials.startTowerBattle) == "function",
    "the shimmed startTowerBattle hook reached the VM")
  ok(type(world.vm.specials.setObjectSprite) == "function",
    "and so did setObjectSprite")

  local roster = BattleTower.roster(game.data)
  ok(roster ~= nil, "trainers.lua carries the Battle Tower roster")
  if roster then
    say(("roster: %d trainers, %d groups of %d, sample ceiling %d")
      :format(#roster.trainers, roster.levelGroups, roster.uniqueMon,
        roster.sampleTrainers))
  end

  -- Three legal mons over the L10 room, each with ONE strong move so a blind
  -- A-press run cannot pick a status move for a hundred turns.
  local party = {}
  for _, row in ipairs({ { "TYPHLOSION", 60, "FLAMETHROWER" },
      { "FERALIGATR", 60, "SURF", "BERRY" },
      { "MEGANIUM", 60, "BODY_SLAM", "GOLD_BERRY" } }) do
    local def = game.data.moves[row[3]]
    local mon = Mon.new(game.data, row[1], row[2], {
      moves = { { id = row[3], pp = def.pp, maxPp = def.pp } },
    })
    mon.item = row[4]
    party[#party + 1] = mon
  end
  game.save.party = party

  -- The desk's own SAVELEVELGROUP write, so the room the script walks into is
  -- the L10 one (battle_tower.asm:1129-1141).
  local tower = BattleTower.state(game.save)
  tower.levelGroup = 1
  tower.streak = 0
  tower.trainers = {}
  tower.challenge = BattleTower.NO_CHALLENGE

  while game.stack:top() do game.stack:pop() end
  assert(world:setMap("BATTLE_TOWER_BATTLE_ROOM", 3, 7, "up"),
    "no BATTLE_TOWER_BATTLE_ROOM in the cache")
  U.wait(30)
  shot("room-entered")

  -- The scene script walks the player in, draws the opponent and starts the
  -- battle; nothing here presses anything until a text box wants it.
  local sawOpponent, sawBattle = false, false
  for _ = 1, 900 do
    local vm = world.vm
    if vm and vm.btOpponent and not sawOpponent then
      sawOpponent = true
      say(("opponent: %s %s (row %d), sprite %s, group %d")
        :format(tostring(vm.btOpponent.classId), tostring(vm.btOpponent.name),
          vm.btOpponent.index, tostring(vm.btOpponent.sprite),
          vm.btOpponent.group))
      for slot, mon in ipairs(vm.btOpponent.rows) do
        say(("  mon %d: %s L%d %s"):format(slot, mon.species, mon.level,
          tostring(mon.item)))
      end
      U.wait(20)
      shot("opponent-walked-in")
    end
    if world.battleActive then
      sawBattle = true
      break
    end
    if world.textbox or world.choicebox then tap("a", 4) else U.wait(2) end
  end
  ok(sawOpponent, "special LoadOpponentTrainerAndPokemonWithOTSprite drew one")
  ok(sawBattle, "special BattleTowerBattle pushed the battle screen")

  local screen, battle = nil, nil
  if sawBattle then
    U.wait(90)
    shot("battle-open")
    screen = game.stack:top()
    battle = screen and screen.battle
    ok(battle ~= nil, "the battle screen owns a Battle")
    if battle then
      ok(battle.inBattleTowerBattle == true,
        "wInBattleTowerBattle is set, so DoBadgeTypeBoosts is off")
      say("enemy trainer: " .. tostring(battle.trainer and battle.trainer.name))
      say("enemy lead: " .. tostring(battle.enemy and battle.enemy.species)
        .. " L" .. tostring(battle.enemy and battle.enemy.level))
      ok(battle.trainer ~= nil and #battle.trainer.party == 3,
        "with a three-mon Tower party")
    end
  end

  -- One press per look at the phase: FIGHT off the 2x2 menu, then the hardest
  -- move with PP left.
  local function hardestMove(mon)
    local best, bestPower = 1, -1
    for index, move in ipairs((mon and mon.moves) or {}) do
      local def = game.data.moves and game.data.moves[move.id]
      local power = (def and def.power) or 0
      if (move.pp or 0) > 0 and power > bestPower then
        best, bestPower = index, power
      end
    end
    return best
  end

  -- PP topped up between turns: an unattended run otherwise Struggles itself
  -- to death long before the third opponent mon is down.
  local function refill(mon)
    for _, move in ipairs((mon and mon.moves) or {}) do
      move.pp = move.maxPp or move.pp
    end
  end

  local menus = 0
  for _ = 1, 900 do
    if not world.battleActive or (battle and battle.over) then break end
    local phase = screen and screen.phase
    if phase == "menu" then
      menus = menus + 1
      if menus == 1 then shot("battle-menu") end
      refill(battle and battle.player)
      screen.menuIndex = 1
      tap("a", 4)
    elseif phase == "moves" then
      screen.menuIndex = hardestMove(battle and battle.player)
      tap("a", 4)
    elseif phase == "submenu" then
      -- A forced switch cannot be cancelled, so walk off the fainted lead.
      tap("down", 3)
      tap("a", 4)
    else
      tap("a", 3)
    end
  end
  if battle then
    say("battle over=" .. tostring(battle.over)
      .. " outcome=" .. tostring(battle.outcome)
      .. " phase=" .. tostring(screen and screen.phase))
    ok(battle.over, "the battle resolved")
    ok(battle.outcome == "win", "and the L60 party won it")
    shot("battle-end")
  end
  for _ = 1, 200 do
    if not world.battleActive then break end
    tap("a", 3)
  end
  ok(not world.battleActive, "the battle screen came down")
  U.wait(30)
  shot("after-battle")

  local vm = world.vm
  local state = BattleTower.state(game.save)
  say(("streak=%d challenge=%d scriptVar=%s wNrOfBeaten=%s strbuf=%q")
    :format(state.streak, state.challenge, tostring(vm and vm.scriptVar),
      tostring(vm and vm.mem and vm.mem[BattleTower.WRAM_NR_BEATEN]),
      tostring(vm and vm.stringBuffer)))
  ok(state.streak >= 1, "ReadBTTrainerParty stepped the streak counter")
  ok(state.challenge == BattleTower.CHALLENGE_IN_PROGRESS,
    "and armed sBattleTowerChallengeState")
  ok(#(state.trainers or {}) >= 1, "sBTTrainers recorded who was fought")
  ok(state.prevTeams and #state.prevTeams.prev == 3,
    "and sBTMonPrevTrainer recorded the team")

  -- The receptionist's heal, the "next up, opponent no. N" prompt and the
  -- second draw all follow on their own.
  local pages, secondDraw = {}, nil
  for _ = 1, 400 do
    local body = world.lastText
    if type(body) == "string" and body ~= "" and pages[#pages] ~= body then
      pages[#pages + 1] = body
      if #pages <= 6 then shot("page-" .. #pages) end
    end
    if world.battleActive then
      secondDraw = world.vm and world.vm.btOpponent
      break
    end
    if world.choicebox then tap("a", 4) else tap("a", 3) end
  end
  say("pages: " .. table.concat(pages, " | "))
  local joined = table.concat(pages, " | ")
  ok(joined:find("healed to full health", 1, true) ~= nil
    or joined:find("Next up", 1, true) ~= nil,
    "the room script carried on past the battle")
  ok(joined:find("Next up, opponent\nno.2", 1, true) ~= nil
    or joined:find("no.2", 1, true) ~= nil,
    "and wStringBuffer3 named the SECOND opponent")

  if world.battleActive then
    U.wait(60)
    shot("second-battle")
    ok(true, "the loop came back round for opponent two")
    say("second opponent: " .. tostring(secondDraw and secondDraw.name))
  end

  say(("streak after round two: %d"):format(BattleTower.state(game.save).streak))
  say(fails == 0 and "PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
