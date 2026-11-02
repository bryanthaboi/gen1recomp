#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local SE = require("src.core.game3.se_ids")
local Audio = require("src.core.game3.audio")
local BallOpen = require("src.core.game3.battle.ball_open")
local CatchSeq = require("src.core.game3.battle.catch_seq")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local CB = CatchSeq._cb
check(type(CB) == "table" and type(CB.doClick) == "function", "catch_seq exposes CB.doClick")
if failed > 0 then os.exit(1) end

local played, spawns, fades = {}, {}, {}
Audio.playSe = function(id) played[#played + 1] = id end
Audio.stopAll = function() end
BallOpen.spawnSprite = function(x, y)
  local p = { x = x, y = y, data = {} }
  spawns[#spawns + 1] = p
  return p
end
BallOpen.beginFade = function(...) fades[#fades + 1] = { ... } end

local function run(version, ticks)
  SE.select(version)
  played, spawns, fades = {}, {}, {}
  local b = { data = { [0] = 0, 0, 0, 0, 0, 0, 0, 0 }, blend = {}, x = 120, y = 60, mon = {} }
  b.cb = CB.doClick
  local seAt = {}
  for t = 1, ticks do
    local before = #played
    local ok, err = pcall(CB.doClick, b)
    if not ok then return nil, err end
    if #played > before then seAt[#seAt + 1] = t end
  end
  return { seAt = seAt, played = played, spawns = #spawns, fades = #fades, coeff = b.blend.coeff }
end

for _, v in ipairs({ "ruby", "sapphire" }) do
  local r, err = run(v, 94)
  check(r ~= nil, v .. ": doClick runs ticks 1-94 without error " .. tostring(err or ""))
  if r then
    -- pokeruby/src/battle_anim_special.c:1130
    check(#r.played == 0, v .. ": no SE through tick 94 (got " .. #r.played .. ")")
    check(r.coeff == nil, v .. ": no capture blend at tick 40")
    check(r.spawns == 0, v .. ": no capture stars at tick 40 (got " .. r.spawns .. ")")
    check(r.fades == 0, v .. ": no tick-60 fade (got " .. r.fades .. ")")
  end
end

local CLICK = { firered = "SE_BALL_CLICK", leafgreen = "SE_BALL_CLICK", emerald = "SE_RG_BALL_CLICK" }
for _, v in ipairs({ "firered", "leafgreen", "emerald" }) do
  local r, err = run(v, 94)
  check(r ~= nil, v .. ": doClick runs ticks 1-94 without error " .. tostring(err or ""))
  if r then
    SE.select(v)
    check(#r.seAt == 1 and r.seAt[1] == 40 and r.played[1] == SE[CLICK[v]],
      v .. ": " .. CLICK[v] .. " once at tick 40")
    check(r.coeff == 6, v .. ": capture blend coeff 6 at tick 40")
    check(r.spawns == 3, v .. ": three capture stars at tick 40")
    check(r.fades == 1, v .. ": one fade at tick 60")
  end
end
SE.select("firered")

if failed > 0 then
  print(failed .. " FAIL")
  os.exit(1)
end
print("PASS ruby and sapphire skip the capture click, blend, stars and tick-60 fade")
