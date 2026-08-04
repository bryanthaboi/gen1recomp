-- NX writable-inbox import: path hint, rescan, validate, hash route (SWNX-05..09).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer NX inbox")
local eq = S.eq
local check = S.check

local GameVersion = require("src.core.GameVersion")
local RomImporter = require("src.import.RomImporter")

local MiB = 1024 * 1024
local redData = string.rep("R", MiB)
local blueData = string.rep("B", MiB)
local yellowData = string.rep("Y", MiB)
local badSizeData = string.rep("?", MiB - 1)
local unknownData = string.rep("?", MiB)

love.data = love.data or {}
love.system = love.system or {}
love.filesystem = love.filesystem or {}

local saved = {
  hash = love.data.hash,
  encode = love.data.encode,
  getOS = love.system.getOS,
  getSaveDirectory = love.filesystem.getSaveDirectory,
  createDirectory = love.filesystem.createDirectory,
  remove = love.filesystem.remove,
}

love.data.hash = function(_, data)
  return { tag = data:sub(1, 1) }
end
love.data.encode = function(_, _, digest)
  if type(digest) == "table" and digest.tag == "R" then
    return GameVersion.info("red").sha1
  end
  if type(digest) == "table" and digest.tag == "B" then
    return GameVersion.info("blue").sha1
  end
  if type(digest) == "table" and digest.tag == "Y" then
    return GameVersion.info("yellow").sha1
  end
  return "0000000000000000000000000000000000000000"
end

love.system.getOS = function() return "NX" end
love.filesystem.getSaveDirectory = function() return "sdmc:/switch/gen1recomp/pokemon-love2d" end

local createdDirs = {}
love.filesystem.createDirectory = function(name)
  createdDirs[name] = true
  return true
end

local removed = {}
love.filesystem.remove = function(name)
  removed[name] = true
  return saved.remove(name)
end

package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
RomImporter = require("src.import.RomImporter")

-- mtpHintPath strips only validated sdmc:/ prefix
eq(RomImporter.mtpHintPath("sdmc:/switch/gen1recomp/pokemon-love2d"),
  "switch/gen1recomp/pokemon-love2d", "mtpHintPath strips sdmc:/")
eq(RomImporter.mtpHintPath("/save/pokemon-love2d"),
  "/save/pokemon-love2d", "mtpHintPath leaves non-sdmc paths alone")
eq(RomImporter.mtpHintPath("sdmc:"), "sdmc:",
  "mtpHintPath does not strip bare sdmc: without slash")

local function clearInbox()
  for _, name in ipairs(love.filesystem.getDirectoryItems("imports") or {}) do
    love.filesystem.remove("imports/" .. name)
  end
  for _, name in ipairs(love.filesystem.getDirectoryItems("") or {}) do
    if name:lower():match("%.gbc?$") then love.filesystem.remove(name) end
  end
end

local function freshImporter(ready)
  clearInbox()
  createdDirs = {}
  removed = {}
  package.loaded["src.import.RomImporter"] = nil
  RomImporter = require("src.import.RomImporter")
  return setmetatable({
    isNX = true,
    romImportMode = "save-directory",
    mobileFileBridge = false,
    android = false,
    launcher = true,
    workState = nil,
    tab = "red",
    ready = {
      red = ready.red and true or false,
      blue = ready.blue and true or false,
      yellow = ready.yellow and true or false,
    },
    notice = nil,
    chooseVersion = nil,
    startData = function(self, data, displayName)
      self._started = { data = data, name = displayName }
      if #data ~= MiB then
        self.workState = "error"
        self.detail = "size"
      elseif not GameVersion.forSha1(
          love.data.encode("string", "hex", love.data.hash("sha1", data))) then
        self.workState = "error"
        self.detail = "hash"
      end
    end,
    setError = function(self, message)
      self.workState = "error"
      self.detail = message
    end,
    ensureImportsDir = RomImporter.ensureImportsDir,
    _setNxInboxNotice = RomImporter._setNxInboxNotice,
    scanInbox = RomImporter.scanInbox,
    rescanAction = RomImporter.rescanAction,
  }, RomImporter)
end

-- First open creates imports/ and shows save path + MTP hint
createdDirs = {}
local ri = freshImporter({ red = false, blue = false, yellow = false })
ri:ensureImportsDir()
check(createdDirs.imports, "ensureImportsDir creates imports/")
ri:_setNxInboxNotice("red")
check(ri.notice ~= nil, "NX notice is set")
check(ri.notice.detail:find("sdmc:/switch/gen1recomp/pokemon-love2d/imports/", 1, true),
  "notice contains runtime save path")
check(ri.notice.detail:find("DBI MTP", 1, true) ~= nil,
  "notice contains OpenMTP-oriented hint")
check(ri.notice.detail:find("switch/gen1recomp/pokemon-love2d/imports/", 1, true),
  "hint uses sdmc-stripped relative path")

