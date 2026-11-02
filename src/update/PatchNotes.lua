-- Resolve the game's patch notes for the launcher footer modal.
--
-- Sources, first hit wins:
--   1. The GitHub body the self-updater already fetched (Check.parseRelease)
--   2. PATCH_NOTES.md, if a build packed one
--   3. mobile/ios/app-repo.json -- CI copies each release's notes into
--      versions[].localizedDescription, so a checkout already has them
--      on disk even when the updater has not run

local Json = require("src.link.Json")
local Semver = require("src.update.Semver")

local PatchNotes = {}

PatchNotes.FILES = {
  "PATCH_NOTES.md",
  "assets/PATCH_NOTES.md",
}

PatchNotes.CACHE_FILES = {
  "updates/notes_cache.json",
}

PatchNotes.REPO_FILES = {
  "mobile/ios/app-repo.json",
}

PatchNotes.FETCH_FAILED = "Unable to fetch patch notes."

PatchNotes.NO_TRANSPORT = "This build has no patch notes packed in, and this platform "
  .. "cannot check GitHub for them.\n\n"
  .. "Release notes: github.com/bryanthaboi/gen1recomp/releases"

function PatchNotes.canCheckOnline()
  local Platform = require("src.core.Platform")
  if not Platform.networkValidated() then return false end
  return require("src.core.HostShell").canFetch() and true or false
end

local function nonempty(s)
  return type(s) == "string" and s:find("%S")
end

function PatchNotes.fromCheck(Check)
  if not (Check and Check.state) then return nil, nil end
  local ok, st = pcall(Check.state)
  st = (ok and type(st) == "table") and st or nil
  if not st then return nil, nil end
  if nonempty(st.notes) then
    return st.notes, st.latest
  end
  return nil, st.latest
end

local function readPath(path)
  local fs = love and love.filesystem
  if fs and fs.read then
    local ok, text = pcall(fs.read, path)
    if ok and nonempty(text) then return text end
  end
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return nonempty(text) and text or nil
end

local function readCachePath(path)
  local fs = require("src.core.SaveData").persistenceFs()
  if not (fs and fs.read) then return nil end
  local ok, text = pcall(fs.read, path)
  return ok and nonempty(text) and text or nil
end

function PatchNotes.fromCache(engine, exactOnly)
  for _, path in ipairs(PatchNotes.CACHE_FILES) do
    local text = readCachePath(path)
    if text then
      local ok, doc = pcall(Json.decode, text)
      if ok and type(doc) == "table" then
        if engine and not engine:match("^0%.0%.0%-dev") then
          if doc[engine] and nonempty(doc[engine]) then
            return doc[engine], engine
          end
          if exactOnly then return nil, nil end
          local bestVer, bestNotes
          for ver, notes in pairs(doc) do
            if nonempty(notes) and (not bestVer or Semver.compare(ver, bestVer) > 0) then
              bestVer, bestNotes = ver, notes
            end
          end
          if bestNotes then return bestNotes, bestVer end
        else
          for ver, notes in pairs(doc) do
            if nonempty(notes) then
              return notes, ver
            end
          end
        end
      end
    end
  end
  return nil, nil
end

function PatchNotes.fromFile()
  for _, path in ipairs(PatchNotes.FILES) do
    local text = readPath(path)
    if text then return text end
  end
  return nil
end

-- Newest-first list of { version, notes } from the iOS sidecar.
function PatchNotes.parseRepo(jsonText)
  local doc = Json.decode(jsonText)
  if type(doc) ~= "table" or type(doc.apps) ~= "table" then return {} end
  local out = {}
  for _, app in ipairs(doc.apps) do
    if type(app) == "table" and type(app.versions) == "table" then
      for _, row in ipairs(app.versions) do
        if type(row) == "table" and nonempty(row.localizedDescription) then
          out[#out + 1] = {
            version = row.version,
            notes = row.localizedDescription,
          }
        end
      end
    end
  end
  return out
end

function PatchNotes.fromRepo(engine)
  for _, path in ipairs(PatchNotes.REPO_FILES) do
    local text = readPath(path)
    if text then
      local list = PatchNotes.parseRepo(text)
      if #list == 0 then return nil, nil end
      if engine and not engine:match("^0%.0%.0%-dev") then
        for _, row in ipairs(list) do
          if row.version == engine then
            return row.notes, row.version
          end
        end
        return nil, nil
      end
      return list[1].notes, list[1].version
    end
  end
  return nil, nil
end

function PatchNotes.body(Check)
  local Version = require("src.core.Version")
  local engine = (Version and Version.engine) or "?"

  local notes, ver = PatchNotes.fromCheck(Check)
  if notes then
    return notes, ver or engine
  end

  notes, ver = PatchNotes.fromCache(engine, true)
  if notes then return notes, ver end

  notes = PatchNotes.fromFile()
  if notes then return notes, engine end

  notes, ver = PatchNotes.fromCache(engine)
  if notes then return notes, ver end

  notes, ver = PatchNotes.fromRepo(engine)
  if notes then return notes, ver end

  if not PatchNotes.canCheckOnline() then
    return PatchNotes.NO_TRANSPORT, engine
  end
  return PatchNotes.FETCH_FAILED, engine
end

return PatchNotes
