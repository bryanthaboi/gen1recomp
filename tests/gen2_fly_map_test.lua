-- FLY's destination picker (pokegold engine/pokegear/pokegear.asm _FlyMap).
--
-- _FlyMap is the town map on its OWN screen: the same LoadTownMapGFX art the
-- POKeGEAR's MAP card draws, with TownMapBubble's "Where?" plate instead of the
-- card strip and no ENGINE_MAP_CARD gate at all.  The cursor walks the
-- Flypoints table between wStartFlypoint and wEndFlypoint, skipping every row
-- CheckIfVisitedFlypoint rejects; A takes the row under it and B answers -1.
--   luajit tests/gen2_fly_map_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 fly map")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local FieldMoves = require("src.world.gen2.FieldMoves")
local Pokegear = require("src.ui.gen2.Pokegear")
require("tests.fixtures.gen2_flypoints").bind("gold")

local function fakeInput()
  local pressed = {}
  return {
    press = function(_self, button) pressed[button] = true end,
    wasPressed = function(_self, button)
      if pressed[button] then
        pressed[button] = nil
        return true
      end
      return false
    end,
  }
end

-- landmarks.lua's shape, for the rows the picker names and parks on.
-- KANTO_LANDMARK is $2e = 46, and Pokegear:region reads the PLAYER's landmark
-- index against it, so the Kanto rows have to sit above it here too.
local LANDMARKS = { landmarks = {}, order = {} }
for i, row in ipairs(FieldMoves.FLYPOINTS) do
  local index = i < FieldMoves.KANTO_FLYPOINT and i
    or (46 + i - FieldMoves.KANTO_FLYPOINT)
  LANDMARKS.landmarks[row.landmark] = {
    index = index, name = row.landmark:gsub("^LANDMARK_", ""), x = 8, y = 8,
  }
  LANDMARKS.order[index] = row.landmark
end
LANDMARKS.landmarks.LANDMARK_ROUTE_27 = {
  index = 0x5b, name = "ROUTE 27", x = 40, y = 64,
}
LANDMARKS.order[0x5b] = "LANDMARK_ROUTE_27"

local function visited(...)
  local save = { engineFlags = {} }
  for _, spawn in ipairs({ ... }) do
    for _, row in ipairs(FieldMoves.FLYPOINTS) do
      if row.spawn == spawn then save.engineFlags[row.flag] = true end
    end
  end
  return save
end

-- The gate World:openFlyMap reads before it pushes this screen instead of
-- falling back to its yes/no chain.
check(Pokegear.FLY_MAP == true, "Pokegear now declares a fly mode")

local function flyScreen(save, opts)
  opts = opts or {}
  local input = fakeInput()
  local points, shown =
    FieldMoves.flyPoints(save, LANDMARKS, opts.region or "johto")
  local chosen, closed
  local screen = Pokegear.new({ input = input, save = save }, {
    save = save,
    landmarks = LANDMARKS,
    currentLandmark = opts.currentLandmark,
    fly = points,
    flyRegion = opts.passRegion and shown or nil,
    onFly = function(spawn) chosen = spawn end,
    onClose = function() closed = true end,
  })
  return screen, input, points,
    function() return chosen end, function() return closed end
end

