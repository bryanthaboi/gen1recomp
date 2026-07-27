-- SaveFileIO -- the launcher's glue between a raw Gen1 .sav battery image and
-- this project's save slots.  Keeps RomImporter lean: the SAVE FILES card just
-- calls importToSlot / exportActiveSlot and renders the {ok, result} outcome.
--
-- Import reads bytes (an absolute picker path, a dropped LOVE file, or raw
-- bytes), runs them through SaveConvert.importSav (32768-byte + checksum
-- validated), then registers a fresh slot, writes it, and makes it active.
-- Export loads the active slot, encodes it back to a 32768-byte SRAM image, and
-- drops it in the save directory's exports/ folder, returning the absolute path
-- so the launcher can offer an "open folder" affordance.
--
-- Every failure returns false + a friendly one-line message (never raises), so
-- the card can surface it as a red notice line rather than crashing.

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local SaveFileIO = {}

local SAVE_SIZE = SaveConvert.SAVE_SIZE

-- Resolve raw save bytes from whatever the launcher hands us:
--   * a LOVE DroppedFile (a table/userdata with :open/:read/:getSize), read the
--     way RomImporter reads a dropped ROM;
--   * a raw 32768-byte string (the tests and the in-memory path) used as-is;
--   * any other string treated as an absolute picker path opened with io.open.
-- A picker path is never 32768 bytes long, so the length test disambiguates it
-- from a raw image cleanly.  Returns bytes, or nil + an error string.
local function readSource(source)
  local t = type(source)
  if t == "table" or t == "userdata" then
    if type(source.read) ~= "function" then
      return nil, "that file could not be read"
    end
    local ok, openErr = source:open("r")
    if not ok then return nil, "could not open the dropped file: " .. tostring(openErr) end
    local data, readErr = source:read(source:getSize())
    source:close()
    if not data then return nil, "could not read the dropped file: " .. tostring(readErr) end
    return data
  end
  if t ~= "string" then
    return nil, "no save file was provided"
  end
  if #source == SAVE_SIZE then
    return source
  end
  local f, openErr = io.open(source, "rb")
  if f then
    local data = f:read("*a")
    f:close()
    if type(data) ~= "string" then return nil, "the save file was empty" end
    return data
  end
  -- Android SAF drops (picked_save.sav) and USB copies land in the LOVE save
  -- directory; io.open cannot see them, so fall back to love.filesystem.
  if love and love.filesystem and love.filesystem.read then
    local data = love.filesystem.read(source)
    if type(data) == "string" then return data end
  end
  return nil, "could not read the save file: " .. tostring(openErr)
end

-- importToSlot(source, version) -> ok, slotIdOrErr
-- source: an absolute path, a LOVE DroppedFile, or raw 32768 bytes.  On success
-- registers a new slot for the version, writes the imported save into it, makes
-- it the active slot, and returns true + the new slot id.  On any failure
-- returns false + a friendly message.
function SaveFileIO.importToSlot(source, version)
  version = version or GameVersion.get()
  local bytes, readErr = readSource(source)
  if not bytes then return false, readErr end
  if #bytes ~= SAVE_SIZE then
    return false, ("A save file must be %d bytes (32 KB); this one is %d.")
      :format(SAVE_SIZE, #bytes)
  end
  local save, convertErr = SaveConvert.importSav(bytes, version)
  if not save then return false, convertErr end
  -- Tag the game version and normalize the meta stamp: SaveConvert leaves
  -- meta.format = "gen1_import", but SaveData.load's migration pass compares
  -- the format numerically, so re-stamp it to the current format (the imported
  -- table is already current-shaped, so no migration is skipped by doing so).
  save.version = version
  save.meta = SaveData.buildMeta(nil, save.meta)
  local slotId = SaveData.createSlot(version)
  if not slotId then return false, "this game has no save slots to import into" end
  local ok, writeErr = SaveData.writeSlot(version, slotId, save)
  if not ok then
    return false, "could not write the imported save: " .. tostring(writeErr)
  end
  SaveData.setActiveSlot(version, slotId)
  return true, slotId
end

-- exportActiveSlot(version) -> ok, pathOrErr
-- Loads the version's active slot save (SaveData.load semantics), encodes it
-- back to a 32768-byte SRAM image, and writes it to
-- exports/gen1recomp-<version>-<slotId>.sav in the save directory (created if
-- absent).  Returns true + the absolute path on success, false + a friendly
-- message otherwise.
function SaveFileIO.exportActiveSlot(version)
  version = version or GameVersion.get()
  local save = SaveData.load(version)
  if not save then return false, "this game has no save to export yet" end
  local bytes, exportErr = SaveConvert.exportSav(save)
  if not bytes then return false, exportErr end
  local slotId = SaveData.activeSlot(version) or "save"
  local fs = love and love.filesystem
  if not (fs and fs.write) then return false, "no filesystem available to export to" end
  if fs.createDirectory then fs.createDirectory("exports") end
  local rel = ("exports/gen1recomp-%s-%s.sav"):format(version, slotId)
  local ok, writeErr = fs.write(rel, bytes)
  if not ok then return false, "could not write the export: " .. tostring(writeErr) end
  local base = fs.getSaveDirectory and fs.getSaveDirectory() or ""
  if base ~= "" then return true, base .. "/" .. rel end
  return true, rel
end

return SaveFileIO
