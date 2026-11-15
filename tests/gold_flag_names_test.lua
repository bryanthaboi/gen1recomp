package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gold flag names")
local check, eq = S.check, S.eq

local FlagIds = require("src.core.gen2.FlagIds")
local constants, cache = require("tests.cache_gen2_constants").load("gold")
if not (constants and constants.eventFlagOrder) then
  print("[skip] no Gold cache with eventFlagOrder")
  check(true, "gold cache absent : SKIPPED")
  S.finish()
  return
end
local names = { events = FlagIds.events(constants), engine = FlagIds.engine(constants) }

check(names.events.EVENT_BEAT_FALKNER ~= nil, "EVENT_* table is populated")
check(names.engine.ENGINE_ZEPHYRBADGE ~= nil, "ENGINE_* table is populated")

-- data/events/engine_flags.asm:46
local badges = {
  "ENGINE_ZEPHYRBADGE", "ENGINE_HIVEBADGE", "ENGINE_PLAINBADGE",
  "ENGINE_FOGBADGE", "ENGINE_MINERALBADGE", "ENGINE_STORMBADGE",
  "ENGINE_GLACIERBADGE", "ENGINE_RISINGBADGE",
}
for i = 2, #badges do
  eq(names.engine[badges[i]], names.engine[badges[i - 1]] + 1,
     badges[i] .. " follows " .. badges[i - 1])
end

local POKEGOLD = os.getenv("POKEGOLD") or "../pokegold"

local initialPath = cache .. "/data/generated/initial_events.lua"
local stdScripts  = POKEGOLD .. "/engine/events/std_scripts.asm"

local function readable(path)
  local fh = io.open(path, "r")
  if not fh then return false end
  fh:close()
  return true
end

if not readable(initialPath) then
  check(true, "gold cache absent : name table checked, cart cross-check SKIPPED")
  S.finish()
  return
end
if not readable(stdScripts) then
  check(true, "pokegold absent : name table checked, cart cross-check SKIPPED")
  S.finish()
  return
end

local Flags = dofile("tools/goldwalk/flags.lua")
local romIds = assert(loadfile(initialPath))().flags
local pretNames = Flags.setEventsOf(stdScripts, "InitializeEventsScript")

eq(#pretNames, #romIds,
   "InitializeEventsScript sets the same number of flags in pret and the cart")

local mismatches, span = {}, { lo = math.huge, hi = -math.huge }
for i, name in ipairs(pretNames) do
  local want, got = names.events[name], romIds[i]
  if got then
    span.lo, span.hi = math.min(span.lo, got), math.max(span.hi, got)
  end
  if want ~= got then
    mismatches[#mismatches + 1] =
      ("#%d %s pret=%s cart=%s"):format(i, name, tostring(want), tostring(got))
  end
end

if #mismatches > 0 then
  -- Print the first few: the whole list is one-per-flag noise, and the head is
  -- enough to see whether it is a wholesale shift or a single retired const.
  for i = 1, math.min(5, #mismatches) do print("  " .. mismatches[i]) end
end
eq(#mismatches, 0,
   ("pret numbering == cart numbering across ids %d..%d")
     :format(span.lo, span.hi))

S.finish()
