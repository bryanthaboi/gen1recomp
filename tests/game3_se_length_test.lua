#!/usr/bin/env luajit
-- pokefirered/src/battle_anim_special.c:1200

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

local function find_pack_root()
  local candidates = { "data/generated/gba/audio" }
  local home = os.getenv("HOME")
  local identity = os.getenv("POKEPORT_IDENTITY")
  if home then
    local bases = {}
    if identity then bases[#bases + 1] = identity end
    bases[#bases + 1] = "firered-sep20"
    for _, base in ipairs(bases) do
      candidates[#candidates + 1] =
        home .. "/Library/Application Support/LOVE/" .. base .. "/firered/data/generated/gba/audio"
      candidates[#candidates + 1] =
        home .. "/.local/share/love/" .. base .. "/firered/data/generated/gba/audio"
    end
  end
  for _, root in ipairs(candidates) do
    local f = io.open(root .. "/index.lua", "rb")
    if f then f:close(); return root end
  end
  return nil
end

local root = find_pack_root()
if not root then
  print("[skip] no imported FireRed audio pack; nothing to measure")
  os.exit(0)
end
print("[test] pack at " .. root)

local cache = { read = function(_, rel)
  local f = io.open(rel, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end }

local Player = require("src.core.game3.m4a_player")
local Mix = require("src.core.game3.m4a_mix")
local Audio = require("src.core.game3.audio")

local pack, err = Player.loadPack(cache, root)
if not pack then
  print("[skip] loadPack failed: " .. tostring(err))
  os.exit(0)
end

local function bake_seconds(id, maxSec)
  local slot = { voices = {} }
  if not Player.start(pack, cache, slot, id, { forceSeq = true }) then return nil end
  local L = Player.bakeSlot(slot, { raw = true, maxSec = maxSec, stopOnGoto = false })
  return #L / Mix.SAMPLE_RATE
end

-- pokefirered/src/m4a_1.s:751
local longest, longestId = 0, nil
for id = 0, 400 do
  local info = Player.songInfo(pack, id)
  if info and info.kind == "se" and not info.hasGoto then
    local s = bake_seconds(id, 60)
    if s and s > longest then longest, longestId = s, id end
  end
end
check(longest > 0, "measured the pack's one-shot SE cues")
check((tonumber(Audio.SE_ONESHOT_MAX_SEC) or 0) > longest,
  string.format("SE_ONESHOT_MAX_SEC %.1fs clears the longest one-shot (id %s, %.3fs)",
    Audio.SE_ONESHOT_MAX_SEC or -1, tostring(longestId), longest))
check(Audio.SE_LOOP_MAX_SEC == 2.5, "looping cues keep pret's 2.5s slice")

Audio._ready = true
Audio._pack = pack
Audio._cache = cache
local realBake = Player.bakeSlot
local function production_max(id)
  local seen = nil
  Player.bakeSlot = function(slot, opts) seen = opts and opts.maxSec; return { 0 }, { 0 } end
  Audio._seRawClear()
  pcall(Audio.playSe, id)
  Player.bakeSlot = realBake
  Audio._seRawClear()
  return seen
end
local prodMax = production_max(319)
check(type(prodMax) == "number", "Audio.playSe passes a numeric maxSec (" .. tostring(prodMax) .. ")")

-- pokefirered/src/battle_anim_special.c:1200
local SE = require("src.core.game3.se_ids")
check(production_max(SE.SE_EXP) == Audio.SE_LOOP_MAX_SEC,
  "SE_EXP keeps the 2.5s slice (" .. tostring(production_max(SE.SE_EXP)) .. ")")
check(production_max(SE.SE_LOW_HEALTH) == Audio.SE_LOOP_MAX_SEC,
  "SE_LOW_HEALTH keeps the 2.5s slice (" .. tostring(production_max(SE.SE_LOW_HEALTH)) .. ")")

-- pokefirered/include/constants/songs.h:89, :102, :284
local CUES = { 319, 165, 204, 227, 249, 276, 85, 98 }
for _, id in ipairs(CUES) do
  local natural = bake_seconds(id, 60)
  local idMax = production_max(id)
  local production = idMax and bake_seconds(id, idMax)
  if not natural then
    print("[skip] id " .. id .. " not in this pack")
  else
    check(production and math.abs(production - natural) <= 1 / 60,
      string.format("id %d bakes in full (%.3fs production vs %.3fs natural)",
        id, production or -1, natural))
  end
end

local bakes = 0
Player.bakeSlot = function(slot, opts) bakes = bakes + 1; return realBake(slot, opts) end
Audio._seRawClear()
for _ = 1, 3 do pcall(Audio.playSe, 319) end
check(bakes == 1, "MUS_CAUGHT_INTRO bakes once across three plays (" .. bakes .. ")")
local entry = Audio._seRaw[319]
check(entry and entry.frames / Mix.SAMPLE_RATE >= 4.5,
  string.format("memoized buffer is the full cue (%.3fs)", entry and entry.frames / Mix.SAMPLE_RATE or -1))
bakes = 0
pcall(Audio.playSe, 319, { maxSec = 1 })
check(bakes == 1 and Audio._seRaw[319] == entry, "an explicit maxSec bypasses the memo")
local budget = Audio.SE_RAW_MAX_FRAMES
Audio.SE_RAW_MAX_FRAMES = entry and entry.frames + 1 or budget
pcall(Audio.playSe, 5)
check(Audio._seRaw[5] ~= nil and Audio._seRaw[319] == nil
    and Audio._seRawFrames <= Audio.SE_RAW_MAX_FRAMES,
  "memo evicts least-recent cue at the frame budget (" .. tostring(Audio._seRawFrames) .. ")")
Audio.SE_RAW_MAX_FRAMES = budget
Audio._seRawClear()
Player.bakeSlot = realBake

local caught = bake_seconds(319, prodMax)
check(caught and caught >= 4.5,
  string.format("MUS_CAUGHT_INTRO is at least 4.5s (%.3fs)", caught or -1))

if failed > 0 then
  print(string.format("\n%d check(s) failed", failed))
  os.exit(1)
end
print("\nall SE length checks passed")
