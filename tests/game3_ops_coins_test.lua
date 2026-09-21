#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Runtime = require("src.core.game3.runtime")
local Bag = require("src.core.game3.bag")
local CoinsBox = require("src.ui.game3.coins_box")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local VAR_TEMP_1 = 0x4001
local VAR_TEMP_2 = 0x4002
local VAR_RESULT = Ctx.VAR_RESULT
local VAR_0x8006 = 0x8006

-- pokefirered/include/constants/coins.h:4
local MAX_COINS = 9999

local function run(scripts, key, store)
  store = store or Flags.newStore()
  local vm = Vm.new({ store = store, scripts = scripts, adapters = Adapters.host(nil, nil, nil) })
  vm:start(key)
  return vm, store
end

local prevSession = Runtime.session
Runtime.session = { coins = 0, money = 0 }
local session = Runtime.session

print("[test] 1. checkcoins reads the live balance into the destination var")
-- pokefirered/src/scrcmd.c:2197
session.coins = 137
local vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "checkcoins", [1] = VAR_TEMP_1 },
    { op = "checkcoins", [1] = VAR_RESULT },
    { op = "copyvar", [1] = VAR_TEMP_2, [2] = VAR_RESULT },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 137, "checkcoins VAR_TEMP_1 writes the balance")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_2), 137, "checkcoins VAR_RESULT writes the same balance")

print("[test] 2. addcoins")
-- pokefirered/src/coins.c:21
session.coins = 0
vm, store = run({
  t = {
    { op = "addcoins", [1] = 500 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}, "t")
eq(session.coins, 500, "addcoins 500 credits a literal operand")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "VAR_RESULT is FALSE after a successful addcoins")

-- pokefirered/data/scripts/obtain_item.inc:202
session.coins = 10
vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_0x8006, [2] = 40 },
    { op = "addcoins", [1] = VAR_0x8006 },
    { op = "end" },
  },
}, "t")
eq(session.coins, 50, "addcoins VAR_0x8006 VarGets its operand")

print("[test] 3. removecoins is all or nothing")
-- pokefirered/src/coins.c:41
session.coins = 1000
vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_2, [2] = 800 },
    { op = "removecoins", [1] = VAR_TEMP_2 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}, "t")
eq(session.coins, 200, "removecoins VAR_TEMP_2 debits the var's value")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "VAR_RESULT is FALSE after a successful removecoins")

session.coins = 200
vm, store = run({
  t = {
    { op = "removecoins", [1] = 800 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}, "t")
eq(session.coins, 200, "a short balance is left untouched")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 1, "VAR_RESULT is TRUE when removecoins fails")

session.coins = 0
run({ t = { { op = "removecoins", [1] = 1 }, { op = "end" } } }, "t")
eq(session.coins, 0, "the balance floors at zero")

print("[test] 4. the MAX_COINS cap")
-- pokefirered/src/coins.c:24
session.coins = MAX_COINS - 10
vm, store = run({
  t = {
    { op = "addcoins", [1] = 500 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}, "t")
eq(session.coins, MAX_COINS, "an oversized add saturates at 9999")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "saturating is still a success, VAR_RESULT FALSE")

session.coins = MAX_COINS
vm, store = run({
  t = {
    { op = "addcoins", [1] = 1 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}, "t")
eq(session.coins, MAX_COINS, "adding at the cap changes nothing")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 1, "adding at the cap sets VAR_RESULT TRUE")

session.coins = 60000
vm, store = run({ t = { { op = "checkcoins", [1] = VAR_TEMP_1 }, { op = "end" } } }, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), MAX_COINS, "a stored value above the cap reads back clamped")
session.coins = 0

print("[test] 5. CeladonCity_GameCorner_EventScript_Buy500Coins")
-- pokefirered/data/maps/CeladonCity_GameCorner/scripts.inc:45
local buy500 = {
  Buy = {
    { op = "checkcoins", [1] = VAR_TEMP_1 },
    { op = "compare_var_to_value", [1] = VAR_TEMP_1, [2] = (MAX_COINS + 1) - 500 },
    { op = "goto_if", [1] = 4, [2] = "NoRoom" },
    { op = "checkmoney", [1] = 10000 },
    { op = "compare_var_to_value", [1] = VAR_RESULT, [2] = 0 },
    { op = "goto_if", [1] = 1, [2] = "NoMoney" },
    { op = "addcoins", [1] = 500 },
    { op = "removemoney", [1] = 10000 },
    { op = "setvar", [1] = VAR_TEMP_2, [2] = 1 },
    { op = "end" },
  },
  NoRoom = { { op = "setvar", [1] = VAR_TEMP_2, [2] = 2 }, { op = "end" } },
  NoMoney = { { op = "setvar", [1] = VAR_TEMP_2, [2] = 3 }, { op = "end" } },
}
session.coins, session.money = 0, 12000
vm, store = run(buy500, "Buy")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_2), 1, "the clerk sells 500 coins")
eq(session.coins, 500, "the coin case holds 500")
eq(session.money, 2000, "10000 left the wallet")

session.coins, session.money = 9600, 12000
vm, store = run(buy500, "Buy")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_2), 2, "9600 coins takes the no-room branch")
eq(session.coins, 9600, "the no-room branch buys nothing")

session.coins, session.money = 0, 900
vm, store = run(buy500, "Buy")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_2), 3, "900 money takes the not-enough-money branch")
eq(session.coins, 0, "the not-enough-money branch buys nothing")

