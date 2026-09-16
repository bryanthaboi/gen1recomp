--   POKEPORT_IDENTITY=bsa2227port POKEPORT_DRIVER=tests/drivers/shaderfx_portable_paths.lua love /tmp/pm/lovegame
local U = require("tests.drivers.util")
local ShaderFX = require("src.render.ShaderFX")
local SaveData = require("src.core.SaveData")

return function(game)
  local fails = 0
  local function ok(cond, label)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. label)
  end

  U.wait(30)

  local saveDir = love.filesystem.getSaveDirectory()
  local base = SaveData.portableBaseDir and SaveData.portableBaseDir()
  print("saveDir=" .. tostring(saveDir))
  print("portableBaseDir=" .. tostring(base))
  print("presetDir=" .. tostring(ShaderFX.presetDir()))

  ok(base ~= nil, "portable.txt puts this install in portable mode")
  ok(base ~= saveDir, "the portable base and the save directory are different roots")

  love.filesystem.createDirectory("shaders")
  love.filesystem.createDirectory("shaders/handheld")
  ok(love.filesystem.write("shaders/handheld/probe.slangp", "#reference \"x\"\n"),
    "a preset written through love.filesystem lands in the save directory")

  local found
  for _, e in ipairs(ShaderFX.list()) do
    if e.name == "probe.slangp" then found = e end
  end
  ok(found ~= nil, "ShaderFX.list() enumerates the probe preset")
  if found then
    print("fullPath=" .. tostring(found.fullPath))
    local f = io.open(found.fullPath, "rb")
    ok(f ~= nil, "io.open(entry.fullPath) opens the file the bridge is handed")
    if f then f:close() end
  end

  love.filesystem.remove("shaders/handheld/probe.slangp")
  print(("shaderfx_portable_paths: %s"):format(fails == 0 and "ALL PASS" or (fails .. " FAILURES")))
  love.event.quit(fails == 0 and 0 or 1)
end
