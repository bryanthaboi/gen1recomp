local sizes = require("src.core.game3.battle.anim_port.g1_pic_sizes")

local function convert(packed)
  local w = math.floor(packed / 256)
  local h = packed % 256
  return (w / 8) * 16 + h / 8
end

local OUT = { front = {}, back = {} }
for sp, packed in pairs(sizes.front or {}) do OUT.front[sp] = convert(packed) end
for sp, packed in pairs(sizes.back or {}) do OUT.back[sp] = convert(packed) end

return OUT
