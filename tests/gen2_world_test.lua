-- Gen 2 COLL_* permissions + New Bark warp/connection facts against a Gold
-- cache.  Self-contained: `luajit tests/gen2_world_test.lua`; also dofile'd
-- by tests/run_tests.lua.  Map checks SKIP when no gold cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 world")
local check, eq = S.check, S.eq

local Permissions = require("src.world.gen2.Permissions")
local Map = require("src.world.gen2.Map")
local NPC = require("src.world.gen2.Npc")
local Events = require("src.world.gen2.Events")

-- Object visibility: flag SET hides; 0xFFFF always shown.
local ev = Events.new({ 1794 })
check(ev:get(1794), "initial flag applied")
check(not ev:objectVisible(1794), "set flag hides object")
check(ev:objectVisible(nil), "nil eventFlag always visible")
check(ev:objectVisible(0xFFFF), "0xFFFF eventFlag always visible")
check(ev:objectVisible(1600), "unset flag leaves object visible")


check(Permissions.isWalkable(0x00), "COLL_FLOOR walkable")
check(not Permissions.isWalkable(0x07), "COLL_WALL blocked")
check(Permissions.isWater(0x29), "COLL_WATER is water")
check(Permissions.isWarpCollision(0x71), "COLL_DOOR is warp")
check(Permissions.isImmediateWarp(0x71), "COLL_DOOR immediate")
check(not Permissions.isImmediateWarp(0x70), "carpet not immediate")
eq(Permissions.carpetDirection(0x70), "down", "carpet down")
eq(Permissions.of(0xff), Permissions.WALL, "missing coll → wall")
check(not Permissions.isWalkable(0xff), "sentinel $ff not walkable")

-- ---------------------------------------------------------------- field
-- The two encounter systems that need an INPUT path: a rod used from the PACK
-- and an A press on a headbutt tree.  Both are wired here rather than called
-- directly, because the wiring is the thing under test -- a stub input drives
-- PackMenu, a stub map drives World:interact, and the world's own text /
-- choice / battle seams are recorded so the ORDER the cart's script imposes
-- (ask, then shake, then roll) is checkable.

local World = require("src.world.gen2.World")
local PackMenu = require("src.ui.gen2.PackMenu")

-- Collisions the two paths key off, straight out of the table above:
-- COLL_FLOOR walkable land, COLL_WATER, COLL_HEADBUTT_TREE.
local COLL_FLOOR, COLL_WATER, COLL_TREE = 0x00, 0x29, 0x15

check(World.isHeadbuttTree(COLL_TREE), "COLL_HEADBUTT_TREE is a tree")
check(World.isHeadbuttTree(0x1d), "COLL_HEADBUTT_TREE_1D alias is a tree")
check(not World.isHeadbuttTree(COLL_FLOOR), "floor is not a tree")
check(not World.isHeadbuttTree(nil), "no tile is not a tree")
check(Permissions.isWall(COLL_TREE), "a headbutt tree blocks a step")

-- ItemNames indices out of constants/item_constants.asm.
local ITEMS = {
  OLD_ROD = { id = "OLD_ROD", name = "OLD ROD", pocket = "KEY_ITEM",
    index = 0x3a },
  GOOD_ROD = { id = "GOOD_ROD", name = "GOOD ROD", pocket = "KEY_ITEM",
    index = 0x3b },
  SUPER_ROD = { id = "SUPER_ROD", name = "SUPER ROD", pocket = "KEY_ITEM",
    index = 0x3d },
  BICYCLE = { id = "BICYCLE", name = "BICYCLE", pocket = "KEY_ITEM",
    index = 0x06 },
  -- A key item with no field handler of its own, which is what the PACK's
  -- onChoose fallthrough needs: every other key item here is a rod or the
  -- BICYCLE, and both of those are claimed by useFieldItem.
  COIN_CASE = { id = "COIN_CASE", name = "COIN CASE", pocket = "KEY_ITEM",
    index = 0x47 },
  -- ../pokecrystal/data/items/attributes.asm:242
  BLUE_CARD = { id = "BLUE_CARD", name = "BLUE CARD", pocket = "KEY_ITEM",
    index = 0x74, fieldMenu = "ITEMMENU_CURRENT",
    battleMenu = "ITEMMENU_NOUSE" },
  REPEL = { id = "REPEL", name = "REPEL", pocket = "ITEM", index = 0x14,
    canSelect = true },
  SUPER_REPEL = { id = "SUPER_REPEL", name = "SUPER REPEL", pocket = "ITEM",
    index = 0x2a },
  MAX_REPEL = { id = "MAX_REPEL", name = "MAX REPEL", pocket = "ITEM",
    index = 0x2b },
  -- ITEMATTR_PERMISSIONS: a plain field item with no CANT_SELECT_F.
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 0x02,
    canSelect = true },
  -- A TM/HM's CheckSelectableItem.CheckTMHM always refuses (RegisterItem's
  -- .cant_register), which the extractor already answers as canSelect = false.
  HM_CUT = { id = "HM_CUT", name = "HM01", pocket = "TM_HM", index = 0x32,
    canSelect = false },
}
check(World.isRod("OLD_ROD", ITEMS), "OLD ROD is a rod")
check(World.isRod("GOOD_ROD", ITEMS), "GOOD ROD is a rod")
check(World.isRod("SUPER_ROD", ITEMS), "SUPER ROD is a rod")
check(not World.isRod("BICYCLE", ITEMS), "BICYCLE is not a rod")
check(not World.isRod("OLD_ROD", { OLD_ROD = { index = 7 } }),
  "a rod at the wrong ItemNames index is refused")

local DATA = {
  items = ITEMS,
  moves = {
    HEADBUTT = { name = "HEADBUTT", pp = 15 },
    SPLASH = { name = "SPLASH", pp = 40 },
    TACKLE = { name = "TACKLE", pp = 35 },
  },
  pokemon = {
    MAGIKARP = {
      name = "MAGIKARP", types = { "WATER", "WATER" },
      baseStats = { hp = 20, attack = 10, defense = 55, speed = 80,
        specialAttack = 15, specialDefense = 20 },
      levelMoves = { { level = 1, move = "SPLASH" } },
    },
    HOOTHOOT = {
      name = "HOOTHOOT", types = { "NORMAL", "FLYING" },
      baseStats = { hp = 60, attack = 30, defense = 30, speed = 50,
        specialAttack = 36, specialDefense = 56 },
      levelMoves = { { level = 1, move = "TACKLE" } },
    },
  },
}

-- One always-hit row per list, so the roll is not what these assert.
local ENCOUNTERS = {
  fishGroups = {
    FISHGROUP_POND = {
      old = { { chance = 256, species = "MAGIKARP", level = 10 } },
      good = { { chance = 256, species = "MAGIKARP", level = 20 } },
      super = { { chance = 256, species = "MAGIKARP", level = 40 } },
    },
  },
  trees = { TEST_MAP = "TREEMON_SET_TEST" },
  treeSets = {
    TREEMON_SET_TEST = {
      common = { { chance = 100, species = "HOOTHOOT", level = 12 } },
      rare = { { chance = 100, species = "HOOTHOOT", level = 12 } },
    },
  },
}

-- A 100-wide strip of collisions, keyed y*100+x, plus the empty event lists
-- World:interact walks.  `opts` fills in the parts of a real Map the field
-- moves read: the block grid CUT and WHIRLPOOL edit, the tileset that decides
-- which replacement block they use, and the environment the encounter gate
-- branches on.
local MAP_W, MAP_H = 10, 10

local function fakeMap(cells, opts)
  opts = opts or {}
  local blocks = {}
  for i = 1, MAP_W * MAP_H do blocks[i] = 0 end
  for index, id in pairs(opts.blocks or {}) do blocks[index] = id end
  local map
  map = {
    id = "TEST_MAP",
    width = MAP_W, height = MAP_H,
    blocks = blocks,
    def = {
      bgEvents = {}, objects = {}, blocks = blocks,
      width = MAP_W, height = MAP_H,
      tileset = opts.tileset or "TILESET_JOHTO",
      environment = opts.environment or "ROUTE",
      palette = opts.palette or "PALETTE_AUTO",
    },
    cellCollision = function(_, x, y) return cells[y * 100 + x] or COLL_FLOOR end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < MAP_W * 2 and y < MAP_H * 2
    end,
    isWalkable = function(_, x, y)
      if not map:inBounds(x, y) then return false end
      return Permissions.isWalkable(map:cellCollision(x, y))
    end,
    objectStepPermitted = function(_, cx, cy, dir)
      local d = Map.DELTA[dir]
      if not d then return false end
      local tx, ty = cx + d[1], cy + d[2]
      if not map:inBounds(tx, ty) then return false end
      return Permissions.objectStepPermitted(
        map:cellCollision(cx, cy), map:cellCollision(tx, ty), dir)
    end,
    warpAt = function() return nil end,
  }
  return map
end

local function fakePlayer(x, y, facing)
  return {
    cellX = x, cellY = y, px = x * 16, py = y * 16,
    facing = facing, moving = false, turnArmed = true,
    update = function() return false end,
    -- Player:setSprite, which World:applyPlayerState calls every time
    -- wPlayerState changes.  Nothing here draws, so it only has to exist.
    setSprite = function() end,
  }
end

