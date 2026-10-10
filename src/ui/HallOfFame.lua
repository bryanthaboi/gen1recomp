-- Hall of Fame induction (engine/movie/hall_of_fame.asm): each party
-- member's back sprite sweeps across the screen and its front sprite then
-- scrolls onto the right side (HoFShowMonOrPlayer's two .ScrollPic passes,
-- #847), then HoFDisplayMonInfo draws the
-- left-side LEVEL/TYPE box, plays the cry, holds, and pops the bottom
-- "HALL OF FAME" text box before fading to the next mon.  After the
-- party, the player pic scrolls in and HoFDisplayPlayerStats shows the
-- name/time/money boxes plus the dex rating.  Plays Music_HallOfFame
-- when the audio data has it.  Calls onDone() after popping itself.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local TextBox = require("src.render.TextBox")
local Music = require("src.core.Music")
local Sound = require("src.core.Sound")
local TypeChart = require("src.battle.TypeChart")
local Strings = require("src.core.Strings")

local HallOfFame = {}
HallOfFame.__index = HallOfFame
HallOfFame.isOpaque = true

-- SGB: SetPal_PokemonWholeScreen for the mon on display
function HallOfFame:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  if self.phase == "intro" then
    local ow = game.overworld
    if ow and ow.sgbPalettes then return ow:sgbPalettes(game) end
    return nil
  end
  if self.phase == "player" or self.phase == "player_dex"
      or self.phase == "player_rating" then
    return P.wholeNamed(game.data, "MEWMON")
  end
  local mon = game.save.party[self.index or 0]
  if mon then
    local c = P.monPal(game.data, mon.species)
    if c then return { P.whole(c) } end
    return nil
  end
  return P.wholeNamed(game.data, "MEWMON")
end

-- HoFShowMonOrPlayer's .ScrollPic: hSCX is nudged by e = 4px per
-- DelayFrame (doubled on SGB) until it settles.  The front pic rests at
-- hlcoord 12,5 (engine/movie/hall_of_fame.asm HoFLoadMonPlayerPicTileIDs).
local SCROLL_SPEED = 4 -- px/frame @ 60fps
local PIC_X, PIC_Y = 12 * 8, 5 * 8

-- The BACK pic pass that runs in front of every front pic (#847).
-- HoFShowMonOrPlayer loads the back pic (predef LoadMonBackPic, or
-- RedPicBack through HoFLoadPlayerPics) into the same 7x7 window at
-- hlcoord 12,5, points the tilemap at base tile $31, and sweeps hSCX from
-- $c0 to $a0 at e = 4 -- in screen pixels the pic enters at x = 160 and
-- leaves at x = -64, 56 frames.  Only then is the window re-pointed at the
-- front pic (base tile 0) with hSCY back to 0 and e = -4, so the front pic
-- starts at x = -64 rather than at its own width.
-- hSCY = $d0 during the back pass puts the window's top row at y = 88, so
-- its 7 tiles sit flush with the bottom of the screen.  ScaleSpriteByTwo
-- (engine/battle/scale_sprites.asm) doubles the 32x32 back sprite into that
-- 7x7 = 56x56 buffer with the last 4 source rows and the last source column
-- dropped, so what shows is the sprite's top-left 28x28 at 2x.
local BACK_START_X, BACK_END_X = 160, -64
local BACK_Y = 88
local BACK_SCALE = 2
local BACK_CROP = 28
local FRONT_START_X = -64

-- After HoFDisplayAndRecordMonInfo: 80 DelayFrames, then the bottom
-- HALL OF FAME box for 180 DelayFrames, then GBFadeOutToWhite.
local INFO_HOLD = 80
local HOF_HOLD = 180
local FADE_FRAMES = 20

-- scripts/HallOfFame.asm:24
local INTRO_DELAY = 3
-- home/fade.asm:26
local INTRO_FADE = 24
-- engine/movie/hall_of_fame.asm:4
local INTRO_HOLD = 100

-- HoFPrintTextAndDelay after each dex line
local DEX_HOLD = 120

-- through Assets.resolve so an enabled mod's overrides/ shadows these the
-- same way it shadows every other generated asset
local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
  return ok and img or nil
end

-- POKéDEX rating tiers (engine/events/pokedex_rating.asm DexRatingsTable)
local function dexRatingKey(owned)
  if owned >= 150 then return "_DexRatingText_Own150To151" end
  local lo = math.floor(owned / 10) * 10
  return ("_DexRatingText_Own%dTo%d"):format(lo, lo + 9)
end

function HallOfFame.new(game, onDone)
  local self = setmetatable({}, HallOfFame)
  self.game = game
  self.onDone = onDone
  self.index = 0
  self.timer = 0
  self.phase = "intro"
  self.introT = 0
  self.isOpaque = false
  self.introFade = require("src.render.Transition").whiteOut(game)
  self.sprites = {} -- species -> image or false
  self.spriteTrueColor = {} -- species -> full-color art flag (#637)
  self.backs = {} -- species (or "@player") -> back image or false (#847)
  self.backTrueColor = {}
  local playerPath, playerTrueColor =
    require("src.pokemon.Sprites").playerPath(
      game.data, "front", { kind = "hof" })
  self.playerPic = tryImage(playerPath)
  self.playerTrueColor = self.playerPic and playerTrueColor or false
  self.scrollX = PIC_X
  self.showHofBanner = false
  self.fade = 0
  return self
end

function HallOfFame:updateIntro()
  self.introT = self.introT + 1
  if self.introT == INTRO_DELAY + 1 then
    -- engine/movie/hall_of_fame.asm:283
    Music.fadeOut(10)
  end
  if self.introT > INTRO_DELAY + INTRO_FADE then self.isOpaque = true end
  if self.introT >= INTRO_DELAY + INTRO_FADE + INTRO_HOLD then
    -- engine/movie/hall_of_fame.asm:38
    local data = self.game.data
    if data.audio and data.audio.songs and data.audio.songs.Music_HallOfFame then
      pcall(Music.play, data, "Music_HallOfFame")
    end
    self:nextMon()
  end
end

function HallOfFame:nextMon()
  self.index = self.index + 1
  local mon = self.game.save.party[self.index]
  self.showHofBanner = false
  self.fade = 0
  self.backQuad = nil
  -- HoFShowMonOrPlayer runs the back pic sweep for a party member and for
  -- the player alike (wHoFMonOrPlayer only picks which pics get loaded), so
  -- both enter through the "back" phase and the front pic follows it (#847)
  self.phase = "back"
  self.afterBack = mon and "mons" or "player"
  self.timer = 0
  self.scrollX = BACK_START_X
end

function HallOfFame:spriteFor(species)
  local cached = self.sprites[species]
  if cached == nil then
    local path, trueColor = require("src.pokemon.Sprites").path(
      self.game.data, species, "front", { kind = "hof" })
    cached = tryImage(path) or false
    self.sprites[species] = cached
    self.spriteTrueColor[species] = cached and trueColor or false
  end
  return cached or nil
end

-- The back pic for the pass ahead of the current front pic: the party
-- member's own back sprite (predef LoadMonBackPic), or RedPicBack once the
-- party is done (HoFLoadPlayerPics).  Cached like spriteFor (#847).
function HallOfFame:backPicFor()
  local mon = self.game.save.party[self.index]
  local key = mon and mon.species or "@player"
  local cached = self.backs[key]
  if cached == nil then
    local Sprites = require("src.pokemon.Sprites")
    local path, trueColor
    if mon then
      path, trueColor = Sprites.path(self.game.data, mon.species, "back",
                                     { kind = "hof" })
    else
      path, trueColor = Sprites.playerPath(self.game.data, "back",
                                           { kind = "hof" })
    end
    cached = tryImage(path) or false
    self.backs[key] = cached
    self.backTrueColor[key] = cached and trueColor or false
  end
  return cached or nil, self.backTrueColor[key]
end

-- HoFDisplayPlayerStats' DisplayDexRating tally (also
-- OverworldController:dexRating / PokedexMenu.new's seen+owned counts)
function HallOfFame:dexSeenOwned()
  local dex = self.game.save.pokedex or { seen = {}, owned = {} }
  local seen, owned = 0, 0
  for _ in pairs(dex.seen or {}) do seen = seen + 1 end
  for _ in pairs(dex.owned or {}) do owned = owned + 1 end
  return seen, owned
end

function HallOfFame:advanceMonPhase()
  if self.phase == "mons" and not self.showHofBanner then
    -- 80-frame info hold done: TextBoxBorder at (2,13) + "HALL OF FAME"
    self.showHofBanner = true
    self.timer = HOF_HOLD
  elseif self.phase == "mons" then
    self.phase = "fade"
    self.timer = FADE_FRAMES
    self.fade = 0
  elseif self.phase == "fade" then
    self:nextMon()
  end
end

function HallOfFame:update(dt)
  -- .ScrollPic with d = $a0, e = 4: the back pic crosses the screen right to
  -- left and is gone before the front pic starts.  Both scrolls are plain
  -- DelayFrame loops in the ROM, so neither takes a button (#847).
  if self.phase == "intro" then
    self:updateIntro()
    return
  end
  if self.phase == "back" then
    self.scrollX = self.scrollX - SCROLL_SPEED
    if self.scrollX <= BACK_END_X then
      self.phase = self.afterBack
      self.timer = self.phase == "mons" and INFO_HOLD or 0
      self.scrollX = FRONT_START_X
    end
    return
  end

  if self.phase == "mons" or self.phase == "fade" then
    if self.phase == "mons" and self.scrollX < PIC_X then
      self.scrollX = math.min(PIC_X, self.scrollX + SCROLL_SPEED)
      -- PlayCry is the tail of HoFDisplayMonInfo, which runs only after
      -- HoFShowMonOrPlayer's two scrolls have both settled (#847)
      if self.scrollX >= PIC_X then
        local mon = self.game.save.party[self.index]
        if mon then Sound.playCry(self.game.data, mon.species) end
      end
      return
    end
    if self.phase == "fade" then
      self.timer = self.timer - 1
      self.fade = 1 - math.max(0, self.timer) / FADE_FRAMES
      if self.timer <= 0 then self:advanceMonPhase() end
      return
    end
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self:advanceMonPhase()
    end
  elseif self.phase == "player" then
    if self.scrollX < PIC_X then
      self.scrollX = math.min(PIC_X, self.scrollX + SCROLL_SPEED)
      return
    end
    -- engine/movie/hall_of_fame.asm:242
    self.phase = "player_dex"
    self:showDexTexts()
  end
  -- player_dex / player_rating are driven by the TextBox chain that
  -- showDexTexts pushes; nothing is timed here
end

-- HoFDisplayPlayerStats' three HoFPrintTextAndDelay calls: seen/owned,
-- "POKéDEX Rating:", then the tier text DisplayDexRating copied into
-- wDexRatingText -- each through PrintText (the standard two-row box, so
-- the tier text's \v rows scroll inside it) followed by 120 DelayFrames
-- with no button wait.  Hand-drawing these flattened the \v scrolls and
-- painted the third row over the box's bottom border (#314).
function HallOfFame:showDexTexts()
  local game = self.game
  local text = game.data.text or {}
  local seen, owned = self:dexSeenOwned()
  local seenOwned = (text._DexSeenOwnedText
      or Strings("POKéDEX   Seen:{NUM:wDexRatingNumMonsSeen, 1, 3}\n         Owned:{NUM:wDexRatingNumMonsOwned, 1, 3}"))
    :gsub("{NUM:wDexRatingNumMonsSeen[^}]*}", tostring(seen))
    :gsub("{NUM:wDexRatingNumMonsOwned[^}]*}", tostring(owned))
  local header = (text._DexRatingText or Strings("POKéDEX Rating{COLON}"))
    :gsub("{COLON}", ":")
  local rating = text[dexRatingKey(owned)] or Strings("Keep it up!")
  local function finish()
    -- HoFFadeOutScreenAndMusic -> Credits lead-in (no A wait here)
    game.stack:pop()
    if self.onDone then self.onDone() end
  end
  -- engine/movie/hall_of_fame.asm:24
  local function dexBox(str, nextFn)
    game.stack:push(TextBox.new(game, str, nextFn,
                                { auto = { delay = DEX_HOLD },
                                  noLetterDelay = true }))
  end
  local function showRating() dexBox(rating, finish) end
  local function showHeader()
    self.phase = "player_rating"
    dexBox(header, showRating)
  end
  dexBox(seenOwned, showHeader)
end

-- HoFDisplayMonInfo: TextBoxBorder (0,2) b=9,c=10 + LEVEL/TYPE labels
function HallOfFame:drawMonInfo(mon)
  local def = self.game.data.pokemon[mon.species]
  Font.drawBox(0, 2, 12, 11)
  love.graphics.setColor(0, 0, 0, 1)
  local name = mon.nickname or (def and def.name) or mon.species
  Font.draw(name, 1 * 8, 4 * 8)
  -- HoFMonInfoText is placed at (2,6) with "next" separators, and PlaceNextChar
  -- advances 2 * SCREEN_WIDTH per <NEXT> unless BIT_SINGLE_SPACED_LINES is set
  -- (home/text.asm); nothing on the HoF path sets it, so the labels sit on rows
  -- 6/8/10 lined up with their values, not 6/7/8 (#697).
  Font.draw(Strings("LEVEL/"), 2 * 8, 6 * 8)
  Font.draw(Strings("TYPE1/"), 2 * 8, 8 * 8)
  local t1 = def and def.types and def.types[1]
  local t2 = def and def.types and def.types[2]
  local dual = t2 and t2 ~= t1
  if dual then
    -- EraseType2Text blanks 6 tiles at hl+$13 from (3,9), so TYPE2/ is at (2,10)
    Font.draw(Strings("TYPE2/"), 2 * 8, 10 * 8)
  end
  -- PrintLevelCommon at (8,7): bare level digits (no <LV> tile here)
  Font.draw(tostring(mon.level), 8 * 8, 7 * 8)
  -- PrintMonType at (3,9) / +2 rows for type 2
  if t1 then
    Font.draw(TypeChart.displayName(t1, self.game.data), 3 * 8, 9 * 8)
  end
  if dual then
    Font.draw(TypeChart.displayName(t2, self.game.data), 3 * 8, 11 * 8)
  end
end

-- Bottom HALL OF FAME banner: TextBoxBorder (2,13) b=3,c=14
function HallOfFame:drawHofBanner()
  Font.drawBox(2, 13, 16, 5)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("HALL OF FAME"), 4 * 8, 15 * 8)
end

function HallOfFame:drawPic(img, trueColor)
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  local x = self.scrollX or PIC_X
  love.graphics.draw(img, x, PIC_Y)
  -- SET_PAL_POKEMON_WHOLE_SCREEN (HoFShowMonOrPlayer) colors the WHOLE
  -- screen in the mon's palette, so sgbPalettes above hands the blit a
  -- whole-canvas zone -- and a full-color pic has to sit that remap out.
  -- Report the rect the pic covers for the unshaded pass, the way
  -- SummaryMenu does for the status screen pic (#637; #430).
  if trueColor then
    require("src.render.PaletteFX").markTrueColor(x, PIC_Y,
                                                 img:getDimensions())
  end
end

-- The back pic sweep (see the BACK_* constants): the same 7x7 window as the
-- front pic, one screen lower, cropped to the 28x28 ScaleSpriteByTwo keeps.
function HallOfFame:drawBackPic()
  local img, trueColor = self:backPicFor()
  if not img then return end
  local w = math.min(img:getWidth(), BACK_CROP)
  local h = math.min(img:getHeight(), BACK_CROP)
  if not self.backQuad then
    self.backQuad = love.graphics.newQuad(0, 0, w, h, img:getDimensions())
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, self.backQuad, self.scrollX, BACK_Y, 0,
                     BACK_SCALE, BACK_SCALE)
  -- same whole-screen palette exemption the front pic takes (#637)
  if trueColor then
    require("src.render.PaletteFX").markTrueColor(self.scrollX, BACK_Y,
                                                 w * BACK_SCALE,
                                                 h * BACK_SCALE)
  end
end

-- HoFDisplayPlayerStats boxes + labels (player pic already on the right)
function HallOfFame:drawPlayerStats()
  local save = self.game.save
  -- name box: TextBoxBorder (5,0) b=2,c=9 → drawBox(5,0,11,4)
  Font.drawBox(5, 0, 11, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(save.player.name or "RED", 7 * 8, 2 * 8)

  -- play time / money box: TextBoxBorder (0,4) b=6,c=10 → drawBox(0,4,12,8)
  Font.drawBox(0, 4, 12, 8)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("PLAY TIME"), 1 * 8, 6 * 8)
  local t = math.floor(save.playTime or 0)
  Font.draw(("%3d:%02d"):format(math.floor(t / 3600), math.floor(t / 60) % 60),
            5 * 8, 7 * 8)
  Font.draw(Strings("MONEY"), 1 * 8, 9 * 8)
  -- PrintBCDNumber with MONEY_SIGN; port uses ¥ like TrainerCard
  Font.draw(("¥%d"):format(save.money or 0), 4 * 8, 10 * 8)
end

function HallOfFame:draw()
  if self.phase == "intro" and not self.isOpaque then
    if self.introT > INTRO_DELAY then
      self.introFade.t = self.introT - INTRO_DELAY
      self.introFade:draw()
    end
    return
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  if self.phase == "back" then
    self:drawBackPic()
  elseif self.phase == "mons" or self.phase == "fade" then
    local mon = self.game.save.party[self.index]
    if mon then
      self:drawPic(self:spriteFor(mon.species),
                   self.spriteTrueColor[mon.species])
      if self.scrollX >= PIC_X then
        self:drawMonInfo(mon)
        if self.showHofBanner then
          self:drawHofBanner()
        end
      end
    end
    if self.phase == "fade" and self.fade > 0 then
      love.graphics.setColor(1, 1, 1, self.fade)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
    end
  elseif self.phase == "player" then
    self:drawPic(self.playerPic, self.playerTrueColor)
  elseif self.phase == "player_dex" or self.phase == "player_rating" then
    -- the TextBox chain draws the dex texts over the stat boxes
    self:drawPic(self.playerPic, self.playerTrueColor)
    self:drawPlayerStats()
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return HallOfFame
