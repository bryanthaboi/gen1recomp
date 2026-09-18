-- Sprite callbacks for createsprite templates (pret Anim* ports, pooled).

local AnimSprites = require("src.core.game3.battle.anim_sprites")

local AnimCallbacks = {}

local function destroy(sprite)
  AnimSprites.release(sprite)
end

--- pret AnimHitSplatBasic — IMPACT mark at attacker/target, brief scale-in then destroy.
function AnimCallbacks.HitSplatBasic(sprite)
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local life = sprite.data[0]
  local u = math.min(1, life / 8)
  local sc = 0.55 + 0.55 * u
  if life > 10 then
    sc = sc * (1 - (life - 10) / 6)
  end
  sprite.w = (sprite._baseW or 32) * sc
  sprite.h = (sprite._baseH or 32) * sc
  sprite.alpha = life <= 10 and 1 or math.max(0, 1 - (life - 10) / 6)
  if life >= 16 then
    destroy(sprite)
  end
end
AnimCallbacks.CrossImpact = AnimCallbacks.HitSplatBasic
AnimCallbacks.FlashingHitSplat = AnimCallbacks.HitSplatBasic
AnimCallbacks.HitSplatPersistent = AnimCallbacks.HitSplatBasic

--- pret AnimCuttingSlice + AnimSlice_Step (Cut, Fury Cutter, Air Cutter).
-- args[1]=dx (40), args[2]=dy (-32), args[3]=dir (0=R to L, 1=L to R).
function AnimCallbacks.CuttingSlice(sprite)
  if not sprite._inited then
    sprite._inited = true
    local dir = tonumber(sprite.data[2]) or 0
    sprite.data[0] = 0 -- frame step counter
    sprite.data[1] = -0x400 -- vx_fp (-4.0 px/frame)
    sprite.data[2] = 0x400  -- vy_fp (+4.0 px/frame)
    sprite.data[3] = 0      -- x offset accumulator (fp)
    sprite.data[4] = 0      -- y offset accumulator (fp)
    sprite.data[5] = dir
    if dir == 1 then
      sprite.data[1] = -sprite.data[1]
      sprite.hFlip = true
    else
      sprite.hFlip = false
    end
  end

  -- AnimSlice_Step
  sprite.data[3] = (sprite.data[3] or 0) + (sprite.data[1] or 0)
  sprite.data[4] = (sprite.data[4] or 0) + (sprite.data[2] or 0)
  local dir = sprite.data[5] or 0
  if dir == 0 then
    sprite.data[1] = sprite.data[1] + 0x18
  else
    sprite.data[1] = sprite.data[1] - 0x18
  end
  sprite.data[2] = sprite.data[2] - 0x18

  sprite.ox = math.floor((sprite.data[3] or 0) / 256)
  sprite.oy = math.floor((sprite.data[4] or 0) / 256)

  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step

  -- AnimCmds: 4 frames, 5 ticks per frame (y cell 0, 32, 64, 96)
  local frame = math.min(3, math.floor((step - 1) / 5))
  sprite.quadY = frame * (sprite._baseH or 32)

  if step >= 20 then
    destroy(sprite)
  end
end
AnimCallbacks.AirCutterSlice = AnimCallbacks.CuttingSlice

