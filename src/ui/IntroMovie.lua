-- ..(engine/movie/intro.asm ln 8)
-- ..(engine/movie/splash.asm ln 27)

local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Timing = require("src.core.Timing")
local FaithfulRes = require("src.core.FaithfulRes")
local TouchSkin = require("src.core.TouchSkin")

local IntroMovie = {}
IntroMovie.__index = IntroMovie
IntroMovie.isOpaque = true

-- Same as the title screen: full-bleed art, no world behind it, no player zoom
-- to respect, so fill the window rather than sit at the fixed integer scale.
function IntroMovie:wantsFillScale()
  if FaithfulRes.locked then return false end
  if TouchSkin.drawable() then return false end
  return true
end

-- SGB intro palettes: the splash uses PalPacket_GameFreakIntro (logo
-- GAMEFREAK, falling star columns RED/VIRIDIAN/BLUEMON), the attract
-- fight PalPacket_NidorinoIntro (PURPLEMON letterbox, BLACK bars)
function IntroMovie:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  if self.phase == 1 and (self.studio.card or self.studio.credit) then
    return nil
  end
  -- engine/movie/intro.asm:306
  if self.phase == 1 or self.phase == 2 then
    local logo = P.pal(game.data, "GAMEFREAK")
    if not logo then return nil end
    return {
      P.whole(logo),
      P.zone(P.pal(game.data, "REDMON"), 5, 11, 7, 13),
      P.zone(P.pal(game.data, "VIRIDIAN"), 8, 11, 9, 13),
      P.zone(P.pal(game.data, "BLUEMON"), 12, 11, 14, 13),
    }
  elseif self.phase == 3 then
    local purple = P.pal(game.data, "PURPLEMON")
    if not purple then return nil end
    return {
      P.zone(P.pal(game.data, "BLACK"), 0, 0, 19, 3),
      P.zone(purple, 0, 4, 19, 13),
      P.zone(P.pal(game.data, "BLACK"), 0, 14, 19, 17),
    }
  end
  return nil
end

local COPYRIGHT_FRAMES = 180  -- ld c, 180 (intro.asm:311-312)

-- phase 2 (shooting star) timeline, in frames from phase start
local STAR_START = 64         -- ld c, 64 (intro.asm:323-324)
local STAR_FRAMES = 40        -- OAM Y 0->160 in +4 steps (splash.asm:32-60)
local FLASH_START = STAR_START + STAR_FRAMES
local FLASH_FRAMES = 30       -- 3 loops x 10 frames (splash.asm:72-82)
local WAVES_START = FLASH_START + FLASH_FRAMES
local WAVE_FRAMES = 24        -- 8 substeps x 3 frames (splash.asm:186-209)
local WAVES_END = WAVES_START + 6 * WAVE_FRAMES  -- 4 waves + 2 empty
local SPLASH_FRAMES = WAVES_END + 40  -- ld c, 40 (intro.asm:329-331)

-- After GBFadeOutToWhite, PlayIntro still DelayFrame's once (intro.asm:20)
-- and DisplayTitleScreen keeps GBPalWhiteOut through two
-- TitleScreenCopyTileMapToVRAM Delay3 waits (title.asm:136, 142) before
-- GBPalNormal and the logo bounce.  Without this hold the title drops in
-- the same breath as the fade.
local POST_FADE_WHITE = 1 + 3 + 3

-- ..(engine/movie/splash.asm ln 211)
local LOGO_X, LOGO_Y = 72, 56
local TEXT_X, TEXT_Y = 40, 80

-- engine/movie/splash.asm:72
local LOGO_OBP0 = { [0] = 0xF9, 0x7E, 0x9F, 0xE7 }
-- engine/movie/splash.asm:4
local STAR_OBP1 = 0xA4

local rampCache = setmetatable({}, { __mode = "k" })

