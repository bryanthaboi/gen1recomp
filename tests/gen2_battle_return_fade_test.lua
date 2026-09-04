-- engine/tilesets/timeofday_pals.asm:65-91
-- data/maps/setup_scripts.asm:124-139

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle return fade")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")

local function rowEq(row, a, b, c, d, label)
  check(row ~= nil, label .. " (row exists)")
  if not row then return end
  check(row[1] == a and row[2] == b and row[3] == c and row[4] == d,
    label .. " (" .. row[1] .. row[2] .. row[3] .. row[4] .. ")")
end

rowEq(World.fadeRampRow("white", 0.25), 3, 2, 1, 0,
  "the first white step is the identity row")
rowEq(World.fadeRampRow("white", 0.5), 2, 1, 0, 0,
  "the second collapses one gradation")
rowEq(World.fadeRampRow("white", 0.75), 1, 0, 0, 0,
  "the third another")
rowEq(World.fadeRampRow("white", 1), 0, 0, 0, 0,
  "the fourth is solid white")
rowEq(World.fadeRampRow("black", 1), 3, 3, 3, 3,
  "the black ramp ends solid black")
rowEq(World.fadeRampRow("white", 0), 3, 2, 1, 0,
  "a floor of one keeps level 0 on the identity row")
rowEq(World.fadeRampRow("white", 2), 0, 0, 0, 0,
  "and a cap of four keeps an overshoot on white")
eq(World.fadeRampRow("outWhite", 1), nil, "an unknown kind quantizes to nothing")
eq(World.fadeRampRow(nil, 1), nil, "and so does no fade at all")

eq(World.fadeRampByte({ 3, 2, 1, 0 }), 0xe4, "identity packs to $e4")
eq(World.fadeRampByte({ 0, 0, 0, 0 }), 0x00, "white packs to $00")
eq(World.fadeRampByte({ 3, 3, 3, 3 }), 0xff, "black packs to $ff")

local w = {}
World.battleReturnFade(w)
check(w.mapSetup ~= nil, "the battle exit arms a map setup chain")
eq(w.mapSetup.phase, "in", "the chain is the fade-in half only")
eq(w.mapSetup.step, 4, "four steps up")
eq(w.fade, "white", "under a full white sheet")
eq(w.fadeLevel, 1, "at full strength")
check(World.busy(w), "and the world is busy for its whole run")

local armed = { mapSetup = { phase = "out", step = 2, wait = 1 } }
World.battleReturnFade(armed)
eq(armed.mapSetup.phase, "out",
  "a chain already running is left alone")
eq(armed.fade, nil, "and its sheet untouched")

-- home/init.asm:149-153
eq(World.MAP_LOAD_WHITE_FRAMES, 13,
  "a door holds white for the 13 frames measured on the cart (11 LCD-off + 2)")
eq(World.WARP_LOAD_WHITE_FRAMES, 15,
  "a Warp/Teleport/Fly holds 15: LoadBlockData and LoadMapObjects are under the LCD too")
eq(w.fadeHold, World.WARP_LOAD_WHITE_FRAMES,
  "the battle return opens holding pure white for that window")
eq(w.fadeWhiten, nil, "with LoadMapPalettes' plain set already back")

local ticks, white, sheet = 0, 0, 0
while w.mapSetup and ticks < 64 do
  if w.fadeLevel == 1 then white = white + 1 end
  if w.fadeHold then sheet = sheet + 1 end
  World.updateMapSetup(w)
  ticks = ticks + 1
end
eq(sheet, World.WARP_LOAD_WHITE_FRAMES,
  "pure white is the LCD-off window and nothing else")
eq(white, World.WARP_LOAD_WHITE_FRAMES + World.FADE_STEP_FRAMES,
  "the hold plus FadeInFromWhite's own first row, which is a palette row")
eq(ticks, 6 + World.WARP_LOAD_WHITE_FRAMES + World.FADE_STEP_FRAMES,
  "then three more rows of two frames")
