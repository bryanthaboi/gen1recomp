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

local STUB_NAME = "multichoice" .. "_data_stub"
local STUB_MODULE = "src.import.gba." .. STUB_NAME
local STUB_FILE = "src/import/gba/" .. STUB_NAME .. ".lua"

print("[test] 1. the checked-in list table is gone")
local stubFile = io.open(STUB_FILE, "rb")
check(stubFile == nil, STUB_FILE .. " no longer exists")
if stubFile then stubFile:close() end
local okStub = pcall(require, STUB_MODULE)
check(okStub == false, "requiring the stub module fails")
local pipe = io.popen("grep -rl '" .. STUB_NAME .. "' src 2>/dev/null")
local hits = pipe and pipe:read("*a") or ""
if pipe then pipe:close() end
check(hits == "", "no file under src/ references the stub (" .. hits:gsub("%s+", " ") .. ")")

local Extract = require("src.import.gba.extract_island1")
Extract.CACHE_ROOT = "/nonexistent-multichoice-root"
local Multichoice = require("src.core.game3.scripting.multichoice")
local MultichoiceExtract = require("src.import.gba.multichoice_extract")

print("[test] 2. the reader and the writer agree on one cache path")
check(Multichoice.CACHE_REL == "data/generated/gba/" .. MultichoiceExtract.CACHE_REL,
  "Multichoice.CACHE_REL is the extractor's path (" .. tostring(Multichoice.CACHE_REL) .. ")")

if os.getenv("POKEPORT_IDENTITY") then
  print("[skip] fixture sections need a run without POKEPORT_IDENTITY: the identity cache is read first")
else
  print("[test] 3. a missing cache degrades to synthetic labels")
  Multichoice.LISTS = {}
  check(Multichoice.tryLoadCache() == false, "no cache means no lists")
  local synthetic = Multichoice.resolve(4242, 3)
  check(#synthetic == 3, "an unknown list keeps the count hint (" .. #synthetic .. ")")
  check(tostring(synthetic[1]):find("OPTION") ~= nil,
    "an unknown list falls back to OPTION labels (" .. tostring(synthetic[1]) .. ")")

  print("[test] 4. the cache table is what resolve() serves")
  local tmp = os.tmpname()
  os.remove(tmp)
  os.execute('mkdir -p "' .. tmp .. '/scripts"')
  local fixture = assert(io.open(tmp .. "/scripts/multichoice.lua", "wb"))
  fixture:write('return {\n')
  fixture:write('  [0] = { count = 2, labels = { "CACHE YES", "CACHE NO" } },\n')
  fixture:write('  [900] = { count = 1, labels = { "CACHE ONLY" } },\n')
  fixture:write('}\n')
  fixture:close()
  Extract.CACHE_ROOT = tmp
  Multichoice.LISTS = {}
  check(Multichoice.tryLoadCache() == true, "the cache table loads")
  local zero = Multichoice.resolve(0, 2)
  check(zero[1] == "CACHE YES" and zero[2] == "CACHE NO",
    "list 0 comes from the cache (" .. tostring(zero[1]) .. ", " .. tostring(zero[2]) .. ")")
  local only = Multichoice.resolve(900, 2)
  check(only[1] == "CACHE ONLY", "a cache-only list id resolves (" .. tostring(only[1]) .. ")")
  os.execute('rm -rf "' .. tmp .. '"')
end

print("[test] 5. an imported cache serves the ROM lists")
local Cache = require("tests.game3_cache")
local root = Cache.root("scripts/multichoice.lua")
if not root then
  print("[skip] imported multichoice lists: " .. tostring(Cache.reason))
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end
print("[info] FireRed cache at " .. root)
Multichoice.LISTS = {}
Extract.CACHE_ROOT = root
check(Multichoice.tryLoadCache() == true, "the imported cache loads")
local count = 0
for _ in pairs(Multichoice.LISTS) do count = count + 1 end
check(count >= 65, "the imported cache carries every list (" .. count .. ")")
local yesNo = Multichoice.resolve(0, 2)
check(yesNo[1] == "YES" and yesNo[2] == "NO",
  "list 0 is YES / NO (" .. tostring(yesNo[1]) .. ", " .. tostring(yesNo[2]) .. ")")
-- include/constants/menu.h:20
local bike = Multichoice.resolve(13, 2)
check(tostring(bike[1]):find("BICYCLE") ~= nil and bike[2] == "NO THANKS",
  "list 13 is the Bike Shop menu (" .. tostring(bike[1]) .. ", " .. tostring(bike[2]) .. ")")
-- include/constants/menu.h:27
local elevator = Multichoice.resolve(20, 3)
check(elevator[1] == "ROOFTOP" and elevator[3] == "EXIT",
  "list 20 is the Trainer Tower elevator (" .. tostring(elevator[1]) .. ")")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
