-- The evolution movie (engine/movie/evolution.asm): the mon's pic
-- flashes back and forth with the evolved form, speeding up, then the
-- new form appears with its cry and the "evolved into" text
-- (engine/pokemon/evos_moves.asm:120-128).
-- pokered engine/movie/evolution.asm (Evolution_CheckForCancel) polls the
-- joypad during the flash: a fresh B press aborts the evolution -- the mon
-- keeps its species and _StoppedEvolvingText ("Huh? MON stopped evolving!")
-- prints.  Two kinds are exempt: trade evolutions, which evos_moves.asm
-- routes past the poll entirely (wLinkState == LINK_STATE_TRADING, #213),
-- and stone evolutions, where the B press is read but thrown away because
-- ItemUseEvoStone left wForceEvolution set (#290).

local Music = require("src.core.Music")
local romText = require("src.core.RomText")

-- Not opaque: ClearScreenArea wipes rows 0-11 only (evos_moves.asm:126-128),
-- so the "is evolving!" box beneath stays visible through the flash (#1596).
local EvolutionState = {}
EvolutionState.__index = EvolutionState

local PIC_LOAD_FRAMES = 84
-- evolution.asm EvolveMon delays 80 frames before .animLoop, polling nothing (#968, #1031)
local CANCEL_GRACE_FRAMES = 80
local ANIM_LOOP_FRAMES = 288
local FLASH_FRAMES = CANCEL_GRACE_FRAMES + ANIM_LOOP_FRAMES

-- SGB: SetPal_PokemonWholeScreen for the mon on display
function EvolutionState:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  -- engine/movie/evolution.asm EvolveMon runs the back-and-forth flash with
  -- the whole screen on PAL_BLACK -- `ld c, 1 ; set PAL_BLACK instead of mon
  -- palette` right before .animLoop, then `ld c, 0` again at .done once the
  -- loop is over -- so both forms read as silhouettes while they trade places
  -- and only the settled form wears a mon palette (#279).  PAL_BLACK is not
  -- four blacks: data/sgb/sgb_palettes.asm gives it `RGB 31,29,31, 07,07,07,
  -- 02,03,03, 03,02,02`, the usual paper white with the three darker shades
  -- crushed, which is why a hardware capture shows a dark mon on an unchanged
  -- background rather than an all-black screen.  Going through P.pal keeps
  -- every COLORS mode honest for free: OG RED short-circuits every name to the
  -- one global boot-ROM palette (a Game Boy Color ignores the SGB packets, so
  -- it never blacks out) and the mono modes replace it in effectiveColors.
  -- ../pokered/engine/movie/evolution.asm:23-26, :49-50
  if not self.done and self.t >= CANCEL_GRACE_FRAMES then
    local black = P.pal(game.data, "BLACK")
    if black then return { P.whole(black) } end
  end
  -- a cancelled evolution keeps the old species (never applied), so only
  -- colorize with the new form once it has actually evolved
  local species = (self.done and not self.canceled) and self.newSpecies
    or self.mon.species
  local c = P.monPal(game.data, species)
  if c then return { P.whole(c) } end
  return P.wholeNamed(game.data, "MEWMON")
end

-- which pic is on screen t frames into .animLoop
local function evoShowsNew(t)
  for b = 1, 8 do
    local hold = 18 - 2 * b
    if t < hold then return false end
    t = t - hold
    local swap = b * 6
    if t < swap then return t % 6 < 3 end
    t = t - swap
  end
  return true
end

local function frontSprite(game, species, mon)
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, species, "front", { mon = mon, kind = "evolution" })
  if not path then return nil, false end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil, ok and trueColor or false
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
  self.oldSprite, self.oldSpriteTrueColor = frontSprite(game, mon.species, mon)
  self.newSprite, self.newSpriteTrueColor = frontSprite(game, newSpecies, mon)
  self.t = 0
  self.done = false
  self.canceled = false
  -- engine/movie/evolution.asm:12-19
  Music.stop()
  require("src.core.Sound").play(game.data, "Tink")
  self.loading = PIC_LOAD_FRAMES
  self.crySrc = nil
  self.cryT = 0
  self.cryWait = false
  return self
end

-- engine/movie/evolution.asm:39-46
function EvolutionState:beginCry()
  self.crySrc = require("src.core.Sound").playCry(self.game.data, self.mon.species)
  self.cryT = 0
  self.cryWait = self.crySrc ~= nil
  if not self.cryWait then
    Music.play(self.game.data, Music.special(self.game.data, "evolution"))
  end
end

-- engine/movie/evolution.asm:68-74
function EvolutionState:beginDoneCry(species)
  Music.stop()
  self.endCrySrc = require("src.core.Sound").playCry(self.game.data, species)
  self.endCryT = 0
  self.endCryWait = self.endCrySrc ~= nil
  if not self.endCryWait then self:pushDoneText() end
end

-- engine/pokemon/evos_moves.asm:136-153, :293
function EvolutionState:pushDoneText()
  local game = self.game
  local TextBox = require("src.render.TextBox")
  local Evolution = require("src.pokemon.Evolution")
  if self.canceled then
    game.stack:push(TextBox.new(game,
      romText(game.data, "_StoppedEvolvingText", nil, self.oldName),
      function()
        game.stack:pop()
        -- engine/pokemon/evos_moves.asm:296
        Evolution.clearScreen(game, self.mon.species)
        if self.onDone then self.onDone() end
      end))
    return
  end
  local newName = game.data.pokemon[self.newSpecies].name
  -- engine/pokemon/evos_moves.asm:136-153
  local msg = romText(game.data, "_EvolvedText", nil, self.oldName)
    .. romText(game.data, "_IntoText", nil, newName)
  game.stack:push(TextBox.new(game, msg,
    function()
      game.stack:pop()
      -- engine/pokemon/evos_moves.asm:156
      Evolution.clearScreen(game, self.newSpecies)
      -- engine/pokemon/evos_moves.asm:212 (#12)
      Evolution.learnEvolutionMoves(game, self.mon, self.onDone)
    end,
    TextBox.soundOpts(game, "Get_Item2")))
end

function EvolutionState:update(dt)
  -- engine/movie/evolution.asm:20-40
  if self.loading then
    self.loading = self.loading - 1
    if self.loading > 0 then return end
    self.loading = nil
    self:beginCry()
    return
  end
  if self.cryWait then
    self.cryT = self.cryT + 1
    local src = self.crySrc
    local playing = src and src.isPlaying and src:isPlaying()
    if self.cryT >= 3 and (not playing or self.cryT > 180) then
      self.cryWait, self.crySrc = false, nil
      Music.play(self.game.data, Music.special(self.game.data, "evolution"))
    end
    return
  end
  -- home/pokemon.asm:145-149
  if self.endCryWait then
    self.endCryT = self.endCryT + 1
    local src = self.endCrySrc
    local playing = src and src.isPlaying and src:isPlaying()
    if self.endCryT >= 3 and (not playing or self.endCryT > 180) then
      self.endCryWait, self.endCrySrc = false, nil
      self:pushDoneText()
    end
    return
  end
  self.t = self.t + 1
  if self.done then return end
  local game = self.game
  -- evolution.asm Evolution_CheckForCancel reads hJoy5, a fresh edge rather
  -- than a hold, so B held from the level-up box must not cancel (#968, #1031)
  if self.cancelable and self.t > CANCEL_GRACE_FRAMES
     and game.input:wasPressed("b") then
    self.done = true
    self.canceled = true
    -- evolution.asm:89-94
    self:beginDoneCry(self.mon.species)
    return
  end
  if self.t >= FLASH_FRAMES then
    self.done = true
    local Evolution = require("src.pokemon.Evolution")
    Evolution.apply(game, self.mon, self.newSpecies, self.via)
    self:beginDoneCry(self.newSpecies)
  end
end

function EvolutionState:draw()
  -- pokered/engine/pokemon/evos_moves.asm:133
  require("src.render.PaletteFX").clearSpriteRedraws()
  love.graphics.setColor(1, 1, 1, 1)
  -- rows 0-11 only (hlcoord 0,0 / lb bc, 12, 20, evos_moves.asm:126-128)
  love.graphics.rectangle("fill", 0, 0, 160, 96)
  -- engine/movie/evolution.asm:20-40
  if self.loading then return end

  -- accelerating flash between the two forms
  local sprite, spriteTrueColor
  if self.done then
    -- a cancelled evolution settles back on the original form
    if self.canceled then
      sprite, spriteTrueColor = self.oldSprite, self.oldSpriteTrueColor
    else
      sprite, spriteTrueColor = self.newSprite, self.newSpriteTrueColor
    end
  elseif evoShowsNew(self.t - CANCEL_GRACE_FRAMES) then
    sprite, spriteTrueColor = self.newSprite, self.newSpriteTrueColor
  else
    sprite, spriteTrueColor = self.oldSprite, self.oldSpriteTrueColor
  end
  if sprite then
    local x = math.floor((160 - sprite:getWidth()) / 2)
    local y = math.max(8, 64 - sprite:getHeight())
    -- engine/movie/evolution.asm:103
    love.graphics.draw(sprite, x + sprite:getWidth(), y, 0, -1, 1)
    if spriteTrueColor then
      require("src.render.PaletteFX").markTrueColor(x, y, sprite:getDimensions())
    end
  end
end

return EvolutionState
