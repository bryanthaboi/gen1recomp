-- The Hall of Fame (pokegold engine/events/halloffame.asm), both halves of it:
-- the induction the champion script runs, and the roster viewer the PC opens.
--
-- Two entry points on the cart, one screen here because they share every
-- drawing routine:
--
--   AnimateHallOfFame   each party member enters (AnimateHOFMonEntrance),
--                       gets DisplayHOFMon plus "New Hall of Famer!", its cry
--                       and 180 frames, then HOF_AnimatePlayerPic ends on the
--                       player's own card
--   _HallOfFamePC       LoadHOFTeam walks the roster newest first and
--                       DisplayHOFMon shows one mon at a time; A is next mon,
--                       START is next team, B leaves
--
-- THE ENTRANCE IS A SCROLL, not a sprite move.  AnimateHOFMonEntrance blanks
-- the whole tilemap, lays ONE pic into it, and then animates hSCX and hSCY:
-- because nothing else is on screen, scrolling the background IS sliding the
-- pic, and that is how it is drawn here.  The two loops are exact --
--
--   HOF_SlideBackpic    hSCX $90, +4 a frame until it reads $70 (56 frames,
--                       the long way round the byte)
--   HOF_SlideFrontpic   hSCX -2 a frame until it reads 0
--
-- -- so the mon's BACK pic sweeps across the screen and off the left, and then
-- the pan reverses and its FRONT pic comes back in from the left and settles
-- at hlcoord 6, 5.  hSCY goes $d0 -> $00 between the two, which is the same
-- wrap-around trick vertically.
--
-- COORDINATES are taken literally off the hlcoord lines, never laid out by
-- eye, and the placements are built as data so tests/gen2_halloffame_test.lua
-- can assert them without a graphics device (the same shape
-- src/ui/gen2/SummaryMenu.lua uses).
--
-- WHAT THE CACHE DOES NOT HAVE.  GetTrainerPic for TRAINER_CLASS CAL -- the
-- 7x7 picture of the player HOF_AnimatePlayerPic ends on -- is not extracted.
-- The player's own 5x7 portrait from the trainer card is, and it is the same
-- character, so that stands in and is padded into the 7x7 block the way
-- PlaceGraphic would.  ProfOaksPCRating, which the cart prints into the bottom
-- box afterwards, needs Oak's PC (still a stub in src/script/gen2/Specials.lua)
-- and so the box is drawn empty, exactly as it is before that farcall.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local CommonText = require("src.core.gen2.CommonText")
local Core = require("src.core.gen2.HallOfFame")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Music = require("src.core.Music")
local Palettes = require("src.world.gen2.Palettes")
local Sound = require("src.core.Sound")
local TileSheet = require("src.ui.gen2.TileSheet")
local Unown = require("src.core.gen2.Unown")

local HallOfFame = {}
HallOfFame.__index = HallOfFame
HallOfFame.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144

-- Where each pic lands.  AnimateHOFMonEntrance puts the backpic at hlcoord
-- 6, 6 and the frontpic at hlcoord 6, 5; HOF_AnimatePlayerPic puts the
-- player's backpic at 6, 6 and the trainer pic at 12, 5.
local BACKPIC_X, BACKPIC_Y = 6, 6
local FRONTPIC_X, FRONTPIC_Y = 6, 5
local TRAINERPIC_X, TRAINERPIC_Y = 12, 5
local PIC_TILES = 7

-- The scroll registers the two slide loops walk.
local SCY_START = 0xd0
local BACKPIC_SCX_START, BACKPIC_SCX_END, BACKPIC_STEP = 0x90, 0x70, 4
local FRONTPIC_STEP = 2
local TRAINER_SCX_START = 0xc0

-- .DisplayNewHallOfFamer: `ld c, 180 / call DelayFrames` after the cry.
local FAMER_FRAMES = 180
-- AnimateHallOfFame .done: RotateThreePalettesRight, then `ld c, 8`.
local END_FRAMES = 8

local HOF_MUSIC = "Music_HallOfFame"

-- The three strings the two modes print at hlcoord 1, 2.  Their leading
-- spaces are load bearing: PrintNum writes the count over the first of them
-- at hlcoord 2, 2, so "    -Time Famer" becomes "  12-Time Famer".
HallOfFame.NEW_FAMER = "New Hall of Famer!"
HallOfFame.TIME_FAMER = "    -Time Famer"
HallOfFame.HOF_MASTER = "    HOF Master!"

