#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local Game3Cache = require("tests.game3_cache")
if not Game3Cache.bundle() then print("[skip] bufferstdstring: " .. tostring(Game3Cache.reason)) return end

local Flags = require("src.core.game3.scripting.flags")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")

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

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local host = Adapters.host(nil, nil, nil)
local stub = Adapters.stub({})

local function runVm(src, pre)
  local rows = {}
  for _, r in ipairs(pre or {}) do rows[#rows + 1] = r end
  rows[#rows + 1] = { op = "bufferstdstring", dest = 0, src = src }
  rows[#rows + 1] = { op = "end" }
  local vm = Vm.new({
    store = Flags.newStore(),
    scripts = { t = rows },
    adapters = Adapters.host(nil, nil, nil),
  })
  vm:start("t")
  return vm.ctx.stringVars and vm.ctx.stringVars[1]
end

-- pokefirered/include/constants/menu.h:99
eq(host.bufferName("bufferstdstring", 15), "BOULDERBADGE", "host 15 is BOULDERBADGE")
eq(host.bufferName("bufferstdstring", 22), "EARTHBADGE", "host 22 is EARTHBADGE")
eq(stub.bufferName("bufferstdstring", 15), "BOULDERBADGE", "stub 15 is BOULDERBADGE")
eq(stub.bufferName("bufferstdstring", 22), "EARTHBADGE", "stub 22 is EARTHBADGE")

eq(runVm(15), "BOULDERBADGE", "VM STR_VAR_1 for STDSTRING_BOULDER_BADGE")
eq(runVm(22), "EARTHBADGE", "VM STR_VAR_1 for STDSTRING_EARTH_BADGE")
eq(runVm(23), "COINS", "VM STR_VAR_1 for STDSTRING_COINS")
eq(runVm(0x8004, { { op = "setvar", [1] = 0x8004, [2] = 17 } }), "THUNDERBADGE",
  "VM STR_VAR_1 via VAR_0x8004 = STDSTRING_THUNDER_BADGE")

local menuH = slurp("../pokefirered/include/constants/menu.h")
local menuC = slurp("../pokefirered/src/script_menu.c")
local stringsC = slurp("../pokefirered/src/strings.c")
if not (menuH and menuC and stringsC) then
  print("[skip] ../pokefirered not present; pret table parity skipped")
else
  local texts = {}
  for sym, body in stringsC:gmatch("const u8 (gText_[%w_]+)%[%] = _%(\"(.-)\"%);") do
    texts[sym] = body
  end
  local ptrs = {}
  local block = menuC:match("gStdStringPtrs%[%] = {(.-)};")
  check(block ~= nil, "found gStdStringPtrs in script_menu.c")
  for name, sym in (block or ""):gmatch("%[(STDSTRING_[%w_]+)%]%s*=%s*([%w_]+)") do
    ptrs[name] = sym
  end
  local n = 0
  for name, id in menuH:gmatch("#define (STDSTRING_[%w_]+)%s+(%d+)") do
    n = n + 1
    id = tonumber(id)
    local want = texts[ptrs[name] or ""]
    check(want ~= nil, name .. " has a pret string")
    for label, a in pairs({ host = host, stub = stub }) do
      local got = a.bufferName("bufferstdstring", id)
      check(got ~= nil and not tostring(got):match("^%d+$"),
        string.format("%s %s (%d) is text: %s", label, name, id, tostring(got)))
      eq(got, want, string.format("%s %s matches pret", label, name))
    end
  end
  check(n == 29, "menu.h defines 29 STDSTRING ids (" .. n .. ")")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