--- pret AnimSlashSlice / AnimClawSlash / AnimFurySwipes (Slash, Scratch, Claw, False Swipe).
function AnimCallbacks.SlashSlice(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local frame = math.min(3, math.floor((step - 1) / 4))
  sprite.quadY = frame * (sprite._baseH or 32)
  if step >= 16 then
    destroy(sprite)
  end
end
AnimCallbacks.ClawSlash = AnimCallbacks.SlashSlice
AnimCallbacks.FalseSwipeSlice = AnimCallbacks.SlashSlice
AnimCallbacks.FalseSwipePositionedSlice = AnimCallbacks.SlashSlice
AnimCallbacks.FurySwipes = AnimCallbacks.SlashSlice
AnimCallbacks.RevengeScratch = AnimCallbacks.SlashSlice

--- pret AnimBite / AnimFang / AnimSuperFang (Bite, Crunch, Super Fang).
function AnimCallbacks.Bite(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local frame = math.min(3, math.floor((step - 1) / 4))
  sprite.quadY = frame * (sprite._baseH or 32)
  if step >= 16 then
    destroy(sprite)
  end
end
AnimCallbacks.Fang = AnimCallbacks.Bite
AnimCallbacks.SuperFang = AnimCallbacks.Bite

--- pret AnimRoarNoiseLine — noise arcs from attacker (Growl/Roar).
-- arg 0: initial x pixel offset
-- arg 1: initial y pixel offset
-- arg 2: direction (0 = upward, 1 = downward, 2 = horizontal)
function AnimCallbacks.RoarNoiseLine(sprite)
  if not sprite._inited then
    sprite._inited = true
    local dir = tonumber(sprite.data[2]) or 0
    local isOpponent = sprite._reversed and true or false

    local vx = 0x280
    local vy = 0
    local animBank = 0

    if dir == 0 then
      vx = 0x280
      vy = -0x280
      sprite.vFlip = false
    elseif dir == 1 then
      vx = 0x280
      vy = 0x280
      sprite.vFlip = true
    else
      animBank = 1
      vx = 0x280
      vy = 0
      sprite.vFlip = false
    end

    if isOpponent then
      vx = -vx
      sprite.hFlip = true
    else
      sprite.hFlip = false
    end

    sprite.data[0] = vx
    sprite.data[1] = vy
    sprite.data[3] = animBank
    sprite.data[5] = 0
    sprite.data[6] = 0
    sprite.data[7] = 0
  end

  local step = (sprite.data[5] or 0) + 1
  sprite.data[5] = step

  sprite.data[6] = (sprite.data[6] or 0) + (sprite.data[0] or 0)
  sprite.data[7] = (sprite.data[7] or 0) + (sprite.data[1] or 0)
  sprite.ox = math.floor((sprite.data[6] or 0) / 256)
  sprite.oy = math.floor((sprite.data[7] or 0) / 256)

  local bank = sprite.data[3] or 0
  local phase = math.floor((step - 1) / 3) % 2
  local cell = (bank == 0) and phase or (2 + phase)
  sprite.quadY = cell * (sprite._baseH or 32)

  if step >= 14 then
    destroy(sprite)
  end
end

--- Projectile trajectory (BulletSeed, WaterBubbleProjectile, etc.).
function AnimCallbacks.ThrowProjectile(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[5] = 16
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local dur = sprite.data[5] or 16
  local u = math.min(1, step / dur)
  local h = math.sin(u * math.pi) * 20
  sprite.ox = math.floor((sprite._dx or 0) * u)
  sprite.oy = math.floor((sprite._dy or 0) * u - h)
  if step >= dur then
    destroy(sprite)
  end
end
AnimCallbacks.BulletSeed = AnimCallbacks.ThrowProjectile
AnimCallbacks.WaterBubbleProjectile = AnimCallbacks.ThrowProjectile
AnimCallbacks.SludgeProjectile = AnimCallbacks.ThrowProjectile
AnimCallbacks.BoneHitProjectile = AnimCallbacks.ThrowProjectile

--- pret AnimSpriteOnMonPos — plays sprite sheet frames centered on mon position
function AnimCallbacks.SpriteOnMonPos(sprite)
  if sprite.tag == "ECLIPSING_ORB" then
    return AnimCallbacks.EclipsingOrb(sprite)
  end
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  local frame = math.min(totalFrames - 1, math.floor((step - 1) / 3))
  sprite.quadY = frame * cellH
  if step >= totalFrames * 3 then
    destroy(sprite)
  end
end

--- pret sEclipsingOrbAnimCmds (Defense Curl orb bubble expansion/contraction).
function AnimCallbacks.EclipsingOrb(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step

  local frameSeq = {
    { cell = 0, hFlip = false },
    { cell = 1, hFlip = false },
    { cell = 2, hFlip = false },
    { cell = 3, hFlip = false },
    { cell = 2, hFlip = true },
    { cell = 1, hFlip = true },
    { cell = 0, hFlip = true },
  }
  local cycleTick = (step - 1) % 21
  local idx = math.min(7, math.floor(cycleTick / 3) + 1)
  local f = frameSeq[idx] or frameSeq[1]
  sprite.quadY = f.cell * (sprite._baseH or 32)
  sprite.hFlip = f.hFlip

  if step >= 42 then
    destroy(sprite)
  end
end
--- pret AnimMovePowderParticle (PoisonPowder, StunSpore, SleepPowder, CottonSpore).
-- Sprites fall downwards with sinusoidal sway onto the target Pokémon.
function AnimCallbacks.MovePowderParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = tonumber(args[3]) or 80
    sprite._vy = (tonumber(args[4]) or 80) / 256
    local amp = tonumber(args[5]) or 5
    if sprite._reversed then amp = -amp end
    sprite._amp = amp
    sprite._speed = tonumber(args[6]) or 1
    sprite._phase = 0
    sprite._yAccum = 0
    sprite._step = 0
  end

  sprite._step = sprite._step + 1
  sprite._yAccum = sprite._yAccum + sprite._vy
  sprite.oy = math.floor(sprite._yAccum)
  sprite._phase = (sprite._phase + sprite._speed) % 256
  sprite.ox = math.floor(math.sin(sprite._phase * 2 * math.pi / 256) * sprite._amp)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end

--- pret AnimAbsorptionOrb (Absorb, Mega Drain, Giga Drain, Leech Life).
-- Energy orbs travel from target to attacker in an arc.
function AnimCallbacks.AbsorptionOrb(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = math.max(12, tonumber(args[4]) or 20)
    sprite._amp = tonumber(args[3]) or 16
    sprite._step = 0
    sprite._startX = sprite.x
    sprite._startY = sprite.y
    local ax, ay = sprite._attackerX or sprite.x, sprite._attackerY or sprite.y
    sprite._dx = ax - sprite._startX
    sprite._dy = ay - sprite._startY
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  local arc = math.sin(u * math.pi) * sprite._amp
  sprite.ox = math.floor(sprite._dx * u)
  sprite.oy = math.floor(sprite._dy * u - arc)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.PowerAbsorptionOrb = AnimCallbacks.AbsorptionOrb

--- Linear / projectile translation to target mon location (Ember, Water Gun, Heart, etc.).
-- pokefirered/src/battle_anim_mons.c:1440 TranslateAnimSpriteToTargetMonLocation
function AnimCallbacks.TranslateAnimSpriteToTargetMonLocation(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = math.max(1, tonumber(args[5]) or 20)
    sprite._step = 0
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.ox = math.floor((sprite._dx or 0) * u)
  sprite.oy = math.floor((sprite._dy or 0) * u)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.TranslateLinearSingleSineWave = AnimCallbacks.TranslateAnimSpriteToTargetMonLocation
AnimCallbacks.PainSplitProjectile = AnimCallbacks.TranslateAnimSpriteToTargetMonLocation
AnimCallbacks.RedHeartProjectile = AnimCallbacks.TranslateAnimSpriteToTargetMonLocation

--- Diagonal travel with flame animation (Ember flare, Burn flame, TravelDiagonally).
-- pokefirered/src/battle_anim_fire.c:603 & pokefirered/src/battle_anim_mons.c:1482
function AnimCallbacks.AnimTravelDiagonally(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = math.max(1, tonumber(args[5]) or 20)
    sprite._step = 0
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.ox = math.floor((sprite._dx or 0) * u)
  sprite.oy = math.floor((sprite._dy or 0) * u)

  -- sAnim_BasicFire: 5 frames (32x32 each), 4 ticks per frame (20 ticks full loop)
  local cellH = sprite._baseH or 32
  local totalFrames = 5
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 4) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.TravelDiagonally = AnimCallbacks.AnimTravelDiagonally
AnimCallbacks.AnimEmberFlare = AnimCallbacks.AnimTravelDiagonally
AnimCallbacks.EmberFlare = AnimCallbacks.AnimTravelDiagonally
AnimCallbacks.AnimBurnFlame = AnimCallbacks.AnimTravelDiagonally
AnimCallbacks.BurnFlame = AnimCallbacks.AnimTravelDiagonally

--- Floating / drifting particles (Petal Dance, Sweet Scent, Razor Leaf, Flying Particle).
function AnimCallbacks.FlyingParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._dur = 32
    sprite._step = 0
    local args = sprite._args or {}
    sprite._vx = (tonumber(args[3]) or 1) * (sprite._reversed and -1 or 1)
    sprite._vy = tonumber(args[4]) or 1
  end

  sprite._step = sprite._step + 1
  sprite.ox = (sprite.ox or 0) + sprite._vx
  sprite.oy = (sprite.oy or 0) + sprite._vy

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 4) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.PetalDanceSmallFlower = AnimCallbacks.FlyingParticle
AnimCallbacks.PetalDanceBigFlower = AnimCallbacks.FlyingParticle
AnimCallbacks.SweetScentPetal = AnimCallbacks.FlyingParticle
AnimCallbacks.RazorLeafParticle = AnimCallbacks.FlyingParticle
AnimCallbacks.FallingFeather = AnimCallbacks.FlyingParticle

--- Falling rocks / projectiles (Rock Slide, Rock Tomb, Eruption).
function AnimCallbacks.FallingRock(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 20
    sprite.oy = -60
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.oy = math.floor(-60 + 60 * (u * u))

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.EruptionFallingRock = AnimCallbacks.FallingRock
AnimCallbacks.RockFragment = AnimCallbacks.FallingRock
AnimCallbacks.RockTomb = AnimCallbacks.FallingRock

--- Flames rising and expanding (Ember, Flamethrower, Fire Blast, Outrage).
function AnimCallbacks.LargeFlame(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 24
  end

  sprite._step = sprite._step + 1
  sprite.oy = -(sprite._step * 0.75)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.OutrageFlame = AnimCallbacks.LargeFlame
AnimCallbacks.OverheatFlame = AnimCallbacks.LargeFlame
AnimCallbacks.DragonFireToTarget = AnimCallbacks.LargeFlame
AnimCallbacks.DragonRageFirePlume = AnimCallbacks.LargeFlame
AnimCallbacks.FireSpiralInward = AnimCallbacks.LargeFlame

--- Sparkling stars & twinkle particles (Wish, Swift, Moonlight, Morning Sun).
function AnimCallbacks.GrantingStars(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 20
  end

  sprite._step = sprite._step + 1
  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.SparklingStars = AnimCallbacks.GrantingStars
AnimCallbacks.EyeSparkle = AnimCallbacks.GrantingStars
AnimCallbacks.WallSparkle = AnimCallbacks.GrantingStars
AnimCallbacks.MoonlightSparkle = AnimCallbacks.GrantingStars

--- Status / Emote particles (Confuse Duck, Hearts, Tears, Alert, Anger).
function AnimCallbacks.DizzyPunchDuck(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 36
  end

  sprite._step = sprite._step + 1
  local angle = (sprite._step / 36) * math.pi * 4
  sprite.ox = math.floor(math.cos(angle) * 16)
  sprite.oy = math.floor(math.sin(angle) * 6 - 8)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.AngerMark = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.TealAlert = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.TearDrop = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.PinkHeart = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RedHeartRising = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RedHeartProjectile = AnimCallbacks.TranslateAnimSpriteToTargetMonLocation

--- Swirling vortex & orbiting debris (Twister, Whirlpool, Sandstorm, Fire Spin).
function AnimCallbacks.ParticleInVortex(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 32
    sprite._radius = 24
    sprite._angle = (tonumber(sprite.data[1]) or 0) * (math.pi / 4)
  end

  sprite._step = sprite._step + 1
  sprite._angle = sprite._angle + 0.22
  sprite.rotation = sprite._angle

  local r = sprite._radius * (1.0 - (sprite._step / sprite._dur) * 0.4)
  sprite.ox = math.floor(math.cos(sprite._angle) * r + 0.5)
  sprite.oy = math.floor(math.sin(sprite._angle) * (r * 0.45) - (sprite._step * 0.6) + 0.5)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.MoveTwisterParticle = AnimCallbacks.ParticleInVortex
AnimCallbacks.WhirlwindLine = AnimCallbacks.ParticleInVortex
AnimCallbacks.FlyingSandCrescent = AnimCallbacks.ParticleInVortex
AnimCallbacks.OrbitFast = AnimCallbacks.ParticleInVortex
AnimCallbacks.OrbitScatter = AnimCallbacks.ParticleInVortex

--- Energy orbs with pulsing affine scale and rotation (Dragon Dance, Meteor Mash, Power Orbs).
function AnimCallbacks.DragonDanceOrb(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 28
  end

  sprite._step = sprite._step + 1
  sprite.rotation = sprite.rotation + 0.15
  local pulse = 1.0 + math.sin((sprite._step / 28) * math.pi * 3) * 0.25
  sprite.scaleX = pulse
  sprite.scaleY = pulse

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.MeteorMashStar = AnimCallbacks.DragonDanceOrb
AnimCallbacks.ReversalOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SpitUpOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SwallowBlueOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SuperpowerOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SuperpowerRock = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SuperpowerFireball = AnimCallbacks.DragonDanceOrb
AnimCallbacks.EndureEnergy = AnimCallbacks.DragonDanceOrb
AnimCallbacks.TailGlowOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.ThunderboltOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.GrowingChargeOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.GrowingShockWaveOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SharpenSphere = AnimCallbacks.DragonDanceOrb
AnimCallbacks.TriAttackTriangle = AnimCallbacks.DragonDanceOrb

--- Projectiles & multi-hit stingers (Pin Missile, Twineedle, Spike Cannon, Poison Sting).
function AnimCallbacks.TranslateStinger(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 16
    local dx = sprite._dx or (sprite._reversed and -80 or 80)
    local dy = sprite._dy or (sprite._reversed and 40 or -40)
    sprite.rotation = math.atan2(dy, dx)
  end

  sprite._step = sprite._step + 1
  local progress = sprite._step / sprite._dur
  sprite.ox = math.floor((sprite._dx or 0) * progress + 0.5)
  sprite.oy = math.floor((sprite._dy or 0) * progress + 0.5)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.BonemerangProjectile = AnimCallbacks.TranslateStinger
AnimCallbacks.SonicBoomProjectile = AnimCallbacks.TranslateStinger
AnimCallbacks.RockBlastRock = AnimCallbacks.TranslateStinger
AnimCallbacks.LeechLifeNeedle = AnimCallbacks.TranslateStinger
AnimCallbacks.ThrowMistBall = AnimCallbacks.TranslateStinger

--- Ice Beam / Blizzard crystal streams.
function AnimCallbacks.IceBeamParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 18
  end

  sprite._step = sprite._step + 1
  sprite.rotation = sprite.rotation + 0.2
  local progress = sprite._step / sprite._dur
  sprite.ox = math.floor((sprite._dx or 0) * progress + 0.5)
  sprite.oy = math.floor((sprite._dy or 0) * progress + 0.5)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.IcePunchSwirlingParticle = AnimCallbacks.ParticleInVortex

--- Sludge Bomb / Acid / Poison Gas particles.
function AnimCallbacks.SludgeBombHitParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 20
    sprite._vx = (math.random() - 0.5) * 2.5
    sprite._vy = -math.random() * 2.0
  end

  sprite._step = sprite._step + 1
  sprite._vy = sprite._vy + 0.18 -- gravity
  sprite.ox = math.floor((sprite.ox or 0) + sprite._vx + 0.5)
  sprite.oy = math.floor((sprite.oy or 0) + sprite._vy + 0.5)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.AcidPoisonDroplet = AnimCallbacks.SludgeBombHitParticle
AnimCallbacks.AcidPoisonBubble = AnimCallbacks.SludgeBombHitParticle
AnimCallbacks.InitPoisonGasCloudAnim = AnimCallbacks.SludgeBombHitParticle

--- Radial particle explosion (Explosion, Self-Destruct, Swift burst).
function AnimCallbacks.ParticleBurst(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 24
    local angle = math.random() * math.pi * 2
    local speed = 1.5 + math.random() * 2.0
    sprite._vx = math.cos(angle) * speed
    sprite._vy = math.sin(angle) * speed
  end

  sprite._step = sprite._step + 1
  sprite.ox = math.floor((sprite.ox or 0) + sprite._vx + 0.5)
  sprite.oy = math.floor((sprite.oy or 0) + sprite._vy + 0.5)
  sprite.alpha = math.max(0, 1.0 - (sprite._step / sprite._dur))

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end

--- Additive energy shields & barriers (Reflect, Light Screen, Barrier, Protect).
function AnimCallbacks.DefensiveWall(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 36
    sprite.blendMode = "add"
  end

  sprite._step = sprite._step + 1
  local pulse = 0.6 + math.sin((sprite._step / 36) * math.pi * 4) * 0.35
  sprite.alpha = pulse

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.GuardRing = AnimCallbacks.DefensiveWall
AnimCallbacks.BlendThinRing = AnimCallbacks.DefensiveWall
AnimCallbacks.Protect = AnimCallbacks.DefensiveWall
AnimCallbacks.WhiteHalo = AnimCallbacks.DefensiveWall

--- Barrier overlays & entanglements (Block, Disable, Spikes, Web).
AnimCallbacks.BlockX = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RedX = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SpiderWeb = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Spikes = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.StringWrap = AnimCallbacks.SpriteOnMonPos

--- Musical notes & sound waves (Sing, Heal Bell, Perish Song, Growl, Roar, Screech, Snore).
function AnimCallbacks.HealBellMusicNote(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 32
    sprite._freq = 0.15 + (tonumber(sprite.data[1]) or 0) * 0.05
  end

  sprite._step = sprite._step + 1
  sprite.oy = -(sprite._step * 0.9)
  sprite.ox = math.floor(math.sin(sprite._step * sprite._freq) * 8 + 0.5)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.PerishSongMusicNote = AnimCallbacks.HealBellMusicNote
AnimCallbacks.PerishSongMusicNote2 = AnimCallbacks.HealBellMusicNote
AnimCallbacks.FlyingMusicNotes = AnimCallbacks.HealBellMusicNote
AnimCallbacks.SlowFlyingMusicNotes = AnimCallbacks.HealBellMusicNote
AnimCallbacks.JaggedMusicNote = AnimCallbacks.HealBellMusicNote
AnimCallbacks.UproarRing = AnimCallbacks.DefensiveWall

--- Snooze Z's and smoke puffs (Rest, Yawn, Smokescreen).
function AnimCallbacks.SleepLetterZ(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 28
  end

  sprite._step = sprite._step + 1
  sprite.oy = -(sprite._step * 0.7)
  sprite.ox = math.floor(math.sin(sprite._step * 0.2) * 6 + 0.5)
  sprite.alpha = math.max(0, 1.0 - (sprite._step / sprite._dur) * 0.7)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.LetterZ = AnimCallbacks.SleepLetterZ
AnimCallbacks.YawnCloud = AnimCallbacks.SleepLetterZ
AnimCallbacks.BlackSmoke = AnimCallbacks.SleepLetterZ
AnimCallbacks.BreathPuff = AnimCallbacks.SleepLetterZ
AnimCallbacks.MovementWaves = AnimCallbacks.SpriteOnMonPos

--- Combat emotes and props (Metronome, Clapping, Fingers, Spoons, Eyes).
function AnimCallbacks.MetronomeFinger(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 36
  end

  sprite._step = sprite._step + 1
  sprite.rotation = math.sin((sprite._step / 36) * math.pi * 6) * 0.35

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.FollowMeFinger = AnimCallbacks.MetronomeFinger
AnimCallbacks.TauntFinger = AnimCallbacks.MetronomeFinger
AnimCallbacks.BellyDrumHand = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.HelpingHandClap = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SmellingSaltsHand = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ClappingHand = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ClappingHand2 = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ForesightMagnifyingGlass = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.MeanLookEye = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.BentSpoon = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Pencil = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ThoughtBubble = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.TrickBag = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.BatonPassPokeball = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Present = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Moon = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Angel = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Devil = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.QuestionMark = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SmellingSaltExclamation = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.GreenStar = AnimCallbacks.GrantingStars
AnimCallbacks.WeakFrustrationAngerMark = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.KnockOffStrike = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.LockOnTarget = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.LockOnMoveTarget = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.MilkBottle = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Leer = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.FallingCoin = AnimCallbacks.FallingRock
AnimCallbacks.CoinThrow = AnimCallbacks.ThrowProjectile
AnimCallbacks.FlatterSpotlight = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.FlatterConfetti = AnimCallbacks.FlyingParticle
AnimCallbacks.PsychoBoost = AnimCallbacks.ParticleInVortex
AnimCallbacks.Spotlight = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Recycle = AnimCallbacks.ParticleInVortex
AnimCallbacks.SlideHandOrFootToTarget = AnimCallbacks.TranslateStinger
AnimCallbacks.GustToTarget = AnimCallbacks.TranslateStinger
AnimCallbacks.EllipticalGust = AnimCallbacks.ParticleInVortex
AnimCallbacks.FistOrFootRandomPos = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SporeParticle = AnimCallbacks.MovePowderParticle
AnimCallbacks.TravelDiagonally = AnimCallbacks.TranslateStinger
AnimCallbacks.RapidSpin = AnimCallbacks.ParticleInVortex
AnimCallbacks.Lick = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Conversion = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Conversion2 = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RaiseSprite = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ComplexPaletteBlend = AnimCallbacks.SpriteOnMonPos

--- pret AnimLightning — 5-frame lightning bolt strike downward on target (Thunderbolt, Thunder, Spark).
function AnimCallbacks.Lightning(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite.z = AnimSprites.Z.GLOBAL_FRONT
  end
  sprite._step = sprite._step + 1
  local cellH = sprite._baseH or 32
  local totalFrames = 5
  local frame = math.min(totalFrames - 1, math.floor((sprite._step - 1) / 4))
  sprite.quadY = frame * cellH
  if sprite._step >= totalFrames * 4 then
    destroy(sprite)
  end
end
AnimCallbacks.ElectricPuff = AnimCallbacks.Lightning
AnimCallbacks.ElectricBoltSegment = AnimCallbacks.Lightning
AnimCallbacks.ShockWaveLightning = AnimCallbacks.Lightning

--- pret AnimSparkElectricityFlashing — multi-spark rotating flash around battler (Thunder Punch, Zap Cannon).
function AnimCallbacks.SparkElectricityFlashing(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    local args = sprite._args or {}
    sprite._dur = math.max(12, tonumber(args[4]) or 24)
    sprite._radius = tonumber(args[3]) or 20
    sprite._speed = tonumber(args[6]) or 8
    sprite._angle = (tonumber(args[5]) or 0) * (math.pi / 128)
    sprite.z = AnimSprites.Z.GLOBAL_FRONT
  end
  sprite._step = sprite._step + 1
  sprite._angle = sprite._angle + (sprite._speed * 0.05)
  sprite.ox = math.floor(math.cos(sprite._angle) * sprite._radius)
  sprite.oy = math.floor(math.sin(sprite._angle) * (sprite._radius * 0.6))
  sprite.alpha = (sprite._step % 3 == 0) and 0.4 or 1.0
  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.ZapCannonSpark = AnimCallbacks.SparkElectricityFlashing
AnimCallbacks.SparkElectricity = AnimCallbacks.SparkElectricityFlashing
AnimCallbacks.VoltTackleOrbSlide = AnimCallbacks.SparkElectricityFlashing

--- pret AnimBasicFistOrFoot — physical punch/kick strike on attacker/target (Mega Punch, Fire/Ice/Thunder Punch, Mega Kick).
function AnimCallbacks.BasicFistOrFoot(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    local args = sprite._args or {}
    local animNum = tonumber(args[5]) or 0
    local dur = math.max(12, tonumber(args[3]) or 18)
    sprite._dur = dur
    local cellH = sprite._baseH or 32
    sprite.quadY = (animNum % 4) * cellH
    sprite.z = AnimSprites.Z.GLOBAL_FRONT
  end
  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / (sprite._dur or 18))
  local sc = (u < 0.3) and (0.7 + u * 1.5) or 1.0
  sprite.w = math.floor((sprite._baseW or 32) * sc)
  sprite.h = math.floor((sprite._baseH or 32) * sc)
  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.SpinningKickOrPunch = AnimCallbacks.BasicFistOrFoot
AnimCallbacks.SlidingKick = AnimCallbacks.BasicFistOrFoot
AnimCallbacks.JumpKick = AnimCallbacks.BasicFistOrFoot
AnimCallbacks.StompFoot = AnimCallbacks.BasicFistOrFoot
AnimCallbacks.CrossChopHand = AnimCallbacks.BasicFistOrFoot

--- pret AnimNeedleArmSpike — projectile spikes flying in linear trajectory (Needle Arm, Pin Missile, Poison Sting, Spikes).
function AnimCallbacks.NeedleArmSpike(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    local args = sprite._args or {}
    local dur = math.max(8, tonumber(args[5]) or 16)
    sprite._dur = dur
    local targetX = tonumber(args[3]) or 0
    local targetY = tonumber(args[4]) or 0
    sprite._dx = targetX
    sprite._dy = targetY
    sprite.rotation = math.atan2(targetY, targetX)
    sprite.z = AnimSprites.Z.MID_FIELD
  end
  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.ox = math.floor((sprite._dx or 0) * u)
  sprite.oy = math.floor((sprite._dy or 0) * u)
  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.Spikes = AnimCallbacks.NeedleArmSpike
AnimCallbacks.PoisonSting = AnimCallbacks.NeedleArmSpike
AnimCallbacks.PinMissile = AnimCallbacks.NeedleArmSpike

--- pret AnimHitSplatRandom / AnimHitSplatHandleInvert — scattered multi-hit splats (Fury Swipes, Double Slap).
function AnimCallbacks.HitSplatRandom(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite.ox = math.random(-16, 16)
    sprite.oy = math.random(-16, 16)
    sprite.z = AnimSprites.Z.GLOBAL_FRONT
  end
  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / 8)
  local sc = 0.6 + 0.5 * u
  sprite.w = math.floor((sprite._baseW or 32) * sc)
  sprite.h = math.floor((sprite._baseH or 32) * sc)
  sprite.alpha = (sprite._step <= 8) and 1.0 or math.max(0, 1 - (sprite._step - 8) / 6)
  if sprite._step >= 14 then
    destroy(sprite)
  end
end
AnimCallbacks.HitSplatHandleInvert = AnimCallbacks.HitSplatRandom

--- pret AnimMudSportDirt — mud splatter arching and dripping (Mud-Slap, Mud Shot, Mud Sport).
function AnimCallbacks.MudSportDirt(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    local args = sprite._args or {}
    sprite._dur = math.max(10, tonumber(args[3]) or 20)
    sprite._vx = math.random(-12, 12)
    sprite._vy = -math.random(15, 30)
    sprite.z = AnimSprites.Z.GLOBAL_BEHIND
  end
  sprite._step = sprite._step + 1
  local t = sprite._step
  sprite.ox = math.floor(sprite._vx * (t / 10))
  sprite.oy = math.floor(sprite._vy * (t / 10) + (0.5 * 3.8 * (t / 10)^2))
  sprite.alpha = math.max(0, 1 - sprite._step / sprite._dur)
  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.MudSlap = AnimCallbacks.MudSportDirt
AnimCallbacks.MudShot = AnimCallbacks.MudSportDirt

--- pret AnimSmallDriftingBubbles (pokefirered/src/battle_anim_water.c:1011)
-- args: [1]=dx, [2]=dy
function AnimCallbacks.SmallDriftingBubbles(sprite)
  if not sprite._inited then
    sprite._inited = true
    local r1 = math.random(0, 255) + 256
    local r2 = math.random(0, 511)
    if r2 > 255 then r2 = 256 - r2 end
    sprite.data[0] = 0   -- step counter
    sprite.data[1] = r1  -- Q8.8 vx
    sprite.data[2] = r2  -- Q8.8 vy
    sprite.data[3] = 0   -- Q8.8 x accumulator
    sprite.data[4] = 0   -- Q8.8 y accumulator
    sprite.z = AnimSprites.Z.FRONT
  end

  sprite.data[3] = (sprite.data[3] or 0) + (sprite.data[1] or 256)
  sprite.data[4] = (sprite.data[4] or 0) + (sprite.data[2] or 128)

  if (sprite.data[1] % 2) == 1 then
    sprite.ox = -math.floor((sprite.data[3] or 0) / 256)
  else
    sprite.ox = math.floor((sprite.data[3] or 0) / 256)
  end
  sprite.oy = math.floor((sprite.data[4] or 0) / 256)

  sprite.data[0] = (sprite.data[0] or 0) + 1
  if sprite.data[0] >= 21 then
    destroy(sprite)
  end
end

--- pret AnimBubbleEffect (pokefirered/src/battle_anim_water.c:286)
-- Floating bubble with horizontal sine oscillation and pop
function AnimCallbacks.BubbleEffect(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0  -- step
    sprite.data[1] = 0  -- sine phase
    sprite.data[2] = math.random(18, 28) -- duration
    sprite.z = AnimSprites.Z.FRONT
  end

  sprite.data[0] = (sprite.data[0] or 0) + 1
  sprite.data[1] = ((sprite.data[1] or 0) + 12) % 256
  sprite.ox = math.floor(math.sin((sprite.data[1] / 256) * 2 * math.pi) * 6)
  sprite.oy = -(sprite.data[0] * 1.2)

  local u = sprite.data[0] / sprite.data[2]
  local sc = 0.6 + 0.5 * u
  sprite.w = math.floor((sprite._baseW or 16) * sc)
  sprite.h = math.floor((sprite._baseH or 16) * sc)
  sprite.alpha = math.max(0, 1.0 - u * 0.3)

  if sprite.data[0] >= sprite.data[2] then
    destroy(sprite)
  end
end
AnimCallbacks.SmallBubblePair = AnimCallbacks.BubbleEffect
AnimCallbacks.WaterPulseBubble = AnimCallbacks.BubbleEffect
AnimCallbacks.WaterGunDroplet = AnimCallbacks.BubbleEffect
AnimCallbacks.WaterPulseRing = AnimCallbacks.BubbleEffect

--- pret AnimFirePlume (pokefirered/src/battle_anim_fire.c:486)
-- arg 0: dx, arg 1: dy, arg 2: duration, arg 3: dy_step, arg 4: dx_step, arg 5: unused
function AnimCallbacks.FirePlume(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    local dx = tonumber(args[1]) or 0
    local dy = tonumber(args[2]) or 0
    local dur = tonumber(args[3]) or 20
    local dyStep = tonumber(args[4]) or -2
    local dxStep = tonumber(args[5]) or 0
    if sprite._reversed then
      dxStep = -dxStep
    end
    sprite.data[0] = 0      -- step
    sprite.data[1] = dur    -- lifetime
    sprite.data[2] = dxStep -- x velocity
    sprite.data[3] = dyStep -- y velocity
    sprite.data[4] = dur    -- move duration
    sprite.z = AnimSprites.Z.FRONT
  end

  sprite.data[0] = (sprite.data[0] or 0) + 1
  if sprite.data[0] < (sprite.data[4] or 20) then
    sprite.ox = (sprite.ox or 0) + (sprite.data[2] or 0)
    sprite.oy = (sprite.oy or 0) + (sprite.data[3] or -2)
  end

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite.data[0] - 1) / 3) % totalFrames) * cellH
  sprite.alpha = math.max(0, 1.0 - (sprite.data[0] / (sprite.data[1] or 20)) * 0.4)

  if sprite.data[0] >= (sprite.data[1] or 20) then
    destroy(sprite)
  end
end

--- pret AnimFireSpiralOutward (pokefirered/src/battle_anim_fire.c:703)
-- arg 0: unused, arg 1: unused, arg 2: duration, arg 3: startDelay
function AnimCallbacks.FireSpiralOutward(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite.data[0] = tonumber(args[4]) or 0   -- delay
    sprite.data[1] = tonumber(args[3]) or 24  -- duration
    sprite.data[2] = 0                       -- radius Q8.8
    sprite.data[3] = (tonumber(args[5]) or 0) * 32 -- angle
    sprite.z = AnimSprites.Z.FRONT
  end

  if (sprite.data[0] or 0) > 0 then
    sprite.data[0] = sprite.data[0] - 1
    sprite.alpha = 0
    return
  end
  sprite.alpha = 1

  local angle = sprite.data[3] or 0
  local radius = math.floor((sprite.data[2] or 0) / 256)
  sprite.ox = math.floor(math.sin((angle / 256) * 2 * math.pi) * radius)
  sprite.oy = math.floor(math.cos((angle / 256) * 2 * math.pi) * (radius * 0.6))
  sprite.data[3] = (angle + 10) % 256
  sprite.data[2] = (sprite.data[2] or 0) + 0xD0

  local cellH = sprite._baseH or 16
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor(angle / 32) % totalFrames) * cellH

  sprite.data[1] = (sprite.data[1] or 24) - 1
  if sprite.data[1] <= 0 then
    destroy(sprite)
  end
end

--- pret AnimElectricity / AnimSparkElectricity (pokefirered/src/battle_anim_electric.c:85, 140)
function AnimCallbacks.Electricity(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[1] = 16 -- duration
    sprite.z = AnimSprites.Z.FRONT
  end
  sprite.data[0] = (sprite.data[0] or 0) + 1
  sprite.ox = math.random(-8, 8)
  sprite.oy = math.random(-8, 8)
  sprite.hFlip = (math.random() > 0.5)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite.data[0] - 1) / 2) % totalFrames) * cellH

  if sprite.data[0] >= sprite.data[1] then
    destroy(sprite)
  end
end
AnimCallbacks.SparkElectricity = AnimCallbacks.Electricity
AnimCallbacks.ThunderboltSegment = AnimCallbacks.Electricity

--- pret AnimSolarBeamBigOrb / AnimSolarBeamSmallOrb (pokefirered/src/battle_anim_effects_2.c:400)
function AnimCallbacks.SolarBeamBigOrb(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[1] = 24
    sprite.z = AnimSprites.Z.FRONT
  end
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local progress = sprite.data[0] / sprite.data[1]
  local sc = 0.5 + 0.7 * math.min(1.0, progress * 1.5)
  sprite.w = math.floor((sprite._baseW or 32) * sc)
  sprite.h = math.floor((sprite._baseH or 32) * sc)
  sprite.rotation = (sprite.rotation or 0) + 0.15

  if sprite.data[0] >= sprite.data[1] then
    destroy(sprite)
  end
end
AnimCallbacks.SolarBeamSmallOrb = AnimCallbacks.SolarBeamBigOrb
AnimCallbacks.GrowingChargeOrb = AnimCallbacks.SolarBeamBigOrb

--- pret AnimWeatherBallDown / AnimWeatherBallUp (pokefirered/src/battle_anim_effects_2.c:650)
function AnimCallbacks.WeatherBallDown(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[1] = 20
    sprite.z = AnimSprites.Z.FRONT
  end
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local progress = sprite.data[0] / sprite.data[1]
  sprite.oy = math.floor(progress * 48)
  sprite.rotation = (sprite.rotation or 0) + 0.1

  if sprite.data[0] >= sprite.data[1] then
    destroy(sprite)
  end
end
AnimCallbacks.WeatherBallUp = AnimCallbacks.WeatherBallDown
AnimCallbacks.ZapCannonBall = AnimCallbacks.WeatherBallDown

--- pret AnimIceEffectParticle / AnimSwirlingSnowball (pokefirered/src/battle_anim_ice.c:95, 180)
function AnimCallbacks.IceEffectParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[1] = 20
    sprite.data[2] = (math.random() - 0.5) * 1.5 -- vx
    sprite.data[3] = 1.2 + math.random() * 0.8  -- vy
    sprite.z = AnimSprites.Z.FRONT
  end
  sprite.data[0] = (sprite.data[0] or 0) + 1
  sprite.ox = math.floor((sprite.ox or 0) + sprite.data[2])
  sprite.oy = math.floor((sprite.oy or 0) + sprite.data[3])
  sprite.rotation = (sprite.rotation or 0) + 0.12

  if sprite.data[0] >= sprite.data[1] then
    destroy(sprite)
  end
end
AnimCallbacks.SwirlingSnowball = AnimCallbacks.IceEffectParticle
AnimCallbacks.IceBallChunk = AnimCallbacks.IceEffectParticle

--- pret AnimDirtPlumeParticle / AnimRockScatter / AnimDirtScatter (pokefirered/src/battle_anim_ground.c:110, 210)
function AnimCallbacks.DirtPlumeParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[1] = 22
    sprite.data[2] = (math.random() - 0.5) * 2.0 -- vx
    sprite.data[3] = -2.5 - math.random() * 1.5  -- vy initial upward
    sprite.z = AnimSprites.Z.FRONT
  end
  sprite.data[0] = (sprite.data[0] or 0) + 1
  sprite.data[3] = sprite.data[3] + 0.25 -- gravity
  sprite.ox = math.floor((sprite.ox or 0) + sprite.data[2])
  sprite.oy = math.floor((sprite.oy or 0) + sprite.data[3])

  if sprite.data[0] >= sprite.data[1] then
    destroy(sprite)
  end
end
AnimCallbacks.RockScatter = AnimCallbacks.DirtPlumeParticle
AnimCallbacks.DirtScatter = AnimCallbacks.DirtPlumeParticle
AnimCallbacks.MudSportDirt = AnimCallbacks.DirtPlumeParticle
AnimCallbacks.SandAttackMud = AnimCallbacks.DirtPlumeParticle
AnimCallbacks.MudSand = AnimCallbacks.DirtPlumeParticle

--- pret AnimWaveFromCenterOfTarget / AnimAirWaveCrescent / AnimSoundWave (pokefirered/src/battle_anim_sound.c:220, 270)
function AnimCallbacks.WaveFromCenterOfTarget(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[1] = 20
    sprite.z = AnimSprites.Z.FRONT
  end
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local progress = sprite.data[0] / sprite.data[1]
  local sc = 0.4 + 1.2 * progress
  sprite.w = math.floor((sprite._baseW or 32) * sc)
  sprite.h = math.floor((sprite._baseH or 32) * sc)
  sprite.alpha = math.max(0, 1.0 - progress)

  if sprite.data[0] >= sprite.data[1] then
    destroy(sprite)
  end
end
AnimCallbacks.AirWaveCrescent = AnimCallbacks.WaveFromCenterOfTarget
AnimCallbacks.SoundWave = AnimCallbacks.WaveFromCenterOfTarget

--- pret AnimWillOWispFire / AnimWillOWispOrb — orbiting ghostly flames (Will-O-Wisp, Fire Spin).
function AnimCallbacks.WillOWispFire(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 32
    sprite._angle = (sprite.data[0] or 0) * (math.pi / 4)
    sprite._radius = 28
    sprite.z = AnimSprites.Z.FRONT
  end
  sprite._step = sprite._step + 1
  sprite._angle = sprite._angle + 0.15
  sprite._radius = math.max(4, sprite._radius - 0.7)
  sprite.ox = math.floor(math.cos(sprite._angle) * sprite._radius)
  sprite.oy = math.floor(math.sin(sprite._angle) * (sprite._radius * 0.6))
  sprite.alpha = math.max(0, 1.0 - sprite._step / sprite._dur)
  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.WillOWispOrb = AnimCallbacks.WillOWispFire
AnimCallbacks.IngrainOrb = AnimCallbacks.WillOWispFire
AnimCallbacks.IngrainRoot = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.FrenzyPlantRoot = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ConstrictBinding = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.LeechSeed = AnimCallbacks.ThrowProjectile
AnimCallbacks.ThunderWave = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.AssistPawprint = AnimCallbacks.SpriteOnMonPos

--- Orbit attacker, translate to target, orbit target (Fire Blast Ring).
-- pokefirered/src/battle_anim_fire.c:628
function AnimCallbacks.AnimFireRing(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._angle = tonumber(args[3]) or 0
    sprite._phase = 1
    sprite._phaseTimer = 0
    sprite._step = 0
  end

  sprite._phaseTimer = sprite._phaseTimer + 1
  local rad = (sprite._angle / 256) * 2 * math.pi
  local orbitX = math.floor(math.sin(rad) * 28)
  local orbitY = math.floor(math.cos(rad) * 28)
  sprite._angle = (sprite._angle + 20) % 256

  if sprite._phase == 1 then
    sprite.ox = orbitX
    sprite.oy = orbitY
    if sprite._phaseTimer >= 18 then
      sprite._phase = 2
      sprite._phaseTimer = 0
    end
  elseif sprite._phase == 2 then
    local u = math.min(1, sprite._phaseTimer / 25)
    local tx = math.floor((sprite._dx or 0) * u)
    local ty = math.floor((sprite._dy or 0) * u)
    sprite.ox = tx + orbitX
    sprite.oy = ty + orbitY
    if sprite._phaseTimer >= 25 then
      sprite._phase = 3
      sprite._phaseTimer = 0
    end
  elseif sprite._phase == 3 then
    sprite.ox = (sprite._dx or 0) + orbitX
    sprite.oy = (sprite._dy or 0) + orbitY
    if sprite._phaseTimer >= 31 then
      destroy(sprite)
      return
    end
  end

  local cellH = sprite._baseH or 32
  local totalFrames = 5
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite._step = (sprite._step or 0) + 1
  sprite.quadY = (math.floor((sprite._step - 1) / 4) % totalFrames) * cellH
end
AnimCallbacks.FireRing = AnimCallbacks.AnimFireRing

--- Fire Blast Cross impact blast (pokefirered/src/battle_anim_fire.c:692).
function AnimCallbacks.AnimFireCross(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = math.max(1, tonumber(args[3]) or 13)
    sprite._step = 0
    local dxStep = tonumber(args[4]) or 0
    local dyStep = tonumber(args[5]) or 0
    if sprite._reversed then dxStep = -dxStep end
    sprite._vx = dxStep
    sprite._vy = dyStep
  end

  sprite._step = sprite._step + 1
  sprite.ox = (sprite.ox or 0) + sprite._vx
  sprite.oy = (sprite.oy or 0) + sprite._vy

  local cellH = sprite._baseH or 32
  local totalFrames = 5
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.FireCross = AnimCallbacks.AnimFireCross

--- Fire spread blast for Blaze Kick / Fire Punch (pokefirered/src/battle_anim_fire.c:475).
function AnimCallbacks.AnimFireSpread(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = math.max(1, tonumber(args[5]) or 16)
    sprite._step = 0
    local txStep = tonumber(args[3]) or 0
    local tyStep = tonumber(args[4]) or 0
    if sprite._reversed then txStep = -txStep end
    sprite._vx = txStep
    sprite._vy = tyStep
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.ox = math.floor(sprite._vx * u)
  sprite.oy = math.floor(sprite._vy * u)

  local cellH = sprite._baseH or 32
  local totalFrames = 5
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.FireSpread = AnimCallbacks.AnimFireSpread

--- Sunlight ray beam from Sunny Day (pokefirered/src/battle_anim_fire.c:583).
function AnimCallbacks.AnimSunlight(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 30
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.alpha = math.sin(u * math.pi)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.Sunlight = AnimCallbacks.AnimSunlight

function AnimCallbacks.SimpleFadeOut(sprite)
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local life = sprite.data[0]
  sprite.alpha = 1 - life / 20
  if life >= 20 then destroy(sprite) end
end

--- noGfx helpers are handled as visual tasks, not sprites.
AnimCallbacks.HorizontalLunge = nil
AnimCallbacks.VerticalDip = nil
AnimCallbacks.SlideMonToOriginalPos = nil
AnimCallbacks.SlideMonToOffset = nil

AnimCallbacks._destroy = destroy
for _, group in ipairs({ "g1", "g2", "g3", "g4" }) do
  local ok, mod = pcall(require, "src.core.game3.battle.anim_port." .. group .. "_callbacks")
  if ok and type(mod) == "function" then mod = mod(AnimCallbacks) end
  if ok and type(mod) == "table" then
    for k, fn in pairs(mod) do AnimCallbacks[k] = fn end
  elseif not ok and not tostring(mod):find("not found") then
    print("[battle.anim] " .. group .. "_callbacks: " .. tostring(mod))
  end
end

function AnimCallbacks.get(name)
  if not name then return AnimCallbacks.HitSplatBasic end
  if AnimCallbacks[name] then return AnimCallbacks[name] end
  local clean = tostring(name):gsub("^Anim", "")
  if AnimCallbacks[clean] then return AnimCallbacks[clean] end
  if AnimCallbacks["Anim" .. clean] then return AnimCallbacks["Anim" .. clean] end
  return AnimCallbacks.SimpleFadeOut
end

return AnimCallbacks

