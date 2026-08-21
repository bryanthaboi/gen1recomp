-- The egg hatch cutscene: engine/pokemon/breeding.asm
-- EggHatch_AnimationSequence, the beat HatchEggs runs between "Huh?" and
-- "<NAME> came out of its EGG!".
--
-- The sequence, in the cart's own order:
--
--   1. `ld de, MUSIC_NONE / call PlayMusic`, then BlankScreen and DisableLCD.
--      isOpaque is therefore correct: the map really is torn down.
--   2. EggHatchGFX's two tiles to vTiles0, the hatchling's frontpic to
--      vTiles2 $00 and the EGG's to $31.
--   3. MUSIC_EVOLUTION, EnableLCD, and the EGG pic laid at hlcoord 7, 4.
--   4. `ld c, 80 / call DelayFrames`: the egg just sits there.
--   5. Eight rounds.  Round r wobbles r times -- each wobble is hSCX = +2 for
--      two frames then -2 for two frames, with wGlobalAnimXOffset carrying the
--      sprites the same way so the cracks stay on the shell -- then sixteen
--      still frames, then EggHatch_CrackShell.
--   6. SFX_EGG_HATCH, ten shell fragments, the HATCHLING's pic at hlcoord 6, 3,
--      then Hatch_ShellFragmentLoop's 129 frames, WaitSFX and PlayMonCry.
--
-- The two sprite objects are built here rather than in
-- src/ui/gen2/SpriteAnims.lua because both are one 8x8 tile with a fixed
-- frameset (data/sprite_anims/framesets.asm .Frameset_EggCrack and
-- .Frameset_EggHatch1..4 are each a single `oamframe ..., 32 / oamend`) and
-- only ONE of the two moves at all.  Coordinates follow the same convention
-- every other caller of _InitSpriteAnimStruct uses (engine/sprite_anims/
-- core.asm:113, "at pixel x=e, y=d"), and OAM's own -8 / -16 bias is applied
-- at draw time exactly as src/ui/gen2/GoldSilverIntro.lua does it.
--
-- Every asset is optional.  A cache built before the extractor grew
-- menu_gfx.eggHatch has no egg pic and no shell tiles, and the screen then
-- runs the same clock with whatever it does have -- which is the timing beat
-- src/world/gen2/World.lua's hatch path used to stand in for on its own.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Music = require("src.core.Music")
local Palettes = require("src.world.gen2.Palettes")
local Sound = require("src.core.Sound")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")

local EggHatchAnim = {}
EggHatchAnim.__index = EggHatchAnim
EggHatchAnim.isOpaque = true

-- Hatch_UpdateFrontpicBGMapCenter is called twice with different hlcoords:
-- the egg sits at (7,4) and the hatchling at (6,3).  Both are `lb bc, 7, 7`
-- PlaceGraphic boxes, and the pic inside that box has already been padded to
-- 7x7 in VRAM, so a 40x40 egg and a 56x56 mon share a ground line.
local EGG_TILE_X, EGG_TILE_Y = 7, 4
local MON_TILE_X, MON_TILE_Y = 6, 3

-- PadFrontpic (engine/gfx/load_pics.asm:342) fills the 7x7 box column by
-- column: one whole blank column first, then per pic column a fixed run of
-- blank tiles above the pic tiles.  `.six` fills one tile per column and
-- `.five` two, so the pic's top-left tile lands at (1,1) and (1,2)
-- respectively and a 7-wide pic fills the box.  Same table, for the same
-- reason, as src/ui/gen2/SummaryMenu.lua:120.
local PIC_PAD = { [7] = { 0, 0 }, [6] = { 1, 1 }, [5] = { 1, 2 } }

