#!/usr/bin/env luajit
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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Bag = require("src.core.game3.bag")
local Coins = Bag.Coins
local Schema = require("src.core.game3.save_schema_firered")

print("[test] 1. the accessor exists with pret's cap")
check(type(Coins) == "table", "Bag.Coins is a table")
check(type(Coins.get) == "function", "Coins.get")
check(type(Coins.add) == "function", "Coins.add")
check(type(Coins.remove) == "function", "Coins.remove")
eq(Bag.MAX_COINS, 9999, "MAX_COINS")

print("[test] 2. add and remove move the session field")
local s = { coins = 0 }
check(Coins.add(s, 50) == true, "add 50 succeeded")
eq(Coins.get(s), 50, "50 coins")
eq(s.coins, 50, "the session field really moved")
check(Coins.add(s, 25) == true, "add 25 succeeded")
eq(Coins.get(s), 75, "75 coins")
check(Coins.remove(s, 20) == true, "remove 20 succeeded")
eq(Coins.get(s), 55, "55 coins")

print("[test] 3. the 9999 clamp")
local s3 = { coins = 9990 }
check(Coins.add(s3, 100) == true, "adding over the cap still succeeds")
eq(Coins.get(s3), 9999, "clamped to MAX_COINS")
check(Coins.add(s3, 1) == false, "adding at the cap fails")
eq(Coins.get(s3), 9999, "and leaves the count alone")
local s3b = { coins = 0 }
check(Coins.add(s3b, 65535) == true, "a u16-wrapping add still succeeds")
eq(Coins.get(s3b), 9999, "and saturates at MAX_COINS")

print("[test] 4. the zero floor")
local s4 = { coins = 10 }
check(Coins.remove(s4, 11) == false, "removing more than held fails")
eq(Coins.get(s4), 10, "and takes nothing")
check(Coins.remove(s4, 10) == true, "removing exactly the balance succeeds")
eq(Coins.get(s4), 0, "0 coins")
check(Coins.remove(s4, 1) == false, "removing from 0 fails")
eq(Coins.get(s4), 0, "still 0, never negative")

print("[test] 5. garbage in the field reads as a legal count")
eq(Coins.get({ coins = -5 }), 0, "a negative stored count reads 0")
eq(Coins.get({ coins = 50000 }), 9999, "an over-cap stored count reads MAX_COINS")
eq(Coins.get({}), 0, "a missing field reads 0")
eq(Coins.get(nil), 0, "no session reads 0")
check(Coins.add(nil, 1) == false, "add with no session fails")
check(Coins.remove(nil, 1) == false, "remove with no session fails")

print("[test] 6. New Game resets the count")
local fresh = Schema.newGame({ name = "RED" })
eq(Coins.get(fresh), 0, "a new game starts on 0 coins")
Coins.add(fresh, 1234)
eq(Coins.get(fresh), 1234, "1234 coins")
local fresh2 = Schema.newGame({ name = "RED" })
eq(Coins.get(fresh2), 0, "the next New Game is back to 0")

print("[test] 7. the count survives a save round trip")
local session = Schema.newGame({ name = "RED" })
Coins.add(session, 777)
local saved = Schema.toSaveTable(session)
eq(saved.coins, 777, "toSaveTable carries the count")
local loaded = Schema.fromSaveTable(saved)
eq(Coins.get(loaded), 777, "fromSaveTable restores it")
check(Coins.remove(loaded, 777) == true, "and it can be spent after the load")
eq(Coins.get(loaded), 0, "0 coins")
local saved2 = Schema.toSaveTable(loaded)
eq(Schema.fromSaveTable(saved2).coins, 0, "0 round-trips as 0, not as nil")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
