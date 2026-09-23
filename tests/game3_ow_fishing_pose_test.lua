#!/usr/bin/env luajit
-- pokefirered/src/data/object_events/object_event_anims.h:877
-- pokefirered/src/field_player_avatar.c:1954 AlignFishingAnimationFrames

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

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local OwSprites = require("src.core.game3.ow_sprites")

local function pose(spr, facing, opts)
  local f, flip = OwSprites.pose(spr, facing, 0, false, opts)
  return f, flip
end

print("[test] 1. fishing sheet layout W 0-3 / N 4-7 / S 8-11, east = west hflip")
for _, n in ipairs({ 12, 18 }) do
  local spr = { frameCount = n, quads = {} }
  local want = {
    { "down", 3, 11, false }, { "up", 3, 7, false },
    { "left", 3, 3, false }, { "right", 3, 3, true },
    { "down", 0, 8, false }, { "up", 0, 4, false },
    { "left", 0, 0, false }, { "right", 0, 0, true },
  }
  for _, w in ipairs(want) do
    local f, flip = pose(spr, w[1], { fishing = true, fishFrame = w[2] })
    check(f == w[3] and flip == w[4], string.format(
      "frameCount %d %s fishFrame %d -> %d%s (got %s%s)", n, w[1], w[2], w[3],
      w[4] and " hflip" or "", tostring(f), flip and " hflip" or ""))
  end
end

