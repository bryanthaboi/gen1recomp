-- Driver: regression coverage for #196 "Dig not working exactly as intended".
--
-- Report (v0.1.23): using DIG, the character appears SPINNING INSIDE the
-- Pokemon Center in front of the nurse, and there is no spin-before-fade on
-- departure.  Expected (reporter + triage cluster E + the file's own code
-- comments): the sprite begins to spin, the screen fades, and the player
-- fades in OUTSIDE the nearest town's Pokemon Center door -- exactly like Fly.
--
-- Gen1/pokered references this exercises:
--   engine/overworld/player_animations.asm _LeaveMapAnim (SFX_TELEPORT_EXIT_1
--     + PlayerSpinWhileMovingUp) for the departure spin-up;
--   EnterMapAnim (PlayerSpinWhileMovingDown) for the arrival spin-down;
--   engine/items/item_effects.asm ItemUseEscapeRope (Dig/Teleport share it).
--
-- Two defects, two assertions:
--   FIX A: a DEPARTURE spin must appear on the origin (cave) map BEFORE the
--          warp -- ow.teleportOut set / player spinning while still in the cave.
--   FIX B: the landing map must be the town (VIRIDIAN_CITY) at the in-front-of
--          -door fly spot (23,26), NOT the interior VIRIDIAN_POKECENTER.
-- Pre-fix this driver documents the bug (lands in VIRIDIAN_POKECENTER, no
-- departure spin); post-fix it passes.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local failures = {}
  local function check(cond, msg)
    if cond then
      U.log("PASS:", msg)
    else
      U.log("FAIL:", msg)
      table.insert(failures, msg)
    end
  end

  -- ---- set up a heal record with a remembered Viridian town door ----
  -- Simulate having healed at the Viridian Pokemon Center: lastHeal points
  -- at the INTERIOR (the buggy landing), but carries the outdoor town door
  -- so the fix can relocate the escape-warp outside like Fly does.
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "bryan"
  game.save.lastOutdoor = { id = "VIRIDIAN_CITY", x = 23, y = 25 }
  game.save.lastHeal = {
    map = "VIRIDIAN_POKECENTER", x = 3, y = 3,
    outdoor = { id = "VIRIDIAN_CITY", x = 23, y = 25 },
  }
  -- field.flyWarps.VIRIDIAN_CITY = {23,26} is the canonical in-front-of-door
  -- fly landing (one tile south of the PC door warp at 23,25).
  local fw = game.data.field.flyWarps.VIRIDIAN_CITY
  U.log("viridian flyWarp:", tostring(fw and fw.x), tostring(fw and fw.y))

  -- ======================= LEG 1: DIG via the party menu ==============
  -- A DIG-knowing party mon.  Pokemon.movesAtLevel never grants DIG, so
  -- inject the move directly (DIG needs no badge and works in CAVERN maps).
  local digger = Pokemon.new(game.data, "NIDOKING", 40)
  digger.moves = { { id = "DIG", pp = 10 } }
  game.save.party = { digger }

  -- MT_MOON_1F tileset is CAVERN (in DIG_TILESETS); a walkable cave cell.
  U.teleport(game, "MT_MOON_1F", 14, 34, "down")
  local ow = game.overworld
  U.log("start map:", tostring(ow and ow.map and ow.map.id),
        "tileset:", tostring(ow and ow.map and ow.map.def and ow.map.def.tileset))
  U.shot(game, DIR .. "/dig_00_cave.png")
  U.wait(4)

  -- open the party menu and pick DIG on slot 1
  -- (submenu order for a DIG-only mon: DIG / STATS / SWITCH -- #768)
  Screens.push(game, "PartyMenu")
  U.wait(5)
  U.tap(game, "a")    -- open the per-mon submenu, cursor on DIG
  U.wait(2)
  U.tap(game, "a")    -- choose DIG
  U.wait(2)

  -- ---- FIX A: watch for a DEPARTURE spin on the cave map before the warp ----
  -- A departure spin counts only if it happens while we are still in the cave
  -- (map.id == MT_MOON_1F). The pre-fix code only spins on arrival, inside the
  -- Center, so this stays false pre-fix.
  local sawDepartureSpin = false
  local spinShotTaken = false
  local leftCave = false
  local facingRuns, lastFacing, lastTick, maxTick = {}, nil, -1, 0
  local function sampleSpin()
    if not ow.player.spinning then return end
    local tick = ow.player.spinTimer or 0
    if tick == lastTick then return end
    lastTick = tick
    if tick > maxTick then maxTick = tick end
    local _, _, _, facing = ow.player:pose()
    if facing ~= lastFacing then
      lastFacing = facing
      facingRuns[#facingRuns + 1] = 1
    else
      facingRuns[#facingRuns] = facingRuns[#facingRuns] + 1
    end
  end
  for _ = 1, 400 do
    local stillCave = ow.map and ow.map.id == "MT_MOON_1F"
    if stillCave then sampleSpin() end
    -- departure-only markers: ow.teleportOut is the new pre-warp spin state,
    -- and player.spinRise is the rising spin (the arrival uses spinDrop), so
    -- neither can be confused with the interior arrival spin-down
    if stillCave and (ow.teleportOut ~= nil or ow.player.spinRise) then
      sawDepartureSpin = true
      if not spinShotTaken then
        U.shot(game, DIR .. "/dig_01_spin.png")
        spinShotTaken = true
      end
    end
    if ow.map and ow.map.id ~= "MT_MOON_1F" then
      leftCave = true
      break
    end
    U.wait(1)
  end
  U.log("sawDepartureSpin:", tostring(sawDepartureSpin),
        "leftCave:", tostring(leftCave))

  -- ---- settle the arrival, then FIX B: where did we land? ----
  local landedMap
  for _ = 1, 240 do
    landedMap = ow.map and ow.map.id
    -- wait until the transition settles onto a stable map that isn't the cave
    if landedMap and landedMap ~= "MT_MOON_1F" and not ow.transitioning then
      break
    end
    U.wait(1)
  end
  U.wait(8)
  U.shot(game, DIR .. "/dig_02_land.png")
  U.wait(4)
  landedMap = ow.map and ow.map.id
  U.log("DIG landed map:", tostring(landedMap),
        "cell:", tostring(ow.player.cellX), tostring(ow.player.cellY))

  check(sawDepartureSpin,
    "DIG: departure spin appears in the cave before the fade (FIX A)")

  do
    local runs = {}
    for i, n in ipairs(facingRuns) do runs[i] = n end
    U.log("departure fixed steps:", tostring(maxTick),
          "facing runs:", table.concat(runs, ","))
    check(maxTick >= 130,
      "DIG: the departure spin runs the cart's 135 fixed steps -- got "
      .. tostring(maxTick))
    check((runs[2] or 0) >= 12,
      "DIG: the spin starts slow (>=12 frames a facing) -- got "
      .. tostring(runs[2]))
    local monotonic, prev = true, math.huge
    for i = 2, math.min(#runs, 15) do
      if runs[i] > prev then monotonic = false end
      prev = runs[i]
    end
    check(monotonic,
      "DIG: PlayerSpinInPlace accelerates (run lengths never grow)")
    local sawRise = false
    for i = 12, #runs do if runs[i] == 3 then sawRise = true end end
    check(sawRise,
      "DIG: the rise runs at PlayerSpinWhileMovingUp's 3 frames a step")
  end
  check(landedMap == "VIRIDIAN_CITY",
    "DIG: lands OUTSIDE at VIRIDIAN_CITY, not the interior (FIX B) -- got "
    .. tostring(landedMap))
  check(ow.player.cellX == 23 and ow.player.cellY == 26,
    "DIG: lands at the in-front-of-door fly spot 23,26 -- got "
    .. tostring(ow.player.cellX) .. "," .. tostring(ow.player.cellY))

  -- ======================= LEG 2: ESCAPE ROPE via the bag =============
  -- Same shared departure path, but driven through BagMenu's escape_rope
  -- branch so src/ui/BagMenu.lua is exercised too.
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 8) }
  game.save.bagOrder = nil
  game.save.inventory = { ESCAPE_ROPE = 1 }
  game.save.money = game.save.money or 3000

  U.teleport(game, "MT_MOON_1F", 14, 34, "down")
  ow = game.overworld
  U.shot(game, DIR .. "/dig_03_rope_cave.png")
  U.wait(4)

  Screens.push(game, "BagMenu")
  U.wait(5)
  U.tap(game, "a")    -- choose ESCAPE ROPE (only item) -> USE / TOSS menu
  U.wait(3)
  U.tap(game, "a")    -- USE (first option) -> escape_rope branch
  U.wait(2)

  local ropeSpin = false
  for _ = 1, 400 do
    local stillCave = ow.map and ow.map.id == "MT_MOON_1F"
    if stillCave and (ow.teleportOut ~= nil or ow.player.spinRise) then
      ropeSpin = true
    end
    if ow.map and ow.map.id ~= "MT_MOON_1F" then break end
    U.wait(1)
  end
  local ropeLanded
  for _ = 1, 240 do
    ropeLanded = ow.map and ow.map.id
    if ropeLanded and ropeLanded ~= "MT_MOON_1F" and not ow.transitioning then
      break
    end
    U.wait(1)
  end
  U.wait(8)
  U.shot(game, DIR .. "/dig_04_rope_land.png")
  U.wait(4)
  ropeLanded = ow.map and ow.map.id
  U.log("ESCAPE ROPE landed map:", tostring(ropeLanded),
        "cell:", tostring(ow.player.cellX), tostring(ow.player.cellY))

  check(ropeSpin,
    "ESCAPE ROPE: departure spin appears in the cave before the fade (FIX A)")
  check(ropeLanded == "VIRIDIAN_CITY",
    "ESCAPE ROPE: lands OUTSIDE at VIRIDIAN_CITY (FIX B) -- got "
    .. tostring(ropeLanded))

  if #failures == 0 then
    U.log("RESULT bug196 PASS")
  else
    U.log("RESULT bug196 FAIL (" .. #failures .. "):")
    for _, m in ipairs(failures) do U.log("  -", m) end
  end
end
