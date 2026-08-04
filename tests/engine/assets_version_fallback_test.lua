-- NxAssetOverlay: fused love-nx often cannot mount blue|yellow onto
-- assets/generated, so on NX the love loaders are wrapped once at boot and
-- fall back to the versioned save-dir path.  Desktop/Android never install
-- the overlay; the chip worker gets the prefix explicitly via the audio
-- payload.  Self-contained: luajit tests/engine/assets_version_fallback_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local Platform = require("src.core.Platform")
local Assets = require("src.render.Assets")
local Overlay = require("src.core.NxAssetOverlay")

local PNG = "assets/generated/tilesets/reds_house.png"
local savedVersion = GameVersion.get()
local savedSystem = love.system

local function clearPath(path)
  love.filesystem.remove(path)
end

local function setOS(osName)
  love.system = {
    getOS = function() return osName end,
  }
  Platform._resetForTests()
end

-- --- Assets.resolve stays platform-free: no rewrite even for NX Yellow
setOS("NX")
GameVersion.set("yellow")
love.filesystem.write("yellow/" .. PNG, "yellow-png-bytes")
clearPath(PNG)
eq(Assets.resolve(PNG), PNG,
  "resolve is the identity without a mod loader (overlay owns NX fallback)")

-- --- Overlay installed: every loader falls back to the versioned path
-- Write-side functions must NEVER be wrapped (the importer targets the
-- versioned tree explicitly); capture references to prove identity.
local rawWrite = love.filesystem.write
local rawRemove = love.filesystem.remove
local rawGetInfo = love.filesystem.getInfo
local seed_chunk = "assets/generated/boot_chunk.lua"
love.filesystem.write("yellow/" .. seed_chunk, "return 42")

Overlay.install()
check(Overlay.isInstalled(), "overlay installs")
check(love.filesystem.write == rawWrite,
  "install leaves filesystem.write stock (writes never wrapped)")
check(love.filesystem.remove == rawRemove,
  "install leaves filesystem.remove stock")
check(love.filesystem.getInfo ~= rawGetInfo, "install wraps getInfo")

local img = love.graphics.newImage(PNG)
eq(img.path, "yellow/" .. PNG, "wrapped newImage receives the yellow/ path")

local id = love.image.newImageData(PNG)
eq(id.path, "yellow/" .. PNG, "wrapped newImageData receives the yellow/ path")

eq(love.filesystem.read(PNG), "yellow-png-bytes",
  "wrapped filesystem.read returns the versioned bytes")

check(love.filesystem.getInfo(PNG) ~= nil,
  "wrapped getInfo sees the versioned file at the un-prefixed path")

-- The whole read surface, not just image/audio loaders: a future state
-- using any of these APIs with a generated path stays inside the fallback.
local chunk = love.filesystem.load(seed_chunk)
eq(type(chunk) == "function" and chunk() or nil, 42,
  "wrapped filesystem.load resolves the versioned chunk")

local sd = love.sound.newSoundData(PNG)
eq(sd.path, "yellow/" .. PNG,
  "wrapped newSoundData receives the yellow/ path (widenMono's re-read)")
eq(sd:getChannelCount(), 1,
  "path-form newSoundData stays mono so widenMono has work to do")
eq(sd:getBitDepth(), 8, "path-form stub mimics the 8-bit pika-cry WAVs")

local fnt = love.graphics.newFont(14)
check(fnt ~= nil, "wrapped newFont ignores non-path arguments")

-- Assets.image/imageData benefit transparently (no call-site changes)
Assets.flush()
local aimg = Assets.image(PNG)
eq(aimg.path, "yellow/" .. PNG, "Assets.image loads via the overlay")

-- Non-string arguments pass through untouched
local fromData = love.graphics.newImage(id)
check(fromData ~= nil, "newImage(ImageData) is not rewritten")

-- Non-generated paths pass through untouched
local launcher = love.graphics.newImage("assets/launcher/gear.png")
eq(launcher.path, "assets/launcher/gear.png",
  "overlay leaves non-generated paths alone")

-- The real un-prefixed file wins when it exists
love.filesystem.write(PNG, "root-png-bytes")
eq(love.filesystem.read(PNG), "root-png-bytes",
  "overlay prefers the real un-prefixed file over the versioned copy")
clearPath(PNG)

-- Blue gets the same treatment
GameVersion.set("blue")
love.filesystem.write("blue/" .. PNG, "blue-png-bytes")
clearPath("yellow/" .. PNG)
eq(love.filesystem.read(PNG), "blue-png-bytes",
  "overlay maps generated reads to blue/ for Blue")

-- Red has no prefix: nothing is rewritten
GameVersion.set("red")
clearPath("blue/" .. PNG)
eq(love.filesystem.read(PNG), nil, "Red keeps the stock miss behavior")

-- Uninstall restores the stock loaders byte for byte
GameVersion.set("yellow")
love.filesystem.write("yellow/" .. PNG, "yellow-png-bytes")
Overlay.uninstall()
check(not Overlay.isInstalled(), "overlay uninstalls")
eq(love.filesystem.read(PNG), nil,
  "after uninstall the stock loader no longer sees the versioned path")

-- --- ChipSynth honors audio.programPrefix (the worker exception)
local ChipSynth = require("src.core.ChipSynth")
ChipSynth.invalidateBanks()
local PROG = "assets/generated/audio/programs.bin"
local PROG_BYTES = string.rep("\0", 0x4000 * 2)
clearPath(PROG)
love.filesystem.write("yellow/" .. PROG, PROG_BYTES)
local workerData = { audio = {
  programFile = PROG,
  programPrefix = "yellow/",
  bankOrder = { 1, 2 },
} }
local okW, wbanks = pcall(ChipSynth._loadBanksForTest, workerData)
check(okW and wbanks ~= nil, "loadBanks uses audio.programPrefix when set")
if okW and wbanks then
  eq(wbanks[1], PROG_BYTES:sub(1, 0x4000),
    "programPrefix loads the bank 1 bytes from the versioned file")
end

-- Without programPrefix the sync path relies on the overlay/mount: with the
-- overlay uninstalled (this test process), the plain read misses.
ChipSynth.invalidateBanks()
local plainData = { audio = { programFile = PROG, bankOrder = { 1, 2 } } }
local okP = pcall(ChipSynth._loadBanksForTest, plainData)
check(not okP, "without programPrefix or overlay, programs.bin is a clean miss")

-- --- ChipAudio.slimAudio hands the NX prefix to the worker payload
setOS("NX")
GameVersion.set("yellow")
local ChipAudio = require("src.core.ChipAudio")
local slim = ChipAudio._slimAudioForTest(plainData)
eq(slim.programPrefix, "yellow/",
  "slimAudio passes the NX cache prefix to the worker")
setOS("OS X")
local slimDesktop = ChipAudio._slimAudioForTest(plainData)
eq(slimDesktop.programPrefix, nil,
  "desktop worker payloads carry no prefix (mount owns the overlay)")

clearPath("yellow/" .. PNG)
clearPath("yellow/" .. PROG)
clearPath("yellow/" .. seed_chunk)

love.system = savedSystem
Platform._resetForTests()
GameVersion.set(savedVersion)
Assets.flush()

T.finish()
