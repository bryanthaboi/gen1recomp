-- The Gen 2 evolution screen: engine/movie/evolution_animation.asm plus the
-- text beats around it in engine/pokemon/evolve.asm's EvolveAfterBattle.
--
-- All of the arithmetic (which species, whether the condition is met, what the
-- party record becomes, and every frame count below) is
-- src/core/gen2/Evolution.lua's; this file is the only half that draws, so an
-- evolution can be asserted end to end with no window.
--
-- The animation is NOT a cross fade.  The cart loads BOTH frontpics into
-- vTiles2 -- the new species' 7x7 = 49 tiles at tile $31, the old one's at
-- tile $00 -- and then adds or subtracts 49 to every tilemap entry of the
-- 7x7 box at hlcoord 7, 2.  That is a hard swap between two pics, once per
-- WaitBGMap, run in accelerating bursts:
--
--   `lb bc, 1, 16` then, per round, `inc b / dec c / dec c`
--   round 1: hold the old pic 16 frames, then flash 1 time
--   round 2: hold 14,                     flash 2 times
--   ... eight rounds, ending 2 / 8, and each "flash" is new-then-old.
--
-- The whole flashing half runs under PREDEFPAL_BLACKOUT (_CGB_Evolution's
-- `ld c` = TRUE branch), which is what makes both pics read as one silhouette;
-- the new species' real colours only arrive on the last swap.
--
-- Layout: hlcoord 7, 2 with `lb bc, 7, 7` (PrepMonFrontpic), i.e. a 7x7 tile
-- box at (56, 16).  The text box below it is never cleared -- EvolveAfterBattle
-- clears rows 0..11 only -- so "What? <NICK> is evolving!" stays under the pic
-- for the whole animation.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Evolution = require("src.core.gen2.Evolution")
local GbcPalette = require("src.render.GbcPalette")
local Mon = require("src.battle.gen2.Mon")
local Music = require("src.core.Music")
local Palettes = require("src.world.gen2.Palettes")
local Sound = require("src.core.Sound")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")

local EvolutionAnim = {}
EvolutionAnim.__index = EvolutionAnim
EvolutionAnim.isOpaque = true

-- PrepMonFrontpic's box: hlcoord 7, 2, `lb bc, 7, 7`.
local PIC_TILE_X, PIC_TILE_Y, PIC_TILES = 7, 2, 7

-- TEXTBOX_Y is SCREEN_HEIGHT - TEXTBOX_HEIGHT and TEXTBOX_INNERY is
-- TEXTBOX_Y + 2; `line` ($4f) targets the box's absolute second line, which is
-- two rows below the first.
local BOX_X, BOX_Y, BOX_W, BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2

-- PromptButton pages: the port holds a prompt for this long and takes A or B
-- as the press, the same deal src/ui/gen2/BattleState.lua's MESSAGE_FRAMES
-- gives every other Gold text box.
local PROMPT_FRAMES = 48

-- Paragraph's own `ld c, 20 / call DelayFrames` between clearing the box and
-- printing the next page.
local PARAGRAPH_FRAMES = 20

-- gfx/sgb/predef.pal PREDEFPAL_BLACKOUT, through the extractor's own 5-bit to
-- 8-bit scale (floor(v * 255 / 31 + 0.5)).
local BLACKOUT = {
  { 255, 255, 255 }, { 58, 58, 58 }, { 16, 25, 25 }, { 0, 0, 0 },
}

-- NUM_SPRITE_ANIM_STRUCTS.  InitSpriteAnimStruct refuses once the pool is
-- full, so the balls of light cap out at ten on screen no matter how many
-- .GenerateBallOfLight would like to make.
local BALL_LIMIT = 10

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

function EvolutionAnim:wantsFillScale() return true end
function EvolutionAnim:drawsWidescreen() return true end

