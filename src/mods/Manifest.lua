-- Manifest v2: a strict superset of v1, so every shipped v1 manifest stays
-- valid.  Pure (no filesystem): the loader's validate phase owns the checks
-- that need to stat a file, this owns shape, vocabulary and range grammar.
local Logger = require("src.core.Logger")
local Semver = require("src.mods.Semver")
local Version = require("src.core.Version")

local Manifest = {}

Manifest.PROFILES = { content = true, overhaul = true, total_conversion = true }
Manifest.PERMISSIONS = { network = true, filesystem = true, engine_internals = true }

-- link-relevant registries; a mod that writes into one of these while
-- declaring affects_link = false gets an attributed warning from the loader
Manifest.LINK_REGISTRIES = {
  pokemon = true, moves = true, type_chart = true,
  statuses = true, move_effects = true,
}

local function array(value)
  if value == nil then return {} end
  assert(type(value) == "table", "manifest arrays must be tables")
  return value
end

-- api 2 treats vocabulary violations as load errors; api 1 keeps loading and
-- gets an attributed warning so v1 mods never break on a field they predate
local function violation(strict, id, message)
  if strict then error(message, 0) end
  Logger.warn("[%s] %s", tostring(id), message)
end

-- "id" or "id@<range>"; a malformed id or range fails for every api level
-- because there is no sane fallback reading for it
local function parseSpecs(list, field)
  local specs = {}
  for _, entry in ipairs(list) do
    assert(type(entry) == "string" and entry ~= "",
      field .. " entries must be non-empty strings")
    local id, range = entry:match("^([%w_%-]+)@(.+)$")
    if not id then
      id = entry:match("^([%w_%-]+)$")
      assert(id, ("malformed %s entry %q"):format(field, entry))
      range = nil
    end
    local ok, err = Semver.validRange(range)
    assert(ok, ("malformed %s range in %q: %s"):format(field, entry, tostring(err)))
    specs[#specs + 1] = { id = id, range = range }
  end
  return specs
end

-- Optional GitHub repo for launcher auto-update / other-versions.
-- Accepts "owner/repo" or a github.com URL; empty/absent means no updates.
function Manifest.parseGithub(value)
  if value == nil or value == "" then return nil end
  assert(type(value) == "string", "github must be a string")
  local trimmed = value:match("^%s*(.-)%s*$") or value
  if trimmed == "" then return nil end
  local owner, repo = trimmed:match(
    "^https?://github%.com/([%w%._%-]+)/([%w%._%-]+)/?$")
  if not owner then
    owner, repo = trimmed:match(
      "^https?://github%.com/([%w%._%-]+)/([%w%._%-]+)%.git/?$")
  end
  if not owner then
    owner, repo = trimmed:match("^([%w%._%-]+)/([%w%._%-]+)$")
  end
  assert(owner and repo and owner ~= "" and repo ~= "",
    "github must be owner/repo or a github.com URL")
  repo = repo:gsub("%.git$", "")
  return owner .. "/" .. repo
end

-- conflicts + incompatible (alias) merged, first-wins on duplicate ids
local function mergeConflictLists(conflicts, incompatible)
  local seen, out = {}, {}
  for _, list in ipairs({ array(conflicts), array(incompatible) }) do
    for _, entry in ipairs(list) do
      if not seen[entry] then
        seen[entry] = true
        out[#out + 1] = entry
      end
    end
  end
  return out
end

-- Drop bytes that are not valid UTF-8 (malformed sequences, overlongs,
-- surrogates, > U+10FFFF) and a leading BOM.  LÖVE's text renderer raises
-- "Invalid UTF-8" from love.graphics.print/printf, so any manifest string a
-- panel may draw must be scrubbed here -- the one place every mod manifest
-- passes through -- or a single mangled description crashes the whole MODS
-- panel instead of misrendering one card.
local function scrubUtf8(s)
  if type(s) ~= "string" then return s end
  s = s:gsub("^\239\187\191", "")
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    local len
    if b < 0x80 then len = 1
    elseif b >= 0xC2 and b <= 0xDF then len = 2
    elseif b >= 0xE0 and b <= 0xEF then len = 3
    elseif b >= 0xF0 and b <= 0xF4 then len = 4
    end
    local ok = len ~= nil and i + len - 1 <= n
    if ok and len > 1 then
      for j = i + 1, i + len - 1 do
        local c = s:byte(j)
        if c < 0x80 or c > 0xBF then ok = false; break end
      end
      if ok then
        -- boundary lead bytes narrow their second byte: no overlongs
        -- (E0/F0), no surrogates (ED), nothing past U+10FFFF (F4)
        local b2 = s:byte(i + 1)
        if (b == 0xE0 and b2 < 0xA0) or (b == 0xED and b2 > 0x9F)
            or (b == 0xF0 and b2 < 0x90) or (b == 0xF4 and b2 > 0x8F) then
          ok = false
        end
      end
    end
    if ok then
      out[#out + 1] = s:sub(i, i + len - 1)
      i = i + len
    else
      i = i + 1
    end
  end
  return table.concat(out)
end

function Manifest.validate(raw, path)
  assert(type(raw) == "table", "manifest must be an object")
  -- scrubbed in place so every later reader agrees, including the launcher's
  -- badge derivation, which reads raw.category rather than the validated copy
  raw.name = scrubUtf8(raw.name)
  raw.version = scrubUtf8(raw.version)
  raw.description = scrubUtf8(raw.description)
  raw.category = scrubUtf8(raw.category)
  assert(type(raw.id) == "string" and raw.id:match("^[%w_%-]+$"),
    "manifest id must contain only letters, numbers, _ or -")
  assert(type(raw.name) == "string" and raw.name ~= "", "manifest name is required")
  assert(type(raw.version) == "string" and raw.version ~= "", "manifest version is required")
  assert(type(raw.entry) == "string" and raw.entry ~= "", "manifest entry is required")

  -- absent means 1: full v1 compat, schema violations downgrade to warnings
  assert(raw.api == nil or tonumber(raw.api) ~= nil, "manifest api must be a number")
  local api = tonumber(raw.api) or 1
  assert(api >= 1 and api % 1 == 0, "manifest api must be a positive integer")
  assert(api <= Version.modApi, ("requires mod API %d; this engine provides %d")
    :format(api, Version.modApi))
  local strict = api >= 2

  local profile = raw.profile or "content"
  if not Manifest.PROFILES[profile] then
    violation(strict, raw.id, ("unknown profile %q"):format(tostring(profile)))
    profile = "content"
  end

  local permissions, permissionSet = {}, {}
  for _, name in ipairs(array(raw.permissions)) do
    if Manifest.PERMISSIONS[name] then
      permissions[#permissions + 1] = name
      permissionSet[name] = true
    else
      violation(strict, raw.id, ("unknown permission %q"):format(tostring(name)))
    end
  end

  local gameVersionOk, gameVersionErr = Semver.validRange(raw.game_version)
  assert(gameVersionOk, ("malformed game_version %q: %s")
    :format(tostring(raw.game_version), tostring(gameVersionErr)))

  local github = Manifest.parseGithub(raw.github)

  assert(raw.experimental == nil or type(raw.experimental) == "boolean",
    "experimental must be a boolean")
  local experimental = raw.experimental == true

  -- #501: a translation declares itself here.  Neither the ROM's dialogue
  -- nor the engine's own strings are hashed into the link surface
  -- (src/link/Fingerprint.lua header), so an English install and a Spanish
  -- one run the same lockstep simulation, exactly as two regional carts on
  -- a real cable did.  The flag is only the author's claim;
  -- Handshake.onlineBlockers checks it against the ops the mod actually
  -- appended before online play trusts it.
  assert(raw.language == nil or type(raw.language) == "boolean",
    "language must be a boolean")
  local language = raw.language == true

  -- overhauls and total conversions are assumed to move the link
  -- fingerprint unless the manifest says otherwise; content packs and
  -- declared translations are not
  local affectsLink = profile ~= "content" and not language
  if type(raw.affects_link) == "boolean" then affectsLink = raw.affects_link end

  local function optionalFile(value, field)
    if value == nil then return nil end
    assert(type(value) == "string" and value ~= "", field .. " must be a file path")
    return value
  end

  local conflicts = mergeConflictLists(raw.conflicts, raw.incompatible)

  return {
    id = raw.id,
    name = raw.name,
    version = raw.version,
    entry = raw.entry,
    api = api,
    priority = tonumber(raw.priority) or 0,
    dependencies = array(raw.dependencies),
    optional_dependencies = array(raw.optional_dependencies),
    conflicts = conflicts,
    incompatible = array(raw.incompatible),
    dependencySpecs = parseSpecs(array(raw.dependencies), "dependencies"),
    optionalSpecs = parseSpecs(array(raw.optional_dependencies), "optional_dependencies"),
    conflictSpecs = parseSpecs(conflicts, "conflicts"),
    category = raw.category or "OTHER",
    game_version = raw.game_version,
    description = raw.description or "",
    github = github,
    experimental = experimental,
    profile = profile,
    language = language,
    affects_link = affectsLink,
    permissions = permissions,
    permissionSet = permissionSet,
    options_schema = optionalFile(raw.options_schema, "options_schema"),
    assets_transforms = optionalFile(raw.assets_transforms, "assets_transforms"),
    force_enable_env = optionalFile(raw.force_enable_env, "force_enable_env"),
    path = path,
    raw = raw,
  }
end

return Manifest
