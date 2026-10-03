package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("UWP native picker")
local check = S.check

local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  getPickedFile = love.system.getPickedFile,
  getPickError = love.system.getPickError,
  remove = os.remove,
}

love.system.getOS = function() return "UWP" end
love.system.pickFile = function() return true end
love.system.getPickedFile = function()
  love.system.getPickedFile = function() return nil end
  return [[C:\LocalState\picked_mod.zip]]
end
love.system.getPickError = function() return nil end

local removedPath
os.remove = function(path)
  removedPath = path
  return true
end

Platform._resetForTests()
local importer = RomImporter.new(function() end, { launcher = true })
importer.pickerPendingKind = "mod"
importer._installMod = function(self, source)
  self.installedPath = source
  self.modNotice = { ok = true, text = "Installed test-mod" }
end
importer:update(0)

check(importer.installedPath == [[C:\LocalState\picked_mod.zip]],
  "passes the picked path to the mod installer")
check(removedPath == [[C:\LocalState\picked_mod.zip]],
  "removes the temporary copy after installation")

-- The UWP picker returns a temporary path rather than a mobile staged name.
-- Required imports must use that same picker and remain scoped to the selected
-- mod instead of relying on a desktop shell or Android/iOS inbox handling.
local pickedKind
love.system.pickFile = function(kind)
  pickedKind = kind
  return true
end
love.system.getPickedFile = function()
  love.system.getPickedFile = function() return nil end
  return [[C:\LocalState\picked_required_import.bin]]
end
removedPath = nil
local required = RomImporter.new(function() end, { launcher = true })
required.mods = { {
  id = "needs-source",
  manifest = {
    id = "needs-source", name = "Needs source",
    required_imports = { {
      id = "source", name = "Source", file = "source.bin",
      md5 = { "00000000000000000000000000000000" },
    } },
  },
} }
required._importRequiredSource = function(self, modId, importId, path)
  self.requiredPath = { modId = modId, importId = importId, path = path }
  return true
end
required:chooseRequiredImport("needs-source", "source")
check(pickedKind == "required_import", "UWP requests the required-import picker kind")
required:update(0)
check(required.requiredPath and required.requiredPath.path
    == [[C:\LocalState\picked_required_import.bin]],
  "UWP routes the picked dependency to its declared import")
check(required.requiredPath.modId == "needs-source"
    and required.requiredPath.importId == "source",
  "UWP preserves the pending mod and import identity")
check(removedPath == [[C:\LocalState\picked_required_import.bin]],
  "UWP removes its temporary required-import copy after validation")

-- Importer descriptors, rather than the launcher's GB/GBA defaults, select
-- the native ROM filter. The source bytes are validated by the importer.
local pickedFormats
love.system.pickFile = function(kind, formats)
  pickedKind, pickedFormats = kind, formats
  return true
end
local gen5 = RomImporter.new(function() end, { launcher = true })
gen5:_beginImporterImport("gen5_bw")
check(pickedKind == "rom" and pickedFormats == "nds",
  "Gen 5 UWP picker receives the descriptor's NDS format")
check(gen5.pickerPendingKind == "importer"
    and gen5.pickerPendingImporterId == "gen5_bw",
  "Gen 5 picker preserves importer routing")
love.system.pickFile = function() return false end
gen5.pickerPendingKind, gen5.pickerPendingImporterId = nil, nil
gen5:_beginImporterImport("gen5_bw")
check(gen5.pickerPendingKind == nil and gen5.pickerPendingImporterId == nil
    and gen5._importerNotice ~= nil,
  "failed native importer picker clears its pending route")

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.system.getPickedFile = saved.getPickedFile
love.system.getPickError = saved.getPickError
os.remove = saved.remove
Platform._resetForTests()

S.finish()
