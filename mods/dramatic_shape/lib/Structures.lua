-- Voxel world mode: detect the map's structures and pick a 3D model for
-- each -- the 3dSen idea applied to a tile map. 3dSen turns flat NES
-- scenes into 3D by classifying every graphic into a geometry archetype
-- (floor, wall, box, voxelized sprite) and building real geometry that
-- keeps the original art as its texture; this module does the same with
-- the map's tile layer as the scene description:
--
--   1. Flood-fill every connected region of solid (upright, unauthored)
--      tiles -- a house with its mailbox, the potted plant, a fence row,
--      a stretch of border forest.
--
--   2. Decide which pixels of the region's art are BACKGROUND. Tileset
--      art carries no alpha and white is a paint color (window frames,
--      wall stripes), so whiteness alone says nothing. The map does: the
--      background is the white that CONNECTS TO WALKABLE GROUND in the
--      assembled scene. Seeding a flood from the surrounding ground
--      eats the air around a fence post or a plant's leaves but cannot
--      reach an interior wall's white stripes sealed behind its dark
--      trim -- exactly the distinction a human reads.
--
--   3. Tiles whose art turned out mostly background are SPRITE-LIKE;
--      their connected clusters become per-pixel voxel OBJECTS at the
--      art's real drawn height (a 2-row plant is a 16px silhouette, a
--      fence a row of true posts with air between), thin voxel depth,
--      standing on synthesized ground. This splits mixed regions: the
--      mailbox voxelizes even where it touches the house.
--
--   4. Everything else becomes a VOLUME: each column rises to the height
--      the structure is actually DRAWN. A column's run gives its extent,
--      repetition caps it -- the border forest repeats a 2-row canopy
--      for forty rows and must be rows of 16px trees, not a monolith --
--      and columns answer to their region: the column above a doorway
--      repeats internally but adopts its 48px house. The south face
--      folds the artwork up (ChunkMesher's band rule).
--
-- data/voxel_heights.lua is the PROFILE over this: a tile authored there
-- (ledges, or a mod pinning a shape) bypasses detection entirely, the way
-- a 3dSen game profile pins a pattern to a geometry type.
--
-- Everything here is derived per map and cached; pixel access (object
-- voxelization, void detection) degrades gracefully headless -- regions
-- simply stay volumes and the geometry tests keep passing.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")
local Map = require("src.world.Map")
local Buildings = V.require("Buildings")
local TileShape = V.require("TileShape")
local Budget = V.require("BuildBudget")

local Structures = {}

-- must match ChunkMesher's ring (3 border blocks, in tiles)
local RING = 12

-- how far past the map body cells still get the hull. A route's ring is
-- nearly as big as its body; modelling all of it costs hundreds of
-- thousands of quads of border trees nobody walks near. Beyond this,
-- pinned cells simply are not claimed and fall through to the mesher's
-- plain box -- cheap distant scenery. (Declared up here rather than
-- beside buildCylinders because forMap's grid resolve reads it too.)
local ROUND_RING = 4

-- object-mode gates
local OBJECT_MAX_ROWS = 6          -- a prop is at most 48px of drawing
local OBJECT_MAX_QUADS = 4096      -- safety cap per cluster
local TILE_BG_RATIO = 0.20         -- art background for "sprite-like"
local CLUSTER_MIN_BG = 0.05        -- a silhouette must actually exist
local OBJECT_DEPTH = 6             -- voxel thickness of a detected prop
-- thickness of profile-pinned standees per class: a TV is a deliberate
-- object and reads better with body; `prop` doubles as the THIN pool
-- (plants, stools -- mostly silhouette); `cutout` is paper: one voxel,
-- pure profile; `post` matches the 6px the detector gives the fence
-- rows it finds on its own, so pinned and detected fences look alike;
-- `signpost` is a plate on a stick -- 2 voxels, the thinnest that still
-- shows an edge
local PINNED_DEPTH = { billboard = 10, prop = 5, stool = 10, cutout = 1,
                       console = 10, post = 6, signpost = 2 }

local MAX_ROWS = 6                 -- volume height cap: 48px

local cache = {}

-- ---------------------------------------------------------------- pixels --

local atlasData = {}

local function pixels(tileset)
  local path = tileset.image
  if atlasData[path] == nil then
    local ok, data = pcall(Assets.imageData, path)
    atlasData[path] = (ok and data and data.getPixel) and data or false
  end
  return atlasData[path] or nil
end

-- tiles whose art is entirely black or transparent (interior darkness):
-- these never extrude, whatever class they resolved to
local function voidTiles(tileset)
  local data = pixels(tileset)
  if not data then return nil end
  local perRow = tileset.tilesPerRow or 16
  local iw, ih = data:getDimensions()
  local set = {}
  for t = 0, (iw / 8) * (ih / 8) - 1 do
    local ox = (t % perRow) * 8
    local oy = math.floor(t / perRow) * 8
    local void = true
    for py = 0, 7 do
      for px = 0, 7 do
        local r, g, b, a = data:getPixel(ox + px, oy + py)
        if a > 0 and math.max(r, g, b) > 0.17 then
          void = false
          break
        end
      end
      if not void then break end
    end
    if void then set[t] = true end
  end
  return set
end

-- ----------------------------------------------------------------- build --

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function keyOf(tx, ty)
  return (ty + 64) * 4096 + (tx + 64)
end

function Structures.forMap(map)
  local S = cache[map.id]
  if S then return S end

  local tileset = map.tileset
  local shapes = TileShape.forMap(map)
  local void = voidTiles(tileset)
  local perRow = tileset.tilesPerRow or 16

  local def = map.def
  local tw, th = def.width * 4, def.height * 4
  local x0, x1 = -RING, tw + RING - 1
  local y0, y1 = -RING, th + RING - 1

  -- resolve the whole grid once: shape + tile per key. Ring positions use
  -- the same border override the 2D renderer draws with
  -- (TileRenderer.borderBlockFor: outdoor maps ring with the solid tree
  -- wall, NOT their own borderBlock) -- a route's borderBlock is the GRASS
  -- block, and meshing that grew a 12-tile apron of tall grass past every
  -- route edge, which leaked into the neighbouring town's plaza.
  -- BLACK void fill is not a block at all: borderBlockFor answers `false`,
  -- and there is simply nothing out there to build. tileLookup then returns
  -- nil past the body and the ring keys are never written, which the whole
  -- file already copes with -- every neighbour query reaches one step
  -- outside the analysed range and reads nil for its trouble, so an absent
  -- cell is the shape "nothing" has always had here. (It used to add 1 to
  -- that `false`, which threw, failed the mesh build for every map on the
  -- route, and dropped the mode to the flat 2D path entirely.)
  local TileRenderer = require("src.render.TileRenderer")
  local borderId = TileRenderer.borderBlockFor(map)
  local borderBlk = borderId and tileset.blocks[borderId + 1] or nil
  -- TREES fill stops at ROUND_RING instead of running the full RING.
  -- Only that far out does a tree cell get carved into a hull; past it
  -- the cells fall through to the mesher's plain box, and a slab of
  -- flat-topped boxes beside the modelled wall reads as a painted-on
  -- plateau -- the wall looking like it was cut off with scissors. So
  -- the far ring is simply not built: beyond ROUND_RING tileLookup
  -- answers nil, which is the same "nothing out there" BLACK already
  -- produces and every pass below already copes with. The cut lands on
  -- the carve boundary exactly -- the 2x2-cell canopy scan starts at
  -- floor(-RING/2) and RING, ROUND_RING and the body are all multiples
  -- of 4 tiles, so no group is left half-resolved at the edge.
  --
  -- WATER and the other tilesets' own borders keep the full ring: a flat
  -- sheet of water is what water looks like from above anyway, and an
  -- interior's border is black already.
  local hullRingOnly = borderBlk and def.tileset == "OVERWORLD"
                       and (TileRenderer.voidFill or "trees") == "trees"
  local tw2, th2 = tw, th
  local function tileLookup(tx, ty)
    if tx >= 0 and ty >= 0 and tx < tw2 and ty < th2 then
      return map:tileAt(tx, ty)
    end
    if not borderBlk then return nil end
    if hullRingOnly and (tx < -ROUND_RING or ty < -ROUND_RING
                         or tx >= tw2 + ROUND_RING
                         or ty >= th2 + ROUND_RING) then
      return nil
    end
    return borderBlk[(ty % 4) * 4 + (tx % 4) + 1] or 0
  end
  local shapeAt, tileAt = {}, {}
  for ty = y0, y1 do
    for tx = x0, x1 do
      Budget.tick()
      local tile = tileLookup(tx, ty)
      if tile then
        local k = keyOf(tx, ty)
        local s = TileShape.at(map, shapes, tile, tx, ty)
        if s and void and void[tile] and not s.authored then
          s = shapes.classes.void
        end
        shapeAt[k], tileAt[k] = s, tile
      end
    end
  end

  -- ---- buildings: whole sprites voxelized band by band ----
  --
  -- Before anything else looks at this grid. A profiled building is a
  -- drawing whose bands depict DIFFERENT 3D surfaces (roof from above,
  -- facade face-on, ends sloped), and the passes below -- the door fold,
  -- the region flood, the volume builder -- all assume one drawing is one
  -- upright thing. Modelling the building first and claiming its tiles
  -- keeps every one of them off it.
  --
  -- (grassQuads live apart from objectQuads: grass renders as its own mesh
  -- AFTER the characters -- see VoxelScene -- so the southern tuft row
  -- still overdraws a walker's feet even though characters stamp over
  -- terrain.)
  S = { shapeAt = shapeAt, tileAt = tileAt, outdoor = Map.isOutdoor(def),
        hideBareRing = hullRingOnly or nil,
        runs = {}, skip = {}, ground = {}, doorFold = {}, objectQuads = {},
        grassQuads = {}, flowerQuads = {}, roundStamps = {}, figures = {} }
  Buildings.build(S, map, pixels(tileset), perRow)

  -- Fold doors into their buildings. A door cell is WALKABLE (the player
  -- steps onto it to warp), so it resolves to ground and punches a hole in
  -- the facade: the door lies flat, the rows above it recess, and -- worse
  -- -- the hole lets the background flood into the building's interior
  -- whites, shredding it into misdetected sprite clusters. Visually the
  -- door is part of the facade, so mark the door cell's tiles structural:
  -- the fold then shows the door art standing at ground level in the
  -- building's front face. Door graphics only (the tileset's doorTiles);
  -- interior stair/mat warps stay flat.
  --
  -- A PROFILE PIN WINS over the fold. The fold is detection, and rule 1
  -- of the resolution order is that an authored tile bypasses detection
  -- -- but this used to overwrite shapeAt unconditionally, so a pin on
  -- any tile the tileset also lists in doorTiles was dead on arrival.
  -- Celadon Mansion is the case that found it: all four of its
  -- staircases are door tiles, so `stair_e` / `stair_down_w` pins there
  -- silently did nothing and the flights stayed painted on the floor.
  for cy = math.floor(y0 / 2), math.floor(y1 / 2) do
    for cx = math.floor(x0 / 2), math.floor(x1 / 2) do
      if map.doorTiles[map:cellTile(cx, cy)] then
        local northK = keyOf(cx * 2, cy * 2 - 1)
        local ns = shapeAt[northK]
        if ns and ns.art == "upright" then
          for dy = 0, 1 do
            for dx = 0, 1 do
              local dk = keyOf(cx * 2 + dx, cy * 2 + dy)
              local ds = shapeAt[dk]
              if not (ds and ds.authored) then
                shapeAt[dk] = shapes.classes.wall
                -- remembered for buildVolume: a folded doorway column
                -- answers to its REGION for height and top, not to its
                -- own drawn extent (see the door adoption there)
                S.doorFold[dk] = true
              end
            end
          end
        end
      end
    end
  end

  -- a structure cell: solid art the detector may model (authored tiles are
  -- profile-pinned and keep their authored shape)
  local function structural(k)
    local s = shapeAt[k]
    return s and s.art == "upright" and not s.authored
  end

  -- ---- cylinders: profile-pinned round graphics, one per 16x16 cell ----
  -- the flat ground tiles this map actually places, for the hull's
  -- ground matching: the ball's own drawn background picks its floor
  local groundTiles = {}
  do
    local seenG = {}
    for k, s in pairs(shapeAt) do
      if s and s.flat and s.class == "ground" then
        local t = tileAt[k]
        if t and not seenG[t] then
          seenG[t] = true
          groundTiles[#groundTiles + 1] = t
        end
      end
    end
  end
  Structures.buildCylinders(S, map, x0, x1, y0, y1, groundTiles)

  -- ---- stairs: profile-pinned cells that render as real steps ----
  Structures.buildStairs(S, map, x0, x1, y0, y1)

  -- ---- bookcases: pinned shelves collapsed to one cell of depth ----
  Structures.buildBookcases(S, map, x0, x1, y0, y1)

  -- ---- figures: a person drawn INTO furniture, lifted off it ----
  -- Before the region flood and the volume pass, so everything after this
  -- reads the tiles the profile says are there once the figure is gone.
  -- (Its own tiles are authored furniture or walkable floor either way, so
  -- no pass below would have claimed them -- but the repaint is what those
  -- passes should see, and this needs no pixel access to do it.)
  Structures.buildFigures(S, map, x0, x1, y0, y1)

  -- ---- flood-fill regions of structural tiles ----
  local seen = {}
  local regions = {}
  for ty = y0, y1 do
    for tx = x0, x1 do
      local k = keyOf(tx, ty)
      if structural(k) and not seen[k] then
        local region = { tiles = {}, minX = tx, maxX = tx,
                         minY = ty, maxY = ty }
        local queue = { { tx, ty } }
        seen[k] = true
        while #queue > 0 do
          Budget.tick()
          local c = table.remove(queue)
          local cx, cy = c[1], c[2]
          region.tiles[#region.tiles + 1] = c
          region.minX = math.min(region.minX, cx)
          region.maxX = math.max(region.maxX, cx)
          region.minY = math.min(region.minY, cy)
          region.maxY = math.max(region.maxY, cy)
          for _, d in ipairs(DIRS4) do
            local nx, ny = cx + d[1], cy + d[2]
            if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
              local nk = keyOf(nx, ny)
              if structural(nk) and not seen[nk] then
                seen[nk] = true
                queue[#queue + 1] = { nx, ny }
              end
            end
          end
        end
        regions[#regions + 1] = region
      end
    end
  end

  -- ---- model each region: carve out per-pixel objects, volume the rest --
  local data = pixels(tileset)
  for _, region in ipairs(regions) do
    local leftover = region.tiles
    if data then
      leftover = Structures.extractObjects(S, map, region, data, perRow)
    end
    if #leftover > 0 then
      Structures.buildVolume(S, map, leftover)
    end
  end

  -- ---- profile-pinned billboards (signs): forced per-pixel slabs ----
  if data then
    local seenB = {}
    for ty = y0, y1 do
      for tx = x0, x1 do
        local k = keyOf(tx, ty)
        local s = shapeAt[k]
        if s and s.art == "billboard" and not seenB[k] then
          local reg = { tiles = {}, minX = tx, maxX = tx,
                        minY = ty, maxY = ty }
          local queue = { { tx, ty } }
          seenB[k] = true
          while #queue > 0 do
            local c = table.remove(queue)
            reg.tiles[#reg.tiles + 1] = c
            reg.minX = math.min(reg.minX, c[1])
            reg.maxX = math.max(reg.maxX, c[1])
            reg.minY = math.min(reg.minY, c[2])
            reg.maxY = math.max(reg.maxY, c[2])
            for _, d in ipairs(DIRS4) do
              local nk = keyOf(c[1] + d[1], c[2] + d[2])
              local ns = shapeAt[nk]
              -- same CLASS, not just billboard art: `billboard` and
              -- `prop` are two pools precisely so touching drawings (a TV
              -- behind its console) become two standing objects instead
              -- of one stacked cutout
              if ns and ns.art == "billboard" and ns.class == s.class
                 and not seenB[nk] then
                seenB[nk] = true
                queue[#queue + 1] = { c[1] + d[1], c[2] + d[2] }
              end
            end
          end
          Structures.extractObjects(S, map, reg, data, perRow, true)
        end
      end
    end

    -- ---- profile-pinned fence posts: per-CELL standee slabs ----
    -- A fence line repeats one drawing for a dozen cells, and its art
    -- touches across cell seams. Pooled like a billboard the whole line
    -- would stand as ONE drawing-tall tower at one depth (the detector's
    -- vertical-repetition guard exists precisely to refuse that, which
    -- is why undetected fence columns fell to the volume path as boxes).
    -- Each CELL extracts alone instead: its posts stand in their own row
    -- band and the fence marches north cell by cell.
    local postCells = {}
    for ty = y0, y1 do
      for tx = x0, x1 do
        local s = shapeAt[keyOf(tx, ty)]
        if s and s.art == "post" then
          local ck = keyOf(math.floor(tx / 2), math.floor(ty / 2))
          postCells[ck] = postCells[ck] or {}
          local list = postCells[ck]
          list[#list + 1] = { tx, ty }
        end
      end
    end
    for _, tiles in pairs(postCells) do
      local reg = { tiles = tiles,
                    minX = tiles[1][1], maxX = tiles[1][1],
                    minY = tiles[1][2], maxY = tiles[1][2] }
      for _, c in ipairs(tiles) do
        reg.minX = math.min(reg.minX, c[1])
        reg.maxX = math.max(reg.maxX, c[1])
        reg.minY = math.min(reg.minY, c[2])
        reg.maxY = math.max(reg.maxY, c[2])
      end
      Structures.extractObjects(S, map, reg, data, perRow, "opaque")
    end

    -- ---- profile-pinned relief props: top-down drawings that extrude ----
    local seenR = {}
    for ty = y0, y1 do
      for tx = x0, x1 do
        local k = keyOf(tx, ty)
        local s = shapeAt[k]
        if s and s.art == "relief" and not seenR[k] then
          local reg = { tiles = {}, minX = tx, maxX = tx,
                        minY = ty, maxY = ty }
          local queue = { { tx, ty } }
          seenR[k] = true
          while #queue > 0 do
            local c = table.remove(queue)
            reg.tiles[#reg.tiles + 1] = c
            reg.minX = math.min(reg.minX, c[1])
            reg.maxX = math.max(reg.maxX, c[1])
            reg.minY = math.min(reg.minY, c[2])
            reg.maxY = math.max(reg.maxY, c[2])
            for _, d in ipairs(DIRS4) do
              local nk = keyOf(c[1] + d[1], c[2] + d[2])
              local ns = shapeAt[nk]
              if ns and ns.art == "relief" and ns.class == s.class
                 and not seenR[nk] then
                seenR[nk] = true
                queue[#queue + 1] = { c[1] + d[1], c[2] + d[2] }
              end
            end
          end
          for _, c in ipairs(reg.tiles) do
            local ck = keyOf(c[1], c[2])
            S.skip[ck] = true
            S.ground[ck] = false
          end
          Structures.buildRelief(S, map, reg, data, perRow, s.h or 5)
        end
      end
    end

    -- ---- tall grass: two standing tuft rows per tile. BODY only: the 2D
    -- renderer never draws a neighbour's ring, and standing scenery past a
    -- map's edge would poke into the map next door ----
    Structures.buildGrass(S, map, 0, tw - 1, 0, th - 1, data)

    -- ---- flowers: the animated meadow tile stands as a 1px cutout ----
    Structures.buildFlowers(S, map, tw, th, x0, x1, y0, y1, data)
  end

  -- ---- authored ground under pinned props ----
  -- The profile can name the tile a pinned prop stands on (a tileset
  -- entry's prop_ground: prop tile id -> ground tile id), overriding
  -- the neighbour vote. The cuttable bush stands on the plain grass
  -- Cut itself leaves behind, not on whatever path its neighbours
  -- happen to vote in.
  do
    local okP, prof = pcall(V.data, "voxel_heights")
    local entry = okP and type(prof) == "table" and prof.tilesets
                  and prof.tilesets[tileset.id]
    local pg = entry and entry.prop_ground
    if type(pg) == "table" then
      for k, skipped in pairs(S.skip) do
        if skipped then
          local g = pg[S.tileAt[k]]
          if g then S.ground[k] = g end
        end
      end
    end
  end

  -- unresolved claimed ground (a hull with no art match, headless
  -- cylinders): no flat neighbour to vote with, so fall back to the
  -- map's commonest ground tile
  local votes, best, bestN = {}, nil, 0
  for k, s in pairs(shapeAt) do
    if s and s.flat and s.class == "ground" then
      local t = tileAt[k]
      votes[t] = (votes[t] or 0) + 1
      if votes[t] > bestN then best, bestN = t, votes[t] end
    end
  end
  for k, g in pairs(S.ground) do
    if g == false then S.ground[k] = best end
  end

  cache[map.id] = S
  return S
end

-- ---- round scenery: outline-hulled voxel balls ----

-- Cells the profile pins as round (tree canopies -- the class keeps its
-- historical `cylinder` name in the data file) render as a VOXEL HULL cut
-- from the drawing itself. The first shipped attempt was a lathe -- the
-- per-row silhouette width revolved into a 12-segment column with the art
-- wrapped by sin(angle) -- and it read exactly like what it was: the
-- sprite pasted on a cylinder, with the wrap smearing the pixels into
-- vertical stripes. This replaces it with real voxels.
--
-- Segmentation first, silhouette-width second: the tree cell's art is a
-- ball drawn over background grass, and the background's mid greens pass
-- any brightness test (they inflated every lathe row to full width). The
-- ball's own DARKEST pixels are what bound it, so the mask is "the
-- darkest-shade outline plus everything it encloses": flood from the cell
-- border through every non-black pixel; what the flood cannot reach is
-- the tree, and the cast shadow under the canopy (dark but not enclosed)
-- floods away with the grass. Art with no closed black outline -- the
-- border tree wall is a dither of black and canopy with no drawn ring --
-- encloses nothing; there the flood passes only through the LIGHT shades
-- (the methodology doc's rule: black and dark together form the
-- boundary), and the dither mass itself becomes the mask, checker holes
-- and all, because a 4-connected flood cannot thread a diagonal checker.
--
-- Volume: each mask row is a disc. The row's span gives a center and
-- half-width, and every mask pixel's column runs that circle's chord in
-- z, quantized to whole voxels -- the front view IS the sprite, the plan
-- view is the sprite's own width profile turned in depth, and both step
-- pixel by pixel. Rows below the mask (the drawn shadow) repeat the
-- bottom row's discs down to the ground so the canopy stands on a short
-- dark foot instead of floating.
--
-- Skin: front and back faces carry the drawing per-pixel (the back reads
-- mirrored, sprite-pure); side and step faces take their column's own
-- texel, which puts the drawn outline exactly on the silhouette's rim;
-- and a fully exposed cap keeps its outline only on the rim cells while
-- the interior samples the canopy a couple of rows deeper -- painting the
-- whole cap with the outline row blacked out every dome on the first
-- attempt (the lathe hit the same bug with its top discs).
--
-- Tree walls repeat the same four tiles for hundreds of cells, so the
-- hull is built once per distinct art signature and stamped per cell.
local ROUND_SHADE = { front = 1.0, back = 0.68, side = 0.78,
                      top = 1.0, bottom = 0.55 }

local function roundTemplate(S, map, data, cx, cy, groundTiles, N, capRows)
  N = N or 16                  -- art canvas: 16 = one cell, 32 = 2x2 cells
  local N2 = N / 2
  local perRow = map.tileset.tilesPerRow or 16
  local atlasW = map.tileset.imageWidth or 128
  local atlasH = map.tileset.imageHeight or 48

  -- cell-space art access (NxN, row 0 = top), anchored at cell (cx, cy)
  local function tileOf(px, py)
    return S.tileAt[keyOf(cx * 2 + math.floor(px / 8),
                          cy * 2 + math.floor(py / 8))]
  end
  local function texel(px, py)
    local tile = tileOf(px, py)
    return (tile % perRow) * 8 + px % 8,
           math.floor(tile / perRow) * 8 + py % 8
  end

  -- shade class of every canvas pixel, indexed py * N + px
  local cls = {}
  for py = 0, N - 1 do
    for px = 0, N - 1 do
      local ax, ay = texel(px, py)
      local r, g, b, a = data:getPixel(ax, ay)
      cls[py * N + px] = a == 0 and "off"
                         or Structures.shadeClass(math.min(r, g, b))
    end
  end

  -- 4-connected flood from the canvas border through `passable` classes
  local function floodOutside(passable)
    local out, stack = {}, {}
    local function seed(i)
      if not out[i] and passable[cls[i]] then
        out[i] = true
        stack[#stack + 1] = i
      end
    end
    for i = 0, N - 1 do
      seed(i); seed(N * (N - 1) + i); seed(i * N); seed(i * N + N - 1)
    end
    while #stack > 0 do
      local i = table.remove(stack)
      local px = i % N
      if px > 0 then seed(i - 1) end
      if px < N - 1 then seed(i + 1) end
      if i >= N then seed(i - N) end
      if i < N * (N - 1) then seed(i + N) end
    end
    return out
  end

  -- the mask: darkest-pixel outline plus its enclosure; dither fallback
  local out = floodOutside({ off = true, dark = true,
                             light = true, white = true })
  local mask, enclosed = {}, 0
  for i = 0, N * N - 1 do
    if not out[i] then
      mask[i] = true
      if cls[i] ~= "black" then enclosed = enclosed + 1 end
    end
  end
  if enclosed < N * N / 8 then
    out = floodOutside({ off = true, light = true, white = true })
    mask = {}
    for i = 0, N * N - 1 do
      if not out[i] and cls[i] ~= "off" then mask[i] = true end
    end
  end
  local any = nil
  for i = 0, N * N - 1 do any = any or mask[i] end
  if not any then return {} end

  -- a CAPPED hull (the stump): the top capRows rows of the mask are the
  -- drawn cut face -- a surface seen at an angle, not body. Strip them
  -- from the mask and remember their art span; the top-face quads below
  -- project that ellipse across the round cap.
  local capY0, capY1 = nil, nil
  if capRows and capRows > 0 then
    local top = nil
    for iy = 0, N - 1 do
      for ix = 0, N - 1 do
        if mask[iy * N + ix] then top = iy break end
      end
      if top then break end
    end
    if top then
      capY0 = top
      capY1 = math.min(top + capRows - 1, N - 2)
      for iy = capY0, capY1 do
        for ix = 0, N - 1 do mask[iy * N + ix] = nil end
      end
      any = nil
      for i = 0, N * N - 1 do any = any or mask[i] end
      if not any then return {} end
    end
  end

  -- the ground the ball stands on: the drawing's own background names
  -- it. Score every flat ground tile the map places against the cell's
  -- unmasked light pixels and keep the closest -- mid-forest trees have
  -- no flat neighbour to vote with, and the commonest-ground fallback
  -- paints pale path under trees whose art sits on grass. Dark unmasked
  -- pixels (the drawn cast shadow) stay out of the score: no ground
  -- tile carries a shadow, and their darks would drag every match.
  local bg = nil
  if groundTiles and #groundTiles > 0 then
    local bestScore = nil
    for _, t in ipairs(groundTiles) do
      local ox = (t % perRow) * 8
      local oy = math.floor(t / perRow) * 8
      local score, n = 0, 0
      for py = 0, N - 1 do
        for px = 0, N - 1 do
          local i = py * N + px
          local c = cls[i]
          if not mask[i] and (c == "light" or c == "white") then
            local ax, ay = texel(px, py)
            local r1, g1, b1 = data:getPixel(ax, ay)
            local r2, g2, b2 = data:getPixel(ox + px % 8, oy + py % 8)
            local dr, dg, db = r1 - r2, g1 - g2, b1 - b2
            score = score + dr * dr + dg * dg + db * db
            n = n + 1
          end
        end
      end
      if n > 0 then
        score = score / n
        if not bestScore or score < bestScore then bestScore, bg = score, t end
      end
    end
  end

  -- discs: per mask pixel a z chord [z0, z1), from its row's span circle
  local z0, z1, src = {}, {}, {}
  local loRow, hiRow = {}, {}
  local yBot = nil
  for iy = 0, N - 1 do
    local lo, hi = nil, nil
    for ix = 0, N - 1 do
      if mask[iy * N + ix] then
        lo = lo or ix
        hi = ix
      end
    end
    if lo then
      loRow[iy], hiRow[iy] = lo, hi
      yBot = iy
      local c = (lo + hi + 1) / 2
      local hw = (hi - lo + 1) / 2
      for ix = lo, hi do
        local i = iy * N + ix
        if mask[i] then
          local dx = ix + 0.5 - c
          local n = 1
          if hw * hw > dx * dx then
            n = math.max(1, math.floor(2 * math.sqrt(hw * hw - dx * dx)
                                       + 0.5))
          end
          z0[i] = math.floor(N2 - n / 2 + 0.5)
          z1[i] = z0[i] + n
          src[i] = iy
        end
      end
    end
  end

  -- foot: rows under the mask repeat the bottom row's discs, wearing the
  -- bottom row's (outline-dark) pixels
  for iy = yBot + 1, N - 1 do
    loRow[iy], hiRow[iy] = loRow[yBot], hiRow[yBot]
    for ix = loRow[yBot], hiRow[yBot] do
      local b = yBot * N + ix
      if z0[b] then
        local i = iy * N + ix
        z0[i], z1[i], src[i] = z0[b], z1[b], yBot
      end
    end
  end

  -- the round cap's top row and z extent, for the stump's ring
  -- projection below
  local capTopRow, capZ0, capZ1 = nil, nil, nil
  if capY0 then
    for iy = 0, N - 1 do
      if loRow[iy] then capTopRow = iy break end
    end
    if capTopRow then
      for ix = loRow[capTopRow], hiRow[capTopRow] do
        local i = capTopRow * N + ix
        if z0[i] then
          capZ0 = math.min(capZ0 or z0[i], z0[i])
          capZ1 = math.max(capZ1 or z1[i], z1[i])
        end
      end
    end
  end

  local function solidAt(ix, iy, iz)
    if ix < 0 or ix > N - 1 or iy < 0 or iy > N - 1 then return false end
    local i = iy * N + ix
    return z0[i] ~= nil and iz >= z0[i] and iz < z1[i]
  end

  -- cap interiors sample the canopy a couple of rows below the rim,
  -- skipping outline-dark pixels
  local function deepTexel(ix, iy)
    for iy2 = iy + 2, math.min(N - 1, iy + 4) do
      local i = iy2 * N + ix
      if mask[i] and cls[i] ~= "black" then return texel(ix, iy2) end
    end
    return texel(ix, iy)
  end

  -- side walls read as material, not outline: walk inward past black
  -- pixels (the building extruder's de-outline rule). The silhouette's
  -- edge columns are all outline, and without this every flank of the
  -- ball paints solid black the moment the camera turns. The foot rows
  -- stay dark on purpose: their whole source row is outline-black.
  local function sideTexel(ix, iy)
    local r = src[iy * N + ix]
    local dir = ix + ix < loRow[iy] + hiRow[iy] and 1 or -1
    for step = 0, 3 do
      local x2 = ix + dir * step
      local i2 = r * N + x2
      if x2 < 0 or x2 > N - 1 or not mask[i2] then break end
      if cls[i2] ~= "black" then return texel(x2, r) end
    end
    return texel(ix, r)
  end

  local quads = {}

  for iy = 0, N - 1 do
    if loRow[iy] then
      local yB, yT = N - 1 - iy, N - iy

      -- front and back: the drawing per-pixel, columns merged where they
      -- share a chord plane; a run never crosses the 8px atlas tile seam
      -- (its u range must interpolate inside one tile)
      local ix = loRow[iy]
      while ix <= hiRow[iy] do
        local i = iy * N + ix
        if z0[i] then
          local ix2 = ix
          while ix2 + 1 <= hiRow[iy] do
            local j = iy * N + ix2 + 1
            if z0[j] == z0[i] and z1[j] == z1[i]
               and math.floor((ix2 + 1) / 8) == math.floor(ix / 8) then
              ix2 = ix2 + 1
            else
              break
            end
          end
          local ax0, ay = texel(ix, src[i])
          local ax1 = (texel(ix2, src[i]))
          local u0, u1 = (ax0 + 0.05) / atlasW, (ax1 + 0.95) / atlasW
          local v0, v1 = (ay + 0.05) / atlasH, (ay + 0.95) / atlasH
          local x0, x1 = ix - N2, ix2 - N2 + 1
          local zF, zB = z1[i] - N2, z0[i] - N2
          quads[#quads + 1] = {
            { x0, yB, zF }, { x1, yB, zF }, { x1, yT, zF }, { x0, yT, zF },
            uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
            shade = ROUND_SHADE.front,
          }
          quads[#quads + 1] = {
            { x1, yB, zB }, { x0, yB, zB }, { x0, yT, zB }, { x1, yT, zB },
            uv = { { u1, v1 }, { u0, v1 }, { u0, v0 }, { u1, v0 } },
            shade = ROUND_SHADE.back,
          }
          ix = ix2 + 1
        else
          ix = ix + 1
        end
      end

      -- sides, steps, undersides: constant-texel quads over the z runs a
      -- neighbour doesn't cover
      for ix = loRow[iy], hiRow[iy] do
        local i = iy * N + ix
        if z0[i] then
          local ax, ay = texel(ix, src[i])
          local u, v = (ax + 0.5) / atlasW, (ay + 0.5) / atlasH
          local x0, x1 = ix - N2, ix - N2 + 1

          -- exposed z pieces against one neighbouring column
          local function pieces(nx, ny, emit)
            local iz = z0[i]
            while iz < z1[i] do
              if not solidAt(nx, ny, iz) then
                local iz2 = iz
                while iz2 + 1 < z1[i] and not solidAt(nx, ny, iz2 + 1) do
                  iz2 = iz2 + 1
                end
                emit(iz - N2, iz2 - N2 + 1, iz, iz2)
                iz = iz2 + 1
              else
                iz = iz + 1
              end
            end
          end

          local sax, say = sideTexel(ix, iy)
          local su, sv = (sax + 0.5) / atlasW, (say + 0.5) / atlasH
          pieces(ix - 1, iy, function(zA, zB)
            quads[#quads + 1] = {
              { x0, yB, zA }, { x0, yB, zB }, { x0, yT, zB }, { x0, yT, zA },
              u = su, v = sv, shade = ROUND_SHADE.side,
            }
          end)
          pieces(ix + 1, iy, function(zA, zB)
            quads[#quads + 1] = {
              { x1, yB, zB }, { x1, yB, zA }, { x1, yT, zA }, { x1, yT, zB },
              u = su, v = sv, shade = ROUND_SHADE.side,
            }
          end)
          pieces(ix, iy - 1, function(zA, zB, izA, izB)
            local function top(za, zb, tu, tv)
              quads[#quads + 1] = {
                { x0, yT, za }, { x1, yT, za }, { x1, yT, zb }, { x0, yT, zb },
                u = tu, v = tv, shade = ROUND_SHADE.top,
              }
            end
            if capTopRow and iy == capTopRow and capZ1 then
              -- the CUT FACE (a capped hull's top): project the drawn
              -- ellipse across the round cap voxel row by voxel row --
              -- its top arc at the cap's north rim, its bottom arc at
              -- the south, the perspective the 2D art already implies
              for iz = izA, izB do
                local t = capZ1 - 1 > capZ0
                          and (iz - capZ0) / (capZ1 - 1 - capZ0) or 0
                local ry = capY0 + math.floor(t * (capY1 - capY0) + 0.5)
                local cax, cay = texel(ix, ry)
                top(iz - N2, iz - N2 + 1,
                    (cax + 0.5) / atlasW, (cay + 0.5) / atlasH)
              end
            elseif izA == z0[i] and izB == z1[i] - 1 and izB - izA >= 2 then
              -- the dome cap: outline on the rim cells, canopy inside
              local du, dv = deepTexel(ix, iy)
              top(zA, zA + 1, u, v)
              top(zA + 1, zB - 1, (du + 0.5) / atlasW, (dv + 0.5) / atlasH)
              top(zB - 1, zB, u, v)
            else
              top(zA, zB, u, v)
            end
          end)
          if iy < N - 1 then
            pieces(ix, iy + 1, function(zA, zB)
              quads[#quads + 1] = {
                { x0, yB, zB }, { x1, yB, zB }, { x1, yB, zA }, { x0, yB, zA },
                u = u, v = v, shade = ROUND_SHADE.bottom,
              }
            end)
          end
        end
      end
    end
  end
  return quads, bg
end

-- Hull templates dedupe GLOBALLY per (tileset, four tiles, ground set):
-- the same four-tile tree repeats for hundreds of cells on a map and
-- across every route of its tileset, so the carve runs once per distinct
-- drawing per session.  What a map keeps is a STAMP LIST -- (template,
-- cell offset) pairs the mesher expands while packing vertices -- rather
-- than materialized per-cell quad tables, which retained ~500 quads x
-- hundreds of tree cells x six Lua tables each PER MAP (the multi-GB
-- heap growth on a cross-region trek).
local roundCache = {}

function Structures.buildCylinders(S, map, x0, x1, y0, y1, groundTiles)
  local data = pixels(map.tileset)
  local tw, th = map.def.width * 4, map.def.height * 4

  -- ground-set fingerprint: the template's art-matched floor depends on
  -- which ground tiles this map places, so maps sharing a tileset but
  -- not a palette of floors carve separately
  local gsig
  do
    local g = {}
    for i, t in ipairs(groundTiles or {}) do g[i] = t end
    table.sort(g)
    gsig = table.concat(g, ",")
  end
  local tsid = tostring(map.tileset.id or map.tileset.image or "?")

  -- the stump class's drawn-ellipse height, hand-authored per tileset
  -- (the profile's stump_cap, in art rows)
  local stumpCap = 6
  do
    local okP, prof = pcall(V.data, "voxel_heights")
    local entry = okP and type(prof) == "table" and prof.tilesets
                  and prof.tilesets[map.tileset.id]
    if entry and type(entry.stump_cap) == "number" then
      stumpCap = entry.stump_cap
    end
  end

  -- cells consumed by a 2x2 `canopy` group; the scan runs north to
  -- south, west to east, so an anchor always claims its partners
  -- before they are visited
  local grouped = {}
  for cy = math.floor(y0 / 2), math.floor(y1 / 2) do
    for cx = math.floor(x0 / 2), math.floor(x1 / 2) do
      Budget.tick()
      local ckey = cy * 8192 + cx
      local k = keyOf(cx * 2, cy * 2)
      local s = (not grouped[ckey]) and S.shapeAt[k] or nil
      local near = cx * 2 >= -ROUND_RING and cx * 2 < tw + ROUND_RING
               and cy * 2 >= -ROUND_RING and cy * 2 < th + ROUND_RING
      if s and s.art == "canopy" and near then
        -- ONE 32px hull over the 2x2-cell drawing. The partner cells
        -- must be round-pinned too, or the drawing is partial (a map
        -- edit, a mod's stray anchor tile) and the anchor is left
        -- alone rather than carved into a half-empty giant.
        local whole = true
        for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
          local ps = S.shapeAt[keyOf((cx + d[1]) * 2, (cy + d[2]) * 2)]
          if not (ps and (ps.art == "cylinder" or ps.art == "canopy")) then
            whole = false
          end
        end
        if whole then
          local ground = false
          if data then
            local ids = {}
            for dy = 0, 3 do
              for dx = 0, 3 do
                ids[#ids + 1] = S.tileAt[keyOf(cx * 2 + dx, cy * 2 + dy)]
              end
            end
            local sig = tsid .. "|g32|" .. gsig .. "|"
                        .. table.concat(ids, ":")
            local tpl = roundCache[sig]
            if not tpl then
              local tq, tbg = roundTemplate(S, map, data, cx, cy,
                                            groundTiles, 32)
              tpl = { quads = tq, bg = tbg }
              roundCache[sig] = tpl
            end
            ground = tpl.bg or false
            S.roundStamps[#S.roundStamps + 1] =
              { quads = tpl.quads, mx = cx * 16 + 16, mz = cy * 16 + 16,
                r = 16 }
          end
          for dy = 0, 3 do
            for dx = 0, 3 do
              local tk = keyOf(cx * 2 + dx, cy * 2 + dy)
              S.skip[tk] = true
              S.ground[tk] = ground
            end
          end
          grouped[ckey + 1] = true
          grouped[ckey + 8192] = true
          grouped[ckey + 8193] = true
        end
      elseif s and s.art == "cylinder" and near then
        -- a `stump`-class cell is the same hull with a cut face: its
        -- top capRows of drawing project onto the round top
        local cap = s.class == "stump" and stumpCap or nil
        local ground = false
        if data then
          local sig = tsid .. (cap and ("|c" .. cap) or "") .. "|"
            .. gsig .. "|" .. table.concat({
            S.tileAt[k], S.tileAt[keyOf(cx * 2 + 1, cy * 2)],
            S.tileAt[keyOf(cx * 2, cy * 2 + 1)],
            S.tileAt[keyOf(cx * 2 + 1, cy * 2 + 1)] }, ":")
          local tpl = roundCache[sig]
          if not tpl then
            local tq, tbg = roundTemplate(S, map, data, cx, cy,
                                          groundTiles, 16, cap)
            tpl = { quads = tq, bg = tbg }
            roundCache[sig] = tpl
          end
          ground = tpl.bg or false
          S.roundStamps[#S.roundStamps + 1] =
            { quads = tpl.quads, mx = cx * 16 + 8, mz = cy * 16 + 8 }
        end
        -- headless (no pixels): no hull, but still claim the tiles so
        -- the volume path never boxes a pinned cell. Ground is the
        -- template's own art-matched tile; `false` (no match, headless)
        -- falls to the commonest-ground pass below.
        for dy = 0, 1 do
          for dx = 0, 1 do
            local tk = keyOf(cx * 2 + dx, cy * 2 + dy)
            S.skip[tk] = true
            S.ground[tk] = ground
          end
        end
      end
    end
  end
end

-- ---- relief props: top-down drawings lying on their surface ----

-- A cell pinned `relief` is a prop DRAWN FROM ABOVE (a game console on
-- the floor): standing it up would be wrong, and a solid box would carry
-- the drawn floor around it.  The drawing is segmented like any forced
-- prop (black outline; the shades touching the cluster's edge are the
-- background) and the object pixels extrude straight up a few voxels,
-- art on the top face -- a piece of the drawing pushed out of the
-- ground.  The floor the flood removed is repainted by the claimed
-- tiles' common-ground fill.
local RELIEF_SHADE = { top = 1.0, south = 0.9, north = 0.62, side = 0.75 }

function Structures.buildRelief(S, map, region, data, perRow, h)
  local atlasW = map.tileset.imageWidth or 128
  local atlasH = map.tileset.imageHeight or 48
  local bw = (region.maxX - region.minX + 1) * 8
  local bh = (region.maxY - region.minY + 1) * 8
  local member = {}
  for _, c in ipairs(region.tiles) do member[keyOf(c[1], c[2])] = true end

  local cls, srcU, srcV = {}, {}, {}
  for py = 0, bh - 1 do
    for px = 0, bw - 1 do
      local i = py * bw + px
      local k = keyOf(region.minX + math.floor(px / 8),
                      region.minY + math.floor(py / 8))
      if member[k] then
        local tile = S.tileAt[k]
        local ax = (tile % perRow) * 8 + px % 8
        local ay = math.floor(tile / perRow) * 8 + py % 8
        srcU[i], srcV[i] = ax, ay
        local r, g, b, a = data:getPixel(ax, ay)
        cls[i] = a == 0 and "off" or Structures.shadeClass(math.min(r, g, b))
      end
    end
  end

  local bg = {}
  for py = 0, bh - 1 do
    for px = 0, bw - 1 do
      if px == 0 or px == bw - 1 or py == 0 or py == bh - 1 then
        local c = cls[py * bw + px]
        if c and c ~= "black" and c ~= "off" then bg[c] = true end
      end
    end
  end

  local flooded, queue = {}, {}
  local function seed(i)
    local c = cls[i]
    if c and c ~= "black" and (c == "off" or bg[c]) and not flooded[i] then
      flooded[i] = true
      queue[#queue + 1] = i
    end
  end
  for px = 0, bw - 1 do
    seed(px)
    seed((bh - 1) * bw + px)
  end
  for py = 0, bh - 1 do
    seed(py * bw)
    seed(py * bw + bw - 1)
  end
  while #queue > 0 do
    local i = table.remove(queue)
    local px, py = i % bw, math.floor(i / bw)
    for _, d in ipairs(DIRS4) do
      local nx, ny = px + d[1], py + d[2]
      if nx >= 0 and nx < bw and ny >= 0 and ny < bh then
        seed(ny * bw + nx)
      end
    end
  end

  local function on(px, py)
    if px < 0 or px >= bw or py < 0 or py >= bh then return false end
    local i = py * bw + px
    return cls[i] ~= nil and cls[i] ~= "off" and not flooded[i]
  end

  local quads = S.objectQuads
  local wx0, wz0 = region.minX * 8, region.minY * 8
  for py = 0, bh - 1 do
    for px = 0, bw - 1 do
      if on(px, py) then
        local i = py * bw + px
        local u = (srcU[i] + 0.5) / atlasW
        local v = (srcV[i] + 0.5) / atlasH
        local x, z = wx0 + px, wz0 + py
        local function quad(c1, c2, c3, c4, shade)
          quads[#quads + 1] = { c1, c2, c3, c4, u = u, v = v, shade = shade }
        end
        quad({ x, h, z }, { x + 1, h, z }, { x + 1, h, z + 1 },
             { x, h, z + 1 }, RELIEF_SHADE.top)
        if not on(px, py + 1) then
          quad({ x, 0, z + 1 }, { x + 1, 0, z + 1 }, { x + 1, h, z + 1 },
               { x, h, z + 1 }, RELIEF_SHADE.south)
        end
        if not on(px, py - 1) then
          quad({ x + 1, 0, z }, { x, 0, z }, { x, h, z },
               { x + 1, h, z }, RELIEF_SHADE.north)
        end
        if not on(px - 1, py) then
          quad({ x, 0, z }, { x, 0, z + 1 }, { x, h, z + 1 },
               { x, h, z }, RELIEF_SHADE.side)
        end
        if not on(px + 1, py) then
          quad({ x + 1, 0, z + 1 }, { x + 1, 0, z }, { x + 1, h, z },
               { x + 1, h, z + 1 }, RELIEF_SHADE.side)
        end
      end
    end
  end
end

-- ---- bookcases: free-standing shelves collapsed to true depth ----

-- A drawn bookcase is TALL, not deep: the graphic spans two cell rows
-- because the shelf is 32px high, while the object stands one cell
-- (16px) deep.  Columns of tiles pinned `bookcase` collapse in ranks
-- (at most four drawn rows each, measured from the south): every rank
-- raises one box over its front two tile rows -- the drawing folded up
-- its south face band by band -- and its back rows become hidden floor.
-- When the row just above a rank is undetected structure (a shared trim
-- tile the profile cannot pin), the rank adopts it as its CAP: one more
-- band of height and the art its top face wears.
local BOOK_SHADE = { south = 1.0, north = 0.68, flank = 0.8, top = 0.85 }

local function bookcaseRank(S, map, tx, northTy, frontTy, capTile)
  local quads = S.objectQuads
  local perRow = map.tileset.tilesPerRow or 16
  local atlasW = map.tileset.imageWidth or 128
  local atlasH = map.tileset.imageHeight or 48
  local function uvRect(tile)
    local ax = (tile % perRow) * 8
    local ay = math.floor(tile / perRow) * 8
    return (ax + 0.5) / atlasW, (ax + 7.5) / atlasW,
           (ay + 0.5) / atlasH, (ay + 7.5) / atlasH
  end

  local size = frontTy - northTy + 1
  local bands = size + (capTile and 1 or 0)
  local h = bands * 8
  local depth = math.min(2, size) * 8
  local x0, x1 = tx * 8, tx * 8 + 8
  local z1 = frontTy * 8 + 8
  local z0 = z1 - depth

  -- does the neighbouring column continue this shelf? (flanks only cap
  -- the ends of a run of bookcases standing side by side)
  local function joined(nx)
    local ns = S.shapeAt[keyOf(nx, frontTy)]
    return ns ~= nil and ns.art == "bookcase"
  end

  for band = 0, bands - 1 do
    local tile = band < size and map:tileAt(tx, frontTy - band) or capTile
    local u0, u1, v0, v1 = uvRect(tile)
    local y0, y1 = band * 8, band * 8 + 8
    quads[#quads + 1] = { { x0, y0, z1 }, { x1, y0, z1 },
      { x1, y1, z1 }, { x0, y1, z1 },
      uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
      shade = BOOK_SHADE.south }
    quads[#quads + 1] = { { x1, y0, z0 }, { x0, y0, z0 },
      { x0, y1, z0 }, { x1, y1, z0 },
      uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
      shade = BOOK_SHADE.north }
    if not joined(tx - 1) then
      quads[#quads + 1] = { { x0, y0, z0 }, { x0, y0, z1 },
        { x0, y1, z1 }, { x0, y1, z0 },
        uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
        shade = BOOK_SHADE.flank }
    end
    if not joined(tx + 1) then
      quads[#quads + 1] = { { x1, y0, z1 }, { x1, y0, z0 },
        { x1, y1, z0 }, { x1, y1, z1 },
        uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
        shade = BOOK_SHADE.flank }
    end
  end

  local topTile = capTile or map:tileAt(tx, northTy)
  local u0, u1, v0, v1 = uvRect(topTile)
  for seg = 0, depth / 8 - 1 do
    local sz0 = z0 + seg * 8
    quads[#quads + 1] = { { x0, h, sz0 }, { x1, h, sz0 },
      { x1, h, sz0 + 8 }, { x0, h, sz0 + 8 },
      uv = { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } },
      shade = BOOK_SHADE.top }
  end
end

function Structures.buildBookcases(S, map, x0, x1, y0, y1)
  -- What to do with the rows a rank VACATES (see TileShape.bookcaseBackfill).
  -- Read once: it is a property of the tileset, not of the column.
  local backfill = TileShape.bookcaseBackfill(map.tileset.id)
  for tx = x0, x1 do
    local ty = y1
    while ty >= y0 do
      local s = S.shapeAt[keyOf(tx, ty)]
      if s and s.art == "bookcase" then
        -- the contiguous pinned run above this front row
        local north = ty
        while north > y0 do
          local ns = S.shapeAt[keyOf(tx, north - 1)]
          if ns and ns.art == "bookcase" then north = north - 1 else break end
        end
        -- ranks of at most four drawn rows, southmost first
        local front = ty
        while front >= north do
          local top = math.max(north, front - 3)
          -- adopt the trim row just above as the cap: either undetected
          -- structure the profile could not pin, or a row pinned `table`
          -- because the same trim tiles cap other furniture too
          local capTile = nil
          if top == north then
            local ck = keyOf(tx, north - 1)
            local cs = S.shapeAt[ck]
            if cs and not cs.flat and not S.skip[ck] and not S.runs[ck]
               and (not cs.authored or cs.class == "table") then
              capTile = S.tileAt[ck]
            end
          end
          -- The box is one cell deep, so it covers only the run's southmost
          -- rows; everything north of that is vacated.  By default a vacated
          -- row is skipped and painted with synthesized ground -- right for a
          -- shelf standing in a room.  `bookcase_backfill = "above"` hands it
          -- the cell above the run instead, shape and art, so a wall cut into
          -- a terrace has more terrace behind it rather than a trench.
          local covered = math.min(2, front - top + 1)
          local srcK = keyOf(tx, top - 1)
          local src = backfill == "above" and S.shapeAt[srcK] or nil
          for cy = top, front do
            local tk = keyOf(tx, cy)
            if src and cy <= front - covered then
              S.shapeAt[tk] = src
              S.tileAt[tk] = S.tileAt[srcK]
            else
              S.skip[tk] = true
              S.ground[tk] = false
            end
          end
          bookcaseRank(S, map, tx, top, front, capTile)
          front = top - 1
        end
        ty = north - 1
      else
        ty = ty - 1
      end
    end
  end
end

-- ---- stairs: pinned cells that render as real steps ----

-- A cell the profile pins stair_e / stair_w (art "stair") becomes a
-- flight of STAIR_STEPS boxes rising evenly across the cell toward the
-- named side, each the full cell deep.  stair_down_e / stair_down_w is
-- the same flight EXCAVATED: the cell opens into a stairwell and the
-- steps descend below floor level toward the named side -- the shape a
-- staircase leading down a floor actually has.  The 2D staircase is
-- drawn from the side, so vertical faces (step fronts and stairwell
-- walls) wear the matching slice of that drawing -- the railing's
-- diagonal lands along the stepped silhouette -- while treads sample the
-- art band drawn at their own height.
local STAIR_STEPS = 4

local STAIR_SHADE = { south = 1.0, north = 0.68, tread = 1.0,
                      riser = 0.82, cap = 0.78,
                      wellN = 0.9, wellS = 0.55, wellEnd = 0.15,
                      wellTread = 0.8 }

local function stairCell(S, map, data, cx, cy, s)
  local perRow = map.tileset.tilesPerRow or 16
  local atlasW = map.tileset.imageWidth or 128
  local atlasH = map.tileset.imageHeight or 48
  local quads = S.objectQuads
  local down = s.class == "stair_down_e" or s.class == "stair_down_w"
  local east = s.class == "stair_e" or s.class == "stair_down_e"
  local mx, mz = cx * 16, cy * 16
  local h = s.h or 16
  local rise = h / STAIR_STEPS
  local runW = 16 / STAIR_STEPS
  local z0, z1 = mz, mz + 16

  -- cell-space art coords (16x16, row 0 the top) -> atlas uv; callers keep
  -- a quad's range inside one 8px tile so it never samples across a seam
  local function uv(px, py)
    px = math.max(0.05, math.min(15.95, px))
    py = math.max(0.05, math.min(15.95, py))
    local tile = S.tileAt[keyOf(cx * 2 + (px >= 8 and 1 or 0),
                                cy * 2 + (py >= 8 and 1 or 0))]
    return ((tile % perRow) * 8 + px % 8) / atlasW,
           (math.floor(tile / perRow) * 8 + py % 8) / atlasH
  end
  -- corners run bottom-left, bottom-right, top-right, top-left as seen
  -- from outside (the mesher's side convention); art rect in cell space
  local function face(c1, c2, c3, c4, ax0, ay0, ax1, ay1, shade)
    local u0, v0 = uv(ax0, ay0)
    local u1, v1 = uv(ax1, ay1)
    quads[#quads + 1] = { c1, c2, c3, c4,
      uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
      shade = shade }
  end
  -- a vertical face spanning heights [fy0, fy1] wearing art rows
  -- [ay0, ay1], emitted per 8-row art band so no quad crosses the seam
  local function banded(z, ax0, ax1, fy0, fy1, ay0, ay1, shade, flip)
    local scale = (fy1 - fy0) / math.max(ay1 - ay0, 0.001)
    for _, band in ipairs({ { ay0, math.min(8, ay1) },
                            { math.max(ay0, 8), ay1 } }) do
      local a0, a1 = band[1], band[2]
      if a1 > a0 then
        local by1 = fy1 - (a0 - ay0) * scale
        local by0 = fy1 - (a1 - ay0) * scale
        local xa, xb = mx + ax0, mx + ax1
        if flip then
          face({ xb, by0, z }, { xa, by0, z }, { xa, by1, z },
               { xb, by1, z }, ax0, a0, ax1, a1, shade)
        else
          face({ xa, by0, z }, { xb, by0, z }, { xb, by1, z },
               { xa, by1, z }, ax0, a0, ax1, a1, shade)
        end
      end
    end
  end

  for i = 0, STAIR_STEPS - 1 do
    local sx0 = east and (i * runW) or (16 - (i + 1) * runW)
    local sx1 = sx0 + runW
    local x0, x1 = mx + sx0, mx + sx1

    if down then
      -- stairwell: tread i sits (i+1) rises below the floor; the walls
      -- above it are the excavation, wearing the drawing at its depth
      local yTop = -(i + 1) * rise
      local dep = (i + 1) * rise

      face({ x0, yTop, z0 }, { x1, yTop, z0 },
           { x1, yTop, z1 }, { x0, yTop, z1 },
           sx0, dep - 1.4, sx1, dep, STAIR_SHADE.wellTread)

      -- stairwell walls above this tread: north wall faces the camera
      banded(z0, sx0, sx1, yTop, 0, 0, dep, STAIR_SHADE.wellN)
      banded(z1, sx0, sx1, yTop, 0, 0, dep, STAIR_SHADE.wellS, true)

      -- riser dropping to this tread from the shallower step
      local rx = east and x0 or x1
      local ry1 = -i * rise
      local rax = east and (sx0 + 0.1) or (sx1 - 1.3)
      if east then
        face({ rx, yTop, z0 }, { rx, yTop, z1 },
             { rx, ry1, z1 }, { rx, ry1, z0 },
             rax, i * rise, rax + 1.2, dep, STAIR_SHADE.riser)
      else
        face({ rx, yTop, z1 }, { rx, yTop, z0 },
             { rx, ry1, z0 }, { rx, ry1, z1 },
             rax, i * rise, rax + 1.2, dep, STAIR_SHADE.riser)
      end

      -- the deep end: a dark opening under the wall the flight leaves by
      if i == STAIR_STEPS - 1 then
        local px = east and (mx + 16) or mx
        local cax = east and 14.7 or 0.1
        if east then
          face({ px, -h, z1 }, { px, -h, z0 }, { px, 0, z0 }, { px, 0, z1 },
               cax, 0, cax + 1.2, 16, STAIR_SHADE.wellEnd)
        else
          face({ px, -h, z0 }, { px, -h, z1 }, { px, 0, z1 }, { px, 0, z0 },
               cax, 0, cax + 1.2, 16, STAIR_SHADE.wellEnd)
        end
      end
    else
      -- rising flight
      local yTop = (i + 1) * rise
      local py0 = 16 - yTop

      -- south + north faces: the drawn flight sliced at this step's column
      banded(z1, sx0, sx1, 0, yTop, py0, 16, STAIR_SHADE.south)
      banded(z0, sx0, sx1, 0, yTop, py0, 16, STAIR_SHADE.north, true)

      -- tread: the step's top, wearing the art band drawn at its height
      face({ x0, yTop, z0 }, { x1, yTop, z0 },
           { x1, yTop, z1 }, { x0, yTop, z1 },
           sx0, py0, sx1, py0 + 1.4, STAIR_SHADE.tread)

      -- riser: the vertical strip exposed above the previous step
      local rx = east and x0 or x1
      local ry0 = i * rise
      local rax = east and (sx0 + 0.1) or (sx1 - 1.3)
      if east then
        face({ rx, ry0, z0 }, { rx, ry0, z1 },
             { rx, yTop, z1 }, { rx, yTop, z0 },
             rax, 16 - yTop, rax + 1.2, 16 - ry0, STAIR_SHADE.riser)
      else
        face({ rx, ry0, z1 }, { rx, ry0, z0 },
             { rx, yTop, z0 }, { rx, yTop, z1 },
             rax, 16 - yTop, rax + 1.2, 16 - ry0, STAIR_SHADE.riser)
      end

      -- cap the tall end of the flight so it never shows a hole
      if i == STAIR_STEPS - 1 then
        local px = east and (mx + 16) or mx
        local cax = east and 14.7 or 0.1
        if east then
          face({ px, 0, z1 }, { px, 0, z0 }, { px, h, z0 }, { px, h, z1 },
               cax, 0, cax + 1.2, 16, STAIR_SHADE.cap)
        else
          face({ px, 0, z0 }, { px, 0, z1 }, { px, h, z1 }, { px, h, z0 },
               cax, 0, cax + 1.2, 16, STAIR_SHADE.cap)
        end
      end
    end
  end
end

function Structures.buildStairs(S, map, x0, x1, y0, y1)
  local data = pixels(map.tileset)
  for cy = math.floor(y0 / 2), math.floor(y1 / 2) do
    for cx = math.floor(x0 / 2), math.floor(x1 / 2) do
      local s = S.shapeAt[keyOf(cx * 2, cy * 2)]
      if s and s.art == "stair" then
        -- claim the cell whichever way the quads go: the mesher must not
        -- box or floor it.  A rising flight stands on the map's common
        -- floor; a stairwell IS the hole, so nothing is painted under it
        local down = s.class == "stair_down_e" or s.class == "stair_down_w"
        for dy = 0, 1 do
          for dx = 0, 1 do
            local tk = keyOf(cx * 2 + dx, cy * 2 + dy)
            S.skip[tk] = true
            if not down then S.ground[tk] = false end
          end
        end
        if data then stairCell(S, map, data, cx, cy, s) end
      end
    end
  end
end

-- ---- volume mode: per-column runs with real drawn heights ----

-- `tiles` is a list of {tx, ty} forming one region (or what is left of one
-- after object extraction); runs are column-local, heights are measured
-- per column and reconciled per region.
function Structures.buildVolume(S, map, tiles)
  local cols = {}
  for _, c in ipairs(tiles) do
    cols[c[1]] = cols[c[1]] or {}
    cols[c[1]][c[2]] = true
  end

  local runs = {}
  local heightVotes = {}
  local repeatVotes = {}
  for tx, ys in pairs(cols) do
    -- visit each contiguous vertical run in this column
    local sorted = {}
    for y in pairs(ys) do sorted[#sorted + 1] = y end
    table.sort(sorted)
    local i = 1
    while i <= #sorted do
      local north = sorted[i]
      local front = north
      while i + 1 <= #sorted and sorted[i + 1] == front + 1 do
        i = i + 1
        front = sorted[i]
      end
      i = i + 1
      local extent = front - north + 1

      -- the column's own reading: its extent, unless its tile sequence
      -- repeats -- then the repeat period is the drawn unit. Both readings
      -- cap at MAX_ROWS (a long-period repeat is still not one column of
      -- drawing).
      local unit, repeatRead = math.min(extent, MAX_ROWS), false
      if extent > 1 then
        local t0 = map:tileAt(tx, front)
        for k = 1, extent - 1 do
          if map:tileAt(tx, front - k) == t0 then
            unit = math.min(math.max(k, 2), MAX_ROWS)
            repeatRead = true
            break
          end
        end
        -- A one-row TRIM at the column's foot hides a repeat from the
        -- scan above, which anchors at the front tile: a cliff plateau
        -- ends its south edge in a rounded corner tile, the corner
        -- never recurs, and the column read its whole capped extent --
        -- a 48px fin (or a whole tent of them) sticking out of a 16px
        -- mesa on Routes 3 and 4. When the two rows directly above the
        -- front are IDENTICAL, the column is that repeat wearing a trim
        -- foot: one course plus the trim is its drawn unit. Doorway
        -- columns are untouched -- their run answers to the region
        -- (see below) before the unit matters.
        if not repeatRead and extent > 2
           and map:tileAt(tx, front - 1) == map:tileAt(tx, front - 2) then
          unit = 2
          repeatRead = true
        end
      end
      local isDoor = false
      for ty = north, front do
        if S.doorFold[keyOf(tx, ty)] then
          isDoor = true
          break
        end
      end
      local run = { front = front, north = north, extent = extent,
                    unit = unit, fromRepeat = repeatRead, door = isDoor }
      runs[#runs + 1] = { tx = tx, run = run }
      local h = unit * 8
      heightVotes[h] = (heightVotes[h] or 0) + 1
      if repeatRead then repeatVotes[h] = (repeatVotes[h] or 0) + 1 end
    end
  end

  -- region consensus: the dominant height. A column whose reading came
  -- from a repeat adopts it when taller (the column above a doorway
  -- repeats internally but belongs to a 48px house); a column that read
  -- its full extent keeps it (an attached low wing stays low).
  local modeH, modeN = 16, 0
  for h, n in pairs(heightVotes) do
    if n > modeN or (n == modeN and h > modeH) then modeH, modeN = h, n end
  end
  -- whether the region's dominant columns are flat repeats (a cliff
  -- mound's plateau) rather than drawn facades (a house's front)
  local modeRepeat = (repeatVotes[modeH] or 0) * 2 > modeN
  for _, r in ipairs(runs) do
    local run = r.run
    local h = run.unit * 8
    local adopted = false
    local flatDoor = false
    if run.door then
      -- A folded doorway column answers to its region ENTIRELY. Its own
      -- reading spans the door plus everything drawn above it -- a
      -- house's full height when the door is a house's, but a 32px
      -- tower over a 16px plateau when the door is a cave mouth cut
      -- into a cliff mound (Diglett's Cave: the entrance jumped a block
      -- above the mound around it). Height and top both come from the
      -- region: the mode height, roofed like a facade when the mode
      -- columns are drawn facades, flat when they are flat repeats.
      h = modeH
      adopted = not modeRepeat
      flatDoor = modeRepeat
    elseif run.fromRepeat and modeH > h then
      h = modeH
      adopted = true
    end
    -- Outdoors, a structure's top rows are its ROOF: the drawn height
    -- splits into a vertical facade and a slope rising north to the drawn
    -- peak (the mesher builds it; hips close the exposed flanks). Repeat
    -- patterns (a border wall) stay flat-topped -- unless they adopted
    -- their region's height, which means they are part of a building (the
    -- column above a doorway) and roof with it. Total height is always
    -- the drawn height: facade + rise = extent rows * 8.
    --
    -- But only PITCHED roofs slope. Gen 1 draws two kinds: a pitched roof
    -- has distinct ridge and eaves rows (the houses' stripes), while a
    -- flat ROOFTOP (the lab, the mart) repeats one texture tile over the
    -- whole roof area -- and a rooftop tilted into a 48px ramp reads
    -- wrong instantly. Distinct top rows -> slope; repeated -> level top.
    local roofRows = 0
    if S.outdoor and (not run.fromRepeat or adopted) and h >= 16
       and not flatDoor then
      roofRows = math.min(2, math.floor(h / 8) - 1)
      if roofRows > 0 and map:tileAt(r.tx, run.north)
                         == map:tileAt(r.tx, run.north + 1) then
        roofRows = 0
      end
    end
    run.roofRows = roofRows
    run.rise = roofRows * 8
    run.peak = h
    run.h = h - run.rise               -- facade height: what sides build to
    for ty = run.north, run.front do
      S.runs[keyOf(r.tx, ty)] = run
    end
  end
end

-- ---- object mode: per-pixel voxelization of drawn props ----

local OBJ_SHADE = { front = 1.0, back = 0.68, side = 0.78,
                    top = 1.0, bottom = 0.55 }

-- The four GB shades, by a pixel's darkest channel.  Force-mode
-- segmentation reasons in these: black is always outline/object, the
-- other three are background only where they touch the cluster's edge.
function Structures.shadeClass(v)
  if v <= 0.25 then return "black" end
  if v <= 0.55 then return "dark" end
  if v <= 0.85 then return "light" end
  return "white"
end

-- Analyze one region's art against its surroundings, voxelize the
-- sprite-like clusters, and return the tiles that remain for volume mode.
-- `force` (profile-pinned billboards) voxelizes every tile of the region
-- unconditionally -- the pin IS the classification. `force = "opaque"`
-- (the `post` pool) keeps the decree -- every tile is a prop, aprons
-- seed the flood, validation is skipped -- but classifies pixels the way
-- the DETECTOR does (everything non-white is solid) instead of by
-- outline shade: a fence's mid browns are its body, and the outline
-- rule would strip the posts to black skeletons.
function Structures.extractObjects(S, map, region, data, perRow, force)
  local bw = (region.maxX - region.minX + 1) * 8
  local bh = (region.maxY - region.minY + 1) * 8

  local member = {}
  for _, c in ipairs(region.tiles) do member[keyOf(c[1], c[2])] = true end

  -- Image over the region bbox plus a 1px ground apron. Pixel states:
  --   solid   opaque member art (non-white, or white that survives)
  --   cand    member white: background candidate, the flood decides
  --   air     ground the flood may travel: INSIDE the bbox (the gaps
  --           between fence posts), or the SOUTH apron row. This is the
  --           direction the viewer reads background from -- a prop's
  --           white meets the ground at its feet. OUTDOORS the other
  --           aprons are barriers on purpose: a building's roof stripes
  --           touch the grass BEHIND it, and a flood allowed to walk
  --           around the sides would pour in from the north and shred the
  --           roof into misdetected sprite clusters (it did). INDOORS all
  --           four aprons seed: furniture backs onto walls and bottom-row
  --           props meet the void ring, so the south row alone often
  --           cannot reach the background at all -- and there are no
  --           roofs inside to protect.
  --   barrier everything else
  local W, H = bw + 2, bh + 2
  local state = {}
  local srcU, srcV = {}, {}
  for iy = 0, H - 1 do
    for ix = 0, W - 1 do
      Budget.tick()
      local i = iy * W + ix
      local px, py = ix - 1, iy - 1
      local tx = region.minX + math.floor(px / 8)
      local ty = region.minY + math.floor(py / 8)
      local k = keyOf(tx, ty)
      local inside = px >= 0 and px < bw and py >= 0 and py < bh
      -- a forced (pinned) prop floods from every apron even when the
      -- neighbours are solid: the pin itself declares the art a prop
      -- whose whites are background -- a monitor pinned atop its desk has
      -- no flat neighbour anywhere to seed from
      local apron = iy == H - 1
        or ((force or not S.outdoor)
            and (iy == 0 or ix == 0 or ix == W - 1))
      if inside and member[k] then
        local tile = S.tileAt[k]
        local ax = (tile % perRow) * 8 + px % 8
        local ay = math.floor(tile / perRow) * 8 + py % 8
        srcU[i], srcV[i] = ax, ay
        local r, g, b, a = data:getPixel(ax, ay)
        if a == 0 then
          state[i] = "cand"
        elseif force and force ~= "opaque" then
          state[i] = Structures.shadeClass(math.min(r, g, b))
        else
          state[i] = math.min(r, g, b) > 0.83 and "cand" or "solid"
        end
      elseif inside or apron then
        if force then
          -- a pinned prop's surroundings are background BY DECREE -- the
          -- pin declares the drawing a prop even when every neighbour is
          -- solid furniture (a vase boxed in by its table).  Ring pixels
          -- seed the flood outright; interior non-member pixels ("iair")
          -- seed it too but never drain paint whites -- only a white run
          -- reaching the RING is background white.
          state[i] = inside and "iair" or "air"
        else
          local s = S.shapeAt[k]
          state[i] = (s and s.flat and s.class ~= "void") and "air"
                     or "barrier"
        end
      else
        state[i] = "barrier"
      end
    end
  end

  -- Forced (pinned) props are segmented the way the art is authored:
  -- objects wear a BLACK OUTLINE, and the background is whatever shades
  -- actually touch the cluster's edge -- the white floor around a TV,
  -- the grey tabletop around a vase.  Only those shades flood; the
  -- outline, its interior, the drawing's paint whites and anything they
  -- enclose all survive as the object.
  --
  -- The `cutout` pool is STRICTER, per the pure-profile contract: mid
  -- shades are always background (a drawn cast shadow must not ring the
  -- object in brown), and whites flood only along white runs from the
  -- edge -- a background white sheet drains away, but paint whites the
  -- flood could only reach through grey are the object.
  if force and force ~= "opaque" then
    local strict = false
    do
      local fs = S.shapeAt[keyOf(region.tiles[1][1], region.tiles[1][2])]
      strict = fs ~= nil and fs.class == "cutout"
    end
    -- The rim vote reads the shades on the DRAWING'S OWN bounding box, so a
    -- prop whose body reaches its own edge votes itself out. The Center's
    -- potted plants are the case: the pot's olive base is drawn flush on the
    -- bottom row of the block, so "dark" came back as background and every
    -- dark pixel in the whole plant drained with it -- the pots rendered as
    -- hollow black frames while the 2D art has solid olive bodies.
    --
    -- Where the vote misreads the art, the profile can name the background
    -- shades outright (a tileset entry's prop_bg). Keyed BY TILE rather than
    -- per tileset, because the answer is per drawing: the healing consoles'
    -- screens really do stand on a dark wall band and really do need dark
    -- voted out, and the PC really does need light kept.
    local bg = {}
    do
      local named = TileShape.propBg(map.tileset.id)
      if named then
        for _, c in ipairs(region.tiles) do
          local rule = named[S.tileAt[keyOf(c[1], c[2])]]
          if rule then
            for shadeName in pairs(rule) do bg[shadeName] = true end
            break
          end
        end
      end
    end
    if not next(bg) then
      for iy = 0, H - 1 do
        for ix = 0, W - 1 do
          local px, py = ix - 1, iy - 1
          local edge = px == 0 or px == bw - 1 or py == 0 or py == bh - 1
          local st = state[iy * W + ix]
          if edge and (st == "dark" or st == "light" or st == "white") then
            bg[st] = true
          end
        end
      end
      if not (bg.dark or bg.light or bg.white) then bg.white = true end
    end
    for i, st in pairs(state) do
      if strict then
        if st == "dark" or st == "light" then
          state[i] = "cand"
        elseif st == "white" then
          state[i] = "wcand"
        elseif st == "black" then
          state[i] = "solid"
        end
      elseif st == "dark" or st == "light" or st == "white" then
        state[i] = bg[st] and "cand" or "solid"
      elseif st == "black" then
        state[i] = "solid"
      end
    end
  end

  -- flood background in from the ground at the structure's feet
  local flooded = {}
  local queue = {}
  for i, st in pairs(state) do
    if st == "air" or st == "iair" then
      flooded[i] = true
      queue[#queue + 1] = i
    end
  end
  while #queue > 0 do
    Budget.tick()
    local i = table.remove(queue)
    local ix, iy = i % W, math.floor(i / W)
    for _, d in ipairs(DIRS4) do
      local nx, ny = ix + d[1], iy + d[2]
      if nx >= 0 and nx < W and ny >= 0 and ny < H then
        local ni = ny * W + nx
        if not flooded[ni] then
          local ns = state[ni]
          -- "wcand" (a strict cutout's white) drains only along a white
          -- run that reaches the RING: entered from the outer apron or
          -- from another flooded white, never through grey or through
          -- interior air
          if ns == "cand" or ns == "air" or ns == "iair"
             or (ns == "wcand"
                 and (state[i] == "air" or state[i] == "wcand")) then
            flooded[ni] = true
            queue[#queue + 1] = ni
          end
        end
      end
    end
  end

  -- per-tile background ratio -> sprite-like tiles (a pinned billboard is
  -- sprite-like by decree)
  local sprite = {}
  for _, c in ipairs(region.tiles) do
    Budget.tick()
    if force then
      sprite[keyOf(c[1], c[2])] = true
    else
      local bx = (c[1] - region.minX) * 8
      local by = (c[2] - region.minY) * 8
      local bg = 0
      for py = 0, 7 do
        for px = 0, 7 do
          if flooded[(by + py + 1) * W + (bx + px + 1)] then bg = bg + 1 end
        end
      end
      if bg / 64 >= TILE_BG_RATIO then sprite[keyOf(c[1], c[2])] = true end
    end
  end

  -- cluster sprite-like tiles; validate each cluster as one prop
  local leftover, claimed = {}, {}
  local clusterSeen = {}
  for _, c in ipairs(region.tiles) do
    local k = keyOf(c[1], c[2])
    if sprite[k] and not clusterSeen[k] then
      local cluster = { tiles = {}, minX = c[1], maxX = c[1],
                        minY = c[2], maxY = c[2] }
      local queue2 = { c }
      clusterSeen[k] = true
      while #queue2 > 0 do
        local cc = table.remove(queue2)
        cluster.tiles[#cluster.tiles + 1] = cc
        cluster.minX = math.min(cluster.minX, cc[1])
        cluster.maxX = math.max(cluster.maxX, cc[1])
        cluster.minY = math.min(cluster.minY, cc[2])
        cluster.maxY = math.max(cluster.maxY, cc[2])
        for _, d in ipairs(DIRS4) do
          local nk = keyOf(cc[1] + d[1], cc[2] + d[2])
          if sprite[nk] and not clusterSeen[nk] then
            clusterSeen[nk] = true
            queue2[#queue2 + 1] = { cc[1] + d[1], cc[2] + d[2] }
          end
        end
      end
      if Structures.buildObject(S, map, region, cluster,
                                state, flooded, srcU, srcV, W, force) then
        for _, cc in ipairs(cluster.tiles) do
          claimed[keyOf(cc[1], cc[2])] = true
        end
      end
    end
  end

  for _, c in ipairs(region.tiles) do
    if not claimed[keyOf(c[1], c[2])] then leftover[#leftover + 1] = c end
  end
  return leftover
end

-- One sprite-like cluster -> a per-pixel voxel prism, or false when it
-- fails validation (too tall, vertically repeating, too big) and should
-- stay part of the volume.
function Structures.buildObject(S, map, region, cluster,
                                state, flooded, srcU, srcV, W, force)
  local rows = cluster.maxY - cluster.minY + 1
  if not force then
    if rows > OBJECT_MAX_ROWS then return false end

    -- a prop stands ON the ground: somewhere the cluster must meet flat
    -- ground to its south. A cluster carved out of a structure's middle
    -- (roof rows whose whites leaked) fails this and stays in the volume.
    -- Indoors any side will do -- furniture backs onto walls and bottom-row
    -- props meet the void ring, so south alone is too strict.
    local dirs = S.outdoor and { { 0, 1 } } or DIRS4
    local touchesGround = false
    for _, c in ipairs(cluster.tiles) do
      for _, d in ipairs(dirs) do
        local ss = S.shapeAt[keyOf(c[1] + d[1], c[2] + d[2])]
        if ss and ss.flat and ss.class ~= "void" then
          touchesGround = true
          break
        end
      end
      if touchesGround then break end
    end
    if not touchesGround then return false end

    -- a vertically repeating cluster (tree wall edge) is scenery, not a
    -- prop
    local cols = {}
    for _, c in ipairs(cluster.tiles) do
      cols[c[1]] = cols[c[1]] or {}
      cols[c[1]][c[2]] = true
    end
    for tx, ys in pairs(cols) do
      local front = nil
      for y in pairs(ys) do front = math.max(front or y, y) end
      local extent = 0
      while ys[front - extent] do extent = extent + 1 end
      if extent > 1 then
        local t0 = map:tileAt(tx, front)
        for k = 1, extent - 1 do
          if map:tileAt(tx, front - k) == t0 then return false end
        end
      end
    end
  end

  local memberC = {}
  for _, c in ipairs(cluster.tiles) do memberC[keyOf(c[1], c[2])] = true end

  -- solid pixels of this cluster (art minus flooded background)
  local solidPx, count, bgCount = {}, 0, 0
  local bw = (cluster.maxX - cluster.minX + 1) * 8
  local bh = (cluster.maxY - cluster.minY + 1) * 8
  for _, c in ipairs(cluster.tiles) do
    local rx = (c[1] - region.minX) * 8
    local ry = (c[2] - region.minY) * 8
    for py = 0, 7 do
      Budget.tick()
      for px = 0, 7 do
        local i = (ry + py + 1) * W + (rx + px + 1)
        local on = state[i] ~= nil and state[i] ~= "air"
                   and state[i] ~= "iair" and state[i] ~= "barrier"
                   and not flooded[i]
        if on then
          local lx = (c[1] - cluster.minX) * 8 + px
          local ly = (c[2] - cluster.minY) * 8 + py
          solidPx[ly * bw + lx] = i
          count = count + 1
        else
          bgCount = bgCount + 1
        end
      end
    end
  end
  if count == 0 or count > OBJECT_MAX_QUADS then return false end
  if not force and bgCount / (count + bgCount) < CLUSTER_MIN_BG then
    return false
  end

  -- geometry: each solid pixel is one voxel column deep enough to read as
  -- a body, standing at the cluster's south row, base on the ground plane
  local depth = OBJECT_DEPTH
  if force then
    local cs = S.shapeAt[keyOf(cluster.tiles[1][1], cluster.tiles[1][2])]
    depth = (cs and PINNED_DEPTH[cs.class]) or PINNED_DEPTH.billboard
  end
  local wx0 = cluster.minX * 8

  -- A pinned prop drawn directly above an authored box stands ON it -- a
  -- monitor on its desk, a flower pot on the table.  The prism rises from
  -- the box's top with its feet on the box's north row, and the claimed
  -- tiles keep rendering as that box (wearing its plain art) instead of
  -- punching a floor-level hole through it.
  --
  -- Only when the prop's OWN CELL IS BLOCKED, though.  "Is something
  -- drawn above me?" is not the same question as "am I standing on it":
  -- a chair drawn against the north side of a table is above the table's
  -- trim row too, and it was being lifted onto the tabletop -- three
  -- chairs standing on the furniture in Cinnabar's trade room and
  -- Fuchsia's meeting room, with the claimed cells re-tiled as tabletop
  -- so the table marched two rows north with them.  The world already
  -- knows which is which: a thing that sits ON furniture occupies a
  -- blocked cell (you cannot walk through the gym statue, Red's plant,
  -- the PC), while a seat you walk up to is in a walkable one.
  --
  -- FENCE POSTS (the `post` pool, force == "opaque") never take the lift
  -- at all. A post stands in the ground by definition -- it is not a
  -- thing set down on top of something -- and its cell is blocked like
  -- any other post, so the test above cannot tell it apart. Lavender
  -- Town is where it showed: pinning the cliff's slope chain gave the
  -- posts along the cliff edge an authored 16px box to their south, and
  -- they were hoisted to stand on the clifftop instead of the path.
  local baseY, support = 0, nil
  if force and force ~= "opaque" then
    local bs = S.shapeAt[keyOf(cluster.minX, cluster.maxY + 1)]
    local blocked = not map:isWalkableCell(math.floor(cluster.minX / 2),
                                           math.floor(cluster.maxY / 2))
    -- `bookcase` supports as well as `upright`.  A prop drawn above an
    -- authored box stands ON it whatever art the box renders with, and a
    -- stacked box is still a box: the Plateau's gate pilasters carry a
    -- statue on 48 of their tops, and collapsing the pilaster to a stacked
    -- run made every one of them fail this test and drop to ground level.
    if blocked and bs and bs.authored and (bs.h or 0) > 0
       and (bs.art == "upright" or bs.art == "bookcase") then
      baseY, support = bs.h, bs
    end
  end
  local atlasW = map.tileset.imageWidth or 128
  local atlasH = map.tileset.imageHeight or 48
  local quads = S.objectQuads

  local function at(lx, ly)
    if lx < 0 or lx >= bw or ly < 0 or ly >= bh then return nil end
    return solidPx[ly * bw + lx]
  end

  -- Connected components: one cluster can hold several OBJECTS -- two
  -- stools stacked in adjacent cells, a loose leaf beside a vase.  Each
  -- component stands on its own feet (base on the ground or the support
  -- box, never floating at its bbox height) in the depth band of the
  -- tile row its lowest pixel is drawn in, so stacked drawings become
  -- separate standees in their own cells instead of one tower.
  -- 8-connectivity keeps diagonal strokes whole.
  local comp, comps = {}, {}
  for ly = 0, bh - 1 do
    Budget.tick()
    for lx = 0, bw - 1 do
      local idx = ly * bw + lx
      if solidPx[idx] and not comp[idx] then
        local c = { lowY = ly, n = 0 }
        comps[#comps + 1] = c
        local stack = { idx }
        comp[idx] = c
        while #stack > 0 do
          local p = table.remove(stack)
          local px, py = p % bw, math.floor(p / bw)
          c.n = c.n + 1
          if py > c.lowY then c.lowY = py end
          for dy = -1, 1 do
            for dx = -1, 1 do
              local nx, ny = px + dx, py + dy
              if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < bw
                 and ny >= 0 and ny < bh then
                local ni = ny * bw + nx
                if solidPx[ni] and not comp[ni] then
                  comp[ni] = c
                  stack[#stack + 1] = ni
                end
              end
            end
          end
        end
      end
    end
  end
  for _, c in ipairs(comps) do
    c.z0 = cluster.minY * 8 + math.floor(c.lowY / 8) * 8
           + (support and 8 or 0) + (8 - depth) / 2
    c.z1 = c.z0 + depth
  end

  -- A `cutout` or `console` pin is ONE object by contract: keep only
  -- the largest connected drawing.  Loose black scraps -- a cast
  -- shadow's drawn edge, a seam, the vertical rules the surrounding
  -- furniture draws down its own edges -- are background even though
  -- black pixels always survive the shade flood, and this is what
  -- removes them.  Every other pool may hold several objects per
  -- cluster (two stools side by side, a leaf beside a vase), so this
  -- cannot be the default.
  if force then
    local cs = S.shapeAt[keyOf(cluster.tiles[1][1], cluster.tiles[1][2])]
    if cs and (cs.class == "cutout" or cs.class == "console")
       and #comps > 1 then
      local biggest = comps[1]
      for _, c in ipairs(comps) do
        if c.n > biggest.n then biggest = c end
      end
      for idx, c in pairs(comp) do
        if c ~= biggest then solidPx[idx] = nil end
      end
    end
  end

  for ly = 0, bh - 1 do
    Budget.tick()
    for lx = 0, bw - 1 do
      local i = at(lx, ly)
      if i then
        local c = comp[ly * bw + lx]
        local z0, z1 = c.z0, c.z1
        local x, y = wx0 + lx, baseY + c.lowY - ly
        local u = (srcU[i] + 0.5) / atlasW
        local v = (srcV[i] + 0.5) / atlasH
        local function quad(c1, c2, c3, c4, shade)
          quads[#quads + 1] = { c1, c2, c3, c4, u = u, v = v, shade = shade }
        end
        quad({ x, y, z1 }, { x + 1, y, z1 }, { x + 1, y + 1, z1 },
             { x, y + 1, z1 }, OBJ_SHADE.front)
        quad({ x + 1, y, z0 }, { x, y, z0 }, { x, y + 1, z0 },
             { x + 1, y + 1, z0 }, OBJ_SHADE.back)
        if not at(lx, ly - 1) then
          quad({ x, y + 1, z0 }, { x + 1, y + 1, z0 }, { x + 1, y + 1, z1 },
               { x, y + 1, z1 }, OBJ_SHADE.top)
        end
        if y > baseY and not at(lx, ly + 1) then
          quad({ x, y, z1 }, { x + 1, y, z1 }, { x + 1, y, z0 },
               { x, y, z0 }, OBJ_SHADE.bottom)
        end
        if not at(lx - 1, ly) then
          quad({ x, y, z0 }, { x, y, z1 }, { x, y + 1, z1 },
               { x, y + 1, z0 }, OBJ_SHADE.side)
        end
        if not at(lx + 1, ly) then
          quad({ x + 1, y, z1 }, { x + 1, y, z0 }, { x + 1, y + 1, z0 },
               { x + 1, y + 1, z1 }, OBJ_SHADE.side)
        end
      end
    end
  end

  -- the ground the prop stands on: the commonest flat tile touching the
  -- cluster, painted under every cluster tile (the art that was there is
  -- now standing up as the object)
  local votes, best, bestN = {}, nil, 0
  for _, c in ipairs(cluster.tiles) do
    for _, d in ipairs(DIRS4) do
      local nk = keyOf(c[1] + d[1], c[2] + d[2])
      local ns = S.shapeAt[nk]
      if ns and ns.flat and ns.class ~= "void" and not memberC[nk] then
        local t = S.tileAt[nk]
        votes[t] = (votes[t] or 0) + 1
        if votes[t] > bestN then best, bestN = t, votes[t] end
      end
    end
  end
  for _, c in ipairs(cluster.tiles) do
    local k = keyOf(c[1], c[2])
    if support and (support.class == "wall" or support.class == "cliff"
                    or support.art == "bookcase") then
      -- a figure drawn above a FULL-HEIGHT block (the gym statue on its
      -- plinth) is a statue on a pillar with ONE cell of footprint: the
      -- block below already carries the whole base, so the drawn cell
      -- becomes synthesized floor rather than a second block marching
      -- the base backwards. Furniture supports (a monitor on its desk)
      -- keep the box-extension below -- their drawn cell is the
      -- furniture's own upper rows, and floor there would amputate it.
      --
      -- STRUCTURE, not height, decides which: `cliff` and `bookcase` are
      -- full-height blocks like `wall` and belong here, while `desk` is
      -- 24px and still furniture.  The Plateau's statues on stacked
      -- pilasters found this -- taking the furniture branch turned each
      -- statue's own two rows into a 32px box wearing the pilaster's art,
      -- so every one of them stood inside a slab of its own plinth.
      S.skip[k] = true
      S.ground[k] = best
    elseif support then
      -- the claimed tile keeps rendering as the box the prop stands on,
      -- wearing the art its own ROW would have without the drawing (the
      -- trim row stays trim); only when the whole row is the prop does
      -- it fall back to the row below
      S.shapeAt[k] = support
      local src = keyOf(c[1], cluster.maxY + 1)
      for dx = 1, 3 do
        for _, sx in ipairs({ c[1] - dx, c[1] + dx }) do
          local nk = keyOf(sx, c[2])
          local ns = S.shapeAt[nk]
          if not memberC[nk] and ns and ns.authored
             and ns.class == support.class then
            src = nk
            break
          end
        end
        if src ~= keyOf(c[1], cluster.maxY + 1) then break end
      end
      S.tileAt[k] = S.tileAt[src]
    else
      S.skip[k] = true
      S.ground[k] = best
    end
  end
  return true
end

-- ---- figures: a person drawn INTO furniture, cut out and stood up ----

-- One authored figure at one matched position.
--
-- The mask IS the classification: no flood, no shade segmentation, no
-- validation gate.  Every automatic route in this file asks the art where
-- the object ends, and a figure painted into its own furniture has no
-- answer to give -- so the profile answers instead, and this only has to
-- believe it.  Which also means figures build HEADLESS: unlike every
-- other standee here, nothing below reads a pixel.
--
-- A figure is a SPRITE, not a prop.  It gets exactly the treatment
-- SpriteBillboards gives a character: one flat plane of the drawing's own
-- pixels, no thickness, standing at its feet and leaned back by the
-- camera's pitch at draw time so it always reads face-on -- because that
-- is what the artwork is.  A seated man drawn face-on is a 2D icon like
-- every other Gen 1 figure; extruding him into a slab reconstructs a body
-- nobody drew (the ten-voxel version read as a wedge of furniture, and
-- even one voxel showed an edge the sprites never show).
--
-- So the quads are emitted in the card's OWN LOCAL SPACE -- x from the
-- mask's west edge, y from his feet, all at z = 0 -- and the placement
-- (`wx`, `wz`, `y`) rides along for VoxelScene to build the lean matrix
-- from.  One quad per pixel rather than one alpha-keyed texture: the
-- tileset atlas has no alpha to key on, and per-pixel quads cut the exact
-- same silhouette straight out of the live atlas, so every palette bake
-- (SGB, RED++ per-tile groups, a mod's own art) textures him for free.
local function buildFigure(S, map, fig, tx, ty, perRow)
  local bw, bh = fig.w * 8, fig.h * 8

  local function at(lx, ly)
    if lx < 0 or lx >= bw or ly < 0 or ly >= bh then return false end
    return fig.mask[ly * bw + lx] or false
  end

  -- his feet and his west edge: the card's own origin
  local lowY, minX = 0, bw - 1
  for ly = 0, bh - 1 do
    for lx = 0, bw - 1 do
      if at(lx, ly) then
        if ly > lowY then lowY = ly end
        if lx < minX then minX = lx end
      end
    end
  end

  -- He stands ON the furniture he was drawn into -- the same lift a pinned
  -- prop above a pinned box takes (see buildObject), and gated the same
  -- way: a thing set down on furniture occupies a BLOCKED cell, while a
  -- seat you merely walk up to is in a walkable one.
  local baseY = 0
  local bs = S.shapeAt[keyOf(tx, ty + fig.h)]
  local blocked = not map:isWalkableCell(math.floor(tx / 2),
                                         math.floor((ty + fig.h - 1) / 2))
  if blocked and bs and bs.authored and bs.art == "upright"
     and (bs.h or 0) > 0 then
    baseY = bs.h
  end

  local atlasW = map.tileset.imageWidth or 128
  local atlasH = map.tileset.imageHeight or 48
  local quads = {}
  for ly = 0, bh - 1 do
    Budget.tick()
    for lx = 0, bw - 1 do
      if at(lx, ly) then
        local tile = fig.tiles[math.floor(ly / 8) * fig.w
                               + math.floor(lx / 8) + 1]
        local u = ((tile % perRow) * 8 + lx % 8 + 0.5) / atlasW
        local v = (math.floor(tile / perRow) * 8 + ly % 8 + 0.5) / atlasH
        local x, y = lx - minX, lowY - ly
        quads[#quads + 1] = { { x, y, 0 }, { x + 1, y, 0 },
                              { x + 1, y + 1, 0 }, { x, y + 1, 0 },
                              u = u, v = v, shade = 1 }
      end
    end
  end

  -- Where the card stands.  `wz` is the MIDDLE of the tile row his feet are
  -- drawn in, which is the same convention a character card uses (its feet
  -- plane sits at its cell's middle) -- so he sorts against the couch and
  -- against a player walking past exactly the way an NPC standing there
  -- would.
  S.figures[#S.figures + 1] = {
    quads = quads,
    wx = tx * 8 + minX,
    wz = ty * 8 + math.floor(lowY / 8) * 8 + 4,
    y = baseY,
  }

  -- What each covered tile wears now that he is off it.  Only the ART
  -- changes: the couch tiles keep their `counter` box (they ARE the
  -- couch) and the floor tiles he overhung stay flat floor -- the
  -- profile just names the version of each drawing without him in it,
  -- so nothing has to be synthesized or repainted from a neighbour vote.
  for i = 1, #fig.tiles do
    local dx, dy = (i - 1) % fig.w, math.floor((i - 1) / fig.w)
    S.tileAt[keyOf(tx + dx, ty + dy)] = fig.under[i]
  end
end

-- Every authored figure, wherever the map draws it.
--
-- Matched by TILE PATTERN rather than by coordinates: one blockset entry
-- places this couch once in each of the eleven Pokemon Centers (and the
-- Celadon Hotel), so the pattern finds all of them without the profile
-- naming a single map or cell.  The repaint above replaces the pattern's
-- own tiles, so a match can never fire twice on the same drawing.
function Structures.buildFigures(S, map, x0, x1, y0, y1)
  local figures = TileShape.figures(map.tileset.id)
  if not figures then return end
  local perRow = map.tileset.tilesPerRow or 16
  for _, fig in ipairs(figures) do
    for ty = y0, y1 - fig.h + 1 do
      for tx = x0, x1 - fig.w + 1 do
        Budget.tick()
        local hit = true
        for i = 1, #fig.tiles do
          local dx, dy = (i - 1) % fig.w, math.floor((i - 1) / fig.w)
          if S.tileAt[keyOf(tx + dx, ty + dy)] ~= fig.tiles[i] then
            hit = false
            break
          end
        end
        if hit then buildFigure(S, map, fig, tx, ty, perRow) end
      end
    end
  end
end

-- ---- tall grass ----

-- A tall-grass CELL is four tufts: 2x2 tiles, and each 8x8 tile is one
-- whole clump of grass. Each tile stands as its own thin per-pixel slab
-- at ITS OWN depth -- the cell's north tile row in the north half of the
-- cell, the south row in the south half -- over the flat grass base the
-- tile already renders. So the player walks BETWEEN the two rows, and
-- the southern row occludes their feet the way the 2D grass overdraw
-- did. Transparency respected: only the tuft strokes stand. Runs of
-- adjacent pixels merge into single quads, and one template per grass
-- tile id is stamped across the map (grass comes in fields).
--
-- One tile is ONE standing piece, full height. The first cut split each
-- tile again into its top and bottom four art rows and stood those at
-- two different depths, which cut every blade that runs down the tile
-- clean in half -- the two halves ended up 4px tall and 4px apart in
-- depth, so a clump read as two stubs rather than one tuft.
local GRASS_THICK = 2

local function grassTemplate(map, data, tileId)
  local perRow = map.tileset.tilesPerRow or 16
  local atlasW = map.tileset.imageWidth or 128
  local atlasH = map.tileset.imageHeight or 48
  local ax0 = (tileId % perRow) * 8
  local ay0 = math.floor(tileId / perRow) * 8

  local function opaque(px, py)
    if px < 0 or px > 7 or py < 0 or py > 7 then return false end
    local r, g, b, a = data:getPixel(ax0 + px, ay0 + py)
    return a > 0 and math.min(r, g, b) <= 0.83
  end

  local quads = {}
  -- the slab stands across the middle of its own tile, so the two tile
  -- rows of a cell are half a cell apart in depth
  local zMid = 4
  local zB, zF = zMid - GRASS_THICK / 2, zMid + GRASS_THICK / 2
  for iy = 0, 7 do
    local yTop = 8 - iy
    local yBot = yTop - 1
    local ix = 0
    while ix < 8 do
      if opaque(ix, iy) then
        local ix2 = ix
        while ix2 + 1 < 8 and opaque(ix2 + 1, iy) do
          ix2 = ix2 + 1
        end
        local u0 = (ax0 + ix + 0.05) / atlasW
        local u1 = (ax0 + ix2 + 0.95) / atlasW
        local v0 = (ay0 + iy + 0.05) / atlasH
        local v1 = (ay0 + iy + 0.95) / atlasH
        quads[#quads + 1] = {           -- front
          { ix, yBot, zF }, { ix2 + 1, yBot, zF },
          { ix2 + 1, yTop, zF }, { ix, yTop, zF },
          uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
          shade = 1,
        }
        quads[#quads + 1] = {           -- back
          { ix2 + 1, yBot, zB }, { ix, yBot, zB },
          { ix, yTop, zB }, { ix2 + 1, yTop, zB },
          uv = { { u1, v1 }, { u0, v1 }, { u0, v0 }, { u1, v0 } },
          shade = 0.68,
        }
        -- blade tips: a top strip where the row above is clear
        if not opaque(ix, iy - 1) then
          quads[#quads + 1] = {
            { ix, yTop, zB }, { ix2 + 1, yTop, zB },
            { ix2 + 1, yTop, zF }, { ix, yTop, zF },
            uv = { { u0, v0 }, { u1, v0 }, { u1, v0 }, { u0, v0 } },
            shade = 1,
          }
        end
        ix = ix2 + 1
      else
        ix = ix + 1
      end
    end
  end
  return quads
end

function Structures.buildGrass(S, map, x0, x1, y0, y1, data)
  local templates = {}
  local quads = S.grassQuads
  for ty = y0, y1 do
    for tx = x0, x1 do
      Budget.tick()
      local k = keyOf(tx, ty)
      local s = S.shapeAt[k]
      -- tufts only where the CELL is tall grass by the engine's own rule
      -- (isGrassCell: the cell's collision tile). The grass GRAPHIC also
      -- appears as decorative filler inside ordinary ground blocks, and a
      -- tile-level test sprouted tufts all over town plazas.
      if s and s.art == "grass"
         and map:isGrassCell(math.floor(tx / 2), math.floor(ty / 2)) then
        local tileId = S.tileAt[k]
        local tpl = templates[tileId]
        if not tpl then
          tpl = grassTemplate(map, data, tileId)
          templates[tileId] = tpl
        end
        local wx, wz = tx * 8, ty * 8
        for _, q in ipairs(tpl) do
          quads[#quads + 1] = {
            { q[1][1] + wx, q[1][2], q[1][3] + wz },
            { q[2][1] + wx, q[2][2], q[2][3] + wz },
            { q[3][1] + wx, q[3][2], q[3][3] + wz },
            { q[4][1] + wx, q[4][2], q[4][3] + wz },
            uv = q.uv, shade = q.shade,
          }
        end
      end
    end
  end
end

-- ---- flowers ----

-- The animated flower tile stands up as a billboard ONE VOXEL deep, cut
-- to the drawing's darkest tones PLUS everything they enclose -- the
-- round-scenery hull's rule: flood the tile border through every
-- non-dark pixel, and what the flood cannot reach is the flower, its
-- pale petal insides included. The mesh is static and the flower is
-- not, so the geometry spans the UNION of that mask over the base art
-- and every animation frame, and TerrainAtlas rewrites the tile's slot
-- each step with only the CURRENT frame's mask opaque -- the rest keyed
-- to alpha, which the voxel shader discards. The standing silhouette
-- trims itself frame by frame in texture space; the sway animates
-- without a vertex moving, off the same engine clock as the flat path.
--
-- The ground beneath is synthesized from the commonest flat neighbour,
-- like the ground under a detected prop: the tile's own slot no longer
-- holds art anyone can draw flat.
local FLOWER_THICK = 1

local function flowerFrames(tileset, tileId)
  local out = {}
  local ok, declared = pcall(function()
    if tileset.animatedTiles then return tileset.animatedTiles end
    local TileRenderer = require("src.render.TileRenderer")
    return TileRenderer.defaultAnimatedTiles(tileset)
  end)
  if not ok then return out end
  for _, spec in ipairs(type(declared) == "table" and declared or {}) do
    if spec.kind == "frames" and spec.tile == tileId then
      for _, path in pairs(spec.images or {}) do
        local okF, frame = pcall(Assets.imageData, path)
        if okF and frame then out[#out + 1] = frame end
      end
    end
  end
  return out
end

local function flowerTemplate(map, data, tileId)
  local tileset = map.tileset
  local perRow = tileset.tilesPerRow or 16
  local atlasW = tileset.imageWidth or 128
  local atlasH = tileset.imageHeight or 48
  local ax0 = (tileId % perRow) * 8
  local ay0 = math.floor(tileId / perRow) * 8

  -- per image: dark tones, then the border flood that finds what they
  -- enclose. Each image closes over ITS OWN outline before the union --
  -- a pocket two frames only enclose together is not part of either.
  local dark = {}
  local function markMask(img, ox, oy)
    local d, reach, stack = {}, {}, {}
    for py = 0, 7 do
      for px = 0, 7 do
        local r, g, b, a = img:getPixel(ox + px, oy + py)
        if a > 0 and math.min(r, g, b) <= 0.5 then
          d[py * 8 + px] = true
        end
      end
    end
    for i = 0, 7 do
      for _, s in ipairs({ i, 56 + i, i * 8, i * 8 + 7 }) do
        if not d[s] and not reach[s] then
          reach[s] = true
          stack[#stack + 1] = s
        end
      end
    end
    while #stack > 0 do
      local p = table.remove(stack)
      local px, py = p % 8, math.floor(p / 8)
      for _, dir in ipairs(DIRS4) do
        local nx, ny = px + dir[1], py + dir[2]
        if nx >= 0 and nx < 8 and ny >= 0 and ny < 8 then
          local ni = ny * 8 + nx
          if not d[ni] and not reach[ni] then
            reach[ni] = true
            stack[#stack + 1] = ni
          end
        end
      end
    end
    for i = 0, 63 do
      if d[i] or not reach[i] then dark[i] = true end
    end
  end
  markMask(data, ax0, ay0)
  for _, frame in ipairs(flowerFrames(tileset, tileId)) do
    pcall(markMask, frame, 0, 0)
  end

  local function on(px, py)
    if px < 0 or px > 7 or py < 0 or py > 7 then return false end
    return dark[py * 8 + px] == true
  end

  local quads = {}
  local zB = 4 - FLOWER_THICK / 2      -- one slab at the tile's middle
  local zF = zB + FLOWER_THICK
  for py = 0, 7 do
    Budget.tick()
    local yTop, yBot = 8 - py, 7 - py
    local ix = 0
    while ix < 8 do
      if on(ix, py) then
        local ix2 = ix
        while ix2 + 1 < 8 and on(ix2 + 1, py) do ix2 = ix2 + 1 end
        local u0 = (ax0 + ix + 0.05) / atlasW
        local u1 = (ax0 + ix2 + 0.95) / atlasW
        local v0 = (ay0 + py + 0.05) / atlasH
        local v1 = (ay0 + py + 0.95) / atlasH
        quads[#quads + 1] = {           -- front
          { ix, yBot, zF }, { ix2 + 1, yBot, zF },
          { ix2 + 1, yTop, zF }, { ix, yTop, zF },
          uv = { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
          shade = OBJ_SHADE.front,
        }
        quads[#quads + 1] = {           -- back
          { ix2 + 1, yBot, zB }, { ix, yBot, zB },
          { ix, yTop, zB }, { ix2 + 1, yTop, zB },
          uv = { { u1, v1 }, { u0, v1 }, { u0, v0 }, { u1, v0 } },
          shade = OBJ_SHADE.back,
        }
        -- petal tips: a top strip where the row above is clear. The
        -- strip samples its own row's texel, so a tip that is not in
        -- the current frame discards with the face beneath it
        if not on(ix, py - 1) then
          quads[#quads + 1] = {
            { ix, yTop, zB }, { ix2 + 1, yTop, zB },
            { ix2 + 1, yTop, zF }, { ix, yTop, zF },
            uv = { { u0, v0 }, { u1, v0 }, { u1, v0 }, { u0, v0 } },
            shade = OBJ_SHADE.top,
          }
        end
        ix = ix2 + 1
      else
        ix = ix + 1
      end
    end
  end
  return quads
end

function Structures.buildFlowers(S, map, tw, th, x0, x1, y0, y1, data)
  local templates = {}
  -- flowerQuads, not objectQuads: flowers sit on WALKABLE cells, so
  -- their mesh draws after the characters with the character pull
  -- (ChunkMesher's flower mesh) -- terrain-baked they lose the depth
  -- fight against the pulled card whenever the player stands among them
  local quads = S.flowerQuads
  for ty = y0, y1 do
    for tx = x0, x1 do
      Budget.tick()
      local k = keyOf(tx, ty)
      local s = S.shapeAt[k]
      if s and s.art == "flower" then
        -- the tile's atlas slot carries only the standing cutout now, so
        -- EVERY flower position -- ring included -- paints synthesized
        -- ground instead of its own art: the commonest flat neighbour
        -- that is not itself a flower, else the map's commonest ground
        -- (forMap's end-of-build vote resolves the `false`)
        S.skip[k] = true
        local votes, best, bestN = {}, nil, 0
        for _, d in ipairs(DIRS4) do
          local nk = keyOf(tx + d[1], ty + d[2])
          local ns = S.shapeAt[nk]
          if ns and ns.flat and ns.class ~= "void"
             and ns.class ~= "flower" then
            local t = S.tileAt[nk]
            votes[t] = (votes[t] or 0) + 1
            if votes[t] > bestN then best, bestN = t, votes[t] end
          end
        end
        S.ground[k] = best or false

        -- standee BODY only, like grass: standing scenery past a map's
        -- edge would poke into the map next door
        if tx >= 0 and ty >= 0 and tx < tw and ty < th then
          local tileId = S.tileAt[k]
          local tpl = templates[tileId]
          if not tpl then
            tpl = flowerTemplate(map, data, tileId)
            templates[tileId] = tpl
          end
          local wx, wz = tx * 8, ty * 8
          for _, q in ipairs(tpl) do
            quads[#quads + 1] = {
              { q[1][1] + wx, q[1][2], q[1][3] + wz },
              { q[2][1] + wx, q[2][2], q[2][3] + wz },
              { q[3][1] + wx, q[3][2], q[3][3] + wz },
              { q[4][1] + wx, q[4][2], q[4][3] + wz },
              uv = q.uv, shade = q.shade,
            }
          end
        end
      end
    end
  end
end

-- Drop one map's analysis (Cut changed the block layer) or everything.
-- Hull templates key on art content (tileset + tiles), which a block edit
-- cannot change, so only the full drop clears them (atlas reload).
function Structures.invalidate(mapId)
  if mapId then
    cache[mapId] = nil
  else
    cache = {}
    atlasData = {}
    roundCache = {}
    Buildings.invalidate()
  end
end

Assets.register(function() Structures.invalidate() end)

return Structures