-- ...and the labels they live under in the cart.  All three are plain
-- `db "…@"` inside engine/events/halloffame.asm rather than text streams, so
-- nothing but the routine that prints them names them.
local LABELS = {
  NEW_FAMER = "AnimateHallOfFame.String_NewHallOfFamer",
  TIME_FAMER = "_HallOfFamePC.TimeFamer",
  HOF_MASTER = "_HallOfFamePC.HOFMaster",
}

HallOfFame.LABELS = LABELS

-- PadFrontpic centres a 5x5 or 6x6 pic inside the 7x7 block, same table the
-- stats screen and the dex use.
local PIC_PAD = { [7] = { 0, 0 }, [6] = { 1, 1 }, [5] = { 1, 2 } }

local WHITE = { 255, 255, 255 }

--------------------------------------------------------------------------
-- Placements
--------------------------------------------------------------------------

local function put(list, text, x, y)
  if text == nil then return list end
  list[#list + 1] = { text = tostring(text), x = x, y = y }
  return list
end

-- The text a placement list writes at a coordinate, or nil.
function HallOfFame.at(placements, x, y)
  for _, entry in ipairs(placements or {}) do
    if entry.x == x and entry.y == y then return entry.text end
  end
  return nil
end

local function levelText(level)
  level = math.max(1, math.floor(tonumber(level) or 1))
  -- PrintLevel: a three-digit level does `dec hl` first so the digits
  -- overwrite the <LV> tile and the field starts at the same column.
  if level >= 100 then return tostring(level) end
  return "<LV>" .. tostring(level)
end

-- GetGender's three answers: carry for a genderless species (a space is
-- written), then non-zero male, zero female.
local function genderGlyph(gender)
  if gender == "male" then return "♂" end
  if gender == "female" then return "♀" end
  return nil
end

-- DisplayHOFMon, hlcoord for hlcoord.  `def` is the species row out of
-- pokemon.lua, for the dex number and the base name the routine gets from
-- GetBasePokemonName -- the roster keeps the NICKNAME, so the species name
-- has to be looked up rather than stored.
function HallOfFame.monPlacements(mon, def)
  mon = mon or {}
  local out = {}
  -- `.print_id_no` is jumped to for an EGG, so everything above it is skipped
  -- and only the ID line prints.  The roster never stores an egg
  -- (GetHallOfFameParty skips them), but the branch is the routine's.
  if mon.species ~= "EGG" then
    -- (1,13) '№' and (2,13) '.' are two `ld [hli]` writes.
    put(out, "№.", 1, 13)
    put(out, Chrome.number(def and def.dex or 0, 3, true), 3, 13)
    put(out, (def and def.name) or mon.species, 7, 13)
    put(out, genderGlyph(mon.gender), 18, 13)
    -- (8,14) is a bare '/', so the nickname starts at (9,14).
    put(out, "/", 8, 14)
    put(out, mon.nickname or mon.name or mon.species, 9, 14)
    put(out, levelText(mon.level), 1, 16)
  end
  -- '<ID>' '№' '/' at (7,16), (8,16), (9,16), then five digits at (10,16).
  put(out, "<ID>№/", 7, 16)
  put(out, Chrome.number(mon.otId or 0, 5, true), 10, 16)
  return out
end

