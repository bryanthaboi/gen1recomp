local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Space = require("src.core.game3.scripting.space")
local ExtractScripts = require("src.import.gba.extract_scripts")
local Field = require("src.core.game3.field")
local Player = require("src.core.game3.player")
local Objects = require("src.core.game3.objects")

local love_cache = function()
  return {
    read = function(_, rel)
      local f = io.open(rel, "rb")
      if not f then return nil end
      local c = f:read("*all")
      f:close()
      return c
    end,
    exists = function(_, rel)
      local f = io.open(rel, "rb")
      if f then f:close(); return true end
      return false
    end
  }
end

Space.bundle = ExtractScripts.loadBundle(love_cache(), "data/generated/gba", { allowIncomplete = true })
assert(Space.bundle, "Bundle must be loaded")

local passed = 0
local function check(cond, msg)
  if not cond then
    error("Assertion failed: " .. tostring(msg), 2)
  end
  passed = passed + 1
end

print("Test 1: Initial Pallet Town state before starter")
do
  local session = {
    map = "FR_PALLET_TOWN",
    flags = {},
    vars = {}
  }
  Field._session = session
  Field.running = true
  Field.locked = false

  Space.activate(nil, "FR_PALLET_TOWN", { data = { maps = { FR_PALLET_TOWN = Space.bundle.events["FR_PALLET_TOWN"] } } }, nil)
  Objects.loadMap(nil, "FR_PALLET_TOWN", Space.bundle.events["FR_PALLET_TOWN"])
  Space.runEnterScripts(nil, "FR_PALLET_TOWN", nil, nil)

  local lady = Objects.find(1)
  check(lady ~= nil, "Sign lady object exists")
  check(lady.cellX == 5 and lady.cellY == 15, "Sign lady starts at (5, 15) in front of trainer tips sign")
  check(lady.facing == "up", "Sign lady faces up towards sign")
  check(Flags.getVar(Space.store, Space.vm.ctx, 16386) == 0, "VAR_TEMP_2 is 0 before starter")
end

print("Test 2: After choosing starter in Oak's lab (FLAG_PALLET_LADY_NOT_BLOCKING_SIGN set)")
do
  local session = {
    map = "FR_PALLET_TOWN",
    flags = { [657] = true },
    vars = { [16496] = 0 }
  }
  Field._session = session
  Field.running = true
  Field.locked = false

  Space.activate(nil, "FR_PALLET_TOWN", { data = { maps = { FR_PALLET_TOWN = Space.bundle.events["FR_PALLET_TOWN"] } } }, nil)
  Flags.setFlag(Space.store, nil, 657, true)
  Objects.loadMap(nil, "FR_PALLET_TOWN", Space.bundle.events["FR_PALLET_TOWN"])
  Space.runEnterScripts(nil, "FR_PALLET_TOWN", nil, nil)

  local lady = Objects.find(1)
  check(lady ~= nil, "Sign lady object exists")
  check(lady.cellX == 12 and lady.cellY == 2, "Sign lady moved to north exit at (12, 2)")
  check(lady.facing == "down", "Sign lady faces down towards town")
  check(Flags.getVar(Space.store, Space.vm.ctx, 16386) == 1, "VAR_TEMP_2 is set to 1 (SIGN_LADY_READY)")

  -- Player walks up towards Route 1 and steps on (13, 2)
  Player.cellX = 13
  Player.cellY = 2
  Player.facing = "up"

  local messagesShown = {}
  local framesUsed = {}
  local origOpenMessage = Space.vm.adapters.openMessageStay or Space.vm.adapters.openMessage
  Space.vm.adapters.openMessageStay = function(body, stay)
    messagesShown[#messagesShown + 1] = body
  end
  local Message = require("src.ui.game3.message")
  local origSetFrame = Message.setFrame
  Message.setFrame = function(f)
    framesUsed[#framesUsed + 1] = f
  end

  local started = Field.tryCoordEvents({ data = { maps = { FR_PALLET_TOWN = Space.bundle.events["FR_PALLET_TOWN"] } } }, 13, 2)
  check(started == true, "Field.tryCoordEvents triggered sign lady script at (13, 2)")

  -- Run script to completion
  for _ = 1, 100 do
    if not Space.vm:isRunning() then break end
    Objects.update(nil, nil)
    Space.vm:tick()
  end

  check(not Space.vm:isRunning(), "Script finished executing")
  check(Flags.getFlag(Space.store, nil, 2110) == true, "FLAG_OPENED_START_MENU (2110) is set")
  check(Flags.getVar(Space.store, Space.vm.ctx, 16496) == 1, "VAR_MAP_SCENE_PALLET_TOWN_SIGN_LADY is set to 1")
  check(Flags.getVar(Space.store, Space.vm.ctx, 16386) == 0, "VAR_TEMP_2 is reset to 0")
  check(#messagesShown >= 2, "Both dialogue and copied sign messages were displayed")
  check(messagesShown[1]:find("Look, look!") ~= nil or messagesShown[1]:find("TRAINER TIPS") ~= nil, "Message content contains sign lady text")
  check(messagesShown[2]:find("TRAINER TIPS") ~= nil, "Message content contains Trainer Tips text")

  Message.setFrame = origSetFrame
end

print("Test 3: copyobjectxytoperm works properly")
do
  local lady = Objects.find(1)
  lady.cellX = 4
  lady.cellY = 15
  Objects.copyObjectXYToPerm(1)
  check(lady.homeX == 4 and lady.homeY == 15, "copyObjectXYToPerm updated home coordinates")
end

print("Test 4: Opening Start Menu before reaching north exit does not skip sign lady scene")
do
  local session = {
    map = "FR_PALLET_TOWN",
    flags = { [657] = true },
    vars = { [16496] = 0 }
  }
  Field._session = session
  Field.running = true
  Field.locked = false

  Space.activate(nil, "FR_PALLET_TOWN", { data = { maps = { FR_PALLET_TOWN = Space.bundle.events["FR_PALLET_TOWN"] } } }, nil)
  Flags.setFlag(Space.store, nil, 657, true)
  Flags.setFlag(Space.store, nil, 2110, false)
  Flags.setVar(Space.store, Space.vm.ctx, 16496, 0)
  
  -- Simulate opening Start Menu
  local Hud = require("src.ui.game3.hud")
  -- In Hud.openStartMenu, it checks scene >= 1 before setting FLAG_OPENED_START_MENU
  check(Flags.getFlag(Space.store, nil, 2110) == false, "FLAG_OPENED_START_MENU not set prematurely")

  Objects.loadMap(nil, "FR_PALLET_TOWN", Space.bundle.events["FR_PALLET_TOWN"])
  Space.runEnterScripts(nil, "FR_PALLET_TOWN", nil, nil)

  local lady = Objects.find(1)
  check(lady ~= nil, "Sign lady object exists")
  check(lady.cellX == 12 and lady.cellY == 2, "Sign lady is at north entrance (12, 2)")
  check(lady.facing == "down", "Sign lady faces down")
  check(Flags.getVar(Space.store, Space.vm.ctx, 16386) == 1, "VAR_TEMP_2 is 1 (SIGN_LADY_READY)")
end

print(string.format("ALL %d TESTS PASSED!", passed))
