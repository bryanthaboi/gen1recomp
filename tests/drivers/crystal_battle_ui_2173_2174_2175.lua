-- ../pokecrystal/engine/battle/core.asm:3208
-- ../pokecrystal/engine/battle/core.asm:5156
-- ../pokecrystal/home/text.asm:630
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-battle-ui-2173"
  os.execute("mkdir -p '" .. out .. "'")
  local shotN = 0
  local function shot(tag)
    shotN = shotN + 1
    game.capturePath = string.format("%s/%03d_%s.png", out, shotN, tag)
    U.wait(2)
  end
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[battle-ui-2173/2174/2175] " .. (cond and "PASS " or "FAIL ") .. msg)
    return cond
  end

  U.wait(60)
  local world, data, save = game.world, game.data, game.save
  assert(world and world.map, "the crystal world did not boot")
  save.party = {
    Mon.new(data, "CYNDAQUIL", 20),
    Mon.new(data, "TOTODILE", 20),
  }
  save.inventory = { POKE_BALL = 5 }
  world:warpToMapId("NEW_BARK_TOWN", 13, 7, "down")
  for _ = 1, 120 do
    if not world:busy() then break end
    U.wait(1)
  end

  local function screenUp()
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then return top end
      U.wait(1)
    end
  end

  -- ShowSetEnemyMonAndSendOutAnimation runs (core.asm:3221)
  local trainer = {
    class = 1, classId = "YOUNGSTER", memberId = "JOEY",
    name = "YOUNGSTER JOEY", trainerName = "JOEY", className = "YOUNGSTER",
    party = { Mon.new(data, "RATTATA", 4) },
    baseMoney = 12,
  }
  assert(world:startBattle({ trainer = trainer }), "trainer battle failed")
  local screen = screenUp()
  ok(screen ~= nil, "the trainer battle screen is up")

  local sawTrainer, sawEmpty, popped = false, false, false
  local shotEmpty = false
  for _ = 1, 2400 do
    if screen.showEnemyTrainer then sawTrainer = true end
    if sawTrainer and not screen.showEnemyTrainer and not screen.afterSendOut
       and not screen.anim and not screen.showEnemyHud then
      if screen:picBoxCleared("enemy") then
        sawEmpty = true
        if not shotEmpty then shotEmpty = true shot("2173_box_empty") end
      else
        popped = true
      end
    end
    if screen.showEnemyHud then break end
    if (screen.messageTimer or 0) > 0 then U.tap(game, "a") end
    U.wait(1)
  end
  ok(sawTrainer, "the trainer frontpic stood in the enemy box")
  ok(sawEmpty, "the box was empty across SlideBattlePicOut -> the send-out")
  ok(not popped, "the mon never popped in before ANIM_SEND_OUT_MON")

  local held = false
  for _ = 1, 1800 do
    if (screen.messageTimer or 0) > 0 and screen.typer and screen.typer:done()
    then held = true break end
    U.wait(1)
  end
  ok(held, "a battle line is holding for PromptButton")
  if held then
    screen.arrowBlink = 0
    ok(screen:messageArrowVisible(), "the down arrow is on at blink phase 0")
    shot("2174_arrow_on")
    screen.arrowBlink = 16
    ok(not screen:messageArrowVisible(),
      "UnloadBlinkingCursor blanks it at phase 16")
    shot("2174_arrow_off")
    screen.arrowBlink = 0
  end

  for _ = 1, 2400 do
    if screen.phase == "menu" then break end
    if (screen.messageTimer or 0) > 0 or screen.phase == "stats-box" then
      U.tap(game, "a")
    end
    U.wait(1)
  end
  ok(screen.phase == "menu", "reached the battle menu")

  -- accepted switch calls CloseWindow (core.asm:5162)
  U.tap(game, "right")
  U.wait(4)
  U.tap(game, "a")
  local list
  for _ = 1, 300 do
    local top = game.stack:top()
    if top and top ~= screen then list = top break end
    U.wait(1)
  end
  ok(list ~= nil, "the party list opened")
  U.wait(6)
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "a")
  U.wait(8)
  local result = list and list.itemResult
  ok(game.stack:top() == list, "the party list is still on screen")
  ok(list and list.submenu == nil, "the SWITCH/STATS/CANCEL box is gone")
  ok(result and (result.text or ""):find("already out"),
    "BattleText_MonIsAlreadyOut printed over the list")
  ok(screen.phase == "submenu", "the battle screen never took the box back")
  shot("2175_already_out")
  U.tap(game, "a")
  U.wait(8)
  ok(list and list.itemResult == nil and game.stack:top() == list,
    "A dismisses the line back to a live list")
  shot("2175_list_back")

  print("[battle-ui-2173/2174/2175] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")) .. " -- " .. shotN .. " shots in " .. out)
  love.event.quit(fails == 0 and 0 or 1)
end
