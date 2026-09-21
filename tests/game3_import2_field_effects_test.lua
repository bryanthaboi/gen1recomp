#!/usr/bin/env luajit
-- pokefirered/src/data/field_effects/field_effect_objects.h:1

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

local Versions = require("src.import.gba.versions")
local FE = Versions.FIELD_EFFECTS or {}

print("[test] 1. FIELD_EFFECTS rows are not the objects they used to point at")

local EXPECT = {
  splash = { pic = 0x39AC48, pal = 0x398FA8, w = 16, h = 8, frames = 2 },
  hot_springs_water = { pic = 0x39C508, pal = 0x398FC8, w = 16, h = 16, frames = 1 },
  ripple = { pic = 0x3986A8, pal = 0x398FC8, w = 16, h = 16, frames = 5 },
  fly_bird = { pic = 0x39D3C8, pal = 0x35B968, w = 64, h = 64, frames = 5 },
  rock_smash = { pic = 0x3947A8, pal = 0x36D888, w = 16, h = 16, frames = 4 },
}

local ORDER = { "splash", "hot_springs_water", "ripple", "fly_bird", "rock_smash" }

for _, name in ipairs(ORDER) do
  check(type(FE[name]) == "table", name .. " has a FIELD_EFFECTS row")
end

check(FE.ripple and FE.ripple.pic ~= 0x398BA8, "ripple is not the arrow sheet")
check(FE.fly_bird and FE.fly_bird.pic ~= 0x398048, "fly_bird is not the small shadow")
check(FE.rock_smash and FE.rock_smash.pic ~= 0x398928, "rock_smash is not the ash sheet")

print("[test] 2. baked sheet sizes match what FieldEffects.load_sheet asks for")

local Cache = require("tests.game3_cache")
local root = Cache.root("meta.json")
if not root then
  print("[skip] cache half: " .. tostring(Cache.reason))
else
  print("[info] FireRed cache at " .. root)
  local cache = Cache.cache()
  for _, name in ipairs(ORDER) do
    local want = EXPECT[name]
    local bytes = want.w * want.h * 4 * want.frames
    local blob = cache:read(root .. "/field_effects/" .. name .. ".rgba")
    eq(blob and #blob or nil, bytes, name .. ".rgba byte size")

    local metaSrc = cache:read(root .. "/field_effects/" .. name .. ".meta")
    local meta = metaSrc and loadstring(metaSrc)
    meta = meta and meta()
    check(type(meta) == "table", name .. ".meta loads")
    if type(meta) == "table" then
      eq(meta.frames, want.frames, name .. ".meta frames")
      eq(meta.fw, want.w, name .. ".meta fw")
      eq(meta.fh, want.h, name .. ".meta fh")
      eq(meta.w, want.w, name .. ".meta sheet width")
      eq(meta.h, want.h * want.frames, name .. ".meta sheet height")
    end
  end

  print("[test] 3. the fly bird sheet is a bird, not a shadow blob")
  local blob = cache:read(root .. "/field_effects/fly_bird.rgba")
  if type(blob) == "string" then
    -- pokefirered/src/data/field_effects/field_effect_objects.h:1108
    local frameBytes = 64 * 64 * 4
    local function scan(frame)
      local base = frame * frameBytes
      local opaque, red = 0, 0
      for n = 1, 64 * 64 do
        local o = base + (n - 1) * 4
        local r, g, b, a = blob:byte(o + 1, o + 4)
        if a ~= 0 then
          opaque = opaque + 1
          if r > 150 and g < 90 and b < 90 then red = red + 1 end
        end
      end
      return opaque, red
    end
    local alone, aloneRed = scan(0)
    local ridden, riddenRed = scan(1)
    check(ridden > alone,
      "fly_bird frame 1 carries a rider frame 0 does not, got " .. tostring(ridden) .. " vs " .. tostring(alone))
    -- pokefirered/src/data/object_events/object_event_graphics_info.h:8
    check(riddenRed > 0 and aloneRed == 0,
      "fly_bird frame 1 alone carries the player's red, got " .. tostring(riddenRed) .. " / " .. tostring(aloneRed))
  end
end

if failed > 0 then
  print(string.format("[result] %d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("[result] all checks passed")
os.exit(0)
