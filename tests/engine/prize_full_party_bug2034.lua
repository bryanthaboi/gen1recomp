-- ../pokered/engine/events/prize_menu.asm:181 (#2034)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function() end,
  drawCode = function() end,
  drawBox = function() end,
  width = function(text) return #tostring(text) * 8 end,
  split = function(text)
    local out = {}
    for i = 1, #tostring(text) do out[i] = i end
    return out
  end,
}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts, isTextBox = true }
  end,
}
package.loaded["src.core.Sound"] = { play = function() end }
package.loaded["src.core.GameVersion"] = {
  isBlue = function() return false end,
  isYellow = function() return false end,
}
local bagFull = false
package.loaded["src.inventory.Bag"] = {
  add = function() return not bagFull end,
}

local M = assert(loadfile("data/scripts/story3.lua"))()
local counters = M.GAME_CORNER_PRIZE_ROOM.talk

local pressed, done, ran
local function mkGame(coins)
  done, ran = false, nil
  local mons = {}
  for _, n in ipairs({ "ABRA", "CLEFAIRY", "NIDORINA" }) do
    mons[n] = { name = n }
  end
  return {
    data = {
      text = {},
      pokemon = mons,
      items = {
        TM_DRAGON_RAGE = { name = "TM23" },
        TM_HYPER_BEAM = { name = "TM15" },
        TM_SUBSTITUTE = { name = "TM35" },
      },
    },
    save = { coins = coins, inventory = { COIN_CASE = 1 } },
    input = {
      wasPressed = function(_, b) return pressed == b end,
      isDown = function() return false end,
    },
    stack = {
      states = {},
      push = function(self, s) self.states[#self.states + 1] = s end,
      pop = function(self) return table.remove(self.states) end,
      top = function(self) return self.states[#self.states] end,
    },
  }
end

local function mkOw(game)
  return {
    runner = {
      run = function(_, script, extra)
        ran = { script = script, extra = extra, depth = #game.stack.states }
      end,
    },
  }
end

local function open(n, coins)
  local game = mkGame(coins or 5000)
  local ow = mkOw(game)
  counters["TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_" .. n](
    game, ow, nil, function() done = true end)
  local exchange = game.stack:pop()
  exchange.onDone()
  local which = game.stack:top()
  which.opts.stay.onShown()
  return game, which, game.stack:top(), ow
end

local function pick(game, window, index, yes)
  window.index = index
  pressed = "a"
  window:update(1 / 60)
  pressed = nil
  local ask = game.stack:pop()
  ask.opts.choice(yes)
end

do
  local game, which, window, ow = open(1)
  local cost = window.prizes[1].cost
  pick(game, window, 1, true)

  check(ran ~= nil, "the mon gift runs on the script runner")
  -- engine/events/prize_menu.asm:24-28,42
  check(ow.prizeWindow ~= nil,
        "the prize list is still drawn while the gift script runs")
  eq(ow.prizeWindow.index, 1, "with the cursor on the picked row")
  eq(ran.depth, 0,
     "WhichPrizeText and the menu come down first, so nothing is orphaned")
  eq(#game.stack.states, 0, "and the callback pushed nothing of its own")
  for _, state in ipairs(game.stack.states) do
    check(state ~= which, "the stay box never survives the transaction")
  end
  eq(game.save.coins, 5000, "coins are the script's job, not the callback's")
  check(type(ran.extra.onDone) == "function",
        "the runner releases the sign when the script ends")
  ran.extra.onDone()
  eq(ow.prizeWindow, nil, "and the window's rows go back with it")
  check(done, "the conversation ends there")

  local rows = ran.script
  eq(rows[1][1], "give_pokemon", "GivePokemon first (prize_menu.asm:224)")
  eq(rows[1][2], window.prizes[1].prize.species, "for the picked prize")
  eq(rows[1][5], true, "with GotMonText (give_pokemon.asm:46, :68)")
  eq(rows[2][1], "jump_if_false", "carry decides (prize_menu.asm:233)")
  eq(rows[3][1], "take_coins", "only then .subtractCoins")
  eq(rows[3][2], cost, "for the prize's price")

  local function exec(gave)
    local labels, texts, coins = {}, {}, 0
    for i, row in ipairs(rows) do
      if row[1] == "label" then labels[row[2]] = i end
    end
    local pc, lastCheck = 1, nil
    while pc <= #rows do
      local row = rows[pc]
      local verb = row[1]
      if verb == "give_pokemon" then
        lastCheck = gave
      elseif verb == "take_coins" then
        coins = coins + row[2]
      elseif verb == "show_text" then
        texts[#texts + 1] = row[2]
      elseif verb == "jump" then
        pc = labels[row[2]]
      elseif verb == "jump_if_false" and not lastCheck then
        pc = labels[row[2]]
      end
      pc = pc + 1
    end
    return coins, table.concat(texts, ",")
  end

  local spent, texts = exec(true)
  eq(spent, cost, "a mon that landed costs its coins")
  eq(texts, "", "and prints nothing beyond GivePokemon's own text")
  spent, texts = exec(false)
  eq(spent, 0, "party and box full: `ret nc`, no coins move")
  eq(texts, "_BoxIsFullText",
     "and the box-full line is GivePokemon's (give_pokemon.asm:40-42)")
end

do
  bagFull = false
  local game, _, window = open(3, 9999)
  local cost = window.prizes[2].cost
  pick(game, window, 2, true)
  eq(ran, nil, "a TM needs no script (prize_menu.asm:209-216)")
  eq(game.save.coins, 9999 - cost, ".subtractCoins runs inline")
  eq(#game.stack.states, 0, "with the menu and its text box both down")
  check(done, "and the sign released")
end

do
  bagFull = true
  local game, _, window = open(3)
  pick(game, window, 1, true)
  eq(game.save.coins, 5000, ".bagFull rets before .subtractCoins")
  eq(#game.stack.states, 1, "one box left over the overworld")
  check(type(game.stack:top().onDone) == "function",
        "PrizeRoomBagIsFullText owns the release (prize_menu.asm:245-246)")
  bagFull = false
end

do
  local game, which, window = open(1)
  pick(game, window, 1, false)
  eq(#game.stack.states, 1, "OhFineThenText is all that is left")
  check(game.stack:top() ~= which, "the stay box is gone")
  eq(game.save.coins, 5000, "no coins move on NO")
end

do
  local game, which, window = open(1, 10)
  pick(game, window, 1, true)
  eq(#game.stack.states, 1, "SorryNeedMoreCoinsText is all that is left")
  check(game.stack:top() ~= which, "the stay box is gone")
  eq(ran, nil, "HasEnoughCoins fails before GivePokemon")
end

do
  local Commands = require("src.script.Commands")
  local ctx = { save = { coins = 500 } }
  Commands.take_coins(ctx, 180)
  eq(ctx.save.coins, 320, "take_coins subtracts")
  Commands.take_coins(ctx, 9999)
  eq(ctx.save.coins, 0, "and clamps at zero")
end

package.loaded["src.render.Font"] = nil
package.loaded["src.render.TextBox"] = nil
package.loaded["src.core.Sound"] = nil
package.loaded["src.core.GameVersion"] = nil
package.loaded["src.inventory.Bag"] = nil

T.finish()
