-- #2103: Android diploma / dex prints write under prints/ in the app-private
-- save dir, which USB and file managers often show as empty.  Printer.save
-- must call love.system.exportImage so GameActivity can copy into
-- Pictures/Gen1Recomp and media-scan the in-app file.
--   luajit tests/engine/printer_android_gallery_bug2103.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Printer = require("src.core.Printer")

-- ------- Android: gallery bridge is called with the prints/ path

do
  local exported = {}
  love.system.getOS = function() return "Android" end
  love.system.exportImage = function(path)
    exported[#exported + 1] = path
    return true
  end

  local path, err = Printer.save("diploma", 40, 36, function() end)
  check(path ~= nil, "Printer.save still returns the prints/ path (" .. tostring(err) .. ")")
  check(path:match("^prints/diploma_.*%.png$") ~= nil,
    "the PNG stays under prints/ for the in-app copy")
  eq(#exported, 1, "Android asks the native bridge to export the image")
  eq(exported[1], path, "and hands it the same relative path")
  eq(Printer.lastAlbumPath, "Pictures/Gen1Recomp",
    "the Printed dialog can say Pictures/Gen1Recomp")
  local where = Printer.savedWhereText(path)
  check(where:find("Pictures/Gen1Recomp", 1, true) ~= nil,
    "savedWhereText points at the public album")
  check(where:find("save", 1, true) == nil
      or where:find("Pictures", 1, true) ~= nil,
    "and does not claim the invisible save folder alone")
end

-- ------- Desktop: no gallery bridge call

do
  local calls = 0
  love.system.getOS = function() return "Linux" end
  love.system.exportImage = function()
    calls = calls + 1
    return true
  end
  local path = Printer.save("dex_1", 40, 36, function() end)
  check(path ~= nil, "desktop print still writes")
  eq(calls, 0, "desktop does not call exportImage")
  eq(Printer.lastAlbumPath, nil, "desktop has no album hint")
  local where = Printer.savedWhereText(path)
  check(where:find(path, 1, true) ~= nil,
    "desktop still names the save-folder PNG")
end

-- ------- Missing bridge: print still succeeds (new .love on old APK)

do
  love.system.getOS = function() return "Android" end
  love.system.exportImage = nil
  local path = Printer.save("box_1", 40, 36, function() end)
  check(path ~= nil, "print works when exportImage is absent (old APK)")
  eq(Printer.lastAlbumPath, nil, "no album hint without the bridge")
  local where = Printer.savedWhereText(path)
  check(where:find(path, 1, true) ~= nil,
    "old APK falls back to the save-folder path in the Printed dialog")
  check(where:find("Pictures/Gen1Recomp", 1, true) == nil,
    "and does not claim the gallery copy that never happened")
end

-- ------- Bridge present but returns false / throws: same soft fallback

do
  love.system.getOS = function() return "Android" end
  love.system.exportImage = function() error("JNI method missing") end
  local path = Printer.save("surf_hiscore", 40, 20, function() end)
  check(path ~= nil, "print survives a throwing exportImage bridge")
  eq(Printer.lastAlbumPath, nil, "a failed bridge leaves no album hint")

  love.system.exportImage = function() return false end
  path = Printer.save("box_2", 40, 20, function() end)
  check(path ~= nil, "print survives exportImage returning false")
  eq(Printer.lastAlbumPath, nil, "false from the bridge is not a gallery success")
end

-- ------- Native + Lua surface pins

do
  local java = assert(io.open(
    "mobile/android/love/src/main/java/org/love2d/android/GameActivity.java")):read("*a")
  check(java:find("exportImageToGallery", 1, true) ~= nil,
    "GameActivity exports exportImageToGallery")
  check(java:find("Pictures", 1, true) ~= nil
      and java:find("Gen1Recomp", 1, true) ~= nil,
    "gallery target is Pictures/Gen1Recomp")
  check(java:find("MediaScannerConnection", 1, true) ~= nil,
    "and media-scans the in-app prints/ copy for USB")

  local wrap = assert(io.open(
    "mobile/android/love/src/jni/love/src/modules/system/wrap_System.cpp")):read("*a")
  check(wrap:find('"exportImage"', 1, true) ~= nil,
    "love.system.exportImage is registered")
end

T.finish("printer_android_gallery_bug2103")
