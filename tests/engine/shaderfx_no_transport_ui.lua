package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function() end,
  drawCode = function() end,
  drawBox = function() end,
  width = function(text) return #tostring(text) * 8 end,
  split = function(text)
    local spans = {}
    for i = 1, #tostring(text) do spans[i] = { from = i, to = i, code = 0 } end
    return spans
  end,
  spansFitting = function(spans, pixels) return math.min(#spans, math.floor(pixels / 8)) end,
}
package.loaded["src.core.Logger"] = {
  info = function() end,
  error = function() end,
  warn = function() end,
}
package.loaded["src.core.Sound"] = { play = function() end }

local savedHostShell = package.loaded["src.core.HostShell"]
local savedPlatform = package.loaded["src.core.Platform"]
local savedShaderFX = package.loaded["src.render.ShaderFX"]
local savedScreen = package.loaded["src.ui.ShaderFXScreen"]

local downloads, converts = 0, 0
local fake
fake = {
  fetch = false,
  can = false,
  nx = false,
  OPTION_KEY = { main = "shaderfx", secondary = "shaderfx2" },
  canConvert = function() return fake.can end,
  recordError = function() end,
  bridgeError = function() return fake.can and nil or "librashader bridge not found" end,
  list = function()
    return {
      { name = "bevel.slangp", converted = true },
      { name = "zfast-lcd.slangp", converted = false },
    }
  end,
  activeEntry = function() return nil end,
  convert = function() converts = converts + 1; return true end,
  activate = function() return true end,
  deactivate = function() end,
  clearBridgeQuarantine = function() end,
  downloadPresets = function() downloads = downloads + 1; return {} end,
  downloadStatus = function() return { status = "error", err = "no network transport on this platform" } end,
  installDownloaded = function() return 0 end,
}
package.loaded["src.render.ShaderFX"] = fake
package.loaded["src.core.HostShell"] = { canFetch = function() return fake.fetch end }
package.loaded["src.core.Platform"] = {
  isNX = function() return fake.nx end,
  isUWP = function() return false end,
  detect = function() return { nx = fake.nx } end,
}
package.loaded["src.ui.ShaderFXScreen"] = nil

local ShaderFXScreen = require("src.ui.ShaderFXScreen")

local function open()
  downloads, converts = 0, 0
  return ShaderFXScreen.new({
    input = { wasPressed = function() return false end },
    stack = { top = function() end, pop = function() end },
    save = { options = {} },
    writeOptions = function() end,
  }, "main")
end

fake.fetch, fake.can, fake.nx = false, false, true
local s = open()
local row = s.items[#s.items]
eq(row.download, true, "the last row is still the download action")
eq(row.muted, true, "with no transport the download row is muted")
s.onChoose(row)
eq(downloads, 0, "A on the muted row never starts a download")
check(row.right ~= "FAILED" and row.right ~= "...",
  "the row does not read FAILED or a spinner (got " .. tostring(row.right) .. ")")
eq(s.footer, "Copy to shaders/", "the footer says how presets arrive instead")
check(#s.footer <= 18 and s.footer:find("\n", 1, true) == nil,
  "the manual-install hint fits the one 18-column footer line")
s.update(s, 0)
check(row.right ~= "FAILED", "a later frame does not turn the row into FAILED")

s.onChoose(s.items[3])
eq(converts, 0, "A on an unconverted preset with no bridge never converts")
eq(s.footer, "Convert on a PC", "on Switch the unconverted row points at a desktop convert")
check(#s.footer <= 18, "that footer stays one 18-column line")
eq(s.items[3].right, "UPDATE", "the row keeps its UPDATE label")

fake.fetch, fake.can, fake.nx = true, false, false
s = open()
row = s.items[#s.items]
eq(row.muted, nil, "with a transport the download row is not muted")
s.onChoose(row)
eq(downloads, 1, "A on it starts exactly one download")
eq(row.right, "...", "and shows the in-flight marker")
eq(s.footer, "SELECT:EDIT PARAMS", "the footer keeps its hint")

s.onChoose(s.items[3])
eq(s.footer, "Reinstall the app", "off Switch a missing bridge still advises a reinstall")

package.loaded["src.core.HostShell"] = savedHostShell
package.loaded["src.core.Platform"] = savedPlatform
package.loaded["src.render.ShaderFX"] = savedShaderFX
package.loaded["src.ui.ShaderFXScreen"] = savedScreen

T.finish("shaderfx no-transport picker")
