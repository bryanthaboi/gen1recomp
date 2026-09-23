-- Custom Carts "Import .g1rcart" follows the same platform split as ROM, mod,
-- and save import. Self-contained: luajit tests/engine/cart_import_picker.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("cart import picker")
local eq, check = S.eq, S.check

local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  pickFileKinds = love.system.pickFileKinds,
  getPickedFile = love.system.getPickedFile,
}

local picks = {}
local function androidImporter()
  picks = {}
  love.system.getOS = function() return "Android" end
  love.system.pickFile = function(kind)
    picks[#picks + 1] = kind
    return true
  end
  love.system.pickFileKinds = function()
    return "rom,mod,sav,cart,required_import"
  end
  Platform._resetForTests()
  local imp = RomImporter.new(function() end, { launcher = true })
  imp._installCartFile = function(self, source)
    self.installed = source
    self._cartNotice = "Imported Picked One. It is in this list now."
    return true
  end
  return imp
end

local imp = androidImporter()
imp._cartPopup = "red"
eq(imp:importCartFile("red"), true, "Android Import .g1rcart opens the picker")
eq(picks[1], "cart", "and asks for the cart kind, not a ROM")
eq(imp.pickerPendingKind, "cart", "focus knows the staged file is a cart")

love.filesystem.write("picked_cart.g1rcart", "cart-bytes")
imp:focus(true)
eq(imp.installed, "picked_cart.g1rcart", "focus installs the staged cart")
check(love.filesystem.getInfo("picked_cart.g1rcart") == nil,
  "and retires the staged file")

love.system.pickFileKinds = function() return "rom,mod,sav" end
Platform._resetForTests()
local legacy = RomImporter.new(function() end, { launcher = true })
legacy._installCartFile = imp._installCartFile
picks = {}
eq(legacy:importCartFile("red"), false,
  "an Android build that predates the cart kind does not open a ROM picker")
eq(#picks, 0, "and never calls pickFile")
check(type(legacy._cartNotice) == "string" and legacy._cartNotice:find(".g1rcart", 1, true),
  "it tells the player to copy a .g1rcart instead")

love.system.getOS = function() return "NX" end
love.system.pickFile = nil
Platform._resetForTests()
local nx = RomImporter.new(function() end, { launcher = true })
nx._installCartFile = function(self, source)
  self.installed = source
  self._cartNotice = "Imported inbox."
  return true
end
love.filesystem.write("imports/carts/inbox.g1rcart", "cart-bytes")
eq(nx:importCartFile("red"), true, "NX Import scans imports/carts/")
eq(nx.installed, "imports/carts/inbox.g1rcart", "and installs the inbox file")
love.filesystem.remove("imports/carts/inbox.g1rcart")

nx.installed = nil
eq(nx:importCartFile("red"), false, "an empty NX inbox does not invent a cart")
check(nx._cartNotice:find("imports/carts/", 1, true) ~= nil,
  "and the notice names the MTP folder")

-- PS4 shares the NX inbox (no file picker), with FTP in the hints.
love.system.getOS = function() return "PS4" end
Platform._resetForTests()
local ps4 = RomImporter.new(function() end, { launcher = true })
ps4._installCartFile = nx._installCartFile
eq(ps4:_cartImportButtonLabel(), "Scan again", "PS4 cart button rescans the inbox")
love.filesystem.write("imports/carts/inbox.g1rcart", "cart-bytes")
eq(ps4:importCartFile("red"), true, "PS4 Import scans imports/carts/")
eq(ps4.installed, "imports/carts/inbox.g1rcart", "and installs the inbox file")
love.filesystem.remove("imports/carts/inbox.g1rcart")
ps4.installed = nil
eq(ps4:importCartFile("red"), false, "an empty PS4 inbox does not invent a cart")
check(ps4._cartNotice:find("over FTP", 1, true) ~= nil
    and ps4._cartNotice:find("DBI MTP", 1, true) == nil,
  "and the notice says FTP, not the Switch's MTP")

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.system.pickFileKinds = saved.pickFileKinds
love.system.getPickedFile = saved.getPickedFile
Platform._resetForTests()

print("ok   cart import picker")
