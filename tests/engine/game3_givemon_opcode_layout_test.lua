-- The givemon opcode must consume the pret operand layout.
--
-- Regression: opcodes.lua declared
--   [0x79] = op("givemon", 9, { H, B, H, H, H })
-- but pret (asm/macros/event.inc) is
--   .byte 0x79 / .2byte species / .byte level / .2byte item / .4byte 0 / .4byte 0 / .byte 0
-- i.e. two WORDS where the port had two halves -- 14 operand bytes after the
-- opcode, not 9.  disasm.decodeOne iterates def.args (the size field is unused)
-- and extract_scripts decodes a script linearly, so every command after a
-- givemon was misaligned and baked into the dataset with wrong operands.
--
-- Disasm.decodeOne takes a 1-based array of byte values (not a string).
--   luajit tests/engine/game3_givemon_opcode_layout_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Disasm = require("src.core.game3.scripting.disasm")
local Opcodes = require("src.core.game3.scripting.opcodes")

local function push8(t, v) t[#t + 1] = v % 256 end
local function push16(t, v) push8(t, v % 256); push8(t, math.floor(v / 256) % 256) end
local function push32(t, v) push16(t, v % 65536); push16(t, math.floor(v / 65536) % 65536) end

-- opcode, species 25, level 10, item 13, two words, trailing byte
local stream = {}
push8(stream, 0x79)
push16(stream, 25)
push8(stream, 10)
push16(stream, 13)
push32(stream, 0x11223344)
push32(stream, 0x55667788)
push8(stream, 0)

local row, nextIdx = Disasm.decodeOne(stream, 1)
eq(row.op, "givemon", "the opcode decodes as givemon")
eq(nextIdx, 16, "givemon consumes 15 bytes: opcode + the pret operand layout")
eq(row[1], 25, "species")
eq(row[2], 10, "level")
eq(row[3], 13, "item")
eq(row[4], 0x11223344, "the first word operand")
eq(row[5], 0x55667788, "the second word operand")
eq(row[6], 0, "the trailing byte operand")

-- The desync: the command after a givemon must still decode.
push8(stream, 0x02) -- 0x02 = end
local _, afterGivemon = Disasm.decodeOne(stream, 1)
local following = Disasm.decodeOne(stream, afterGivemon)
eq(following.op, "end", "the command after givemon decodes (no stream desync)")

-- The declared size must agree with the argument list: every other entry adds
-- the opcode byte to its args (addvar is 5 for two halves).
eq(Opcodes.get(0x79).size, 15, "the declared size includes the opcode byte")

T.finish("game3_givemon_opcode_layout_test")
