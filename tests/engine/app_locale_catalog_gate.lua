-- Ratchet for built-in application localization catalogs.
--
-- AppLocale uses English source strings as keys.  That keeps call sites
-- readable and preserves the same source-as-key model already used by
-- Strings(), but it means an English wording change intentionally orphans the
-- old translation.  This gate makes that visible in CI: every AppLocale
-- literal used by src/ must exist in the Spanish reference catalog, every
-- Spanish entry must still have a live source, and format directives must
-- remain compatible.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local AppLocale = require("src.core.AppLocale")
local Spanish = require("src.locales.es_es")

-- Native application sources are deliberately explicit call-site literals.
-- If a future feature needs composed/dynamic source keys, add a source marker
-- API first rather than teaching this gate to guess runtime strings.
local function harvest(body)
  local found = {}
  for source in body:gmatch('AppLocale%s*%(%s*"([^"]+)"') do
    found[source] = true
  end
  for source in body:gmatch("AppLocale%s*%(%s*'([^']+)'") do
    found[source] = true
  end
  for source in body:gmatch('AppLocale%.text%s*%(%s*"([^"]+)"') do
    found[source] = true
  end
  for source in body:gmatch("AppLocale%.text%s*%(%s*'([^']+)'") do
    found[source] = true
  end
  for source in body:gmatch('AppLocale%.source%s*%(%s*"([^"]+)"') do
    found[source] = true
  end
  for source in body:gmatch("AppLocale%.source%s*%(%s*'([^']+)'") do
    found[source] = true
  end
  for source in body:gmatch('AppMessage%s*%(%s*"([^"]+)"') do
    found[source] = true
  end
  for source in body:gmatch("AppMessage%s*%(%s*'([^']+)'") do
    found[source] = true
  end
  return found
end

-- High-confidence guard for application text passed straight to the drawing
-- kit.  Dynamic values are allowed, but a literal in the visible-text slot
-- must be wrapped in AppLocale even when its spelling is shared by both
-- languages.  Keeping this deliberately narrow avoids treating font names,
-- widget ids and mod-provided metadata as application copy.
local function bareUiSources(body)
  local found = {}
  for source in body:gmatch(
      'Kit%.text[%w]*%s*%(%s*"[^"]+"%s*,%s*"([^"]+)"') do
    found[source] = true
  end
  for source in body:gmatch(
      "Kit%.text[%w]*%s*%(%s*'[^']+'%s*,%s*'([^']+)'") do
    found[source] = true
  end
  for source in body:gmatch(
      'Kit%.caption%s*%([^,]+,[^,]+,%s*"([^"]+)"') do
    found[source] = true
  end
  for source in body:gmatch(
      "Kit%.caption%s*%([^,]+,[^,]+,%s*'([^']+)'") do
    found[source] = true
  end
  return found
end

local used = {}
local bare = {}
local scanned = 0
for _, path in ipairs(FsIo.luaFilesUnder("src")) do
  -- Do not harvest examples/comments in the implementation or catalogs; only
  -- application call sites define the live source inventory.
  if path ~= "src/core/AppLocale.lua" and path ~= "src/core/AppMessage.lua"
      and not path:match("^src/locales/") then
    local f = io.open(path, "rb")
    if f then
      local body = f:read("*a")
      f:close()
      scanned = scanned + 1
      for source in pairs(harvest(body)) do used[source] = true end
      if path:match("^src/import/") then
        for source in pairs(bareUiSources(body)) do
          bare[#bare + 1] = path .. ": " .. source
        end
      end
    end
  end
end

T.check(scanned > 20, "the app-locale gate scanned the source tree")
T.check(next(used) ~= nil, "at least one native application source is harvested")

local missing, stale, badFormat = {}, {}, {}
for source in pairs(used) do
  local translated = Spanish.strings[source]
  if type(translated) ~= "string" or translated == "" then
    missing[#missing + 1] = source
  elseif not AppLocale.formatCompatible(source, translated) then
    badFormat[#badFormat + 1] = source
  end
end
for source, translated in pairs(Spanish.strings) do
  if type(source) ~= "string" or type(translated) ~= "string" then
    stale[#stale + 1] = tostring(source) .. " (malformed entry)"
  elseif not used[source] then
    stale[#stale + 1] = source
  end
end

table.sort(missing)
table.sort(stale)
table.sort(badFormat)
table.sort(bare)

T.check(#bare == 0,
  ("%d bare application UI literal(s): %s")
    :format(#bare, table.concat(bare, ", ")))

T.check(#missing == 0,
  ("%d application source(s) missing from es-ES: %s")
    :format(#missing, table.concat(missing, ", ")))
T.check(#stale == 0,
  ("%d stale es-ES source key(s): %s")
    :format(#stale, table.concat(stale, ", ")))
T.check(#badFormat == 0,
  ("%d es-ES translation(s) have incompatible format directives: %s")
    :format(#badFormat, table.concat(badFormat, ", ")))

T.finish("app_locale_catalog_gate")
