local U = require("tests.drivers.util")
local Loader = require("src.mods.Loader")
local Sdk = require("tests.modkit.sdk")
local Mon = require("src.battle.gen2.Mon")
local Boxes = require("src.core.gen2.Boxes")

local MOD = {
  ["mods/p7_parity/manifest.json"] = [[{
    "id": "p7_parity",
    "name": "p7 parity",
    "version": "1.0.0",
    "api": 2,
    "entry": "main.lua",
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/p7_parity/main.lua"] = [[
return function(mod)
  local e = mod.exports
  e.style, e.full, e.gifts = 0, 0, {}
  mod.hooks:wrap("battle.style", function(next, battle)
    e.style = e.style + 1
    e.styleArg = battle
    return e.styleAnswer or "set"
  end)
  mod.hooks:wrap("catch.party_full", function(next, ctx)
    e.full = e.full + 1
    e.claimed = ctx.mon
    return true
  end)
  mod.events:on("pokemon.before_give", function(gift)
    e.gifts[#e.gifts + 1] = { species = gift.species, level = gift.level, isEgg = gift.isEgg }
    if not gift.isEgg then
      gift.species, gift.level, gift.nickname = "PICHU", 7, "SPIKE"
    end
  end)
  mod.events:on("pokemon.caught", function(payload) e.destination = payload.destination end)
end
]],
}

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_mod_hooks_p7"
  local version = game.save.version
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen2_mod_hooks_p7 " .. tostring(version)
      .. " failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map and world.vm, "p7 world booted") then return finish() end

  local loader = Loader.new({ fs = Sdk.memfs(MOD), generation = 2, version = version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(2)) do data[key] = nil end
  loader:load(data)
  local mod = loader.mods.p7_parity
  local out = loader.exports.p7_parity
  if not check(mod and not mod.failed and out ~= nil, "p7 mod loaded") then return finish() end

  local asked = 0
  local yesorno = world.vm.yesornoFn
  world.vm.yesornoFn = function(onChoose)
    asked = asked + 1
    return yesorno(onChoose)
  end
  local function runRows(rows, tag)
    if not check(world.vm:start(rows), tag .. " script started") then return false end
    for _ = 1, 1200 do
      if not world.vm:running() then break end
      U.tap(game, "b")
      U.wait(2)
    end
    U.wait(10)
    return check(not world.vm:running(), tag .. " script finished")
  end

  local lead = Mon.new(game.data, "DRAGONITE", 60)
  for i, move in ipairs(lead.moves) do
    local def = game.data.moves[move.id]
    if def and (def.power or 0) > 0 then
      table.remove(lead.moves, i)
      table.insert(lead.moves, 1, move)
      break
    end
  end
  game.save.party = { lead }

  local eevee = game.data.pokemon.EEVEE.index
  if runRows({ { op = "givepoke", species = eevee, level = 20, item = 0, trainer = 0 },
      { op = "end" } }, "p7 givepoke") then
    local gift = out.gifts[1]
    local mon = game.save.party[2]
    check(gift and gift.species == "EEVEE" and gift.level == 20,
      "p7 givepoke raised pokemon.before_give with EEVEE L20")
    check(gift and gift.isEgg == false, "p7 givepoke gift.isEgg is false")
    check(mon and mon.species == "PICHU" and mon.level == 7, "p7 givepoke gave the rewritten PICHU L7")
    check(mon and mon.nickname == "SPIKE", "p7 givepoke named the gift SPIKE")
    check(asked == 0, "p7 givepoke asked no nickname question")
  end

  local togepi = game.data.pokemon.TOGEPI.index
  if runRows({ { op = "giveegg", species = togepi, level = 5 }, { op = "end" } }, "p7 giveegg") then
    local gift = out.gifts[2]
    local egg = game.save.party[3]
    check(gift and gift.species == "TOGEPI" and gift.isEgg == true,
      "p7 giveegg raised pokemon.before_give with isEgg")
    check(egg and egg.isEgg and egg.species == "TOGEPI", "p7 giveegg gave the TOGEPI egg")
  end

  local function battleScreen()
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then return top end
      U.wait(1)
    end
  end
  local function leaveBattle()
    for _ = 1, 600 do
      local top = game.stack:top()
      if not (top and top.battle) then return true end
      U.tap(game, "b")
      U.wait(2)
    end
  end
  local function boxed()
    local n = 0
    for i = 1, Boxes.NUM_BOXES do n = n + #Boxes.box(game.save, i) end
    return n
  end

  game.save.inventory = { MASTER_BALL = 5 }
  game.save.party = {}
  for i = 1, 6 do game.save.party[i] = Mon.new(game.data, "CYNDAQUIL", 30) end
  local boxBefore = boxed()
  local wild = Mon.new(game.data, "SENTRET", 3)
  if check(world:startBattle({ wild = wild }), "p7 wild battle started") then
    local screen = battleScreen()
    if check(screen ~= nil, "p7 wild battle screen up") then
      for _ = 1, 400 do
        if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
        U.tap(game, "a")
        U.wait(3)
      end
      screen:useItem("MASTER_BALL")
      local nickAsked, pcLine = false, false
      for _ = 1, 1500 do
        if screen.phase == "done" then break end
        if screen.phase == "ask-nickname" then nickAsked = true end
        local msg = type(screen.message) == "string" and screen.message:gsub("\n", " ") or ""
        if msg:find("BILL's PC", 1, true) then pcLine = true end
        U.tap(game, "b")
        U.wait(3)
      end
      leaveBattle()
      U.wait(30)
      check(out.full == 1, "p7 catch.party_full ran once on a 6/6 catch")
      check(out.claimed == wild, "p7 catch.party_full ctx.mon is the caught mon")
      check(#game.save.party == 6, "p7 claimed catch left the party at six")
      check(boxed() == boxBefore, "p7 claimed catch put nothing in a box")
      check(not pcLine, "p7 claimed catch printed no BILL's PC line")
      check(not nickAsked, "p7 claimed catch asked no nickname")
      check(out.destination == "mod", "p7 pokemon.caught reported destination mod")
    end
  end

  game.options.battleStyle = "SHIFT"
  local function trainerBattle(answer, shotName)
    out.styleAnswer = answer
    game.save.party = { lead, Mon.new(game.data, "CYNDAQUIL", 30) }
    local trainer = {
      class = 16, classId = "CHAMPION", memberId = "LANCE",
      name = "CHAMPION LANCE", trainerName = "LANCE", className = "CHAMPION",
      party = { Mon.new(game.data, "RATTATA", 5), Mon.new(game.data, "SENTRET", 5) },
      baseMoney = 25,
    }
    local r = { styleBefore = out.style, prompted = false, question = false, replaced = false, shot = false }
    if not check(world:startBattle({ trainer = trainer }), "p7 " .. answer .. " trainer battle started") then
      return r
    end
    local screen = battleScreen()
    r.screen = screen
    if not check(screen ~= nil, "p7 " .. answer .. " trainer battle screen up") then return r end
    for _ = 1, 4000 do
      local phase = screen.phase
      local enemy = screen.battle and screen.battle.enemy
      local msg = type(screen.message) == "string" and screen.message:gsub("\n", " ") or ""
      local typed = screen.typer and screen.typedText == screen.message and screen.typer:done()
      if phase == "ask-shift" or phase == "shift-intro" then r.prompted = true end
      if typed and msg:find("change", 1, true) then r.question = true end
      if typed and not r.firstPage and msg:find("SENTRET", 1, true) then r.firstPage = msg end
      if enemy and enemy.species == "SENTRET" and phase == "menu" then
        r.replaced = true
        break
      end
      if phase == "ask-shift" and not r.shot then
        if typed and (screen.messageTimer or 0) > 0 then
          U.tap(game, "a")
        elseif typed then
          U.wait(4)
          r.shotPage = msg
          r.shotBox = screen.phase == "ask-shift" and (screen.messageTimer or 0) <= 0
          r.shot = U.still(game, dir .. "/" .. shotName)
        end
      elseif answer == "set" and not r.shot and typed and r.firstPage then
        r.shotPage = msg
        r.shotBox = screen.phase == "ask-shift"
        r.shot = U.still(game, dir .. "/" .. shotName)
      elseif phase == "menu" and enemy and enemy.species == "RATTATA" then
        enemy.hp, enemy.moves, enemy.status = 1, {}, false
        U.tap(game, "a")
        U.wait(2)
        U.tap(game, "a")
        U.wait(2)
      elseif phase == "ask-shift" then
        U.tap(game, "b")
      elseif (screen.messageTimer or 0) > 0 and typed then
        U.tap(game, "a")
      end
      U.wait(1)
    end
    return r
  end
  local function winBattle(screen)
    for _ = 1, 3000 do
      local top = game.stack:top()
      if not (top and top.battle) then return true end
      local enemy = screen.battle and screen.battle.enemy
      if screen.phase == "menu" and enemy and (enemy.hp or 0) > 0 then
        enemy.hp, enemy.moves, enemy.status = 1, {}, false
        U.tap(game, "a")
        U.wait(2)
        U.tap(game, "a")
      else
        U.tap(game, "a")
      end
      U.wait(2)
    end
    return false
  end

  local set = trainerBattle("set", "p7_02_set_first_page_after_faint_has_no_question.png")
  check(set.replaced, "p7 the second foe came out")
  check(out.style > set.styleBefore, "p7 battle.style was consulted on the replacement")
  check(out.styleArg == set.screen, "p7 battle.style got the battle screen")
  check(not set.prompted, "p7 set skipped the will-you-change prompt under SHIFT")
  check(set.firstPage ~= nil and not set.firstPage:find("about to use", 1, true),
    "p7 set first page naming SENTRET after the faint is the send-out line: " .. tostring(set.firstPage))
  check(set.shot and not set.question and not set.shotBox,
    "p7 set no change POKEMON question on screen after the faint")
  if not check(set.screen and winBattle(set.screen), "p7 set battle won and closed") then return finish() end
  U.wait(30)

  local shift = trainerBattle("shift", "p7_01_shift_asks_will_you_change_after_faint.png")
  check(shift.prompted, "p7 shift control offered the switch")
  check(shift.shot and shift.shotBox and shift.shotPage and shift.shotPage:find("change", 1, true) ~= nil,
    "p7 shift control shows the change POKEMON question with YES/NO after the faint: " .. tostring(shift.shotPage))
  check(shift.replaced, "p7 shift control sent the second foe out after NO")
  finish()
end
