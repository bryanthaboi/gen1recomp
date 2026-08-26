-- The Crystal story specials, driven in a real game.
--
--   POKEPORT_IDENTITY=unitb-crystal POKEPORT_GAME=crystal \
--     POKEPORT_VERSION=crystal POKEPORT_SHOT_DIR=/tmp/unitb \
--     POKEPORT_DRIVER=tests/drivers/crystal_story_shots.lua love .
--
-- Four sections, each entered by putting the player on the real map and
-- letting the extracted script run:
--   A  TIN_TOWER_1F  the Suicune confrontation, and whether it flees
--   B  ILEX_FOREST   the GS Ball shrine, Celebi, and CheckCaughtCelebi
--   C  DRAGON_SHRINE GiveDratini's Extremespeed moveset
--   D  DAY_CARE      GiveOddEgg
local U = require("tests.drivers.util")

local BattleState = require("src.ui.gen2.BattleState")
local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local Roamers = require("src.core.gen2.Roamers")
local Save = require("src.core.gen2.Save")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-story"
  local fails = 0

  local function say(line) print("[driver] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "OK   " or "FAIL ") .. line)
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function top() return game.stack:top() end
  local function battleState()
    local st = top()
    if st ~= nil and getmetatable(st) == BattleState then return st end
    return nil
  end
  local function inBattle()
    local st = battleState()
    return st and st.battle or nil
  end

  local function waitFor(pred, frames)
    for _ = 1, frames or 1200 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end

  local world

  -- Mash A until the script is finished and the stack is bare again.  The
  -- naming screen gets B: `givepoke` ends in Specials.askNickname
  -- (src/script/gen2/Specials.lua:382) and mashing A there types letters
  -- forever instead of leaving.
  -- The naming screen has no B exit: crystal_boot_smoke.lua leaves it by
  -- putting the cursor on the bottom row's confirm cell.  Confirming a blank
  -- name is the cart's own "no nickname" (home/string.asm:6 _InitString).
  local function mash()
    local st = top()
    if getmetatable(st) == NamingScreen then
      st.row, st.col = st:bottomRow(), 6
    end
    tap("a", 2)
  end

  local function settle(frames)
    for _ = 1, frames or 3000 do
      if not world:busy() and top() == nil then return true end
      mash()
    end
    local meta, name = getmetatable(top()), "?"
    for id, mod in pairs(package.loaded) do
      if mod == meta then name = id end
    end
    say(("   stuck on %s (phase=%s) busy=%s"):format(name,
      tostring(top() and top().phase), tostring(world:busy())))
    return false
  end

  -- Stand one cell below the object carrying `scriptKey`, facing it.
  local function standBelow(mapId, scriptKey)
    world:setMap(mapId, 1, 1, "down")
    U.wait(10)
    local tx, ty
    for _, npc in ipairs(world.npcs or {}) do
      if npc.def and npc.def.scriptKey == scriptKey then
        tx, ty = npc.cellX, npc.cellY
      end
    end
    if not tx then return false end
    world:setMap(mapId, tx, ty + 1, "up")
    U.wait(30)
    return world.player.cellX == tx and world.player.cellY == ty + 1
  end

  local function moveIds(mon)
    local list = {}
    for _, move in ipairs((mon and mon.moves) or {}) do
      list[#list + 1] = move.id
    end
    return table.concat(list, ",")
  end

  U.wait(60)
  world = game.world
  assert(world and world.map, "crystal world did not boot")
  say("version=" .. GameVersion.get() .. " engine=" .. GameVersion.engine())

  local save = game.save
  save.player = save.player or {}
  save.player.name = save.player.name or "CHRIS"
  save.player.id = save.player.id or 30000
  save.inventory = save.inventory or {}
  save.party = { Mon.new(game.data, "TYPHLOSION", 50) }

  -- ---- A  TIN_TOWER_1F ----------------------------------------------------
  -- ../pokecrystal/maps/TinTower1F.asm:84 TinTower1FSuicuneBattleScript, run
  -- from the SCENE_TINTOWER1F_SUICUNE_BATTLE scene script at :22.
  say("A  Tin Tower")
  say("   crystal AlwaysFleeMons SUICUNE = "
    .. tostring(Roamers.alwaysFleeMons("crystal").SUICUNE)
    .. ", gold = " .. tostring(Roamers.alwaysFleeMons("gold").SUICUNE))
  world.mapScenes.TIN_TOWER_1F = 0
  world:setMap("TIN_TOWER_1F", 9, 14, "up")
  U.wait(20)
  U.shot(game, out .. "/a1-tintower-enter.png")

  ok(waitFor(function() return world:busy() end, 600),
    "the scene script started on map entry")
  U.wait(120)
  U.shot(game, out .. "/a2-beasts.png")
  ok(waitFor(function() return inBattle() ~= nil end, 3000),
    "the Tin Tower scene reached a battle")
  local battle = inBattle()
  if battle then
    U.wait(90)
    U.shot(game, out .. "/a3-suicune-battle.png")
    ok(battle.enemy and battle.enemy.species == "SUICUNE",
      "the wild mon is SUICUNE (got " ..
      tostring(battle.enemy and battle.enemy.species) .. ")")
    ok((battle.enemy and battle.enemy.level) == 40, "at level 40")
    -- ../pokecrystal/engine/battle/core.asm:759 TryEnemyFlee: with Suicune off
    -- AlwaysFleeMons it has to survive the two random gates as well.
    local fled = 0
    for _ = 1, 500 do
      if battle:tryEnemyFlee() then fled = fled + 1 end
    end
    ok(fled == 0, "Suicune never flees in 500 rolls (fled " .. fled .. ")")
    ok(battle.outcome == nil, "and the battle is still live")
    battle.outcome = "run"
    local st = battleState()
    if st then st:finishBattle() end
  end
  ok(settle(2000), "the Tin Tower script ran to its end")

  -- ---- B  ILEX_FOREST -----------------------------------------------------
  -- ../pokecrystal/maps/IlexForest.asm:429 IlexForestShrineScript, a BGEVENT_UP
  -- at (8,22).  EVENT_FOREST_IS_RESTLESS and the GS Ball are the two gates; on
  -- a retail cart neither can be reached, so both are set here the way the
  -- Virtual Console wrapper sets sGSBallFlag
  -- (../pokecrystal/engine/menus/save.asm:168).
  say("B  Ilex Forest shrine")
  save.party = { Mon.new(game.data, "TYPHLOSION", 50) }
  Save.crystalState(save).gsBall = "have"
  save.inventory.GS_BALL = 1
  save.inventory.MASTER_BALL = 5
  world:setMap("ILEX_FOREST", 8, 23, "up")
  U.wait(40)
  world.events:set(192, true)
  U.shot(game, out .. "/b1-shrine.png")

  tap("a", 30)
  U.shot(game, out .. "/b2-shrine-prompt.png")
  -- The prompt is the script's own yesorno; A takes YES.
  ok(waitFor(function()
    if inBattle() then return true end
    tap("a", 3)
    return false
  end, 400), "the shrine script reached a battle")
  local celebi = inBattle()
  if celebi then
    U.wait(90)
    U.shot(game, out .. "/b3-celebi.png")
    ok(celebi.enemy and celebi.enemy.species == "CELEBI",
      "the wild mon is CELEBI (got " ..
      tostring(celebi.enemy and celebi.enemy.species) .. ")")
    ok(celebi.battleType == 11,
      "the battle carries BATTLETYPE_CELEBI (got "
      .. tostring(celebi.battleType) .. ")")
    -- Catch it with a MASTER BALL so CheckCaughtCelebi has something to read.
    local thrown = false
    for _ = 1, 900 do
      local st = battleState()
      if not st then break end
      if not thrown and st.phase == "menu" then
        st:useItem("MASTER_BALL")
        thrown = true
        U.wait(60)
        U.shot(game, out .. "/b4-masterball.png")
      end
      mash()
    end
  end
  ok(settle(2000), "the shrine script ran to its end")
  U.shot(game, out .. "/b5-after-celebi.png")
  local caught = false
  for _, mon in ipairs(save.party) do
    if mon.species == "CELEBI" then caught = true end
  end
  ok(caught, "Celebi is in the party")
  ok(Save.crystalState(save).celebiCaught == true,
    "CheckCaughtCelebi recorded the catch")
  ok((save.inventory.GS_BALL or 0) == 0, "the GS Ball was taken")

  -- ---- C  DRAGON_SHRINE ---------------------------------------------------
  -- ../pokecrystal/maps/DragonShrine.asm:192 DragonShrineElder1Script, whose
  -- .GiveDratini arm (:208) is `givepoke DRATINI, 15 / checkevent
  -- EVENT_ANSWERED_DRAGON_MASTER_QUIZ_WRONG / special GiveDratini`.
  say("C  Dragon Shrine")
  save.party = { Mon.new(game.data, "TYPHLOSION", 50) }
  -- ../pokecrystal/maps/DragonShrine.asm:10 SCENE_DRAGONSHRINE_NOOP; scene 0 is
  -- the Dragon Master quiz cutscene, which is not what this section measures.
  world.mapScenes.DRAGON_SHRINE = 1
  ok(standBelow("DRAGON_SHRINE", "63:51a5"), "found the shrine elder")
  U.shot(game, out .. "/c1-shrine.png")
  tap("a", 30)
  U.shot(game, out .. "/c2-elder.png")
  ok(settle(2000), "the elder's script ran to its end")
  U.shot(game, out .. "/c3-dratini.png")
  local dratini
  for _, mon in ipairs(save.party) do
    if mon.species == "DRATINI" then dratini = mon end
  end
  ok(dratini ~= nil, "the elder handed over a DRATINI")
  if dratini then
    say("   moves = " .. moveIds(dratini))
    ok(moveIds(dratini) == "WRAP,THUNDER_WAVE,TWISTER,EXTREMESPEED",
      "with .Moveset0, Extremespeed and all")
    ok(dratini.moves[4].pp == 5, "Extremespeed arrives with 5 PP")
  end

  -- ---- D  DAY_CARE --------------------------------------------------------
  -- ../pokecrystal/maps/DayCare.asm:23 DayCareManScript_Inside, whose
  -- `special GiveOddEgg` is at :33.
  say("D  Day Care")
  save.party = { Mon.new(game.data, "TYPHLOSION", 50) }
  save.inventory.EGG_TICKET = 1
  ok(standBelow("DAY_CARE", "18:6f8f"), "found the Day-Care Man")
  U.shot(game, out .. "/d1-daycare.png")
  tap("a", 30)
  U.shot(game, out .. "/d2-gramps.png")
  ok(settle(2000), "the Day-Care Man's script ran to its end")
  U.shot(game, out .. "/d3-oddegg.png")
  local egg = save.party[2]
  ok(egg ~= nil and egg.isEgg == true, "an EGG joined the party")
  if egg then
    say(("   %s ot=%s otId=%s eggSteps=%s moves=%s"):format(
      tostring(egg.species), tostring(egg.ot), tostring(egg.otId),
      tostring(egg.eggSteps), moveIds(egg)))
    ok(egg.ot == "ODD", "with OT ODD")
    ok(egg.eggSteps == 20, "and 20 hatch cycles")
  end
  ok((save.inventory.EGG_TICKET or 0) == 0, "the EGG TICKET was tossed")

  say(fails == 0 and ("PASS crystal story in " .. out)
    or ("FAIL " .. fails .. " checks, shots in " .. out))
  love.event.quit(fails == 0 and 0 or 1)
end