-- Empty inbox rescan refreshes notice
ri = freshImporter({ red = false, blue = false, yellow = false })
ri:rescanAction("red")
check(ri.notice ~= nil, "empty inbox rescan shows notice")
check(ri._started == nil, "empty inbox does not start import")

-- Bad extension ignored
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/readme.txt", "nope")
ri:rescanAction("red")
check(ri._started == nil, "non-ROM extension is ignored")

-- Bad size rejected
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/small.gb", badSizeData)
ri:rescanAction("red")
check(ri._started ~= nil, "undersized ROM triggers import attempt")
eq(ri.workState, "error", "undersized ROM is rejected")
check(ri._started.name == "small.gb", "bad size uses basename")

-- Unknown hash rejected
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/hacked.gb", unknownData)
ri:rescanAction("red")
check(ri._started ~= nil, "unknown hash ROM is routed through startData")
eq(ri.workState, "error", "unknown hash is rejected")

-- Valid Red from imports/
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/pokemon red.gb", redData)
ri:rescanAction("red")
check(ri._started ~= nil, "valid Red stub imports")
eq(ri._started.name, "pokemon red.gb", "unicode/space filename preserved")
eq(ri._started.data, redData, "Red bytes passed through")
check(not removed["pokemon red.gb"], "NX retains source dump after import start")

-- imports/ scanned before save root
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/blue.gbc", blueData)
love.filesystem.write("red_root.gb", redData)
ri:rescanAction("blue")
eq(ri._started.name, "blue.gbc", "imports/ wins over save root ordering")

-- Already-imported dump skipped so another version can import
ri = freshImporter({ red = true, blue = false, yellow = false })
love.filesystem.write("imports/pokemon red.gb", redData)
love.filesystem.write("imports/pokemon blue.gb", blueData)
ri:rescanAction("blue")
eq(ri._started.name, "pokemon blue.gb", "ready Red dump ignored for pending Blue")

-- Yellow valid stub
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/pika.gbc", yellowData)
ri:rescanAction("yellow")
eq(ri._started.name, "pika.gbc", "valid Yellow stub imports")

-- Tab Scan again matches by SHA: Yellow must not import a pending Red dump
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/pokemon red.gb", redData)
ri:rescanAction("yellow")
check(ri._started == nil, "Yellow Scan again does not import pending Red")
check(ri.notice ~= nil, "Yellow Scan again with only Red sets notice")
eq(ri.notice.version, "yellow", "notice stays on Yellow tab")
check(ri.notice.status:find("matching", 1, true) or ri.notice.status:find("Matching", 1, true),
  "notice reports no matching ROM for the tab")

-- Mixed inbox: Red listed first, Yellow pending — Yellow tab still picks Yellow
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/aaa_red.gb", redData)
love.filesystem.write("imports/zzz_yellow.gbc", yellowData)
ri:rescanAction("yellow")
eq(ri._started.name, "zzz_yellow.gbc",
  "Yellow Scan again prefers Yellow SHA over earlier Red file")

-- Blue tab ignores pending Red (same SHA filter as Yellow)
ri = freshImporter({ red = false, blue = false, yellow = false })
love.filesystem.write("imports/pokemon red.gb", redData)
ri:rescanAction("blue")
check(ri._started == nil, "Blue Scan again does not import pending Red")
eq(ri.notice.version, "blue", "Blue-only-other-dump notice stays on Blue")

-- Target already ready in a mixed inbox → No new ROM (not other-version import)
ri = freshImporter({ red = false, blue = false, yellow = true })
love.filesystem.write("imports/aaa_red.gb", redData)
love.filesystem.write("imports/zzz_yellow.gbc", yellowData)
ri:rescanAction("yellow")
check(ri._started == nil, "ready Yellow + pending Red does not start import")
check(ri.notice ~= nil and ri.notice.status:find("No new ROM", 1, true),
  "ready Yellow dump yields No new ROM found")

-- Cleanup + restore stubs shared with other suites
love.filesystem.remove("imports/readme.txt")
love.filesystem.remove("imports/small.gb")
love.filesystem.remove("imports/hacked.gb")
love.filesystem.remove("imports/pokemon red.gb")
love.filesystem.remove("imports/blue.gbc")
love.filesystem.remove("imports/pokemon blue.gb")
love.filesystem.remove("imports/pika.gbc")
love.filesystem.remove("imports/aaa_red.gb")
love.filesystem.remove("imports/zzz_yellow.gbc")
love.filesystem.remove("red_root.gb")
love.data.hash = saved.hash
love.data.encode = saved.encode
love.system.getOS = saved.getOS
love.filesystem.getSaveDirectory = saved.getSaveDirectory
love.filesystem.createDirectory = saved.createDirectory
love.filesystem.remove = saved.remove
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
