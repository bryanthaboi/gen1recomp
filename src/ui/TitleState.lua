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
    -- A DMG-grays zone, not the trueColor opt-out: through the shade-remap
    -- shader GRAYS is the identity for the box's four shades, so SGB /
    -- ADVANCED / OG modes keep #133's white paper and black ink exactly,
    -- while effectiveColors still substitutes the mono and inverted display
    -- modes -- a trueColor rect skipped the shader entirely, leaving the
    -- main menu and CONTINUE info box a raw white hole over a CLASSIC
    -- pea-green title instead of matching it like the START menu does (#870).
    z[#z + 1] = P.zone(P.GRAYS, box[1], box[2], box[3], box[4])
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
-- ..(engine/movie/title.asm ln 227)
local HOLD_FRAMES = 200
local STARTERS = { CHARMANDER = true, SQUIRTLE = true, BULBASAUR = true }

-- ..(engine/movie/title2.asm ln 13)
local function scrollFrames(steps, offset)
  local frames = {}
  for _, step in ipairs(steps) do
    for _ = 1, step[2] do
      frames[#frames + 1] = offset
      offset = offset - step[1]
    end
  end
  return frames
end
local OUT_FRAMES = scrollFrames(
  { { 1, 2 }, { 2, 2 }, { 3, 2 }, { 4, 2 }, { 5, 2 }, { 6, 2 },
    { 8, 3 }, { 9, 3 } }, 0)
local IN_FRAMES = scrollFrames(
  { { 10, 2 }, { 9, 4 }, { 8, 4 }, { 6, 3 }, { 5, 2 }, { 3, 1 },
    { 1, 1 } }, 120)

-- ..(engine/movie/title2.asm ln 85)
local BALL_FRAMES = { 97, 95, 94, 93, 92, 93, 94, 95, 97, 100 }
local BALL_REST = 100

local function tryImage(path)
  if not path then return nil end
  -- resolve through Assets so a mod's derived art (save/mod-derived/)
  -- wins here the way it does for every other generated sheet -- but
  -- load uncached, because on NX the per-version overlay redirects the
  -- open itself and a cached image would leak across Yellow/Blue boots
  local ok, img = pcall(love.graphics.newImage,
    require("src.render.Assets").resolve(path))
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

-- ..(engine/movie/title.asm ln 321)
local function replayObjSprite(game, image, quad, x, y)
  local P = require("src.render.PaletteFX")
  if not P.usesSpriteObp() then return end
  local top = game.stack and game.stack:top()
  local box = top and top.titleUiBox
  if box then
    local w, h
    if quad then
      w, h = select(3, quad:getViewport())
    else
      w, h = image:getDimensions()
    end
    if x < (box[3] + 1) * 8 and x + w > box[1] * 8
       and y < (box[4] + 1) * 8 and y + h > box[2] * 8 then
      return
    end
  end
  P.markUiSpriteRedraw(image, quad, x, y)
end

function TitleState.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TitleState)
  self.game = game
  self.onNewGame = opts.onNewGame
  self.onContinue = opts.onContinue
  self.onExit = opts.onExit
  -- branding comes from field.title with the shipped art as fallback, so
  -- a total conversion rebrands the title without replacing the screen
  local title = (game.data.field and game.data.field.title) or {}
  -- field.title itself is extraction data the field schema never exposes;
  -- boot.title is the mod-reachable half of the same seam, so its keys
  -- override here (a localized ribbon, a rebranded logo)
  local boot = game.data.field and game.data.field.boot
  if boot and type(boot.title) == "table" then
    local merged = {}
    for key, value in pairs(title) do merged[key] = value end
    for key, value in pairs(boot.title) do merged[key] = value end
    title = merged
  end
  self.title = title
  self.logo = tryImage(imagePath(title.logo)
                       or "assets/logo/pokemon_logo.png")
  -- versionRibbon is the file-12 key; version is the importer's.  The
  -- vanilla sheet is two fragments the draw pass repositions, so an
  -- explicit ribbon (a conversion's or a translation's continuous art)
  -- draws whole instead.
  self.versionFull = imagePath(title.versionRibbon) ~= nil
  self.version = tryImage(imagePath(title.versionRibbon or title.version)
                          or "assets/generated/title/red_version.png")
  self.playerPath = imagePath(title.player)
                    or "assets/generated/title/player.png"
  self.player = tryImage(self.playerPath)
  -- ..(engine/movie/title2.asm ln 85)
  if self.player then
    local pw, ph = self.player:getDimensions()
    self.ballQuad = love.graphics.newQuad(0, 16, 8, 8, pw, ph)
    self.playerQuads = {
      { love.graphics.newQuad(0, 0, pw, 16, pw, ph), 0, 0 },
      { love.graphics.newQuad(8, 16, pw - 8, 8, pw, ph), 8, 16 },
      { love.graphics.newQuad(0, 24, pw, ph - 24, pw, ph), 0, 24 },
    }
  end
  self.copyImg = tryImage(imagePath(title.copyright)
                          or "assets/generated/title/copyright.png")
  self.copyQuads = {}
  if self.copyImg then
    local iw, ih = self.copyImg:getDimensions()
    for t = 0, 18 do
      self.copyQuads[t] = love.graphics.newQuad(t * 8, 0, 8, 8, iw, ih)
    end
  end
  self.gfInc = tryImage(imagePath(title.gamefreakInc)
                        or "assets/generated/title/gamefreak_inc.png")
  self.blue = GameVersion.isBlue()
  self.yellow = GameVersion.isYellow()
    or title.layout == "yellow_pikachu"
  -- ..(pokeyellow engine/movie/title.asm .tileScreenCopyrightTiles / NineTile)
  self.nineImg = self.yellow and tryImage(imagePath(title.nine)
    or "assets/generated/title/nine.png") or nil
  self.copyPrefix = self.yellow
    and { 0, 1, 2, 3, 1, 2 } or { 0, 1, 2, 1, 3, 1, 4 }
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
    -- ..(engine/movie/title.asm ln 28)
    self.scy = 0x40
    self.phase = "drop"
    self.dropStep, self.dropLeft = 1, nil
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
  self.scrollPhase = "hold"
  self.scrollFrame = 1
  self.monOffset = 0
  self.ballY = BALL_REST
  return self
end

function TitleState:enter()
  if self.phase ~= "loop" then return end
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
local SETTLE_FRAMES = 36

-- ..(engine/movie/title.asm ln 201)
local RIBBON_FRAMES = {}
for offset = 112, 4, -4 do RIBBON_FRAMES[#RIBBON_FRAMES + 1] = offset end

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
    self.timer = self.timer + 1
    if self.timer >= SETTLE_FRAMES then
      self.whooshSrc = Sound.play(data, "Intro_Whoosh")
      self.showBubble = true
      self.phase = self.yellowLayout and "bubble" or "ribbon"
      self.ribbonOffset = RIBBON_FRAMES[1]
      self.timer = 0
    end
  elseif self.phase == "ribbon" then
    self.timer = self.timer + 1
    local offset = RIBBON_FRAMES[self.timer + 1]
    if offset then
      self.ribbonOffset = offset
    else
      -- title.asm: Delay3 then WaitForSoundToFinish before MUSIC_TITLE_SCREEN
      self.ribbonOffset = nil
      self.phase = "preMusic"
      self.timer = 0
    end
  elseif self.phase == "preMusic" then
    self.timer = self.timer + 1
    local playing = self.whooshSrc and self.whooshSrc.isPlaying
      and self.whooshSrc:isPlaying()
    if self.timer >= 3 and (not playing or self.timer > 180) then
      self.whooshSrc = nil
      self:startMusic()
      self.phase = "loop"
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
  -- the name follows the label's real width (one space after it), so a
  -- localized label longer than PLAYER's six glyphs cannot run into it
  local playerLabel = Strings("PLAYER")
  Font.draw(playerLabel, 40, 72)
  Font.draw((save.player and save.player.name) or "RED",
    math.max(96, 40 + (#Font.split(playerLabel) + 1) * 8), 72)
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
    if self.onExit then
      self.onExit()
    elseif love.event and love.event.quit then
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
  -- full-width title LOGO zones would recolor this box; see sgbPalettes.
  -- Menu.new may have grown tw for longer (e.g. localized) labels, so the
  -- recolor zone follows the box's real width instead of the vanilla 13.
  menu.titleUiBox = { 0, 0, menu.tw - 1, th - 1 }
  game.stack:push(menu)
end

-- ..(engine/movie/title.asm ln 271)
function TitleState:pickNewMon()
  if #self.cycleSpecies < 2 then return end
  local pick = self.cycleIndex
  while pick == self.cycleIndex do
    pick = love.math.random(1, #self.cycleSpecies)
  end
  self.cycleIndex = pick
end

function TitleState:setCyclePhase(phase)
  self.scrollPhase = phase
  self.scrollFrame = 1
  self.timer = 0
  if phase == "in" then
    self:pickNewMon()
    self.monOffset = IN_FRAMES[1]
  elseif phase == "out" then
    self.monOffset = OUT_FRAMES[1]
  elseif phase == "ball" then
    self.ballY = BALL_FRAMES[1]
  else
    self.monOffset = 0
  end
end

function TitleState:updateCycle()
  local phase = self.scrollPhase
  if phase == "hold" then
    if self.timer >= HOLD_FRAMES then self:setCyclePhase("out") end
    return
  end
  local frames = phase == "out" and OUT_FRAMES
              or phase == "ball" and BALL_FRAMES or IN_FRAMES
  self.scrollFrame = self.scrollFrame + 1
  local value = frames[self.scrollFrame]
  if value then
    if phase == "ball" then self.ballY = value else self.monOffset = value end
    return
  end
  if phase == "out" then
    -- ..(engine/movie/title.asm ln 235)
    self:setCyclePhase(
      STARTERS[self.cycleSpecies[self.cycleIndex]] and "ball" or "in")
  elseif phase == "ball" then
    self:setCyclePhase("in")
  else
    self:setCyclePhase("hold")
  end
end

function TitleState:update(dt)
  if self.phase ~= "loop" then
    self:updateSequence()
    return
  end
  if self.yellowLayout then
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
  self:updateCycle()
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

-- ..(engine/movie/title.asm ln 28)
function TitleState:draw()
  local PaletteFX = require("src.render.PaletteFX")
  local playerImage = self.player
  if playerImage and PaletteFX.usesSpriteObp() then
    playerImage = require("src.render.SpriteRenderer").obpImage(
      self.playerPath, PaletteFX.ogObj())
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local scrollY = -(self.scy or 0)
  -- ..(engine/movie/title.asm ln 28)
  local preRibbon = not self.yellowLayout
    and (self.phase == "drop" or self.phase == "settle")
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
    if self.version and not self.yellow and not preRibbon then
      local iw, ih = self.version:getDimensions()
      local rx = self.ribbonOffset or 0
      if self.versionFull then
        -- a continuous ribbon (versionRibbon) centers as one piece
        love.graphics.draw(self.version, math.floor((160 - iw) / 2) + rx, 64)
      elseif self.blue then
        love.graphics.draw(self.version,
          love.graphics.newQuad(0, 0, 64, 8, iw, ih), 56 + rx, 64)
      else
        love.graphics.draw(self.version,
          love.graphics.newQuad(0, 0, 16, 8, iw, ih), 56 + rx, 64)
        love.graphics.draw(self.version,
          love.graphics.newQuad(40, 0, 40, 8, iw, ih), 80 + rx, 64)
      end
    end
    local sprite, spriteTrueColor
    if self.scrollPhase ~= "ball" then
      sprite, spriteTrueColor = self:currentSprite()
    end
    if sprite then
      local w, h = sprite:getDimensions()
      local x = 40 + math.floor((56 - w) / 2) + self.monOffset
      local y = 136 - h
      love.graphics.draw(sprite, x, y)
      -- SGB: the mon keeps its palette minus the strip Red's OAM covers
      -- (#350); Yellow never reaches here (title_yellow.asm)
      if spriteTrueColor then
        local cover
        if playerImage and not require("src.render.PaletteFX").usesSpriteObp() then
          local pw, ph = playerImage:getDimensions()
          cover = { 82, 80, pw, ph }
        end
        markVisibleTrueColor(x, y, w, h, cover)
      end
    end
    -- Red is OAM in the original: he draws over the mon's box edge
    if self.playerQuads then
      for _, part in ipairs(self.playerQuads) do
        love.graphics.draw(playerImage, part[1], 82 + part[2], 80 + part[3])
        replayObjSprite(self.game, playerImage, part[1], 82 + part[2], 80 + part[3])
      end
      love.graphics.draw(playerImage, self.ballQuad, 82, self.ballY)
      replayObjSprite(self.game, playerImage, self.ballQuad, 82, self.ballY)
    elseif playerImage then
      love.graphics.draw(playerImage, 82, 80)
      replayObjSprite(self.game, playerImage, nil, 82, 80)
    end
  end
  self:drawCopyright(136 + (preRibbon and 0 or scrollY))
end

function TitleState:drawCopyright(y)
  if not self.title.copyrightText and self.copyImg and self.gfInc then
    local x = 16
    for _, t in ipairs(self.copyPrefix) do
      love.graphics.draw(self.copyImg, self.copyQuads[t], x, y)
      x = x + 8
    end
    if self.nineImg then
      love.graphics.draw(self.nineImg, x, y)
      x = x + 8
    end
    love.graphics.draw(self.gfInc, x, y)
    return
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.title.copyrightText or Strings("GAME FREAK inc."), 16, y)
  love.graphics.setColor(1, 1, 1, 1)
end

return TitleState
