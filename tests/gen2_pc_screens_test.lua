-- The Pokecenter PC and the player's item PC.
--
--   luajit tests/gen2_pc_screens_test.lua        (GOLD_CACHE for the map runs)
--
-- Three layers, matching how the cart reaches them:
--
--   * World:interact's CheckFacingTileForStdScript arm
--     (engine/events/std_collision.asm): an A press on a COLL_PC tile runs
--     PCScript out of std_scripts, which is the ONLY way any Pokecenter PC
--     opens -- no Pokecenter map carries a PC bg event.
--   * CenterPcMenu (engine/events/pokecenter_pc.asm PokemonCenterPC): the
--     whose-PC list and its .ChooseWhichPCListToUse gating, the party gate,
--     and the rows it opens.
--   * ItemPcMenu (_PlayersPC + the PlayerWithdraw/Deposit/TossItemMenu rows):
--     items moving bag <-> save.pcItems for real, with the cart's caps and
--     refusals.
--
-- With a GOLD_CACHE the whole chain runs on the real Cherrygrove Pokecenter
-- and the real bedroom map: a real Map, a real Vm over the extracted scripts,
-- and World:openPc pushing the real screens.

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
  setLineWidth = function() end,
}
love.math = love.math or {
  random = function(a, b)
    if b then return a end
    return a and 1 or 0.5
  end,
}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

require("src.core.Logger").warn = function() end

local S = require("tests.harness").suite("gen2 pc screens")
local check, eq = S.check, S.eq

local Bag = require("src.inventory.Bag")
local CenterPcMenu = require("src.ui.gen2.CenterPcMenu")
local ItemPcMenu = require("src.ui.gen2.ItemPcMenu")
local Map = require("src.world.gen2.Map")
local Save = require("src.core.gen2.Save")
local Screens = require("src.ui.Screens")
local Vm = require("src.script.gen2.Vm")
local World = require("src.world.gen2.World")

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local ITEMS = {
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 2,
    canToss = true },
  ANTIDOTE = { id = "ANTIDOTE", name = "ANTIDOTE", pocket = "ITEM", index = 9,
    canToss = true },
  BICYCLE = { id = "BICYCLE", name = "BICYCLE", pocket = "KEY_ITEM", index = 6,
    canToss = false },
  HM_CUT = { id = "HM_CUT", name = "HM01", pocket = "TM_HM", index = 0xf3,
    canToss = false },
  TM_HEADBUTT = { id = "TM_HEADBUTT", name = "TM02", pocket = "TM_HM",
    index = 0xea, canToss = true, teaches = "HEADBUTT" },
}

local function newGame(save, items)
  local input = newInput()
  return {
    input = input,
    save = save,
    data = { audio = {}, pokemon = {}, items = items or ITEMS },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }, input
end

local function newSave(partySize)
  local save = Save.newGame({ playerName = "GOLD", trainerId = 1234 })
  for i = 1, partySize or 1 do
    save.party[i] = { species = "CYNDAQUIL", nickname = "MON" .. i,
      hp = 20, maxHp = 20, level = 10 }
  end
  return save
end

-- Drive a screen: press the buttons one at a time, updating after each.
local function press(screen, input, ...)
  for _, button in ipairs({ ... }) do
    input:press(button)
    screen:update(0)
  end
end

