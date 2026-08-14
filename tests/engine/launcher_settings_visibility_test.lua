-- Android launcher settings must apply the same visibleIf contract as the
-- in-game mod manager, including live updates from a parent toggle.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local loveStub = require("tests.love_stub")
_G.love = loveStub

local LauncherSettings = require("src.import.LauncherSettings")
local SaveData = require("src.core.SaveData")

local oldLoadOptions, oldFs = SaveData.loadOptions, love.filesystem
local opts = { mods = {}, modOptions = {} }
local schemaSource = [[return {
  { key = "master", label = "MASTER", type = "toggle", default = false },
  { key = "detail", label = "DETAIL", type = "toggle", default = true,
    visibleIf = { key = "master", equals = true } },
  { key = "nested", label = "NESTED", type = "toggle", default = true,
    visibleIf = { all = {
      { key = "master", equals = true },
      { key = "detail", equals = true },
    } } },
}]]
local files = {
  ["mods/launcher_fixture/manifest.json"] =
    '{"id":"launcher_fixture","name":"Launcher Fixture",'
    .. '"version":"1.0.0","entry":"main.lua",'
    .. '"options_schema":"options.lua"}',
  ["mods/launcher_fixture/options.lua"] = schemaSource,
}
local fs = {
  getInfo = function(path)
    if path == "mods" or path == "mods/launcher_fixture" then
      return { type = "directory" }
    end
    if files[path] then return { type = "file" } end
    return nil
  end,
  getDirectoryItems = function(path)
    if path == "mods" then return { "launcher_fixture" } end
    return {}
  end,
  read = function(path) return files[path] end,
  load = function(path)
    if not files[path] then return nil end
    return assert(load(files[path], path))
  end,
}
love.filesystem = fs
SaveData.loadOptions = function() return opts end

local ok, err = xpcall(function()
  local model = LauncherSettings.open()
  local section
  for _, candidate in ipairs(model.sections) do
    if candidate.mod and candidate.mod.id == "launcher_fixture" then
      section = candidate
      break
    end
  end
  check(section ~= nil, "Android launcher discovers a mod option schema")
  check(#section.rows == 2 and section.rows[1].label == "MASTER",
    "Android launcher omits hidden dependent rows initially")
  section.rows[1].step(1)
  local refreshed = model.refresh()
  check(refreshed and #section.rows == 4
    and section.rows[2].label == "DETAIL"
    and section.rows[3].label == "NESTED",
    "Android launcher reveals direct and nested dependencies live")
  section.rows[2].step(-1)
  check(model.refresh() and #section.rows == 3
    and section.rows[2].label == "DETAIL",
    "Android launcher hides a nested row when its default-true parent is off")
  section.rows[1].step(-1)
  check(model.refresh() and #section.rows == 2,
    "Android launcher hides dependent rows after disabling the parent")
end, debug.traceback)

SaveData.loadOptions, love.filesystem = oldLoadOptions, oldFs
if not ok then error(err, 0) end

T.finish("launcher_settings_visibility")
