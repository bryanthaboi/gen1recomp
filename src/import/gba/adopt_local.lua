-- Install a FireRed/LeafGreen dump into baseroms/ without the file picker.
-- Test envs (and NX-style drops) often cannot open a picker; placing the ROM
-- at baseroms/firered.gba is enough — validateStored writes the receipt.

local Adopt = {}

local CANDIDATE_NAMES = {
  "firered.gba",
  "leafgreen.gba",
  "Pokemon - FireRed Version (USA).gba",
  "Pokemon - LeafGreen Version (USA).gba",
}

local function fs()
  return love and love.filesystem or nil
end

local function listDir(path)
  local fsys = fs()
  if fsys and fsys.getDirectoryItems then
    return fsys.getDirectoryItems(path) or {}
  end
  return {}
end

local function fileInfo(path)
  local fsys = fs()
  if fsys and fsys.getInfo then
    return fsys.getInfo(path, "file")
  end
  return nil
end

local function ensureDir(path)
  local fsys = fs()
  if fsys and fsys.createDirectory then
    fsys.createDirectory(path)
  end
end

local function copyFile(src, dest)
  local fsys = fs()
  if not (fsys and fsys.read and fsys.write) then
    return nil, "love.filesystem read/write unavailable"
  end
  local data = fsys.read(src)
  if type(data) ~= "string" or #data == 0 then
    return nil, "could not read " .. tostring(src)
  end
  local parent = dest:match("^(.*)/[^/]+$")
  if parent then ensureDir(parent) end
  local ok, err = fsys.write(dest, data)
  if ok == false then return nil, err or "write failed" end
  return true, #data
end

local function matchImportId(filename, size)
  if size ~= 16777216 then return nil end
  local lower = filename:lower()
  if lower:find("leaf", 1, true) or lower:find("leafgreen", 1, true) then
    return "leafgreen", "leafgreen.gba"
  end
  -- Default FireRed for other 16 MiB GBA dumps (MD5 still gates acceptance).
  return "firered", "firered.gba"
end

--- Try to make firered/leafgreen visible to mod.imports without a picker.
-- @return ok, detail
function Adopt.try(mod)
  if not (mod and mod.manifest and mod.imports) then
    return false, "mod.imports unavailable"
  end

  -- Already installed?
  for _, id in ipairs({ "firered", "leafgreen" }) do
    local info = mod.imports:info(id)
    if info then
      return true, { already = true, id = id, md5 = info.md5 }
    end
  end

  local RequiredImports = require("src.mods.RequiredImports")
  local manifest = mod.manifest
  local modPath = manifest.path or mod.path or ""
  local baseroms = modPath .. "/baseroms"
  ensureDir(baseroms)

  local tried = {}

  local function adoptPath(srcRel, importId, destName)
    tried[#tried + 1] = srcRel
    local dest = baseroms .. "/" .. destName
    -- Already sitting in the right place?
    if srcRel == dest or srcRel:sub(-#destName) == destName and srcRel:find("/baseroms/", 1, true) then
      local spec = nil
      for _, s in ipairs(RequiredImports.specs(manifest)) do
        if s.id == importId then spec = s break end
      end
      if not spec then return nil, "unknown import " .. importId end
      local ok, detail = RequiredImports.validateStored(manifest, spec, fs())
      if ok then return true, { adopted = srcRel, id = importId, md5 = detail } end
      return nil, detail
    end
    local ok, err = copyFile(srcRel, dest)
    if not ok then return nil, err end
    local spec
    for _, s in ipairs(RequiredImports.specs(manifest)) do
      if s.id == importId then spec = s break end
    end
    if not spec then return nil, "unknown import " .. importId end
    local vok, detail = RequiredImports.validateStored(manifest, spec, fs())
    if not vok then
      return nil, detail
    end
    return true, { adopted = srcRel, id = importId, md5 = detail, dest = dest }
  end

  -- 1) baseroms/firered.gba or leafgreen.gba already present
  for _, id in ipairs({ "firered", "leafgreen" }) do
    local name = id == "firered" and "firered.gba" or "leafgreen.gba"
    local path = baseroms .. "/" .. name
    if fileInfo(path) then
      local ok, detail = adoptPath(path, id, name)
      if ok then return true, detail end
      print("[sevii] baseroms/" .. name .. " present but invalid: " .. tostring(detail))
    end
  end

  -- 2) NX-style inbox: imports/baseroms/*
  local inbox = "imports/baseroms"
  for _, name in ipairs(listDir(inbox)) do
    if name:sub(1, 1) ~= "." and name:lower():match("%.gba$") then
      local path = inbox .. "/" .. name
      local info = fileInfo(path)
      local importId, destName = matchImportId(name, info and info.size)
      if importId then
        local ok, detail = adoptPath(path, importId, destName)
        if ok then return true, detail end
        print("[sevii] inbox " .. path .. " rejected: " .. tostring(detail))
      end
    end
  end

  -- 3) Loose .gba in the mod root (dev / test trees)
  for _, name in ipairs(listDir(modPath)) do
    if name:lower():match("%.gba$") then
      local path = (modPath ~= "" and (modPath .. "/") or "") .. name
      local info = fileInfo(path)
      local importId, destName = matchImportId(name, info and info.size)
      if importId then
        local ok, detail = adoptPath(path, importId, destName)
        if ok then return true, detail end
        print("[sevii] mod-root " .. name .. " rejected: " .. tostring(detail))
      end
    end
  end

  -- 4) Well-known filenames under mod root
  for _, name in ipairs(CANDIDATE_NAMES) do
    local path = (modPath ~= "" and (modPath .. "/") or "") .. name
    if fileInfo(path) then
      local importId, destName = matchImportId(name, 16777216)
      local ok, detail = adoptPath(path, importId, destName)
      if ok then return true, detail end
    end
  end

  return false,
    "no FireRed/LeafGreen dump found. Without a file picker, copy a clean US dump to:\n"
      .. "  " .. baseroms .. "/firered.gba\n"
      .. "or drop it in imports/baseroms/ then reload.\n"
      .. "Dev helper: sevii/gba/install_local_rom.sh /path/to/firered.gba"
end

return Adopt
