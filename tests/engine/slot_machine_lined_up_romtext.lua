-- SlotMachine:resolveWin's "%s lined up!\nScored %d coins!" message used
-- to interpolate the symbol id AND the payout into one bare Lua literal.
-- The real _LinedUpText label has no slot for the symbol at all (the
-- original ROM drew it separately) -- only for the coin count. This test
-- fakes _LinedUpText and checks the symbol is concatenated in front of the
-- translated suffix, with the payout correctly substituted into it.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

local SlotMachine = require("src.ui.SlotMachine")

local function mkSelf()
  local game = { data = Data, save = { coins = 0 } }
  return setmetatable({ game = game, allowMatchesCounter = 0 }, SlotMachine)
end

-- translated: the fake suffix reaches self.message, with the symbol
-- concatenated in front and the payout substituted into the fake text
do
  local self = mkSelf()
  Data.text._LinedUpText = " FAKE-SUFFIX {RAM:wStringBuffer}!"
  self:resolveWin({ symbol = "CHERRY", payout = 8 })
  T.eq(self.message, "CHERRY FAKE-SUFFIX 8!",
    "a translated _LinedUpText reaches the lined-up message")
  Data.text._LinedUpText = nil
end

-- vanilla: with no catalog entry, the English literal still substitutes,
-- with its own leading space (the original had no slot for the symbol)
do
  local self = mkSelf()
  self:resolveWin({ symbol = "CHERRY", payout = 8 })
  T.eq(self.message, "CHERRY lined up!\nScored 8 coins!",
    "no catalog entry still falls back to the English literal")
end

T.finish("slot_machine_lined_up_romtext")
