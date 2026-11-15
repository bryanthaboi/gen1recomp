package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local files = {}
local noop = function() end
love = {
  filesystem = {
    read = function(rel) return files[rel] end,
    getInfo = function(rel) return files[rel] and { type = "file" } or nil end,
  },
  graphics = {
    newQuad = function() return {} end,
    setColor = noop, rectangle = noop, draw = noop,
  },
  image = { newImageData = function() return {} end },
}

require("src.core.GameVersion").set("firered")

local rawBlob = string.rep("\255", 64)
local brokenLua = "return {"

local function raises(fn, rel, bytes, label, staged)
  for k, v in pairs(staged or {}) do files["firered/" .. k] = v end
  files["firered/" .. rel] = bytes
  local ok, err = pcall(fn)
  for k in pairs(staged or {}) do files["firered/" .. k] = nil end
  files["firered/" .. rel] = nil
  check(not ok and tostring(err):find(rel, 1, true) ~= nil, label .. ": " .. tostring(err))
  if bytes == nil then
    check(not ok and tostring(err):find("is not in the cache", 1, true) ~= nil, label .. " names the miss")
  end
end

local FameCheckerUi = require("src.ui.game3.fame_checker")
local function famePack()
  FameCheckerUi.reloadAssets()
  return FameCheckerUi.pack()
end
local function fameBg()
  FameCheckerUi.reloadAssets()
  return FameCheckerUi.background()
end
raises(fameBg, "data/generated/gba/fame_checker/bg.rgba", rawBlob, "an undeflated fame checker background raises")
raises(famePack, "data/generated/gba/fame_checker/pack.lua", brokenLua, "a broken fame checker pack raises")
raises(fameBg, "data/generated/gba/fame_checker/bg.rgba", nil, "a missing fame checker background raises")
raises(famePack, "data/generated/gba/fame_checker/pack.lua", nil, "a missing fame checker pack raises")

local BRAILLE_MANIFEST = "data/generated/gba/chrome/fonts/braille.lua"
local brailleManifest = { [BRAILLE_MANIFEST] = "return { width = 256, height = 64, cols = 16 }" }
local Braille = require("src.ui.game3.braille")
local function brailleSheet()
  Braille.invalidate()
  return Braille.hasSheet()
end
raises(brailleSheet, "data/generated/gba/chrome/fonts/braille_fg.rgba", rawBlob,
  "an undeflated braille glyph sheet raises", brailleManifest)
raises(brailleSheet, BRAILLE_MANIFEST, brokenLua, "a broken braille manifest raises")
raises(brailleSheet, "data/generated/gba/chrome/fonts/braille_fg.rgba", nil,
  "a missing braille glyph sheet raises", brailleManifest)
raises(brailleSheet, BRAILLE_MANIFEST, nil, "a missing braille manifest raises")

local CacheBlob = require("src.import.CacheBlob")
local BRAILLE_FG = "data/generated/gba/chrome/fonts/braille_fg.rgba"
local BRAILLE_SHADOW = "data/generated/gba/chrome/fonts/braille_shadow.rgba"
local fgSheet = CacheBlob.encode(BRAILLE_FG, string.rep("\0", 256 * 64 * 4))
love.graphics.newImage = function(data)
  return { getWidth = function() return 256 end, getHeight = function() return 64 end, setFilter = noop, data = data }
end
raises(brailleSheet, BRAILLE_SHADOW, nil, "a missing braille shadow sheet raises when the manifest declares one",
  { [BRAILLE_MANIFEST] = brailleManifest[BRAILLE_MANIFEST], [BRAILLE_FG] = fgSheet })

files["firered/" .. BRAILLE_MANIFEST] =
  "return { layout = 'rs', width = 256, height = 64, cols = 16, linePitch = 32, shadow = false }"
files["firered/" .. BRAILLE_FG] = fgSheet
Braille.invalidate()
local okRs, rsSheet = pcall(Braille.hasSheet)
check(okRs and rsSheet == true, "a shadow = false braille manifest loads without a shadow sheet: " .. tostring(rsSheet))
check(okRs and Braille._sh == nil and Braille._fg ~= nil, "a shadow = false braille manifest draws the glyph sheet only")
check(okRs and Braille.linePitch() == 32, "a shadow = false braille manifest keeps its line pitch")
files["firered/" .. BRAILLE_MANIFEST] = nil
files["firered/" .. BRAILLE_FG] = nil
Braille.invalidate()

local RECORDS_MANIFEST = "data/generated/gba/trainer_tower/manifest.lua"
local recordsManifest = { [RECORDS_MANIFEST] = "return { recordsBg = { width = 240, height = 160 } }" }
local Records = require("src.ui.game3.trainer_tower_records")
local function recordsDraw()
  Records.resetArt()
  Records.open, Records._kind = true, "tower"
  return Records.draw()
end
raises(recordsDraw, "data/generated/gba/trainer_tower/records_bg.rgba", rawBlob,
  "an undeflated tower records background raises", recordsManifest)
raises(recordsDraw, RECORDS_MANIFEST, brokenLua, "a broken tower records manifest raises")
raises(recordsDraw, "data/generated/gba/trainer_tower/records_bg.rgba", nil,
  "a missing tower records background raises", recordsManifest)
raises(recordsDraw, RECORDS_MANIFEST, nil, "a missing tower records manifest raises")

T.finish("game3_ui_cache_read_strict")
