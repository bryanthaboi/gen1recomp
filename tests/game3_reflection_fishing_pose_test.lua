package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(ok, msg)
  if not ok then
    failed = failed + 1
    print("FAIL " .. msg)
  end
end

love = love or {}
love.graphics = love.graphics or {}

local okFe, FieldEffects = pcall(require, "src.core.game3.field_effects")
local okOw, Ow = pcall(require, "src.core.game3.ow_sprites")
if not (okFe and okOw) then
  print("[skip] field effects need runtime: " .. tostring(okFe and Ow or FieldEffects))
  os.exit(0)
end

local spr = { frameCount = 18 }
local fishing = { frame = 2, x2 = 0, y2 = 8 }
package.loaded["src.core.game3.field"] = {
  fishingPose = function()
    if fishing then return fishing.frame, fishing.x2, fishing.y2 end
  end,
}

for _, facing in ipairs({ "down", "up", "left", "right" }) do
  local P = { facing = facing, fieldMoveAnim = 0 }
  local opts, x2, y2 = FieldEffects.playerReflectionPose(P, Ow)
  local frame = Ow.pose(spr, facing, 0, false, opts)
  check(frame == Ow.fishingAbsFrame(facing, fishing.frame),
    "fishing reflection facing " .. facing .. " uses the cast frame, got " .. tostring(frame))
  check(x2 == 0 and y2 == 8, "fishing reflection carries the rod offset facing " .. facing)
end

fishing = nil
local P = { facing = "down", fieldMoveAnim = 0 }
local opts, x2, y2 = FieldEffects.playerReflectionPose(P, Ow)
check(Ow.pose(spr, "down", 0, false, opts) == Ow.pose(spr, "down", 0, false, nil),
  "idle reflection keeps the standing frame")
check(x2 == 0 and y2 == 0, "idle reflection has no offset")

if failed > 0 then os.exit(1) end
print("game3_reflection_fishing_pose_test ok")
