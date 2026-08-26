-- The six .VarActionTable rows Crystal appends past VAR_SPECIALPHONECALL, and
-- TryQuickSave -- the save Link_SaveGame runs behind the Battle Tower desk.
-- ROM-free:
--   luajit tests/gen2_crystal_vars_test.lua
--
-- ../pokecrystal/constants/script_constants.asm:69-74,
-- ../pokecrystal/engine/overworld/variables.asm:62-67,
-- engine/link/link.asm:2356 and engine/menus/save.asm:63.
--
-- The point of the World half is that these reads and writes land in the SAVE.
-- World.scriptVars is rebuilt empty on every map load (src/world/gen2/World.lua
-- :579), so a var parked there is a var Buena's Blue Card loses the moment the
-- player walks out of the Radio Tower.
package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or { random = function(a, b) return b and a or 1 end }
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
}
love.timer = love.timer or { getTime = function() return 0 end }

local S = require("tests.harness").suite("gen2 crystal vars")
local check, eq = S.check, S.eq

require("src.core.Logger").warn = function() end

local Apricorns = require("src.core.gen2.Apricorns")
local Events = require("src.world.gen2.Events")
local Save = require("src.core.gen2.Save")
local SaveSerializer = require("src.core.SaveSerializer")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")
local World = require("src.world.gen2.World")

local H = Specials.HANDLERS

-- ../pokecrystal/constants/script_constants.asm:69-74.
local VAR_BT_WIN_STREAK = 0x15
local VAR_KURT_APRICORNS = 0x16
local VAR_CALLERID = 0x17
local VAR_BLUECARDBALANCE = 0x18
local VAR_BUENASPASSWORD = 0x19
local VAR_KENJI_BREAK = 0x1a

-- ---------------------------------------------------------------- fixtures

local DATA = {
  audio = {},
  items = {
    LEVEL_BALL = { index = 5, name = "LEVEL BALL" },
    RED_APRICORN = { index = 78, name = "RED APRICORN" },
    BLU_APRICORN = { index = 79, name = "BLU APRICORN" },
  },
  pokemon = {},
  moves = {},
}

local function newSave()
  local save = {
    version = "crystal",
    player = { name = "KRIS", id = 0x1234, money = 0 },
    party = {},
    inventory = {},
    bagOrder = {},
    boxes = {},
  }
  Save.crystalState(save)
  Save.battleTowerState(save)
  return save
end

local function newWorld(save)
  local game = { data = DATA, save = save, stack = nil }
  local world = World.new(game)
  world.vm = { curPhoneCaller = 0 }
  return world, game
end

-- ============================================ the ids, against the cart's own
do
  local save = newSave()
  local world = newWorld(save)
  -- .VarActionTable is walked by index, so a row in the wrong slot reads a
  -- different variable.  Pin the six by writing a distinct value into each
  -- store and reading it back through the id the script byte carries.
  Save.battleTowerState(save).streak = 4
  save.kurtApricornQuantity = 3
  world.vm.curPhoneCaller = 11
  Save.crystalState(save).buenaPassword.balance = 17
  Save.crystalState(save).buenaPassword.word = 0x52
  Save.crystalState(save).kenjiBreak = 5

  eq(world:readVar(VAR_BT_WIN_STREAK), 4, "$15 is wNrOfBeatenBattleTowerTrainers")
  eq(world:readVar(VAR_KURT_APRICORNS), 3, "$16 is wKurtApricornQuantity")
  eq(world:readVar(VAR_CALLERID), 11, "$17 is wCurCaller")
  eq(world:readVar(VAR_BLUECARDBALANCE), 17, "$18 is wBlueCardBalance")
  eq(world:readVar(VAR_BUENASPASSWORD), 0x52, "$19 is wBuenasPassword")
  eq(world:readVar(VAR_KENJI_BREAK), 5, "$1a is wKenjiBreakTimer")
  -- NUM_VARS' own guard: nothing above the table answers with a neighbour.
  eq(world:readVar(0x1b), 0, "$1b is past the table and reads 0")
end

