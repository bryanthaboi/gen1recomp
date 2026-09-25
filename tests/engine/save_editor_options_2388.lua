package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

love = require("tests.love_stub")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end
local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local SessionLifecycle = require("src.core.SessionLifecycle")
local FsIo = require("tests.fs_io")
local Ops = require("Ops")
local App = require("App")

local fs = love.filesystem

local ffi = require("ffi")
local setVar
if ffi.os == "Windows" then
  ffi.cdef([[ int _putenv(const char *envstring); ]])
  setVar = function(name, value) ffi.C._putenv(name .. "=" .. value) end
else
  ffi.cdef([[
  int setenv(const char *name, const char *value, int overwrite);
  int unsetenv(const char *name);
  ]])
  setVar = function(name, value)
    if value == "" then ffi.C.unsetenv(name) else ffi.C.setenv(name, value, 1) end
  end
end
local originalDataDir = os.getenv("POKEPORT_DATA_DIR")
setVar("POKEPORT_DATA_DIR", "tests/fixture_data")

do
  local opts = SaveData.loadOptions()
  opts.battleLayout, opts.battleFit, opts.battleHud, opts.battleBg = "wide", "fixed", "extended", "world"
  opts.colors, opts.tilt = "og", 2
  SaveData.saveOptions(opts)
  local slotId = SaveData.createSlot("red")
  check(slotId ~= nil, "a red slot is created")
  SaveData.setActiveSlot("red", slotId)
  local before = fs.read("options.lua")
  check(type(before) == "string" and before:find("wide", 1, true) ~= nil, "options.lua holds WIDE before the edit")
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.options = { battleLayout = "og", battleBg = "white", colors = "gbc", tilt = 0, videoMode = "windowed" }
  check(SaveData.writeSlot("red", slotId, save) == true, "writeSlot writes the slot")
  eq(save.options.battleLayout, "og", "writeSlot leaves the caller's table alone")
  local slotBody = SaveData.readSlotSource("red", slotId)
  check(slotBody ~= nil, "the slot reads back")
  local slotTable = slotBody and SaveSerializer.decode(slotBody)
  check(slotTable ~= nil and slotTable.options == nil, "writeSlot strips options from a gen1 slot")
  eq(fs.read("options.lua"), before, "writeSlot does not touch options.lua")

  local tmpBase = os.tmpname()
  local tmpPath = tmpBase .. "-options-2388.lua"
  local f = io.open(tmpPath, "wb")
  f:write(slotBody)
  f:close()
  App.load(tmpPath, { version = "red", slotId = slotId, embedded = true, onClose = function() end })
  local s = App.getState()
  check(s ~= nil and s.loadError == false, "the editor opens the slot")
  Ops.addMoney(s, 10)
  s.save.pokedex = s.save.pokedex or {}
  s.save.pokedex.owned = s.save.pokedex.owned or {}
  s.save.pokedex.owned.PIKACHU = true
  s.dirty = true
  App.save()
  eq(fs.read("options.lua"), before, "App.save leaves options.lua byte-identical")
  pcall(SessionLifecycle.endEditorSession, { version = "red", app = App })
  eq(fs.read("options.lua"), before, "closing the editor leaves options.lua byte-identical")

  local rf = io.open(tmpPath, "rb")
  local edited = rf and rf:read("*a") or ""
  if rf then rf:close() end
  local editedTable = SaveSerializer.decode(edited)
  check(editedTable ~= nil, "the edited slot decodes")
  check(editedTable and editedTable.options == nil, "the edited slot has no options key")
  check(editedTable and editedTable.pokedex and editedTable.pokedex.owned
    and editedTable.pokedex.owned.PIKACHU == true, "the dex edit landed")

  check(SaveData.writeSlot("red", slotId, editedTable) == true, "the edited slot writes back")
  local loaded = SaveData.load("red")
  check(loaded ~= nil, "the edited slot loads")
  eq(loaded and loaded.options and loaded.options.battleLayout, "wide", "battle layout stays WIDE after an edit")
  eq(loaded and loaded.options and loaded.options.battleBg, "world", "battle bg stays WORLD after an edit")
  eq(loaded and loaded.options and loaded.options.battleHud, "extended", "battle hud stays EXTENDED after an edit")
  eq(loaded and loaded.options and loaded.options.colors, "og", "colors stay OG after an edit")
  eq(fs.read("options.lua") and SaveSerializer.decode(fs.read("options.lua")).battleLayout, "wide",
    "options.lua still says WIDE after the load")

  os.remove(tmpPath)
  os.remove(tmpBase)
  for _, bak in ipairs(FsIo.globPrefix(tmpPath .. ".bak-")) do os.remove(bak) end
end

do
  local slotId = SaveData.createSlot("firered")
  if slotId then
    local save = { engine = "game3", version = "firered", name = "RED", options = { textSpeed = 1, frameType = 3 } }
    check(SaveData.writeSlot("firered", slotId, save) == true, "writeSlot writes a firered slot")
    local back = SaveSerializer.decode(SaveData.readSlotSource("firered", slotId) or "")
    eq(back and back.options and back.options.frameType, 3, "a gen3 slot keeps its in-save options block")
  end
end

setVar("POKEPORT_DATA_DIR", originalDataDir or "")

print(string.format("save editor options 2388: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
