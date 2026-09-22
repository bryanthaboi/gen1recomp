local Profile = require("src.core.game3.profile")

local Font = {}

Font.DEFAULT_MODULE = "src.ui.game3.frlg_font"

local impls = {}
local overrides = {}
local logged = false

local function modulePath(versionId)
  local row = Profile.of(versionId)
  local font = type(row) == "table" and row.font or nil
  return (font and font.module) or Font.DEFAULT_MODULE
end

local function log(msg)
  if logged then return end
  logged = true
  print("[game3/font] " .. tostring(msg))
end

function Font.register(versionId, impl)
  if type(versionId) ~= "string" or versionId == "" then return false end
  if type(impl) ~= "table" then return false end
  overrides[versionId] = impl
  impls[versionId] = impl
  return true
end

function Font.unregister(versionId)
  if type(versionId) ~= "string" then return false end
  overrides[versionId] = nil
  impls[versionId] = nil
  return true
end

function Font.impl(versionId)
  local key = versionId
  if type(key) ~= "string" or key == "" then key = Profile.active().id end
  local impl = overrides[key] or impls[key]
  if impl then return impl end
  local ok, mod = pcall(require, modulePath(key))
  if ok and type(mod) == "table" then
    impls[key] = mod
    return mod
  end
  if key ~= Profile.FALLBACK_ID then
    local okDefault, fallback = pcall(require, modulePath(Profile.FALLBACK_ID))
    if okDefault and type(fallback) == "table" then
      impls[key] = fallback
      return fallback
    end
  end
  log("no glyph implementation for '" .. tostring(key) .. "'")
  return nil
end

function Font.active()
  return Font.impl(nil)
end

function Font.reset()
  impls = {}
  logged = false
end

setmetatable(Font, {
  __index = function(_, key)
    local impl = Font.impl(nil)
    if not impl then return nil end
    return rawget(impl, key)
  end,
})

return Font
