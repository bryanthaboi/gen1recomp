package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

local SaveData = require("src.core.SaveData")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local textBoxStub = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
  soundOpts = function() return {} end,
}

local MAP_ID = "FIX_CORNER"
Data.field.hiddenCoins = Data.field.hiddenCoins or {}
Data.field.slotMachines = Data.field.slotMachines or {}
-- data/events/hidden_events.asm:262
Data.field.slotMachines[MAP_ID] = {
  { x = 12, y = 14, state = "ok" },
  { x = 12, y = 15, state = "ok" },
}
-- data/events/hidden_events.asm:298
Data.field.hiddenCoins[MAP_ID] = {
  { x = 10, y = 16, coins = 10 },
  { x = 12, y = 15, coins = 10 },
}

local function mkGame(opts)
  local save = SaveData.newGame()
  save.player.name = "FAKEPLAYER"
  if opts.coinCase then save.inventory.COIN_CASE = 1 end
  save.coins = opts.coins or 0
  if opts.taken then save.hiddenTaken = { [MAP_ID .. "_12_15"] = true } end
  pushed = {}
  local game = {
    data = Data, save = save,
    stack = { push = function(_, item) pushed[#pushed + 1] = item end },
  }
  setUpvalue(OW.tryHiddenObject, "Game", game)
  return game
end

T.check(setUpvalue(OW.tryHiddenObject, "TextBox", textBoxStub), "TextBox upvalue on tryHiddenObject")

local fakeSelf = setmetatable({
  map = { id = MAP_ID }, player = { facing = "up" },
}, { __index = OW })

local function text(i) return (pushed[i] and pushed[i].text) or "" end

do
  local game = mkGame({ coinCase = true, coins = 0 })
  local handled = fakeSelf:tryHiddenObject(12, 15)
  T.check(handled == true, "shared seat handles A with a COIN CASE and no coins")
  T.eq(game.save.coins, 0, "shared seat pays no hidden coins")
  T.check(not (game.save.hiddenTaken or {})[MAP_ID .. "_12_15"], "shared seat sets no hiddenTaken key")
  T.check(text(1):find("any coins", 1, true) ~= nil, "shared seat prints the no-coins slot text")
end

do
  local game = mkGame({ coinCase = true, coins = 50 })
  fakeSelf:tryHiddenObject(12, 15)
  T.eq(game.save.coins, 50, "shared seat with coins leaves the balance alone")
  T.check(pushed[1] and pushed[1].opts and type(pushed[1].opts.choice) == "function",
    "shared seat opens the slot machine prompt")
end

do
  mkGame({ coins = 0 })
  local handled = fakeSelf:tryHiddenObject(12, 15)
  T.check(handled == true, "shared seat without a COIN CASE still answers")
  T.check(text(1):find("COIN CASE", 1, true) ~= nil, "shared seat asks for a COIN CASE")
end

do
  mkGame({ coinCase = true, coins = 50, taken = true })
  local handled = fakeSelf:tryHiddenObject(12, 15)
  T.check(handled == true, "shared seat still works after the coin flag was set")
  T.check(pushed[1] and pushed[1].opts and type(pushed[1].opts.choice) == "function",
    "shared seat with a stale coin flag opens the slot prompt")
end

do
  local game = mkGame({ coinCase = true, coins = 0 })
  local handled = fakeSelf:tryHiddenObject(10, 16)
  T.check(handled == true, "coin-only cell is found")
  T.check(game.save.coins > 0, "coin-only cell pays coins")
  T.check(game.save.hiddenTaken[MAP_ID .. "_10_16"] == true, "coin-only cell sets its flag")
end

do
  mkGame({ coinCase = true, coins = 50 })
  fakeSelf:tryHiddenObject(12, 14)
  T.check(pushed[1] and pushed[1].opts and type(pushed[1].opts.choice) == "function",
    "slot-only seat opens the slot prompt")
end

T.finish("overworld_slot_seat_over_hidden_coin")
