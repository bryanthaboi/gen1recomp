-- ../pokecrystal/data/text/battle.asm:240-246
-- ../pokecrystal/data/text/common_2.asm:137-140
-- ../pokecrystal/home/text.asm:502-526
-- ../pokecrystal/home/text.asm:566
-- ../pokecrystal/engine/battle/core.asm:44-46
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal_sendout_nopress_bug3096"
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[3096] " .. (cond and "PASS " or "FAIL ") .. line)
  end
  local function finish()
    print("[3096] " .. (fails == 0 and "PASS done" or "FAIL done"))
    love.event.quit(fails == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  U.wait(45)
  local world = game.world
  ok(world and world.map, "the world booted")
  if not (world and world.map) then finish() end

  local lead = Mon.new(game.data, "DRAGONITE", 47)
  for i, move in ipairs(lead.moves) do
    local def = game.data.moves[move.id]
    if def and (def.power or 0) > 0 then
      table.remove(lead.moves, i)
      table.insert(lead.moves, 1, move)
      break
    end
  end
  game.save.party = { lead }
  game.save.inventory = { POKE_BALL = 5 }
  local trainer = {
    class = 16, classId = "CHAMPION", memberId = "LANCE",
    name = "CHAMPION LANCE", trainerName = "LANCE", className = "CHAMPION",
    party = { Mon.new(game.data, "GYARADOS", 44),
      Mon.new(game.data, "DRAGONITE", 61) },
    baseMoney = 25,
  }
  ok(world:startBattle({ trainer = trainer }), "trainer battle started")
  local screen
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  ok(screen ~= nil, "battle screen up")
  if not screen then finish() end

  local function lines()
    return table.concat(screen:messageLines(), "|")
  end
  local function settle()
    for _ = 1, 600 do
      if screen.typer and screen.typedText == screen.message
          and screen.typer:done() then return true end
      U.wait(1)
    end
    return false
  end
  local function waitFor(p, n)
    for _ = 1, n do
      if p() then return true end
      U.wait(1)
    end
    return p() and true or false
  end
  local function onPage1()
    local m = screen.message
    return m and m:find("sent out", 1, true) and screen.messagePages ~= nil
  end

  local function tapUntilPage1(cap)
    for _ = 1, cap do
      if onPage1() then return true end
      if screen.phase == "menu" then
        if (screen.battle.enemy.hp or 0) > 1 then
          screen.battle.enemy.hp = 1
          screen.battle.enemy.moves = {}
          screen.battle.enemy.status = false
        end
        U.tap(game, "a")
        U.wait(2)
        U.tap(game, "a")
        U.wait(2)
      elseif (screen.messageTimer or 0) > 0 and screen.typer and screen.typer:done() then
        U.tap(game, "a")
      end
      U.wait(1)
    end
    return onPage1()
  end

  ok(tapUntilPage1(2400), "intro reaches CHAMPION LANCE / sent out")
  if not onPage1() then finish() end
  settle()
  ok(lines() == "CHAMPION LANCE|sent out", "intro page 1 reads: " .. lines())
  ok((screen.messageTimer or 0) > 0, "intro page 1 waits for A (cont)")
  U.still(game, out .. "/3096_01_page1_waits.png")
  U.tap(game, "a")
  U.wait(2)
  settle()
  ok(lines() == "sent out|GYARADOS!", "intro page 2 reads: " .. lines())
  ok((screen.messageTimer or 0) == 0, "intro page 2 holds for no press (done)")
  U.still(game, out .. "/3096_02_page2_no_arrow.png")

  local hudAt, slideAt, frames = nil, nil, 0
  local reachedGo = waitFor(function()
    frames = frames + 1
    if not hudAt and screen.showEnemyHud then hudAt = frames end
    if not slideAt and screen.backpicSlide then slideAt = frames end
    return screen.message and screen.message:find("^Go!") ~= nil
  end, 900)
  ok(reachedGo, "Go! DRAGONITE! comes up with no press after page 2")
  ok(hudAt and slideAt and slideAt - hudAt >= 40,
    ("DelayFrames 40 before the back pic slide (%s frames)"):format(
      tostring(hudAt and slideAt and slideAt - hudAt)))
  if reachedGo then
    settle()
    U.still(game, out .. "/3096_03_go_line.png")
  end
  ok(waitFor(function() return screen.phase == "menu" end, 900),
    "battle menu opens with no press after Go!")

  ok(tapUntilPage1(2400), "replacement reaches CHAMPION LANCE / sent out")
  if not onPage1() then finish() end
  settle()
  ok((screen.messageTimer or 0) > 0, "replacement page 1 waits for A (cont)")
  U.tap(game, "a")
  U.wait(2)
  settle()
  ok(lines() == "sent out|DRAGONITE!", "replacement page 2 reads: " .. lines())
  ok((screen.messageTimer or 0) == 0, "replacement page 2 holds for no press (done)")
  U.still(game, out .. "/3096_04_replacement_page2.png")
  ok(waitFor(function() return screen.phase == "menu" end, 900),
    "battle menu opens with no press after the replacement")
  finish()
end
