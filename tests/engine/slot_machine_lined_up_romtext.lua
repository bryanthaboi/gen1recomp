package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

local SlotMachine = require("src.ui.SlotMachine")

local function mkSelf()
  local game = { data = Data, save = { coins = 0 } }
  return setmetatable({ game = game, allowMatchesCounter = 0 }, SlotMachine)
end

-- engine/slots/slot_machine.asm:617-631
do
  local self = mkSelf()
  Data.text._LinedUpText = " FAKE-SUFFIX {RAM:wStringBuffer}!"
  self:resolveWin({ symbol = "CHERRY", payout = 8 })
  T.eq(self.message, " FAKE-SUFFIX 8!",
    "a translated _LinedUpText reaches the lined-up message")
  T.eq(self.winSymbol, "CHERRY", "the winning symbol is kept for its picture")
  Data.text._LinedUpText = " lined up!\nScored {RAM:wStringBuffer} coins!{DONE}"
end

do
  local self = mkSelf()
  self:resolveWin({ symbol = "CHERRY", payout = 8 })
  T.eq(self.message, " lined up!\nScored 8 coins!",
    "the cached _LinedUpText prints with the payout")
end

do
  local self = mkSelf()
  Data.text._LinedUpText = nil
  local ok, err = pcall(self.resolveWin, self, { symbol = "CHERRY", payout = 8 })
  T.check(not ok and tostring(err):find("_LinedUpText", 1, true) ~= nil,
    "a cache without _LinedUpText is an error, not an English literal")
end

T.finish("slot_machine_lined_up_romtext")
