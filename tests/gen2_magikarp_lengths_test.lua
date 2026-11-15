package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 magikarp lengths")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Specials = require("src.script.gen2.Specials")

local function vmWith(tables, fish)
  local vm = {
    scriptVar = 0,
    specials = {
      data = function() return { gen2EventTables = tables } end,
      save = function() return {} end,
      monName = function(sp) return sp end,
      selectPartyMon = function(_, done) done(1, fish) end,
    },
  }
  function vm:setStringBuffer(v) self.stringBuffer = v end
  return vm
end

local LONG = { species = "MAGIKARP", otId = 0, ot = "KURT",
  dvs = { attack = 15, defense = 15, speed = 15, special = 15 } }

do
  local ok, err = pcall(Specials.HANDLERS.CheckMagikarpLength, vmWith({}, LONG))
  check(not ok and tostring(err):find("magikarpLengths", 1, true),
    "an events.lua without magikarpLengths is an error")
  ok, err = pcall(Specials.magikarpLengths, { specials = {} })
  check(not ok and tostring(err):find("magikarpLengths", 1, true),
    "and so is no event data at all")
end

do
  local flat = {}
  for i = 1, 14 do flat[i] = { 65535, 1 } end
  flat[1] = { 0x0100, 1 }
  local vm = vmWith({ magikarpLengths = flat, magikarpRecordHolder = "X" }, LONG)
  Specials.HANDLERS.CheckMagikarpLength(vm)
  local feet, inches, mm = Specials.magikarpLength(flat, 0, 0xffff)
  eq(vm.stringBuffer, Specials.magikarpLengthText(feet, inches),
    "the handler measures with the cache's rows")
  check(mm ~= nil and mm ~= 0 and not (feet == 5 and inches == 3),
    "rows that are not the cart's give a different length")
end

do
  local ok, err = pcall(Specials.HANDLERS.MagikarpHouseSign, vmWith({}, LONG))
  check(not ok and tostring(err):find("magikarpRecordHolder", 1, true),
    "an events.lua without magikarpRecordHolder is an error")
  local vm = vmWith({ magikarpRecordHolder = "KOJI" }, LONG)
  eq(Specials.magikarpBest(vm, {}).name, "KOJI",
    "the default holder is the cache's name")
  eq(Specials.magikarpBest(vm, {}).feet .. "/" .. Specials.magikarpBest(vm, {}).inches,
    "3/6", "at the cart's 3'6\"")
  eq(Specials.magikarpBest(vm, { magikarpRecord = { feet = 4, inches = 1, name = "KURT" } }).name,
    "KURT", "a set record keeps its own holder")
end

local home = os.getenv("HOME") or ""
local pattern = os.getenv("GEN2_IDENTITY") or "g1r-%s"
local found = 0
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local path = home .. "/Library/Application Support/LOVE/"
    .. pattern:format(version) .. "/" .. version .. "/data/generated/events.lua"
  local chunk = loadfile(path)
  local ok, events = false, nil
  if chunk then ok, events = pcall(chunk) end
  if ok and type(events) == "table" then
    found = found + 1
    eq(events.magikarpRecordHolder, "RALPH",
      version .. ": InitializeMagikarpHouse.Ralph is in events.lua")
    local rows = events.magikarpLengths
    check(type(rows) == "table" and #rows == 14,
      version .. ": events.lua carries fourteen MagikarpLengths rows")
    if type(rows) == "table" and #rows == 14 then
      eq(rows[1][1] .. "/" .. rows[1][2], "110/1", version .. ": row 1 is dwb 110, 1")
      eq(rows[14][1] .. "/" .. rows[14][2], "65510/1", version .. ": row 14 is dwb 65510, 1")
      local vm = vmWith({ magikarpLengths = rows,
        magikarpRecordHolder = events.magikarpRecordHolder }, LONG)
      Specials.HANDLERS.CheckMagikarpLength(vm)
      eq(vm.stringBuffer, [[5'3"]], version .. ": the cached rows measure the long fish at 5'3\"")
      local feet, inches = Specials.magikarpLength(rows, 1000, 0xffff)
      eq(Specials.magikarpLengthText(feet, inches), [[3'2"]],
        version .. ": and the short one at 3'2\"")
    end
  end
end
if found == 0 then
  print("[skip] no gen2 cache: cache half not run")
end

S.finish()
