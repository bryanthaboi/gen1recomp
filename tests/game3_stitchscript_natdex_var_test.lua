#!/usr/bin/env luajit
-- pokefirered/src/event_data.c:107 IsNationalPokedexEnabled

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

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

require("src.core.GameVersion").set("firered")

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Ops = require("src.core.game3.scripting.ops_a")
local Dex = require("src.core.game3.dex")

local store = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = store }

local session = { name = "RED", party = {}, dex = Dex.new(), vars = {}, flags = {} }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local a = { log = function() end }
local function newCtx()
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  return ctx
end

local function specialvar(ctx, dest, id)
  Ops.dispatch({ ctx = ctx, store = store, adapters = a, setPc = function() end },
    { op = "specialvar", [1] = dest, [2] = id })
  return Flags.getVar(store, ctx, dest)
end

local VAR_RESULT = 0x800D
local VAR_0x8008 = 0x8008
local FLAG_SYS_NATIONAL_DEX = 0x840

print("[test] 1. a locked national dex writes 0 into the destination var")
local ctx = newCtx()
Flags.setVar(store, ctx, VAR_RESULT, 9)
eq(specialvar(ctx, VAR_RESULT, Std.SPECIAL.IsNationalPokedexEnabled), 0,
  "specialvar VAR_RESULT, IsNationalPokedexEnabled is FALSE on a fresh save")

print("[test] 2. an unlocked national dex writes 1")
Flags.setFlag(store, ctx, FLAG_SYS_NATIONAL_DEX, true)
eq(specialvar(ctx, VAR_RESULT, Std.SPECIAL.IsNationalPokedexEnabled), 1,
  "FLAG_SYS_NATIONAL_DEX makes it TRUE")

print("[test] 3. it writes whichever var the script names")
Flags.setVar(store, ctx, VAR_0x8008, 7)
eq(specialvar(ctx, VAR_0x8008, Std.SPECIAL.IsNationalPokedexEnabled), 1,
  "specialvar VAR_0x8008 takes the same answer")

print("[test] 4. the Dunsparce Tunnel ON_TRANSITION branch fires")
-- pokefirered/data/maps/ThreeIsland_DunsparceTunnel/scripts.inc:5
local function onTransition()
  local c = newCtx()
  c.pc = { listKey = "ThreeIsland_DunsparceTunnel_OnTransition", index = 1 }
  c.stack = {}
  local jumped = nil
  local vm = { ctx = c, store = store, adapters = a,
    setPc = function(_, key) jumped = key end }
  Ops.dispatch(vm, { op = "specialvar", [1] = VAR_RESULT,
    [2] = Std.SPECIAL.IsNationalPokedexEnabled })
  Ops.dispatch(vm, { op = "copyvar", [1] = VAR_0x8008, [2] = VAR_RESULT })
  Ops.dispatch(vm, { op = "compare_var_to_value", [1] = VAR_0x8008, [2] = 1 })
  Ops.dispatch(vm, { op = "call_if", cond = 1, target = "SetLayoutDugOut" })
  Ops.dispatch(vm, { op = "compare_var_to_value", [1] = VAR_0x8008, [2] = 0 })
  Ops.dispatch(vm, { op = "call_if", cond = 1, target = "MoveProspectorToWall" })
  return jumped
end

eq(onTransition(), "SetLayoutDugOut",
  "with the national dex the tunnel calls SetLayoutDugOut")
Flags.setFlag(store, ctx, FLAG_SYS_NATIONAL_DEX, false)
Flags.setVar(store, ctx, 0x404E, 0)
eq(onTransition(), "MoveProspectorToWall",
  "without it the prospector is moved to the wall instead")

done()
