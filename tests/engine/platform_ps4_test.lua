-- PS4 capability detection, and the launcher capabilities it shares with or
-- keeps apart from NX / Xbox / iOS / desktop.
-- Self-contained: luajit tests/engine/platform_ps4_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local savedLove = _G.love

local function withOS(osName, pickFile, fn)
  _G.love = {
    system = {
      getOS = function() return osName end,
      pickFile = pickFile,
    },
  }
  package.loaded["src.core.Platform"] = nil
  local Platform = require("src.core.Platform")
  Platform._resetForTests()
  local ok, err = pcall(fn, Platform)
  _G.love = savedLove
  package.loaded["src.core.Platform"] = nil
  if not ok then error(err) end
end

-- PS4: the Switch's inbox import, Xbox's focus navigation, iOS's system quit.
withOS("PS4", nil, function(Platform)
  local caps = Platform.detect()
  eq(caps.ps4, true, "PS4 flag")
  eq(caps.nx, false, "PS4 is not NX")
  eq(caps.console, true, "PS4 console")
  eq(caps.romImportMode, "save-directory", "PS4 imports through the inbox")
  eq(caps.canSpawnProcess, false, "PS4 cannot spawn processes")
  eq(caps.networkValidated, false, "PS4 has no self-updater")
  eq(Platform.isPS4(), true, "isPS4 convenience")
  eq(Platform.isNX(), false, "isNX false on PS4")
  eq(Platform.padNavigation(), "focus", "PS4 pad drives the focus ring")
  eq(Platform.systemQuit(), true, "PS4: the PS button owns quitting")
  eq(Platform.inboxTransfer(), "ftp", "PS4 inbox hints say FTP")
end)

withOS("NX", nil, function(Platform)
  eq(Platform.padNavigation(), "pointer", "NX pad drives the virtual cursor")
  eq(Platform.systemQuit(), false, "NX keeps the Quit button")
  eq(Platform.inboxTransfer(), "mtp", "NX inbox hints say MTP")
end)

withOS("UWP", function() end, function(Platform)
  eq(Platform.padNavigation(), "focus", "Xbox pad drives the focus ring")
  eq(Platform.systemQuit(), false, "Xbox keeps the Quit button")
  eq(Platform.inboxTransfer(), nil, "Xbox has no inbox")
end)

withOS("iOS", function() end, function(Platform)
  eq(Platform.systemQuit(), true, "iOS: Home owns quitting")
  eq(Platform.padNavigation(), nil, "iOS pad cursor stays latent")
end)

withOS("OS X", nil, function(Platform)
  eq(Platform.padNavigation(), nil, "desktop pad cursor stays latent")
  eq(Platform.systemQuit(), false, "desktop keeps the Quit button")
  eq(Platform.inboxTransfer(), nil, "desktop has no inbox")
end)

T.finish()
