return function(game)
  local U = dofile("tests/drivers/util.lua")
  local LaunchOptions = require("src.core.LaunchOptions")
  local RomImporter = require("src.import.RomImporter")
  local ModUpdate = require("src.mods.ModUpdate")
  local LauncherMods = require("src.mods.LauncherMods")
  local Platform = require("src.core.Platform")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/updatemods2037"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local failed = false
  local function expect(cond, label, why)
    if cond then
      print("PASS " .. label)
    else
      failed = true
      print("FAIL " .. label .. (why and (": " .. tostring(why)) or ""))
    end
  end

  local t = LaunchOptions.tasks({ "--game=red", "--update-mods" }, nil, false)
  expect(t.mods == true and t.update == false, "flag_parsed",
    tostring(t.mods) .. "/" .. tostring(t.update))
  expect(LaunchOptions.tasks({ "--updatemods" }, nil, false).mods == true,
    "flag_alias_parsed")

  local realBeginZip = ModUpdate.beginDownloadZip
  local realPumpZip = ModUpdate.pumpDownloadZip
  local realInstall = LauncherMods.installDownloadedZip
  local realRemote = Platform.canFetchRemote
  local realDeps = LauncherMods.checkDependencies

  local failId = nil
  local installs = {}
  local onDisk = {}
  ModUpdate.beginDownloadZip = function() return { frames = 0 } end
  ModUpdate.pumpDownloadZip = function(h)
    h.frames = h.frames + 1
    if h.frames < 90 then return false, nil, nil, h.frames / 90 end
    love.filesystem.write("update_mods_2037.zip", "BYTES")
    return true, "update_mods_2037.zip"
  end
  LauncherMods.installDownloadedZip = function(id, _, version)
    installs[#installs + 1] = id
    if id == failId then return nil, "the archive had no manifest" end
    onDisk[id] = version
    return true, version
  end
  LauncherMods.checkDependencies = function() return { hasIssues = false } end
  Platform.canFetchRemote = function() return true end

  local RELEASE = { version = "2.0.0",
                    zip = { url = "https://example.invalid/fake.zip" } }
  local function newLauncher()
    local imp = RomImporter.new(function() end, { launcher = true })
    imp.safeMode = false
    onDisk = {}
    imp._refreshMods = function(self)
      for _, m in ipairs(self.mods or {}) do
        if onDisk[m.id] then m.version = onDisk[m.id] end
      end
      self._modUpdateRev = (self._modUpdateRev or 0) + 1
    end
    imp._refreshFindSources = function(self) self.findSources = {} end
    imp._refreshFind = function() end
    imp._pumpFindFetch = function() end
    imp._findFetch = nil
    imp.findLoaded = true
    imp.findIndex = { mods = {}, carts = {} }
    imp.mods = {
      { id = "fake_mod", name = "Fake Mod", version = "1.0.0",
        github = "example/fake-mod", enabled = true, status = "ok" },
    }
    imp._syncModUpdateInfo = function(self)
      self.modUpdateInfo = { fake_mod = { status = "available",
        latest = "2.0.0", best = RELEASE, releases = { RELEASE } } }
      self._modUpdateRev = (self._modUpdateRev or 0) + 1
    end
    return imp
  end

  local imp
  local pending = nil
  love.draw = function()
    if imp then imp:draw() end
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end
  local confirmSeen = false
  local function step(n)
    for _ = 1, n do
      if imp then
        imp:update(1 / 60)
        if imp._modConfirm then confirmSeen = true end
      end
      coroutine.yield()
    end
  end
  local function shot(name)
    pending = dir .. "/" .. name
    for _ = 1, 30 do
      if not pending then break end
      step(1)
    end
    step(2)
    local f = io.open(dir .. "/" .. name, "rb")
    U.log(f and "shot" or "FAIL shot", name)
    if f then f:close() end
  end

  imp = newLauncher()
  local results = {}
  local started = imp:autoUpdateAll(function(r)
    results[#results + 1] = r
  end, { tab = "mods" })
  expect(started, "auto_sweep_started")
  expect(imp.tab == "mods", "launcher_on_mods_tab", imp.tab)
  step(30)
  expect(imp._modInstall ~= nil and imp._busy ~= nil, "overlay_updating_row",
    imp._busy and imp._busy.title)
  expect(not confirmSeen, "no_confirm_modal")
  shot("2037_01_updating_overlay_no_confirm.png")
  for _ = 1, 200 do
    if #results > 0 then break end
    step(1)
  end
  expect(#results == 1 and results[1].ok == true, "on_done_ok_boot_handoff",
    results[1] and tostring(results[1].ok))
  expect(installs[1] == "fake_mod", "mod_installed", installs[1])
  expect(not confirmSeen, "no_confirm_whole_run")
  expect(imp.modNotice and imp.modNotice.text == "Updated 1 items.",
    "notice_updated", imp.modNotice and imp.modNotice.text)
  local row = imp.mods[1]
  local rowInfo = imp:_modUpdateInfo("fake_mod")
  expect(row.version == "2.0.0" and rowInfo and rowInfo.status == "current",
    "row_shows_updated_version",
    tostring(row.version) .. "/" .. tostring(rowInfo and rowInfo.status))
  step(20)
  shot("2037_02_update_done_notice.png")

  imp = newLauncher()
  failId = "fake_mod"
  installs, results, confirmSeen = {}, {}, false
  imp:autoUpdateAll(function(r) results[#results + 1] = r end, { tab = "mods" })
  for _ = 1, 300 do
    if #results > 0 then break end
    step(1)
  end
  failId = nil
  expect(#results == 1 and results[1].ok == false, "failure_reported_not_ok")
  expect(imp.modNotice and imp.modNotice.ok == false
    and #(imp.modNotice.failures or {}) == 1, "failure_stays_on_launcher",
    imp.modNotice and imp.modNotice.text)
  step(20)
  shot("2037_03_failed_update_stays_on_launcher.png")

  imp = newLauncher()
  confirmSeen = false
  imp:_switchTab("mods")
  expect(imp:pressUpdateAllMods(), "button_press_starts")
  step(10)
  expect(confirmSeen and (imp._updateAll or {}).stage == "confirm",
    "button_still_confirms")
  step(10)
  shot("2037_04_button_still_confirms.png")
  imp._modConfirm = nil
  step(3)

  ModUpdate.beginDownloadZip = realBeginZip
  ModUpdate.pumpDownloadZip = realPumpZip
  LauncherMods.installDownloadedZip = realInstall
  LauncherMods.checkDependencies = realDeps
  Platform.canFetchRemote = realRemote
  imp = nil
  U.log("done")
  love.event.quit(failed and 1 or 0)
end
