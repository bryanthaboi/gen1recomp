#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Player = require("src.core.game3.player")
local Runtime = require("src.core.game3.runtime")
local Storage = require("src.core.game3.storage")

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
local VAR_0x8004 = 0x8004

local function run(scripts, key, store)
  store = store or Flags.newStore()
  local vm = Vm.new({ store = store, scripts = scripts, adapters = Adapters.host(nil, nil, nil) })
  vm:start(key)
  return vm, store
end

print("[test] 1. addvar / subvar arithmetic")
local vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "addvar", [1] = VAR_TEMP_1, [2] = 1 },
    { op = "addvar", [1] = VAR_TEMP_1, [2] = 1 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 2, "addvar twice by 1 reaches 2")

vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 10 },
    { op = "subvar", [1] = VAR_TEMP_1, [2] = 3 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 7, "subvar by a literal")

print("[test] 2. subvar VarGets its second operand, addvar does not")
-- pokefirered/src/scrcmd.c:448
vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_2, [2] = 3 },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 10 },
    { op = "subvar", [1] = VAR_TEMP_1, [2] = VAR_TEMP_2 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 7, "subvar VAR_TEMP_1, VAR_TEMP_2 subtracts VAR_TEMP_2's value")

print("[test] E9: incrementgamestat / checkpartymove implement pret")
local prevSess = Runtime.session
Runtime.session = { gameStats = {}, party = {} }
-- pokefirered/src/scrcmd.c:576-579, overworld.c:366-375
vm, store = run({
  t = {
    { op = "incrementgamestat", [1] = 13 },
    { op = "incrementgamestat", [1] = 99 },
    { op = "end" },
  },
}, "t")
eq(Runtime.session.gameStats[13], 1, "incrementgamestat bumps the stat (scrcmd.c:576)")
eq(Runtime.session.gameStats[99], nil, "an out-of-range statId is ignored (overworld.c:369)")
Runtime.session.gameStats[13] = 0xFFFFFF
vm, store = run({
  t = {
    { op = "incrementgamestat", [1] = 13 },
    { op = "end" },
  },
}, "t")
eq(Runtime.session.gameStats[13], 0xFFFFFF, "the stat saturates at 0xFFFFFF (overworld.c:371-374)")

-- pokefirered/src/scrcmd.c:1777-1795
Runtime.session.party = {
  { species = 1, moves = { 0, 0, 0, 0 } },
  { species = 4, moves = { { id = 15 } }, isEgg = true },
  { species = 7, moves = { { id = 15 } } },
}
vm, store = run({
  t = {
    { op = "checkpartymove", [1] = 15 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "copyvar", [1] = VAR_TEMP_2, [2] = VAR_0x8004 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 2, "checkpartymove skips the egg, Result is the 0-based slot")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_2), 7, "VAR_0x8004 carries that mon's species")
vm, store = run({
  t = {
    { op = "checkpartymove", [1] = 99 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 6, "no match leaves Result = PARTY_SIZE (scrcmd.c:1781)")
Runtime.session = prevSess

vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_2, [2] = 5 },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "addvar", [1] = VAR_TEMP_1, [2] = VAR_TEMP_2 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0x4002, "addvar adds the raw halfword, not VarGet of it")

print("[test] 3. u16 wrap")
vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "subvar", [1] = VAR_TEMP_1, [2] = 1 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 65535, "0 - 1 underflows to 65535")

vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 65535 },
    { op = "addvar", [1] = VAR_TEMP_1, [2] = 2 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 1, "65535 + 2 wraps to 1")

print("[test] 4. Rocket Hideout B4F barrier gate")
-- pokefirered/data/maps/RocketHideout_B4F/scripts.inc:7
local hideout = {
  OnLoad = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "call", [1] = "CountGruntDefeated" },
    { op = "call", [1] = "CountGruntDefeated" },
    { op = "compare_var_to_value", [1] = VAR_TEMP_1, [2] = 2 },
    { op = "call_if", [1] = 5, [2] = "SetBarrier" },
    { op = "end" },
  },
  Defeated = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "call", [1] = "CountGruntDefeated" },
    { op = "call", [1] = "CountGruntDefeated" },
    { op = "compare_var_to_value", [1] = VAR_TEMP_1, [2] = 2 },
    { op = "call_if", [1] = 1, [2] = "RemoveBarrier" },
    { op = "end" },
  },
  CountGruntDefeated = {
    { op = "addvar", [1] = VAR_TEMP_1, [2] = 1 },
    { op = "return" },
  },
  SetBarrier = { { op = "setflag", [1] = 0x300 }, { op = "return" } },
  RemoveBarrier = { { op = "clearflag", [1] = 0x300 }, { op = "return" } },
}
store = Flags.newStore()
vm = Vm.new({ store = store, scripts = hideout, adapters = Adapters.host(nil, nil, nil) })
vm:start("OnLoad")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 2, "OnLoad counts both grunts")
check(Flags.getFlag(store, vm.ctx, 0x300) == false, "barrier not re-set once both grunts are down")
vm:start("Defeated")
check(Flags.getFlag(store, vm.ctx, 0x300) == false, "RemoveBarrier branch taken at 2")

