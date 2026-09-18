#!/usr/bin/env luajit
-- Running Shoes: FLAG_SYS_B_DASH gating + Brock defeat → aide clearflag → setflag.

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

local Flags = require("src.core.game3.scripting.flags")
local Vm = require("src.core.game3.scripting.vm")
local Player = require("src.core.game3.player")
local Space = require("src.core.game3.scripting.space")

print("[test] 1. Flag / var constants (pret)")
check(Flags.IDS.SYS_B_DASH == 0x82F, "SYS_B_DASH = 0x82F")
check(Flags.IDS.HIDE_PEWTER_CITY_RUNNING_SHOES_GUY == 0x092, "HIDE aide = 146")
check(Flags.IDS.MAP_SCENE_PEWTER_CITY == 0x406C, "MAP_SCENE_PEWTER_CITY")
check(Flags.IDS.BADGE01_GET == 0x820, "BADGE01_GET")
check(Flags.trainerFlagId(414) == 0x500 + 414, "Brock trainer flag")
check(Flags.NEW_GAME_HIDE_FLAGS[4] == 146 or (function()
  for _, id in ipairs(Flags.NEW_GAME_HIDE_FLAGS) do
    if id == 146 then return true end
  end
  return false
end)(), "new-game hides Running Shoes aide")

print("[test] 2. B-dash gated on SYS_B_DASH")
local store = Flags.newStore()
Flags.applyNewGameHideFlags(store)
Space.store = store
check(Flags.getFlag(store, nil, 146) == true, "aide hidden at new game")
check(Player.canDash() == false, "no dash before shoes")
Flags.setFlag(store, nil, Flags.IDS.SYS_B_DASH, true)
check(Player.canDash() == true, "dash after SYS_B_DASH")
Flags.setFlag(store, nil, Flags.IDS.SYS_B_DASH, false)
check(Player.canDash() == false, "dash revoked")

print("[test] 3. CONTINUE_SCRIPT trainerbattle → eventScript (Brock → clearflag aide)")
local scripts = {
  ["talk_brock"] = {
    {
      op = "trainerbattle",
      type = 1, -- CONTINUE_SCRIPT_NO_MUSIC
      trainer = 414,
      localId = 0,
      eventScript = "defeated_brock",
      introText = "t_intro",
      defeatText = "t_defeat",
    },
    { op = "setvar", var = 0x406C, value = 99 }, -- must NOT run on first win
    { op = "end" },
  },
  ["defeated_brock"] = {
    { op = "setflag", flag = 1200 }, -- FLAG_DEFEATED_BROCK
    { op = "setflag", flag = 0x820 }, -- BADGE01
    { op = "setvar", var = 0x406C, value = 1 }, -- MAP_SCENE_PEWTER_CITY
    { op = "setflag", flag = 46 }, -- hide gym guide
    { op = "clearflag", flag = 146 }, -- show Running Shoes aide
    { op = "end" },
  },
  ["aide_give"] = {
    { op = "setflag", flag = 0x82F }, -- SYS_B_DASH
    { op = "setvar", var = 0x406C, value = 2 },
    { op = "end" },
  },
}

store = Flags.newStore()
Flags.applyNewGameHideFlags(store)
Space.store = store

local vm = Vm.new({
  store = store,
  scripts = scripts,
  adapters = {
    log = function() end,
    startTrainerBattle = function(_foe, done)
      done("win")
    end,
  },
})

check(vm:start("talk_brock") == true, "start Brock talk")
-- Instant battle: drain waiting if any
for _ = 1, 20 do
  if not vm:isRunning() then break end
  vm:tick()
end
check(not vm:isRunning(), "script finished")
check(Flags.getFlag(store, nil, Flags.trainerFlagId(414)) == true, "Brock trainer flag set")
check(Flags.getFlag(store, nil, 146) == false, "aide hide flag cleared")
check(Flags.getVar(store, nil, 0x406C) == 1, "MAP_SCENE_PEWTER_CITY = 1")
check(Flags.getVar(store, nil, 0x406C) ~= 99, "did not fall through past trainerbattle")
check(Flags.getFlag(store, nil, 0x820) == true, "badge 1 set")
check(Player.canDash() == false, "still no dash until aide")

check(vm:start("aide_give") == true, "aide give shoes")
for _ = 1, 10 do
  if not vm:isRunning() then break end
  vm:tick()
end
check(Flags.getFlag(store, nil, 0x82F) == true, "SYS_B_DASH set by aide")
check(Flags.getVar(store, nil, 0x406C) == 2, "MAP_SCENE_PEWTER_CITY = 2")
check(Player.canDash() == true, "dash after aide")

print("[test] 4. Re-talk Brock skips battle (already fought)")
local battled = 0
vm = Vm.new({
  store = store,
  scripts = scripts,
  adapters = {
    log = function() end,
    startTrainerBattle = function(_foe, done)
      battled = battled + 1
      done("win")
    end,
  },
})
check(vm:start("talk_brock") == true, "re-talk Brock")
for _ = 1, 20 do
  if not vm:isRunning() then break end
  vm:tick()
end
check(battled == 0, "no second battle")
check(Flags.getVar(store, nil, 0x406C) == 99, "falls through to post-battle script")

print("[test] 5. Extracted cache has Pewter aide + B_DASH ops")
local cacheRoot = (os.getenv("HOME") or "") .. "/.local/share/love/pokemon-love2d/firered"
local evPath = cacheRoot .. "/data/generated/gba/scripts/events.lua"
local scPath = cacheRoot .. "/data/generated/gba/scripts/scripts.lua"
local evF = io.open(evPath, "r")
local scF = io.open(scPath, "r")
if evF and scF then
  local events = load(evF:read("*a"), "@events", "t", {})()
  evF:close()
  local scriptsPack = load(scF:read("*a"), "@scripts", "t", {})()
  scF:close()
  local pew = events.FR_PEWTER_CITY
  check(pew ~= nil, "FR_PEWTER_CITY events in cache")
  local aide
  for _, o in ipairs((pew and pew.objects) or {}) do
    if tonumber(o.flag) == 146 then aide = o break end
  end
  check(aide ~= nil, "aide object flag 146")
  check(aide and aide.x == 46 and aide.y == 20, "aide at (46,20)")
  local give = scriptsPack["g3:081662de"]
  local foundDash = false
  if give then
    for _, row in ipairs(give) do
      if row.op == "setflag" and tonumber(row.flag or row[1]) == 0x82F then
        foundDash = true
      end
    end
  end
  check(foundDash, "AideGiveRunningShoes setflag SYS_B_DASH")
  local defeated = scriptsPack["g3:0816a5c5"]
  local foundClear = false
  if defeated then
    for _, row in ipairs(defeated) do
      if row.op == "clearflag" and tonumber(row.flag or row[1]) == 146 then
        foundClear = true
      end
    end
  end
  check(foundClear, "DefeatedBrock clearflag aide")
else
  print("[skip] live firered cache not present")
end

if failed > 0 then
  print(string.format("\n%d FAILURE(S)", failed))
  os.exit(1)
end
print("\nAll running-shoes checks passed.")