eq(w.mapSetup, nil, "then the chain ends")
eq(w.fade, nil, "with nothing left over the world")
eq(w.fadeHold, nil, "and no hold left behind")
check(not World.busy(w), "and control back")

-- data/maps/setup_scripts.asm:102-125
local door = { mapSetup = { phase = "out", step = 0, wait = 2,
  load = function() return true end }, fadeWhiten = true }
local levels, whiteRun, doorSheet, whitenRun = {}, 0, 0, 0
ticks = 0
while door.mapSetup and ticks < 64 do
  if door.fadeLevel == 1 then whiteRun = whiteRun + 1 end
  if door.fadeHold then doorSheet = doorSheet + 1 end
  if door.fadeWhiten then whitenRun = whitenRun + 1 end
  World.updateMapSetup(door)
  ticks = ticks + 1
  levels[#levels + 1] = door.fadeLevel or 0
end
-- engine/tilesets/timeofday_pals.asm:160-187
eq(doorSheet, World.MAP_LOAD_WHITE_FRAMES,
  "a door is pure white for the load alone")
eq(whiteRun, World.FADE_STEP_FRAMES + World.MAP_LOAD_WHITE_FRAMES
  + World.FADE_STEP_FRAMES,
  "the colour-0 plane brackets it: last out row, load, first in row")
eq(whitenRun, (World.FADE_STEPS + 1) * World.FADE_STEP_FRAMES,
  "FillWhiteBGColor holds over the whole way out and no further")
eq(door.fadeWhiten, nil, "the load puts the plain palettes back")
eq(ticks, (World.FADE_STEPS + 1) * World.FADE_STEP_FRAMES
  + World.MAP_LOAD_WHITE_FRAMES + World.FADE_STEPS * World.FADE_STEP_FRAMES,
  "out ramp, hold, in ramp")
eq(levels[World.FADE_STEP_FRAMES], 0.25, "the out ramp opens on the identity row")
eq(levels[#levels], 0, "and the in ramp closes on nothing")

-- data/maps/setup_scripts.asm:27-32
do
  local MAPSETUP_TELEPORT, MAPSETUP_DOOR = 0xf4, 0xf5
  local function armed(method)
    local wm = { roamMonsBeforeLoad = function() end,
      roamMonsAfterLoad = function() end }
    World.runMapSetup(wm, method, function() return true end)
    local hold
    while wm.mapSetup and wm.mapSetup.phase == "out" do
      World.updateMapSetup(wm)
      hold = wm.fadeHold or hold
    end
    return hold
  end
  eq(armed(MAPSETUP_TELEPORT), World.WARP_LOAD_WHITE_FRAMES,
    "a teleport falls into _Fly falls into _Warp, so it holds the Warp window")
  eq(armed(MAPSETUP_DOOR), World.MAP_LOAD_WHITE_FRAMES,
    "a door falls into _Train and keeps the shorter one")
end

-- engine/tilesets/timeofday_pals.asm:122-128
do
  local wf = {}
  World.screenFade(wf, "outWhite")
  eq(wf.fadeLevel, 1, "a bare FadeOutToWhite lands on the solid row")
  eq(wf.fadeHold, nil, "with no LCD-off hold of its own")
  eq(wf.fadeWhiten, true, "and FillWhiteBGColor's pals 1-6 in place")
  World.screenFade(wf, "outBlack")
  eq(wf.fadeWhiten, nil, "FadeOutToBlack does not call FillWhiteBGColor")
end

-- night, never white -- into pals 1 to 6 (timeofday_pals.asm:160-187)
do
  local pal = function(c0)
    return { c0, { 20, 20, 20 }, { 10, 10, 10 }, { 0, 0, 0 } }
  end
  local set = { pal({ 15, 14, 24 }), pal({ 30, 30, 11 }), pal({ 1, 1, 1 }),
    pal({ 2, 2, 2 }), pal({ 3, 3, 3 }), pal({ 4, 4, 4 }), pal({ 5, 5, 5 }),
    pal({ 6, 6, 6 }) }
  local w2 = {
    palettes = { bg = { set[1] }, environments = { TOWN = { DAY = {} } },
      specialTilesets = { TILESET_TEST = set } },
    map = { def = { tileset = "TILESET_TEST", environment = "INDOOR" } },
    daytime = "NITE",
  }
  local plain = World.fadeBgSet(w2)
  eq(plain[2][1][1], 30, "with no whitening the pals are the map's own")
  w2.fadeWhiten = true
  local whitened = World.fadeBgSet(w2)
  eq(whitened[1][1][1], 15, "pal 0 keeps its own colour 0")
  eq(whitened[2][1][1], 15, "and pals 1 to 6 take it")
  eq(whitened[2][1][3], 24, "the night plane, not white")
  eq(whitened[7][1][1], 15, "up to pal 6")
  eq(whitened[8][1][1], 6, "pal 7 is left alone, as the `ld c, 6` loop leaves it")
  eq(whitened[2][2][1], 20, "and colours 1 to 3 are untouched")
end

-- MAPSETUP_WARP` at the end of Script_Whiteout (engine/events/whiteout.asm:19)
local Screens = require("src.ui.Screens")

local DATA = {
  pokemon = {
    RATTATA = { id = "RATTATA", name = "RATTATA", index = 19, baseExp = 57,
      growthRate = "MEDIUM_FAST", stats = { hp = 30, attack = 56,
        defense = 35, speed = 72, specialAttack = 25, specialDefense = 35 },
      types = { "NORMAL" } },
  },
  moves = {},
}

local function battleWorld()
  local captured = {}
  Screens.invalidate()
  local game = {
    data = { pokemon = DATA.pokemon, moves = DATA.moves,
      screens = { Gen2BattleState = function(_, opts)
        captured.opts = opts
        return { screenId = "Gen2BattleState" }
      end } },
    save = { player = { name = "GOLD", money = 3000 },
      mom = { savedMoney = 0 }, party = {} },
    stack = { push = function() end, pop = function() end },
  }
  local world = World.new(game)
  game.world = world
  world.map = { def = { id = "TEST_MAP" } }
  world.maps = { TEST_MAP = world.map.def }
  world.playBattleMusic = function() end
  world.battleMusicContext = function() return nil end
  world.pushBattleTransition = function() return nil end
  world.restoreMapMusic = function() end
  world.forceMapMusic = function() end
  world.healParty = function() end
  world.warpToSpawn = function(self) self.fade, self.fadeHold = nil, nil end
  return world, captured
end

do
  local world, captured = battleWorld()
  world:startBattle({ trainer = { name = "FALKNER", baseMoney = 25,
    party = { { species = "RATTATA", level = 5, hp = 0, maxHp = 20,
      moves = {}, stats = {}, dvs = {}, statExp = {} } } } })
  check(captured.opts ~= nil, "startBattle pushes the battle screen")
  captured.opts.onDone("win")
  eq(world.fade, "white", "a win comes back through MAPSETUP_RELOADMAP")
  eq(world.mapSetup and world.mapSetup.phase, "in", "which is a fade in")
end

do
  local world, captured = battleWorld()
  world:startBattle({ trainer = { name = "FALKNER", baseMoney = 25,
    party = { { species = "RATTATA", level = 5, hp = 0, maxHp = 20,
      moves = {}, stats = {}, dvs = {}, statExp = {} } } } })
  captured.opts.onDone("lose")
  eq(world.fade, "white",
    "a loss fades in from the whiteout's own warp, not from the reload")
  eq(world.mapSetup and world.mapSetup.phase, "in",
    "armed AFTER the warp loaded, so the load cannot clear it")
  eq(world.fadeHold, World.WARP_LOAD_WHITE_FRAMES,
    "with the LCD-off window held first")
end

S.finish()
