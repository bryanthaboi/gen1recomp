-- engine/events/prize_menu.asm:24-28,42
--   POKEPORT_SHOT_DIR=/tmp/shots POKEPORT_VERSION=yellow \
--     POKEPORT_DRIVER=tests/drivers/prize_box_persists_2195.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
              or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local PrizeCounter = require("src.ui.PrizeCounter")

  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end
  local function quit()
    U.wait(2)
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local function topMeta() return getmetatable(game.stack:top()) end
  local function pageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local parts = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "bryan"
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.COIN_CASE = 1
  game.save.coins = 5000

  U.teleport(game, "GAME_CORNER_PRIZE_ROOM", 2, 3, "up")
  U.wait(20)
  local ow = game.overworld
  if not check("prize room loaded", ow and ow.map
               and ow.map.id == "GAME_CORNER_PRIZE_ROOM") then quit() end

  local function openMenu()
    U.tap(game, "a")
    for _ = 1, 120 do
      if topMeta() == PrizeCounter then return true end
      U.tap(game, "a")
      U.wait(1)
    end
    return false
  end

  if not check("the prize window opens", openMenu()) then quit() end
  U.tap(game, "down")
  U.wait(2)
  local prize = game.stack:top().prizes[game.stack:top().index]
  U.log("picking", prize.name, "for", prize.cost, "coins")
  U.tap(game, "a")

  local sawAsk = false
  for _ = 1, 120 do
    if topMeta() == ChoiceBox then sawAsk = true break end
    U.wait(1)
  end
  check("SoYouWantPrize's YES/NO comes up", sawAsk)
  check("with the prize list handed to the overworld",
        ow.prizeWindow ~= nil and ow.prizeWindow.index == 2)
  U.shot(game, DIR .. "/2195_01_window_during_ask.png")

  U.tap(game, "a")
  for _ = 1, 120 do
    if topMeta() ~= ChoiceBox then break end
    U.wait(1)
  end
  local sawGot, sawNick, shotGot = false, false, false
  for _ = 1, 900 do
    if game.stack:top() == ow then break end
    local text = pageText()
    if not shotGot and text:find("got", 1, true)
       and text:find(prize.name, 1, true) then
      sawGot = true
      for _ = 1, 60 do
        local top = game.stack:top()
        if getmetatable(top) == TextBox and top.waiting then break end
        U.wait(1)
      end
      check("the prize list is still up over the gift text",
            ow.prizeWindow ~= nil)
      shotGot = U.shot(game, DIR .. "/2195_02_window_during_got_mon.png")
    end
    if topMeta() == ChoiceBox then
      if not sawNick then
        sawNick = true
        check("and still up under the nickname prompt", ow.prizeWindow ~= nil)
        U.shot(game, DIR .. "/2195_03_window_during_nickname.png")
      end
      U.tap(game, "b")
    else
      U.tap(game, "a")
    end
    U.wait(1)
  end

  check("the counter hands control back", game.stack:top() == ow)
  check("GotMonText printed", sawGot)
  check("the nickname prompt appeared", sawNick)
  check("coins were subtracted once", game.save.coins == 5000 - prize.cost)
  check("and the window's rows go back to the map", ow.prizeWindow == nil)
  U.wait(10)
  U.shot(game, DIR .. "/2195_04_window_gone.png")

  if check("the window opens again", openMenu()) then
    U.tap(game, "a")
    for _ = 1, 120 do
      if topMeta() == ChoiceBox then break end
      U.wait(1)
    end
    U.tap(game, "b")
    for _ = 1, 120 do
      if getmetatable(game.stack:top()) == TextBox then break end
      U.wait(1)
    end
    check("Oh, fine then. prints under the prize list", ow.prizeWindow ~= nil)
    U.shot(game, DIR .. "/2195_05_window_during_oh_fine_then.png")
    for _ = 1, 120 do
      if game.stack:top() == ow then break end
      U.tap(game, "a")
      U.wait(2)
    end
    check("and the refusal ends the conversation", game.stack:top() == ow)
    check("dropping the window with it", ow.prizeWindow == nil)
  end

  quit()
end
