-- Voxel world mode: a building voxelized from its own sprite.
--
-- A Game Boy overworld building is a fake-3D projection that packs several
-- different 3D facings into one flat drawing: the roof is drawn as if seen
-- from above, the facade as if seen face-on, and the sloped ends as
-- diagonal silhouettes. Raising the whole footprint as one box (what the
-- generic volume path does) folds all three into a wall, so a house comes
-- out as a cube wearing its own elevation.
--
-- This module does the other thing: it classifies each BAND of the drawing
-- by the surface it depicts and applies the matching operation per band --
-- the pipeline written up in assets/docs/buidling_to_voxel/. Two rules govern it:
--
--   1. Every visible voxel colour is a real texel of the drawing. Nothing
--      is invented but the geometry the sprite implies and never paints
--      (undersides, the depth behind the facade), and those wear the
--      drawing's own four shades.
--   2. The sprite is ground truth, not the tile grid. The silhouette, the
--      taper rate, the eave height and every window are MEASURED off the
--      pixels; the profile only says which rows are roof and which are
--      facade.
--
-- The pipeline, per template (see data/voxel_heights.lua `buildings`):
--
--   read     composite the building out of the atlas and flood its
--            silhouette in from the border through light pixels only --
--            the black outline and the #555 shading together are the
--            boundary, and a "not black" test eats the shaded flanks.
--   measure  the topmost drawn row of each column IS the roof's elevation
--            profile (the drawn taper is the slope); the facade's panes
--            are the non-black regions its black frames seal off.
--   build    facade rows extrude straight back over the footprint, the
--            awning band juts past them, panes sink one voxel, and the
--            roof lays the top-facing rows flat -- level over the
--            plateau, stepping down the drawn taper at the ends -- then
--            overwrites the walls it intersects.
--   emit     cull to the shell and merge runs of texel-adjacent faces into
--            single quads, so a 90k-voxel house ships as ~2k quads.
--
-- One model is built per template and stamped at every placement: Red's
-- and Blue's houses are the same seven-placement drawing, so they cost one
-- build between them. mods/DRAMATIC_SHAPE/tools/building_voxels.py is the
-- reference implementation of the same algorithm and prints the voxel and
-- shell counts this one must agree with.
--
-- Purely presentational, like everything else in the mod: the tiles a
-- building claims keep the collision, warps and triggers they always had.

-- the mod namespace (see main.lua): V.data loads a shipped data file
local V = ...

local Budget = V.require("BuildBudget")

local Buildings = {}

-- The four GB shades, lightest first (same cutoffs as Structures.shadeClass,
-- which reasons about the same art).
local WHITE, GREY, DARK, BLACK = 0, 1, 2, 3

-- A pane is a window or a doorway: a non-black region the drawing seals
-- off behind its own black frame. Anything wider or taller than this is a
-- band of the facade itself -- a siding course, the awning's grey field --
-- and must stay flush.
local RECESS_MAX = 24

-- Face shades, matching the rest of the mod's objects: the south face is
-- the drawing itself and draws at full brightness.
local SHADE = { top = 0.95, south = 1.0, north = 0.68,
                side = 0.78, bottom = 0.5 }

local function keyOf(tx, ty)
  return (ty + 64) * 4096 + (tx + 64)
end

local function shadeOf(r, g, b, a)
  if a == 0 then return WHITE end
  local v = math.min(r, g, b)
  if v <= 0.25 then return BLACK end
  if v <= 0.55 then return DARK end
  if v <= 0.85 then return GREY end
  return WHITE
end

-- The shape profile ships with the mod; absent or broken simply means no
-- building templates, and every building falls back to the volume path.
local spec = nil
local function profile()
  if spec == nil then
    local ok, s = pcall(V.data, "voxel_heights")
    spec = (ok and type(s) == "table") and s or false
  end
  return spec or nil
end

local models = {}          -- "<tileset>:<index>" -> prebuilt local quads

-- ------------------------------------------------------------------ read --

