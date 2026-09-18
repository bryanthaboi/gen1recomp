local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local fails = 0
  local function check(cond, label)
    if cond then
      print("PASS " .. label)
    else
      fails = fails + 1
      print("FAIL " .. label)
    end
  end

  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED", rivalName = "BLUE", gender = 0 })
  U.wait(120)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local Party = require("src.core.game3.party")
  local Rng = require("src.core.game3.rng")
  session.party = {}
  Party.giveMon(session, 52, 50)
  Party.giveMon(session, 52, 10)
  local lead = session.party[1]
  lead.moves, lead.pp, lead.maxPp = { 6 }, { 20 }, { 20 }
  lead.item, lead.heldItem = 13, 13
  local picker = session.party[2]
  picker.abilityId, picker.item, picker.heldItem = 53, nil, nil
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")

  local function onScreen()
    if not Ui._showing then return "" end
    local log = Ui.log() or {}
    return log[#log - #(Ui._queue or {})] or ""
  end
  local function find(needle)
    for i, t in ipairs(Ui.log() or {}) do
      if t:find(needle, 1, true) then return i end
    end
    return nil
  end
  local function count(needle)
    local n = 0
    for _, t in ipairs(Ui.log() or {}) do
      if t:find(needle, 1, true) then n = n + 1 end
    end
    return n
  end
  local function advanceUntil(pred, limit)
    for f = 1, limit do
      U.wait(1)
      if pred() then return true end
      if f % 20 == 0 then U.tap(game, "a") end
    end
    return false
  end

  local money0 = tonumber(session.money) or 0
  local ok = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 2 }, {})
  check(ok, "u7b wild battle started")
  local sawCoins = advanceUntil(function() return onScreen():find("Coins scattered", 1, true) ~= nil end, 3000)
  check(sawCoins, "u7b wild Pay Day scattered coins")
  if sawCoins then
    U.wait(60)
    U.shot(game, DIR .. "/u7b_01_wild_coins_scattered.png")
  end
  local realRandom = Rng.Random
  local stubbed = false
  local sawPick = advanceUntil(function()
    if not stubbed and find("fainted!") then
      Rng.Random = function() return 0 end
      stubbed = true
    end
    return onScreen():find("picked up", 1, true) ~= nil
  end, 3000)
  check(sawPick, "u7b wild picked up line on screen")
  if sawPick then
    local n = count("Coins scattered")
    local expect = 250 * n
    check(onScreen() == string.format("RED picked up\n¥%d!", expect), "u7b wild picked up text is RED picked up ¥" .. expect)
    check((tonumber(session.money) or 0) == money0 + expect, "u7b wild money increased by Pay Day bonus")
    local iExp, iPick = find("EXP. Points"), find("picked up")
    check(iExp and iPick and iExp < iPick, "u7b wild picked up follows EXP line")
    check(#(Ui._queue or {}) == 0, "u7b wild picked up is the last text")
    U.wait(120)
    U.shot(game, DIR .. "/u7b_02_wild_picked_up_money.png")
  end
  local ended = advanceUntil(function() return not Battle.isActive() end, 3000)
  Rng.Random = realRandom
  check(ended, "u7b wild battle ended")
  check(picker.item == 139 and picker.heldItem == 139, "u7b Pickup MEOWTH picked up ORAN BERRY")
  check(lead.item == 13, "u7b holding MEOWTH kept its item")
  U.wait(90)
  U.shot(game, DIR .. "/u7b_03_wild_back_on_overworld.png")

  for i, t in ipairs(Ui.log() or {}) do print("U7B WILD LOG", i, (t:gsub("\n", " / "))) end

  U.wait(30)
  local money1 = tonumber(session.money) or 0
  ok = BattleBridge.start(Runtime._mod, game, { species = 7, level = 5, trainerId = 326 }, { trainerId = 326 })
  check(ok, "u7b trainer battle started")
  local sawPrize = advanceUntil(function() return onScreen():find("for winning", 1, true) ~= nil end, 4000)
  check(sawPrize, "u7b trainer prize money line on screen")
  if sawPrize then
    local iPrize, iPick = find("for winning"), find("picked up")
    check(iPick == nil or (iPrize < iPick and #(Ui._queue or {}) > 0), "u7b trainer picked up not shown before prize money")
    U.wait(120)
    U.shot(game, DIR .. "/u7b_04_trainer_prize_money.png")
  end
  local sawPick2 = advanceUntil(function() return onScreen():find("picked up", 1, true) ~= nil end, 2000)
  check(sawPick2, "u7b trainer picked up line follows prize money")
  if sawPick2 then
    local n = count("Coins scattered")
    local prize = 0
    for _, t in ipairs(Ui.log() or {}) do
      local v = t:match("got ¥(%d+)")
      if v then prize = tonumber(v) end
    end
    check((tonumber(session.money) or 0) == money1 + prize + 250 * n, "u7b trainer money has prize plus Pay Day bonus")
    U.wait(120)
    U.shot(game, DIR .. "/u7b_05_trainer_picked_up_after_prize.png")
  end
  local tEnded = advanceUntil(function() return not Battle.isActive() end, 3000)
  check(tEnded, "u7b trainer battle ended")

  for i, t in ipairs(Ui.log() or {}) do print("U7B TRAINER LOG", i, (t:gsub("\n", " / "))) end
  if fails == 0 then
    print("PASS u7b payday")
    love.event.quit(0)
  else
    print("FAIL u7b payday")
    love.event.quit(1)
  end
end