local function entryIds(entries)
  local ids = {}
  for _, entry in ipairs(entries) do ids[#ids + 1] = entry.id end
  return table.concat(ids, ",")
end

-- ------------------------------------------------- the ids resolve

Screens.invalidate()
local sg = { data = {} }
eq(Screens.get(sg, "Gen2CenterPcMenu"), CenterPcMenu,
  "Gen2CenterPcMenu resolves to its builtin")
eq(Screens.get(sg, "Gen2ItemPcMenu"), ItemPcMenu,
  "Gen2ItemPcMenu resolves to its builtin")

-- ------------------------------------------------- the whose-PC gating

-- PCPC_BEFORE_POKEDEX: three rows.
do
  local save = newSave(1)
  local game, input = newGame(save)
  local pc = CenterPcMenu.new(game, { save = save, onClose = function() end })
  check(pc.message ~= nil, "the PC boots with the turn-on line")
  press(pc, input, "a")
  eq(pc.message, nil, "which one A clears")
  eq(entryIds(pc.entries), "bills,players,turnoff",
    "no #DEX: BILL's PC / <PLAYER>'s PC / TURN OFF")
  eq(pc.entries[2].label, "GOLD's PC", "the item PC row carries the name")
end

-- PCPC_BEFORE_HOF: PROF.OAK's PC appears with CheckReceivedDex.
do
  local save = newSave(1)
  save.engineFlags = { [CenterPcMenu.ENGINE_POKEDEX] = true }
  local game = newGame(save)
  local pc = CenterPcMenu.new(game, { save = save })
  eq(entryIds(pc.entries), "bills,players,oaks,turnoff",
    "with the #DEX the OAK row slots in above TURN OFF")
end

-- PCPC_POSTGAME: HALL OF FAME appears once wHallOfFameCount is non-zero.
do
  local save = newSave(1)
  save.engineFlags = { [CenterPcMenu.ENGINE_POKEDEX] = true }
  save.hallOfFame.count = 1
  local game = newGame(save)
  local pc = CenterPcMenu.new(game, { save = save })
  eq(entryIds(pc.entries), "bills,players,oaks,hof,turnoff",
    "a champion sees all five rows")
end

-- PC_CheckPartyForPokemon: no party, no PC.
do
  local save = newSave(0)
  local game, input = newGame(save)
  local closed = false
  local pc = CenterPcMenu.new(game, { save = save,
    onClose = function() closed = true end })
  check(pc.message ~= nil, "an empty party gets the Bzzzzt! refusal")
  press(pc, input, "a")
  check(closed, "and the PC never opens")
  eq(#game.stack._items, 0, "nothing was pushed")
end

-- ------------------------------------------------- the rows open the screens

-- <PLAYER>'s PC opens the item PC (PLAYERSPC_NORMAL).
do
  local save = newSave(1)
  local game, input = newGame(save)
  local pc = CenterPcMenu.new(game, { save = save })
  press(pc, input, "a")           -- boot line
  press(pc, input, "down", "a")   -- <PLAYER>'s PC
  check(pc.message ~= nil, "PokecenterPlayersPCText comes up first")
  press(pc, input, "a", "a")      -- both pages
  local top = game.stack:top()
  check(top ~= nil, "then the item PC is pushed")
  eq(top and top.screenId, "Gen2ItemPcMenu", "as Gen2ItemPcMenu")
  eq(entryIds(top.entries), "withdraw,deposit,toss,mailbox,logoff",
    "with _PlayersPC's PLAYERSPC_NORMAL rows, LOG OFF last")
end

-- BILL's PC opens the storage system with _BillsPC's own five rows.
do
  local save = newSave(1)
  local game, input = newGame(save)
  local pc = CenterPcMenu.new(game, { save = save })
  press(pc, input, "a")           -- boot line
  press(pc, input, "a")           -- BILL's PC (row 1)
  press(pc, input, "a", "a")      -- PokecenterBillsPCText, both pages
  local top = game.stack:top()
  eq(top and top.screenId, "Gen2PcMenu", "BILL's PC pushes the storage menu")
  eq(entryIds(top.entries), "withdraw,deposit,changebox,move,seeya",
    "with no MAIL BOX row: that lives on the item PC")
end

-- PROF.OAK's PC: the yes/no, the counts, the rating, the link-closed line.
do
  local save = newSave(1)
  save.engineFlags = { [CenterPcMenu.ENGINE_POKEDEX] = true }
  save.pokedex = { seen = { A = true, B = true, C = true },
    caught = { A = true, B = true } }
  local game, input = newGame(save)
  local pc = CenterPcMenu.new(game, { save = save })
  press(pc, input, "a")            -- boot line
  press(pc, input, "down", "down", "a") -- PROF.OAK's PC
  press(pc, input, "a", "a")       -- PokecenterOaksPCText, both pages
  check(pc.confirm ~= nil, "OakPCText1 asks for the yes/no")
  press(pc, input, "a")            -- YES
  check(pc.message ~= nil, "and the rating flow starts")
  local sawCounts, sawRating = false, false
  for _ = 1, 12 do
    if not pc.message then break end
    local page = pc.message.pages[pc.message.page]
    for _, line in ipairs(page) do
      if line == "3 #MON seen" then sawCounts = true end
      if line == "Look for #MON" then sawRating = true end
    end
    press(pc, input, "a")
  end
  check(sawCounts, "the counts page names 3 seen")
  check(sawRating, "2 owned lands on OakRating01")
  check(pc.closed == false, "the OAK flow drops back to the menu, not out")
end

-- TURN OFF: the Link closed line, then the shutdown.
do
  local save = newSave(1)
  local game, input = newGame(save)
  local closed = false
  local pc = CenterPcMenu.new(game, { save = save,
    onClose = function() closed = true end })
  press(pc, input, "a")            -- boot line
  press(pc, input, "up", "a")      -- TURN OFF (wraps to the last row)
  check(pc.message ~= nil, "TurnOffPC prints the Link closed line")
  press(pc, input, "a")
  check(closed, "and carries into .shutdown")
end

-- ------------------------------------------------- the item PC, for real

-- DEPOSIT: bag -> save.pcItems through the PACK chooser.
do
  local save = newSave(1)
  local game, input = newGame(save)
  check(Bag.add(save, "POTION", 5, game.data), "five POTIONs in the bag")
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  eq(pc.message, nil, "PLAYERSPC_NORMAL boots straight to the menu")
  press(pc, input, "down", "a")    -- DEPOSIT ITEM
  eq(pc.phase, "deposit", "DEPOSIT opens the PACK as a chooser")
  check(pc.pack ~= nil, "held by the screen, the way the mart sells")
  press(pc, input, "a")            -- choose POTION
  check(pc.qtyState ~= nil, "the quantity selector comes up")
  press(pc, input, "up")           -- 2
  press(pc, input, "a")            -- deposit x2
  eq(save.pcItems.POTION, 2, "two POTIONs land in the PC")
  eq(save.inventory.POTION, 3, "and leave the bag")
  check(pc.message ~= nil, "with _PlayersPCDepositItemsText up")
  eq(pc.message.pages[1][1], "Deposited 2", "naming the count")
  press(pc, input, "a")            -- clear it
  press(pc, input, "b")            -- close the PACK
  eq(pc.phase, "menu", "B drops back to the item PC menu")
end

-- The same DepositSellPack chooser holds a TM: it must reach the quantity
-- selector like everything tossable, never the teach party (issue #1243).
do
  local save = newSave(1)
  local game, input = newGame(save)
  Bag.add(save, "TM_HEADBUTT", 1, game.data)
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  press(pc, input, "down", "a")                 -- DEPOSIT ITEM
  press(pc, input, "right", "right", "right")  -- ITEM -> BALL -> KEY_ITEM -> TM_HM
  press(pc, input, "a")                         -- choose the TM
  check(pc.qtyState ~= nil, "a TM asks how many to deposit")
  eq(#game.stack._items, 0, "with no teach screen pushed over the pack")
  press(pc, input, "a")                         -- deposit x1
  eq(save.pcItems.TM_HEADBUTT, 1, "the TM lands in the PC")
  eq(save.inventory.TM_HEADBUTT, nil, "and leaves the bag")
end

-- .DepositItem: CANT_TOSS only skips .AskQuantity.  A KEY ITEM deposits x1,
-- and .Submenu withdraws it back the same way (issue #1486).
do
  local save = newSave(1)
  local game, input = newGame(save)
  Bag.add(save, "BICYCLE", 1, game.data)
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  press(pc, input, "down", "a")            -- DEPOSIT ITEM
  press(pc, input, "right", "right")       -- ITEM -> BALL -> KEY_ITEM pocket
  press(pc, input, "a")                    -- choose the BICYCLE
  eq(pc.qtyState, nil, "no quantity selector for a KEY ITEM")
  eq(save.pcItems.BICYCLE, 1, "the BICYCLE lands in the PC")
  eq(save.inventory.BICYCLE, nil, "and leaves the bag")
  eq(pc.message.pages[1][1], "Deposited 1", "_PlayersPCDepositItemsText")
  press(pc, input, "a")                    -- clear it
  press(pc, input, "b")                    -- close the PACK
  press(pc, input, "up", "a")              -- WITHDRAW ITEM
  eq(pc.phase, "withdraw", "the PC item list opens on the KEY ITEM")
  press(pc, input, "a")                    -- the BICYCLE row
  eq(pc.qtyState, nil, "no quantity selector on the way back either")
  eq(save.inventory.BICYCLE, 1, "the BICYCLE is back in the bag")
  eq(save.pcItems.BICYCLE, nil, "and out of the PC")
end

-- The TM_HM pocket's HMs are CANT_TOSS too, and deposit prompt-free x1.
do
  local save = newSave(1)
  local game, input = newGame(save)
  Bag.add(save, "HM_CUT", 1, game.data)
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  press(pc, input, "down", "a")                -- DEPOSIT ITEM
  press(pc, input, "right", "right", "right")  -- ITEM -> BALL -> KEY_ITEM -> TM_HM
  press(pc, input, "a")                        -- choose HM01
  eq(pc.qtyState, nil, "no quantity selector for an HM")
  eq(save.pcItems.HM_CUT, 1, "HM01 lands in the PC")
  eq(save.inventory.HM_CUT, nil, "and leaves the bag")
end

-- PlaceMenuItemQuantity: the PC list draws no xNN for a CANT_TOSS row.
do
  local save = newSave(1)
  local game = newGame(save)
  save.pcItems = { POTION = 3, HM_CUT = 1 }
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  local Chrome = require("src.ui.gen2.Chrome")
  local TIMES = "\xc3\x97"
  local saved = { print = Chrome.print, box = Chrome.box,
    cursor = Chrome.cursor }
  local printed = {}
  Chrome.print = function(text, x, y)
    printed[#printed + 1] = { text = text, x = x, y = y }
  end
  Chrome.box = function() end
  Chrome.cursor = function() end
  pc.phase = "withdraw"
  pc:rebuild()
  local drew, err = pcall(function() pc:drawList() end)
  Chrome.print, Chrome.box, Chrome.cursor = saved.print, saved.box, saved.cursor
  check(drew, "the PC list draws: " .. tostring(err))
  local rowY = {}
  for i, row in ipairs(pc.rows) do rowY[row.id] = i * 2 end
  local counts = {}
  for _, p in ipairs(printed) do
    if p.x == 7 then counts[p.y] = p.text end
  end
  eq(counts[rowY.POTION + 1], TIMES .. " 3", "the POTION stack keeps its xNN")
  eq(counts[rowY.HM_CUT + 1], nil,
    "and the HM row draws none (PlaceMenuItemQuantity .done)")
end

-- An empty bag never opens the PACK (.CheckItemsInBag).
do
  local save = newSave(1)
  local game, input = newGame(save)
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  press(pc, input, "down", "a")
  eq(pc.phase, "menu", "DEPOSIT refuses with nothing to deposit")
  eq(pc.message.pages[1][1], "No items here!", "with _PlayersPCNoItemsText")
end

-- WITHDRAW: save.pcItems -> bag, with the no-room refusal.
do
  local save = newSave(1)
  local game, input = newGame(save)
  save.pcItems = { POTION = 2 }
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  press(pc, input, "a")            -- WITHDRAW ITEM
  eq(pc.phase, "withdraw", "the PC item list opens")
  eq(pc.rows[1] and pc.rows[1].id, "POTION", "with the POTION stack on it")
  press(pc, input, "a")            -- choose it
  check(pc.qtyState ~= nil, "stackable: the selector asks how many")
  press(pc, input, "a")            -- x1
  eq(save.inventory.POTION, 1, "one POTION reaches the bag")
  eq(save.pcItems.POTION, 1, "one stays behind")
  eq(pc.message.pages[1][1], "Withdrew 1", "_PlayersPCWithdrewItemsText")
  press(pc, input, "a")

  -- Fill the ITEM pocket: ReceiveItem answers no-carry and the stack stays.
  Bag.remove(save, "POTION", 1)
  for i = 1, Bag.capacity(game.data, "ITEM") do
    check(Bag.add(save, "FILL_" .. i, 1, game.data), "filler " .. i .. " fits")
  end
  press(pc, input, "a", "a")   -- choose the POTION stack again, x1
  eq(pc.message.pages[1][1], "There's no room",
    "a full pocket is _PlayersPCNoRoomWithdrawText")
  eq(save.pcItems.POTION, 1, "and the stack never left the PC")
  press(pc, input, "a", "b")   -- clear, back to menu
end

-- TOSS: the quantity, the yes/no, the discard -- and the KEY ITEM refusal.
do
  local save = newSave(1)
  local game, input = newGame(save)
  save.pcItems = { POTION = 3, HM_CUT = 1 }
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  press(pc, input, "down", "down", "a")  -- TOSS ITEM
  eq(pc.phase, "toss", "the toss list opens")
  press(pc, input, "a")                  -- POTION (index 2 sorts it first)
  check(pc.qtyState ~= nil, "TossItemFromPC asks how many")
  press(pc, input, "up", "up", "a")      -- x3
  check(pc.confirm ~= nil, "then .ItemsThrowAwayText asks yes/no")
  eq(pc.confirm.prompt[1], "Throw away 3", "naming the count")
  press(pc, input, "a")                  -- YES
  eq(save.pcItems.POTION, nil, "the stack is discarded")
  eq(pc.message.pages[1][1], "Discarded", "_ItemsDiscardedText")
  press(pc, input, "a")

  press(pc, input, "a")                  -- the HM is the only row left
  eq(pc.qtyState, nil, "an HM never reaches the selector")
  eq(pc.message.pages[1][1], "That's too impor-",
    ".CantToss: _ItemsTooImportantText")
  press(pc, input, "a", "b")
end

-- The PC's fifty stacks (ReceiveItem over wNumPCItems).
do
  local save = newSave(1)
  local game, input = newGame(save)
  Bag.add(save, "POTION", 1, game.data)
  save.pcItems = {}
  for i = 1, ItemPcMenu.PC_ITEM_CAPACITY do save.pcItems["S" .. i] = 1 end
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS })
  press(pc, input, "down", "a")    -- DEPOSIT ITEM
  press(pc, input, "a")            -- choose POTION
  press(pc, input, "a")            -- x1
  eq(pc.message.pages[1][1], "There's no room to",
    "the fifty-first stack is _PlayersPCNoRoomDepositText")
  eq(save.inventory.POTION, 1, "and the POTION stays in the bag")
end

-- PLAYERSPC_HOUSE: the boot line, DECORATION, TURN OFF, and the answer out.
do
  local save = newSave(1)
  local game, input = newGame(save)
  local answered = nil
  local pc = ItemPcMenu.new(game, { save = save, items = ITEMS, house = true,
    onClose = function(changed) answered = changed end })
  check(pc.message ~= nil, "_PlayersHousePC opens on PlayersPCTurnOnText")
  press(pc, input, "a")
  eq(entryIds(pc.entries), "withdraw,deposit,toss,mailbox,decoration,turnoff",
    "PLAYERSPC_HOUSE carries DECORATION and ends on TURN OFF")
  -- The DECORATION row pushes the decoration menu and carries `changed` out.
  press(pc, input, "up", "up", "a")
  local top = game.stack:top()
  eq(top and top.screenId, "Gen2DecorationMenu", "DECORATION opens the menu")
  top.onDone(true)
  eq(pc.changedDecorations, true, "a moved decoration is remembered")
  press(pc, input, "b")
  eq(answered, true, "and answered out, for PlayersHousePCScript's iftrue")
end

-- ------------------------------------------------- the A press, wired

-- World:interact's CheckFacingTileForStdScript arm, on a stub map: COLL_PC
-- runs PCScript, COLL_RADIO runs Radio1Script, floor runs nothing.
do
  local started = nil
  local world = setmetatable({
    map = {
      def = { bgEvents = {} },
      cellCollision = function(_, x, _) return x == 1 and 0x93
        or (x == 3 and 0x94) or 0x00 end,
    },
    player = { facing = "up", cellX = 1, cellY = 1, moving = false },
    npcs = {},
    events = { get = function() return false end },
    stdScripts = { scripts = {
      PCScript = { key = "s:pc" },
      Radio1Script = { key = "s:radio" },
    } },
    vm = { start = function(_, key) started = key return true end,
      running = function() return false end },
  }, { __index = World })
  check(world:interact(), "A on a COLL_PC tile is claimed")
  eq(started, "s:pc", "and runs PCScript")
  world.player.cellX = 3
  world:interact()
  eq(started, "s:radio", "COLL_RADIO runs Radio1Script")
  started = nil
  world.player.cellX = 5
  check(not world:interact(), "a plain floor tile claims nothing")
  eq(started, nil, "and starts nothing")
end

-- ------------------------------------------------- the real thing

local cache = os.getenv("GOLD_CACHE")
local function loadCache(name)
  local chunk = cache
    and loadfile(cache .. "/data/generated/" .. name .. ".lua")
  return chunk and chunk()
end

local mapsData = loadCache("maps")
local tilesetsData = loadCache("tilesets")
local scriptsData = loadCache("scripts")
local textData = loadCache("text")
local stdScriptsData = loadCache("std_scripts")
local constsData = loadCache("constants")
local itemsData = loadCache("items")

local haveCache = mapsData and tilesetsData and scriptsData and stdScriptsData
  and constsData and (constsData.specialOrder ~= nil)

if not haveCache then
  check(true, "no GOLD_CACHE: real-map PC checks (SKIP)")
else
  local function realWorld(mapId, save)
    local def = mapsData[mapId]
    if not def then return nil end
    local game = newGame(save, itemsData or ITEMS)
    local world = World.new(game)
    game.world = world
    world.map = Map.new(def, tilesetsData[def.tileset] or {})
    world.maps = mapsData
    world.stdScripts = stdScriptsData
    world.text = textData
    world.constants = constsData
    world.pollTimeOfDay = function() end
    world.vm = Vm.new(scriptsData, textData, world.events, {
      specialOrder = constsData.specialOrder,
      specials = world:specialHooks(),
      openPc = function() world:openPc() end,
    })
    return world, game
  end

  -- The Cherrygrove Pokecenter: find the PC by its collision, stand under it,
  -- press A, and the whole chain runs -- PCScript out of std_scripts, the
  -- PokemonCenterPC special, World:openPc, the whose-PC menu.
  do
    local save = newSave(1)
    local world, game = realWorld("CHERRYGROVE_POKECENTER_1F", save)
    check(world ~= nil, "the cache carries CHERRYGROVE_POKECENTER_1F")
    if world then
      local pcX, pcY
      for cy = 0, world.map.heightCells - 1 do
        for cx = 0, world.map.widthCells - 1 do
          if world.map:cellCollision(cx, cy) == 0x93 then pcX, pcY = cx, cy end
        end
      end
      check(pcX ~= nil, "and its PC is a COLL_PC tile")
      if pcX then
        world.player = { facing = "up", cellX = pcX, cellY = pcY + 1,
          moving = false }
        check(world:interact(), "the A press at the PC is claimed")
        for _ = 1, 8 do
          if not world.vm:running() then break end
          world.vm:update()
        end
        local top = game.stack:top()
        eq(top and top.screenId, "Gen2CenterPcMenu",
          "and the whose-PC menu is on the stack")
        if top and top.screenId == "Gen2CenterPcMenu" then
          local input = game.input
          press(top, input, "a")           -- boot line
          eq(entryIds(top.entries), "bills,players,turnoff",
            "a fresh save sees the BEFORE_POKEDEX list")
          -- Deposit a POTION through <PLAYER>'s PC, for real.
          Bag.add(save, "POTION", 2, game.data)
          press(top, input, "down", "a", "a", "a")
          local itemPc = game.stack:top()
          eq(itemPc and itemPc.screenId, "Gen2ItemPcMenu",
            "<PLAYER>'s PC opens the item PC")
          if itemPc and itemPc.screenId == "Gen2ItemPcMenu" then
            press(itemPc, input, "down", "a") -- DEPOSIT ITEM
            press(itemPc, input, "a")         -- the POTION row
            press(itemPc, input, "a")         -- x1
            eq(save.pcItems.POTION, 1, "the POTION lands in save.pcItems")
            eq(save.inventory.POTION, 1, "and leaves the bag")
            press(itemPc, input, "a", "b", "b") -- message, PACK, log off
            eq(game.stack:top(), top, "LOG OFF drops back to the whose-PC menu")
          end
          press(top, input, "b")            -- shutdown
          eq(game.stack:top(), nil, "and B logs the whole PC off")
        end
      end
    end
  end

  -- The bedroom: the real PLAYERS_HOUSE_2F bg event, the blocking
  -- PlayersHousePC special, the item PC -- and the FALSE answered back to
  -- PlayersHousePCScript when no decoration moved.
  do
    local save = newSave(1)
    local world, game = realWorld("PLAYERS_HOUSE_2F", save)
    check(world ~= nil, "the cache carries PLAYERS_HOUSE_2F")
    if world then
      local pcEvent
      for _, ev in ipairs(world.map.def.bgEvents or {}) do
        if ev.kind == 1 then pcEvent = ev end -- BGEVENT_UP: the PC
      end
      check(pcEvent ~= nil, "the bedroom PC is its BGEVENT_UP event")
      if pcEvent then
        world.player = { facing = "up", cellX = pcEvent.x, cellY = pcEvent.y + 1,
          moving = false }
        check(world:interact(), "the A press at the bedroom PC is claimed")
        for _ = 1, 4 do
          if game.stack:top() then break end
          world.vm:update()
        end
        local top = game.stack:top()
        eq(top and top.screenId, "Gen2ItemPcMenu",
          "and the bedroom PC is the ITEM PC, not the storage system")
        if top and top.screenId == "Gen2ItemPcMenu" then
          eq(top.house, true, "in its PLAYERSPC_HOUSE shape")
          check(top.message ~= nil, "with the turn-on line up")
          local input = game.input
          press(top, input, "a", "b")  -- boot line, then TURN OFF via B
          eq(game.stack:top(), nil, "closing it pops the screen")
          for _ = 1, 6 do
            if not world.vm:running() then break end
            world.vm:update()
          end
          check(not world.vm:running(),
            "and PlayersHousePCScript runs to its end off the FALSE answer")
        end
      end
    end
  end
end

-- ------------------------------------------- MOVE POKéMON W/O MAIL, in full
--
-- The regression this block exists for: A on a mon used to move it instantly
-- to "the next box with room", with the confirmation string computed and then
-- thrown away -- so from the player's chair the PC ATE the mon.  Nothing on
-- screen named a destination and nothing was printed, which is the shape of
-- the bug report ("Move Pokemon w/o mail deletes the Pokemon when you select
-- it").  These checks pin the cart's own flow instead
-- (_MovePKMNWithoutMail, engine/pokemon/bills_pc.asm:480): a submenu, a
-- destination the player picks, and the mon accounted for at every step.
do
  local BoxMenu = require("src.ui.gen2.BoxMenu")
  local Boxes = require("src.core.gen2.Boxes")

  local function census(save)
    local n = #(save.party or {})
    for i = 1, Boxes.NUM_BOXES do n = n + Boxes.count(save, i) end
    return n
  end

  local save = newSave(3)
  local box = Boxes.box(save, 1)
  box[1] = { species = "PIDGEY", nickname = "BOXED1", hp = 10, maxHp = 10,
    level = 3 }
  box[2] = { species = "RATTATA", nickname = "BOXED2", hp = 10, maxHp = 10,
    level = 3 }
  local game, input = newGame(save)
  local menu = BoxMenu.new(game, { save = save, mode = "move",
    onClose = function() end })
  eq(census(save), 5, "five mons before anything is moved")
  eq(menu:prompt(), "Choose a <PK><MN>.", "PCString_ChooseaPKMN opens the list")

  -- 1. A opens .MoveMonWOMailSubmenu rather than moving anything.
  press(menu, input, "a")
  eq(menu.phase, "submenu", "A on a mon opens the submenu")
  eq(menu:prompt(), "What's up?", "under PCString_WhatsUp")
  eq(#Boxes.box(save, 1), 2, "and the box is untouched by opening it")

  -- CANCEL and B both come back with the mon exactly where it was.
  press(menu, input, "b")
  eq(menu.phase, nil, "B closes the submenu")
  eq(#Boxes.box(save, 1), 2, "still two in BOX1")

  -- 2. MOVE asks where, and the mon is STILL in its box while it asks.
  press(menu, input, "a", "a")
  eq(menu.phase, "insert", "MOVE opens the insert cursor")
  eq(menu:prompt(), "Move to where?", "under PCString_MoveToWhere")
  eq(#Boxes.box(save, 1), 2, "nothing has left the box yet")
  eq(census(save), 5, "and nothing has left the save")

  -- B there is .b_button_2: the backed-up position, nothing moved.
  press(menu, input, "b")
  eq(menu.phase, nil, "B backs out of the insert cursor")
  eq(#Boxes.box(save, 1), 2, "with the mon still in BOX1")
  eq(census(save), 5, "and the census unchanged")

  -- 3. right walks to BOX2 and A inserts there -- the destination the player
  -- chose, named on screen, with the cart's own confirmation.
  press(menu, input, "a", "a", "right")
  eq(menu.boxIndex, 2, "right walks the insert cursor to the next box")
  eq(menu:title(), "BOX2", "and the header names it")
  press(menu, input, "a")
  eq(census(save), 5, "the mon still exists")
  eq(#Boxes.box(save, 1), 1, "one left BOX1")
  eq(Boxes.box(save, 2)[1].nickname, "BOXED1", "and it is in BOX2")
  eq(menu.message, "Saving\xe2\x80\xa6 Leave ON!",
    "MovePKMNWithoutMail_InsertMon's own line says so")

  -- 4. left twice reaches the PARTY (wBillsPC_LoadedBox 0), which the old
  -- screen could not show at all.
  press(menu, input, "a", "left", "left")
  eq(menu.boxIndex, 0, "left wraps through BOX1 to the party")
  eq(menu:title(), "PARTY <PK><MN>", "BillsPC_BoxName's .party arm")
  eq(#menu:list(), 3, "and the list is the party")

  -- A party mon moves into a box, and the party shrinks by exactly one.
  press(menu, input, "a", "a", "right")
  eq(menu.boxIndex, 1, "right from the party is BOX1")
  press(menu, input, "a")
  eq(#save.party, 2, "the party is one shorter")
  eq(census(save), 5, "and the mon is still in the save")
  eq(Boxes.box(save, 1)[1].nickname, "MON1", "sitting where the cursor was")

  -- BillsPC_CheckMail_PreventBlackout: a party of two may not send one away.
  press(menu, input, "a", "left")
  eq(menu.boxIndex, 0, "back on the party")
  press(menu, input, "a", "a")
  eq(menu.phase, nil, "the MOVE is refused outright")
  eq(menu.message, "It's your last <PK><MN>!", "with PCString_ItsYourLastPKMN")
  eq(#save.party, 2, "and the party is untouched")

  -- .MoveMonWOMailSubmenu has no RELEASE row, so SELECT on this screen must
  -- not open the withdraw list's release question either.
  press(menu, input, "a")
  press(menu, input, "select")
  eq(#game.stack._items, 0, "SELECT on the move screen opens nothing")
  eq(census(save), 5, "and releases nothing")
end

S.finish()
