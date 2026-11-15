-- The player's coin case: engine/events/money.asm GiveCoins / TakeCoins /
-- CheckCoins, transcribed onto save.player.coins.
--
-- MAX_COINS is 9999 (constants/misc_constants.asm) and Save.MAX_COINS is the
-- same number on the save side (src/core/gen2/Save.lua), which is also where
-- Save.normalize re-clamps a loaded file.
local Save = require("src.core.gen2.Save")

local CoinCase = {}

CoinCase.MAX_COINS = Save.MAX_COINS

function CoinCase.coins(save)
  local player = save and save.player
  return (player and player.coins) or 0
end

-- GiveCoins: add, and if the total passes MAX_COINS write MAX_COINS back and
-- return carry.  Returns the new balance and whether the case capped.
function CoinCase.giveCoins(save, amount)
  local player = save and save.player
  if not player then return 0, false end
  local total = (player.coins or 0) + math.floor(amount or 0)
  if total >= CoinCase.MAX_COINS then
    player.coins = CoinCase.MAX_COINS
    return player.coins, true
  end
  player.coins = total
  return total, false
end

-- TakeCoins: subtract, and on borrow leave the case at zero rather than
-- wrapping (`; leave with 0 coins`).
function CoinCase.takeCoins(save, amount)
  local player = save and save.player
  if not player then return 0, false end
  local total = (player.coins or 0) - math.floor(amount or 0)
  if total < 0 then
    player.coins = 0
    return 0, true
  end
  player.coins = total
  return total, false
end

-- CheckCoins -> CompareMoneyAction, which writes wScriptVar.
-- constants/script_constants.asm: HAVE_MORE 0, HAVE_AMOUNT 1, HAVE_LESS 2.
CoinCase.HAVE_MORE = 0
CoinCase.HAVE_AMOUNT = 1
CoinCase.HAVE_LESS = 2

function CoinCase.checkCoins(save, amount)
  local have = CoinCase.coins(save)
  amount = math.floor(amount or 0)
  if have < amount then return CoinCase.HAVE_LESS end
  if have == amount then return CoinCase.HAVE_AMOUNT end
  return CoinCase.HAVE_MORE
end

function CoinCase.canAfford(save, cost)
  return CoinCase.checkCoins(save, cost) ~= CoinCase.HAVE_LESS
end

return CoinCase