print("[test] 6. CeladonCity_GameCorner_PrizeRoom_EventScript_TryGivePrize")
-- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:312
local prize = {
  Try = {
    { op = "checkcoins", [1] = VAR_RESULT },
    { op = "compare_var_to_var", [1] = VAR_RESULT, [2] = VAR_TEMP_2 },
    { op = "goto_if", [1] = 0, [2] = "NotEnough" },
    { op = "removecoins", [1] = VAR_TEMP_2 },
    { op = "updatecoinsbox", [1] = 0, [2] = 5 },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 1 },
    { op = "end" },
  },
  NotEnough = { { op = "setvar", [1] = VAR_TEMP_1, [2] = 9 }, { op = "end" } },
}
session.coins = 1000
store = Flags.newStore()
store.vars[VAR_TEMP_2] = 800
vm, store = run(prize, "Try", store)
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 1, "1000 coins buys the 800 coin SMOKE BALL")
eq(session.coins, 200, "the prize clerk took exactly 800")

session.coins = 700
store = Flags.newStore()
store.vars[VAR_TEMP_2] = 800
vm, store = run(prize, "Try", store)
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 9, "700 coins takes the not-enough branch")
eq(session.coins, 700, "nothing was debited on the not-enough branch")

print("[test] 7. the three box ops drive the coins window")
-- pokefirered/src/scrcmd.c:1859
CoinsBox.hide()
session.coins = 1000
vm, store = run({
  t = {
    { op = "showcoinsbox", [1] = 0, [2] = 5 },
    { op = "end" },
  },
}, "t")
check(CoinsBox.isVisible() == true, "showcoinsbox opens the window")
eq(CoinsBox.amount(), 1000, "showcoinsbox seeds the window with the live balance")
eq(CoinsBox.x, 0, "showcoinsbox passes the script's x")
eq(CoinsBox.y, 5, "showcoinsbox passes the script's y")

run({
  t = {
    { op = "removecoins", [1] = 800 },
    { op = "updatecoinsbox", [1] = 0, [2] = 5 },
    { op = "end" },
  },
}, "t")
eq(CoinsBox.amount(), 200, "updatecoinsbox redraws the decremented balance")

run({ t = { { op = "hidecoinsbox", [1] = 0, [2] = 0 }, { op = "end" } } }, "t")
check(CoinsBox.isVisible() == false, "hidecoinsbox closes the window")

print("[test] 8. the box ops are safe with no coins window module")
local savedPath, savedCpath = package.path, package.cpath
local savedBox = package.loaded["src.ui.game3.coins_box"]
package.loaded["src.ui.game3.coins_box"] = nil
package.path = "./no_such_dir/?.lua"
package.cpath = ""
session.coins = 300
local okRun, err = pcall(run, {
  t = {
    { op = "showcoinsbox", [1] = 0, [2] = 0 },
    { op = "removecoins", [1] = 100 },
    { op = "updatecoinsbox", [1] = 0, [2] = 5 },
    { op = "hidecoinsbox", [1] = 0, [2] = 0 },
    { op = "end" },
  },
}, "t")
package.path, package.cpath = savedPath, savedCpath
package.loaded["src.ui.game3.coins_box"] = savedBox
check(okRun, "a script with all three box ops runs with the window module missing: " .. tostring(err))
eq(session.coins, 200, "the coin value still moved while the window was missing")

print("[test] 9. the coin ops survive a missing session")
Runtime.session = nil
okRun, err = pcall(run, {
  t = {
    { op = "checkcoins", [1] = VAR_TEMP_1 },
    { op = "addcoins", [1] = 10 },
    { op = "removecoins", [1] = 10 },
    { op = "end" },
  },
}, "t")
check(okRun, "no session is not a crash: " .. tostring(err))
Runtime.session = session

print("[test] 10. quest log playback suppresses the two script windows")
-- pokefirered/src/scrcmd.c:1864
local MoneyBox = require("src.ui.game3.money_box")
local prevGame = Runtime._game
CoinsBox.hide()
MoneyBox.hide()
session.coins, session.money = 1000, 5000
Runtime._game = { phase = "quest_log" }
run({
  t = {
    { op = "showcoinsbox", [1] = 0, [2] = 5 },
    { op = "showmoneybox", [1] = 0, [2] = 0, [3] = 0 },
    { op = "end" },
  },
}, "t")
check(CoinsBox.isVisible() == false, "showcoinsbox draws nothing during quest log playback")
check(MoneyBox.isVisible() == false, "showmoneybox draws nothing during quest log playback")
Runtime._game = { phase = "game3" }
run({
  t = {
    { op = "showcoinsbox", [1] = 0, [2] = 5 },
    { op = "showmoneybox", [1] = 0, [2] = 0, [3] = 0 },
    { op = "end" },
  },
}, "t")
check(CoinsBox.isVisible() == true, "showcoinsbox draws normally in the field")
check(MoneyBox.isVisible() == true, "showmoneybox draws normally in the field")
CoinsBox.hide()
MoneyBox.hide()
Runtime._game = prevGame
session.coins = 0

print("[test] 11. Bag.Coins is the one owner of the value")
eq(Bag.Coins.MAX_COINS, MAX_COINS, "Bag.Coins.MAX_COINS is 9999")
session.coins = 40
run({ t = { { op = "addcoins", [1] = 5 }, { op = "end" } } }, "t")
eq(Bag.Coins.get(session), 45, "the opcode moved the same field Bag.Coins reads")

Runtime.session = prevSession

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
