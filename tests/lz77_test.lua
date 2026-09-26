-- Unit test for GBA LZ77 decompression
local Lz77 = require("src.import.gba.lz77")

local function test_lz77_basic()
  local payload = "HELLO WORLD, THIS IS A TEST OF GBA LZ77 COMPRESSION AND DECOMPRESSION!"
  local compressed = Lz77.compressStore(payload)
  assert(compressed[1] == 0x10, "header type 0x10")
  
  local decomp, consumed = Lz77.decompressFromBytes(compressed, 0)
  assert(#decomp == #payload, ("decomp length %d != payload %d"):format(#decomp, #payload))
  local decompStr = Lz77.toString(decomp)
  assert(decompStr == payload, "decompressed string must match original payload")
  print("✓ test_lz77_basic passed")
end

local function test_lz77_matches()
  -- Create a payload with repeated patterns to test LZ77 sliding window references
  local raw = "ABCDEFGHABCDEFGH" -- 16 bytes: 8 literals, then 1 match of length 8 at disp 8
  local bytes = {
    0x10, 16, 0, 0,
    0x00, -- flags: 8 literals
    string.byte("A"), string.byte("B"), string.byte("C"), string.byte("D"),
    string.byte("E"), string.byte("F"), string.byte("G"), string.byte("H"),
    0x80, -- flags: bit 7 is match
    0x50, 0x07, -- length=8 (0x5+3), disp=7 (goes back 7+1=8 bytes)
  }

  local decomp, consumed = Lz77.decompressFromBytes(bytes, 0)
  local decompStr = Lz77.toString(decomp)
  assert(decompStr == raw, ("expected '%s', got '%s'"):format(raw, decompStr))
  print("✓ test_lz77_matches passed")
end

local function test_lz77_bounds_safety()
  -- Corrupted match with negative / out-of-bounds displacement
  local bytes = {
    0x10, 4, 0, 0,
    0x80, -- match on first byte! read_pos = 0 - 100 < 0
    0x10, 0x64, -- length=4, disp=100
  }
  -- Should NOT crash or segfault; safely writes 0s
  local decomp, consumed = Lz77.decompressFromBytes(bytes, 0)
  assert(#decomp == 4, "should decompress 4 bytes")
  for i = 1, 4 do
    assert(decomp[i] == 0, "OOB read should produce 0")
  end
  print("✓ test_lz77_bounds_safety passed")
end

local function test_lz77_decompress_string()
  local payload = "ZERO COPY STRING DECOMPRESSION TEST PAYLOAD 1234567890ABCDEF"
  local compressed = Lz77.compressStore(payload)
  local decompStr, consumed = Lz77.decompressString(function(i) return compressed[i + 1] end, 0)
  assert(decompStr == payload, "decompressString should match original payload")
  print("✓ test_lz77_decompress_string passed")
end

local function run_all()
  test_lz77_basic()
  test_lz77_matches()
  test_lz77_bounds_safety()
  test_lz77_decompress_string()
  print("All LZ77 unit tests passed!")
end

run_all()