-- opts:
--   mon      the party record as it stands BEFORE evolving
--   entry    the EvosAttacks row Evolution.check picked
--   index    its party slot, so the new record lands in the right one
--   party    the party table to write back into (defaults to save.party)
--   save     for SetSeenAndCaughtMon
--   force    wForceEvolution: a stone evolution cannot be cancelled with B
--   onDone(result)  result = { canceled, evolved, learned, full }
function EvolutionAnim.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, EvolutionAnim)
  self.game = game
  self.data = (game and game.data) or {}
  self.palettes = self.data.gen2Palettes
  self.save = opts.save or (game and game.save)
  self.party = opts.party or (self.save and self.save.party) or {}
  self.index = opts.index or 1
  self.mon = opts.mon or self.party[self.index]
  self.entry = opts.entry
  self.force = opts.force or false
  self.onDone = opts.onDone

  self.oldSpecies = self.mon and self.mon.species
  self.newSpecies = self.entry and self.entry.into
  -- wStringBuffer2 is filled with GetNickname BEFORE the animation, so every
  -- line below (including "stopped evolving!") names the mon by the name it
  -- had going in.
  self.nick = (self.mon and (self.mon.nickname or self.mon.name))
    or self.oldSpecies or "?"
  self.newName = Evolution.speciesName(self.data, self.newSpecies)

  self.picCache = {}
  self.rounds = Evolution.flashRounds()
  self.canceled = false
  self.learned = {}
  self.full = {}
  self.balls = {}
  self.ballFrame = 0
  -- Which of the two pics the 7x7 box is showing.  The box starts on the OLD
  -- one and every round of flashing ends back on it, which is why a B press
  -- during a hold always leaves the old mon on screen.
  self.showNew = false
  self.blackout = false

  self:setPhase("evolving")
  return self
end

--------------------------------------------------------------------------
-- Phases
--------------------------------------------------------------------------

function EvolutionAnim:playCry(species)
  if not species then return end
  local cries = self.data.audio and self.data.audio.cries
  if cries and cries[species] then Sound.playCry(self.data, species) end
end

function EvolutionAnim:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

-- NOT `enter`.  `enter` is the stack's own lifecycle hook -- StateStack:push
-- calls `state:enter(...)` (src/core/StateStack.lua:18), and Gold runs that
-- same stack (src/core/Game2.lua:makeStack) -- so a screen that also used
-- `enter` for its internal state machine had that machine reset the instant
-- it was pushed:
-- Screens.push passes no extra arguments, so the hook arrived as `enter(nil)`,
-- phase became nil and every branch of update() then missed.  The screen sat
-- there decrementing its timer forever with the world still marked busy, which
-- made a post-battle evolution an unrecoverable hang -- the Gold route bot hit
-- it the first time its starter reached level 14.
function EvolutionAnim:setPhase(phase)
  self.phase = phase
  self.timer = 0

  if phase == "evolving" then
    -- PrintText EvolvingText, then `ld c, 50 / call DelayFrames`.  The pics are
    -- not placed yet: on the cart the battle screen is still up behind this
    -- line and ClearBox only wipes rows 0..11 once the delay is over.
    self.lines = { "What? " .. self.nick, "is evolving!" }
    self.timer = Evolution.EVOLVING_FRAMES
    return
  end

  if phase == "cry" then
    -- PlayMonCry of the OLD species, then MUSIC_EVOLUTION, then 80 frames.
    -- PlayMusic MUSIC_NONE ran first, so nothing else is sounding.
    Music.stop()
    self:playCry(self.oldSpecies)
    local songs = self.data.audio and self.data.audio.songs
    if songs and songs.Music_Evolution then
      Music.play(self.data, "Music_Evolution", true, { reason = "evolution" })
    end
    self.timer = Evolution.MUSIC_FRAMES
    return
  end

  if phase == "flash" then
    -- GetSGBLayout with c = TRUE: PREDEFPAL_BLACKOUT for the whole burst.
    self.blackout = true
    self.round = 1
    self.step = "wait"
    self.timer = self.rounds[1].wait
    self.swapsLeft = 0
    return
  end

  if phase == "reveal" then
    -- The final `ld a, 7 * 7 / call .ReplaceFrontpic` commits the new pic, then
    -- wPlayerHPPal takes the new species and GetSGBLayout comes back with
    -- c = FALSE, so the colours arrive on the same beat.
    self.blackout = false
    self.showNew = not self.canceled
    if self.canceled then
      -- .PlayEvolvedSFX returns immediately once wEvolutionCanceled is set:
      -- no SFX_EVOLVED and no balls of light, straight to the cry.
      self:playCry(self.oldSpecies)
      return self:setPhase("stopped")
    end
    self:playSfx("Sfx_Evolved")
    self.timer = Evolution.BALL_SPAWN_FRAMES + Evolution.BALL_TAIL_FRAMES
    return
  end

  if phase == "stopped" then
    -- CancelEvolution: StoppedEvolvingText over the pic, then ClearTilemap.
    self.lines = { "Huh? " .. self.nick, "stopped evolving!" }
    self.timer = PROMPT_FRAMES
    return
  end

  if phase == "congrats" then
    self.lines = { "Congratulations!", "Your " .. self.nick }
    self.timer = PROMPT_FRAMES
    return
  end

  if phase == "paragraph" then
    -- Paragraph clears the box and waits 20 frames before the next page.
    self.lines = nil
    self.timer = PARAGRAPH_FRAMES
    return
  end

  if phase == "evolved" then
    -- EvolvedIntoText, then MUSIC_NONE / SFX_CAUGHT_MON / WaitSFX and
    -- `ld c, 40 / call DelayFrames`.
    self.lines = { "evolved into", self.newName .. "!" }
    Music.stop()
    self:playSfx("Sfx_CaughtMon")
    self.timer = Evolution.CONGRATS_FRAMES
    return
  end

  if phase == "learn" then
    -- ClearTilemap, then the party slot is rewritten and LearnLevelMoves runs.
    self:commit()
    self.learnIndex = 0
    return self:nextLearn()
  end

  if phase == "done" then
    if self.onDone then
      self.onDone({
        canceled = self.canceled,
        evolved = self.evolved,
        learned = self.learned,
        full = self.full,
      })
    end
    local stack = self.game and self.game.stack
    if stack and stack.top and stack:top() == self then stack:pop() end
    return
  end