-- Composite the template out of the atlas and flood the silhouette in from
-- the border. Returns flat arrays indexed y * W + x.
--
-- `topRows`, when a template carries it, is extra drawing rows composited
-- ABOVE the matched grid: rows of the same drawing that are not on the
-- map this template places on. The Pokemon Tower is the case that needs
-- it -- the drawing straddles the LAVENDER_TOWN / ROUTE_10 boundary, its
-- roof band and top window courses standing in the route's last rows, so
-- no single map's grid holds the whole building. The matcher never sees
-- topRows (placement is still by `tiles` alone); they exist so the MODEL
-- is built from the complete drawing and the tower rises to its real
-- height instead of folding as two half-buildings.
local function read(t, data, perRow)
  local tiles = t.tiles
  if t.topRows then
    tiles = {}
    for _, row in ipairs(t.topRows) do tiles[#tiles + 1] = row end
    for _, row in ipairs(t.tiles) do tiles[#tiles + 1] = row end
  end
  local bh, bw = #tiles, #t.tiles[1]
  local W, H = bw * 8, bh * 8
  local col, ax, ay = {}, {}, {}
  for sy = 0, H - 1 do
    Budget.tick()
    local row = tiles[math.floor(sy / 8) + 1]
    for sx = 0, W - 1 do
      local tile = row[math.floor(sx / 8) + 1]
      local px = (tile % perRow) * 8 + sx % 8
      local py = math.floor(tile / perRow) * 8 + sy % 8
      local i = sy * W + sx
      ax[i], ay[i] = px, py
      local r, g, b, a = data:getPixel(px, py)
      col[i] = shadeOf(r, g, b, a)
    end
  end

  local outside = {}
  local queue, n = {}, 0
  local function seed(x, y)
    local i = y * W + x
    if not outside[i] and col[i] <= GREY then
      outside[i] = true
      n = n + 1
      queue[n] = i
    end
  end
  -- The flood comes in from the border, which assumes the drawing is
  -- bounded by its own outline on every side. A drawing trimmed flush to
  -- its art -- one whose base course is a row of brick rather than the
  -- black threshold every other building stands on -- names the sides it
  -- runs off in `seal`, and the flood does not seed there. Without it the
  -- flood climbs in through the light mortar and hollows the wall out.
  local seal = t.seal or ""
  local function sealed(side) return string.find(seal, side, 1, true) ~= nil end
  for x = 0, W - 1 do
    if not sealed("n") then seed(x, 0) end
    if not sealed("s") then seed(x, H - 1) end
  end
  for y = 0, H - 1 do
    if not sealed("w") then seed(0, y) end
    if not sealed("e") then seed(W - 1, y) end
  end
  while n > 0 do
    local i = queue[n]
    n = n - 1
    local x, y = i % W, math.floor(i / W)
    if x + 1 < W then seed(x + 1, y) end
    if x > 0 then seed(x - 1, y) end
    if y + 1 < H then seed(x, y + 1) end
    if y > 0 then seed(x, y - 1) end
  end

  local inside = {}
  for i = 0, W * H - 1 do inside[i] = not outside[i] end
  return { W = W, H = H, col = col, ax = ax, ay = ay, inside = inside }
end

-- --------------------------------------------------------------- measure --

local function measure(sp, t)
  local W, H = sp.W, sp.H
  local roofRows = t.roofRows

  -- The drawn taper IS the slope: the first drawn row of a column is how
  -- far the roof has stepped down by the time it reaches that column.
  local top = {}
  for x = 0, W - 1 do
    local r = roofRows
    for y = 0, roofRows - 1 do
      if sp.inside[y * W + x] then r = y break end
    end
    top[x] = r
  end

  local wallH = H - roofRows
  local ytop = wallH - 1 + t.slab

  -- Side faces must not come out as slabs of outline black: where the
  -- drawing's own pixel is the outline, walk inward for the first painted
  -- colour, which is what the flanks of the real thing would show.
  local interior = {}
  for sy = roofRows, H - 1 do
    for sx = 0, W - 1 do
      local i = sy * W + sx
      local src = i
      if sp.inside[i] and sp.col[i] == BLACK then
        local step = sx < W / 2 and 1 or -1
        for d = 1, 3 do
          local nx = sx + step * d
          if nx >= 0 and nx < W then
            local ni = sy * W + nx
            if sp.inside[ni] and sp.col[ni] ~= BLACK then
              src = ni
              break
            end
          end
        end
      end
      interior[i] = src
    end
  end

  -- Panes: the facade's non-black pixels split into regions across the
  -- black frames, and a region small enough to be a window or a doorway
  -- sinks a voxel. Frames stay proud, so the pane behind them reads as
  -- glass set into the wall -- and a nested frame (the door's own little
  -- window) layers for free.
  local recess, seen = {}, {}
  for sy = roofRows, H - 1 do
    for sx = 0, W - 1 do
      local i0 = sy * W + sx
      if not seen[i0] and sp.inside[i0] and sp.col[i0] ~= BLACK then
        local cells, stack = {}, { i0 }
        seen[i0] = true
        local x0, x1, y0, y1 = sx, sx, sy, sy
        local function step(nx, ny)
          if nx < 0 or nx >= W or ny < roofRows or ny >= H then return end
          local ni = ny * W + nx
          if not seen[ni] and sp.inside[ni] and sp.col[ni] ~= BLACK then
            seen[ni] = true
            stack[#stack + 1] = ni
          end
        end
        while #stack > 0 do
          local i = table.remove(stack)
          cells[#cells + 1] = i
          local cx, cy = i % W, math.floor(i / W)
          if cx < x0 then x0 = cx end
          if cx > x1 then x1 = cx end
          if cy < y0 then y0 = cy end
          if cy > y1 then y1 = cy end
          step(cx + 1, cy)
          step(cx - 1, cy)
          step(cx, cy + 1)
          step(cx, cy - 1)
        end
        if x1 - x0 < RECESS_MAX and y1 - y0 < RECESS_MAX then
          for _, i in ipairs(cells) do recess[i] = true end
        end
      end
    end
  end

  -- One representative texel per shade, taken from the building's own art:
  -- the roof's fascia and its undersides are geometry the drawing implies
  -- but never paints, and they must still wear its palette (and pick up
  -- whatever SGB recolouring the atlas carries).
  local shadeTexel = {}
  for i = 0, sp.W * sp.H - 1 do
    if sp.inside[i] and not shadeTexel[sp.col[i]] then
      shadeTexel[sp.col[i]] = i
    end
  end
  for s = WHITE, BLACK do
    shadeTexel[s] = shadeTexel[s] or shadeTexel[BLACK] or 0
  end

  -- Depth is the MATCHED footprint, not the sprite height. The two are
  -- the same number for every whole-drawing template (the sprite is
  -- built from `tiles` alone), but a template with `topRows` has a
  -- sprite taller than its footprint -- the tower's 16-row drawing
  -- stands on the 8 rows of it that are actually on the map, and D = H
  -- would have pushed its body 64px south into the town plaza.
  return { top = top, ytop = ytop, D = #t.tiles * 8,
           recess = recess, interior = interior, shadeTexel = shadeTexel }
end

-- ----------------------------------------------------------------- build --

-- The voxel model as a lookup: `at(x, y, z)` is the index of the sprite
-- pixel that voxel wears, or nil. Build ORDER is expressed as lookup
-- order -- roof first, so it overwrites the walls it intersects, and walls
-- are trimmed to its underside so nothing pokes through the surface.
local function model(sp, pr, t)
  local W, H, D = sp.W, sp.H, pr.D
  local slab, roofRows = t.slab, t.roofRows
  local top, ytop = pr.top, pr.ytop

  -- The roof's drawn span. A sprite inset from its box (B03) leaves outer
  -- columns undrawn in the roof band; they carry no roof at all, and the
  -- rim treatment belongs to the outermost drawn columns instead of the
  -- box edge.
  local x0d, x1d
  for x = 0, W - 1 do
    if top[x] < roofRows then
      x0d = x0d or x
      x1d = x
    end
  end
  local ledge0, ledge1 = nil, nil
  if t.ledge then ledge0, ledge1 = t.ledge[1], t.ledge[2] end

  local rz0, rz1 = 0, D - 1 + (t.frontEave or 0)
  local back, front = t.roofBack, t.roofFront
  local cyc0, cyc1 = t.roofCycle[1], t.roofCycle[2]
  local cycN = cyc1 - cyc0 + 1

  -- Which drawn row lies at depth z. The drawing looks at the roof from
  -- the north, so its top rows ARE the far edge and its bottom rows the
  -- eave over the facade. The band is shallower than the building, so the
  -- rims map one row per voxel and the middle cycles a run whose period is
  -- the course rhythm -- picked up where the north rim left off, which
  -- continues both the course lines and the roof texture seamlessly.
  local roofSy = {}
  for z = rz0, rz1 do
    local df, db = z - rz0, rz1 - z          -- from the north / south edge
    if df < back then
      roofSy[z] = df
    elseif db < front then
      roofSy[z] = roofRows - 1 - db
    else
      roofSy[z] = cyc0 + (df - cyc0) % cycN
    end
  end

  local T = {}
  for x = 0, W - 1 do T[x] = ytop - top[x] end

  local function at(x, y, z)
    if x < 0 or x >= W then return nil end
    local tx = T[x]

    -- roof: a solid of constant thickness following the elevation profile
    if top[x] < roofRows
        and y > tx - slab and y <= tx and z >= rz0 and z <= rz1 then
      if y == tx and x > x0d and x < x1d and z > rz0 and z < rz1 then
        -- the surface itself. Clamping the row into the column's first
        -- drawn row keeps the flank battens running down the slope
        -- instead of falling off the silhouette.
        local sy = roofSy[z]
        if sy < top[x] then sy = top[x] end
        return sy * W + x
      end
      -- The rim reproduces the eave the drawing itself paints under the
      -- roof: a black outline, a shaded fascia, closed by the outline
      -- again. (A GREY fascia band -- what the first cut had -- comes out
      -- WHITE once the atlas is recoloured and turns every sloped end
      -- into a black-and-white zip.) Under the surface it is all shadow.
      local outer = x == x0d or x == x1d or z == rz0 or z == rz1
      if not outer then return pr.shadeTexel[DARK] end
      if y == tx or y == tx - slab + 1 then return pr.shadeTexel[BLACK] end
      return pr.shadeTexel[DARK]
    end

    -- trimmed: under the slope. A column with no roof over it has no
    -- underside to trim to, and must not be cut away by a profile the
    -- drawing never set.
    if top[x] < roofRows and y > tx - slab then return nil end

    -- the awning: the band juts two voxels past the walls, front and back
    if ledge0 and (z == -2 or z == -1 or z == D or z == D + 1) then
      local sy = H - 1 - y
      if sy >= ledge0 and sy <= ledge1 and sp.inside[sy * W + x] then
        return sy * W + x
      end
      return nil
    end

    -- the facade, extruded straight back over the footprint
    if z < 0 or z >= D then return nil end
    local sy = H - 1 - y
    local i = sy * W + x
    if y == 0 and not sp.inside[i] and sy > 0 and sp.inside[i - W] then
      -- the drawing's last row is the ground the building stands on, so
      -- its base course is one row up; without this the walls float a
      -- voxel over their own plot
      sy, i = sy - 1, i - W
    end
    if not sp.inside[i] then return nil end
    if z == D - 1 then
      if pr.recess[i] then return nil end
      return i
    end
    if z == 0 then return i end
    return pr.interior[i]
  end

  return { at = at, W = W, ytop = ytop,
           zmin = ledge0 and -2 or 0,
           zmax = math.max(rz1, ledge0 and (D + 1) or 0) }
end

-- ------------------------------------------------------------------ emit --

-- Cull to the shell and merge. A run of faces collapses into one quad when
-- its texels are the SAME (a flat-coloured strip, which is most of a side
-- face) or ADJACENT IN THE ATLAS along the run (the drawing continuing
-- across the face, which is most of a front face or a roof top). Both keep
-- every texel exactly where the sprite put it.
local function emit(m, sp, atlasW, atlasH)
  local W = m.W
  local quads = { voxels = 0, shell = 0 }
  local cell = {}                        -- (y, z, x) -> sprite pixel index

  local zmin, zmax, ytop = m.zmin, m.zmax, m.ytop
  local zn = zmax - zmin + 1
  local function ci(x, y, z)
    if x < 0 or x >= W or y < 0 or y > ytop or z < zmin or z > zmax then
      return nil
    end
    return cell[(y * zn + (z - zmin)) * W + x]
  end
  for y = 0, ytop do
    Budget.tick()
    for z = zmin, zmax do
      local base = (y * zn + (z - zmin)) * W
      for x = 0, W - 1 do
        local v = m.at(x, y, z)
        cell[base + x] = v
        if v then quads.voxels = quads.voxels + 1 end
      end
    end
  end
  -- the shell: what survives hidden-face culling. Counted here rather than
  -- derived from the quads because it is the number
  -- tools/building_voxels.py checks this build against.
  for y = 0, ytop do
    Budget.tick()
    for z = zmin, zmax do
      for x = 0, W - 1 do
        if ci(x, y, z) and not (ci(x + 1, y, z) and ci(x - 1, y, z)
            and ci(x, y + 1, z) and ci(x, y - 1, z)
            and ci(x, y, z + 1) and ci(x, y, z - 1)) then
          quads.shell = quads.shell + 1
        end
      end
    end
  end

  -- u/v of a run: `n` texels starting at sprite pixel `i`, stepping along
  -- the atlas when the run is a strip and standing still when it is flat.
  local function uvOf(i, strip, n)
    local x0 = sp.ax[i]
    local y0 = sp.ay[i]
    local x1 = strip and (x0 + n) or (x0 + 1)
    return (x0 + 0.05) / atlasW, (x1 - 0.05) / atlasW,
           (y0 + 0.05) / atlasH, (y0 + 1 - 0.05) / atlasH
  end

  local function put(c1, c2, c3, c4, uv, shade)
    quads[#quads + 1] = { c1, c2, c3, c4, uv = uv, shade = shade }
  end

  -- How far a run of exposed faces reaches from `x`, and whether it is a
  -- strip (texels marching along the atlas) or flat (one texel repeated).
  local function runX(y, z, dx, dy, dz, x)
    local i0 = ci(x, y, z)
    local strip, n = nil, 1
    while true do
      local nx = x + n
      local i = ci(nx, y, z)
      if not i or ci(nx + dx, y + dy, z + dz) then break end
      local prev = ci(nx - 1, y, z)
      if sp.ay[i] ~= sp.ay[prev] then break end
      local d = sp.ax[i] - sp.ax[prev]
      if d == 1 then
        if strip == false then break end
        strip = true
      elseif d == 0 then
        if strip == true then break end
        strip = false
      else
        break
      end
      n = n + 1
    end
    return i0, strip == true, n
  end

  -- ---- faces along +-Z (the facade, the roof's rims): merge along x ----
  for _, d in ipairs({ 1, -1 }) do
    local shade = d == 1 and SHADE.south or SHADE.north
    for y = 0, ytop do
      Budget.tick()
      for z = zmin, zmax do
        local x = 0
        while x < W do
          if ci(x, y, z) and not ci(x, y, z + d) then
            local i, strip, n = runX(y, z, 0, 0, d, x)
            local u0, u1, v0, v1 = uvOf(i, strip, n)
            local zf = d == 1 and (z + 1) or z
            if d == 1 then
              put({ x, y, zf }, { x + n, y, zf },
                  { x + n, y + 1, zf }, { x, y + 1, zf },
                  { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, shade)
            else
              put({ x + n, y, zf }, { x, y, zf },
                  { x, y + 1, zf }, { x + n, y + 1, zf },
                  { { u1, v1 }, { u0, v1 }, { u0, v0 }, { u1, v0 } }, shade)
            end
            x = x + n
          else
            x = x + 1
          end
        end
      end
    end
  end

  -- ---- faces along +-Y (roof surfaces, undersides): merge along x ----
  for _, d in ipairs({ 1, -1 }) do
    local shade = d == 1 and SHADE.top or SHADE.bottom
    for y = 0, ytop do
      Budget.tick()
      -- the underside of the bottom layer is the ground it stands on
      if not (d == -1 and y == 0) then
        for z = zmin, zmax do
          local x = 0
          while x < W do
            if ci(x, y, z) and not ci(x, y + d, z) then
              local i, strip, n = runX(y, z, 0, d, 0, x)
              local u0, u1, v0, v1 = uvOf(i, strip, n)
              local yf = d == 1 and (y + 1) or y
              if d == 1 then
                put({ x, yf, z }, { x + n, yf, z },
                    { x + n, yf, z + 1 }, { x, yf, z + 1 },
                    { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, shade)
              else
                put({ x, yf, z + 1 }, { x + n, yf, z + 1 },
                    { x + n, yf, z }, { x, yf, z },
                    { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, shade)
              end
              x = x + n
            else
              x = x + 1
            end
          end
        end
      end
    end
  end

  -- ---- faces along +-X (the flanks): merge along z, one texel each ----
  for _, d in ipairs({ 1, -1 }) do
    for y = 0, ytop do
      for x = 0, W - 1 do
        local z = zmin
        while z <= zmax do
          local i = ci(x, y, z)
          if i and not ci(x + d, y, z) then
            local n = 1
            while z + n <= zmax do
              local j = ci(x, y, z + n)
              if j ~= i or ci(x + d, y, z + n) then break end
              n = n + 1
            end
            local u0, u1, v0, v1 = uvOf(i, false, n)
            local xf = d == 1 and (x + 1) or x
            if d == 1 then
              put({ xf, y, z + n }, { xf, y, z },
                  { xf, y + 1, z }, { xf, y + 1, z + n },
                  { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                  SHADE.side)
            else
              put({ xf, y, z }, { xf, y, z + n },
                  { xf, y + 1, z + n }, { xf, y + 1, z },
                  { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                  SHADE.side)
            end
            z = z + n
          else
            z = z + 1
          end
        end
      end
    end
  end

  return quads
end

-- ------------------------------------------------------------- placement --

-- Does the template's tile grid sit at (tx, ty)?
local function matches(S, t, tx, ty)
  local tiles = t.tiles
  for r = 1, #tiles do
    local row = tiles[r]
    for c = 1, #row do
      if S.tileAt[keyOf(tx + c - 1, ty + r - 1)] ~= row[c] then
        return false
      end
    end
  end
  return true
end

-- Find every placement of every template for this map's tileset, build one
-- model per template, and stamp it. Returns nothing; the quads land in
-- S.objectQuads and the tiles are claimed so the volume path never boxes a
-- building this module has already modelled.
function Buildings.build(S, map, data, perRow)
  if not data then return end
  local tileset = map.tileset
  local s = profile()
  local list = s and s.buildings and s.buildings[tileset.id]
  if not list then return end

  local atlasW = tileset.imageWidth or 128
  local atlasH = tileset.imageHeight or 48
  local tw, th = map.def.width * 4, map.def.height * 4
  local quads = S.objectQuads

  for index, t in ipairs(list) do
    if type(t.tiles) == "table" and #t.tiles > 0 then
      local bh, bw = #t.tiles, #t.tiles[1]
      local first = t.tiles[1][1]
      local built = nil
      for ty = 0, th - bh do
        Budget.tick()
        for tx = 0, tw - bw do
          -- A placement never stamps into cells another template already
          -- claimed. Templates are matched independently, and one
          -- drawing can satisfy two grids: the Pokemon Tower's upper
          -- twelve rows on ROUTE_10 are a standard 6-cell block tile for
          -- tile, so `gabled_block_6x6` matched there and stood a whole
          -- second building behind the tower. First claim wins, so the
          -- list order below is the priority order -- the tower's own
          -- templates come first precisely so they take those cells.
          local free = S.tileAt[keyOf(tx, ty)] == first
          if free then
            for r = 0, bh - 1 do
              for c = 0, bw - 1 do
                if S.skip[keyOf(tx + c, ty + r)] then
                  free = false
                  break
                end
              end
              if not free then break end
            end
          end
          if free and matches(S, t, tx, ty) then
            if not built then
              local key = tileset.id .. ":" .. index
              if not models[key] then
                if t.claimOnly then
                  -- claim the cells, stamp nothing: the drawing here is
                  -- the off-map half of a building another map models in
                  -- full (the tower's roof rows on ROUTE_10 -- Lavender's
                  -- placement composites them via topRows). Left to the
                  -- detector they stood as a second half-building.
                  models[key] = {}
                else
                  local sp = read(t, data, perRow)
                  local pr = measure(sp, t)
                  models[key] = emit(model(sp, pr, t), sp, atlasW, atlasH)
                end
              end
              built = models[key]
            end
            Buildings.stamp(S, map, built, tx, ty, bw, bh)
          end
        end
      end
    end
  end
end

-- One placement: claim its tiles (so the detector leaves them alone and
-- the mesher paints ground under them) and copy the model into place.
function Buildings.stamp(S, map, quads, tx, ty, bw, bh)
  local shape = { class = "building", h = 0, art = "building",
                  flat = false, authored = true }

  -- the ground the building stands on: the commonest flat tile around its
  -- feet, so a house on a path keeps its path
  local votes, best, bestN = {}, nil, 0
  local function vote(x, y)
    local k = keyOf(x, y)
    local ns = S.shapeAt[k]
    if ns and ns.flat and ns.class ~= "void" then
      local tile = S.tileAt[k]
      votes[tile] = (votes[tile] or 0) + 1
      if votes[tile] > bestN then best, bestN = tile, votes[tile] end
    end
  end
  for c = 0, bw - 1 do
    vote(tx + c, ty - 1)
    vote(tx + c, ty + bh)
  end
  for r = 0, bh - 1 do
    vote(tx - 1, ty + r)
    vote(tx + bw, ty + r)
  end

  for r = 0, bh - 1 do
    for c = 0, bw - 1 do
      local k = keyOf(tx + c, ty + r)
      S.shapeAt[k] = shape
      S.skip[k] = true
      S.ground[k] = best or false
    end
  end

  local mx, mz = tx * 8, ty * 8
  local out = S.objectQuads
  for _, q in ipairs(quads) do
    out[#out + 1] = {
      { q[1][1] + mx, q[1][2], q[1][3] + mz },
      { q[2][1] + mx, q[2][2], q[2][3] + mz },
      { q[3][1] + mx, q[3][2], q[3][3] + mz },
      { q[4][1] + mx, q[4][2], q[4][3] + mz },
      uv = q.uv, shade = q.shade,
      -- placements only ever scan the BODY, so a building is always this
      -- map's own structure: the mesher's edge keep-rules must not eat
      -- the parts that poke past the boundary (an edge-row house's eave
      -- juts frontEave voxels into the neighbour's airspace, and the
      -- neighbour-body mask read that overhang as a ring scrap -- which
      -- opened the roof rim into the sky from across the seam)
      own = true,
    }
  end
end

-- What the models built so far cost, keyed "<tileset>:<index>": the voxel
-- and shell counts tools/building_voxels.py checks this implementation
-- against (Stage 5 of the methodology), and the quad count that ships.
function Buildings.stats()
  local out = {}
  for key, quads in pairs(models) do
    out[key] = { voxels = quads.voxels, shell = quads.shell,
                 quads = #quads }
  end
  return out
end

-- Drop the prebuilt models (hot reload, or a mod shadowing the profile).
function Buildings.invalidate()
  spec = nil
  models = {}
end

return Buildings
