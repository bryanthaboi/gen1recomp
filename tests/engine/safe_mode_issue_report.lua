package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("safe mode and issue report")
local check = S.check

local SaveData = require("src.core.SaveData")
local LauncherMods = require("src.mods.LauncherMods")
local IssueReport = require("src.core.IssueReport")
local Version = require("src.core.Version")

local options = SaveData.defaultOptions()
check(not SaveData.isSafeMode(options), "safe mode defaults off")
SaveData.setSafeMode(options, true)
check(SaveData.isSafeMode(options), "safe mode can be enabled")

local manifests = {
  { id = "alpha", name = "Alpha", version = "1.0.0", experimental = false,
    raw = {}, dependencySpecs = {}, conflictSpecs = {} },
  { id = "beta", name = "Beta", version = "1.0.0", experimental = false,
    raw = {}, dependencySpecs = {}, conflictSpecs = {} },
}
options.mods.alpha = false
options.mods.beta = true
local rows = LauncherMods.deriveList(manifests, options, "red")
check(#rows == 2, "safe mode keeps installed mods visible")
check(not rows[1].enabled and not rows[2].enabled,
  "safe mode disables every launcher mod row")
check(rows[1].status == "safe_mode" and rows[2].status == "safe_mode",
  "safe mode explains every disabled launcher row")

SaveData.setSafeMode(options, false)
rows = LauncherMods.deriveList(manifests, options, "red")
local byId = {}
for _, row in ipairs(rows) do byId[row.id] = row end
check(not byId.alpha.enabled and byId.beta.enabled,
  "turning safe mode off restores saved mod choices")

local previousLove = _G.love
local openedURL
_G.love = {
  getVersion = function() return 12, 0, 0, "Mysterious Mysteries" end,
  system = {
    getOS = function() return "iOS" end,
    getDeviceModel = function() return "iPhone16,2" end,
    getModel = function() return "Apple A17 Pro GPU" end,
    openURL = function(url) openedURL = url end,
  },
  graphics = {
    getRendererInfo = function()
      return "Metal", "3.0", "Apple", "Simulator GPU"
    end,
    getDimensions = function() return 1024, 768 end,
    getPixelDimensions = function() return 2048, 1536 end,
  },
  window = {
    getMode = function() return 1024, 768, { fullscreen = false } end,
  },
}

local url, fields, info = IssueReport.build({
  safeMode = true,
  lastVersion = "gold",
}, {
  version = "gold",
  mods = { { id = "alpha", name = "Alpha", enabled = true } },
})
check(url:find("template=bug_report.yml", 1, true) ~= nil,
  "report URL selects the bug form")
check(url:find("title=bug%3A%20replace%20this%20with%20a%20meaningful%20title", 1, true) ~= nil,
  "report URL uses the requested bug title")
check(info.os == "iOS",
  "report metadata maps the platform")
check(fields.mods_which == "",
  "safe mode leaves the optional mod list blank")
check(not url:find("game=", 1, true)
    and not url:find("os=", 1, true)
    and not url:find("mods_enabled=", 1, true),
  "report URL omits unsupported dropdown and checkbox prefills")
check(fields.summary == "" and fields.location == "" and fields.screenshot == ""
    and fields.steps == "" and fields.expected == "",
  "report leaves user-entered fields blank")
check(info.device == "iPhone 15 Pro Max"
    and info.metadata:find("Device: iPhone 15 Pro Max", 1, true) ~= nil
    and info.metadata:find("LÖVE: 12.0.0", 1, true) ~= nil
    and info.metadata:find("Safe mode: on", 1, true) ~= nil,
  "report metadata includes device and app details")
check(not info.metadata:find("Simulator GPU", 1, true),
  "report metadata does not mistake the renderer device for the device")
check(not info.metadata:find("unknown", 1, true),
  "report metadata omits unknown values")
check(not info.metadata:find("Game id", 1, true)
    and not info.metadata:find("Game:", 1, true)
    and not info.metadata:find("Mods:", 1, true)
    and not info.metadata:find("Processors", 1, true)
    and not info.metadata:find("Power", 1, true),
  "report metadata omits redundant system fields")

local previousEngine = Version.engine
Version.engine = "0.1.50"
local _, versionFields, versionInfo = IssueReport.build({}, { mods = {} })
check(versionFields.version == "0.1.50"
    and versionInfo.metadata:find("App: gen1recomp v0.1.50", 1, true) ~= nil,
  "report uses the stamped app version")
Version.engine = previousEngine
local _, _, developmentInfo = IssueReport.build({}, { mods = {} })
check(not developmentInfo.metadata:find("0.0.0-dev", 1, true),
  "report omits an unstamped development version")

local previousOS = love.system.getOS
local previousModel = love.system.getModel
local previousDeviceModel = love.system.getDeviceModel
local previousIO = _G.io
love.system.getOS = function() return "OS X" end
love.system.getModel = nil
love.system.getDeviceModel = nil
_G.io = {
  popen = function(command)
    local output = command:find("system_profiler", 1, true)
      and "Hardware Overview:\n    Model Name: MacBook Air\n    Model Identifier: Mac14,15\n    Chip: Apple M2\n"
      or "Mac14,15\n"
    return {
      read = function() return output end,
      close = function() end,
    }
  end,
}
local desktopInfo = IssueReport.metadata({}, { mods = {} })
check(desktopInfo.device == "MacBook Air (Apple M2)",
  "report finds desktop device model when LOVE has no model")
love.system.getOS = function() return "UWP" end
local xboxInfo = IssueReport.metadata({}, { mods = {} })
check(xboxInfo.os == "Xbox", "report maps the Xbox runtime platform")
love.system.getOS = previousOS
love.system.getModel = previousModel
love.system.getDeviceModel = previousDeviceModel
_G.io = previousIO

local opened = IssueReport.open({ safeMode = false }, {
  version = "red",
  mods = {},
})
check(opened and openedURL and openedURL:find("title=bug%3A%20replace%20this%20with%20a%20meaningful%20title", 1, true) ~= nil,
  "report action opens the generated URL")

_G.love = previousLove

S.finish()
