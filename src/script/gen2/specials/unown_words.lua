-- ../pokecrystal/data/events/special_pointers.asm:151 DisplayUnownWords, run by all four
-- chambers: ../pokecrystal/maps/RuinsOfAlphKabutoChamber.asm:123,
-- ../pokecrystal/maps/RuinsOfAlphHoOhChamber.asm:86, ../pokecrystal/maps/RuinsOfAlphOmanyteChamber.asm:86,
-- ../pokecrystal/maps/RuinsOfAlphAerodactylChamber.asm:85.

local Specials = require("src.script.gen2.Specials")
local UnownWords = require("src.world.gen2.UnownWords")

local S = Specials.shared

local M = {}

M.DisplayUnownWords = function(vm)
  local h = S.hooks(vm)
  local world = h.world
  local game = world and world.game
  if not (game and game.stack) then return end
  local wall = UnownWords.wallFor(game.data, vm.scriptVar or 0)
  if not wall then return end
  S.block(vm, function(done)
    local screen = UnownWords.new(game, {
      wall = wall, world = world, onClose = function() done(true) end,
    })
    local ok = pcall(game.stack.push, game.stack, screen)
    if not ok then done(false) end
  end)
end

return M
