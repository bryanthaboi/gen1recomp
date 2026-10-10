package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ImportGc = require("src.import.ImportGc")

local function envWith(set)
  return function(name) return set[name] end
end

for _, name in ipairs({ "HANDHELD", "POKEPORT_HANDHELD", "PORTMASTER", "POKEPORT_PORTMASTER" }) do
  check(ImportGc.lowMemoryHost(envWith({ [name] = "1" })), name .. "=1 is a low-memory import host")
end
check(not ImportGc.lowMemoryHost(envWith({})), "a desktop env is not a low-memory host")
check(not ImportGc.lowMemoryHost(envWith({ PORTMASTER = "0" })), "PORTMASTER=0 is not a low-memory host")

collectgarbage("setpause", 200)
collectgarbage("setstepmul", 200)
eq(ImportGc.tune(envWith({})), false, "desktop import leaves the collector alone")
eq(collectgarbage("setpause", 200), 200, "desktop pause untouched")
eq(collectgarbage("setstepmul", 200), 200, "desktop stepmul untouched")

eq(ImportGc.tune(envWith({ PORTMASTER = "1" })), true, "PortMaster import tunes the collector")
eq(collectgarbage("setpause", 200), ImportGc.PAUSE, "PortMaster pause applied")
eq(collectgarbage("setstepmul", 200), ImportGc.STEPMUL, "PortMaster stepmul applied")
check(ImportGc.PAUSE <= 100, "pause collects before the heap doubles")
check(ImportGc.STEPMUL >= 400, "stepmul keeps pace with extractor garbage")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

for _, path in ipairs({ "src/import/ExtractThread.lua", "src/import/gba/extract_worker.lua" }) do
  local src = read(path)
  local tuneAt = src:find('require("src.import.ImportGc").tune()', 1, true)
  local argsAt = src:find("= ...", 1, true)
  check(tuneAt ~= nil and argsAt ~= nil and tuneAt < argsAt,
    path .. " tunes its thread state before taking the ROM bytes")
end

local gen3 = read("src/import/RomExtractorGen3.lua")
check(gen3:find('require("src.import.ImportGc").lowMemoryHost()', 1, true) ~= nil,
  "worker count and GC tuning share one low-memory gate")

T.finish("import_gc_handheld_bug2828")
