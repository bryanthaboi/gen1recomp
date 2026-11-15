-- ../pokegold/data/wild/fish.asm:210 TimeFishGroups
-- ../pokegold/data/phone/special_calls.asm:1 SpecialPhoneCallList
-- ../pokegold/data/phone/non_trainer_names.asm:1 NonTrainerCallerNames

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

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local manifest = readJson("tools/rom_manifest_" .. version .. ".json")
  check(manifest ~= nil, version .. ": manifest loads")
  local consts = manifest and manifest.constants or {}
  eq(consts.timeFishGroupCount, 22,
    version .. ": TimeFishGroups has the asm's 22 rows")
  for _, symbol in ipairs({ "NonTrainerCallerNames", "SpecialCallOnlyWhenOutside",
      "SpecialCallWhereverYouAre", "MenuHeader_UsableKeyItem",
      "ScrollingMenu_UpdateDisplay.CancelString" }) do
    check(manifest and manifest.symbols and manifest.symbols[symbol] ~= nil,
      version .. ": manifest resolves " .. symbol)
  end
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
  local encounters, events, consts, text =
    load("encounters"), load("events"), load("constants"), load("text")
  if not (encounters and events and consts and text) then
    print("[skip] no " .. version .. " cache")
  else
    local rows = 0
    for _ in pairs(encounters.timeFishGroups or {}) do rows = rows + 1 end
    eq(rows, consts.timeFishGroupCount,
      version .. ": the cache holds exactly TimeFishGroups' rows")
    eq(encounters.timeFishGroups[consts.timeFishGroupCount], nil,
      version .. ": nothing is read past the last row")
    local unresolved = 0
    for _, group in pairs(encounters.fishGroups or {}) do
      for _, rod in ipairs({ "old", "good", "super" }) do
        for _, entry in ipairs(group[rod] or {}) do
          if entry.timeGroup and not entry.day then unresolved = unresolved + 1 end
        end
      end
    end
    eq(unresolved, 0, version .. ": every time_group row resolves")

    eq(#events.specialCalls, #consts.specialCallOrder - 1,
      version .. ": one special call per SPECIALCALL_* past NONE")
    for _, row in ipairs(events.specialCalls) do
      check(row.call ~= nil and (row.when == "outside" or row.when == "anywhere"),
        version .. ": special call " .. row.id .. " has a name and a condition")
    end
    eq(events.specialCalls[6].when, "anywhere",
      version .. ": SPECIALCALL_BIKESHOP is SpecialCallWhereverYouAre")
    eq(events.specialCalls[1].when, "outside",
      version .. ": SPECIALCALL_POKERUS is SpecialCallOnlyWhenOutside")
    check(type(events.phoneNames) == "table" and events.phoneNames[1] ~= nil,
      version .. ": NonTrainerCallerNames is in events.lua")
    if version == "crystal" then
      eq(events.phoneNames[5], "BUENA:<LF>   DISC JOCKEY",
        "crystal: Buena's caller name keeps its second line")
    end

    eq(events.packSubmenu and table.concat(events.packSubmenu, "|"),
      "USE|GIVE|TOSS|SEL|QUIT", version .. ": the PACK submenu's rows")
    local cancel = text.labels["ScrollingMenu_UpdateDisplay.CancelString"]
    eq(cancel and text[cancel], "CANCEL", version .. ": ScrollingMenu's CANCEL")
  end
end

T.finish("gen2_rom_tables_s6")
