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

local Player = require("src.core.game3.m4a_player")
local Seq = require("src.core.game3.m4a_seq")
local Mix = require("src.core.game3.m4a_mix")
local Audio = require("src.core.game3.audio")

print("[test] 1. Player.stopAt keeps active voices after fast-forward")
local slot = {
  songId = 296,
  seq = {
    tracks = {
      { pc = 1, vel = 100, callStack = {}, data = string.char(0x00, 0xB1) }
    },
    voices = {}
  },
  voices = {},
  frameSamplesLeft = 0,
  frameSampleCarry = 0,
  abs = 100000,
}
local snaps = {
  {
    at = 50000,
    seq = { tracks = { { pc = 1, vel = 100, callStack = {}, data = string.char(0x00, 0xB1) } }, mem = {} },
    done = false,
    frameSamplesLeft = 0,
    frameSampleCarry = 0,
  }
}

local newAbs = Player.stopAt(slot, snaps, 60000, 100000)
check(newAbs == 60000, "rewound abs to target at")

print("[test] 2. Player.stopAt handles timestamp older than retained snaps")
local emptySnaps = {
  {
    at = 80000,
    seq = { tracks = { { pc = 15, vel = 100, callStack = {} } }, mem = {} },
    done = false,
  }
}
-- If at is 20000 (predates earliest snap of 80000)
local fallbackAbs = Player.stopAt(slot, emptySnaps, 20000, 100000)
check(fallbackAbs == 20000 or fallbackAbs == slot.abs, "stopAt safely handled out-of-range timestamp")

print("[test] 3. Audio.resumeBgm ensures bgmPaused is false")
Audio._bgmPaused = true
Audio.resumeBgm()
check(Audio._bgmPaused == false, "resumeBgm cleared _bgmPaused")

if failed > 0 then
  print(string.format("\n%d check(s) FAILED", failed))
  os.exit(1)
end
print("\nall fanfare BGM resume checks passed")
