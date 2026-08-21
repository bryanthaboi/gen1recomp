-- The battle state: wild and trainer battles driven entirely by generated
-- data (species, moves, type chart, trainer parties, encounter tables).
--
-- Flow: intro -> menu (FIGHT/PKMN/ITEM/RUN) -> move select -> turn
-- resolution (a queue of messages/actions/UI pushes) -> back to menu,
-- until one side is out, then finish.  Pops itself and calls
-- onFinish("win"|"lose"|"run"|"caught").
--
-- The Gen 1 move-effect pipeline (multi-hit, charge, trapping, thrash,
-- bide, recharge, confusion, screens, substitute, transform, ...) is
-- ported from engine/battle/core.asm; see docs/behavior-porting-notes.md.

local Assets = require("src.render.Assets")
local Catching = require("src.battle.Catching")
local Damage = require("src.battle.Damage")
local EffectRegistry = require("src.battle.EffectRegistry")
local Experience = require("src.battle.Experience")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local MoveEffects = require("src.battle.MoveEffects")
local Party = require("src.pokemon.Party")
local Pokemon = require("src.pokemon.Pokemon")
local Runtime = require("src.mods.Runtime")
local BattleSafety = require("src.battle.BattleSafety")
local Screens = require("src.ui.Screens")
local Status = require("src.battle.Status")
local Theme = require("src.ui.Theme")
local Timing = require("src.core.Timing")
local TrainerAI = require("src.battle.TrainerAI")
local TurnOrder = require("src.battle.TurnOrder")
local TypeChart = require("src.battle.TypeChart")
local UIVisibility = require("src.battle.UIVisibility")
local RomText = require("src.core.RomText")
local Strings = require("src.core.Strings")
local WideBattle = require("src.battle.WideBattle")

local romText = RomText

local BattleState = {}
BattleState.__index = BattleState
BattleState.isOpaque = true
BattleState.isBattleState = true

-- Category identity for per-category GAME SPEED (RFC 0007), the same
-- style OverworldController.isOverworld already uses. Every battle --
-- wild, trainer, link, safari, the old-man demo -- is this metatable, so
-- Game.speedCategoryInStack needs no special-casing beyond this one flag.
BattleState.isBattle = true

function BattleState:romText(label, fallback, ...)
  return romText(self.data, label, fallback, ...)
end
-- Letterbox voids around the 160x144 battle canvas fill white so the
-- window reads as one continuous battle screen (no black bars).
BattleState.letterboxWhite = true

-- A battle is a self-contained SCREEN, not the window.  The overworld's
-- dialogue box docks to the window edge on purpose (Renderer:setUIAnchor) --
-- a box floating in the middle of a zoomed-out map reads as detached.  A
-- battle is the opposite: pokered draws its text box and YES/NO in the same
-- 160x144 tilemap as the HUD, and pulling them out to the window edge splits
-- the composition in two -- the caught-mon nickname prompt lands a whole
-- letterbox below the white field it is supposed to be printed on.  Anchors
-- are held off for as long as a battle is in the stack.
BattleState.holdsUIAnchors = true

-- BATTLE LAYOUT: the classic 160x144 arrangement, or the widescreen one on
-- a 304x144 surface (src/battle/WideBattle.lua).  Only the composition
-- differs; every battler, queue and animation below is shared.  Menus and
-- prompts pushed during a wide battle keep its wide canvas, while drawing
-- their classic 160px UI centred within it (Game:draw).
function BattleState:isWideBattleLayout()
  local options = self.game and self.game.save and self.game.save.options
  return options and options.battleLayout == "wide" or false
end

function BattleState:wideLayout()
  return self:isWideBattleLayout()
end

-- BATTLE SIZE: "fixed" keeps the classic integer-scaled letterbox (a GB pixel
-- is a whole number of screen pixels, and the battle is the same size at any
-- zoom); "fill" scales the battle surface to the window instead, so it fills
-- vertically.  Filling means a fractional scale, so pixels stop being evenly
-- sized -- that is the trade, which is why it is a setting rather than a
-- change.  Only the battle surface is affected; the overworld is unchanged.
function BattleState:wantsFillScale()
  local options = self.game and self.game.save and self.game.save.options
  return options and options.battleFit == "fill" or false
end

-- EXTENDED HUD configurations are admitted one at a time after their own
-- placement and screenshot review.  FIXED supports the three authored battle
-- backgrounds; FILL uses one adaptive presentation stored as WHITE: stock
-- battles retain the paper field required by Gen 1 back sprites, while arena
-- providers may replace it with their own scene.  Only the HUD moves to window
-- space.
function BattleState:extendedHUD()
  local options = self.game and self.game.save and self.game.save.options
  local bg = options and options.battleBg
  return self:wideLayout()
     and options and options.battleHud == "extended"
     and ((options.battleFit == "fixed"
           and (bg == "world" or bg == "white" or bg == "black"))
       or (options.battleFit == "fill" and bg == "white"))
end

function BattleState:extendedWorldHUD()
  local options = self.game and self.game.save and self.game.save.options
  return self:extendedHUD() and options
     and options.battleFit == "fixed" and options.battleBg == "world"
end

function BattleState:extendedBlackHUD()
  local options = self.game and self.game.save and self.game.save.options
  return self:extendedHUD() and options and options.battleBg == "black"
end

-- BATTLE BG: what fills the screen AROUND the battle -- the letterbox voids
-- that grow as the window gets bigger or the view is zoomed out.  The battle
-- screen itself is untouched: it keeps its white paper field in every mode.
--
--   "white"  the display mode's paper shade (the classic look)
--   "black"  plain black bars
--   "world"  the frozen overworld, dimmed
--
-- "world" works by making the battle NON-opaque: StateStack:visibleBase then
-- finds the overworld below it and Game:draw keeps drawing the map, so the
-- voids show it instead of a flat clear.  The battle still paints its own
-- opaque 160x144 field over the top, so only the surround changes.
function BattleState:bgMode()
  local options = self.game and self.game.save and self.game.save.options
  local mode = options and options.battleBg
  if mode == "black" or mode == "world" then return mode end
  return "white"
end

-- Resume a semantic checkpoint directly at the command menu. Unlike enter(),
-- this deliberately does not replay the battle transition, intro queues,
-- cries, happiness changes, or battle-start events.
function BattleState:resumeCheckpoint()
  self.isOpaque = self:bgMode() ~= "world"
  require("src.core.Music").playBattle(self.data,
    self.musicKind or self:computeMusicKind())
end

-- How far to dim the overworld behind a "world" background, 0..1.  Enough
-- that the battle reads as the foreground rather than competing with a fully
-- lit map behind it.
BattleState.BG_WORLD_DIM = 0.55

-- Renderer:setUISize asks the top state for its surface before anything draws
function BattleState:uiSize()
  if self:wideLayout() then return WideBattle.WIDTH, WideBattle.HEIGHT end
  return 160, 144
end

-- Battle colors itself per-pixel (species pics + HP bar tints), so the
-- SGB whole-screen remap must not run over it.  The wide layout still
-- needs a zone list of its own: the invented 160x144 one would leave its
-- extra columns unremapped in the forced-mono modes (WideBattle.zones).
function BattleState:sgbPalettes()
  if self:wideLayout() then return WideBattle.zones() end
  return nil
end

function BattleState:bottomUIVisible()
  return UIVisibility.bottomVisible(self, true)
end

function BattleState:statusHUDVisible()
  if not Runtime.wantsHook("battle.status_hud_visible") then return true end
  return Runtime.call("battle.status_hud_visible", function() return true end,
                      self) ~= false
end

function BattleState:caughtMarkerVisible()
  local dex = self.game and self.game.save and self.game.save.pokedex
  if not self.enemy or (self.kind ~= "wild" and self.kind ~= "safari")
      or not (dex and dex.owned and dex.owned[self.enemy.mon.species]) then
    return false
  end
  if not Runtime.wantsHook("battle.caught_marker_visible") then return false end
  return Runtime.call("battle.caught_marker_visible",
                      function() return false end, self) == true
end

function BattleState:catchChance(ball, rateOverride)
  if Runtime.wantsHook("catch.rate") then return nil end
  return Catching.chance(ball, self.enemy.mon, self.enemy.def, rateOverride,
    { ballDef = self:ballDef(ball), statuses = self.data.statuses,
      battle = self })
end

function BattleState:moveGridNavigation()
  if self:wideLayout() then return true end
  if not Runtime.wantsHook("battle.move_grid_navigation") then return false end
  return Runtime.call("battle.move_grid_navigation", function() return false end,
                      self) == true
end

local Rulesets = {
  gen1_faithful = require("src.battle.rulesets.gen1_faithful"),
  modern_clean = require("src.battle.rulesets.modern_clean"),
}

-- the Poké Ball toss chain (TossBallAnimation) plays even with battle
-- animations off: PlayMoveAnimation jumps to it before checking wOptions
local BALL_ANIMS = {
  TOSS_ANIM = true, GREATTOSS_ANIM = true, ULTRATOSS_ANIM = true,
  BLOCKBALL_ANIM = true, POOF_ANIM = true, HIDEPIC_ANIM = true,
  SHAKE_ANIM = true, SHOWPIC_ANIM = true,
}

local imageCache = {}
-- The three tables below are keyed by the Image OBJECT, not by a path, and a
-- running battle holds the pics it built at enter() (battler.sprite,
-- playerBackPic, trainerPic).  Weak keys let a dropped pic's row go with it,
-- so invalidate() can drop the path cache without orphaning what is on
-- screen right now (#316).
local WEAK_KEYS = { __mode = "k" }
-- fully transparent rows below a pic's content (the extracted 32x32 back
-- pics carry baked-in padding); used to sit the pic flush on the text box
local imagePadBottom = setmetatable({}, WEAK_KEYS)
-- fully transparent columns left of a pic's content; at 2x (back pics)
-- this is subtracted from hlcoord 1,5 so opaque pixels match hardware,
-- where those columns were white-on-white rather than shifted content
local imagePadLeft = setmetatable({}, WEAK_KEYS)
-- image -> { path, pal } so palette-fade variants (see fadeImage) can be
-- rebuilt for any battle pic, whatever code loaded it
local imageMeta = setmetatable({}, WEAK_KEYS)
-- pal = { name, colors } recolors the 4 GB shades like the Super Game Boy.
-- trueColor art (14 §the 4-shade contract) opts out of the quantize
-- entirely, so its palette variant collapses back onto the plain path.
local function getImage(path, pal, trueColor)
  if not path then return nil end
  if trueColor and require("src.render.PaletteFX").honorsTrueColor() then
    pal = nil
  else
    trueColor = nil
  end
  local key = pal and (path .. "#" .. pal.name) or path
  if not imageCache[key] then
    local img, pad, padL = nil, 0, 0
    if love.image and love.image.newImageData then
      local id = Assets.imageData(path)
      if pal then
        local c = pal.colors
        id:mapPixel(function(_, _, r, g, b, a)
          if a == 0 then return r, g, b, a end
          local col = r > 0.83 and c[1] or r > 0.5 and c[2]
                      or r > 0.17 and c[3] or c[4]
          return col[1] / 255, col[2] / 255, col[3] / 255, a
        end)
      end
      local w, h = id:getDimensions()
      local bottom = h - 1
      while bottom >= 0 do
        local opaque = false
        for x = 0, w - 1 do
          local _, _, _, a = id:getPixel(x, bottom)
          if a > 0 then opaque = true break end
        end
        if opaque then break end
        bottom = bottom - 1
      end
      local left = 0
      while left < w do
        local opaque = false
        for y = 0, h - 1 do
          local _, _, _, a = id:getPixel(left, y)
          if a > 0 then opaque = true break end
        end
        if opaque then break end
        left = left + 1
      end
      img = love.graphics.newImage(id)
      pad = h - 1 - bottom
      padL = left
    else
      img = Assets.image(path) -- headless stub: no pixel access
    end
    imageCache[key] = img
    imagePadBottom[img] = pad
    imagePadLeft[img] = padL
    imageMeta[img] = { path = path, pal = pal, trueColor = trueColor or nil }
  end
  return imageCache[key]
end

