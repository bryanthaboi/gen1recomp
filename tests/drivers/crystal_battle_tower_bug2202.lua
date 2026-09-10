-- mobile/mobile_46.asm:5271-5340, load_trainer.asm:101-108, maps/BattleTower1F.asm:122-133
--   POKEPORT_IDENTITY=crystal-sep04 POKEPORT_GAME=crystal POKEPORT_VERSION=crystal \
--     POKEPORT_SHOT_DIR=/tmp/tower-2202 \
--     POKEPORT_DRIVER=tests/drivers/crystal_battle_tower_bug2202.lua love .
local U = require("tests.drivers.util")

local BattleTower = require("src.core.gen2.BattleTower")
local BattleTowerMenu = require("src.ui.gen2.BattleTowerMenu")
local Mon = require("src.battle.gen2.Mon")
local PackMenu = require("src.ui.gen2.PackMenu")
local Specials = require("src.script.gen2.Specials")

local VITAMINS = { "HP_UP", "PROTEIN", "IRON", "CARBOS", "CALCIUM" }

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/tower-2202"
  local fails = 0

  local function say(line) print("[driver] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end
  local function shot(name)
    U.shot(game, ("%s/%s.png"):format(out, name))
  end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end
  local function top() return game.stack:top() end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")

  local function party(spec)
    local list = {}
    for _, row in ipairs(spec) do
      local opts = nil
      if row[3] then
        local def = game.data.moves[row[3]]
        opts = { moves = { { id = row[3], pp = def.pp, maxPp = def.pp } } }
      end
      local m = Mon.new(game.data, row[1], row[2], opts)
      m.item = row[4]
      list[#list + 1] = m
    end
    return list
  end

  say("--- A: the room menu's message rows and the uber refusal's pages")
  while top() do game.stack:pop() end
  local save = game.save
  save.party = party({ { "LUGIA", 30 }, { "FERALIGATR", 30, nil, "BERRY" },
    { "MEGANIUM", 30, nil, "GOLD_BERRY" } })
  local picked = nil
  ok(world:pushScreen("Gen2BattleTowerMenu", {
    save = save,
    party = save.party,
    rows = BattleTower.levelGroupRows(save),
    monName = world.vm.specials.monName,
    onDone = function(group) picked = group end,
  }), "Gen2BattleTowerMenu pushed")
  U.wait(4)
  local screen = top()
  ok(getmetatable(screen) == BattleTowerMenu, "and it is on top")
  tap("up", 4); tap("up", 4)
  ok(screen.cursor == 3, "the spinner sits on L:30")
  tap("a", 6)
  ok(screen.phase == "message", "an uber under L70 is refused")
  ok(screen.pages and #screen.pages == 2, "Text_UberRestriction's para is two pages")
  ok(screen.page == 1 and (screen.message or ""):find("may go", 1, true) ~= nil,
    "page one: <MON> may go / only to BATTLE")
  shot("2202_01_uber_page1_rows_14_16")
  U.wait(0x90)
  ok(screen.phase == "message" and screen.page == 1,
    "page one waits on a button, not the $80 countdown")
  tap("a", 6)
  ok(screen.page == 2 and (screen.message or ""):find("Lv.70", 1, true) ~= nil,
    "A turns to ROOMS that are / Lv.70 or higher.")
  shot("2202_02_uber_page2_rows_14_16")
  for _ = 1, 0x90 do
    if screen.phase == "pick" then break end
    U.wait(1)
  end
  ok(screen.phase == "pick", "and the menu restarts after the hold")
  tap("b", 6)
  ok(screen.phase == "quit", "B opens the cancel prompt")
  shot("2202_03_cancel_prompt_rows_14_16")
  tap("down", 4); tap("a", 6)
  ok(screen.phase == "pick", "NO puts the spinner back")

  save.party = party({ { "TYPHLOSION", 30, "FLAMETHROWER" },
    { "FERALIGATR", 30, "SURF", "BERRY" },
    { "MEGANIUM", 30, "BODY_SLAM", "GOLD_BERRY" } })
  screen.party = save.party
  tap("up", 4); tap("up", 4)
  ok(screen.cursor == 3, "back on L:30")
  tap("a", 6)
  ok(picked == 3, "L:30 is accepted, level group 3")
  ok(top() == nil, "and the screen is gone")
  -- mobile/mobile_46.asm:1283-1286
  world.vm.btLevelGroup = picked

  say("--- B: the battle room draws out of the chosen group")
  save.party = party({ { "TYPHLOSION", 60, "FLAMETHROWER" },
    { "FERALIGATR", 60, "SURF", "BERRY" },
    { "MEGANIUM", 60, "BODY_SLAM", "GOLD_BERRY" } })
  local tower = BattleTower.state(save)
  tower.levelGroup = 1
  tower.streak = 6
  tower.trainers = {}
  tower.prevTeams = nil
  tower.challenge = BattleTower.NO_CHALLENGE
  world.vm.scriptVar = BattleTower.ACTIONS.CHOOSEREWARD
  Specials.ALL.BattleTowerAction(world.vm)
  say("reward banked at the desk: " .. tostring(tower.reward))
  ok(tower.reward ~= nil and tower.reward ~= "POTION",
    "BATTLETOWERACTION_CHOOSEREWARD rolled a vitamin")

  assert(world:setMap("BATTLE_TOWER_BATTLE_ROOM", 3, 7, "up"),
    "no BATTLE_TOWER_BATTLE_ROOM in the cache")
  U.wait(30)

  local opponent, sawBattle = nil, false
  for _ = 1, 900 do
    local vm = world.vm
    if vm and vm.btOpponent and not opponent then
      opponent = vm.btOpponent
      say(("opponent: %s %s group %d"):format(tostring(opponent.classId),
        tostring(opponent.name), opponent.group))
      for slot, mon in ipairs(opponent.rows) do
        say(("  mon %d: %s L%d"):format(slot, mon.species, mon.level))
      end
      U.wait(20)
      shot("2202_04_opponent_from_l30_group")
    end
    if world.battleActive then sawBattle = true break end
    if world.textbox or world.choicebox then tap("a", 4) else U.wait(2) end
  end
  ok(opponent ~= nil, "LoadOpponentTrainerAndPokemonWithOTSprite drew one")
  ok(opponent and opponent.group == 3, "out of level group 3, not the SRAM byte's 1")
  local allThirty = opponent ~= nil and #opponent.rows == 3
  for _, mon in ipairs((opponent and opponent.rows) or {}) do
    if mon.level ~= 30 then allThirty = false end
  end
  ok(allThirty, "every drawn mon is L30")
  ok(sawBattle, "BattleTowerBattle pushed the battle screen")

  local bscreen = sawBattle and top() or nil
  local battle = bscreen and bscreen.battle
  if battle then
    -- engine/battle/core.asm:7808-7817, the enemy HUD comes up on the send-out
    local hudUp = false
    for _ = 1, 600 do
      if bscreen.showEnemyHud and not bscreen:hudCleared("enemy") then
        hudUp = true
        break
      end
      tap("a", 3)
    end
    ok(hudUp, "the enemy HUD is drawn")
    ok(battle.enemy and battle.enemy.level == 30, "the enemy lead is L30 in battle")
    U.wait(8)
    shot("2202_05_enemy_hud_l30")
  end

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
  local function refill(mon)
    for _, move in ipairs((mon and mon.moves) or {}) do
      move.pp = move.maxPp or move.pp
    end
  end
  for _ = 1, 2400 do
    if not world.battleActive or (battle and battle.over) then break end
    local phase = bscreen and bscreen.phase
    if phase == "menu" then
      refill(battle and battle.player)
      bscreen.menuIndex = 1
      tap("a", 4)
    elseif phase == "moves" then
      bscreen.menuIndex = hardestMove(battle and battle.player)
      tap("a", 4)
    elseif phase == "submenu" then
      tap("down", 3)
      tap("a", 4)
    else
      tap("a", 3)
    end
  end
  say("battle over=" .. tostring(battle and battle.over) .. " outcome="
    .. tostring(battle and battle.outcome) .. " phase=" .. tostring(bscreen and bscreen.phase))
  ok(battle and battle.over and battle.outcome == "win", "the seventh battle is won")
  for _ = 1, 200 do
    if not world.battleActive then break end
    tap("a", 3)
  end
  ok(not world.battleActive, "the battle screen came down")

  say("--- C: Script_GivePlayerHisPrize")
  local pages = {}
  local shotCongrats, shotPrize = false, false
  for _ = 1, 600 do
    local body = world.lastText
    if type(body) == "string" and body ~= "" and pages[#pages] ~= body then
      pages[#pages + 1] = body
      say("page: " .. body:gsub("\n", " / "))
      if not shotCongrats and body:find("Congratulations", 1, true) then
        shotCongrats = true
        U.wait(90)
        shot("2202_06_congratulations")
      elseif not shotPrize and body:find("got five", 1, true) then
        shotPrize = true
        U.wait(90)
        shot("2202_07_got_five_vitamin")
      end
    end
    if shotPrize and not world:busy() and top() == nil then break end
    if world.choicebox then tap("a", 4) else tap("a", 3) end
  end
  local joined = table.concat(pages, " | ")
  ok(joined:find("got five", 1, true) ~= nil, "Text_PlayerGotFive printed")
  local named = nil
  for _, id in ipairs(VITAMINS) do
    local def = game.data.items[id]
    if def and joined:find(def.name, 1, true) then named = def.name end
  end
  ok(named ~= nil, "and it names a vitamin: " .. tostring(named))
  ok(joined:find("Item0", 1, true) == nil, "not Item0")

  local banked = nil
  for _, id in ipairs(VITAMINS) do
    if (save.inventory[id] or 0) >= 5 then banked = id end
  end
  ok(banked ~= nil, "the pack holds five of " .. tostring(banked))
  local junk = {}
  for key in pairs(save.inventory) do
    if tostring(key):match("^ITEM_?%d+$") then junk[#junk + 1] = key end
  end
  ok(#junk == 0, "and no ITEM_255 row: " .. table.concat(junk, ","))
  say("map after the prize: " .. tostring(world.map and world.map.id))

  while top() do game.stack:pop() end
  ok(world:pushScreen("Gen2PackMenu", { onClose = function() end }),
    "the pack opens")
  U.wait(10)
  ok(getmetatable(top()) == PackMenu, "on top")
  shot("2202_08_pack_with_vitamins")
  while top() do game.stack:pop() end

  say(fails == 0 and "PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
