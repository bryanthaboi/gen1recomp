-- NX / Android / desktop capability detection (SWNX-01).
-- Self-contained: luajit tests/engine/platform_nx_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
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

-- NX: save-directory import, no shell spawn, network gated off
withOS("NX", nil, function(Platform)
  local caps = Platform.detect()
  eq(caps.os, "NX", "NX detect os")
  eq(caps.nx, true, "NX flag")
  eq(caps.romImportMode, "save-directory", "NX romImportMode")
  eq(caps.canSpawnProcess, false, "NX cannot spawn processes")
  eq(caps.networkValidated, false, "NX network not validated")
  eq(Platform.isNX(), true, "isNX convenience")
  eq(Platform.romImportMode(), "save-directory", "romImportMode helper")
end)

-- Android: mobile native picker path, not NX semantics
withOS("Android", function() end, function(Platform)
  local caps = Platform.detect()
  eq(caps.os, "Android", "Android detect os")
  eq(caps.nx, false, "Android is not NX")
  eq(caps.mobile, true, "Android mobile")
  eq(caps.hasNativePicker, true, "Android has pickFile")
  eq(caps.romImportMode, "native-picker", "Android romImportMode")
  eq(Platform.isNX(), false, "Android isNX false")
end)

-- Desktop Linux: shell spawn + desktop import mode
withOS("Linux", nil, function(Platform)
  local caps = Platform.detect()
  eq(caps.os, "Linux", "Linux detect os")
  eq(caps.nx, false, "Linux is not NX")
  eq(caps.canSpawnProcess, true, "Linux can spawn processes")
  eq(caps.romImportMode, "desktop", "Linux romImportMode")
  eq(caps.networkValidated, true, "Linux network validated")
  eq(Platform.canSpawnProcess(), true, "canSpawnProcess helper")
end)

T.finish()