-- ../pokecrystal/engine/overworld/events.asm:349-353
do
  local Movement = require("src.script.gen2.Movement")
  local w = World.new({ data = { audio = { sfxOrder = {} } },
    save = { player = {} } })
  w.player = { cellX = 0, cellY = 0, facing = "down" }
  local sfx = {}
  w.playSfxNamed = function(_, name) sfx[#sfx + 1] = name end

  w:startSkyfall()
  eq(sfx[1], "Sfx_Kinesis", "the fall opens on SFX_KINESIS")
  check(w.playerMasked, "OBJECT_ACTION_00 is SetFacingStanding: nothing drawn")
  check(w:busy(), "and the applymovement holds the overworld")
  for _ = 1, 16 do w:updateSkyfall() end
  check(not w.playerMasked, "the sprite comes back for the descent")
  eq(w.player.spriteYOffset, nil, "and has not moved yet")

  w:updateSkyfall()
  eq(w.player.spriteYOffset, Movement.teleportYOffset(1),
    "the first falling frame is off the top of the screen")
  local last = w.player.spriteYOffset
  for _ = 1, 14 do
    w:updateSkyfall()
    check(w.player.spriteYOffset > last, "the drop eases down every frame")
    last = w.player.spriteYOffset
  end
  w:updateSkyfall()
  eq(w.player.spriteYOffset, 0, "landing flush on the tile")
  check(w.skyfall == nil, "and the state is done")
  check(not w:busy(), "so the world is walkable again")
  eq(sfx[2], "Sfx_Strength", "SFX_STRENGTH on the landing")
  eq(#sfx, 2, "and no warpsound anywhere in the fall")
  eq(w.shake and w.shake.amplitude, 1, "earthquake 16 is a one-pixel shake")
  eq(w.shake and w.shake.left, 16, "for sixteen frames")
end

-- engine/events/overworld.asm:864-872
do
  local Movement = require("src.script.gen2.Movement")
  local w = World.new({ data = { audio = { sfxOrder = {} } },
    save = { player = {} } })
  local spins = {}
  w.player = {
    cellX = 0, cellY = 0, facing = "down", moving = false,
    scriptSpin = function(_, frames, flicker)
      spins[#spins + 1] = { frames = frames, flicker = flicker }
    end,
  }
  w:beginMovement(0, Movement.digOutBytes())
  w:updateMovement()
  eq(spins[1] and spins[1].frames, 32, "step_dig 32 spins for 32 frames")
  check(not spins[1].flicker, "and the out-spin does not strobe")
  check(not w.playerHidden, "hide_object has not been read yet")
  for _ = 1, 33 do w:updateMovement() end
  check(w.playerHidden, "hide_object hides the player for the fade")
  check(w.moveState == nil, "and the stream ends on step_end")

  w:beginMovement(0, Movement.digReturnBytes())
  w:updateMovement()
  check(not w.playerHidden, "show_object brings them back on the far side")
  eq(spins[2] and spins[2].frames, 32, "return_dig 32 spins for 32 too")
  eq(spins[2] and spins[2].flicker, true,
    "and StepFunction_DigTo strobes it on the odd frames")
end

-- A world with the render half replaced: no love here, so the seams that would
-- push a TextBox, a ChoiceBox or the battle screen record instead.  `log` is
-- the script trace the assertions read.
local function fakeWorld(cells, player, party, fishGroup, opts)
  opts = opts or {}
  local game = {
    data = DATA,
    save = { player = { name = "GOLD", badges = opts.badges or {} },
      party = party or {},
      inventory = { OLD_ROD = 1, BICYCLE = 1, COIN_CASE = 1 } },
  }
  local world = World.new(game)
  game.world = world
  world.map = fakeMap(cells, opts)
  -- maps[id] IS the map's def in the real world, and World:restoreBlocks
  -- reaches for it that way when a cut tree has to grow back.
  world.map.def.fishGroup = fishGroup or "FISHGROUP_POND"
  world.maps = { TEST_MAP = world.map.def }
  world.player = player
  world.encounters = ENCOUNTERS
  world.vm = { running = function() return false end, update = function() end }
  -- The palette poll re-bakes map canvases through love.graphics; nothing in
  -- these assertions is about colour.
  world.pollTimeOfDay = function() end

  local log = {}
  world.log = log
  world.showText = function(self, body, onDone)
    log[#log + 1] = body
    self.textbox = true
    self.pendingText = function()
      self.textbox = nil
      if onDone then onDone() end
    end
  end
  world.askYesNo = function(self, onChoose)
    log[#log + 1] = "<yesno>"
    self.choicebox = true
    self.pendingChoice = function(yes)
      self.choicebox = nil
      onChoose(yes)
    end
  end
  world.startBattle = function(_, opts)
    log[#log + 1] = "<battle:" .. tostring(opts.wild and opts.wild.species) .. ">"
    return true
  end
  return world, game
end

-- The A that closes a text box, and the YES/NO answer.
local function advanceText(world)
  local fn = world.pendingText
  world.pendingText = nil
  if fn then fn() end
end

local function answerYesNo(world, yes)
  local fn = world.pendingChoice
  world.pendingChoice = nil
  if fn then fn(yes) end
end

local function runFrames(world, n)
  for _ = 1, n do world:step() end
end

local function stubInput()
  local input = { queued = {} }
  function input:press(button) self.queued[button] = true end
  function input:wasPressed(button)
    if self.queued[button] then
      self.queued[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

-- A stack that only has to answer the one question PackMenu asks of it.
local function stubStack()
  return { cleared = 0, clear = function(self) self.cleared = self.cleared + 1 end }
end

-- A on a field-PACK row does not use the item: it opens the item submenu
-- (.ItemBallsKey_LoadSubmenu, engine/items/pack.asm:243) whose first row is
-- USE, so "use the highlighted row" is two A presses through that menu -- which
-- is why every use below presses A twice.  The chooser packs (the mart's SELL,
-- the item PC's DEPOSIT, the DUDE's) have no submenu and still answer the first
-- press; see PackMenu:hasSubmenu.  Written out at each site rather than as a
-- helper because this file is already at the 200-local ceiling.

-- ---- A. the rod ----------------------------------------------------------
-- Facing land: .TryFish falls to $3 .FailFish, so UseItem's .Oak prints inside
-- the PACK and the PACK stays open.
local landWorld, landGame = fakeWorld({}, fakePlayer(5, 5, "down"))
landGame.input = stubInput()
landGame.stack = stubStack()
local chosen = nil
local landPack = PackMenu.new(landGame, {
  pocket = "KEY_ITEM",
  onChoose = function(id) chosen = id end,
  onClose = function() chosen = "<closed>" end,
})
eq(landPack.rows[1].id, "BICYCLE", "key items sort by ItemNames index")
eq(landPack.rows[2].id, "OLD_ROD", "the rod is the second key item")
landPack.index = 2
landGame.input:press("a")
landPack:update(0)
landGame.input:press("a")
landPack:update(0)
check(landPack.message ~= nil, "rod on land keeps the PACK open with a message")
eq(landPack.message[1], "OAK: {PLAYER}!", "and the message is Oak's")
eq(landGame.stack.cleared, 0, "rod on land does not quit the PACK")
eq(chosen, nil, "rod on land never reaches onChoose")
check(landWorld.fishing == nil, "rod on land starts no cast")
-- home/text.asm:502
landGame.input:press("a")
landPack:update(0)
eq(landPack.messagePage, 2, "a button scrolls Oak's `cont` to its second page")
landGame.input:press("a")
landPack:update(0)
check(landPack.message == nil, "and the next clears the message")

-- CoinCaseEffect (engine/items/item_effects.asm:2243) is a MenuTextboxWaitButton
-- over _CoinCaseCountText: the PACK stays open and nothing reaches onChoose.
landGame.save.player.coins = 250
landPack.index = 3
landGame.input:press("a")
landPack:update(0)
landGame.input:press("a")
landPack:update(0)
check(landPack.message ~= nil, "the COIN CASE prints inside the PACK")
eq(landPack.message[1], "Coins:", "_CoinCaseCountText's first row")
eq(landPack.message[2], "250", "and the count on the second")
eq(chosen, nil, "the COIN CASE never reaches onChoose")
eq(landGame.stack.cleared, 0, "and does not quit the PACK either")
landGame.input:press("a")
landPack:update(0)

-- BlueCardEffect (../pokecrystal/engine/items/item_effects.asm:2251)
do
  landGame.save.inventory.BLUE_CARD = 1
  landPack:rebuild()
  landWorld:writeVar(0x18, 12)
  landPack.index = 4
  eq(landPack.rows[4].id, "BLUE_CARD", "the BLUE CARD is the fourth key item")
  landGame.input:press("a")
  landPack:update(0)
  landGame.input:press("a")
  landPack:update(0)
  check(landPack.message ~= nil, "the BLUE CARD prints inside the PACK")
  eq(landPack.message[1], "You now have", "_BlueCardBalanceText's first row")
  eq(landPack.message[2], "12 points.", "and the balance on the second")
  eq(chosen, nil, "the BLUE CARD never reaches onChoose")
  eq(landGame.stack.cleared, 0, "and does not quit the PACK")
  landGame.input:press("a")
  landPack:update(0)
  landGame.save.inventory.BLUE_CARD = nil
  landPack:rebuild()
end

-- Facing water: the roll lands on $2 .FishGotSomething, the PACK quits
-- (PACKSTATE_QUITRUNSCRIPT) and Script_FishCastRod's cast owns the world.
local waterCells = { [4 * 100 + 5] = COLL_WATER }
local seaWorld, seaGame = fakeWorld(waterCells, fakePlayer(5, 5, "up"))
seaGame.input = stubInput()
seaGame.stack = stubStack()
local seaPack = PackMenu.new(seaGame, { pocket = "KEY_ITEM" })
seaPack.index = 2
seaGame.input:press("a")
seaPack:update(0)
seaGame.input:press("a")
seaPack:update(0)
check(seaPack.message == nil, "rod on water prints no refusal")
eq(seaGame.stack.cleared, 1, "rod on water quits the PACK")
check(seaWorld.fishing ~= nil, "rod on water starts the cast")
eq(seaWorld.fishing.outcome, "battle", "and the roll already hooked something")
check(seaWorld:busy(), "the cast holds the world")
-- ../pokecrystal/engine/menus/start_menu.asm:492
check(seaWorld.mapSetup ~= nil, "the rod quits the PACK through ExitAllMenus")
do
  local exitGuard = 0
  while seaWorld.mapSetup and exitGuard < 120 do
    seaWorld:step()
    exitGuard = exitGuard + 1
  end
end
eq(seaWorld.fishing.phase, "cast", "the cast has not started under the white")
-- pause 40, the bite, pause 40, then RodBiteText.
runFrames(seaWorld, 41)
eq(seaWorld.fishing.phase, "bite", "the cast runs out into the bite")
eq(#seaWorld.log, 0, "and says nothing until the rod comes back")
runFrames(seaWorld, 41)
eq(seaWorld.log[1], "Oh!\nA bite!", "RodBiteText lands after the second pause")
check(seaWorld.log[2] == nil, "and the battle waits on the button")
advanceText(seaWorld)
eq(seaWorld.log[2], "<battle:MAGIKARP>", "the hooked mon is the battle")
check(seaWorld.fishing == nil, "the cast is over")
check(not seaWorld:busy(), "and the world is free again")

-- FISHGROUP_NONE is $4 .FishNoFish: the PACK still quits, the rod still casts,
-- and RodNothingText is what comes back.
local dryWorld = fakeWorld(waterCells, fakePlayer(5, 5, "up"), nil,
  "FISHGROUP_NONE")
eq(dryWorld:useRod("OLD_ROD"), "nofish", "no fish group is .FishNoFish")
runFrames(dryWorld, 41)
eq(dryWorld.log[1], "Not even a nibble!", "and RodNothingText is the line")
advanceText(dryWorld)
check(dryWorld.fishing == nil, "the rod goes away after the nibble line")

-- A rod is ITEMMENU_NOUSE in battle, and a running script owns the world.
local busyWorld = fakeWorld(waterCells, fakePlayer(5, 5, "up"))
busyWorld.battleActive = true
eq(busyWorld:useRod("OLD_ROD"), "nowhere", "no fishing from inside a battle")
busyWorld.battleActive = nil
busyWorld.vm = { running = function() return true end, update = function() end }
eq(busyWorld:useRod("OLD_ROD"), "nowhere", "no fishing while a script runs")
check(busyWorld:useFieldItem("POTION") == nil,
  "useFieldItem passes an unhandled item back to the PACK")
eq(busyWorld:useFieldItem("COIN_CASE"), "coin_case",
  "the COIN CASE is ITEMMENU_CURRENT and World claims it")
do
  busyWorld:writeVar(0x18, 17)
  local result, balance = busyWorld:useFieldItem("BLUE_CARD")
  eq(result, "blue_card", "the BLUE CARD is ITEMMENU_CURRENT too")
  eq(balance, 17, "and it comes back with wBlueCardBalance")
end

-- ---- A2. REPEL / SUPER REPEL / MAX REPEL ----------------------------------
-- UseRepel (engine/items/item_effects.asm): the step count is the only thing
-- that differs between the three items, wRepelEffect already set refuses
-- without touching either the counter or the bag, and only the success arm
-- goes through UseDisposableItem.
-- Scoped in its own `do` block: the file is already brushing Lua's 200-local
-- ceiling, and this test needs its own world/game/pack rather than reusing
-- the rod fixtures above.
do
local repelWorld, repelGame = fakeWorld({}, fakePlayer(5, 5, "down"))
repelGame.save.inventory.REPEL = 2
repelGame.save.inventory.SUPER_REPEL = 1
eq(repelWorld:useRepel("REPEL"), "repel_used", "a fresh REPEL is used")
eq(repelGame.save.repelSteps, 100, "REPEL sets the counter to 100")
eq(repelGame.save.inventory.REPEL, 1, "and one REPEL leaves the bag")

eq(repelWorld:useRepel("SUPER_REPEL"), "repel_active",
  "a REPEL already ticking refuses a SUPER REPEL")
eq(repelGame.save.repelSteps, 100, "the counter is untouched by the refusal")
eq(repelGame.save.inventory.SUPER_REPEL, 1,
  "and the SUPER REPEL is not taken from the bag")

repelGame.save.repelSteps = 0
eq(repelWorld:useRepel("SUPER_REPEL"), "repel_used",
  "a SUPER REPEL is used once the counter reaches zero")
eq(repelGame.save.repelSteps, 200, "SUPER REPEL sets the counter to 200")
check(repelGame.save.inventory.SUPER_REPEL == nil,
  "the last SUPER REPEL is gone from the bag")

-- Battle refuses a REPEL exactly like a rod (ITEMMENU_NOUSE): the world is
-- shared with BattleState:openPack, so the guard has to live here too.
repelWorld.battleActive = true
repelGame.save.repelSteps = 0
eq(repelWorld:useRepel("MAX_REPEL"), "nowhere",
  "no REPEL from inside a battle")
eq(repelGame.save.repelSteps, 0, "and the refusal never sets the counter")
repelWorld.battleActive = nil

-- The PACK: World already claims the item, so onChoose is never reached, and
-- the still-in-effect message keeps the row list (and the bag) untouched.
local packGame = { data = DATA, save = repelGame.save,
  stack = stubStack(), input = stubInput(), world = repelWorld }
local repelPack = PackMenu.new(packGame, { pocket = "ITEM" })
local chosenRepel
repelPack.onChoose = function(id) chosenRepel = id end
for i, row in ipairs(repelPack.rows) do
  if row.id == "REPEL" then repelPack.index = i end
end
packGame.input:press("a")
repelPack:update(0)
packGame.input:press("a")
repelPack:update(0)
check(repelPack.message ~= nil, "using a REPEL keeps the PACK open with a message")
eq(repelPack.message[1], "{PLAYER} used the", "the message is ItemUsedText")
eq(repelPack.message[2], "REPEL.", "naming the item that was used")
eq(packGame.stack.cleared, 0, "and the PACK is never quit")
eq(chosenRepel, nil, "onChoose never sees a REPEL the world already claimed")
eq(repelGame.save.repelSteps, 100, "the PACK path set the counter too")

packGame.input:press("a")
repelPack:update(0)
check(repelPack.message == nil, "a button clears ItemUsedText")

for i, row in ipairs(repelPack.rows) do
  if row.id == "SUPER_REPEL" then repelPack.index = i end
end
repelGame.save.inventory.SUPER_REPEL = 1
repelPack:rebuild()
for i, row in ipairs(repelPack.rows) do
  if row.id == "SUPER_REPEL" then repelPack.index = i end
end
packGame.input:press("a")
repelPack:update(0)
packGame.input:press("a")
repelPack:update(0)
eq(repelPack.message[1], "The REPEL used",
  "a REPEL already active refuses a second item with the static text")
eq(repelPack.message[4], "in effect.",
  "with `cont` between it and the third line (data/text/common_3.asm:1270)")
end

-- ---- A3. SACRED ASH -------------------------------------------------------
-- SacredAshEffect / _SacredAsh (engine/items/item_effects.asm,
-- engine/events/sacred_ash.asm).  CheckAnyFaintedMon is the whole gate: no
-- fainted (non-egg) party member means no carry, wItemEffectSucceeded stays
-- 0, and UseItem's .Field falls to .Oak with the Ash untouched -- "nowhere",
-- same answer PackMenu already gives a rod cast nowhere useful.  A hit queues
-- SacredAshScript (special HealParty, three Pokecenter fade cycles, the
-- "all healed" line) and only then removes the one Ash.
do
local order = { "HealParty", "FadeOutToWhite", "FadeInFromWhite" }

local faintedParty = {
  { species = "MAGIKARP", nickname = "KARP", hp = 0, maxHp = 20,
    moves = { { id = "SPLASH", pp = 0, maxPp = 40 } } },
}
local ashWorld, ashGame = fakeWorld({}, fakePlayer(5, 5, "down"), faintedParty)
ashWorld.constants = { specialOrder = order }
ashGame.save.inventory.SACRED_ASH = 1

eq(ashWorld:useFieldItem("SACRED_ASH"), "sacredash",
  "a fainted party takes the Ash through useFieldItem")
eq(ashGame.save.inventory.SACRED_ASH, nil, "and the last Ash leaves the bag")

local script = ashWorld.queuedScript
check(script ~= nil, "the effect queues SacredAshScript")
eq(script[1].op, "special", "special HealParty opens the script")
eq(script[1].id, 0, "HealParty resolves through specialOrder, not a bare index")
local fades = 0
for _, cmd in ipairs(script) do
  if cmd.op == "special" and cmd.id == 1 then fades = fades + 1 end
end
eq(fades, 3, "three FadeOutToWhite cycles, same as a Pokecenter warp")
eq(script[#script].op, "end", "the script ends")
eq(script[#script - 1].op, "closetext", "and closes the text box first")

-- A fully healthy party never sets carry: refused, nothing spent.
local healthyParty = {
  { species = "MAGIKARP", nickname = "KARP", hp = 20, maxHp = 20 },
}
local healthyWorld, healthyGame =
  fakeWorld({}, fakePlayer(5, 5, "down"), healthyParty)
healthyWorld.constants = { specialOrder = order }
healthyGame.save.inventory.SACRED_ASH = 1
eq(healthyWorld:useSacredAsh(), "nowhere", "no fainted mon refuses the Ash")
eq(healthyGame.save.inventory.SACRED_ASH, 1,
  "and nothing is taken from the bag")
check(healthyWorld.queuedScript == nil, "no script queued either")

-- An egg's hp field is the box struct underneath, not a real total that can
-- be "fainted"; CheckAnyFaintedMon's `cp EGG / jr z, .next` skips it.
local eggOnlyParty = { { species = "EGG", isEgg = true, hp = 0, maxHp = 0 } }
local eggWorld, eggGame = fakeWorld({}, fakePlayer(5, 5, "down"), eggOnlyParty)
eggWorld.constants = { specialOrder = order }
eggGame.save.inventory.SACRED_ASH = 1
eq(eggWorld:useSacredAsh(), "nowhere", "an egg-only party has nothing to revive")

-- ITEMMENU_NOUSE in battle, the same guard every field item gets.
ashWorld.battleActive = true
eq(ashWorld:useSacredAsh(), "nowhere", "no Sacred Ash from inside a battle")
ashWorld.battleActive = nil
end

-- Ho-Oh's own end: BATTLETYPE_FORCEITEM (InitEnemyMon's `.WildItem`) is what
-- actually puts a SACRED_ASH on the mon the player catches -- the effect
-- above is reachable only once something stamps the held item on, and until
-- this the port never did.  The general 25%/8% wild-item roll stays
-- unmodeled (Mon.new's own note); only the unconditional FORCEITEM path is.
do
local Mon = require("src.battle.gen2.Mon")
local realMonNew = Mon.new
Mon.new = function(_, id, level) return { species = id, level = level } end

local forceWorld, forceGame = fakeWorld({}, fakePlayer(5, 5, "down"))
forceGame.data = { pokemon = {
  HO_OH = { index = 250, items = { "SACRED_ASH", "SACRED_ASH" } },
} }
local captured
forceWorld.startBattle = function(_, opts) captured = opts return true end

forceWorld.scriptVars[0x03] = 10 -- VAR_BATTLETYPE, BATTLETYPE_FORCEITEM
forceWorld:startScriptedBattle(nil, { species = 250, level = 70 },
  function() end)
eq(captured and captured.wild and captured.wild.item, "SACRED_ASH",
  "BATTLETYPE_FORCEITEM hands Ho-Oh's Item1 to the wild mon unconditionally")

captured = nil
forceWorld:startScriptedBattle(nil, { species = 250, level = 70 },
  function() end)
check(captured and captured.wild and captured.wild.item == nil,
  "without FORCEITEM armed again, no held item is stamped on")

Mon.new = realMonNew
end

-- ---- B. the tree ---------------------------------------------------------
local treeCells = { [4 * 100 + 5] = COLL_TREE }

-- No party mon knows HEADBUTT: TryHeadbuttOW returns nc and the A press is
-- dropped entirely (.noevent), text included.
local bareWorld = fakeWorld(treeCells, fakePlayer(5, 5, "up"), {
  { species = "MAGIKARP", nickname = "KARP",
    moves = { { id = "SPLASH", pp = 40 } } },
})
check(not bareWorld:interact(), "a tree with no HEADBUTT mon refuses the press")
eq(#bareWorld.log, 0, "and says nothing at all")

-- With one, AskHeadbuttScript opens; NO closes it without a roll.
local noWorld = fakeWorld(treeCells, fakePlayer(5, 5, "up"), {
  { species = "HOOTHOOT", nickname = "OWL",
    moves = { { id = "HEADBUTT", pp = 15 } } },
})
check(noWorld:interact(), "a tree with a HEADBUTT mon takes the press")
eq(noWorld.log[1], "A POKéMON could be\nin this tree.\fWant to HEADBUTT\nit?",
  "AskHeadbuttText is the question")
advanceText(noWorld)
eq(noWorld.log[2], "<yesno>", "and it is a yesorno")
answerYesNo(noWorld, false)
eq(#noWorld.log, 2, "NO ends the script there")
check(noWorld.headbutt == nil, "NO shakes nothing")

-- YES: nickname, UseHeadbuttText, the 32-frame shake, and only then the roll.
local hitWorld, hitGame = fakeWorld(treeCells, fakePlayer(5, 5, "up"), {
  { species = "HOOTHOOT", nickname = "OWL",
    moves = { { id = "HEADBUTT", pp = 15 } } },
})
-- ../pokecrystal/engine/events/treemons.asm:126 GetTreeMon
hitWorld.treemonRandom = function() return 0 end
check(hitWorld:interact(), "the ask opens again")
advanceText(hitWorld)
answerYesNo(hitWorld, true)
eq(hitGame.stringBuffer, "OWL", "GetPartyNickname fills wStringBuffer2")
eq(hitWorld.log[3], "{STRBUF} did a\nHEADBUTT!", "UseHeadbuttText names the mon")
check(hitWorld.headbutt == nil, "the shake waits for the text")
advanceText(hitWorld)
check(hitWorld.headbutt ~= nil, "then ShakeHeadbuttTree starts")
eq(hitWorld.headbutt.timer, 32, "wFrameCounter is 32")
check(hitWorld:busy(), "the shake holds the world")
runFrames(hitWorld, 32)
eq(hitWorld.log[4], nil, "nothing is rolled mid-shake")
runFrames(hitWorld, 1)
eq(hitWorld.log[4], "<battle:HOOTHOOT>", "TreeMonEncounter runs after the shake")
check(hitWorld.headbutt == nil, "and the shake is over")

-- A map with no treemon set is the cart's other no_battle: the tree still
-- shakes, and "Nope. Nothing…" is what it gives up.
local emptyWorld = fakeWorld(treeCells, fakePlayer(5, 5, "up"), {
  { species = "HOOTHOOT", nickname = "OWL",
    moves = { { id = "HEADBUTT", pp = 15 } } },
})
emptyWorld.encounters = { fishGroups = ENCOUNTERS.fishGroups }
check(emptyWorld:interact(), "the ask opens on the bare map too")
advanceText(emptyWorld)
answerYesNo(emptyWorld, true)
advanceText(emptyWorld)
runFrames(emptyWorld, 33)
eq(emptyWorld.log[4], "Nope. Nothing…", "HeadbuttNothingText closes it out")

-- A tree the player is not facing is somebody else's press.
local pastWorld = fakeWorld(treeCells, fakePlayer(5, 5, "down"), {
  { species = "HOOTHOOT", nickname = "OWL",
    moves = { { id = "HEADBUTT", pp = 15 } } },
})
check(not pastWorld:interact(), "facing away from the tree does nothing")

-- ../pokecrystal/engine/events/treemons.asm:199 GetTreeScore
do
  local Enc = require("src.battle.gen2.Encounter")
  eq(Enc.treeScore(5, 4, 12345), Enc.TREEMON_SCORE_GOOD,
    "diff 1..4 is a GOOD tree")
  eq(Enc.treeScore(5, 4, 17), Enc.TREEMON_SCORE_RARE,
    "diff 0 is the 1-in-10 RARE tree")
  eq(Enc.treeScore(5, 4, 0), Enc.TREEMON_SCORE_BAD, "diff 5..9 is BAD")
  check(Enc.treeScore(0, 0, 0) ~= Enc.treeScore(-4, -4, 0),
    "RefreshPlayerCoords' +4 is in the coordinate half")
  check(Enc.treeScore(5, 4, 12345) ~= Enc.treeScore(5, 4, 0),
    "and wPlayerID is in the other half")

  -- ../pokecrystal/engine/events/treemons.asm:96 GetTreeMons
  eq(Enc.treeSetUsable("TREEMON_SET_NONE", "crystal"), false,
    "TREEMON_SET_NONE never rolls")
  eq(Enc.treeSetUsable("TREEMON_SET_CITY", "crystal"), true,
    "Crystal has no CITY set to refuse")
  eq(Enc.treeSetUsable("TREEMON_SET_CITY", "gs"), false,
    "but G/S's CITY table is dead data")
  eq(Enc.treeSetUsable("TREEMON_SET_UNUSED", "gs"), false, "so is UNUSED")

  -- ../pokecrystal/engine/battle/core.asm:6422 CheckSleepingTreeMon
  eq(Enc.treeMonAsleep("SPEAROW", "NITE", "crystal"), true,
    "SPEAROW is on the Nite list")
  eq(Enc.treeMonAsleep("SPEAROW", "DARK", "crystal"), true,
    "DARKNESS_F falls through to Nite")
  eq(Enc.treeMonAsleep("SPEAROW", "DAY", "crystal"), false,
    "and is awake by day")
  eq(Enc.treeMonAsleep("HOOTHOOT", "DAY", "crystal"), true,
    "HOOTHOOT is on the Day list")
  eq(Enc.treeMonAsleep("HOOTHOOT", "DAY", "gs"), false,
    "pokegold has no asleep table at all")
end

-- ../pokecrystal/engine/events/treemons.asm:126 GetTreeMon's three gates
do
  local function headbutt(rolls, otId)
    local world = fakeWorld(treeCells, fakePlayer(5, 5, "up"), {
      { species = "HOOTHOOT", nickname = "OWL",
        moves = { { id = "HEADBUTT", pp = 15 } } },
    })
    world.game.save.player.id = otId
    local index = 0
    world.treemonRandom = function()
      index = index + 1
      return rolls[index] or 0
    end
    return world:tryHeadbutt(5, 4)
  end
  eq(headbutt({ 0 }, 0), "battle", "a BAD tree gives up a mon on a 0")
  eq(headbutt({ 1 }, 0), "nothing", "and nothing on a 1")
  eq(headbutt({ 4 }, 12345), "battle", "a GOOD tree still answers a 4")
  eq(headbutt({ 5 }, 12345), "nothing", "but not a 5")
  eq(headbutt({ 7 }, 17), "battle", "a RARE tree answers a 7")
  eq(headbutt({ 8 }, 17), "nothing", "and refuses an 8")
end

-- ---- C. the cave encounter gate ------------------------------------------
-- CanEncounterWildMon (engine/overworld/events.asm): a CAVE or DUNGEON map
-- skips CheckGrassCollision entirely, so any non-ice walkable tile rolls.
local FieldMoves = require("src.world.gen2.FieldMoves")
local Palettes = require("src.world.gen2.Palettes")

local COLL_TALL_GRASS, COLL_ICE = 0x18, 0x23
local COLL_CUT_TREE, COLL_WHIRLPOOL, COLL_WATERFALL = 0x12, 0x24, 0x33

local function canEncounter(env, coll, noWild)
  return FieldMoves.canEncounterWildMon(env, coll, noWild)
end

check(canEncounter("ROUTE", COLL_TALL_GRASS), "route + tall grass rolls")
check(not canEncounter("ROUTE", COLL_FLOOR), "route + bare floor does not")
check(canEncounter("CAVE", COLL_FLOOR), "CAVE floor rolls: no grass check")
check(canEncounter("DUNGEON", COLL_FLOOR), "DUNGEON floor rolls too")
check(not canEncounter("CAVE", COLL_ICE), "ice in a cave still refuses")
check(not canEncounter("ROUTE", COLL_ICE), "ice on a route refuses")
check(canEncounter("ROUTE", COLL_WATER), "COLL_WATER is in CheckGrassCollision")
check(not canEncounter("CAVE", COLL_FLOOR, true), "wildoff beats the cave arm")
check(not canEncounter("ROUTE", COLL_TALL_GRASS, true), "wildoff beats grass")
check(not canEncounter("INDOOR", COLL_FLOOR), "a house floor is not a cave")
-- The unused $10 / $1c grass aliases are NOT in the cart's array.
check(not canEncounter("ROUTE", 0x10), "COLL_TALL_GRASS_10 is not in the array")
check(Permissions.isGrass(0x10), "...even though it reads as grass")
eq(FieldMoves.encounterTable(COLL_WATER), "water", "water tile, water list")
eq(FieldMoves.encounterTable(COLL_TALL_GRASS), "grass", "grass tile, grass list")
eq(FieldMoves.encounterTable(COLL_FLOOR), "grass", "cave floor, grass list")

-- ...and the same thing through World:tryWildEncounter, which is where the
-- bug actually bit: Dark Cave and Union Cave gave nothing at all.
local ALWAYS = {
  grass = {
    TEST_MAP = {
      rates = { MORN = 256, DAY = 256, NITE = 256 },
      slots = {
        DAY = {}, MORN = {}, NITE = {},
      },
    },
  },
}
for _, key in ipairs({ "DAY", "MORN", "NITE" }) do
  for i = 1, 7 do
    ALWAYS.grass.TEST_MAP.slots[key][i] =
      { species = "HOOTHOOT", level = 5 }
  end
end

local PARTY_ONE = { { species = "MAGIKARP", nickname = "KARP",
  moves = { { id = "SPLASH", pp = 40 } } } }

local caveWorld = fakeWorld({}, fakePlayer(5, 5, "down"), PARTY_ONE, nil,
  { environment = "CAVE" })
caveWorld.encounters = ALWAYS
check(caveWorld:tryWildEncounter(), "a cave floor step rolls an encounter")
eq(caveWorld.log[1], "<battle:HOOTHOOT>", "and it is the grass list")

-- CheckWildEncounterCooldown (engine/overworld/events.asm:357-365), the first
-- thing RandomEncounter runs: EnterMap arms it with 5, and only the step that
-- ticks it to zero may roll.
caveWorld.wildCooldown = 5
for _ = 1, 4 do
  check(not caveWorld:tryWildEncounter(), "the five-step cooldown blocks a step")
end
check(caveWorld:tryWildEncounter(), "the fifth step rolls again")

local routeWorld = fakeWorld({}, fakePlayer(5, 5, "down"), PARTY_ONE, nil,
  { environment = "ROUTE" })
routeWorld.encounters = ALWAYS
check(not routeWorld:tryWildEncounter(), "the same step on a route does not")

local iceWorld = fakeWorld({ [5 * 100 + 5] = COLL_ICE },
  fakePlayer(5, 5, "down"), PARTY_ONE, nil, { environment = "CAVE" })
iceWorld.encounters = ALWAYS
check(not iceWorld:tryWildEncounter(), "ice inside a cave rolls nothing")

local offWorld = fakeWorld({}, fakePlayer(5, 5, "down"), PARTY_ONE, nil,
  { environment = "CAVE" })
offWorld.encounters = ALWAYS
offWorld.noWildEncounters = true
check(not offWorld:tryWildEncounter(), "wildoff stops the cave roll")

-- ---- D. badges and party moves -------------------------------------------
local function saveWith(badges)
  return { player = { name = "GOLD", badges = badges } }
end

check(FieldMoves.hasBadge(saveWith({ HIVE = true }), "HIVE"),
  "a badge keyed by name is owned")
check(FieldMoves.hasBadge(saveWith({ [2] = true }), "HIVE"),
  "...and so is one keyed by its wJohtoBadges position")
check(not FieldMoves.hasBadge(saveWith({ ZEPHYR = true }), "HIVE"),
  "a different badge is not the HIVEBADGE")
check(not FieldMoves.hasBadge({}, "HIVE"), "a save with no badges owns none")
eq(FieldMoves.BADGE.CUT, "HIVE", "CUT is the HIVEBADGE")
eq(FieldMoves.BADGE.FLASH, "ZEPHYR", "FLASH is the ZEPHYRBADGE")
eq(FieldMoves.BADGE.SURF, "FOG", "SURF is the FOGBADGE")
eq(FieldMoves.BADGE.STRENGTH, "PLAIN", "STRENGTH is the PLAINBADGE")
eq(FieldMoves.BADGE.FLY, "STORM", "FLY is the STORMBADGE")
eq(FieldMoves.BADGE.WHIRLPOOL, "GLACIER", "WHIRLPOOL is the GLACIERBADGE")
eq(FieldMoves.BADGE.WATERFALL, "RISING", "WATERFALL is the RISINGBADGE")

local CUTTER = { { species = "HOOTHOOT", nickname = "OWL",
  moves = { { id = "CUT", pp = 30 }, { id = "FLASH", pp = 20 } } } }
local mon, slot = FieldMoves.partyMoveUser(CUTTER, "CUT")
check(mon ~= nil, "CheckPartyMove finds the cutter")
eq(slot, 1, "and leaves its slot in wCurPartyMon")
check(FieldMoves.partyMoveUser(CUTTER, "SURF") == nil, "no SURF in the party")
check(FieldMoves.partyMoveUser(
  { { egg = true, moves = { { id = "CUT" } } } }, "CUT") == nil,
  "an EGG slot is skipped")

-- ---- E. the seven, from the party submenu --------------------------------
-- MonMenu_*: the badge is checked with the noisy CheckBadge, so every refusal
-- here has a line, and every success is QUEUED rather than run.
local ALL_BADGES = {
  ZEPHYR = true, HIVE = true, PLAIN = true, FOG = true,
  STORM = true, MINERAL = true, GLACIER = true, RISING = true,
}
local T = FieldMoves.TEXT

-- One johto tree block in the block the facing cell (5,4) sits in: bx 2, by 2
-- of a 10-wide grid, so blocks[2 * 10 + 2 + 1].
local TREE_BLOCK_INDEX = 2 * MAP_W + 2 + 1

local function fieldWorld(cells, party, opts)
  opts = opts or {}
  opts.badges = opts.badges == nil and ALL_BADGES or opts.badges
  local world, game = fakeWorld(cells, fakePlayer(5, 5, "up"), party, nil, opts)
  world.encounters = nil
  return world, game
end

-- CUT, refused: no HIVEBADGE.
local noHive = fieldWorld({ [4 * 100 + 5] = COLL_CUT_TREE }, CUTTER,
  { badges = { ZEPHYR = true },
    blocks = { [TREE_BLOCK_INDEX] = 0x5b } })
local res = noHive:useFieldMove("CUT", CUTTER[1])
check(not res.ok, "CUT with no HIVEBADGE is refused")
eq(res.badge, "HIVE", "and CheckBadge names the badge it wanted")
eq(noHive.log[1], T.BADGE_REQUIRED, "BadgeRequiredText is the line")
check(noHive.queuedFieldMove == nil, "nothing is queued")

-- CUT, refused: badge in hand, nothing in front worth cutting.
local nothingToCut = fieldWorld({}, CUTTER)
check(not nothingToCut:useFieldMove("CUT", CUTTER[1]).ok, "bare floor: no cut")
eq(nothingToCut.log[1], T.CUT_NOTHING, "CutNothingText is the line")

-- CUT, done.  The block swap waits for the text box, and the tree is a whole
-- BLOCK, not a tile.
local cutWorld = fieldWorld({ [4 * 100 + 5] = COLL_CUT_TREE }, CUTTER,
  { blocks = { [TREE_BLOCK_INDEX] = 0x5b } })
local cutRes = cutWorld:useFieldMove("CUT", CUTTER[1])
check(cutRes.ok, "CUT with the badge and a tree in front succeeds")
eq(#cutWorld.log, 0, "QueueScript says nothing while the menu is still up")
check(cutWorld.queuedFieldMove ~= nil, "the script is queued")
runFrames(cutWorld, 1)
eq(cutWorld.log[1], T.USE_CUT, "the queued script runs once the world is back")
eq(cutWorld.game.stringBuffer, "OWL", "GetPartyNickname filled {STRBUF}")
eq(cutWorld.map.def.blocks[TREE_BLOCK_INDEX], 0x5b, "the tree is still standing")
advanceText(cutWorld)
eq(cutWorld.map.def.blocks[TREE_BLOCK_INDEX], 0x3c,
  "CutDownTreeOrGrass swaps block $5b for $3c")
-- LoadMapAttributes refills the buffer from ROM: the tree grows back.
cutWorld:restoreBlocks()
eq(cutWorld.map.def.blocks[TREE_BLOCK_INDEX], 0x5b, "a map load regrows it")

-- CUT mows grass too, and picks that tileset's own replacement.
eq(select(1, FieldMoves.blockReplacement(
  FieldMoves.CUT_BLOCKS, "TILESET_JOHTO", 0x03)), 0x02, "johto grass -> $02")
eq(select(2, FieldMoves.blockReplacement(
  FieldMoves.CUT_BLOCKS, "TILESET_JOHTO", 0x03)), 1, "grass takes animation 1")
eq(select(2, FieldMoves.blockReplacement(
  FieldMoves.CUT_BLOCKS, "TILESET_JOHTO", 0x5b)), 0, "a tree takes animation 0")
check(FieldMoves.blockReplacement(
  FieldMoves.CUT_BLOCKS, "TILESET_CAVE", 0x03) == nil,
  "a tileset with no CutTreeBlockPointers row cuts nothing")

-- FLASH: the ZEPHYRBADGE, and only on a DARKNESS_PALSET map.
local FLASHER = { { species = "HOOTHOOT", nickname = "OWL",
  moves = { { id = "FLASH", pp = 20 } } } }
local litWorld = fieldWorld({}, FLASHER, { environment = "CAVE" })
check(not litWorld:useFieldMove("FLASH", FLASHER[1]).ok,
  "FLASH in a lit cave is refused")
eq(litWorld.log[1], T.CANT_USE_HERE, "and it is FieldMoveFailed's line")

local darkWorld = fieldWorld({}, FLASHER,
  { environment = "CAVE", palette = "PALETTE_DARK" })
check(not darkWorld.flashUsed, "a dark map starts unflashed")
eq(Palettes.daytimeFor(darkWorld.map.def, 12, false), "DARK",
  "PALETTE_DARK resolves to the DARK palette row")
check(darkWorld:useFieldMove("FLASH", FLASHER[1]).ok, "FLASH in the dark works")
runFrames(darkWorld, 1)
eq(darkWorld.log[1], T.BLINDING_FLASH, "BlindingFlashText")
advanceText(darkWorld)
check(darkWorld.flashUsed, "BlindingFlash sets STATUSFLAGS_FLASH_F")
eq(Palettes.daytimeFor(darkWorld.map.def, 12, true), "NITE",
  "and a flashed dark map reads as NITE")
check(not darkWorld:useFieldMove("FLASH", FLASHER[1]).ok,
  "a second FLASH in the same cave is refused")

local noZephyr = fieldWorld({}, FLASHER,
  { badges = {}, environment = "CAVE", palette = "PALETTE_DARK" })
eq(noZephyr:useFieldMove("FLASH", FLASHER[1]).badge, "ZEPHYR",
  "FLASH without the ZEPHYRBADGE is refused first")

-- FLY: outdoors only.
local FLYER = { { species = "HOOTHOOT", nickname = "OWL",
  moves = { { id = "FLY", pp = 15 } } } }
local indoorFly = fieldWorld({}, FLYER, { environment = "INDOOR" })
check(not indoorFly:useFieldMove("FLY", FLYER[1]).ok, "no FLY indoors")
eq(indoorFly.log[1], T.CANT_USE_HERE, "and it is the generic refusal")
check(not fieldWorld({}, FLYER, { environment = "CAVE" })
  :useFieldMove("FLY", FLYER[1]).ok, "no FLY in a cave either")
check(fieldWorld({}, FLYER, { environment = "TOWN" })
  :useFieldMove("FLY", FLYER[1]).ok, "FLY works in a town")
check(fieldWorld({}, FLYER, { environment = "ROUTE" })
  :useFieldMove("FLY", FLYER[1]).ok, "...and on a route")
eq(fieldWorld({}, FLYER, { badges = {}, environment = "ROUTE" })
  :useFieldMove("FLY", FLYER[1]).badge, "STORM", "FLY wants the STORMBADGE")

-- Flypoints: Johto's twelve rows, filtered by what has been visited.
local LANDMARKS = {
  landmarks = {
    LANDMARK_NEW_BARK_TOWN = { index = 1, name = "NEW BARK\nTOWN" },
    LANDMARK_VIOLET_CITY = { index = 5, name = "VIOLET CITY" },
    LANDMARK_INDIGO_PLATEAU = { index = 63, name = "INDIGO\nPLATEAU" },
  },
  spawns = {
    SPAWN_NEW_BARK = { map = "NEW_BARK_TOWN", x = 4, y = 5 },
    SPAWN_VIOLET = { map = "VIOLET_CITY", x = 9, y = 21 },
  },
}
local flySave = { player = { badges = ALL_BADGES },
  visitedSpawns = { SPAWN_NEW_BARK = true } }
local points = FieldMoves.flyPoints(flySave, LANDMARKS, "johto")
eq(#points, 1, "only visited flypoints are offered")
eq(points[1].spawn, "SPAWN_NEW_BARK", "and it is the one that was visited")
flySave.visitedSpawns.SPAWN_VIOLET = true
points = FieldMoves.flyPoints(flySave, LANDMARKS, "johto")
eq(#points, 2, "a second visit adds a second row")
eq(points[2].landmark, "LANDMARK_VIOLET_CITY", "in Flypoints order")
-- Kanto is withheld until Indigo Plateau is on the record, or the picker has
-- no legal cursor position at all.
eq(#FieldMoves.flyPoints(flySave, LANDMARKS, "kanto"), 2,
  "standing in Kanto with no Indigo flypoint shows the Johto map")
flySave.visitedSpawns.SPAWN_INDIGO = true
eq(#FieldMoves.flyPoints(flySave, LANDMARKS, "kanto"), 1,
  "with Indigo visited the Kanto half takes over")
eq(FieldMoves.FLYPOINTS[FieldMoves.KANTO_FLYPOINT].spawn, "SPAWN_PALLET",
  "KANTO_FLYPOINT is the Pallet Town row")
eq(#FieldMoves.FLYPOINTS, 24, "Flypoints has 24 rows")

-- The real path: MAPCALLBACK_NEWMAP's `setflag ENGINE_FLYPOINT_*` lands on
-- save.engineFlags[id] (Vm.lua's setflag), and that is what the menu now
-- reads first -- visitedSpawns is only the fallback for a save that predates
-- this.
local engineSave = { player = { badges = ALL_BADGES }, engineFlags = {} }
eq(#FieldMoves.flyPoints(engineSave, LANDMARKS, "johto"), 0,
  "no engine flags set yet: nothing offered")
engineSave.engineFlags[64] = true -- ENGINE_FLYPOINT_NEW_BARK
local enginePoints = FieldMoves.flyPoints(engineSave, LANDMARKS, "johto")
eq(#enginePoints, 1, "the engine flag alone is enough")
eq(enginePoints[1].spawn, "SPAWN_NEW_BARK", "and it is the right spawn")
-- A save with BOTH an engine flag and stale visitedSpawns trusts the engine
-- flag, even when it disagrees -- an explicit false beats a leftover true.
engineSave.visitedSpawns = { SPAWN_VIOLET = true }
engineSave.engineFlags[66] = false -- ENGINE_FLYPOINT_VIOLET, explicitly unset
eq(#FieldMoves.flyPoints(engineSave, LANDMARKS, "johto"), 1,
  "an explicit engine-flag false overrides a stale visitedSpawns true")

-- STRENGTH from the menu: the badge and nothing else.
local LIFTER = { { species = "HOOTHOOT", nickname = "OWL",
  moves = { { id = "STRENGTH", pp = 15 } } } }
local strWorld = fieldWorld({}, LIFTER)
check(strWorld:useFieldMove("STRENGTH", LIFTER[1]).ok,
  "STRENGTH off the menu only wants the PLAINBADGE")
runFrames(strWorld, 1)
check(strWorld.strengthActive, "SetStrengthFlag runs before the text")
eq(strWorld.log[1], T.USE_STRENGTH, "UseStrengthText")
advanceText(strWorld)
check(strWorld.fieldMove ~= nil, "then `pause 3`")
runFrames(strWorld, 4)
eq(strWorld.log[2], T.MOVE_BOULDER, "MoveBoulderText follows the pause")
eq(fieldWorld({}, LIFTER, { badges = {} })
  :useFieldMove("STRENGTH", LIFTER[1]).badge, "PLAIN", "STRENGTH wants PLAIN")

-- WATERFALL: facing UP at one, and only then.
local CLIMBER = { { species = "MAGIKARP", nickname = "KARP",
  moves = { { id = "WATERFALL", pp = 15 } } } }
local fallCells = { [4 * 100 + 5] = COLL_WATERFALL, [3 * 100 + 5] = COLL_WATERFALL }
local flatWorld = fieldWorld({}, CLIMBER)
check(not flatWorld:useFieldMove("WATERFALL", CLIMBER[1]).ok,
  "no waterfall above: refused")
local sideWorld = fieldWorld(fallCells, CLIMBER)
sideWorld.player.facing = "left"
check(not sideWorld:useFieldMove("WATERFALL", CLIMBER[1]).ok,
  "facing away from the waterfall: refused")
check(FieldMoves.waterfallContinues(COLL_WATERFALL),
  "the climb continues while the tile underfoot is a waterfall")
check(FieldMoves.waterfallContinues(0x3b),
  "COLL_CURRENT_DOWN counts as a waterfall tile too")
check(not FieldMoves.waterfallContinues(COLL_WATER), "plain water ends it")

-- WHIRLPOOL: the block table, not just the collision.
local SPINNER = { { species = "MAGIKARP", nickname = "KARP",
  moves = { { id = "WHIRLPOOL", pp = 15 } } } }
local poolWorld = fieldWorld({ [4 * 100 + 5] = COLL_WHIRLPOOL }, SPINNER,
  { blocks = { [TREE_BLOCK_INDEX] = 0x07 } })
check(poolWorld:useFieldMove("WHIRLPOOL", SPINNER[1]).ok, "whirlpool cleared")
runFrames(poolWorld, 1)
eq(poolWorld.log[1], T.USE_WHIRLPOOL, "UseWhirlpoolText")
advanceText(poolWorld)
-- engine/events/overworld.asm:1142-1164
eq(poolWorld.map.def.blocks[TREE_BLOCK_INDEX], 0x07,
  "the whirlpool block is still on screen while the sfx plays (#1862)")
runFrames(poolWorld, 4)
eq(poolWorld.map.def.blocks[TREE_BLOCK_INDEX], 0x36,
  "DisappearWhirlpool swaps block $07 for $36 once the sfx ends")
local wrongBlock = fieldWorld({ [4 * 100 + 5] = COLL_WHIRLPOOL }, SPINNER)
check(not wrongBlock:useFieldMove("WHIRLPOOL", SPINNER[1]).ok,
  "a whirlpool collision over the wrong block is refused")

-- A move the port has no routine for still answers the way the cart does.
check(not fieldWorld({}, CUTTER):useFieldMove("DIG", CUTTER[1]).ok,
  "DIG is not ported and lands on FieldMoveFailed")

-- ---- E2. SWEET_SCENT -------------------------------------------------------
-- SweetScentFromMenu (engine/events/sweet_scent.asm): no badge, no facing
-- tile test at all -- QueueScript always succeeds, and whether anything is
-- home is answered by the queued script once the menus are gone, same as
-- HEADBUTT's shake.
-- `do`/`end`-scoped: the file is one big chunk and LuaJIT's main function
-- caps at 200 live locals, so a fresh block of world/game fixtures has to
-- free its slots at `end` rather than pile onto the running total.
do
local SCENTER = { { species = "HOOTHOOT", nickname = "OWL",
  moves = { { id = "SWEET_SCENT", pp = 20 } } } }
local NOTHING_HERE = "Looks like there's\nnothing here…"

local bareScent, bareGame = fieldWorld({}, SCENTER)
bareScent.encounters = nil
check(bareScent:useFieldMove("SWEET_SCENT", SCENTER[1]).ok,
  "SWEET SCENT always queues")
eq(#bareScent.log, 0, "QueueScript says nothing while the menu is still up")
runFrames(bareScent, 1)
eq(bareScent.log[1], "{STRBUF} used\nSWEET SCENT!",
  "UseSweetScentText names the mon")
eq(bareGame.stringBuffer, "OWL", "GetPartyNickname fills wStringBuffer2")
advanceText(bareScent)
eq(bareScent.log[2], NOTHING_HERE,
  "no encounter table on this map: SweetScentNothingText")

-- A grass tile with a nonzero rate: ChooseWildEncounter runs unconditionally,
-- with no percentage roll of its own -- the whole point of the move.
local grassScent = fieldWorld({ [5 * 100 + 5] = COLL_TALL_GRASS }, SCENTER)
grassScent.encounters = ALWAYS
check(grassScent:useFieldMove("SWEET_SCENT", SCENTER[1]).ok)
runFrames(grassScent, 1)
advanceText(grassScent)
eq(grassScent.log[2], "<battle:HOOTHOOT>",
  "SweetScentEncounter forces a battle off the current tile's table")

-- Bare floor on a ROUTE: CanEncounterWildMon still refuses (no grass, no
-- water) -- SWEET SCENT does not walk through that gate, it only skips the
-- roll behind it.
local floorScent = fieldWorld({}, SCENTER)
floorScent.encounters = ALWAYS
check(floorScent:useFieldMove("SWEET_SCENT", SCENTER[1]).ok)
runFrames(floorScent, 1)
advanceText(floorScent)
eq(floorScent.log[2], NOTHING_HERE, "bare ROUTE floor still refuses the roll")

-- wildoff (STATUSFLAGS_NO_WILD_ENCOUNTERS_F) beats SWEET SCENT the same way
-- it beats a step.
local offScent = fieldWorld({ [5 * 100 + 5] = COLL_TALL_GRASS }, SCENTER)
offScent.encounters = ALWAYS
offScent.noWildEncounters = true
check(offScent:useFieldMove("SWEET_SCENT", SCENTER[1]).ok)
runFrames(offScent, 1)
advanceText(offScent)
eq(offScent.log[2], NOTHING_HERE, "wildoff refuses too")

-- ENGINE_BUG_CONTEST_TIMER: farsjump's straight past GetMapEncounterRate to
-- the park's own table, same branch RandomEncounter takes on a normal step.
-- A one-row ContestMons list so the pick is deterministic without adding
-- CATERPIE and friends to the shared DATA fixture every other case here uses.
local contestScent = fieldWorld({ [5 * 100 + 5] = COLL_TALL_GRASS }, SCENTER)
contestScent.encounters = ALWAYS
contestScent.game.save.bugContest = { active = true }
contestScent.game.data = {
  items = DATA.items, moves = DATA.moves, pokemon = DATA.pokemon,
  encounters = { bugContest = {
    { chance = 1000, species = "HOOTHOOT", min = 5, max = 5 },
  } },
}
check(contestScent:useFieldMove("SWEET_SCENT", SCENTER[1]).ok)
runFrames(contestScent, 1)
advanceText(contestScent)
check(contestScent.log[2]:match("^<battle:"),
  "the contest's own table runs, not the map's grass list")
end

-- ---- F. the same seven, from an A press ----------------------------------
-- Try*OW: the MOVE is checked first and the badge silently, so the refusals
-- are the tile's own lines, not "a new BADGE is required".
local owNoCut = fieldWorld({ [4 * 100 + 5] = COLL_CUT_TREE },
  { { species = "MAGIKARP", moves = { { id = "SPLASH" } } } },
  { blocks = { [TREE_BLOCK_INDEX] = 0x5b } })
check(owNoCut:interact(), "a cut tree takes the A press even with no cutter")
eq(owNoCut.log[1], T.CAN_CUT, "CanCutText, not the badge line")

local owNoBadge = fieldWorld({ [4 * 100 + 5] = COLL_CUT_TREE }, CUTTER,
  { badges = {}, blocks = { [TREE_BLOCK_INDEX] = 0x5b } })
check(owNoBadge:interact(), "and with the mon but no badge it still answers")
eq(owNoBadge.log[1], T.CAN_CUT, "CheckEngineFlag is the silent check")

local owCut = fieldWorld({ [4 * 100 + 5] = COLL_CUT_TREE }, CUTTER,
  { blocks = { [TREE_BLOCK_INDEX] = 0x5b } })
check(owCut:interact(), "the A press opens AskCutScript")
eq(owCut.log[1], T.ASK_CUT, "AskCutText")
advanceText(owCut)
eq(owCut.log[2], "<yesno>", "and it is a yesorno")
answerYesNo(owCut, false)
eq(#owCut.log, 2, "NO closes it and cuts nothing")
eq(owCut.map.def.blocks[TREE_BLOCK_INDEX], 0x5b, "the tree is untouched")

local owCut2 = fieldWorld({ [4 * 100 + 5] = COLL_CUT_TREE }, CUTTER,
  { blocks = { [TREE_BLOCK_INDEX] = 0x5b } })
owCut2:interact()
advanceText(owCut2)
answerYesNo(owCut2, true)
eq(owCut2.log[3], T.USE_CUT, "YES runs Script_Cut on the spot (CallScript)")
advanceText(owCut2)
eq(owCut2.map.def.blocks[TREE_BLOCK_INDEX], 0x3c, "and the tree comes down")

-- WHIRLPOOL, from the water.
local owPool = fieldWorld({ [4 * 100 + 5] = COLL_WHIRLPOOL }, SPINNER,
  { blocks = { [TREE_BLOCK_INDEX] = 0x07 } })
check(owPool:interact(), "a whirlpool takes the press")
eq(owPool.log[1], T.ASK_WHIRLPOOL, "AskWhirlpoolText")
local owPoolNo = fieldWorld({ [4 * 100 + 5] = COLL_WHIRLPOOL },
  { { species = "MAGIKARP", moves = { { id = "SPLASH" } } } },
  { blocks = { [TREE_BLOCK_INDEX] = 0x07 } })
check(owPoolNo:interact(), "and refuses with a line rather than silence")
eq(owPoolNo.log[1], T.MAY_PASS_WHIRLPOOL, "MayPassWhirlpoolText")

-- WATERFALL, from the bottom.
local owFall = fieldWorld(fallCells, CLIMBER)
check(owFall:interact(), "a waterfall takes the press")
eq(owFall.log[1], T.ASK_WATERFALL, "AskWaterfallText")
local owFallNo = fieldWorld(fallCells,
  { { species = "MAGIKARP", moves = { { id = "SPLASH" } } } })
check(owFallNo:interact(), "with no climber it still answers")
eq(owFallNo.log[1], T.HUGE_WATERFALL, "HugeWaterfallText")

-- The climb itself: Script_UsedWaterfall loops one turn_waterfall UP step at a
-- time and stops only once the tile UNDERFOOT is no longer a waterfall tile.
local PlayerModule = require("src.world.gen2.Player")
local climbCells = {
  [4 * 100 + 5] = COLL_WATERFALL,
  [3 * 100 + 5] = COLL_WATERFALL,
  [2 * 100 + 5] = COLL_WATER,
}
local climb = fakeWorld(climbCells, PlayerModule.new(5, 5, "up"), CLIMBER, nil,
  { badges = ALL_BADGES })
climb.encounters = nil
check(climb:interact(), "the waterfall takes the press")
advanceText(climb)
answerYesNo(climb, true)
eq(climb.log[3], T.USE_WATERFALL, "UseWaterfallText")
advanceText(climb)
check(climb.fieldMove ~= nil, "and then the climb owns the world")
check(climb:busy(), "nothing else runs during it")
runFrames(climb, 60)
eq(climb.player.cellY, 2, "the climb stops on the first non-waterfall tile")
check(climb.fieldMove == nil, "and hands the world back")
check(not climb:busy(), "the world is free again")

-- ---- G. SURF, the player state -------------------------------------------
local RealPlayer = require("src.world.gen2.Player")
local SURFER = { { species = "MAGIKARP", nickname = "KARP",
  moves = { { id = "SURF", pp = 15 } } } }

check(not FieldMoves.isSurfing(FieldMoves.PLAYER_NORMAL), "normal is not surf")
check(FieldMoves.isSurfing(FieldMoves.PLAYER_SURF), "PLAYER_SURF is")
check(FieldMoves.isSurfing(FieldMoves.PLAYER_SURF_PIKA), "so is the Pika one")
eq(FieldMoves.surfType({ species = "PIKACHU" }), FieldMoves.PLAYER_SURF_PIKA,
  "GetSurfType gives PIKACHU its own state")
eq(FieldMoves.surfType({ species = "LAPRAS" }), FieldMoves.PLAYER_SURF,
  "and everything else the ordinary one")
eq(FieldMoves.STATE_SPRITE[FieldMoves.PLAYER_SURF], "SPRITE_SURF",
  "ChrisStateSprites maps PLAYER_SURF to SPRITE_SURF")

local seaCells = {
  [4 * 100 + 5] = COLL_WATER,
  [3 * 100 + 5] = COLL_WATER,
}

-- No SURF mon: TrySurfOW's every failure is `.quit`, so the press is silent.
local dryShore = fakeWorld(seaCells, fakePlayer(5, 5, "up"),
  { { species = "HOOTHOOT", moves = { { id = "TACKLE" } } } }, nil,
  { badges = ALL_BADGES })
dryShore.encounters = nil
check(not dryShore:interact(), "water with no SURF mon drops the press")
eq(#dryShore.log, 0, "and says nothing at all")

local noFog = fakeWorld(seaCells, fakePlayer(5, 5, "up"), SURFER, nil,
  { badges = { ZEPHYR = true } })
noFog.encounters = nil
check(not noFog:interact(), "no FOGBADGE is just as silent")
eq(#noFog.log, 0, "CheckEngineFlag never prints")

local sea = fakeWorld(seaCells, RealPlayer.new(5, 5, "up"), SURFER, nil,
  { badges = ALL_BADGES })
sea.encounters = nil
check(sea:interact(), "with the badge and the mon, AskSurfScript opens")
eq(sea.log[1], T.ASK_SURF, "AskSurfText")
advanceText(sea)
answerYesNo(sea, true)
eq(sea.log[3], T.USED_SURF, "UsedSurfText")
eq(sea.playerState, FieldMoves.PLAYER_NORMAL, "still on foot behind the text")
advanceText(sea)
eq(sea.playerState, FieldMoves.PLAYER_SURF, "then wPlayerState becomes SURF")
check(sea.player.moving, "SurfStartStep walks into the water")
check(sea:busy(), "and the world is frozen for it")
runFrames(sea, 20)
eq(sea.player.cellY, 4, "the step lands on the water tile")
check(not sea:busy(), "and the world comes back")

-- NO at the shore leaves the player on foot.
local declined = fakeWorld(seaCells, RealPlayer.new(5, 5, "up"), SURFER, nil,
  { badges = ALL_BADGES })
declined.encounters = nil
check(declined:interact(), "the ask opens again")
advanceText(declined)
answerYesNo(declined, false)
eq(declined.playerState, FieldMoves.PLAYER_NORMAL, "NO stays on the bank")
eq(declined.player.cellY, 5, "and takes no step")

-- Surfing, a step across open water is an ordinary step...
eq(sea:movePlayer("up"), "moved", "a surfing step onto water is allowed")
for _ = 1, 16 do sea.player:update() end
eq(sea.player.cellY, 3, "and it lands")
eq(sea.playerState, FieldMoves.PLAYER_SURF, "still surfing")

-- ...and a step onto LAND is .ExitWater, which puts the state back BEFORE the
-- step rather than after it.
sea.player.facing = "down"
sea.player.turnArmed = false
eq(sea:movePlayer("down"), "moved", "and back down over the water")
for _ = 1, 16 do sea.player:update() end
eq(sea.player.cellY, 4, "one cell short of the beach")
eq(sea.playerState, FieldMoves.PLAYER_SURF, "still afloat over water")
eq(sea:movePlayer("down"), "moved", "a surfing step onto land is allowed too")
eq(sea.playerState, FieldMoves.PLAYER_NORMAL,
  "GetOutOfWater runs before .DoStep")

-- A wall is neither land nor water: .CheckSurfPerms bumps.
local walled = fakeWorld({ [4 * 100 + 5] = COLL_WATER,
  [3 * 100 + 5] = 0x07 }, RealPlayer.new(5, 4, "up"), SURFER, nil,
  { badges = ALL_BADGES })
walled.encounters = nil
walled.playerState = FieldMoves.PLAYER_SURF
eq(walled:movePlayer("up"), "blocked", "a wall stops a surfing step")
eq(Permissions.surfable(COLL_WATER), "water", "water keeps you surfing")
eq(Permissions.surfable(COLL_FLOOR), "land", "land is .ExitWater")
check(Permissions.surfable(0x07) == nil, "a wall is neither")

-- Already surfing, the menu says so rather than trying again.
local afloat = fieldWorld(seaCells, SURFER)
afloat.playerState = FieldMoves.PLAYER_SURF
eq(afloat:useFieldMove("SURF", SURFER[1]).text, T.ALREADY_SURFING,
  "AlreadySurfingText comes before the tile check")
afloat.playerState = FieldMoves.PLAYER_NORMAL
local ashore = fieldWorld({}, SURFER)
eq(ashore:useFieldMove("SURF", SURFER[1]).text, T.CANT_SURF,
  "and dry land is CantSurfText")

-- Encounters roll while surfing: the tile underfoot is water, so the gate
-- passes on CheckGrassCollision's COLL_WATER row and the WATER list is rolled.
local surfEnc = fakeWorld({ [5 * 100 + 5] = COLL_WATER },
  fakePlayer(5, 5, "down"), PARTY_ONE, nil, { environment = "ROUTE" })
surfEnc.playerState = FieldMoves.PLAYER_SURF
surfEnc.encounters = {
  water = { TEST_MAP = { rate = 256,
    slots = { { species = "MAGIKARP", level = 20 },
      { species = "MAGIKARP", level = 20 },
      { species = "MAGIKARP", level = 20 } } } },
}
check(surfEnc:tryWildEncounter(), "a surfing step rolls")
eq(surfEnc.log[1], "<battle:MAGIKARP>", "off the water list")

-- ...and fishing does not: .TryFish reads wPlayerState first.
local rodAfloat = fakeWorld({ [4 * 100 + 5] = COLL_WATER },
  fakePlayer(5, 5, "up"), SURFER)
rodAfloat.playerState = FieldMoves.PLAYER_SURF
eq(rodAfloat:useRod("OLD_ROD"), "nowhere", "no fishing from the water")

-- ---- H. STRENGTH and the boulder -----------------------------------------
local function fakeBoulder(x, y)
  return {
    def = { index = 1, movement = 0x19 }, -- SPRITEMOVEDATA_STRENGTH_BOULDER
    cellX = x, cellY = y, px = x * 16, py = y * 16,
    moving = false, facing = "down",
    scriptStep = function(self, dir)
      local d = Map.DELTA[dir]
      self.facing = dir
      self.targetX, self.targetY = self.cellX + d[1], self.cellY + d[2]
      self.moving = true
      return true
    end,
    update = function() end,
  }
end

check(World.isStrengthBoulder({ def = { movement = 0x19 } }),
  "SPRITEMOVEDATA_STRENGTH_BOULDER is a boulder")
check(not World.isStrengthBoulder({ def = { movement = 0x18 } }),
  "SPRITEMOVEDATA_SMASHABLE_ROCK is not")

local function boulderWorld(party, badges)
  local world = fieldWorld({}, party, { badges = badges })
  local rock = fakeBoulder(5, 4)
  world.npcs = { rock }
  world.entities = { world.player, rock }
  return world, rock
end

-- Talking to a boulder with no STRENGTH mon: BouldersMayMoveText.
local rockNoMon, _ = boulderWorld(
  { { species = "MAGIKARP", moves = { { id = "SPLASH" } } } })
check(rockNoMon:interact(), "a boulder answers the A press")
eq(rockNoMon.log[1], T.BOULDERS_MAY_MOVE, "BouldersMayMoveText")

-- With the mon and the badge, AskStrengthScript.
local rockWorld, rock = boulderWorld(LIFTER)
check(rockWorld:interact(), "and offers STRENGTH")
eq(rockWorld.log[1], T.ASK_STRENGTH, "AskStrengthText")
advanceText(rockWorld)
answerYesNo(rockWorld, true)
check(rockWorld.strengthActive, "YES sets BIKEFLAGS_STRENGTH_ACTIVE")
eq(rockWorld.log[3], T.USE_STRENGTH, "UseStrengthText")
advanceText(rockWorld)
runFrames(rockWorld, 4)
eq(rockWorld.log[4], T.MOVE_BOULDER, "MoveBoulderText")
advanceText(rockWorld)

-- Already on: the third of TryStrengthOW's three answers.
check(rockWorld:interact(), "a second press still answers")
eq(rockWorld.log[5], T.BOULDERS_MOVE, "BouldersMoveText once STRENGTH is on")

-- The push itself.  The boulder moves; the player bumps.
check(not rock.moving, "the boulder is standing")
check(rockWorld:tryPushBoulder("up", 5, 4), "walking into it pushes it")
eq(rock.targetY, 3, "one cell in the walking direction")
eq(rockWorld.player.cellY, 5, "and the player does not move")
check(not rockWorld:tryPushBoulder("up", 5, 4), "a moving boulder is not pushed")

-- No STRENGTH, no push.
local coldWorld, coldRock = boulderWorld(LIFTER)
check(not coldWorld:tryPushBoulder("up", 5, 4),
  "without BIKEFLAGS_STRENGTH_ACTIVE nothing moves")
check(not coldRock.moving, "the boulder stays put")

-- A boulder against a wall does not move (CanObjectMoveInDirection).
local pinned = fieldWorld({ [3 * 100 + 5] = 0x07 }, LIFTER)
local pinnedRock = fakeBoulder(5, 4)
pinned.npcs = { pinnedRock }
pinned.entities = { pinned.player, pinnedRock }
pinned.strengthActive = true
check(not pinned:tryPushBoulder("up", 5, 4), "a boulder against a wall holds")

-- ---- I. the party submenu's field-move row -------------------------------
-- MonMenu_Cut's $2 / $3 return, through the screen a player actually uses:
-- the row is picked, the world queues the script, and the party list plus the
-- START menu behind it are torn down so the overworld can run it.
local PartyMenu = require("src.ui.gen2.PartyMenu")

local menuWorld, menuGame = fieldWorld({ [4 * 100 + 5] = COLL_CUT_TREE },
  CUTTER, { blocks = { [TREE_BLOCK_INDEX] = 0x5b } })
menuGame.input = stubInput()
menuGame.stack = stubStack()
local list = PartyMenu.new(menuGame, { party = CUTTER, submenu = true })
local rows = list:submenuItems(CUTTER[1])
eq(rows[1].id, "CUT", "a mon that knows CUT gets a CUT row first")
check(rows[1].fieldMove, "and it is flagged as a field move")
eq(rows[2].id, "FLASH", "FIELD_MOVES order, not the mon's move order")
menuGame.input:press("a")
list:update(0)
check(list.submenu ~= nil, "A on the mon opens PokemonActionSubmenu")
menuGame.input:press("a")
list:update(0)
check(menuWorld.queuedFieldMove ~= nil, "CUT queues its script")
eq(menuGame.stack.cleared, 1, "and the $2 return clears the menus off")

-- A refusal is the $3 return: the line prints and the list stays.
local menuFail, failGame = fieldWorld({}, CUTTER)
failGame.input = stubInput()
failGame.stack = stubStack()
local failList = PartyMenu.new(failGame, { party = CUTTER, submenu = true })
failGame.input:press("a")
failList:update(0)
failGame.input:press("a")
failList:update(0)
check(menuFail.queuedFieldMove == nil, "nothing to cut queues nothing")
eq(menuFail.log[1], T.CUT_NOTHING, "the refusal prints over the list")
eq(failGame.stack.cleared, 0, "and the party list stays open")

-- ---- J. the dark cave -----------------------------------------------------
-- There is no vision mask in Gen 2: the whole map resolves to near-black
-- through the ordinary bake, and FlickeringCaveEntrancePalette blinks
-- PAL_BG_YELLOW's color 0 between its own two colours on a four-frame cycle.
eq(Palettes.PAL_BG_YELLOW, 5, "PAL_BG_YELLOW is the fifth 1-based slot")
eq(Palettes.caveFlickerSource(0), 1, "frame 0 leaves color 0 alone")
eq(Palettes.caveFlickerSource(1), 1, "...and so does frame 1")
eq(Palettes.caveFlickerSource(2), 2, "frame 2 copies color 1 into it")
eq(Palettes.caveFlickerSource(3), 2, "...and so does frame 3")
eq(Palettes.FLICKER_PERIOD, 4, "the cycle is four frames long")

local DARK_SET = {}
for slot = 1, 8 do
  DARK_SET[slot] = { { 8, 8, 16 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
end
DARK_SET[Palettes.PAL_BG_YELLOW] =
  { { 247, 247, 90 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
local lit = Palettes.withCaveFlicker(DARK_SET, 1)
eq(lit[Palettes.PAL_BG_YELLOW][1][1], 247, "phase 1 keeps the entrance lit")
local unlit = Palettes.withCaveFlicker(DARK_SET, 2)
eq(unlit[Palettes.PAL_BG_YELLOW][1][1], 0, "phase 2 blinks it out")
eq(unlit[1][1][1], 8, "and no other palette moves")
eq(DARK_SET[Palettes.PAL_BG_YELLOW][1][1], 247, "the source set is untouched")
check(Palettes.isDarkness({ palette = "PALETTE_DARK" }, 12, false),
  "an unflashed PALETTE_DARK map is DARKNESS_PALSET")
check(not Palettes.isDarkness({ palette = "PALETTE_DARK" }, 12, true),
  "...and a flashed one is not")
check(not Palettes.isDarkness({ palette = "PALETTE_NITE" }, 12, false),
  "a merely dim cave is not DARKNESS_PALSET")

-- ResetFlashIfOutOfCave: the flag survives cave-to-cave and dies outdoors.
eq(Permissions.isCutTree(0x12), true, "COLL_CUT_TREE")
eq(Permissions.isCutTree(0x1a), true, "COLL_CUT_TREE_1A alias")
check(not Permissions.isCutTree(0x15), "a headbutt tree is not a cut tree")
check(Permissions.isWhirlpool(0x24) and Permissions.isWhirlpool(0x2c),
  "both whirlpool collisions")
check(Permissions.isWaterfall(0x33) and Permissions.isWaterfall(0x3b),
  "COLL_WATERFALL and COLL_CURRENT_DOWN")
check(Permissions.isIce(0x23) and Permissions.isIce(0x2b), "both ice tiles")
check(Permissions.isCuttable(0x18) and Permissions.isCuttable(0x12),
  "CUT swings at grass and at trees")
check(not Permissions.isCuttable(0x15), "but not at a headbutt tree")

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end

local mapsPath = cache .. "/data/generated/maps.lua"
local mapsFile = io.open(mapsPath, "r")
if not mapsFile then
  check(true, "gold cache absent : permission checks only (SKIP map facts)")
  S.finish()
  return
end
mapsFile:close()

local function loadLua(rel)
  local path = cache .. "/" .. rel
  return assert(loadfile(path))()
end

local maps = loadLua("data/generated/maps.lua")
local tilesets = loadLua("data/generated/tilesets.lua")
local town = Map.new(maps.NEW_BARK_TOWN, tilesets[maps.NEW_BARK_TOWN.tileset])

eq(town.widthCells, 20, "New Bark width cells")
eq(town.heightCells, 18, "New Bark height cells")
check(town:isWalkable(13, 6), "south of player house walkable")
check(not town:isWalkable(0, 0), "corner wall blocked")
eq(town:cellCollision(6, 3), 0x71, "Elm door COLL_DOOR")
eq(town:warpAt(6, 3).def.destMap, "ELMS_LAB", "Elm door → ELMS_LAB")
eq(town:warpAt(13, 5).def.destMap, "PLAYERS_HOUSE_1F", "house door")

-- The four cell predicates a mod binds to, shared with src/world/Map.lua so one
-- placement routine reads either generation's map (src/world/gen2/Map.lua).
-- Without them a mod guarding on `map.isWalkableCell and ...` silently decides
-- every cell is walkable, dry and grassless.
do
  local Permissions = require("src.world.gen2.Permissions")
  local walkAgrees, waterAgrees, grassAgrees = true, true, true
  local sawGrass = false
  for cy = 0, town.heightCells - 1 do
    for cx = 0, town.widthCells - 1 do
      local coll = town:cellCollision(cx, cy)
      if town:isWalkableCell(cx, cy) ~= town:isWalkable(cx, cy) then
        walkAgrees = false
      end
      if town:isWaterCell(cx, cy) ~= Permissions.isWater(coll) then
        waterAgrees = false
      end
      if town:isGrassCell(cx, cy) ~= Permissions.isGrass(coll) then
        grassAgrees = false
      end
    end
  end
  check(walkAgrees, "isWalkableCell tracks isWalkable")
  check(waterAgrees, "isWaterCell tracks the WATER permission")
  check(grassAgrees, "isGrassCell tracks the grass collisions")
  -- and it actually answers true somewhere: New Bark Town is paved, so the
  -- route next door is where a mod's placement code would look for grass
  local route29 = Map.new(maps.ROUTE_29, tilesets[maps.ROUTE_29.tileset])
  for cy = 0, route29.heightCells - 1 do
    for cx = 0, route29.widthCells - 1 do
      if route29:isGrassCell(cx, cy) then sawGrass = true end
    end
  end
  check(sawGrass, "ROUTE_29 has grass cells")
  eq(town:cellTile(6, 3), town:cellCollision(6, 3), "cellTile is the COLL_ byte")
  check(not town:isGrassCell(-1, -1), "off-map cells are never grass")
  check(not town:isWaterCell(-1, -1), "off-map cells are never water")
end

-- src/world/gen2/CmdQueue.lua's hand-ported stone tables name warps, object ids
-- and event flags by NUMBER, because the callback they live behind is not
-- extracted.  Pin the four numbers the cache actually emits, so a re-import that
-- shifts any of them fails here rather than by a boulder quietly not falling.
do
  local CmdQueue = require("src.world.gen2.CmdQueue")
  local ice = maps.ICE_PATH_B1F
  local iceMap = Map.new(ice, tilesets[ice.tileset])
  for i, row in ipairs(CmdQueue.STONE_TABLES.ICE_PATH_B1F) do
    local obj = ice.objects[row.object - 1]
    eq(obj and obj.movement, CmdQueue.BOULDER_MOVEDATA,
      ("Ice Path row %d names a STRENGTH_BOULDER object"):format(i))
    eq(obj.eventFlag, 1800 + i,
      ("and it is EVENT_BOULDER_IN_ICE_PATH_%d"):format(i))
    local warp = ice.warps[row.warp]
    check(warp ~= nil, ("row %d names a real warp"):format(i))
    eq(iceMap:cellCollision(warp.x, warp.y), 0x60,
      ("and the tile under it is COLL_PIT (%d,%d)"):format(warp.x, warp.y))
    eq(row.script[2].event, 1804 + i,
      ("it clears EVENT_BOULDER_IN_ICE_PATH_%dA"):format(i))
  end
  local below = maps.ICE_PATH_B2F_MAHOGANY_SIDE
  for i = 1, 4 do
    eq(below.objects[i].eventFlag, 1804 + i,
      ("which is the boulder one floor down (%d)"):format(i))
  end
  local gym = maps.BLACKTHORN_GYM_2F
  for i, row in ipairs(CmdQueue.STONE_TABLES.BLACKTHORN_GYM_2F) do
    local obj = gym.objects[row.object - 1]
    eq(obj and obj.movement, CmdQueue.BOULDER_MOVEDATA,
      ("Blackthorn row %d names a STRENGTH_BOULDER object"):format(i))
    check(gym.warps[row.warp] ~= nil,
      ("Blackthorn row %d names a real warp"):format(i))
  end
end

-- Map callbacks.  maps.lua now carries the map script header's second half
-- (`def_callbacks` / `callback TYPE, script`), which is what makes the two
-- stone tables reachable without hand-porting them.  The counts are the
-- decomp's: `grep -h "^\tcallback " ../pokegold/maps/*.asm | sort | uniq -c`.
do
  local seen, total = {}, 0
  for id, def in pairs(maps) do
    if type(def) == "table" and def.callbacks then
      for _, cb in ipairs(def.callbacks) do
        seen[cb.callback] = (seen[cb.callback] or 0) + 1
        total = total + 1
        check(type(cb.scriptKey) == "string",
          ("%s callback names a script key"):format(id))
      end
    end
  end
  if total == 0 then
    check(true, "cache predates map callbacks (SKIP)")
  else
    eq(total, 84, "every map callback in the game")
    eq(seen.MAPCALLBACK_TILES, 19, "MAPCALLBACK_TILES")
    eq(seen.MAPCALLBACK_OBJECTS, 24, "MAPCALLBACK_OBJECTS")
    eq(seen.MAPCALLBACK_CMDQUEUE, 2, "MAPCALLBACK_CMDQUEUE")
    eq(seen.MAPCALLBACK_NEWMAP, 39, "MAPCALLBACK_NEWMAP")
    -- MAPCALLBACK_SPRITES is in the enum and no map uses it; a count here
    -- would mean the type byte is being read one row off.
    eq(seen.MAPCALLBACK_SPRITES, nil, "no map uses MAPCALLBACK_SPRITES")
  end
end

-- The extracted stone tables against the hand-ported ones.  These are the
-- SAME data by two routes -- CmdQueue.STONE_TABLES was transcribed from
-- pokegold, the rows below were followed out of the ROM -- so any drift means
-- one of them is wrong.
do
  local CmdQueue = require("src.world.gen2.CmdQueue")
  local scripts = loadLua("data/generated/scripts.lua")
  local function extractedRows(mapId)
    for _, cb in ipairs(maps[mapId].callbacks or {}) do
      if cb.callback == "MAPCALLBACK_CMDQUEUE" then
        for _, cmd in ipairs(scripts[cb.scriptKey] or {}) do
          if cmd.op == "writecmdqueue" then return cmd.queue end
        end
      end
    end
  end
  local ice = extractedRows("ICE_PATH_B1F")
  if not ice then
    check(true, "cache predates writecmdqueue following (SKIP)")
  else
    eq(ice.queue, "CMDQUEUE_STONETABLE", "Ice Path writes a stone table")
    for mapId, hand in pairs(CmdQueue.STONE_TABLES) do
      local got = CmdQueue.fromExtracted(extractedRows(mapId), mapId)
      check(got ~= nil, ("%s converts to a queue entry"):format(mapId))
      eq(#got.rows, #hand, ("%s row count"):format(mapId))
      for i, row in ipairs(hand) do
        eq(got.rows[i].warp, row.warp, ("%s row %d warp"):format(mapId, i))
        eq(got.rows[i].object, row.object, ("%s row %d object"):format(mapId, i))
        -- The hand-ported row inlines its command list; the extracted one
        -- names a scripts.lua key, and the script behind it must exist or the
        -- boulder disappears into a missing key.
        check(scripts[got.rows[i].script] ~= nil,
          ("%s row %d script is in scripts.lua"):format(mapId, i))
      end
    end
    -- The boulder script the cart runs, which the hand-port had to write out
    -- as `rawtext` because nothing pointed at its string.
    local first = CmdQueue.fromExtracted(ice, "ICE_PATH_B1F").rows[1]
    local body = scripts[first.script]
    eq(body[1].op, "disappear", "the boulder disappears first")
    eq(body[1].object, 2, "and it is ICEPATHB1F_BOULDER1")
    eq(body[2].op, "clearevent", "then clears its twin one floor down")
    eq(body[2].event, 1805, "EVENT_BOULDER_IN_ICE_PATH_1A")
  end
end

local west = town:connection("west")
check(west and west.mapId == "ROUTE_29", "west connection Route 29")
local east = town:connection("east")
check(east and east.mapId == "ROUTE_27", "east connection Route 27")

local r29 = maps.ROUTE_29
local lx, ly = Map.connectionLanding(r29, west, "left", 0, 8)
eq(lx, r29.width * 2 - 1, "west edge → Route 29 x")
eq(ly, 8, "west edge → Route 29 y")

-- Neighbor strip placement (RBY-style): Route 29 sits flush on New Bark's west.
local nbs = World.computeNeighbors(maps, "NEW_BARK_TOWN", 2)
local found29
for _, n in ipairs(nbs) do
  if n.id == "ROUTE_29" then found29 = n break end
end
check(found29 ~= nil, "computeNeighbors includes ROUTE_29")
if found29 then
  eq(found29.ox, -r29.width * 32, "Route 29 west strip ox")
  eq(found29.oy, 0, "Route 29 west strip oy")
end
local found27
for _, n in ipairs(nbs) do
  if n.id == "ROUTE_27" then found27 = n break end
end
check(found27 ~= nil, "computeNeighbors includes ROUTE_27")

local lab = Map.new(maps.ELMS_LAB, tilesets[maps.ELMS_LAB.tileset])
eq(maps.ELMS_LAB.tileset, "TILESET_LAB", "lab uses indoor tileset (no roofs)")
eq(lab:cellCollision(4, 11), 0x70, "lab exit carpet")
eq(Permissions.carpetDirection(lab:cellCollision(4, 11)), "down",
  "lab carpet faces down")
eq(lab:warpAt(4, 11).def.destMap, "NEW_BARK_TOWN", "lab carpet → town")
-- Officer on the starter table is hidden by InitializeEventsScript at boot.
local labObjs = maps.ELMS_LAB.objects
eq(#labObjs, 6, "Elms Lab has 6 object_events")
eq(labObjs[6].sprite, "SPRITE_OFFICER", "lab object 6 is the cop")
eq(labObjs[6].x, 5, "cop x on starter table")
eq(labObjs[6].y, 3, "cop y on starter table")
local initPath = cache .. "/data/generated/initial_events.lua"
local initFile = io.open(initPath, "r")
if initFile then
  initFile:close()
  local initial = loadLua("data/generated/initial_events.lua")
  local copFlag = labObjs[6].eventFlag
  local hidden = false
  for _, id in ipairs(initial.flags or {}) do
    if id == copFlag then hidden = true break end
  end
  check(hidden, "InitializeEventsScript hides lab cop (flag "
    .. tostring(copFlag) .. ")")
else
  check(true, "initial_events.lua absent : re-import Gold")
end

-- Overworld sprites (Chris + New Bark NPCs) when the cache is post-sprite extract.
local spritesPath = cache .. "/data/generated/sprites.lua"
local spritesFile = io.open(spritesPath, "r")
if spritesFile then
  spritesFile:close()
  local sprites = loadLua("data/generated/sprites.lua")
  local chris = sprites.SPRITE_CHRIS
  check(chris ~= nil, "SPRITE_CHRIS extracted")
  if chris then
    eq(chris.frames, 6, "Chris walking sheet has 6 frames")
    check(chris.walker, "Chris is a walker")
    eq(chris.image, "assets/generated/sprites/chris.png", "Chris image path")
  end
  check(sprites.SPRITE_TEACHER ~= nil, "SPRITE_TEACHER extracted")
  check(sprites.SPRITE_RIVAL ~= nil, "SPRITE_RIVAL extracted")
  local objs = maps.NEW_BARK_TOWN.objects
  eq(#objs, 3, "New Bark has 3 object_events")
  eq(objs[1].sprite, "SPRITE_TEACHER", "New Bark teacher sprite")
  eq(objs[3].sprite, "SPRITE_RIVAL", "New Bark rival sprite")

  -- Anim paths from SPRITEMOVEDATA_* (no SpriteRenderer : headless luajit).
  local kind, dirs = NPC.patternFor(NPC.MOVE.SPINRANDOM_SLOW)
  eq(kind, "spin", "teacher movement is spin")
  kind, dirs = NPC.patternFor(NPC.MOVE.WALK_UP_DOWN)
  eq(kind, "walk", "fisher movement is walk")
  check(dirs and dirs[1] == "up" and dirs[2] == "down", "fisher walks up/down")
  kind = NPC.patternFor(NPC.MOVE.STANDING_RIGHT)
  eq(kind, "stand", "rival stands")
  eq(select(1, NPC.patternFor(objs[1].movement)), "spin", "New Bark teacher spins")
  eq(select(1, NPC.patternFor(objs[2].movement)), "walk", "New Bark fisher walks")
  eq(select(1, NPC.patternFor(objs[3].movement)), "stand", "New Bark rival stands")

  -- Fisher radius (0,1): home±1 in Y stays in radius, X step does not.
  local fisher = setmetatable({
    homeX = objs[2].x, homeY = objs[2].y,
    radiusX = (objs[2].radius and objs[2].radius.x) or 0,
    radiusY = (objs[2].radius and objs[2].radius.y) or 0,
  }, NPC)
  eq(fisher.radiusY, 1, "fisher radius Y")
  check(fisher:inRadius(fisher.homeX, fisher.homeY + 1), "fisher +Y in radius")
  check(not fisher:inRadius(fisher.homeX + 1, fisher.homeY), "fisher +X out of radius")
else
  check(true, "sprites.lua absent : skip OW sprite facts (re-import Gold)")
end

-- ------------------------------------------------------- the script VM hooks
-- The 81 opcodes the interpreter grew are inert without these: an `appear` that
-- reaches no World never spawns the object, a `changeblock` never opens the
-- door, and a `warpcheck` never drops the player through the hole.  Every hook
-- the VM guards with `if self.xFn then` is asserted here against real World
-- behaviour rather than against the closure that forwards to it.
-- The world under test is built with World.new and then poked directly: the
-- constructor is love-free, and each method below is the WORLD half of one
-- transcribed command, so a stub map and a stub save are the whole rig.

local function hookWorld(opts)
  opts = opts or {}
  local game = {
    data = {
      pokemon = {
        MAGIKARP = { name = "MAGIKARP", index = 129 },
        SHUCKLE = { name = "SHUCKLE", index = 213, eggSteps = 20 },
        CHIKORITA = { name = "CHIKORITA", index = 152, eggSteps = 20,
          baseStats = { hp = 45, attack = 49, defense = 65, speed = 45,
            specialAttack = 49, specialDefense = 65 },
          levelMoves = { { level = 1, move = "TACKLE" } } },
      },
      items = {
        POTION = { id = "POTION", name = "POTION", index = 18 },
        COIN_CASE = { id = "COIN_CASE", name = "COIN CASE", index = 0x47 },
      },
      moves = { TACKLE = { name = "TACKLE", pp = 35 } },
      audio = { sfxOrder = { "Sfx_Dummy", "Sfx_Item", "Sfx_WarpTo",
        "Sfx_EnterDoor", "Sfx_ExitBuilding" } },
    },
    save = {
      version = opts.version or "gold",
      player = { name = "GOLD", id = 1234, money = 3000, coins = 40 },
      mom = { savedMoney = 500 },
      party = opts.party or {},
      inventory = opts.inventory or {},
      boxes = {},
    },
  }
  local world = World.new(game)
  world.maps = {
    TEST_MAP = { id = "TEST_MAP", group = 1, map = 2, width = 4, height = 4,
      blocks = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
      objects = {}, warps = {}, sceneScripts = { [0] = { scriptKey = "s" } } },
    OTHER_MAP = { id = "OTHER_MAP", group = 3, map = 4, width = 2, height = 2,
      blocks = { 1, 2, 3, 4 }, objects = {}, warps = {} },
  }
  world.map = { id = "TEST_MAP", def = world.maps.TEST_MAP, width = 4,
    height = 4 }
  world.map.blocks = world.maps.TEST_MAP.blocks
  world.constants = { spriteOrder = { "SPRITE_CHRIS", "SPRITE_TEACHER",
    "SPRITE_RIVAL" } }
  world.sprites = { SPRITE_CHRIS = {}, SPRITE_TEACHER = {}, SPRITE_RIVAL = {} }
  world.daytime = opts.daytime or "DAY"
  world.player = fakePlayer(2, 3, "down")
  return world, game
end

-- ---- scene, clock, cartridge ----------------------------------------------
local hw = hookWorld()
eq(hw:mapSceneOf(1, 2), 0, "checkmapscene: a map with scene scripts reads 0")
hw.mapScenes.TEST_MAP = 3
eq(hw:mapSceneOf(1, 2), 3, "and reads back what setmapscene wrote")
check(hw:mapSceneOf(3, 4) == nil,
  "a map with NO scene_var row answers nil, which the VM turns into $ff")
check(hw:mapSceneOf(9, 9) == nil, "and an unresolvable pair is nil too")

-- hw.tod is the production read (the unpinned wTimeOfDay split, #1557);
-- hw.daytime is the palette pin it must NOT follow
hw.tod = "DAY"
eq(hw:timeOfDayId(), 1, "DAY is wTimeOfDay 1")
hw.tod = "MORN"
eq(hw:timeOfDayId(), 0, "MORN is 0")
hw.tod = "NITE"
eq(hw:timeOfDayId(), 2, "NITE is 2")
hw.tod = "NITE"
hw.daytime = "DARK"
eq(hw:timeOfDayId(), 2, "a PALETTE_DARK pin does not leak into wTimeOfDay")
hw.tod = nil
hw.daytime = "DARK"
eq(hw:timeOfDayId(), 3, "DARKNESS is 3 only on the tod-less fallback arm")
hw.tod, hw.daytime = nil, "DAY"
eq(hw:gsVersion(), 0, "checkver: a Gold save is 0")
eq(hookWorld({ version = "silver" }):gsVersion(), 1, "and a Silver save is 1")

-- ---- LoadPlayerData -------------------------------------------------------
-- engine/menus/save.asm copies sPlayerData straight back over wPlayerData, and
-- BOTH wEventFlags and the w<Map>SceneID block sit inside that region, so a
-- reload comes back with every flag the player set and with each map still on
-- the scene it had reached.  World:load runs this before the first setMap;
-- these are the halves of it on their own.
-- The seed is InitializeEventsScript's setevent list, which the cache carries
-- as data/generated/initial_events.lua.  Three of its ids stand in for it here:
-- EVENT_ILEX_FOREST_APPRENTICE 1794, EVENT_EARLS_ACADEMY_EARL 1739, and
-- EVENT_INITIALIZED_EVENTS 54, which the script sets last and
-- PlayersHouse2FInitializeRoomCallback checks before running it at all.
local SEED = { 1739, 1794, 54 }
do
  local fresh = hookWorld()
  fresh.initialEvents = SEED
  fresh:loadPlayerData(fresh.game.save)
  check(fresh.events:get(1794), "a save with no bitfield gets the seed")
  check(fresh.events:get(54), "including EVENT_INITIALIZED_EVENTS")
  eq(next(fresh.mapScenes), nil, "and no map has been advanced yet")
  fresh:loadPlayerData(nil)
  check(fresh.events:get(1794), "and so does no save at all")

  -- Play: one flag set (EVENT_TOGEPI_HATCHED 84), one of the seeded flags
  -- CLEARED the way MeetMomScript clears EVENT_PLAYERS_HOUSE_MOM_2 on its way
  -- out, and the map advanced off scene 0.  This is what the snapshot writes.
  fresh.events:set(84, true)
  fresh.events:set(1794, false)
  fresh.mapScenes.TEST_MAP = 3
  local written = {
    events = fresh.events:serialize(),
    mapScenes = fresh.mapScenes,
  }

  local reload = hookWorld()
  reload.initialEvents = SEED
  reload:loadPlayerData(written)
  check(reload.events:get(84), "a flag the player set survives the reload")
  check(not reload.events:get(1794),
    "a CLEARED seed flag stays cleared rather than being seeded again")
  check(reload.events:get(1739), "the rest of the seed is still set")
  eq(reload.mapScenes.TEST_MAP, 3, "and the map is still on its scene")
  eq(reload:mapSceneOf(1, 2), 3, "which is what checkmapscene reads back")

  -- A bitfield that has flags but has never had the seed -- a save built by
  -- hand, or one written before InitializeEventsScript ran -- keeps its own
  -- flags AND gets the seed, which is the branch the bedroom callback takes.
  local partial = hookWorld()
  partial.initialEvents = SEED
  partial:loadPlayerData({ events = { [10] = 0x01 } })
  check(partial.events:get(80), "an un-seeded bitfield keeps its own flags")
  check(partial.events:get(1794), "and gets the seed on top")

  -- Objects read the restored bitfield, not the seed: this is the whole point
  -- of the restore happening before the first map load.
  check(not reload.events:objectVisible(84),
    "a restored flag hides the object that names it")
  check(reload.events:objectVisible(1794),
    "and a restored CLEAR shows the object again")
end

-- ---- wPlayerState across a save -------------------------------------------
-- The third member of the sPlayerData block LoadPlayerData copies back.  Until
-- it rode the save, a reload walked the player off the BICYCLE and off the
-- water: everything the state decides follows from this one field, so all
-- three of the things it decides are checked here.
-- Wrapped in a function for the same reason bikeChecks is, and called on the
-- spot rather than through a name of its own: block locals count against the
-- main chunk's 200-local ceiling and this file has none left.
;(function()
local Bike = require("src.world.gen2.Bike")
local Player = require("src.world.gen2.Player")
local Gen2Save = require("src.core.gen2.Save")

-- Save on the bike, reload on the bike: the state itself, ChrisStateSprites'
-- bike row on the player, and STEP_BIKE under the next step.
local riding = hookWorld()
riding.sprites.SPRITE_CHRIS_BIKE = { name = "SPRITE_CHRIS_BIKE" }
local worn
riding.player.setSprite = function(_, def) worn = def end
riding:loadPlayerData({ playerState = "bike" })
eq(riding.playerState, FieldMoves.PLAYER_BIKE,
  "a save made on the BICYCLE reloads on the BICYCLE")
eq(worn and worn.name, "SPRITE_CHRIS_BIKE", "wearing the bike's own sprite")
eq(Bike.stepFrames(riding.playerState, "up", false, 16), 8,
  "and stepping at STEP_BIKE rather than STEP_WALK")

-- Save afloat, reload afloat, on the sprite GetSurfType picked at the time.
local afloat = hookWorld()
afloat.sprites.SPRITE_SURFING_PIKACHU = { name = "SPRITE_SURFING_PIKACHU" }
local raft
afloat.player.setSprite = function(_, def) raft = def end
afloat:loadPlayerData({ playerState = "surf_pika" })
eq(afloat.playerState, FieldMoves.PLAYER_SURF_PIKA,
  "a save made surfing reloads surfing")
eq(raft and raft.name, "SPRITE_SURFING_PIKACHU",
  "on the PIKACHU it was riding, not on a generic Lapras")

-- The third thing that follows: .TranslateIntoMovement picks .CheckSurfPerms
-- off wPlayerState, so the restored state is what lets the reload step back
-- out onto the water it was saved on.  Water at (3,2), the player facing it.
local sea = fakeWorld({ [2 * 100 + 3] = COLL_WATER })
sea.player = Player.new(3, 3, "up", nil)
sea.game.save.playerState = "surf"
sea:loadPlayerData(sea.game.save)
eq(sea.playerState, FieldMoves.PLAYER_SURF, "the state comes off the save")
eq(sea:movePlayer("up"), "moved", "and the step onto the water is legal")

-- The same world without the state restored is the bug: on foot, and the sea
-- the save was made on is a wall.
local dry = fakeWorld({ [2 * 100 + 3] = COLL_WATER })
dry.player = Player.new(3, 3, "up", nil)
dry:loadPlayerData({})
eq(dry.playerState, FieldMoves.PLAYER_NORMAL,
  "a save with no state at all is on foot")
check(dry:movePlayer("up") ~= "moved", "and that same step bumps")

-- Only a name the save format vouches for is taken back; the two ends of the
-- round trip share one set, so neither can drift.
local bogus = hookWorld()
bogus:loadPlayerData({ playerState = "skateboard" })
eq(bogus.playerState, FieldMoves.PLAYER_NORMAL,
  "a state no cartridge could write comes back as PLAYER_NORMAL")
check(Gen2Save.PLAYER_STATES[FieldMoves.PLAYER_SURF_PIKA],
  "and the set World tests against names every state FieldMoves does")
check(Gen2Save.PLAYER_STATES[FieldMoves.PLAYER_BIKE], "the bike included")
end)()

-- ---- ENGINE_* flags -------------------------------------------------------
-- A namespace of its own: BADGE_ZEPHYR must never collide with an object's
-- MAPOBJECT_EVENT_FLAG, and setting one must not respawn anybody.
check(not hw:engineFlag(26), "an unset engine flag is false")
hw:setEngineFlag(26, true)
check(hw:engineFlag(26), "setflag ENGINE_ZEPHYRBADGE reads back")
-- A BADGE id is the one ENGINE_* that does not live in save.engineFlags.
-- World:setEngineFlag routes it to save.player.badges instead, because that is
-- the store hasBadge, VAR_BADGES, the trainer card and the save summary all
-- read -- and while the two disagreed no field move in the game could be used
-- (tests/gen2_badges_test.lua).  This assertion still expected the old store.
check(hw.game.save.player.badges[FieldMoves.JOHTO_BADGES[1]],
      "and it lives on the save, in the badge store")
check(not (hw.game.save.engineFlags or {})[26],
      "not in engineFlags, which nothing reads for badges")
check(not hw.events:get(26), "and it did NOT touch the wEventFlags array")
hw:setEngineFlag(26, false)
check(not hw:engineFlag(26), "clearflag clears it")

-- ---- vars -----------------------------------------------------------------
hw:writeVar(0x03, 10) -- VAR_BATTLETYPE, BATTLETYPE_FORCEITEM
eq(hw:battleType(), 10, "writevar VAR_BATTLETYPE is read back by startbattle")

-- ---- map objects ----------------------------------------------------------
-- disappear then appear has to be symmetrical BOTH ways: through the event
-- flag when the object has one, and through the synthetic hide when it does
-- not.  A one-way pair is why a scripted NPC used to vanish for good.
local objWorld = hookWorld()
objWorld.maps.TEST_MAP.objects = {
  { index = 1, sprite = "SPRITE_TEACHER", x = 1, y = 1, eventFlag = 700 },
  { index = 2, sprite = "SPRITE_RIVAL", x = 2, y = 2, eventFlag = 0xFFFF },
  { index = 3, sprite = 244, x = 3, y = 3, eventFlag = 0xFFFF },
}
objWorld.rebuildPeople = function(self) self.rebuilds = (self.rebuilds or 0) + 1 end
objWorld:disappearObject(2) -- object_const 2 -> index 1
check(objWorld.events:get(700), "disappear sets the object's event flag")
objWorld:appearObject(2)
check(not objWorld.events:get(700), "and appear clears it again")
objWorld:disappearObject(3) -- eventFlag $ffff: the mask, with no flag to set
check(objWorld.objectMasks["TEST_MAP:2"], "a flagless disappear masks by key")
objWorld:appearObject(3)
check(objWorld.objectMasks["TEST_MAP:2"] == false,
  "and appear unmasks it, so the pair is not one-way")

-- maps/LancesRoom.asm:118
do
  local rebuildsBefore = objWorld.rebuilds or 0
  objWorld:disappearObject(0)
  check(objWorld.playerMasked == true,
    "disappear PLAYER masks the player sprite")
  check(objWorld.objectMasks["TEST_MAP:-1"] == nil, "and touches no map object")
  eq(objWorld.rebuilds or 0, rebuildsBefore, "and rebuilds nobody")
  objWorld:appearObject(0)
  check(not objWorld.playerMasked, "appear PLAYER unmasks it")
end

-- NewBarkTown_RivalShovesYouOutMovement maps/NewBarkTown.asm:178-183
do
  local Player = require("src.world.gen2.Player")
  local jw = hookWorld()
  jw.player = Player.new(3, 4, "down")
  local done = false
  jw:beginMovement(0, { 0x01, 0x3b, 0x30, 0x3a, 0x47 }, function() done = true end)
  jw:updateMovement()
  eq(jw.player.facing, "up", "turn_head UP turns the player")
  jw:updateMovement()
  check(jw.player.moving and jw.player.jumping, "jump_step DOWN is a jump")
  eq(jw.player.targetY, 6, "two cells long")
  eq(jw.player.facing, "up", "under fix_facing the player keeps facing up")
  eq(jw.moveState and jw.moveState.pendingStep, nil, "with no second walk queued")
  local lowest = 0
  for _ = 1, 32 do
    jw.player:update()
    lowest = math.min(lowest, jw.player.spriteYOffset or 0)
    jw:updateMovement()
  end
  eq(lowest, -12, "the sprite arcs twelve pixels up on the way")
  eq(jw.player.cellY, 6, "and lands two cells down")
  check(done, "then the stream ends")
  check(not jw.player.fixedFacing, "remove_fixed_facing released the facing")
end

-- Three object_events SHARING one MAPOBJECT_EVENT_FLAG is ordinary: the
-- animated Burned Tower beasts all carry EVENT_BURNED_TOWER_B1F_BEASTS_1
-- (maps/BurnedTowerB1F.asm:152) and ReleaseTheBeasts appears and jumps them
-- away one at a time.  MaskObject writes ONE byte (home/map.asm:1542) and the
-- flag is only read back at the next LoadObjectMasks, so a `disappear` must
-- take its own object off the map and leave the other two standing.
do
local beasts = hookWorld()
beasts.maps.TEST_MAP.objects = {
  { index = 1, sprite = "SPRITE_TEACHER", x = 1, y = 1, eventFlag = 1866 },
  { index = 2, sprite = "SPRITE_TEACHER", x = 2, y = 2, eventFlag = 1866 },
  { index = 3, sprite = "SPRITE_TEACHER", x = 3, y = 3, eventFlag = 1866 },
}
beasts.pooledNpc = function(_, mapId, obj)
  return { def = obj, id = mapId .. ":" .. tostring(obj.index) }
end
local function standing(world)
  local ids = {}
  for _, npc in ipairs(world.npcs) do ids[npc.id] = true end
  return ids
end
beasts:loadObjectMasks() -- the map load, with the shared flag clear
beasts:rebuildPeople()
eq(#beasts.npcs, 3, "all three spawn while the shared flag is clear")
beasts:disappearObject(2) -- object_const 2 -> index 1
beasts:rebuildPeople()
local left = standing(beasts)
check(not left["TEST_MAP:1"], "the beast that jumped away is gone")
check(left["TEST_MAP:2"] and left["TEST_MAP:3"],
  "and the two sharing its event flag are still standing")
check(beasts.events:get(1866), "the flag is set for the next map load")

-- The reveal half, the same way round: a load with the shared flag SET masks
-- every one of them, and each `appear` unmasks its own (Script_appear ->
-- UnmaskCopyMapObjectStruct, home/map_objects.asm:309).
beasts:loadObjectMasks()
beasts:rebuildPeople()
eq(#beasts.npcs, 0, "a load with the shared flag set masks all three")
beasts:appearObject(2)
beasts:rebuildPeople()
local shown = standing(beasts)
check(shown["TEST_MAP:1"], "the first appear puts exactly one on the map")
check(not (shown["TEST_MAP:2"] or shown["TEST_MAP:3"]),
  "the other two wait for their own appear")
-- The hour poll stands in for a reload the cart never runs, so it passes
-- keepScripted: it re-derives the hour windows, but an object a scene masked
-- with no flag to remember it by ($ffff takes MaskObject's path alone) must
-- not walk back in at the top of the hour.
beasts.maps.TEST_MAP.objects[4] =
  { index = 4, sprite = "SPRITE_TEACHER", x = 1, y = 3, eventFlag = 0xFFFF }
beasts:loadObjectMasks()
beasts:disappearObject(5) -- object_const 5 -> index 4
beasts:loadObjectMasks({ keepScripted = true })
beasts:rebuildPeople()
check(not standing(beasts)["TEST_MAP:4"],
  "the hour poll leaves a scripted mask alone")
end

-- moveobject writes the DEF as well as the live NPC, because it nearly always
-- names an object that has not spawned yet.
objWorld:moveObject(2, 7, 9)
eq(objWorld.maps.TEST_MAP.objects[1].x, 7, "moveobject writes the object def x")
eq(objWorld.maps.TEST_MAP.objects[1].y, 9, "and its y")

-- variablesprite: an object whose sprite is a NUMBER is a wVariableSprites
-- slot, and nothing spawns for it until the slot is filled.
check(objWorld:resolveSprite(244) == nil,
  "SPRITE_WEIRD_TREE resolves to nothing while its slot is empty")
objWorld:setVariableSprite(0xf4 - 0xf0, 2)
eq(objWorld:resolveSprite(244), "SPRITE_TEACHER",
  "and to the sprite the slot names once variablesprite has run")
eq(objWorld:resolveSprite("SPRITE_RIVAL"), "SPRITE_RIVAL",
  "a named sprite passes straight through")
check(objWorld:resolveSprite(130) == nil,
  "a SPRITE_POKEMON byte is below SPRITE_VARS and still resolves to nothing")

-- Script_appear RESPAWNS the object struct out of the map object
-- (UnmaskCopyMapObjectStruct -> CopyObjectStruct -> CopyMapObjectToObjectStruct,
-- engine/overworld/player_object.asm:207-215), so the pooled NPC -- the OLD
-- struct, still sitting on the old cell -- has to go with it or a
-- `moveobject` + `appear` pair spawns at the cell the object was already on.
-- That is Kurt after the Slowpoke Well grunt: moved to (11,6), reappearing at
-- (16,14).
objWorld.npcPool = { TEST_MAP_obj_1 = "stale struct",
  TEST_MAP_obj_2 = "another object" }
objWorld:appearObject(2)
check(objWorld.npcPool.TEST_MAP_obj_1 == nil,
  "appear drops the pooled struct so the coords are re-read from the def")
eq(objWorld.npcPool.TEST_MAP_obj_2, "another object",
  "and only that object's")

-- ---- the day care ---------------------------------------------------------
-- data/events/engine_flags.asm:18-20: ENGINE_DAY_CARE_MAN_HAS_EGG (5),
-- _MAN_HAS_MON (6) and _LADY_HAS_MON (7) ARE bits of wDayCareMan/wDayCareLady,
-- the bits the deposit, DayCareStep and the withdrawal write.  So
-- Route34EggCheckCallback's `checkflag` reads the deposit state itself and
-- there is exactly one store; a second copy in save.engineFlags is what kept
-- EVENT_DAY_CARE_MON_1/2 set forever and the yard empty.
do
  local dcWorld, dcGame = hookWorld()
  local Breeding = require("src.core.gen2.Breeding")
  check(not dcWorld:engineFlag(6), "an empty day care answers checkflag 6 false")
  check(not dcWorld:engineFlag(7), "and checkflag 7")
  check(not dcWorld:engineFlag(5), "and no egg is waiting")
  Breeding.side(dcGame.save, "man").mon = { species = "CHIKORITA", level = 5 }
  check(dcWorld:engineFlag(6), "a deposit into the man's slot sets checkflag 6")
  check(not dcWorld:engineFlag(7), "without touching the lady's")
  Breeding.side(dcGame.save, "lady").mon = { species = "MAGIKARP", level = 5 }
  check(dcWorld:engineFlag(7), "and the lady's slot sets checkflag 7")
  Breeding.side(dcGame.save, "man").mon = nil
  check(not dcWorld:engineFlag(6), "a withdrawal clears it again")
  -- DayCareStep's `set DAYCAREMAN_HAS_EGG_F` is the only writer of the egg bit
  -- besides DayCareManScript_Outside's clearflag, which is the one cart script
  -- that writes any of the three.
  Breeding.dayCare(dcGame.save).hasEgg = true
  check(dcWorld:engineFlag(5), "a built egg answers checkflag 5")
  dcWorld:setEngineFlag(5, false)
  check(not Breeding.dayCare(dcGame.save).hasEgg,
    "and the script's clearflag writes save.dayCare, not a second store")
  check(dcWorld:engineFlags()[5] == nil,
    "nothing lands in save.engineFlags for an aliased id")
  -- No cart script writes the two HAS_MON bits: the deposit routines own them.
  dcWorld:setEngineFlag(6, true)
  check(not dcWorld:engineFlag(6),
    "a setflag on ENGINE_DAY_CARE_MAN_HAS_MON does not fake a deposit")

  -- GetMonSprite (engine/overworld/overworld.asm:279-305) tests
  -- SPRITE_DAY_CARE_MON_1/2 ($e0/$e1) BEFORE the SPRITE_VARS range and answers
  -- with LoadOverworldMonIcon of wBreedMon1Species / wBreedMon2Species.  Route
  -- 34's two yard objects carry those bytes, so without the arm they resolved
  -- to nothing and the mons never spawned even with the flags right.
  dcGame.data.gen2Icons = {
    species = { CHIKORITA = "ICON_BULBASAUR", MAGIKARP = "ICON_FISH" },
    icons = {
      ICON_BULBASAUR = { id = "ICON_BULBASAUR",
        image = "assets/generated/icons/gen2/bulbasaur.png" },
      ICON_FISH = { id = "ICON_FISH",
        image = "assets/generated/icons/gen2/fish.png" },
    },
  }
  check(dcWorld:resolveSprite(0xe0) == nil,
    "an empty man's slot leaves the yard object unresolved, so it stays hidden")
  Breeding.side(dcGame.save, "man").mon = { species = "CHIKORITA", level = 5 }
  local def = dcWorld:resolveSprite(0xe0)
  check(type(def) == "table", "a deposited mon resolves to a built sprite def")
  eq(def and def.species, "CHIKORITA", "for the species that was deposited")
  eq(def and def.image, "assets/generated/icons/gen2/bulbasaur.png",
    "pointed at that mon's own menu icon")
  eq(def and def.spriteType, "POKEMON_SPRITE",
    "in the shape extractMonSprites emits")
  local lady = dcWorld:resolveSprite(0xe1)
  eq(lady and lady.species, "MAGIKARP", "and $e1 reads the lady's slot")
end

-- ---- map blocks -----------------------------------------------------------
local blockWorld = hookWorld()
blockWorld.refreshMapImages = function() return true end
check(blockWorld:changeBlock(1, 1, 99), "changeblock writes one block")
eq(blockWorld.maps.TEST_MAP.blocks[1 * 4 + 1 + 1], 99,
  "at row * width + column + 1")
check(not blockWorld:changeBlock(9, 9, 99), "and refuses a block off the grid")
-- restoreBlocks is LoadMapAttributes' refill: the edit must not survive a map
-- load, or the shared maps.lua table would carry it into a New Game.
blockWorld:restoreBlocks()
eq(blockWorld.maps.TEST_MAP.blocks[6], 6, "and the next map load puts it back")

-- changemapblocks repaints the WHOLE map off a second blockdata array.  The
-- operand is a raw ROM bank/pointer, so the test carries the blockdata pair
-- RomExtractorGen2 now records for every map and checks that the pointer is
-- placed by the array it lands IN -- offset and all -- rather than by a name.
do
  local world = hookWorld()
  world.maps.TEST_MAP.blockdata = { bank = 0x60, address = 0x4000 }
  local alt = {}
  for i = 1, 20 do alt[i] = 100 + i end
  world.maps.ALT_BLOCKS = { id = "ALT_BLOCKS", group = 5, map = 6,
    width = 4, height = 5, blocks = alt, objects = {}, warps = {},
    blockdata = { bank = 0x60, address = 0x5000 } }
  -- Enough of the bake path to be real: refreshMapImages does nothing at all
  -- when the world has never baked, and the bake drop is half of what is under
  -- test here.
  world.mapImage = "stale canvas"
  world.mapImages = { ["TEST_MAP|DAY|gbc|1"] = "stale",
    ["OTHER_MAP|DAY|gbc|1"] = "keep" }
  world.imageFor = function() return "rebaked" end
  world.rebuildNeighbors = function() end

  check(not world:changeMapBlocks(0x61, 0x5000),
    "a pointer in another bank places nowhere and changes nothing")
  check(not world:changeMapBlocks(0x60, 0x7000),
    "and so does one no map's blockdata covers")
  -- 4 x 4 is sixteen blocks read as one flat run, so an offset that leaves
  -- fewer than that in the source array would run off the end of it.
  check(not world:changeMapBlocks(0x60, 0x5008),
    "a run that would read past the source array is refused")
  eq(world.maps.TEST_MAP.blocks[1], 1, "none of the three touched a block")

  check(world:changeMapBlocks(0x60, 0x5000), "and the array itself is copied")
  eq(world.maps.TEST_MAP.blocks[1], 101, "from its first block")
  eq(world.maps.TEST_MAP.blocks[16], 116, "to the sixteenth, width * height")
  eq(alt[17], 117, "without disturbing the source")
  check(world.mapImages["TEST_MAP|DAY|gbc|1"] == nil,
    "the bake taken off the old blocks is dropped, or the screen keeps it")
  eq(world.mapImages["OTHER_MAP|DAY|gbc|1"], "keep",
    "and only that map's bakes go")

  -- LoadMapAttributes' refill, exactly as for changeblock: a whole-map repaint
  -- is still an edit to the shared maps.lua table.
  world:restoreBlocks()
  eq(world.maps.TEST_MAP.blocks[1], 1, "the next map load puts the map back")
  eq(world.maps.TEST_MAP.blocks[16], 16, "every block of it")

  -- A pointer part way into an array: the cart's copy starts there, it does not
  -- start at the array's head.
  world.mapImages["TEST_MAP|DAY|gbc|1"] = "stale again"
  check(world:changeMapBlocks(0x60, 0x5004), "a pointer inside an array works")
  eq(world.maps.TEST_MAP.blocks[1], 105, "and the copy starts at the offset")
  check(world.mapImages["TEST_MAP|DAY|gbc|1"] == nil, "dropping the bake again")
end

-- ---- earthquake -----------------------------------------------------------
-- One byte, two numbers: `earthquake 80` ($50) is amplitude 1 << 1 held for
-- $50 & $3f = 16 frames, not eighty of anything.
local quakeWorld = hookWorld()
quakeWorld:earthquake(80, 16)
eq(quakeWorld.shake.amplitude, 2, "earthquake 80 shakes by two pixels")
eq(quakeWorld.shake.left, 16, "for sixteen frames")
quakeWorld:updateShake()
check(quakeWorld.shake.phase ~= 0, "and the offset flips off zero at once")
for _ = 1, 20 do quakeWorld:updateShake() end
check(quakeWorld.shake == nil, "the shake ends itself")
quakeWorld:earthquake(0xc1, 1)
eq(quakeWorld.shake.amplitude, 8, "the top two bits pick 1 << 3 for $c1")

-- ---- warps ----------------------------------------------------------------
local warpWorld = hookWorld()
local warped = {}
warpWorld.setMap = function(_, id, x, y, facing)
  warped = { id = id, x = x, y = y, facing = facing }
  return true
end
check(warpWorld:warpTo(3, 4, 5, 6, "up"), "warpfacing resolves group/map")
eq(warped.id, "OTHER_MAP", "to the right map")
eq(warped.x, 5, "at the raw cell x")
eq(warped.facing, "up", "facing the byte warpfacing carried")
check(not warpWorld:warpTo(9, 9, 0, 0), "an unresolvable pair is a no-op")

-- warpcheck ARMS a warp; it must not take it, because the commands queued
-- behind it would run with the map pulled out from under them.
local checkWorld = hookWorld()
checkWorld.map.warpAt = function(_, x, y)
  if x == 2 and y == 3 then return { def = { destMap = "OTHER_MAP" } } end
  return nil
end
check(checkWorld:armWarpCheck(), "warpcheck finds the warp underfoot")
check(checkWorld.pendingWarp ~= nil, "and parks it")
local took = false
checkWorld.takeWarp = function() took = true return true end
check(not took, "without warping inside the command")
checkWorld:takePendingWarp()
check(took, "the drain is what takes it")
check(checkWorld.pendingWarp == nil, "and it fires once")

-- blackoutmod overrides the SPAWN_* lookup, so losing at sea does not respawn
-- the player somewhere they cannot leave.
local boWorld = hookWorld()
boWorld.landmarks = { spawns = { SPAWN_HOME = { map = "TEST_MAP", x = 1, y = 1 } } }
local spawned
boWorld.setMap = function(_, id) spawned = id return true end
boWorld:warpToSpawn()
eq(spawned, "TEST_MAP", "with no override the SPAWN_* table wins")
boWorld:setBlackoutMap(3, 4)
eq(boWorld.game.save.blackoutMap, "OTHER_MAP", "blackoutmod stores a map id")
boWorld:warpToSpawn()
eq(spawned, "OTHER_MAP", "and warpToSpawn prefers it")

-- warpmod is stored and nothing more; the elevator that reads it does not
-- exist yet, which is exactly why storing it is the point.
boWorld:setWarpMod(2, 3, 4)
eq(boWorld.game.save.warpMod.map, "OTHER_MAP", "warpmod resolves its map id")
eq(boWorld.game.save.warpMod.warp, 2, "and keeps the warp number")

-- ---- the map setup chain --------------------------------------------------
-- Walking onto a warp tile is PLAYEREVENT_WARP -> WarpToNewMapScript, which is
-- `warpsound` then `newloadmap MAPSETUP_DOOR`.  MapSetupScript_Door opens on
-- FadeOutToWhite and falls through into _Train, whose tail is FadeInFromWhite,
-- so the LOAD SITS IN THE MIDDLE of the script rather than replacing it.
local doorWorld = hookWorld()
doorWorld.maps.OTHER_MAP.warps = { { x = 1, y = 1 } }
local doorSfx = {}
doorWorld.playSfx = function(_, id) doorSfx[#doorSfx + 1] = id end
doorWorld.map.cellCollision = function() return 0x71 end -- COLL_DOOR underfoot
local doorLoad = nil
doorWorld.setMap = function(self, id, x, y, facing)
  doorLoad = { id = id, x = x, y = y, facing = facing }
  self.fade = nil -- a map load repaints everything, exactly as setMap does
  return true
end
check(doorWorld:takeWarp({ destMap = "OTHER_MAP", destWarp = 1 }),
  "takeWarp takes a resolvable warp_event")
eq(doorSfx[1], 3, "warpsound runs BEFORE the load, off the tile underfoot")
check(doorLoad == nil, "and the map does not load on the frame it is taken")
check(doorWorld:busy(),
  "the setup script is a blocking call, so the world is busy for it")
-- engine/tilesets/timeofday_pals.asm:115-128
do
  -- (engine/tilesets/timeofday_pals.asm:160-187)
  -- follows it is pure white (home/lcd.asm:35-72)
  local doorOut = (World.FADE_STEPS + 1) * World.FADE_STEP_FRAMES
  local doorHold = World.MAP_LOAD_WHITE_FRAMES + World.FADE_STEP_FRAMES
  local doorIn = (World.FADE_STEPS - 1) * World.FADE_STEP_FRAMES
  local doorChain = doorOut + doorHold + doorIn
  for _ = 1, doorOut - 1 do doorWorld:updateMapSetup() end
  check(doorLoad == nil, "one frame short of the fade out, it is still running")
  eq(doorWorld.fade, "white", "and the sheet it fades to is FillWhiteBGColor's")
  eq(doorWorld.fadeLevel, 1, "whose last row is the colour-0 plane")
  check(doorWorld.fadeWhiten,
    "drawn through the remap with pals 1-6 whitened, not as a white sheet")
  eq(doorWorld.fadeHold, nil, "so nothing holds the flat sheet yet")
  doorWorld:updateMapSetup()
  check(doorLoad ~= nil, "the load lands after that last row, under the LCD")
  eq(doorLoad.id, "OTHER_MAP", "on the destination map")
  eq(doorLoad.x, 1, "at the destination WARP's own cell")
  eq(doorWorld.fadeLevel, 1,
    "with the sheet re-armed, because the load cleared it")
  eq(doorWorld.fadeHold, World.MAP_LOAD_WHITE_FRAMES,
    "and the pure white held for the LCD-off window alone")
  eq(doorWorld.fadeWhiten, nil,
    "LoadMapPalettes put the plain time-of-day set back")
  for _ = 1, World.MAP_LOAD_WHITE_FRAMES do doorWorld:updateMapSetup() end
  eq(doorWorld.fadeHold, nil, "the LCD comes back on")
  eq(doorWorld.fadeLevel, 1,
    "on FadeInFromWhite's own first row, a palette row again")
  for _ = 1, doorHold + doorIn - 1 - World.MAP_LOAD_WHITE_FRAMES do
    doorWorld:updateMapSetup()
  end
  check(doorWorld.mapSetup ~= nil, "the fade in runs out the remaining rows")
  doorWorld:updateMapSetup()
  check(doorWorld.mapSetup == nil,
    "and frame " .. doorChain .. " ends the chain")
  check(doorWorld.fade == nil, "with nothing left over the world")
  check(not doorWorld:busy(), "and control back")
end

-- MapSetupScript_Connection and _Submenu are the only two rows with no fade at
-- all: an edge cross must not hitch.  Everything else fades back IN at least,
-- and only DOOR / FALL / TELEPORT fade OUT first (FALL and TELEPORT by
-- FALLTHROUGH -- neither names a FadeOutToWhite of its own).
local setupWorld = hookWorld()
local setupLoads = 0
setupWorld.setMap = function() setupLoads = setupLoads + 1 return true end
setupWorld:runMapSetup(0xf7, function() return setupWorld:setMap() end)
eq(setupLoads, 1, "MAPSETUP_CONNECTION loads on the spot")
check(setupWorld.mapSetup == nil, "with no chain behind it")
setupWorld.playerMasked = true
setupWorld:runMapSetup(0xf1, function() return setupWorld:setMap() end)
eq(setupLoads, 2, "MAPSETUP_WARP opens on DisableLCD, so it loads at once too")
check(setupWorld.playerMasked == nil,
  "and the load respawns a `disappear`ed player")
eq(setupWorld.mapSetup.phase, "in", "and only fades back in")
setupWorld.mapSetup = nil
setupWorld:runMapSetup(0xf6, function() return setupWorld:setMap() end)
eq(setupLoads, 2, "MAPSETUP_FALL fades out FIRST, by fallthrough into _Door")
eq(setupWorld.mapSetup.phase, "out", "so its load is still to come")

-- Script_newloadmap is four lines and none of them is a PlaySFX; where the cart
-- wants a sound it writes `warpsound` in front (WarpToNewMapScript is that
-- pair).  Inventing one here rang a door bell over every scripted re-entry.
local reloadWorld = hookWorld()
local reloadSfx = 0
reloadWorld.playSfx = function() reloadSfx = reloadSfx + 1 end
reloadWorld.setMap = function() return true end
reloadWorld:newLoadMap(0xf5) -- MAPSETUP_DOOR
eq(reloadSfx, 0, "newloadmap alone is silent")

-- RefreshPlayerSprite: CheckWarpFacingDown against the tile the player ARRIVES
-- on, then `call c, SpawnInFacingDown`.  Anything not in that array keeps the
-- facing they walked in with, which is why you enter a building still facing up
-- and step out of one facing the street.
local faceWorld = hookWorld()
faceWorld.player.facing = "up"
faceWorld.map.cellCollision = function() return 0x70 end -- COLL_WARP_CARPET_DOWN
faceWorld:spawnFacing()
eq(faceWorld.player.facing, "up", "a doormat inside a building keeps the facing")
faceWorld.map.cellCollision = function() return 0x71 end -- COLL_DOOR
faceWorld:spawnFacing()
eq(faceWorld.player.facing, "down", "a doorway outside one spawns facing down")
faceWorld.player.facing = "left"
faceWorld.map.cellCollision = function() return 0x7b end -- COLL_CAVE
faceWorld:spawnFacing()
eq(faceWorld.player.facing, "down", "and so does a cave mouth")

-- checkWarpOnArrive has to ANSWER whether it warped: DoPlayerEvent hands the
-- frame to WarpToNewMapScript, so the rest of that frame's overworld loop --
-- DoPlayerMovement included -- never runs.  Falling through to World:movePlayer
-- gave a still-held direction one free step on the far side of the door, which
-- put the player a cell too far into Elm's Lab before its scene script started.
local arriveWorld = hookWorld()
arriveWorld.map.cellCollision = function() return 0x71 end -- COLL_DOOR
arriveWorld.map.warpAt = function() return { def = { destMap = "OTHER_MAP" } } end
arriveWorld.takeWarp = function() return true end
check(arriveWorld:checkWarpOnArrive(), "an immediate warp answers true")
arriveWorld.map.cellCollision = function() return 0x00 end
check(not arriveWorld:checkWarpOnArrive(), "an ordinary tile answers false")
arriveWorld.map.cellCollision = function() return 0x70 end -- carpet, needs DOWN
arriveWorld.heldDir = nil
check(not arriveWorld:checkWarpOnArrive(),
  "and a carpet with nothing held answers false rather than warping")
arriveWorld.heldDir = "down"
check(arriveWorld:checkWarpOnArrive(), "a carpet pressed into does warp")

-- GetWarpSFX picks by the tile the player STANDS on, not the destination.
local sfxWorld = hookWorld()
local played = {}
sfxWorld.playSfx = function(_, id) played[#played + 1] = id end
sfxWorld.map.cellCollision = function() return 0x71 end -- COLL_DOOR
sfxWorld:warpSound()
eq(played[1], 3, "COLL_DOOR plays Sfx_EnterDoor by NAME, not by a fixed index")
sfxWorld.map.cellCollision = function() return 0x7c end -- COLL_WARP_PANEL
sfxWorld:warpSound()
eq(played[2], 2, "COLL_WARP_PANEL plays Sfx_WarpTo")
sfxWorld.map.cellCollision = function() return 0x00 end
sfxWorld:warpSound()
eq(played[3], 4, "and anything else is Sfx_ExitBuilding")

-- ---- encounters -----------------------------------------------------------
-- StoreSwarmMapIndices falls THROUGH into SetSwarmFlag, so both halves land.
local swarmWorld = hookWorld()
swarmWorld:setSwarm(3, 4)
eq(swarmWorld.game.save.swarmMap, "OTHER_MAP", "swarm stores the map")
check(swarmWorld.game.save.dailyFlags.swarm,
  "and DAILYFLAGS1_SWARM, which is what CheckSwarmFlag clears it by")

-- ---- bag, money, coins ----------------------------------------------------
local bagWorld = hookWorld({ inventory = { POTION = 3 } })
check(bagWorld:hasItem(18), "checkitem finds a POTION by its ItemNames index")
check(not bagWorld:hasItem(0x47), "and does not find one that is not there")
check(not bagWorld:takeItem(18, 5),
  "takeitem takes NOTHING when the pack holds fewer than asked")
eq(bagWorld.game.save.inventory.POTION, 3, "so the count is untouched")
check(bagWorld:takeItem(18, 3), "and takes them all when it can")
check(bagWorld.game.save.inventory.POTION == nil, "clearing the row")

eq(bagWorld:money(0), 3000, "YOUR_MONEY is the player's wallet")
eq(bagWorld:money(1), 500, "MOMS_MONEY is the savings account")
bagWorld:setMoney(1, 9000)
eq(bagWorld.game.save.mom.savedMoney, 9000, "and setMoney writes it back")
eq(bagWorld:coins(), 40, "the coin case")
bagWorld:setCoins(9999)
eq(bagWorld:coins(), 9999, "and its write")

-- ---- party ----------------------------------------------------------------
local partyWorld = hookWorld({ party = { { species = "MAGIKARP" } } })
check(partyWorld:hasPoke(129), "checkpoke finds MAGIKARP in the party")
check(not partyWorld:hasPoke(213), "and refuses a species that is not in it")
check(partyWorld:giveEgg(152, 5), "giveegg builds the egg")
local egg = partyWorld.game.save.party[2]
check(egg.isEgg, "and marks the slot as one")
eq(egg.eggSteps, 20, "with the species' own hatch counter")
eq(egg.hp, 0, "and DayCare_GiveEgg's zeroed HP")
for _ = 1, 6 do partyWorld:giveEgg(152, 5) end
eq(#partyWorld.game.save.party, 6, "a full party refuses the next one")

-- ---- fruit trees ----------------------------------------------------------
-- FruitTreeItems is not extracted (nothing in the bytecode points at it), so
-- the table is src/core/gen2/Apricorns.lua's and this side turns its item ids
-- into the indices the VM's giveitem speaks in.  An item this stub data table
-- has no row for still answers 0, which is the "no fruit here" the VM prints
-- "BERRY" for.
local treeWorld = hookWorld()
treeWorld.game.data.items.BERRY = { id = "BERRY", name = "BERRY", index = 173 }
eq(treeWorld:fruitTreeItem(1), 173, "FRUITTREE_ROUTE_29 is a BERRY")
eq(treeWorld:fruitTreeItem(0x11), 0,
  "and an item the table has no row for is 0")
check(not treeWorld:fruitTreePicked(4), "an unpicked tree")
treeWorld:fruitTreePick(4)
check(treeWorld:fruitTreePicked(4), "stays picked")
check(treeWorld.game.save.fruitTrees[4], "on the save")
-- TryResetFruitTrees, the top of FruitTreeScript: the first tree examined
-- after the daily rollover refills every one of the thirty.
check(treeWorld:fruitTreeReset(), "the first look refills them all")
check(not treeWorld:fruitTreePicked(4), "so the picked one has fruit again")
check(not treeWorld:fruitTreeReset(),
  "and ENGINE_ALL_FRUIT_TREES stops a second refill the same day")

-- ---- music ----------------------------------------------------------------
-- musicfadeout queues the song UNDER the ramp; it must not start until the
-- ramp reaches the bottom, or the cross-fade reads as a cut.
local musicWorld = hookWorld()
musicWorld.game.data.audio.musicOrder = { "Music_Nothing", "Music_NewBarkTown" }
musicWorld.game.data.audio.songs = { Music_NewBarkTown = {} }
-- World captured the Music module by reference, so patching the two entry
-- points on the table is what keeps this headless: neither has a love-free
-- path, and neither is what is under test here.
local Music = require("src.core.Music")
local realFadeOut, realPlay = Music.fadeOut, Music.play
local started = {}
Music.fadeOut = function(control) started.control = control end
Music.play = function(_, name) started.song = name end
musicWorld:fadeOutMusic(1, 4)
eq(started.control, 4, "the ramp is handed the control byte")
check(musicWorld.pendingMusic ~= nil, "the label is queued")
eq(musicWorld.pendingMusic.left, 28, "for control * 7 frames of ramp")
for _ = 1, 27 do musicWorld:updateMusicFade() end
check(musicWorld.pendingMusic ~= nil, "and is still waiting one frame short")
musicWorld:updateMusicFade()
check(musicWorld.pendingMusic == nil, "then starts")
eq(started.song, "Music_NewBarkTown", "with the label the id named")
musicWorld:fadeOutMusic(0, 4)
check(musicWorld.pendingMusic == nil, "MUSIC_NONE queues nothing behind it")
-- tests/run_tests.lua dofiles every suite into ONE process, so a patched module
-- table would follow this file into the next one.
Music.fadeOut, Music.play = realFadeOut, realPlay

-- ---- the phone ------------------------------------------------------------
local phoneWorld = hookWorld()
-- PHONE_MOM is contact 1 (constants/phone_constants.asm); the table is keyed
-- by that number, not by the label.
check(phoneWorld:addPhoneNumber(1), "askforphonenumber stores one")
check(not phoneWorld:addPhoneNumber(1),
  "and refuses the same contact twice, the way _CheckCellNum does")
phoneWorld:setSpecialCall(3)
eq(phoneWorld:specialCall(), 3, "specialphonecall parks its id")
phoneWorld:setSpecialCall(0)
eq(phoneWorld:specialCall(), 0, "and SPECIALCALL_NONE clears it")

-- ---- roaming legendaries --------------------------------------------------
-- engine/overworld/wildmons.asm InitRoamMons / CheckEncounterRoamMon /
-- UpdateRoamMons / JumpRoamMons, and data/wild/roammon_maps.asm.  All of it is
-- pure state, so none of these need a map loaded.
-- Wrapped in a function because Lua 5.1 caps a chunk at 200 active locals and
-- this suite is already close to it; the alternative is renaming everything
-- above, which would make the diff lie about what changed.
local function roamerAndSwarmSuite()

local Encounter = require("src.battle.gen2.Encounter")
local Roamers = require("src.core.gen2.Roamers")

-- A random that hands back a scripted queue of ROM bytes.  `% n` because the
-- module asks for 0..n-1 and the cart masks the same byte down at each use.
local function seeded(bytes)
  local index = 0
  return function(n)
    index = index + 1
    return (bytes[index] or 0) % n
  end
end

eq(#Roamers.MAPS, Roamers.NUM_MAPS, "RoamMaps has NUM_ROAMMON_MAPS entries")
eq(Roamers.NUM_MAPS, 16, "...which is 16, the width JumpRoamMon's mask assumes")
-- Every destination has to be a START map too, or a beast that walks there can
-- never walk out again: `.Update`'s not-found path leaves it parked forever.
local strandedFrom = {}
for _, row in ipairs(Roamers.MAPS) do
  for _, dest in ipairs(row.to) do
    if not Roamers.entryFor(dest) then
      strandedFrom[#strandedFrom + 1] = row.map .. "->" .. dest
    end
  end
end
eq(table.concat(strandedFrom, ","), "",
  "every roam destination is itself a roam map")
-- The two four-way junctions, and the one dead end.  `and %11` gives a two-bit
-- index, so four is the most connections an entry can actually use.
eq(#Roamers.entryFor("ROUTE_36").to, 4, "ROUTE 36 is a four-way junction")
eq(#Roamers.entryFor("ROUTE_42").to, 4, "so is ROUTE 42")
eq(#Roamers.entryFor("ROUTE_39").to, 1, "ROUTE 39 is a dead end")
local widest = 0
for _, row in ipairs(Roamers.MAPS) do widest = math.max(widest, #row.to) end
eq(widest, 4, "no entry has more connections than a two-bit index can reach")
check(Roamers.entryFor("ROUTE_40") == nil,
  "the water routes are absent: ROUTE 40 is not a roam map")
check(Roamers.entryFor("ROUTE_41") == nil, "nor is ROUTE 41")

-- InitRoamMons, in slot order.  The order IS the identity: CheckEncounterRoamMon
-- indexes the structs by a random 0..2.
local roamSave = {}
Roamers.init(roamSave)
eq(#roamSave.roamers, 3, "three beasts")
eq(roamSave.roamers[1].species, "RAIKOU", "slot 1 is RAIKOU")
eq(roamSave.roamers[2].species, "ENTEI", "slot 2 is ENTEI")
eq(roamSave.roamers[3].species, "SUICUNE", "slot 3 is SUICUNE")
eq(roamSave.roamers[1].map, "ROUTE_42", "RAIKOU starts on ROUTE 42")
eq(roamSave.roamers[2].map, "ROUTE_37", "ENTEI starts on ROUTE 37")
eq(roamSave.roamers[3].map, "ROUTE_38", "SUICUNE starts on ROUTE 38")
eq(roamSave.roamers[1].level, 40, "all three are level 40")
eq(roamSave.roamers[1].hp, 0, "with no stats rolled yet")
roamSave.roamers[1].map = "ROUTE_29"
Roamers.init(roamSave)
eq(roamSave.roamers[1].map, "ROUTE_29",
  "a second InitRoamMons does not hand the player three fresh beasts")

-- `.Update`, byte by byte.  From ROUTE 42 the connection list is
-- { ROUTE_43, ROUTE_44, ROUTE_37, ROUTE_38 }, and the index is the low two
-- bits of the byte after it has been masked to five.
eq(Roamers.moveOne("ROUTE_42", nil, "NEW_BARK_TOWN", seeded({ 2 })),
  "ROUTE_37", "index 2 out of ROUTE 42 is ROUTE 37")
eq(Roamers.moveOne("ROUTE_42", nil, "NEW_BARK_TOWN", seeded({ 3 })),
  "ROUTE_38", "index 3 is ROUTE 38")
-- An index at or past the entry's count re-rolls: ROUTE 39 has one connection,
-- so only a byte whose low two bits are 0 (and which is not itself 0, that
-- being the jump) can pick it.
eq(Roamers.moveOne("ROUTE_39", nil, "NEW_BARK_TOWN", seeded({ 1, 4 })),
  "ROUTE_38", "an out-of-range index re-rolls rather than picking nil")
-- The last-map check: the beast refuses the map the player was on before this
-- one, which is what stops it shadowing a player pacing two routes.
eq(Roamers.moveOne("ROUTE_42", "ROUTE_37", "NEW_BARK_TOWN", seeded({ 2, 3 })),
  "ROUTE_38", "a connection equal to the last map re-rolls")
-- A beast standing somewhere RoamMaps does not list stays put (`cp -1 / ret z`
-- leaves b and c alone).
eq(Roamers.moveOne("GOLDENROD_CITY", nil, "NEW_BARK_TOWN", seeded({ 2 })),
  "GOLDENROD_CITY", "an unlisted map leaves the beast where it is")

-- The 1-in-32 jump, and the fact that the SAME byte decides both: a byte whose
-- low five bits are zero jumps instead of stepping.
eq(Roamers.moveOne("ROUTE_42", nil, "NEW_BARK_TOWN", seeded({ 32, 5 })),
  Roamers.MAPS[6].map, "a masked byte of 0 jumps to a random roam map")
eq(Roamers.MAPS[6].map, "ROUTE_34", "...which for index 5 is ROUTE 34")
-- JumpRoamMon re-rolls off the map the PLAYER is standing on.
eq(Roamers.jumpOne("ROUTE_34", seeded({ 5, 6 })), "ROUTE_35",
  "a jump onto the player's own map re-rolls")

-- A seeded walk across connected maps, which is the thing that has to hold
-- end to end: 42 -> 37 -> 38 -> 39 -> 38.
local walkSave = {}
Roamers.init(walkSave)
local WALK = { 2, 1, 1, 1, 4 }
local WANT = { "ROUTE_37", "ROUTE_38", "ROUTE_39", "ROUTE_38" }
local rng = seeded(WALK)
local where = walkSave.roamers[1].map
local path = {}
for _ = 1, 4 do
  where = Roamers.moveOne(where, nil, "NEW_BARK_TOWN", rng)
  path[#path + 1] = where
end
eq(table.concat(path, ","), table.concat(WANT, ","),
  "a seeded roamer walks 42 -> 37 -> 38 -> 39 -> 38")

-- UpdateRoamMons moves every live beast and then backs up the map indices, so
-- the NEXT update avoids the map the player has just left.
local updSave = {}
Roamers.init(updSave)
Roamers.update(updSave, "ROUTE_30", seeded({ 2, 1, 1 }))
eq(updSave.roamerMaps.current, "ROUTE_30", "the player's map becomes Cur")
check(updSave.roamerMaps.last == nil, "and Last is still empty on the first")
Roamers.update(updSave, "ROUTE_31", seeded({ 2, 1, 1 }))
eq(updSave.roamerMaps.last, "ROUTE_30", "Cur shifts into Last on the second")
eq(updSave.roamerMaps.current, "ROUTE_31", "...and the new map into Cur")

-- JumpRoamMons scatters all three (the Teleport map setup script).
local jumpSave = {}
Roamers.init(jumpSave)
Roamers.jumpAll(jumpSave, "NEW_BARK_TOWN", seeded({ 0, 1, 2 }))
eq(jumpSave.roamers[1].map, "ROUTE_29", "RAIKOU jumped to entry 0")
eq(jumpSave.roamers[2].map, "ROUTE_30", "ENTEI to entry 1")
eq(jumpSave.roamers[3].map, "ROUTE_31", "SUICUNE to entry 2")

-- CheckEncounterRoamMon's three gates off ONE byte.
local encSave = {}
Roamers.init(encSave)
check(Roamers.checkEncounter(encSave, "ROUTE_42", true, seeded({ 1 })) == nil,
  "surfing refuses before anything else")
check(Roamers.checkEncounter(encSave, "ROUTE_42", false, seeded({ 100 })) == nil,
  "a byte of 100 or more is no encounter")
check(Roamers.checkEncounter(encSave, "ROUTE_42", false, seeded({ 4 })) == nil,
  "a byte whose low two bits are 0 is no encounter")
local met = Roamers.checkEncounter(encSave, "ROUTE_42", false, seeded({ 1 }))
check(met ~= nil, "byte 1 picks slot 1")
eq(met and met.species, "RAIKOU", "...which is RAIKOU, and it is on ROUTE 42")
eq(met and met.level, 40, "...at level 40")
check(Roamers.checkEncounter(encSave, "ROUTE_42", false, seeded({ 2 })) == nil,
  "byte 2 picks ENTEI, which is on ROUTE 37, so nothing happens")
check(Roamers.checkEncounter(encSave, "ROUTE_37", false, seeded({ 2 })) ~= nil,
  "...and the same byte on ROUTE 37 does meet it")

-- A beast that has been beaten is gone for good.
local goneSave = {}
Roamers.init(goneSave)
Roamers.endBattle(goneSave, 1, "win", 40, "ROUTE_42", seeded({ 2 }))
check(goneSave.roamers[1].species == nil, "a defeated beast loses its species")
check(goneSave.roamers[1].map == nil, "...and its map")
check(Roamers.checkEncounter(goneSave, "ROUTE_42", false, seeded({ 1 })) == nil,
  "...so it is never met again")
local caughtSave = {}
Roamers.init(caughtSave)
Roamers.endBattle(caughtSave, 1, "caught", 40, "ROUTE_42", seeded({ 2 }))
check(caughtSave.roamers[1].species == nil, "a caught beast goes the same way")

-- HP ACROSS TWO ENCOUNTERS, which is the whole point of the roam struct.
local ROAM_DATA = {
  pokemon = {
    growthRates = {
      GROWTH_SLOW = { numerator = 5, denominator = 4, squared = 0,
        linear = 0, constant = 0 },
    },
    RAIKOU = {
      id = "RAIKOU", index = 243, name = "RAIKOU",
      baseStats = { hp = 90, attack = 85, defense = 75, speed = 115,
        specialAttack = 115, specialDefense = 100 },
      types = { "ELECTRIC", "ELECTRIC" }, catchRate = 3, baseExp = 216,
      growthRate = "GROWTH_SLOW", genderRatio = 0xff,
      levelMoves = { { level = 1, move = "BITE" } },
      evolutions = {},
    },
  },
  moves = { BITE = { id = "BITE", name = "BITE", pp = 25 } },
}

local hpSave = {}
Roamers.init(hpSave)
local beast, slot = Roamers.beginBattle(hpSave, 1, ROAM_DATA)
check(beast ~= nil, "the first encounter builds the beast")
eq(beast.species, "RAIKOU", "...as RAIKOU")
eq(beast.level, 40, "...at level 40")
check(#beast.moves > 0,
  "...through Mon.new, so it has a Gen 2 moveset rather than none")
eq(slot.hp, beast.maxHp,
  ".InitRoamHP banks the full HP the moment the battle starts")
check(slot.dvs ~= nil, "and the DVs are kept from the first meeting")
local firstDVs = slot.dvs
-- The player knocks it down and it flees: DRAW, so the struct keeps the HP.
beast.hp = 17
Roamers.endBattle(hpSave, 1, "fled", beast.hp, "ROUTE_42", seeded({ 2 }))
eq(slot.hp, 17, "a flee banks the damage")
-- ...and the beast moved on, so it has to be found again.
check(slot.map ~= nil, "the beast is still out there")
local again = Roamers.beginBattle(hpSave, 1, ROAM_DATA)
eq(again.hp, 17, "the second encounter is the SAME hurt beast")
eq(again.maxHp, beast.maxHp, "...at the same max HP")
eq(again.dvs.attack, firstDVs.attack, "...and the same individual")
eq(again.dvs.special, firstDVs.special, "...on every DV")

-- The player running away banks the damage the same way (TryToRunAwayFromBattle
-- writes DRAW too).
local runSave = {}
Roamers.init(runSave)
local runBeast = Roamers.beginBattle(runSave, 1, ROAM_DATA)
runBeast.hp = 3
Roamers.endBattle(runSave, 1, "run", runBeast.hp, "ROUTE_42", seeded({ 2 }))
eq(runSave.roamers[1].hp, 3, "a player run banks the damage as well")

-- BattleEnd_HandleRoamMons `.not_roaming`: one wild battle in sixteen moves the
-- beasts even though you never saw one.
local driftSave = {}
Roamers.init(driftSave)
check(not Roamers.afterWildBattle(driftSave, "ROUTE_30", seeded({ 1 })),
  "fifteen wild battles in sixteen leave the beasts alone")
check(Roamers.afterWildBattle(driftSave, "ROUTE_30", seeded({ 16, 2, 1, 1 })),
  "and the sixteenth moves them")

-- ---- swarms ---------------------------------------------------------------
-- engine/events/specials.asm StoreSwarmMapIndices / SetSwarmFlag /
-- CheckSwarmFlag, and _SwarmWildmonCheck's place in front of the normal table.

local Swarm = Roamers.Swarm

-- A stand-in cache.  encounters.swarmGrass is NOT in data/generated today, so
-- this is also the assertion that the reader will pick it up unchanged when it
-- arrives: the shape is exactly encounters.grass'.
local SWARM_ENCOUNTERS = {
  grass = {
    ROUTE_35 = { rates = { MORN = 5, DAY = 5, NITE = 5 },
      slots = { MORN = { { species = "NIDORAN_M", level = 12 } },
        DAY = { { species = "NIDORAN_M", level = 12 } },
        NITE = { { species = "NIDORAN_M", level = 12 } } } },
  },
  water = {},
  swarmGrass = {
    ROUTE_35 = { rates = { MORN = 25, DAY = 25, NITE = 25 },
      slots = { MORN = { { species = "YANMA", level = 12 } },
        DAY = { { species = "YANMA", level = 12 } },
        NITE = { { species = "YANMA", level = 12 } } } },
  },
  swarmWater = {},
}

local swarmSave = {}
check(not Swarm.active(swarmSave), "no swarm to start with")
eq(Swarm.tables(swarmSave, SWARM_ENCOUNTERS, "ROUTE_35"), SWARM_ENCOUNTERS,
  "and with none, the encounter tables are handed back untouched")

Swarm.set(swarmSave, "ROUTE_35")
check(Swarm.active(swarmSave),
  "StoreSwarmMapIndices falls through into SetSwarmFlag")
eq(Swarm.mapId(swarmSave), "ROUTE_35", "and parks the map")
eq(Swarm.check(swarmSave), 0, "CheckSwarmFlag answers 0 while the flag is up")

local view = Swarm.tables(swarmSave, SWARM_ENCOUNTERS, "ROUTE_35")
check(view ~= SWARM_ENCOUNTERS, "an active swarm builds a view")
eq(view.grass.ROUTE_35.slots.DAY[1].species, "YANMA",
  "_SwarmWildmonCheck searches the swarm table BEFORE the Johto one")
eq(view.grass.ROUTE_35.rates.DAY, 25, "...rate and all")
eq(Encounter.grassSlot(view, "ROUTE_35", "DAY", function() return 0 end)
  .species, "YANMA", "so Encounter rolls the swarm's list unchanged")
-- The override is one map wide: everywhere else still reads its own table.
eq(SWARM_ENCOUNTERS.grass.ROUTE_35.slots.DAY[1].species, "NIDORAN_M",
  "and the cache's own table is not mutated")
eq(Swarm.tables(swarmSave, SWARM_ENCOUNTERS, "ROUTE_32"), SWARM_ENCOUNTERS,
  "a swarm on ROUTE 35 does not touch ROUTE 32")
-- A swarm map the swarm TABLE does not list falls through to the normal
-- lookup rather than blanking the map (`jr nc, .noSwarm`).
local fishOnly = {}
Swarm.set(fishOnly, "ROUTE_32")
eq(Swarm.tables(fishOnly, SWARM_ENCOUNTERS, "ROUTE_32"), SWARM_ENCOUNTERS,
  "a swarm map with no swarm rows falls through to the normal table")

-- ActivateFishingSwarm sets the fishing flag and lights the same daily flag,
-- but leaves the map pair alone.
local fishSave = {}
Swarm.setFishing(fishSave, Swarm.FISH_QWILFISH)
check(Swarm.active(fishSave), "a fishing swarm lights DAILYFLAGS1_SWARM too")
eq(Swarm.fishing(fishSave), Swarm.FISH_QWILFISH, "and records which one")
check(fishSave.swarmMap == nil, "without touching the map pair")

-- EXPIRY.  Nothing but the daily reset ends a swarm: CheckDailyResetTimer
-- zeroes the daily flags, and CheckSwarmFlag -- which runs immediately after
-- it in CheckTimeEvents -- is what then clears the map pair.
local dailySave = {}
Swarm.set(dailySave, "ROUTE_35")
check(not Swarm.timeEvents(dailySave, 100),
  "the first time check only starts the countdown")
check(Swarm.active(dailySave), "so the swarm is still on")
check(not Swarm.timeEvents(dailySave, 100),
  "and the same day does not end it either")
eq(Swarm.mapId(dailySave), "ROUTE_35", "the map is still parked")
check(Swarm.timeEvents(dailySave, 101), "the next day ends it")
check(not Swarm.active(dailySave), "the daily flag is gone")
check(dailySave.swarmMap == nil, "and CheckSwarmFlag cleared the map pair")
eq(Swarm.check(dailySave), 1, "CheckSwarmFlag now answers 1")
eq(Swarm.tables(dailySave, SWARM_ENCOUNTERS, "ROUTE_35"), SWARM_ENCOUNTERS,
  "so ROUTE 35 is back on its own encounter table")

-- A fishing swarm expires on the same clock and takes its flag with it.
local fishExpire = {}
Swarm.setFishing(fishExpire, Swarm.FISH_REMORAID)
Swarm.timeEvents(fishExpire, 200)
Swarm.timeEvents(fishExpire, 201)
eq(Swarm.fishing(fishExpire), Swarm.FISH_NONE,
  "the fishing flag is cleared with the rest")

-- The cache does not carry the swarm or roam tables today.  Assert the reader
-- SHAPE rather than the data, so this suite tells the truth either way.
check(Roamers.mapTable(nil) == Roamers.MAPS,
  "with no extracted RoamMaps the transcribed table is used")
local FAKE_ROAM = { { map = "ROUTE_29", to = { "ROUTE_30" } } }
check(Roamers.mapTable({ roamMaps = FAKE_ROAM }) == FAKE_ROAM,
  "and an extracted encounters.roamMaps takes over the moment it appears")

end
roamerAndSwarmSuite()

-- ---- the hook table itself ------------------------------------------------
-- Every hook the interpreter guards has to exist by the name the VM looks it
-- up under, or the command it belongs to is silently inert.  Reading the Vm
-- source is the honest check here: it names each one exactly once.
local vmSource = (function()
  local f = io.open("src/script/gen2/Vm.lua", "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end)()
check(vmSource ~= nil, "the VM source is readable")
if vmSource then
  local wired = hookWorld():specialHooks()
  check(wired.world ~= nil, "specialHooks hands the world to Specials.lua")
  local wantHooks = {
    "getMapScene", "getTimeOfDay", "gsVersion", "getEngineFlag",
    "setEngineFlag", "writeVar", "callAsm", "appear", "moveObject",
    "variableSprite", "changeBlock", "earthquake", "warpTo", "warpCheck",
    "warpSound", "newLoadMap", "writeCmdQueue", "delCmdQueue",
    "setWarpMod", "setBlackoutMap", "setSwarm",
    "setWildEncounters", "rollWild", "playMapMusic", "fadeOutMusic",
    "dontRestartMapMusic", "hasItem", "takeItem", "getMoney", "setMoney",
    "getCoins", "setCoins", "hasPoke", "giveEgg", "getLandmarkName",
    "fruitTreeItem", "fruitTreePicked", "fruitTreePick", "addPhoneNumber",
    "setSpecialCall", "getSpecialCall", "specials",
  }
  local worldSource = (function()
    local f = io.open("src/world/gen2/World.lua", "r")
    if not f then return "" end
    local body = f:read("*a")
    f:close()
    return body
  end)()
  local unwired = {}
  for _, name in ipairs(wantHooks) do
    -- `hooks.<name>` is how Vm.new reads it, `<name> =` is how World writes it.
    if not (vmSource:find("hooks." .. name, 1, true)
        and worldSource:find("\n    " .. name .. " = ", 1, true)) then
      unwired[#unwired + 1] = name
    end
  end
  eq(table.concat(unwired, ","), "", "every VM hook is wired from World")
end

-- ---- readvar: the rest of engine/overworld/variables.asm .VarActionTable --
-- VAR_WEEKDAY and VAR_FACING are covered above (through the hooks table) and
-- in gen2_map_callbacks_test.lua; this pins the other eleven live slots a
-- Gold script reads through readvar.
local Phone = require("src.core.gen2.Phone")
local rv, rvGame = hookWorld()
rv.player.cellX, rv.player.cellY = 7, 9
rv.map.def.environmentId = 4 -- CAVE (constants/map_data_constants.asm)

eq(rv:readVar(0x01), 0, "VAR_PARTYCOUNT: an empty party is 0")
rvGame.save.party = { {}, {} }
eq(rv:readVar(0x01), 2, "VAR_PARTYCOUNT reads save.party's length")

eq(rv:readVar(0x02), 0, "VAR_BATTLERESULT: no battle fought yet reads 0")
rv.lastBattleResult = 1
eq(rv:readVar(0x02), 1, "VAR_BATTLERESULT reads the last battle's outcome")

rvGame.save.pokedex = {
  caught = { CHIKORITA = true, MAGIKARP = true },
  seen = { CHIKORITA = true, MAGIKARP = true, SHUCKLE = true },
}
eq(rv:readVar(0x05), 2, "VAR_DEXCAUGHT counts save.pokedex.caught")
eq(rv:readVar(0x06), 3, "VAR_DEXSEEN counts save.pokedex.seen")

rvGame.save.player.badges = { BOULDERBADGE = true }
rvGame.save.player.kantoBadges = { EARTHBADGE = true, VOLCANOBADGE = true }
eq(rv:readVar(0x07), 3,
  "VAR_BADGES counts BOTH badge cases, the way CountSetBits walks wBadges' two bytes")

eq(rv:readVar(0x08), 0, "VAR_MOVEMENT: PLAYER_NORMAL is wPlayerState 0")
rv.playerState = require("src.world.gen2.FieldMoves").PLAYER_SURF
eq(rv:readVar(0x08), 4, "VAR_MOVEMENT: PLAYER_SURF is wPlayerState 4")

rv.clockHour = 14
eq(rv:readVar(0x0a), 14, "VAR_HOUR reads the RTC hour")

eq(rv:readVar(0x0c), 1, "VAR_MAPGROUP reads the current map's group")
eq(rv:readVar(0x0d), 2, "VAR_MAPNUMBER reads the current map's number")

eq(rv:readVar(0x0f), 4, "VAR_ENVIRONMENT reads the map's raw environmentId")

rvGame.save.currentBox = 1
rvGame.save.boxes = { { {}, {}, {} } }
eq(rv:readVar(0x10), 17,
  "VAR_BOXSPACE is MONS_PER_BOX (20) minus the current box's 3 mons")

rvGame.save.bugContest = { minutes = 15, seconds = 30 }
eq(rv:readVar(0x11), 15, "VAR_CONTESTMINUTES reads wBugContestMinsRemaining")

eq(rv:readVar(0x12), 7, "VAR_XCOORD reads the player's cell x")
eq(rv:readVar(0x13), 9, "VAR_YCOORD reads the player's cell y")

eq(rv:readVar(0x14), 0, "VAR_SPECIALPHONECALL: nothing queued reads 0")
Phone.queueSpecialCall(rvGame.save, 3)
eq(rv:readVar(0x14), 3, "VAR_SPECIALPHONECALL reads back what was queued")

-- VAR_UNOWNCOUNT (0x0e): CountUnown walks wUnownDex, a per-FORM catch list.
-- The port's pokedex only ever flags the species UNOWN as one boolean, so
-- there is no honest count to answer with; it must not silently invent one.
eq(rv:readVar(0x0e), 0,
  "VAR_UNOWNCOUNT: blocked upstream, no per-letter Unown tracking to read")

-- ---- SELECT menu shortcut -------------------------------------------------
-- engine/overworld/select_menu.asm (SelectMenu / CheckRegisteredItem /
-- UseRegisteredItem) plus RegisterItem (engine/items/pack.asm).  This port
-- reaches RegisterItem off the one PACK button left unbound (SELECT on a
-- highlighted row) rather than the cart's own USE/GIVE/TOSS/SEL/QUIT
-- submenu, which is not built.
do
local selWorld, selGame = fakeWorld({}, fakePlayer(5, 5, "down"))
selGame.data = { items = ITEMS, moves = DATA.moves, pokemon = DATA.pokemon }
selGame.save.inventory = { POTION = 1, REPEL = 1, HM_CUT = 1 }

-- CheckSelectableItem's gate: a TM/HM refuses outright and nothing is set.
eq(selWorld:registerItem("HM_CUT"), false,
  "RegisterItem.cant_register: a TM/HM cannot be registered")
check(selGame.save.registeredItem == nil,
  "and the refusal never touches the slot")

-- A selectable item registers.
eq(selWorld:registerItem("POTION"), true, "a plain ITEM pocket item registers")
eq(selGame.save.registeredItem.id, "POTION", "RegisteredItemText names it")
eq(selWorld:registeredItemId(), "POTION",
  "CheckRegisteredItem confirms it while the bag still has one")

-- No field handler is wired for POTION, so SELECT lands on CantUseItem --
-- ItemsOakWarningText, the same line a busy world answers.
eq(selWorld:useSelectItem(), "cant_use",
  "UseRegisteredItem.CantUse: no field handler for this item yet")

selWorld.battleActive = true
eq(selWorld:useSelectItem(), "nowhere",
  "SELECT is refused mid-battle exactly like the PACK's own UseItem")
selWorld.battleActive = nil

-- Registering something else re-runs CheckRegisteredItem.IsSameItem's swap;
-- REPEL's field handler is useFieldItem's existing UseRepel arm, so SELECT
-- dispatches through the identical path a PACK UseItem would.
eq(selWorld:registerItem("REPEL"), true, "REPEL replaces the registered item")
eq(selWorld:useSelectItem(), "repel_used",
  "SELECT on a registered REPEL runs UseRepel through useFieldItem")
eq(selGame.save.inventory.REPEL, nil,
  "and the last REPEL leaves the bag the same way a PACK use would")

-- CheckRegisteredItem.NotEnoughItems: the registered item running out of the
-- bag silently clears the slot rather than holding a stale pointer.
eq(selWorld:registerItem("POTION"), true, "register the POTION again")
selGame.save.inventory.POTION = nil
check(selWorld:registeredItemId() == nil,
  "an item gone from the bag no longer answers as registered")
check(selGame.save.registeredItem == nil,
  "and the slot itself is cleared, not just skipped")

-- SelectMenu.NotRegistered: nothing registered prints MayRegisterItemText.
eq(selWorld:useSelectItem(), "not_registered",
  "SELECT with nothing registered answers not_registered")

-- The PACK side: the item submenu's SEL row is RegisterItem's only door --
-- the cart's SELECT is the bag's own item shuffle
-- (engine/items/pack.asm:1290 Pack_InterpretJoypad .select).
selGame.save.inventory.POTION = 3
selGame.input = stubInput()
local selPack = PackMenu.new(selGame, { pocket = "ITEM" })
selPack.index = 1
check(selPack.rows[1].id == "POTION", "the ITEM pocket row under test")
selGame.input:press("select")
selPack:update(0)
eq(selPack.switching, 1, "SELECT on a row arms the item shuffle")
check(selGame.save.registeredItem == nil, "and registers nothing")
selGame.input:press("b")
selPack:update(0)
check(selPack.switching == nil and selPack.message == nil,
  "B backs out of the shuffle")
selPack:openSubmenu()
check(table.concat(selPack.submenu.rows, ","):find("sel", 1, true) ~= nil,
  "the POTION submenu offers the SEL row")
selPack:closeSubmenu()
selPack:registerSelected()
check(selPack.message ~= nil, "SEL opens RegisteredItemText")
eq(selGame.save.registeredItem.id, "POTION",
  "and World:registerItem actually ran")
selGame.input:press("a")
selPack:update(0)
check(selPack.message == nil, "A dismisses the confirmation like any prompt")

-- SELECT on CANCEL does nothing -- there is no row under the cursor.
selPack.index = selPack:total()
selGame.save.registeredItem = nil
selGame.input:press("select")
selPack:update(0)
check(selPack.switching == nil and selPack.message == nil,
  "SELECT on CANCEL arms nothing")
selPack:registerSelected()
check(selGame.save.registeredItem == nil, "and the slot stays empty")

-- CantRegisterText: a TM/HM row refuses from the PACK too.
selGame.save.inventory.HM_CUT = 1
selPack:rebuild()
local tmPack = PackMenu.new(selGame, { pocket = "TM_HM" })
tmPack.index = 1
check(tmPack.rows[1].id == "HM_CUT", "the TM/HM pocket row under test")
tmPack:registerSelected()
check(tmPack.message ~= nil, "SEL on the HM still opens a message")
check(selGame.save.registeredItem == nil,
  "CantRegisterText: the HM never becomes the registered item")
end

-- ---- the BICYCLE ----------------------------------------------------------
-- BikeFunction (engine/events/overworld.asm) end to end: where the bike may be
-- got on, what the queued script does, and the Cycling Road's two flags.
-- Wrapped in a function rather than a `do` block: block locals still count
-- against the main chunk's 200-local ceiling and this file is already near it.
local function bikeChecks()
local Bike = require("src.world.gen2.Bike")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Player = require("src.world.gen2.Player")

-- .CheckEnvironment: CheckOutdoorMap plus CAVE and GATE by name.
check(Bike.environmentAllows("ROUTE"), "a ROUTE allows the bike")
check(Bike.environmentAllows("TOWN"), "so does a TOWN")
check(Bike.environmentAllows("CAVE"), "and a CAVE")
check(Bike.environmentAllows("GATE"), "and a gatehouse")
check(not Bike.environmentAllows("INDOOR"), "an INDOOR map refuses")
check(not Bike.environmentAllows("DUNGEON"), "and so does a DUNGEON")

-- The tile half: GetPlayerTilePermission `and $f` has to be LAND_TILE.
check(Bike.canUseHere("ROUTE", COLL_FLOOR), "plain ground is rideable")
check(not Bike.canUseHere("ROUTE", COLL_WATER), "water is not")
-- A door tile IS land in CollisionPermissionTable, which is why the door is
-- not in this list: the tiles the lo nybble rejects are water and walls.
check(not Bike.canUseHere("ROUTE", 0x07), "and neither is a wall")
check(Bike.canUseHere("ROUTE", 0x71), "a door tile is LAND_TILE, so it passes")

-- .TryBike's four answers.
eq(Bike.tryBike({ state = FieldMoves.PLAYER_NORMAL, environment = "ROUTE",
  collision = COLL_FLOOR }), "mount", "walking on a route gets on")
eq(Bike.tryBike({ state = FieldMoves.PLAYER_BIKE, environment = "ROUTE",
  collision = COLL_FLOOR }), "dismount", "riding on a route gets off")
eq(Bike.tryBike({ state = FieldMoves.PLAYER_BIKE, environment = "ROUTE",
  collision = COLL_FLOOR, alwaysOnBike = true }), "cant_get_off",
  "ALWAYS_ON_BIKE refuses the dismount")
check(Bike.tryBike({ state = FieldMoves.PLAYER_SURF, environment = "ROUTE",
  collision = COLL_FLOOR }) == nil, "a surfing player falls to .CannotUseBike")
check(Bike.tryBike({ state = FieldMoves.PLAYER_NORMAL, environment = "INDOOR",
  collision = COLL_FLOOR }) == nil, "and so does an indoor one")

-- CheckUpdatePlayerSprite's biking arms.
eq(Bike.mapSetupState(FieldMoves.PLAYER_NORMAL, "ROUTE", true),
  FieldMoves.PLAYER_BIKE, ".CheckForcedBiking puts the player on the bike")
eq(Bike.mapSetupState(FieldMoves.PLAYER_BIKE, "INDOOR", false),
  FieldMoves.PLAYER_NORMAL, "riding indoors takes them off it")
eq(Bike.mapSetupState(FieldMoves.PLAYER_BIKE, "CAVE", false),
  FieldMoves.PLAYER_BIKE, "a cave keeps them on it")
eq(Bike.mapSetupState(FieldMoves.PLAYER_SURF, "INDOOR", false),
  FieldMoves.PLAYER_SURF,
  "and with no tile to read, the surf arms are left alone")

-- Its surfing arms, which is what a save made afloat reloads through.
-- .CheckSurfing reads the tile the player is STANDING on, so it is the water
-- under them that keeps them there.
eq(Bike.mapSetupState(FieldMoves.PLAYER_SURF, "ROUTE", false, true),
  FieldMoves.PLAYER_SURF, "landing on water while surfing keeps surfing")
eq(Bike.mapSetupState(FieldMoves.PLAYER_SURF_PIKA, "ROUTE", false, true),
  FieldMoves.PLAYER_SURF_PIKA, "and a PIKACHU rider keeps its own sprite")
eq(Bike.mapSetupState(FieldMoves.PLAYER_NORMAL, "ROUTE", false, true),
  FieldMoves.PLAYER_SURF, "a load onto water is a surfing load")
eq(Bike.mapSetupState(FieldMoves.PLAYER_SURF, "ROUTE", false, false),
  FieldMoves.PLAYER_NORMAL,
  ".ResetSurfingOrBikingState takes a warp onto land off the Lapras")
eq(Bike.mapSetupState(FieldMoves.PLAYER_SURF, "ROUTE", true, true),
  FieldMoves.PLAYER_BIKE, "and .CheckForcedBiking still wins outright")
eq(Bike.mapSetupState(FieldMoves.PLAYER_BIKE, "ROUTE", false, false),
  FieldMoves.PLAYER_BIKE, "a dry outdoor load leaves the bike alone")

-- .DoStep and .GetDPad.
eq(Bike.stepFrames(FieldMoves.PLAYER_NORMAL, "up", false, 16), 16,
  "a walk is a walk")
eq(Bike.stepFrames(FieldMoves.PLAYER_BIKE, "up", false, 16), 8,
  "STEP_BIKE is half the duration of STEP_WALK")
eq(Bike.stepFrames(FieldMoves.PLAYER_BIKE, "up", true, 16), 16,
  "downhill and not moving down is back to walking pace")
eq(Bike.stepFrames(FieldMoves.PLAYER_BIKE, "down", true, 16), 8,
  "downhill and moving down is the fast step")
eq(Bike.forcedDirection(nil, true), "down",
  "no direction held on a downhill map reads as DOWN")
eq(Bike.forcedDirection("up", true), "up", "a held direction still wins")
check(Bike.forcedDirection(nil, false) == nil, "and off the road, nothing")

-- The Player really does cross the cell in half the frames.
local fast = Player.new(3, 3, "down", nil)
fast.stepFrames = Bike.stepFrames(FieldMoves.PLAYER_BIKE, "down", false,
  Player.STEP_FRAMES)
eq(fast:tryMove("down", fakeMap({}), nil), "moved", "the bike step starts")
local frames = 0
while fast.moving and frames < 40 do fast:update() frames = frames + 1 end
eq(frames, 8, "and lands after eight")
eq(fast.cellY, 4, "one cell further down")

-- The world path.  A ROUTE with the player standing on plain ground.
local bikeWorld = fakeWorld({}, fakePlayer(5, 5, "down"))
eq(bikeWorld.playerState, FieldMoves.PLAYER_NORMAL, "the world starts walking")
eq(bikeWorld:useFieldItem("BICYCLE"), "bike_on",
  "the BICYCLE is claimed by useFieldItem now")
local mount = bikeWorld.queuedScript
check(mount ~= nil, "and QueueScript left a script behind")
local loadvar
for _, cmd in ipairs(mount) do
  if cmd.op == "loadvar" then loadvar = cmd end
end
check(loadvar ~= nil, "Script_GetOnBike is a loadvar")
eq(loadvar.args[1], Bike.VAR_MOVEMENT, "of VAR_MOVEMENT")
eq(loadvar.args[2], Bike.PLAYER_BIKE_ID, "with PLAYER_BIKE")

-- That loadvar is the whole mount: writeVar is where it lands.
bikeWorld:writeVar(loadvar.args[1], loadvar.args[2])
eq(bikeWorld.playerState, FieldMoves.PLAYER_BIKE, "and the player is riding")
eq(bikeWorld:readVar(Bike.VAR_MOVEMENT), 1,
  "VAR_MOVEMENT reads back PLAYER_BIKE")

-- Riding, the same item gets off again.
eq(bikeWorld:useFieldItem("BICYCLE"), "bike_off", "the second use dismounts")
local off
for _, cmd in ipairs(bikeWorld.queuedScript) do
  if cmd.op == "loadvar" then off = cmd end
end
eq(off.args[2], Bike.PLAYER_NORMAL_ID, "back to PLAYER_NORMAL")

-- A forced stretch refuses, and refuses WITHOUT touching wPlayerState.
bikeWorld:writeVar(Bike.VAR_MOVEMENT, Bike.PLAYER_BIKE_ID)
bikeWorld:setEngineFlag(Bike.ENGINE_ALWAYS_ON_BIKE, true)
eq(bikeWorld:useFieldItem("BICYCLE"), "bike_stuck",
  "ALWAYS_ON_BIKE is Script_CantGetOffBike")
for _, cmd in ipairs(bikeWorld.queuedScript) do
  check(cmd.op ~= "loadvar", "which never writes VAR_MOVEMENT")
end
eq(bikeWorld.playerState, FieldMoves.PLAYER_BIKE, "so the player still rides")
bikeWorld:setEngineFlag(Bike.ENGINE_ALWAYS_ON_BIKE, false)

-- Indoors is .CannotUseBike, which is wFieldMoveSucceeded 0 -- the PACK's own
-- Oak line, not a queued script.
local hallWorld = fakeWorld({}, fakePlayer(5, 5, "down"), nil, nil,
  { environment = "INDOOR" })
eq(hallWorld:useFieldItem("BICYCLE"), "nowhere", "no cycling indoors")
check(hallWorld.queuedScript == nil, "and nothing was queued")

-- SELECT sets wUsingItemWithSelect, and .CheckIfRegistered swaps in the silent
-- pair: the same state change with no text at all.
local selWorld = fakeWorld({}, fakePlayer(5, 5, "down"))
selWorld.game.save.registeredItem = { id = "BICYCLE" }
eq(selWorld:useSelectItem(), "bike_on", "SELECT on the BICYCLE gets on")
for _, cmd in ipairs(selWorld.queuedScript) do
  check(cmd.op ~= "rawtext", "Script_GetOnBike_Register prints nothing")
end
check(selWorld.usingItemWithSelect == nil,
  "and wUsingItemWithSelect is cleared behind it")
end
bikeChecks()

-- ---------------------------------------------------------------- ice slides
-- CheckStandingOnIce / .CheckForced / STEP_ICE.  Wrapped in a function for the
-- same 200-local ceiling reason as bikeChecks.
local function iceSlideChecks()
  local Player = require("src.world.gen2.Player")
  local COLL_WALL = 0x07
  local iceCells = {
    [5 * 100 + 3] = COLL_ICE,
    [5 * 100 + 4] = COLL_ICE,
    [5 * 100 + 5] = COLL_ICE,
    [5 * 100 + 6] = COLL_WALL,
  }
  local slide = fakeWorld(iceCells, Player.new(2, 5, "right"))
  slide.player.turnArmed = false
  slide.entities = { slide.player }
  slide.heldDir = "right"
  -- Tap: start the first step, then release.  The latch has to carry the rest.
  for _ = 1, 2 do slide:step() end
  check(slide.player.moving or slide.turningDirection == "right",
    "a step onto ice latches FinishFacing")
  slide.heldDir = nil
  local frames = 0
  while frames < 200 do
    slide:step()
    frames = frames + 1
    if not slide.player.moving and not slide.turningDirection then break end
  end
  eq(slide.player.cellX, 5, "the slide rests on the last ice cell")
  eq(slide.player.cellY, 5, "same row")
  check(slide.turningDirection == nil, "and the bump clears the latch")

  -- Landing on ordinary floor ends the slide without a wall.
  local mixed = {
    [5 * 100 + 3] = COLL_ICE,
    [5 * 100 + 4] = COLL_ICE,
    -- (5,5) is COLL_FLOOR by default
  }
  local stop = fakeWorld(mixed, Player.new(2, 5, "right"))
  stop.player.turnArmed = false
  stop.entities = { stop.player }
  stop.heldDir = "right"
  for _ = 1, 2 do stop:step() end
  stop.heldDir = nil
  frames = 0
  while frames < 200 do
    stop:step()
    frames = frames + 1
    if not stop.player.moving and not stop.turningDirection then break end
  end
  eq(stop.player.cellX, 5, "leaving ice onto floor is the rest position")
  eq(stop.player.cellY, 5, "same row on the floor landing")

  -- Off ice, a released direction is still a single cell.
  local dry = fakeWorld({}, Player.new(2, 5, "right"))
  dry.player.turnArmed = false
  dry.entities = { dry.player }
  dry.heldDir = "right"
  for _ = 1, 2 do dry:step() end
  dry.heldDir = nil
  frames = 0
  while frames < 40 do
    dry:step()
    frames = frames + 1
    if not dry.player.moving then break end
  end
  eq(dry.player.cellX, 3, "plain floor still walks one cell per press")
end
iceSlideChecks()

-- ------------------------------------------------- ledges and one-way walls
-- .TryJump (STEP_LEDGE) and GetMovementPermissions' side-wall arms.  Burned
-- Tower B1F's landing pockets drain only through hop-down ledges, and Ice Path
-- 1F's HM07 rest chain only exists because a slide may not glide down onto the
-- COLL_UP_WALL strip -- both were unwalkable while these two mechanics were
-- missing.  Wrapped for the 200-local ceiling like the blocks above.
local function ledgeOneWayChecks()
  local Player = require("src.world.gen2.Player")
  local COLL_WALL, COLL_HOP_DOWN, COLL_HOP_RIGHT = 0x07, 0xa3, 0xa0
  local COLL_UP_WALL = 0xb2

  local function press(world, dir, budget)
    world.heldDir = dir
    for _ = 1, 2 do world:step() end
    world.heldDir = nil
    local frames = 0
    while frames < (budget or 60) do
      world:step()
      frames = frames + 1
      if not world.player.moving and not world.turningDirection then break end
    end
  end

  -- Standing on a HOP_DOWN ledge with the tile past it blocked: the refused
  -- step becomes a two-cell jump.
  local hopCells = {
    [5 * 100 + 4] = COLL_HOP_DOWN,   -- player stands here
    [6 * 100 + 4] = COLL_WALL,       -- the refused single step
    -- (4,7) floor: the landing
  }
  local hop = fakeWorld(hopCells, Player.new(4, 5, "down"))
  hop.player.turnArmed = false
  hop.entities = { hop.player }
  press(hop, "down")
  eq(hop.player.cellY, 7, "a refused step off a HOP_DOWN ledge jumps two cells")
  eq(hop.player.cellX, 4, "straight down")

  -- The ledge only fires for its own facings: HOP_DOWN does nothing for a
  -- rightward bump.
  local wrongWay = fakeWorld({
    [5 * 100 + 4] = COLL_HOP_DOWN,
    [5 * 100 + 5] = COLL_WALL,
  }, Player.new(4, 5, "right"))
  wrongWay.player.turnArmed = false
  wrongWay.entities = { wrongWay.player }
  press(wrongWay, "right")
  eq(wrongWay.player.cellX, 4, "HOP_DOWN does not jump a rightward bump")

  -- HOP_RIGHT jumps rightward bumps (Gold's $a0 is HOP_RIGHT, not Crystal's
  -- HOP_DOWN -- the direction table is the part a wrong port would swap).
  local hopRight = fakeWorld({
    [5 * 100 + 4] = COLL_HOP_RIGHT,
    [5 * 100 + 5] = COLL_WALL,
  }, Player.new(4, 5, "right"))
  hopRight.player.turnArmed = false
  hopRight.entities = { hopRight.player }
  press(hopRight, "right")
  eq(hopRight.player.cellX, 6, "$a0 hops rightward")

  -- An occupied landing refuses the jump rather than stacking sprites.
  local npc = Player.new(4, 7, "up")
  local blockedLanding = fakeWorld({
    [5 * 100 + 4] = COLL_HOP_DOWN,
    [6 * 100 + 4] = COLL_WALL,
  }, Player.new(4, 5, "down"))
  blockedLanding.player.turnArmed = false
  blockedLanding.entities = { blockedLanding.player, npc }
  press(blockedLanding, "down")
  eq(blockedLanding.player.cellY, 5, "no jump onto an occupied landing")

  -- COLL_UP_WALL: Gold's neighbour arm blocks stepping DOWN onto it...
  local noEntry = fakeWorld({
    [6 * 100 + 4] = COLL_UP_WALL,
  }, Player.new(4, 5, "down"))
  noEntry.player.turnArmed = false
  noEntry.entities = { noEntry.player }
  press(noEntry, "down")
  eq(noEntry.player.cellY, 5, "no stepping down onto an UP_WALL")

  -- ...standing on it blocks UP...
  local noLeave = fakeWorld({
    [5 * 100 + 4] = COLL_UP_WALL,
  }, Player.new(4, 5, "up"))
  noLeave.player.turnArmed = false
  noLeave.entities = { noLeave.player }
  press(noLeave, "up")
  eq(noLeave.player.cellY, 5, "standing on an UP_WALL blocks moving up")

  -- ...and sideways ON the strip stays legal.
  local alongside = fakeWorld({
    [5 * 100 + 4] = COLL_UP_WALL,
    [5 * 100 + 5] = COLL_UP_WALL,
  }, Player.new(4, 5, "right"))
  alongside.player.turnArmed = false
  alongside.entities = { alongside.player }
  press(alongside, "right")
  eq(alongside.player.cellX, 5, "walking along the strip is an ordinary step")

  -- An ice slide rests on the last ice cell above an UP_WALL strip instead of
  -- gliding onto it -- the rest position Ice Path 1F's HM07 chain is built on.
  local slideCells = {
    [5 * 100 + 3] = COLL_ICE,
    [6 * 100 + 3] = COLL_ICE,
    [7 * 100 + 3] = COLL_ICE,
    [8 * 100 + 3] = COLL_UP_WALL,
  }
  local slide = fakeWorld(slideCells, Player.new(3, 4, "down"))
  slide.player.turnArmed = false
  slide.entities = { slide.player }
  press(slide, "down", 200)
  eq(slide.player.cellY, 7, "the slide rests above the UP_WALL strip")
end
ledgeOneWayChecks()

-- ---- the IN_GRASS latch and the tileset anim clock ------------------------
-- UpdateTallGrassFlags only RE-tests while IN_GRASS is already set (engine/
-- overworld/map_objects.asm:226), so a step INTO grass stays clear until
-- SetTallGrassFlags runs at the far end of it (:247); a step OUT of grass
-- clears on the frame it starts.
local function grassLatchChecks()
  local COLL_GRASS = 0x18
  local PlayerMod = require("src.world.gen2.Player")

  local into = fakeWorld({ [6 * 100 + 5] = COLL_GRASS },
    PlayerMod.new(5, 5, "down"), PARTY_ONE)
  into.entities = { into.player }
  into.noWildEncounters = true
  local ip = into.player
  ip.turnArmed = false
  check(not ip.inGrass, "standing on a path is not IN_GRASS")
  eq(into:movePlayer("down"), "moved", "the step into grass is taken")
  check(not ip.inGrass, "UpdateTallGrassFlags does not set it mid-step")
  check(ip.grassShake, "NormalStep still spawns the rustle on that step")
  for _ = 1, PlayerMod.STEP_FRAMES + 1 do into:step() end
  check(not ip.moving, "the step lands")
  check(ip.inGrass, "SetTallGrassFlags sets it once the step has landed")

  local outOf = fakeWorld({ [5 * 100 + 5] = COLL_GRASS },
    PlayerMod.new(5, 5, "down"), PARTY_ONE)
  outOf.entities = { outOf.player }
  outOf.noWildEncounters = true
  local op = outOf.player
  op.turnArmed = false
  op.inGrass = true
  eq(outOf:movePlayer("down"), "moved", "the step out of grass is taken")
  check(not op.inGrass, "the latch clears on the first frame of that step")
  check(not op.grassShake, "and nothing rustles on a path")

  -- StepFunction_Reset -> SetTallGrassFlags (map_objects.asm:498-511): National
  -- Park's four spinning trainers are IN_GRASS at load (maps/NationalPark.asm:503-506).
  local parked = { kind = "stand", cellX = 5, cellY = 5, inGrass = false }
  NPC.update(parked, outOf.map)
  check(parked.inGrass, "an object spawned in grass is IN_GRASS before it steps")

  -- applymovement's step_* is the same NormalStep as a walk (movement.asm:
  -- 434-481), so a scripted step rustles the grass it steps into.
  local scripted = fakeWorld({ [6 * 100 + 5] = COLL_GRASS },
    PlayerMod.new(5, 5, "down"), PARTY_ONE)
  scripted.entities = { scripted.player }
  scripted.noWildEncounters = true
  scripted.player.turnArmed = false
  check(scripted.player:scriptStep("down"), "the scripted step starts")
  scripted:step()
  check(scripted.player.grassShake, "a scripted step spawns the rustle too")

  -- JumpStep res IN_GRASS_F and calls neither UpdateTallGrassFlags nor
  -- ShakeGrass (movement.asm:741-770); the landing re-latches at the far end.
  local hopGrass = fakeWorld({
    [5 * 100 + 5] = 0xa3,       -- COLL_HOP_DOWN, the cell hopped FROM
    [6 * 100 + 5] = 0x07,       -- COLL_WALL, the refused single step
    [7 * 100 + 5] = COLL_GRASS, -- the landing
  }, PlayerMod.new(5, 5, "down"), PARTY_ONE)
  hopGrass.entities = { hopGrass.player }
  hopGrass.noWildEncounters = true
  local hp = hopGrass.player
  hp.turnArmed = false
  eq(hopGrass:movePlayer("down"), "moved", "the refused step becomes the hop")
  check(hp.jumping, "and it is a jump")
  check(not hp.grassShake, "no rustle spawns for the airborne cells")
  check(not hp.inGrass, "and IN_GRASS is clear for the whole hop")
  -- A hop clears two cells, so it runs two step-times, not one (#1165).
  for _ = 1, PlayerMod.STEP_FRAMES * 2 + 1 do hopGrass:step() end
  check(hp.inGrass, "the landing tile latches it once the hop ends")
end
grassLatchChecks()

local function tileAnimChecks()
  -- AnimateWaterTile's `wTileAnimationTimer and %110` (engine/tilesets/
  -- tileset_anims.asm:172-174): four frames, each held for two timer ticks.
  local seq = {}
  for timer = 0, 7 do seq[#seq + 1] = World.waterFrameFor(timer) end
  eq(table.concat(seq, ","), "1,1,2,2,3,3,4,4",
    "the water strip cycles a frame every two ticks")
  eq(World.waterFrameFor(8), World.waterFrameFor(0),
    "StandingTileFrame8 wraps the timer at 8")

  -- _AnimateTileset runs one row per frame and DoneTileAnimation wraps the
  -- index (tileset_anims.asm:11, :48), so a pass costs `period` frames.
  local world = fakeWorld({}, fakePlayer(5, 5, "down"))
  world.tilesets = { TILESET_JOHTO = { anim = { period = 11 } } }
  for _ = 1, 11 * 2 do world:pollTileAnim() end
  eq(world.animTimer, 2, "two passes of an 11-row program tick the timer twice")
  eq(world.animClock, 0, "and the frame counter is back at the top")
end
tileAnimChecks()

S.finish()
