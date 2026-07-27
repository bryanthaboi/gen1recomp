-- Hall of Fame induction (engine/movie/hall_of_fame.asm): each party
-- member's front sprite scrolls onto the right side of the screen
-- (HoFShowMonOrPlayer's .ScrollPic), then HoFDisplayMonInfo draws the
-- left-side LEVEL/TYPE box, plays the cry, holds, and pops the bottom
-- "HALL OF FAME" text box before fading to the next mon.  After the
-- party, the player pic scrolls in and HoFDisplayPlayerStats shows the
-- name/time/money boxes plus the dex rating.  Plays Music_HallOfFame
-- when the audio data has it.  Calls onDone() after popping itself.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
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
  if self.phase == "player" or self.phase == "player_stats"
      or self.phase == "player_dex" or self.phase == "player_rating" then
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

-- After HoFDisplayAndRecordMonInfo: 80 DelayFrames, then the bottom
-- HALL OF FAME box for 180 DelayFrames, then GBFadeOutToWhite.
local INFO_HOLD = 80
local HOF_HOLD = 180
local FADE_FRAMES = 20

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

-- \n/\v/\f-marked extracted text, one Font.draw line at a time (same
-- technique as DexEntryMenu.lua's dex-description block)
local function drawTextBlock(text, x, y, maxY)
  for line in (text:gsub("\v", "\n"):gsub("\f", "\n") .. "\n"):gmatch("(.-)\n") do
    if maxY and y > maxY then break end
    Font.draw(line, x, y)
    y = y + 8
  end
  return y
end

function HallOfFame.new(game, onDone)
  local self = setmetatable({}, HallOfFame)
  self.game = game
  self.onDone = onDone
  self.index = 0
  self.timer = 0
  self.phase = "mons"
  self.sprites = {} -- species -> image or false
  self.playerPic = tryImage(require("src.pokemon.Sprites").playerPath(
    game.data, "front", { kind = "hof" }))
  self.scrollX = PIC_X
  self.showHofBanner = false
  self.fade = 0
  return self
end

function HallOfFame:enter()
  local data = self.game.data
  if data.audio and data.audio.songs and data.audio.songs.Music_HallOfFame then
    pcall(Music.play, data, "Music_HallOfFame")
  end
  self:nextMon()
end

function HallOfFame:nextMon()
  self.index = self.index + 1
  local mon = self.game.save.party[self.index]
  self.showHofBanner = false
  self.fade = 0
  if mon then
    self.phase = "mons"
    self.timer = INFO_HOLD
    Sound.playCry(self.game.data, mon.species)
    local sprite = self:spriteFor(mon.species)
    local w = sprite and sprite:getWidth() or 56
    self.scrollX = -w
  else
    -- HoFShowMonOrPlayer with wHoFMonOrPlayer = player
    self.phase = "player"
    self.timer = 0
    local w = self.playerPic and self.playerPic:getWidth() or 56
    self.scrollX = -w
  end
end

function HallOfFame:spriteFor(species)
  local cached = self.sprites[species]
  if cached == nil then
    local path = require("src.pokemon.Sprites").path(
      self.game.data, species, "front", { kind = "hof" })
    cached = tryImage(path) or false
    self.sprites[species] = cached
  end
  return cached or nil
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
  local input = self.game.input
  local skip = input:wasPressed("a")

  if self.phase == "mons" or self.phase == "fade" then
    if self.phase == "mons" and self.scrollX < PIC_X then
      self.scrollX = math.min(PIC_X, self.scrollX + SCROLL_SPEED)
      return
    end
    if self.phase == "fade" then
      self.timer = self.timer - 1
      self.fade = 1 - math.max(0, self.timer) / FADE_FRAMES
      if self.timer <= 0 or skip then self:advanceMonPhase() end
      return
    end
    self.timer = self.timer - 1
    if skip or self.timer <= 0 then
      self:advanceMonPhase()
    end
  elseif self.phase == "player" then
    if self.scrollX < PIC_X then
      self.scrollX = math.min(PIC_X, self.scrollX + SCROLL_SPEED)
      return
    end
    self.phase = "player_stats"
    self.timer = DEX_HOLD
  elseif self.phase == "player_stats" then
    -- name / play time / money boxes are up; then DexSeenOwnedText
    self.timer = self.timer - 1
    if skip or self.timer <= 0 then
      self.phase = "player_dex"
      self.timer = DEX_HOLD
    end
  elseif self.phase == "player_dex" then
    self.timer = self.timer - 1
    if skip or self.timer <= 0 then
      self.phase = "player_rating"
      self.timer = DEX_HOLD
    end
  elseif self.phase == "player_rating" then
    self.timer = self.timer - 1
    if skip or self.timer <= 0 then
      -- HoFFadeOutScreenAndMusic -> Credits lead-in (no A wait here)
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

-- HoFDisplayMonInfo: TextBoxBorder (0,2) b=9,c=10 + LEVEL/TYPE labels
function HallOfFame:drawMonInfo(mon)
  local def = self.game.data.pokemon[mon.species]
  Font.drawBox(0, 2, 12, 11)
  love.graphics.setColor(0, 0, 0, 1)
  local name = mon.nickname or (def and def.name) or mon.species
  Font.draw(name, 1 * 8, 4 * 8)
  Font.draw(Strings("LEVEL/"), 2 * 8, 6 * 8)
  Font.draw(Strings("TYPE1/"), 2 * 8, 7 * 8)
  local t1 = def and def.types and def.types[1]
  local t2 = def and def.types and def.types[2]
  local dual = t2 and t2 ~= t1
  if dual then
    Font.draw(Strings("TYPE2/"), 2 * 8, 8 * 8)
  end
  -- PrintLevelCommon at (8,7): bare level digits (no <LV> tile here)
  Font.draw(tostring(mon.level), 8 * 8, 7 * 8)
  -- PrintMonType at (3,9) / +2 rows for type 2
  if t1 then
    Font.draw(TypeChart.displayName(t1), 3 * 8, 9 * 8)
  end
  if dual then
    Font.draw(TypeChart.displayName(t2), 3 * 8, 11 * 8)
  end
end

-- Bottom HALL OF FAME banner: TextBoxBorder (2,13) b=3,c=14
function HallOfFame:drawHofBanner()
  Font.drawBox(2, 13, 16, 5)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("HALL OF FAME"), 4 * 8, 15 * 8)
end

function HallOfFame:drawPic(img)
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, self.scrollX or PIC_X, PIC_Y)
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

