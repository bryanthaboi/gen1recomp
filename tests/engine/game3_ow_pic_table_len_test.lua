-- pokefirered/src/data/object_events/object_event_pic_tables.h

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local OwExtract = require("src.import.gba.ow_extract")

local SIZE = 0x4000
local bytes = {}
for i = 0, SIZE - 1 do bytes[i] = 0 end
local function w16(o, v) bytes[o] = v % 256; bytes[o + 1] = math.floor(v / 256) % 256 end
local function w32(o, v) w16(o, v % 65536); w16(o + 2, math.floor(v / 65536)) end
local function ptr(o) return 0x08000000 + o end

local POINTERS, INFOS, ANIMS, PICS, GFX = 0x100, 0x200, 0x300, 0x800, 0x2000
local STRIDE = 0x24

local ANIM0, ANIM_RAISE = ANIMS + 0x100, ANIMS + 0x120
w32(ANIM0, 0x00100000); w16(ANIM0 + 4, 0xFFFE); w16(ANIM0 + 6, 0)
w32(ANIM_RAISE, 0x00100009); w16(ANIM_RAISE + 4, 0xFFFF)
for i = 0, 19 do w32(ANIMS + i * 4, ptr(ANIM0)) end
w32(ANIMS + 20 * 4, ptr(ANIM_RAISE))

local tables = {
  { frames = 9, w = 16, h = 32 },
  { frames = 9, w = 16, h = 32, unreferenced = true },
  { frames = 10, w = 16, h = 32 },
  { frames = 4, w = 16, h = 16, inanimate = true },
}
local at = PICS
for _, t in ipairs(tables) do
  t.off = at
  local fb = t.w * t.h / 2
  for f = 0, t.frames - 1 do
    w32(at, ptr(GFX + f * fb)); w16(at + 4, fb)
    at = at + 8
  end
end

local slot, gid = 0, 0
for _, t in ipairs(tables) do
  local info = INFOS + slot * STRIDE
  w16(info, 0xFFFF)
  w16(info + 6, t.w * t.h / 2)
  w16(info + 8, t.w); w16(info + 10, t.h)
  bytes[info + 12] = t.inanimate and 0x40 or 0
  w32(info + 0x18, ptr(ANIMS))
  w32(info + 0x1C, ptr(t.off))
  if not t.unreferenced then
    w32(POINTERS + gid * 4, ptr(info))
    t.gid = gid
    gid = gid + 1
  end
  slot = slot + 1
end

local chars = {}
for i = 0, SIZE - 1 do chars[i + 1] = string.char(bytes[i]) end
local data = table.concat(chars)
local rom = { size = SIZE }
function rom:get(o) return data:byte(o + 1) end
function rom:u16(o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom:u32(o) local a, b, c, d = data:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
function rom:readBytes(o, n) return data:sub(o + 1, o + n) end

local version = { ow_gfx_pointers = POINTERS, num_obj_event_gfx = gid }

local s0 = OwExtract.extractOne(rom, tables[1].gid, nil, version)
eq(s0 and s0.frameCount, 9,
  "9-frame table stops at the next table even though the anim table reaches frame 9")
local s1 = OwExtract.extractOne(rom, tables[3].gid, nil, version)
eq(s1 and s1.frameCount, 10, "10-frame table keeps its RaiseHand frame")
local s2 = OwExtract.extractOne(rom, tables[4].gid, nil, version)
eq(s2 and s2.frameCount, 4, "inanimate multi-frame table keeps every frame")
check(s0 and #s0.frames == 9, "frame pixels decoded for each table entry only")

T.finish("game3_ow_pic_table_len_test")