-- Hot reload / COLORS change (PaletteFX.setMode calls this): the next
-- getImage re-resolves every pic through the asset search path and
-- re-measures its ground padding.  ONLY the path->image cache is dropped.
-- Wiping the three per-image tables as well orphaned the pics a running
-- battle already holds: imagePadBottom went nil, so backPlacement lost the
-- four transparent rows it grounds the back pic on and the pic jumped
-- pad * 2x = 8px UP the frame COLORS changed (#316), and imageMeta went nil,
-- so picImage's forced-mono grayImage (#207), fadeImage's BGP variants and
-- imagePathOf's battle_sprite_scales lookup all silently stopped resolving.
-- Those rows are weak-keyed, so entries for pics nothing references any more
-- are collected on their own rather than leaking.
function BattleState.invalidate()
  imageCache = {}
end

Assets.register(BattleState.invalidate)

-- the species' SGB palette (active COLORS pack), or nil
local function monPalette(data, species)
  local PaletteFX = require("src.render.PaletteFX")
  local colors = PaletteFX.monPal(data, species)
  if not colors then return nil end
  local name = PaletteFX.monPalName(data, species)
  -- prefix so GBC vs RED++ cache keys don't collide on shared names
  if PaletteFX.usesGbcPack() then name = "redpp:" .. name end
  return { name = name, colors = colors }
end

-- a named palette from the active COLORS pack as a getImage pal
local function namedPalette(data, name)
  local PaletteFX = require("src.render.PaletteFX")
  local colors = PaletteFX.pal(data, name)
  if not colors then return nil end
  local key = name
  if PaletteFX.usesGbcPack() then key = "redpp:" .. name end
  return { name = key, colors = colors }
end

-- Custom trainer portraits can opt into the same Advanced OBJ palette source
-- as their overworld walker. Vanilla trainers preserve the hardware-faithful
-- MEWMON fallback used during the battle introduction.
function BattleState.trainerPalette(data, trainer)
  local source = trainer and trainer.paletteSource
  if source then
    local PaletteFX = require("src.render.PaletteFX")
    local colors, group = PaletteFX.spriteObp({ paletteSource = source }, trainer.id)
    if colors then
      return { name = "trainer:" .. source .. ":" .. tostring(group), colors = colors }
    end
  end
  return namedPalette(data, "MEWMON")
end

-- Yellow only: ROCKET with wTrainerNo >= $2a is Jessie & James, who share
-- the class and the name "ROCKET" but battle behind their own pic
-- (home/trainers2.asm IsFightingJessieJames).  picJessieJames exists only
-- in a Yellow cache extracted after #439, so an older cache keeps the
-- grunt pic until it is re-imported.
function BattleState.trainerPicPath(data, trainer, oppClass, partyIndex)
  if oppClass == "OPP_ROCKET" and (partyIndex or 1) >= 42
     and trainer and trainer.picJessieJames then
    return trainer.picJessieJames
  end
  if trainer and trainer.pic then return trainer.pic end
  local base = trainer and trainer.basePic and data.trainers[trainer.basePic]
  return base and base.pic or nil
end

-- trueColor on the trainer record, or on the basePic it reuses when the
-- subclass does not set the flag itself.  Explicit false stays false.
function BattleState.trainerTrueColor(data, trainer)
  if not trainer then return false end
  if trainer.trueColor ~= nil then
    return trainer.trueColor and true or false
  end
  local base = trainer.basePic and data and data.trainers
    and data.trainers[trainer.basePic]
  return (base and base.trueColor) and true or false
end

-- Load a trainer frontpic through getImage so a trueColor portrait skips
-- the 4-shade quantize the same way a species pic does.
function BattleState.trainerSprite(data, trainer, oppClass, partyIndex)
  return getImage(
    BattleState.trainerPicPath(data, trainer, oppClass, partyIndex),
    BattleState.trainerPalette(data, trainer),
    BattleState.trainerTrueColor(data, trainer))
end

-- The battle-BGP fade variant of a pic (AnimationFlashScreen and the
-- SetAnimationBGPalette effects remap the four BG shades; on the SGB
-- the colorizer then colors the REMAPPED shade, so a faded pic shows
-- palette[bgp[shade]]).  bgp = shade map {[0..3] -> 0..3} or nil.
local function fadeImage(img, bgp)
  if not bgp or not img then return img end
  local meta = imageMeta[img]
  if not meta then return img end
  -- a full-color pic has no DMG shades to remap
  if meta.trueColor then return img end
  local PaletteFX = require("src.render.PaletteFX")
  local base = meta.pal and meta.pal.colors or PaletteFX.GRAYS
  local name = (meta.pal and meta.pal.name or "GB")
               .. "&" .. bgp[0] .. bgp[1] .. bgp[2] .. bgp[3]
  return getImage(meta.path,
                  { name = name, colors = PaletteFX.permute(base, bgp) })
end

-- the raw DMG-gray build of a colored pic (SE_WAVY_SCREEN bakes the
-- pics into the BG canvas so they wave with it; the zone pass then
-- colors them by region like the real SGB)
local function grayImage(img)
  local meta = imageMeta[img]
  if not meta or not meta.pal then return img end
  return getImage(meta.path) or img
end

-- SET_PAL_BATTLE_BLACK re-bake of a pic (engine/battle/core.asm:1151,
-- engine/gfx/palettes.asm:22-25); resolved like sgbBattlePals' blackout (#292).
local function blackImage(data, img)
  local meta = imageMeta[img]
  if not meta or meta.trueColor then return img end
  local PaletteFX = require("src.render.PaletteFX")
  local pack = PaletteFX.pack(data)
  local pals = pack and pack.palettes
  if not (pals and pals.BLACK) then return img end
  local colors = PaletteFX.usesYellowCgb() and pals.BLACK
                 or PaletteFX.pal(data, "BLACK") or pals.BLACK
  local name = PaletteFX.usesGbcPack() and "redpp:BLACK" or "BLACK"
  return getImage(meta.path, { name = name, colors = colors }) or img
end

-- the asset path a loaded battle image came from (nil for the headless
-- stub images), so the battle_sprite_scales registry can be looked up by
-- the same path data references
local function imagePathOf(img)
  local m = imageMeta[img]
  return m and m.path
end

-- the image a battler pic actually draws with this frame
function BattleState:picImage(img)
  local PaletteFX = require("src.render.PaletteFX")
  -- #207: OG / OG INV / CLASSIC are forced-mono display modes.  A battle that
  -- exposes no SGB zones (sgbPalettes() == nil) has a whole-screen GRAYS zone
  -- invented by PaletteFX.ensureZones, so Renderer:endFrame re-thresholds the
  -- WHOLE finished frame through the shade shader a second time (keyed on the
  -- red channel).  A pic baked with the species' SGB color is then remapped
  -- again and loses its warm mid shades -- REDMON's reds 1.0/0.839 both land in
  -- the c0 bucket, collapsing CHARMANDER's body into the white paper and
  -- leaving only the outline.  Emit the raw DMG-gray build instead (exactly
  -- what the SE_WAVY_SCREEN grayPics path already does) so the downstream remap
  -- recolors 255->c0/170->c1/85->c2/0->c3 and all four shades survive; cool
  -- palettes (CYANMON reds 0.678/0.451) already rendered correctly.  This mode
  -- set mirrors PaletteFX.ensureZones / effectiveColors -- keep them in sync.
  local mono = PaletteFX.mode == "og" or PaletteFX.mode == "og_inv"
               or PaletteFX.mode == "classic"
  if self.grayPics or mono then return grayImage(img) end
  -- SET_PAL_BATTLE_BLACK covers every battle palette slot, so the pics go
  -- dark with the HP bars while the blackout text is up (#292).  The intro
  -- silhouette slide (SlidePlayerAndEnemySilhouettesOnScreen) darkens the
  -- same way: the original slides both pics in under the %11100100
  -- silhouette palette and only runs SET_PAL_BATTLE once they have landed,
  -- so a still-sliding pic reads as a black silhouette, exactly like the
  -- evolution movie's PAL_BLACK (#577).  Below the mono check on purpose:
  -- the forced-mono modes re-threshold the whole frame downstream, and the
  -- DMG had no SGB darkening to begin with.
  if self.blackedOut or (self.introSlide or 0) > 0 then
    return blackImage(self.data, img)
  end
  return fadeImage(img, self:activeBgp())
end

-- Gen 1 trainer Pokémon have fixed DVs (engine/battle/core.asm);
-- constants.trainerDvs overrides, this is the imported-cache fallback
local TRAINER_DVS = { attack = 9, defense = 8, speed = 8, special = 8, hp = 8 }

-- charge-turn texts by move id; the move record's chargeText field wins
-- (ChargeEffect's per-move text pointers)
-- Strings.source, not Strings: this table is built at require time, before
-- Strings.load has a catalog, so translating here would freeze the English.
-- The marker is a no-op that puts these lines in the catalog anyway; the
-- lookup happens where chargeText is formatted below.
local CHARGE_TEXT = {
  FLY = Strings.source("%s\nflew up high!"),
  DIG = Strings.source("%s\ndug a hole!"),
  RAZOR_WIND = Strings.source("%s\nmade a whirlwind!"),
  SOLARBEAM = Strings.source("%s\ntook in sunlight!"),
  SKULL_BASH = Strings.source("%s\nlowered its head!"),
  SKY_ATTACK = Strings.source("%s\nis glowing!"),
}

-- pokered's <USER>/<TARGET> text macros (home/text.asm
-- PlaceMoveUsersName): battle texts naming the enemy mon print
-- "Enemy " before the nickname; player-side mons never get it.
-- Translatable as one "Enemy %s" template (#779) so languages that
-- qualify after the name, or decline, can (e.g. "%s ennemi").
local function displayName(b)
  return b.isPlayer and b.name or Strings("Enemy %s", b.name)
end

-- Apply the enemy qualifier to a pre-built message from a module that
-- only knows the raw nickname (Status.beforeMove/residual): replace the
-- first name occurrence with the qualified form.
local function prefixEnemy(msg, battler)
  if battler.isPlayer then return msg end
  local s = msg:find(battler.name, 1, true)
  if not s then return msg end
  return msg:sub(1, s - 1) .. Strings("Enemy %s", battler.name)
      .. msg:sub(s + #battler.name)
end

-- Level-up stats window (PrintStatsBox .LevelUpStatsBox: box (9,2)
-- 11x10 over the battle, dismissed with A/B)
local StatBox = {}
StatBox.__index = StatBox

function StatBox.new(game, mon, onDone)
  return setmetatable({ game = game, mon = mon, onDone = onDone }, StatBox)
end

function StatBox:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function StatBox:draw()
  Font.drawBox(9, 2, 11, 10)
  love.graphics.setColor(0, 0, 0, 1)
  local s = self.mon.stats
  -- labels through Strings so a mod catalog translates them (#811)
  local rows = { { Strings("ATTACK"), s.attack },
                 { Strings("DEFENSE"), s.defense },
                 { Strings("SPEED"), s.speed },
                 { Strings("SPECIAL"), s.special } }
  for i, r in ipairs(rows) do
    Font.draw(Strings(r[1]), 88, 24 + (i - 1) * 16)
    Font.draw(("%3d"):format(r[2]), 128, 32 + (i - 1) * 16)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------

local function makeBattler(data, mon, isPlayer, save)
  local def = data.pokemon[mon.species]
  local badgeBoosts = data.constants and data.constants.badgeBoosts
  local badges = nil
  if isPlayer and save then
    -- Gen 1 badge stat boosts (x9/8); the badge set follows the merged
    -- badgeBoosts rows so a retuned list changes what gets baked in
    badges = {}
    for _, row in ipairs(badgeBoosts or Damage.BADGE_BOOSTS) do
      if save.inventory[row.badge] then badges[row.badge] = true end
    end
  end
  return {
    mon = mon,
    def = def,
    name = mon.nickname or def.name,
    isPlayer = isPlayer,
    badges = badges,
    -- merged registry views consumed by the pure battle modules
    badgeBoosts = badgeBoosts,
    statuses = data.statuses,
    shownHP = mon.hp, -- the HP the bar displays (UpdateHPBar drain)
    -- the bar's own length in GetHPBarLength pixels; it trails shownHP
    -- because UpdateHPBar_AnimateHPBar slides it one pixel at a time
    shownPx = Timing.hpBarPixels(mon.hp, math.max(1, mon.stats.hp)),
    -- HUD status label (DrawHUDsAndHPBars); mon.status can land mid-move
    -- while the tilemap still shows the prior condition until the next
    -- post-action HUD refresh (core.asm after Execute*Move)
    shownStatus = mon.status,
    stages = {},
    -- volatile state; Transform/Conversion/Mimic override the cur* fields
    curStats = mon.stats,
    curTypes = def.types,
    curMoves = mon.moves,
    sprite = (function()
      local Sprites = require("src.pokemon.Sprites")
      local path, tc = Sprites.path(data, mon.species,
        isPlayer and "back" or "front",
        { mon = mon, kind = "battle" })
      return getImage(path, monPalette(data, mon.species), tc)
    end)(),
  }
end

-- LinkBattle builds clamped copies with save=nil (no badge boosts); wild
-- and trainer constructors pass the live save for the player side.
BattleState.makeBattler = makeBattler

-- The battle pic for `species` on the given side (back pic for the
-- player side, front pic for the enemy side), tinted PAL_GRAYMON --
-- the same path makeBattler uses, but forced gray -- since this is only
-- ever used for a Transformed mon's swapped-in pic (transform.asm:31-53
-- AnimationTransformMon; the SGB color comes from DeterminePaletteID,
-- which forces PAL_GRAYMON for a Transformed mon rather than the copied
-- species' own palette).
function BattleState:speciesSprite(species, isPlayerSide)
  local def = self.data.pokemon[species]
  if not def then return nil end
  local Sprites = require("src.pokemon.Sprites")
  local path, tc = Sprites.path(self.data, species,
    isPlayerSide and "back" or "front", { kind = "battle" })
  local PaletteFX = require("src.render.PaletteFX")
  local colors = PaletteFX.monPal(self.data, species, true)
  local name = "GRAYMON"
  if PaletteFX.usesGbcPack() then name = "redpp:GRAYMON" end
  return getImage(path,
                  colors and { name = name, colors = colors } or nil,
                  tc)
end

local function markSeen(game, species)
  local dex = game.save.pokedex
  if dex then dex.seen[species] = true end
end

-- newly obtained mons carry the player's OT name/ID (status screen)
local function stampOT(save, mon)
  save.player.id = save.player.id or math.random(0, 65535)
  mon.ot = mon.ot or save.player.name
  -- engine/battle/experience.asm:69
  if not mon.traded then mon.otId = mon.otId or save.player.id end
end
BattleState.stampOT = stampOT

local function markOwned(game, species)
  local dex = game.save.pokedex
  if dex then
    dex.seen[species] = true
    dex.owned[species] = true
  end
end
BattleState.markOwned = markOwned
BattleState.StatBox = StatBox -- the level-up stat window (PrintStatsBox)

local function newBattle(game)
  local self = setmetatable({}, BattleState)
  self.game = game
  -- InitBattleVariables (engine/battle/init_battle_variables.asm) zeroes
  -- wPartyAndBillsPCSavedMenuItem, so entering a battle drops the party
  -- cursor the field menu has been carrying (src/ui/PartyMenu.lua). #768
  game.partyMenuSavedIndex = nil
  self.data = game.data
  -- ruleset from the merged registry (the requires above are the same
  -- records on a mod-free boot); an unknown save value falls back to the
  -- default with a notice instead of silently switching behavior
  local rulesets = game.data.rulesets or Rulesets
  local selected = game.save.options and game.save.options.ruleset
  local fallback = (game.data.constants and game.data.constants.defaultRuleset)
                   or "gen1_faithful"
  local ruleset = selected and rulesets[selected]
  if selected and not ruleset then
    Logger.warn("unknown ruleset %s; using %s", tostring(selected), fallback)
  end
  self.ruleset = ruleset or rulesets[fallback] or Rulesets.gen1_faithful
  self.rng = function(a, b) return love.math.random(a, b) end
  -- side/field substrate: vanilla writes nothing here, but every battle
  -- carries the stable shape mods hang screens/hazards/tokens on
  self.sides = {
    { index = 1, battlers = {}, screens = {}, hazards = {}, tokens = {} },
    { index = 2, battlers = {}, screens = {}, hazards = {}, tokens = {} },
  }
  self.field = { weather = nil, tokens = {}, sides = self.sides }
  TypeChart.load(game.data)
  -- the subanimation player (data/battle_anims via battle_anims.lua)
  if game.data.battle_anims then
    local ok, AnimPlayer = pcall(require, "src.battle.AnimPlayer")
    if ok then
      self.animPlayer = AnimPlayer.new(game.data.battle_anims)
    end
  end
  self.queue = {}
  self.phase = "intro"
  self.menuIndex = 1
  self.moveIndex = 1
  self.playerMoveListIndex = 1
  self.frame = 0
  return self
end

local function scopedPlayerParty(game, indices)
  if indices == nil then return nil, nil end
  if type(indices) ~= "table" then
    Logger.warn("trainer battle party scope is not a table; using full party")
    return nil, nil
  end
  local count = #indices
  local keyCount = 0
  for key in pairs(indices) do
    keyCount = keyCount + 1
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
      Logger.warn("trainer battle party scope is malformed; using full party")
      return nil, nil
    end
  end
  if count == 0 or keyCount ~= count then
    Logger.warn("trainer battle party scope is empty or sparse; using full party")
    return nil, nil
  end
  local party, normalized, seen = {}, {}, {}
  for i = 1, count do
    local index = indices[i]
    if type(index) ~= "number" or index % 1 ~= 0
        or not game.save.party[index] or seen[index] then
      Logger.warn("trainer battle party scope contains an invalid index; using full party")
      return nil, nil
    end
    seen[index] = true
    normalized[i] = index
    party[i] = game.save.party[index]
  end
  return party, normalized
end

function BattleState:playerPartyView()
  return self.playerParty or self.game.save.party
end

-- opts.hooked: rod encounter, announced with _HookedMonAttackedText
function BattleState.newWild(game, species, level, opts)
  local self = newBattle(game)
  self.kind = "wild"
  local playerMon = Party.firstHealthy(game.save.party)
  if not playerMon then
    Logger.warn("wild battle with no healthy party; skipping")
    self.dead = true
  else
    self.player = makeBattler(game.data, playerMon, true, game.save)
  end
  self.enemy = makeBattler(game.data, Pokemon.new(game.data, species, level), false)
  markSeen(game, species)
  if opts and opts.hooked then
    self.introText = self:romText("_HookedMonAttackedText", "The hooked\n%s\nattacked!", self.enemy.name)
  else
    self.introText = self:romText("_WildMonAppearedText", "Wild %s\nappeared!", self.enemy.name)
  end
  return self
end

-- data/trainers/special_moves.asm + read_trainer_party.asm: boss move
-- overrides, always written into the mon's THIRD move slot.
--   LoneMoves: the gym scripts write the gym number to wGymLeaderNo, so
--   these fire only for the leaders' gym battles (Giovanni: party 3);
--   the table's "index n" lands on the (n+1)-th party mon via AddNTimes.
--   TeamMoves: despite the "whole team" comment, the code writes only
--   wEnemyMon5Moves+2,  the FIFTH mon of each Elite Four member.
--   RIVAL3 (Champion): Pidgeot gets SKY ATTACK, the starter's final
--   form gets MEGA DRAIN / FIRE BLAST / BLIZZARD.
local LONE_MOVES = {
  OPP_BROCK = { 2, "BIDE" },
  OPP_MISTY = { 2, "BUBBLEBEAM" },
  OPP_LT_SURGE = { 3, "THUNDERBOLT" },
  OPP_ERIKA = { 3, "MEGA_DRAIN" },
  OPP_KOGA = { 4, "TOXIC" },
  OPP_SABRINA = { 4, "PSYWAVE" },
  OPP_BLAINE = { 4, "FIRE_BLAST" },
  OPP_GIOVANNI = { 5, "FISSURE", onlyParty = 3 },
}
local TEAM_MOVES = {
  OPP_LORELEI = "BLIZZARD", OPP_BRUNO = "FISSURE",
  OPP_AGATHA = "TOXIC", OPP_LANCE = "BARRIER",
}
local RIVAL_STARTER_MOVES = {
  VENUSAUR = "MEGA_DRAIN", CHARIZARD = "FIRE_BLAST", BLASTOISE = "BLIZZARD",
}

local function setThirdMove(data, mon, moveId)
  if not mon then return end
  local mdef = data.moves[moveId]
  local entry = { id = moveId, pp = mdef and mdef.pp or 0 }
  mon.moves[math.min(3, #mon.moves + 1)] = entry
end

local function applySpecialMoves(data, oppClass, partyIndex, party)
  local lone = LONE_MOVES[oppClass]
  if lone and (not lone.onlyParty or lone.onlyParty == partyIndex) then
    setThirdMove(data, party[lone[1]], lone[2])
    return
  end
  local team = TEAM_MOVES[oppClass]
  if team then
    setThirdMove(data, party[5], team)
    return
  end
  if oppClass == "OPP_RIVAL3" then
    setThirdMove(data, party[1], "SKY_ATTACK")
    local starter = party[6]
    if starter and RIVAL_STARTER_MOVES[starter.species] then
      setThirdMove(data, starter, RIVAL_STARTER_MOVES[starter.species])
    end
  end
end

function BattleState.newTrainer(game, oppClass, partyIndex, opts)
  local self = newBattle(game)
  self.kind = "trainer"
  self.oppClass = oppClass
  -- the object_event trainer arg (roster index).  computeMusicKind keys
  -- data/scripts/victories.lua on class#party, so keep it on the battle (#782).
  self.partyIndex = partyIndex or 1
  self.playerParty, self.playerPartyIndices = scopedPlayerParty(game,
    type(opts) == "table" and opts.playerPartyIndices or nil)
  self.trainer = game.data.trainers[oppClass]
  assert(self.trainer, "unknown trainer class " .. tostring(oppClass))
  -- pret GetTrainerName_: RIVAL1/2/3 copy wRivalName into wTrainerName
  -- instead of TrainerNames ("RIVAL1" etc.).  Overlay so we don't mutate
  -- the shared data table.
  if oppClass == "OPP_RIVAL1" or oppClass == "OPP_RIVAL2"
     or oppClass == "OPP_RIVAL3" then
    local rivalName = (game.save.player and game.save.player.rival) or "BLUE"
    self.trainer = setmetatable({ name = rivalName }, { __index = self.trainer })
  end
  self.enemyAIMods = self.trainer.aiMods
  local partyDef = self.trainer.parties[partyIndex or 1]
  assert(partyDef, ("trainer %s has no party %s"):format(oppClass, tostring(partyIndex)))
  if Runtime.wantsHook("trainer.party") then
    partyDef = Runtime.call("trainer.party", function(_, _, party)
      return party
    end, oppClass, partyIndex or 1, partyDef) or partyDef
  end
  local trainerDvs = (game.data.constants and game.data.constants.trainerDvs)
                     or TRAINER_DVS
  self.enemyParty = {}
  for _, slot in ipairs(partyDef) do
    local mon = Pokemon.new(game.data, slot.species, slot.level)
    -- fixed trainer DVs, recomputed stats
    mon.dvs = trainerDvs
    mon.stats = require("src.pokemon.Stats").calc(game.data.pokemon[slot.species],
                                                  slot.level, trainerDvs)
    mon.hp = mon.stats.hp
    table.insert(self.enemyParty, mon)
  end
  applySpecialMoves(game.data, oppClass, partyIndex or 1, self.enemyParty)
  -- a party slot's own moves list wins over the legacy boss-move tables
  for i, slot in ipairs(partyDef) do
    local mon = self.enemyParty[i]
    if mon and slot.moves then
      mon.moves = {}
      for _, moveId in ipairs(slot.moves) do
        local mdef = game.data.moves[moveId]
        table.insert(mon.moves, { id = moveId, pp = mdef and mdef.pp or 0 })
      end
    end
  end
  self.enemyIndex = 1
  local playerMon = Party.firstHealthy(self:playerPartyView())
  if not playerMon then
    Logger.warn("trainer battle with no healthy party; skipping")
    self.dead = true
  else
    self.player = makeBattler(game.data, playerMon, true, game.save)
  end
  self.enemy = makeBattler(game.data, self.enemyParty[1], false)
  self.aiUses = self:aiUsesFor() -- wAICount, reset per enemy mon
  markSeen(game, self.enemyParty[1].species)
  -- SGB: the enemy-side battle palette while the trainer pic is up is
  -- MonsterPalettes[0] = PAL_MEWMON -- InitBattleCommon zeroes
  -- wEnemyMonSpecies2 before the intro's SET_PAL_BATTLE
  -- (engine/battle/core.asm:6682, engine/gfx/palettes.asm SetPal_Battle)
  self.trainerPic = BattleState.trainerSprite(
    game.data, self.trainer, oppClass, partyIndex)
  self.introText = Strings("%s wants\nto fight!", self.trainer.name)
  return self
end

-- The disguise itself.  InitWildBattle .isGhost (engine/battle/core.asm)
-- swaps only the pic and the nick -- wEnemyMonSpecies2 still holds the real
-- species, so the SGB palette stays the disguised mon's.  ghostReal keeps
-- what LoadEnemyMonData puts back when the scope unveils.
local function disguiseAsGhost(self)
  self.ghostReal = { name = self.enemy.name, sprite = self.enemy.sprite }
  self.enemy.name = "GHOST"
  self.enemy.sprite = getImage("assets/generated/battle/front/ghost.png",
                               monPalette(self.data, self.enemy.mon.species))
  self.introText = Strings("The GHOST\nappeared!")
end

-- Pokémon Tower ghosts (engine/battle/core.asm): without the Silph Scope
-- the enemy is "GHOST", you're too scared to attack, and balls fail.
function BattleState:makeGhost()
  self.ghost = true
  disguiseAsGhost(self)
end

-- The RESTLESS SOUL with the SILPH SCOPE in the bag.  Mechanically this is
-- not a ghost battle at all -- IsGhostBattle (core.asm) returns false the
-- moment the scope is in the bag, so the mon attacks, is attacked and rolls
-- for flight normally -- but InitWildBattle still enters disguised: its
-- .isGhost branch fires on wCurOpponent == RESTLESS_SOUL as well.  Taking
-- the disguise off is PrintBeginningBattleText .isMarowak's job
-- (engine/battle/common_text.asm), which enter() queues through
-- queueScopeReveal (#492).
function BattleState:makeUnveiledGhost()
  self.scopeReveal = true
  disguiseAsGhost(self)
end

-- MarowakAnim (engine/battle/ghost_marowak_anim.asm) counted in frames: the
-- ghost pic is copied into OAM and flashed 8 times by xor-ing rOBP1 with
-- $80 (10 frames a side), the BG pic underneath is swapped to the RESTLESS
-- SOUL, rOBP1 is shifted left two bits every 10 frames until the ghost has
-- faded into the paper (3 shifts), and the Marowak copy fades back in the
-- same way (4 shifts).  Alpha over the paper is what those OBP shifts look
-- like on screen.
BattleState.GHOST_FLASH_FRAMES = 80
BattleState.GHOST_FADE_OUT_FRAMES = 30
BattleState.GHOST_FADE_IN_FRAMES = 40
BattleState.GHOST_REVEAL_FRAMES = 150

-- The rows .isMarowak prints over the disguise, after the "GHOST appeared!"
-- box enter() has already queued: the unveil line, MarowakAnim, then "Wild
-- MAROWAK appeared!" under the restored name.  The fall-through into
-- .playSFX at the end is the same SFX_TRAINER_APPEARED the port does not
-- play for trainer intros either, so it is left out here too.
function BattleState:queueScopeReveal()
  local unveiled = self.data.text and self.data.text._UnveiledGhostText
  self:say(unveiled
           or Strings("SILPH SCOPE\nunveiled the\vGHOST's identity!"))
  self:act(function() self.ghostReveal = { t = 0 } end)
  table.insert(self.queue, { wait = BattleState.GHOST_REVEAL_FRAMES })
  self:say(self:romText("_WildMonAppearedText", "Wild %s\nappeared!",
                   self.ghostReal and self.ghostReal.name or self.enemy.name))
end

-- The old man's catch tutorial (BATTLE_TYPE_OLD_MAN,
-- engine/battle/core.asm DisplayBattleMenu .oldManName branch): no
-- player mon; the battle menu appears under the OLD MAN's name and a
-- scripted cursor hovers FIGHT, hops to ITEM and forces the item menu
-- (one POKé BALL x50).  Nothing is kept.
-- Yellow's Pallet intro (BATTLE_TYPE_PIKACHU) is the same simulated
-- script under "PROF.OAK" (pokeyellow core.asm .profOakName), so the
-- displayed thrower name is a parameter.
-- The throw catches everywhere except Yellow's FIRST Viridian training.
-- ItemUseBall's .oldManBattle branch checks EVENT_INITIAL_CATCH_TRAINING
-- and, when it is set, stores anim data $63 in place of the $43 capture
-- value -- three shakes, then a breakout (pokeyellow
-- engine/items/item_effects.asm).  Red/Blue's ItemUseBall has no such
-- branch and jumps straight to .captured, and Yellow's repeat "Watch
-- closely!" demo resets the event before its battle
-- (ViridianCityOldManStartCatchTrainingScript), so only the initial
-- tutorial passes failThrow -- it stands in for that event (#636).
function BattleState:makeOldManDemo(name, failThrow)
  self.demo = true
  self.demoName = name or Strings("OLD MAN")
  self.demoFails = failThrow and true or false
  -- LoadPlayerBackPic and DisplayBattleMenu split on the same wBattleType:
  -- BATTLE_TYPE_OLD_MAN gets .oldManName + OldManPicBack, BATTLE_TYPE_PIKACHU
  -- gets .profOakName + ProfOakPicBack (pokeyellow core.asm).  The thrower
  -- name the caller passes IS that distinction here, so it picks the pic too
  -- -- data/scripts/story2.lua is the only site that names PROF.OAK (#557).
  self.oakDemo = name == "PROF.OAK"
  -- Yellow's Pallet intro runs this before the player owns any mon
  -- (BATTLE_TYPE_PIKACHU precedes the lab gift), so newWild flagged the
  -- battle dead for lack of a party.  The demo never sends out, draws, or
  -- acts with the player side; a hidden placeholder battler keeps the
  -- shared battle phases nil-safe.
  if not self.player then
    self.dead = false
    self.player = makeBattler(self.game.data,
      Pokemon.new(self.game.data, self.enemy.mon.species, 5), true)
  end
end

-- Safari Zone battles (engine/battle/core.asm safari sections +
-- engine/battle/safari_zone.asm): no player mon acts; the menu is
-- BALL / BAIT / ROCK / RUN.  state is save.safari ({balls, steps}).
function BattleState:makeSafari(state)
  self.safari = state
  self.safariCatchRate = self.enemy.def.catchRate
  self.baitFactor = 0
  self.escapeFactor = 0
end

-- ---------------------------------------------------------------------
-- message/action queue
-- ---------------------------------------------------------------------

function BattleState:say(text)
  table.insert(self.queue, { text = text })
end

-- A message whose ROM tail is `text_end` / `done` rather than `prompt`:
-- NextTextCommand returns straight out of PrintText on TX_END
-- (home/text.asm:328-334) and only TX_PROMPT_BUTTON blinks the arrow and
-- runs ManualTextScroll (home/text.asm:434-446), so these pages never wait
-- on the player.  autoDelay is the frame hold before the queue moves on
-- (0 = the next row starts immediately, as PrintText returning does) (#765).
function BattleState:sayAuto(text, delay)
  table.insert(self.queue, { text = text, auto = true, autoDelay = delay or 0 })
end

-- Message that opens YES/NO once typed out, keeping the text visible
-- underneath (pokered `done` + TWO_OPTION_MENU / TextBox opts.choice).
function BattleState:sayChoice(text, onChoose, opts)
  table.insert(self.queue, { text = text, choice = onChoose, choiceOpts = opts })
end

function BattleState:act(fn)
  table.insert(self.queue, { fn = fn })
end

-- push a UI state above the battle; the queue pauses until it pops
function BattleState:ui(factory)
  table.insert(self.queue, { ui = factory })
end

-- insert an animation row right after the current queue item (the
-- POOF/ball-toss animations past the move table); `shakes` marks the
-- ball-shake row with its wNumShakes repeat count, `ball` marks a toss
-- row with the thrown ball item (wCurItem -- a Master/Ultra toss
-- flickers the OBJ palette, DoBallTossSpecialEffects)
function BattleState:animNext(name, isPlayer, shakes, ball)
  self.nextInsert = (self.nextInsert or 0) + 1
  local row = { anim = name, attackerIsPlayer = isPlayer, shakes = shakes,
                ball = ball }
  table.insert(self.queue, self.nextInsert, row)
  return row
end

-- an animation row ahead of the move's own, with PlayBattleAnimation2's
-- applying-animation shake (engine/battle/effects.asm:1461-1471)
function BattleState:animBeforeMove(name, isPlayer)
  local at
  for i, item in ipairs(self.queue) do
    if item == self.moveAnimRow then at = i break end
  end
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, at or self.nextInsert,
               { anim = name, attackerIsPlayer = isPlayer, animDelayed = true,
                 hit = { animType = isPlayer and 6 or 3 } })
end

-- insert an act right after the current queue item
function BattleState:actNext(fn)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { fn = fn })
end

-- insert message right after the currently-executing queue item (the
-- counter is reset by updateQueue before each fn item runs)
function BattleState:sayNext(text)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { text = text })
end

function BattleState:sayNextWaitSfx(text, sfx)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { text = text, waitForLearningSfx = sfx })
end

-- WaitForSoundToFinish for a sound an act() has already started: PlayCry
-- ends in `jp WaitForSoundToFinish` (home/pokemon.asm), so every cry in
-- Gen 1 holds whatever the ROM does next.  `src` is the audio source, or a
-- getter the row calls at execution time when the source is only known then.
function BattleState:waitSfxNext(src)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert,
               { waitSound = type(src) == "function" and src
                             or function() return src end })
end

-- sayNext for a page that ends in `text_end` (see sayAuto) (#765)
function BattleState:sayNextAuto(text, delay)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert,
               { text = text, auto = true, autoDelay = delay or 0 })
end

-- insert a UI push right after the current queue item (dex page, the
-- level-up stat box -- anything that must keep queue order)
function BattleState:uiNext(factory)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { ui = factory })
end

-- ui rows compose screens unpushed (updateQueue pushes them), so
-- Screens.push's mod-screen degrade can't cover them; mirror it here,
-- stamping the id the same way
function BattleState:buildScreen(id, ...)
  local game = self.game
  local factory = Screens.get(game, id)
  local inst
  if factory.__modOwned then
    -- a broken mod screen degrades to the builtin, never a dead end
    local ok, result = pcall(factory.new, game, ...)
    if ok and result then
      inst = result
    else
      Logger.error("mod screen '%s' failed: %s -- using builtin",
                   id, tostring(result))
      Screens.invalidate()
      inst = require("src.ui." .. id).new(game, ...)
    end
  else
    inst = factory.new(game, ...)
  end
  inst.screenId = inst.screenId or id
  return inst
end

-- insert a wait for the HP bars to finish draining (UpdateHPBar):
-- the queue holds until every battler's displayed HP catches up.
-- `stopAt` pins how far that battler's bar may drain on this row.  A
-- multi-hit move takes every strike off the model while the turn is still
-- being queued, so an unpinned row would drain straight to the
-- post-last-hit HP and the later strikes would animate nothing (#394);
-- ApplyDamageToEnemyPokemon runs UpdateHPBar2 once per strike inside the
-- wNumAttacksLeft loop (engine/battle/core.asm:4727).
function BattleState:drainNext(battler, stopAt)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert,
               { drain = true, battler = battler, stopAt = stopAt })
end

-- Queue a pure frame hold at the current insert point, the way the original
-- spends DelayFrames between the beats of a turn.  Mirrors sayNext/drainNext
-- so a caller can interleave holds with messages in source order.
function BattleState:waitNext(frames)
  if not frames or frames <= 0 then return end
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = frames })
end

-- One frame of the HP-bar drain (engine/gfx/hp_bar.asm UpdateHPBar).
--
-- The original walks the bar ONE HP POINT per loop iteration (:81-120), and
-- what each iteration costs depends on the side:
--   * UpdateHPBar_PrintHPNumber spends a DelayFrame (:234) reprinting the
--     number, but only when wHPBarType is nonzero (:207-209) -- the player's
--     own HUD and the party menu, never the enemy's;
--   * UpdateHPBar_AnimateHPBar spends 2 frames for each pixel the bar
--     actually moved (:147-148), and most single-HP steps move none.
-- So the player's bar drains at 1 HP per frame plus 2 frames per pixel,
-- while the enemy's costs nothing until it crosses a pixel boundary.  The
-- old flat maxHP/96 rate was the enemy-side formula applied to both, which
-- ran a 150 HP mon's full drain in 96 frames against hardware's 249.
--
-- Returns true while animating.
function BattleState:stepHPDrain()
  local busy = false
  for _, b in ipairs({ self.player, self.enemy }) do
    if b and b.shownHP then
      -- drainFloor is the stop the running row carries (see drainNext)
      local goal = b.mon.hp
      if b.drainFloor and b.drainFloor > goal
         and b.shownHP >= b.drainFloor then
        goal = b.drainFloor
      end
      local maxHP = math.max(1, b.mon.stats.hp)
      local playerSide = (b == self.player)
      local targetPx = Timing.hpBarPixels(b.shownHP, maxHP)
      if not b.shownPx then b.shownPx = targetPx end
      if (b.drainHold or 0) > 0 then
        b.drainHold = b.drainHold - 1
        -- Once the count runs out with nothing left pending (bar and
        -- number already on the final total), the drain is over, not just
        -- between steps: leave the field at 0 and BattleSafety.inspect
        -- reads it as still mid-animation for the rest of the battle,
        -- since drainHold ~= nil is its settled-presentation gate.
        if b.drainHold <= 0 and b.shownPx == targetPx and b.shownHP == goal
            and not b.draining then
          b.drainHold = nil
        end
        busy = true
      elseif b.shownPx ~= targetPx then
        -- .barAnimationLoop redraws the bar one pixel at a time, `ld c, 2 /
        -- call DelayFrames` apiece (:141-148), so a single HP point that
        -- spans several pixels still slides instead of jumping
        b.shownPx = b.shownPx + ((b.shownPx > targetPx) and -1 or 1)
        b.drainHold = Timing.HP_BAR_PIXEL_STEP - 1
        busy = true
      elseif b.shownHP ~= goal then
        local spent = 0
        -- consume whole HP steps until this frame's budget is spent; on the
        -- enemy HUD several free steps can land in the same frame
        repeat
          b.shownHP = b.shownHP + ((b.shownHP > goal) and -1 or 1)
          spent = spent + (playerSide and Timing.HP_BAR_HP_STEP or 0)
          targetPx = Timing.hpBarPixels(b.shownHP, maxHP)
        until b.shownHP == goal or targetPx ~= b.shownPx or spent >= 1
        if spent > 0 then
          b.drainHold = spent - 1
        elseif targetPx ~= b.shownPx then
          -- the enemy HUD printed no number, so this frame is already the
          -- first of the pixel step the crossing just asked for
          b.shownPx = b.shownPx + ((b.shownPx > targetPx) and -1 or 1)
          b.drainHold = Timing.HP_BAR_PIXEL_STEP - 1
        else
          b.drainHold = 0
        end
        b.draining = true
        busy = true
      elseif b.draining then
        -- .animateHPBarDone's final number print, one more pixel step and
        -- Delay3 (hp_bar.asm:132-135); this frame is the first of them
        b.draining = nil
        b.drainHold = Timing.hpDrainClosingFrames(b == self.player) - 1
        busy = true
      end
    end
  end
  return busy
end

-- the integer HP the HUD shows for a battler (whole HP ticks, like
-- UpdateHPBar's 1-HP steps)
local function shownHP(b)
  local shown = b.shownHP or b.mon.hp
  if shown > b.mon.hp then return math.ceil(shown) end
  return math.floor(shown)
end

-- Parse a battle message into its rendered lines.  The extractor marks
-- \n = next line and \v = CONT (home/text.asm ContText: draw the blinking
-- ▼, WaitForTextScrollButtonPress, then ScrollTextUpOneLine); the boosted /
-- EXP.ALL exp lines end in the CONT code in the ROM (data/generated/text.lua
-- _BoostedText/_WithExpAllText = "...\011").  Each entry is { codes, cont },
-- cont true when the line was preceded by \v.  Splitting before Font.encode
-- keeps the control chars out of the glyph stream.  The box then types into
-- a rolling 2-line window (self.shown) that scrolls when a 3rd line arrives
-- instead of drawing it off-screen at y=144 (#216).
function BattleState:startMessage(item)
  self.current = item
  self.lines = {}
  self.total = 0
  local text = item.text or ""
  local pos, cont = 1, false
  while true do
    local npos = text:find("[\n\v]", pos)
    local chunk = npos and text:sub(pos, npos - 1) or text:sub(pos)
    local codes = Font.encode(chunk)
    self.lines[#self.lines + 1] = { codes = codes, cont = cont, text = chunk }
    self.total = self.total + #codes
    if not npos then break end
    cont = text:sub(npos, npos) == "\v"
    pos = npos + 1
  end
  self.shown = {}        -- up to two visible lines of revealed glyph codes
  self.lineIndex = 0
  -- self.charIndex counts glyphs typed across the WHOLE message (drivers read
  -- it against self.total); the current line's revealed count is #shown[last]
  self.charIndex = 0
  self.msgWaiting = nil
  self.msgPrompt = nil
  self.msgAutoWait = nil
  self.msgHold = nil
  self.scrollPx = nil
  self:beginMsgLine()
end

-- Start typing the next line into the rolling window.  When the box already
-- shows two lines, drop the top one and set the pixel scroll-up
-- (ScrollTextUpOneLine), mirroring TextBox:beginLine.
function BattleState:beginMsgLine()
  self.lineIndex = self.lineIndex + 1
  local ln = self.lines[self.lineIndex]
  self.codes = ln and ln.codes or {}
  if #self.shown >= 2 then
    table.remove(self.shown, 1)
    self.scrollPx = 8
  end
  self.shown[#self.shown + 1] = {}
end

function BattleState:visibleText()
  if self.phase ~= "messages" or not (self.current or self.animPlaying) then
    return nil
  end
  local out, count = {}, #(self.shown or {})
  for i = math.max(1, self.lineIndex - count + 1), self.lineIndex do
    local line = self.lines and self.lines[i]
    if line then out[#out + 1] = line.text or "" end
  end
  return #out > 0 and out or nil
end

function BattleState:updateQueue()
  if self.waitingUI then
    if self.game.stack:top() ~= self then return true end
    self.waitingUI = nil
  end
  -- a queued hold (faint slide, hit blink) counts down before the next row
  if self.waitFrames and self.waitFrames > 0 then
    self.waitFrames = self.waitFrames - 1
    return true
  end
  -- WaitForSoundToFinish (home/delay.asm:15-20) blocks until the sfx has
  -- actually stopped sounding, which is how the original gives a sound its
  -- own clear window instead of letting the next beat play over it
  if self.waitingSound then
    local src = self.waitingSound
    if src and src.isPlaying and src:isPlaying() then return true end
    self.waitingSound = nil
  end
  -- an HP-bar drain holds the queue until the bar catches up
  if self.draining then
    if self:stepHPDrain() then return true end
    self.draining = nil
    if self.player then self.player.drainFloor = nil end
    if self.enemy then self.enemy.drainFloor = nil end
  end
  -- a move animation holds the queue until it finishes; its screen
  -- effects (SE_*) and per-row sounds route into the fx layer as they
  -- fire (applyAnimEffect implements each AnimationXXX routine)
  if self.animPlaying then
    self.animPlayer:update()
    if self.animPlayer.pollEffects and self.applyAnimEffect then
      for _, ev in ipairs(self.animPlayer:pollEffects()) do
        self:applyAnimEffect(ev)
      end
    end
    if self.animPlayer:isDone() then
      self.animPlaying = false
      -- the target's hit blink + damage sound follow the animation
      -- (pokered plays them after PlayMoveAnimation returns)
      if self.pendingHit then
        self:applyHitFx(self.pendingHit)
        self.pendingHit = nil
      end
    end
    return true
  end
  if not self.current then
    local item = table.remove(self.queue, 1)
    if not item then return false end
    if item.fn then
      self.nextInsert = 0 -- sayNext inserts right after this item
      item.fn()
      self.current = nil
      return true
    end
    if item.ui then
      self.waitingUI = true
      self.game.stack:push(item.ui())
      return true
    end
    if item.drain then
      self.draining = true
      if item.battler then item.battler.drainFloor = item.stopAt end
      return true
    end
    if item.wait then
      self.waitFrames = item.wait
      return true
    end
    if item.waitSound then
      -- the source is fetched now, not when the row was queued, so the
      -- act() that started the sound has already run
      self.waitingSound = item.waitSound()
      return true
    end
    if item.mimicSelect then
      -- pause the queue on Mimic's copy menu (MoveSelectionMenu with
      -- wMoveMenuType = 1 lists the enemy's moves; cursor starts on 1)
      local ctx = item.mimicSelect
      local rows = {}
      for i, m in ipairs(ctx.target.curMoves) do
        if m.id and m.pp ~= nil then rows[#rows + 1] = { slot = i, id = m.id } end
      end
      self.mimicMoves = rows
      self.mimicIndex = 1
      self.mimicCtx = ctx
      self.phase = "mimicSelect"
      return true
    end
    -- animation queue rows: play the move sound and start the
    -- subanimation (or just the coarse fx when animations are off).
    -- item.hit carries the target's blink + damage sound, applied when
    -- the animation ends (hitRow rows carry a hit with no animation --
    -- Mimic, whose animation waits on a successful copy).
    if item.anim or item.hitRow then
      -- PlayMoveAnimation writes wAnimationID, calls Delay3, and only then
      -- jumps to MoveAnimation (core.asm:6635-6640), so three frames pass
      -- between the move's announcement and the first frame of its
      -- animation.  Put the row back and pay that first.
      if item.anim and not item.animDelayed then
        item.animDelayed = true
        table.insert(self.queue, 1, item)
        self.waitFrames = Timing.MOVE_ANIM_PRE
        return true
      end
      local mdef = item.anim and self.data.moves[item.anim]
      local anim = mdef and mdef.anim
      if item.anim == "POOF_ANIM" then
        -- the send-out poof plays SFX_BALL_POOF
        require("src.core.Sound").play(self.data, "Ball_Poof")
      elseif item.anim == "HIDEPIC_ANIM" then
        self.enemyHidden = true    -- SE_HIDE_ENEMY_MON_PIC
      elseif item.anim == "SHOWPIC_ANIM" then
        self.enemyHidden = false   -- SE_SHOW_ENEMY_MON_PIC
      end
      -- ball/send-out anims ignore the OPTIONS toggle: PlayMoveAnimation
      -- short-circuits to TossBallAnimation before its wOptions check
      -- (engine/battle/animations.asm:415)
      if item.anim and (self:animationsOn() or BALL_ANIMS[item.anim]) then
        if self.animPlayer then
          local ok = pcall(self.animPlayer.start, self.animPlayer,
                           item.anim, item.attackerIsPlayer,
                           (item.shakes or item.ball)
                             and { shakes = item.shakes, ball = item.ball,
                                   ballFlicker = item.ball
                                     and self:ballFlicker(item.ball) or nil }
                             or nil)
          self.animPlaying = ok
        end
        self.fx = self.fx or {}
        if anim and anim.shake and not self.animPlaying then self.fx.shake = 24 end
        if anim and anim.flash and not self.animPlaying then self.fx.flash = 16 end
      end
      if self.animPlaying then
        -- the animation rows carry their own sounds (PlayAnimation
        -- plays each row's MoveSoundTable entry with its pitch/tempo
        -- modifiers); which side the pic effects target follows the
        -- attacker (hWhoseTurn)
        self.animName = item.anim
        self.animAttackerIsPlayer = item.attackerIsPlayer
        self:resetPicFx()
        for _, ev in ipairs(self.animPlayer:pollEffects()) do
          self:applyAnimEffect(ev) -- frame-0 rows (first sound/effect)
        end
        self.pendingHit = item.hit
      else
        -- no subanimation player: keep the single-sound fallback (with
        -- the move's pitch/tempo modifiers; GROWL/ROAR play the
        -- attacker's cry -- GetMoveSound/IsCryMove)
        if self:animationsOn() and (item.anim == "GROWL" or item.anim == "ROAR") then
          local attacker = item.attackerIsPlayer and self.player or self.enemy
          if attacker then
            require("src.core.Sound").playMoveCry(self.data, attacker.mon.species,
                                                   anim and anim.tempo)
          end
        elseif self:animationsOn() and anim and anim.sound then
          local Sound = require("src.core.Sound")
          if Sound.playMove then
            Sound.playMove(self.data, anim)
          else
            Sound.play(self.data, anim.sound)
          end
        end
        if item.hit then
          self:applyHitFx(item.hit)
        end
      end
      self.current = nil
      return true
    end
    self:startMessage(item)
  end
  local input = self.game.input
  -- a \v CONT wait holds the box until A/B, then scrolls the next line in
  -- (home/text.asm ContText); this keeps a 3rd line on-screen (#216)
  if self.msgWaiting then
    -- _ContText prints the â–¼ and runs ProtectedDelay3 BEFORE ManualTextScroll
    -- starts watching the joypad (home/text.asm:263-267), so three frames
    -- pass with the arrow up and the button ignored
    if (self.msgPreWait or 0) > 0 then
      self.msgPreWait = self.msgPreWait - 1
      return true
    end
    if input:wasPressed("a") or input:wasPressed("b") then
      self.msgWaiting = nil
      self:beginMsgLine()
      -- then the two ScrollTextUpOneLine calls block for 5 frames each
      -- (home/text.asm:280-305) before the next line starts typing
      self.waitFrames = Timing.TEXT_SCROLL_PAIR
    end
    return true
  end
  local cur = self.shown[#self.shown]
  if #cur < #self.codes then
    -- Battle text prints through the same PrintText path as everything
    -- else, so it pays PrintLetterDelay per character (home/print_text.asm:
    -- 4-45): hFrameCounter is loaded from wOptions & $f -- the OPTION text
    -- speed, 1/3/5, default 3 -- and the loop spins until it drains, unless
    -- A or B is held, which collapses the wait to a single DelayFrame.
    -- This used to run two glyphs per frame flat, six times hardware speed
    -- at the default setting, and ignored the text-speed option entirely.
    local delay = (self.game.save.options and self.game.save.options.textSpeed)
                  or 3
    if delay ~= 1 and delay ~= 3 and delay ~= 5 then delay = 3 end
    if input:isDown("a") or input:isDown("b") then delay = 1 end
    self.charTimer = (self.charTimer or 0) + 1
    while self.charTimer >= delay and #cur < #self.codes do
      self.charTimer = self.charTimer - delay
      cur[#cur + 1] = self.codes[#cur + 1]
      self.charIndex = self.charIndex + 1
    end
  elseif self.lineIndex < #self.lines then
    -- current line finished, more lines remain: \v waits for A/B + ▼ before
    -- scrolling, \n advances now (beginMsgLine scrolls if the box is full)
    if self.lines[self.lineIndex + 1].cont then
      self.msgWaiting = true
      self.msgPreWait = Timing.TEXT_PRE_ADVANCE
    else
      self:beginMsgLine()
    end
  else
    local item = self.current
    -- TrainerAboutToUseText ends in `done` then DisplayTextBoxID: YES/NO
    -- overlays the still-visible "Will … change POKéMON?" page.
    if item and item.choice and not item.choiceOpen then
      item.choiceOpen = true
      self.waitingUI = true
      local ChoiceBox = require("src.ui.ChoiceBox")
      local battle = self
      self.game.stack:push(ChoiceBox.new(self.game, function(yes)
        local fn = item.choice
        battle.current = nil
        fn(yes)
      end, item.choiceOpts))
      return true
    end
    if item and item.auto then
      -- No prompt: this page's ROM tail is `text_end`, so PrintText is
      -- already back with the box still on screen -- pokered's used-move
      -- line (engine/battle/used_move_text.asm EndUsedMove1Text..
      -- EndUsedMove5Text) and the item-use line (ItemUseText00,
      -- engine/items/item_effects.asm) are both of that kind.  Only
      -- TX_PROMPT_BUTTON waits on A/B (home/text.asm:434-446) (#765).
      self.msgAutoWait = self.msgAutoWait or item.autoDelay or 0
      if self.msgAutoWait > 0 then
        self.msgAutoWait = self.msgAutoWait - 1
      else
        self.msgAutoWait = nil
        -- the typed page stays drawn behind whatever runs next (the move
        -- animation, the ball toss): PrintText leaves the textbox tilemap
        -- alone and animations only touch sprites (#296)
        self.msgHold = true
        self.current = nil
      end
    elseif not (item and item.choice) then
      if item and item.waitForLearningSfx and not item.soundStarted then
        item.soundStarted = true
        self.waitingSound = item.waitForLearningSfx()
        return true
      end
      -- The page is typed out and waiting on the player: PromptText
      -- (home/text.asm:209-217) writes '▼' at (18,16) and ManualTextScroll
      -- blinks it until A/B, so the arrow belongs on a finished page and not
      -- only on a \v CONT hold (#317).  A flag of its own, not msgWaiting:
      -- that branch above scrolls the NEXT line in, which this page has not
      -- got, so reusing it would call beginMsgLine on a drained message.
      if not self.msgPrompt then
        self.msgPrompt = true
        -- PromptText runs ProtectedDelay3 between writing the arrow and
        -- ManualTextScroll (home/text.asm:213-217), so the page holds for
        -- three frames with the button ignored before it can be dismissed.
        -- Without it a queued A press could clear a page the same frame its
        -- last glyph landed, which is most of "it doesn't hold sometimes".
        self.msgPromptWait = Timing.TEXT_PRE_ADVANCE
      end
      if (self.msgPromptWait or 0) > 0 then
        self.msgPromptWait = self.msgPromptWait - 1
      elseif input:wasPressed("a") or input:wasPressed("b") then
        self.msgPrompt = nil
        self.current = nil
      end
    end
  end
  return true
end

-- ---------------------------------------------------------------------
-- update / menus
-- ---------------------------------------------------------------------

-- PrintSendOutMonMessage (engine/battle/common_text.asm): the shout
-- scales with the enemy's remaining HP percentage, approximated as
-- curHP * 25 / (maxHP / 4): >=70 "Go!", 40-69 "Do it!", 10-39
-- "Get'm!", below 10 "The enemy's weak!  Get'm!".
function BattleState:sendOutText(name)
  local e = self.enemy and self.enemy.mon
  local pct = 100
  if e and e.hp > 0 then
    -- the same routine stamps wLastSwitchInEnemyMonHP
    -- (engine/battle/common_text.asm:105-110)
    self.lastSwitchInEnemyHP = e.hp
    if math.floor(e.stats.hp / 4) > 0 then
      pct = math.floor(e.hp * 25 / math.floor(e.stats.hp / 4))
    end
  end
  if pct >= 70 then return Strings("Go! %s!", name) end
  if pct >= 40 then return Strings("Do it! %s!", name) end
  if pct >= 10 then return Strings("Get'm! %s!", name) end
  return self:romText("_EnemysWeakText", "The enemy's weak!\nGet'm! %s!", name)
end

-- RetreatMon / PlayerMon2Text (engine/battle/common_text.asm:167-243): the
-- adjective reads the enemy HP lost since this mon switched in
function BattleState:withdrawText(name)
  local e = self.enemy and self.enemy.mon
  local drop = 0
  if e and self.lastSwitchInEnemyHP and math.floor(e.stats.hp / 4) > 0 then
    drop = math.floor((self.lastSwitchInEnemyHP - e.hp) * 25
                      / math.floor(e.stats.hp / 4))
  end
  local word = ""
  if drop <= 0 then
    word = self:romText("_EnoughText", "enough!")
  elseif drop >= 70 then
    word = self:romText("_GoodText", "good!")
  elseif drop >= 30 then
    word = self:romText("_OKExclamationText", "OK!")
  end
  return self:romText("_PlayerMon2Text", "%s ", name) .. word
         .. self:romText("_ComeBackText", "\nCome back!")
end

-- The cry a mon makes as it takes the field.  Yellow does not run its
-- starter Pikachu through PlayCry at all: SendOutMon branches to
-- .starterPikachu (engine/battle/core.asm:1807-1817) and voices PCM
-- PikachuCry11, the short "Pika!", or PikachuCry37 when the Pikachu is
-- asleep (IsPlayerPikachuAsleepInParty); PrintBeginningBattleText does the
-- same for the BATTLE_TYPE_PIKACHU intro (engine/battle/common_text.asm:
-- 12-19).  Without a clip the bare playCry reached for clip 1, the long
-- title-screen "Pikachuuu" (#837).  Every PIKACHU gets it here, the same
-- starter approximation the rest of the port makes
-- (PikachuFollower.starterInParty).
function BattleState:playEntranceCry(battler)
  local mon = battler and battler.mon
  if not mon then return end
  return require("src.core.Sound").playCry(self.data, mon.species,
    mon.status == "SLP" and 37 or 11)
end

-- audio/play_battle_music.asm: gym leaders (wGymLeaderNo) get the
-- gym-leader theme, Lance does too, and the Champion (OPP_RIVAL3)
-- gets the final-battle theme
function BattleState:computeMusicKind()
  local isBoss = false
  if self.kind == "trainer" and self.oppClass then
    -- wGymLeaderNo is written only by the eight gym scripts
    -- (scripts/PewterGym.asm .. ViridianGym.asm), so the badge rosters in
    -- victories.lua are exactly the fights that set it.  The lookup must
    -- include the party index: a class-wide prefix match also caught
    -- Giovanni's Rocket Hideout (#1) and Silph Co (#2) battles, which never
    -- touch wGymLeaderNo and take MUSIC_TRAINER_BATTLE like any other
    -- trainer (#782).
    local victories = require("data.scripts.victories")
    local reward = victories[self.oppClass .. "#" .. tostring(self.partyIndex or 1)]
    isBoss = reward ~= nil and reward.badge ~= nil
  end
  -- init_battle.asm: challenging a gym leader (wGymLeaderNo, the badge
  -- fights only -- not Lance or the Champion) bumps the companion's
  -- happiness the moment the battle starts
  self.isGymLeader = isBoss
  if self.kind == "trainer" and self.trainer
     and self.trainer.id == "OPP_RIVAL3" then
    return "final"
  elseif isBoss or (self.trainer and self.trainer.id == "OPP_LANCE") then
    return "gym"
  elseif self.kind == "trainer" or self.kind == "link" then
    return "trainer"
  end
  return "wild"
end

-- a mod-set per-trainer battle theme (trainers.battleTheme, an audio.songs
-- id); nil for vanilla trainers, so the kind default is untouched (#782)
function BattleState:battleTheme()
  local trainer = self.trainer
  if trainer and trainer.battleTheme then return trainer.battleTheme end
  return nil
end

-- the battle-theme cue for this battle: the mod-set trainer battleTheme
-- when the class has one, else the kind default.  The single choke point
-- both the transition-wipe start (OverworldController:pushBattle) and
-- enter() route through, so a per-trainer override can't drift between
-- them.  self.musicKind is set by enter(); pushBattle runs before that,
-- so compute it here when absent.
function BattleState:playBattleTheme()
  require("src.core.Music").playBattle(self.data,
    self.musicKind or self:computeMusicKind(),
    self.trainer and self.trainer.id, self:battleTheme())
end

-- side tables mirror the singles battlers; called before every
-- battler-switch notification so sides[i].battlers[1] stays honest
function BattleState:syncSides()
  self.sides[1].battlers[1] = self.player
  self.sides[2].battlers[1] = self.enemy
end

function BattleState:sideOf(battler)
  return (battler and battler.isPlayer) and self.sides[1] or self.sides[2]
end

-- battle.started's kind verb: the mutated ghost/safari/oldman variants
-- override the constructor's wild/trainer/link
function BattleState:battleKind()
  if self.ghost then return "ghost" end
  if self.safari then return "safari" end
  if self.demo then return "oldman" end
  return self.kind
end

function BattleState:enter()
  -- Out of useable POKéMON before the battle even starts.  pokered does not
  -- skip the battle: .checkAnyPartyAlive (engine/battle/core.asm:158-162)
  -- runs right after the intro and jumps to HandlePlayerBlackOut, so the
  -- player blacks out and afterBattle's "lose" path revives the party at the
  -- last heal point.  Handing the map back with a 0 HP party instead bricked
  -- the save: every later encounter aborted here too and sighted trainers
  -- re-engaged forever (#425).  self.dead alone is not the test --
  -- makeOldManDemo and LinkBattle install a player battler after the
  -- constructor flagged the battle dead.
  if self.dead and not self.player then
    local name = self.game.save.player.name
    self.result = "lose"
    self.game.stack:pop()
    require("src.core.Music").restoreMap(self.data)
    Runtime.emit("battle.ended", { battle = self, result = "lose", skipped = true })
    local onFinish = self.onFinish
    local function blackedOut()
      if onFinish then onFinish("lose") end
    end
    -- the Oak's Lab starter rival returns above PlayerBlackedOutText2 and
    -- afterBattle keeps the player in the lab, so print nothing there
    if BattleState.isOaksLabStarterRival(self) then return blackedOut() end
    -- _PlayerBlackedOutText2 (data/text/text_2.asm:896): the two paragraphs
    -- playerMonFainted queues on the battle screen; there is no battle
    -- screen to queue them on here, so they print over the map.
    -- _PlayerBlackedOutText (no "2") extracts to the identical wording from
    -- a different ROM address and is unused anywhere in this engine -- not
    -- a fallback for this one, just pokered printing the same paragraph
    -- from a second call site elsewhere.
    self.game.stack:push(require("src.render.TextBox").new(self.game,
      self:romText("_PlayerBlackedOutText2",
        "%s is out of\nuseable POKéMON!\f%s blacked\nout!", name, name),
      blackedOut))
    return
  end
  self.musicKind = self:computeMusicKind()
  if self.isGymLeader then
    require("src.world.PikachuFollower")
      .modifyHappiness(self.game.save, "GYMLEADER")
  end
  -- normally already playing: the transition wipe starts the theme
  -- (audio/play_battle_music.asm runs before the transition, and
  -- Music.play no-ops on the same song); this covers battles pushed
  -- without a transition (link battles, scripted pushes)
  self:playBattleTheme()
  -- intro presentation (SlidePlayerAndEnemySilhouettesOnScreen): both
  -- sides slide in; the trainer pics stay up until the send-outs
  -- BATTLE BG "world" drops this battle's opacity so StateStack keeps drawing
  -- the overworld underneath it (see bgMode).  Per instance, so the class
  -- default stays opaque for every other battle and for older saves.
  self.isOpaque = self:bgMode() ~= "world"
  self.introSlide = Timing.BATTLE_SLIDE_IN_FRAMES
  -- GetTrainerInformation .linkBattle (home/trainers2.asm:26-31): the link
  -- foe's pic is RedPicFront whatever either save looks like, and
  -- InitBattleCommon loads and tilemaps it at hlcoord 12,0 for every
  -- wIsInBattle == 2 battle (core.asm:6681-6688), the link one included.
  -- wEnemyMonSpecies2 is zeroed under it, so the pic palette is PAL_MEWMON
  -- exactly as it is for a trainer.
  if self.kind == "link" and not self.trainerPic then
    local frontPath, frontTrueColor =
      require("src.pokemon.Sprites").playerPath(self.data, "front",
        { kind = "battle", battle = self })
    if frontPath and require("src.render.Assets").exists(frontPath) then
      self.trainerPic = getImage(frontPath, namedPalette(self.data, "MEWMON"),
                                 frontTrueColor)
    end
  end
  self.showEnemyTrainer = (self.kind == "trainer" or self.kind == "link")
                          and self.trainerPic ~= nil
  -- DrawAllPokeballs (common_text.asm:27) puts the party ball rows AND the
  -- HUD corner/underline tiles under them (PlacePlayerHUDTiles /
  -- PlaceEnemyHUDTiles, draw_hud_pokeball_gfx.asm:119-165) on screen with
  -- the intro text; _InitBattleCommon (core.asm:6755-6762) ClearScreenArea's
  -- both HUD blocks and ClearSprites's the balls the moment that text is
  -- dismissed.  This flag is exactly that window: drawHUDs draws the intro
  -- chrome while it is up and holds the real enemy HUD back, since a wild
  -- battle's DrawEnemyHUDAndHPBar only runs after the text (#317).  The
  -- draw is still gated on the slide having landed, so nothing shows while
  -- the silhouettes are still coming in.
  self.introBalls = true
  -- SGB: the player-side battle palette while the back pic is up is
  -- MonsterPalettes[0] = PAL_MEWMON (wBattleMonSpecies is still 0 when
  -- the intro's SET_PAL_BATTLE runs -- SetPal_Battle,
  -- engine/gfx/palettes.asm:28)
  -- field.playerPics picks the pic (the catch tutorial's old man fights in
  -- the player's place), then the player.sprite hook gets the last word so
  -- a mod can vary it per save.  It loads through getImage like every other
  -- battle pic, so a replacement keeps the SGB recolor, the transition
  -- fade, the ground-padding measurement and battle_sprite_scales.
  local backPath, backTrueColor =
    require("src.pokemon.Sprites").playerPath(self.data, "back",
      { kind = "battle", demo = self.demo, oakDemo = self.oakDemo,
        battle = self })
  self.playerBackPic = getImage(backPath,
    namedPalette(self.data, "MEWMON"), backTrueColor)
  self.showPlayerBack = self.playerBackPic ~= nil
  -- the enemy's cry as it appears (data/pokemon/cries.asm); PlayCry sits at
  -- a different point in each battle kind, so queue it per branch
  local function queueEnemyCry()
    self:act(function()
      self:waitSfxNext(self:playEntranceCry(self.enemy))
    end)
  end
  -- PrintBeginningBattleText (engine/battle/common_text.asm:10-19): a wild
  -- battle calls PlayCry BEFORE PrintText WildMonAppearedText, and PlayCry
  -- ends in WaitForSoundToFinish, so the cry runs to its end and only then
  -- does the "Wild X appeared!" box open (#303).  The Silph-Scope-less tower
  -- ghost gets no cry at all (common_text.asm:43-48), and neither does the
  -- unveiled MAROWAK: .isMarowak never reaches PlayCry (#492).
  if self.kind ~= "trainer" and self.kind ~= "link"
     and not self.ghost and not self.scopeReveal then
    queueEnemyCry()
  end
  -- PrintBeginningBattleText .trainerBattle (common_text.asm): a trainer
  -- battle gives SFX_SILPH_SCOPE a clear window -- PlaySound, then
  -- WaitForSoundToFinish, which blocks -- and only after `ld c, 20 /
  -- DelayFrames` do DrawAllPokeballs and the "wants to fight!" text run.
  -- The balls and the text used to appear on the same frame the silhouettes
  -- landed, so the sound had to share its whole duration with the ball draw
  -- and the text scroll instead of landing on its own.
  --
  -- The sfx is extracted as "Trainer_Appeared" (tools/rom_manifest.json
  -- sfxHeaders, bank 8 / $42bb -- the same header pokered names
  -- SFX_Silph_Scope); nothing had ever played it.
  --
  -- A link battle is wIsInBattle == 2, so PrintBeginningBattleText takes the
  -- same .trainerBattle arm and owes the sfx too (common_text.asm:20-23).
  if self.kind == "trainer" or self.kind == "link" then
    self:act(function()
      self.introSfx = require("src.core.Sound").play(self.data,
                                                     "Trainer_Appeared")
    end)
    table.insert(self.queue, { waitSound = function() return self.introSfx end })
    table.insert(self.queue, { wait = Timing.TRAINER_INTRO_SFX_GAP })
  end
  self:say(self.introText)
  -- the unveil rides on that same box, before _InitBattleCommon clears the
  -- intro chrome below (#492)
  if self.scopeReveal then self:queueScopeReveal() end
  -- _InitBattleCommon (core.asm:6755-6762): the instant the intro text is
  -- dismissed both HUD blocks are cleared and ClearSprites drops the
  -- pokeball OAM, so the intro chrome never returns for the rest of the
  -- battle -- not on a switch, and not when the beaten trainer's pic
  -- scrolls back in (#317, #282)
  self:act(function() self.introBalls = nil end)
  if self.kind == "trainer" or self.kind == "link" then
    local foeName = self.trainer and self.trainer.name
                    or self.opponentName or Strings("FOE")
    if self.showEnemyTrainer then
      -- EnemySendOutFirstMon (core.asm:1308-1310): SlideTrainerPicOffScreen
      -- walks the foe's pic off the RIGHT edge (hlcoord 18,0, a = 8 tiles,
      -- one tile every 2 frames) BEFORE TrainerSentOutText -- the pic does
      -- not blink out under the text (#317)
      self:act(function() self:slidePic("foe", 0, 64, 4) end)
      table.insert(self.queue, { wait = 16 })
    end
    self:act(function()
      self.showEnemyTrainer = false
      -- the slot is EMPTY from here until AnimateSendingOutMon runs below:
      -- the pic has walked off and the mon is still in its ball, so nothing
      -- stands in the enemy slot while TrainerSentOutText prints.  Without
      -- this the front sprite popped in full-size the instant the trainer
      -- left, sat there through the whole text box, and the grow-in then
      -- restarted it from nothing -- the mon appearing before it was sent
      -- out.  Mirrors the flag the mid-battle replacement already sets.
      self.enemySendingOut = true
      self:slidePic("foe")
    end)
    -- _TrainerSentOutText ends `done`, not `prompt` (data/text/text_2.asm:923)
    self:sayAuto(self:romText("_TrainerSentOutText", "%s sent\nout %s!",
      foeName, self.enemy.name))
    self:act(function()
      -- EnemySendOutFirstMon (core.asm:1421-1434): after the text the
      -- pic grows out of the ball (AnimateSendingOutMon), then the cry
      self.enemySendingOut = false
      self:startGrowIn(self.enemy)
    end)
    queueEnemyCry()
  end
  -- StartBattle .foundFirstAliveEnemyMon (core.asm:152-156): the `call nz`
  -- gates only EnemySendOutFirstMon -- the `ld c, 40 / call DelayFrames`
  -- after it is unconditional, so a wild battle pays it too, between
  -- "Wild X appeared!" and "Go! Y!".  It lands before .playerSendOutFirstMon
  -- (:166), not at the end of the intro.  Appended, not waitNext'd: the
  -- intro is built linearly, and waitNext's insert point is for rows added
  -- while the queue is already running.
  table.insert(self.queue, { wait = Timing.BATTLE_START_SENDOUT })
  if not self.safari and not self.demo then
    -- StartBattle .playerSendOutFirstMon (core.asm:236-240): the back pic
    -- walks off the LEFT edge (SlideTrainerPicOffScreen, hlcoord 1,5,
    -- a = 9 tiles, one tile every 2 frames) BEFORE SendOutMon prints
    -- "Go! X!" -- Red does not simply vanish under the message (#317)
    self:act(function() self:slidePic("back", 0, -72, 4) end)
    table.insert(self.queue, { wait = 18 })
    self:act(function()
      self.showPlayerBack = false
      self.sendingOut = true
      self:slidePic("back")
    end)
    -- _GoText.._PlayerMon1Text carry no prompt (data/text/text_2.asm:1274-1294)
    self:sayAuto(self:sendOutText(self.player.name))
    -- then the POOF plays and the mon appears with its cry
    -- (SendOutMon: message -> AnimateSendingOutMon -> PlayCry)
    self:queueSendOutAnim(true)
    self:markParticipant()
  end
  self.phase = "messages"
  self.afterQueue = "menu"
  self:syncSides()
  Runtime.emit("battle.started", {
    battle = self, kind = self:battleKind(),
    trainerId = self.trainer and self.trainer.id,
    species = self.enemy and self.enemy.mon.species,
    level = self.enemy and self.enemy.mon.level,
  })
end

-- any pop (finish, script teardown) must silence the alarm loop
-- (end_of_battle.asm clears wLowHealthAlarm when a battle ends)
function BattleState:exit()
  require("src.core.Sound").stopLoop("Low_Health_Alarm")
  -- end_of_battle.asm clears wPartyAndBillsPCSavedMenuItem as well, so the
  -- field party menu comes back on slot 1 after a battle. #768
  self.game.partyMenuSavedIndex = nil
  -- Free this battle's own GPU objects now rather than waiting on a GC
  -- finalizer: the two full-screen wavy-effect canvases (colorMode) and
  -- the AnimPlayer's per-instance tilesheet images/quads.  The shared
  -- module caches (imageCache/imagePadBottom, keyed by path+palette) are
  -- reused by the next battle, so they are deliberately left alone -- only
  -- the per-instance objects, which are dead once this battle is popped,
  -- are released here.
  local function rel(o) if o and o.release then pcall(o.release, o) end end
  rel(self.bgCanvas); self.bgCanvas = nil
  rel(self.waveCanvas); self.waveCanvas = nil
  self.colorFxReady = nil
  if self.animPlayer and self.animPlayer.release then
    self.animPlayer:release()
  end
end

-- End a trapping sequence (USING_TRAPPING_MOVE).  SendOutMon clears the
-- foe's bit (core.asm:1761-1762); EnemySendOutFirstMon clears the
-- player's (core.asm:1314-1315).  Any switch frees the other side.
local function clearTrapping(battler)
  if not battler then return end
  battler.trappingTurns = nil
  battler.trapMove = nil
  battler.trapDamage = nil
end

-- SendOutMon (core.asm:1733-1735) clears both battle cursors, though the
-- disassembly only names one of them: `ld hl, wBattleAndStartSavedMenuItem /
-- ld [hli], a / ld [hl], a` writes zero to that byte AND to the byte behind
-- it, which is wPlayerMoveListIndex (wram.asm:242-244).  So every player
-- send-out puts the main menu back on FIGHT and the move list back on the
-- first slot; the cursors are only remembered across sub-menus of the mon
-- that is already out (#737).  Enemy send-outs run EnemySendOutFirstMon,
-- not SendOutMon, and leave both alone.
local function sendOutMonCursors(self)
  self.menuIndex = 1
  self.moveIndex = 1
  self.playerMoveListIndex = 1
end

-- core.asm:297-300: both sides' FLINCHED bits are cleared as a turn's move
-- selection opens, but the clear is skipped for a mon that must recharge or
-- is locked into Rage (core.asm:293-295 -- the Hyper Beam flinch-recharge
-- glitch).
--
-- A method rather than three lines inside the menu branch, because two
-- other places need the identical rule at the identical point in the turn
-- and both got it wrong by not having it:
--
--   * guarded PER BATTLER, not off self.player alone.  This runs on
--     whichever machine is looking at its own menu, and in a lockstep link
--     battle "self.player" is the host's mon on one peer and the guest's on
--     the other, so one shared guard let one peer clear both flags while
--     the other cleared neither -- a bogus desync draw in a winnable match.
--   * a tournament spectator never enters the menu phase at all (it has no
--     decision to make), so nothing cleared a flinch in its replay: the
--     flag survived into the next turn, ate a move the real players saw
--     land, and from there the replay was watching a different battle.
--     LinkBattle.newSpectator calls this at the head of every turn.
function BattleState:clearTurnFlinches()
  for _, b in ipairs({ self.player, self.enemy }) do
    if b and not (b.mustRecharge or b.rageMove) then b.flinched = false end
  end
end

-- Actions that skip DisplayBattleMenu entirely (core.asm:300-310):
-- recharge, Rage, thrash, charge.  Bide / trapping / being held do NOT
-- skip the menu -- the player can still item/switch (and must press
-- FIGHT to continue a trapping sequence).
function BattleState:menuLockedAction(battler)
  if battler.mustRecharge then return { special = "recharge" } end
  if battler.charging then return battler.charging end
  if battler.thrashTurns and battler.thrashTurns > 0 then return battler.thrashMove end
  if battler.rageMove then return battler.rageMove end
  return nil
end

-- After FIGHT: skip MoveSelectionMenu (core.asm:320-329).  Own
-- trapping/Bide continues; foe trapping forces CANNOT_MOVE ($ff).
function BattleState:fightLockedAction(battler)
  if battler.trappingTurns and battler.trappingTurns > 0 then
    return { special = "trapping" }
  end
  if battler.bideTurns then return { special = "bide" } end
  -- held while the OPPONENT's trapping bit is set (live mirror so a
  -- trap ended early by paralysis/faint frees the victim immediately).
  -- Read, not written: executeAction refreshes battler.boundTurns from the
  -- same expression when the action actually runs, and that site runs on
  -- both peers of a link battle.  Storing it here instead wrote a hashed
  -- field on whichever machine happened to open its own FIGHT menu, which
  -- left the two peers holding boundTurns=0 against nil for the same
  -- battler and ended the match as a desync over a mirror of a mirror.
  local opp = battler.isPlayer and self.enemy or self.player
  local bound = opp and opp.trappingTurns
                and math.max(1, opp.trappingTurns) or nil
  if bound then
    return { special = "bound" }
  end
  return nil
end

-- Full lock for AI / callers that need any forced action.
function BattleState:lockedAction(battler)
  return self:menuLockedAction(battler) or self:fightLockedAction(battler)
end

function BattleState:playerHasPP()
  for i, mv in ipairs(self.player.curMoves) do
    if mv.pp > 0 and self.player.disabledSlot ~= i then return true end
  end
  return false
end

-- One semantic path for the native command menu and mod.battle intents.
function BattleState:chooseMenu(choice)
  if self.phase ~= "menu" then return nil, "battle menu is not active" end
  if not self.player or not self.player.mon or self.player.mon.hp <= 0
      or self:menuLockedAction(self.player) then
    return nil, "battle menu is not ready"
  end
  self:clearTurnFlinches()
  if choice == "fight" and self.ghost then
    self:say(Strings("%s is too\nscared to move!", self.player.name))
    self.phase = "messages"
    self.afterQueue = "menu"
    self:act(function()
      self:executeAction(self.enemy, self.player, self:enemyAction())
    end)
    -- A scared turn still ticks the player's residual effects.
    self:queueResidual(self.player, self.enemy)
    self:act(function() self:endOfTurn() end)
  elseif choice == "fight" then
    -- Trapping, Bide, and similar locks skip the move list.
    local fightLock = self:fightLockedAction(self.player)
    if fightLock then
      self:resolveTurn(fightLock)
    elseif not self:playerHasPP() then
      -- No usable PP goes straight to Struggle.
      self:say(Strings("%s has no\nmoves left!", self.player.name))
      self:resolveTurn({ id = "STRUGGLE", pp = 1, struggle = true })
    else
      self.phase = "moveSelect"
      self.moveIndex = math.min(self.moveIndex, #self.player.curMoves)
      self.moveSwapIndex = nil
    end
  elseif choice == "run" then
    self:tryRun()
  elseif choice == "item" then
    self:openItems()
  elseif choice == "party" then
    self:openParty()
  else
    return nil, "unknown battle menu choice"
  end
  return true
end

function BattleState:chooseMove(index)
  if self.phase ~= "moveSelect" then return nil, "move menu is not active" end
  local move = self.player.curMoves[index]
  if not move then return nil, "invalid move slot" end
  self.moveIndex = index
  if self.player.disabledSlot == index then
    self:say(self:romText("_MoveDisabledText", "The move is\ndisabled!"))
    self.phase = "messages"
    self.afterQueue = "menu"
  elseif move.pp <= 0 then
    self:say(self:romText("_MoveNoPPText", "No PP left for\nthis move!"))
    self.phase = "messages"
    self.afterQueue = "menu"
  else
    self.playerMoveListIndex = index
    self:resolveTurn(move)
  end
  return true
end

function BattleState:cancelMove()
  if self.phase ~= "moveSelect" then return nil, "move menu is not active" end
  self.moveSwapIndex = nil
  self.phase = "menu"
  return true
end

local SAFARI_ACTION_INDEX = { ball = 1, bait = 2, rock = 3, run = 4 }

function BattleState:chooseSafari(action)
  if self.phase ~= "menu" or not self.safari then
    return nil, "safari menu is not active"
  end
  if self.safari.balls <= 0 then return nil, "no safari balls remain" end
  local index = SAFARI_ACTION_INDEX[action]
  if not index then return nil, "invalid safari action" end
  self.menuIndex = index
  self:safariAction(action)
  return true
end

function BattleState:chooseMimic(index)
  if self.phase ~= "mimicSelect" then
    return nil, "mimic menu is not active"
  end
  if type(index) ~= "number" or index % 1 ~= 0 then
    return nil, "invalid mimic slot"
  end
  local pick = self.mimicMoves and self.mimicMoves[index]
  local ctx = self.mimicCtx
  if not pick or not ctx then return nil, "invalid mimic slot" end
  self.mimicIndex = index
  self.mimicMoves, self.mimicCtx = nil, nil
  self.phase = "messages"
  self.nextInsert = 0 -- the copy's anim + text go to the queue head
  self:applyMimic(ctx.user, ctx.target, ctx.moveInst, pick.slot)
  return true
end

function BattleState:swapMoves(i, j)
  if i == j then return end
  local moves = self.player.curMoves
  local a, b = moves[i], moves[j]
  if not (a and b) then return end
  moves[i], moves[j] = b, a
  local stored = self.player.mon and self.player.mon.moves
  if stored and stored ~= moves and stored[i] and stored[j] then
    stored[i], stored[j] = stored[j], stored[i]
  end
  local disabled = self.player.disabledSlot
  if disabled == i then
    self.player.disabledSlot = j
  elseif disabled == j then
    self.player.disabledSlot = i
  end
  require("src.core.Sound").play(self.data, "Swap")
end

-- One frame of the presentational clock: the BGP flash sequences, the
-- per-battler pic slide/hide programs, the send-out grow-in, the intro
-- slide and the screen-shake programs all advance in updateFx and nowhere
-- else.  It lives behind its own entry point because a caller that has to
-- skip the rest of update() for a frame must still tick this, and a link
-- battle does exactly that on two hot paths -- waiting on the peer's action,
-- and draining a resolved lockstep turn.  Skipping it there froze whatever
-- was mid-flight: a flash stuck on its inverted BGP step repainted the whole
-- UI in inverted shades, and a pic part-way through a slide-off or a grow-in
-- simply stayed gone -- for as long as the opponent took to choose.
function BattleState:tickFx()
  self.frame = self.frame + 1
  self:updateFx()
end

function BattleState:update(dt)
  self:tickFx()
  local input = self.game.input

  -- safety net: HP/status changed outside a queued drain (level-up heals,
  -- field effects, bag cures) snaps once the queue is idle
  if self.phase == "menu" then
    for _, b in ipairs({ self.player, self.enemy }) do
      if b then
        if b.shownHP then
          b.shownHP = b.mon.hp
          b.shownPx = Timing.hpBarPixels(b.mon.hp, math.max(1, b.mon.stats.hp))
        end
        b.drainFloor = nil
        b.shownStatus = b.mon.status
      end
    end
  end

  if self.phase == "messages" then
    -- Nothing queued starts until the silhouettes have finished sliding in:
    -- SlidePlayerAndEnemySilhouettesOnScreen ends with `jpfar
    -- PrintBeginningBattleText` (engine/battle/core.asm:100), so the enemy
    -- cry and the "Wild X appeared!" box belong at the end of the slide, not
    -- on its first frame (#303).  The hold sits here rather than in
    -- updateQueue because only this loop has a frame clock: updateFx above
    -- counts introSlide down, and a headless caller driving updateQueue on
    -- its own has no slide to wait for.
    if (self.introSlide or 0) > 0 then return end
    if not self:updateQueue() then
      local destination = self.afterQueue
      -- These fields are queue/presentation cursors, not durable battle
      -- state. Once the queue has drained, keeping their terminal values
      -- makes the real command menu look busy to BattleSafety even though
      -- every message, wait and intro animation has settled.
      self.afterQueue = nil
      self.nextInsert = nil
      self.waitFrames = nil
      if destination == "menu" then
        self.introSlide = nil
        self.phase = "menu"
      elseif destination == "finish" then
        self:finish()
      end
    end
    return
  end

  if self.phase == "menu" and self.demo then
    -- DisplayBattleMenu's old-man branch (core.asm:2018-2050): input is
    -- never read.  The player name is swapped to OLD MAN, then the
    -- keystrokes are simulated on screen -- the '▶' cursor sits next to
    -- FIGHT (9,14) for 80 frames, hops down to ITEM (9,16) for 50, goes
    -- hollow ('▷') and the ITEM menu is forced (a = $2 ->
    -- .upperLeftMenuItemWasNotSelected).  The old man never attacks;
    -- backing out of the ball menu re-enters DisplayBattleMenu, which
    -- replays the whole script.
    self.demoTimer = (self.demoTimer or 0) + 1
    if self.demoTimer > 130 then
      self.demoTimer = nil
      self:openOldManBag()
    end
    return
  end

  if self.phase == "menu" and self.safari then
    if self.safari.balls <= 0 then
      self:say(Strings("PA: You're out of\nSAFARI BALLs!\nGame over!"))
      self.phase = "messages"
      self.result = "run"
      self.afterQueue = "finish"
      return
    end
    local col = (self.menuIndex - 1) % 2
    local row = math.floor((self.menuIndex - 1) / 2)
    if input:wasPressed("left") then
      col = math.max(0, col - 1)
    elseif input:wasPressed("right") then
      col = math.min(1, col + 1)
    elseif input:wasPressed("up") then
      row = math.max(0, row - 1)
    elseif input:wasPressed("down") then
      row = math.min(1, row + 1)
    end
    self.menuIndex = row * 2 + col + 1
    if input:wasPressed("a") then
      require("src.core.Sound").play(self.data, "Press_AB")
      self:chooseSafari(({ "ball", "bait", "rock", "run" })[self.menuIndex])
    end
    return
  end

  if self.phase == "menu" then
    -- forced replacement after a faint: ChooseNextMon (core.asm:1086)
    -- loops the party menu until a healthy mon is picked, so B and
    -- fainted picks land back here and reopen it
    if self.player.mon.hp <= 0 then
      if Party.firstHealthy(self:playerPartyView()) then
        self:openReplacementMenu()
      end
      return
    end
    self:clearTurnFlinches()
    -- only recharge/Rage/thrash/charge skip DisplayBattleMenu; trapping
    -- victims (and wrappers) still get FIGHT/PKMN/ITEM/RUN (core.asm:312)
    local locked = self:menuLockedAction(self.player)
    if locked then
      self:resolveTurn(locked)
      return
    end
    -- START has no vanilla action at a settled supported player-decision
    -- boundary.  A tool mod may claim this semantic auxiliary action through
    -- the public hook, receiving only game plus a data-only kind.  The shared
    -- safety predicate keeps every unsupported/forced/animated phase inert.
    if input:wasPressed("start") and Runtime.wantsHook("battle.menu_auxiliary") then
      local safe = BattleSafety.inspect(self.game, self)
      if safe and Runtime.call("battle.menu_auxiliary", function() return false end,
          self.game, { kind = self.kind }) == true then
        return
      end
    end
    local col = (self.menuIndex - 1) % 2
    local row = math.floor((self.menuIndex - 1) / 2)
    if input:wasPressed("left") then
      col = math.max(0, col - 1)
    elseif input:wasPressed("right") then
      col = math.min(1, col + 1)
    elseif input:wasPressed("up") then
      row = math.max(0, row - 1)
    elseif input:wasPressed("down") then
      row = math.min(1, row + 1)
    end
    self.menuIndex = row * 2 + col + 1
    if input:wasPressed("a") then
      require("src.core.Sound").play(self.data, "Press_AB")
      self:chooseMenu(({ "fight", "party", "item", "run" })[self.menuIndex])
    end
    return
  end

  if self.phase == "moveSelect" then
    local moves = self.player.curMoves
    -- The widescreen layout lays the four slots out as a 2x2 grid, so all
    -- four directions navigate it; nil means no direction was pressed and
    -- A / B / SELECT below behave the same in either layout.
    local grid = self:moveGridNavigation()
                 and WideBattle.navigate(self.moveIndex, #moves, input)
    if grid then
      self.moveIndex = grid
    elseif input:wasPressed("up") then
      self.moveIndex = self.moveIndex > 1 and self.moveIndex - 1 or #moves
    elseif input:wasPressed("down") then
      self.moveIndex = self.moveIndex < #moves and self.moveIndex + 1 or 1
    elseif input:wasPressed("select") then
      if self.moveSwapIndex then
        self:swapMoves(self.moveSwapIndex, self.moveIndex)
        self.moveSwapIndex = nil
        self.moveIndex = math.min(self.playerMoveListIndex or 1, #moves)
      else
        self.moveSwapIndex = self.moveIndex
        self.moveIndex = math.min(self.playerMoveListIndex or 1, #moves)
      end
    elseif input:wasPressed("b") then
      require("src.core.Sound").play(self.data, "Press_AB")
      self:cancelMove()
    elseif input:wasPressed("a") then
      require("src.core.Sound").play(self.data, "Press_AB")
      if self.moveSwapIndex then
        self:swapMoves(self.moveSwapIndex, self.moveIndex)
        self.moveSwapIndex = nil
        return
      end
      self:chooseMove(self.moveIndex)
    end
    return
  end

  -- Mimic's mid-move copy menu (MimicEffect .letPlayerChooseMove,
  -- effects.asm:1243-1260): opened by the queue AFTER the hit test
  -- passes.  MoveSelectionMenu's mimic type watches only UP/DOWN/A
  -- (core.asm:2553-2557), so there is no backing out with B.
  if self.phase == "mimicSelect" then
    local moves = self.mimicMoves
    -- the copy menu shares the widescreen move grid, so it navigates the
    -- same way there (the classic layout keeps the vertical list)
    local grid = self:moveGridNavigation()
                 and WideBattle.navigate(self.mimicIndex, #moves, input)
    if grid then
      self.mimicIndex = grid
    elseif input:wasPressed("up") then
      self.mimicIndex = self.mimicIndex > 1 and self.mimicIndex - 1 or #moves
    elseif input:wasPressed("down") then
      self.mimicIndex = self.mimicIndex < #moves and self.mimicIndex + 1 or 1
    elseif input:wasPressed("a") then
      require("src.core.Sound").play(self.data, "Press_AB")
      self:chooseMimic(self.mimicIndex)
    end
    return
  end
end

-- MimicEffect (engine/battle/effects.asm:1203-1273) runs MID-move: a
-- 50-frame beat, MoveHitTest, and only on a hit does the player's copy
-- menu open (.letPlayerChooseMove).  The enemy's Mimic -- and either
-- side of a link battle -- copies a RANDOM non-empty slot instead
-- (.getRandomMove).  Both failure paths (accuracy roll, mid-Fly/Dig
-- target) print PrintButItFailedText_ and skip the move animation.
function BattleState:resolveMimic(user, target, move, moveInst)
  -- ld c, 50 / call DelayFrames before anything happens
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = 50 })
  if target.invulnerable
     or not self:accuracyRoll(move, user, target) then
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end
  local slots = {}
  for i, m in ipairs(target.curMoves) do
    if m.id and m.pp ~= nil then slots[#slots + 1] = i end
  end
  if #slots == 0 then
    -- .getRandomMove rerolls empty slots forever; a moveless target
    -- can't happen in practice, so just fail instead of hanging
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end
  if user.isPlayer and self.kind ~= "link" then
    if self.mimicChoice then -- test-injection hook for the player pick
      local slot = self:mimicChoice(target)
      if slot and target.curMoves[slot] and target.curMoves[slot].pp ~= nil then
        self:applyMimic(user, target, moveInst, slot)
        return
      end
    end
    -- pause the queue on a chooser row; the mimicSelect phase applies
    -- the pick and resumes
    self.nextInsert = self.nextInsert + 1
    table.insert(self.queue, self.nextInsert, {
      mimicSelect = { user = user, target = target, moveInst = moveInst },
    })
    return
  end
  self:applyMimic(user, target, moveInst, slots[self.rng(1, #slots)])
end

-- The copied move OVERWRITES the used slot's move id in place; the PP
-- byte is untouched (only wBattleMonMoves is written, effects.asm:
-- 1261-1266), so the copy inherits Mimic's remaining PP and keeps
-- draining that same slot (DecrementPP hits both the battle copy and
-- the party struct).  curMoves aliases mon.moves, so the original id is
-- remembered and restored when the battler leaves play -- pokered never
-- writes the party copy, and the battle copy is rebuilt from it on a
-- switch or at battle end.  Then PlayCurrentMoveAnimation and
-- _MimicLearnedMoveText.
function BattleState:applyMimic(user, target, moveInst, slot)
  local src = target.curMoves[slot]
  if not (src and src.id) then return end
  local mySlot
  for i, m in ipairs(user.curMoves) do
    if m == moveInst then mySlot = i break end
  end
  if not mySlot then
    -- a called Mimic (Metronome) isn't in the list.  For the player,
    -- non-link case, MimicEffect snapshots wCurrentMenuItem BEFORE the
    -- copy-picker menu opens and restores it afterward as the write
    -- index (effects.asm:1247, 1256/1261) -- it reuses whatever slot
    -- was left highlighted by the FIGHT menu.  That's provably always
    -- the calling move's own slot (e.g. METRONOME's): selecting a move
    -- syncs wCurrentMenuItem and wPlayerMoveListIndex together
    -- (core.asm's SelectMenuItem), and nothing touches either before
    -- the effect runs.  self.moveIndex mirrors this exactly -- it's
    -- frozen at the FIGHT-menu confirm and untouched through mid-move
    -- resolution -- so it already equals the calling move's slot here;
    -- there's no separate "reused index" to chase.  (Enemy/link Mimic
    -- instead reads w*MoveListIndex directly, effects.asm:1235-1241.)
    mySlot = user.isPlayer and math.min(self.moveIndex or 1, #user.curMoves) or 1
  end
  local entry = user.curMoves[mySlot]
  self.mimicRestores = self.mimicRestores or {}
  table.insert(self.mimicRestores, { battler = user, entry = entry, id = entry.id })
  entry.id = src.id
  entry.mimic = true
  self:animNext("MIMIC", user.isPlayer)
  -- _MimicLearnedMoveText: "<USER> / learned / MOVE!"
  self:sayNext(self:romText("_MimicLearnedMoveText", "%s\nlearned\n%s!", displayName(user),
                                           self.data.moves[src.id].name))
end

-- Undo Mimic's in-place id overwrite for a battler leaving play (the GB
-- battle copy is discarded; the party struct never changed).
function BattleState:restoreMimicked(battler)
  if not self.mimicRestores then return end
  local keep = {}
  -- iterate newest-first so the oldest snapshot (the true pre-Mimic
  -- move id, from before any repeated Mimic-on-Mimic via Metronome)
  -- is applied last and wins, instead of a stale intermediate id
  for i = #self.mimicRestores, 1, -1 do
    local r = self.mimicRestores[i]
    if r.battler == battler then
      r.entry.id, r.entry.mimic = r.id, nil
    else
      keep[#keep + 1] = r
    end
  end
  self.mimicRestores = #keep > 0 and keep or nil
end

-- BagWasSelected's old-man fork (core.asm:2193-2210): the list menu is
-- fed OldManItemList -- one POKé BALL x50 -- instead of the player's
-- bag.  The list is as scripted as the battle menu (DisplayListMenuID's
-- old-man branch, home/list_menu.asm:65-80): no input is ever read --
-- backing out is impossible -- the '▶' sits in front of POKé BALL for
-- 80 frames, then A is auto-pressed and .buttonAPressed's
-- PlaceUnfilledArrowMenuCursor leaves the hollow '▷' on the row for the
-- handful of frames UseBagItem takes to reach ItemUseBall's screen
-- restore (item_effects.asm:145) and the throw text.
function BattleState:openOldManBag()
  local ListMenu = require("src.ui.ListMenu")
  local game = self.game
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    local list
    -- The canned bag (POKE_BALL, not read from the player's real
    -- inventory) differs by version: pokered's OldManItemList has 50
    -- POKé BALLs; pokeyellow's SimulatedInputBattleItemList, shared by
    -- the Viridian tutorial and Oak's catch, has one.
    local qty = require("src.core.GameVersion").isYellow() and "x1" or "x50"
    -- the tutorial bag rides DisplayBagMenu's LIST_MENU_BOX over the battle
    -- screen (engine/battle/core.asm:2210)
    list = ListMenu.new(game, "ITEMS", {
      { value = "POKE_BALL", label = Strings("POKé BALL"), right = qty },
    }, {
      itemBox = true,
      script = function(l)
        l.scriptTimer = (l.scriptTimer or 0) + 1
        if l.scriptTimer == 81 then
          -- the auto A-press: the cursor goes hollow on the chosen row
          l.hollowIndex = l.index
        elseif l.scriptTimer > 88 then
          -- ItemUseBall takes over: list down, OLD MAN throws
          l:close()
          self:oldManThrow()
        end
      end,
    })
    return list
  end)
end

-- ItemUseBall for BATTLE_TYPE_OLD_MAN: the party/box-full checks are
-- skipped (item_effects.asm:114-118), every capture calculation is
-- skipped -- the old man branch jumps straight to .captured, $43 anim
-- data = 3 shakes and caught (:155-164 + :193-200) -- and
-- .oldManCaughtMon prints the caught text WITHOUT adding the mon to
-- the party or the dex (:568-570).  Yellow's initial training is the one
-- exception (demoFails, #636): its .oldManBattle branch forces $63, so
-- the same chain ends in a breakout and ItemUseBallText04 instead.
-- The "used" line reads OLD MAN
-- because DisplayBattleMenu swapped wPlayerName (core.asm:2024-2037);
-- no ball is consumed (.done returns early, :576-578).
function BattleState:oldManThrow()
  self.phase = "messages"
  self.afterQueue = "finish"
  self.result = "run" -- nothing is kept; wBattleResult only ends the demo
  self:sayAuto(Strings("%s used\nPOKé BALL!", self.demoName or Strings("OLD MAN")))
  self:act(function()
    require("src.core.Sound").play(self.data, "Ball_Toss")
    -- ItemUseBall's beat before the toss chain (like throwBall)
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert, { wait = 20 })
    if self.demoFails then
      -- $63 instead of $43: the same three shakes, then POOF+SHOWPIC and
      -- ItemUseBallText04.  No sound_caught_mon, and .captured is never
      -- reached, so nothing touches the party or the dex either (#636).
      self:ballChain("TOSS_ANIM", false, 3, "POKE_BALL")
      self:sayNext(self:ballMissMessage(3))
      return
    end
    self:ballChain("TOSS_ANIM", true, 3, "POKE_BALL")
    -- ItemUseBallText05: text_far, sound_caught_mon, text_promptbutton --
    -- the fanfare follows the caught text and holds the prompt
    self:sayNextWaitSfx(Strings("All right!\n%s was\ncaught!", self.enemy.name),
      function() return require("src.core.Sound").play(self.data, "Caught_Mon") end)
  end)
end

-- ---------------------------------------------------------------------
-- turn resolution
-- ---------------------------------------------------------------------

function BattleState:moveDef(moveInst)
  return self.data.moves[moveInst.id]
end

-- the merged move_effects record for an effect id; the module records
-- cover battles built without a loader
function BattleState:effectRecord(effect)
  local effects = self.data.move_effects
  if effects then return effects[effect] end
  return MoveEffects.RECORDS[effect]
end

-- the merged ball record (Catching.attempt handles the unknown-id default)
function BattleState:ballDef(ball)
  local balls = self.data.balls
  return balls and balls[ball] or Catching.BALLS[ball]
end

-- the HUD label drawn in place of the level for a statused mon
function BattleState:statusLabel(mon)
  return Status.hudLabelFor(self.data.statuses, mon.status)
end

-- the one accuracy roll (MoveHitTest), hooked as battle.accuracy
function BattleState:accuracyRoll(move, user, target)
  if Runtime.wantsHook("battle.accuracy") then
    return Runtime.call("battle.accuracy", function(c)
      return Damage.accuracyRoll(c.ruleset, c.move, c.user, c.target, c.rng)
    end, { battle = self, ruleset = self.ruleset, move = move,
           user = user, target = target, rng = self.rng })
  end
  return Damage.accuracyRoll(self.ruleset, move, user, target, self.rng)
end

-- Damage.compute, hooked as battle.damage; the ctx table is only built
-- when a chain is installed, so the no-mod path allocates nothing
function BattleState:computeDamage(user, target, move, opts)
  if Runtime.wantsHook("battle.damage") then
    return Runtime.call("battle.damage", function(c)
      return Damage.compute(c.ruleset, c.user, c.target, c.move, c.opts)
    end, { battle = self, ruleset = self.ruleset, user = user,
           target = target, move = move, opts = opts, rng = self.rng })
  end
  return Damage.compute(self.ruleset, user, target, move, opts)
end

-- Catching.attempt against the merged registry, hooked as catch.rate
function BattleState:catchAttempt(ball, rateOverride)
  if Runtime.wantsHook("catch.rate") then
    local battle = self
    return Runtime.call("catch.rate", function(b, mon, def, o)
      return Catching.attempt(b, mon, def, o.rng, o.rateOverride,
        { ballDef = battle:ballDef(b), statuses = battle.data.statuses,
          battle = battle })
    end, ball, self.enemy.mon, self.enemy.def,
    { rng = self.rng, rateOverride = rateOverride, battle = self })
  end
  return Catching.attempt(ball, self.enemy.mon, self.enemy.def, self.rng,
    rateOverride, { ballDef = self:ballDef(ball),
                    statuses = self.data.statuses, battle = self })
end

-- wAICount: item/switch uses per enemy Pokémon for this trainer class
function BattleState:aiUsesFor()
  if self.kind ~= "trainer" or not self.trainer then return 0 end
  local class = TrainerAI.classFor(self)
  return class and class.uses or 0
end

-- Exp participants: every player mon that has been in against the
-- current enemy mon (wPartyGainExpFlags).
function BattleState:markParticipant()
  self.participants = self.participants or {}
  if self.player and self.player.mon then
    self.participants[self.player.mon] = true
  end
end

-- the whole choke point is hooked (battle.enemy_action), so a mod can
-- rewrite any trainer's choice without registering brains
function BattleState:enemyAction()
  if Runtime.wantsHook("battle.enemy_action") then
    return Runtime.call("battle.enemy_action", function(battle)
      return battle:vanillaEnemyAction()
    end, self)
  end
  return self:vanillaEnemyAction()
end

function BattleState:vanillaEnemyAction()
  local locked = self:lockedAction(self.enemy)
  if locked then return locked end
  -- an ai_classes brain (or one on the trainer record) supersedes the
  -- class action and move scoring entirely
  if self.kind == "trainer" and self.trainer then
    local class = TrainerAI.classFor(self)
    local brain = self.trainer.brain or (class and class.brain)
    if brain then return brain(self) end
  end
  -- class AI may spend the turn on an item or a switch
  local classAct = TrainerAI.classAction(self)
  if classAct then return classAct end
  return TrainerAI.chooseMove(self.enemy, self.rng, self)
end

local function orderMove(action, data)
  if action and action.id then return data.moves[action.id] end
  return nil
end

function BattleState:resolveTurn(playerAction)
  local enemyAction = self:enemyAction()
  self.turnCount = (self.turnCount or 0) + 1
  Runtime.emit("battle.turn_started", {
    battle = self, turn = self.turnCount,
    playerAction = playerAction, enemyAction = enemyAction,
  })
  local pMove = orderMove(playerAction, self.data)
  local eMove = orderMove(enemyAction, self.data)
  local pFirst
  if Runtime.wantsHook("battle.turn_order") then
    pFirst = Runtime.call("battle.turn_order", function(a, aMove, b, bMove, c)
      return TurnOrder.firstMover(a, aMove, b, bMove, c.rng, c.invertTie)
    end, self.player, pMove, self.enemy, eMove, { rng = self.rng })
  else
    pFirst = TurnOrder.firstMover(self.player, pMove, self.enemy, eMove, self.rng)
  end
  local order
  if pFirst then
    order = { { true, playerAction }, { false, enemyAction } }
  else
    order = { { false, enemyAction }, { true, playerAction } }
  end

  self.phase = "messages"
  self.afterQueue = "menu"

  for _, entry in ipairs(order) do
    self:act(function()
      local user = entry[1] and self.player or self.enemy
      local target = entry[1] and self.enemy or self.player
      self:executeAction(user, target, entry[2])
    end)
  end
  self:act(function() self:endOfTurn() end)
end

-- A switch action: replace the player's mon, enemy gets a free move.
function BattleState:resolveSwitch(newMon)
  self.phase = "messages"
  self.afterQueue = "menu"
  self:act(function()
    -- SwitchPlayerMon (core.asm:2419-2423): RetreatMon prints over the
    -- outgoing pic and holds 50 frames, then AnimateRetreatingPlayerMon
    -- runs before the mon is recalled
    self:sayNextAuto(self:withdrawText(self.player.name),
                     Timing.SWITCH_PLAYER_MON)
    self:queueRetreatAnim()
    self:actNext(function()
      self:restoreMimicked(self.player) -- the battle copy leaves with it
      local previous = self.player
      self.player = makeBattler(self.data, newMon, true, self.game.save)
      -- SendOutMon (core.asm:1761-1762): player's send-out clears the
      -- foe's USING_TRAPPING_MOVE -- Wrap/Bind/etc. ends on any switch
      clearTrapping(self.enemy)
      self:syncSides()
      Runtime.emit("battle.battler_switched", {
        battle = self, side = self.sides[1], battler = self.player,
        previous = previous,
      })
      self:markParticipant()
      sendOutMonCursors(self)
      self.sendingOut = true
      self:sayNextAuto(self:sendOutText(self.player.name))
      self:queueSendOutAnim(false)
    end)
  end)
  self:act(function()
    self:executeAction(self.enemy, self.player, self:enemyAction())
  end)
  self:act(function() self:endOfTurn() end)
end

-- Gen 1 calls HandlePoisonBurnLeechSeed right after the acting side's
-- move (core.asm:426-464), so the drain lands before the slower mon acts;
-- the modern ruleset sweeps residuals at end of round instead (Gen 3+).
local function residualAfterMove(battle)
  local ruleset = battle.ruleset
  return not ruleset or ruleset.residualAfterMove ~= false
end

-- HandlePoisonBurnLeechSeed for one side, run right after its action.
-- Skipped when the action settled the battle (a Teleport escape rets
-- before the call), when an AI switch swapped the side out mid-action, or
-- when the move already knocked the opponent out (core.asm:423-425,
-- 452-454) -- the same bypass the end-of-round sweep applies.
function BattleState:residualFor(b, opp)
  if self.result then return end
  if self.player ~= b and self.enemy ~= b then return end
  if b.mon.hp <= 0 or opp.mon.hp <= 0 then return end
  -- engine/battle/core.asm:435-473
  if b.residualDone then return end
  b.residualDone = true
  local msgs = Status.residual(b, opp, self)
  local rec = Status.recordFor(self.data and self.data.statuses, b.mon.status)
  for _, m in ipairs(msgs) do self:sayNext(prefixEnemy(m, b)) end
  -- engine/battle/core.asm:490-493
  if rec and rec.residual then
    self:animNext("BURN_PSN_ANIM", b.isPlayer)
  end
  if b.leechSeeded and b.mon.hp > 0 then
    -- the drain plays the ABSORB animation from the healing side
    -- (core.asm:506-517 flips hWhoseTurn before PlayMoveAnimation)
    self:animNext("ABSORB", opp.isPlayer)
  end
  if #msgs > 0 then self:drainNext() end -- poison/burn/seed HP moved
  self.sideToxic = self.sideToxic or {}
  if b.toxicCounter then
    self.sideToxic[b.isPlayer and "player" or "enemy"] = b.toxicCounter
  end
  if b.mon.hp <= 0 then
    self:onFaint(b)
  end
end

-- append one side's residual to the queue under Gen 1 timing; a no-op
-- under the modern ruleset, whose sweep runs in endOfTurn instead
function BattleState:queueResidual(b, opp)
  if residualAfterMove(self) then
    self:act(function() self:residualFor(b, opp) end)
  end
end

function BattleState:endOfTurn()
  -- the same ret: a decided battle never reaches HandlePoisonBurnLeechSeed
  -- or CheckNumAttacksLeft (core.asm:417-421, 456-460), so the residual
  -- sweep and the trapping-counter release are skipped on the turn a
  -- Teleport escape (or a win/loss/capture) settles it (#441).  The
  -- turn_ended hook still fires: mods count turns, not residuals.
  if self.result then
    Runtime.emit("battle.turn_ended", { battle = self, turn = self.turnCount or 0 })
    return
  end
  -- sideToxic mirrors w*ToxicCounter: it advances only while the
  -- battler's badly-poisoned flag (toxicCounter) is set, an item/AI
  -- cure clears the flag but NOT the side counter, and a fresh Toxic
  -- re-seeds it (effects.asm:137-139 zeroes the counter when setting
  -- BADLY_POISONED).  It is never copied back onto a battler: pokered
  -- reads the counter only while the flag is set, and the only code
  -- that sets the flag also zeroes the counter, so a stale value is
  -- unobservable (a switch or cure downgrades Toxic to plain poison).
  self.sideToxic = self.sideToxic or {}
  -- Gen 1 timing already ran each side's residual right after its move
  -- (see executeAction); the end-of-round sweep is the modern ruleset's
  local sweep = not residualAfterMove(self)
  -- a battler whose opponent was already knocked out by a move this turn
  -- skips its own residual (HandlePoisonBurnLeechSeed is bypassed when the
  -- move faints the target); snapshot before residual so one side's
  -- residual faint can't suppress the other's
  local playerAlive = self.player.mon.hp > 0
  local enemyAlive = self.enemy.mon.hp > 0
  for _, pair in ipairs({ { self.player, self.enemy, "player", enemyAlive },
                          { self.enemy, self.player, "enemy", playerAlive } }) do
    local b, opp, side, oppAlive = pair[1], pair[2], pair[3], pair[4]
    if sweep and not b.residualDone and b.mon.hp > 0 and oppAlive then
      b.residualDone = true
      local msgs = Status.residual(b, opp, self)
      for _, m in ipairs(msgs) do self:sayNext(prefixEnemy(m, b)) end
      if #msgs > 0 then self:drainNext() end -- poison/burn/seed HP moved
      if b.toxicCounter then
        self.sideToxic[side] = b.toxicCounter
      end
      if b.mon.hp <= 0 then
        self:onFaint(b)
      end
    end
    -- the Haze move-forfeit only covers the turn Haze was used; if the
    -- cured mon had already moved, drop the flag before next turn
    b.skipMove = nil
    b.residualDone = nil
    -- CheckNumAttacksLeft (core.asm:683-697): a trapping counter that
    -- hit 0 this turn releases its bit only now, at the end of the turn
    if b.trappingTurns and b.trappingTurns <= 0 then
      b.trappingTurns = nil
    end
  end
  self:tickTokens()
  Runtime.emit("battle.turn_ended", { battle = self, turn = self.turnCount or 0 })
end

-- side/field tokens ({ id, turns?, onResidual?, onExpire? }) tick after
-- the residual sweep; with the tables empty this is a nil check per list
local function tickTokenList(battle, tokens, holder)
  if tokens[1] == nil then return end
  for i = #tokens, 1, -1 do
    local token = tokens[i]
    if token.turns then token.turns = token.turns - 1 end
    if token.onResidual then token.onResidual(battle, holder) end
    if token.turns and token.turns <= 0 then
      if token.onExpire then token.onExpire(battle, holder) end
      table.remove(tokens, i)
    end
  end
end

function BattleState:tickTokens()
  for _, side in ipairs(self.sides) do
    tickTokenList(self, side.tokens, side)
  end
  tickTokenList(self, self.field.tokens, self.field)
end

-- ---------------------------------------------------------------------
-- battle animation layer
-- ---------------------------------------------------------------------
--
-- An approximation of the original's subanimation bytecode engine
-- (docs/known-differences.md): the move's real sound (data/moves/sfx.asm
-- via each move's anim table), screen shake / flash for moves whose
-- animation data uses SE_SHAKE_SCREEN / screen-flash effects, target
-- blink on damage, and a faint slide with the cry.  The Poké Ball toss
-- chain (toss/poof/hide/shake/show) rides the queue as anim rows.

-- the OPTIONS animation toggle (sounds always play)
function BattleState:animationsOn()
  local o = self.game.save.options
  return not o or o.animations ~= false
end

-- Drop the announcement-time move-anim row.  Gen 1 queues PlayMoveAnimation
-- only after MoveHitTest / the effect lands (HandleIfPlayerMoveMissed skips
-- it on a miss unless EXPLODE_EFFECT); we insert early for blink attachment
-- and peel it back on miss/fail paths.
-- Dig/Fly charge leaves the user pic hidden (SLIDE_DOWN / TELEPORT); the
-- second-turn DIG/FLY anim restores it via SE_SLIDE_MON_UP / SE_SHOW_MON_PIC.
-- Cancelling that row on miss/immune would otherwise leave the digger
-- invisible until another anim's resetPicFx (#100).
function BattleState:cancelMoveAnim()
  local row = self.moveAnimRow
  if not row then return end
  self.moveAnimRow = nil
  if row.anim == "DIG" or row.anim == "FLY" then
    local user = row.attackerIsPlayer and self.player or self.enemy
    local pf = user and self.picFx and self.picFx[user]
    if pf then pf.hidden = nil end
  end
  for i, item in ipairs(self.queue) do
    if item == row then
      table.remove(self.queue, i)
      if self.nextInsert and i <= self.nextInsert then
        self.nextInsert = self.nextInsert - 1
      end
      return
    end
  end
end

-- ------------------------------------------------------------------
-- special-effect (SE_*) implementations.  Palette effects are BGP
-- shade maps ({[i] = shade color index i displays as}); on the SGB the
-- colorizer colors the REMAPPED shade, so the zone palettes are
-- permuted through the active map (engine/battle/animations.asm
-- SetAnimationBGPalette / AnimationFlashScreen / ...ScreenLong).
-- ------------------------------------------------------------------

local BGP_IDENTITY = { [0] = 0, 1, 2, 3 }              -- $e4
local BGP_INVERT   = { [0] = 3, 2, 1, 0 }              -- $1b (flash phase 1)
local BGP_WHITE    = { [0] = 0, 0, 0, 0 }              -- $00 (flash phase 2)
local BGP_DARK     = { [0] = 3, 3, 2, 1 }              -- $6f DarkScreenPalette
local BGP_LIGHT    = { [0] = 0, 0, 1, 2 }              -- $90 LightScreenPalette
local BGP_DARKEN   = { [0] = 0, 1, 3, 3 }              -- $f4 DarkenMonPalette (SGB)

-- FlashScreenLongSGB (animations.asm:1010): 12 BGP values per cycle,
-- 3 cycles; the first cycle holds each for 2 frames, the rest for 1
-- (FlashScreenLongDelay)
local FLASH_LONG_MAPS = {
  { [0] = 0, 2, 3, 3 }, { [0] = 0, 3, 3, 3 }, { [0] = 3, 3, 3, 3 },
  { [0] = 0, 3, 3, 3 }, { [0] = 0, 2, 3, 3 }, { [0] = 0, 1, 2, 3 },
  { [0] = 0, 0, 1, 2 }, { [0] = 0, 0, 0, 1 }, { [0] = 0, 0, 0, 0 },
  { [0] = 0, 0, 0, 1 }, { [0] = 0, 0, 1, 2 }, { [0] = 0, 1, 2, 3 },
}

-- the shade map in force this frame (a running flash wins over the
-- persistent palette)
function BattleState:activeBgp()
  local fx = self.fx
  if not fx then return nil end
  local seq = fx.bgpSeq
  if seq then
    local st = seq.steps[seq.idx]
    if st then return st.map end
  end
  return fx.bgp
end

-- per-battler pic effect state (offsets/hides driven by the SE rows)
function BattleState:picFxFor(battler)
  if not battler then return nil end
  self.picFx = self.picFx or {}
  local pf = self.picFx[battler]
  if not pf then
    pf = { ox = 0, oy = 0 }
    self.picFx[battler] = pf
  end
  return pf
end

-- transient pic effects reset when a new animation row starts (each
-- PlayAnimation redraws from a clean slate); `minimized` survives --
-- the minimize sprite replaces the pic DATA until reload. Dig/Fly's
-- charge hide is a cleared tilemap that must survive until SE_SHOW_* /
-- SE_SLIDE_MON_UP (or cancelMoveAnim on a missed Dig/Fly release):
-- clearing it here made Dig pop in before emerge and wrap/bounce (#100).
-- Other hides (Acid Armor, etc.) still clear so the next anim restores.
function BattleState:resetPicFx()
  if not self.picFx then return end
  local digFly = self.animName == "DIG" or self.animName == "FLY"
  local digFlyUser = digFly and (self.animAttackerIsPlayer
                                 and self.player or self.enemy) or nil
  for battler, pf in pairs(self.picFx) do
    pf.kind, pf.t = nil, nil
    pf.ox, pf.oy = 0, 0
    local keepHide = battler.invulnerable or battler == digFlyUser
    if not keepHide then
      pf.hidden = nil
    end
  end
end

-- the battler an SE row's routine acts on: "the mon" is the attacker's
-- side; the SE_*_ENEMY_* variants run through CallWithTurnFlipped
function BattleState:animFxBattler(flipped)
  local isPlayer = self.animAttackerIsPlayer
  if flipped then isPlayer = not isPlayer end
  return isPlayer and self.player or self.enemy
end

-- a row's sound byte is a move id: GetMoveSound plays its
-- MoveSoundTable sfx with the pitch/tempo modifier bytes; for the
-- GROWL/ROAR animations (IsCryMove) it plays the attacker's cry, with
-- the move's own pitch/tempo bytes (from its own row, soundMove ==
-- self.animName for these) layered on as the extra shift
function BattleState:playAnimSound(soundMove)
  local Sound = require("src.core.Sound")
  local mdef = self.data.moves[soundMove]
  if self.animName == "GROWL" or self.animName == "ROAR" then
    local attacker = self:animFxBattler(false)
    if attacker then
      Sound.playMoveCry(self.data, attacker.mon.species,
                         mdef and mdef.anim and mdef.anim.tempo)
    end
    return
  end
  if mdef and mdef.anim then
    if Sound.playMove then
      Sound.playMove(self.data, mdef.anim)
    else
      Sound.play(self.data, mdef.anim.sound)
    end
  end
end

local function startPicKind(pf, kind)
  if not pf then return end
  pf.kind, pf.t = kind, 0
  pf.hidden = nil
end

-- PredefShakeScreenHorizontally (engine/gfx/screen_effects.asm): the window
-- jumps right by b for 5 frames then home for 4, b counting down to 1.
-- b = 8 for SE_SHAKE_SCREEN and the heavy applying-attack shake, b = 2 for
-- the light one.
local function fastShakeProg(b)
  local prog = {}
  for i = b, 1, -1 do
    prog[#prog + 1] = { dx = i, frames = 5 }
    prog[#prog + 1] = { dx = 0, frames = 4 }
  end
  return prog
end

-- AnimationShakeScreenHorizontallySlow (engine/battle/animations.asm:526):
-- rWX creeps 1px right every 2 frames b times, then back down to 0, c times
-- over.  Silent -- this is the non-damaging move's feedback.
local function slowShakeProg(b, c)
  local prog = {}
  for _ = 1, c do
    for i = 1, b do prog[#prog + 1] = { dx = i, frames = 2 } end
    for i = b - 1, 0, -1 do prog[#prog + 1] = { dx = i, frames = 2 } end
  end
  return prog
end

-- Route one AnimPlayer event into the fx layer.  Frame counts and
-- amplitudes are the routines' own (engine/battle/animations.asm;
-- shakes: engine/gfx/screen_effects.asm).
function BattleState:applyAnimEffect(ev)
  self.fx = self.fx or {}
  local fx = self.fx
  if ev.sound then
    self:playAnimSound(ev.sound)
  end
  local e = ev.effect
  if not e then return end

  if e == "SFX_TINK" then
    -- each ball shake opens with a tink (DoBallShakeSpecialEffects)
    require("src.core.Sound").play(self.data, "Tink")

  -- ---------------------------------------------- palette effects
  elseif e == "SE_DARK_SCREEN_PALETTE" then
    fx.bgp = BGP_DARK
  elseif e == "SE_LIGHT_SCREEN_PALETTE" then
    fx.bgp = BGP_LIGHT
  elseif e == "SE_DARKEN_MON_PALETTE" then
    fx.bgp = BGP_DARKEN
  elseif e == "SE_RESET_SCREEN_PALETTE" then
    fx.bgp = nil
  elseif e == "SE_DARK_SCREEN_FLASH" then
    -- AnimationFlashScreen: 2 frames inverted, 2 frames white, restore
    fx.bgpSeq = { steps = { { map = BGP_INVERT, frames = 2 },
                            { map = BGP_WHITE, frames = 2 } },
                  idx = 1, left = 2 }
  elseif e == "SE_FLASH_SCREEN_LONG" then
    local steps = {}
    for cycle = 1, 3 do
      for _, m in ipairs(FLASH_LONG_MAPS) do
        steps[#steps + 1] = { map = m, frames = (cycle == 1) and 2 or 1 }
      end
    end
    fx.bgpSeq = { steps = steps, idx = 1, left = steps[1].frames }

  -- ---------------------------------------------- screen shakes
  elseif e == "SE_SHAKE_SCREEN" then
    fx.shakeProg = fastShakeProg(8)
  elseif e == "SE_ROCK_SLIDE_SHAKE" then
    -- DoRockSlideSpecialEffects: 1px horizontal then vertical rumble
    fx.shakeProg = { { dx = 1, frames = 5 }, { dx = 0, frames = 4 },
                     { dy = 1, frames = 3 }, { dy = 0, frames = 3 } }
  elseif e == "SE_SHAKE_ENEMY_HUD" then
    -- AnimationShakeEnemyHUD: SCX +-2 for 2 frames each, 8 times; the
    -- window + a sprite copy of the back pic keep everything below the
    -- enemy HUD still, so only the HUD area moves
    local prog = {}
    for _ = 1, 8 do
      prog[#prog + 1] = { dx = 2, frames = 2 }
      prog[#prog + 1] = { dx = -2, frames = 2 }
    end
    fx.hudShakeProg = prog
  elseif e == "SE_WAVY_SCREEN" then
    -- AnimationWavyScreen: 255 frames of per-scanline SCX offsets
    -- walking WavyScreenLineOffsets
    fx.wavy = { left = 255, phase = 0 }

  -- ---------------------------------------------- mon pic effects
  elseif e == "SE_SLIDE_MON_OFF" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "slideOff")
  elseif e == "SE_SLIDE_ENEMY_MON_OFF" then
    startPicKind(self:picFxFor(self:animFxBattler(true)), "slideOff")
  elseif e == "SE_SLIDE_MON_HALF_OFF" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "slideHalf")
  elseif e == "SE_SLIDE_MON_UP" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "slideUp")
  elseif e == "SE_SLIDE_MON_DOWN" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "slideDown")
  elseif e == "SE_SLIDE_MON_DOWN_AND_HIDE" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "slideDownHide")
  elseif e == "SE_SHAKE_BACK_AND_FORTH" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "shakeBF")
  elseif e == "SE_BOUNCE_UP_AND_DOWN" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "bounce")
  elseif e == "SE_SQUISH_MON_PIC" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "squish")
  elseif e == "SE_BLINK_MON" then
    startPicKind(self:picFxFor(self:animFxBattler(false)), "blink")
  elseif e == "SE_BLINK_ENEMY_MON" then
    startPicKind(self:picFxFor(self:animFxBattler(true)), "blink")
  elseif e == "SE_MOVE_MON_HORIZONTALLY" then
    -- redraw one tile inward: player pic at hlcoord 2,5 (from 1,5),
    -- enemy pic at 11,0 (from 12,0)
    local b = self:animFxBattler(false)
    local pf = self:picFxFor(b)
    if pf then
      pf.kind, pf.hidden = nil, nil
      pf.ox = b.isPlayer and 8 or -8
      pf.oy = 0
    end
  elseif e == "SE_RESET_MON_POSITION" then
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then
      pf.kind, pf.hidden, pf.ox, pf.oy = nil, nil, 0, 0
    end
  elseif e == "SE_SHOW_MON_PIC" then
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then pf.kind, pf.hidden, pf.ox, pf.oy = nil, nil, 0, 0 end
  elseif e == "SE_SHOW_ENEMY_MON_PIC" then
    local pf = self:picFxFor(self:animFxBattler(true))
    if pf then pf.kind, pf.hidden, pf.ox, pf.oy = nil, nil, 0, 0 end
  elseif e == "SE_HIDE_MON_PIC" or e == "SE_HIDE_ATTACKER_PIC" then
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then pf.kind, pf.hidden = nil, true end
  elseif e == "SE_HIDE_ENEMY_MON_PIC" then
    local pf = self:picFxFor(self:animFxBattler(true))
    if pf then pf.kind, pf.hidden = nil, true end
  elseif e == "SE_MINIMIZE_MON" then
    -- the pic data is replaced by the tiny MinimizedMonSprite blob
    local pf = self:picFxFor(self:animFxBattler(false))
    if pf then
      pf.kind, pf.hidden = nil, nil
      pf.minimized = true
    end
  elseif e == "SE_FLASH_MON_PIC" or e == "SE_FLASH_ENEMY_MON_PIC" then
    -- ChangeMonPic reloads the mon's own pic (clears a minimize)
    local pf = self:picFxFor(self:animFxBattler(e == "SE_FLASH_ENEMY_MON_PIC"))
    if pf then pf.kind, pf.hidden, pf.minimized = nil, nil, nil end
  elseif e == "SE_TRANSFORM_MON" then
    -- AnimationTransformMon redraws the user as the opposing species
    -- (MoveEffects.TRANSFORM_EFFECT swaps the rest when it applies)
    local user = self:animFxBattler(false)
    local target = self:animFxBattler(true)
    if user and target and self.speciesSprite then
      user.sprite = self:speciesSprite(target.mon.species, user.isPlayer)
                    or user.sprite
      local pf = self:picFxFor(user)
      if pf then pf.minimized = nil end
    end
  end
  -- SE_SUBSTITUTE_MON needs no visual here: the doll is drawn while
  -- battler.substituteHP is set (MoveEffects raises it with the move)
end

-- The post-animation applying-attack feedback (PlayApplyingAttackAnimation
-- -> AnimationTypePointerTable, engine/battle/animations.asm:475-524).
-- hit.animType is wAnimationType, 1..6:
--   1 enemy damaging, no added effect   ShakeScreenVertically (b=8)
--   2 enemy damaging, added effect      fast horizontal shake, b=8
--   3 enemy non-damaging                slow horizontal shake, b=6, c=2
--   4 player damaging, no added effect  BlinkEnemyMonSprite
--   5 player damaging, added effect     fast horizontal shake, b=2
--   6 player non-damaging               slow horizontal shake, b=3, c=2
-- Types 3 and 6 are silent; the rest open with PlayApplyingAttackSound,
-- which is the damage sound hit.sfx already carries.  Only 1 and 4 were
-- implemented, so every move with an added effect blinked (or shook
-- vertically) instead of shaking sideways and every status move showed
-- nothing at all -- Bubblebeam, Confusion, Hypnosis (#354).  A hold keeps
-- the queue still until the effect finishes.
function BattleState:applyHitFx(hit)
  self.fx = self.fx or {}
  -- rows queued before animType existed carry only the blink target
  local t = hit.animType
  if not t and hit.blink then t = hit.blink.isPlayer and 1 or 4 end
  if hit.sfx then
    local Sound = require("src.core.Sound")
    -- EffectRegistry hands the row the PlayApplyingAttackSound sound WITH its
    -- wFrequencyModifier byte, so it goes through the same pitch/tempo path
    -- move sounds use (#826).  A bare string -- an older row, or a mod that
    -- built its own hit fx -- still plays unmodified.
    if type(hit.sfx) == "table" then
      Sound.playMove(self.data, hit.sfx)
    else
      Sound.play(self.data, hit.sfx)
    end
  end
  if not t then return end
  if t == 1 then
    -- PredefShakeScreenVertically b=8: the window drops by b for 3 frames
    -- then home for 3, b counting down
    local prog = {}
    for b = 8, 1, -1 do
      prog[#prog + 1] = { dy = b, frames = 3 }
      prog[#prog + 1] = { dy = 0, frames = 3 }
    end
    self.fx.shakeProg = prog
    self.waitFrames = Timing.SHAKE_VERTICAL -- the predef blocks until it settles
  elseif t == 2 then
    self.fx.shakeProg = fastShakeProg(8)
    self.waitFrames = Timing.SHAKE_HORIZ_HEAVY
  elseif t == 3 then
    self.fx.shakeProg = slowShakeProg(6, 2)
    self.waitFrames = Timing.SHAKE_HORIZ_SLOW
  elseif t == 4 then
    if hit.blink then
      -- AnimationBlinkMon: 6 iterations of hide/5 frames/show/5 frames.
      -- This is the animation for every plain damaging move the player
      -- uses, and it ran at a third of its length.
      self.fx.blink = { target = hit.blink, frames = Timing.BLINK_MON }
      self.waitFrames = Timing.BLINK_MON
    end
  elseif t == 5 then
    self.fx.shakeProg = fastShakeProg(2)
    self.waitFrames = Timing.SHAKE_HORIZ_LIGHT
  elseif t == 6 then
    self.fx.shakeProg = slowShakeProg(3, 2)
    self.waitFrames = Timing.SHAKE_HORIZ_SLOW2
  end
end

-- Primary status effects whose pokered handler ends in
-- PlayCurrentMoveAnimation2 (engine/battle/effects.asm:1448), which sets
-- wAnimationType 6 on the player's turn and 3 on the enemy's: sleep,
-- poison, confuse, disable and the primary stat-down effects.  Every other
-- primary effect goes through PlayCurrentMoveAnimation and leaves the type
-- at 0 (no applying animation): paralysis (FreezeBurnParalyzeEffect),
-- leech seed, the stat-UP effects, Splash.  Side-effect stat drops are
-- skipped too -- UpdateLoweredStatDone bails out for them because the
-- damaging move's own type 2/5 shake already played.
local SLOW_SHAKE_EFFECTS = {
  SLEEP_EFFECT = true, POISON_EFFECT = true, CONFUSION_EFFECT = true,
  DISABLE_EFFECT = true,
  ATTACK_DOWN1_EFFECT = true, DEFENSE_DOWN1_EFFECT = true,
  DEFENSE_DOWN2_EFFECT = true, SPEED_DOWN1_EFFECT = true,
  ACCURACY_DOWN1_EFFECT = true,
}

-- AnimateSendingOutMon (core.asm:6801-6838): the mon grows out of the
-- ball -- a 3-frame ball beat, 4 frames of the pic at 3/7 scale (a 3x3
-- block of its 7x7 tiles), 5 frames at 5/7 (5x5), then full size.
-- Queues a hold so the text stays up while it grows.  Runs inside a
-- queued fn (updateQueue resets nextInsert before each one).
function BattleState:startGrowIn(battler)
  self.growIn = { battler = battler, frame = 0 }
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = 12 })
end

-- SendOutMon branches on IsThisPartyMonStarterPikachu before the animation:
-- the starter gets no ball and no grow-in -- pokeyellow core.asm:1798-1819
function BattleState:starterPikachuSendOut()
  if not require("src.core.GameVersion").isYellow() then return false end
  local mon = self.player and self.player.mon
  return require("src.world.PikachuFollower")
           .isStarterPikachu(self.game.save, mon)
end

-- StarterPikachuBattleEntranceAnimation: the back pic walks in from hlcoord
-- 0,5, one column every 2 frames -- engine/battle/pikachu_entrance_anim.asm:1
function BattleState:startPikachuEntrance()
  self:slidePic("playerMon", -56, 0, 8, 2)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = 16 })
  self:actNext(function()
    self:slidePic("playerMon")
    self:waitSfxNext(self:playEntranceCry(self.player))
  end)
end

-- Player send-out tail: POOF_ANIM + AnimateSendingOutMon (core.asm:1757-1762),
-- or the starter Pikachu entrance instead (pokeyellow core.asm:1798-1819)
function BattleState:queueSendOutAnim(append)
  local pikachu = self:starterPikachuSendOut()
  if not pikachu then
    if append then
      table.insert(self.queue, { anim = "POOF_ANIM", attackerIsPlayer = false })
    else
      self:animNext("POOF_ANIM", false)
    end
  end
  local fn = function()
    self.sendingOut = false
    if pikachu then
      self:startPikachuEntrance()
    else
      self:startGrowIn(self.player)
      self:waitSfxNext(self:playEntranceCry(self.player))
    end
  end
  if append then self:act(fn) else self:actNext(fn) end
end

-- AnimateRetreatingPlayerMon (core.asm:1769-1796); the Yellow starter Pikachu
-- slides off instead (pokeyellow core.asm:1862-1866, animations.asm:1259)
function BattleState:queueRetreatAnim()
  if self:starterPikachuSendOut() then
    self:actNext(function() self:slidePic("playerMon", 0, -64, 8, 3) end)
    self:waitNext(24)
    self:actNext(function()
      -- .clearScreenArea keeps the 7x7 area blank until the swap
      -- (pokeyellow core.asm:1867-1871) (#1545)
      self.sendingOut = true
      self:slidePic("playerMon")
    end)
  else
    self:actNext(function()
      self.shrinkOut = { battler = self.player, frame = 0 }
    end)
    self:waitNext(7)
  end
end

-- Should the low-health alarm sound this frame?  pokered keys it off
-- the drawn bar color: DrawPlayerHUDAndHPBar (core.asm:1846-1875) sets
-- wLowHealthAlarm bit 7 when GetHealthBarColor says the player bar is
-- red (< 10 of 48 pixels -- the same threshold HudTiles.drawHPBar
-- tints with) and clears it when the bar isn't red or the mon fainted
-- (RemoveFaintedPlayerMon).  Winning disables it for the rest of the
-- battle (EndLowHealthAlarm sets wLowHealthAlarmDisabled, mirrored by
-- playVictoryMusic) and every other outcome tears it down in
-- end_of_battle.asm -- self.result covers those.  The damage drain
-- gates the START (the HUD redraw runs after UpdateHPBar finishes) but
-- never the stop, and healing out of the red silences it at once
-- (item_effects.asm:991-994 clears the alarm before the bar animates).
-- No alarm before the player HUD first draws (send-out), nor in the
-- safari/old-man battles, which have no player mon HUD.
function BattleState:lowHealthAlarmActive()
  local p = self.player
  if not p or self.safari or self.demo or self.result
     or self.lowHealthAlarmDisabled then return false end
  if self.showPlayerBack or (self.introSlide or 0) > 0 then return false end
  if p.fainted then return false end
  -- A siren that is ALREADY sounding follows the drawn bar, not the
  -- model: wLowHealthAlarm is a latch DrawPlayerHUDAndHPBar only revisits
  -- once UpdateHPBar2 has finished animating (core.asm:4727-4729 /
  -- core.asm:4845-4847 both drain first, then jp DrawHUDsAndHPBars), and
  -- a KO clears it in RemoveFaintedPlayerMon (core.asm:1011-1016), i.e.
  -- after the bar has drained empty.  applyDamage takes the HP off the
  -- model while the turn is still being queued, so keying a running alarm
  -- off mon.hp cut it dead for the whole "used X!" line + move animation
  -- + drain window (#293).  max() keeps a heal out of the red silencing
  -- it on the spot, the way item_effects.asm does.
  local hp = p.mon.hp
  if self.lowHealthAlarmOn then
    hp = math.max(hp, shownHP(p))
  elseif p.shownHP and p.shownHP > hp then
    return false -- drain running: the HUD redraw has not happened yet
  end
  if hp <= 0 then return false end
  local px = math.max(1, math.floor(hp * 48 / math.max(1, p.mon.stats.hp)))
  return px < 10
end

-- advance a {dx/dy, frames} step program; returns the current step
local function stepProgram(prog)
  local head = prog[1]
  while head and head.frames <= 0 do
    table.remove(prog, 1)
    head = prog[1]
  end
  if head then head.frames = head.frames - 1 end
  return head
end

-- Trainer-pic slides.  SlideTrainerPicOffScreen (core.asm:1235) walks a
-- trainer pic off its own screen edge one tile every 2 frames (9 tiles left
-- for the player back pic, 8 tiles right for the foe), and
-- _ScrollTrainerPicAfterBattle (engine/battle/scroll_draw_trainer_pic.asm)
-- brings the beaten foe back in from the right one column every 4 frames.
-- picOff holds the live programs by slot -- "foe" = the enemy trainer pic,
-- "back" = the player's back pic, "playerMon" = the player's mon back pic --
-- as a screen-pixel x offset stepped toward `to`; updateFx advances them,
-- drawPicsLayer adds them, and the queue rows that start them park a
-- { wait } of the matching length.  Call with no target to clear
-- a slot (#317, #282).
function BattleState:slidePic(slot, from, to, step, hold)
  self.picOff = self.picOff or {}
  if to == nil then
    self.picOff[slot] = nil
    return
  end
  self.picOff[slot] = { x = from or 0, to = to, step = step or 4, hold = hold }
end

-- the live x offset for a pic slot, 0 when nothing is sliding
function BattleState:picOffset(slot)
  local p = self.picOff and self.picOff[slot]
  return p and p.x or 0
end

function BattleState:updateFx()
  if self.introSlide and self.introSlide > 0 then
    self.introSlide = self.introSlide - 1
  end
  -- step each live trainer-pic slide toward its target; a landed program
  -- holds its offset (the after-battle scroll-in rests two tiles right of
  -- the battle slot) until its owner clears the slot
  if self.picOff then
    for _, p in pairs(self.picOff) do
      local move = true
      if p.hold then
        p.held = (p.held or 0) + 1
        move = p.held >= p.hold
        if move then p.held = 0 end
      end
      if move then
        if p.x < p.to then
          p.x = math.min(p.to, p.x + p.step)
        elseif p.x > p.to then
          p.x = math.max(p.to, p.x - p.step)
        end
      end
    end
  end
  local fx = self.fx
  if fx then
    if fx.shake and fx.shake > 0 then fx.shake = fx.shake - 1 end
    if fx.flash and fx.flash > 0 then fx.flash = fx.flash - 1 end
    if fx.blink and fx.blink.frames > 0 then
      fx.blink.frames = fx.blink.frames - 1
    end
    if fx.faint and fx.faint.frames > 0 then
      fx.faint.frames = fx.faint.frames - 1
    end
    -- SE-driven screen offsets (window/SCX shakes)
    fx.shakeX, fx.shakeY = 0, 0
    if fx.shakeProg then
      local st = stepProgram(fx.shakeProg)
      if st then
        fx.shakeX, fx.shakeY = st.dx or 0, st.dy or 0
      else
        fx.shakeProg = nil
      end
    end
    fx.hudShakeX = 0
    if fx.hudShakeProg then
      local st = stepProgram(fx.hudShakeProg)
      if st then
        fx.hudShakeX = st.dx or 0
      else
        fx.hudShakeProg = nil
      end
    end
    -- BGP flash sequences
    local seq = fx.bgpSeq
    if seq then
      seq.left = seq.left - 1
      if seq.left <= 0 then
        seq.idx = seq.idx + 1
        local st = seq.steps[seq.idx]
        if st then
          seq.left = st.frames
        else
          fx.bgpSeq = nil -- restore: activeBgp falls back to fx.bgp
        end
      end
    end
    if fx.wavy then
      fx.wavy.left = fx.wavy.left - 1
      fx.wavy.phase = fx.wavy.phase + 1
      if fx.wavy.left <= 0 then fx.wavy = nil end
    end
  end
  -- SE-driven pic effects: advance the per-battler programs and apply
  -- their end states (timings in the SE_* handlers' comments)
  if self.picFx then
    for b, pf in pairs(self.picFx) do
      if pf.kind then
        pf.t = (pf.t or 0) + 1
        local k, t = pf.kind, pf.t
        if k == "slideOff" and t >= 24 then
          pf.kind, pf.hidden = nil, true
        elseif k == "slideHalf" and t >= 19 then
          pf.kind = nil
          pf.ox = b.isPlayer and -32 or 32 -- the pic stays half off
        elseif k == "slideUp" and t >= 14 then
          pf.kind = nil -- a full cyclic wrap lands back on the pic
        elseif k == "slideDown" and t >= 21 then
          pf.kind, pf.hidden = nil, true
        elseif k == "slideDownHide" and t >= 19 then
          pf.kind, pf.hidden = nil, true
        elseif k == "shakeBF" and t >= 96 then
          pf.kind, pf.hidden = nil, true -- the loop ends on a cleared pic
        elseif k == "bounce" and t >= 105 then
          pf.kind = nil -- AnimationShowMonPic after the last bounce
        elseif k == "squish" and t >= 24 then
          pf.kind, pf.hidden = nil, true
        elseif k == "blink" and t >= 60 then
          pf.kind = nil -- ends shown
        end
      end
    end
  end
  -- The Silph Scope unveil (MarowakAnim; queueScopeReveal parks a wait row
  -- of GHOST_REVEAL_FRAMES over it): the ghost flashes, fades out, the pic
  -- and the nick swap back the way LoadEnemyMonData restores them, and the
  -- real mon fades in (#492).
  local gr = self.ghostReveal
  if gr and self.enemy then
    gr.t = gr.t + 1
    local pf = self:picFxFor(self.enemy)
    local flashEnd = BattleState.GHOST_FLASH_FRAMES
    local outEnd = flashEnd + BattleState.GHOST_FADE_OUT_FRAMES
    if gr.t <= flashEnd then
      pf.fade = (math.floor((gr.t - 1) / 10) % 2 == 1) and 0.5 or 1
    elseif gr.t <= outEnd then
      pf.fade = 1 - math.ceil((gr.t - flashEnd) / 10) / 3
    else
      if not gr.swapped then
        gr.swapped = true
        local real = self.ghostReal
        if real then
          self.enemy.name = real.name or self.enemy.name
          self.enemy.sprite = real.sprite or self.enemy.sprite
        end
      end
      pf.fade = math.min(1, math.ceil((gr.t - outEnd) / 10) / 4)
    end
    if gr.t >= BattleState.GHOST_REVEAL_FRAMES then
      self.ghostReveal, self.scopeReveal, pf.fade = nil, nil, nil
    end
  end
  -- the send-out grow-in (AnimateSendingOutMon): 3+4+5 frames, then
  -- the pic draws at full size again
  if self.growIn then
    self.growIn.frame = self.growIn.frame + 1
    if self.growIn.frame >= 12 then self.growIn = nil end
  end
  -- the retreat shrink (AnimateRetreatingPlayerMon): 4+3 frames, then the
  -- 7x7 area holds cleared (scale 0) until the swap replaces the battler
  if self.shrinkOut then
    self.shrinkOut.frame = self.shrinkOut.frame + 1
    if self.shrinkOut.battler ~= self.player then self.shrinkOut = nil end
  end
  -- low-HP alarm (audio/low_health_alarm.asm): the two-tone siren
  -- loops while the player's bar is red; see lowHealthAlarmActive
  local Sound = require("src.core.Sound")
  -- self.lowHealthAlarmOn mirrors wLowHealthAlarm's bit 7: a latch read
  -- back inside lowHealthAlarmActive (the RHS sees last frame's value)
  -- so a sounding siren rides out the next hit's HP drain instead of
  -- dropping out mid-announcement (#293)
  self.lowHealthAlarmOn = self:lowHealthAlarmActive()
  -- battle.low_health_alarm: on/off toggle for the siren loop, ctx.on
  -- mirrors self.lowHealthAlarmOn. Vanilla just starts/stops the loop
  -- each frame; a mod can wrap this to reshape the toggle (e.g. force
  -- ctx.on false after some budget) before letting vanilla act on it.
  if Runtime.wantsHook("battle.low_health_alarm") then
    Runtime.call("battle.low_health_alarm", function(ctx)
      if ctx.on then
        Sound.startLoop(ctx.battle.data, "Low_Health_Alarm")
      else
        Sound.stopLoop("Low_Health_Alarm")
      end
    end, { on = self.lowHealthAlarmOn, battle = self })
  else
    if self.lowHealthAlarmOn then
      Sound.startLoop(self.data, "Low_Health_Alarm")
    else
      Sound.stopLoop("Low_Health_Alarm")
    end
  end
end

-- ---------------------------------------------------------------------
-- move execution pipeline
-- ---------------------------------------------------------------------

-- Mirror DrawHUDsAndHPBars: reveal mon.status on the HUD only after the
-- current action's queued anim/text have played (PoisonEffect sets the
-- bit before PlayCurrentMoveAnimation2 + PrintText, but the HUD redraw
-- waits until after Execute*Move returns).
function BattleState:syncShownStatus()
  for _, b in ipairs({ self.player, self.enemy }) do
    if b then b.shownStatus = b.mon.status end
  end
end

function BattleState:executeAction(user, target, action)
  -- MainInBattleLoop reads wEscapedFromBattle right after Execute*Move and
  -- rets (core.asm:417-421, 456-460): a Teleport/Roar/Whirlwind escape ends
  -- the turn where it lands and the second mover never moves.  self.result
  -- is only ever set once the battle is over (run/win/lose/caught), and the
  -- faint cases are already covered by the HP guard below (#441)
  if self.result then return end
  if user.mon.hp <= 0 or target.mon.hp <= 0 then return end
  if not action then return end

  local function run()
    -- ghost battles: the ghost never attacks; its whole turn is the
    -- GetOutText (ExecuteEnemyMove -> PrintGhostText, core.asm:5462-5463)
    if self.ghost and not user.isPlayer then
      self:sayNext(self.data.text._GetOutText or Strings("GHOST: Get out...\nGet out..."))
      return
    end

    -- refresh the held-in-place mirror before the status checks (see
    -- lockedAction): the victim is held exactly while the opponent's
    -- trapping bit is set -- including a counter sitting at 0 until the
    -- end-of-turn CheckNumAttacksLeft clear
    user.boundTurns = target.trappingTurns
                      and math.max(1, target.trappingTurns) or nil

    -- wPlayerSelectedMove / wEnemySelectedMove as the status gauntlet
    -- reads it: the locked specials keep continuing the move they
    -- started, so they carry a move id too.  Resolved once here and
    -- handed to every statusInterrupt below, which is where
    -- .TriedToUseDisabledMoveCheck lives (#860).
    local selectedId = action.id
                       or (action.special == "trapping" and user.trapMove)
                       or (action.special == "bide" and "BIDE")
                       or nil

    -- trainer class AI actions (engine/battle/trainer_ai.asm)
    if action.special == "aiItem" then
      self.aiUses = (self.aiUses or 1) - 1
      -- useItem's messages arrive final: its item line prints the raw
      -- nickname on purpose (no "Enemy " in AIPrintItemUseText), so the
      -- prefix splice must not touch them.
      for _, m in ipairs(TrainerAI.useItem(self, action.item)) do
        self:sayNext(m)
      end
      self:drainNext()
      require("src.core.Sound").play(self.data, "Heal_Ailment")
      return
    end
    if action.special == "aiSwitch" then
      self.aiUses = (self.aiUses or 1) - 1
      local previous = self.enemy
      local oldName = self.enemy.name
      self.enemyIndex = action.index
      self.enemy = makeBattler(self.data, self.enemyParty[action.index], false)
      -- EnemySendOutFirstMon (core.asm:1314-1315): clears player's trap
      clearTrapping(self.player)
      self:syncSides()
      Runtime.emit("battle.battler_switched", {
        battle = self, side = self.sides[2], battler = self.enemy,
        previous = previous,
      })
      self.aiUses = self:aiUsesFor()
      markSeen(self.game, self.enemy.mon.species)
      self:sayNext(self:romText("_AIBattleWithdrawText", "%s with-\ndrew %s!",
        self.trainer.name, oldName))
      -- EnemySendOut falls into EnemySendOutFirstMon: TrainerSentOutText,
      -- then AnimateSendingOutMon and PlayCry (core.asm:1276-1434)
      self.enemySendingOut = true
      self:sayNextAuto(self:romText("_TrainerSentOutText", "%s sent\nout %s!",
        self.trainer.name, self.enemy.name))
      self:actNext(function()
        self.enemySendingOut = false
        self:startGrowIn(self.enemy)
        self:actNext(function()
          self:waitSfxNext(self:playEntranceCry(self.enemy))
        end)
      end)
      return
    end

    -- special locked actions.  All of them still run the status gauntlet:
    -- CheckPlayerStatusConditions (core.asm:3328-3583) evaluates sleep ->
    -- freeze -> held-in-place -> flinch -> recharge -> disable tick ->
    -- confusion -> paralysis BEFORE the bide/thrash/trapping handling.
    if action.special == "recharge" then
      -- only reaching .HyperBeamCheck consumes the flag (core.asm:3384-
      -- 3392): sleep/freeze/held/flinch keep the mon recharging next turn
      if self:preRechargeChecks(user, target) then return end
      user.mustRecharge = nil
      self:sayNext(self:romText("_MustRechargeText", "%s\nmust recharge!", displayName(user)))
      return
    end
    if action.special == "bound" then
      if not target.trappingTurns then
        -- the trap ended earlier this turn: the CANNOT_MOVE selection is
        -- simply lost (ExecutePlayerMove returns immediately on $ff)
        return
      end
      -- sleep/freeze take precedence over the held-in-place message
      if self:statusInterrupt(user, target) then return end
      return
    end
    if action.special == "trapping" then
      if self:statusInterrupt(user, target, selectedId) then return end
      self:continueTrapping(user, target)
      return
    end
    if action.special == "bide" then
      if self:statusInterrupt(user, target, selectedId) then return end
      self:continueBide(user, target)
      return
    end

    if self:statusInterrupt(user, target, selectedId) then return end
    self:performMove(user, target, action, false)
  end
  run()
  -- after announce/anim/effect text (pokered DrawHUDsAndHPBars)
  self:actNext(function() self:syncShownStatus() end)
  -- MainInBattleLoop calls HandlePoisonBurnLeechSeed right after each
  -- Execute*Move (core.asm:426-464): the acting side's poison/burn/leech
  -- seed ticks before the slower mon acts, not at end of round
  if residualAfterMove(self) then
    self:actNext(function() self:residualFor(user, target) end)
  end
end

-- Sleep / confusion onomatopoeia from Check*StatusConditions
-- (core.asm): side-specific SLP_*/CONF_* anims, not the Rest/Amnesia
-- move rows.  Player sleep plays the anim before FastAsleepText;
-- enemy sleep and both confusion sides print the text first.
function BattleState:statusOnomatopoeia(user, kind)
  local isPlayer = user.isPlayer
  local anim
  if kind == "sleep" then
    anim = isPlayer and "SLP_PLAYER_ANIM" or "SLP_ANIM"
  else
    anim = isPlayer and "CONF_PLAYER_ANIM" or "CONF_ANIM"
  end
  local text = kind == "sleep"
    and self:romText("_FastAsleepText", "%s\nis fast asleep!", displayName(user))
    or self:romText("_IsConfusedText", "%s\nis confused!", displayName(user))
  if kind == "sleep" and isPlayer then
    self:animNext(anim, isPlayer)
    self:sayNext(text)
  else
    self:sayNext(text)
    self:animNext(anim, isPlayer)
  end
end

-- Queue status text (+ sleep/confusion FX when the line matches).
-- Wake / snap-out / flinch / etc. stay text-only.
function BattleState:sayStatusMsg(user, msg)
  local text = prefixEnemy(msg, user)
  if msg:find("is fast asleep!", 1, true) then
    self:statusOnomatopoeia(user, "sleep")
  elseif msg:find("is confused!", 1, true) then
    self:statusOnomatopoeia(user, "confused")
  else
    self:sayNext(text)
  end
end

-- The pre-recharge slice of CheckPlayerStatusConditions (core.asm:
-- 3328-3382): sleep -> freeze -> held-in-place -> flinch, each losing
-- the turn WITHOUT consuming the recharge flag.  The disable/confusion/
-- paralysis ticks come after the recharge consume in the asm, so they
-- must not run on a recharge turn.  Mirrors Status.beforeMove's early
-- checks (kept there for normal moves).
function BattleState:preRechargeChecks(user, target)
  if user.skipMove then -- Haze forfeit (selected move = CANNOT_MOVE)
    user.skipMove = nil
    return true
  end
  local mon = user.mon
  if mon.status == "SLP" then
    user.sleepTurns = (user.sleepTurns or 1) - 1
    if user.sleepTurns <= 0 then
      mon.status = nil
      self:sayNext(self:romText("_WokeUpText", "%s\nwoke up!", displayName(user)))
    else
      self:statusOnomatopoeia(user, "sleep")
    end
    return true
  end
  if mon.status == "FRZ" then
    self:sayNext(self:romText("_IsFrozenText", "%s\nis frozen solid!", displayName(user)))
    return true
  end
  if target.trappingTurns then
    self:sayNext(self:romText("_CantMoveText", "%s\ncan't move!", displayName(user)))
    return true
  end
  if user.flinched then
    -- reachable: the turn-start flinch reset is skipped while the
    -- player recharges, so the flinch eats the recharge turn and the
    -- flag survives (the Hyper Beam flinch glitch)
    user.flinched = false
    self:sayNext(self:romText("_FlinchedText", "%s\nflinched!", displayName(user)))
    return true
  end
  return false
end

-- Runs Status.beforeMove plus the shared interruption bookkeeping;
-- returns true when the user's action is interrupted.
function BattleState:statusInterrupt(user, target, selectedId)
  local canMove, msgs, selfHit = Status.beforeMove(user, self.rng, self, selectedId)
  for _, m in ipairs(msgs) do self:sayStatusMsg(user, m) end
  if selfHit then
    -- confusion self-hit (core.asm:3428-3434): clears everything in
    -- status1 except CONFUSED, then HandleSelfConfusionDamage deals a
    -- 40-power typeless hit against the mon's own defense -- with the
    -- OPPONENT's Reflect still applying (the screen check keeps
    -- reading the opponent's battle status)
    local dmg = self:computeDamage(user, user,
                                   { id = "CONFUSED", power = 40, type = "NORMAL", accuracy = 100 },
                                   { rng = self.rng, forceCrit = false, typeless = true,
                                     screens = target })
    self:sayNext(self:romText("_HurtItselfText", "It hurt itself in\nits confusion!"))
    -- HandleSelfConfusionDamage (core.asm:3706-3714, enemy side :5807-5811)
    self:animNext("POUND", not user.isPlayer)
    self:clearVolatiles(user, true)
    self:applyDamage(user, dmg)
    if user.mon.hp <= 0 then self:onFaint(user) end
    return true
  end
  if not canMove then
    -- full paralysis (core.asm:3459-3464) clears bide/thrash/charge/
    -- trapping; sleep, freeze, flinch and held-in-place leave every
    -- volatile in place (a sleeping wrapper keeps its victim held)
    if user.mon.status == "PAR" and msgs[#msgs]
       and msgs[#msgs]:find("fully paralyzed", 1, true) then
      self:clearVolatiles(user, false)
    end
    return true
  end
  return false
end

-- The status1 volatile clears shared by full paralysis and the
-- confusion self-hit.  selfHit additionally clears INVULNERABLE and
-- FLINCHED (status1 &= CONFUSED); full paralysis does NOT touch
-- INVULNERABLE -- the famous Fly/Dig invulnerability glitch.
function BattleState:clearVolatiles(user, selfHit)
  user.bideTurns, user.bideDamage = nil, nil
  user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
  user.charging, user.chargeReady = nil, nil
  user.trappingTurns = nil -- the opponent is freed via the live mirror
  if selfHit then
    user.invulnerable = nil
    user.flinched = false
  end
end

-- performMove runs a move (possibly via Metronome/Mirror Move recursion).
-- Decomposed into a staged pipeline over the merged move_effects record:
-- announcement -> callsMove -> charge -> perform -> primary run -> the
-- damaging pipeline (EffectRegistry.runDamaging).

-- Gen 1 status/stat primary effects call PlayCurrentMoveAnimation only
-- after they land; these failure texts print with no animation.  Failures
-- whose text is an ordinary sentence rather than one of the shared fail
-- lines set msgs.failed instead of relying on this sniffer -- Substitute's
-- two failure lines name the move, not the failure (#644).
local function primaryEffectFailed(msgs)
  if not msgs or #msgs == 0 then return true end
  if msgs.failed then return true end
  -- the extracted lines keep the ROM's own trailing blank ("But, it
  -- failed! "), so match with it trimmed or a refused status animates
  local m = msgs[1]:gsub("%s+$", "")
  if m == "But, it failed!" or m == "Nothing happened!" then return true end
  if m:find("didn't affect", 1, true) then return true end
  if m:find("is unaffected", 1, true) then return true end
  if m:find("protected by MIST", 1, true) then return true end
  if m:find("Already", 1, true) then return true end
  return false
end

function BattleState:performMove(user, target, moveInst, isCalled)
  local move = self:moveDef(moveInst)
  if not move then
    Logger.warn("unknown move instance %s", tostring(moveInst.id))
    return
  end
  local record = self:effectRecord(move.effect)

  -- charge release?
  local releasing = user.charging == moveInst and user.chargeReady
  if releasing then
    user.charging, user.chargeReady, user.invulnerable = nil, nil, nil
  end

  -- PP: not for continuations, struggle, called moves, or (under
  -- gen1_faithful) wild/trainer enemies -- pokered DecrementPP only ever
  -- mutates wBattleMonPP / party PP (engine/battle/decrement_pp.asm).
  -- That rule doesn't apply in a link battle: "the enemy" there is a real
  -- human peer independently tracking their own PP the normal way, not an
  -- AI Gen 1 never bothered to decrement -- applying it made each side
  -- silently skip decrementing the OTHER side's PP for the move it just
  -- used, so both simulations' party state diverged by exactly 1 PP on
  -- the very first move either side made, failing the lockstep hash
  -- check turn 1 of literally every link battle.
  local isContinuation = releasing
      or (user.thrashTurns and user.thrashTurns > 0 and moveInst == user.thrashMove)
      or moveInst == user.rageMove
  local enemyUnlimited = not user.isPlayer and self.kind ~= "link"
      and self.ruleset and self.ruleset.enemyUnlimitedPP
  if not isContinuation and not moveInst.struggle and not isCalled
      and not enemyUnlimited then
    moveInst.pp = math.max(0, moveInst.pp - 1)
  end

  self.moveAnimRow = nil
  local thrashing = user.thrashTurns and moveInst == user.thrashMove
    and user.thrashAnnounced or false
  if thrashing then
    -- .ThrashingAboutCheck (core.asm:3531-3552)
    self:sayNextAuto(self:romText("_ThrashingAboutText", "%s's\nthrashing about!",
                                  displayName(user)))
    user.thrashTurns = user.thrashTurns - 1
    if user.thrashTurns <= 0 then
      user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
      if not user.confusedTurns then user.confusedTurns = self.rng(2, 5) end
    end
  else
    self:sayNextAuto(self:romText("_ItemUseText001", "%s\nused %s!", displayName(user), move.name))
  end
  -- PlayCurrentMoveAnimation follows the announcement; Mimic (announceAnim
  -- = false) queues it from applyMimic after a successful copy
  if not (record and record.announceAnim == false) then
    self.nextInsert = (self.nextInsert or 0) + 1
    -- ld a, THRASH / ld [wPlayerMoveNum] (core.asm:3534-3535, :5909-5910) #1577
    self.moveAnimRow = { anim = thrashing and "THRASH" or move.id,
                         attackerIsPlayer = user.isPlayer }
    table.insert(self.queue, self.nextInsert, self.moveAnimRow)
  end
  Runtime.emit("battle.move_used", {
    battle = self, user = user, target = target, move = move,
    isCalled = isCalled or false,
  })

  local ctx = EffectRegistry.makeCtx(self, user, target, move, moveInst, isCalled)
  -- .ThrashingAboutCheck jumps past JumpMoveEffect into PlayerCalcMoveDamage
  -- (core.asm:3540), so SpecialEffectsCont never re-runs on a locked turn
  ctx.thrashing = thrashing

  -- Metronome / Mirror Move re-entry; a nil pick means the record
  -- already said its failure text
  if record and record.callsMove then
    local pick = record.callsMove(ctx)
    -- Mirror Move never plays its own anim (MetronomePickMove does;
    -- MirrorMoveCopyMove only reloads the copied move or prints fail)
    if move.id == "MIRROR_MOVE" or not pick then
      self:cancelMoveAnim()
    end
    if pick then
      self:performMove(user, target, { id = pick, pp = 1 }, true)
    end
    return
  end
  user.lastMove = move.id

  -- charge moves: first turn just charges; the text comes from the move
  -- record (chargeText) and the invulnerability from semiInvulnerable,
  -- falling back to the id tables (Fly AND Dig go semi-invulnerable:
  -- ChargeEffect sets INVULNERABLE for both)
  local chargeRequired = record and record.charge ~= nil and not releasing
  if chargeRequired and Runtime.wantsHook("battle.charge_required") then
    local required = Runtime.call("battle.charge_required", function(c)
      return c.charge
    end, {
      battle = self, user = user, target = target, move = move,
      charge = true, isCalled = isCalled or false,
    })
    chargeRequired = required ~= false
  end
  if chargeRequired then
    self:cancelMoveAnim()
    user.charging = moveInst
    user.chargeReady = true
    local invulnerable = move.semiInvulnerable
    if invulnerable == nil then
      invulnerable = record.charge.invulnerable or move.id == "DIG"
    end
    if invulnerable then
      user.invulnerable = true
    end
    local chargeAnim = record.charge.anim
    if move.id == "DIG" then
      chargeAnim = "SLIDE_DOWN_ANIM"
    elseif record.charge.enemyAnim and not user.isPlayer then
      chargeAnim = record.charge.enemyAnim
    end
    if chargeAnim then
      self:animNext(chargeAnim, user.isPlayer)
    end
    local chargeText = move.chargeText or CHARGE_TEXT[move.id]
                       or Strings.source("%s\nis charging up!")
    -- the template is a source string (a move record may supply its own),
    -- so translate it here rather than where it was declared
    self:sayNext(Strings(chargeText, displayName(user)))
    return
  end

  -- fully custom resolution (Bide, Roar/Teleport, Mimic)
  if record and record.perform then
    record.perform(ctx)
    return
  end

  -- pure status moves
  if move.power == 0 and record and record.kind == "primary" and record.run then
    -- accuracy-checked status effects run MoveHitTest, which has no
    -- 100%-accuracy early-out (even Thunder Wave misses on the 255
    -- roll) and misses outright against a mid-Fly/Dig target; the
    -- never-miss paths (X ACCURACY) live inside Damage.accuracyRoll
    if record.accuracyChecked
       and (target.invulnerable
            or not self:accuracyRoll(move, user, target)) then
      -- SleepEffect/PoisonEffect/... call PlayCurrentMoveAnimation only
      -- after the effect lands; a miss skips it
      self:cancelMoveAnim()
      self:sayNext(self:romText("_AttackMissedText", "%s's\nattack missed!", displayName(user)))
      return
    end
    local msgs = record.run(ctx)
    -- Gen 1 status/stat effects animate only when they take effect
    -- (AlreadyAsleep / NothingHappened / ButItFailed print with no anim)
    if primaryEffectFailed(msgs) then
      self:cancelMoveAnim()
    elseif SLOW_SHAKE_EFFECTS[move.effect] and self.moveAnimRow then
      self.moveAnimRow.hit = { animType = user.isPlayer and 6 or 3 }
    end
    for _, m in ipairs(msgs) do
      self:sayNext(m)
    end
    self:drainNext() -- REST/RECOVER/SOFTBOILED move the user's bar
    return
  end
  if move.power == 0 and not (record and record.kind == "full") then
    MoveEffects.warnUnknown(move.effect)
    self:cancelMoveAnim()
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end

  -- damaging pipeline, driven by the record's stage callbacks
  EffectRegistry.runDamaging(self, ctx, record)
end

function BattleState:continueTrapping(user, target)
  self:sayNext(self:romText("_AttackContinuesText", "%s's\nattack continues!", displayName(user)))
  -- .MultiturnMoveCheck (core.asm:3554-3566) prints AttackContinuesText
  -- then jumps to GetPlayerAnimationType, so the trapping move's full
  -- animation replays each locked turn (same damage, animation shown).
  -- Mirror performMove's anim row (BattleState.lua ~1307), gated on the
  -- OPTIONS animation toggle.
  if user.trapMove and self:animationsOn() then
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert,
                 { anim = user.trapMove, attackerIsPlayer = user.isPlayer })
  end
  -- the counter can sit at 0 until the END of the turn: the trapping
  -- bit is only cleared by CheckNumAttacksLeft (core.asm:439/467)
  -- after BOTH battlers acted, so a slower victim is still held
  -- through the attacker's final hit (endOfTurn nils it)
  user.trappingTurns = user.trappingTurns - 1
  self:applyDamage(target, user.trapDamage or 1)
  if target.mon.hp <= 0 then self:onFaint(target) end
end

function BattleState:continueBide(user, target)
  user.bideTurns = user.bideTurns - 1
  if user.bideTurns > 0 then
    self:sayNext(Strings("%s\nis storing energy!", displayName(user)))
    return
  end
  self:sayNext(self:romText("_UnleashedEnergyText", "%s\nunleashed energy!", displayName(user)))
  local dmg = (user.bideDamage or 0) * 2
  user.bideTurns, user.bideDamage = nil, nil
  if dmg <= 0 then
    self:cancelMoveAnim()
    self:sayNext(self:romText("_ButItFailedText", "But, it failed!"))
    return
  end
  -- .UnleashEnergy (core.asm:3501-3529) re-points wPlayerMoveNum at BIDE
  -- and rejoins HandleIfPlayerMoveMissed, so BIDE's own animation plays
  -- here, after UnleashedEnergyText and before the damage (#375)
  self:animNext("BIDE", user.isPlayer)
  self:applyDamage(target, dmg)
  if target.mon.hp <= 0 then self:onFaint(target) end
end

function BattleState:selfDestruct(user)
  user.mon.hp = 0
  self:onFaint(user)
end

-- Applies damage honoring Substitute, Bide storage and Rage; returns the
-- amount that counts as dealt (for recoil/drain).
function BattleState:applyDamage(target, dmg)
  if target.substituteHP then
    target.substituteHP = target.substituteHP - dmg
    if target.substituteHP <= 0 then
      target.substituteHP = nil
      self:sayNext(self:romText("_SubstituteBrokeText", "%s's\nSUBSTITUTE broke!", displayName(target)))
    else
      self:sayNext(self:romText("_SubstituteTookDamageText", "The SUBSTITUTE\ntook damage for\n%s!", displayName(target)))
    end
    return dmg
  end
  local dealt = math.min(dmg, target.mon.hp)
  target.mon.hp = target.mon.hp - dealt
  if dealt > 0 then self:drainNext(target, target.mon.hp) end -- animate the bar down
  if target.bideTurns then
    target.bideDamage = (target.bideDamage or 0) + dealt
  end
  if target.rageMove and dealt > 0 then
    target.stages.attack = math.min(6, (target.stages.attack or 0) + 1)
    self:sayNext(self:romText("_BuildingRageText", "%s's\nRAGE is building!", displayName(target)))
  end
  return dealt
end

-- ---------------------------------------------------------------------
-- fainting / exp / party
-- ---------------------------------------------------------------------

function BattleState:onFaint(battler)
  if battler.faintQueued then return end
  battler.faintQueued = true
  if battler.isPlayer and self.participants then
    self.participants[battler.mon] = nil
  end
  Runtime.emit("battle.fainted", { battle = self, battler = battler })
  if battler.isPlayer then
    -- HandlePlayerMonFainted (core.asm:1070-1085): the companion loses
    -- happiness on its own faint; an enemy 30+ levels above it makes
    -- that the CARELESSTRAINER hit instead
    local enemyLevel = self.enemy and self.enemy.mon
                       and self.enemy.mon.level or 0
    local reason = (enemyLevel - (battler.mon.level or 0)) >= 30
                   and "CARELESSTRAINER" or "FAINTED"
    require("src.world.PikachuFollower")
      .modifyHappiness(self.game.save, reason, battler.mon)
  end
  -- the faint slide + cry ride the queue (after the move animation and
  -- the HP-bar drain, pokered's order); the slide finishes before the
  -- faint text via a queued hold
  self:actNext(function()
    battler.fainted = true
    local Sound = require("src.core.Sound")
    if battler.isPlayer then
      -- RemoveFaintedPlayerMon: the species cry (core.asm:1040-1042),
      -- PikachuCry4 on Yellow (engine/battle/core.asm:1058)
      self.faintCry = Sound.playCry(self.data, battler.mon.species, 4)
    elseif self.kind ~= "wild" then
      -- FaintEnemyPokemon (core.asm:732-771): the enemy faint plays no
      -- species cry; trainer battles get SFX_FAINT_FALL, then SFX_FAINT_THUD
      -- once it finishes (wild battles skip straight to the victory music)
      Sound.play(self.data, "Faint_Fall")
    end
    self.fx = self.fx or {}
    -- SlideDownFaintedMonPic: PIC_HEIGHT (7) slide steps, each closing with
    -- DelayFrames 2 (core.asm:1186-1222).  The port held this one twice as
    -- long as hardware.
    self.fx.faint = { battler = battler, frames = Timing.FAINT_SLIDE }
  end)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { wait = Timing.FAINT_SLIDE })
  if battler.isPlayer then
    -- RemoveFaintedPlayerMon ends `call PlayCry / jp PrintText`, and PlayCry
    -- is `jp WaitForSoundToFinish`, so "X fainted!" waits out the cry
    self:waitSfxNext(function() return self.faintCry end)
  end
  if not battler.isPlayer and self.kind ~= "wild" then
    -- FaintEnemyPokemon's SFX_FAINT_THUD lands as the slide does (after
    -- Faint_Fall, before EnemyMonFaintedText)
    self:actNext(function()
      require("src.core.Sound").play(self.data, "Faint_Thud")
    end)
  end
  if not battler.isPlayer and self.kind == "wild" then
    -- FaintEnemyPokemon .wild_win (core.asm:792-795): beating a wild
    -- mon calls EndLowHealthAlarm and starts MUSIC_DEFEATED_WILD_MON
    -- as the slide lands, BEFORE EnemyMonFaintedText and the exp text;
    -- trainer battles keep the battle theme until TrainerBattleVictory.
    -- (Starting it even when the player mon dropped too matches the
    -- acknowledged core.asm:797-798 bug.)
    self:actNext(function() self:playVictoryMusic() end)
  end
  -- _EnemyMonFaintedText already carries its own "Enemy" wording, so this
  -- passes the raw name -- displayName's separate Strings("Enemy %s", ...)
  -- would double it up
  self:sayNext(battler.isPlayer
    and self:romText("_PlayerMonFaintedText", "%s\nfainted!", battler.name)
    or self:romText("_EnemyMonFaintedText", "Enemy %s\nfainted!", battler.name))
  if battler.isPlayer then
    self:act(function() self:playerMonFainted() end)
  else
    self:act(function() self:enemyMonFainted() end)
  end
end

-- Exp for the defeated enemy, shared by the faint path (enemyMonFainted)
-- and, when a mod's battle.catch_exp hook says so, the catch path
-- (storeCaughtMon).
function BattleState:awardExp()
  -- exp is split among the mons that fought this enemy
  -- (engine/battle/experience.asm); traded mons earn x1.5; each
  -- participant gets the full stat exp
  -- a mon that fainted mid-fight has had its gain-exp flag cleared
  -- (RemoveFaintedPlayerMon), so it drops out of the divisor and only
  -- the surviving participants are counted and paid
  local participants, alive = 0, {}
  local playerParty = self:playerPartyView()
  for _, mon in ipairs(playerParty) do
    if self.participants and self.participants[mon] then
      participants = participants + 1
      if mon.hp > 0 then table.insert(alive, mon) end
    end
  end
  if participants == 0 and self.player.mon.hp > 0 then
    participants, alive = 1, { self.player.mon }
  end
  local function applyShare(mon, split, announce)
    local playerId = self.game.save.player and self.game.save.player.id
    -- GainExperience (engine/battle/experience.asm:69-88) compares the
    -- stored MON_OTID against wPlayerID every award; no persistent flag
    -- mon.traded covers otId-less mons (repairTradedOtIds, old link peers) #1488
    local traded = playerId ~= nil and ((mon.otId ~= nil and mon.otId ~= playerId)
      or (mon.otId == nil and mon.traded == true))
    local levels, gained = Experience.apply(self.data, mon, self.enemy.def,
                                            self.enemy.mon.level, self.kind == "trainer",
                                            split, traded)
    -- Track level-ups for EvolveAfterBattle (OverworldState:afterBattle ->
    -- Evolution.checkParty).  B-cancel leaves the mon at/above threshold;
    -- without this gate it re-triggers after every later fight (#213).
    if #levels > 0 then
      self.leveledUp = self.leveledUp or {}
      self.leveledUp[mon] = true
    end
    Runtime.emit("battle.exp_gained", {
      battle = self, mon = mon, gained = gained, levels = levels,
    })
    local name = mon.nickname or self.data.pokemon[mon.species].name
    if announce then
      -- GainedText (experience.asm:342-354): "X gained" plus one of
      -- _WithExpAllText / _BoostedText / _ExpPointsText; the EXP.ALL
      -- pass beats the traded boost (wBoostExpByExpAll checks first),
      -- and _ExpPointsText prints wExpAmountGained -- the raw share,
      -- captured before the max-level cap (experience.asm:92-100).
      -- _BoostedText / _WithExpAllText end in the CONT code (\v, "...\011"
      -- in data/generated/text.lua): the box waits for A/B + ▼ then scrolls
      -- the amount line in, so it stays on-screen instead of at y=144 (#216).
      local text = Strings.source("%s gained\n%d EXP. Points!")
      if announce == "expAll" then
        text = Strings.source("%s gained\nwith EXP.ALL,\v%d EXP. Points!")
      elseif traded then
        text = Strings.source("%s gained\na boosted\v%d EXP. Points!")
      end
      self:sayNext(Strings(text, name, gained))
    end
    -- per level: GrewLevelText -> the stats window (PrintStatsBox) ->
    -- the move-learn checks (experience.asm:245-256)
    local game = self.game
    for _, lv in ipairs(levels) do
      -- experience.asm:248 fires per grew-level text
      require("src.world.PikachuFollower")
        .modifyHappiness(game.save, "LEVELUP", mon)
      -- GrewLevelText: text_far, sound_level_up, text_end (experience.asm:
      -- 369-372); PrintStatsBox only runs once PrintText has returned
      self:sayNextWaitSfx(Strings("%s grew\nto level %d!", name, lv),
        function() return require("src.core.Sound").play(game.data, "Level_Up") end)
      self:uiNext(function()
        return StatBox.new(game, mon)
      end)
      -- After PrintStatsBox, experience.asm reloads the active battler's
      -- wBattleMon and runs DrawHUDsAndHPBars, so its HP bar reflects the
      -- higher current HP.  Experience.lua:84 already raised mon.hp by
      -- (newMaxHP - oldMaxHP); the party mon and the battler share one table
      -- (makeBattler), so mon.stats.hp (the bar's denominator) jumps to the
      -- new max instantly while the battler's shownHP numerator lags at the
      -- old current HP -- the bar SHRINKS (#224).  Animate shownHP up to the
      -- new current HP (house convention: potions drain the bar too, see
      -- itemUsed) so the bar grows instead.  Only the active player battler
      -- shares its table with the HUD; other party mons (EXP.ALL) have no bar.
      if mon == self.player.mon then self:drainNext() end
      for _, moveId in ipairs(Experience.movesLearnedAt(
          self.data.pokemon[mon.species], lv)) do
        self:learnMove(mon, moveId)
      end
    end
  end
  -- battle.exp_award: the participant/EXP.ALL split, factored out so a
  -- mod can replace it wholesale (e.g. a flat undivided share to every
  -- non-fainted party mon) without re-deriving participants/alive.
  -- ctx.applyShare(mon, split, announce) is the same helper vanilla uses.
  local function vanillaExpAward(ctx)
    -- with EXP.ALL, participants split half the exp and the other half
    -- is divided among the whole party (engine/battle/experience.asm)
    local expAll = (self.game.save.inventory.EXP_ALL or 0) > 0
    for _, mon in ipairs(ctx.alive) do
      ctx.applyShare(mon, ctx.participants * (expAll and 2 or 1), true)
    end
    if expAll then
      -- the second GainExperience pass sets the gain flags for the WHOLE
      -- party, so DivideExpDataByNumMonsGainingExp divides the already
      -- halved-and-participant-divided exp again by the party count, and
      -- .partyMonLoop still skips fainted mons (core.asm:818-858 +
      -- experience.asm:9-13); each mon gets its own GainedText with the
      -- "with EXP.ALL," tail (wBoostExpByExpAll) -- pokered prints no
      -- summary line
      for _, mon in ipairs(playerParty) do
        if mon.hp > 0 then
          ctx.applyShare(mon, math.max(1, ctx.participants) * #playerParty * 2, "expAll")
        end
      end
    end
  end
  local awardCtx = { battle = self, participants = participants, alive = alive,
                      applyShare = applyShare }
  if Runtime.wantsHook("battle.exp_award") then
    Runtime.call("battle.exp_award", vanillaExpAward, awardCtx)
  else
    vanillaExpAward(awardCtx)
  end
  self.participants = {}
end

function BattleState:enemyMonFainted()
  self:awardExp()

  if self.kind == "trainer" then
    -- EnemySendOutFirstMon / AnyEnemyPokemonAliveCheck (core.asm): scan
    -- the whole enemy party for the first mon with HP left.  Blindly
    -- doing enemyIndex+1 softlocks after an AI switch (Agatha): a later
    -- slot can already be fainted, so the empty-HP mon comes out, the
    -- FIGHT menu returns, and executeAction no-ops on target.hp <= 0.
    local nextIndex
    for i, mon in ipairs(self.enemyParty) do
      if mon.hp > 0 then
        nextIndex = i
        break
      end
    end
    if nextIndex then
      self.enemyIndex = nextIndex
      -- EnemySendOutFirstMon (core.asm:1366-1443): SHIFT offers a free
      -- switch when party count > 1, the active mon is alive, and the
      -- battle-style bit is clear.  pokered counts party slots (not
      -- remaining HP); SET / single-mon / fainted active skip the prompt.
      local nextMon = self.enemyParty[self.enemyIndex]
      local nextName = nextMon.nickname or self.data.pokemon[nextMon.species].name
      local style = tostring((self.game.save.options or {}).battleStyle or "shift")
        :lower()
      local partyCount = #self:playerPartyView()
      -- ReplaceFaintedEnemyMon (core.asm:892-896): DrawEnemyPokeballs puts the
      -- foe's party ball row -- and the HUD chrome PlaceEnemyHUDTiles lays
      -- down under it (draw_hud_pokeball_gfx.asm:9-11, 33-45, 134-141) -- into
      -- the block FaintEnemyPokemon just cleared, after the exp text and
      -- BEFORE the next send-out.  It survives EnemySendOutFirstMon's
      -- SlideTrainerPicOffScreen (core.asm:1308-1310, 8 steps x DelayFrames 2)
      -- so SET style gets the brief flash, and stays up through the whole
      -- SHIFT prompt below (#283).
      self:act(function() self.showEnemyBalls = true end)
      table.insert(self.queue, { wait = 16 })
      -- SwitchPlayerMon runs AFTER TrainerSentOutText (core.asm:1436-1443)
      local shiftSwitchMon = nil
      if style ~= "set" and partyCount > 1 and self.player.mon.hp > 0 then
        -- _TrainerAboutToUseText (data/text/text_2.asm): "X is" / "about to
        -- use" then a CONT to the nick, not a fresh box -- the box scrolls
        -- "X is" off so "about to use" stays above the name, instead of the
        -- page ending on a bare nick (#565).  Then para "Will PLAYER" /
        -- "change POKéMON?" with YES/NO.
        --
        -- _TrainerAboutToUseText combines both \f-paged, but unlike
        -- _ItemUseBallText00's say()+say() merge above, this is say()+
        -- sayChoice(): tried merging into one romText/sayChoice call and
        -- confirmed via tests/engine/trainer_shift_prompt_bug565.lua that
        -- the battle queue's own \f handling (not TextBox.lua's) does not
        -- page a sayChoice string the same way -- left as two calls.
        self:say(Strings("%s is\nabout to use\v%s!", self.trainer.name, nextName))
        -- EnemySendOutFirstMon .next9/.next8 (core.asm:1390-1409) and
        -- HasMonFainted's NoWillText (core.asm:1473-1488)
        self:sayChoice(
          Strings("Will %s\nchange POKéMON?", self.game.save.player.name),
          function(yes)
            if not yes then return end
            local game = self.game
            local shiftOpts, reopenShift
            reopenShift = function(text)
              table.insert(self.queue, 1, { ui = function()
                return self:buildScreen("PartyMenu", shiftOpts)
              end })
              table.insert(self.queue, 1, { text = text })
            end
            shiftOpts = {
              battle = self,
              party = self:playerPartyView(),
              forceSwitch = true,
              onSwitch = function(mon)
                if mon == self.player.mon then
                  reopenShift(self:romText("_AlreadyOutText",
                    "%s is\nalready out!", self.player.name))
                elseif mon.hp <= 0 then
                  reopenShift(self:romText("_NoWillText", "There's no will\nto fight!"))
                else
                  shiftSwitchMon = mon
                end
              end,
            }
            Screens.push(game, "PartyMenu", shiftOpts)
          end, { box = Theme.trainerSwitchBox })
      end
      self:act(function()
        local previous = self.enemy
        self.enemy = makeBattler(self.data, self.enemyParty[self.enemyIndex], false)
        -- EnemySendOutFirstMon (core.asm:1359-1363): the fresh foe's HP is the
        -- new wLastSwitchInEnemyMonHP baseline RetreatMon measures from
        self.lastSwitchInEnemyHP = self.enemy.mon.hp
        -- EnemySendOutFirstMon (core.asm:1314-1315): clears player's trap
        clearTrapping(self.player)
        self:syncSides()
        Runtime.emit("battle.battler_switched", {
          battle = self, side = self.sides[2], battler = self.enemy,
          previous = previous,
        })
        self.aiUses = self:aiUsesFor()
        markSeen(self.game, self.enemy.mon.species)
        -- EnemySendOutFirstMon .next4 (core.asm:1413-1417): ClearSprites and
        -- the 4x11 ClearScreenArea take the ball row away with the rest of
        -- the enemy HUD block, right before TrainerSentOutText (#283)
        self.showEnemyBalls = nil
        self:markParticipant()
        -- EnemySendOutFirstMon (core.asm:1413-1435): the enemy HUD area
        -- clears, TrainerSentOutText prints, THEN the pic appears
        -- (AnimateSendingOutMon) with the cry; no POOF -- that animation
        -- belongs to the player-side SendOutMon (core.asm:1757-1762)
        self.enemySendingOut = true
        self:sayNextAuto(self:romText("_TrainerSentOutText", "%s sent\nout %s!",
          self.trainer.name, self.enemy.name))
        self:actNext(function()
          self.enemySendingOut = false
          self:startGrowIn(self.enemy)
          self:actNext(function()
            self:waitSfxNext(self:playEntranceCry(self.enemy))
          end)
        end)
      end)
      -- SwitchPlayerMon after the enemy is out (core.asm:1436-1443)
      self:act(function()
        local mon = shiftSwitchMon
        if not mon then return end
        -- SwitchPlayerMon (core.asm:2419-2423): RetreatMon, the 50-frame
        -- hold, AnimateRetreatingPlayerMon, then the recall and the send-out
        self.nextInsert = 0
        self:sayNextAuto(self:withdrawText(self.player.name),
                         Timing.SWITCH_PLAYER_MON)
        self:queueRetreatAnim()
        self:actNext(function()
          local previous = self.player
          self.player = makeBattler(self.data, mon, true, self.game.save)
          clearTrapping(self.enemy)
          self:syncSides()
          Runtime.emit("battle.battler_switched", {
            battle = self, side = self.sides[1],
            battler = self.player, previous = previous,
          })
          -- Taking the SHIFT offer ZEROES wPartyGainExpFlags and
          -- wPartyFoughtCurrentEnemyFlags before jumping to SwitchPlayerMon
          -- (EnemySendOutFirstMon tail, core.asm:1436-1443), and SwitchPlayerMon
          -- then FLAG_SETs only the mon coming in (core.asm:2424-2433).  Without
          -- the reset the mon that was out when the enemy fainted -- marked by
          -- the send-out act above, which mirrors EnemySendOut's own re-flag
          -- (core.asm:1276-1289) -- stayed a participant, so the exp divisor in
          -- enemyMonFainted counted two mons and the switch-in earned half the
          -- next KO (#275).  Voluntary switches (resolveSwitch) and post-faint
          -- replacements (openReplacementMenu) must NOT do this: pokered's
          -- party-menu SwitchPlayerMon keeps the outgoing mon flagged, which is
          -- the deliberate exp-share, and a fainted mon is already dropped by
          -- onFaint mirroring RemoveFaintedPlayerMon (core.asm:1002-1007).
          self.participants = {}
          self:markParticipant()
          self.nextInsert = 0
          sendOutMonCursors(self)
          self.sendingOut = true
          self:sayNextAuto(self:sendOutText(self.player.name))
          self:queueSendOutAnim(false)
        end)
      end)
      return
    end
    local prize = (self.trainer.baseMoney or 0) * self.enemy.mon.level
    self.game.save.money = self.game.save.money + prize
    -- TrainerBattleVictory (core.asm:915-949) in order: EndLowHealthAlarm
    -- and the victory theme, TrainerDefeatedText, ScrollTrainerPicAfterBattle
    -- (the beaten trainer scrolls back in from the right, one column every 4
    -- frames, resting two tiles right of the battle slot), DelayFrames 40,
    -- PrintEndBattleText -- the trainer's OWN loss line, on the battle
    -- screen -- and only then MoneyForWinningText.  Every row rides the
    -- *Next inserters so it keeps that order behind the running queue item;
    -- the plain act() the pic used to ride appended to the END of the queue,
    -- which is why the trainer only flashed up for a frame or two as the
    -- battle popped and the loss line had to be printed by the overworld
    -- afterwards, stranding any evolution between two cuts (#282).
    -- endBattleText is filled in by whoever started the battle
    -- (OverworldState:engageTrainer in src/world/OverworldController.lua);
    -- scripted battles that print their own follow-up leave it nil.
    self:actNext(function() self:playVictoryMusic() end)
    -- _TrainerDefeatedText: "<PLAYER> defeated\nTRAINER!"
    self:sayNext(self:romText("_TrainerDefeatedText", "%s defeated\n%s!", self.game.save.player.name,
                                             self.trainer.name))
    self:actNext(function()
      self.showEnemyTrainer = self.trainerPic ~= nil
      if self.showEnemyTrainer then self:slidePic("foe", 64, 16, 2) end
    end)
    -- the 24-frame scroll-in plus the DelayFrames 40 that follows it
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert, { wait = 64 })
    if self.endBattleText then
      -- PrintEndBattleText prints one text box; a `para` (\f) inside it
      -- starts a fresh page, which is a message row of its own here (five
      -- EndBattleTexts carry one, e.g. _Route9Youngster1EndBattleText)
      -- TrainerEndBattleText (home/trainers.asm) prints _TrainerNameText
      -- (wNameBuffer then ": ", data/text/text_1.asm) and only then the
      -- saved pointer, so the loss line opens with the trainer class tag on
      -- its first line (RIVAL1/2/3 tag with the rival's name:
      -- TrainerNamePointers aims those entries at wTrainerName).  The tag
      -- prints once, so a `para` page carries no second copy (#566).
      local tag = self.trainer and self.trainer.name
      -- the badge jingle (sound_get_item_1 and friends) rides the armed
      -- line's first page, as the script's text command would (#1606)
      local sfx = self.endBattleSound
      local data = self.data
      for page in (self.endBattleText .. "\f"):gmatch("(.-)\f") do
        if page ~= "" then
          local line = tag and (tag .. ": " .. page) or page
          if sfx then
            local id = sfx
            self:sayNextWaitSfx(line, function()
              return require("src.core.Sound").play(data, id)
            end)
            sfx = nil
          else
            self:sayNext(line)
          end
          tag = nil
        end
      end
    end
    self:sayNext(self:romText("_MoneyForWinningText", "%s got ¥%d\nfor winning!", self.game.save.player.name, prize))
  end
  self.result = "win"
  self.afterQueue = "finish"
end

-- Queue the learn-a-move flow (auto if a slot is free, else the forget UI)
function BattleState:learnMove(mon, moveId)
  local mdef = self.data.moves[moveId]
  if not mdef then return end
  for _, mv in ipairs(mon.moves) do
    if mv.id == moveId then return end
  end
  if #mon.moves < 4 then
    table.insert(mon.moves, { id = moveId, pp = mdef.pp })
    Runtime.emit("pokemon.move_learned", { mon = mon, moveId = moveId })
    self:sayNextWaitSfx(self:romText("_MimicLearnedMoveText", "%s learned\n%s!", mon.nickname or self.data.pokemon[mon.species].name,
                                            mdef.name), function()
      return require("src.core.Sound").play(self.data, "Level_Up")
    end)
    return
  end
  -- the "trying to learn" preamble lives inside MoveLearnMenu:enter;
  -- ordered insert so multi-level gains keep each level's checks
  -- between its own stat box and the next "grew to level" text
  self:uiNext(function()
    return self:buildScreen("MoveLearnMenu", mon, moveId, nil, "Level_Up")
  end)
end

-- Map the battle was fought on (overworld wins; save.player.map is fallback).
function BattleState.currentMapId(self)
  local game = self.game
  local ow = game and game.overworld
  if ow and ow.map then return ow.map.id end
  local player = game and game.save and game.save.player
  return player and player.map
end

-- pret HandlePlayerBlackOut: OPP_RIVAL1 in OAKS_LAB prints Rival1WinText
-- and returns without blacking out.  OaksLabRivalEndBattleScript then heals.
function BattleState.isOaksLabStarterRival(self)
  return self.oppClass == "OPP_RIVAL1"
    and BattleState.currentMapId(self) == "OAKS_LAB"
end

function BattleState:playerMonFainted()
  local nextMon = Party.firstHealthy(self:playerPartyView())
  -- Being out of useable POKéMON blacks you out even when the battle was
  -- already decided in our favour.  A double faint -- our last mon dying
  -- to residual damage on the turn it lands the KO -- used to hit the
  -- "battle is decided" guard below and return with result = "win", so
  -- afterBattle never took the lose branch: no revive, no warp to the
  -- heal point, and the player was left standing on the map with a party
  -- at 0 HP.  Nothing recovers from that state (every later encounter
  -- aborts with "no healthy party"), and it is not reachable in pokered:
  -- HandlePlayerMonFainted runs the player-side check on its own, so
  -- losing your last mon always blacks you out whatever the enemy did.
  -- Exception: the Oak's Lab starter rival (HandlePlayerBlackOut).
  if not nextMon and self.result ~= "lose" then
    if self.oppClass == "OPP_RIVAL1" then
      local TextBox = require("src.render.TextBox")
      local raw = (self.data.text and self.data.text._Rival1WinText)
        or Strings("{RIVAL}: Yeah! Am\nI great or what?")
      self:sayNext(TextBox.substitute(self.game, raw))
    end
    -- Oak's Lab starter rival: Rival1WinText only (no blackout lines).
    -- Any other wipe, including Route 22 RIVAL1, still blacks out.
    if not BattleState.isOaksLabStarterRival(self) then
      -- HandlePlayerBlackOut (core.asm:1150-1159): SET_PAL_BATTLE_BLACK runs
      -- BEFORE PlayerBlackedOutText2, so the enemy pic and both HP bars are
      -- already dark under the blackout lines (#292).  The Oak's Lab starter
      -- rival returns one line above that call and never darkens.  Set here
      -- rather than queued: this whole function already runs from a queued
      -- act after "<mon> fainted!" was dismissed, which is where the palette
      -- command sits.  (The Route 22 RIVAL1 wipe darkens one box early, over
      -- Rival1WinText, which pokered prints just before the same command.)
      self.blackedOut = true
      self:sayNext(Strings("%s is out of\nuseable POKéMON!", self.game.save.player.name))
      self:sayNext(Strings("%s blacked\nout!", self.game.save.player.name))
    end
    self.result = "lose"
    self.afterQueue = "finish"
    return
  end
  if self.result then return end -- double faint: the battle is decided
  -- DoUseNextMonDialogue (core.asm:1052-1078): only WILD battles ask
  -- "Use next POKéMON?"; NO goes through the run check with party slot
  -- 1's speed, and a failed run still forces the party menu.  Trainer
  -- battles go straight to the party menu (the menu-phase guard).
  if self.kind ~= "wild" then return end
  local game = self.game
  self:say(self.data.text._UseNextMonText or Strings("Use next POKéMON?"))
  self:ui(function()
    local ChoiceBox = require("src.ui.ChoiceBox")
    return ChoiceBox.new(game, function(yes)
      if yes then return end -- the menu-phase guard opens the party menu
      local pSpd = (game.save.party[1].stats or { speed = 0 }).speed or 0
      if self:runRoll(pSpd, TurnOrder.effectiveSpeed(self.enemy)) then
        require("src.core.Sound").play(self.data, "Run")
        self:say(self:romText("_GotAwayText", "Got away safely!"))
        self.result = "run"
        self.afterQueue = "finish"
      else
        self:say(self:romText("_CantEscapeText", "Can't escape!"))
      end
    end)
  end)
end

-- ChooseNextMon (core.asm:1086-1128): the battle party menu; a fainted
-- pick re-prompts (via the menu-phase guard), a healthy pick is sent
-- out with no free enemy move.
function BattleState:openReplacementMenu()
  local game = self.game
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    return self:buildScreen("PartyMenu", {
      battle = self,
      party = self:playerPartyView(),
      -- ChooseNextMon: pick immediately (no SWITCH/STATS/CANCEL)
      forceSwitch = true,
      onSwitch = function(mon)
        if mon.hp <= 0 then
          self:say(self:romText("_NoWillText", "There's no will\nto fight!"))
          return -- the menu-phase guard reopens the menu
        end
        self:restoreMimicked(self.player)
        local previous = self.player
        self.player = makeBattler(self.data, mon, true, game.save)
        clearTrapping(self.enemy) -- SendOutMon clears foe trap
        self:syncSides()
        Runtime.emit("battle.battler_switched", {
          battle = self, side = self.sides[1], battler = self.player,
          previous = previous,
        })
        self:markParticipant()
        self.nextInsert = 0
        sendOutMonCursors(self)
        self.sendingOut = true
        self:sayNextAuto(self:sendOutText(self.player.name))
        self:queueSendOutAnim(false)
      end,
    })
  end)
end

-- ---------------------------------------------------------------------
-- Safari game turns
-- ---------------------------------------------------------------------

-- BAIT halves the working catch rate and raises the bait factor by 1-5
-- (zeroing the escape factor); ROCK doubles the catch rate and raises
-- the escape factor by 1-5 (zeroing bait) -- ItemUseBait/ItemUseRock,
-- engine/items/item_effects.asm.
function BattleState:safariAction(choice)
  self.phase = "messages"
  self.afterQueue = "menu"
  local st = self.safari
  local playerName = self.game.save.player.name

  if choice == "run" then
    require("src.core.Sound").play(self.data, "Run")
    self:say(self:romText("_GotAwayText", "Got away safely!"))
    self.result = "run"
    self.afterQueue = "finish"
    return
  end

  if choice == "ball" then
    st.balls = st.balls - 1
    self:sayAuto(Strings("%s used\nSAFARI BALL!", playerName))
    self:act(function()
      require("src.core.Sound").play(self.data, "Ball_Toss")
      self.lastBall = "SAFARI_BALL"
      local caught, shakes = self:catchAttempt("SAFARI_BALL", self.safariCatchRate)
      Runtime.emit("battle.ball_thrown", {
        battle = self, ball = "SAFARI_BALL", caught = caught, shakes = shakes,
      })
      -- SAFARI_BALL is neither POKE nor GREAT, so TossBallAnimation
      -- lands on the ULTRATOSS arc (no flicker: SAFARI_BALL is $08,
      -- above DoBallTossSpecialEffects's <= ULTRA_BALL check)
      self:ballChain(self:tossAnimFor("SAFARI_BALL"), caught, shakes, "SAFARI_BALL")
      if caught then
        -- ItemUseBallText05: text_far, sound_caught_mon, text_promptbutton --
        -- the fanfare follows the caught text and holds the prompt
        self:sayNextWaitSfx(Strings("All right!\n%s was\ncaught!", self.enemy.name),
          function() return require("src.core.Sound").play(self.data, "Caught_Mon") end)
        -- same ItemUseBall .captured flow as a regular ball
        self:act(function() self:storeCaughtMon() end)
      else
        self:sayNext(self:ballMissMessage(shakes))
        self:act(function() self:safariEnemyTurn() end)
      end
    end)
    return
  end

  if choice == "bait" then
    self:say(self:romText("_ThrewBaitText", "%s threw some\nBAIT.", playerName))
    self.safariCatchRate = math.floor(self.safariCatchRate / 2)
    self.baitFactor = math.min(255, self.baitFactor + self.rng(1, 5))
    self.escapeFactor = 0
  else -- rock
    self:say(self:romText("_ThrewRockText", "%s threw a\nROCK.", playerName))
    self.safariCatchRate = math.min(255, self.safariCatchRate * 2)
    self.escapeFactor = math.min(255, self.escapeFactor + self.rng(1, 5))
    self.baitFactor = 0
  end
  self:act(function() self:safariEnemyTurn() end)
end

-- Per-turn factor decay (PrintSafariZoneBattleText,
-- engine/battle/safari_zone.asm: when the escape factor runs out the
-- catch rate resets) then the flee check (engine/battle/core.asm:
-- b = 2*speed, quartered while eating, doubled while angry; the mon
-- flees when speed > 127 or rand(0,255) < b).
function BattleState:safariEnemyTurn()
  if self.baitFactor > 0 then
    self.baitFactor = self.baitFactor - 1
    self:sayNext(self:romText("_SafariZoneEatingText", "Wild %s\nis eating!", self.enemy.name))
  elseif self.escapeFactor > 0 then
    self.escapeFactor = self.escapeFactor - 1
    if self.escapeFactor == 0 then
      self.safariCatchRate = self.enemy.def.catchRate
    end
    self:sayNext(self:romText("_SafariZoneAngryText", "Wild %s\nis angry!", self.enemy.name))
  end
  self:act(function()
    local speed = self.enemy.curStats.speed % 256
    local fled = speed > 127
    local b = (speed * 2) % 256
    if not fled then
      if self.baitFactor > 0 then
        b = math.floor(b / 4)
      end
      if self.escapeFactor > 0 then
        b = math.min(255, b * 2)
      end
      fled = self.rng(0, 255) < b
    end
    if fled then
      self:sayNext(self:romText("_WildRanText", "Wild %s\nran!", self.enemy.name))
      self:actNext(function()
        require("src.core.Sound").play(self.data, "Run")
        startPicKind(self:picFxFor(self.enemy), "slideOff")
      end)
      self.nextInsert = (self.nextInsert or 0) + 1
      table.insert(self.queue, self.nextInsert, { wait = 24 })
      self.result = "run"
      self.afterQueue = "finish"
    end
  end)
end

-- ---------------------------------------------------------------------
-- run / items / party
-- ---------------------------------------------------------------------

-- Gen 1 escape formula (engine/battle/core.asm TryRunningFromBattle),
-- shared by the RUN menu choice and the faint dialogue's NO branch;
-- counts a run attempt each call.  Hooked as battle.run.
function BattleState:runRoll(pSpd, eSpd)
  self.runAttempts = (self.runAttempts or 0) + 1
  if Runtime.wantsHook("battle.run") then
    local battle = self
    return Runtime.call("battle.run", function(c)
      return battle:runRollVanilla(c.pSpd, c.eSpd)
    end, { battle = self, pSpd = pSpd, eSpd = eSpd,
           attempts = self.runAttempts, rng = self.rng })
  end
  return self:runRollVanilla(pSpd, eSpd)
end

function BattleState:runRollVanilla(pSpd, eSpd)
  if self.ghost then
    return true -- IsGhostBattle -> always escapes
  end
  if pSpd >= eSpd then return true end
  local b = math.floor(eSpd / 4) % 256
  if b == 0 then
    return true -- divisor of zero auto-escapes
  end
  local x = math.floor(pSpd * 32 / b)
  -- +30 per PREVIOUS attempt, escape on 8-bit overflow or on
  -- rand <= x (the original's jr nc keeps the equal case)
  x = x + 30 * (self.runAttempts - 1)
  return x >= 256 or self.rng(0, 255) <= x
end

-- Gen 1 escape formula (engine/battle/core.asm TryRunningFromBattle)
function BattleState:tryRun()
  self.phase = "messages"
  self.afterQueue = "menu"
  if self.kind == "trainer" then
    -- _NoRunningText is three lines in a two-line box, so the third arrives
    -- on a \v scroll (ContText: ▼ then a button press) rather than a \n.
    -- Spelling it with three \n dropped "trainer battle!" and handed the
    -- menu straight back (#239).
    self:say(self.data.text._NoRunningText
      or Strings("No! There's no\nrunning from a\vtrainer battle!"))
    return
  end
  -- modified in-battle speeds (stat stages + paralysis), like the
  -- wBattleMonSpeed the original hands to TryRunningFromBattle
  local escaped = self:runRoll(TurnOrder.effectiveSpeed(self.player),
                               TurnOrder.effectiveSpeed(self.enemy))
  if escaped then
    require("src.core.Sound").play(self.data, "Run")
    self:say(self:romText("_GotAwayText", "Got away safely!"))
    self.result = "run"
    self.afterQueue = "finish"
  else
    self:say(self:romText("_CantEscapeText", "Can't escape!"))
    self:act(function()
      self:executeAction(self.enemy, self.player, self:enemyAction())
    end)
    -- a failed escape loses the turn (core.asm:1572): the player's
    -- residual still ticks, same as an item turn
    self:queueResidual(self.player, self.enemy)
    self:act(function() self:endOfTurn() end)
  end
end

function BattleState:openItems()
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    return self:buildScreen("BagMenu", { battle = self })
  end)
end

-- called by BagMenu after an item is used in battle (consumes the turn)
function BattleState:itemUsed(messages)
  -- bag cures clear mon.status before the message UI; refresh the HUD
  -- once control returns (pokered DrawHUDsAndHPBars after item use)
  self:syncShownStatus()
  for _, m in ipairs(messages or {}) do self:say(m) end
  table.insert(self.queue, { drain = true }) -- potions animate the bar
  self:act(function()
    self:executeAction(self.enemy, self.player, self:enemyAction())
  end)
  -- the item spends the player's move, but its residual still ticks:
  -- ExecutePlayerMove rets early on wActionResultOrTookBattleTurn and
  -- MainInBattleLoop calls HandlePoisonBurnLeechSeed anyway
  -- (core.asm:3086-3088, 3275-3279)
  self:queueResidual(self.player, self.enemy)
  self:act(function() self:endOfTurn() end)
end

-- Wobble messages by shake count (ItemUseBallText01..04)
function BattleState:ballMissMessage(shakes)
  local t = self.data.text
  if shakes == 0 then
    return t._ItemUseBallText01 or Strings("You missed the\nPOKéMON!")
  elseif shakes == 1 then
    return t._ItemUseBallText02 or Strings("Darn! The POKéMON\nbroke free!")
  elseif shakes == 2 then
    return (t._ItemUseBallText03 or self:romText("_ItemUseBallText03", "Aww! It appeared\nto be caught!")):gsub("%s+$", "")
  end
  return t._ItemUseBallText04 or self:romText("_ItemUseBallText04", "Shoot! It was so\nclose too!")
end

-- AskName (engine/menus/naming_screen.asm): ClearSprites, wild field blank,
-- PrintText, YES/NO while text stays (TextBox opts.choice). Shared by party
-- AddPartyMon and SendNewMonToBox (#172).
function BattleState:askNicknameUI(mon, displayName)
  local game = self.game
  self.lockedBall = nil
  self.blankForAskName = true
  local TextBox = require("src.render.TextBox")
  local text = self:romText("_DoYouWantToNicknameText", "Do you want to\ngive a nickname\nto %s?", displayName)
  local label = game.data.text and game.data.text._DoYouWantToNicknameText
  if label then
    -- extractor CONT is \t; TextBox scrolls on \n/\v
    text = label:gsub("\t", "\n"):gsub("{RAM:?[%w_]*}", displayName)
  end
  return TextBox.new(game, text, nil, {
    choice = function(yes)
      self.blankForAskName = false
      if not yes then return end
      pcall(Screens.push, game, "NamingScreen", {
        title = Strings("NICKNAME?"), maxLen = 10,
        onDone = function(name)
          if name and #name > 0 then mon.nickname = name end
        end,
      })
    end,
  })
end

-- The caught mon joins the party or a PC box (ItemUseBall .captured,
-- item_effects.asm:518-566): the caught text, then for a NEW species
-- "New POKéDEX data will be added" + the dex entry page, then
-- AddPartyMon or SendNewMonToBox (both call AskName), then the PC
-- transfer text when the party was full.
function BattleState:storeCaughtMon()
  -- ItemUseBall reloads the caught mon via LoadEnemyMonData
  -- (item_effects.asm:472-501), regenerating its move list from the
  -- base data -- a Mimic'd slot never leaves the battle with it
  self:restoreMimicked(self.enemy)
  -- battle.catch_exp: vanilla catches never grant exp; a mod can flip
  -- this to true to pay out the same award a faint would have.
  if Runtime.wantsHook("battle.catch_exp")
     and Runtime.call("battle.catch_exp", function() return false end, { battle = self }) then
    self:awardExp()
  end
  local game = self.game
  local dex = game.save.pokedex
  local species = self.enemy.mon.species
  local isNew = dex ~= nil and not dex.owned[species]
  local destination = "party"
  markOwned(game, species)
  stampOT(game.save, self.enemy.mon)
  if isNew then
    -- _ItemUseBallText06 + ShowPokedexData: text_far, sound_dex_page_added,
    -- text_promptbutton (item_effects.asm:624-629), so the fanfare follows
    -- the box rather than firing when the dex bit is set
    self:sayNextWaitSfx(
      self:romText("_ItemUseBallText06",
        "New POKéDEX data\nwill be added for\n%s!", self.enemy.name),
      function() return require("src.core.Sound").play(self.data, "Dex_Page_Added") end)
    self:uiNext(function()
      return self:buildScreen("DexEntryMenu", species)
    end)
  end
  local function askCaughtNickname()
    local caught = self.enemy.mon
    local enemyName = self.enemy.name
    self:uiNext(function()
      return self:askNicknameUI(caught, enemyName)
    end)
  end
  if Party.add(game.save.party, self.enemy.mon) then
    askCaughtNickname()
  else
    destination = "box"
    local boxNum = require("src.pokemon.Boxes").deposit(game.save, self.enemy.mon)
    if boxNum then
      askCaughtNickname()
      -- _ItemUseBallText07/08 keyed on EVENT_MET_BILL
      local metBill = game.save.flags and game.save.flags.EVENT_MET_BILL
      self:sayNext(self:romText(
        metBill and "_ItemUseBallText07" or "_ItemUseBallText08",
        metBill and "%s was\ntransferred to\nBILL's PC!"
                or "%s was\ntransferred to\nsomeone's PC!",
        self.enemy.name))
    else
      self:sayNext(Strings("But every BOX\nis full!"))
    end
  end
  Runtime.emit("pokemon.caught", {
    battle = self, mon = self.enemy.mon, species = species, isNew = isNew,
    ball = self.lastBall, destination = destination, game = game,
  })
  self.result = "caught"
  self.afterQueue = "finish"
end

-- TossBallAnimation (engine/battle/animations.asm:2582): the tier's toss
-- anim, then wPokeBallAnimData's upper-nybble count of .PokeBallAnimations
-- entries -- POOF+HIDEPIC+SHAKE for a capture ($43), all five (plus a
-- reappearing POOF+SHOWPIC) for a breakout ($6x); a clean miss ($20)
-- stops after the poof, so the mon never hides
function BattleState:ballChain(tossAnim, caught, shakes, ball)
  self:animNext(tossAnim, true, nil, ball)
  self:animNext("POOF_ANIM", true)
  if not caught and shakes == 0 then return end
  self:animNext("HIDEPIC_ANIM", true)
  self:animNext("SHAKE_ANIM", true, shakes)
  if not caught then
    self:animNext("POOF_ANIM", true)
    self:animNext("SHOWPIC_ANIM", true)
    return
  end
  -- on a capture the $43 chain simply ends after SHAKE_ANIM
  -- (TossBallAnimation returns): the GB leaves the resting closed ball
  -- in OAM, so it stays on screen through the caught text
  self:actNext(function()
    self.lockedBall = self.animPlayer and self.animPlayer:finalSprites() or nil
  end)
end

-- TossBallAnimation picks the toss arc from the ball record's tossAnim;
-- an unknown ball keeps the wCurItem mapping: POKE->TOSS,
-- GREAT->GREATTOSS, everything else (ULTRA/MASTER/SAFARI...)->ULTRATOSS
function BattleState:tossAnimFor(ball)
  local def = self:ballDef(ball)
  if def and def.tossAnim then return def.tossAnim end
  return ball == "POKE_BALL" and "TOSS_ANIM"
         or ball == "GREAT_BALL" and "GREATTOSS_ANIM"
         or "ULTRATOSS_ANIM"
end

-- the Master/Ultra OBJ-palette flicker, from the ball record
function BattleState:ballFlicker(ball)
  local def = self:ballDef(ball)
  return (def and def.flicker) or false
end

-- called by BagMenu when a ball is thrown
function BattleState:throwBall(ball)
  -- ItemUseBall branches to ThrowBallAtTrainerMon on wIsInBattle != 1
  -- (item_effects.asm:109-113) BEFORE it reaches `ld hl, ItemUseText00 /
  -- call PrintText` (:146-147), so a trainer battle never shows the
  -- "<PLAYER> used <ITEM>!" line (#291).  Safari and the old man demo are
  -- still wIsInBattle == 1, and this port models both as kind == "wild".
  if self.kind == "wild" then
    self:sayAuto(self:romText("_ItemUseText001", "%s used\n%s!", self.game.save.player.name,
                                     self.data.items[ball].name))
  end
  self:act(function()
    require("src.core.Sound").play(self.data, "Ball_Toss")
    if self.kind ~= "wild" then
      -- ThrowBallAtTrainerMon (item_effects.asm:2292-2303) still animates the
      -- toss: MoveAnimation routes TOSS_ANIM to TossBallAnimation, which takes
      -- its .BlockBall branch in a trainer battle (animations.asm:2582-2585,
      -- 2629-2637) -- the plain TOSS arc whatever the ball tier, then
      -- SFX_FAINT_THUD and BLOCKBALL_ANIM, and only then the two texts.  The
      -- ball still counts as used: UseItem_ sets
      -- wActionResultOrTookBattleTurn = 1 (item_effects.asm:1-3) and this path
      -- never clears it, so UseBagItem does not fall back to the bag
      -- (core.asm:2257-2259) and the turn is spent -- the foe moves (#291).
      local t = self.data.text
      self:animNext("TOSS_ANIM", true, nil, ball)
      self:actNext(function()
        require("src.core.Sound").play(self.data, "Faint_Thud")
      end)
      self:animNext("BLOCKBALL_ANIM", true)
      self:sayNext(t._ThrowBallAtTrainerMonText1
                   or self:romText("_ThrowBallAtTrainerMonText1", "The trainer\nblocked the BALL!"))
      self:sayNext(t._ThrowBallAtTrainerMonText2
                   or self:romText("_ThrowBallAtTrainerMonText2", "Don't be a thief!"))
      self:act(function()
        self:executeAction(self.enemy, self.player, self:enemyAction())
      end)
      -- a thrown ball spends the turn like an item: the player's residual
      -- still ticks (core.asm:3275-3279)
      self:queueResidual(self.player, self.enemy)
      self:act(function() self:endOfTurn() end)
      return
    end
    if self.ghost or self.noCatch then
      -- ItemUseBall's can't-be-caught path (item_effects.asm:149-153):
      -- the ball is thrown (TossBallAnimation still picks the arc from
      -- wCurItem, so a Master/Ultra toss keeps its flicker), dodged
      -- ($10 anim data, no wobbles), and the turn is spent like any
      -- failed throw.  battle.noCatch is the .notOldManBattle half of the
      -- same check (item_effects.asm:166-175): the POKEMON_TOWER_6F
      -- RESTLESS SOUL dodges balls even once the scope has revealed it,
      -- so it is not a ghost battle any more (#444)
      self:animNext(self:tossAnimFor(ball), true, nil, ball)
      -- _ItemUseBallText00 is one label for both lines, \f-paged.  Unlike
      -- TextBox.new() (which splits \f itself), the battle queue's own
      -- startMessage() only splits on \n/\v -- confirmed live: the \f
      -- landed mid-line and the second sentence overflowed off the box
      -- instead of starting a fresh page.  Resolve the label once, then
      -- split it the same way TextBox.lua does and queue one sayNext per
      -- page, so the two ROM sentences still render as two pages.
      local dodgeText = self:romText("_ItemUseBallText00",
        "It dodged the\nthrown BALL!\fThis POKéMON\ncan't be caught!")
      for page in (dodgeText .. "\f"):gmatch("(.-)\f") do
        self:sayNext(page)
      end
      self:act(function()
        self:executeAction(self.enemy, self.player, self:enemyAction())
      end)
      -- a thrown ball spends the turn like an item: the player's residual
      -- still ticks (core.asm:3275-3279)
      self:queueResidual(self.player, self.enemy)
      self:act(function() self:endOfTurn() end)
      return
    end
    self.lastBall = ball
    local caught, shakes = self:catchAttempt(ball)
    Runtime.emit("battle.ball_thrown", {
      battle = self, ball = ball, caught = caught, shakes = shakes,
    })
    -- ItemUseBall's 20-frame beat, then the toss chain for the outcome
    self.nextInsert = (self.nextInsert or 0) + 1
    table.insert(self.queue, self.nextInsert, { wait = 20 })
    self:ballChain(self:tossAnimFor(ball), caught, shakes, ball)
    if caught then
      -- ItemUseBallText05 carries sound_caught_mon (item_effects.asm:
      -- 608-614): text_far, sound_caught_mon, text_promptbutton -- the
      -- fanfare follows the caught message and holds the prompt
      self:sayNextWaitSfx(Strings("All right!\n%s was\ncaught!", self.enemy.name),
        function() return require("src.core.Sound").play(self.data, "Caught_Mon") end)
      self:act(function() self:storeCaughtMon() end)
    else
      self:sayNext(self:ballMissMessage(shakes))
      self:act(function()
        self:executeAction(self.enemy, self.player, self:enemyAction())
      end)
      -- a thrown ball spends the turn like an item: the player's residual
      -- still ticks (core.asm:3275-3279)
      self:queueResidual(self.player, self.enemy)
      self:act(function() self:endOfTurn() end)
    end
  end)
end

function BattleState:openParty()
  self.phase = "messages"
  self.afterQueue = "menu"
  self:ui(function()
    return self:buildScreen("PartyMenu", {
      battle = self,
      party = self:playerPartyView(),
      onSwitch = function(mon)
        -- PartyMenuOrRockOrRun's SWITCH .partyMonDeselected (core.asm:2396-2408)
        if mon == self.player.mon then
          self:say(self:romText("_AlreadyOutText",
            "%s is\nalready out!", self.player.name))
          self:act(function() self:openParty() end)
        elseif mon.hp <= 0 then
          self:say(self:romText("_NoWillText", "There's no will\nto fight!"))
          self:act(function() self:openParty() end)
        else
          self:resolveSwitch(mon)
        end
      end,
    })
  end)
end

-- PlayBattleVictoryMusic (core.asm:959-967) + EndLowHealthAlarm
-- (core.asm:864-872): winning stops the low-health alarm and disables
-- it for the rest of the battle (wLowHealthAlarmDisabled), then starts
-- the victory theme once; gym leaders, Lance and the final rival share
-- MUSIC_DEFEATED_GYM_LEADER (core.asm:917-926).
function BattleState:playVictoryMusic()
  require("src.core.Sound").stopLoop("Low_Health_Alarm")
  self.lowHealthAlarmDisabled = true
  if self.victoryMusicPlayed then return end
  self.victoryMusicPlayed = true
  local kind = self.musicKind == "final" and "gym" or (self.musicKind or "wild")
  require("src.core.Music").playVictory(self.data, kind)
end

function BattleState:finish()
  if self.payDay and self.result == "win" then
    self.game.save.money = self.game.save.money + self.payDay
    self:say(self:romText("_PickUpPayDayMoneyText", "%s picked up\n¥%d!", self.game.save.player.name, self.payDay))
    self.payDay = nil
    self.afterQueue = "finish"
    self.phase = "messages"
    return
  end
  -- Invariant: a battle can never hand the overworld a party with nothing
  -- healthy in it -- except the Oak's Lab starter rival, where pret skips
  -- the blackout and OaksLabRivalEndBattleScript HealParty's immediately.
  -- afterBattle only revives and warps to the heal point on a normal
  -- "lose", so any other result here strands the player at 0 HP with no
  -- way back -- an unrecoverable state, not merely a wrong one.
  -- playerMonFainted is the path that should have caught this; if we land
  -- here it did not, so say so rather than silently papering over it.
  -- The old-man / PROF.OAK demo also skips it: the party never fought
  -- (Yellow's Pallet intro runs before the player owns a mon at all).
  if self.kind ~= "link" and self.result ~= "lose" and not self.demo
     and not Party.firstHealthy(self:playerPartyView()) then
    Logger.warn("battle finished %s with no healthy party; forcing blackout",
                tostring(self.result))
    self.result = "lose"
  end
  self.lockedBall = nil
  -- pokered never writes Mimic's copy into the party struct; leaving
  -- battle discards the battle copy, so the original ids come back
  self:restoreMimicked(self.player)
  self:restoreMimicked(self.enemy)
  -- end_of_battle.asm clears wLowHealthAlarm at battle teardown
  require("src.core.Sound").stopLoop("Low_Health_Alarm")
  -- the victory theme already started when the win was decided
  -- (FaintEnemyPokemon .wild_win / TrainerBattleVictory) and loops until
  -- the battle screen closes; leaving battle brings back the map theme,
  -- like the overworld reload's PlayDefaultMusicFadeOutCurrent
  -- (home/overworld.asm:2343-2348)
  require("src.core.Music").restoreMap(self.data)
  self.game.stack:pop()
  Runtime.emit("battle.ended", { battle = self, result = self.result or "run" })
  -- Coming back from the battle screen is a fade, not a cut: EnterMap sees
  -- BIT_BATTLE_OVER_OR_BLACKOUT set and runs MapEntryAfterBattle
  -- (home/overworld.asm:22, :749-753) = GBFadeInFromWhite.  This is the one
  -- choke point every battle -- wild, trainer, walk-up, scripted, link --
  -- passes through on its way out, so the fade is guaranteed here rather
  -- than depending on each caller having wrapped onFinish correctly.
  local result = self.result or "run"
  local onFinish = self.onFinish
  if result == "lose" then
    -- the blackout path warps to the heal point with its own transition
    if onFinish then onFinish(result) end
    return
  end
  self.game.stack:push(require("src.render.Transition").battleReturn(self.game,
    function() if onFinish then onFinish(result) end end))
end

-- ---------------------------------------------------------------------
-- draw
-- ---------------------------------------------------------------------

-- In-battle HUD tiles + the tile HP bar live in src/render/HudTiles.lua
-- (shared with the status screen)
local HudTiles = require("src.render.HudTiles")
local hudTile = HudTiles.tile
local drawHPBar = HudTiles.drawHPBar

-- CenterMonName: 1-2 letter names print two tiles right, 3-4 one tile.
-- Counted in glyphs, not bytes: a nickname carrying "é" or "♂" is one
-- charmap sequence per glyph, and byte length would push it a tile left.
local function nameX(tx, name)
  local n = #Font.split(name)
  return tx * 8 + (n <= 2 and 16 or n <= 4 and 8 or 0)
end

-- Party pokeball row (SetupPokeballs tiles: ball / status ball /
-- fainted ball / empty), 6 slots stepping dx from (x,y).
local ballQuads
local function balls()
  if ballQuads == nil then
    local ok, img = pcall(love.graphics.newImage, "assets/generated/battle/balls.png")
    if ok then
      ballQuads = { img = img }
      for i = 0, 3 do
        ballQuads[i] = love.graphics.newQuad(i * 8, 0, 8, 8, img:getDimensions())
      end
    else
      ballQuads = false
    end
  end
  return ballQuads or nil
end

function BattleState:drawCaughtBall(x, y)
  local quads = balls()
  if not quads then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(quads.img, quads[0], x, y)
end

function BattleState:drawBallRow(party, x, y, dx)
  local quads = balls()
  if not quads then return end
  for i = 1, 6 do
    local mon = party[i]
    local tile = not mon and 3 or mon.hp <= 0 and 2 or mon.status and 1 or 0
    love.graphics.draw(quads.img, quads[tile], x + (i - 1) * dx, y)
  end
end

-- the grow-in scale for a battler's pic this frame: nil when not
-- growing, else 0 (ball beat) / 3/7 / 5/7 -- AnimateSendingOutMon's
-- stages (core.asm:6801-6838): 3 frames of the ball tile, 4 frames of
-- a 3x3 block of the 7x7 pic tiles, 5 frames of 5x5, then full size
function BattleState:growInScale(battler)
  local grow = self.growIn
  if not grow or grow.battler ~= battler then return nil end
  local f = grow.frame
  return f < 3 and 0 or f < 7 and 3 / 7 or 5 / 7
end

-- AnimateRetreatingPlayerMon's CopyDownscaledMonTiles stages
-- (core.asm:1769-1796)
function BattleState:shrinkOutScale(battler)
  local shrink = self.shrinkOut
  if not shrink or shrink.battler ~= battler then return nil end
  -- scale 0 past Delay3: the area stays cleared until the swap
  -- (core.asm:1790-1796) (#1563)
  return shrink.frame < 4 and 5 / 7 or shrink.frame < 7 and 3 / 7 or 0
end

-- battler hidden this frame? (damage blink)
--
-- AnimationBlinkMon hides the pic, waits DelayFrames 5, shows it, waits
-- DelayFrames 5, six times over (animations.asm:1360-1376) -- a 10-frame
-- period, not 8.  With Timing.BLINK_MON that is exactly six blinks.
function BattleState:fxHidden(battler)
  local fx = self.fx
  if fx and fx.blink and fx.blink.target == battler and fx.blink.frames > 0 then
    return self.frame % 10 < 5
  end
  return false
end

-- is the faint slide currently playing for this battler?
function BattleState:fxFaintActive(battler)
  local fx = self.fx
  return fx and fx.faint and fx.faint.battler == battler
         and fx.faint.frames > 0 or false
end

-- vertical slide offset for a fainting battler.  The offset is in screen
-- pixels, so it scales with the pic's draw scale (the player's default 2x
-- sinks 2x as fast to sink at the same visual rate); a mod scale composes
-- the same way.  scale defaults to the vanilla side scale when unknown.
-- SlideDownFaintedMonPic drops the pic one 8px row per 2-frame step, so
-- the offset advances Timing.FAINT_SLIDE_STEP (4px) per frame at 1x --
-- the full 56px PIC_HEIGHT slide over the 14-frame budget (#671: the
-- old (30 - frames) math teleported the sprite 32px down on frame one).
function BattleState:fxFaintOffset(battler, scale)
  local fx = self.fx
  if self:fxFaintActive(battler) then
    scale = scale or (battler.isPlayer and 2 or 1)
    return (Timing.FAINT_SLIDE - fx.faint.frames) * Timing.FAINT_SLIDE_STEP * scale
  end
  return 0
end

-- Substitute doll (AnimationSubstitute, engine/battle/animations.asm):
-- while a battler's substitute is up, its pic is replaced by the mini
-- doll from gfx/sprites/monster.png -- the facing-DOWN frame for the
-- enemy, facing-UP for the player, a 16x16 sprite at pic tiles
-- (2..3,4..5) / (3..4,4..5) of the 7x7 frame: screen (112,32) enemy,
-- (32,72) player.
local substDoll
function BattleState:drawSubstituteDoll(battler)
  if substDoll == nil then
    local ok, img = pcall(love.graphics.newImage,
                          "assets/generated/sprites/monster.png")
    if ok then
      local w, h = img:getDimensions()
      substDoll = { img = img,
                    down = love.graphics.newQuad(0, 0, 16, 16, w, h),
                    up = love.graphics.newQuad(0, 16, 16, 16, w, h) }
    else
      substDoll = false
    end
  end
  if not substDoll then return end
  -- in colorized mode the doll (drawn from BG tiles on the GB) takes
  -- its screen zone's SGB palette like everything else in the region
  local shader
  if self:colorMode() then
    local PaletteFX = require("src.render.PaletteFX")
    shader = PaletteFX.shader()
    if shader then
      local colors = self:zoneColorsAt(battler.isPlayer and 32 or 112,
                                       battler.isPlayer and 72 or 32)
      if colors then
        love.graphics.setShader(shader)
        PaletteFX.sendColors(shader,
          require("src.render.PaletteFX").permute(colors, self:activeBgp()))
      else
        shader = nil
      end
    end
  end
  if battler.isPlayer then
    love.graphics.draw(substDoll.img, substDoll.up, 32, 72)
  else
    love.graphics.draw(substDoll.img, substDoll.down, 112, 32)
  end
  if shader then love.graphics.setShader() end
end

-- MinimizedMonSprite (animations.asm:1745): the 8x5 blob that replaces
-- a minimized mon's pic, written at pic tile (3,4)+2px.  Rows are bit
-- patterns, drawn as shade-3 pixels.
local MINIMIZED_ROWS = {
  { 3, 4 },          -- ...XX...
  { 2, 5 },          -- ..XXXX..
  { 1, 6 },          -- .XXXXXX.
  { 2, 5 },          -- ..XXXX..
  { 2, 2, 5, 5 },    -- ..X..X..
}
function BattleState:drawMinimizedBlob(battler, x, y)
  local r, g, b, a = love.graphics.getColor()
  local col = { 0, 0, 0, 1 }
  local pals = self:colorMode() and self:sgbBattlePals()
  if pals then
    local P = pals[battler.isPlayer and 2 or 3]
    local shade = P[4]
    col = { shade[1] / 255, shade[2] / 255, shade[3] / 255, 1 }
  end
  love.graphics.setColor(col)
  for row, runs in ipairs(MINIMIZED_ROWS) do
    for i = 1, #runs, 2 do
      love.graphics.rectangle("fill", x + 24 + runs[i], y + 34 + row - 1,
                              runs[i + 1] - runs[i] + 1, 1)
    end
  end
  love.graphics.setColor(r, g, b, a)
end

-- Draw a battler pic, sinking it behind its own baseline while the
-- faint slide plays (pokered's AnimationSlideMonDown); a fainted
-- battler stays hidden once the slide ends.  A standing substitute
-- shows the mini doll instead of the mon's own pic.  The SE-driven
-- pic effects (slides/squish/blink/minimize; see applyAnimEffect)
-- offset, clip or replace the pic, and an active BGP fade swaps in a
-- shade-remapped recolor of it.
function BattleState:drawBattlerPic(battler, x, y, scale)
  local img = self:picImage(battler.sprite)
  if battler.substituteHP and not self:fxFaintActive(battler)
     and not battler.fainted then
    self:drawSubstituteDoll(battler)
    return
  end
  if self:fxFaintActive(battler) then
    local off = self:fxFaintOffset(battler, scale)
    local visible = img:getHeight() - math.floor(off / scale)
    if visible > 0 then
      local quad = love.graphics.newQuad(0, 0, img:getWidth(), visible,
                                         img:getWidth(), img:getHeight())
      love.graphics.draw(img, quad, x, y + off, 0, scale, scale)
    end
    return
  end
  if battler.fainted then return end

  -- MarowakAnim's rOBP1 fades (updateFx): alpha over the paper is what those
  -- palette shifts look like, and the test has to sit ahead of the plain
  -- fast path below (#492)
  local fadePf = self.picFx and self.picFx[battler]
  if fadePf and fadePf.fade then
    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setColor(cr, cg, cb, ca * fadePf.fade)
    love.graphics.draw(img, x, y, 0, scale, scale)
    love.graphics.setColor(cr, cg, cb, ca)
    return
  end

  local pf = self.picFx and self.picFx[battler]
  if not pf or (not pf.kind and not pf.hidden and not pf.minimized
                and (pf.ox or 0) == 0 and (pf.oy or 0) == 0) then
    love.graphics.draw(img, x, y, 0, scale, scale)
    return
  end
  if pf.hidden then return end
  if pf.minimized then
    self:drawMinimizedBlob(battler, x, y)
    return
  end

  local w, h = img:getWidth(), img:getHeight()
  local ox, oy = pf.ox or 0, pf.oy or 0
  local k, t = pf.kind, pf.t or 0
  local xscale = 1
  -- while an SE effect displaces the pic, confine it to its side's
  -- tile window like the GB tilemap does (the pic can never overwrite
  -- the HUD columns or the text box rows)
  -- ...except under the widescreen layout, where the side's own region
  -- scissor is already that window on a battlefield the classic tile
  -- columns do not describe (an 88..160 clip would fall entirely outside
  -- the enemy's region and erase the pic).
  local clip = love.graphics.setScissor and love.graphics.intersectScissor
                 and not self.wideRegion
  local scx, scy, scw, sch
  if clip then
    scx, scy, scw, sch = love.graphics.getScissor()
    if battler.isPlayer then
      love.graphics.intersectScissor(0, 0, 80, 96)
    else
      love.graphics.intersectScissor(88, 0, 72, 56)
    end
  end
  if k == "slideOff" then
    -- one tile (8px) toward the mon's own screen edge per 3 frames
    local dir = battler.isPlayer and -1 or 1
    ox = ox + dir * 8 * math.min(8, math.floor(t / 3) + 1)
  elseif k == "slideHalf" then
    local dir = battler.isPlayer and -1 or 1
    ox = ox + dir * 8 * math.min(4, math.floor(t / 4) + 1)
  elseif k == "slideDown" then
    oy = oy + 8 * math.min(7, math.floor(t / 3) + 1)
  elseif k == "slideDownHide" then
    oy = oy + 16 * (math.floor(t / 8) + 1)
  elseif k == "bounce" then
    -- 5 back-to-back AnimationSlideMonDown passes
    oy = oy + 8 * math.min(7, math.floor((t % 21) / 3) + 1)
  elseif k == "shakeBF" then
    ox = ox + ((math.floor(t / 3) % 2 == 0) and -8 or 8)
  elseif k == "squish" then
    xscale = math.max(0, 7 - 2 * (math.floor(t / 6) + 1)) / 7
  elseif k == "blink" then
    -- skip; falls through to the scissor-restore below instead of an
    -- early return that would leave the pic-window scissor stuck
  end

  local skipDraw = (k == "squish" and xscale <= 0)
                    or (k == "blink" and math.floor(t / 5) % 2 == 0)

  if skipDraw then
    -- draw nothing this frame, but still restore the scissor rect
  elseif oy > 0 then
    -- sink below the baseline (AnimationSlideMonDown-style row clip)
    local visible = h - math.floor(oy / scale)
    if visible > 0 then
      local quad = love.graphics.newQuad(0, 0, w, visible, w, h)
      love.graphics.draw(img, quad, x + ox, y + oy, 0, scale, scale)
    end
  elseif k == "slideUp" then
    -- AnimationSlideMonUp (animations.asm): 7 row steps x 2f. After Dig's
    -- SLIDE_DOWN the tilemap is blank; each step fills the next bottom
    -- row so the mon emerges from underground. A cyclic wrap of a full
    -- pic looked like a bounce at Dig's end (#100).
    local step = math.min(7, math.floor((t - 1) / 2) + 1)
    local visible = math.floor(h * step / 7)
    if visible > 0 then
      local quad = love.graphics.newQuad(0, h - visible, w, visible, w, h)
      love.graphics.draw(img, quad, x + ox,
                         y + (h - visible) * scale, 0, scale, scale)
    end
  elseif xscale < 1 then
    -- AnimationSquishMonPic: columns collapse toward the middle
    love.graphics.draw(img, x + w * scale * (1 - xscale) / 2, y,
                       0, scale * xscale, scale)
  else
    love.graphics.draw(img, x + ox, y + oy, 0, scale, scale)
  end
  if clip then
    if scx then
      love.graphics.setScissor(scx, scy, scw, sch)
    else
      love.graphics.setScissor()
    end
  end
end

-- ------------------------------------------------------------------
-- SGB battle colorization.  SetPal_Battle (engine/gfx/palettes.asm:28)
-- assigns pal 0 = player HP-bar palette, pal 1 = enemy HP-bar palette,
-- pal 2 = player mon palette, pal 3 = enemy mon palette;
-- BlkPacket_Battle (data/sgb/sgb_packets.asm:65) maps them onto screen
-- regions.  The BG layer is drawn in DMG grays to a canvas and each
-- region is recolored through the PaletteFX shader; the OAM anim
-- sprites are colored per sprite afterwards (BGP fades never touch
-- them, matching the hardware).
-- ------------------------------------------------------------------

-- BlkPacket_Battle ATTR_BLK data: pal slot + inclusive tile rect.
-- The first entry is the %111 outside fill; the blocks are disjoint.
local BATTLE_ZONES = {
  { pal = 0, 0, 0, 19, 17 },  -- everything else
  { pal = 1, 1, 0, 10, 3 },   -- enemy HUD
  { pal = 0, 10, 7, 19, 10 }, -- player HUD
  { pal = 2, 0, 4, 8, 11 },   -- player mon
  { pal = 3, 11, 0, 19, 6 },  -- enemy mon
  { pal = 2, 0, 12, 19, 17 }, -- message box
}

-- the colorizer needs canvases + shaders + pixel access (headless
-- stubs and stripped-down builds fall back to the flat colored path)
function BattleState:colorMode()
  if self.colorFxReady == nil then
    local ready = false
    local g = love and love.graphics
    local PaletteFX = require("src.render.PaletteFX")
    if g and g.newCanvas and g.setScissor and g.setShader and g.getCanvas
       and love.image and PaletteFX.pack(self.data)
       and PaletteFX.shader() then
      -- 160x144 real pixels, not DPI units, or the colored battle background
      -- resamples against the UI canvas on mobile (#208; PixelCanvas.lua)
      local PixelCanvas = require("src.render.PixelCanvas")
      local ok1, bg = pcall(PixelCanvas.new, 160, 144)
      local ok2, wv = pcall(PixelCanvas.new, 160, 144)
      if ok1 and ok2 and bg and wv then
        self.bgCanvas, self.waveCanvas = bg, wv
        ready = true
      end
    end
    self.colorFxReady = ready
  end
  return self.colorFxReady
end

-- The four SGB palettes SetPal_Battle would currently send: bar
-- palettes track the drawn HP bars (GetHealthBarColor), the mon slots
-- hold MonsterPalettes[wBattleMonSpecies]/[wEnemyMonSpecies2] --
-- PAL_MEWMON (= MonsterPalettes[0]) while a side still shows its
-- trainer/back pic (the species bytes are 0 then).
function BattleState:sgbBattlePals()
  local PaletteFX = require("src.render.PaletteFX")
  local pack = PaletteFX.pack(self.data)
  local pals = pack and pack.palettes
  if not pals then return nil end
  -- HandlePlayerBlackOut (core.asm:1151) runs SET_PAL_BATTLE_BLACK
  -- (engine/gfx/palettes.asm:22-25); picImage re-bakes through it (#292).
  if self.blackedOut and pals.BLACK then
    local b = PaletteFX.usesYellowCgb() and pals.BLACK
              or PaletteFX.pal(self.data, "BLACK") or pals.BLACK
    return { [0] = b, [1] = b, [2] = b, [3] = b }
  end
  -- home/palettes.asm:38
  local function bar(b)
    if not b then
      return PaletteFX.pal(self.data, "GREENBAR") or pals.GREENBAR
    end
    local hp = b.shownHP or b.mon.hp
    return PaletteFX.pal(self.data,
                         PaletteFX.barPalName(hp, b.mon.stats.hp, b.shownPx))
           or pals.GREENBAR
  end
  local function mon(b, placeholder)
    if placeholder or not b then
      if PaletteFX.usesYellowCgb() then return pals.MEWMON or pals.GREENBAR end
      return PaletteFX.pal(self.data, "MEWMON") or pals.MEWMON or pals.GREENBAR
    end
    return PaletteFX.monPal(self.data, b.mon.species) or pals.MEWMON
  end
  local out = {
    [0] = bar(self.player),
    [1] = bar(self.enemy),
    [2] = mon(self.player, self.showPlayerBack or self.safari or self.demo),
    [3] = mon(self.enemy, self.showEnemyTrainer),
  }
  return out
end

-- the SGB palette covering a screen pixel (BlkPacket_Battle regions)
function BattleState:zoneColorsAt(x, y)
  local pals = self:sgbBattlePals()
  if not pals then return nil end
  local tx = math.floor(x / 8)
  local ty = math.floor(y / 8)
  if ty >= 12 then return pals[2] end                      -- message box
  if tx >= 11 and ty <= 6 then return pals[3] end          -- enemy mon
  if tx <= 8 and ty >= 4 and ty <= 11 then return pals[2] end -- player mon
  if tx >= 1 and tx <= 10 and ty <= 3 then return pals[1] end -- enemy HUD
  return pals[0]
end

-- AnimationWavyScreen's per-scanline SCX offsets
-- (WavyScreenLineOffsets, animations.asm:1926)
local WAVY_OFFSETS = { 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1,
                       0, 0, 0, 0, 0, -1, -1, -1, -2, -2, -2, -2, -2,
                       -1, -1, -1 }

-- wave the BG canvas one scanline at a time; the offset table walks
-- one entry per frame like the asm's advancing pointer
function BattleState:applyWavy(src)
  local wavy = self.fx and self.fx.wavy
  if not wavy then return src end
  local g = love.graphics
  local prev = g.getCanvas()
  g.setCanvas(self.waveCanvas)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", 0, 0, 160, 144)
  self.waveQuad = self.waveQuad or g.newQuad(0, 0, 160, 1, 160, 144)
  for line = 0, 143 do
    self.waveQuad:setViewport(0, line, 160, 1)
    g.draw(src, self.waveQuad,
           WAVY_OFFSETS[(line + wavy.phase) % 32 + 1], line)
  end
  g.setCanvas(prev)
  return self.waveCanvas
end

-- recolor the grayscale BG canvas per zone; an active BGP fade permutes
-- the zone palette (the SGB colors the remapped DMG shade).  A window
-- shake draws only the offset copy: the baked canvas holds the HUDs and
-- text box (window-layer content), so compositing an unshifted copy
-- underneath ghosted every name in the vacated strip (#295).  The strip
-- shows blank color 0 instead, like the hardware revealing empty BG.
function BattleState:drawZonePass(src, sx, sy)
  local PaletteFX = require("src.render.PaletteFX")
  local shader = PaletteFX.shader()
  local pals = self:sgbBattlePals()
  local bgp = self:activeBgp()
  -- #822: OG / OG INV / CLASSIC are forced-mono modes, so sgbPalettes() being
  -- nil here makes PaletteFX.ensureZones invent a whole-screen zone and the
  -- WHOLE finished frame is re-thresholded through the shade shader at blit
  -- time -- which is why picImage already hands those modes raw DMG grays.
  -- This pass has to leave DMG shades behind for the same reason: sendColors
  -- runs the mode substitution HERE too, and the frame-level pass then
  -- substitutes a second time.  OG INV inverts twice and comes out upright;
  -- CLASSIC's color 0 (155,188,15) has red 0.61, which falls in the shader's
  -- c1 bucket, so the paper darkens one shade.  Either way the battle stops
  -- matching the YES/NO box an overlay state draws over it, since that box
  -- only ever sees the frame-level pass.  OG is the identity, which is why
  -- only the other two showed it.  Keep this mode set in sync with picImage /
  -- PaletteFX.ensureZones / WideBattle.monoMode.
  local mono = PaletteFX.mode == "og" or PaletteFX.mode == "og_inv"
               or PaletteFX.mode == "classic"
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(shader)
  local shaking = sx ~= 0 or sy ~= 0
  for _, z in ipairs(BATTLE_ZONES) do
    if mono then
      -- the BGP fade still runs, just in gray: the frame-level pass colors
      -- whatever DMG shade this leaves behind
      PaletteFX.sendShades(shader, PaletteFX.permute(PaletteFX.GRAYS, bgp))
    else
      PaletteFX.sendColors(shader, PaletteFX.permute(pals[z.pal], bgp))
    end
    local zx, zy = z[1] * 8, z[2] * 8
    local zw, zh = (z[3] - z[1] + 1) * 8, (z[4] - z[2] + 1) * 8
    love.graphics.setScissor(zx, zy, zw, zh)
    if shaking then
      love.graphics.rectangle("fill", zx, zy, zw, zh)
      love.graphics.draw(src, sx, sy)
    else
      love.graphics.draw(src, 0, 0)
    end
  end
  love.graphics.setScissor()
  love.graphics.setShader()
end

-- SetAnimationPalette (engine/battle/animations.asm:551): wAnimPalette = $f0
-- on SGB, $e4 otherwise; rOBP1 = $6c either way
local OBJ_SHADES = {
  f0 = { 0, 3, 3 },   -- color 1 -> shade 0, colors 2/3 -> shade 3
  f0x = { 3, 0, 3 },  -- $f0 xor %00111100 = $cc (DoBallTossSpecialEffects,
                      -- engine/battle/animations.asm:685)
  e4 = { 1, 2, 3 },   -- identity
  e4x = { 2, 1, 3 },  -- $e4 xor %00111100 = $d8
  obp1 = { 3, 2, 1 }, -- $6c
}
function BattleState:animSpriteColors(s, px, py)
  local PaletteFX = require("src.render.PaletteFX")
  local key = s.obp or "f0"
  local P
  -- engine/battle/animations.asm:551 (.notSGB)
  if PaletteFX.usesSpriteObp() then
    P = PaletteFX.ogObj()
    if key == "f0" then key = "e4" elseif key == "f0x" then key = "e4x" end
  else
    P = self:zoneColorsAt(px or (s.x - 8 + 4), py or (s.y - 16 + 4))
  end
  if not P then return nil end
  local m = OBJ_SHADES[key] or OBJ_SHADES.f0
  local function c(shade)
    local col = P[shade + 1]
    return { col[1] / 255, col[2] / 255, col[3] / 255 }
  end
  return { c(m[1]), c(m[2]), c(m[3]) }
end

-- the OAM anim layer (subanimation sprites / the resting caught ball)
function BattleState:drawAnimLayer(colorized)
  local colorFn
  if colorized then
    colorFn = function(s, px, py) return self:animSpriteColors(s, px, py) end
  end
  if self.animPlaying and self.animPlayer then
    love.graphics.setColor(1, 1, 1, 1)
    pcall(self.animPlayer.draw, self.animPlayer, colorFn)
  elseif self.lockedBall and self.animPlayer then
    -- the resting closed ball stays on screen through the caught text
    -- (the $43 chain ends after SHAKE_ANIM and the GB never clears the
    -- ball's OAM entries until the battle screen is torn down)
    love.graphics.setColor(1, 1, 1, 1)
    pcall(self.animPlayer.drawSprites, self.animPlayer, self.lockedBall,
          colorFn)
  end
end

-- ------------------------------------------------------------------
-- Mod-facing battle sprite scaling.  The enemy front pic draws at 1x and
-- the player back pic at 2x on the GB; a mod can override either per
-- species (pokemon.battleScaleFront / battleScaleBack) or per image path
-- (the battle_sprite_scales registry, which is the only handle on the
-- non-species pics like the trainer back).  These resolvers and the
-- placement math are pure (no love.*) so the grounding contract -- feet
-- pinned at any scale -- is unit-tested directly.
-- ------------------------------------------------------------------

-- the vanilla scale for a side: enemy front 1x, player back 2x
BattleState.BATTLE_SCALE_DEFAULT = { front = 1, back = 2 }

-- image-level override for an asset path, or nil.  scales is the merged
-- data.battle_sprite_scales table (record id -> { path, scale }).
function BattleState.imageBattleScale(scales, path)
  if not scales or not path then return nil end
  for id, rec in pairs(scales) do
    if id ~= "_owners" and type(rec) == "table" and rec.path == path then
      return rec.scale
    end
  end
  return nil
end

-- effective battle scale for a pic: image-level override, else the
-- species-level override for the side, else the side default.  side is
-- "front" (enemy) or "back" (player); species may be nil (a non-species
-- pic like the trainer back, which only image-level scaling reaches).
function BattleState.resolveBattleScale(data, side, path, species)
  local img = data and BattleState.imageBattleScale(data.battle_sprite_scales, path)
  if img then return img end
  local def = species and data and data.pokemon and data.pokemon[species]
  local field = side == "back" and "battleScaleBack" or "battleScaleFront"
  local override = def and def[field]
  if override then return override end
  return BattleState.BATTLE_SCALE_DEFAULT[side] or 1
end

-- Player (back) placement: feet flush on the text-box top (y=96) at any
-- scale, with the left transparent columns pulled back so opaque pixels
-- land where hardware's white-on-white columns left them.  Returns the
-- top-left x, y and the scale (slide/shake offsets are added by the
-- caller).  Feet stay at 96 for every scale: y + (h - pad) * scale == 96.
function BattleState.backPlacement(w, h, pad, padL, scale)
  return 8 - padL * scale, 96 - (h - pad) * scale, scale
end

-- Enemy (front) placement: given the s=1 slot origin (ex, ey) from the
-- 7x7 tile layout, keep the bottom edge and horizontal centre pinned as
-- the pic scales -- the same compensation AnimateSendingOutMon's grow
-- uses.  Returns top-left x, y and the scale.  The bottom edge stays put
-- for every scale: y + h * scale == ey + h.
function BattleState.frontPlacement(ex, ey, w, h, scale)
  return ex + w * (1 - scale) / 2, ey + h * (1 - scale), scale
end

-- Front/trainer pics: LoadUncompressedSpriteData centers the sprite in
-- a 7x7 tile buffer, then CopyUncompressedPicToTilemap places that
-- buffer at hlcoord 12,0.  Horizontal pad is floor((8-w)/2) tiles;
-- vertical pad is (7-h) -- bottom-aligned inside the 7x7.
local function enemyPicXY(img, slide, sx, sy)
  local tw = math.floor(img:getWidth() / 8)
  local th = math.floor(img:getHeight() / 8)
  if tw < 1 then tw = 1 elseif tw > 7 then tw = 7 end
  if th < 1 then th = 1 elseif th > 7 then th = 7 end
  local hPad = math.floor((8 - tw) / 2)
  local vPad = 7 - th
  return 96 + 8 * hPad - slide + sx, 8 * vPad + sy
end

-- the two mon pics (or the trainer/back pics), offset by the window
-- shake -- on the GB the pics are BG tiles, so they move with it
-- onlySide ("player" / "enemy") draws one side's pic alone, and
-- skipMenuClip drops the move-menu row clip below: the widescreen layout
-- composites each side into its own region of a taller battlefield, where
-- neither the other side's pixels nor the classic menu rows apply.
function BattleState:drawPicsLayer(slide, sx, sy, onlySide, skipMenuClip)
  -- The move-select boxes are BG tiles on the GB, so they REPLACE the
  -- player pic's rows: the TYPE/PP box at (0,8) (PrintMenuItem) wipes
  -- pic rows 8+, and Mimic's copy menu at (0,7) (MoveSelectionMenu
  -- .mimicmenu) wipes rows 7+.  The port draws pics above the menu
  -- layer in the colorized pipeline, so clip them to the visible rows.
  local g = love.graphics
  local clipY = not skipMenuClip and self:bottomUIVisible()
                and (self.phase == "mimicSelect" and 56
                     or self.phase == "moveSelect" and 64)
                or nil
  local clipped, cs1, cs2, cs3, cs4
  if clipY and g.getScissor and g.intersectScissor then
    cs1, cs2, cs3, cs4 = g.getScissor()
    g.intersectScissor(0, 0, 160, clipY)
    clipped = true
  end
  -- Enemy: front sprite in the 7x7 slot at hlcoord 12,0.
  if onlySide ~= "player" and self.showEnemyTrainer and self.trainerPic then
    -- the enemy trainer pic holds the mon slot until the send-out
    local img = self:picImage(self.trainerPic)
    love.graphics.setColor(1, 1, 1, 1)
    local ex, ey = enemyPicXY(img, slide, sx, sy)
    -- SlideTrainerPicOffScreen / _ScrollTrainerPicAfterBattle offset (#317)
    love.graphics.draw(img, ex + self:picOffset("foe"), ey)
  elseif onlySide ~= "player"
     and self.enemy and self.enemy.sprite and not self.enemyHidden
     and not self.enemySendingOut and not self:fxHidden(self.enemy) then
    local img = self:picImage(self.enemy.sprite)
    love.graphics.setColor(1, 1, 1, 1)
    local ex, ey = enemyPicXY(img, slide, sx, sy)
    local s = BattleState.resolveBattleScale(self.data, "front",
      imagePathOf(img), self.enemy.mon and self.enemy.mon.species)
    local gs = self:growInScale(self.enemy)
    if gs then
      -- AnimateSendingOutMon: the downscaled pic keeps its bottom edge
      -- and horizontal center pinned to the mon's slot while it grows --
      -- the mod scale composes multiplicatively with the grow stage
      local eff = s * gs
      if eff > 0 then
        local dx, dy = BattleState.frontPlacement(ex, ey,
          img:getWidth(), img:getHeight(), eff)
        love.graphics.draw(img, dx, dy, 0, eff, eff)
      end
    else
      local dx, dy = BattleState.frontPlacement(ex, ey,
        img:getWidth(), img:getHeight(), s)
      self:drawBattlerPic(self.enemy, dx, dy, s)
    end
  end

  -- Player: back sprite at hlcoord 1,5 (x=8), 2x like the GB, feet at y=96.
  -- Left transparent columns (matted white) are pulled back so opaque
  -- pixels land where hardware's white-on-white columns left them.
  local hidePlayer = self.safari or self.demo
  if onlySide ~= "enemy" and self.showPlayerBack and self.playerBackPic then
    -- Red's (or the old man's) back pic until "Go!"; it stays up for
    -- the whole safari / catch-demo battle like the original
    local img = self:picImage(self.playerBackPic)
    local pad = imagePadBottom[self.playerBackPic] or 0
    local padL = imagePadLeft[self.playerBackPic] or 0
    -- the trainer back is a bare pic, not species-keyed, so only an
    -- image-level battle_sprite_scales entry can rescale it
    local s = BattleState.resolveBattleScale(self.data, "back",
      imagePathOf(self.playerBackPic), nil)
    love.graphics.setColor(1, 1, 1, 1)
    local dx, dy = BattleState.backPlacement(img:getWidth(), img:getHeight(),
      pad, padL, s)
    -- picOffset: SlideTrainerPicOffScreen walking the back pic off the left
    love.graphics.draw(img, dx + slide + sx + self:picOffset("back"),
                       dy + sy, 0, s, s)
  elseif onlySide ~= "enemy"
     and self.player and self.player.sprite and not hidePlayer
     and not self.sendingOut and not self:fxHidden(self.player) then
    local img = self:picImage(self.player.sprite)
    love.graphics.setColor(1, 1, 1, 1)
    -- feet flush on the text box top (y=96), ignoring baked-in padding
    local pad = imagePadBottom[self.player.sprite] or 0
    local padL = imagePadLeft[self.player.sprite] or 0
    local s = BattleState.resolveBattleScale(self.data, "back",
      imagePathOf(self.player.sprite),
      self.player.mon and self.player.mon.species)
    local gs = self:growInScale(self.player) or self:shrinkOutScale(self.player)
    if gs then
      -- the player-side AnimateSendingOutMon grow (core.asm:1757-1762) and
      -- the AnimateRetreatingPlayerMon shrink (core.asm:1769-1796)
      local eff = s * gs
      if eff > 0 then
        -- the retreat stages sit one tile right of the grow-in's
        -- (hlcoord 3,7 / 4,9 vs 2,7 / 3,9, core.asm:1770-1788) (#1563)
        local shrinkX = self.shrinkOut
          and self.shrinkOut.battler == self.player and 8 or 0
        love.graphics.draw(img,
          8 + shrinkX - padL * s + img:getWidth() * s * (1 - gs) / 2 + sx,
          96 - (img:getHeight() - pad) * eff + sy, 0, eff, eff)
      end
    else
      local dx, dy = BattleState.backPlacement(img:getWidth(),
        img:getHeight(), pad, padL, s)
      -- picOffset: StarterPikachuBattleEntranceAnimation walking the pic in
      -- from the left -- engine/battle/pikachu_entrance_anim.asm:1
      self:drawBattlerPic(self.player, dx + sx + self:picOffset("playerMon"),
                          dy + sy, s)
    end
  end
  if clipped then
    if cs1 then
      g.setScissor(cs1, cs2, cs3, cs4)
    else
      g.setScissor()
    end
  end
end

-- the BG-tile UI: HUDs, pokeball rows, safari ball count.  Grayscale;
-- the zone pass colors it in colorized mode.
function BattleState:drawHUDs(slide)
  -- the HUD clears with the send-out text (ClearScreenArea,
  -- core.asm:1414-1417) and DrawEnemyHUDAndHPBar (1435) only redraws
  -- it after the grow-in + cry
  -- In colorized modes the zone pass (drawZonePass over BATTLE_ZONES pal 0/1)
  -- recolors the bar's DMG gray fill by region, so drawHPBar must skip its
  -- per-pixel tint (grayFill) -- otherwise GREENBAR's red-channel-0 fill
  -- double-applies and the zone shade shader maps the whole bar to black (#229).
  local grayFill = self:colorMode()
  local showStatus = self:statusHUDVisible()
  local barData = self.data
  local fx = self.fx
  local hudShake = (fx and fx.hudShakeX) or 0
  -- FaintEnemyPokemon clears the enemy HUD area; it stays blank through
  -- TrainerAboutToUseText until DrawEnemyHUDAndHPBar after the next send-out
  -- ...and it is not up yet during the intro text either: a wild battle's
  -- DrawEnemyHUDAndHPBar is called from _InitBattleCommon (core.asm:6763)
  -- AFTER PrintBeginningBattleText returns, so "Wild X appeared!" shows the
  -- player's ball row with no enemy HUD beside it (#317)
  if showStatus and self.enemy and not self.showEnemyTrainer
     and not self.enemySendingOut
     and not self:growInScale(self.enemy) and slide == 0
     and not self.introBalls and not self.enemy.fainted then
    -- enemy HUD (DrawEnemyHUDAndHPBar): name row 0, <LV>+level (4,1),
    -- HP bar (2,2) with the vertical tick at (1,2), underline row 3;
    -- AnimationShakeEnemyHUD nudges just this block via SCX
    if hudShake ~= 0 then
      love.graphics.push()
      love.graphics.translate(hudShake, 0)
    end
    love.graphics.setColor(0, 0, 0, 1)
    local enemyNameX = nameX(1, self.enemy.name)
    local enemyNameWidth = Font.draw(self.enemy.name, enemyNameX, 0)
    if self:caughtMarkerVisible() then
      self:drawCaughtBall(enemyNameX + enemyNameWidth, 0)
      love.graphics.setColor(0, 0, 0, 1)
    end
    if self.enemy.shownStatus then
      Font.draw(self:statusLabel({ status = self.enemy.shownStatus }), 40, 8)
    else
      hudTile(0x6E, 32, 8) -- <LV>
      Font.draw(tostring(self.enemy.mon.level), 40, 8)
    end
    hudTile(0x73, 8, 16)
    drawHPBar(barData, 2, 2,
              { hp = shownHP(self.enemy), stats = self.enemy.mon.stats },
              nil, grayFill, nil, self.enemy.shownPx)
    hudTile(0x74, 8, 24)
    for i = 2, 9 do hudTile(0x76, i * 8, 24) end
    hudTile(0x78, 80, 24)
    if hudShake ~= 0 then
      love.graphics.pop()
    end
  end

  -- ReplaceFaintedEnemyMon -> DrawEnemyPokeballs (core.asm:896,
  -- draw_hud_pokeball_gfx.asm:9-11 -> SetupEnemyPartyPokeballs :33-45):
  -- between a KO and the next send-out the foe's ball row sits in the enemy
  -- HUD block FaintEnemyPokemon cleared, over the chrome PlaceEnemyHUDTiles
  -- writes with it -- the same $73 (1,2) / $74 (1,3) / $76 run / $78 tiles
  -- the live HUD draws, minus the HP bar (#283).  Its own block rather than
  -- a third arm of showIntroBalls below: that window is DrawAllPokeballs's
  -- (#317) and clears for the rest of the battle, this one reopens on every
  -- enemy faint.  wBaseCoordX $48 / wBaseCoordY $20 stepping -8 is screen
  -- (64,16) leftward, the same row the intro draws.
  if self.showEnemyBalls and self.enemyParty and slide == 0 then
    hudTile(0x73, 8, 16)
    hudTile(0x74, 8, 24)
    for i = 2, 9 do hudTile(0x76, i * 8, 24) end
    hudTile(0x78, 80, 24)
    love.graphics.setColor(1, 1, 1, 1)
    self:drawBallRow(self.enemyParty, 64, 16, -8)
  end

  -- A safari / old-man battle has no player mon out, so no player HUD (see
  -- hidePlayer below).  Nothing takes its place: PrintSafariZoneSteps -- the
  -- "nnn/500 / BALLx nn" box -- is start-menu only and returns early off the
  -- nine interior maps (engine/overworld/player_state.asm:219-224), so no
  -- ball count belongs over the battlefield.  The count lives in the BALL
  -- menu item instead (drawTextArea, #540).
  -- Party pokeball rows and the HUD chrome under them, for exactly the
  -- window DrawAllPokeballs owns (common_text.asm:27, with the intro text).
  -- SetupOwnPartyPokeballs runs in EVERY battle, so the player's row belongs
  -- on the wild intro too -- keying it off the enemy trainer pic meant a
  -- wild battle never drew one (#317) -- and SetupEnemyPartyPokeballs is
  -- skipped when wIsInBattle == 1, so only a trainer/link battle gets the
  -- foe's row.  Gating on introBalls rather than on the pics also stops the
  -- rows coming back when the beaten trainer scrolls in (#282):
  -- _ScrollTrainerPicAfterBattle redraws tilemap columns and never touches
  -- OAM, which ClearSprites emptied when the intro text was dismissed.
  local showIntroBalls = self.introBalls and slide == 0
  if showIntroBalls then
    if self.enemyParty and (self.kind == "trainer" or self.kind == "link") then
      -- PlaceEnemyHUDTiles (hlcoord 1,2): $73, then $74 + 8x $76 + $78
      -- rightward along row 3 (draw_hud_pokeball_gfx.asm:133-165)
      hudTile(0x73, 8, 16)
      hudTile(0x74, 8, 24)
      for i = 2, 9 do hudTile(0x76, i * 8, 24) end
      hudTile(0x78, 80, 24)
      love.graphics.setColor(1, 1, 1, 1)
      self:drawBallRow(self.enemyParty, 64, 16, -8)
    end
    -- PlacePlayerHUDTiles (hlcoord 18,10): $73, then $77 + 8x $76 + $6F
    -- LEFTWARD along row 11 (draw_hud_pokeball_gfx.asm:119-131)
    hudTile(0x73, 144, 80)
    hudTile(0x77, 144, 88)
    for i = 10, 17 do hudTile(0x76, i * 8, 88) end
    hudTile(0x6F, 72, 88)
    love.graphics.setColor(1, 1, 1, 1)
    self:drawBallRow(self:playerPartyView(), 88, 80, 8)
  end
  local hidePlayer = self.safari or self.demo
  if showStatus and self.player and not hidePlayer and not self.showPlayerBack
     and slide == 0 then
    -- player HUD (DrawPlayerHUDAndHPBar): name (10,7), <LV>+level
    -- (14,8), HP bar (10,9), HP numbers row 10, underline row 11 with
    -- the tick at (18,10) and the triangle at (9,11)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.player.name, nameX(10, self.player.name), 56)
    if self.player.shownStatus then
      Font.draw(self:statusLabel({ status = self.player.shownStatus }), 120, 64)
    else
      hudTile(0x6E, 112, 64) -- <LV>
      Font.draw(tostring(self.player.mon.level), 120, 64)
    end
    drawHPBar(barData, 10, 9,
              { hp = shownHP(self.player), stats = self.player.mon.stats },
              1, grayFill, nil, self.player.shownPx) -- wHPBarType 1: the $6D cap
    Font.draw(("%3d/%3d"):format(shownHP(self.player), self.player.mon.stats.hp), 88, 80)
    hudTile(0x73, 144, 80)
    hudTile(0x77, 144, 88)
    for i = 10, 17 do hudTile(0x76, i * 8, 88) end
    hudTile(0x6F, 72, 88)
  end
end

function BattleState:drawTextArea()
  if not self:bottomUIVisible() then return end
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  if self.phase == "messages"
     and (self.current or self.animPlaying or self.msgHold) then
    -- during the move animation self.current is nil but shown still holds
    -- the "used X!" lines; keep drawing them like pokered, whose move
    -- animations only touch sprites and never the textbox tilemap (#296)
    -- rolling 2-line window: shown[1] at row y=112, shown[2] at y=128 (battle
    -- text uses every other tile row, hlcoord *,14 / *,16).  scrollPx animates
    -- the lines up one row (ScrollTextUpOneLine) so a 3rd line scrolls into
    -- view instead of drawing off-screen at y=144 (#216).
    if self.scrollPx and self.scrollPx > 0 then
      self.scrollPx = self.scrollPx - 2
      if self.scrollPx <= 0 then self.scrollPx = nil end
    end
    local off = self.scrollPx or 0
    local ys = { 112, 128 }
    for li, line in ipairs(self.shown or {}) do
      local y = (ys[li] or 128) + off
      for i = 1, #line do
        Font.drawCode(line[i], 8 + (i - 1) * 8, y)
      end
    end
    -- the blinking down arrow ('▼', glyph $EE) while a \v CONT wait
    -- (_ContText) or a typed-out page (PromptText) holds the box; both write
    -- it at (18,16), bottom-right, like TextBox / home/text.asm (#317)
    if (self.msgWaiting or self.msgPrompt) and self.frame % 60 < 30 then
      Font.drawCode(0xEE, (0 + 20 - 2) * 8, (12 + 6 - 1) * 8 - 4)
    end
  elseif self.phase == "menu" and self.demo then
    -- the old-man script (DisplayBattleMenu, core.asm:2038-2049): the
    -- standard menu, with the '▶' hand drawn by the scripted keystrokes
    -- -- next to FIGHT (9,14) for the first 80 frames, then ITEM (9,16)
    Font.drawBox(8, 12, 12, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("FIGHT", "battle"), 80, 112)
    Font.drawCode(0xE1, 128, 112); Font.drawCode(0xE2, 136, 112)
    Font.draw(Strings("ITEM", "battle"), 80, 128); Font.draw(Strings("RUN", "battle"), 128, 128)
    Font.drawCode(0xED, 72, (self.demoTimer or 0) <= 80 and 112 or 128)
  elseif self.phase == "menu" then
    local col = (self.menuIndex - 1) % 2
    local row = math.floor((self.menuIndex - 1) / 2)
    if self.safari then
      -- SAFARI_BATTLE_MENU_TEMPLATE: full-width box, "BALLx  BAIT /
      -- THROW ROCK  RUN" from (2,14)
      Font.drawBox(0, 12, 20, 6)
      Font.draw(Strings("BALLx"), 16, 112); Font.draw(Strings("BAIT"), 112, 112)
      Font.draw(Strings("THROW ROCK"), 16, 128); Font.draw(Strings("RUN", "battle"), 112, 128)
      -- DisplayBattleMenu .safariLeftColumn / .safariRightColumn print
      -- wNumSafariBalls at hlcoord 7,14 with `lb bc, 1, 2` -- one byte, two
      -- digits, space padded -- right after the "BALLx" label at columns
      -- 2..6 (engine/battle/core.asm:2074-2079, 2107-2112) (#540)
      Font.draw(("%2d"):format(self.safari.balls), 56, 112)
      Font.drawCode(0xED, (col == 0 and 8 or 104), 112 + row * 16)
    else
      -- BATTLE_MENU_TEMPLATE: box (8,12)-(19,17), "FIGHT <PK><MN> /
      -- ITEM  RUN" from (10,14); cursor columns 9 / 15
      Font.drawBox(8, 12, 12, 6)
      Font.draw(Strings("FIGHT", "battle"), 80, 112)
      Font.drawCode(0xE1, 128, 112); Font.drawCode(0xE2, 136, 112)
      Font.draw(Strings("ITEM", "battle"), 80, 128); Font.draw(Strings("RUN", "battle"), 128, 128)
      Font.drawCode(0xED, (col == 0 and 72 or 120), 112 + row * 16)
    end
  elseif self.phase == "moveSelect" then
    -- pokered MoveSelectionMenu: move list in a box at (4,12) 16x6,
    -- names at column 6 from row 13, cursor at column 5.  PrintMenuItem:
    -- the TYPE/PP box at (0,8) 11x5, with "TYPE/" at (1,9), the type at
    -- (2,10) and "PP cur/max" at (5,11); its bottom border merges into
    -- the move box's top border ('─' at (4,12), '┘' at (10,12)).
    Font.drawBox(0, 8, 11, 5)
    Font.drawBox(4, 12, 16, 6)
    -- Those two cells are REPLACED on hardware: MoveSelectionMenu writes them
    -- straight into the tilemap over the border it just laid down
    -- (core.asm:2492-2501), and PrintMenuItem's own TextBoxBorder then redraws
    -- the whole row on top (core.asm:2838-2844).  Font.drawCode blits a
    -- black-on-transparent glyph instead, so the tile underneath survives: the
    -- move box's '┌' keeps its Poké Ball corner showing through the '─', and
    -- the '─' the move box drew at (10,12) pokes two dots out from under the
    -- '┘' (#240).  Wipe each cell back to box white first, the way a tilemap
    -- write does.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 32, 96, 8, 8)
    love.graphics.rectangle("fill", 80, 96, 8, 8)
    Font.drawCode(Font.BORDER.h, 32, 96)
    Font.drawCode(Font.BORDER.br, 80, 96)
    love.graphics.setColor(0, 0, 0, 1)
    -- engine/battle/misc.asm:37
    for i = 1, 4 do
      local mv = self.player.curMoves[i]
      if mv then
        -- unknown ids (mod-injected moves) print raw instead of crashing
        local def = self.data.moves[mv.id]
        Font.draw(def and def.name or tostring(mv.id), 48, 96 + i * 8)
      else
        Font.draw("-", 48, 96 + i * 8)
      end
    end
    -- Swap cursor: SelectMenuItem parks the hollow arrow on the marked row
    -- (core.asm:2600-2607), then HandleMenuInput's PlaceMenuCursor writes the
    -- filled arrow into the tilemap over it whenever the cursor sits there
    -- (home/window.asm:184-185), so the current row is always filled.  Only
    -- one glyph may land per cell -- drawCode blits black-on-transparent, so
    -- stacking 0xED over 0xEC would merge the two arrows (#814).
    Font.drawCode(0xED, 40, 96 + self.moveIndex * 8)
    if self.moveSwapIndex and self.moveSwapIndex ~= self.moveIndex then
      Font.drawCode(0xEC, 40, 96 + self.moveSwapIndex * 8)
    end
    local sel = self.player.curMoves[self.moveIndex]
    if sel then
      local def = self.data.moves[sel.id]
      if self.player.disabledSlot == self.moveIndex then
        Font.draw(Strings("disabled!"), 8, 80)
      elseif def then
        Font.draw(Strings("TYPE/"), 8, 72)
        -- the type record's display name (a mod type shows its name, and
        -- PSYCHIC_TYPE prints PSYCHIC like the original)
        Font.draw(def.type and TypeChart.displayName(def.type) or "", 16, 80)
        local maxPP = def.pp + (sel.ppUps or 0) * math.floor(def.pp / 5)
        Font.draw(("%2d/%2d"):format(sel.pp, maxPP), 40, 88)
      end
    end
  elseif self.phase == "mimicSelect" then
    -- Mimic's copy menu (MoveSelectionMenu .mimicmenu, core.asm:2506-2517):
    -- 16x6 box at (0,7), names from (2,8), cursor at column 1
    Font.drawBox(0, 7, 16, 6)
    love.graphics.setColor(0, 0, 0, 1)
    -- engine/battle/misc.asm:37
    for i = 1, 4 do
      local m = self.mimicMoves[i]
      local def = m and self.data.moves[m.id]
      Font.draw(m and (def and def.name or tostring(m.id)) or "-",
        16, (7 + i) * 8)
    end
    Font.drawCode(0xED, 8, (7 + self.mimicIndex) * 8)
    Font.draw(Strings("WHICH TECHNIQUE?"), 8, 112)
  end
end

function BattleState:draw()
  if self:wideLayout() then return WideBattle.draw(self) end
  return self:drawClassic()
end

function BattleState:drawClassic()
  -- AskName: ClearSprites + wild ClearScreenArea -- white field under the
  -- nickname TextBox / YES/NO (naming_screen.asm); overlays draw on top.
  if self.blankForAskName then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    return
  end
  local fx = self.fx
  -- window shakes (SE_SHAKE_SCREEN / the enemy-hit vertical shake);
  -- the animations-off fallback keeps the old +-2 alternation
  local sx = (fx and fx.shakeX) or 0
  local sy = (fx and fx.shakeY) or 0
  if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
    sx = self.frame % 4 < 2 and 2 or -2
  end
  -- intro slide-in offset: 2 px per frame, so 144 px over 72 frames
  local slide = (self.introSlide or 0) * Timing.BATTLE_SLIDE_PX_PER_FRAME

  if self:colorMode() then
    -- SGB pipeline: gray BG canvas -> (wavy) -> zone recolor with the
    -- BGP fade -> mon pics -> OAM anim sprites (never BGP-faded)
    local g = love.graphics
    local prev = g.getCanvas()
    local wavy = fx and fx.wavy
    g.setCanvas(self.bgCanvas)
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 0, 0, 160, 144)
    self:drawHUDs(slide)
    self:drawTextArea()
    if wavy then
      -- the mon pics are BG tiles on the GB, so SE_WAVY_SCREEN bends
      -- them too: bake them into the canvas as DMG grays and let the
      -- zone pass color them by region (exactly what the SGB did)
      self.grayPics = true
      g.setScissor(0, 0, 160, 96) -- BG pics live above the text box
      self:drawPicsLayer(slide, 0, 0)
      g.setScissor()
      self.grayPics = nil
    end
    g.setCanvas(prev)
    self:drawZonePass(self:applyWavy(self.bgCanvas), sx, sy)
    if not wavy then
      -- the pics are BG tiles in rows 0-11 on the GB: they can never
      -- cover the text box, whatever the SE offsets do (a vertical
      -- window shake moves the box down with everything else)
      g.setScissor(0, 0, 160, 96 + math.max(0, sy))
      self:drawPicsLayer(slide, sx, sy)
      g.setScissor()
    end
    self:drawAnimLayer(true)
  else
    -- flat fallback (headless / no shader support): pre-colorized pics
    -- on white, no palette fades
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    local shaking = sx ~= 0 or sy ~= 0
    if shaking then
      love.graphics.push()
      love.graphics.translate(sx, sy)
    end
    self:drawPicsLayer(slide, 0, 0)
    self:drawHUDs(slide)
    self:drawAnimLayer(false)
    self:drawTextArea()
    if shaking then
      love.graphics.pop()
    end
  end
  -- screen flash (flash-effect moves without the subanimation player):
  -- white flicker overlay
  if fx and fx.flash and fx.flash > 0 and self.frame % 4 < 2 then
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
  end
  love.graphics.setColor(1, 1, 1, 1)
  -- battle.overlay: shiny sparkles, custom HUD chrome, etc.  Draw-only;
  -- the vanilla link is a no-op so an empty chain costs nothing.
  if Runtime.wantsHook("battle.overlay") then
    Runtime.call("battle.overlay", function() end, self)
  end
end

return BattleState
