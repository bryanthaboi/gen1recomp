-- Title screen (engine/movie/title.asm + engine/menus/main_menu.asm):
-- the logo (or a text fallback while the asset is missing), a cycling
-- Pokémon front sprite, the copyright line, and the CONTINUE / NEW GAME
-- / OPTION / EXIT GAME main menu on START or A.

local Font = require("src.render.Font")
local Music = require("src.core.Music")
local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Runtime = require("src.mods.Runtime")
local Logger = require("src.core.Logger")

local TitleState = {}
TitleState.__index = TitleState
TitleState.isOpaque = true

-- Fill the window (aspect preserved, bars on the long axis) instead of sitting
-- at the fixed integer scale.  The title screen is a full-bleed picture with no
-- world behind it, so a small centred box in a large window is just wasted
-- glass -- and unlike the overworld it has no zoom the player chose to respect.
function TitleState:wantsFillScale() return true end

-- SGB title zones (PalPacket_Titlescreen): the logo rows get LOGO2,
-- the version-ribbon band LOGO1, the rest MEWMON.
--
-- The CONTINUE / NEW GAME menu and the continue-info box sit inside those
-- LOGO bands.  pokered's MainMenu clears the title and runs
-- RunDefaultPaletteCommand so black UI ink stays black; this port keeps the
-- title art visible underneath, so without an overlay those boxes inherit
-- LOGO2 blue / LOGO1 red (issue #133).  A trailing trueColor zone leaves the
-- overlay's DMG black unshaded while the logo and title mon keep title pals.
--
-- Every title SuperPal shares color 0 on hardware (sgb_palettes.asm: LOGO1,
-- LOGO2 and MEWMON all start RGB 31,29,31), so the ribbon band's white has to
-- be the neighbouring zones' white.  Under RED++, LOGO2/MEWMON come from the
-- GBC pack (pure white) while Blue's LOGO1 stays on the ROM pack (#128) and
-- the row reads as a pink band; taking LOGO2's white fixes that without
-- forcing pure white in SGB, where a brighter band drew two faint lines
-- across the title (#373).  Ink colors (Blue/Red "Version" text) stay intact.
local function withWhiteOf(pal, ref)
  if not pal then return nil end
  if not (ref and ref[1]) then return pal end
  return { ref[1], pal[2], pal[3], pal[4] }
end

function TitleState:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local z
  if self.yellowLayout then
    -- Yellow's BlkPacket_Titlescreen (pokeyellow data/sgb/sgb_packets.asm):
    -- rows 0-7 logo band pal 0 (PAL_LOGO2), rows 8-17 Pikachu + copyright
    -- pal 2 (PAL_MEWMON), then the two bubble-tail cells at (9,8)-(10,8)
    -- back on pal 0.  No Red/Blue LOGO1 ribbon band.
    local logoPal = P.pal(game.data, "LOGO2")
    z = {
      P.zone(logoPal, 0, 0, 19, 7),
      P.zone(P.pal(game.data, "MEWMON"), 0, 8, 19, 17),
      P.zone(logoPal, 9, 8, 10, 8),
    }
  else
    local logoPal = P.pal(game.data, "LOGO2")
    z = {
      P.zone(logoPal, 0, 0, 19, 7),
      P.zone(withWhiteOf(P.pal(game.data, "LOGO1"), logoPal), 0, 8, 19, 9),
      P.zone(P.pal(game.data, "MEWMON"), 0, 10, 19, 17),
    }
  end
  local top = game.stack and game.stack:top()
  local box = top and top.titleUiBox
  if box then
    z[#z + 1] = P.trueColorZone(box[1], box[2], box[3], box[4])
  end
  return z[3] and z or nil
end

-- the Red-version TitleMons list (data/pokemon/title_mons.asm):
-- TitleScreenPickNewMon draws a random, never-repeating pick from it;
-- field.title.cycleSpecies replaces it wholesale
local CYCLE_SPECIES = {
  "CHARMANDER", "SQUIRTLE", "BULBASAUR", "WEEDLE", "NIDORAN_M", "SCYTHER",
  "PIKACHU", "CLEFAIRY", "RHYDON", "ABRA", "GASTLY", "DITTO",
  "PIDGEOTTO", "ONIX", "PONYTA", "MAGIKARP",
}
-- Blue's TitleMons (data/pokemon/title_mons.asm, _BLUE branch): STARTER2 is
-- Squirtle, STARTER1 Charmander, STARTER3 Bulbasaur.
local BLUE_CYCLE_SPECIES = {
  "SQUIRTLE", "CHARMANDER", "BULBASAUR", "MANKEY", "HITMONLEE",
  "VULPIX", "CHANSEY", "AERODACTYL", "JOLTEON", "SNORLAX",
  "GLOOM", "POLIWAG", "DODUO", "PORYGON", "GENGAR", "RAICHU",
}
-- Yellow has no TitleMons table (engine/movie/title_yellow.asm is a fixed
-- Pikachu title).  Until field.title.cycleSpecies is imported, keep a short
-- Pikachu-centric list so the Red/Blue cycling UI still has something to show.
local YELLOW_CYCLE_SPECIES = {
  "PIKACHU", "EEVEE", "BULBASAUR", "CHARMANDER", "SQUIRTLE",
  "JIGGLYPUFF", "MEOWTH", "PSYDUCK", "VULPIX", "ABRA",
  "GROWLITHE", "CUBONE", "GASTLY", "HITMONLEE", "SNORLAX", "DRAGONITE",
}
local CYCLE_FRAMES = 240 -- the original waits ~4s between picks

local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil
end

-- the importer seeds field.title with {path,width,height} descriptors
-- (the shape IntroMovie unwraps); mod patches may use plain path strings
local function imagePath(entry)
  if type(entry) == "table" then return entry.path end
  return entry
end

-- PaletteFX redraws a true-color rectangle after the palette pass.  Red's
-- title art is drawn on top of the title mon, so leave its bounds out of the
-- rectangle rather than redrawing that art without its title palette.
local function markVisibleTrueColor(x, y, w, h, cover)
  local P = require("src.render.PaletteFX")
  if not cover then
    P.markTrueColor(x, y, w, h)
    return
  end
  local cx, cy, cw, ch = cover[1], cover[2], cover[3], cover[4]
  local right, bottom = x + w, y + h
  local cright, cbottom = cx + cw, cy + ch
  local ix1, iy1 = math.max(x, cx), math.max(y, cy)
  local ix2, iy2 = math.min(right, cright), math.min(bottom, cbottom)
  if ix1 >= ix2 or iy1 >= iy2 then
    P.markTrueColor(x, y, w, h)
    return
  end
  if y < iy1 then P.markTrueColor(x, y, w, iy1 - y) end
  if iy2 < bottom then P.markTrueColor(x, iy2, w, bottom - iy2) end
  if x < ix1 then P.markTrueColor(x, iy1, ix1 - x, iy2 - iy1) end
  if ix2 < right then P.markTrueColor(ix2, iy1, right - ix2, iy2 - iy1) end
end

function TitleState.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TitleState)
  self.game = game
  self.onNewGame = opts.onNewGame
  self.onContinue = opts.onContinue
  -- branding comes from field.title with the shipped art as fallback, so
  -- a total conversion rebrands the title without replacing the screen
  local title = (game.data.field and game.data.field.title) or {}
  self.title = title
  self.logo = tryImage(imagePath(title.logo)
                       or "assets/logo/pokemon_logo.png")
  -- versionRibbon is the file-12 key; version is the importer's
  self.version = tryImage(imagePath(title.versionRibbon or title.version)
                          or "assets/generated/title/red_version.png")
  self.player = tryImage("assets/generated/title/player.png")
  self.blue = GameVersion.isBlue()
  self.yellow = GameVersion.isYellow()
    or title.layout == "yellow_pikachu"
  -- Yellow title is a fixed Pikachu composition (title_yellow.asm), not
  -- TitleMons cycling.  Prefer composed pikachu.png from the Yellow import.
  self.yellowPikachu = self.yellow and tryImage(imagePath(title.pikachu)
    or "assets/generated/title/pikachu.png") or nil
  self.yellowBubble = self.yellow and tryImage(imagePath(title.pikaBubble)
    or "assets/generated/title/pika_bubble.png") or nil
  self.yellowLayout = self.yellow and self.yellowPikachu ~= nil
  if self.yellowLayout then
    -- title.asm boot: hSCY starts at $40 with the logo parked above the
    -- viewport; .bouncePokemonLogoLoop drops it in with an overshoot
    -- bounce, then the whoosh, the speech bubble, and PikachuCry1 before
    -- the title music starts.  Blink overlays are the OB tile swaps of
    -- DoTitleScreenFunction.
    self.eyesHalf = tryImage("assets/generated/title/eyes_half.png")
    self.eyesClosed = tryImage("assets/generated/title/eyes_closed.png")
    self.scy = 0x40
    self.phase = "drop"
    self.dropStep, self.dropLeft = 1, nil
    self.showBubble = false
    self.blinkTimer = 0
    self.blinkAt = nil
  else
    self.phase = "loop"
    self.showBubble = true
  end
  local defaultCycle = self.yellowLayout and { "PIKACHU" }
                    or (self.yellow and YELLOW_CYCLE_SPECIES)
                    or (self.blue and BLUE_CYCLE_SPECIES or CYCLE_SPECIES)
  self.cycleSpecies = (type(title.cycleSpecies) == "table"
                       and #title.cycleSpecies > 0)
                      and title.cycleSpecies or defaultCycle
  self.sprites = {} -- species -> { image, trueColor } or false (load failed)
  self.cycleIndex = 1
  self.timer = 0
  self.blink = 0
  return self
end

function TitleState:enter()
  -- Yellow defers the title theme until after the logo drop and
  -- Pikachu's cry (title.asm plays MUSIC_TITLE_SCREEN only after
  -- WaitForSoundToFinish on PikachuCry1)
  if self.yellowLayout then return end
  self:startMusic()
end

function TitleState:startMusic()
  local data = self.game.data
  local song = self.title.music or "Music_TitleScreen"
  if data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
end

-- .TitleScreenPokemonLogoYScrolls: { dy per frame, frames }; the -3
-- rebound step lands with SFX_INTRO_CRASH
local DROP_STEPS = {
  { -4, 16 }, { 3, 4 }, { -3, 4 }, { 2, 2 }, { -2, 2 }, { 1, 2 }, { -1, 2 },
}

-- the boot cinematic up to the interactive loop; one call per frame
function TitleState:updateSequence()
  local Sound = require("src.core.Sound")
  local data = self.game.data
  if self.phase == "drop" then
    local step = DROP_STEPS[self.dropStep]
    if not step then
      self.phase = "settle"
      self.timer = 0
      return
    end
    if self.dropLeft == nil then
      self.dropLeft = step[2]
      if step[1] == -3 then Sound.play(data, "Intro_Crash") end
    end
    self.scy = self.scy + step[1]
    self.dropLeft = self.dropLeft - 1
    if self.dropLeft <= 0 then
      self.dropStep = self.dropStep + 1
      self.dropLeft = nil
    end
  elseif self.phase == "settle" then
    -- ld c, 36 / DelayFrames, then the whoosh and the bubble
    self.timer = self.timer + 1
    if self.timer >= 36 then
      Sound.play(data, "Intro_Whoosh")
      self.showBubble = true
      self.phase = "bubble"
      self.timer = 0
    end
  elseif self.phase == "bubble" then
    self.timer = self.timer + 1
    if self.timer >= 3 then
      self.crySrc = Sound.playPikaCry(data, 1)
      self.phase = "cry"
      self.timer = 0
    end
  elseif self.phase == "cry" then
    -- WaitForSoundToFinish before the music starts
    self.timer = self.timer + 1
    local playing = self.crySrc and self.crySrc.isPlaying
      and self.crySrc:isPlaying()
    if not playing or self.timer > 180 then
      self.crySrc = nil
      self:startMusic()
      self.phase = "loop"
      self.blinkTimer = 0
    end
  end
end

-- DoTitleScreenFunction.CheckTimer: an 8-bit frame counter blinks at 0,
-- $80 and $90; the blink itself runs half/closed/half over 9 frames
function TitleState:updateBlink()
  local t = self.blinkTimer
  self.blinkTimer = (t + 1) % 256
  if t == 0 or t == 0x80 or t == 0x90 then self.blinkAt = 0 end
  if self.blinkAt then
    self.blinkAt = self.blinkAt + 1
    if self.blinkAt > 9 then self.blinkAt = nil end
  end
end

-- the blink overlay for this frame (nil = open eyes)
function TitleState:blinkOverlay()
  local at = self.blinkAt
  if not at then return nil end
  if at <= 3 or at > 6 then return self.eyesHalf end
  return self.eyesClosed
end

function TitleState:currentSprite()
  local species = self.cycleSpecies[self.cycleIndex]
  local cached = self.sprites[species]
  if cached == nil then
    local path, trueColor = require("src.pokemon.Sprites").path(
      self.game.data, species, "front", { kind = "title" })
    local image = tryImage(path)
    cached = image and { image = image, trueColor = trueColor } or false
    self.sprites[species] = cached
  end
  return cached and cached.image or nil, cached and cached.trueColor or false
end

local function hasSave()
  local ok, info = pcall(function()
    -- the active game's save file (save.lua for Red, save_blue.lua for Blue)
    local name = require("src.core.SaveData").saveFilename(GameVersion.get())
    return love.filesystem and love.filesystem.getInfo
       and love.filesystem.getInfo(name) or nil
  end)
  return ok and info ~= nil
end

local function sameItems(_, items) return items end

-- The CONTINUE info window (main_menu.asm DisplayContinueGameInfo):
-- PLAYER / BADGES / POKéDEX / TIME over the title, shown after choosing
-- CONTINUE.  A confirms and loads the game, B returns to the main menu.
local ContinueInfo = {}
ContinueInfo.__index = ContinueInfo

function ContinueInfo.new(title, save)
  -- box at (4,7), 16x10 tiles -- see ContinueInfo:draw / DisplayContinueGameInfo
  return setmetatable({
    title = title, game = title.game, save = save,
    titleUiBox = { 4, 7, 19, 16 },
  }, ContinueInfo)
end

function ContinueInfo:update(dt)
  local input = self.game.input
  if input:wasPressed("a") then
    self.game.stack:pop()
    if self.title.onContinue then self.title.onContinue() end
  elseif input:wasPressed("b") then
    self.game.stack:pop()
    self.title:openMenu()
  end
end

function ContinueInfo:draw()
  local save = self.save
  -- box at (4,7), 8x14 content; labels double-spaced from (5,9)
  Font.drawBox(4, 7, 16, 10)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("PLAYER"), 40, 72)
  Font.draw((save.player and save.player.name) or "RED", 96, 72)
  local badges = require("src.inventory.Badges").count(self.game.data, save)
  Font.draw(Strings("BADGES"), 40, 88)
  Font.draw(("%2d"):format(badges), 128, 88)
  local owned = 0
  for _ in pairs(save.pokedex and save.pokedex.owned or {}) do
    owned = owned + 1
  end
  Font.draw(Strings("POKéDEX"), 40, 104)
  Font.draw(("%3d"):format(owned), 120, 104)
  local t = math.floor(save.playTime or 0)
  Font.draw(Strings("TIME"), 40, 120)
  Font.draw(("%3d:%02d"):format(math.floor(t / 3600),
                                math.floor(t / 60) % 60), 104, 120)
  love.graphics.setColor(1, 1, 1, 1)
end

function TitleState:openMenu()
  local Menu = require("src.ui.Menu")
  local game = self.game
  local items = {}
  if hasSave() then
    table.insert(items, { label = Strings("CONTINUE"), onSelect = function()
      -- peek at the save for the info window; fall through if the
      -- file can't be read
      local ok, loaded = pcall(require("src.core.SaveData").load)
      if ok and loaded then
        game.stack:push(ContinueInfo.new(self, loaded))
      elseif self.onContinue then
        self.onContinue()
      end
    end })
  end
  table.insert(items, { label = Strings("NEW GAME"), onSelect = function()
    if self.onNewGame then self.onNewGame() end
  end })
  table.insert(items, { label = Strings("OPTION"), onSelect = function()
    require("src.ui.Screens").push(game, "OptionsMenu")
  end })
  table.insert(items, { label = Strings("EXIT GAME"), onSelect = function()
    if love.event and love.event.quit then
      love.event.quit()
    end
  end })
  local hooked = Runtime.call("ui.title_menu.items", sameItems, game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.title_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end
  local th = #items * 2 + 2
  local menu = Menu.new(game, items, { tx = 0, ty = 0, tw = 13, th = th })
  -- full-width title LOGO zones would recolor this box; see sgbPalettes
  menu.titleUiBox = { 0, 0, 12, th - 1 }
  game.stack:push(menu)
end

function TitleState:update(dt)
  if self.yellowLayout then
    if self.phase ~= "loop" then
      self:updateSequence()
      return -- input is ignored until the cinematic lands (title.asm)
    end
    self:updateBlink()
    local input = self.game.input
    if input:wasPressed("start") or input:wasPressed("a") then
      -- .go_to_main_menu voices PikachuCry11 on the way out
      local Sound = require("src.core.Sound")
      if not Sound.playPikaCry(self.game.data, 11) then
        Sound.playCry(self.game.data, "PIKACHU")
      end
      self:openMenu()
    end
    return
  end
  self.timer = self.timer + 1
  self.blink = (self.blink + 1) % 60
  if not self.yellowLayout and self.timer >= CYCLE_FRAMES then
    self.timer = 0
    -- random pick that never repeats the current one
    if #self.cycleSpecies > 1 then
      local pick = self.cycleIndex
      while pick == self.cycleIndex do
        pick = love.math.random(1, #self.cycleSpecies)
      end
      self.cycleIndex = pick
    end
    self.slideIn = 20 -- TitleScreenScrollInMon slides the pic in
  end
  if self.slideIn and self.slideIn > 0 then
    self.slideIn = self.slideIn - 1
  end
  local input = self.game.input
  if input:wasPressed("start") or input:wasPressed("a") then
    -- the title mon cries when you leave the title (.finishedWaiting);
    -- Yellow's fixed Pikachu title always cries Pikachu.
    require("src.core.Sound").playCry(self.game.data,
      self.yellowLayout and "PIKACHU"
      or self.cycleSpecies[self.cycleIndex])
    self:openMenu()
  end
end

-- The original tilemap (engine/movie/title.asm): logo at tile (2,1),
-- the version ribbon at (7,8), Red's title art as OAM at px (82,80),
-- the title mon in the 7x7 box at tile (5,10), copyright on row 17.
-- Yellow (title_yellow.asm): logo (2,1), speech bubble (6,4), Pikachu
-- (4,8) 12x9 -- no version ribbon, no cycling mon, no Red OAM.
function TitleState:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local scrollY = self.yellowLayout and -(self.scy or 0) or 0
  if self.logo then
    love.graphics.draw(self.logo, 16, 8 + scrollY)
  else
    love.graphics.setColor(0, 0, 0, 1)
    local brand = self.yellow and "POKéMON YELLOW"
               or (self.blue and "POKéMON BLUE" or Strings("POKéMON RED"))
    Font.draw(brand, (160 - 12 * 8) / 2, 24 + scrollY)
    love.graphics.setColor(1, 1, 1, 1)
  end
  if self.yellowLayout then
    -- everything scrolls together through the logo drop (rSCY): screen
    -- y = BG y - SCY, so the composition rides at -scy until it lands
    local dy = scrollY
    if self.yellowBubble and self.showBubble then
      love.graphics.draw(self.yellowBubble, 48, 32 + dy)
    end
    -- hlcoord 4,8 → px (32, 64); composed 13x9 tile sprite
    love.graphics.draw(self.yellowPikachu, 32, 64 + dy)
    local overlay = self:blinkOverlay()
    if overlay then
      -- the eye OAM band sits at (56,80) on the landed screen
      love.graphics.draw(overlay, 32 + 24, 64 + 16 + dy)
    end
  else
    -- Yellow's Version_GFX slot holds a leftover "Blue Version" ribbon
    -- (pokeyellow gfx/title/blue_version.png, unreferenced by title code);
    -- the Yellow fallback layout draws no ribbon at all.
    if self.version and not self.yellow then
      local iw, ih = self.version:getDimensions()
      -- The ribbon is loaded at the END of the VERSION_TILES band
      -- (title.asm: vChars2 tile $60 + (VERSION_TILES tiles - size) / 2), so
      -- a ribbon narrower than the band is right-aligned; the band ends at
      -- px 120.  US Red is the one 80px ribbon, and it is the only one drawn
      -- in two pieces: "RED" (px 0-16) and "VERSION" (px 40-80) with the
      -- unused middle skipped.  Everything else -- US Blue, and the 64px EUR
      -- ribbons (EDICION ROJA/AZUL) -- is one continuous graphic, and
      -- quad-ing 80px out of a 64px image cut the word short (it read past
      -- the image edge).
      if iw == 80 and not self.blue then
        love.graphics.draw(self.version,
          love.graphics.newQuad(0, 0, 16, 8, iw, ih), 56, 64)
        love.graphics.draw(self.version,
          love.graphics.newQuad(40, 0, 40, 8, iw, ih), 80, 64)
      else
        love.graphics.draw(self.version,
          love.graphics.newQuad(0, 0, iw, 8, iw, ih), 120 - iw, 64)
      end
    end
    local sprite, spriteTrueColor = self:currentSprite()
    if sprite then
      local w, h = sprite:getDimensions()
      local slide = (self.slideIn or 0) * 8 -- scroll in from the right
      -- bottom-aligned and centered in the (5,10)-(11,16) tile box
      local x = 40 + math.floor((56 - w) / 2) + slide
      local y = 136 - h
      love.graphics.draw(sprite, x, y)
      -- a full-color mon keeps its own palette through the SGB pass, minus
      -- the strip Red's OAM covers (#350).  Yellow never reaches here: its
      -- layout has no cycling mon and no Red art (title_yellow.asm).
      if spriteTrueColor then
        local cover
        if self.player then
          local pw, ph = self.player:getDimensions()
          cover = { 82, 80, pw, ph }
        end
        markVisibleTrueColor(x, y, w, h, cover)
      end
    end
    -- Red is OAM in the original: he draws over the mon's box edge
    if self.player then
      love.graphics.draw(self.player, 82, 80)
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.title.copyrightText or Strings("2026 bois club games"),
    1, 136 + scrollY)
  love.graphics.setColor(1, 1, 1, 1)
end

return TitleState
