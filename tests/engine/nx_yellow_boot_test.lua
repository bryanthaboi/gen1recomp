-- NX Yellow boot, headless: the runtime complement to
-- tests/engine/nx_generated_guard_test.lua.  The guard only sees literal
-- loader calls; this suite drives the REAL boot states (TitleState,
-- YellowIntro/IntroMovie, Sound.playPikaCry) against a broken-mount NX
-- filesystem where generated art exists ONLY under the versioned save-dir
-- prefix (yellow|blue/), and records every path that reaches the raw love
-- loaders AFTER NxAssetOverlay's rewrite.  Any data-driven or formatted
-- assets/generated path the overlay misses shows up here as a bare path
-- the recorder saw.  Self-contained:
--   luajit tests/engine/nx_yellow_boot_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local Platform = require("src.core.Platform")
local Overlay = require("src.core.NxAssetOverlay")
local TitleState = require("src.ui.TitleState")
local YellowIntro = require("src.ui.YellowIntro")
local Sound = require("src.core.Sound")

local savedVersion = GameVersion.get()

local GENERATED = "assets/generated/"

-- --- fixtures ----------------------------------------------------------
-- Seeded ONLY under the versioned prefix, mirroring the fused love-nx bug
-- where yellow|blue/assets/generated is never mounted over assets/generated.
local seeded = {}
local function seed(path, bytes)
  love.filesystem.write(path, bytes or "fake-asset-bytes")
  seeded[#seeded + 1] = path
end

local Y_TITLE = {
  "pikachu.png", "pika_bubble.png", "eyes_half.png", "eyes_closed.png",
  "player.png", "copyright.png", "yellow_version.png",
}
for _, name in ipairs(Y_TITLE) do
  seed("yellow/assets/generated/title/" .. name)
end
local Y_INTRO = {
  "yellow_intro_1.png", "yellow_intro_2.png", "clouds.png",
  -- data-driven manifest entries (the paths a literal scan cannot see)
  "gf_logo.png", "gf_text.png", "big_star.png",
  "falling_star.png", "falling_star_blink.png", "studio_logo.png",
  "gengar_1.png", "gengar_2.png", "gengar_3.png",
  "nidorino_1.png", "nidorino_2.png", "nidorino_3.png",
}
for _, name in ipairs(Y_INTRO) do
  seed("yellow/assets/generated/intro/" .. name)
end
seed("yellow/assets/generated/audio/pika_cries/cry_01.wav", "RIFF-fake-wav")

-- --- recorder, installed BEFORE Overlay.install so it sees the final
-- resolved path (the overlay wraps whatever is in place at install time)
local recorded = {}
local function record(kind, path)
  if type(path) == "string" then
    recorded[#recorded + 1] = { kind = kind, path = path }
  end
end

local rawNewImage = love.graphics.newImage
love.graphics.newImage = function(path, ...)
  record("image", path)
  return rawNewImage(path, ...)
end

local rawRead = love.filesystem.read
love.filesystem.read = function(path, ...)
  record("read", path)
  return rawRead(path, ...)
end

-- widenMono re-reads the caller's bare path via newSoundData; without this
-- recorder the boot suite only saw newSource and could not catch a missing
-- sound.newSoundData wrap (the silent hole that motivated the full-surface
-- overlay).  Installed before Overlay.install so the overlay wraps us.
local rawNewSoundData = love.sound.newSoundData
love.sound.newSoundData = function(samples, ...)
  record("sounddata", samples)
  return rawNewSoundData(samples, ...)
end

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:setVolume() end
function Source:isPlaying() return self.playing end
function Source:getChannelCount() return self.channels or 1 end

love.audio = {
  newSource = function(pathOrData, mode)
    record("source", pathOrData)
    local channels = 1
    if type(pathOrData) == "table" and pathOrData.getChannelCount then
      channels = pathOrData:getChannelCount()
    end
    return setmetatable({
      path = pathOrData, mode = mode, channels = channels,
    }, Source)
  end,
}

Overlay.install()
check(Overlay.isInstalled(), "overlay installs over the recorders")

-- Every recorded path under assets/generated/ must already carry the
-- active version prefix: a bare generated path here is a dynamic-path
-- regression the static guard cannot catch.
local function assertNoBareGenerated(prefix, label)
  local bare = {}
  for _, r in ipairs(recorded) do
    if r.path:sub(1, #GENERATED) == GENERATED then
      bare[#bare + 1] = r.kind .. " " .. r.path
    end
  end
  check(#bare == 0,
    label .. ": every generated path reached the raw loader " .. prefix
      .. "-prefixed"
      .. (#bare > 0 and (" (bare: " .. table.concat(bare, ", ") .. ")") or ""))
end

local function countRecorded(prefix)
  local n = 0
  for _, r in ipairs(recorded) do
    if r.path:sub(1, #prefix) == prefix then n = n + 1 end
  end
  return n
end

-- --- Yellow boot -------------------------------------------------------
GameVersion.set("yellow")

local yellowTitleManifest = {
  layout = "yellow_pikachu",
  pikachu = { path = "assets/generated/title/pikachu.png" },
  pikaBubble = { path = "assets/generated/title/pika_bubble.png" },
  version = { path = "assets/generated/title/yellow_version.png" },
}
local yellowIntroManifest = {
  studio = { logo = "assets/generated/intro/studio_logo.png" },
  gamefreakLogo = { path = "assets/generated/intro/gf_logo.png" },
  gamefreakText = { path = "assets/generated/intro/gf_text.png" },
  bigStar = { path = "assets/generated/intro/big_star.png" },
  fallingStar = { path = "assets/generated/intro/falling_star.png" },
  fallingStarBlink = { path = "assets/generated/intro/falling_star_blink.png" },
  gengar = {
    frame1 = { path = "assets/generated/intro/gengar_1.png" },
    frame2 = { path = "assets/generated/intro/gengar_2.png" },
    frame3 = { path = "assets/generated/intro/gengar_3.png" },
  },
  nidorino = {
    frame1 = { path = "assets/generated/intro/nidorino_1.png" },
    frame2 = { path = "assets/generated/intro/nidorino_2.png" },
    frame3 = { path = "assets/generated/intro/nidorino_3.png" },
  },
}
local game = { data = { field = {
  title = yellowTitleManifest,
  intro = yellowIntroManifest,
} } }

local titleState = TitleState.new(game, {})
check(titleState.yellowLayout, "the Yellow manifest selects the Pikachu layout")
check(titleState.yellowPikachu ~= nil, "title Pikachu art loaded")
eq(titleState.yellowPikachu and titleState.yellowPikachu.path,
  "yellow/assets/generated/title/pikachu.png",
  "title Pikachu resolves to the yellow/ copy")
check(titleState.yellowBubble ~= nil, "title speech bubble loaded")
eq(titleState.yellowBubble and titleState.yellowBubble.path,
  "yellow/assets/generated/title/pika_bubble.png",
  "title bubble resolves to the yellow/ copy")
eq(titleState.eyesHalf and titleState.eyesHalf.path,
  "yellow/assets/generated/title/eyes_half.png",
  "blink overlay (eyes_half) resolves to the yellow/ copy")
eq(titleState.eyesClosed and titleState.eyesClosed.path,
  "yellow/assets/generated/title/eyes_closed.png",
  "blink overlay (eyes_closed) resolves to the yellow/ copy")
eq(titleState.player and titleState.player.path,
  "yellow/assets/generated/title/player.png",
  "title player resolves to the yellow/ copy")
eq(titleState.version and titleState.version.path,
  "yellow/assets/generated/title/yellow_version.png",
  "version ribbon resolves to the yellow/ copy")

-- YellowIntro.new internally builds IntroMovie.new as its pre-roll, so one
-- constructor covers the copyright card, the GAME FREAK splash and the
-- Yellow attract atlases.
local yellowIntro = YellowIntro.new(game, function() end)
eq(yellowIntro.atlas1 and yellowIntro.atlas1.path,
  "yellow/assets/generated/intro/yellow_intro_1.png",
  "YellowIntro atlas1 resolves to the yellow/ copy")
eq(yellowIntro.atlas2 and yellowIntro.atlas2.path,
  "yellow/assets/generated/intro/yellow_intro_2.png",
  "YellowIntro atlas2 resolves to the yellow/ copy")
eq(yellowIntro.clouds and yellowIntro.clouds.path,
  "yellow/assets/generated/intro/clouds.png",
  "YellowIntro clouds resolve to the yellow/ copy")
local pre = yellowIntro.pre
check(pre ~= nil, "the IntroMovie pre-roll was constructed")
eq(pre and pre.copyright and pre.copyright.path,
  "yellow/assets/generated/title/copyright.png",
  "copyright card resolves to the yellow/ copy")
eq(pre and pre.studioLogo and pre.studioLogo.path,
  "yellow/assets/generated/intro/studio_logo.png",
  "data-driven studio logo resolves to the yellow/ copy")
eq(pre and pre.logo and pre.logo.path,
  "yellow/assets/generated/intro/gf_logo.png",
  "data-driven gamefreakLogo resolves to the yellow/ copy")
eq(pre and pre.gfText and pre.gfText.path,
  "yellow/assets/generated/intro/gf_text.png",
  "data-driven gamefreakText resolves to the yellow/ copy")
eq(pre and pre.bigStar and pre.bigStar.path,
  "yellow/assets/generated/intro/big_star.png",
  "data-driven bigStar resolves to the yellow/ copy")
eq(pre and pre.gengarFrames and pre.gengarFrames[2]
    and pre.gengarFrames[2].path,
  "yellow/assets/generated/intro/gengar_2.png",
  "data-driven gengar frame resolves to the yellow/ copy")
eq(pre and pre.nidoFrames and pre.nidoFrames[3]
    and pre.nidoFrames[3].path,
  "yellow/assets/generated/intro/nidorino_3.png",
  "data-driven nidorino frame resolves to the yellow/ copy")

-- Yellow's voiced Pikachu clip: a FORMATTED path (cry_%02d.wav), invisible
-- to the static guard.  playPikaCry also runs widenMono, which re-reads the
-- same bare path via newSoundData and must emit a 16-bit STEREO Source
-- (#626) -- path rewrite alone is not enough on Switch audren.
local cry = Sound.playPikaCry({ audio = { pikaCries = 1 } }, 1)
check(cry ~= nil, "playPikaCry returns a source on NX Yellow")
eq(cry and cry:getChannelCount(), 2,
  "playPikaCry widens the mono PCM clip to stereo")
local sawCrySoundData = false
local sawCrySource = false
for _, r in ipairs(recorded) do
  if r.kind == "sounddata"
      and r.path == "yellow/assets/generated/audio/pika_cries/cry_01.wav" then
    sawCrySoundData = true
  end
  if r.kind == "source"
      and r.path == "yellow/assets/generated/audio/pika_cries/cry_01.wav" then
    sawCrySource = true
  end
end
check(sawCrySource,
  "newSource loaded the cry through the yellow/ prefix")
check(sawCrySoundData,
  "widenMono re-read the cry via newSoundData with the yellow/ path")

check(countRecorded("yellow/assets/generated/") >= 20,
  "the boot pulled its generated art through the yellow/ prefix")
assertNoBareGenerated("yellow/", "Yellow boot")

-- --- Blue boot: parity with Yellow --------------------------------------
-- Blue's real boot is IntroMovie (the Red/Blue attract movie) straight onto
-- the stack, then TitleState with cycling mons -- no Pikachu layout.  Same
-- broken-mount setup, same assertions, blue/ prefix.
recorded = {}
GameVersion.set("blue")
seed("blue/assets/generated/title/blue_version.png", "blue-version-bytes")
seed("blue/assets/generated/title/player.png")
seed("blue/assets/generated/title/copyright.png")
local B_INTRO = {
  "gf_logo.png", "gf_text.png", "big_star.png",
  "falling_star.png", "falling_star_blink.png", "studio_logo.png",
  "gengar_1.png", "gengar_2.png", "gengar_3.png",
  "nidorino_1.png", "nidorino_2.png", "nidorino_3.png",
}
for _, name in ipairs(B_INTRO) do
  seed("blue/assets/generated/intro/" .. name)
end

local blueIntroManifest = {
  studio = { logo = "assets/generated/intro/studio_logo.png" },
  gamefreakLogo = { path = "assets/generated/intro/gf_logo.png" },
  gamefreakText = { path = "assets/generated/intro/gf_text.png" },
  bigStar = { path = "assets/generated/intro/big_star.png" },
  fallingStar = { path = "assets/generated/intro/falling_star.png" },
  fallingStarBlink = { path = "assets/generated/intro/falling_star_blink.png" },
  gengar = {
    frame1 = { path = "assets/generated/intro/gengar_1.png" },
    frame2 = { path = "assets/generated/intro/gengar_2.png" },
    frame3 = { path = "assets/generated/intro/gengar_3.png" },
  },
  nidorino = {
    frame1 = { path = "assets/generated/intro/nidorino_1.png" },
    frame2 = { path = "assets/generated/intro/nidorino_2.png" },
    frame3 = { path = "assets/generated/intro/nidorino_3.png" },
  },
}
local blueGame = { data = { field = {
  title = { version = { path = "assets/generated/title/blue_version.png" } },
  intro = blueIntroManifest,
} } }

local IntroMovie = require("src.ui.IntroMovie")
local blueIntro = IntroMovie.new(blueGame, function() end)
eq(blueIntro.copyright and blueIntro.copyright.path,
  "blue/assets/generated/title/copyright.png",
  "Blue copyright card resolves to the blue/ copy")
eq(blueIntro.studioLogo and blueIntro.studioLogo.path,
  "blue/assets/generated/intro/studio_logo.png",
  "Blue data-driven studio logo resolves to the blue/ copy")
eq(blueIntro.logo and blueIntro.logo.path,
  "blue/assets/generated/intro/gf_logo.png",
  "Blue data-driven gamefreakLogo resolves to the blue/ copy")
eq(blueIntro.gfText and blueIntro.gfText.path,
  "blue/assets/generated/intro/gf_text.png",
  "Blue data-driven gamefreakText resolves to the blue/ copy")
eq(blueIntro.bigStar and blueIntro.bigStar.path,
  "blue/assets/generated/intro/big_star.png",
  "Blue data-driven bigStar resolves to the blue/ copy")
eq(blueIntro.gengarFrames and blueIntro.gengarFrames[2]
    and blueIntro.gengarFrames[2].path,
  "blue/assets/generated/intro/gengar_2.png",
  "Blue data-driven gengar frame resolves to the blue/ copy")
eq(blueIntro.nidoFrames and blueIntro.nidoFrames[3]
    and blueIntro.nidoFrames[3].path,
  "blue/assets/generated/intro/nidorino_3.png",
  "Blue data-driven nidorino frame resolves to the blue/ copy")

local blueTitle = TitleState.new(blueGame, {})
check(not blueTitle.yellowLayout,
  "the Blue manifest keeps the cycling-mons layout")
eq(blueTitle.version and blueTitle.version.path,
  "blue/assets/generated/title/blue_version.png",
  "Blue title ribbon resolves to the blue/ copy")
eq(blueTitle.player and blueTitle.player.path,
  "blue/assets/generated/title/player.png",
  "Blue title player resolves to the blue/ copy")
eq(love.filesystem.read("assets/generated/title/blue_version.png"),
  "blue-version-bytes",
  "a generated filesystem.read resolves to the blue/ bytes")

check(countRecorded("blue/assets/generated/") >= 12,
  "the boot pulled its generated art through the blue/ prefix")
assertNoBareGenerated("blue/", "Blue boot")

-- --- cleanup ------------------------------------------------------------
Overlay.uninstall()
check(not Overlay.isInstalled(), "overlay uninstalls")
love.graphics.newImage = rawNewImage
love.filesystem.read = rawRead
love.sound.newSoundData = rawNewSoundData
love.audio = nil
for _, path in ipairs(seeded) do
  love.filesystem.remove(path)
end
Platform._resetForTests()
GameVersion.set(savedVersion)

T.finish()