local function obpRamp(obp, ramp)
  local byRamp = rampCache[ramp]
  if not byRamp then byRamp = {}; rampCache[ramp] = byRamp end
  local c = byRamp[obp]
  if not c then
    c = { ramp[1] }
    for i = 1, 3 do c[i + 1] = ramp[math.floor(obp / 4 ^ i) % 4 + 1] end
    byRamp[obp] = c
  end
  return c
end

local function romArt(path)
  return path and not path:find("^mods/") and path or nil
end

-- CopyrightTextString (engine/movie/title.asm).  Red/Blue years are
-- (c)'95.'96.'98; Yellow's sheet spells (c)1995-1999 and finishes the
-- last digit with NineTile (title screen).  Intro originally overflows
-- into the font "A" tile for that digit; we draw NineTile so both
-- screens read 1999.
local COPY_PREFIX_RB = { 0, 1, 2, 1, 3, 1, 4 }
local COPY_PREFIX_YELLOW = { 0, 1, 2, 3, 1, 2 }
local COPY_NINTENDO = { 5, 6, 7, 8, 9, 10 }
local COPY_CREATURES = { 11, 12, 13, 14, 15, 16, 17, 18 }

local STUDIO_BOX = { w = 128, h = 52, cx = 80, cy = 60 }

-- the 4 waves of small stars: screen X positions, all spawning at y=88
-- (OAM $68; SmallStarsWave*Coords, splash.asm:160-183)
local STAR_WAVES = {
  { 40, 56, 80, 112 },
  { 48, 64, 88, 104 },
  { 44, 68, 76, 92 },
  { 52, 84, 100, 108 },
}

-- Nidorino movement lists: {dy, dx} applied every 5 frames
-- (AnimateIntroNidorino, intro.asm:143-158)
local ANIM = {
  -- IntroNidorinoAnimation1..7 (intro.asm:370-437)
  { {0,0}, {-2,2}, {-1,2}, {1,2}, {2,2} },        -- 1: hop arc, +8 right
  { {0,0}, {-2,-2}, {-1,-2}, {1,-2}, {2,-2} },    -- 2: hop arc, -8 left
  { {0,0}, {-12,6}, {-8,6}, {8,6}, {12,6} },      -- 3: dodge leap, +24 right
  { {0,0}, {-8,-4}, {-4,-4}, {4,-4}, {8,-4} },    -- 4: high hop, -16 left
  { {0,0}, {-8,4}, {-4,4}, {4,4}, {8,4} },        -- 5: high hop, +16 right
  { {0,0}, {2,0}, {2,0}, {0,0} },                 -- 6: crouch, +4 down
  { {-8,-16}, {-7,-14}, {-6,-12}, {-4,-10} },     -- 7: lunge, -52/-25 up-left
}

-- PlayIntroScene, in source order (intro.asm:23-141).  `move` ops shift
-- 2px per 2 frames (IntroMoveMon, intro.asm:235-269): "scrollIn" moves
-- Nidorino right AND Gengar left together (the fallthrough at :247-259),
-- gengar dx<0 = MOVE_GENGAR_LEFT (SCX+2), dx>0 = MOVE_GENGAR_RIGHT.
local FIGHT_SCRIPT = {
  { move = "scrollIn", px = 80 },                       -- intro.asm:40-41
  { sfx = "Intro_Hip" }, { anim = 1 },                  -- :44-50
  { sfx = "Intro_Hop" }, { anim = 2 }, { wait = 10 },   -- :51-57
  { sfx = "Intro_Hip" }, { anim = 1 },                  -- :60-64
  { sfx = "Intro_Hop" }, { anim = 2 }, { wait = 30 },   -- :65-71
  { pose = 2 }, { sfx = "Intro_Raise" },                -- :74-78
  { move = "gengar", dx = -8 }, { wait = 30 },          -- :79-82
  { pose = 3 }, { sfx = "Intro_Crash" },                -- :85-89
  { move = "gengar", dx = 16 },                         -- :90-91
  { sfx = "Intro_Hip" }, { frame = 2 }, { anim = 3 },   -- :92-98
  { wait = 30 },                                        -- :99-100
  { move = "gengar", dx = -8 }, { pose = 1 },           -- :103-106
  { wait = 60 },                                        -- :107-108
  { sfx = "Intro_Hip" }, { frame = 1 }, { anim = 4 },   -- :111-117
  { sfx = "Intro_Hop" }, { anim = 5 }, { wait = 20 },   -- :118-124
  { frame = 2 }, { anim = 6 }, { wait = 30 },           -- :127-132
  { sfx = "Intro_Lunge" }, { frame = 3 }, { anim = 7 }, -- :135-141
  { fade = 24 },  -- GBFadeOutToWhite: 3 pals x 8 frames (home/fade.asm:26-40)
}
local FIGHT_FADE_INDEX = #FIGHT_SCRIPT

