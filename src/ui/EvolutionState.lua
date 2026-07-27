-- The evolution movie (engine/movie/evolution.asm): the mon's pic
-- flashes back and forth with the evolved form, speeding up, then the
-- new form appears with its cry and the congratulations text.
-- pokered engine/movie/evolution.asm (Evolution_CheckForCancel) polls the
-- joypad during the flash: holding B aborts the evolution -- the mon keeps
-- its species and _StoppedEvolvingText ("Huh? MON stopped evolving!")
-- prints.  Two kinds are exempt: trade evolutions, which evos_moves.asm
-- routes past the poll entirely (wLinkState == LINK_STATE_TRADING, #213),
-- and stone evolutions, where the B press is read but thrown away because
-- ItemUseEvoStone left wForceEvolution set (#290).

local Font = require("src.render.Font")
local Music = require("src.core.Music")
local Strings = require("src.core.Strings")

local EvolutionState = {}
EvolutionState.__index = EvolutionState
EvolutionState.isOpaque = true

-- SGB: SetPal_PokemonWholeScreen for the mon on display
function EvolutionState:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  -- a cancelled evolution keeps the old species (never applied), so only
  -- colorize with the new form once it has actually evolved
  local species = (self.done and not self.canceled) and self.newSpecies
    or self.mon.species
  local c = P.monPal(game.data, species)
  if c then return { P.whole(c) } end
  return P.wholeNamed(game.data, "MEWMON")
end

local FLASH_FRAMES = 220

local function frontSprite(game, species, mon)
  local path = require("src.pokemon.Sprites").path(game.data, species, "front",
    { mon = mon, kind = "evolution" })
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

function EvolutionState.new(game, mon, newSpecies, onDone, via)
  local self = setmetatable({}, EvolutionState)
  self.game = game
  self.mon = mon
  self.newSpecies = newSpecies
  self.onDone = onDone
  self.via = via
  -- evolution.asm Evolution_CheckForCancel: a B press is discarded when
  -- wForceEvolution is set, and ItemUseEvoStone sets it before calling
  -- TryEvolvingMon, so a stone evolution (via == "ITEM") cannot be
  -- cancelled either.  Only level-up and rare-candy evolutions run with
  -- wForceEvolution clear and so honour B (#290, #213).
  self.cancelable = (via ~= "TRADE" and via ~= "ITEM")
  self.oldName = mon.nickname or game.data.pokemon[mon.species].name
  self.oldSprite = frontSprite(game, mon.species, mon)
  self.newSprite = frontSprite(game, newSpecies, mon)
  self.t = 0
  self.done = false
  self.canceled = false
  Music.play(game.data, Music.special(game.data, "evolution"))
  return self
end

function EvolutionState:update(dt)
  self.t = self.t + 1
  if self.done then return end
  local game = self.game
  -- evos_moves.asm EvolveMon: each flash iteration polls hJoyHeld and, for
  -- a cancelable evolution, aborts when B is held -- the mon keeps its
  -- species (Evolution.apply never runs) and _StoppedEvolvingText prints.
  if self.cancelable and game.input:isDown("b") then
    self.done = true
    self.canceled = true
    local TextBox = require("src.render.TextBox")
    -- mirrors data/generated/text.lua _StoppedEvolvingText
    game.stack:push(TextBox.new(game,
      Strings("Huh? %s\nstopped evolving!", self.oldName),
      function()
        Music.restoreMap(game.data)
        game.stack:pop() -- the evolution screen itself
        if self.onDone then self.onDone() end
      end))
    return
  end
  if self.t >= FLASH_FRAMES then
    self.done = true
    local Evolution = require("src.pokemon.Evolution")
    Evolution.apply(game, self.mon, self.newSpecies, self.via)
    require("src.core.Sound").playCry(game.data, self.newSpecies)
    local TextBox = require("src.render.TextBox")
    local newName = game.data.pokemon[self.newSpecies].name
    game.stack:push(TextBox.new(game,
      Strings("Congratulations!\nYour %s\nevolved into\n%s!",
              self.oldName, newName),
      function()
        Music.restoreMap(game.data)
        game.stack:pop() -- the evolution screen itself
        -- Gen1 re-runs the level-up learn check on the evolved species
        -- after the "evolved into" text (evos_moves.asm EvolveMon ->
        -- learn_move.asm LearnMoveFromLevelUp, #12).  Pop the evo screen
        -- first so the "learned MOVE!" text / forget prompt push onto the
        -- overworld / battle-return, not this state.
        Evolution.learnEvolutionMoves(game, self.mon, self.onDone)
      end))
  end
end

function EvolutionState:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  -- accelerating flash between the two forms
  local sprite
  if self.done then
    -- a cancelled evolution settles back on the original form
    sprite = self.canceled and self.oldSprite or self.newSprite
  else
    local period = math.max(4, 28 - math.floor(self.t / 40) * 6)
    local showNew = math.floor(self.t / period) % 2 == 1
    sprite = showNew and self.newSprite or self.oldSprite
  end
  if sprite then
    love.graphics.draw(sprite, math.floor((160 - sprite:getWidth()) / 2),
                       math.max(8, 64 - sprite:getHeight()))
  end

  love.graphics.setColor(0, 0, 0, 1)
  if not self.done then
    Font.draw(Strings("What?"), 8, 104)
    Font.draw(self.oldName .. " is", 8, 114)
    Font.draw(Strings("evolving!"), 8, 124)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return EvolutionState