-- The header line, which is the only thing that differs between the induction
-- and the PC's viewer.
--
-- BUG (docs/bugs_and_glitches.md): "HOF Master!" is compared against
-- HOF_MASTER_COUNT + 1 while the counter itself stops AT HOF_MASTER_COUNT, so
-- the title can never print.  Transcribed with the off-by-one intact.
--
-- `text` is data/generated/text.lua: the three strings are seeded into it by
-- name (RomExtractorGen2's NAMED_TEXT) because nothing points at them, and the
-- constants above are what a cache built before that seed falls back to.
function HallOfFame.headerPlacements(mode, winCount, text)
  local out = {}
  local function line(label, fallback)
    local extracted = CommonText.get(text, label)
    return extracted or fallback
  end
  if mode == "induct" then
    put(out, line(LABELS.NEW_FAMER, HallOfFame.NEW_FAMER), 1, 2)
    return out
  end
  winCount = tonumber(winCount) or 0
  if winCount >= Core.MASTER_COUNT + 1 then
    put(out, line(LABELS.HOF_MASTER, HallOfFame.HOF_MASTER), 1, 2)
    return out
  end
  put(out, line(LABELS.TIME_FAMER, HallOfFame.TIME_FAMER), 1, 2)
  put(out, Chrome.number(winCount, 3), 2, 2)
  return out
end

-- HOF_AnimatePlayerPic's text, once both pics have finished sliding.
function HallOfFame.playerPlacements(save)
  save = save or {}
  local player = save.player or {}
  local time = save.playTime or {}
  local out = {}
  put(out, player.name or "GOLD", 2, 4)
  put(out, "<ID>№/", 1, 6)
  put(out, Chrome.number(player.id or 0, 5, true), 4, 6)
  put(out, "PLAY TIME", 1, 8)
  -- `ld de, wGameTimeHours / lb bc, 2, 3`: a two-byte value in three columns,
  -- then HALLOFFAME_COLON, then the minutes with leading zeros in two.
  put(out, Chrome.number(time.hours or 0, 3), 3, 9)
  put(out, ":", 6, 9)
  put(out, Chrome.number(time.minutes or 0, 2, true), 7, 9)
  return out
end

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

function HallOfFame:wantsFillScale() return true end
function HallOfFame:drawsWidescreen() return true end

-- opts:
--   mode      "induct" (default) or "view"
--   save      the record; the roster and the player card come off it
--   entry     induct only: the row HallOfFame.induct just built.  Passed in
--             rather than re-read so the screen shows the party that walked
--             in even if a later save rewrites the roster.
--   text      text.lua, for the extracted header strings
--   onDone()  induct: the credits follow.  view: the PC menu comes back.
function HallOfFame.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, HallOfFame)
  self.game = game
  local data = (game and game.data) or {}
  self.data = data
  self.save = opts.save or (game and game.save)
  self.mode = opts.mode or "induct"
  self.onDone = opts.onDone
  -- text.lua, for the three header strings.  The induction is pushed from the
  -- champion's script and the viewer from the PC, so the world is under both.
  self.textData = opts.text or (game and game.world and game.world.text)
  self.pokemon = opts.pokemon or data.pokemon
  self.palettes = opts.palettes or data.gen2Palettes
  self.picCache = {}
  self.frames = 0
  self.done = false

  -- Hardware registers, the only state the entrance animation has.
  self.scx, self.scy = 0, 0

  -- The player's own two pictures.  The backpic is a plain image (the battle
  -- HUD's), the front is the trainer card's 5x7 portrait tile sheet.
  local menuGfx = data.gen2MenuGfx or {}
  -- player.sprite, the same hook Gen 1's Hall of Fame raises through
  -- Sprites.playerPath (src/ui/HallOfFame.lua:100).
  self.playerBackPath = require("src.pokemon.Sprites").playerPic(
    (menuGfx.battleHud or {}).playerBack,
    { side = "back", kind = "hof", data = data })
  local card = menuGfx.trainerCard
  if card and card.card then
    self.portrait = TileSheet.new({
      path = card.card, wide = card.cardTilesWide or 16, firstTile = 0,
    })
    self.portraitWide = card.portraitWide or 5
    self.portraitTiles = card.portraitTiles or 35
  end

  if self.mode == "view" then
    -- _HallOfFamePC: wJumptableIndex is the team, wHallOfFameMonCounter the
    -- mon inside it, and both start at zero.  An empty roster makes LoadHOFTeam
    -- return carry on its first call, which ends the screen -- but onDone
    -- usually pops this state off the stack, and it has not been pushed yet, so
    -- the callback is deferred to the first update.
    self.team = 1
    self.index = 1
    self.constructing = true
    self:enterView()
    self.constructing = nil
  else
    self.entry = opts.entry or Core.team(self.save, 1)
    self.index = 1
    self:playMusic(HOF_MUSIC)
    self:enterMon()
  end
  return self
end

--------------------------------------------------------------------------
-- Audio
--------------------------------------------------------------------------