-- `ld c, 80 / call DelayFrames` between the egg appearing and the first wobble.
local HOLD_FRAMES = 80
-- `.outerloop`'s `cp 8`: rounds 0..7, so eight of them, and round r (1-based)
-- wobbles r times because `ld e, [hl]` reads the counter AFTER `inc [hl]`.
local ROUNDS = 8
-- Each half of a wobble is `ld c, 2 / call DelayFrames`, i.e. two frames.
local WOBBLE_HALF = 2
-- `ld a, 2 / ldh [hSCX]` then `ld a, -2`: the screen shifts two pixels.
local SHAKE = 2
-- `ld c, 16 / call DelayFrames` after the wobbles of a round.
local STILL_FRAMES = 16
-- Hatch_ShellFragmentLoop's `ld c, 129`.
local FRAGMENT_FRAMES = 129

-- Hatch_InitShellFragments' .SpriteData, one row per `shell_fragment`.  The
-- macro emits two coordinate bytes and Hatch_InitShellFragments loads the first
-- into e and the second into d, which _InitSpriteAnimStruct reads as x and y
-- respectively -- the same pairing `depixel` produces for every other object.
-- `frameset` is the offset from SPRITE_ANIM_FRAMESET_EGG_HATCH_1, and the four
-- framesets differ only in their OAM flip flags (data/sprite_anims/framesets
-- .asm:360-374): 1 plain, 2 X-flipped, 3 Y-flipped, 4 both.
local FRAGMENTS = {
  { x = 10 * 8 + 4, y =  9 * 8,     flipX = false, flipY = false, angle = 0x3c },
  { x = 11 * 8 + 4, y =  9 * 8,     flipX = true,  flipY = false, angle = 0x04 },
  { x = 10 * 8 + 4, y = 10 * 8,     flipX = false, flipY = false, angle = 0x30 },
  { x = 11 * 8 + 4, y = 10 * 8,     flipX = true,  flipY = false, angle = 0x10 },
  { x = 10 * 8 + 4, y = 11 * 8,     flipX = false, flipY = true,  angle = 0x24 },
  { x = 11 * 8 + 4, y = 11 * 8,     flipX = true,  flipY = true,  angle = 0x1c },
  { x = 10 * 8,     y =  9 * 8 + 4, flipX = false, flipY = false, angle = 0x36 },
  { x = 12 * 8,     y =  9 * 8 + 4, flipX = true,  flipY = false, angle = 0x0a },
  { x = 10 * 8,     y = 10 * 8 + 4, flipX = false, flipY = true,  angle = 0x2a },
  { x = 12 * 8,     y = 10 * 8 + 4, flipX = true,  flipY = true,  angle = 0x16 },
}

-- AnimSeq_RevealNewMon: var1 starts at 0 and grows by 8 a frame until it
-- reaches $80, at which point DeinitializeSprite drops the fragment.  Sixteen
-- frames of flight, then the hatchling stands alone for the rest of the loop.
local FRAGMENT_STEP = 8
local FRAGMENT_LIMIT = 0x80

-- Both egg objects use .OAMData_1x1_Palette0, whose single entry is
-- `dbsprite -1, -1, 4, 4, $00, 0` (data/sprite_anims/oam.asm:94-95, 112-114).
-- dbsprite folds tile and pixel into one byte, so that is a per-object -4 on
-- each axis, added by UpdateAnimFrame through AddOrSubtractX/Y on top of the
-- struct coordinate (engine/sprite_anims/core.asm:240-266).  The flip arm
-- computes `-8 - a`, which for a = -4 is -4 again, so the one constant covers
-- all four framesets.  The remaining -8 / -16 is the hardware's own OAM bias,
-- the same one every other Gold screen applies on its way out.
local OAM_X = -8 - 4
local OAM_Y = -16 - 4

function EggHatchAnim:wantsFillScale() return true end
function EggHatchAnim:drawsWidescreen() return true end

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