function HallOfFame:drawDexBox(kind)
  local save = self.game.save
  local text = self.game.data.text or {}
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  if kind == "seen" then
    local seen, owned = self:dexSeenOwned()
    local seenOwned = text._DexSeenOwnedText
      or Strings("POKéDEX   Seen:{NUM:wDexRatingNumMonsSeen, 1, 3}\n         Owned:{NUM:wDexRatingNumMonsOwned, 1, 3}")
    seenOwned = seenOwned
      :gsub("{NUM:wDexRatingNumMonsSeen[^}]*}", tostring(seen))
      :gsub("{NUM:wDexRatingNumMonsOwned[^}]*}", tostring(owned))
    drawTextBlock(seenOwned, 1 * 8, 14 * 8, 17 * 8)
  else
    local _, owned = self:dexSeenOwned()
    local ratingHeader = (text._DexRatingText or Strings("POKéDEX Rating{COLON}")):gsub("{COLON}", ":")
    Font.draw(ratingHeader, 1 * 8, 14 * 8)
    local rating = text[dexRatingKey(owned)] or Strings("Keep it up!")
    drawTextBlock(rating, 1 * 8, 15 * 8, 17 * 8)
  end
end

function HallOfFame:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  if self.phase == "mons" or self.phase == "fade" then
    local mon = self.game.save.party[self.index]
    if mon then
      self:drawPic(self:spriteFor(mon.species))
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
    self:drawPic(self.playerPic)
  elseif self.phase == "player_stats" then
    self:drawPic(self.playerPic)
    self:drawPlayerStats()
  elseif self.phase == "player_dex" then
    self:drawPic(self.playerPic)
    self:drawPlayerStats()
    self:drawDexBox("seen")
  elseif self.phase == "player_rating" then
    self:drawPic(self.playerPic)
    self:drawPlayerStats()
    self:drawDexBox("rating")
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return HallOfFame