function HallOfFame:playMusic(song)
  local audio = self.data and self.data.audio
  if audio and audio.songs and audio.songs[song] then
    -- HallOfFame_PlayMusicDE plays MUSIC_NONE for a frame first, so nothing
    -- of the previous song survives the switch.
    Music.stop()
    Music.play(self.data, song, true, { reason = "halloffame" })
  end
end

function HallOfFame:playCry(species)
  if not species then return end
  local cries = self.data and self.data.audio and self.data.audio.cries
  if cries and cries[species] then Sound.playCry(self.data, species) end
end

--------------------------------------------------------------------------
-- Phases
--------------------------------------------------------------------------

-- The mon the current phase is about, whichever mode is running.
function HallOfFame:currentMon()
  local entry = self.entry
  return entry and entry.mons and entry.mons[self.index] or nil
end

-- AnimateHOFMonEntrance: blank the screen, load the backpic, hSCY $d0 and
-- hSCX $90, then HOF_SlideBackpic.
function HallOfFame:enterMon()
  local mon = self:currentMon()
  if not mon then return self:enterPlayer() end
  self.phase = "backpic"
  self.scy = SCY_START
  self.scx = BACKPIC_SCX_START
  self.timer = 0
end

-- _HallOfFamePC .DisplayMonAndStrings: no entrance at all, the mon is simply
-- displayed.  A team that has run out, or a roster that has, ends the screen.
function HallOfFame:enterView()
  self.entry = Core.team(self.save, self.team)
  if not self.entry then return self:finish() end
  local mon = self:currentMon()
  if not mon then
    -- `.fail` -> carry -> .start_button -> the next team.
    self.team = self.team + 1
    self.index = 1
    return self:enterView()
  end
  self.phase = "display"
  self.scx, self.scy = 0, 0
  self:playCry(mon.species)
end

function HallOfFame:enterDisplay()
  self.phase = "display"
  self.scx, self.scy = 0, 0
  self.timer = FAMER_FRAMES
  self:playCry((self:currentMon() or {}).species)
end

-- HOF_AnimatePlayerPic, which is where AnimateHallOfFame's .done arm lands
-- once the party has run out.
function HallOfFame:enterPlayer()
  self.phase = "playerBack"
  self.scy = SCY_START
  self.scx = BACKPIC_SCX_START
  -- `ld a, $4 / ld [wMusicFade], a` happens at .done, after the player pic;
  -- the music runs under the whole card until then.
end

function HallOfFame:finish()
  if self.done then return end
  self.done = true
  if self.constructing then
    self.pendingDone = true
    return
  end
  if self.onDone then self.onDone() end
end

--------------------------------------------------------------------------
-- Frame loop
--------------------------------------------------------------------------

-- One frame of whichever slide is running.  Returns true when it is over.
local function slideBackpic(self)
  if self.scx == BACKPIC_SCX_END then return true end
  self.scx = (self.scx + BACKPIC_STEP) % 256
  return self.scx == BACKPIC_SCX_END
end

local function slideFrontpic(self)
  if self.scx == 0 then return true end
  self.scx = (self.scx - FRONTPIC_STEP) % 256
  return self.scx == 0
end

-- The induction's own step, one frame at a time.  Split out so the driver and
-- the test can run the whole cinematic without a graphics device.
function HallOfFame:step()
  if self.done then return true end
  self.frames = self.frames + 1

  if self.phase == "backpic" then
    if slideBackpic(self) then
      -- The frontpic is prepared and hSCY zeroed before HOF_SlideFrontpic.
      self.phase = "frontpic"
      self.scy = 0
    end
    return false
  end

  if self.phase == "frontpic" then
    if slideFrontpic(self) then self:enterDisplay() end
    return false
  end

  if self.phase == "display" then
    if self.mode == "view" then return false end
    self.timer = self.timer - 1
    if self.timer > 0 then return false end
    -- `inc [hl]` on wHallOfFameMonCounter, then round the loop; a counter that
    -- reaches PARTY_LENGTH or a -1 species ends it.
    self.index = self.index + 1
    if self.index > Core.PARTY_LENGTH or not self:currentMon() then
      self:enterPlayer()
    else
      self:enterMon()
    end
    return false
  end

  if self.phase == "playerBack" then
    if slideBackpic(self) then
      self.phase = "playerFront"
      self.scy = 0
      self.scx = TRAINER_SCX_START
    end
    return false
  end

  if self.phase == "playerFront" then
    if slideFrontpic(self) then
      self.phase = "player"
      self.timer = END_FRAMES
      -- wMusicFade = 4: the Hall of Fame theme rings out under the card.
      Music.fadeOut(4)
    end
    return false
  end

  if self.phase == "player" then
    self.timer = self.timer - 1
    if self.timer <= 0 then self:finish() end
    return self.done
  end

  return false
