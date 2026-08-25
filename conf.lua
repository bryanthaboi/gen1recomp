function love.conf(t)
  -- PhysFS ignores symlinks unless told otherwise, so a mod dev-linked into
  -- mods/ (ln -s, matching the mklink /J workflow on Windows) is invisible
  -- to love.filesystem.getDirectoryItems without this.
  love.filesystem.setSymlinksEnabled(true)

  local editor = os.getenv("POKEPORT_EDITOR") == "1"
  local developer = os.getenv("POKEPORT_DEV") == "1"
  local companion = nil
  if arg then
    for _, a in ipairs(arg) do
      if a == "--editor" then editor = true end
      if a == "--developer" then developer = true end
      local port, token = a:match("^%-%-display%-companion=(%d+),([%w]+)$")
      if port then companion = { port = tonumber(port), token = token } end
    end
  end
  -- main.lua runs in the same Lua state right after conf.lua; stash the
  -- decision in a global so it doesn't need to reparse `arg`.
  _G.POKEPORT_EDITOR_MODE = editor
  _G.POKEPORT_DEV_MODE = developer
  _G.POKEPORT_DISPLAY_COMPANION = companion

  if companion then
    t.identity = "pokemon-love2d-companion"
    t.window.title = "gen1recomp Secondary Display"
    t.window.width = 640
    t.window.height = 576
    t.window.minwidth = 160
    t.window.minheight = 144
    t.window.resizable = true
  elseif editor then
    -- Same identity as the game, deliberately: the editor edits the game's
    -- saves and reads the game's ROM cache, both of which live under this
    -- folder.  A private editor identity would point love.filesystem at an
    -- empty directory in a packaged build, so `--editor` could not find
    -- data/generated at all (SaveIO.defaultPath already assumed this name).
    t.identity = os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"
    t.window.title = "Pokemon Save Editor"
    t.window.width = 1280
    t.window.height = 800
  else
    t.identity = os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"
    -- Version.lua has zero requires, so it is loadable this early; fall
    -- back to the plain title if the source is not mounted yet
    local ok, Version = pcall(require, "src.core.Version")
    t.window.title = ok and Version.title()
      or "gen1recomp"
    -- Open at the launcher's design size (the split-screen ROM selector is
    -- laid out for 1024x768). The window is resizable and the 160x144 game
    -- canvas letterboxes into whatever size it ends up, so this only sets the
    -- starting size, not the game's resolution.
    t.window.width = 1024
    t.window.height = 768
    -- Floor for the resizable desktop window.  The launcher's single-column
    -- layout is laid out against ~420 logical px of content, and the game
    -- canvas letterboxes fine below that, so this only stops a drag that would
    -- squeeze the cards past the point where their buttons still read.  Kept
    -- well under the smallest supported desktop display; mobile ignores it
    -- (fullscreen), so the handheld ports are unaffected.
    t.window.minwidth = 480
    t.window.minheight = 360
  end
  t.version = love._os == "iOS" and "12.0" or "11.5"
  t.window.vsync = 1
  t.modules.audio = not companion
  t.modules.joystick = not companion
  t.modules.physics = false
  -- love.sensor exposes raw accelerometer/gyroscope data (love.sensor.getData),
  -- independent of t.accelerometerjoystick below (which instead maps the
  -- accelerometer onto joystick axes and stays off -- see that flag's
  -- comment for why). Explicit here so a future effect (e.g. a tilt-driven
  -- reflective-screen look) has sensor data available without reviving #468.
  t.modules.sensor = true

  -- love.system is not loaded during love.conf; love._os is set by the
  -- engine before conf runs (LÖVE 11.x / 11.5).
  local osName = love._os
  local mobile = osName == "Android" or osName == "iOS"
  local nx = osName == "NX"
  if nx then
    -- Switch (love-nx): hint handheld 720p. SDL auto-switches portable↔dock
    -- (720p↔1080p) only when the window is resizable and not exclusive
    -- fullscreen; NxDisplay.sync also applies the size on boot and dock change.
    t.window.width = 1280
    t.window.height = 720
    t.window.fullscreen = false
    t.window.resizable = true
    t.window.highdpi = false
  elseif mobile then
    -- resizable is what unlocks orientation.  SDL's Android backend, given no
    -- SDL_HINT_ORIENTATIONS (LÖVE sets none), calls setRequestedOrientation
    -- at window creation -- FULL_SENSOR when the window is resizable (rotates
    -- freely to portrait or landscape), otherwise locked to the window's w/h
    -- aspect.  So a non-resizable tall window forced portrait; resizable lets
    -- the game follow the device.  The renderer letterboxes the 160x144
    -- viewport into whatever size results, and the on-screen touch controls
    -- re-lay themselves out from the new window size, so both orientations
    -- just work.  FULL_SENSOR ignores the device's rotation lock, so
    -- GameActivity.setOrientationBis remaps it to FULL_USER after SDL has
    -- run: same orientations allowed, but auto-rotate being off now wins.
    -- A persisted ORIENTATION lock (#592) overrides all of this after boot:
    -- src/core/Orientation.lua sets SDL_HINT_ORIENTATIONS over the FFI and
    -- re-triggers the request, from main.lua for the launcher and from
    -- Game:applyOptions in game.
    -- iOS follows the Info.plist orientations
    -- (see mobile/ios/overlays/love-ios.plist, now portrait + landscape).
    t.window.resizable = true
    -- Starting size is a tall portrait hint; the OS resizes to the real
    -- display and rotations resize again. highdpi is required for Retina iOS
    -- (Android always behaves as highdpi).
    t.window.width = 1080
    t.window.height = 1920
    t.window.fullscreen = true
    t.window.highdpi = true
    -- Android only (irrelevant on iOS): puts the save directory under the
    -- app's external-files folder, which is readable/writable via USB or a
    -- file manager with no runtime permission, so RomImporter can ask the
    -- player to copy their ROM there instead of needing a native file
    -- picker (LOVE 11.5 on Android has none -- see src/import/RomImporter.lua).
    t.externalstorage = osName == "Android"
    -- LOVE 11.x exposes the phone's accelerometer as a 3-axis joystick by
    -- default.  Gravity keeps one axis pinned near +/-1.0 whenever the phone
    -- is held upright, so it streams past-deadzone joystickaxis events that
    -- both hid the touch overlay every instant (it reads as "a controller is
    -- in use") and, via the generic-joystick axis mapping (#459), walked the
    -- player around by tilt.  Nothing in the game reads the accelerometer,
    -- so drop the device entirely (#468).
    t.accelerometerjoystick = false
  else
    t.window.resizable = true
  end
end