-- opts:
--   mon      the hatchling's party record (species, shiny, nickname)
--   species  the hatchling's species, when there is no record to hand
--   onDone() the beat after PlayMonCry
function EggHatchAnim.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, EggHatchAnim)
  self.game = game
  self.data = (game and game.data) or {}
  self.palettes = self.data.gen2Palettes
  self.mon = opts.mon
  self.species = opts.species or (self.mon and self.mon.species)
  self.onDone = opts.onDone

  local gfx = (opts.menuGfx or self.data.gen2MenuGfx or {}).eggHatch or {}
  self.eggPath = gfx.egg
  self.shellPath = gfx.shell
  self.picCache = {}
  self.shell = nil
  self.shellQuads = nil

  -- The screen starts on the egg and only swaps to the hatchling at `.done`,
  -- which is the one thing a viewer has to be able to see happen.
  self.showMon = false
  self.shakeX = 0
  self.sprites = {}

  -- `ld de, MUSIC_NONE / call PlayMusic` and then MUSIC_EVOLUTION, with the
  -- map theme handed back by HatchEggs' own RestartMapMusic afterwards.
  Music.stop()
  local songs = self.data.audio and self.data.audio.songs
  if songs and songs.Music_Evolution then
    Music.play(self.data, "Music_Evolution", true, { reason = "hatch" })
  end

  self.beats = self:buildBeats()
  self.beatIndex = 1
  self.beatLeft = self.beats[1] and self.beats[1].frames or 0
  self:runBeat(self.beats[1])
  return self
end

