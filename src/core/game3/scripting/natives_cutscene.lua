local Std = require("src.core.game3.scripting.stdscripts")

local Cutscene = {}

local function currentGame()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt._game or nil
end

local function cameraObject()
  local ok, CameraObject = pcall(require, "src.core.game3.camera_object")
  if ok and type(CameraObject) == "table" then return CameraObject end
  return nil
end

Cutscene.HANDLERS = {
  -- pokefirered/src/field_specials.c:318
  [Std.SPECIAL.SpawnCameraObject] = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.spawn then
      pcall(CameraObject.spawn, currentGame())
    end
    return false
  end,
  -- pokefirered/src/field_specials.c:325
  [Std.SPECIAL.RemoveCameraObject] = function()
    local CameraObject = cameraObject()
    if CameraObject and CameraObject.remove then
      pcall(CameraObject.remove, currentGame())
    end
    return false
  end,
  -- pokefirered/src/special_field_anim.c:223
  [Std.SPECIAL.AnimateTeleporterHousing] = function()
    return false
  end,
  -- pokefirered/src/special_field_anim.c:285
  [Std.SPECIAL.AnimateTeleporterCable] = function()
    return false
  end,
}

return Cutscene
