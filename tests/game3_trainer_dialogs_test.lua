#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print(string.format("[FAIL] %s (%s ~= %s)", msg, tostring(a), tostring(b)))
  end
end

local TrainerExtract = require("src.import.gba.trainer_extract")

local text = {
  first = { { t = "text", s = "FIRST" } },
  again = { { t = "text", s = "AGAIN" } },
}

local function battle(kind, intro)
  return { { op = "trainerbattle", trainer = 89, type = kind, introText = intro } }
end

print("[test] first battle beats rematch whatever the key order")
for _, keys in ipairs({ { "g3:0a", "g3:0b" }, { "g3:0b", "g3:0a" } }) do
  local scripts = {}
  scripts[keys[1]] = battle(0, "first")
  scripts[keys[2]] = battle(5, "again")
  local d = TrainerExtract.extractDialogs(scripts, text)
  eq(d[89].scriptKey, keys[1], "single battle script wins")
  eq(d[89].introKey, "first", "single battle intro wins")
end

print("[test] ties resolve to the lowest script key")
do
  local scripts = {}
  for i = 1, 40 do scripts[string.format("g3:%04x", 0x100 - i)] = battle(0, "first") end
  local d = TrainerExtract.extractDialogs(scripts, text)
  eq(d[89].scriptKey, string.format("g3:%04x", 0x100 - 40), "lowest key")
end

print("[test] rematch-only trainers still bind")
do
  local d = TrainerExtract.extractDialogs({ ["g3:0c"] = battle(7, "again") }, text)
  eq(d[89].scriptKey, "g3:0c", "rematch double kept")
end

if failed > 0 then
  print(failed .. " failed")
  os.exit(1)
end
print("all passed")
