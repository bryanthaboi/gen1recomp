package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function sourceOf(rel)
  local f = io.open(rel, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function isLoaded(name)
  return package.loaded[name] ~= nil
end

local SaveData = require("src.core.SaveData")
check(isLoaded("src.inventory.Bag") == false,
  "requiring SaveData does not load Bag (the cycle lost its load-time leg)")
check(isLoaded("src.core.Data") == false,
  "requiring SaveData does not load Data")
check(type(SaveData.saveFilename) == "function", "SaveData still exposes saveFilename")

local Bag = require("src.inventory.Bag")
check(isLoaded("src.core.Data") == false,
  "requiring Bag does not load Data (its requires are at call sites)")
check(type(Bag.add) == "function", "Bag still exposes add")

local ChipAudio = require("src.core.ChipAudio")
check(isLoaded("src.core.SessionLifecycle") == false,
  "requiring ChipAudio does not load SessionLifecycle (edge removed)")
check(isLoaded("src.core.Music") == false, "requiring ChipAudio does not load Music")
check(type(ChipAudio.shutdown) == "function", "ChipAudio still exposes shutdown")

local SessionLifecycle = require("src.core.SessionLifecycle")
check(isLoaded("src.core.Music") == false,
  "requiring SessionLifecycle does not load Music (its stop is call-site-only)")
check(type(SessionLifecycle.endProcess) == "function",
  "SessionLifecycle still exposes endProcess")

do
  local chip = sourceOf("src/core/ChipAudio.lua")
  check(chip ~= nil, "ChipAudio.lua is readable")
  check(chip:find('require("src.core.SessionLifecycle")', 1, true) == nil,
    "ChipAudio contains no SessionLifecycle require (SCC edge absent, not deferred)")

  local sd = sourceOf("src/core/SaveData.lua")
  check(sd ~= nil, "SaveData.lua is readable")
  check(sd:find('local Bag = require("src.inventory.Bag")', 1, true) == nil,
    "SaveData has no load-time Bag require")
  check(sd:find('require("src.inventory.Bag")', 1, true) ~= nil,
    "SaveData keeps the call-site Bag require (behaviour unchanged)")

  local sl = sourceOf("src/core/SessionLifecycle.lua")
  check(sl ~= nil, "SessionLifecycle.lua is readable")
  check(sl:find('package.loaded["src.core.ChipAudio"]', 1, true) ~= nil,
    "endProcess reaches ChipAudio through package.loaded (the inversion)")

  local bag = sourceOf("src/inventory/Bag.lua")
  check(bag:find('\nlocal Data = require("src.core.Data")', 1, true) == nil,
    "Bag keeps Data at call sites (no column-0 require)")
  local data = sourceOf("src/core/Data.lua")
  check(data:find('\nlocal CacheFs = require("src.import.CacheFs")', 1, true) == nil,
    "Data keeps CacheFs at call sites (no column-0 require)")
end

local ran = 0
SessionLifecycle.registerProcessShutdown(function() ran = ran + 1 end)
local okEnd = pcall(SessionLifecycle.endProcess)
check(okEnd, "endProcess runs with ChipAudio loaded and no worker thread")
eq(ran, 1, "the registered shutdowns still drain")

local okSecond = pcall(ChipAudio.shutdown)
check(okSecond, "ChipAudio.shutdown is idempotent after endProcess already called it")
check(isLoaded("src.core.SessionLifecycle") == true,
  "SessionLifecycle stays loaded once explicitly required (no reload cycle)")

T.finish("game3_load_order_seam_test")