print("[test] 2. take-out / hooked / put-away timelines")
local function seq(facing, anim, upTo)
  local out = {}
  for t = 0, upTo do out[#out + 1] = (OwSprites.fishingFrame(facing, anim, t)) end
  return table.concat(out, ",")
end
check(seq("down", "takeout", 17) == "0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,3,3",
  "take-out rod: 0,1,2,3 at 4 ticks, then holds 3")
local _, ended = OwSprites.fishingFrame("down", "takeout", 500)
check(ended == true and (OwSprites.fishingFrame("down", "takeout", 500)) == 3,
  "take-out holds the last frame through the dot game")
local sn = {}
for t = 0, 21 do sn[#sn + 1] = (OwSprites.fishingFrame("up", "putaway", t)) end
check(table.concat(sn, ",") == "3,3,3,3,2,2,2,2,2,2,1,1,1,1,1,1,0,0,0,0,0,0",
  "put away north/south: 3@4, 2@6, 1@6, 0@6")
local _, e21 = OwSprites.fishingFrame("up", "putaway", 21)
local _, e22 = OwSprites.fishingFrame("up", "putaway", 22)
check(e21 == false and e22 == true, "north/south put-away ends after 22 ticks")
local _, w15 = OwSprites.fishingFrame("left", "putaway", 15)
local _, w16 = OwSprites.fishingFrame("right", "putaway", 16)
check(w15 == false and w16 == true, "west/east put-away ends after 16 ticks")
check((OwSprites.fishingFrame("down", "hooked", 0)) == 2
  and (OwSprites.fishingFrame("down", "hooked", 6)) == 3
  and (OwSprites.fishingFrame("down", "hooked", 12)) == 2
  and (OwSprites.fishingFrame("down", "hooked", 18)) == 3
  and (OwSprites.fishingFrame("down", "hooked", 53)) == 3
  and (OwSprites.fishingFrame("down", "hooked", 54)) == 2,
  "hooked: 2,3 twice at 6 ticks, hold 3 for 30, then loop")

print("[test] 3. AlignFishingAnimationFrames offsets")
local function off(abs, facing)
  local x2, y2 = OwSprites.fishingOffset(abs, facing)
  return x2 .. "," .. y2
end
check(off(0, "left") == "0,0", "frame 0: no offset")
check(off(3, "left") == "-8,0", "frame 3 facing west: x2 -8")
check(off(3, "right") == "8,0", "frame 3 facing east: x2 +8")
check(off(1, "right") == "8,0" and off(2, "left") == "-8,0", "frames 1-2 shift sideways")
check(off(4, "up") == "0,0" and off(5, "up") == "0,-8" and off(7, "up") == "0,0",
  "north: only frame 5 lifts 8")
check(off(9, "down") == "0,0" and off(10, "down") == "0,8" and off(11, "down") == "0,8",
  "south: frames 10-11 drop 8")

print("[test] 4. field move is sAnim_FieldMove 0-4, south only, never flipped")
local item = { frameCount = 18, quads = {} }
for _, facing in ipairs({ "down", "up", "left", "right" }) do
  local f, flip = pose(item, facing, { fieldMove = true })
  check(f == 4 and flip == false, facing .. " holds frame 4, no flip (got " .. tostring(f) .. ")")
end
local fm = {}
for t = 0, 20 do fm[#fm + 1] = OwSprites.fieldMoveFrame(t) end
check(table.concat(fm, ",") == "0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,4",
  "field move 0,1,2,3 at 4 ticks then 4")
local vs = {}
for t = 0, 88, 4 do vs[#vs + 1] = OwSprites.fieldMoveFrame(t, "vs_seeker") end
check(table.concat(vs, ",") == "0,1,5,6,7,8,7,8,7,8,7,8,7,8,7,8,7,8,6,1,0,0,0",
  "VS Seeker: 0,1,5,6, (7,8)x7, 6,1,0")

print("[test] 4b. VS Seeker on a bike uses gid 6/13 and sAnim_VSSeekerBike")
local vb = {}
for t = 0, 92, 4 do vb[#vb + 1] = OwSprites.fieldMoveFrame(t, "vs_seeker_bike") end
check(table.concat(vb, ",") == "0,1,2,3,4,5,4,5,4,5,4,5,4,5,4,5,4,5,3,2,1,0,0,0",
  "VS Seeker bike: 0,1,2,3, (4,5)x7, 3,2,1,0 (got " .. table.concat(vb, ",") .. ")")
local bikeSheet = { frameCount = 6, quads = {} }
for _, facing in ipairs({ "down", "up", "left", "right" }) do
  local f, flip = pose(bikeSheet, facing, { fieldMove = true, fieldMoveFrame = 5 })
  check(f == 5 and flip == false, "bike VS Seeker sheet " .. facing .. " frame 5, no flip (got "
    .. tostring(f) .. (flip and " hflip" or "") .. ")")
end
do
  local P = require("src.core.game3.player")
  local VsSeeker = require("src.core.game3.vs_seeker")
  local saved = { P.fieldMoveAnim, P.fieldMoveTotal, P.fieldMoveKind, P.biking }
  local function gid(gender)
    return OwSprites.playerGraphicsId({ session = { gender = gender } })
  end
  P.biking = true
  P.startFieldMove(VsSeeker.EFFECT_FRAMES, P.biking and "vs_seeker_bike" or "vs_seeker")
  check(gid("male") == 6, "male on bike using VS Seeker draws gid 6 (got " .. tostring(gid("male")) .. ")")
  check(gid("female") == 13, "female on bike using VS Seeker draws gid 13 (got " .. tostring(gid("female")) .. ")")
  P.biking = false
  P.startFieldMove(VsSeeker.EFFECT_FRAMES, "vs_seeker")
  check(gid("male") == 3 and gid("female") == 10, "on foot VS Seeker keeps the item sheet 3/10")
  P.fieldMoveAnim, P.fieldMoveTotal, P.fieldMoveKind, P.biking = saved[1], saved[2], saved[3], saved[4]
end
do
  local src = io.open("src/core/game3/vs_seeker.lua"):read("*a")
  check(src:find('"vs_seeker_bike"', 1, true) ~= nil and src:find("Player.biking", 1, true) ~= nil,
    "vs_seeker.lua picks the bike anim from Player.biking")
end

print("[test] 5. Field.fishingPose drives the pose from the task")
local okF, Field = pcall(require, "src.core.game3.field")
local Player = require("src.core.game3.player")
if okF and Field and Field.fishingPose then
  Field._fishing = nil
  Player.fishing = false
  Field.startFishing(0)
  Player.facing = "down"
  local g, x2, y2 = Field.fishingPose()
  check(g == 0 and x2 == 0 and y2 == 0, "cast starts on frame 8 with no offset")
  Field._fishing.animT = 12
  g, x2, y2 = Field.fishingPose()
  check(g == 3 and x2 == 0 and y2 == 8, "facing south, frame 11 drops 8")
  Player.facing = "left"
  g, x2, y2 = Field.fishingPose()
  check(g == 3 and x2 == -8 and y2 == 0, "facing west, frame 3 shifts -8")
  Player.facing = "up"
  Field._fishing.animT = 5
  g, x2, y2 = Field.fishingPose()
  check(g == 1 and x2 == 0 and y2 == -8, "facing north, frame 5 lifts 8")
  Field._fishing = nil
  Player.fishing = false
  check(Field.fishingPose() == nil, "no pose once fishing ends")
else
  check(false, "src.core.game3.field loads: " .. tostring(Field))
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
