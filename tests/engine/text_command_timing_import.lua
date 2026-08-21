-- ROM text timing commands are behavior, not decoration.  Both extractors
-- used to discard TX_PAUSE/TX_DOTS (or reject them), which made the correct
-- constants in Timing.lua unreachable from imported cartridge text.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("text command timing import")
love = love or require("tests.love_stub")

local function byteRom(bytes)
  return {
    byte = function(_, _, address)
      return bytes[address + 1] or 0x50
    end,
  }
end

local Gen1 = require("src.import.RomExtractor")
local red = setmetatable({ rom = byteRom({
  0x0a,       -- TX_PAUSE
  0x0c, 0x02, -- TX_DOTS 2
  0x50,       -- TX_END
}) }, { __index = Gen1 })
T.eq(red:decodeTextCommands({ bank = 1, address = 0, name = "Timed" }, {}),
  "{PAUSE}{DOTS:2}",
  "Gen 1 extraction preserves pause and per-dot count in stream order")

local Gold = require("src.import.RomExtractorGen2")
local gold = setmetatable({ rom = byteRom({
  0x0a,             -- TX_PAUSE
  0x0c, 0x02,       -- TX_DOTS 2
  0x00, 0x80, 0x50, -- text_start, A, @
  0x50,             -- TX_END
}) }, { __index = Gold })
T.eq(gold:decodeGen2Text(1, 0, { ["128"] = "A" }),
  "{PAUSE}{DOTS:2}A",
  "Gen 2 extraction no longer drops pause/dots before visible text")

local zero = setmetatable({ rom = byteRom({
  0x0c, 0x00, 0x00, 0x80, 0x50, 0x50,
}) }, { __index = Gold })
T.eq(zero:decodeGen2Text(1, 0, { ["128"] = "A" }), "{DOTS:0}A",
  "zero-count TX_DOTS is preserved without inventing an ellipsis")

T.finish()
