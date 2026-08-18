-- Driver: renders the launcher's SKINS tab, exercises Use / import, and
-- shoots it.  Stands in for main.lua's Importer branch so the panel can be
-- eyeballed without clicking through the real launcher.
--   SHOT_DIR=/tmp/skinstab POKEPORT_DRIVER=tests/drivers/launcher_skins_tab_shot.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local TouchSkin = require("src.core.TouchSkin")

  local dir = os.getenv("SHOT_DIR") or "/tmp/skinstab"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local studioOpenedWith = nil
  local imp = RomImporter.new(function() end, {
    launcher = true,
    onOpenSkinStudio = function(v) studioOpenedWith = v end,
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
  U.log("tab:", imp.tab)
  local skins = imp:_ensureSkins()
  U.log("skins listed:", #skins)
  for _, e in ipairs(skins) do
    U.log(("  %s  source=%s pages=%d buttons=%d screen=%s ok=%s"):format(
      e.id, e.source, e.pages, e.controls, tostring(e.screen), tostring(e.ok)))
  end
  U.log("active skin:", tostring(imp:_activeSkin()))
  shot("skins_tab.png")

  imp._gamePopup = true
  U.wait(2)
  shot("game_dropdown.png")
  imp._gamePopup = nil
  U.wait(2)

  -- pick one, the way clicking its row does
  imp:_useSkin("tv_crt")
  U.wait(2)
  U.log("after use:", tostring(imp:_activeSkin()), "notice:", imp._skinNotice.text)
  shot("skins_tab_selected.png")

  -- studio hook carries a real cartridge, not the "skins" tab id
  imp.modScope = "red"
  if imp.onOpenSkinStudio then imp.onOpenSkinStudio(imp.modScope or "red") end
  U.log("studio opened with version:", tostring(studioOpenedWith))

  -- import: a dropped zip on this tab is a skin, not a mod
  local exported = TouchSkin.export(
    assert(TouchSkin.load("assets/skins/gb_anim", "gb_anim")),
    "skins/dropped_probe.zip")
  U.log("staged archive:", tostring(exported))
  local raw = love.filesystem.read("skins/dropped_probe.zip")
  love.filesystem.remove("skins/dropped_probe.zip")
  -- same shape LOVE's DroppedFile presents to readDroppedFile
  local dropped = {
    getFilename = function() return "/tmp/my_cool_skin.zip" end,
    getSize = function() return #raw end,
    open = function() return true end,
    read = function() return raw end,
    close = function() return true end,
  }
  imp:filedropped(dropped)
  U.log("import notice:", imp._skinNotice.text)
  U.log("skins after import:", #imp:_ensureSkins())
  U.log("my_cool_skin found:", tostring(TouchSkin.find("my_cool_skin") ~= nil))
  imp:_useSkin(nil)
  shot("skins_tab_imported.png")

  -- import button: the picker hands back an absolute host path, not a drop
  local picked = dir .. "/picked_skin.zip"
  local pf = io.open(picked, "wb")
  pf:write(raw)
  pf:close()
  imp:_installSkinZip(picked)
  U.log("path import notice:", imp._skinNotice.text)
  U.log("picked_skin found:", tostring(TouchSkin.find("picked_skin") ~= nil))
  U.log("import label:", imp:_skinsImportButtonLabel())
  shot("skins_tab_path_imported.png")

  love.window.setMode(520, 760, { resizable = true, highdpi = true })
  U.wait(3)
  shot("skins_tab_narrow.png")

  U.log("done")
  love.event.quit()
  while true do coroutine.yield() end
end
