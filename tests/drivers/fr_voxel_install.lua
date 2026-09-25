-- Android-lifecycle install: the packaged game.love carries NO mods/ (read-only
-- APK), so the phone flow is launcher -> MODS -> Import mod .zip.  This driver
-- runs that real installZip against a zip staged in the save dir, the same
-- place the platform file pickers drop their uploads.
--
--   copy dist/mods/fr_voxel.zip <savedir>/fr_voxel.zip
--   POKEPORT_DRIVER=tests/drivers/fr_voxel_install.lua love <game.love>

local U = require("tests.drivers.util")

local ZIP = "fr_voxel.zip"

local failures = 0
local function result(ok, label, extra)
  if extra ~= nil then label = label .. " -- " .. tostring(extra) end
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print(failures == 0 and "PASS fr_voxel_install"
    or ("FAIL fr_voxel_install failures=" .. failures))
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  local okReq, LauncherMods = pcall(require, "src.mods.LauncherMods")
  if not result(okReq, "require src.mods.LauncherMods", LauncherMods) then
    finish()
    return
  end

  result(love.filesystem.getInfo(ZIP) ~= nil, "mod zip staged in the save dir", ZIP)

  local okCall, ok, idOrErr = pcall(LauncherMods.installZip, ZIP)
  if result(okCall and ok == true, "installZip accepted the archive",
      okCall and tostring(idOrErr) or tostring(idOrErr)) then
    result(idOrErr == "fr_voxel", "installed id is fr_voxel", tostring(idOrErr))
    result(love.filesystem.getInfo("mods/fr_voxel/manifest.json") ~= nil,
      "manifest landed in save-dir mods/fr_voxel/")
    result(love.filesystem.getInfo("mods/fr_voxel/lib/Voxel3D.lua") ~= nil,
      "lib payload installed")
    local versions = LauncherMods.installedVersions()
    result(type(versions) == "table" and type(versions.fr_voxel) == "string",
      "installedVersions reports fr_voxel",
      versions and tostring(versions.fr_voxel))
  end

  finish()
end
