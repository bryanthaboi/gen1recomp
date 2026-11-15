-- ../pokegold/data/phone/permanent_numbers.asm:1 PermanentNumbers
-- ../pokegold/constants/event_flags.asm:268
-- ../pokecrystal/constants/engine_flags.asm:125
-- ../pokegold/data/events/pokedex_ratings.asm:7 OakRatings
-- ../pokegold/data/events/happiness_probabilities.asm:1

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function readJson(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return require("src.link.Json").decode(body)
end

local Phone = require("src.core.gen2.Phone")
local Fixture = require("tests.fixtures.gen2_phone_events")

check(next(Phone.PERMANENT_NUMBERS) == nil,
  "no hand-typed permanent numbers before events.lua is read")
eq(Phone.REMATCH_EVENTS, nil, "no hand-typed rematch event table")

Fixture.install()
eq(table.concat(Phone.PERMANENT_NUMBERS, ","), "1,4",
  "permanent numbers come off events.lua")
eq(Phone.rematchEvent(15), 628, "Joey's rematch flag comes off constants.rematchFlags")

do
  local events = {}
  for k, v in pairs(Fixture.events) do events[k] = v end
  events.permanentNumbers = nil
  local ok, err = pcall(Phone.useExtracted, events)
  check(not ok and tostring(err):find("permanentNumbers") ~= nil,
    "an events.lua without permanentNumbers is an error")
end

do
  local constants = {}
  for k, v in pairs(Fixture.constants) do constants[k] = v end
  constants.rematchFlags = nil
  local ok, err = pcall(Phone.useRegistry,
    { gen2EventTables = Fixture.events, gen2Constants = constants })
  check(not ok and tostring(err):find("rematchFlags") ~= nil,
    "a constants.lua without rematchFlags is an error")
end

do
  local constants = {}
  for k, v in pairs(Fixture.constants) do constants[k] = v end
  constants.rematchFlags = { { 15, "engine", 109 } }
  Phone.useRegistry({ gen2EventTables = Fixture.events, gen2Constants = constants })
  eq(Phone.rematchEvent(15), nil, "an engine-flag rematch has no event number")
  eq(Phone.rematchEngineFlag(15), 109, "and names its engine flag")
  local engineFlags = {}
  check(Phone.setRematchReady(nil, 15, true, engineFlags), "the engine flag can be set")
  eq(engineFlags[109], true, "on the engine flag table")
  check(Phone.isReadyForRematch(nil, 15, engineFlags), "and reads back")
  Fixture.install()
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local manifest = readJson("tools/rom_manifest_" .. version .. ".json")
  local consts = manifest and manifest.constants or {}
  for _, symbol in ipairs({ "OakRatings", "PermanentNumbers",
      "HappinessData_OlderHaircutBrother", "HappinessData_YoungerHaircutBrother",
      "HappinessData_DaisysGrooming", "StatNames" }) do
    check(manifest and manifest.symbols and manifest.symbols[symbol] ~= nil,
      version .. ": manifest resolves " .. symbol)
  end
  check(type(consts.rematchFlags) == "table" and #consts.rematchFlags > 0,
    version .. ": manifest carries rematchFlags")
end

local home = os.getenv("HOME") or ""
local base = home .. "/Library/Application Support/LOVE"
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local root = os.getenv(version:upper() .. "_CACHE")
    or (base .. "/g1r-" .. version .. "/" .. version)
  local function load(name)
    local chunk = loadfile(root .. "/data/generated/" .. name .. ".lua")
    return chunk and chunk() or nil
  end
  local events, consts, text = load("events"), load("constants"), load("rom_text")
  if not (events and consts and text) then
    print("[skip] no " .. version .. " cache")
  else
    eq(table.concat(events.permanentNumbers or {}, ","), "1,4",
      version .. ": PermanentNumbers is MOM, ELM")
    eq(#(events.oakRatings or {}), 19, version .. ": OakRatings has 19 rows")
    eq(events.oakRatings[1].max, 9, version .. ": the first rating caps at 9")
    eq(events.oakRatings[19].max, 255, version .. ": the last rating caps at 255")
    check(text[events.oakRatings[15].text] ~= nil,
      version .. ": every rating's text is a rom_text label")
    eq(events.haircutTables and events.haircutTables.older[1][3], "OLDERCUT1",
      version .. ": the older brother's first row is OLDERCUT1")
    local joey
    for _, row in ipairs(consts.rematchFlags or {}) do
      if row[1] == 15 then joey = row end
    end
    if version == "crystal" then
      eq(joey and joey[2], "engine", "crystal: Joey's rematch is an engine flag")
      eq(joey and consts.engineFlagOrder[joey[3] + 1], "ENGINE_JOEY_READY_FOR_REMATCH",
        "crystal: and it is ENGINE_JOEY_READY_FOR_REMATCH")
    else
      eq(joey and joey[2], "event", version .. ": Joey's rematch is an event flag")
      eq(joey and joey[3], 628, version .. ": EVENT_JOEY_READY_FOR_REMATCH is 628")
    end
    eq(text["StatNames#1"], "ATTACK", version .. ": StatNames is a rom_text list")
    eq(text["StatNames#8"], "ABILITY", version .. ": through ABILITY")
    eq(text["YesNoMenuHeader.MenuData#2"], "NO", version .. ": a static menu's rows are keyed #k")
    check((text["_BenFernText1"] or ""):find("{DAY}", 1, true) ~= nil,
      version .. ": text_today decodes as {DAY}")
  end
end

T.finish("gen2_rom_tables_s7")
