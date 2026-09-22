-- engine/items/item_effects.asm:1731-1745
-- audio/poke_flute.asm:1
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1; print("PASS " .. label)
    else fail = fail + 1; print("FAIL " .. label) end
    return ok
  end
  local function finish()
    U.log(("RESULT pass=%d fail=%d"):format(pass, fail))
    love.event.quit(fail == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local lead = Pokemon.new(game.data, "CHARIZARD", 50)
  game.save.party = { lead }
  Bag.add(game.save, "POKE_FLUTE", 1)
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(20)

  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  for _ = 1, 120 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  if not check("2305 wild battle reached its menu", battle.phase == "menu") then
    finish()
  end

  lead.status = "SLP"
  local turns = 0
  local realItemUsed = battle.itemUsed
  battle.itemUsed = function(self, ...)
    turns = turns + 1
    return realItemUsed(self, ...)
  end

  local bag
  for _ = 1, 20 do
    local top = game.stack:top()
    if top and top.screenId == "BagMenu" then bag = top break end
    U.tap(game, "down"); U.wait(4)
    U.tap(game, "left"); U.wait(4)
    U.tap(game, "a"); U.wait(14)
  end
  if not check("2305 ITEM opened the bag", bag ~= nil) then finish() end

  local row
  for i, item in ipairs(bag.items or {}) do
    if item.value == "POKE_FLUTE" then row = i end
  end
  if not check("2305 POKE FLUTE in the battle bag", row ~= nil) then finish() end
  for _ = 1, 40 do
    if bag.index == row then break end
    U.tap(game, bag.index < row and "down" or "up")
    U.wait(3)
  end
  U.tap(game, "a")
  U.wait(20)

  local box
  for _ = 1, 240 do
    local top = game.stack:top()
    if top and top.isTextBox then box = top break end
    U.wait(1)
  end
  if not check("2305 played-flute box opened", box ~= nil) then finish() end

  for _ = 1, 240 do
    if box.done then break end
    U.tap(game, "a")
  end
  check("2305 line typed out", box.done == true)
  check("2305 no tune before the prompt",
    box.autoStarted ~= true and box.autoSrc == nil)
  U.shot(game, DIR .. "/2305_01_played_flute_prompt.png")

  U.tap(game, "a")
  U.wait(2)
  check("2305 prompt answered", box.autoPrompted == true)
  local src = box.autoSrc
  if not check("2305 tune started", src ~= nil) then finish() end

  local okd, dur = pcall(src.getDuration, src, "seconds")
  dur = okd and dur or -1
  U.log(("tune source runs %.3f s (in-battle 4.267, field 9.600)"):format(dur))
  check("2305 in-battle phrase length (4.27 s, not 9.6 s)",
    math.abs(dur - 256 / 60) < 0.1)
  check("2305 derived def played, not the field Pokeflute",
    require("src.core.Sound").isPlaying("Pokeflute_In_Battle")
    and not require("src.core.Sound").isPlaying("Pokeflute"))

  local t0 = love.timer.getTime()
  local shot, brokeOut = false, false
  for _ = 1, 900 do
    local ok, playing = pcall(src.isPlaying, src)
    if not (ok and playing) then break end
    if game.stack:top() ~= box then brokeOut = true break end
    if not shot and love.timer.getTime() - t0 > 1.5 then
      U.shot(game, DIR .. "/2305_02_short_tune_playing.png")
      shot = true
    else
      U.tap(game, "a")
    end
  end
  local held = love.timer.getTime() - t0
  U.log(("the box stayed up %.2f s under the tune"):format(held))
  check("2305 A never cut the tune short", not brokeOut)
  check("2305 box held about 4.3 s", held > 3.6 and held < 5.2)
  check("2305 turn did not resolve over the tune", turns == 0)

  U.wait(20)
  local woke = game.stack:top()
  check("2305 FluteWokeUpText follows the tune",
    woke ~= nil and woke ~= box and woke.isTextBox == true)
  for _ = 1, 60 do
    if woke.done then break end
    U.wait(2)
  end
  U.shot(game, DIR .. "/2305_03_all_woke_up.png")

  for _ = 1, 200 do
    if turns > 0 then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("2305 dismissing it spends the turn", turns == 1)
  check("2305 lead is awake", lead.status == nil)
  finish()
end
