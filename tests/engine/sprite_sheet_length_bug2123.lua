-- engine/overworld/map_sprites.asm:181
package.path = "./?.lua;./?/init.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local RomExtractor = require("src.import.RomExtractor")
local length = RomExtractor.spriteSheetLength

do
  local bytes, height, frames = length("SPRITE_NURSE", 16, 64, 0xC0)
  eq(bytes, 256, "Yellow nurse: the 16x64 sheet keeps all 4 frames")
  eq(height, 64, "Yellow nurse: height stays 64")
  eq(frames, 4, "Yellow nurse: 4 frames")
end

do
  local bytes, height, frames = length("SPRITE_NURSE", 16, 48, 0xC0)
  eq(bytes, 192, "Red nurse: 16x48 matches the 12-tile table entry")
  eq(height, 48, "Red nurse: height stays 48")
  eq(frames, 3, "Red nurse: 3 frames")
end

do
  local bytes, height, frames = length("SPRITE_RED", 16, 96, 0xC0)
  eq(bytes, 384, "walker: both halves of the table entry")
  eq(height, 96, "walker: height stays 96")
  eq(frames, 6, "walker: 6 frames")
end

do
  local bytes, height, frames = length("SPRITE_SHORT", 16, 32, 0xC0)
  eq(bytes, 192, "manifest shorter than the table: the table wins")
  eq(height, 48, "manifest shorter than the table: height grows to the table")
  eq(frames, 3, "manifest shorter than the table: 3 frames")
end

do
  local ok = pcall(length, "SPRITE_BAD", 16, 32, 0xC1)
  check(not ok, "a table length that is not tile-aligned is rejected")
end

T.finish("sprite_sheet_length_bug2123")
