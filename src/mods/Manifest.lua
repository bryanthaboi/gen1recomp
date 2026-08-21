-- Manifest v2: a strict superset of v1, so every shipped v1 manifest stays
-- valid.  Pure (no filesystem): the loader's validate phase owns the checks
-- that need to stat a file, this owns shape, vocabulary and range grammar.
local Logger = require("src.core.Logger")
local ModTargets = require("src.mods.ModTargets")
local SafePath = require("src.mods.SafePath")
local Semver = require("src.mods.Semver")
local Version = require("src.core.Version")

local Manifest = {}

Manifest.PROFILES = { content = true, overhaul = true, total_conversion = true }
Manifest.PERMISSIONS = { network = true, filesystem = true,
                         engine_internals = true, steps = true,
                         background = true, compute = true }

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

-- "id", "id@<range>", "id@<range>#<github>", "id#<github>", or table entry
local function parseSpecs(list, field, sources)
  local specs = {}
  sources = type(sources) == "table" and sources or {}
  for _, entry in ipairs(list) do
    local id, range, ghHint, gamesRaw, gameVersion
    if type(entry) == "table" then
      id = entry.id
      range = entry.range or entry.version
      ghHint = entry.github or entry.repo
      gamesRaw = entry.games or entry.game
      gameVersion = entry.game_version
    elseif type(entry) == "string" and entry ~= "" then
      local main, hashRepo = entry:match("^([^#]+)#(.*)$")
      if main then
        entry = main
        ghHint = hashRepo
      end
      id, range = entry:match("^([%w_%-]+)@(.+)$")
      if not id then
        id = entry:match("^([%w_%-]+)$")
        assert(id, ("malformed %s entry %q"):format(field, entry))
        range = nil
      end
    else
      error(field .. " entries must be non-empty strings or tables")
    end
    assert(id, ("malformed %s entry"):format(field))
    local ok, err = Semver.validRange(range)
    assert(ok, ("malformed %s range in %q: %s"):format(field, tostring(entry), tostring(err)))

    if gameVersion then
      local okV, errV = Semver.validRange(gameVersion)
      assert(okV, ("malformed %s game_version range in %q: %s"):format(field, tostring(entry), tostring(errV)))
    end

    local parsedGames = nil
    if gamesRaw ~= nil then
      if type(gamesRaw) == "string" then gamesRaw = { gamesRaw } end
      assert(type(gamesRaw) == "table", "dependency games must be a string or table")
      local normalized, unknown = ModTargets.normalize(gamesRaw)
      assert(#unknown == 0, ("unknown game in %s: %s"):format(field, table.concat(unknown, ", ")))
      parsedGames = normalized
    end

    local parsedGh = nil
    local rawGh = ghHint or sources[id]
    if rawGh then
      local okGh, cleanGh = pcall(Manifest.parseGithub, rawGh)
      if okGh and cleanGh then parsedGh = cleanGh end
    end

    specs[#specs + 1] = {
      id = id,
      range = range,
      github = parsedGh,
      games = parsedGames,
      game_version = gameVersion,
    }
  end
  return specs
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

local scrubUtf8 -- shared by required-import labels and top-level strings

-- User-supplied files a mod needs beside its own source.  The launcher owns
-- the picker and the copy; the mod only reads the resulting
-- <mod>/baseroms/<file> through its existing scoped mod:read surface.  MD5 is
-- deliberately the manifest vocabulary here: ROM preservation databases and
-- the mods consuming these files commonly identify dumps by MD5, and the
-- digest is an identity check rather than a security boundary.
local function parseImports(value, field, required)
  field = field or "required_imports"
  local out, ids, files = {}, {}, {}
  for _, entry in ipairs(array(value)) do
    assert(type(entry) == "table", field .. " entries must be objects")
    local id = entry.id
    assert(type(id) == "string" and id:match("^[%w_%-]+$"),
      field .. " id must contain only letters, numbers, _ or -")
    assert(not ids[id], "duplicate " .. field .. " id: " .. id)
    ids[id] = true

    local file = entry.file
    assert(type(file) == "string" and file ~= "",
      field .. " file is required")
    file = SafePath.require(file, field .. " file")
    assert(not file:find("/", 1, true),
      field .. " file must be a filename inside baseroms")
    assert(file:sub(1, 1) ~= ".",
      field .. " file must not use a hidden metadata filename")
    assert(not files[file], "duplicate " .. field .. " file: " .. file)
    files[file] = true

    local hashes = entry.md5
    if type(hashes) == "string" then hashes = { hashes } end
    assert(type(hashes) == "table" and #hashes > 0,
      field .. " md5 must be a hash or non-empty array")
    local accepted, seen = {}, {}
    for _, digest in ipairs(hashes) do
      assert(type(digest) == "string" and digest:match("^[%x]+$")
          and #digest == 32, field .. " md5 values must be 32 hex characters")
      digest = digest:lower()
      if not seen[digest] then
        seen[digest] = true
        accepted[#accepted + 1] = digest
      end
    end

    local format = entry.format or "raw"
    assert(format == "raw" or format == "n64",
      field .. " format must be raw or n64")
    local name = entry.name or id
    assert(type(name) == "string" and name ~= "",
      field .. " name must be a non-empty string")
    local description = entry.description or entry.hint
    if description ~= nil then
      assert(type(description) == "string" and description ~= "",
        field .. " description must be a non-empty string")
    end
    local size = entry.size
    local maxSize = entry.max_size
    local function validateSize(value, label)
      if value == nil then return end
      assert(type(value) == "number" and value > 0 and value % 1 == 0,
        field .. " " .. label .. " must be a positive integer")
      assert(value <= 2 * 1024 * 1024 * 1024,
        field .. " " .. label .. " exceeds the 2 GiB hard limit")
    end
    validateSize(size, "size")
    validateSize(maxSize, "max_size")
    assert(not (size and maxSize) or size <= maxSize,
      field .. " size must not exceed max_size")
    out[#out + 1] = {
      id = id,
      name = scrubUtf8(name),
      description = scrubUtf8(description),
      file = file,
      md5 = accepted,
      format = format,
      size = size,
      max_size = maxSize,
      required = required ~= false,
    }
  end
  return out
end

-- Drop bytes that are not valid UTF-8 (malformed sequences, overlongs,
-- surrogates, > U+10FFFF) and a leading BOM.  LÖVE's text renderer raises
-- "Invalid UTF-8" from love.graphics.print/printf, so any manifest string a
-- panel may draw must be scrubbed here -- the one place every mod manifest
-- passes through -- or a single mangled description crashes the whole MODS
-- panel instead of misrendering one card.
scrubUtf8 = function(s)
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
  -- every manifest path is joined to the mod's own directory, so none of them
  -- may climb out of it (src/mods/SafePath.lua)
  local entry = SafePath.require(raw.entry, "manifest entry")

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

  -- log_url: the mod's one-way crash-log reporting destination.  https-only,
  -- declared in the manifest so the engine reviews the target at load instead
  -- of trusting per-call URLs from gameplay code, and gated on the `network`
  -- permission the mod must also declare.  api 1 mods never carry it: it is a
  -- load violation, not a warning, because a postLog-capable mod that does not
  -- opt in to networking is a bug in the manifest itself.
  local logUrl = nil
  if raw.log_url ~= nil then
    if strict and not permissionSet.network then
      violation(strict, raw.id, "log_url requires the network permission")
    elseif strict and (type(raw.log_url) ~= "string"
        or not raw.log_url:match("^https://")) then
      violation(strict, raw.id, "log_url must be an https:// URL")
    elseif strict then
      logUrl = raw.log_url
    end
  end

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

  -- Gen 2 is opt-in and never inferred.  The hook/event names and the
  -- registry names are shared across generations on purpose, so a Gen 1 mod
  -- LOOKS like it would work under Gold; what it actually gets is a subset
  -- (Gold has its own battle, world, script VM and save), and half-running is
  -- worse than not running.  A mod author claims Gen 2 only after testing
  -- there, and until then the loader leaves the mod out of a Gold boot
  -- entirely (Loader:_gateGeneration) rather than letting it half-apply.
  -- Absent means false: every mod written before this field existed is Gen 1
  -- only, which is exactly what it was tested as.
  assert(raw.gen2compat == nil or type(raw.gen2compat) == "boolean",
    "gen2compat must be a boolean")

  -- `games` is the same statement made per game: version ids ("red"),
  -- generations ("gen1"), or "all" (src/mods/ModTargets.lua).  gen2compat is
  -- kept as its Gen 2 spelling and only ever ADDS Gen 2, so no shipped
  -- manifest loses a game it already ran on, and gen2compat below is derived
  -- from the resolved list -- the loader's gate reads that one field.
  assert(raw.games == nil or type(raw.games) == "table",
    "games must be an array")
  local games, unknownGames = ModTargets.normalize(raw.games)
  for _, token in ipairs(unknownGames) do
    violation(strict, raw.id, ("unknown game %q"):format(token))
  end
  if raw.games ~= nil and #games == 0 then
    violation(strict, raw.id, "games names no game this engine knows")
  end
  if #games == 0 then
    games = ModTargets.legacy(raw.gen2compat == true)
  elseif raw.gen2compat == true then
    games = ModTargets.union(games, ModTargets.generationVersions(2))
  end
  local gen2compat = ModTargets.covers(games, 2)

  -- overhauls and total conversions are assumed to move the link
  -- fingerprint unless the manifest says otherwise; content packs and
  -- declared translations are not
  local affectsLink = profile ~= "content" and not language
  if type(raw.affects_link) == "boolean" then affectsLink = raw.affects_link end

  local function optionalString(value, field)
    if value == nil then return nil end
    assert(type(value) == "string" and value ~= "", field .. " must be a file path")
    return value
  end

  local function optionalFile(value, field)
    local text = optionalString(value, field)
    return text and SafePath.require(text, field)
  end

  local conflicts = mergeConflictLists(raw.conflicts, raw.incompatible)

  local requiredImports = parseImports(raw.required_imports,
    "required_imports", true)
  local optionalImports = parseImports(raw.optional_imports,
    "optional_imports", false)
  local importIds, importFiles = {}, {}
  for _, list in ipairs({ requiredImports, optionalImports }) do
    for _, import in ipairs(list) do
      assert(not importIds[import.id], "duplicate import id: " .. import.id)
      assert(not importFiles[import.file], "duplicate import file: " .. import.file)
      importIds[import.id], importFiles[import.file] = true, true
    end
  end

  return {
    id = raw.id,
    name = raw.name,
    version = raw.version,
    entry = entry,
    api = api,
    priority = tonumber(raw.priority) or 0,
    dependencies = array(raw.dependencies),
    optional_dependencies = array(raw.optional_dependencies),
    conflicts = conflicts,
    incompatible = array(raw.incompatible),
    dependencySpecs = parseSpecs(array(raw.dependencies), "dependencies", raw.dependency_sources),
    optionalSpecs = parseSpecs(array(raw.optional_dependencies), "optional_dependencies", raw.dependency_sources),
    conflictSpecs = parseSpecs(conflicts, "conflicts"),
    category = raw.category or "OTHER",
    game_version = raw.game_version,
    description = raw.description or "",
    github = github,
    experimental = experimental,
    profile = profile,
    language = language,
    games = games,
    gen2compat = gen2compat,
    affects_link = affectsLink,
    permissions = permissions,
    permissionSet = permissionSet,
    log_url = logUrl,
    options_schema = optionalFile(raw.options_schema, "options_schema"),
    assets_transforms = optionalFile(raw.assets_transforms, "assets_transforms"),
    required_imports = requiredImports,
    optional_imports = optionalImports,
    -- an env var name, not a path, so it keeps the plain string check
    force_enable_env = optionalString(raw.force_enable_env, "force_enable_env"),
    path = path,
    raw = raw,
  }
end

return Manifest
