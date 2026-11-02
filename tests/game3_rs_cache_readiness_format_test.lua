#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Readiness = require("src.import.gba.rs.cache_readiness")
local BattleChromeExtract = require("src.import.gba.battle_chrome_extract")

local battle
for _, spec in ipairs(Readiness.MODULES) do
  if spec[1] == "pokemon/battle/manifest.lua" then battle = spec end
end

if not battle then
  print("FAIL rs readiness has no battle manifest entry")
  os.exit(1)
end
if battle[2].format ~= BattleChromeExtract.FORMAT_VERSION then
  print(string.format("FAIL rs readiness wants battle manifest format %s, extractor writes %s",
    tostring(battle[2].format), tostring(BattleChromeExtract.FORMAT_VERSION)))
  os.exit(1)
end
print("PASS rs readiness battle manifest format matches the extractor")

local Builds = require("src.import.gba.rs_builds")
local Rs = require("src.import.gba.games.rs")
local ROOT = "data/generated/gba/"
local EASY_CHAT = {"rse/easy_chat", "rse/trendy_phrase", "rse/easy_chat_editor"}
local failures = 0

local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local function serialize(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, x in pairs(v) do
    local key = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
    parts[#parts + 1] = key .. "=" .. serialize(x)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function fakeCache(version, build, staleSub)
  local files = {}
  for _, spec in ipairs(Readiness.PACKS or {}) do
    local man = {assetLayout = "rs", build = build, game = version, format = 1, files = {}}
    for k, v in pairs(spec[2] or {}) do man[k] = v end
    for _, sub in ipairs(EASY_CHAT) do
      if spec[1] == sub and sub ~= staleSub then man.titlePalette = 1 end
    end
    if spec[1] == staleSub then man.titlePalette = nil end
    files[ROOT .. spec[1] .. "/manifest.lua"] = "return " .. serialize(man)
  end
  for _, spec in ipairs(Readiness.MODULES) do
    local man = {build = build, game = version, files = {}}
    for k, v in pairs(spec[2] or {}) do man[k] = v end
    files[ROOT .. spec[1]] = "return " .. serialize(man)
  end
  files[ROOT .. "chrome/native_fonts.lua"] = "return {layout = \"rs\", formatVersion = 2}"
  for gender = 0, 2 do files[ROOT .. "trainers/back_" .. gender .. ".rgba"] = string.rep("\0", 64 * 64 * 4 * 4) end
  for _, name in ipairs({"elements.rgba", "elements_exp.rgba"}) do
    files[ROOT .. "pokemon/battle/" .. name] = string.rep("\0", 320 * 24 * 4)
  end
  files[ROOT .. "pokemon/battle/healthbox_safari.rgba"] = string.rep("\0", 128 * 64 * 4)
  files[ROOT .. "pokemon/battle/healthbox_doubles_player.rgba"] = string.rep("\0", 128 * 32 * 4)
  files[ROOT .. "pokemon/battle/healthbox_doubles_opponent.rgba"] = string.rep("\0", 128 * 32 * 4)
  return {read = function(path) return files[path] end, exists = function() return true end}
end

for _, version in ipairs({"ruby", "sapphire"}) do
  local row = Builds[version][1]
  local ok, path, why = Readiness.check(version, fakeCache(version, row.build), row.sha1)
  check(ok == true, version .. " readiness accepts a current Easy Chat cache"
    .. (ok and "" or (" (" .. tostring(path) .. ": " .. tostring(why) .. ")")))
  for _, sub in ipairs(EASY_CHAT) do
    ok, path, why = Readiness.check(version, fakeCache(version, row.build, sub), row.sha1)
    check(ok == false and path == ROOT .. sub .. "/manifest.lua" and why == "invalid titlePalette",
      version .. " readiness rejects " .. sub .. " without titlePalette")
  end
  check(Rs.new(version).CACHE_VERSION >= 9, version .. " CACHE_VERSION retires pre-titlePalette caches")
end

if failures > 0 then os.exit(1) end
