package.path = "./?.lua;./?/init.lua;" .. package.path

local phase, root = arg[1], arg[2]
assert(phase == "write" or phase == "recover", "phase must be write or recover")
assert(type(root) == "string" and root ~= "", "test needs a persistence root")

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function full(path) return root .. "/" .. path end
local fs = {}

function fs.createDirectory(path)
  local status = os.execute("mkdir -p " .. quote(full(path)))
  return status == 0 or status == true
end

function fs.write(path, body)
  local parent = path:match("^(.*)/[^/]+$")
  if parent then assert(fs.createDirectory(parent)) end
  local handle, err = io.open(full(path), "wb")
  if not handle then return false, err end
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
  local handle = io.open(full(path), "rb")
  if not handle then return nil end
  handle:close()
  return { type = "file" }
end

function fs.getSaveDirectory() return root end

love = require("tests.love_stub")
love.filesystem = fs

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
SaveData.portableFs = function() return nil end
SaveData.resetSlotState()

if phase == "write" then
  local save = SaveData.newGame({ version = "red", playerName = "FIRST" })
  assert(SaveData.save(save))
  save.player.name = "SECOND"
  assert(SaveData.save(save))
  assert(fs.getInfo("save.lua.bak"), "second save did not roll a backup")
  print("save restart write: PASS")
else
  assert(fs.write("save.lua", "return { this is corrupt"))
  local save, recovered = SaveData.load("red")
  assert(save and save.player.name == "FIRST",
    "cold process did not recover the last verified save")
  assert(recovered == "bak", "load did not report backup recovery")
  -- The first cold read also migrates a legacy flat save into slot1.  Resolve
  -- the active filename after load so this checks the file gameplay now owns.
  local active = SaveData.saveFilename("red")
  local healed = SaveSerializer.decode(assert(fs.read(active)))
  assert(healed and healed.player.name == "FIRST",
    "recovery did not heal the main save")

  -- Negative path: when every durable copy is corrupt, loading must return
  -- nil instead of executing or manufacturing partially parsed progress.
  assert(fs.write(active, "return os.execute('false')"))
  assert(fs.write(active .. ".bak", "not lua at all"))
  fs.remove(active .. ".tmp")
  SaveData.resetSlotState()
  assert(SaveData.load("red") == nil,
    "unrecoverable save corruption must fail closed")
  print("save restart recovery + negative corruption: PASS")
end
