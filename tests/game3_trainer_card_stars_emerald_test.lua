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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local HOENN = 202
package.loaded["src.core.game3.dex"] = {
  regionalMax = function() return HOENN end,
  regionalNumber = function(sp)
    sp = tonumber(sp)
    if sp and sp >= 1 and sp <= HOENN then return sp end
    return nil
  end,
  summaryCount = function(save)
    local n = 0
    for _, on in pairs(save.dex and save.dex.caught or {}) do if on then n = n + 1 end end
    return n
  end,
  isCaught = function(dex, sp) return dex and dex.caught and dex.caught[sp] == true or false end,
  nationalEnabled = function() return true end,
  countCaught = function() return 0 end,
}

local Flags = require("src.core.game3.scripting.flags")
local store = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = store, getStore = function() return store end }
require("src.core.game3.link.family").activeVersion = function() return "emerald" end

local TrainerCard = require("src.ui.game3.trainer_card")
local IDS = Flags.forVersion("emerald").IDS

local function session()
  local caught = {}
  -- pokeemerald/src/pokedex.c:4392
  for n = 1, HOENN - 2 do caught[n] = true end
  local winners = {}
  for i = 1, 13 do winners[i] = { species = 0 } end
  -- pokeemerald/src/contest_util.c:2386
  for i = 9, 13 do winners[i] = { species = 25 + i } end
  return {
    version = "emerald", name = "MAY",
    hofDebutHours = 40, hofDebutMinutes = 12, hofDebutSeconds = 3,
    dex = { caught = caught, seen = caught },
    contestWinners = winners,
  }
end

local function setSymbols(on)
  -- pokeemerald/src/trainer_card.c:652
  for i = 0, 6 do
    Flags.setFlag(store, nil, IDS.SYS_TOWER_SILVER + 2 * i, on)
    Flags.setFlag(store, nil, IDS.SYS_TOWER_GOLD + 2 * i, on)
  end
end

print("[test] 1. HoF + Hoenn dex without Jirachi/Deoxys + 5 paintings + all gold symbols = 4 stars")
eq(IDS.SYS_TOWER_SILVER, 0x860 + 0x64, "FLAG_SYS_TOWER_SILVER is SYSTEM_FLAGS + 0x64")
eq(IDS.SYS_TOWER_GOLD, 0x860 + 0x65, "FLAG_SYS_TOWER_GOLD is SYSTEM_FLAGS + 0x65")
setSymbols(true)
local c = TrainerCard.rseCardData(session())
check(c.hasAllPaintings, "five museum paintings set hasAllPaintings")
eq(c.stars, 4, "gold card")

print("[test] 2. Each criterion is worth one star")
local s = session()
for i = 9, 13 do s.contestWinners[i].species = 0 end
s.contestWinners[9].species = 1
eq(TrainerCard.rseCardData(s).stars, 3, "one painting is not enough")

s = session()
s.dex.caught[200] = nil
eq(TrainerCard.rseCardData(s).stars, 3, "a missing Hoenn mon below Jirachi drops the dex star")

s = session()
s.hofDebutHours, s.hofDebutMinutes, s.hofDebutSeconds = 0, 0, 0
eq(TrainerCard.rseCardData(s).stars, 3, "no HoF debut drops the HoF star")

Flags.setFlag(store, nil, IDS.SYS_TOWER_GOLD + 2 * 6, false)
eq(TrainerCard.rseCardData(session()).stars, 3, "a silver-only Pyramid symbol drops the frontier star")
setSymbols(false)
eq(TrainerCard.rseCardData(session()).stars, 3, "no symbols leaves HoF, dex and paintings")

if failed > 0 then
  print(string.format("[test] %d FAILED", failed))
  os.exit(1)
end
print("[test] all passed")