local single = {}
for k, v in pairs(hideout) do single[k] = v end
single.OnLoad = {
  { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
  { op = "call", [1] = "CountGruntDefeated" },
  { op = "compare_var_to_value", [1] = VAR_TEMP_1, [2] = 2 },
  { op = "call_if", [1] = 5, [2] = "SetBarrier" },
  { op = "end" },
}
store = Flags.newStore()
vm = Vm.new({ store = store, scripts = single, adapters = Adapters.host(nil, nil, nil) })
vm:start("OnLoad")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 1, "one grunt counts 1")
check(Flags.getFlag(store, vm.ctx, 0x300) == true, "barrier stays set with one grunt down")

print("[test] 5. getpartysize counts eggs")
-- pokefirered/src/pokemon.c:3742
local prevSession = Runtime.session
Runtime.session = {
  gender = 0,
  party = {
    { species = 1, level = 5, hp = 20 },
    { species = 4, level = 5, hp = 0 },
    { species = 172, level = 5, hp = 11, isEgg = true },
  },
}
local PARTY_SIZE = {
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 99 },
    { op = "getpartysize" },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}
vm, store = run(PARTY_SIZE, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 3, "party of 2 mons + 1 egg reports 3")

Runtime.session.party = {}
vm, store = run(PARTY_SIZE, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "empty party reports 0")

print("[test] 6. gift-mon party slot (pokefirered/data/scripts/pc_transfer.inc:1-5)")
Runtime.session.party = {
  { species = 1, level = 5, hp = 20 },
  { species = 4, level = 5, hp = 20 },
  { species = 7, level = 5, hp = 20 },
}
vm, store = run({
  t = {
    { op = "getpartysize" },
    { op = "subvar", [1] = VAR_RESULT, [2] = 1 },
    { op = "copyvar", [1] = VAR_0x8004, [2] = VAR_RESULT },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_0x8004 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 2, "last slot of a 3-mon party is index 2")

print("[test] 7. checkplayergender")
-- pokefirered/include/constants/global.h:85
local GENDER = {
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 99 },
    { op = "checkplayergender" },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_RESULT },
    { op = "end" },
  },
}
Runtime.session.gender = 0
vm, store = run(GENDER, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "male player reports MALE")

Runtime.session.gender = 1
vm, store = run(GENDER, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 1, "female player reports FEMALE")

-- pokefirered/data/maps/Route25_SeaCottage/scripts.inc:28
local bill = {
  Bill = {
    { op = "checkplayergender" },
    { op = "compare_var_to_value", [1] = VAR_RESULT, [2] = 0 },
    { op = "goto_if", [1] = 1, [2] = "Male" },
    { op = "compare_var_to_value", [1] = VAR_RESULT, [2] = 1 },
    { op = "goto_if", [1] = 1, [2] = "Female" },
    { op = "end" },
  },
  Male = { { op = "setvar", [1] = VAR_TEMP_1, [2] = 11 }, { op = "end" } },
  Female = { { op = "setvar", [1] = VAR_TEMP_1, [2] = 22 }, { op = "end" } },
}
for gender, want in pairs({ [0] = 11, [1] = 22 }) do
  Runtime.session.gender = gender
  store = Flags.newStore()
  store.vars[VAR_TEMP_1] = 0
  vm = Vm.new({ store = store, scripts = bill, adapters = Adapters.host(nil, nil, nil) })
  vm.ctx.specialVars[VAR_RESULT] = 4
  vm:start("Bill")
  eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), want, "Bill reaches a branch with gender " .. gender)
end