-- home/fade.asm:71-73
local FADE_TO_WHITE = {
  { bgp = 0x90, obp = 0x80 },
  { bgp = 0x40, obp = 0x40 },
  { bgp = 0x00, obp = 0x00 },
}
local BGP_NORMAL = 0xE4

local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

function IntroMovie.new(game, onDone)
  local self = setmetatable({}, IntroMovie)
  self.game = game
  self.onDone = onDone
  self.phase = 1
  self.timer = 0
  self.finished = false

  local intro = game.data.field and game.data.field.intro or {}
  self.introCfg = intro
  -- brand-level knobs (12 4.7): studio strings and the skip a total
  -- conversion or dev profile sets to jump straight to the title
  self.studio = intro.studio or {}
  self.skipAll = intro.skip and true or false
  local function img(e) return tryImage(e and e.path) end
  local titleCfg = game.data.field and game.data.field.title or {}
  self.copyright = img(titleCfg.copyright)
    or tryImage("assets/generated/title/copyright.png")
  self.copyQuads = {}
  if self.copyright then
    local iw, ih = self.copyright:getDimensions()
    for t = 0, 18 do
      self.copyQuads[t] = love.graphics.newQuad(t * 8, 0, 8, 8, iw, ih)
    end
  end
  self.gfInc = img(titleCfg.gamefreakInc)
    or tryImage("assets/generated/title/gamefreak_inc.png")
  -- ..(pokeyellow engine/movie/title.asm CopyrightTextString / NineTile)
  self.yellowCopy = GameVersion.isYellow()
    or titleCfg.layout == "yellow_pikachu"
  self.copyPrefix = self.yellowCopy and COPY_PREFIX_YELLOW or COPY_PREFIX_RB
  self.nineImg = self.yellowCopy and (
    img(titleCfg.nine) or tryImage("assets/generated/title/nine.png")) or nil
  self.studioLogo = tryImage(self.studio.logo)
  if self.studioLogo then
    self.studioLogo:setFilter("nearest", "nearest")
    local iw, ih = self.studioLogo:getDimensions()
    self.studioScale = math.min(STUDIO_BOX.w / iw, STUDIO_BOX.h / ih)
    self.studioX = STUDIO_BOX.cx - iw * self.studioScale / 2
    self.studioY = STUDIO_BOX.cy - ih * self.studioScale / 2
  end
  self.logo = img(intro.gamefreakLogo)
  self.gfText = img(intro.gamefreakText)
  self.logoPath = self.logo and romArt(intro.gamefreakLogo.path)
  self.gfTextPath = self.gfText and romArt(intro.gamefreakText.path)
  self.bigStar = img(intro.bigStar)
  self.bigStarPath = self.bigStar and romArt(intro.bigStar.path)
  self.smallStar = img(intro.fallingStar)
  self.smallStarBlink = img(intro.fallingStarBlink)
  self.gengarFrames, self.nidoFrames = {}, {}
  self.gengarPaths, self.nidoPaths = {}, {}
  for i = 1, 3 do
    local g = intro.gengar and intro.gengar["frame" .. i]
    local n = intro.nidorino and intro.nidorino["frame" .. i]
    self.gengarFrames[i] = img(g)
    self.nidoFrames[i] = img(n)
    self.gengarPaths[i] = g and g.path
    self.nidoPaths[i] = n and n.path
  end

  -- fight state (PlayIntroScene entry, intro.asm:30-39): Gengar BG pose at
  -- tile (13,7) = screen (104,56); Nidorino OAM base (0,80) = screen
  -- (-8,72) after the OAM +8 offsets
  self.gengarX, self.gengarY = 104, 56
  self.nidoX, self.nidoY = -8, 72
  self.gengarPose, self.nidoFrame = 1, 1
  self.opIndex, self.opTimer = 1, 0
  self.fadeStep = nil
  return self
