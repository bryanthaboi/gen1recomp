-- #1274: with several cartridge dumps sitting in the save directory, Choose
-- ROM imported whichever version was not yet ready rather than the one the
-- player picked.  Select Red, get Blue.
--
-- The fallback exists for devices with no file picker (handheld Linux with
-- no zenity or kdialog, and the Android USB-drop path), where chooseRom
-- returns nil and the importer scans the save directory instead.  That scan,
-- findPendingRom, answered with the first dump whose SHA-1 mapped to any
-- not-yet-ready version, so the selection was dropped on the floor.
--
-- Self-contained: `luajit tests/rom_importer_choose_version_test.lua`
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer honours the chosen version")
local eq = S.eq
local check = S.check

local RomImporter = require("src.import.RomImporter")
local GameVersion = require("src.core.GameVersion")

local ROM_BYTES = 1024 * 1024

-- One dump per version, each a blob of the right size whose first byte says
-- which cart it is.  love.data.hash is stubbed to answer with the real SHA-1
-- from GameVersion, so GameVersion.forSha1 does its own lookup unchanged.
local MARK = { R = "red", B = "blue", Y = "yellow" }
local FILES = {
  ["blue.gb"] = string.rep("B", ROM_BYTES),
  ["red.gb"] = string.rep("R", ROM_BYTES),
  ["yellow.gbc"] = string.rep("Y", ROM_BYTES),
}
-- Deliberately not alphabetical and not selection order: the bug returned
-- whatever getDirectoryItems listed first.
local LISTING = { "blue.gb", "red.gb", "yellow.gbc" }

love.system = love.system or {}
love.data = love.data or {}

local saved = {
  getOS = love.system.getOS,
  hash = love.data.hash,
  encode = love.data.encode,
  getDirectoryItems = love.filesystem.getDirectoryItems,
  getInfo = love.filesystem.getInfo,
  read = love.filesystem.read,
  getSaveDirectory = love.filesystem.getSaveDirectory,
}

-- Not OS X, Windows or Linux, so chooseRom returns nil without shelling out
-- to a dialog that may or may not exist on the machine running the suite.
-- The fallback under test is the same one every pickerless device takes.
love.system.getOS = function() return "Unknown" end
love.filesystem.getSaveDirectory = function() return "/tmp/pokemon-love2d" end
love.filesystem.getDirectoryItems = function() return LISTING end
love.filesystem.getInfo = function(name, filter)
  if FILES[name] then return { type = "file", size = #FILES[name] } end
  return nil
end
love.filesystem.read = function(name) return FILES[name] end
-- RomImporter's sha1 helper is hash then encode-to-hex, so the pair is
-- stubbed together: hash answers with the digest already in the form
-- GameVersion stores, and encode hands it back untouched.
love.data.hash = function(_, data)
  local version = MARK[data:sub(1, 1)]
  return version and GameVersion.info(version).sha1 or "0"
end
love.data.encode = function(_, _, digest) return digest end

local function freshImporter()
  return setmetatable({
    android = false,
    nativePicker = false,
    workState = nil,
    ready = { red = false, blue = false, yellow = false },
    notice = nil,
    modNotice = nil,
    saveNotice = {},
    baseRoms = {},
    chooseVersion = nil,
    startData = function(self, data, displayName)
      self._started = { data = data, name = displayName }
    end,
    startPath = function(self, path) self._startedPath = path end,
  }, RomImporter)
end

-- ------- the report: pick Red, get Red

local ri = freshImporter()
ri:choose("red")
check(ri._started ~= nil, "a pickerless Choose still imports from the save dir")
eq(ri._started and ri._started.name, "red.gb",
  "and it imports the cart that was chosen, not the first pending one")

-- ------- the same for a version listed after another pending dump

ri = freshImporter()
ri:choose("yellow")
eq(ri._started and ri._started.name, "yellow.gbc",
  "Yellow is imported for Yellow, with Blue and Red still pending")

-- ------- a chosen version with no dump present imports nothing

ri = freshImporter()
ri.ready = { red = false, blue = false, yellow = false, gold = false }
ri:choose("gold")
check(ri._started == nil,
  "choosing a version whose dump is absent imports no other cart")

-- ------- an already-imported cart is still never re-extracted (#167)

ri = freshImporter()
ri.ready = { red = true, blue = false, yellow = false }
ri:choose("red")
check(ri._started == nil,
  "and a version already imported is not extracted a second time")

for name, fn in pairs(saved) do
  if name == "getOS" then love.system.getOS = fn
  elseif name == "hash" then love.data.hash = fn
  elseif name == "encode" then love.data.encode = fn
  else love.filesystem[name] = fn end
end

S.finish()
