package.path = "./?.lua;./?/init.lua;" .. package.path

local Doors = require("src.core.game3.doors")
local draws, rectangles = {}, {}
love = { graphics = {
  draw = function(...) draws[#draws + 1] = {...} end,
  rectangle = function(...) rectangles[#rectangles + 1] = {...} end,
  setColor = function() end,
  line = function() end,
} }

local image, quad = {}, {}
local cases = {
  { "native_defaults", 120, 56, nil, nil, 16, true },
  { "portrait_visible", 187, 398, 390, 844, 16, true },
  { "retina_portrait_visible", 139, 293, 294, 634, 16, true },
  { "landscape_visible", 400, 120, 844, 390, 16, true },
  { "survey_visible", 800, 420, 1688, 780, 32, true },
  { "native_right_edge", 239, 60, nil, nil, 16, true },
  { "native_right_offscreen", 240, 60, nil, nil, 16, false },
  { "native_bottom_offscreen", 100, 160, nil, nil, 16, false },
  { "left_partial", -15, 60, 390, 844, 16, true },
  { "left_offscreen", -16, 60, 390, 844, 16, false },
  { "right_offscreen", 390, 60, 390, 844, 16, false },
  { "tall_top_partial", 100, -15, 390, 844, 32, true },
  { "tall_top_offscreen", 100, -16, 390, 844, 32, false },
  { "tall_bottom_partial", 100, 859, 390, 844, 32, true },
  { "tall_bottom_offscreen", 100, 860, 390, 844, 32, false },
}

local failures = 0
for _, t in ipairs(cases) do
  draws, rectangles = {}, {}
  Doors._sheets.Test = {
    image = image, quads = { [1] = quad }, frames = 3,
    frame_width = 16, frame_height = t[6],
  }
  Doors._activeAnim = { x = 73, y = 91, tile = "Test", frame = 1 }
  Doors.draw(73 * 16 - t[2], 91 * 16 - t[3], t[4], t[5])
  local ok = #draws == (t[7] and 1 or 0) and #rectangles == (t[7] and 1 or 0)
  if t[7] and draws[1] then
    local d = draws[1]
    ok = ok and d[1] == image and d[2] == quad and d[3] == t[2]
      and d[4] == t[3] - (t[6] > 16 and 16 or 0)
  end
  print((ok and "PASS " or "FAIL ") .. t[1])
  if not ok then failures = failures + 1 end
end

draws, rectangles = {}, {}
Doors._sheets.Test = false
Doors._activeAnim = { x = 25, y = 30, tile = "Test", frame = 1 }
Doors.draw(0, 0, 844, 780)
assert(#draws == 0 and #rectangles > 0, "fallback on enlarged viewport")
print("PASS fallback_visible")
assert(failures == 0, tostring(failures) .. " viewport cases failed")
print("PASS doors_viewport")
