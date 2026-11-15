-- engine/items/item_effects.asm:114-125
-- engine/items/item_effects.asm:2309-2311
-- engine/battle/core.asm:171-173
-- engine/events/give_pokemon.asm:7-12
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local Boxes = require("src.pokemon.Boxes")
  local BattleState = require("src.battle.BattleState")
  local ItemEffects = require("src.inventory.ItemEffects")
  local Commands = require("src.script.Commands")
  local GameVersion = require("src.core.GameVersion")
  local tag = GameVersion.isYellow() and "yellow" or "red"

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    U.log(ok and "PASS ball_box_full_f4" or "FAIL ball_box_full_f4")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end
  local function ballCount()
    local v = (game.save.inventory or {}).POKE_BALL
    return type(v) == "number" and v or 0
  end
  local function fill(save, boxOne)
    save.party = {}
    for _ = 1, 6 do save.party[#save.party + 1] = Pokemon.new(game.data, "RATTATA", 5) end
    save.boxes = nil
    Boxes.ensure(save)
    save.currentBox = 1
    for _ = 1, boxOne do
      table.insert(save.boxes[1], Pokemon.new(game.data, "PIDGEY", 3))
    end
  end
  local function strip(s)
    return (s or ""):gsub("{[%u_]+}", ""):gsub("[\n\v\f]", " ")
  end

  local cart = game.data.text._BoxFullCannotThrowBallText
  check("cache carries _BoxFullCannotThrowBallText", cart ~= nil)
  local cartKey = "is full! Can't"

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_MET_BILL = true
  game.save.pokedex = game.save.pokedex or { owned = {}, seen = {} }
  game.save.pokedex.owned.PIDGEY = true
  game.save.pokedex.seen.PIDGEY = true

  local seen = {}
  local function watchText(battle)
    local cur = battle and battle.current and battle.current.text
    if cur and seen[#seen] ~= cur then seen[#seen + 1] = cur end
    local top = game.stack:top()
    if top and top.pages then
      local lines = {}
      for _, page in ipairs(top.pages) do
        for _, l in ipairs(page) do lines[#lines + 1] = l end
      end
      local s = "[TextBox] " .. table.concat(lines, " / ")
      if seen[#seen] ~= s then seen[#seen + 1] = s end
    end
  end
  local function sawText(key)
    for _, s in ipairs(seen) do
      if strip(s):find(key, 1, true) then return true end
    end
    return false
  end

  local function startBattle()
    U.teleport(game, "ROUTE_1", 5, 5, "down")
    U.wait(10)
    local ow = game.overworld
    local battle = BattleState.newWild(game, "PIDGEY", 3)
    battle.onFinish = function() end
    battle.rng = function(a) return a end
    ow:pushBattle(battle)
    for _ = 1, 600 do
      if battle.phase == "menu" and game.stack:top() == battle then break end
      U.tap(game, "a")
      U.wait(3)
    end
    return ow, battle
  end

  local function openBagOnBall(battle)
    battle:openItems()
    local bag
    for _ = 1, 120 do
      local t = game.stack:top()
      if t and t.screenId == "BagMenu" then bag = t break end
      U.wait(1)
    end
    if not bag then return nil end
    for _ = 1, 20 do
      local it = bag.items[bag.index]
      if it and it.value == "POKE_BALL" then break end
      U.tap(game, "down")
      U.wait(4)
    end
    return bag
  end

  seen = {}
  game.save.inventory = {}
  Bag.add(game.save, "POKE_BALL", 5)
  fill(game.save, Boxes.CAPACITY)
  local r, payload = ItemEffects.use(game.data, game.save, "POKE_BALL", nil, { kind = "wild" })
  check("A: ItemEffects.use refuses with the cart text", r == "failed"
    and payload and payload[1] == cart)
  local ow, battle = startBattle()
  check("A: battle reached its menu", battle.phase == "menu")
  local bag = openBagOnBall(battle)
  if not check("A: bag opened in battle", bag ~= nil) then finish() end
  U.tap(game, "a")
  local refusalBox
  for _ = 1, 200 do
    watchText(battle)
    local top = game.stack:top()
    if top and top.pages and sawText(cartKey) then refusalBox = top break end
    U.wait(1)
  end
  check("A: BoxFullCannotThrowBallText shown", refusalBox ~= nil)
  if refusalBox then
    U.wait(90)
    U.still(game, DIR .. "/f4_" .. tag .. "_01_box_full_cannot_throw.png")
  end
  check("A: ball not spent", ballCount() == 5)
  for _ = 1, 60 do
    if game.stack:top() == bag then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("A: back in the bag after the refusal", game.stack:top() == bag)
  check("A: no catch", battle.result == nil and #game.save.boxes[1] == Boxes.CAPACITY
    and #game.save.boxes[2] == 0)
  for _ = 1, 60 do
    if game.stack:top() == battle then break end
    U.tap(game, "b")
    U.wait(4)
  end
  U.wait(20)
  check("A: no turn, battle menu back", game.stack:top() == battle and battle.phase == "menu"
    and battle.queue and #battle.queue == 0)
  while game.stack:top() ~= ow do game.stack:pop() end
  U.wait(5)

  seen = {}
  game.save.inventory = {}
  Bag.add(game.save, "POKE_BALL", 5)
  fill(game.save, Boxes.CAPACITY - 1)
  ow, battle = startBattle()
  bag = openBagOnBall(battle)
  if not check("B: bag opened in battle", bag ~= nil) then finish() end
  U.tap(game, "a")
  for _ = 1, 1200 do
    watchText(battle)
    if game.stack:top() == ow then break end
    U.tap(game, "a")
    U.wait(3)
  end
  check("B: ball spent", ballCount() == 4)
  check("B: caught", battle.result == "caught")
  check("B: stored in the current box", #game.save.boxes[1] == Boxes.CAPACITY
    and #game.save.boxes[2] == 0)
  check("B: transfer text shown", sawText("BILL's PC"))
  while game.stack:top() ~= ow do game.stack:pop() end
  U.wait(5)

  seen = {}
  fill(game.save, Boxes.CAPACITY)
  ow, battle = startBattle()
  local st = { balls = 30, steps = 500 }
  battle:makeSafari(st)
  battle.phase = "menu"
  battle:safariAction("ball")
  local safShot = false
  for _ = 1, 400 do
    watchText(battle)
    if not safShot and battle.current and battle.current.text
       and strip(battle.current.text):find(cartKey, 1, true)
       and (battle.charIndex or 0) >= (battle.total or 1) then
      U.still(game, DIR .. "/f4_" .. tag .. "_02_safari_box_full_cannot_throw.png")
      safShot = true
    end
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(3)
  end
  check("C: safari refusal text shown", sawText(cartKey))
  check("C: safari ball not spent", st.balls == 30)
  check("C: safari menu back, no catch", battle.phase == "menu" and battle.result == nil
    and #game.save.boxes[2] == 0)
  while game.stack:top() ~= ow do game.stack:pop() end
  U.wait(5)

  seen = {}
  fill(game.save, Boxes.CAPACITY - 1)
  ow, battle = startBattle()
  st = { balls = 30, steps = 500 }
  battle:makeSafari(st)
  battle.phase = "menu"
  battle:safariAction("ball")
  for _ = 1, 20 do
    watchText(battle)
    if #seen > 0 then break end
    U.wait(1)
  end
  local usedLine = ItemEffects.itemUseLine(game.data, game.save, game.data.items.SAFARI_BALL.name)
  check("D: safari used line is _ItemUseText001", seen[1] == usedLine)
  check("D: safari ball spent", st.balls == 29)
  while game.stack:top() ~= ow do game.stack:pop() end
  U.wait(5)

  fill(game.save, Boxes.CAPACITY)
  local ctx = { game = game, save = game.save }
  Commands.give_pokemon(ctx, "EEVEE", 25)
  check("E: gift refused (carry clear)", ctx.lastCheck == false)
  check("E: gift not put in another box", #game.save.boxes[2] == 0
    and #game.save.boxes[1] == Boxes.CAPACITY)
  while game.stack:top() ~= ow do game.stack:pop() end

  fill(game.save, Boxes.CAPACITY - 1)
  ctx = { game = game, save = game.save }
  Commands.give_pokemon(ctx, "EEVEE", 25)
  check("F: gift stored in the current box", ctx.lastCheck == true
    and #game.save.boxes[1] == Boxes.CAPACITY and #game.save.boxes[2] == 0)
  while game.stack:top() ~= ow do game.stack:pop() end

  for i, s in ipairs(seen) do U.log(("text[%d] %q"):format(i, s)) end
  finish()
end
