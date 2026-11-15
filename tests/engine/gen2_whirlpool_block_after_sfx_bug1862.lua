-- engine/events/overworld.asm:1150-1165, engine/events/field_moves.asm:5-10

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Sound = require("src.core.Sound")
local World = require("src.world.gen2.World")

local busy = false
Sound.sfxBusy = function() return busy end

local log = {}
local world = setmetatable({ game = { data = {
  text = require("tests.fixture_data.gen2_rom_text_s7_g").text() } } }, { __index = World })
world.setNickname = function() end
world.showText = function(_, _, done) if done then done() end end
world.playSfxNamed = function() log[#log + 1] = "sfx" end
world.replaceBlock = function(_, index, blockId)
  log[#log + 1] = "block:" .. tostring(index) .. ":" .. tostring(blockId)
  return true
end

world:runWhirlpool({ text = "_UseWhirlpoolText", blockIndex = 7, replacement = 3 })
T.eq(#log, 0, "the box closing does not swap the block yet")
T.eq(world.fieldMove and world.fieldMove.phase, "whirlpoolsfx",
  "closing the box parks the WaitSFX phase")

busy = false
world:updateFieldMove()
T.same(log, { "sfx" }, "the first WaitSFX passes and SFX_SURF starts")

busy = true
world:updateFieldMove()
world:updateFieldMove()
T.same(log, { "sfx" }, "the whirlpool is still on screen while the sfx plays")

busy = false
world:updateFieldMove()
T.same(log, { "sfx", "block:7:3" },
  "the block is swapped once the second WaitSFX clears")
T.eq(world.fieldMove, nil, "and the phase is done")

-- The callback path (DisappearWhirlpool via callasm) carries no block, and
-- must not invent one.
do
  log = {}
  world.fieldMove = nil
  world:playWhirlpoolSound()
  busy = false
  world:updateFieldMove()
  world:updateFieldMove()
  T.same(log, { "sfx" }, "a bare sound call swaps nothing")
end

T.finish("gen2 whirlpool block after sfx bug 1862")
