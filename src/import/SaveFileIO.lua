-- SaveFileIO -- the launcher's glue between a raw Gen1 .sav battery image and
-- this project's save slots.  Keeps RomImporter lean: the SAVE FILES card just
-- calls importToSlot / exportActiveSlot and renders the {ok, result} outcome.
--
-- Import reads bytes (an absolute picker path, a dropped LOVE file, or raw
-- bytes), runs them through SaveConvert.importSav (32768-byte + checksum
-- validated), then registers a fresh slot, writes it, and makes it active.
-- Export loads the active slot, encodes it back to a 32768-byte SRAM image, and
-- drops it in exports/<version>/ under the same root SaveData's persistFs
-- writes slots to -- the portable game folder when portable.txt marks the
-- install, otherwise the LOVE save directory (#752) -- returning the absolute
-- path so the launcher can offer an "open folder" affordance.
--
-- Every failure returns false + a friendly one-line message (never raises), so
-- the card can surface it as a red notice line rather than crashing.

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local SaveFileIO = {}

-- The cartridge image an imported Gen 2 slot came from, kept BESIDE the slot
-- rather than inside it: export needs the regions the codec does not model,
-- and 32 KB of binary in the serialized table is 40 KB of Lua source reparsed
-- on every save and load.
local function cartPath(version, slotId)
  return ("saves/%s/%s.cart"):format(version, tostring(slotId))
end

local function cartFs()
  local portable = SaveData.portableFs and SaveData.portableFs()
  return portable or (love and love.filesystem)
end

local function writeCart(version, slotId, bytes)
  local fs = cartFs()
  if not (fs and fs.write and bytes) then return end
  if fs.createDirectory then
    fs.createDirectory("saves")
    fs.createDirectory("saves/" .. version)
  end
  fs.write(cartPath(version, slotId), bytes)
end

local function readCart(version, slotId)
  local fs = cartFs()
  if not (fs and fs.read) then return nil end
  local ok, bytes = pcall(fs.read, cartPath(version, slotId))
  if ok and type(bytes) == "string" then return bytes end
  return nil
end

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

-- importToSlot(source, version, force) -> ok, slotIdOrErr | (false, nil, info)
-- source: an absolute path, a LOVE DroppedFile, or raw bytes.  On success
-- registers a new slot for the version, writes the imported save into it, makes
-- it the active slot, and returns true + the new slot id.  On any failure
-- returns false + a friendly message.  force only matters for a file LARGER
-- than 32768 bytes whose first 32768 bytes carry a valid main-data checksum
-- (i.e. a cartridge save padded with an emulator RTC footer): without force
-- this returns false, nil, { needsConfirm = true, size = #bytes } so the
-- launcher can ask the player before truncating; with force the extra bytes
-- are dropped and the 32768-byte save imports.
function SaveFileIO.importToSlot(source, version, force)
  version = version or GameVersion.get()
  local bytes, readErr = readSource(source)
  if not bytes then return false, readErr end
  -- The GAME decides before the BYTES do.  Everything below this line used to
  -- judge a save by Gen 1's rules whatever game it was for, and a Gen 2 cart
  -- is MBC3+TIMER: a real Gold/Silver/Crystal .sav carries an RTC footer, so
  -- it is 32786 bytes, misses the size test, and was then measured against
  -- pokered's checksum -- which is why a perfectly good Crystal save reported
  -- as corrupt (#1832).  mainChecksumValid now takes the game and asks that
  -- generation's rule.
  local supported, unsupportedWhy = SaveConvert.importSupported(version)
  if not supported then return false, unsupportedWhy end
  if #bytes ~= SAVE_SIZE then
    local check = SaveConvert.mainChecksumValid(bytes, version)
    if check == nil then
      return false, ("A save file must be %d bytes (32 KB); this one is %d.")
        :format(SAVE_SIZE, #bytes)
    end
    if check == false then
      return false, "save data checksum invalid (main data checksum mismatch)"
    end
    -- The confirm exists because a Gen 1 save bigger than 32768 is a surprise
    -- worth asking about.  On a Gen 2 cart it is the normal shape -- every
    -- real one has the footer -- so asking would be a prompt with one sensible
    -- answer, on every import, forever.
    if #bytes > SAVE_SIZE and not force
       and not SaveConvert.isGen2Cart(version) then
      return false, nil, { needsConfirm = true, size = #bytes }
    end
    bytes = #bytes > SAVE_SIZE and bytes:sub(1, SAVE_SIZE)
      or (bytes .. string.rep("\0", SAVE_SIZE - #bytes))
  end
  -- 3rd arg: the crosswalk has to come from THIS game's ROM cache.  The
  -- launcher imports before the cache is mounted on the un-prefixed paths, so
  -- SaveConvert cannot find the generated tables by itself here (#420).
  local save, convertErr = SaveConvert.importSav(bytes, version, version)
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
  if SaveConvert.isGen2Cart(version) then writeCart(version, slotId, bytes) end
  return true, slotId
end

-- exportActiveSlot(version) -> ok, pathOrErr
-- Loads the version's active slot save (SaveData.load semantics), encodes it
-- back to a 32768-byte SRAM image, and writes it to
-- exports/<version>/gen1recomp-<version>-<slotId>.sav under the portable game
-- folder when portable mode is on, otherwise the save directory (created if
-- absent).  Returns true + the absolute path on success, false + a friendly
-- message otherwise.
function SaveFileIO.exportActiveSlot(version)
  version = version or GameVersion.get()
  local save = SaveData.load(version)
  if not save then return false, "this game has no save to export yet" end
  local activeSlot = SaveData.activeSlot(version)
  local slotId = activeSlot or "save"
  if activeSlot and type(save.meta) == "table" then
    local minted, id = pcall(SaveData.slotPlaythroughId, version, activeSlot, save)
    if minted and type(id) == "string" then save.meta.playthroughId = id end
  end
  local bytes, exportErr = SaveConvert.exportSav(save, version,
                                                 readCart(version, slotId))
  if not bytes then return false, exportErr end
  -- Portable mode is the same seam SaveData's own persistFs uses: when
  -- portable.txt marks the install every persistent write leaves the OS save
  -- directory for the game folder, and an export is no exception.  Writing
  -- through love.filesystem here dropped the .sav in AppData while the slots
  -- it came from lived on the stick, and the desktop "Open folder" affordance
  -- (RomImporter:exportSave) followed the returned path straight there (#752).
  local portableFs = SaveData.portableFs()
  local fs = portableFs or (love and love.filesystem)
  if not (fs and fs.write) then return false, "no filesystem available to export to" end
  if fs.createDirectory then
    fs.createDirectory("exports")
    fs.createDirectory("exports/" .. version)
  end
  -- Per-game folder so MTP browsing matches inbox layout (red/blue/yellow/gold).
  local rel = ("exports/%s/gen1recomp-%s-%s.sav"):format(version, version, slotId)
  local ok, writeErr = fs.write(rel, bytes)
  if not ok then return false, "could not write the export: " .. tostring(writeErr) end
  -- Absolute path for the notice line, resolved against whichever root took
  -- the write.  Portable paths use the OS separator (slotDiskPath does the
  -- same); LOVE save-directory paths stay "/"-joined as before.
  local portableBase = SaveData.portableBaseDir()
  if portableBase then
    local sep = package.config:sub(1, 1)
    return true, portableBase .. sep .. rel:gsub("/", sep)
  end
  local base = fs.getSaveDirectory and fs.getSaveDirectory() or ""
  if base ~= "" then return true, base .. "/" .. rel end
  return true, rel
end

-- Copy the original serialized source rather than decoding and re-encoding it.
-- readSlotSource also recovers a valid backup when the primary file is damaged.
function SaveFileIO.exportLuaSlot(version, slotId, cartId)
  if not GameVersion.info(version) then return false, "unknown game" end
  slotId = slotId or SaveData.activeSlot(version)
  local bytes
  if cartId then bytes = SaveData.readCartSlotSource(cartId, slotId)
  else bytes = SaveData.readSlotSource(version, slotId) end
  if not bytes then return false, "this slot has no save to export yet" end
  local fs = SaveData.portableFs() or (love and love.filesystem)
  if not (fs and fs.write) then return false, "no filesystem available to export to" end
  if fs.createDirectory then
    fs.createDirectory("exports")
    fs.createDirectory("exports/" .. version)
  end
  local name = (cartId and (cartId .. "-") or "") .. tostring(slotId)
  name = name:gsub("[^%w_-]", "_")
  local rel = ("exports/%s/gen1recomp-%s-%s.lua"):format(version, version, name)
  local ok, err = fs.write(rel, bytes)
  if not ok then return false, "could not write the export: " .. tostring(err) end
  local base = SaveData.portableBaseDir()
  if base then
    local sep = package.config:sub(1, 1)
    return true, base .. sep .. rel:gsub("/", sep)
  end
  base = fs.getSaveDirectory and fs.getSaveDirectory() or ""
  return true, base ~= "" and base .. "/" .. rel or rel
end

return SaveFileIO
