-- #1708: Gold's fishing pose and rod.  The cast is reached the way a player
-- reaches it -- walk to the shore, START, PACK, KEY ITEMS, OLD ROD, USE -- once
-- per facing, and the pose row and rod tile are sampled out of the real draw.
-- FacingFishDown/Up/Left/Right ../pokegold/data/sprites/facings.asm:122-152;
-- LoadFishingGFX ../pokegold/engine/events/fishing_gfx.asm:1-24.
-- No POKEPORT_SPEED: it scales the logic clock only, so the sampled frames and
-- the rendered ones drift apart and the rod is read off the wrong frame.
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_fishing_rod_bug1708_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-fishing \
--     perl -e 'alarm 420; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
local U = require("tests.drivers.util")

local Assets = require("src.render.Assets")
local Map = require("src.world.gen2.Map")
local PackMenu = require("src.ui.gen2.PackMenu")
local Permissions = require("src.world.gen2.Permissions")
local SpriteRenderer = require("src.render.SpriteRenderer")
local StartMenu = require("src.ui.gen2.StartMenu")

local ROD_ITEM = "OLD_ROD"
local FACINGS = { "down", "up", "left", "right" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- The loose rod OAM, `db y, x, attr, tile`, off the sprite's top-left
-- (data/sprites/facings.asm:122-152).  Read here a second time so a typo in the
-- engine's copy of the table is a mismatch rather than a shared mistake.
local ROD_OAM = {
  down  = { dx =  0, dy = 16, tile = 0xfc, flip = false },
  up    = { dx =  0, dy = -8, tile = 0xfc, flip = false },
  left  = { dx = -8, dy =  5, tile = 0xfd, flip = true },
  right = { dx = 16, dy =  5, tile = 0xfd, flip = false },
}
-- LoadFishingGFX's three destinations, vTiles $02 / $06 / $0a, which are the
-- bottom tile rows of the down / up / left standing frames; right is left
-- x-flipped (fishing_gfx.asm:13-18, facings.asm:143-152).
local POSE_ROW = { down = 0, up = 1, left = 2, right = 2 }
local POSE_FLIP = { down = false, up = false, left = false, right = true }
-- Four rows of two tiles: the three pose rows then $fc/$fd.
local SHEET_W, SHEET_H, ROD_ROW_Y = 16, 32, 24

-- Ponds with a shore on all four sides.  Route 28's has no object events at
-- all (../pokegold/maps/Route28.asm:29), so nothing walks into a shot and no
-- trainer's line of sight crosses one; the other two are the fallbacks if its
-- blocks are ever edited (../pokegold/maps/Route28.blk).
local MAPS = { "ROUTE_28", "VIRIDIAN_CITY", "ROUTE_43" }

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-fishing"
  local failures = 0

  local function check(label, condition, detail)
    if condition then
      U.log("PASS", label)
    else
      failures = failures + 1
      U.log("FAIL", label, detail ~= nil and tostring(detail) or "")
    end
    return condition and true or false
  end

  local function tap(btn, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    game.input.state[btn] = true
    U.wait(2)
    game.input.state[btn] = false
    U.wait(frames or 6)
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  local save = game.save

  -- ---- the halves of the drawing, before anything is on screen -------------
  -- A cache with no sheet, a sheet of the wrong size and a draw branch that
  -- never fires all look identical on screen: a plain standing player.

  local sheet = world.fishingSheet
  if not check("the cache carries LoadFishingGFX's sheet (world.fishingSheet)",
               type(sheet) == "string", sheet) then
    U.log("no emotes/fishing.png in this cache, so nothing below can draw.")
    U.log("re-import the cart first:")
    U.log("  POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_IMPORT_ONLY=1 \\")
    U.log("    POKEPORT_IMPORT_ROM=/path/to/gold.gbc love .")
    while true do coroutine.yield() end
  end

  local okImg, image = pcall(Assets.image, sheet)
  check("and it loads: " .. tostring(sheet), okImg and image ~= nil)
  if okImg and image then
    local w, h = image:getDimensions()
    check(("it is %dx%d, the four rows the quads are written against")
            :format(SHEET_W, SHEET_H),
          w == SHEET_W and h == SHEET_H, ("%dx%d"):format(w, h))
    if h ~= SHEET_H then
      U.log("a taller sheet moves the rod row, and both draws then sample")
      U.log("the wrong pixels -- Gen 1 shipped exactly that as #321.")
    end
  end

  local Player = require("src.world.gen2.Player")
  check("Player:drawFishing exists (the branch that reads player.fishing)",
        type(Player.drawFishing) == "function")
  check("SpriteRenderer:drawTile exists (it bakes the OBJ palette; a raw "
        .. "love.graphics.draw would leave the rod in DMG greys)",
        type(SpriteRenderer.drawTile) == "function")

  local rodDef = game.data and game.data.items and game.data.items[ROD_ITEM]
  check("OLD ROD is a real item in this cache", rodDef ~= nil)
  check("and it lives in the KEY ITEMS pocket",
        rodDef ~= nil and rodDef.pocket == "KEY_ITEM",
        rodDef and rodDef.pocket)

  -- ---- pick the pond ------------------------------------------------------
  -- Shores are re-derived from the generated blocks every run, so a re-extract
  -- that shifts the water degrades to another cell instead of parking the
  -- player at a wall.

  local function shores(mapId)
    local def = world.maps and world.maps[mapId]
    local tileset = def and world.tilesets and world.tilesets[def.tileset]
    if not (def and tileset) then return nil end
    local probe = Map.new(def, tileset)
    local taken = {}
    for _, obj in ipairs(def.objects or {}) do
      taken[obj.x .. "," .. obj.y] = true
    end
    local function land(cx, cy)
      if not probe:inBounds(cx, cy) then return false end
      if taken[cx .. "," .. cy] then return false end
      local coll = probe:cellCollision(cx, cy)
      return Permissions.isWalkable(coll) and not Permissions.isWater(coll)
    end
    local found = {}
    for _, facing in ipairs(FACINGS) do
      local d = DELTA[facing]
      for cy = 0, probe.heightCells - 1 do
        for cx = 0, probe.widthCells - 1 do
          if not found[facing] and land(cx, cy)
             and probe:inBounds(cx + d[1], cy + d[2])
             and Permissions.isWater(probe:cellCollision(cx + d[1], cy + d[2]))
             and land(cx - d[1], cy - d[2]) then
            found[facing] = { x = cx, y = cy }
          end
        end
      end
      if not found[facing] then return nil end
    end
    return found
  end

  local MAP, SHORE
  for _, id in ipairs(MAPS) do
    SHORE = shores(id)
    if SHORE then MAP = id break end
  end
  if not check("a pond with all four shores and a step of room behind each",
               MAP ~= nil, table.concat(MAPS, ", ")) then
    while true do coroutine.yield() end
  end
  U.log("fishing on " .. MAP .. ", from " ..
    ("down (%d,%d), up (%d,%d), left (%d,%d), right (%d,%d)"):format(
      SHORE.down.x, SHORE.down.y, SHORE.up.x, SHORE.up.y,
      SHORE.left.x, SHORE.left.y, SHORE.right.x, SHORE.right.y))

  -- ---- the bag, and a pond that never bites -------------------------------
  -- FISHGROUP_NONE is .FishNoFish: the cast, the pose and the rod are the same
  -- as a bite's, and every run ends on "Not even a nibble!" back on the map
  -- rather than in a battle nobody asked for.  Put back before the hand-off.

  save.inventory = { [ROD_ITEM] = 1 }
  save.bagOrder = { ROD_ITEM }
  local mapDef = world.maps[MAP]
  local realGroup = mapDef.fishGroup
  mapDef.fishGroup = "FISHGROUP_NONE"

  -- ---- what the sprite actually drew --------------------------------------

  local watch = nil
  local realDrawTile = SpriteRenderer.drawTile
  SpriteRenderer.drawTile = function(self, path, x, y, flip, quad)
    if watch and path == sheet then
      local qx, qy, qw, qh = 0, 0, 0, 0
      if quad and quad.getViewport then qx, qy, qw, qh = quad:getViewport() end
      watch[#watch + 1] = { x = x, y = y, flip = flip and true or false,
                            qx = qx, qy = qy, qw = qw, qh = qh }
    end
    return realDrawTile(self, path, x, y, flip, quad)
  end

  local function lastOfSize(calls, w, h)
    local hit
    for _, c in ipairs(calls) do
      if c.qw == w and c.qh == h then hit = c end
    end
    return hit
  end

  -- ---- walk to a shore ----------------------------------------------------

  local function goToShore(facing)
    local cell, d = SHORE[facing], DELTA[facing]
    world:setMap(MAP, cell.x - d[1], cell.y - d[2], facing)
    U.wait(24)
    U.hold(game, facing, 26)
    U.wait(10)
    local p = world.player
    if p.cellX ~= cell.x or p.cellY ~= cell.y then
      world:setMap(MAP, cell.x, cell.y, facing)
      U.wait(24)
      p = world.player
    end
    local fx, fy = p.cellX + d[1], p.cellY + d[2]
    check(("%s: standing at (%d,%d) with water in front")
            :format(facing, p.cellX, p.cellY),
          p.facing == facing and world.map:inBounds(fx, fy)
          and Permissions.isWater(world.map:cellCollision(fx, fy)),
          ("facing %s"):format(tostring(p.facing)))
  end

  -- ---- START, PACK, KEY ITEMS, OLD ROD, USE --------------------------------

  local function castRod(facing)
    tap("start")
    local menu = game.stack:top()
    if not check(("%s: START opened the menu"):format(facing),
                 getmetatable(menu) == StartMenu) then
      return false
    end
    for _ = 1, #menu.items do
      local row = menu.list and menu.list:current()
      if row and row.value == "pack" then break end
      tap("down", 4)
    end
    tap("a", 10)
    local pack = game.stack:top()
    if not check(("%s: and the PACK is open"):format(facing),
                 getmetatable(pack) == PackMenu) then
      return false
    end
    for _ = 1, 4 do
      if pack:pocket().id == "KEY_ITEM" then break end
      tap("right", 6)
    end
    check(("%s: on the KEY ITEMS pocket"):format(facing),
          pack:pocket().id == "KEY_ITEM", pack:pocket().id)
    for _ = 1, 20 do
      local row = pack.rows[pack.index]
      if row and row.id == ROD_ITEM then break end
      tap("down", 4)
    end
    local row = pack.rows[pack.index]
    if not check(("%s: cursor on the OLD ROD"):format(facing),
                 row ~= nil and row.id == ROD_ITEM, row and row.id) then
      return false
    end
    tap("a", 8)
    local sub = pack.submenu
    check(("%s: the item submenu opened on USE"):format(facing),
          sub ~= nil and sub.rows[sub.index] == "use",
          sub and sub.rows[sub.index])
    tap("a", 10)
    return true
  end

  -- ---- one facing, end to end ---------------------------------------------

  local function castAndSample(facing, index)
    goToShore(facing)
    if not castRod(facing) then return end

    for _ = 1, 60 do
      if world.fishing then break end
      U.wait(1)
    end
    check(("%s: the rod is out (world.fishing)"):format(facing),
          world.fishing ~= nil)
    check(("%s: the pose is up (player.fishing)"):format(facing),
          world.player.fishing == true)
    check(("%s: and it drew from the fishing sheet"):format(facing),
          world.player.fishSheet == sheet, world.player.fishSheet)
    check(("%s: the PACK closed, so the cast is on screen"):format(facing),
          getmetatable(game.stack:top()) ~= PackMenu)

    watch = {}
    U.wait(6)
    local calls = watch
    watch = nil
    local pose = lastOfSize(calls, 16, 8)
    local rod = lastOfSize(calls, 8, 8)
    check(("%s: a 16x8 pose row was drawn"):format(facing), pose ~= nil)
    check(("%s: and the 8x8 rod tile beside it"):format(facing), rod ~= nil)
    if pose and rod then
      check(("%s: the pose row is sheet row %d")
              :format(facing, POSE_ROW[facing]),
            pose.qx == 0 and pose.qy == POSE_ROW[facing] * 8,
            ("%d,%d"):format(pose.qx, pose.qy))
      check(("%s: the pose is%s x-flipped")
              :format(facing, POSE_FLIP[facing] and "" or " not"),
            pose.flip == POSE_FLIP[facing])
      local oam = ROD_OAM[facing]
      check(("%s: the rod tile is $%02x on the sheet's rod row")
              :format(facing, oam.tile),
            rod.qy == ROD_ROW_Y and rod.qx == (oam.tile - 0xfc) * 8,
            ("%d,%d"):format(rod.qx, rod.qy))
      check(("%s: the rod tile is%s x-flipped")
              :format(facing, oam.flip and "" or " not"),
            rod.flip == oam.flip)
      -- The pose row sits at the sprite's bottom tile row, so the OAM offsets
      -- are read back relative to it.
      local drop = math.max(0, (world.player.sprite.frameHeight or 16) - 8)
      check(("%s: the rod sits at OAM offset %d,%d from the sprite")
              :format(facing, oam.dx, oam.dy),
            rod.x - pose.x == oam.dx and rod.y - pose.y == oam.dy - drop,
            ("%d,%d"):format(rod.x - pose.x, rod.y - pose.y + drop))
    end
    U.shot(game, ("%s/%02d-fishing-%s.png"):format(out, index, facing))

    -- PutTheRodAway: the pose comes down with the verdict box, not later.
    local down = nil
    for frame = 1, 300 do
      if world.textbox then tap("a", 2) else U.wait(1) end
      if not down and world.player.fishing == nil then down = frame end
      if down and not world.textbox then break end
    end
    check(("%s: the pose came down with the box"):format(facing), down ~= nil)
    watch = {}
    U.wait(8)
    local after = #watch
    watch = nil
    check(("%s: and nothing draws the rod afterwards"):format(facing),
          after == 0, after)
  end

  for i, facing in ipairs(FACINGS) do
    castAndSample(facing, i)
  end

  SpriteRenderer.drawTile = realDrawTile
  mapDef.fishGroup = realGroup

  -- ---- hand off on a live cast --------------------------------------------

  goToShore("right")
  castRod("right")
  U.wait(20)

  U.log(("%d shot(s) in %s, one per facing (#1708)."):format(#FACINGS, out))
  U.log("in each one the player's lower half is the two-handed fishing pose,")
  U.log("not the standing legs, and one thin dark rod line runs from the hands")
  U.log("into the water: straight down below the feet facing down, straight up")
  U.log("above the head facing up, and a short stroke starting a tile clear of")
  U.log("the sprite and sloping away from it facing left or right.")
  U.log("the near miss to look for is the pose swapping in with no rod, or the")
  U.log("rod as a garbage block, which is the sheet and the quads disagreeing;")
  U.log("the other is a rod in flat DMG greys while the player is in colour.")
  U.log("the pond bit on nothing for the four shots; the group is back now, so")
  U.log("this last cast can bite. the controls are yours.")
  if failures > 0 then
    U.log(("%d check(s) failed above -- read those before looking at the shots")
            :format(failures))
  end

  while true do
    coroutine.yield()
  end
end
