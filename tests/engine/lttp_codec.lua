package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Lz2 = require("src.import.lttp.Lz2")
local SnesGfx = require("src.import.lttp.SnesGfx")
local LttpImport = require("src.import.lttp.LttpImport")

local function bytes(...)
  local out = {}
  for _, v in ipairs({ ... }) do out[#out + 1] = string.char(v) end
  return table.concat(out)
end

do
  local stream = bytes(0x02, 0x41, 0x42, 0x43, 0xFF)
  local out = Lz2.decompress(stream, 0)
  T.eq(out, "ABC", "direct copy emits the literal run")

  out = Lz2.decompress(bytes(0x23, 0xAB, 0xFF), 0)
  T.eq(#out, 4, "byte fill emits length+1 bytes")
  T.eq(out, string.rep(string.char(0xAB), 4), "and every byte is the fill")

  out = Lz2.decompress(bytes(0x44, 0x11, 0x22, 0xFF), 0)
  T.eq(out, bytes(0x11, 0x22, 0x11, 0x22, 0x11),
    "word fill alternates the pair and stops mid-pair")

  out = Lz2.decompress(bytes(0x63, 0x10, 0xFF), 0)
  T.eq(out, bytes(0x10, 0x11, 0x12, 0x13), "increasing fill counts up")

  out = Lz2.decompress(bytes(0x63, 0xFE, 0xFF), 0)
  T.eq(out, bytes(0xFE, 0xFF, 0x00, 0x01), "increasing fill wraps at 0xFF")

  -- write "ABCD", then copy 2 bytes back from output offset 1
  out = Lz2.decompress(bytes(0x03, 0x41, 0x42, 0x43, 0x44, 0x81, 0x01, 0x00, 0xFF), 0)
  T.eq(out, "ABCDBC", "a back reference copies from the output at its offset")

  -- long form: command 000, length 300
  local long = bytes(0xE1, 43) .. string.rep("Z", 300) .. bytes(0xFF)
  out = Lz2.decompress(long, 0)
  T.eq(#out, 300, "the long-length escape carries a 10-bit length")

  T.eq(Lz2.decompress(bytes(0x05, 0x41), 0), nil,
    "a direct copy running past the end is refused")
  T.eq(Lz2.decompress(bytes(0x81, 0x10, 0x00, 0xFF), 0), nil,
    "a back reference past the written output is refused")
  T.eq(Lz2.decompress(bytes(0x00, 0x41), 0), nil,
    "a stream with no terminator is refused")
  local capped = select(2, Lz2.decompress(bytes(0x23, 0xAB, 0xFF), 0, 2))
  T.check(type(capped) == "string" and capped:find("exceeded", 1, true),
    "the output cap is enforced")
end

do
  T.eq(SnesGfx.loRomOffset(0x00, 0xB8, 0x11), 0x3811,
    "a bank 0 pointer maps into the first half bank")
  T.eq(SnesGfx.loRomOffset(0x11, 0xB8, 0x11), 0x08B811,
    "LoROM drops the high bit of the bank and the $8000 window")
  T.eq(SnesGfx.loRomOffset(0x00, 0x00, 0x10), nil,
    "an address below $8000 is not a LoROM pointer")

  local r, g, b = SnesGfx.color(0x7FFF)
  T.eq(math.floor(r + 0.5) .. "," .. math.floor(g + 0.5) .. "," .. math.floor(b + 0.5),
    "255,255,255", "BGR555 white expands to white")
  r, g, b = SnesGfx.color(0x0000)
  T.eq(r + g + b, 0, "BGR555 zero is black")
  r, g, b = SnesGfx.color(0x001F)
  T.eq(math.floor(r + 0.5) .. "," .. math.floor(g) .. "," .. math.floor(b),
    "255,0,0", "the low five bits are red, so the channel order is BGR")
end

do
  -- one 3bpp tile: row 0 all index 7, row 1 all index 1, rows 2-7 index 0
  local planes01 = bytes(0xFF, 0xFF) .. bytes(0xFF, 0x00) .. string.rep(bytes(0, 0), 6)
  local plane2 = bytes(0xFF) .. string.rep(bytes(0), 7)
  local tile = SnesGfx.decodeTile3bpp(planes01 .. plane2, 0)
  T.eq(tile[1], 7, "3bpp row 0 reads all three planes")
  T.eq(tile[8], 7, "across the whole row")
  T.eq(tile[9], 1, "row 1 uses plane 0 only")
  T.eq(tile[17], 0, "and an empty row is index 0")

  local two = SnesGfx.decodeTile2bpp(bytes(0xAA, 0x00) .. string.rep(bytes(0, 0), 7), 0)
  T.eq(two[1], 1, "2bpp picks up plane 0 at the high bit")
  T.eq(two[2], 0, "and the alternating bit is clear")

  local bits, tiles = SnesGfx.sheetFormat(0x600)
  T.eq(bits, 3, "a 0x600 sheet is 3bpp")
  T.eq(tiles, 64, "with 64 tiles")
  bits, tiles = SnesGfx.sheetFormat(2048)
  T.eq(bits, 2, "a 2048-byte sheet is 2bpp")
  T.eq(tiles, 128, "with 128 tiles")
  T.eq(SnesGfx.sheetFormat(7), nil, "a stray length is neither")
end

do
  T.eq(LttpImport.identify("not a rom"), nil, "a foreign blob is not accepted")
  T.check(LttpImport.isRaw(115) and LttpImport.isRaw(126),
    "the uncompressed sheet band covers 115 through 126")
  T.check(not LttpImport.isRaw(114) and not LttpImport.isRaw(127),
    "and stops either side of it")
  T.eq(LttpImport.RAW_SIZE, 0x600, "a raw sheet is one 3bpp sheet wide")
end

T.finish("lttp_codec")