end

-- _HallOfFamePC's joypad arms.  A is the next mon, START the next team, B out.
function HallOfFame:viewInput(input)
  if not input then return end
  if input:wasPressed("b") then return self:finish() end
  if input:wasPressed("start") then
    self.team = self.team + 1
    self.index = 1
    return self:enterView()
  end
  if input:wasPressed("a") then
    self.index = self.index + 1
    if self.index > Core.PARTY_LENGTH or not self:currentMon() then
      self.team = self.team + 1
      self.index = 1
    end
    return self:enterView()
  end
end

function HallOfFame:update(_dt)
  if self.pendingDone then
    self.pendingDone = nil
    if self.onDone then self.onDone() end
    return
  end
  if self.done then return end
  if self.mode == "view" then
    self.frames = self.frames + 1
    return self:viewInput(self.game and self.game.input)
  end
  self:step()
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

function HallOfFame:image(path)
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  return cached or nil
end

function HallOfFame:speciesDef(species)
  return species and self.pokemon and self.pokemon[species] or nil
end

-- Takes the RECORD, not the species: the entry carries the two DV bytes
-- precisely so the viewer can name the form.  HOF_ShowMonOrPlayer copies them
-- into wTempMonDVs and runs `predef GetUnownLetter` before GetMonBackpic
-- (engine/events/halloffame.asm:225-238); the frontpic path at :458-468 does
-- the same before _PrepMonFrontpic.
function HallOfFame:monPic(mon, back)
  local def = self:speciesDef(mon and mon.species)
  if not def then return nil end
  local path = back and def.spriteBack or def.spriteFront
  if mon.species == Unown.SPECIES then
    path = Unown.formSprite(self.pokemon, Unown.monLetter(mon), back) or path
  end
  return self:image(path)
end

function HallOfFame:monColors(mon)
  if not (self.palettes and mon and mon.species) then return nil end
  return Palettes.monColors(self.palettes, mon.species, mon.shiny)
end

-- hSCX / hSCY applied to one screen-space pixel coordinate.  The BG map wraps
-- every 256 pixels, so a pic mid-sweep can be visible on both edges at once
-- and both copies are drawn.
local function scrolled(base, register)
  local value = (base - register) % 256
  return value, value - 256
end

-- Draw an image at a tile coordinate through the current scroll, padded into
-- the 7x7 block the way PlaceGraphic pads it.
function HallOfFame:drawScrolled(image, tileX, tileY, colors)
  if not image then return end
  local G = love.graphics
  local wide = math.floor(image:getWidth() / 8)
  local pad = PIC_PAD[wide] or PIC_PAD[PIC_TILES]
  local baseX = tileX * 8 + pad[1] * 8
  local baseY = tileY * 8 + pad[2] * 8
  local x1, x2 = scrolled(baseX, self.scx)
  local y1, y2 = scrolled(baseY, self.scy)
  G.setColor(1, 1, 1, 1)
  local function body()
    for _, x in ipairs({ x1, x2 }) do
      for _, y in ipairs({ y1, y2 }) do
        G.draw(image, x, y)
      end
    end
  end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
end

-- The player's front picture: the trainer card's 5x7 portrait, laid out as the
-- run of tile ids TrainerCard_PrintTopHalfOfCard uses, translated by the
-- scroll rather than drawn at a tile coordinate.
function HallOfFame:drawPortrait(tileX, tileY)
  if not (self.portrait and self.portrait:available()) then return end
  local G = love.graphics
  local wide = self.portraitWide
  local high = math.floor((self.portraitTiles or 35) / wide)
  -- A 5x7 portrait standing in for a 7x7 pic sits on the same ground line and
  -- centred, which is what PadFrontpic would have done to it.
  local padX = math.floor((PIC_TILES - wide) / 2)
  local padY = PIC_TILES - high
  local baseX = (tileX + padX) * 8
  local baseY = (tileY + padY) * 8
  local x1, x2 = scrolled(baseX, self.scx)
  local y1, y2 = scrolled(baseY, self.scy)
  for _, x in ipairs({ x1, x2 }) do
    for _, y in ipairs({ y1, y2 }) do
      G.push()
      G.translate(x, y)
      self.portrait:block(0, wide, high, 0, 0)
      G.pop()
    end
  end
