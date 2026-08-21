package.path = "./?.lua;./?/init.lua;" .. package.path

local phase, root = arg[1], arg[2]
assert(phase == "capture" or phase == "resume", "phase must be capture or resume")
assert(type(root) == "string" and root ~= "", "test needs a persistence root")

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function execOk(cmd)
  local status = os.execute(cmd)
  return status == 0 or status == true
end

local function full(path) return root .. "/" .. path end

local fs = {}
function fs.createDirectory(path)
  return execOk("mkdir -p " .. quote(full(path)))
end
function fs.write(path, body)
  local parent = path:match("^(.*)/[^/]+$")
  if parent then assert(fs.createDirectory(parent)) end
  local handle = assert(io.open(full(path), "wb"))
  handle:write(body)
  handle:close()
  return true
end
function fs.read(path)
  local handle = io.open(full(path), "rb")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end
function fs.remove(path)
  os.remove(full(path))
  return true
end
function fs.getInfo(path)
  if execOk("test -d " .. quote(full(path))) then
    return { type = "directory" }
  end
  local handle = io.open(full(path), "rb")
  if handle then handle:close(); return { type = "file" } end
  return nil
end
function fs.load(path)
  local body = fs.read(path)
  if not body then return nil, "no file: " .. path end
  return load(body, "@" .. path)
end
function fs.getDirectoryItems(path)
  local items = {}
  -- -print plus a basename in Lua, not -printf: that is a GNU extension and
  -- BSD find (macOS) fails the whole call, which silently emptied the listing
  -- and left the probe mod undiscovered.
  local pipe = io.popen("find " .. quote(full(path))
    .. " -mindepth 1 -maxdepth 1 -print 2>/dev/null")
  if pipe then
    for item in pipe:lines() do
      items[#items + 1] = item:match("[^/]+$") or item
    end
    pipe:close()
  end
  table.sort(items)
  return items
end
function fs.getSaveDirectory() return root end

love = require("tests.love_stub")
love.filesystem = fs

local Loader = require("src.mods.Loader")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameMethods = require("src.core.Game")
local StateStack = require("src.core.StateStack")

local function writeProbe(version)
  fs.write("mods/cold_start_probe/manifest.json",
    '{"id":"cold_start_probe","name":"cold start probe","version":"'
      .. version .. '",'
      .. '"entry":"main.lua","api":2,"profile":"content"}')
  -- mod.exports, not _G: a mod's globals are its own (src/mods/Sandbox.lua)
  fs.write("mods/cold_start_probe/main.lua", [[
return function(mod)
  mod.exports.version = "]] .. version .. [["
  mod.exports.storage = mod.storage
  mod.exports.checkpoints = mod.checkpoints
end
]])
end

local function writeBrokenProbe()
  fs.write("mods/cold_start_broken/manifest.json",
    '{"id":"cold_start_broken","name":"cold start broken","version":"1.0.0",'
      .. '"entry":"main.lua","api":2,"profile":"content"}')
  fs.write("mods/cold_start_broken/main.lua", [[
return function()
  error("deliberate cold-start entry failure")
end
]])
end

local function statusById(loader)
  local out = {}
  for _, entry in ipairs(loader:status().available) do out[entry.id] = entry end
  return out
end

local function runtime(save, title)
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local game
  local overworld = {
    map = { id = "PALLET_TOWN" },
    player = { cellX = 3, cellY = 6, facing = "down", surfing = false },
    scriptMoves = {}, pendingScripts = {}, parallelRunners = {}, parallelQueue = {},
    runner = { isRunning = function() return false end },
  }
  function overworld:captureSave(target)
    target.player.map, target.player.x, target.player.y = self.map.id,
      self.player.cellX, self.player.cellY
    target.player.facing, target.player.surfing = self.player.facing,
      self.player.surfing and true or false
  end
  function overworld:enter(mapId, x, y, facing)
    self.map = { id = mapId }
    self.player = { cellX = x, cellY = y, facing = facing,
      surfing = game.save.player.surfing and true or false }
    self.scriptMoves, self.pendingScripts = {}, {}
    self.parallelRunners, self.parallelQueue = {}, {}
    self.runner = { isRunning = function() return false end }
  end
  game = setmetatable({
    save = save, stack = stack, overworld = overworld,
    data = {
      pokemon = {}, moves = { TACKLE = { pp = 35 } }, items = { POTION = {} },
      constants = { fallbackMove = "TACKLE" },
      field = { boot = { startMap = "PALLET_TOWN", startX = 3, startY = 6 } },
      maps = { PALLET_TOWN = { id = "PALLET_TOWN", width = 10, height = 9 } },
    },
  }, { __index = GameMethods })
  stack.states[1] = title and { screenId = "TitleState" } or overworld
  if title then function game:makeTitleState() return { screenId = "TitleState" } end end
  return game
end

SaveData.resetSlotState()
local loader = Loader.new({ fs = fs })

if phase == "capture" then
  writeProbe("1.0.0")
  writeBrokenProbe()
  local game = runtime(SaveData.newGame({ version = "red" }), false)
  loader.game = game
  assert(loader:load({}) == false, "the broken disk mod must fail this boot")
  local probe = assert(loader.exports.cold_start_probe)
  assert(probe.version == "1.0.0")
  local status = statusById(loader)
  assert(status.cold_start_broken.state == "failed")
  assert(loader.exports.cold_start_broken == nil,
    "a failed disk mod must publish no exports")
  assert(probe.storage:write(game, "history/index", { newest = "q0001" }))
  local checkpoint = assert(probe.checkpoints:capture(game))
  assert(probe.storage:write(game, "history/q0001", checkpoint))
  local id = assert(game.save.meta.playthroughId)
  assert(probe.checkpoints:ensureNormalSave(game, checkpoint))
  local normal = assert(SaveData.load("red"))
  assert(normal.meta.playthroughId == id)
  fs.write("cold-start-witness.lua", SaveSerializer.encode({ playthroughId = id }))
  -- Simulate a mod update while the process is down.  The resume phase uses a
  -- fresh Loader and must discover the new file rather than retained modules.
  writeProbe("2.0.0")
  print("cold-start capture persisted")
else
  local title = runtime(SaveData.newGame({ version = "red" }), true)
  title.save.options = { volume = 7, bindings = {} }
  loader.game = title
  assert(loader:load({}) == false, "the broken disk mod remains isolated")
  local probe = assert(loader.exports.cold_start_probe)
  assert(probe.version == "2.0.0", "fresh process did not load updated mod")
  assert(statusById(loader).cold_start_broken.state == "failed")
  local selected = assert(probe.storage:selected(title))
  local witness = assert(SaveSerializer.decode(assert(fs.read("cold-start-witness.lua"))))
  assert(selected:context().playthroughId == witness.playthroughId)
  assert(selected:read("history/index").newest == "q0001")
  local checkpoint = assert(selected:read("history/q0001"))
  assert(probe.checkpoints:resume(title, checkpoint))
  assert(title.save.meta.playthroughId == witness.playthroughId)
  assert(title.save.options.volume == 7)
  assert(SaveSerializer.encode(probe.checkpoints:capture(title))
    == SaveSerializer.encode(checkpoint))
  local normal = assert(SaveData.load("red"))
  assert(normal.meta.playthroughId == witness.playthroughId)
  print("cold-start resume reconstructed")
end