-- ================================================= the three writable rows
--
-- ../pokecrystal/engine/overworld/variables.asm:21-25: only a RETVAR_ADDR_DE
-- row hands `Script_writevar` the variable's own address.  The other three
-- rows write wStringBuffer2, which nothing reads back.
do
  local save = newSave()
  local world = newWorld(save)

  world:writeVar(VAR_BLUECARDBALANCE, 6)
  eq(Save.crystalState(save).buenaPassword.balance, 6,
    "writevar VAR_BLUECARDBALANCE lands in the save")
  eq(world:readVar(VAR_BLUECARDBALANCE), 6, "and reads straight back")

  world:writeVar(VAR_BUENASPASSWORD, 0x31)
  eq(Save.crystalState(save).buenaPassword.word, 0x31,
    "writevar VAR_BUENASPASSWORD lands in the save")

  world:writeVar(VAR_CALLERID, 9)
  eq(world.vm.curPhoneCaller, 9, "loadvar VAR_CALLERID parks wCurCaller")
  eq(world:readVar(VAR_CALLERID), 9, "and the callee scripts read it back")

  Save.battleTowerState(save).streak = 2
  world:writeVar(VAR_BT_WIN_STREAK, 99)
  eq(Save.battleTowerState(save).streak, 2,
    "a RETVAR_STRBUF2 row is not writable")
  eq(world:readVar(VAR_BT_WIN_STREAK), 2, "so the streak is unchanged")

  -- One byte wide, `ld [de], a`.
  world:writeVar(VAR_BLUECARDBALANCE, 300)
  eq(world:readVar(VAR_BLUECARDBALANCE), 300 % 256, "the store is one byte")
end

-- =========================================== they survive a save and a reload
--
-- The whole bug: scriptVars is rebuilt empty at World.lua:579 and never
-- serialized, so a balance parked there is gone by the next map.
do
  local save = newSave()
  local world = newWorld(save)
  world:writeVar(VAR_BLUECARDBALANCE, 12)
  world:writeVar(VAR_BUENASPASSWORD, 0x24)

  eq(world.scriptVars[VAR_BLUECARDBALANCE], 12,
    "the scratch mirror still holds it in this session")
  world.scriptVars = {}
  eq(world:readVar(VAR_BLUECARDBALANCE), 12,
    "and a map load that clears the mirror does not lose it")

  local reloaded = SaveSerializer.decode(SaveSerializer.encode(save))
  Save.normalize(reloaded)
  local second = newWorld(reloaded)
  eq(second:readVar(VAR_BLUECARDBALANCE), 12, "a reload still has the balance")
  eq(second:readVar(VAR_BUENASPASSWORD), 0x24, "and the day's password")
end

-- ============================ ../pokecrystal/maps/RadioTower2F.asm:144-146
--
--   readvar VAR_BLUECARDBALANCE / addval 1 / writevar VAR_BLUECARDBALANCE
--
-- run through the VM against a real World, which is the round trip the gate
-- caught reading `blue card balance: 0`.
do
  local save = newSave()
  local world = newWorld(save)
  local vm = Vm.new({}, {}, Events.new(), {
    readVar = function(id) return world:readVar(id) end,
    writeVar = function(id, value) world:writeVar(id, value) end,
  })
  local function awardPoint()
    vm:start({
      { op = "readvar", var = VAR_BLUECARDBALANCE },
      { op = "addval", args = { 1 } },
      { op = "writevar", var = VAR_BLUECARDBALANCE },
    })
    local guard = 0
    while vm:running() and guard < 64 do
      vm:update()
      guard = guard + 1
    end
    check(not vm:running(), "the three rows ran to the end")
  end
  awardPoint()
  eq(world:readVar(VAR_BLUECARDBALANCE), 1, "a correct password is worth 1")
  awardPoint()
  awardPoint()
  eq(Save.crystalState(save).buenaPassword.balance, 3,
    "three shows is three points, in the save")
end

