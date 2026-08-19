return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local TouchSkin = require("src.core.TouchSkin")
  local Fetch = require("src.net.Fetch")

  local dir = os.getenv("SHOT_DIR") or "/tmp/skinurl"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local imp = RomImporter.new(function() end, {
    launcher = true,
    onOpenSkinStudio = function() end,
  })

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

  imp:_switchTab("skins")
  U.wait(3)

  U.log("name from url:", RomImporter.skinUrlName(
    "https://example.com/pads/Neon.deltaskin"))
  U.log("name from cfg:", RomImporter.skinUrlName(
    "https://example.com/overlay.cfg"))

  imp.skinUrl = "https://example.com/pads/neon.deltaskin"
  imp._skinUrlFocus = true
  U.wait(2)
  shot("skins_url_typed.png")

  local realDownload, realPoll, realRelease =
    Fetch.download, Fetch.poll, Fetch.release
  local state = { status = "pending", progress = 0.4 }
  Fetch.download = function(url, dest)
    U.log("download:", url, "->", dest)
    return 1
  end
  Fetch.poll = function() return state end
  Fetch.release = function() end

  imp._skinUrlFocus = false
  imp:_addSkinFromUrl()
  U.log("in flight:", tostring(imp._skinFetch ~= nil))
  U.wait(2)
  shot("skins_url_downloading.png")

  state = { status = "error", err = "could not resolve host" }
  imp:_pumpSkinFetch()
  U.log("failure notice:", imp._skinNotice.text)
  U.wait(2)
  shot("skins_url_failed.png")

  Fetch.download, Fetch.poll, Fetch.release = realDownload, realPoll, realRelease

  local staged = TouchSkin.export(
    assert(TouchSkin.load("assets/skins/gb_anim", "gb_anim")),
    "skins/url_probe.zip")
  local raw = love.filesystem.read("skins/url_probe.zip")
  love.filesystem.remove("skins/url_probe.zip")
  U.log("staged:", tostring(staged), "bytes:", raw and #raw or 0)
  imp:_installSkinData("downloaded_pad.zip", raw)
  U.log("install notice:", imp._skinNotice.text)
  U.wait(2)
  shot("skins_url_installed.png")

  local skins = imp:_ensureSkins(true)
  for _, e in ipairs(skins) do
    U.log(("  %s  format=%s buttons=%d"):format(e.id, tostring(e.format),
      e.controls))
  end

  imp._skinActions = { id = skins[1] and skins[1].id }
  U.wait(2)
  shot("skins_actions_sheet.png")

  for _, kind in ipairs({ "native", "retroarch", "delta" }) do
    local path = imp:_exportSkin(skins[1].id, kind)
    U.log("export " .. kind .. ":", tostring(path))
  end
  imp._skinActions = nil
  U.wait(2)
  shot("skins_exported.png")

  love.window.setMode(520, 820, { resizable = true, highdpi = true })
  U.wait(3)
  shot("skins_url_narrow.png")

  U.log("done")
  love.event.quit()
  while true do coroutine.yield() end
end
