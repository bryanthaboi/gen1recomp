#!/usr/bin/env luajit
-- pokeemerald/src/party_menu.c:6296, pokefirered/src/party_menu.c:1201

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

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local MoveTeach = require("src.core.game3.scripting.natives_moveteach")
local SharedRse = require("src.core.game3.scripting.natives_shared_rse")

local function run(version, pick, deferred)
  local mon = { species = 1, level = 5, moves = { 33, 45 } }
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return { version = version, party = { mon } } end,
    isActive = function() return true end,
  }
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  Flags.setVar(nil, ctx, 0x8005, 1234)
  local pending
  local adapters = {
    log = function() end,
    chooseParty = function(_, done)
      if deferred then pending = done else done(pick) end
    end,
  }
  local handler = version == "emerald" and SharedRse.BY_NAME.ChooseMonForMoveRelearner
    or MoveTeach.BY_NAME.ChooseMonForMoveRelearner
  handler(ctx, adapters)
  if deferred then
    pending(pick)
    ctx.nativePoll()
  end
  return Flags.getVar(nil, ctx, 0x8004), Flags.getVar(nil, ctx, 0x8005)
end

for _, deferred in ipairs({ false, true }) do
  local tag = deferred and " (picker yields)" or ""
  local v4, v5 = run("emerald", nil, deferred)
  check(v4 == 0xFF,
    "Emerald CANCEL leaves VAR_0x8004 = PARTY_NOTHING_CHOSEN" .. tag .. ", got " .. tostring(v4))
  check(v5 == 1234,
    "Emerald CANCEL leaves VAR_0x8005 untouched" .. tag .. ", got " .. tostring(v5))

  v4, v5 = run("firered", nil, deferred)
  check(v4 == 7,
    "FireRed CANCEL leaves VAR_0x8004 = SLOT_CANCEL" .. tag .. ", got " .. tostring(v4))
  check(v5 == 1234,
    "FireRed CANCEL leaves VAR_0x8005 untouched" .. tag .. ", got " .. tostring(v5))
end

package.loaded["src.core.game3.runtime"] = nil

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3_relearner_cancel")
os.exit(0)