-- ======================================= Kurt's quantity, the other dead var
--
-- ../pokecrystal/maps/KurtsHouse.asm:197 is
-- `verbosegiveitemvar LEVEL_BALL, VAR_KURT_APRICORNS`, so a var that reads 0
-- hands over nothing at all.
do
  local save = newSave()
  save.inventory = { RED_APRICORN = 1 }
  local world = newWorld(save)
  local quantities = {}
  local hooks = {
    save = function() return save end,
    data = function() return DATA end,
    itemName = function(id) return (DATA.items[id] or {}).name or id end,
    itemIndex = function(id) return (DATA.items[id] or {}).index end,
    setKurtApricornQuantity = function(n)
      quantities[#quantities + 1] = n
      world:setKurtApricornQuantity(n)
    end,
    scriptMenu = function(_header, onChoose) onChoose(1) end,
  }
  local vm = Vm.new({}, {}, Events.new(), { specials = hooks })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() H.SelectApricornForKurt(vm) end)
  local ok, err = coroutine.resume(vm.co)
  check(ok, "SelectApricornForKurt ran: " .. tostring(err))
  eq(quantities[1], 0, "kurt.asm:24 clears the byte on the way in")
  eq(quantities[2], 1, "and kurt.asm:45 records the apricorn it tossed")
  eq(world:readVar(VAR_KURT_APRICORNS), 1,
    "so verbosegiveitemvar hands over one ball, not none")
  eq(save.inventory.RED_APRICORN, nil, "the apricorn left the pack")
  -- .GaveKurtApricorns' own setevent, which the map script runs, not this
  -- handler: the count must not be conditioned on it.
  check(Apricorns.pending(save) == nil, "the event is still the script's to set")

  -- The cancel arm leaves the byte at zero, which is the `xor a` at :24.
  local cancelled = {}
  hooks.setKurtApricornQuantity = function(n) cancelled[#cancelled + 1] = n end
  hooks.scriptMenu = function(header, onChoose) onChoose(#header.items) end
  local vm2 = Vm.new({}, {}, Events.new(), { specials = hooks })
  vm2.showTextFn = function() end
  vm2.co = coroutine.create(function() H.SelectApricornForKurt(vm2) end)
  coroutine.resume(vm2.co)
  eq(#cancelled, 1, "a cancel writes the byte once")
  eq(cancelled[1], 0, "and leaves it at zero")
end

-- ========================== SampleKenjiBreakCountdown, the KENJI_BREAK writer
--
-- ../pokecrystal/engine/overworld/time.asm:136: `Random / and %11 / add 3`.
do
  eq(Specials.STUB_REASONS.SampleKenjiBreakCountdown, nil,
    "SampleKenjiBreakCountdown is no longer a stub")
  local save = newSave()
  local world = newWorld(save)
  local hooks = { setKenjiBreak = function(days) world:setKenjiBreak(days) end }
  local vm = Vm.new({}, {}, Events.new(), { specials = hooks })
  local seen = {}
  local priorRandom = Specials.random
  for roll = 1, 4 do
    Specials.random = function() return roll end
    H.SampleKenjiBreakCountdown(vm)
    seen[#seen + 1] = world:readVar(VAR_KENJI_BREAK)
  end
  Specials.random = priorRandom
  eq(table.concat(seen, ","), "3,4,5,6", "three to six days, inclusive")
  eq(Save.crystalState(save).kenjiBreak, 6, "and the countdown is in the save")
end

-- ================================================================ TryQuickSave
--
-- engine/link/link.asm:2356 -> engine/menus/save.asm:63 Link_SaveGame.
-- ../pokecrystal/maps/BattleTower1F.asm:84-85 is `special TryQuickSave /
-- iffalse Script_Menu_ChallengeExplanationCancel`, so a FALSE here is a challenge that
-- never starts.
do
  eq(Specials.STUB_REASONS.TryQuickSave, nil, "TryQuickSave is no longer a stub")
  eq(Specials.HANDLER_SOURCE.TryQuickSave, "Specials.lua",
    "and Specials.lua owns the handler")
end

local function runQuickSave(opts)
  local save = newSave()
  local log = { writes = 0, sfx = {} }
  local hooks = {
    save = function() return save end,
    data = function() return DATA end,
    saveFileState = function() return opts.exists, opts.sameId end,
    writeSave = function()
      log.writes = log.writes + 1
      return opts.writeOk ~= false
    end,
    playSfxNamed = function(name) log.sfx[#log.sfx + 1] = name end,
  }
  local vm = Vm.new({}, {}, Events.new(), { specials = hooks })
  vm.showTextFn = function() end
  local pages, holds, asked = {}, {}, 0
  local co = coroutine.create(function() H.TryQuickSave(vm) end)
  vm.co = co
  local send
  while true do
    local ok, req = coroutine.resume(co, send)
    if not ok then error(req, 0) end
    if coroutine.status(co) == "dead" then break end
    send = nil
    if type(req) == "table" and req.kind == "text" then
      pages[#pages + 1] = req.text
      holds[#holds + 1] = req.hold or 0
    elseif type(req) == "table" and req.kind == "yesorno" then
      asked = asked + 1
      send = opts.answers and opts.answers[asked]
    else
      error("TryQuickSave parked on " .. tostring(req and req.kind), 0)
    end
  end
  log.pages, log.holds, log.asked = pages, holds, asked
  log.scriptVar = vm.scriptVar
  return log
end

-- .yoursavefile: an existing file with this player's ID.
do
  local log = runQuickSave({ exists = true, sameId = true, answers = { true } })
  eq(log.asked, 1, "AskOverwriteSaveFile asks once")
  check(log.pages[1]:find("already a", 1, true) ~= nil,
    "AlreadyASaveFileText is the question: " .. tostring(log.pages[1]))
  eq(log.writes, 1, "_SaveGameData ran")
  eq(log.scriptVar, 1, "and wScriptVar is TRUE")
  check(log.pages[2]:find("SAVING", 1, true) ~= nil, "SAVING page printed")
  eq(log.holds[2], 16 + 32, "held for save.asm:247 + :251")
  check(log.pages[3]:find("KRIS saved", 1, true) ~= nil,
    "SavedTheGameText names the player: " .. tostring(log.pages[3]))
  eq(log.holds[3], 30 + 30, "held for save.asm:269 + link.asm:2367")
  eq(log.sfx[1], "Sfx_Save", "SFX_SAVE rang")
end

-- .refused: `jr nz, .refused / scf`, which TryQuickSave turns into FALSE.
do
  local log = runQuickSave({ exists = true, sameId = true, answers = { false } })
  eq(log.asked, 1, "the question was asked")
  eq(log.writes, 0, "NO writes nothing")
  eq(log.scriptVar, 0, "and wScriptVar is FALSE")
  eq(#log.pages, 1, "no SAVING page follows a refusal")
end

-- The other ID: AnotherSaveFileText, and .erase rather than .ok.
do
  local log = runQuickSave({ exists = true, sameId = false, answers = { true } })
  check(log.pages[1]:find("another", 1, true) ~= nil,
    "AnotherSaveFileText: " .. tostring(log.pages[1]))
  eq(log.writes, 1, "and it still saves")
  eq(log.scriptVar, 1, "TRUE")
end

-- `ld a, [wSaveFileExists] / and a / jr z, .erase`: no file, no question.
do
  local log = runQuickSave({ exists = false, sameId = false })
  eq(log.asked, 0, "a first save is not asked to overwrite anything")
  eq(log.writes, 1, "it just writes")
  eq(log.scriptVar, 1, "TRUE")
end

-- The one refusal the cart has no equivalent for: a mod vetoing save.write.
do
  local log = runQuickSave({ exists = false, writeOk = false })
  eq(log.writes, 1, "the write was attempted")
  eq(log.scriptVar, 0, "a refused write is the same FALSE as a refused prompt")
end

-- ====================================== the World half of the two save hooks
do
  local save = newSave()
  local world, game = newWorld(save)
  local wrote = 0
  game.writeSave = function() wrote = wrote + 1 return true end
  check(world:writeSave() == true, "World:writeSave goes through Game2:writeSave")
  eq(wrote, 1, "exactly once")
  game.writeSave = function() return false end
  check(world:writeSave() == false, "and a vetoed write reports false")
  game.writeSave = nil
  check(world:writeSave() == false, "with no game there is nothing to write")

  local hooks = world:specialHooks()
  check(type(hooks.writeSave) == "function", "the writeSave hook is threaded")
  check(type(hooks.saveFileState) == "function", "so is saveFileState")
end

S.finish()
