-- A corrupt mids.idx must not be trusted for its table sizes.
--
-- N-E3 regression: NativePack.decodeIdx read midCount / atlasCols / atlasRows
-- straight out of the u16 header, then looped `midCount * 256` bytes and, via
-- bake_or_load, sized its buffers from `atlasCols x atlasRows`.  With u16 maxima
-- that is a ~4 TB allocation; short of that it raised inside the pixel loop
-- (read_u16 does not bounds-check).  The file lives in the user-writable cache.
--   luajit tests/engine/game3_mids_idx_bounds_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local NativePack = require("src.import.gba.native_pack")

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end

-- 12-byte header: MAGIC(4) + version + flags + midCount + atlasCols + atlasRows
local function header(midCount, cols, rows)
  return NativePack.MAGIC_IDX .. string.char(NativePack.FORMAT_VERSION, 0)
    .. u16(midCount) .. u16(cols) .. u16(rows)
end

-- 1. An impossible mid count with no table data must be rejected, not raise.
local ok1, res1 = pcall(NativePack.decodeIdx, header(65535, 16, 16))
check(ok1, "decodeIdx does not raise on an impossible mid count")
check(res1 == nil, "...it rejects it")

-- 2. An impossible atlas must be rejected (it would size a ~4 TB buffer).
local ok2, res2 = pcall(NativePack.decodeIdx, header(1, 65535, 65535))
check(ok2, "decodeIdx does not raise on an impossible atlas")
check(res2 == nil, "...it rejects it")

-- 3. A blob shorter than its declared tables must be rejected.
local ok3, res3 = pcall(NativePack.decodeIdx, header(4, 16, 4))
check(ok3, "decodeIdx does not raise on a truncated blob")
check(res3 == nil, "...it rejects it")

-- 4. Regression guard: a well-formed idx still decodes.
local good = header(2, 16, 2) .. u16(1) .. u16(2) .. string.rep("\0", 2 * 256)
local decoded = NativePack.decodeIdx(good)
check(type(decoded) == "table", "a well-formed idx decodes")
if type(decoded) == "table" then
  eq(decoded.midCount, 2, "...with its mid count")
  eq(decoded.atlasCols, 16, "...and atlas columns")
  eq(decoded.atlasRows, 2, "...and atlas rows")
  eq(decoded.midIds[2], 2, "...and its mid ids")
end

T.finish("game3_mids_idx_bounds_test")
