-- Identify a baseroms/ candidate by SHA-1; size is only a gate.  Pure Lua so
-- the test tier can drive it without love.

local GameVersion = require("src.core.GameVersion")

local RomDetect = {}

-- Versions whose clean dump has this exact size.
function RomDetect.versionsForSize(size)
  local out = {}
  if type(size) ~= "number" then return out end
  for _, version in ipairs(GameVersion.ORDER) do
    if GameVersion.info(version).romSize == size then
      out[#out + 1] = version
    end
  end
  return out
end

-- The revision label ("1.0", "1.1") a hash belongs to, or nil.
function RomDetect.revisionFor(version, hash)
  for _, revision in ipairs(GameVersion.revisions(version)) do
    if revision.sha1 == hash then return revision.label end
  end
  return nil
end

-- identify({ size, data, sha1 }, { unresolved }) -> { version, revision }
-- or { reject = "size" | "unknown" | "already", ... }.  sha1 may be a hex
-- string or a function(data) -> hex.
function RomDetect.identify(entry, opts)
  opts = opts or {}
  entry = entry or {}
  local data = entry.data
  local size = entry.size or (type(data) == "string" and #data or nil)
  local candidates = RomDetect.versionsForSize(size)
  if #candidates == 0 then
    return { reject = "size", size = size }
  end

  local hash = entry.sha1
  if type(hash) == "function" then hash = hash(data) end
  if type(hash) ~= "string" then
    return { reject = "unknown", versions = candidates }
  end

  local version = GameVersion.forSha1(hash)
  -- A hash from another generation cannot belong to a file of this size.
  if version and GameVersion.info(version).romSize ~= size then version = nil end
  if not version then
    return { reject = "unknown", versions = candidates }
  end
  if opts.unresolved and not opts.unresolved[version] then
    return { reject = "already", version = version }
  end

  return { version = version, revision = RomDetect.revisionFor(version, hash) }
end

return RomDetect