end

-- PlayIntro never StopAllSounds's: Music_IntroBattle outlasts the fade and
-- keeps playing over the title logo drop until title.asm starts
-- MUSIC_TITLE_SCREEN (same continuity Yellow got in #436).
function IntroMovie:finish()
  if self.finished then return end
  self.finished = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

-- Solid white beat before the title screen is pushed (see POST_FADE_WHITE).
function IntroMovie:exitToTitle()
  if self.finished or self.phase == 4 then return end
  self.phase = 4
  self.timer = 0
end

function IntroMovie:startPhase(phase)
  self.phase = phase
  self.timer = 0
  if phase == 3 then
    -- intro.asm:333-338
    local data = self.game.data
    local songs = data.audio and data.audio.songs
    local song = self.introCfg.music or "Music_IntroBattle"
    if songs and songs[song] then
      pcall(Music.play, data, song, false)
    end
  end
end

-- one frame of the fight script (see FIGHT_SCRIPT)
function IntroMovie:endScene()
  self.opIndex = FIGHT_FADE_INDEX
  self.opTimer = 0
end

-- home/overworld.asm:2395
function IntroMovie:pollInterrupt()
  local input = self.game.input
  if not input then return false end
  local function down(b)
    return (input.isDown and input:isDown(b)) or input:wasPressed(b)
  end
  local last = self.lastPollHeld or {}
  local held = { a = down("a"), start = down("start") }
  self.lastPollHeld = held
  if (held.a and not last.a) or (held.start and not last.start) then return true end
  return down("up") and down("select") and down("b")
    and not (held.a or held.start or down("down") or down("left") or down("right"))
end

function IntroMovie:fightStep()
  while true do
    local op = FIGHT_SCRIPT[self.opIndex]
    if not op then
      self:finish()
      return
    end
    -- an op that consumed frames ends ON its last frame; only the instant
    -- ops (sfx / pose / frame, which are plain writes between DelayFrames
    -- calls in PlayIntroScene) chain into the next op the same frame
    local timed = false
    if op.sfx then
      Sound.play(self.game.data, op.sfx)
    elseif op.pose then
      self.gengarPose = op.pose
    elseif op.frame then
      self.nidoFrame = op.frame
    elseif op.move then
      -- 2px per 2 frames (IntroMoveMon: CheckForUserInterruption c=2)
      if self.opTimer % 2 == 0 then
        if op.move == "scrollIn" then
          self.gengarX = self.gengarX - 2
          self.nidoX = self.nidoX + 2
        else
          self.gengarX = self.gengarX + (op.dx > 0 and 2 or -2)
        end
      end
      self.opTimer = self.opTimer + 1
      if self:pollInterrupt() then
        -- engine/movie/intro.asm:264
        if op.move == "scrollIn" then self:endScene() return end
        self.opIndex = self.opIndex + 1
        self.opTimer = 0
        return
      end
      if self.opTimer < (op.px or math.abs(op.dx)) then return end
      timed = true
    elseif op.anim then
      -- one {dy,dx} delta per 5 frames (AnimateIntroNidorino: DelayFrames 5)
      if self.opTimer % 5 == 0 then
        local d = ANIM[op.anim][self.opTimer / 5 + 1]
        self.nidoY = self.nidoY + d[1]
        self.nidoX = self.nidoX + d[2]
      end
      self.opTimer = self.opTimer + 1
      if self.opTimer < #ANIM[op.anim] * 5 then return end
      timed = true
    elseif op.wait then
      self.opTimer = self.opTimer + 1
      if self:pollInterrupt() then self:endScene() return end
      if self.opTimer < op.wait then return end
      timed = true
    elseif op.fade then
      self.opTimer = self.opTimer + 1
      self.fadeStep = math.floor((self.opTimer - 1) / 8) + 1
      if self.opTimer >= op.fade then self:exitToTitle() end
      return
    end
    self.opIndex = self.opIndex + 1
    self.opTimer = 0
    if timed then return end
  end
end

function IntroMovie:update(dt)
  if self.skipAll then
    self:finish()
    return
  end
  if self.phase == 4 then
    self.timer = self.timer + 1
    if self.timer >= POST_FADE_WHITE then self:finish() end
    return
  end
  self.timer = self.timer + 1
  if self.phase == 1 then
    -- the copyright card is a bare DelayFrames, deaf to input (intro.asm:311)
    if self.timer >= COPYRIGHT_FRAMES then self:startPhase(2) end
  elseif self.phase == 2 then
    if self.timer == STAR_START then
      Sound.play(self.game.data, "Shooting_Star")  -- splash.asm:29-30
    end
    -- intro.asm:325 `jr c, .next`
    if self.timer >= STAR_START and self.timer < WAVES_END and self:pollInterrupt() then
      self:startPhase(3)
      return
    end
    if self.timer >= SPLASH_FRAMES then self:startPhase(3) end
  else
    -- PlayShootingStar ends `jp Delay3` once Music_IntroBattle is playing
    -- (intro.asm:337), so PlayIntroScene's first op is not on the music's
    -- own frame
    if self.timer > Timing.DELAY3 then self:fightStep() end
  end
end

-- the letterbox bars: 4 black tile rows top and bottom
-- (IntroDrawBlackBars, intro.asm:343-357); drawn AFTER the sprites since
-- both Nidorino and the small stars carry OAM_PRIO (intro.asm:195,
-- splash.asm:149) so the bars cover them.
local function drawBars(bgp)
  local g = (3 - math.floor((bgp or BGP_NORMAL) / 64) % 4) / 3
  love.graphics.setColor(g, g, g, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 32)
  love.graphics.rectangle("fill", 0, 112, 160, 32)
  love.graphics.setColor(1, 1, 1, 1)
end

function IntroMovie:logoObp0()
  local t = self.timer - FLASH_START
  if t < 0 then return LOGO_OBP0[0] end
  return LOGO_OBP0[math.min(3, math.floor(t / 10) + 1)]
end

function IntroMovie:drawObp0(img, path, x, y, obp)
  if not img then return end
  if not path then
    love.graphics.draw(img, x, y)
    return
  end
  local P = require("src.render.PaletteFX")
  local SR = require("src.render.SpriteRenderer")
  love.graphics.draw(SR.obpImage(path, obpRamp(obp, P.GRAYS), "gfobp" .. obp), x, y)
  if P.usesSpriteObp() then
    local blue = GameVersion.isBlue()
    P.markUiSpriteRedraw(SR.obpImage(path,
      obpRamp(obp, blue and P.GBC_OBJ_BLUE or P.GBC_OBJ),
      (blue and "gfobj_blue" or "gfobj") .. obp), nil, x, y)
  end
end

function IntroMovie:drawSplash()
  local t = self.timer
  if t >= STAR_START then
    -- logo + GAME FREAK letters appear with the star OAM
    -- (LoadShootingStarGraphics, splash.asm:18-25); the logo palette
    -- rotates during the 3-flash loop (splash.asm:72-82)
    if self.studioLogo then
      local flashing = t >= FLASH_START and t < FLASH_START + FLASH_FRAMES
      local dim = flashing and math.floor((t - FLASH_START) / 5) % 2 == 0
      love.graphics.setColor(1, 1, 1, dim and 0.35 or 1)
      love.graphics.draw(self.studioLogo, self.studioX, self.studioY,
                         0, self.studioScale, self.studioScale)
    else
      local obp = self:logoObp0()
      self:drawObp0(self.logo, self.logoPath, LOGO_X, LOGO_Y, obp)
      self:drawObp0(self.gfText, self.gfTextPath, TEXT_X, TEXT_Y, obp)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  if t >= WAVES_START then
    -- small stars: wave w spawns at y=88 every 24 frames, everything falls
    -- +1px per 3-frame substep until the wave loop ends; the lower star in
    -- the tile blinks every substep (splash.asm:97-146, 186-209)
    -- engine/movie/splash.asm:186
    local moves = math.min(math.floor((t - WAVES_START) / 3) + 1, 6 * 8)
    local lit = moves % 2 == 1
    for w, xs in ipairs(STAR_WAVES) do
      local spawn = (w - 1) * 8  -- in substeps
      if moves > spawn then
        local y = 88 + (moves - spawn)
        if y < 144 then
          local img = lit and (self.smallStarBlink or self.smallStar)
                      or self.smallStar
          for _, x in ipairs(xs) do
            if img then
              love.graphics.draw(img, x, y)
            else
              love.graphics.setColor(0, 0, 0, 1)
              love.graphics.rectangle("fill", x + 3, y + 1, 2, 2)
              love.graphics.setColor(1, 1, 1, 1)
            end
          end
        end
      end
    end
  end
  drawBars()
  if t >= STAR_START and t < FLASH_START then
    -- ..(engine/movie/splash.asm ln 32)
    local n = t - STAR_START + 1
    local sx, sy = 152 - 4 * n, -16 + 4 * n
    if self.bigStar and self.bigStarPath then
      local P = require("src.render.PaletteFX")
      local SR = require("src.render.SpriteRenderer")
      love.graphics.draw(SR.obpImage(self.bigStarPath,
        obpRamp(STAR_OBP1, P.GRAYS), "gfobp" .. STAR_OBP1), sx, sy)
      if P.usesSpriteObp() then
        -- engine/movie/splash.asm:22
        local blue = GameVersion.isBlue()
        P.markUiSpriteRedraw(SR.obpImage(self.bigStarPath,
          obpRamp(STAR_OBP1, P.ogBg()),
          (blue and "gfobj1_blue" or "gfobj1") .. STAR_OBP1), nil, sx, sy)
      end
    elseif self.bigStar then
      love.graphics.draw(self.bigStar, sx, sy)
    else
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", sx + 6, sy + 6, 4, 4)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

function IntroMovie:drawFight()
  -- Gengar: a 56x56 BG-tile pose recomposed from gengar_N.tilemap, moved
  -- by scrolling SCX (intro.asm:32-33, 235-269)
    -- Nidorino: 6x6 OAM sprite, one of the three red_nidorino poses
  local fade = self.fadeStep and FADE_TO_WHITE[self.fadeStep]
  local bgp = fade and fade.bgp or BGP_NORMAL
  local obp = fade and fade.obp or BGP_NORMAL
  local P = require("src.render.PaletteFX")
  local SR = require("src.render.SpriteRenderer")
  local nido = self.nidoFrames[self.nidoFrame]
  local nidoPath = self.nidoPaths and self.nidoPaths[self.nidoFrame]
  if nido then
    if fade and nidoPath then
      love.graphics.draw(SR.obpImage(nidoPath, obpRamp(obp, P.GRAYS),
        "fadeobp" .. obp), self.nidoX, self.nidoY)
    else
      love.graphics.draw(nido, self.nidoX, self.nidoY)
    end
  end
  local gengar = self.gengarFrames[self.gengarPose]
  local gengarPath = self.gengarPaths and self.gengarPaths[self.gengarPose]
  if gengar then
    if fade and gengarPath then
      love.graphics.draw(SR.obpImage(gengarPath, obpRamp(bgp, P.GRAYS),
        "fadebgp" .. bgp), self.gengarX, self.gengarY)
    else
      love.graphics.draw(gengar, self.gengarX, self.gengarY)
    end
  end

  if not gengar and not nido then
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("GENGAR VS NIDORINO"), (160 - 18 * 8) / 2, 64)
    love.graphics.setColor(1, 1, 1, 1)
  end
  drawBars(bgp)
  self:replayObjLayer(nido, gengar, fade)
