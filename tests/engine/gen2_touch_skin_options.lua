package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local Save = require("src.core.gen2.Save")

local function memfs()
  local files = {}
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] ~= nil then return { type = "file" } end
      return nil
    end,
  }
end

local fs = memfs()
local seed = SaveData.defaultOptions()
seed.touchControls = { enabled = true, skin = "gb_anim" }
seed.haptics = "off"
seed[Save.OPTIONS_KEY] = { textSpeed = "FAST", touchControls = { enabled = false } }
check(SaveData.saveOptions(seed, fs) ~= nil, "seed write lands")

local opts = Save.loadOptions(fs)
eq(opts.touchControls and opts.touchControls.skin, "gb_anim",
  "gold sees the skin the launcher picked")
eq(opts.touchControls.enabled, true, "top-level touchControls wins over the gold block")
eq(opts.haptics, "off", "top-level haptics wins over the gold default")
eq(opts.textSpeed, "FAST", "gold-block keys still merge")

local fs2 = memfs()
fs2.files["options.lua"] =
  "return { gold = { touchControls = { enabled = false } } }"
local opts2 = Save.loadOptions(fs2)
eq(opts2.touchControls and opts2.touchControls.enabled, true,
  "shared touchControls (default-folded) wins over a stale gold-block copy")

local fs3 = memfs()
SaveData.saveOptions(SaveData.defaultOptions(), fs3)
local gopts = Save.loadOptions(fs3)
gopts.touchControls = { enabled = true, skin = "tv_crt" }
gopts.haptics = "strong"
gopts.textSpeed = "SLOW"
check(Save.saveOptions(gopts, fs3), "gold options write lands")

local file = SaveData.loadOptions(fs3)
eq(file.touchControls and file.touchControls.skin, "tv_crt",
  "gold's touch pick lands on the shared top-level key")
eq(file.haptics, "strong", "gold's haptics lands on the shared top-level key")
eq(file[Save.OPTIONS_KEY].touchControls, nil, "gold block no longer shadows touchControls")
eq(file[Save.OPTIONS_KEY].haptics, nil, "gold block no longer shadows haptics")
eq(file[Save.OPTIONS_KEY].textSpeed, "SLOW", "gold-only keys stay in the gold block")

local g1 = Save.loadOptions(fs3)
eq(g1.touchControls.skin, "tv_crt", "hoisted value round-trips back into gold")

local TouchSkin = require("src.core.TouchSkin")
local Chrome = require("src.ui.gen2.Chrome")

local savedViewport = TouchSkin.viewport
TouchSkin.viewport = function() return nil end
eq(Chrome.fitScale(640, 576), 4, "no cutout: integer fit against the window")
local ox, oy = Chrome.fitOrigin(640, 576)
eq(ox, 0, "no cutout: centred x")
eq(oy, 0, "no cutout: centred y")

TouchSkin.viewport = function(w, h) return w * 0.25, h * 0.125, w * 0.5, h * 0.5 end
eq(Chrome.fitScale(640, 576), 2, "cutout: integer fit against the cutout rect")
local cx, cy = Chrome.fitOrigin(640, 576)
eq(cx, 160 + (320 - 320) / 2, "cutout: origin starts at the cutout")
eq(cy, 72 + math.floor((288 - 288) / 2), "cutout: origin starts at the cutout y")

TouchSkin.viewport = function() error("boom") end
eq(Chrome.fitScale(640, 576), 4, "a throwing viewport degrades to the window fit")

TouchSkin.viewport = savedViewport

T.finish("gen2_touch_skin_options")
