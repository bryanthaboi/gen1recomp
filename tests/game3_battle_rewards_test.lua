#!/usr/bin/env luajit
-- Trainer prize money, badge white-out loss, checkitemspace for gym TMs.

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

print("[test] 1. Prize formula (pret Cmd_getmoneyreward)")
local Prize = require("src.core.game3.battle.prize")
local Trainers = require("src.core.game3.scripting.trainers")
Trainers._pack = nil -- force reload after extract
local brock = Trainers.info(414)
check(brock ~= nil, "Brock trainer pack")
check(brock and brock.class == 84, "Brock class LEADER")
check(brock and brock.lastLevel == 14, "Brock lastLevel Onix 14")
check(Prize.calc(414) == 1400, "Brock prize ¥1400 (4*14*25)")
check(Prize.calc(326) == 80, "Oaks Lab rival ¥80 (4*5*4)")
check(Prize.classValue(84) == 25, "LEADER class value")
check(Prize.classValue(57) == 4, "YOUNGSTER class value")
check(Prize.classValue(9999) == 5, "unknown class defaults to 5")

print("[test] 2. Apply money + message")
local session = { money = 3000, name = "ASH" }
local gained = Prize.awardTrainerWin(session, 414)
check(gained == 1400, "award gained 1400")
check(session.money == 4400, "session money 4400")
check(Prize.moneyMessage("ASH", 1400) == "ASH got ¥1400\nfor winning!", "money message")
session.money = Prize.MAX_MONEY - 10
local g2 = Prize.apply(session, 100)
check(g2 == 10 and session.money == Prize.MAX_MONEY, "cap at MAX_MONEY")

print("[test] 3. White-out loss uses badge flags")
local Bridge = require("src.core.game3.battle_bridge")
check(Bridge.calcMoneyLossFrlg({ party = { { level = 20 } }, flags = {} }, nil) == 160,
  "0 badges: 20*4*2=160")
check(Bridge.calcMoneyLossFrlg({
  party = { { level = 20 } },
  flags = { [0x820] = true },
}, nil) == 320, "1 badge: 20*4*4=320")
check(Bridge.calcMoneyLossFrlg({
  party = { { level = 10 } },
  flags = {
    [0x820] = true, [0x821] = true, [0x822] = true, [0x823] = true,
    [0x824] = true, [0x825] = true, [0x826] = true, [0x827] = true,
  },
}, nil) == 1200, "8 badges: 10*4*30=1200")

print("[test] 4. checkitemspace + additem path")
local Bag = require("src.core.game3.bag")
local bag = Bag.new()
check(Bag.canAdd(bag, "FRLG_327", 1) == true, "empty bag has space for TM39")
check(select(1, Bag.add(bag, "FRLG_327", 1)) == true, "add TM39")
check(Bag.get(bag, "FRLG_327") == 1, "TM39 qty 1")

local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local store = Flags.newStore()
local sess = { money = 0, bag = Bag.new(), name = "ASH" }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return sess end,
  isActive = function() return true end,
}
local vm = Vm.new({
  store = store,
  scripts = {
    give_tm = {
      { op = "checkitemspace", [1] = 327, [2] = 1 },
      { op = "compare_var_to_value", var = Ctx.VAR_RESULT, value = 0 },
      { op = "goto_if", cond = 1, target = "no_room" },
      { op = "additem", [1] = 327, [2] = 1 },
      { op = "setflag", flag = 596 },
      { op = "end" },
    },
    no_room = {
      { op = "end" },
    },
  },
  adapters = {
    log = function() end,
    checkItemSpace = function(item, qty)
      local key = "FRLG_" .. tostring(item)
      return Bag.canAdd(sess.bag, key, qty)
    end,
    modifyItem = function(op, item, qty)
      local key = "FRLG_" .. tostring(item)
      if op == "removeitem" then return Bag.remove(sess.bag, key, qty) end
      return select(1, Bag.add(sess.bag, key, qty))
    end,
  },
})
check(vm:start("give_tm") == true, "start give_tm")
for _ = 1, 20 do if not vm:isRunning() then break end vm:tick() end
check(Bag.get(sess.bag, "FRLG_327") == 1, "TM39 granted via script")
check(Flags.getFlag(store, nil, 596) == true, "GOT_TM39 flag set")

print("[test] 5. addmoney script op")
vm = Vm.new({
  store = store,
  scripts = {
    pay = {
      { op = "addmoney", [1] = 500 },
      { op = "end" },
    },
  },
  adapters = { log = function() end },
})
sess.money = 100
vm:start("pay")
for _ = 1, 10 do if not vm:isRunning() then break end vm:tick() end
check(sess.money == 600, "addmoney +500")

if failed > 0 then
  print(string.format("\n%d FAILURE(S)", failed))
  os.exit(1)
end
print("\nAll battle-reward checks passed.")
