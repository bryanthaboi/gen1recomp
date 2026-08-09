-- Built-in localization for Gen1Recomp's own application UI.
--
-- This module is intentionally separate from src/core/Strings.lua.
-- Strings/Data.strings is also used by gameplay and translation mods; loading
-- Interface Language into that global catalog would translate gameplay and
-- couple the app locale to the Pokemon language. Application-owned surfaces
-- opt into this module instead.

local Logger = require("src.core.Logger")
local Spanish = require("src.locales.es_es")

local AppLocale = {}

local SOURCE_LOCALE = "en"
local locales = {
  [SOURCE_LOCALE] = { id = SOURCE_LOCALE, name = "English", strings = {} },
  [Spanish.id] = Spanish,
}
local order = { SOURCE_LOCALE, Spanish.id }
local current = SOURCE_LOCALE
local generation = 0
local warned = {}

local function specifiers(s)
  local out = {}
  s = tostring(s)
  local i = 1
  while i <= #s do
    local percent = s:find("%", i, true)
    if not percent then break end
    if s:sub(percent + 1, percent + 1) == "%" then
      i = percent + 2
    else
      local j = percent + 1
      while s:sub(j, j):match("[-+ #0]") do j = j + 1 end
      while s:sub(j, j):match("%d") do j = j + 1 end
      if s:sub(j, j) == "." then
        j = j + 1
        while s:sub(j, j):match("%d") do j = j + 1 end
      end
      while s:sub(j, j):match("[hlL]") do j = j + 1 end
      local conversion = s:sub(j, j)
      out[#out + 1] = conversion:match("[cdiouxXeEfgGqs]")
        and conversion or "!" .. conversion
      i = math.max(j + 1, percent + 1)
    end
  end
  return out
end

function AppLocale.formatCompatible(a, b)
  local aa, bb = specifiers(a), specifiers(b)
  if #aa ~= #bb then return false end
  for i = 1, #aa do
    if aa[i] ~= bb[i] then return false end
  end
  return true
end

local function resolve(id)
  if type(id) == "string" then
    if locales[id] then return id end
  end
  return SOURCE_LOCALE
end

function AppLocale.normalize(id)
  return resolve(id)
end

function AppLocale.set(id)
  local nextId = resolve(id)
  if nextId ~= current then
    current = nextId
    generation = generation + 1
  end
  return current
end

-- Apply the locale from a loaded global options table.  This is the bootstrap
-- seam used before the first application frame and also the normalization
-- point for legacy/unknown persisted values.  Mutating the table is deliberate:
-- the next normal options save writes the canonical BCP 47 id back to disk.
function AppLocale.applyOptions(opts)
  local id = AppLocale.set(type(opts) == "table" and opts.interfaceLocale or nil)
  if type(opts) == "table" then opts.interfaceLocale = id end
  return id
end

function AppLocale.get()
  return current
end

function AppLocale.generation()
  return generation
end

function AppLocale.available()
  local out = {}
  for _, id in ipairs(order) do
    out[#out + 1] = { id = id, name = locales[id].name }
  end
  return out
end

function AppLocale.displayName(id)
  return locales[AppLocale.normalize(id)].name
end

function AppLocale.cycle(id, dir)
  local resolved = AppLocale.normalize(id)
  local index = 1
  for i, localeId in ipairs(order) do
    if localeId == resolved then index = i break end
  end
  local n = #order
  local nextIndex = ((index - 1 + (dir or 1)) % n) + 1
  return order[nextIndex]
end

function AppLocale.lookup(source)
  if current == SOURCE_LOCALE then return source end
  local catalog = locales[current] and locales[current].strings
  local translated = catalog and catalog[source]
  if type(translated) ~= "string" or translated == "" then return source end
  if not AppLocale.formatCompatible(source, translated) then
    local key = current .. "\0" .. source
    if not warned[key] then
      warned[key] = true
      Logger.warn("app locale: translation of %q in %s has incompatible format directives -- using the source",
        source, current)
    end
    return source
  end
  return translated
end

-- Marks a source string that is supplied indirectly at runtime.  Returning
-- the string unchanged keeps call sites simple while letting the catalog gate
-- harvest the complete application-owned source inventory.
function AppLocale.source(source)
  return source
end

function AppLocale.message(message)
  local AppMessage = require("src.core.AppMessage")
  if not AppMessage.is(message) then return tostring(message) end
  return AppLocale.text(message.source,
    unpack(message.args, 1, message.args.n))
end

function AppLocale.text(source, ...)
  local text = AppLocale.lookup(source)
  if select("#", ...) == 0 then return text end
  local ok, result = pcall(string.format, text, ...)
  if ok then return result end
  local sourceOk, sourceResult = pcall(string.format, source, ...)
  if sourceOk then return sourceResult end
  return source
end

setmetatable(AppLocale, { __call = function(_, ...) return AppLocale.text(...) end })

return AppLocale