end

function HallOfFame:drawPlacements(list)
  for _, entry in ipairs(list or {}) do
    Chrome.print(entry.text, entry.x, entry.y)
  end
end

-- The two boxes DisplayHOFMon draws: `lb bc, 3, SCREEN_WIDTH - 2` at (0,0) and
-- `lb bc, 4, 18` at (0,12).  Textbox takes INTERIOR rows and columns, so those
-- are 20x5 and 20x6 on screen.
function HallOfFame:drawMonPanel()
  local mon = self:currentMon()
  Chrome.clear()
  Chrome.textbox(0, 0, 18, 3)
  Chrome.textbox(0, 12, 18, 4)
  local def = mon and self:speciesDef(mon.species)
  self:drawScrolled(self:monPic(mon, false),
    FRONTPIC_X, FRONTPIC_Y, self:monColors(mon))
  self:drawPlacements(HallOfFame.headerPlacements(self.mode,
    self.entry and self.entry.winCount, self.textData))
  self:drawPlacements(HallOfFame.monPlacements(mon, def))
end

-- HOF_AnimatePlayerPic's card: `lb bc, 8, 9` at (0,2) and `lb bc, 4, 18` at
-- (0,12).  The bottom box is left empty; ProfOaksPCRating is what fills it.
function HallOfFame:drawPlayerPanel()
  Chrome.clear()
  Chrome.textbox(0, 2, 9, 8)
  Chrome.textbox(0, 12, 18, 4)
  self:drawPortrait(TRAINERPIC_X, TRAINERPIC_Y)
  self:drawPlacements(HallOfFame.playerPlacements(self.save))
end

function HallOfFame:drawPanel()
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)

  -- Both entry points put FontBattleExtra in the $60 slot before anything is
  -- placed: InitDisplayForHallOfFame (engine/movie/init_hof_credits.asm) for
  -- the induction, LoadFontsBattleExtra at the top of _HallOfFamePC for the
  -- viewer.  '№' ($74) and '<ID>' ($73) are that sheet's glyphs, and on the
  -- normal extra sheet those codes are a middle dot and a closing quote.
  local wasBattle = Font.useBattleExtra(true)

  if self.phase == "backpic" then
    local mon = self:currentMon()
    self:drawScrolled(self:monPic(mon, true),
      BACKPIC_X, BACKPIC_Y, self:monColors(mon))
  elseif self.phase == "frontpic" then
    local mon = self:currentMon()
    self:drawScrolled(self:monPic(mon, false),
      FRONTPIC_X, FRONTPIC_Y, self:monColors(mon))
  elseif self.phase == "display" then
    self:drawMonPanel()
  elseif self.phase == "playerBack" then
    self:drawScrolled(self:image(self.playerBackPath), BACKPIC_X, BACKPIC_Y,
      nil)
  elseif self.phase == "playerFront" then
    self:drawPortrait(TRAINERPIC_X, TRAINERPIC_Y)
  elseif self.phase == "player" then
    self:drawPlayerPanel()
  end
  Font.useBattleExtra(wasBattle)
  G.setColor(1, 1, 1, 1)
end

function HallOfFame:draw()
  self:drawPanel()
end

function HallOfFame:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

HallOfFame.WHITE = WHITE
HallOfFame.PIC_PAD = PIC_PAD
HallOfFame.FAMER_FRAMES = FAMER_FRAMES
HallOfFame.END_FRAMES = END_FRAMES
HallOfFame.SCY_START = SCY_START
HallOfFame.BACKPIC_SCX_START = BACKPIC_SCX_START
HallOfFame.BACKPIC_SCX_END = BACKPIC_SCX_END
HallOfFame.TRAINER_SCX_START = TRAINER_SCX_START

return HallOfFame
