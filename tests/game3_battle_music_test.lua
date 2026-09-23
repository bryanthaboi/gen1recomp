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

local Trainers = require("src.core.game3.scripting.trainers")

Trainers._pack = {
  classNames = { [84] = "LEADER", [87] = "ELITE FOUR", [90] = "CHAMPION", [47] = "YOUNGSTER" },
  trainers = {
    [414] = { class = 84, name = "BROCK", pic = 0, party = {} },
    [410] = { class = 87, name = "LORELEI", pic = 0, party = {} },
    [438] = { class = 90, name = "TERRY", pic = 0, party = {} },
    [102] = { class = 47, name = "BEN", pic = 0, party = {} },
  },
}

print("[test] 1. Battle BGM role by trainer class")
local function battle(id)
  local role, song = Trainers.getBattleMusicRole(id)
  return role, song
end

local role, song = battle(414)
eq(role, "battleGymLeader", "LEADER BROCK role")
eq(song, 296, "LEADER BROCK song (MUS_VS_GYM_LEADER)")

role, song = battle(410)
eq(role, "battleGymLeader", "ELITE FOUR LORELEI role")
eq(song, 296, "ELITE FOUR LORELEI song (MUS_VS_GYM_LEADER)")

role, song = battle(438)
eq(role, "battleChampion", "CHAMPION TERRY role")
eq(song, 299, "CHAMPION TERRY song (MUS_VS_CHAMPION)")

role, song = battle(102)
eq(role, "battleTrainer", "YOUNGSTER role")
eq(song, 297, "YOUNGSTER song (MUS_VS_TRAINER)")

role, song = battle(nil)
eq(role, "battleTrainer", "nil trainer falls back to trainer BGM")
eq(song, 297, "nil trainer song")

print("[test] 2. Victory jingle role by trainer class")
local function victory(id)
  local r, s = Trainers.getVictoryMusicRole(id)
  return r, s
end

role, song = victory(414)
eq(role, "victoryGymLeader", "LEADER BROCK victory role")
eq(song, 312, "LEADER BROCK victory song (MUS_VICTORY_GYM_LEADER)")

role, song = victory(438)
eq(role, "victoryGymLeader", "CHAMPION TERRY victory role")
eq(song, 312, "CHAMPION TERRY victory song (MUS_VICTORY_GYM_LEADER)")

role, song = victory(410)
eq(role, "victoryTrainer", "ELITE FOUR victory role")
eq(song, 310, "ELITE FOUR victory song (MUS_VICTORY_TRAINER)")

role, song = victory(102)
eq(role, "victoryTrainer", "YOUNGSTER victory role")
eq(song, 310, "YOUNGSTER victory song (MUS_VICTORY_TRAINER)")

print("[test] 3. Trainers.info still publishes the numeric class key")
local info = Trainers.info(414)
check(info ~= nil, "info(414) resolves")
eq(info and info.class, 84, "info.class preserved for prize.lua and friends")

print("[test] 4. Live cache trainer classes (skipped when no cache)")
local cacheRoot = require("tests.game3_cache").root("trainers.lua")
local fh = cacheRoot and io.open(cacheRoot .. "/trainers.lua", "r")
if fh then
  local src = fh:read("*a")
  fh:close()
  local chunk = load(src, "@trainers.lua", "t", {})
  local okp, pack = pcall(chunk)
  if okp and type(pack) == "table" and pack.trainers then
    Trainers._pack = pack
    eq(select(2, Trainers.getBattleMusicRole(414)), 296, "cache: BROCK -> 296")
    eq(select(2, Trainers.getBattleMusicRole(410)), 296, "cache: LORELEI -> 296")
    eq(select(2, Trainers.getBattleMusicRole(438)), 299, "cache: TERRY -> 299")
    eq(select(2, Trainers.getBattleMusicRole(350)), 296, "cache: GIOVANNI -> 296")
    eq(select(2, Trainers.getVictoryMusicRole(414)), 312, "cache: BROCK victory -> 312")
    eq(select(2, Trainers.getVictoryMusicRole(410)), 310, "cache: LORELEI victory -> 310")
  else
    print("[skip] cache trainers.lua did not load")
  end
else
  print("[skip] no current FireRed cache")
end

if failed > 0 then
  print(string.format("\n%d check(s) FAILED", failed))
  os.exit(1)
end
print("\nall battle music checks passed")