end

-- The writeback: `pop de / pop hl / ld a, [wTempMonSpecies] / ld [hl], a`
-- after CalcMonStats has already rebuilt the struct.  Everything the record
-- becomes is Evolution.apply's, which builds it through
-- src/battle/gen2/Mon.lua so there is still exactly one builder.
function EvolutionAnim:commit()
  local evolved = Evolution.apply(self.data, self.mon, self.entry)
  if not evolved then return end
  self.evolved = evolved
  self.party[self.index] = evolved
  Evolution.markPokedex(self.save, evolved.species)
  -- LearnLevelMoves at wCurPartyLevel, which the .proceed block set to the
  -- level the mon already had.
  self.pending = Evolution.learnedOnEvolve(self.data, evolved.species,
    evolved.level, evolved)
end

function EvolutionAnim:nextLearn()
  self.learnIndex = (self.learnIndex or 0) + 1
  local moveId = self.pending and self.pending[self.learnIndex]
  if not (moveId and self.evolved) then
    self.lines = nil
    return self:setPhase("done")
  end
  local moveDef = self.data.moves and self.data.moves[moveId]
  local moveName = (moveDef and moveDef.name) or moveId
  local ok, reason = Mon.learnMove(self.evolved, moveId, self.data)
  if ok then
    self.learned[#self.learned + 1] = moveId
    self.lines = { self.nick .. " learned", moveName .. "!" }
  elseif reason == "full" then
    if self.game and self.game.learnMoveOn then
      self.phase = "waitingLearn"
      return self.game:learnMoveOn(self.evolved, moveId, function(learned)
        if learned then
          self.learned[#self.learned + 1] = moveId
        else
          self.full[#self.full + 1] = moveId
        end
        self:nextLearn()
      end)
    end
    self.full[#self.full + 1] = moveId
    self.lines = { self.nick .. " wants to", "learn " .. moveName .. "!" }
  else
    return self:nextLearn()
  end
  self.phase = "learn"
  self.timer = PROMPT_FRAMES
end

--------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------

-- .WaitFrames_CheckPressedB reads the joypad every frame of a hold, and
-- .pressed_b honours it only while wForceEvolution is clear: a stone
-- evolution cannot be stopped.
function EvolutionAnim:cancelPressed(input)
  if self.force then return false end
  return input and input:wasPressed("b") or false
end

function EvolutionAnim:update(_dt)
  local input = self.game and self.game.input
  local phase = self.phase
  -- onDone has already fired.
  if phase == "done" then
    local stack = self.game and self.game.stack
    if stack and stack.top and stack:top() == self then stack:pop() end
    return
  end

  if phase == "waitingLearn" then
    local stack = self.game and self.game.stack
    if stack and stack.top and stack:top() == self then self:nextLearn() end
    return
  end

  if phase == "flash" then
    return self:updateFlash(input)
  end

  if phase == "reveal" then
    self:updateBalls()
    self.timer = self.timer - 1
    if self.timer <= 0 then
      -- ClearSpriteAnims, then PlayMonCry of the species the screen is now
      -- showing.
      self:playCry(self.newSpecies)
      self:setPhase("congrats")
    end
    return
  end

  self.timer = (self.timer or 0) - 1
  local prompt = phase == "stopped" or phase == "congrats" or phase == "learn"
  if prompt and input
      and (input:wasPressed("a") or input:wasPressed("b")) then
    self.timer = 0
  end
  if self.timer > 0 then return end

  if phase == "evolving" then return self:setPhase("cry") end
  if phase == "cry" then return self:setPhase("flash") end
  if phase == "stopped" then return self:setPhase("done") end
  if phase == "congrats" then return self:setPhase("paragraph") end
  if phase == "paragraph" then return self:setPhase("evolved") end
  if phase == "evolved" then return self:setPhase("learn") end
  if phase == "learn" then return self:nextLearn() end
end

-- One frame of the flash loop.  A round is `.WaitFrames_CheckPressedB` for its
-- own `c` frames and then `.Flash` b times, each flash being two
-- .ReplaceFrontpic calls (new, then back to old) a WaitBGMap apart.
function EvolutionAnim:updateFlash(input)
  local round = self.rounds[self.round]
  if not round then
    return self:setPhase("reveal")
  end

  if self.step == "wait" then
    if self:cancelPressed(input) then
      -- .cancel_evo: wEvolutionCanceled, and the pic stays on the old stage.
      self.canceled = true
      self.showNew = false
      return self:setPhase("reveal")
    end
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.step = "flash"
      -- Two swaps per flash: to the new pic and back.
      self.swapsLeft = round.flashes * 2
      self.timer = Evolution.SWAP_FRAMES
      self.showNew = true
    end
    return
  end

  -- Each swap holds for one WaitBGMap.
  self.timer = self.timer - 1
  if self.timer > 0 then return end
  self.swapsLeft = self.swapsLeft - 1
  if self.swapsLeft <= 0 then
    self.showNew = false
    self.round = self.round + 1
    local nextRound = self.rounds[self.round]
    if not nextRound then return self:setPhase("reveal") end
    self.step = "wait"
    self.timer = nextRound.wait
    return
  end
  self.showNew = not self.showNew
  self.timer = Evolution.SWAP_FRAMES
end

--------------------------------------------------------------------------
-- Balls of light
--------------------------------------------------------------------------

-- .balls_of_light spawns two balls on every EVEN wJumptableIndex over the 32
-- spawn frames.  The angle it writes is read AFTER `inc [hl]`, so it is the
-- POST-increment index masked to %1110 and shifted left; the second ball of a
-- pair is a further $10 round the table.
--
-- AnimSeq_RevealNewMon then walks each ball out: VAR1 is the radius, starting
-- at $10 and stepping $08 a frame until it passes $80, and the angle is xor'd
-- with $20 every frame so a ball alternates between the two ends of its own
-- diameter.  y comes from Sine and x from Cosine.
function EvolutionAnim:updateBalls()
  local frame = self.ballFrame
  if frame < Evolution.BALL_SPAWN_FRAMES and frame % 2 == 0 then
    -- `ld a, [hl] / inc [hl]` leaves the PRE-increment index in a, which is
    -- what the `and $1` even/odd test sees; .GenerateBallOfLight then re-reads
    -- wJumptableIndex and gets the POST-increment one.  So the angle is
    -- (post & %1110) << 1, with post always odd here.
    local post = frame + 1
    local base = (((post % 16) - (post % 2)) * 2) % 256
    for _, offset in ipairs({ 0x00, 0x10 }) do
      if #self.balls < BALL_LIMIT then
        self.balls[#self.balls + 1] = {
          angle = (base + offset) % 256,
          radius = Evolution.BALL_RADIUS_START,
          age = 0,
        }
      end
    end
  end
  self.ballFrame = frame + 1

  local alive = {}
  for _, ball in ipairs(self.balls) do
    if ball.radius < Evolution.BALL_RADIUS_END then
      local radius = ball.radius
      ball.radius = radius + Evolution.BALL_RADIUS_STEP
      -- `xor $20` on an angle the sine table masks to six bits is the same as
      -- half a period, and Lua 5.1 has no bitwise xor to spell it with.
      ball.angle = (ball.angle + 0x20) % 0x40
      ball.y = EvolutionAnim.signed(SpriteAnims.sine(ball.angle, radius))
      ball.x = EvolutionAnim.signed(SpriteAnims.cosine(ball.angle, radius))
      ball.age = ball.age + 1
      alive[#alive + 1] = ball
    end
  end
  self.balls = alive
end

-- The sine helpers hand back the byte the ASM leaves in a, so a negative
-- offset arrives in two's complement.
function EvolutionAnim.signed(value)
  value = value % 256
  if value >= 128 then return value - 256 end
  return value
end

--------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------

function EvolutionAnim:pic(species)
  local def = species and self.data.pokemon and self.data.pokemon[species]
  local path = def and def.spriteFront
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    -- "and" would truncate the pcall's second return, so the call stands on
    -- its own line.
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  return cached or nil
end

-- The four colours the box draws through right now: the mon's own while the
-- SGB layout is c = FALSE, PREDEFPAL_BLACKOUT while it is TRUE.
-- Shininess is a DV pattern, and the DVs survive the evolution, so both stages
-- read the same flag off the record that walked in.
function EvolutionAnim:picColors(species)
  if self.blackout then return BLACKOUT end
  return Palettes.monColors(self.palettes, species,
    self.mon and self.mon.shiny)
end

function EvolutionAnim:drawPic()
  local species = self.showNew and self.newSpecies or self.oldSpecies
  local image = self:pic(species)
  if not image then return end
  local G = love.graphics
  local w, h = image:getDimensions()
  -- PlaceGraphic pads the pic into the 7x7 box bottom-first, so a 40x40
  -- Cyndaquil stands on the same ground line a 56x56 Onix does.
  local box = PIC_TILES * 8
  local px = PIC_TILE_X * 8 + math.floor((box - w) / 2)
  local py = PIC_TILE_Y * 8 + (box - h)
  G.setColor(1, 1, 1, 1)
  local colors = self:picColors(species)
  local function body() G.draw(image, px, py) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
end

-- gfx/evo/bubble_large.2bpp and gfx/evo/bubble.2bpp are not in the Gold cache
-- (the extractor does not pull gfx/evo/), so the ball is drawn as the disc
-- those two 8x8 tiles are, at the two sizes .Frameset_EvolutionBallOfLight
-- alternates between every two frames.  Its colour goes through
-- GbcPalette.color so the COLOR option still reaches it.
function EvolutionAnim:drawBalls()
  if #self.balls == 0 then return end
  local G = love.graphics
  local colors = Palettes.monColors(self.palettes, self.newSpecies,
    self.evolved and self.evolved.shiny)
  local rgb = GbcPalette.color(colors, 3) or { 0, 0, 0 }
  G.setColor(rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
  for _, ball in ipairs(self.balls) do
    local radius = (math.floor(ball.age / 2) % 2 == 0) and 4 or 3
    G.circle("fill", Evolution.BALL_ORIGIN_X + (ball.x or 0) + 4,
      Evolution.BALL_ORIGIN_Y + (ball.y or 0) + 4, radius)
  end
  G.setColor(1, 1, 1, 1)
end

-- The pic is on screen from the moment .PlaceFrontpic runs until ClearTilemap,
-- which is only reached once the "evolved into" page has had its 40 frames --
-- so the congratulation text prints OVER the new mon, and CancelEvolution's
-- "stopped evolving!" prints over the old one.  The two phases without a pic
-- are the 50 frames before the animation starts and the LearnLevelMoves run
-- after the tilemap is cleared.
function EvolutionAnim:drawPanel()
  Chrome.clear()
  if self.phase ~= "evolving" and self.phase ~= "learn" then
    self:drawPic()
    self:drawBalls()
  end
  if self.lines then
    Chrome.box(BOX_X, BOX_Y, BOX_W, BOX_H)
    for index, line in ipairs(self.lines) do
      Chrome.print(line, TEXT_X, TEXT_Y + (index - 1) * TEXT_LINE)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function EvolutionAnim:draw()
  self:drawPanel()
end

function EvolutionAnim:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return EvolutionAnim