end

local FIGHT_CLIP = { 0, 32, 160, 80 }

function IntroMovie:replayObjLayer(nido, gengar, fade)
  local P = require("src.render.PaletteFX")
  local nidoPath = self.nidoPaths and self.nidoPaths[self.nidoFrame]
  if not (nido and nidoPath and P.usesSpriteObp()) then return end
  local SR = require("src.render.SpriteRenderer")
  local blue = GameVersion.isBlue()
  local opts = { clip = FIGHT_CLIP }
  local objColors = blue and P.GBC_OBJ_BLUE or P.GBC_OBJ
  local objGroup = blue and "gbcobj_blue" or "gbcobj"
  local bgColors, bgGroup = P.ogBg(), blue and "ogbg_blue" or "ogbg"
  if fade then
    objColors, objGroup = obpRamp(fade.obp, objColors), objGroup .. fade.obp
    bgColors, bgGroup = obpRamp(fade.bgp, bgColors), bgGroup .. fade.bgp
  end
  -- engine/movie/intro.asm:28
  P.markUiSpriteRedraw(SR.obpImage(nidoPath, objColors, objGroup),
    nil, self.nidoX, self.nidoY, opts)
  local gengarPath = self.gengarPaths[self.gengarPose]
  if gengar and gengarPath then
    -- engine/movie/intro.asm:195
    P.markUiSpriteRedraw(SR.obpImage(gengarPath, bgColors, bgGroup),
      nil, self.gengarX, self.gengarY, opts)
  end