-- ---------------------------------------------------------------- the screen
do
  local save = visited("SPAWN_NEW_BARK", "SPAWN_VIOLET", "SPAWN_GOLDENROD")
  local screen, input, points, chosen, closed = flyScreen(save)
  eq(#points, 3, "only the visited flypoints are offered")
  eq(#screen.cards, 1, "the picker is one screen, not the card strip")
  eq(screen.mode, "card", "and it opens straight onto the map")
  -- FlyMap's Johto default is JOHTO_FLYPOINT, the first row (New Bark Town).
  eq(screen.flyIndex, 1, "the Johto map opens on the first flypoint")
  eq(screen:flyRow().spawn, "SPAWN_NEW_BARK", "which is New Bark Town")
  -- The MAP card's cursor follows the flypoint, so the name plate and the
  -- arrow both land on the row rather than on a free landmark.
  eq(screen:mapCursorIndex(), LANDMARKS.landmarks.LANDMARK_NEW_BARK_TOWN.index,
    "and the map cursor sits on it")

  input:press("up")
  screen:update(0)
  eq(screen:flyRow().spawn, "SPAWN_VIOLET", ".ScrollNext takes the next row")
  eq(screen:mapCursorIndex(), LANDMARKS.landmarks.LANDMARK_VIOLET_CITY.index,
    "and the cursor moves with it")
  input:press("up")
  screen:update(0)
  input:press("up")
  screen:update(0)
  eq(screen:flyRow().spawn, "SPAWN_NEW_BARK", "and it wraps at wEndFlypoint")
  input:press("down")
  screen:update(0)
  eq(screen:flyRow().spawn, "SPAWN_GOLDENROD",
    ".ScrollPrev wraps the other way at wStartFlypoint")

  -- Left and right do nothing: there is no card to page to on this screen.
  input:press("right")
  screen:update(0)
  eq(screen:flyRow().spawn, "SPAWN_GOLDENROD", "right does not page the gear")
  input:press("left")
  screen:update(0)
  eq(screen:flyRow().spawn, "SPAWN_GOLDENROD", "and neither does left")
  eq(#screen.cards, 1, "the strip is still one row")

  input:press("a")
  screen:update(0)
  eq(chosen(), "SPAWN_GOLDENROD", "A takes the flypoint under the cursor")
  check(not closed(), "and does not also close the screen")
end

do
  -- `ld a, -1`: B answers "no flypoint" and the caller drops it.
  local save = visited("SPAWN_NEW_BARK")
  local screen, input, _points, chosen, closed = flyScreen(save)
  input:press("b")
  screen:update(0)
  check(closed(), "B leaves the picker")
  eq(chosen(), nil, "with nothing chosen")
end

do
  -- .KantoFlyMap opens on the LAST row (Indigo Plateau), and the Kanto half is
  -- withheld entirely until Indigo is visited.
  local save = visited("SPAWN_NEW_BARK", "SPAWN_PALLET", "SPAWN_INDIGO")
  local screen = flyScreen(save, {
    region = "kanto", currentLandmark = "LANDMARK_PALLET_TOWN",
  })
  eq(screen.flyIndex, #screen.fly, "the Kanto map opens on the last flypoint")
  eq(screen:flyRow().spawn, "SPAWN_INDIGO", "which is Indigo Plateau")
end

do
  local save = visited("SPAWN_NEW_BARK", "SPAWN_PALLET")
  local points = FieldMoves.flyPoints(save, LANDMARKS, "kanto")
  eq(#points, 1, "with no Indigo the Kanto half is withheld")
  eq(points[1].spawn, "SPAWN_NEW_BARK", "and the Johto map is shown instead")
end

local JOHTO_ART, KANTO_ART = { "johto art" }, { "kanto art" }
local function drawProbe(screen)
  local probe = { icons = 0 }
  screen.gfx = { maps = { johto = JOHTO_ART, kanto = KANTO_ART } }
  screen.drawTilemap = function(_self, map) probe.tilemap = map end
  screen.drawPlayerIcon = function()
    probe.icons = probe.icons + 1
    return true
  end
  local ok, err = pcall(function() screen:drawMap() end)
  probe.ok, probe.err = ok, err
  return probe
end

-- engine/pokegear/pokegear.asm:2237
for _, passRegion in ipairs({ true, false }) do
  local how = passRegion and " (World's region)" or " (screen's own gate)"
  do
    local save = visited("SPAWN_NEW_BARK", "SPAWN_VIOLET", "SPAWN_MAHOGANY")
    local screen, _input, points = flyScreen(save, {
      region = "kanto", currentLandmark = "LANDMARK_ROUTE_27",
      passRegion = passRegion,
    })
    eq(#points, 3, "Route 27 before Indigo offers the Johto rows" .. how)
    eq(screen:region(), "kanto", "the player still stands in Kanto" .. how)
    eq(screen.flyRegion, "johto", ".NoKanto picks the Johto map" .. how)
    eq(screen.flyIndex, 1, "and defaults to JOHTO_FLYPOINT" .. how)
    eq(screen:flyRow().spawn, "SPAWN_NEW_BARK", "which is New Bark Town" .. how)
    local probe = drawProbe(screen)
    check(probe.ok, "the pre-Indigo picker draws" .. how
      .. " (" .. tostring(probe.err) .. ")")
    check(probe.tilemap == JOHTO_ART, "FillJohtoMap, not the Kanto art" .. how)
    eq(probe.icons, 0, ".NoKanto skips TownMapPlayerIcon" .. how)
  end
  do
    local save = visited("SPAWN_NEW_BARK", "SPAWN_PALLET", "SPAWN_INDIGO")
    local screen = flyScreen(save, {
      region = "kanto", currentLandmark = "LANDMARK_ROUTE_27",
      passRegion = passRegion,
    })
    eq(screen.flyRegion, "kanto", "with Indigo the Kanto map is used" .. how)
    eq(screen:flyRow().spawn, "SPAWN_INDIGO", "opening on Indigo Plateau" .. how)
    local probe = drawProbe(screen)
    check(probe.ok, "the Kanto picker draws" .. how
      .. " (" .. tostring(probe.err) .. ")")
    check(probe.tilemap == KANTO_ART, "FillKantoMap" .. how)
    eq(probe.icons, 1, "and TownMapPlayerIcon" .. how)
  end
  do
    local save = visited("SPAWN_NEW_BARK", "SPAWN_VIOLET")
    local screen = flyScreen(save, {
      currentLandmark = "LANDMARK_VIOLET_CITY", passRegion = passRegion,
    })
    eq(screen.flyRegion, "johto", "the Johto picker stays Johto" .. how)
    local probe = drawProbe(screen)
    check(probe.tilemap == JOHTO_ART, "on the Johto art" .. how)
    eq(probe.icons, 1, "with the player icon drawn" .. how)
  end
end

-- Drawing must not throw: the plain path (no town-map art in the cache) is
-- what a headless run and an older cache take.
do
  local save = visited("SPAWN_NEW_BARK", "SPAWN_VIOLET")
  local screen = flyScreen(save)
  local ok, err = pcall(function() screen:drawPanel() end)
  check(ok, "the unstyled fly picker draws (" .. tostring(err) .. ")")
end

-- IsInJohto (home/region.asm:10, :23)
do
  local World = require("src.world.gen2.World")

  local function landmarkTable(indices)
    local out = { landmarks = {}, order = {} }
    for id, index in pairs(indices) do
      out.landmarks[id] = { index = index, name = id, x = 8, y = 8 }
      out.order[index + 1] = id
    end
    return out
  end

  local GOLD = landmarkTable({
    LANDMARK_NEW_BARK_TOWN = 0x01,
    LANDMARK_SILVER_CAVE = 0x2d,
    LANDMARK_PALLET_TOWN = 0x2e,
    LANDMARK_ROUTE_28 = 0x5d,
    LANDMARK_FAST_SHIP = 0x5e,
  })
  local CRYSTAL = landmarkTable({
    LANDMARK_NEW_BARK_TOWN = 0x01,
    LANDMARK_BATTLE_TOWER = 0x1d,
    LANDMARK_SILVER_CAVE = 0x2e,
    LANDMARK_PALLET_TOWN = 0x2f,
    LANDMARK_ROUTE_28 = 0x5e,
    LANDMARK_FAST_SHIP = 0x5f,
  })

  local function regionAt(landmarks, id)
    return World.region(setmetatable({
      landmarks = landmarks, map = { def = { landmark = id } },
    }, World))
  end

  eq(regionAt(CRYSTAL, "LANDMARK_SILVER_CAVE"), "johto",
    "Crystal's $2e is SILVER CAVE, so Mt. Silver flies to Johto")
  eq(regionAt(CRYSTAL, "LANDMARK_PALLET_TOWN"), "kanto",
    "and its $2f is PALLET TOWN, so Kanto")
  eq(regionAt(CRYSTAL, "LANDMARK_FAST_SHIP"), "johto",
    "the S.S. Aqua is Johto at $5f")
  eq(regionAt(CRYSTAL, "LANDMARK_ROUTE_28"), "kanto",
    "and $5e is ROUTE 28, which is Kanto")

  eq(regionAt(GOLD, "LANDMARK_SILVER_CAVE"), "johto", "Gold's $2d is Johto")
  eq(regionAt(GOLD, "LANDMARK_PALLET_TOWN"), "kanto",
    "Gold's PALLET TOWN is Kanto at $2e")
  eq(regionAt(GOLD, "LANDMARK_FAST_SHIP"), "johto",
    "and its S.S. Aqua is Johto at $5e")

  eq(World.region(setmetatable({ map = { def = { landmark = 0x2e } } }, World)),
    "kanto", "with no landmark table the Gold constants stand in")
end

-- (engine/pokemon/mon_menu.asm:609-626, engine/events/overworld.asm:556-568).
-- the list, and the exit is ExitAllMenus' white (home/map.asm:2281).
do
  local World = require("src.world.gen2.World")
  local PartyMenu = require("src.ui.gen2.PartyMenu")

  local function fakeStack()
    local stack = { states = {}, low = math.huge }
    function stack:push(state)
      self.states[#self.states + 1] = state
      self.low = math.min(self.low, #self.states)
    end
    function stack:pop()
      local state = table.remove(self.states)
      self.low = math.min(self.low, #self.states)
      return state
    end
    function stack:top() return self.states[#self.states] end
    function stack:clear()
      self.states = {}
      self.low = math.min(self.low, 0)
    end
    return stack
  end

  local function flyFromParty()
    local save = visited("SPAWN_NEW_BARK", "SPAWN_VIOLET", "SPAWN_GOLDENROD")
    save.player = { badges = { STORM = true } }
    local stack = fakeStack()
    local game = { save = save, stack = stack, input = fakeInput() }
    local mon = { species = 17, nickname = "PIDGEOTTO" }
    local world = setmetatable({
      game = game,
      landmarks = LANDMARKS,
      map = { def = { landmark = "LANDMARK_NEW_BARK_TOWN" } },
    }, World)
    game.world = world
    local flown
    world.flyTo = function(_self, spawnId, who)
      flown = { spawn = spawnId, mon = who }
      return true
    end
    world.useFieldMove = function(_self, moveId, who)
      local result = FieldMoves.fromMenu(moveId,
        { save = save, environment = "TOWN", mon = who })
      result.mon = result.mon or who
      if result.ok then _self.queuedFieldMove = result end
      return result
    end
    local party = setmetatable({ game = game }, PartyMenu)
    stack:push(party)
    party:useFieldMove("FLY", mon)
    return world, party, stack, mon, function() return flown end, game
  end

  do
    local world, party, stack = flyFromParty()
    eq(#stack.states, 2, "FLY opens a screen OVER the party list")
    eq(stack.states[1], party, "which is still underneath")
    eq(stack:top().screenId, "Gen2BlankScreen",
      "_FlyMap's ClearBGPalettes blanks first")
    eq(world.queuedFieldMove, nil, "and nothing is queued for the overworld yet")

    local blank = stack:top()
    eq(blank.left, 28,
      "_FlyMap: ClearBGPalettes 4 + ClearTilemap 4 + LoadTownMapGFX 7 + border 1"
        .. " + TownMapBGUpdate 7 + TownMapMon 3 + TownMapPlayerIcon 2 = 28 white")
    for _ = 1, 27 do blank:update(0) end
    eq(stack:top(), blank, "the blank is still up on its 28th drawn frame")
    blank:update(0)
    eq(stack:top().screenId, "Gen2Pokegear",
      "the 28th update hands over: the town map is frame 29")
    eq(#stack.states, 2, "still over the list")
    eq(stack.low, 1, "and the stack never emptied on the way in")
  end

  do
    local world, party, stack, mon, _flown, game = flyFromParty()
    game.save.party = { mon, mon }
    local blank = stack:top()
    for _ = 1, blank.left do blank:update(0) end
    local gear = stack:top()
    game.input:press("b")
    gear:update(0)
    local cancelBlank = stack:top()
    eq(cancelBlank and cancelBlank.screenId, "Gen2BlankScreen",
      "B on the fly map: .exit's ClearBGPalettes whites out first")
    eq(cancelBlank.left, 21 + 3 * 2,
      "held for .exit 4 + .illegal 8 + .choosemenu 4 + 3 per party icon + 5")
    eq(#stack.states, 2, "over the party list")
    eq(stack.states[1], party, "which is still underneath")
    for _ = 1, cancelBlank.left do cancelBlank:update(0) end
    eq(stack:top(), party, "then the party list is back")
    eq(#stack.states, 1, "with nothing else left standing")
    eq(world.queuedFieldMove, nil, "and no fly queued behind it")
    eq(world.fade, nil, "nothing fades out for a cancel")
  end

  do
    local world, _party, stack, mon, flown, game = flyFromParty()
    local blank = stack:top()
    for _ = 1, blank.left do blank:update(0) end
    local gear = stack:top()
    gear.flyIndex = 1
    game.input:press("a")
    gear:update(0)
    eq(#stack.states, 0, "A takes the spawn and exits the menus")
    eq(world.queuedFieldMove and world.queuedFieldMove.flySpawn, "SPAWN_NEW_BARK",
      "with the chosen spawn on the queued script")
    eq(world.fade, "white", "ExitAllMenus' ClearBGPalettes is already up")
    eq(world.fadeLevel, 1, "at full white")
    eq(world.mapSetup and world.mapSetup.phase, "in",
      "and FadeInFromWhite is armed behind it")
    eq(world.mapSetup.wait, 31,
      ".exit 4 + CloseWindow 4 + ExitAllMenus 4 + LCD-off reload 9"
        .. " + WaitBGMap2 8 + fade entry 6 for 2 = 31 white")
    for _ = 1, 30 do world:updateMapSetup() end
    eq(world.fadeLevel, 1, "still full white after 30 updates")
    world:updateMapSetup()
    eq(world.fadeLevel, 0.75, "the 31st update starts the ramp")
    for _ = 1, 2 do world:updateMapSetup() end
    eq(world.fadeLevel, 0.5, "two frames a level")
    for _ = 1, 2 do world:updateMapSetup() end
    eq(world.fadeLevel, 0.25, "...and the third level")
    for _ = 1, 2 do world:updateMapSetup() end
    eq(world.fade, nil, "three levels at two frames each, then clear")
    eq(world.mapSetup, nil, "and the setup chain is done")

    world.mapSetup = nil
    local queued = world.queuedFieldMove
    world.queuedFieldMove = nil
    world:runFieldMove(queued)
    eq(flown() and flown().spawn, "SPAWN_NEW_BARK",
      "the queued fly takes the spawn the picker chose")
    eq(flown().mon, mon, "on the mon the list picked")
  end

  do
    -- engine/events/overworld.asm:568
    local world, _party, _stack, mon, _flown, game = flyFromParty()
    game.stack = nil
    local asked = false
    world.showText = function() asked = true end
    eq(world:openFlyMap(mon, { onChosen = function() end }), false,
      "a picker with no screen refuses the menu-side open")
    eq(asked, false, "and does not ask from under the list")
    check(world:openFlyMap(mon) == true, "while the queued path still asks")
    eq(asked, true, "through the same yesorno box")
  end

  do
    local save = visited("SPAWN_NEW_BARK", "SPAWN_VIOLET", "SPAWN_MAHOGANY")
    local stack = fakeStack()
    local game = { save = save, stack = stack, input = fakeInput() }
    local world = setmetatable({
      game = game,
      landmarks = LANDMARKS,
      map = { def = { landmark = "LANDMARK_ROUTE_27" } },
    }, World)
    game.world = world
    check(world:openFlyMap({ species = 17 }) == true,
      "FLY from Route 27 before Indigo opens the picker")
    local gear = stack:top()
    eq(gear and gear.screenId, "Gen2Pokegear", "straight onto the fly map")
    eq(gear.flyRegion, "johto", "World hands over the .NoKanto Johto map")
    eq(gear:flyRow().spawn, "SPAWN_NEW_BARK", "on New Bark Town")
  end
end

S.finish()
