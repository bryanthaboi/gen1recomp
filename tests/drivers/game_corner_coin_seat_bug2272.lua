-- POKEPORT_IDENTITY=red-sep04 POKEPORT_DRIVER=tests/drivers/game_corner_coin_seat_bug2272.lua POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failed = false

  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end

  local KEY = "GAME_CORNER_12_15"

  U.teleport(game, "GAME_CORNER", 12, 16, "up")
  U.wait(20)
  local save = game.save
  save.inventory.COIN_CASE = 1
  save.coins = 50
  save.hiddenTaken = save.hiddenTaken or {}
  save.hiddenTaken[KEY] = nil
  U.shot(game, DIR .. "/2272_01_facing_seat_12_15.png")

  local ow = game.stack:top()
  U.tap(game, "a")
  local frames = 0
  for _ = 1, 120 do
    if game.stack:top() ~= ow then break end
    U.wait(1)
    frames = frames + 1
  end
  local box = game.stack:top()
  check("2272 seat 12_15 opens a box", box ~= ow)
  check("2272 seat 12_15 is the slot prompt", type(box) == "table" and type(box.choice) == "function")
  check("2272 seat 12_15 pays no coins", save.coins == 50)
  check("2272 seat 12_15 sets no hidden coin flag", not save.hiddenTaken[KEY])

  U.wait(frames + 60)
  U.shot(game, DIR .. "/2272_02_slot_prompt_not_coins.png")

  love.event.quit(failed and 1 or 0)
end