-- The whole sequence as a flat list of { frames, enter }.  Building it up front
-- rather than nesting phase machines is what keeps the frame counts readable
-- against the ASM: every number here is one `DelayFrames` operand.
function EggHatchAnim:buildBeats()
  local beats = {}
  local function beat(frames, enter)
    beats[#beats + 1] = { frames = frames, enter = enter }
  end

  beat(HOLD_FRAMES, function() self.shakeX = 0 end)

  for round = 1, ROUNDS do
    for _ = 1, round do
      beat(WOBBLE_HALF, function() self.shakeX = SHAKE end)
      beat(WOBBLE_HALF, function() self.shakeX = -SHAKE end)
    end
    beat(STILL_FRAMES, function() self.shakeX = 0 end)
    beat(0, function() self:crackShell(round) end)
  end

  -- `.done`: hSCX and wGlobalAnimXOffset are zeroed, ClearSprites drops the
  -- cracks, the fragments go up and the pic becomes the hatchling's.
  beat(FRAGMENT_FRAMES, function()
    self.shakeX = 0
    self.sprites = {}
    self:playSfx("Sfx_EggHatch")
    self:initFragments()
    self.showMon = true
  end)
  -- WaitSFX then `ld a, [wJumptableIndex] / call PlayMonCry`.  The port has no
  -- channel state to poll, so the cry simply follows the loop.
  beat(0, function() self:playCry() end)
  return beats
end

--------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------

function EggHatchAnim:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function EggHatchAnim:playCry()
  local species = self.species
  if not species then return end
  local cries = self.data.audio and self.data.audio.cries
  if cries and cries[species] then Sound.playCry(self.data, species) end
end

--------------------------------------------------------------------------
-- The two sprite objects
--------------------------------------------------------------------------

-- EggHatch_CrackShell (breeding.asm:756).  wFrameCounter has already been
-- incremented, so `dec a / and $7` is the round index 0..7; `cp $7 / ret z`
-- drops the last round and `srl a / ret nc` drops every even one, leaving
-- rounds 2, 4 and 6.  The surviving index picks the y coordinate:
-- `swap a / srl a` is a multiply by eight, and `add 9 * TILE_WIDTH` puts the
-- first crack on tile row 9.  x is the fixed `ld e, 11 * TILE_WIDTH`.
function EggHatchAnim:crackShell(round)
  local a = (round - 1) % 8
  if a == 7 then return end
  if a % 2 == 0 then return end
  local step = math.floor(a / 2)
  self.sprites[#self.sprites + 1] = {
    kind = "crack",
    x = 11 * 8,
    y = step * 8 + 9 * 8,
  }
  self:playSfx("Sfx_EggCrack")
end

-- Hatch_InitShellFragments, then the SFX_EGG_HATCH it ends on (which the
-- caller's `.done` has already played -- the cart plays it twice).
function EggHatchAnim:initFragments()
  for _, row in ipairs(FRAGMENTS) do
    self.sprites[#self.sprites + 1] = {
      kind = "fragment",
      x = row.x, y = row.y,
      flipX = row.flipX, flipY = row.flipY,
      -- SPRITEANIMSTRUCT_JUMPTABLE_INDEX carries the fragment's angle, which
      -- AnimSeq_RevealNewMon flips by $20 every frame.
      angle = row.angle,
      var1 = 0,
      xOffset = 0, yOffset = 0,
    }
  end
end

-- AnimSeq_RevealNewMon (engine/sprite_anims/functions.asm:1270), one frame:
-- the amplitude grows by eight, the angle is XORed with $20, and the sine and
-- cosine of that pair become the fragment's y and x offsets.  So each shard
-- alternates between two opposite headings while drifting further out, which
-- is what reads as tumbling.
local function stepFragment(sprite)
  if sprite.var1 >= FRAGMENT_LIMIT then return false end
  local amplitude = sprite.var1
  sprite.var1 = sprite.var1 + FRAGMENT_STEP
  -- `xor $20` toggles bit 5, i.e. half a period of the six-bit angle.  Written
  -- as a bit test rather than an operator because the engine targets LuaJIT's
  -- 5.1 semantics, where there is none.
  local angle = sprite.angle % 256
  local bit5 = math.floor(angle / 0x20) % 2
  sprite.angle = bit5 == 1 and (angle - 0x20) or (angle + 0x20)
  sprite.yOffset = SpriteAnims.sine(sprite.angle, amplitude)
  sprite.xOffset = SpriteAnims.cosine(sprite.angle, amplitude)
  return true
end

--------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------

function EggHatchAnim:runBeat(beat)
  if beat and beat.enter then beat.enter() end
end

function EggHatchAnim:finish()
  self.done = true
  local cb = self.onDone
  self.onDone = nil
  if cb then cb() end
end

function EggHatchAnim:update(_dt)
  if self.done then return end

  -- EggHatch_DoAnimFrame is PlaySpriteAnimations + DelayFrame, so the sprites
  -- advance on every frame the sequence spends anywhere.  A fragment that has
  -- run out its amplitude leaves the screen: AnimSeq_RevealNewMon's
  -- `.finish_EggShell` is a DeinitializeSprite (engine/sprite_anims/functions
  -- .asm:1303), sixteen frames into a 129-frame loop, so the shards do not
  -- hang in mid-air for the rest of it.  Cracks are never dropped here; the
  -- ClearSprites at `.done` has already emptied the list by then.
  local live = {}
  for _, sprite in ipairs(self.sprites) do
    if sprite.kind ~= "fragment" or stepFragment(sprite) then
      live[#live + 1] = sprite
    end
  end
  self.sprites = live

  while self.beatLeft <= 0 do
    self.beatIndex = self.beatIndex + 1
    local beat = self.beats[self.beatIndex]
    if not beat then return self:finish() end
    self.beatLeft = beat.frames
    self:runBeat(beat)
  end
  self.beatLeft = self.beatLeft - 1
end

--------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------

function EggHatchAnim:image(path)
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    -- `and` truncates a multi-return, so the pcall stands alone.
    local ok, image = pcall(Assets.image, path)
    cached = (ok and image) or false
    self.picCache[path] = cached
  end
  return cached or nil
end

function EggHatchAnim:pic()
  if self.showMon then
    local def = self.species and self.data.pokemon
      and self.data.pokemon[self.species]
    return self:image(def and def.spriteFront)
  end
  return self:image(self.eggPath)
end

-- Hatch_LoadFrontpicPal is SCGB_EVOLUTION with c = 0, i.e. the pic's own
-- palette, and the species it is handed is whatever
-- Hatch_UpdateFrontpicBGMapCenter was called with: EGG while the shell is up.
-- PokemonPalettes carries a real EGG row (data/pokemon/palettes.asm:530) and
-- _CGB_Evolution indexes straight into it through GetPlayerOrMonPalettePointer
-- (engine/gfx/color.asm:620), so the egg gets its own cream and brown.  A
-- cache built before the extractor grew that row has no "EGG" key, and
-- monColors returning nil then leaves the shader off and the raw shades in
-- place, exactly as before.
function EggHatchAnim:picColors()
  local species = self.showMon and self.species or "EGG"
  return Palettes.monColors(self.palettes, species,
    self.mon and self.mon.shiny)
end

function EggHatchAnim:drawPic()
  local image = self:pic()
  if not image then return end
  local G = love.graphics
  local w = image:getWidth()
  local tx = self.showMon and MON_TILE_X or EGG_TILE_X
  local ty = self.showMon and MON_TILE_Y or EGG_TILE_Y
  -- PadFrontpic's own placement, not a centring rule: the two agree at 7 and
  -- 5 wide but a 6-wide pic sits a whole tile in, not half of one.
  local pad = PIC_PAD[math.floor(w / 8)] or PIC_PAD[7]
  local px = tx * 8 + pad[1] * 8
  local py = ty * 8 + pad[2] * 8
  G.setColor(1, 1, 1, 1)
  local colors = self:picColors()
  local function body() G.draw(image, px, py) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
end

-- EggHatchGFX is one tile wide and two tall: tile $00 is the crack
-- (SPRITE_ANIM_OAMSET_EGG_CRACK's `spriteanimoam $00`) and tile $01 the shell
-- fragment (`spriteanimoam $01`), both 1x1 on OBJ palette 0.
function EggHatchAnim:shellQuad(index)
  local image = self:image(self.shellPath)
  if not image then return nil, nil end
  if not self.shellQuads then
    self.shellQuads = {
      love.graphics.newQuad(0, 0, 8, 8, image:getDimensions()),
      love.graphics.newQuad(0, 8, 8, 8, image:getDimensions()),
    }
  end
  return image, self.shellQuads[index]
end

function EggHatchAnim:drawSprites()
  if #self.sprites == 0 then return end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  for _, sprite in ipairs(self.sprites) do
    local slot = sprite.kind == "crack" and 1 or 2
    local image, quad = self:shellQuad(slot)
    if image and quad then
      -- OAM_X / OAM_Y carry both the hardware bias and .OAMData_1x1_Palette0's
      -- own -4, and the draw call below adds the flip origin correction.
      local x = sprite.x + (sprite.xOffset or 0) + OAM_X
      local y = sprite.y + (sprite.yOffset or 0) + OAM_Y
      -- The two offsets are the bytes the ASM leaves in a, i.e. two's
      -- complement, so anything past $7f is a negative drift.
      if (sprite.xOffset or 0) > 0x7f then x = x - 256 end
      if (sprite.yOffset or 0) > 0x7f then y = y - 256 end
      local flipX, flipY = sprite.flipX, sprite.flipY
      G.draw(image, quad,
        x + (flipX and 8 or 0), y + (flipY and 8 or 0), 0,
        flipX and -1 or 1, flipY and -1 or 1)
    end
  end
end

-- BlankScreen leaves the whole tilemap on the palette's colour 0, and nothing
-- prints during the sequence: HatchEggs' text boxes are on either side of it.
function EggHatchAnim:drawPanel()
  Chrome.clear()
  local G = love.graphics
  G.push()
  -- Both layers move the SAME way each wobble half (breeding.asm:707-719):
  -- `ldh [hSCX]` of +2 scrolls the viewport right, i.e. slides the background
  -- two pixels left on screen, and the paired `ld [wGlobalAnimXOffset], -2` is
  -- summed into every object's OAM x byte (engine/sprite_anims/core.asm:253
  -- -266), sliding the sprites two pixels left as well.  So the cracks stay
  -- put on the shell and the whole picture shakes as one.
  G.translate(-(self.shakeX or 0), 0)
  self:drawPic()
  self:drawSprites()
  G.pop()
  G.setColor(1, 1, 1, 1)
end

function EggHatchAnim:draw()
  self:drawPanel()
end

function EggHatchAnim:drawWidescreen(winW, winH)
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

return EggHatchAnim
