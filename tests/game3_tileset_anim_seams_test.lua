package.path = "./?.lua;./?/init.lua;" .. package.path

local Native = require("src.core.game3.tileset_native")
local Anim = require("src.core.game3.tileset_anim")
local Versions = require("src.import.gba.versions")
Versions.NATIVE_RENDER, Versions.TILESET_ANIM = true, true
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end
local reads = {}
local cache = { read = function(_, path)
  reads[path] = (reads[path] or 0) + 1
  if path:find("/missing/", 1, true) then return nil end
  if path:match("manifest.lua$") then
    return "return {water={mids={1},frames=8},sand={mids={2},frames=8},flower={mids={3},frames=5}}"
  end
  local frames = path:find("flower", 1, true) and 5 or 8
  local rgba = {}
  for i = 0, frames - 1 do rgba[#rgba + 1] = string.rep(string.char(i, 0, 0, 255), 256) end
  return table.concat(rgba)
end }
local function atlas(pair)
  local data = { pixels = {}, setPixel = function(self, x, y, r)
    if y == 0 then self.pixels[x] = math.floor(r * 255 + 0.5) end
  end }
  local image = { uploads = 0, pixels = {}, replacePixels = function(self, pixels)
    self.uploads = self.uploads + 1
    for x, value in pairs(pixels.pixels) do self.pixels[x] = value end
  end }
  local ts = { imageData = data, image = image, cols = 3, midToSlot = { [1] = 0, [2] = 1, [3] = 2 } }
  Native._pairs[pair] = ts
  return ts
end
local function tick(n) for _ = 1, n do Anim.step() end end
Native.install(cache)
local a, b = atlas("a"), atlas("b")
Native.get("a")
Native.get("b")
tick(33)
check(a.image.pixels[0] == 2 and b.image.pixels[0] == 2,
  "both_visible_atlases_upload_water_frame2")
for _ = 1, 20 do Native.get("a"); Native.get("b") end
check(Anim.counter == 33 and a.image.pixels[0] == 2 and b.image.pixels[0] == 2,
  "cached_get_preserves_general_clock_and_pixels")
local c = atlas("c")
Native.get("c")
check(c.image.pixels[0] == 2 and c.image.pixels[16] == 4 and c.image.pixels[32] == 1,
  "new_pair_uploads_current_general_phases")
atlas("missing")
for _ = 1, 5 do Native.get("missing") end
tick(1)
check(a.image.pixels[32] == 2 and b.image.pixels[32] == 2,
  "missing_manifest_does_not_stop_visible_animation")
local bounded = true
for _, count in pairs(reads) do if count ~= 1 then bounded = false end end
check(bounded, "manifest_and_banks_read_once_per_pair")
if Anim.setVisiblePairs then Anim.setVisiblePairs({ a = true, b = true }) end
local uploads = c.image.uploads
tick(31)
check(c.image.uploads == uploads and a.image.pixels[0] == 4 and b.image.pixels[0] == 4,
  "offscreen_atlas_receives_no_uploads")
Native.get("c")
check(c.image.pixels[0] == 4, "returning_atlas_catches_up_before_draw")
tick(640 - Anim.counter)
check(Anim.counter == 0 and a.image.pixels[16] == 0 and a.image.pixels[0] == 7,
  "general_timer_wrap_keeps_pret_cadence")
tick(1)
check(a.image.pixels[0] == 0, "water_wrap_uploads_on_tick1")
tick(1)
check(a.image.pixels[32] == 0, "flower_wrap_uploads_on_tick2")
local before = a.image.uploads
Native.invalidate()
tick(33)
check(a.image.uploads == before and next(Native._pairs) == nil,
  "invalidate_releases_old_atlases")
Native.install(cache)
local fresh = atlas("fresh")
Native.get("fresh")
check(Anim.counter == 0 and fresh.image.pixels[0] == 0 and a.image.uploads == before,
  "install_starts_fresh_without_old_references")
os.exit(failures == 0 and 0 or 1)
