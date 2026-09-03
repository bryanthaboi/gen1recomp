-- Game Boy Printer stand-in.  Yellow's printer jobs
-- (engine/printer/printer.asm: PrintPokedexEntry and friends) drove a
-- serial thermal printer; this port renders the same printout into a PNG
-- under prints/ in the save directory instead, and the caller shows a
-- dialog with where it landed.  Scaled up 4x so the "print" is legible
-- on a modern screen.
--
-- On Android the app-private prints/ folder is often invisible over USB /
-- file managers even when the write succeeded (#2103).  After the PNG is
-- written, love.system.exportImage copies it into Pictures/Gen1Recomp and
-- media-scans the in-app copy so both Gallery and the save folder work.

local Logger = require("src.core.Logger")

local Printer = {}

local SCALE = 4
local ANDROID_ALBUM = "Pictures/Gen1Recomp"

-- After a successful Android gallery export, the public album path shown
-- in the "Printed!" dialog.  Nil on desktop / when the bridge is absent.
Printer.lastAlbumPath = nil

local function exportToAndroidGallery(relPath)
  Printer.lastAlbumPath = nil
  if not (love.system and love.system.getOS
      and love.system.getOS() == "Android") then
    return false
  end
  local exportImage = love.system.exportImage
  if type(exportImage) ~= "function" then return false end
  local ok, exported = pcall(exportImage, relPath)
  if ok and exported then
    Printer.lastAlbumPath = ANDROID_ALBUM
    return true
  end
  return false
end

-- Render drawFn (which draws a w x h GB-pixel image at 0,0) into
-- prints/<name>_<stamp>.png.  Returns the save-dir-relative path, or nil
-- and an error string (headless / no canvas support degrades gracefully).
-- On Android a successful gallery copy also sets Printer.lastAlbumPath.
function Printer.save(name, w, h, drawFn)
  Printer.lastAlbumPath = nil
  if not (love.graphics and love.graphics.newCanvas) then
    return nil, "no graphics"
  end
  local ok, canvas = pcall(love.graphics.newCanvas, w * SCALE, h * SCALE)
  if not ok then return nil, tostring(canvas) end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.scale(SCALE, SCALE)
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setColor(1, 1, 1, 1)
  local drawOk, drawErr = pcall(drawFn)
  love.graphics.pop()
  if not drawOk then return nil, tostring(drawErr) end
  local data
  ok, data = pcall(canvas.newImageData, canvas)
  if not ok then return nil, tostring(data) end
  love.filesystem.createDirectory("prints")
  local path = ("prints/%s_%s.png"):format(name, os.date("%Y-%m-%d_%H%M%S"))
  local encOk, err = pcall(data.encode, data, "png", path)
  if not encOk then return nil, tostring(err) end
  Logger.info("printed %s -> %s/%s",
    name, love.filesystem.getSaveDirectory(), path)
  exportToAndroidGallery(path)
  return path
end

-- Second page of the "Printed!" dialog: public album on Android when the
-- gallery bridge worked, otherwise the save-dir-relative PNG path.
function Printer.savedWhereText(path)
  local Strings = require("src.core.Strings")
  if Printer.lastAlbumPath then
    return Strings("Saved to\n%s.", Printer.lastAlbumPath)
  end
  return Strings("Saved as\n%s\vin the save\nfolder.", path)
end

return Printer
