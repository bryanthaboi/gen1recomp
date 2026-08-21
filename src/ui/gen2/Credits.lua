-- The credits roll (pokegold engine/movie/credits.asm), built the way
-- src/ui/gen2/GoldSilverIntro.lua is built: the cart's own machinery, driven
-- by a scene script, transcribed rather than approximated.
--
-- THE MACHINERY.  Credits is a 13-entry jumptable stepped once per frame, and
-- almost nothing on screen is per-frame work:
--
--   0      ParseCredits              read the script, if the timer is out
--   1-3    Credits_Next              idle
--   4      Credits_PrepBGMapUpdate   idle
--   5      Credits_UpdateGFXRequestPath  advance the banner's animation frame
--   6      Credits_RequestGFX        idle
--   7      Credits_LYOverride        slide the two border strips 2px
--   8-11   Credits_Next              idle
--   12     Credits_LoopBack          index &= $f0, back to 0
--
-- so ONE pass is 13 frames, and every `db CREDITS_WAIT, 12` in the script is
-- 12 passes -- 156 frames, about 2.6 seconds.  That cadence is the credits;
-- getting it from a timer in seconds would drift against the music.
--
-- THE TILEMAP IS PUSHED ONLY BY `.wait`.  ParseCredits blanks rows 5-12 and
-- then writes the next group's strings, but nothing reaches VRAM until the
-- `.wait` arm sets hBGMapMode.  CREDITS_WAIT2 and CREDITS_END do not, which is
-- why "THE END" survives the blank that runs immediately before CREDITS_END is
-- read.  Two buffers here, `pending` and `shown`, are that hBGMapMode.
--
-- <NEXT> IS TWO ROWS.  A multi-line credits string ("#MON / GOLD VERSION /
-- STAFF", the copyright) uses `next`, which is $4e: two tile rows down at the
-- same column.  And `.print` adds SCREEN_WIDTH * 2 per line index, so the four
-- lines of a group land on rows 6, 8, 10 and 12.  Everything is spaced two.
--
-- THE BANNER is four 4x4-tile mon graphics repeated five times across rows 0-3
-- and 14-17, with a scrolling strip of border tiles on rows 4 and 13.
-- CREDITS_SCENE picks which mon and which of the four palettes; the frame
-- cycles 0,1,2,3 once per pass through Credits_LoadBorderGFX's .Frames table,
-- and CREDITS_CLEAR sets the frame to $ff, which is the solid dark block
-- wCreditsBlankFrame2bpp holds.
--
-- THE GRAPHICS come out of the cache as `data.gen2Credits` (extracted by
-- RomExtractorGen2:extractCredits from CreditsBorderGFX, the four
-- Credits<Mon>GFX sheets, TheEndGFX and CreditsPalettes).  The strip on rows 4
-- and 13 is drawn from the real 9-tile border: DrawCreditsBorder starts at
-- tile $24 on row 4 and $20 on row 13, so the two rows are DIFFERENT halves of
-- that strip, not one strip drawn twice.  A cache that predates the extractor
-- change has no such table, and then the banner falls back to the extracted
-- 16x16 mon ICONS, centred in each 4x4 cell and flipping between their two
-- frames on the cadence the real ones would.
--
-- THE TEXT IS OURS.  This project replaces GAME FREAK's branding with its own
-- everywhere else it appears (the boot card, the title screen row), and a
-- staff roll is branding at its purest, so the script below drives the cart's
-- machinery with this port's own credits.  The command vocabulary, the waits,
-- the scene changes and the copyright/THE END tail are the cart's.

local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Logger = require("src.core.Logger")
local Music = require("src.core.Music")

local Credits = {}
Credits.__index = Credits
Credits.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144
local TILES_W = 20

-- constants/credits_constants.asm, `const_def -1, -1`: the command block
-- counts DOWN from $ff.
Credits.END = 0xff
Credits.WAIT = 0xfe
Credits.SCENE = 0xfd
Credits.CLEAR = 0xfc
Credits.MUSIC = 0xfb
Credits.WAIT2 = 0xfa
Credits.THEEND = 0xf9

-- constants/ram_constants.asm / engine/movie/credits.asm.
local ALLOW_SKIPPING_CREDITS_F = 6
local JUMPTABLE_EXIT_F = 7

-- One trip round Credits_Jumptable.
Credits.PASS_FRAMES = 13
-- The jumptable slots that do something.  Named so the frame loop reads as the
-- table rather than as three magic numbers.
local STEP_PARSE = 0
local STEP_GFX = 5
local STEP_LY = 7

-- ConstructCreditsTilemap's rows.  The banner is rows 0-3 and 14-17, the two
-- border strips rows 4 and 13, and rows 5-12 are the blank $7f text field.
local BANNER_ROWS = { 0, 14 }
local BANNER_TILES = 4          -- a mon graphic is 4x4 tiles
local BANNER_REPEATS = 5        -- .InitTopPortion's `ld b, 5`
local BORDER_ROWS = { 4, 13 }
local TEXT_TOP_ROW = 5          -- ParseCredits clears from hlcoord 0, 5
local TEXT_ROWS = 8             -- ...for SCREEN_WIDTH * 8
local TEXT_FIRST_ROW = 6        -- .print's hlcoord 0, 6
local LINE_SPACING = 2          -- `ld bc, SCREEN_WIDTH * 2`

-- Credits_TheEnd: tiles $40.. at hlcoord 6, 8 and 6, 9, eight apiece.
local THEEND_X, THEEND_Y, THEEND_W = 6, 8, 8

-- Credits_HandleBButton: the fast-forward only unlocks once wCreditsPos has
-- passed $d, i.e. thirteen script bytes in.
local SKIP_AFTER_POS = 0xd

local CREDITS_MUSIC = "Music_Credits"
local POST_CREDITS_MUSIC = "Music_PostCredits"
-- `.end`: `ld a, 32 / ld [wMusicFade], a`.
local POST_CREDITS_FADE = 32

--------------------------------------------------------------------------
-- Palettes
--------------------------------------------------------------------------

-- gfx/credits/credits.pal, the first four sets (GetCreditsPalette masks the
-- scene with %11 and each set is 8 bytes).  RGB555 scaled the way the importer
-- scales it, `round(v * 255 / 31)`, so these sit in the same 0-255 space every
-- other palette in the port does.
local function scale5(value) return math.floor(value * 255 / 31 + 0.5) end

local function pal555(...)
  local out, args = {}, { ... }
  for index = 1, 4 do
    local base = (index - 1) * 3
    out[index] = { scale5(args[base + 1]), scale5(args[base + 2]),
      scale5(args[base + 3]) }
  end
  return out
end

Credits.PALETTES = {
  [0] = pal555(31, 31, 31, 29, 08, 27, 15, 24, 12, 07, 07, 07), -- Bellossom
  [1] = pal555(31, 31, 31, 30, 26, 11, 31, 11, 27, 07, 07, 07), -- Togepi
  [2] = pal555(31, 31, 31, 31, 31, 05, 17, 23, 31, 07, 07, 07), -- Elekid
  [3] = pal555(31, 31, 31, 22, 15, 10, 31, 19, 09, 07, 07, 07), -- Sentret
}

-- Credits_LoadBorderGFX's .Frames, as which of a mon's graphics each of the
-- four animation frames uses.  Three of the four mons repeat their first
-- graphic on frame 2; Sentret is the one with four distinct frames.
Credits.BORDER_FRAMES = {
  [0] = { 1, 2, 1, 3 }, -- Bellossom
  [1] = { 1, 2, 1, 3 }, -- Togepi
  [2] = { 1, 2, 1, 3 }, -- Elekid
  [3] = { 1, 2, 3, 4 }, -- Sentret
}

-- The four species the banner parades, in scene order.
Credits.SCENE_SPECIES = { [0] = "BELLOSSOM", "TOGEPI", "ELEKID", "SENTRET" }

--------------------------------------------------------------------------
-- The strings
--------------------------------------------------------------------------
--
-- data/credits_strings.asm's shape: one table of fixed strings, each padded
-- with leading spaces to sit where it should on a 20-tile row, and an index
-- block (constants/credits_constants.asm) that the script refers to them by.
-- The two comparisons ParseCredits makes on that index are what force the
-- ordering: everything below STAFF is a person, COPYRIGHT prints at column 2
-- instead of column 0.  Both are transcribed even though only COPYRIGHT
-- changes anything, because .staff and the default arm really do land on the
-- same hlcoord.

local STRINGS = {}
local ID = {}
local nextId = 0

local function defineString(name, text)
  ID[name] = nextId
  STRINGS[nextId] = text
  nextId = nextId + 1
  return ID[name]
end

-- The people, first, exactly as the cart orders them.
defineString("BRYANTHABOI", "    BRYANTHABOI")
defineString("BOIS_CLUB", "  BOIS CLUB GAMES")
defineString("THE_BOIS_CLUB", "   THE BOIS CLUB")
defineString("PRET_POKEGOLD", "   PRET POKEGOLD")
defineString("PRET_PROJECT", "  THE PRET PROJECT")
defineString("LOVE2D", "       LOVE2D")
defineString("LUAJIT", "       LUAJIT")
defineString("CHIP_SYNTH", "     CHIP SYNTH")
defineString("EVERY_TESTER", "    EVERY TESTER")
defineString("AND_YOU", "      AND YOU")
defineString("CREDIT_END", "END")

-- STAFF and everything after it is a heading.  Anything BELOW this id is a
-- person as far as ParseCredits is concerned.
-- Credits_Staff differs per edition, including the centring spaces
-- (data/credits_strings.asm:54-60).
Credits.STAFF = defineString("STAFF",
  require("src.core.GameVersion").get() == "silver" and {
    "      #MON",
    "   SILVER VERSION",
    "     PORT STAFF",
  } or {
    "      #MON",
    "    GOLD VERSION",
    "     PORT STAFF",
  })
defineString("DIRECTOR", "      DIRECTOR")
defineString("PROGRAMMING", "    PROGRAMMING")
defineString("ENGINE_DESIGN", "   ENGINE DESIGN")
defineString("BATTLE_ENGINE", "   BATTLE ENGINE")
defineString("SCRIPT_ENGINE", "   SCRIPT ENGINE")
defineString("WORLD_ENGINE", "    WORLD ENGINE")
defineString("AUDIO_ENGINE", "    AUDIO ENGINE")
defineString("GRAPHICS", "      GRAPHICS")
defineString("USER_INTERFACE", "   USER INTERFACE")
defineString("ROM_IMPORTER", "    ROM IMPORTER")
defineString("SAVE_EDITOR", "    SAVE EDITOR")
defineString("MOD_SDK", "      MOD SDK")
defineString("TOOLS", "       TOOLS")
defineString("TESTING", "      TESTING")
defineString("BUILT_WITH", "     BUILT WITH")
defineString("BASED_ON", "      BASED ON")
defineString("SPECIAL_THANKS", "   SPECIAL THANKS")
defineString("PRODUCER", "      PRODUCER")

-- Credits_Copyright, the one string with an hlcoord of its own.  The cart's is
-- three © lines out of data/copyright.asm; this is the port's, in the same
-- three-line shape the boot card prints.
Credits.COPYRIGHT = defineString("COPYRIGHT", {
  "bois club games",
  "bryanthaboi 2026",
  "a fan-made port",
})

Credits.STRINGS = STRINGS
Credits.ID = ID

--------------------------------------------------------------------------
-- The script
--------------------------------------------------------------------------
--
-- data/credits_script.asm's shape, byte for byte: a flat stream read one byte
-- at a time by `.get`, where a string id is followed by its LINE INDEX (0-3,
-- multiplied by two rows) and each command carries its own operands.  Kept
-- flat rather than turned into a list of groups so that `.get`, wCreditsPos
-- and the B-button fast-forward's `cp $d` all still mean what they mean.

local function group(script, ...)
  local rows = { ... }
  for index, id in ipairs(rows) do
    script[#script + 1] = id
    script[#script + 1] = index - 1
  end
  script[#script + 1] = Credits.WAIT
  script[#script + 1] = 12
  return script
end

local function build()
  local s = {}
  -- Clear the banner, put the heading up, and let the music start under it.
  s[#s + 1] = Credits.CLEAR
  s[#s + 1] = ID.STAFF
  s[#s + 1] = 0
  s[#s + 1] = Credits.WAIT
  s[#s + 1] = 8
  s[#s + 1] = Credits.MUSIC
  s[#s + 1] = Credits.WAIT2
  s[#s + 1] = 10
  s[#s + 1] = Credits.WAIT
  s[#s + 1] = 1

  local function scene(n)
    s[#s + 1] = Credits.SCENE
    s[#s + 1] = n
  end
  -- The cart ends each act with a bare `CREDITS_WAIT, 0`, then CREDITS_CLEAR
  -- and a one-tick wait before the next scene: the blank frame is what stops
  -- one mon's banner cutting straight to the next.
  local function endAct()
    s[#s + 1] = Credits.WAIT
    s[#s + 1] = 0
    s[#s + 1] = Credits.CLEAR
    s[#s + 1] = Credits.WAIT
    s[#s + 1] = 1
  end

  scene(0) -- Bellossom
  group(s, ID.DIRECTOR, ID.BRYANTHABOI)
  group(s, ID.PROGRAMMING, ID.BRYANTHABOI, ID.BOIS_CLUB)
  group(s, ID.ENGINE_DESIGN, ID.BOIS_CLUB)
  group(s, ID.BATTLE_ENGINE, ID.BOIS_CLUB)
  group(s, ID.SCRIPT_ENGINE, ID.BOIS_CLUB)
  endAct()

  scene(1) -- Togepi
  group(s, ID.WORLD_ENGINE, ID.BOIS_CLUB)
  group(s, ID.AUDIO_ENGINE, ID.CHIP_SYNTH, ID.BOIS_CLUB)
  group(s, ID.GRAPHICS, ID.BOIS_CLUB)
  group(s, ID.USER_INTERFACE, ID.BOIS_CLUB)
  group(s, ID.ROM_IMPORTER, ID.BOIS_CLUB)
  endAct()

  scene(2) -- Elekid
  group(s, ID.SAVE_EDITOR, ID.BOIS_CLUB)
  group(s, ID.MOD_SDK, ID.BOIS_CLUB)
  group(s, ID.TOOLS, ID.BRYANTHABOI)
  group(s, ID.TESTING, ID.THE_BOIS_CLUB)
  group(s, ID.BUILT_WITH, ID.LOVE2D, ID.LUAJIT)
  endAct()

  scene(3) -- Sentret
  group(s, ID.BASED_ON, ID.PRET_POKEGOLD)
  group(s, ID.SPECIAL_THANKS, ID.PRET_PROJECT, ID.EVERY_TESTER)
  group(s, ID.SPECIAL_THANKS, ID.THE_BOIS_CLUB, ID.AND_YOU)
  group(s, ID.PRODUCER, ID.BRYANTHABOI)

  -- The tail, which is the cart's exactly: the copyright, two long waits, the
  -- graphic, one more wait, stop.
  s[#s + 1] = ID.COPYRIGHT
  s[#s + 1] = 0
  s[#s + 1] = Credits.WAIT
  s[#s + 1] = 20
  s[#s + 1] = Credits.WAIT
  s[#s + 1] = 19
  s[#s + 1] = Credits.THEEND
  s[#s + 1] = Credits.WAIT
  s[#s + 1] = 20
  s[#s + 1] = Credits.END
  return s
end

Credits.SCRIPT = build()

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

function Credits:wantsFillScale() return true end
function Credits:drawsWidescreen() return true end

-- opts:
--   allowSkip   the ALLOW_SKIPPING_CREDITS_F bit.  `HallOfFame::` pushes
--               wStatusFlags BEFORE it sets STATUSFLAGS_HALL_OF_FAME_F and
--               hands the pushed copy to Credits, so a first-time champion
--               gets false here and every later viewing gets true.
--   script      an override, for tests and for RedCredits
--   onDone()
function Credits.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Credits)
  self.game = game
  local data = (game and game.data) or {}
  self.data = data
  self.onDone = opts.onDone
  self.script = opts.script or Credits.SCRIPT
  self.allowSkip = opts.allowSkip and true or false
  self.icons = opts.icons or data.gen2Icons
  self.gfx = opts.gfx or data.gen2Credits
  if not (self.gfx and self.gfx.scenes) and not Credits.warned then
    Credits.warned = true
    Logger.info("gold credits: gfx/credits/ is not in the cache -- the "
      .. "banner falls back to the mon icons")
  end
  self.images = {}

  -- wJumptableIndex's low nibble, and its two flags kept as their own fields
  -- so a reader is never masking.
  self.step = 0
  self.exiting = false
  -- wCreditsPos, 1-based here because a Lua array is; the `cp $d` comparison
  -- below subtracts the difference back out.
  self.pos = 1
  self.timer = 0
  self.frames = 0
  self.passes = 0
  self.done = false

  -- wCreditsBorderMon / wCreditsBorderFrame.  $ff is the blank frame.
  self.scene = 0
  self.borderFrame = 0xff
  self.lyOverride = 0

  -- The tilemap being built and the one on screen; see the header.
  self.pending = {}
  self.shown = {}
  return self
end

--------------------------------------------------------------------------
-- ParseCredits
--------------------------------------------------------------------------

-- `.get`: read the byte at wCreditsPos and step past it.
function Credits:get()
  local byte = self.script[self.pos]
  self.pos = self.pos + 1
  return byte
end

local function clearPending(self)
  self.pending = {}
end

-- One text write into the pending tilemap.  Multi-line strings are laid out
-- with <NEXT>'s two-row step.
local function place(self, id, line)
  local text = STRINGS[id]
  if text == nil then return end
  -- `cp COPYRIGHT / jr z, .copyright` is hlcoord 2, 6; `cp STAFF /
  -- jr c, .staff` and the default arm are both hlcoord 0, 6.
  local x = (id == Credits.COPYRIGHT) and 2 or 0
  local y = TEXT_FIRST_ROW + (line or 0) * LINE_SPACING
  if type(text) == "table" then
    for index, row in ipairs(text) do
      self.pending[#self.pending + 1] =
        { text = row, x = x, y = y + (index - 1) * LINE_SPACING }
    end
    return
  end
  self.pending[#self.pending + 1] = { text = text, x = x, y = y }
end

-- Credits_TheEnd: two rows of eight running tile ids at hlcoord 6, 8.  Without
-- gfx/credits/theend.2bpp the same eight columns carry the words instead.
local function theEnd(self)
  self.pending[#self.pending + 1] =
    { theEnd = true, x = THEEND_X, y = THEEND_Y, width = THEEND_W }
end

-- The `.wait` arm's hBGMapMode: everything written since the last parse
-- becomes what is on screen.
local function pushTilemap(self)
  local copy = {}
  for index, entry in ipairs(self.pending) do copy[index] = entry end
  self.shown = copy
end

function Credits:parse()
  if self.exiting then return end
  if self.timer > 0 then
    self.timer = self.timer - 1
    return
  end

  -- `.parse` clears rows 5-12 of the tilemap first, every time.
  clearPending(self)

  while true do
    local byte = self:get()
    if byte == nil or byte == Credits.END then
      -- `.end`: set the exit flag and queue the post-credits theme behind a
      -- 32-step fade.  The screen stays up until A is pressed.
      self.exiting = true
      self:fadeToPostCredits()
      return
    elseif byte == Credits.WAIT then
      self.timer = self:get() or 0
      pushTilemap(self)
      return
    elseif byte == Credits.WAIT2 then
      -- Same timer, no hBGMapMode: whatever is on screen stays there.
      self.timer = self:get() or 0
      return
    elseif byte == Credits.SCENE then
      self.scene = (self:get() or 0) % 4
      self.borderFrame = 0
    elseif byte == Credits.CLEAR then
      self.borderFrame = 0xff
    elseif byte == Credits.MUSIC then
      self:playMusic(CREDITS_MUSIC)
    elseif byte == Credits.THEEND then
      theEnd(self)
    else
      place(self, byte, self:get())
    end
  end
end

--------------------------------------------------------------------------
-- The other jumptable entries
--------------------------------------------------------------------------

-- Credits_LoadBorderGFX: frame $ff is the blank block and stays blank;
-- otherwise the frame cycles 0,1,2,3 and the pair (scene, frame) picks the
-- graphic out of .Frames.
function Credits:advanceBorder()
  if self.borderFrame == 0xff then return end
  self.borderFrame = (self.borderFrame + 1) % 4
end

-- Which of the current mon's graphics is showing, 1-based, or nil while the
-- banner is cleared.
function Credits:borderGraphic()
  if self.borderFrame == 0xff then return nil end
  local frames = Credits.BORDER_FRAMES[self.scene] or Credits.BORDER_FRAMES[0]
  return frames[self.borderFrame + 1]
end

-- Credits_LYOverride: two more pixels every pass, written into the eight
-- scanlines at $1f and the eight at $67 -- which, with hLCDCPointer pointing
-- at rSCX, is a horizontal slide of the two border strips and nothing else.
function Credits:advanceLY()
  self.lyOverride = (self.lyOverride + 2) % 256
end

--------------------------------------------------------------------------
-- Audio
--------------------------------------------------------------------------

function Credits:playMusic(song)
  local audio = self.data and self.data.audio
  if audio and audio.songs and audio.songs[song] then
    -- HallOfFame_PlayMusicDE: MUSIC_NONE for a frame, then the song.
    Music.stop()
    Music.play(self.data, song, true, { reason = "credits" })
  end
end

function Credits:fadeToPostCredits()
  local audio = self.data and self.data.audio
  if not (audio and audio.songs and audio.songs[POST_CREDITS_MUSIC]) then
    Music.fadeOut(POST_CREDITS_FADE)
    return
  end
  Music.fadeOut(POST_CREDITS_FADE)
  self.postCredits = POST_CREDITS_MUSIC
end

--------------------------------------------------------------------------
-- Frame loop
--------------------------------------------------------------------------

-- Credits_HandleBButton, whose whole job is to tick the timer down an EXTRA
-- time per frame while B is held: the credits do not skip, they hurry.
function Credits:handleB(input)
  if not (input and input.isDown and input:isDown("b")) then return end
  if not self.allowSkip then return end
  -- `cp $d` against the low byte of wCreditsPos, which is 0-based.
  if (self.pos - 1) < SKIP_AFTER_POS then return end
  if self.timer <= 0 then return end
  self.timer = self.timer - 1
end

-- Credits_HandleAButton: A only leaves once ParseCredits has set the exit bit.
function Credits:handleA(input)
  if self.exiting and input and input.isDown and input:isDown("a") then
    return true
  end
  return false
end

-- One frame of `.execution_loop`.  Returns true when the credits are over.
function Credits:step1()
  if self.done then return true end
  self.frames = self.frames + 1
  local step = self.step
  if step == STEP_PARSE then
    self:parse()
  elseif step == STEP_GFX then
    self:advanceBorder()
  elseif step == STEP_LY then
    self:advanceLY()
  end
  if step >= Credits.PASS_FRAMES - 1 then
    -- Credits_LoopBack: `and $f0`, so only the low nibble is reset.
    self.step = 0
    self.passes = self.passes + 1
  else
    self.step = step + 1
  end
  return false
end

function Credits:finish()
  if self.done then return end
  self.done = true
  if self.postCredits then self:playMusic(self.postCredits) end
  if self.onDone then self.onDone() end
end

function Credits:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  self:handleB(input)
  if self:handleA(input) then return self:finish() end
  self:step1()
end

-- Run the whole movie without a graphics device, for tests and drivers.
-- Returns the number of frames it took, or nil if it never reached the end.
function Credits:runToEnd(limit)
  limit = limit or 60000
  for frame = 1, limit do
    self:step1()
    if self.exiting then return frame end
  end
  return nil
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

-- GetCreditsPalette masks the scene with %11 and takes the 8-byte set at that
-- index.  The extracted table is 1-based, so scene 0 is set 1; the transcribed
-- PALETTES above stay as the fallback for a cache without it.
function Credits:palette()
  local sets = self.gfx and self.gfx.palettes
  local extracted = sets and sets[self.scene % 4 + 1]
  if extracted then return extracted end
  return Credits.PALETTES[self.scene] or Credits.PALETTES[0]
end

function Credits:image(path)
  if not path then return nil end
  local cached = self.images[path]
  if cached == nil then
    local Assets = require("src.render.Assets")
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    if cached then cached:setFilter("nearest", "nearest") end
    self.images[path] = cached
  end
  return cached or nil
end

-- The icon standing in for this scene's 4x4 mon graphic, and which of its two
-- 16x16 frames the border frame maps onto.
function Credits:sceneIcon()
  local species = Credits.SCENE_SPECIES[self.scene]
  local icons = self.icons
  if not (species and icons and icons.species and icons.icons) then return nil end
  local entry = icons.icons[icons.species[species]]
  if not entry then return nil end
  return self:image(entry.image), entry
end

-- An icon sheet is one column of `frames` 16x16 cells, so the four border
-- frames fold onto the two the icon has: 1,2,1,3 becomes 1,2,1,2.  Quads are
-- built once per (sheet, frame) rather than per draw.
function Credits:iconQuad(image, entry, graphic)
  local frames = entry.frames or 2
  local index = (graphic - 1) % frames
  self.quads = self.quads or {}
  local key = tostring(entry.id) .. ":" .. index
  local quad = self.quads[key]
  if not quad then
    local height = math.floor((entry.height or 32) / frames)
    quad = love.graphics.newQuad(0, index * height, entry.width or 16, height,
      image:getDimensions())
    self.quads[key] = quad
  end
  return quad
end

-- The real 4x4 sheet for this scene, if the cache has one.  Credits<Mon>GFX
-- is `frames` 32x32 blocks stacked, and .Frames' offsets are in whole blocks,
-- so `graphic` indexes straight into it (clamped, because three of the four
-- mons only have three blocks and .Frames never asks them for a fourth).
function Credits:sceneSheet()
  local scenes = self.gfx and self.gfx.scenes
  local entry = scenes and scenes[self.scene % 4 + 1]
  if not entry then return nil end
  return self:image(entry.image), entry
end

function Credits:sheetQuad(image, entry, graphic)
  local frames = entry.frames or 1
  local index = math.min(graphic, frames) - 1
  local w, h = entry.width or 32, entry.height or 32
  self.quads = self.quads or {}
  local key = "sheet:" .. tostring(entry.species) .. ":" .. index
  local quad = self.quads[key]
  if not quad then
    quad = love.graphics.newQuad(0, index * h, w, h, image:getDimensions())
    self.quads[key] = quad
  end
  return quad
end

-- TheEndGFX, or nil while the cache is without it.
function Credits:theEndImage()
  local path = self.gfx and self.gfx.theEnd
  return path and self:image(path) or nil
end

-- One 8x8 tile out of the 9-tile border strip, 1-based the way
-- DrawCreditsBorder's start ids read after they are turned back into columns.
function Credits:borderQuad(image, tile)
  self.quads = self.quads or {}
  local key = "border:" .. tile
  local quad = self.quads[key]
  if not quad then
    quad = love.graphics.newQuad((tile - 1) * 8, 0, 8, 8, image:getDimensions())
    self.quads[key] = quad
  end
  return quad
end

local function fill(color, x, y, w, h)
  local G = love.graphics
  G.setColor(color[1] / 255, color[2] / 255, color[3] / 255, 1)
  G.rectangle("fill", x, y, w, h)
  G.setColor(1, 1, 1, 1)
end

-- Rows 0-3 and 14-17: five copies of a 4x4-tile block across the screen.
function Credits:drawBanner()
  local pal = GbcPalette.resolve(self:palette())
  local graphic = self:borderGraphic()
  local cell = BANNER_TILES * 8
  for _, row in ipairs(BANNER_ROWS) do
    -- The cleared banner really is one flat colour: wCreditsBlankFrame2bpp is
    -- sixteen tiles of solid colour 2.
    local backdrop = graphic and (GbcPalette.color(pal, 1) or pal[1])
      or (GbcPalette.color(pal, 3) or pal[3])
    fill(backdrop, 0, row * 8, SCREEN_W, cell)
    if graphic then
      -- The real sheet first: a 32x32 block is exactly the 4x4 cell, so it
      -- tiles the row with no centring and no backdrop showing through.
      local image, entry = self:sceneSheet()
      local quad = image and entry and self:sheetQuad(image, entry, graphic)
      local px, py = 0, row * 8
      if not quad then
        image, entry = self:sceneIcon()
        quad = image and entry and self:iconQuad(image, entry, graphic)
        if quad then
          local iconW, iconH = entry.width or 16,
            math.floor((entry.height or 32) / (entry.frames or 2))
          px = math.floor((cell - iconW) / 2)
          py = row * 8 + math.floor((cell - iconH) / 2)
        end
      end
      if quad then
        love.graphics.setColor(1, 1, 1, 1)
        local function body()
          for repeatIndex = 0, BANNER_REPEATS - 1 do
            love.graphics.draw(image, quad, repeatIndex * cell + px, py)
          end
        end
        if GbcPalette.available() then
          GbcPalette.useRaw(pal)
          body()
          GbcPalette.clear()
        else
          body()
        end
      end
    end
  end
end

-- Rows 4 and 13: the border strip, slid sideways by the LY override.  The
-- override goes into rSCX, and a rising SCX moves the picture LEFT, which is
-- why the strip is drawn at `-shift`.  DrawCreditsBorder lays four running
-- tiles five times across the row, so the pattern repeats every 32px and
-- `lyOverride % 32` is the whole of the slide.  Row 4 starts at $24 and row 13
-- at $20: the two rows are different quarters of the 9-tile strip.
function Credits:drawBorderStrips()
  local pal = GbcPalette.resolve(self:palette())
  local color = GbcPalette.color(pal, 3) or pal[3]
  local shift = self.lyOverride % 32
  local gfx = self.gfx
  local image = gfx and gfx.border and self:image(gfx.border)
  local starts = { [BORDER_ROWS[1]] = (gfx and gfx.borderTopTile) or 5,
    [BORDER_ROWS[2]] = (gfx and gfx.borderBottomTile) or 1 }
  for _, row in ipairs(BORDER_ROWS) do
    fill(color, 0, row * 8, SCREEN_W, 8)
    if image then
      local first = starts[row]
      love.graphics.setColor(1, 1, 1, 1)
      local function body()
        for x = -32, SCREEN_W, 32 do
          for tile = 0, 3 do
            love.graphics.draw(image, self:borderQuad(image, first + tile),
              x + tile * 8 - shift, row * 8)
          end
        end
      end
      if GbcPalette.available() then
        GbcPalette.useRaw(pal)
        body()
        GbcPalette.clear()
      else
        body()
      end
    else
      -- Without the real strip art the slide has nothing to move, so the notch
      -- below is what carries it: one lighter cell per four, at the offset the
      -- LY override is holding.
      local light = GbcPalette.color(pal, 2) or pal[2]
      for x = -32, SCREEN_W, 32 do
        fill(light, x + shift, row * 8, 8, 8)
      end
    end
  end
end

function Credits:drawText()
  local pal = self:palette()
  for _, entry in ipairs(self.shown) do
    if entry.theEnd then
      local image = self:theEndImage()
      if image then
        -- TheEndGFX is 16 tiles, placed 8 wide on rows 8 and 9: the sheet's
        -- own 64x16 layout, so it draws whole at the tilemap coordinate.
        local shaded = GbcPalette.resolve(pal)
        love.graphics.setColor(1, 1, 1, 1)
        if GbcPalette.available() then
          GbcPalette.useRaw(shaded)
          love.graphics.draw(image, entry.x * 8, entry.y * 8)
          GbcPalette.clear()
        else
          love.graphics.draw(image, entry.x * 8, entry.y * 8)
        end
      else
        -- Centred in the eight columns the graphic occupies.
        local text = "THE END"
        local width = Font.width(text)
        Chrome.printThrough(text,
          entry.x + math.floor((entry.width * 8 - width) / 16), entry.y, pal)
      end
    else
      Chrome.printThrough(entry.text, entry.x, entry.y, pal)
    end
  end
end

function Credits:drawPanel()
  local pal = GbcPalette.resolve(self:palette())
  -- Rows 4-13 are $7f, the blank tile, which reads as colour 0.
  local paper = GbcPalette.color(pal, 1) or pal[1]
  fill(paper, 0, 0, SCREEN_W, SCREEN_H)
  self:drawBanner()
  self:drawBorderStrips()
  self:drawText()
  love.graphics.setColor(1, 1, 1, 1)
end

function Credits:draw()
  self:drawPanel()
end

function Credits:drawWidescreen(winW, winH)
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

Credits.TILES_W = TILES_W
Credits.TEXT_TOP_ROW = TEXT_TOP_ROW
Credits.TEXT_ROWS = TEXT_ROWS
Credits.TEXT_FIRST_ROW = TEXT_FIRST_ROW
Credits.LINE_SPACING = LINE_SPACING
Credits.BANNER_ROWS = BANNER_ROWS
Credits.BORDER_ROWS = BORDER_ROWS
Credits.SKIP_AFTER_POS = SKIP_AFTER_POS
Credits.ALLOW_SKIPPING_CREDITS_F = ALLOW_SKIPPING_CREDITS_F
Credits.JUMPTABLE_EXIT_F = JUMPTABLE_EXIT_F
Credits.STEP_PARSE = STEP_PARSE
Credits.STEP_GFX = STEP_GFX
Credits.STEP_LY = STEP_LY

return Credits
