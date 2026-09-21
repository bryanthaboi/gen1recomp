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

local PRET = "../pokefirered/data/specials.inc"

local function readPret()
  local fh = io.open(PRET, "r")
  if not fh then return nil end
  local names, index = {}, 0
  for line in fh:lines() do
    local nm = line:match("^%s*def_special%s+([%w_]+)")
    if nm and nm ~= "ptr" then
      names[index] = nm
      index = index + 1
    end
  end
  fh:close()
  return names, index
end

local pretNames, pretCount = readPret()
if not pretNames then
  print("[skip] ../pokefirered not present; nothing to diff against")
  os.exit(0)
end

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")

local ENGINE_BASE = Std.SPECIAL_ENGINE_BASE or 0xF000
local ALIASES = Std.SPECIAL_ALIASES or {}
local NAME_BY_ID = Std.SPECIAL_NAME_BY_ID or {}

print("[test] 1. specials.inc parsed")
check(pretCount == 444, "444 def_special entries (got " .. tostring(pretCount) .. ")")
check(pretNames[0] == "HealPlayerParty", "index 0 is HealPlayerParty")

print("[test] 2. Std.SPECIAL names match their pret index")
local seen = {}
for name, id in pairs(Std.SPECIAL) do
  if id < ENGINE_BASE then
    local canonical = ALIASES[name] or name
    check(pretNames[id] == canonical, string.format(
      "Std.SPECIAL.%s = 0x%X is %s in pret (want %s)",
      name, id, tostring(pretNames[id]), canonical))
    check(pretNames[id] ~= "NullFieldSpecial", string.format(
      "Std.SPECIAL.%s = 0x%X is not a NullFieldSpecial slot", name, id))
    seen[id] = true
  end
end

print("[test] 3. every Natives.ALLOW special key is a known cart id")
local bound = {}
for key in pairs(Natives.ALLOW) do
  local rest = key:match("^special:(.+)$")
  if rest then
    local id = tonumber(rest)
    check(id ~= nil, "ALLOW key '" .. key .. "' is a decimal special id")
    if id and id < ENGINE_BASE then
      bound[#bound + 1] = id
      local declared = NAME_BY_ID[id]
      check(declared ~= nil, string.format(
        "special 0x%X is declared in Std.SPECIAL (pret calls it %s)", id, tostring(pretNames[id])))
      if declared then
        check(pretNames[id] == declared, string.format(
          "bound special 0x%X runs %s and pret names it %s", id, declared, tostring(pretNames[id])))
      end
    end
  end
end
check(#bound > 20, "at least 20 cart specials bound (got " .. #bound .. ")")

print("[test] 4. the ids the audit called mis-bound")
local WANT = {
  ChoosePartyMon = 0x9F,
  ChangePokemonNickname = 0x9E,
  BufferMonNickname = 0x7C,
  IsMonOTIDNotPlayers = 0x7D,
  GetBattleOutcome = 0xB4,
  GetDaycareState = 0xB6,
  SetUnlockedPokedexFlags = 0x181,
  EnableNationalPokedex = 0x16F,
  IsNationalPokedexEnabled = 0x193,
  StartOldManTutorialBattle = 0x9D,
  Script_IsFanClubMemberFanOfPlayer = 0xA3,
  Script_GetNumFansOfPlayerInTrainerFanClub = 0xA4,
  Script_BufferFanClubTrainerName = 0xA5,
  Script_TryLoseFansFromPlayTimeAfterLinkBattle = 0xA6,
  Script_TryLoseFansFromPlayTime = 0xA7,
  Script_SetPlayerGotFirstFans = 0xA8,
  Script_UpdateTrainerFanClubGameClear = 0xA9,
  Script_TryGainNewFanFromCounter = 0xAA,
  GetHeracrossSizeRecordInfo = 0x77,
  CompareHeracrossSize = 0x78,
  GetMagikarpSizeRecordInfo = 0x79,
  CompareMagikarpSize = 0x7A,
  GetProfOaksRatingMessage = 0xD5,
}
for name, id in pairs(WANT) do
  check(Std.SPECIAL[name] == id, string.format("Std.SPECIAL.%s == 0x%X (got %s)",
    name, id, tostring(Std.SPECIAL[name])))
  check(Natives.ALLOW["special:" .. id] ~= nil, string.format("%s (0x%X) has a handler", name, id))
end

print("[test] 5. ids pret never calls stay unbound")
for id = 0, pretCount - 1 do
  if pretNames[id] == "NullFieldSpecial" then
    check(Natives.ALLOW["special:" .. id] == nil,
      string.format("0x%X (NullFieldSpecial) is unbound", id))
  end
end
check(Natives.ALLOW["special:" .. 0x18B] == nil, "0x18B OpenMuseumFossilPic no longer sets dex flags")
check(Natives.ALLOW["special:" .. 0x19D] == nil, "0x19D RemoveBerryPowderVendorMenu unbound")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
