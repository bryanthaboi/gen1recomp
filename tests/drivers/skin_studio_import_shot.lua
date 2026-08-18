-- Driver: imports a bezel image into a fresh skin through the studio's Import
-- button and shoots the result, with the native dialog stubbed out (the real
-- one blocks on osascript / zenity / PowerShell).  Also covers button art and
-- the drag-and-drop path.
--   SHOT_DIR=/tmp/studioimport POKEPORT_DRIVER=tests/drivers/skin_studio_import_shot.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Studio = require("src.ui.SkinStudio")
  local FilePicker = require("src.core.FilePicker")
  local TouchSkin = require("src.core.TouchSkin")

  local dir = os.getenv("SHOT_DIR") or "/tmp/studioimport"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1440, 900, { resizable = true, highdpi = true })
  U.wait(2)

  local pending = nil
  love.draw = function()
    Studio.draw()
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
      coroutine.yield()
    end
    U.wait(3)
    local f = io.open(dir .. "/" .. name, "rb")
    U.log(f and "shot" or "FAIL shot", name)
    if f then f:close() end
  end

  Studio.load({ version = "red", onClose = function() end })
  U.wait(3)
  -- start from New so the run does not depend on the saved skin choice
  Studio.skin = TouchSkin.newSkin("import_probe")
  Studio.skinIdField = "import_probe"
  Studio.pageIndex, Studio.selected, Studio.images = 1, nil, {}
  U.log("skin:", Studio.skin.id, "bezel:", tostring(Studio.page().imagePath))

  -- what the native dialog would hand back
  local picked = "assets/skins/gb_anim/img/gb_back.png"
  local realOpen = FilePicker.open
  FilePicker.open = function(prompt, kind)
    U.log("picker prompt:", prompt, "exts:", table.concat(kind.exts, "/"))
    return picked
  end

  Studio.importImageFile("bezel")
  U.log("status:", tostring(Studio.status))
  U.log("bezel now:", tostring(Studio.page().imagePath),
        "loaded:", tostring(Studio.page().image ~= nil))
  U.log("skin root:", Studio.skin.root)
  U.log("file on disk:",
        tostring(love.filesystem.getInfo(Studio.skin.root .. "/img/gb_back.png") ~= nil))
  local viewport = Studio.page().viewport
  U.log("viewport left alone:", viewport and
    ("%.3f %.3f %.3f %.3f"):format(viewport.x, viewport.y, viewport.w, viewport.h)
    or "none")
  shot("import_bezel.png")

  -- button art goes onto the selected control, not the page
  Studio.addControl()
  FilePicker.open = function() return "assets/skins/gb_anim/img/gbc_a.png" end
  Studio.importImageFile("idle")
  local ctl = Studio.selectedControl()
  U.log("idle art:", tostring(ctl.imagePath),
        "bezel untouched:", tostring(Studio.page().imagePath))
  FilePicker.open = function() return "assets/skins/gb_anim/img/gbc_b.png" end
  Studio.importImageFile("pressed")
  U.log("pressed art:", tostring(ctl.pressedImagePath))
  shot("import_button_art.png")

  -- cancelling the dialog changes nothing
  local before = Studio.page().imagePath
  FilePicker.open = function() return nil end
  Studio.importImageFile("bezel")
  U.log("after cancel:", tostring(Studio.page().imagePath),
        "unchanged:", tostring(before == Studio.page().imagePath))

  -- the drop path shares the import, and refuses non-art
  Studio.imageTarget = "bezel"
  local raw = love.filesystem.read("assets/skins/tv_crt/img/tv-integer.png")
  Studio.filedropped({
    getFilename = function() return "/tmp/tv_frame.png" end,
    open = function() return true end,
    read = function() return raw end,
    close = function() return true end,
  })
  U.log("dropped bezel:", tostring(Studio.page().imagePath))
  Studio.filedropped({
    getFilename = function() return "/tmp/notes.txt" end,
    open = function() return true end,
    read = function() return "nope" end,
    close = function() return true end,
  })
  U.log("after dropping a txt:", tostring(Studio.page().imagePath),
        "status:", tostring(Studio.status))
  shot("import_dropped.png")

  love.window.setMode(760, 900, { resizable = true, highdpi = true })
  U.wait(3)
  shot("import_narrow.png")

  FilePicker.open = realOpen
  local saved = TouchSkin.find("import_probe")
  U.log("skin discoverable:", tostring(saved ~= nil))
  Studio.unload()
  U.log("done")
  love.event.quit()
  while true do coroutine.yield() end
end
