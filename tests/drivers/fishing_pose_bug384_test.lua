-- Driver: the fishing POSE -- the standing frame's bottom tile row swapped for
-- RedFishingTiles so the rod ends in hands -- and its two-stage teardown, rod
-- OAM out at once, pose ~10 frames later (#384).  FishingAnim / RedFishingTiles
-- / res BIT_LEDGE_OR_FISHING: player_animations.asm:378, :485, :449.
-- No POKEPORT_SPEED: fast-forward outruns the rendered frames and the audio
-- clock, so the ten-frame tail can neither be sampled nor watched.
--   POKEPORT_DRIVER=tests/drivers/fishing_pose_bug384_test.lua POKEPORT_IDENTITY=bug384 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local TextBox = require("src.render.TextBox")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Same pond as tests/drivers/fishing_rod_bug321_test.lua: the Viridian City
  -- water block (x=8..13, y=24..27, data/generated/maps.lua VIRIDIAN_CITY) is
  -- the one place all four shores sit a few steps apart.  shoreFor() re-derives
  -- each stand cell from the map so a layout edit cannot park us at a wall.
  local MAP = "VIRIDIAN_CITY"
  local SPOTS = {
    { x = 10, y = 23, facing = "down",  note = "north shore" },
    { x = 8,  y = 28, facing = "up",    note = "south shore" },
    { x = 14, y = 24, facing = "left",  note = "east shore" },
    { x = 7,  y = 24, facing = "right", note = "west shore" },
  }
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local ROD = "OLD_ROD"

  -- ---- the halves of the drawing, before anything is on screen ------------
  -- A missing sheet, a sheet of the wrong size and a Player that never picks
  -- up fishTiles all look the same: a rod ending in mid air, which is the
  -- shipped bug.

  local fx = game.data.field.overworldFx
  local POSE = {
    { key = "redFishFront", facing = "down",  asm = "RedFishingTilesFront, tile $02" },
    { key = "redFishBack",  facing = "up",    asm = "RedFishingTilesBack, tile $06" },
    { key = "redFishSide",  facing = "left",  asm = "RedFishingTilesSide, tile $0a" },
  }
  for _, p in ipairs(POSE) do
    local def = fx and fx[p.key]
    if check(("field.overworldFx.%s resolves (%s)"):format(p.key, p.asm),
             def ~= nil and type(def.path) == "string") then
      local ok, img = pcall(love.graphics.newImage, def.path)
      if check(("%s loads: %s"):format(p.key, def.path), ok and img ~= nil) then
        local w, h = img:getDimensions()
        check(("%s is 16x8, one 16-wide tile row"):format(p.key), w == 16 and h == 8)
      end
    end
  end

  check("SpriteRenderer:drawTile exists (the pose row wears the sprite's OBP)",
        type(SpriteRenderer.drawTile) == "function")

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.inventory = { [ROD] = 1 }
  game.save.bagOrder = { ROD }
  check("OLD ROD is a real item and the only thing in the bag",
        game.data.items[ROD] ~= nil and (game.save.inventory[ROD] or 0) > 0)
  local ItemEffects = require("src.inventory.ItemEffects")
  check("using it routes to the fishing branch",
        ItemEffects.use(game.data, game.save, ROD, nil, nil, nil, game.overworld) == "fish")

  local function useRod()
    Screens.push(game, "BagMenu")
    U.wait(20)
    U.tap(game, "a")   -- OLD ROD -> USE/TOSS
    U.wait(20)
    U.tap(game, "a")   -- USE
    U.wait(30)
  end

  local function topBox()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local shown = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    return top, table.concat(shown, " / ")
  end

  local function shoreFor(map, spot)
    local d = DELTA[spot.facing]
    if map:inBounds(spot.x + d[1], spot.y + d[2])
       and map:isWaterCell(spot.x + d[1], spot.y + d[2])
       and map:isWalkableCell(spot.x, spot.y) then
      return spot.x, spot.y
    end
    for y = 0, map.def.height * 2 - 1 do
      for x = 0, map.def.width * 2 - 1 do
        if map:isWalkableCell(x, y) and not map:isWaterCell(x, y)
           and map:inBounds(x + d[1], y + d[2])
           and map:isWaterCell(x + d[1], y + d[2]) then
          U.log(("(%d,%d) no longer faces water; using (%d,%d) for %s")
                  :format(spot.x, spot.y, x, y, spot.facing))
          return x, y
        end
      end
    end
    return spot.x, spot.y
  end

  -- park on a shore, cast, and stop on the dots box
  local function castFrom(spot)
    U.teleport(game, MAP, spot.x, spot.y, spot.facing)
    U.wait(15)
    local sx, sy = shoreFor(game.overworld.map, spot)
    if sx ~= spot.x or sy ~= spot.y then
      U.teleport(game, MAP, sx, sy, spot.facing)
      U.wait(15)
    end
    local ow = game.overworld
    local fcx, fcy = ow.player:facingCell()
    check(("facing %s from (%d,%d), the %s: water in front")
            :format(spot.facing, sx, sy, spot.note),
          ow.map:inBounds(fcx, fcy) and ow.map:isWaterCell(fcx, fcy))
    useRod()
    return ow
  end

  -- ---- pose up, one facing at a time -------------------------------------
  -- Every facing is left on its verdict box; the next teleport pops it, so no
  -- bite ever reaches a battle here.

  for _, spot in ipairs(SPOTS) do
    local ow = castFrom(spot)
    local dots = topBox()
    check(("%s: USE opened the fishing box"):format(spot.facing), dots ~= nil)
    check(("%s: the rod OAM is up (overworld.fishing)"):format(spot.facing),
          ow.fishing ~= nil and ow.fishing.facing == spot.facing)
    check(("%s: the pose is up (player.fishing)"):format(spot.facing),
          ow.player.fishing == true)
    check(("%s: a pose row exists for this facing"):format(spot.facing),
          ow.player.fishTiles ~= nil and ow.player.fishTiles[spot.facing] ~= nil)
    if spot.facing == "right" then
      check("right reuses the left pose row, x-flipped like the sprite",
            ow.player.fishTiles.right == ow.player.fishTiles.left)
    end
    -- RodResponse (engine/items/item_effects.asm:1878) zeroes wWalkBikeSurfState
    -- across FishingAnim, so the sheet under the pose is always the walking one
    local sheet = ow.player:pose()
    check(("%s: the walking sheet is what draws (not surf/bike)"):format(spot.facing),
          sheet == ow.player.sprite)
    if not U.shot(game, ("%s/bug384_pose_%s.png"):format(SHOT_DIR, spot.facing)) then
      check(("%s: screenshot reached disk"):format(spot.facing), false)
    end
  end

  -- ---- the retract, sampled frame by frame --------------------------------
  -- The rod OAM dies with the verdict box (res BIT_LEDGE_OR_FISHING right
  -- after PrintText, player_animations.asm:449) but the patched player tiles
  -- live until ReloadMapSpriteTilePatterns (home/reload_sprites.asm) a few
  -- frames later.  Only the no-bite verdict shows that gap: a bite goes
  -- straight into a battle, which reloads the tiles itself, so drop OLD ROD's
  -- `always` hook for the rest of this run.
  local rodFishing = (game.data.field.fishing or {})[ROD]
  check("field.fishing.OLD_ROD exists", rodFishing ~= nil)
  if rodFishing then rodFishing.always = nil end

  local ow = castFrom(SPOTS[4])
  local dots = topBox()
  if dots then
    for _ = 1, 12 do
      U.tap(game, "a")
      U.wait(12)
      if game.stack:top() ~= dots then break end
    end
  end
  local verdict, verdictText = topBox()
  check("the no-bite verdict box opened", verdict ~= nil)
  if verdictText then U.log("box reads:", verdictText) end

  local rodGone, poseGone
  for i = 1, 180 do
    if game.stack:top() == verdict then U.tap(game, "a") else U.wait(1) end
    if not rodGone and ow.fishing == nil then rodGone = i end
    if not poseGone and ow.player.fishing == nil then poseGone = i end
    if poseGone then break end
  end
  check("the rod OAM came down", rodGone ~= nil)
  check("the pose came down too", poseGone ~= nil)
  if rodGone and poseGone then
    U.log(("rod out on sample frame %d, pose out on %d"):format(rodGone, poseGone))
    check("the pose OUTLIVES the rod (two stages, not one)", poseGone > rodGone)
    check("the tail is around ten frames", poseGone - rodGone >= 5)
  end

  -- ---- hand off ----------------------------------------------------------
  local live = castFrom(SPOTS[4])
  if live.fishing then
    local box = topBox()
    if box then
      for _ = 1, 12 do
        U.tap(game, "a")
        U.wait(12)
        if game.stack:top() ~= box then break end
      end
    end
  end
  U.log("West shore of the Viridian pond, mid-cast, verdict box open. OLD ROD")
  U.log("was set to never bite for this cast, so dismissing it stays on the map.")
  U.log("The rod should read as one unbroken stroke: hands and near end in the")
  U.log("player's lower body, far end in the loose tile, touching on the same")
  U.log("scanline, and the lower row the same shade as the torso above it.")
  U.log("Dismiss the box: the loose tile goes at once, the hands hold about ten")
  U.log("frames, then the sprite snaps back. Both going together is the bug.")
  U.log("Shots: " .. SHOT_DIR .. "/bug384_pose_<facing>.png")

  while true do
    coroutine.yield()
  end
end