print("[test] 8. getplayerxy reads map-local cell coords")
-- pokefirered/src/scrcmd.c:867
Player.reset(19, 4, "down")
vm, store = run({
  t = {
    { op = "getplayerxy", [1] = VAR_0x8004, [2] = 0x8005 },
    { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_0x8004 },
    { op = "copyvar", [1] = VAR_TEMP_2, [2] = 0x8005 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 19, "getplayerxy X into VAR_0x8004")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_2), 4, "getplayerxy Y into VAR_0x8005")

Player.reset(7, 12, "up")
vm, store = run({
  t = { { op = "getplayerxy", [1] = VAR_TEMP_1, [2] = VAR_TEMP_2 }, { op = "end" } },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 7, "getplayerxy into a temp var, X")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_2), 12, "getplayerxy into a temp var, Y")

print("[test] 9. bufferboxname converts the cart's 0-based box id")
-- pokefirered/src/scrcmd.c:1725
Storage.ensure(Runtime.session)
Runtime.session.storage.boxes[3].name = "GHOSTS"
vm, store = run({
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "bufferboxname", [1] = 0, [2] = VAR_TEMP_1 },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 2 },
    { op = "bufferboxname", [1] = 1, [2] = VAR_TEMP_1 },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 13 },
    { op = "bufferboxname", [1] = 2, [2] = VAR_TEMP_1 },
    { op = "end" },
  },
}, "t")
eq(vm.ctx.stringVars[1], "BOX 1", "box id 0 buffers BOX 1 into STR_VAR_1")
eq(vm.ctx.stringVars[2], "GHOSTS", "box id 2 buffers the renamed third box into STR_VAR_2")
eq(vm.ctx.stringVars[3], "BOX 14", "box id 13 buffers BOX 14 into STR_VAR_3")

Runtime.session = prevSession

print("[test] 10. warp x/y VarGet returns non-var ids literally")
local function warpArgs(x, y, seed)
  local st = Flags.newStore()
  for id, v in pairs(seed or {}) do Flags.setVar(st, nil, id, v) end
  local got
  local adapters = Adapters.host(nil, nil, nil)
  adapters.warp = function(g, n, w, wx, wy, cb) got = { g, n, w, wx, wy }; if cb then cb() end end
  local v = Vm.new({ store = st, scripts = {
    t = { { op = "warp", [1] = 3, [2] = 5, [3] = 1, [4] = x, [5] = y }, { op = "end" } },
  }, adapters = adapters })
  v:start("t")
  return got or {}
end
local w = warpArgs(0xFFFF, 0xFFFF)
eq(w[4], 0xFFFF, "id-only warp keeps x = 0xFFFF")
eq(w[5], 0xFFFF, "id-only warp keeps y = 0xFFFF")
w = warpArgs(7, 9)
eq(w[4], 7, "a literal x below VARS_START passes through")
eq(w[5], 9, "a literal y below VARS_START passes through")
w = warpArgs(VAR_TEMP_1, 0x40FF, { [VAR_TEMP_1] = 12, [0x40FF] = 4 })
eq(w[4], 12, "x in the save var range is read")
eq(w[5], 4, "VARS_END is still a var")
w = warpArgs(0x4100, 0x8015)
eq(w[4], 0x4100, "an id past VARS_END is a literal")
eq(w[5], 0x8015, "an id past SPECIAL_VARS_END is a literal")

print("[test] 11. buffernumberstring VarGets a literal requirement")
-- pokefirered/data/maps/Route10_PokemonCenter_1F/scripts.inc:59
-- pokefirered/src/event_data.c:235-241
store = Flags.newStore()
eq(Flags.getVar(store, nil, 20), 20, "getVar(20) returns the literal 20")
Flags.setVar(store, nil, 0x4050, 3)
eq(Flags.getVar(store, nil, 0x4050), 3, "a var at 0x4050 still reads the store")
vm, store = run({
  t = {
    { op = "setvar", [1] = 0x8006, [2] = 7 },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 42 },
    { op = "buffernumberstring", [1] = 0, [2] = 20 },
    { op = "buffernumberstring", [1] = 1, [2] = VAR_TEMP_1 },
    { op = "buffernumberstring", [1] = 2, [2] = 0x8006 },
    { op = "end" },
  },
}, "t")
eq(vm.ctx.stringVars[1], "20", "buffernumberstring STR_VAR_1, 20 buffers \"20\"")
eq(vm.ctx.stringVars[2], "42", "buffernumberstring of a save var buffers its value")
eq(vm.ctx.stringVars[3], "7", "buffernumberstring of VAR_0x8006 buffers the caught count")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
