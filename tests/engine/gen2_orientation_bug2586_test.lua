package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local SaveData = require("src.core.SaveData")
local Save = require("src.core.gen2.Save")
local Orientation = require("src.core.Orientation")
local Settings = require("src.import.LauncherSettings")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Game2 = require("src.core.Game2")
local StateStack = require("src.core.StateStack")
local realLoad, realSave = SaveData.loadOptions, SaveData.saveOptions
local realApply = Orientation.apply
local applied
Orientation.apply = function(mode) applied = mode; return true end
local function memfs()
  local files = {}
  return {
    write = function(path, content) files[path] = content; return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil; return true end,
    getInfo = function(path) return files[path] and { type = "file" } end,
  }
end
local function orientationRow(model)
  for _, section in ipairs(model.sections) do
    for _, row in ipairs(section.rows) do
      if row.label == "ORIENTATION" then return row end
    end
  end
end
for _, osName in ipairs({ "Android", "iOS", "OS X" }) do
  love.system.getOS = function() return osName end
  for _, version in ipairs({ "red", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
    local fs = memfs()
    local seed = SaveData.defaultOptions()
    seed.orientation = "landscape"
    seed.gold = { orientation = "portrait", textSpeed = "FAST" }
    realSave(seed, fs)
    SaveData.loadOptions = function() return realLoad(fs) end
    SaveData.saveOptions = function(opts) return realSave(opts, fs) end
    local model = Settings.open({}, version)
    local row = orientationRow(model)
    T.eq(row ~= nil, osName ~= "OS X", osName .. " " .. version .. " row visibility")
    if row then
      T.eq(row.value(), Orientation.modeLabel("landscape"), version .. " launcher reads flat orientation")
      applied = nil
      T.eq(row.step(1), true, version .. " orientation row steps")
      T.eq(applied, "reverseLandscape", version .. " launcher applies selection live")
      T.eq(model.opts.orientation, "reverseLandscape", version .. " launcher writes shared root")
      T.eq(model.opts.gold.orientation, "portrait", version .. " launcher ignores stale local copy")
      model.save()
      T.eq(realLoad(fs).orientation, "reverseLandscape", version .. " selection persists flat")
      T.eq(Save.loadOptions(fs).orientation, "reverseLandscape", version .. " shared value loads into Gen2")
    end
    SaveData.loadOptions, SaveData.saveOptions = realLoad, realSave
  end
  local options = Save.defaultOptions()
  options.orientation = "landscape"
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local game = { options = options, stack = stack, data = { text = require("tests.fixture_data.gen2_rom_text_s7_c").text() } }
  local menu = OptionsMenu.new(game, { options = options })
  stack:push(menu)
  local row
  for _, item in ipairs(menu.rows) do if item.id == "orientation" then row = item end end
  T.eq(row ~= nil, osName ~= "OS X", osName .. " in-game orientation visibility")
  if row then
    local focused = menu:focusRow("orientation")
    T.check(focused ~= nil and focused ~= menu, osName .. " orientation lives in VIDEO group")
    T.eq(focused:row().id, "orientation", osName .. " group focuses orientation")
    applied = nil
    focused:cycle(row, 1)
    T.eq(options.orientation, "reverseLandscape", osName .. " actual menu cycles shared options")
    T.eq(applied, "reverseLandscape", osName .. " actual menu applies selection live")
  end
end
SaveData.loadOptions, SaveData.saveOptions = realLoad, realSave
for _, value in ipairs({ "landscape", "reverseLandscape", "bogus" }) do
  local fs = memfs()
  local seed = SaveData.defaultOptions()
  seed.orientation = value
  seed.gold = { orientation = "portrait", textSpeed = "FAST" }
  realSave(seed, fs)
  local options = Save.loadOptions(fs)
  T.eq(options.orientation, Orientation.normalize(value), "root " .. value .. " wins with normalization")
  options.orientation = "portrait"
  T.check(Save.saveOptions(options, fs), "Gen2 orientation persistence returns success")
  local written = realLoad(fs)
  T.eq(written.orientation, "portrait", "Gen2 writes host orientation flat")
  T.eq(written.gold.orientation, nil, "Gen2 write removes stale local orientation")
  T.eq(written.gold.textSpeed, "FAST", "Gen2 cartridge option remains local")
  T.eq(Save.loadOptions(fs).orientation, "portrait", "Gen2 host orientation round-trips")
end
T.eq(Save.loadOptions(memfs()).orientation, "auto", "missing Gen2 orientation defaults to AUTO")
love.system.getOS = function() return "OS X" end
local game = setmetatable({ options = Save.defaultOptions() }, { __index = Game2 })
game.options.orientation = "reverseLandscape"
applied = nil
game:applyOptions()
T.eq(applied, "reverseLandscape", "Game2 applies the loaded host orientation")
Orientation.apply = realApply
T.finish("Gen2 orientation bug 2586")
