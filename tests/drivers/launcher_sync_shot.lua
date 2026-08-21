return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")

  local dir = os.getenv("SHOT_DIR") or "/tmp/syncmodal"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local eng = {
    phase = "idle", status = "Ready", conflicts = {}, state = { enabled = true },
    isLinked = false, isBusy = false,
    linked = function(self) return self.isLinked end,
    busy = function(self) return self.isBusy end,
    createAccount = function(self)
      self.isLinked = true
      self.codes = { code1 = "1234-5678", code2 = "8765-4321" }
      self.status = "Sync account created"
      return true
    end,
    linkDevice = function(self) self.isLinked = true return true end,
    syncNow = function(self) self.status = "Checking for changes..." return true end,
    unlink = function(self) self.isLinked, self.codes = false, nil return true end,
    shareMods = function(self) self.shareCode = "K7QW3M" return true end,
    answerModOptions = function(self, importThem)
      if self.modPlan then self.modPlan.applyOptions = importThem and true or false end
      return importThem
    end,
    fetchShare = function(self) return true end,
    applyModPlan = function(self) self.modPlan = nil return true end,
    resolveConflict = function(self) self.conflicts = {} self.phase = "idle" return true end,
  }

  local imp = RomImporter.new(function() end, { launcher = true })
  imp._sync = eng
  imp._syncTransportOk = true

  local pending = nil
  love.draw = function()
    imp:draw()
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end
  local function shot(name)
    pending = dir .. "/" .. name
    for _ = 1, 90 do
      if not pending then break end
      imp:update(1 / 60)
      coroutine.yield()
    end
    U.wait(3)
    local f = io.open(dir .. "/" .. name, "rb")
    U.log(f and "shot" or "FAIL shot", name)
    if f then f:close() end
  end

  imp:_openSync()
  U.wait(3)
  U.log("modal view:", imp._syncModal.view, "linked:", tostring(eng:linked()))
  shot("sync_new.png")

  imp:_syncView("link")
  imp:_syncFocusField("code1")
  imp:textinput("1234-5678")
  imp:_syncFocusField("code2")
  imp:textinput("8765ab4321")
  U.wait(2)
  U.log("codes typed:", imp._syncModal.code1, imp._syncModal.code2)
  shot("sync_link.png")

  imp:_syncView("home")
  imp:_syncCreate()
  U.wait(2)
  U.log("codes shown:", eng.codes.code1, eng.codes.code2)
  shot("sync_codes.png")

  eng.isBusy = true
  eng.status = "Uploading saves..."
  U.wait(2)
  shot("sync_busy.png")
  eng.isBusy = false
  eng.status = "Ready"

  imp:_syncView("mods")
  imp:_syncShareMods()
  eng.modPlan = {
    indexes = { "https://example.invalid/index.json" },
    toInstall = { { id = "jp_green" }, { id = "randomizer" } },
    toEnable = { { id = "jp_green", version = "red" } },
    missing = { { id = "gone" } },
  }
  U.wait(2)
  U.log("share code:", tostring(eng.shareCode))
  shot("sync_mods.png")

  eng.modPlan.options = {
    { id = "jp_green", values = { language = "JP" } },
    { id = "randomizer", values = { seed = 1234, wild = true } },
    { id = "widescreen_hud", values = { scale = 2 } },
  }
  U.wait(2)
  U.log("options question up:", tostring(eng.modPlan.applyOptions == nil))
  shot("sync_mod_options.png")

  love.window.setMode(800, 480, { resizable = true, highdpi = true })
  U.wait(3)
  shot("sync_mod_options_short.png")
  imp:_syncAnswerModOptions(false)
  U.wait(2)
  shot("sync_mods_short.png")
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(3)

  eng.phase = "conflict"
  eng.status = "These saves were played at the same time."
  eng.conflicts = { {
    key = "red/abcd1234", version = "red", overlap = true,
    localMeta = { savedAt = os.time(), sessionStart = os.time() - 3600,
      summary = { name = "ASH", badges = 3, timeText = "5:42", dexCount = 40 } },
    remoteMeta = { savedAt = os.time() - 600, sessionStart = os.time() - 4200,
      summary = { name = "ASH", badges = 4, timeText = "6:10", dexCount = 44 } },
  } }
  U.wait(2)
  shot("sync_conflict.png")

  love.window.setMode(520, 760, { resizable = true, highdpi = true })
  U.wait(3)
  shot("sync_conflict_narrow.png")

  eng.phase = "idle"
  eng.conflicts = {}
  imp:_syncView("home")
  U.wait(2)
  shot("sync_home_narrow.png")

  imp:_closeSync()
  U.wait(2)
  U.log("closed:", tostring(imp._syncModal == nil))
  shot("sync_closed.png")

  U.log("done")
  love.event.quit()
  while true do coroutine.yield() end
end