end

function IntroMovie:drawCopyPrefix(x, y)
  for _, t in ipairs(self.copyPrefix) do
    love.graphics.draw(self.copyright, self.copyQuads[t], x, y)
    x = x + 8
  end
  if self.nineImg then
    love.graphics.draw(self.nineImg, x, y)
  end
end

function IntroMovie:drawCopyright()
  if self.studio.card or self.studio.credit then
    local card = self.studio.card or ""
    local credit = self.studio.credit or ""
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(card, (160 - #card * 8) / 2, 64)
    Font.draw(credit, (160 - #credit * 8) / 2, 80)
  elseif self.copyright and self.gfInc then
    local function row(seq, x, y)
      for _, t in ipairs(seq) do
        love.graphics.draw(self.copyright, self.copyQuads[t], x, y)
        x = x + 8
      end
    end
    for _, y in ipairs({ 56, 72, 88 }) do self:drawCopyPrefix(16, y) end
    row(COPY_NINTENDO, 80, 56)
    row(COPY_CREATURES, 80, 72)
    love.graphics.draw(self.gfInc, 80, 88)
  else
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("Nintendo"), 80, 56)
    Font.draw(Strings("Creatures inc."), 80, 72)
    Font.draw(Strings("GAME FREAK inc."), 16, 88)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function IntroMovie:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if self.phase == 4 then
    -- GBPalWhiteOut hold (title.asm DisplayTitleScreen load-in)
    return
  elseif self.phase == 1 then
    self:drawCopyright()
  elseif self.phase == 2 then
    self:drawSplash()
  else
    self:drawFight()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return IntroMovie
