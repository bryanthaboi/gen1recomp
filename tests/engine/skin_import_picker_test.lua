-- Skins tab Import button: picker plumbing + path/drop install (SKINIMP-01..05).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("skin import picker")
local eq = S.eq
local check = S.check

local RomImporter = require("src.import.RomImporter")
local TouchSkin = require("src.core.TouchSkin")

love.system = love.system or {}
local saved = {
  pickFile = love.system.pickFile,
  getPickedFile = love.system.getPickedFile,
  getPickError = love.system.getPickError,
  installArchive = TouchSkin.installArchive,
}

local installed
TouchSkin.installArchive = function(name, data)
  installed = { name = name, data = data }
  if not data or data == "" then return nil, "empty archive" end
  return (name:match("([^/\\]+)$") or name):gsub("%.[Zz][Ii][Pp]$", "")
end

local function freshImporter(fields)
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.tab = "skins"
  imp._skins = {}
  imp._ensureSkins = function(self) return self._skins end
  for k, v in pairs(fields or {}) do imp[k] = v end
  return imp
end

-- SKINIMP-01: a picker path installs as a skin, not a mod
installed = nil
local imp = freshImporter()
local tmp = os.tmpname() .. ".zip"
local f = assert(io.open(tmp, "wb"))
f:write("PK\3\4skin-archive")
f:close()
imp:_installSkinZip(tmp)
os.remove(tmp)
check(installed ~= nil, "an absolute picker path reaches TouchSkin.installArchive")
eq(installed.data, "PK\3\4skin-archive", "the picked file's bytes are installed")
check(imp._skinNotice and imp._skinNotice.ok, "a good pick reports success")

-- SKINIMP-02: a dropped file still installs, and both paths land on the tab
installed = nil
imp = freshImporter({ tab = "red" })
imp:filedropped({
  getFilename = function() return "/tmp/dropped_skin.zip" end,
  getSize = function() return 4 end,
  open = function() return true end,
  read = function() return "PKZP" end,
  close = function() return true end,
})
check(installed == nil, "a zip dropped off the skins tab is still a mod")
installed = nil
imp = freshImporter()
imp:filedropped({
  getFilename = function() return "/tmp/dropped_skin.zip" end,
  getSize = function() return 4 end,
  open = function() return true end,
  read = function() return "PKZP" end,
  close = function() return true end,
})
eq(installed and installed.name, "/tmp/dropped_skin.zip",
  "a zip dropped on the skins tab installs as a skin")
eq(imp.tab, "skins", "the skin install stays on the skins tab")

-- SKINIMP-03: the mobile bridge borrows the mod picker kind
local requestedKind
love.system.pickFile = function(kind)
  requestedKind = kind
  return true
end
love.system.getPickedFile = function() return nil end
love.system.getPickError = function() return nil end
imp = freshImporter({ nativePicker = true })
imp:chooseSkin()
eq(requestedKind, "mod", "chooseSkin opens the .zip picker")
eq(imp.pickerPendingKind, "skin", "the pending pick is routed to the skins tab")

-- SKINIMP-04: the picked file comes back through update() as a skin
installed = nil
love.system.getPickedFile = function()
  love.system.getPickedFile = function() return nil end
  return "/picked/from_bridge.zip"
end
imp._installSkinZip = function(self, source)
  self.installedSource = source
  self._skinNotice = { ok = true, text = "Imported from_bridge" }
end
imp:update(0)
eq(imp.installedSource, "/picked/from_bridge.zip",
  "update() hands the picked path to the skin installer")
eq(imp.pickerPendingKind, nil, "the pending kind clears once consumed")

-- SKINIMP-05: a picker error lands on the skins notice, not the mods one
love.system.getPickedFile = function() return nil end
love.system.getPickError = function()
  love.system.getPickError = function() return nil end
  return "picker refused"
end
imp = freshImporter({ nativePicker = true, pickerPendingKind = "skin" })
imp:update(0)
check(imp._skinNotice and not imp._skinNotice.ok,
  "a failed skin pick reports on the skins tab")
eq(imp.modNotice, nil, "a failed skin pick leaves the mods notice alone")

love.system.pickFile = saved.pickFile
love.system.getPickedFile = saved.getPickedFile
love.system.getPickError = saved.getPickError
TouchSkin.installArchive = saved.installArchive

S.finish()
