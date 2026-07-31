-- Voxel world mode: the shape PROFILE -- hand-authored pins over the
-- automatic structure detector, the way a 3dSen game profile pins a
-- graphic to a geometry type.
--
-- Hand-authored by this mod, and read only from here: unlike the tables the
-- ROM extractor writes into the player's own cache, nothing below is
-- extracted, derived or copied from the ROM.
-- Nothing here reaches gameplay, collision or scripts; an entry can only
-- ever change how a tile LOOKS in voxel mode.
--
-- Most of the world needs no entry. The runtime detects structures on its
-- own (src/render/voxel/Structures.lua): it flood-fills each connected
-- drawn thing, voxelizes small props per pixel at their real drawn height
-- with transparency (a 2-row plant is a 16px-tall silhouette, not a box),
-- and raises everything else as a volume whose height is measured from the
-- drawing itself -- repeat-aware, so a 6-row house is 48px while a 40-row
-- border forest is rows of 16px trees, not a monolith.
--
-- Listing a tile here BYPASSES that detection: the tile takes the class's
-- height and art mode, always. Use it where the detector reads art wrong,
-- or from a mod to pin its own tiles. Resolution order per tile:
--
--   1. a group listed under tilesets[<id>] below        (this profile)
--   2. the tile sits in a water cell                    -> "water"
--   3. the tile sits in a WALKABLE cell                 -> "ground"
--   4. tile-level fallback: the map's water set -> "water", its walkable
--      list -> "ground", anything left over             -> "wall"
--
-- Rules 2-3 work at CELL granularity (16x16, the walk grid) because that
-- is the granularity collision actually has: the engine judges a cell by
-- its bottom-left tile alone, so the other three tiles of a cell carry no
-- collision meaning -- flowers and grass tufts sit in walkable cells and
-- must stay flat ground even though no walkable list names them.
--
-- Classes (heights in world pixels; a map cell is 16x16):
--   ground / water / void   flat; water recesses so shorelines show a lip
--   ledge / roof / bed      box with the art on its TOP face; partial side
--                           faces crop the art (a 6px ledge face is the
--                           bottom of the lip drawing; a bed is its
--                           mattress drawn from above, lying low)
--   wall / tree / fence / sign / counter / table / desk
--                           box whose SOUTH face folds the 2D artwork
--                           upright, 8px band by band; authored boxes fold
--                           every face and wear their top row's art on top.
--                           A counter is half a cell -- one band, so its
--                           drawn front panel stands and its top stays on top
--   stair_e / stair_w       real steps rising toward the named side, the
--                           full cell deep, treads and slices textured
--                           from the drawn staircase
--   stair_down_e / _down_w  a sunken stairwell: the cell opens into a
--                           hole with steps descending toward the named
--                           side -- stairs that lead DOWN a floor
--   relief                  a prop drawn from above (a console on the
--                           floor): the drawing stays flat and the
--                           pixels inside its black outline extrude a
--                           few voxels, art on top
--   bookcase                a free-standing shelf drawn tall: each rank
--                           collapses onto a one-cell-deep box at its
--                           full drawn height; back rows become hidden
--                           floor, and an unpinnable trim row above
--                           becomes the cap
--   billboard / prop        a prop drawn face-on: a standing per-pixel
--                           cutout, black-outline segmented; drawn above
--                           a pinned box it stands ON that box (a
--                           monitor on its desk).  prop is a second pool
--                           so two touching cutouts stay separate
--
-- A tileset entry may also carry `prop_ground` (not a class): a map of
-- prop tile id -> ground tile id naming the tile painted under that
-- pinned prop, overriding the flat-neighbour vote -- the cuttable bush
-- stands on the grass Cut leaves behind, whatever borders it.
--
-- And `prop_bg` (not a class either): which GB shades count as BACKGROUND
-- when a pinned per-pixel prop is cut out, for the drawings whose own body
-- reaches the edge of their bounding box and so vote themselves away.
-- Keyed by tile, because two props sharing an atlas can want opposite
-- answers on the same shade.
--
-- And it may carry `figures` (not a class either): hand-drawn pixel masks
-- that lift a FIGURE PAINTED INTO furniture off it and stand it up as a
-- standee, leaving the furniture its own geometry.  A pin resolves a
-- whole 8x8 tile, so it can never separate two things that share one --
-- and nothing automatic can either when the figure has no background
-- margin to flood from and wears the same shades as what it sits on.
-- The Pokemon Center's seated man is the case; see POKECENTER below for
-- the format.
--
-- Whole BUILDINGS are not tile pins -- one drawing packs a roof seen from
-- above, a facade seen face-on and sloped ends as diagonal silhouettes,
-- and no single class covers that.  They live in the `buildings` list at
-- the bottom of this file, as a band table over the drawing's rows.

return {
  version = 1,

  -- class -> height in world pixels
  heights = {
    ground = 0,
    water = -2,
    void = 0,
    ledge = 6,
    fence = 10,
    sign = 12,
    wall = 16,
    -- masonry drawn two courses tall (the Indigo Plateau's rim, the
    -- badge-check gates): as tall as a statue on its plinth
    cliff = 32,
    tree = 16,
    roof = 28,
    bed = 7,
    stool = 8,
    counter = 8,
    table = 12,
    desk = 24,
    prop = 16,
    cutout = 16,
    relief = 3,
    bookcase = 32,
    stair_e = 16,
    stair_w = 16,
    stair_down_e = 16,
    stair_down_w = 16,
  },

  -- Only tiles the detector must not touch need listing. Tile ids are
  -- indices into the tileset's own 8x8 atlas.
  tilesets = {
    OVERWORLD = {
      -- the hop-down edges named by data.field.ledges' ledgeTile: their
      -- art is a ground lip seen from above, which the detector would
      -- otherwise raise as a wall
      -- $34 is the cliff slope's FOOT, and it also punctuates the ledge
      -- rows: the hop-down runs are set into the cliff face and this
      -- tile is the pillar between segments.  It was `wall` with the
      -- rest of the slope chain, which stood those pillars 16px beside
      -- a 6px lip -- the ledge line came out interrupted by blocks
      -- nearly three times its height.  At ledge height the run reads
      -- as one continuous lip, and the mound loses nothing: its foot
      -- row simply reads as the talus it is drawn as.
      ledge = { 13, 29, 39, 52, 54, 55 },
      -- trees are drawn ROUND -- the lone canopy (42/43/58/59) and the
      -- border tree wall (64/65/80/81, blockset $0F). Boxes and per-pixel
      -- cutouts both read wrong for them; the cylinder archetype carves
      -- one voxel ball per 16x16 cell from the canopy's darkest-pixel
      -- outline, round in depth, so tree rows become rows of real canopies
      cylinder = { 42, 43, 58, 59, 64, 65, 80, 81 },
      -- the town sign (blockset 8's SE cell): a standing per-pixel slab
      -- 2 voxels thin, transparency respected -- never a solid box
      signpost = { 70, 71, 86, 87 },
      -- the fence posts drawn in VERTICAL runs (14 the post tops, 85
      -- the bottoms -- across all 222 maps the two tiles pair only in
      -- this one cell). The detector already turns the HORIZONTAL runs
      -- (tile 57) into per-post standees, but a vertical run of repeated
      -- cells trips its scenery guard and fell to the volume path as a
      -- fence-textured tower. `post` extracts each cell alone, so these
      -- render as the same thin posts, marching north
      post = { 14, 85 },
      -- the cliff-mound's dark east slope and its NE corner ($24 the
      -- slope column, $02 the corner).  Their drawn runs span the whole
      -- mound drawing, so the detector raised them to 32px towers --
      -- the rock pillar beside Diglett's Cave -- and the doorway
      -- column, which adopts its REGION's height, inherited the same 32
      -- and put the cave entrance a block above the mound around it.
      -- Pinned to one 16px course they match the plateau body, and the
      -- doorway drops with them.  ($34, the slope's foot, is `ledge`
      -- instead -- see there.)
      wall = { 2, 36 },

      -- the cuttable bush ($2D/$2E/$3D/$3E, the four tiles Cut deletes
      -- -- across the whole tileset they appear only in the five
      -- cut-tree blocks): a standing per-pixel cutout 5 voxels deep,
      -- black-outline segmented with the pixels the outline encloses
      -- kept, its drawn grass dither flooding away as background
      prop = { 45, 46, 61, 62 },
      -- the ground painted under those pinned props, by the prop tile's
      -- own id: the bush stands on plain grass ($2C) -- the very tile
      -- Cut leaves behind (field.cutTreeSwaps' after-blocks) -- rather
      -- than whatever flat tile its neighbours vote
      prop_ground = { [45] = 44, [46] = 44, [61] = 44, [62] = 44 },
    },

    -- The badge gyms and Bruno's room (one tileset): the bird statues
    -- that flank every gym's aisles, and Lt. Surge's trash cans.  A
    -- statue is one cell of figure ($02/$38/$12/$13) drawn over one
    -- cell of plinth ($22/$23/$32/$33); the trash can is one cell
    -- ($0B/$0C/$1B/$1C, blocks 38/39 only).  Across the whole blockset
    -- none of these tiles appears anywhere else.  The plinth stays a
    -- SOLID 16px block; the figure stands ON it as a per-pixel cutout
    -- 5 voxels deep (the thin `prop` pool), collapsing to the plinth's
    -- single cell of footprint (Structures' wall-support rule); the
    -- can is the same 5-voxel cutout at floor level.  Both are
    -- black-outline segmented -- backgrounds flood away, the pixels
    -- the outline encloses stay.  Everything stands on the gyms' main
    -- floor tile ($11), which is also Bruno's floor.
    -- (The round boulder drawn beside some statues, $07/$08/$17/$18,
    -- is NOT pinned: it also tiles wall-to-wall as Pewter's rock rows,
    -- which are scenery for the detector, not a lone prop.  Probed:
    -- the repeat-aware scenery path already gives every one of them a
    -- single 16px course in Pewter's and Bruno's rock walls alike, so
    -- a pin would only restate the derived answer.)
    --
    -- The rest of the tileset is the ten rooms' own furniture: the six
    -- badge gyms it serves (Pewter, Cerulean, Vermilion, Celadon,
    -- Fuchsia, Viridian) plus Bruno's and Lorelei's rooms, the
    -- Champion's room and the Hall of Fame.  (Saffron's and Cinnabar's
    -- gyms are FACILITY, Agatha's room is CEMETERY and Lance's is DOJO,
    -- so none of them takes a pin from here.)  Same failure as every
    -- other interior: the detector reads the black interior walls as
    -- volumes measured off the whole drawn run, so Vermilion's side
    -- walls and Viridian's north-south maze arms came out as 48px fins
    -- with their black fill VOIDED flat between them, and the Hall of
    -- Fame's recording machine merged into the wall band as a 32px slab
    -- whose feet had been flattened away by the walkable-cell rule.
    GYM = {
      -- The wall band is ONE 16px face, whatever the artist drew into
      -- it.  The plinths (34/35/50/51 -- 50 is the $32 water-fallback
      -- trap and would recess into a pond lip); the room's own band
      -- ($05 white course, $10 trim, $06 the doorway's dark head); the
      -- BLACK interior walls every gym is partitioned with -- $0F the
      -- fill (near-black, so the void rule flattens it unless it is
      -- AUTHORED, which is the whole reason it is listed), $24/$26/$27
      -- the top edge and its corners, $25/$35 the sides, $42/$3E the
      -- west and east end caps of a horizontal arm and $10 again as its
      -- lit south face.  Then the things drawn built INTO those walls,
      -- exactly like the Center's healing consoles: Vermilion's target
      -- band ($44-$47 with $05 between, over the $54/$56/$57 stripe),
      -- the barred gate ($20/$21/$30/$31 -- Lorelei's north door, and
      -- the barrier VermilionGymScript paints in until both switches
      -- are thrown), and Vermilion's corner switchboard ($29/$2A over
      -- $0D/$0E and $1D/$1E), which is drawn 32px tall and so reads as
      -- two stacked courses of the same band.
      wall = { 34, 35, 50, 51,
               5, 16,
               15, 36, 37, 38, 39, 53, 62, 66,
               68, 69, 70, 71, 84, 86, 87,
               32, 33, 48, 49,
               13, 14, 29, 30, 41, 42 },
      -- Fuchsia's invisible maze walls ($1F) are deliberately NOT here.
      -- The artist drew them as the floor with its stripes broken: on
      -- the GB they are invisible, and the puzzle IS walking into them.
      -- Raising them to a course would read better as a room and give
      -- the player something to bump into -- and would also hand them
      -- the solution, turning a maze into a corridor.  A shape is
      -- purely presentational and this file's job is to reproduce what
      -- was drawn, so the drawn answer wins: left to the derived path,
      -- $1F stays the floor it is painted as and the gym plays exactly
      -- as the flat game does.
      -- Cerulean's pools are the ONE place the $14 water-fallback trap
      -- is right: $14 really is the gym's water, so it is left to fall
      -- through to the engine's water set and recess.  Its north coping
      -- ($04, the grated lip) is drawn in the TOP half of a water cell,
      -- so the cell rule dragged it down to the water line with it;
      -- pinned flat it stays the poolside at floor level and the water
      -- shows a real lip.  The pool's south lip ($01) needs nothing --
      -- it is always the top half of a walkable FLOOR cell, so rule 3
      -- already lays it flat.  Lorelei's room uses the same pair for
      -- the paved plaza that stands out of her water.
      -- the entrance mat every gym lays inside its door ($06 over $16,
      -- 28 placements and nowhere else): drawn from straight above, so
      -- it lies FLAT.  $06 was in the wall band above, which stood the
      -- mat's top half up as a 16px box in the doorway -- the cell rule
      -- could not save it, because a pin outranks the cell.
      ground = { 4, 6, 22 },
      -- Celadon's hedge: a round shrub, one per cell ($2C/$2D over
      -- $2E/$2F), 35 of them planted wall to wall.  Round drawings get
      -- the cylinder archetype -- one voxel ball per 16x16 cell carved
      -- from the darkest-pixel outline -- the same treatment the
      -- overworld's tree canopies take, and per-CELL, so a hedge row
      -- becomes a row of bushes instead of one boxed monolith.
      cylinder = { 44, 45, 46, 47 },
      -- The statues, the cans, and Celadon's three little trees
      -- ($40/$41 canopy over $50/$51 trunk).  A trunk is not round, so
      -- the tree cannot be a ball like the shrubs beside it -- it takes
      -- the thin standee pool every interior plant takes, which is also
      -- a pool apart from the cylinders it touches.
      prop = { 2, 56, 18, 19, 11, 12, 27, 28,
               64, 65, 80, 81 },
      -- The Hall of Fame's recording machine, the one piece of real
      -- furniture in the tileset.  It is drawn 32px wide and THREE tile
      -- rows tall against the north band, and the detector made a mess
      -- of it twice over: the top two rows merged into the wall band as
      -- one 32px slab, and the base row -- whose cell is walkable,
      -- because the Hall's floor tile ($19) is its own bottom-left --
      -- was flattened into the floor, so the machine stood on nothing.
      -- Split at the drawn seam: the plinth row ($58/$59/$5A) is a
      -- half-cell counter, and the console above it ($5B-$5E over
      -- $36/$37/$55/$5F) is a standing per-pixel billboard that rides
      -- the plinth's top face through the authored-box support rule.
      -- 8 + 16 is exactly the 24px the machine is drawn.
      counter = { 88, 89, 90 },
      billboard = { 91, 92, 93, 94, 54, 55, 85, 95 },
      -- the ground painted under each pinned prop, by the prop tile's
      -- own id: statues and cans stand on the gyms' main floor ($11),
      -- Celadon's trees on the garden's light dither ($2B) rather than
      -- on whatever their neighbours vote.
      -- (Celadon's flowerbed tile $03 is deliberately absent: the
      -- tileset ANIMATES it by frame rewrite, so TileShape derives the
      -- `flower` pin for it already -- flat ground plus a standing
      -- 1px cutout -- and listing it here would take that away.  The
      -- floors need nothing either.  $11/$16/$2B and Viridian's arrow
      -- and dot markings $3C/$3D/$3F/$4C/$4D are in the walkable list
      -- outright; the paved slabs the Hall of Fame is floored with and
      -- Lorelei's plaza is built of ($09/$0A over $19/$1A) get there
      -- through the CELL: only $19 is listed, but it is the cell's
      -- bottom-left, so rule 3 lays all four of them flat together.
      -- Cerulean uses the very same slab as its poolside deck, which is
      -- why that gym's perimeter is a deck and not a wall -- the room's
      -- only wall band is the one drawn course along its north edge.)
      prop_ground = { [2] = 17, [56] = 17, [18] = 17, [19] = 17,
                      [11] = 17, [12] = 17, [27] = 17, [28] = 17,
                      [64] = 43, [65] = 43, [80] = 43, [81] = 43 },
    },

    -- The caves: one blockset serves nineteen maps -- Mt Moon's three
    -- floors, Rock Tunnel's two, Seafoam Islands' five, Victory Road's
    -- three, Cerulean Cave's three, and Diglett's Cave with its two
    -- route-side stubs.
    --
    -- THE CAVE'S VERTICAL SCHEME.  A Gen 1 cave is drawn on two floor
    -- levels, and the game's own collision data says which is which.
    -- data.field.tilePairs forbids stepping between $20/$21/$2A/$41 and
    -- $05 on land, and between $14 and $05 while SURFING -- but nothing
    -- forbids $14 <-> $20.  Read that back and the elevation falls out:
    -- the dark floor and the water are one plane, the lit floor is a
    -- step above both, and the rock is the room around them.
    --
    --        h  what                                 tiles
    --        0  DARK LOWER FLOOR -- the datum         $20 $21 $2A
    --        0  CAVE WATER, the surfable pool         $14
    --        0  fall-through drop hole                $2F $22
    --        0  unlit black (the void rule, no pin)   $3C
    --        3  Victory Road's boulder switch plate   $2B $2C $2D $2E
    --        6  LIT SHELF, one step up (`ledge`)      $05 $29
    --        6  the stair plate down off that shelf   $15 $16
    --       16  ROCK -- one band for the masses, the  everything else
    --           faces, the caps and the ceiling mass
    --   0 up 16  ladder shaft UP a floor              $0A $0B $1A $1B
    --   0 dn 16  ladder shaft DOWN a floor            $08 $09 $18 $19
    --
    -- NO CAVE SURFACE SITS BELOW 0.  The datum is the dark floor; the
    -- water is level with it (you surf off a pool straight onto the dark
    -- floor, which is exactly what the missing $14/$20 tile pair says);
    -- every other surface is above it.  A cave is underground, not
    -- underwater, and the only class in this file that goes negative is
    -- `water` (-2), which exists to cut the overworld's shoreline lip.
    -- It is deliberately NOT used anywhere in this entry.  The one thing
    -- that does reach below the datum is the DOWN ladder's stairwell,
    -- which is a hole on purpose: it is the shaft to the floor below,
    -- and no walkable surface is drawn in it.
    --
    -- What the detector made of it: the rock EDGES towered.  A shelf's
    -- side is drawn as a cap over a run of face tiles over a corner
    -- pair -- $04 / $31 x5 / $28 / $10 down one column -- and the volume
    -- builder's repeat scan anchors on the column's FRONT tile, which
    -- here is a one-off corner that never recurs above it.  Neither the
    -- repeat read nor the trim rule (two identical rows directly above
    -- the front) fires, so the column keeps its whole extent and caps at
    -- MAX_ROWS: a 48px fin out of the 16px band beside it, while the
    -- column one tile west -- ending on $28 with two $31 above -- reads
    -- 16.  Probed before pinning: MT_MOON_B2F tiles (5,4)-(5,11) and
    -- (17,8)-(17,15) at 48 with 16 either side; VICTORY_ROAD_2F
    -- (25,26)-(25,31); SEAFOAM_ISLANDS_B4F (22,0)-(22,7),
    -- (13,12)-(13,19) and (12,13)-(12,19).  The same reading turns a
    -- column of four DIFFERENT rock tiles into 32px -- VICTORY_ROAD_1F
    -- (28,20)-(29,23) and (30,20)-(31,23), $02/$12 over $0C/$1C, next
    -- to identical rock at 16.  An authored tile never reaches the
    -- volume builder, so pinning the rock is the whole fix: there is no
    -- run left to misread.
    CAVERN = {
      -- ---- 16: the rock, one band ----
      --
      -- Reading across the blockset: $02/$03 over $12/$13 is the
      -- speckled rock mass and $0C/$0D over $1C/$1D the boulder-cluster
      -- mass, both solid wall-to-wall fills; $10/$11 is the cobble
      -- course facing the south side of every lit shelf, $31 its west
      -- face and $17 its east; $04/$07/$28 are the caps and $25/$26 the
      -- inner corners where two faces meet.  $0E/$0F over $1E/$1F is the
      -- barred rock shelf that stands alone on the dark floor
      -- (MT_MOON_1F, ROCK_TUNNEL_1F and twice in SEAFOAM_ISLANDS_B4F):
      -- one cell of face-on drawing, so one 16px face -- never a
      -- standee, its black surround touches all four rims and would
      -- segment into a solid slab.
      --
      -- $06/$27 over $24/$01 is the CEILING MASS: a pale dithered rock
      -- fill with a black rim dithered along its north and south edges,
      -- so a run of it tiles into the grid of light blocks that walls
      -- off most of MT_MOON_B2F (37 cells) and stands as one lump in
      -- each of VICTORY_ROAD_1F/2F/3F.  It is blocked in every map that
      -- places it ($24 is not on the walkable list) and it is NOT in the
      -- engine's water set, so it is rock and belongs in the band with
      -- the rest of the rock.  The first pass read the checker as a pond
      -- and pinned it `water`: that recessed 612 tiles to -2 and cut
      -- open trenches down the middle of Mt Moon B2F -- 06w-2 27w-2 /
      -- 24w-2 01w-2 for ten cells straight, hard against 31w16 rock and
      -- the 05l06 shelf.  Its unpinned reading was 48px (eight rows of
      -- alternating $06/$24 read as one drawing); 16 is the answer.
      wall = { 2, 3, 18, 19,       -- $02/$03 over $12/$13, speckled mass
               12, 13, 28, 29,     -- $0C/$0D over $1C/$1D, boulder mass
               16, 17,             -- $10/$11, the shelf's south cobbles
               49, 23,             -- $31 west face, $17 east face
               4, 7, 40,           -- $04 NW cap, $07 NE cap, $28 SW cap
               37, 38,             -- $25/$26, the inner corners
               14, 15, 30, 31,     -- $0E/$0F over $1E/$1F, barred shelf
               6, 39, 36, 1 },     -- $06/$27 over $24/$01, ceiling mass
      -- ---- 6: the lit shelf, and the stairs off it ----
      --
      -- $05 is the lit floor -- the shipped pin, and the step
      -- data.field.tilePairs encodes ($20/$21/$2A/$41 <-> $05).  $29 is
      -- the SAME surface: the artist's shadow row where the shelf runs
      -- up against the rock above it.  It sits in walkable cells, so
      -- unpinned it resolved to flat ground and cut a 6px trench along
      -- the north edge of every lit room (`29g00` with `05l06` one tile
      -- south, all the way across MT_MOON_B2F).
      --
      -- $15/$16 is the STAIR down off that shelf, and the elevation it
      -- spans is 6px, not 16.  Its art is four treads seen from above,
      -- each a light tread over a black riser line, stacked NORTH-SOUTH:
      -- every one of the 54 stair cells in the tileset has the lit floor
      -- $05 to its NORTH and the low ground to its SOUTH (dark floor x35,
      -- water x14, lit floor x5 where two flights meet), so the flight
      -- climbs NORTHWARD, one cell deep, 0 -> 6.
      --
      -- It is NOT pinned `stair_e`/`stair_w`, and that is deliberate.
      -- Those classes build a flight that marches along X -- 16px tall,
      -- rising toward the named side -- so either of them here would
      -- throw a 16px staircase sideways across a 6px north-south step,
      -- blocking the passage it is supposed to open and climbing at
      -- right angles to the drawn risers.  A wrong-way flight is worse
      -- than a flat one.  `ledge` is the honest reading available: the
      -- stair cell joins the shelf it belongs to, wears its four treads
      -- on the TOP face (which is how they are drawn -- from above), and
      -- puts its 6px riser face at the FOOT of the flight where the
      -- player actually steps down onto the dark floor.  See the report:
      -- a real sloped cave stair wants `stair_n`/`stair_s` in
      -- Structures.stairCell, which is an engine change, not a pin.
      ledge = { 5, 41,             -- $05 lit floor, $29 its north shading
                21, 22 },          -- $15/$16, the stair plate off it
      -- ---- 0: the floor plane ----
      --
      -- The dark lower floor, pinned rather than left derived so the
      -- datum this whole entry measures from is stated in it.  $20 is
      -- the rough floor, $21 the bright checker, $2A the fine checker;
      -- all three are on the tileset's walkable list and all three
      -- already resolved here -- the pins restate the level, they do not
      -- move it.
      --
      -- $14 IS THE CAVE WATER: the tileset animates by TILEANIM_WATER,
      -- and TileRenderer's WATER_TILE is $14 -- it is the tile that
      -- h-shifts to ripple.  Map's water set names it too, so its cells
      -- are the ones Surf works on: Cerulean Cave's lake (352 + 272
      -- tiles on 1F/B1F) and the Seafoam channels (304 on B3F, 816 on
      -- B4F).  The first pass read its blocky white dither as "bright
      -- rubble mass" and pinned it `wall`, which stood both lakes up as
      -- 16px rock -- two thirds of SEAFOAM_ISLANDS_B4F was a rock slab
      -- you were meant to surf across.  It is water, and it lies at the
      -- floor plane: `ground` keeps the drawn (and animated) water art
      -- exactly as it is and puts its surface at 0, level with the dark
      -- floor you step off onto, one 6px step below the lit shelf you
      -- cannot surf onto.  NOT the `water` class -- that is -2, a
      -- shoreline lip for the overworld sea, and a cave pool must never
      -- read as a trough sunk into the floor you are walking on.
      --
      -- $2F over $22 is Seafoam's and Victory Road's fall-through drop
      -- hole (Map's warpPadTiles calls $22 a "hole").  Its art is a lit
      -- rim over solid black and its cell is walkable -- you step on it
      -- and drop a floor -- so it stays flat at the floor plane; the pin
      -- keeps the rim out of the wall fallback.
      ground = { 32, 33, 42,       -- $20/$21/$2A, the dark lower floor
                 20,               -- $14, the surfable cave water
                 47, 34 },         -- $2F over $22, the drop hole
      -- ---- 0 to 16: the ladders, the caves' real staircases ----
      --
      -- Both ladder graphics are drawn from above as a shaft with two
      -- rails and rungs between them, and which one is which is not a
      -- guess -- it is in the warp table.  Across all nineteen maps,
      -- every one of the 37 $08 cells warps to a LOWER floor
      -- (MT_MOON_1F->B1F, B1F->B2F, ROCK_TUNNEL_1F->B1F, each
      -- SEAFOAM_ISLANDS floor to the next one down, CERULEAN_CAVE_2F->1F
      -- and 1F->B1F, the Diglett's route stubs down into the cave) and
      -- every one of the 40 $0A cells warps to a HIGHER one (the exact
      -- reverse, plus MT_MOON_B1F's and ROCK_TUNNEL_1F's exits back out
      -- to daylight).  $08 is the ladder DOWN, $0A the ladder UP: 77
      -- cells, no exceptions.
      --
      -- So they take the two classes that MOVE between floors.  $0A
      -- becomes a rising flight -- four real steps climbing 0 -> 16, the
      -- height of the rock band it disappears into -- and $08 becomes an
      -- excavated stairwell, four steps descending below the floor into
      -- a dark opening.  East for both: the ladder art is symmetric
      -- about its own centre line so the drawing does not choose a side,
      -- the cell's east neighbour is the closed (rock) side more often
      -- than its west, and the rest of this profile's staircases
      -- (REDS_HOUSE_1, UNDERGROUND) climb east too.  The flight's treads
      -- land one rung apiece, which is as close to a drawn ladder as
      -- stepped geometry gets.
      --
      -- All four tiles of each cell are listed, the way REDS_HOUSE_1
      -- lists its flight: buildStairs anchors on the cell's TOP-LEFT
      -- tile ($08 / $0A) and claims the other three, but pinning them
      -- too keeps them out of the region flood and the door fold.
      stair_e = { 10, 11, 26, 27 },        -- $0A/$0B over $1A/$1B, UP
      stair_down_e = { 8, 9, 24, 25 },     -- $08/$09 over $18/$19, DOWN
      -- ---- 3: the boulder switches ----
      --
      -- Victory Road's four plates ($2B/$2C over $2D/$2E, on 1F, 2F and
      -- 3F).  Round art, but NOT a round object: the Strength boulders
      -- themselves are overworld SPRITES, and this is the plate they get
      -- pushed onto -- drawn from straight above as a black ring, a
      -- white highlight rim and a grey disc.  `cylinder` was tried here
      -- first, because a circle is what the overworld's round canopies
      -- take, and it came out wrong: the plate's own dithered background
      -- carries stray black pixels the darkest-outline flood cannot
      -- reach, so they joined the mask, inflated the top and bottom row
      -- spans to the full 16, and the hull rendered as a clutch of white
      -- shards standing where the plate should be (VICTORY_ROAD_1F cell
      -- 17,13).  `relief` is the reading anything drawn from above
      -- wants: the disc stays flat and the pixels inside its black ring
      -- lift a few voxels, so it reads as a plate -- and the cell is
      -- walkable, so you step on it.
      relief = { 43, 44, 45, 46 },
      -- Left to the derived default on purpose: $3C is solid black --
      -- the unlit rock that is most of MT_MOON_B1F -- and the void rule
      -- flattens it (`3Cv00`).  Pinning it would BREAK that, since the
      -- void rule skips authored tiles; a 16px black band there would
      -- also wall the corridors in with something the 2D art draws as
      -- nothing at all.  $30 and $41 are on the walkable list and in
      -- tilePairs but no block in this tileset places either, so there
      -- is nothing for a pin to catch.
    },
    -- Viridian Forest.  Nearly everything drawn here is ROUND, and the
    -- detector was boxing all of it: the big trees came out as ragged
    -- mixed-height volumes (their sparse canopy-edge tiles read 0px,
    -- their bodies 32px), the stump rows merged into 16px crate walls
    -- wearing folded stump art, and the trail sign was a broken pile --
    -- its $32 tile is the water-fallback trap and recessed into a pond
    -- lip in the middle of the woods.
    FOREST = {
      -- the hop-down edge, from data.field.tilePairs (CAVERN's entry
      -- above carries the same note for its own pair)
      ledge = { 46 },
      -- the big trees: the whole 2x2-CELL drawing carves as ONE 32px
      -- voxel hull, so a tree is a single tall canopy instead of four
      -- ground-level quarter-pancakes ("cut in half", as the first
      -- attempt read).  `canopy` pins the drawing's top-left corner
      -- tile ($04) as the group anchor; every other tile of the
      -- drawing stays `cylinder` so the group build can verify and
      -- claim its cells -- and so a stray partial drawing degrades to
      -- per-cell hulls rather than boxes
      canopy = { 4 },
      cylinder = { 5, 6, 7, 21, 22, 23,
                   35, 36, 37, 38, 39, 53, 54 },
      -- the stumps ($02/$03/$12/$13): a hull whose drawn top is a CUT
      -- FACE.  The body builds from the bark rows alone, and the drawn
      -- ellipse of growth rings projects onto the hull's round flat
      -- top -- its bottom arc to the south, the way the 2D art means
      -- it.  stump_cap is the ellipse's height in art rows
      stump = { 2, 3, 18, 19 },
      stump_cap = 7,
      -- the white sparkle filler inside the tree masses: flat, not an
      -- invisible zero-height box
      ground = { 0 },
      -- the trail signs: the standing thin-slab treatment every town
      -- sign gets ($32 pinned is also what lifts it out of the water
      -- trap)
      signpost = { 33, 34, 49, 50 },
    },

    -- Oak's Lab (the tileset also serves the Fighting Dojo and Lance's
    -- room, which use none of these tiles).  The free-standing shelf
    -- ranks: book rows and base pinned; the shared trim tiles above
    -- (41/42, also the lab tables' corners) are adopted as caps by the
    -- bookcase builder rather than pinned.
    DOJO = {
      bookcase = { 13, 14, 29, 30 },
      -- the lab tables (the starter-ball display and the north tables):
      -- 41/42 are also the shelf trim the bookcase builder adopts as
      -- caps, which its cap rule allows for authored table rows.
      -- Pinning stops the display frame's black corner brackets from
      -- auto-extracting into standing prisms, and the ball/Pokedex
      -- sprites ride the table's authored height.
      table = { 41, 42, 57, 59, 78, 79 },
    },

    -- Red's room and the Copycat's room (one tileset).  The detector reads
    -- this furniture as wall-height volumes -- and merges the wall-touching
    -- table and desk INTO the wall, towering both -- so every object here
    -- is pinned to the shape it depicts.
    REDS_HOUSE_2 = {
      -- the wall band with its windows stays one 16px face
      wall = { 0, 36, 37, 52, 53 },
      -- the bed: a mattress drawn from above, half a block high
      bed = { 45, 46, 47, 61, 62, 63 },
      -- stools: a seat-high box, seat art on top, legs on the front
      stool = { 2, 3, 18, 19 },
      -- the long table under the windows, and the PC desk's body with
      -- its hutch row -- the monitor standing on it is pinned below
      table = { 38, 39, 41, 42, 43, 44, 50, 51,
                58, 59, 60, 66, 67 },
      -- standing per-pixel props, black-outline segmented.  The PC
      -- (64/65 monitor top, 32/33 monitor bottom + keyboard) is drawn
      -- above the desk's body, so it stands ON the desk; the TV stands
      -- on the floor
      billboard = { 6, 7, 22, 23, 32, 33, 64, 65 },
      -- the potted plant: mostly silhouette, so it takes the THIN
      -- standee pool
      prop = { 8, 9, 24, 25, 68, 69, 70, 71 },
      -- the small potted plant on the table: a paper-thin profile
      -- cutout standing on the tabletop, its leaf crown (in 40) included
      cutout = { 40, 54, 55, 56, 57 },
      -- the game console in front of the TV is drawn from above: it
      -- lies flat and extrudes a few voxels inside its outline
      relief = { 14, 15, 30, 31 },
      -- the staircase leads DOWN to 1F: a sunken stairwell.  The player
      -- enters at the east lip and the flight descends westward, the way
      -- the drawn railing slopes (high at the east, low at the west)
      stair_down_w = { 10, 11, 26, 27 },
    },

    -- Red's and the Copycat's ground floor (one tileset, same atlas as
    -- the floor above).  Bookcases, dining table with its flower pot,
    -- stools, the TV on the floor, and the staircase up.
    REDS_HOUSE_1 = {
      wall = { 0, 36, 37, 52, 53 },
      stool = { 2, 3, 18, 19 },
      -- the dining table (38-44/58-60); its top row also caps the
      -- bookcases below
      table = { 38, 39, 41, 42, 43, 44, 58, 59, 60 },
      -- the bookcase bodies: tall shelf boxes; their drawn top-edge row
      -- (38/41, pinned table above) becomes their top face
      desk = { 34, 35, 48, 49, 50, 51 },
      -- the TV on the floor
      billboard = { 6, 7, 22, 23 },
      -- the small potted plant on the table: a paper-thin profile
      -- cutout standing on the tabletop, its leaf crown (in 40) included
      cutout = { 40, 54, 55, 56, 57 },
      -- the staircase leads UP to 2F: a rising flight climbing east
      stair_e = { 12, 13, 28, 29 },
      -- the front-door mat: its collision tile is $14, which the engine's
      -- stale-cache fallback counts as water in every tileset, so the rug
      -- would recess into a pond lip.  It is a flat rug on the floor
      ground = { 4, 20 },
    },

    -- The generic town house (Blue's, Daisy at her table, and eighteen
    -- more homes; the schoolhouse and the trashed house reuse it too).
    -- Same failure as Red's rooms: the detector reads the furniture as
    -- wall-height volumes and towers the table, so every object is
    -- pinned to the shape it depicts.
    HOUSE = {
      -- the wall band stays one 16px face: blank courses, the window,
      -- the framed picture, and the schoolhouse blackboard (72-75/88-91)
      wall = { 0, 36, 45, 46, 52, 61, 62, 72, 73, 75, 88, 89, 90, 91 },
      -- stools: a seat-high box that also seats Daisy
      stool = { 2, 3, 18, 19 },
      -- the dining table (top edge 38/41 also caps the bookcases);
      -- 80-83 are its ransacked corner in CERULEAN_TRASHED_HOUSE, which
      -- stays at table height rather than de-merging into a wall stub
      table = { 38, 39, 41, 47, 54, 57, 58, 59, 60, 80, 81, 82, 83 },
      -- the bookcase bodies: book ranks (14/15 left pair, 48/49 right)
      -- and the base course; the drawn top edge (38/41, pinned table
      -- above) becomes their top face
      desk = { 14, 15, 30, 31, 48, 49 },
      -- the corner potted plants: mostly silhouette, the THIN standee
      -- pool (crown 10/11, leaves 8/9/26/27, pot 24/25)
      prop = { 8, 9, 10, 11, 24, 25, 26, 27 },
      -- the open book on the schoolhouse table: a paper-thin cutout
      -- standing on the pinned tabletop
      cutout = { 70, 71, 86, 87 },
      -- the front-door mat: same $14 water-fallback trap as Red's; flat
      ground = { 4, 20 },
    },

    -- The Pokemon Center lobby.  One tileset serves all eleven Centers
    -- and the Celadon Hotel, and VIRIDIAN_POKECENTER places every tile
    -- the other maps use, so this list -- read off Viridian -- covers
    -- them all.  (The Marts are a DIFFERENT tileset id, MART, that only
    -- shares the atlas image; pins do not carry over.)  Same failure as
    -- the houses: the detector merges the wall-touching counters and
    -- machines into the wall and towers them, and the lounge seat --
    -- which has a PERSON drawn into the tile art -- becomes a monolith
    -- wearing his face.
    POKECENTER = {
      -- the wall band stays one 16px face: striped panels (40), the high
      -- windows (92-95; 94 doubles as the map's warp tile, and pins are
      -- look-only), the pokeball poster (2/3/18/19), and the pillars
      -- (16/41) with their bases (4/5/20/21; 20 is the $14 water-fallback
      -- trap and would recess into a pond lip).  The healing machines'
      -- bodies (72/76/77 console face, 6/22 button panel, 73 light edge,
      -- 7/13 shadowed edge) are ALSO wall: drawn 16px tall against the
      -- band, so wall height is their drawn height and they read as
      -- consoles jutting from it; the near-black screen tiles must be
      -- pinned or the void rule flattens them, and 72 is the $48
      -- water-fallback trap
      wall = { 2, 3, 4, 5, 6, 7, 13, 16, 18, 19, 20, 21, 22, 40, 41,
               72, 73, 76, 77, 92, 93, 94, 95 },
      -- the counters, half a cell high: top band (8) with the nurse's
      -- tray (10), front face (24/25, the game's counterTiles), left end
      -- cap (56) and the Cable Club's light sections (90/91).  8px is
      -- one clean band, so the drawn front panel stands up and the
      -- counter top stays on top; at 12 they read as wall stubs
      counter = { 8, 10, 24, 25, 56, 90, 91,
                  -- and the lounge couch with the man sitting on it.
                  -- Same half-cell box: its bottom row (42/43, the front
                  -- base) stands up as the couch's front, and the three
                  -- rows above it -- cushion (38/39) and the man
                  -- (36/37 head, 52/53 face) -- ride the top face in
                  -- drawn order, each exactly once.  See the note below
                  -- on why he cannot be stood upright.
                  36, 37, 38, 39, 42, 43, 52, 53 },
      -- standing per-pixel props, black-outline segmented: the healing
      -- machines' screen tops (58/59/74/75, drawn above the pinned
      -- bodies so they stand ON them) and the PC (66/70/82/86), which
      -- stands on its pinned desk
      billboard = { 58, 59, 66, 70, 74, 75, 82, 86 },
      -- The man on the couch, cut out by hand and stood up (see `figures`
      -- below).  Nothing automatic reaches him.  A class pin resolves a
      -- whole 8x8 tile and he SHARES his tiles with the couch, so pinning
      -- them stands the furniture up with him; riding the couch's top
      -- face (what this did before) draws him lying flat on the cushion;
      -- and he cannot be segmented into a standee either, because the
      -- drawing has no background margin for a flood to enter by and his
      -- skin is the same light shade as the couch -- the mask drained 307
      -- of his 420 interior pixels, 46% of him, even segmented alone.
      -- An authored mask is the only thing that can tell a man from the
      -- sofa he is painted into, so that is what `figures` carries.
      -- the PC's desk body, which the PC stands on
      table = { 9, 88 },
      -- the potted plants: bush (32/33/48/49) over pot (34/35/50/51,
      -- 50 is the $32 water-fallback trap).  Standing per-pixel
      -- billboards in the THIN pool, like every other interior plant --
      -- and a pool apart from the sofa, which touches the corner pair
      -- and must stay a separate object.  The bush's light checker
      -- highlights share the floor's shades, so the mask drains some of
      -- them; the standee reads darker than the flat art, which is the
      -- accepted trade for a real plant silhouette
      prop = { 32, 33, 34, 35, 48, 49, 50, 51 },
      -- ...but the POTS were draining outright.  The plant pair is drawn
      -- as one 4x4-tile block and the pot's olive base is flush on that
      -- block's bottom row, so the background vote -- which reads the
      -- shades touching the drawing's own bounding box -- came back with
      -- "dark" in it, and every dark pixel in the plant left with the
      -- floor.  The pots rendered as hollow black frames around one or
      -- two surviving pixels while the flat art has solid olive bodies.
      --
      -- So name the background outright for these eight tiles: the floor
      -- IS light and white here, and nothing else is.  That restores 152
      -- pixels of the block (55% -> 69% of it kept) and cannot move any
      -- other prop, which matters -- the same call tileset-wide would pull
      -- the dark wall band into the healing consoles' screens and strip
      -- three pixels off the PC, because those two want the opposite
      -- answer on the very same shades.
      prop_bg = {
        { tiles = { 32, 33, 34, 35, 48, 49, 50, 51 },
          shades = { "light", "white" } },
      },
      -- THE MAN ON THE COUCH.  He is drawn INTO the lounge furniture and
      -- spills out of it in BOTH directions, which is why he needs three
      -- tile columns:
      --
      --   36 / 52   the couch's west arm.  36's two RIGHTMOST columns are
      --             the back of his head; 52 is the plain arm, and is also
      --             what 36 wears once his hair comes off it
      --   37 / 53   him: head, then face and body
      --   57 / 60   the floor east of the couch, which his hair and his
      --             foot overhang.  1 and 26 are those same two floor
      --             tiles as the artist drew them WITHOUT him -- 8 and 5
      --             pixels apart respectively -- so lifting him off is
      --             lossless there
      --
      -- `pixels` is the hand-drawn line between the man and the furniture;
      -- `under` is what each tile wears once he is lifted off it.  The
      -- couch keeps its polygonal box and he stands on top of it.
      --
      -- The mask keeps ALL of 37/53's column 7, the couch's east edge.
      -- Where that column is drawn dark it is the couch's own rule -- but
      -- it is also where his hair crosses the tile seam, so dropping it
      -- floats the overhang free of his head.  And where it is drawn WHITE
      -- it is the right side of his face, so dropping it opens a slit down
      -- his cheek (rows 5-8, which is exactly what the first cut did).
      -- Keeping the rule twice costs nothing: tile 39 redraws it on the
      -- couch beneath him either way.  Repainting 36 as 52 does cost one
      -- row -- 36's top trim band, which 52 does not carry -- and that is
      -- the accepted price for not leaving a second copy of his head lying
      -- on the arm.  The background corners around his head and the
      -- cushion wedge under his legs are the only pixels given back.
      figures = {
        {
          w = 3,
          tiles = { 36, 37, 57,
                    52, 53, 60 },
          under = { 52, 39,  1,
                    52, 39, 26 },
          pixels = {
            "..........XXXXX.........",
            "........XXXXXXXX........",
            ".......XXXXXXXXXX.......",
            "......XXXXXXXXXXXX......",
            "......XXXXXXXXXXXX......",
            "......XXXXXXXXXXX.......",
            "......XXXXXXXXXXX.......",
            "......XXXXXXXXXXX.......",
            "........XXXXXXXXX.......",
            "........XXXXXXXX........",
            "........XXXXXXXX........",
            "........XXXXXXXX........",
            "........XXXXXXXXX.......",
            ".........XXXXXXXXX......",
            "...........XXXXXX.......",
            "..............XX........",
          },
        },
      },
    },

    -- The Poke Marts (one 4x4 layout serves every city; the tileset
    -- shares the Center's atlas image but is its own id, so the pins
    -- above do not carry over).  Same failures as everywhere indoors:
    -- the detector towered the whole north display band to 32px, merged
    -- the clerk's booth into a 48px slab wearing the juice poster, and
    -- boxed the two free-standing shelf racks into one 4-tile-deep
    -- monolith.
    MART = {
      -- THE BACK WALL.  It is drawn FOUR tile rows tall -- trim (40, or
      -- the fridge tops 90/91), the SALE signs (78/79) or glass upper
      -- (44/45), the black display niche (76/77) or glass lower (46/47),
      -- and the cases' base and goods (23/29, 62/63) -- which is 32px of
      -- artwork depicting ONE wall, not four things at four depths.
      --
      -- Pinned `wall` that is exactly what it became: every row got its
      -- own 16px box marching north, so the only face you ever saw was
      -- the southmost row (the cases' base), the signs and the niche hid
      -- behind it, and the trim ended up lying flat as a gold shelf on
      -- the roofs of the boxes behind.  Laid out in depth instead of
      -- stacked up.
      --
      -- `bookcase` is the class that collapses a tall drawing onto a
      -- one-cell-deep box at its real drawn height, so the run of four
      -- rows becomes a single 32px wall: bands from the south are base,
      -- niche, sign, trim, its top face wears the trim, and the three
      -- rows behind become hidden floor.  Same treatment the shelf racks
      -- below already get -- a Mart's back wall IS a wall of display
      -- cases, and the geometry does not care which we call it.
      bookcase = { 23, 29, 40, 44, 45, 46, 47, 62, 63, 76, 77, 78, 79,
                   90, 91,
                   -- the free-standing shelf racks: TALL drawings, not
                   -- deep ones -- each rank collapses onto a
                   -- one-cell-deep shelf at its drawn height (the
                   -- Dojo/Red's-house treatment). 64/65/67 and 80/81/83
                   -- are the bottle rows the clerk's booth also wears as
                   -- its top display; 68/69/71 and 84/85/87 the goods
                   -- rows below
                   64, 65, 67, 68, 69, 71, 80, 81, 83, 84, 85, 87 },
      -- The wall's own tiles are reused elsewhere, and the back wall is
      -- the one place they are drawn on the map's TOP EDGE.  So `bookcase`
      -- is their default and this hands every other use back to `wall`,
      -- which is what all of them were before: 40 is also the clerk's
      -- booth back panel (under the shelf rows 80/81 or under itself), and
      -- 40/76/77/90/91 all recur in INDIGO_PLATEAU_LOBBY, the ninth map on
      -- this id, where they draw the hall and the lift bank.
      --
      -- NEVER put 0 in an `above` set.  Map:tileAt does not answer nil off
      -- the top of a map -- it border-extends, so row 0 reads the map's
      -- borderBlock, which indoors is the black void block 0.  Listing 0
      -- to catch the Lobby's void-backed 90/91 fired the rule on every
      -- Mart's fridge row as well: row 0 dropped out of the bookcase run,
      -- the fridges came out 24px against the SALE cases' 32px, and their
      -- trim row stood as a separate box BEHIND the wall instead of on top
      -- of it.  Nothing can separate those two cases from above -- both
      -- see void -- so the Lobby (already out of scope here) gets the
      -- bookcase reading too, and the Marts come out right.
      when_above = {
        [40] = { { above = { 40, 80, 81, 83, 90, 91 }, class = "wall" } },
        [76] = { { above = { 74, 75 }, class = "wall" } },
        [77] = { { above = { 74, 75 }, class = "wall" } },
        [90] = { { above = { 17 }, class = "wall" } },
        [91] = { { above = { 27 }, class = "wall" } },
      },
      -- the clerk's counter, half a cell high like every service
      -- counter.  It is a C wrapping the alcove the clerk stands in: the
      -- south arm's drawn front (24/25) under its top band (8/56), the
      -- light work surface the east arm and the rest of the south arm
      -- share (16/41), and the north arm's end panel (89).  8 and 56 are
      -- the two halves of one top band -- the first pass read 8 as the
      -- cash register, pinned it `billboard`, and got a bare black
      -- outline standing on the counter with the tile's own art replaced
      -- by its neighbour's.
      -- ...and the register's own two tile rows (14/15 over 30/31) are
      -- part of that same work surface now that the machine has been cut
      -- off them as a sprite -- see `figures` below.
      counter = { 8, 14, 15, 16, 24, 25, 30, 31, 41, 56, 89 },
      -- Left to the derived default on purpose: the floor checker and
      -- its shadowed variants (1/11/17/26/27/54) and the exit mat
      -- (12/28) all sit in cells the ROM marks walkable, so the cell
      -- rule lays them flat unaided.  (76/77, the SALE case's black
      -- interior, used to be left to the volume path here; it is now the
      -- back wall's third band, because a run of four rows has to be
      -- contiguous for the wall to collapse into one box at all.)
      -- THE CASH REGISTER: a keypad and a curl of receipt paper drawn
      -- face-on across two tile rows in the middle of the counter's east
      -- arm.  Like the Center's seated man it is a FIGURE drawn into the
      -- furniture, so it gets the same treatment -- a flat sprite card
      -- standing on the counter -- and for the same reason: no class pin
      -- can separate it from the counter, because the counter draws its
      -- own edging down columns 0 and 15 of the very same tiles.
      --
      -- That edging is what defeated every automatic reading. Black
      -- always survives the shade flood, so the standee pools extruded
      -- the two rules along with the machine and it stood flanked by a
      -- pair of tall black slabs; `console`'s keep-the-largest-drawing
      -- rule dropped them, but only by throwing away the receipt curl
      -- too whenever the flood happened to cut it loose.  The mask just
      -- says where the machine is: columns 2-13, plus the curl climbing
      -- to the top right, and the counter keeps its edging and its light
      -- work surface.
      --
      -- `under` is 16/41 twice -- the plain work surface, which already
      -- carries the west edging (black over white) and the east (dark
      -- over black), so the counter closes up behind the machine with no
      -- synthesis at all.
      figures = {
        {
          w = 2,
          tiles = { 14, 15,
                    30, 31 },
          under = { 16, 41,
                    16, 41 },
          pixels = {
            ".........XX.....",
            "........XXXX....",
            "........XXXXX...",
            "........XXXXXX..",
            "...XXXXXXXXXXX..",
            "..XXXXXXXXXXXX..",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
            "..XXXXXXXXXXX...",
          },
        },
      },
      -- NOT covered: INDIGO_PLATEAU_LOBBY, the ninth map on this id and
      -- the only one that is not the 4x4 shop.  It draws its own hall,
      -- lift bank and rope stanchions from tiles no Mart places, three
      -- of which fall in the engine's stale water set -- see
      -- reports/COUNTERS_pass2.md.  Pinning them is a tileset pass of
      -- its own and is deliberately not attempted here.
    },

    -- The route gates and their upstairs lounges, the four Underground
    -- Path entrance huts, the Safari Zone gate and its four rest houses
    -- -- twenty-five maps on one tileset.  (Viridian Forest's two gates
    -- draw the very same art from a SEPARATE id, FOREST_GATE below, and
    -- pins do not carry between ids.)  Before this entry every one of
    -- them was a swimming pool: 50/51 -- the dark panel the artist reuses
    -- as the wall's base course AND as every counter's front -- is one of
    -- the three ids (20/50/72, the $14/$32/$48 of the stale cache) that
    -- the engine's water set claims in every tileset, so the whole wall
    -- perimeter and every counter front recessed into a moat.  The other
    -- two are placed here as well: 20 is the exit doormat, 72 the top
    -- course of Route 2's wall.  What survived the water was towered
    -- instead -- the counters raised to a 16px slab, the cabinets boxed,
    -- the 2F window read as a 16-to-40px skyline, and the tables and
    -- binoculars flattened into the floor because their cells are
    -- walkable.
    GATE = {
      -- The wall band stays ONE 16px face.  Three wall drawings share
      -- it: the route gates' panelled course (32/33 -- its base course
      -- 50/51 is `counter`, see below), the
      -- Underground Path huts' and Route 22's plain stripes (0), and
      -- Route 2's speckled plaster (72 over its dark skirting 74).  0
      -- and 74 need no height correction but are pinned anyway, so the
      -- detector cannot swallow the corner plants into the band and
      -- tower them with it.  The gate 2F's big window is the same band
      -- two cells deep (58 glass, 45 its dither, 61 the diagonal glare,
      -- 62 the black mullions).  The door panes (41/43, the leaf drawn
      -- above the walkable threshold) are wall too, so a doorway reads
      -- as a recess in the band instead of a picture of a door lying on
      -- the floor -- the Center's warp-tile treatment, and pins are
      -- look-only so the cell stays walkable.
      --
      -- 50/51 is NOT in that list, and that is the one deliberate cost in
      -- this entry.  The artist draws one panel twice: as the wall cell's
      -- base course (32/33 over 50/51) and as the front of every counter
      -- (7/9/8 or 17/18 over 50/51).  A pin is per tile id and a class
      -- carries one height, so the two uses cannot be separated here at
      -- all -- only in `lib`, by letting a pin be conditional on the tile
      -- drawn ABOVE (see reports/COUNTERS_pass2.md).  Pinned `wall` (16)
      -- the band is one clean face and the counter the guard stands
      -- behind is a full 16px slab that hides him to the shoulders.
      -- Pinned `counter` (8) every counter is the half cell it is drawn
      -- as -- which is what the room is FOR -- and the price is that the
      -- wall cell's front 8px of depth drops with it: a shallow wall
      -- gains an 8px plinth (reads as a wainscot), and the deep margin
      -- masses that run two to eight cells north-south down the east and
      -- west sides of the fourteen maps that place both drawings (Routes
      -- 5/6/7/8, the five gate 1Fs, the Safari gate and its four rest
      -- houses) corrugate, their exposed flank stepping 16/8/16/8 every
      -- 8px of depth.  The other six -- Route 2, Route 22 and the four
      -- Underground Path huts -- place 50/51 and never 32/33, so they
      -- take the half cell for nothing.  The counters win where it costs:
      -- they are the object the player walks up to and talks over, they
      -- sit mid-room, and the margin masses are pure border filler seen
      -- edge-on.  This also puts GATE and FOREST_GATE on the same footing
      -- at last -- ROUTE_2_GATE draws the forest gates' room tile for
      -- tile and used to be the only one of the three with a 16px front.
      wall = { 0, 32, 33, 41, 43, 45, 58, 61, 62, 72, 74 },
      -- the counter, half a cell high everywhere it is drawn: its north
      -- rim and end caps (7/8), the long run between them (9), the top
      -- surface a counter drawn running north-south wears (23/24), and
      -- the drawn front panel (50/51) standing up as one clean 8px band
      -- with the surface riding the top face.  The guard leans on it
      -- instead of standing behind a wall stub, and a counter that runs
      -- wall to wall (Route 12's pair) matches one that ends in the open.
      counter = { 7, 8, 9, 23, 24, 50, 51 },
      -- 50/51 draws BOTH the counter's front and the wall's base course,
      -- and it is the bottom row of its cell either way -- so a flat pin
      -- has to pick one and be wrong about the other. Pinned `wall` the
      -- counters stood a full 16px; pinned `counter` the deep border
      -- banks corrugated 16/8 for sixteen rows and the room read as
      -- crates. What tells the two uses apart is what is drawn ABOVE:
      -- the wall stacks its panelled course (32/33) over the base, while
      -- a counter carries its own top (7/8/9). So the counter pin above
      -- is the default and this puts the wall back wherever the panel
      -- sits on top of it -- resolved per position, in TileShape.at.
      when_above = {
        [50] = { { above = { 32 }, class = "wall" } },
        [51] = { { above = { 33 }, class = "wall" } },
      },
      -- the tall glass-fronted cabinets: three shelf ranks (34/35)
      -- folded up a 24px box whose top face adopts the drawn top rim
      -- (7/8, pinned `counter` directly above it) through the mesher's
      -- authored-fold rule -- the HOUSE / Red's-house bookcase
      -- treatment.  Deliberately not `bookcase`: that collapses the
      -- drawing to one cell of depth, which would leave the wall cell
      -- behind each cabinet as bare floor, and its cap rule refuses a
      -- row pinned anything but `table`, so the cabinets would lose
      -- their tops as well.
      desk = { 34, 35 },
      -- standing per-pixel props with body, black-outline segmented: the
      -- little tables of the 2F lounges and the Safari rest houses (2/3
      -- the top, 18/19 the legs) and the 2F observation binoculars (36
      -- eyepieces, 52 barrels, 57 pedestal).  Both are drawn face-on
      -- with air between their legs and a clean white floor margin, so
      -- the standee segments whole -- and both were invisible before,
      -- flattened by the walkable-cell rule.  They stand on the floor:
      -- the window band is drawn ABOVE them, and the support rule only
      -- lifts a prop drawn above a box.
      billboard = { 2, 3, 18, 19, 36, 52, 57 },
      -- the plants, in the THIN pool like every other interior plant:
      -- the potted palm that stands in every hut and rest-house corner
      -- (5/6 crown, 21/22 fronds, 37/38 over 53/54 the pot), and Route
      -- 22's wall plant (14/15 crown, 30/31 pot), which stands on the
      -- half-cell planter its base course (50/51) makes -- a planter box
      -- now rather than the 16px pedestal it used to perch on.
      prop = { 5, 6, 14, 15, 21, 22, 30, 31, 37, 38, 53, 54 },
      -- the exit doormat (4 over 20): drawn from straight above, so it
      -- has to lie flat -- and 20 is the $14 water-fallback trap, which
      -- sank every gate's own doorway into a pond lip.
      ground = { 4, 20 },
      -- the flight up to a gate's 2F: real steps climbing east, the way
      -- the drawn treads rise to the right.  Pixel for pixel the same
      -- staircase as Red's house 1F, on the same four tile ids.
      stair_e = { 12, 13, 28, 29 },
      -- the flight down -- to 1F from a gate 2F, into the tunnel from an
      -- Underground Path hut: a sunken stairwell descending westward,
      -- high at the east lip where the player enters.  Again the same
      -- drawing and the same ids as Red's room upstairs.
      stair_down_w = { 10, 11, 26, 27 },
      -- Left to the derived default on purpose: the two floor checkers
      -- (1/17) and every threshold -- the door mats (55/56/94) and the
      -- tile under the door panels (42/59) -- sit in walkable cells, so
      -- the cell rule already lays them flat; and tile 16 is solid
      -- black, which the void rule flattens into exactly the darkness
      -- that should sit above Route 16's north wall.
    },

    -- Viridian Forest's north and south gates.  Tile for tile they are
    -- the same drawing as ROUTE_2_GATE, but they are their own tileset
    -- id, so they need their own copy of the pins.  These two maps never
    -- place the panelled wall course (32/33), so 50/51 is a counter
    -- front here and nothing else -- the half cell it is drawn as costs
    -- this id nothing at all, where GATE pays for it in the wall (see
    -- the note there).  Both ids run 50/51 `counter` now, so the three
    -- rooms that share this drawing -- the two forest gates and
    -- ROUTE_2_GATE -- finally match.  Before this entry the room was a
    -- pond with an island: 72 ($48) sank the north wall's top course, 50
    -- ($32) sank all four counter fronts, and 20 ($14) sank the exit
    -- doormat -- the three stale-cache water ids, all three placed in
    -- one small room.
    FOREST_GATE = {
      -- the wall band, one 16px face: the speckled plaster course (72)
      -- over its dark skirting (74), plus the door pane (41/43) drawn
      -- above the walkable threshold, so the doorway reads as a recess
      -- in the band rather than a door lying flat on the floor (pins are
      -- look-only; the cell stays walkable).  72 is the $48
      -- water-fallback trap and took the whole north wall down with it.
      wall = { 41, 43, 72, 74 },
      -- the four counters, half a cell high: end caps (7/8), the top
      -- surface running north-south (23/24), and the front panel (50/51)
      -- standing up as one clean 8px band with the surface riding the
      -- top face.  50 is the $32 water-fallback trap -- unpinned, every
      -- counter's front cell was a pond notch.
      counter = { 7, 8, 23, 24, 50, 51 },
      -- the potted palms down both side walls, three to a side, in the
      -- THIN standee pool like every other interior plant: 5/6 crown,
      -- 21/22 fronds, 37/38 over 53/54 the pot.  They stack with no gap
      -- between them, and each still segments as its own plant.
      prop = { 5, 6, 21, 22, 37, 38, 53, 54 },
      -- the exit doormat (4 over 20), drawn from straight above so it
      -- lies flat; 20 is the $14 water-fallback trap.
      ground = { 4, 20 },
      -- Left to the derived default on purpose: the two floor checkers
      -- (1/17) and the tile under the door panes (42/59) sit in walkable
      -- cells, so the cell rule already lays them flat.
    },

    -- Celadon's department store and the rooms that share its blockset:
    -- CELADON_MART_1F..5F and the ROOF, the two 2x2 lift cabins
    -- (CELADON_MART_ELEVATOR, SILPH_CO_ELEVATOR), ROCKET_HIDEOUT_ELEVATOR,
    -- the GAME_CORNER with its PRIZE_ROOM, and CELADON_DINER -- twelve
    -- maps off one atlas.  Everything the store owns was wrong: the
    -- U-shaped sales counters read their whole north-south arm as one
    -- drawing and towered to 48px (dragging the wall band they touch up
    -- with them), the merchandise racks fused sideways into 32px
    -- monoliths FOUR tiles deep -- the Poke Mart's failure exactly --
    -- the diner and roof stools sit in walkable cells and so flattened
    -- into the floor entirely, and three separate tiles fell into the
    -- engine's stale water set and sank into ponds indoors.
    LOBBY = {
      -- The two exit cells of every map (the sliding-door threshold, 4
      -- over 20).  20 is $14, which the stale-cache fallback counts as
      -- water in EVERY tileset, and rule 2 judges the whole CELL by it:
      -- both tiles of the doorway recessed into a pond lip just inside
      -- the shop door.  It is a flat mat, and the lift cabins use the
      -- same pair for their car door.
      ground = { 4, 20 },
      -- The wall band stays ONE 16px face.  The blank course (1) and the
      -- skirting course below it (33) are the band itself; everything
      -- else here is drawn BUILT INTO it at 16px, so wall height is the
      -- drawn height and each reads as a fitting jutting from the band
      -- rather than a tower:
      --   6/22    the framed notice beside the stairwell, every floor
      --   2/3/18/19   the pair of pay phones on 1F
      --   46/47   the floor-directory plaque (it also sits at the east
      --           end of 1F's counter top, where 16px reads as a sign
      --           board standing on the counter -- the one placement
      --           that is not wall, and the least bad of the two)
      --   62/63   the lift call-button panel in both 2x2 cabins
      --   72/73/88/89 the framed picture (72 is $48, a water-set id, so
      --           unpinned its top half sank)
      --   68/84   the roof's perimeter safety railing, drawn 16px tall
      --   75/76/77/78/79 the roof parapet and the Rocket lift's cabin
      --           walls (79 also rings the roof map as its border block);
      --           the Game Corner reuses 75/76/77/78 as the dark south
      --           end of its machine banks, where 16px reads as the
      --           bank's end cabinet
      --   91      the dithered wall course above the Prize Room counter
      --           and the roof stairhead
      --   92/93   the Rocket lift's horizontal cabin frame
      --   70/71   NOT wall panelling: the round tables' lower-left and
      --           lower-right rim ($46/$47).  They are here to lift the
      --           terrace and diner tabletops to the one height their
      --           middle can be built at -- see the long round-table
      --           note under `counter`.  The tileset places them in the
      --           two table blocks (29, 49) and nowhere else, so 16px
      --           costs nothing anywhere in the group.
      wall = { 1, 2, 3, 6, 18, 19, 22, 33, 46, 47,
               62, 63, 68, 70, 71, 72, 73, 75, 76, 77, 78, 79, 84,
               88, 89, 91, 92, 93 },
      -- 3F's television sets ($0E/$0F/$1E/$1F): the one drawing in this
      -- tileset that is a deliberate object with a body -- a black-framed
      -- cabinet, a bezel and a lit screen, drawn face-on -- and the same
      -- thing Red's living room stands up.  Six placements: four on the
      -- two goods counters, two against the east wall band.  As `wall`
      -- each was a 16px CUBE with the TV art folded onto one face, so the
      -- counters wore grey filing cabinets and the TV shop read as a
      -- stockroom.  The standee pool cuts the drawing per pixel at 10
      -- voxels of body instead, and the support rule does the rest: the
      -- four counter sets are drawn directly above an authored 8px
      -- `counter` row, so they STAND ON the counter and the tiles they
      -- claim keep rendering as counter top rather than holing it.  (The
      -- art carries a full black frame with light margin inside it, so
      -- the segmentation flood has nothing to drain and the whole set
      -- survives.)  Its own pool, away from `stool`, so a TV never stacks
      -- with a chair drawn beside it.
      billboard = { 14, 15, 30, 31 },
      -- Every service counter in the group, half a cell high like the
      -- Center's and the Mart's.  One 8px band means the drawn front row
      -- stands up and everything above it rides the TOP face in drawn
      -- order -- which is what a counter arm running north-south IS: the
      -- rows above the front are its top surface seen from above, not
      -- height.  Unpinned the arms measured their full 7-row run and
      -- towered to 48px, taking the wall band they touch with them.
      --   38/39/41    the top surface and its end caps
      --   21/48/49    the south front panel and its end caps
      --   54/57       the arms' left and right side edges
      --   36/37/52/53 the games console and its controller laid out on
      --               3F's counter.  This is pixel for pixel the drawing
      --               Red's house pins `relief` -- a prop seen from
      --               ABOVE -- and `relief` is the class it wants.  It
      --               cannot have it here: Structures.buildRelief anchors
      --               its extrusion at y=0 and has no support lookup,
      --               while every placement of this drawing in the
      --               tileset is on a counter TOP.  Pinned `relief` the
      --               cell is claimed, dropped to floor level and punched
      --               a 16x16 hole clean through the counter (verified
      --               in-engine, pass-2 report).  `counter` leaves the
      --               console exactly where relief would put it -- flat,
      --               flush with the surface, art on the top face, drawn
      --               once -- and gives up only relief's three voxels of
      --               lift.  The report carries the one-place engine
      --               change that would free it.
      --   9/25/85/86/87  the round tables of the diner and the roof
      --               terrace: their north rim (9/25 = $09/$19) and the
      --               pedestal course at the south (85/86/87).
      --
      -- THE ROUND TABLES in full, because the shape is a compromise.  The
      -- drawing (block 29, and the same four rows split across blocks 45
      -- and 49 in the diner) is
      --      $09 $27 $27 $19      an octagonal top seen from above, with
      --      $36 $37 $37 $39      a pedestal drawn below its southern
      --      $46 $37 $37 $47      rim
      --      $55 $56 $57 $37
      -- Its four INTERIOR tiles are $37, which is ALSO the light half of
      -- the checkerboard floor and the plain upper wall of the Prize Room
      -- and the roof stairhead, so $37 cannot be pinned at all (see the
      -- closing note).  Left to the detector those four are a two-row
      -- column, which buildVolume reads as a repeat, floors at unit 2 and
      -- builds at 16px -- and with the whole rim pinned `counter` at 8px
      -- the terrace tables came out as grey CUBES sitting on trays.
      --
      -- So stop fighting the 16px and let it BE the tabletop: 70/71
      -- ($46/$47, the lower-left and lower-right rim) move to `wall`, and
      -- the table's whole front course then stands at the same 16px its
      -- middle already does -- one flat disc, the drawn octagon on its
      -- top face and the lower arc folded down its front.  What stays at
      -- 8px is the FAR rim (9/25, and the shared 39/54/57) and the
      -- pedestal (85/86/87): the far rim is occluded by the 16px top in
      -- front of it, and the pedestal is meant to sit low.  16px is also
      -- the right height against the 8px `stool` chairs drawn around it
      -- -- a terrace table you sit at, not a footstool.
      counter = { 9, 21, 25, 36, 37, 38, 39, 41, 48, 49, 52, 53, 54,
                  57, 85, 86, 87 },
      -- Free-standing merchandise racks and glass cases: TALL drawings,
      -- not deep ones.  The four-row rack (42-45 / 58-61 / 64-67 /
      -- 80-83) stands two racks abreast on floors 2F-5F and along the
      -- Game Corner's north wall, and the detector boxed each pair into
      -- ONE 32px slab four tiles deep -- the Poke Mart's exact failure.
      -- A bookcase rank collapses onto a one-cell-deep box at the full
      -- drawn height instead, and the back rows become hidden floor, so
      -- racks standing side by side stay separate objects with an aisle
      -- behind them.
      -- 34/35/50/51 is the glass display case / vending machine, which
      -- the same rule fits at BOTH its drawn sizes: 16px where it wears
      -- the 1F phones or the 3F TV above it, 24px where a counter cap
      -- (38/41) tops it on the roof, the Prize Room and the Game
      -- Corner.  50 is $32, a water-set id, so every one of these cases
      -- stood in a pond before it was pinned.
      bookcase = { 34, 35, 42, 43, 44, 45, 50, 51, 58, 59, 60, 61,
                   64, 65, 66, 67, 80, 81, 82, 83 },
      -- The stools: the diner's chairs, the roof terrace's, the six
      -- rows in front of the Game Corner's machine banks and the four
      -- on 1F.  Their cell's bottom-left tile is 23 ($17), which IS on
      -- the tileset's walkable list, so rule 3 resolved every one of
      -- them to flat ground and they vanished into the floor
      -- completely.  A pin is the only thing that overrides that.  The
      -- drawing carries a full black outline with the floor dither
      -- showing at all four corners, so the standee segments cleanly --
      -- and `stool` keeps its own pool, apart from anything it touches.
      stool = { 7, 8, 23, 24 },
      -- Deliberately NOT pinned:
      --   $37 (55) is three different things -- the light half of the
      --     checkerboard floor, the interior of the round tables, and
      --     the plain upper wall of the Prize Room and the roof
      --     stairhead -- and every class that suits one ruins the
      --     others: `ground` holes the wall and the tabletop, `counter`
      --     turns every second floor tile into an 8px lump, `wall` turns
      --     it into a 16px pillar.  The cell rules already answer the
      --     floor (its cells are walkable through their $45 bottom-left
      --     tile) and the wall (its cells are not), and the tabletop is
      --     answered above by raising 70/71 to meet the 16px the
      --     detector builds there.  Left unpinned on purpose.
      --   $10 (16) is pure black and the void rule already flattens it
      --     to the interior darkness above the Game Corner's wall.
      --   The stair openings (10/11/26/27, 40/56) and the lift doors
      --     (12/13/28/29) all sit in WALKABLE cells and fold into the
      --     facade on their own, which is what the doorway fold is for.
      --   $20/$45 (32/69) are the two floors and are walkable.
    },

    -- Pewter's museum, both floors (the tileset shares the gates' atlas
    -- image but is its own id).  The exhibits were the worst case in the
    -- whole building: 50 is $32, a water-set id, and it is the base row
    -- of EVERY display case, so rule 2 judged each case's bottom cell
    -- water and sank the fossil vitrines, the space shuttle and the
    -- glass cabinets into ponds.  72 is $48 and is the wall band's upper
    -- course, so the north wall recessed too -- leaving its lower course
    -- alone as an 8px stub.  On top of that the benches sat in walkable
    -- cells and flattened away, the corner plants towered to 32px, and
    -- both staircases (also walkable) were flat floor.
    MUSEUM = {
      -- the two street doors on 1F: the same $14 mat trap as the
      -- department store's, flat
      ground = { 4, 20 },
      -- the wall band as one 16px face: the dithered upper course (72,
      -- the $48 water-set id) over the skirting course (74), and the
      -- two framed paintings hung in it (78/79)
      wall = { 72, 74, 78, 79 },
      -- The low partitions that divide both floors -- the tileset's own
      -- counterTiles name 23 ($17) -- drawn exactly like the department
      -- store's counter arms: a light top surface seen from above with
      -- dark side edges.  Half a cell, so they read as barriers you see
      -- over rather than interior walls.  Their north caps and their
      -- south base rows belong to the case group below, at the same 8px.
      counter = { 23, 24 },
      -- Every vitrine in the museum, as tall drawings one cell deep:
      --   7/8/34/35   the run of eight glass cabinets along 1F's north
      --               wall (7/8 is the cabinet's top surface, so the
      --               rank wears it as its top face -- which is why it
      --               is here and not in `counter` with the partitions
      --               whose north cap it also draws)
      --   9/50/51     the low case at 1F's centre (9 the top surface,
      --               50/51 the base panels) and the base row under the
      --               partition ends
      --   25/39/40/44/46/48/49/58/60/63/70/71/83  the fossil vitrine,
      --               four drawn rows inside one black frame: the dark
      --               top surface, the ammonite specimens on their
      --               light bed, the placard, and the base.  Two on 1F,
      --               one on 2F.  Collapsed to one cell of depth it
      --               stands as a 32px case instead of a 16px lid
      --               floating over a pond.
      --   64-69/80-91 the space-shuttle vitrine on 2F, the same drawing
      --               shape three cells wide.
      -- 50/51 is $32/$33 -- the water-set id that sank all of them.
      bookcase = { 7, 8, 9, 25, 34, 35, 39, 40, 44, 46, 48, 49, 50,
                   51, 58, 60, 63, 64, 65, 66, 67, 68, 69, 70, 71,
                   80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91 },
      -- the visitors' benches on 1F: their cell's bottom-left tile is
      -- 18 ($12), which is on the walkable list, so they resolved to
      -- flat ground and disappeared.  Seat-height standees in their own
      -- pool, like the department store's stools
      stool = { 2, 3, 18, 19 },
      -- the corner potted plants (crown 5/6/21/22, pot 37/38/53/54):
      -- the THIN standee pool, like every other interior plant in this
      -- profile.  Unpinned they were a 32px two-cell tower.
      prop = { 5, 6, 21, 22, 37, 38, 53, 54 },
      -- the Old Amber in its rounded case, drawn face-on with a clean
      -- black outline and a light margin at every corner: the standee
      -- with body, segmented so the backing floods away and the amber
      -- inside the outline stays
      billboard = { 76, 77, 92, 93 },
      -- 1F's staircase UP to 2F: a real rising flight climbing east,
      -- the way the treads are drawn (low at the west, high at the
      -- east).  Its cell is walkable, so without the pin it was flat
      -- floor with the stair art painted on it.
      stair_e = { 12, 13, 28, 29 },
      -- 2F's staircase DOWN to 1F: the same flight from above, so it
      -- descends westward -- the player steps on at the east lip.  Same
      -- tile ids Red's bedroom uses for its stairwell, which is the
      -- convention across Gen 1's interior blocksets.
      stair_down_w = { 10, 11, 26, 27 },
      -- Deliberately NOT pinned: 1 and 17 ($01/$11), the two halves of
      -- the checkerboard floor.  Every floor cell's bottom-left tile is
      -- $01, which is walkable, so the cell rule already makes the whole
      -- cell flat ground.
    },

    -- Cinnabar Lab and its three side rooms (trade, metronome, fossil),
    -- the Fuchsia Warden's house, the Fuchsia meeting room and the Safari
    -- Zone's secret house -- seven maps on one tileset.  Every indoor
    -- failure mode shows up here at once: the detector raised the machine
    -- banks as 32px monoliths TWO cells deep, boxed the free-standing
    -- shelf racks the same way (and CAPPED the metronome room's racks at
    -- 16px because their book rows repeat, so a 32px shelf came out a
    -- 4-tile-deep 16px slab), cut every lab bench into a patchwork of
    -- 8/16/32px stubs, flattened the chairs into floor, merged the
    -- meeting room's long partition with the corner plants into a 48px
    -- tower -- and dropped six tile ids into the engine's stale-cache
    -- water set, so the bench tops ($04/$05/$14/$15), the table's monitor
    -- ($48) and the Warden's round specimens ($32) recessed into pond
    -- lips inside the building.  Oak's Lab (the DOJO entry) is the
    -- reference: same rooms, same answers.
    LAB = {
      -- the wall band stays one 16px face.  Blank courses ($22), the
      -- pillar/corner that turns Cinnabar Lab's L ($23), the framed
      -- Pokeball picture (16/17/32/33), the metronome room's row of
      -- wall brackets (48/49 -- drawn INTO a band that is two cells
      -- deep there, so both cell rows stay one 16px face), the vent
      -- panel over Cinnabar Lab's three doorways (24/25), and the low
      -- dark base course with its end caps (42/43) that the meeting
      -- room's partition and the Warden's machine both stand on.
      -- The Warden's big machine (87/88/89 top, 28/71/29 the dial row,
      -- 36/37 the grille row, over 24/25 and the 42-34-34-43 base) is
      -- ALSO wall: it is drawn 32px tall and free-standing, so a
      -- `bookcase` would be the honest shape -- but its grille tiles
      -- 24/25 are the very tiles Cinnabar Lab hangs in its wall band
      -- above the doors, and its base row is the shared $22 band, so no
      -- per-tile pin can make it 32px without either stubbing the Lab's
      -- wall panel or splitting the machine into columns of different
      -- heights.  One clean 16px console beats both.
      wall = { 16, 17, 24, 25, 28, 29, 32, 33, 34, 35, 36, 37,
               42, 43, 48, 49, 71, 87, 88, 89 },
      -- the equipment banks and the shelf racks: TALL drawings, not deep
      -- ones.  Each rank collapses onto a ONE-CELL-DEEP box at its full
      -- drawn height and its back rows become hidden floor -- the
      -- Dojo/Mart treatment, and the only thing that stops the fossil
      -- room's and the secret house's machine walls from being 32px
      -- blocks two cells thick.  69/70 + 85/86 are the cabinet tops,
      -- 10/11 the dial faces, 74/75 + 90/91 the narrow filler columns,
      -- 26/27 the plinth with its feet, 59 the black end pilaster;
      -- 40/41 are the metronome room's and the meeting room's shelf
      -- ranks.
      --
      -- 64/65/66 -- the TOP-TRIM row (one black line, one white
      -- highlight, then grey) that every flat-topped unit in this
      -- tileset wears -- are here too, and this is the load-bearing
      -- decision in the entry.  They used to be `table`.  A `table` is
      -- an authored upright BOX, and the support rule stands a pinned
      -- standee drawn directly above an authored box ON it: every chair
      -- on the FAR side of a table in this tileset is drawn directly
      -- above that table's trim row, so the trade room's two north
      -- chairs and the meeting room's spare chair were lifted onto the
      -- tabletops -- and their cells were re-tiled as tabletop, marching
      -- each table two tile rows north to meet them.  A `bookcase` is
      -- authored but is NOT a box (its art mode is the rank collapse),
      -- so the support rule does not fire and those three chairs stand
      -- on the floor where they are drawn.
      -- Nothing else about the trim changes for the worse.  Where it
      -- caps a shelf rank (64/66 over 40/41 or 10/11, in the metronome
      -- room, the meeting room, the fossil room and the secret house)
      -- it simply becomes the rank's fourth row: the same 32px height
      -- and the same top-face art the cap-adoption rule used to hand it,
      -- minus the 12px stub the trim used to render as BEHIND the shelf.
      -- Where it tops a table or the Warden's bench it becomes that
      -- unit's own 8px back rim, tucked behind the 12px top.
      -- (The one thing it costs is named in the report: the meeting
      -- room's two partitions used to hand this trim to the 16px band's
      -- TOP face -- the mesher gives a full-height course the authored
      -- UPRIGHT row above it -- and now top with their own band art.)
      bookcase = { 10, 11, 26, 27, 40, 41, 59, 64, 65, 66, 69, 70,
                   74, 75, 85, 86, 90, 91 },
      -- the lab furniture, at table height.  The benches in the fossil
      -- and metronome rooms (2/3 the specimen tray, 4/5 + 20/21 the
      -- microscope, 18/19 the tray's rack row) and the big lab tables
      -- (80/81/82 the top, 83/58/84 the front rail and its legs).
      -- 72/73 -- the monitor and the ball lying on the table -- ride the
      -- table's authored height rather than standing as separate
      -- cutouts, exactly as Oak's starter balls do; pinning them also
      -- stops the display frame's black corner brackets from
      -- auto-extracting into standing prisms.  Four of these ids
      -- ($04/$05/$14/$15) plus $48 are the tileset's water-fallback
      -- traps: unpinned they sink into a pond lip in the middle of the
      -- room.  With the trim row moved to `bookcase` the top face of
      -- each table now wears its own drawn surface instead of the trim
      -- -- which is how the Warden's bench finally shows the monitor and
      -- the Pokeball the artist drew on it.
      table = { 2, 3, 4, 5, 18, 19, 20, 21, 58, 72, 73,
                80, 81, 82, 83, 84 },
      -- seats, the 8px standee pool, all of them in WALKABLE cells and
      -- therefore flat floor until pinned: the four chairs round the
      -- trade room's table and the meeting room's spare (14/15/30/31,
      -- a whole cell each) and the little stool tucked under every lab
      -- bench (6/7 its top edge, 22/23 its seat and legs).  6/7 also
      -- carry the bench's apron along their top edge -- the standee
      -- wears a thin dark cap for it, which is cheaper than dropping
      -- the stool to a half-cell drawing with no floor margin.
      -- The chairs on the far side of a table stay on the FLOOR only
      -- because the trim row above them is no longer a box; see the
      -- bookcase group.
      stool = { 6, 7, 14, 15, 22, 23, 30, 31 },
      -- the tall corner plants: two cells of drawing (44/45 + 60/61 the
      -- frond crown, 46/47 + 62/63 the stem and pot), mostly silhouette,
      -- so the THIN standee pool -- as in every other interior.  The
      -- detector had them at 0/8/16/24/32px depending on which corner
      -- they stood in, and in the meeting room it fused them into the
      -- partition and towered the pair to 48px.
      prop = { 44, 45, 46, 47, 60, 61, 62, 63 },
      -- the five round specimens in the Warden's house: one 16x16 cell
      -- each, drawn ROUND with a dithered shell and a lit underside.
      -- Neither a box nor a flat cutout reads them; the round archetype
      -- carves a voxel ball per cell from the drawing's darkest-pixel
      -- outline, which is what they are.  50 is a water-fallback trap,
      -- so unpinned the row sat in five pond lips.
      cylinder = { 50, 51, 67, 68 },
      -- Deliberately NOT pinned: the checker floor (1/38) and the fossil
      -- room's striped carpet (12/13) are walkable cells and already
      -- flat; the doormat (39/55) likewise; the three doorways
      -- (76/77 over 52/53) are walkable and the engine folds them into
      -- the facade; Cinnabar Lab's black surround (54) is authored void
      -- by the void rule; and the bench aprons 8/9 stay flat floor,
      -- which is where the artist drew them -- inside the walkable cell
      -- in front of the bench.
    },

    -- Celadon Mansion's three floors and its roof, plus the Celadon
    -- chief's house -- five maps on one tileset.  The mansion maps are
    -- half interior and half OUTSIDE: the east third of every floor is
    -- the open-air stair landing, so the entry has to keep an outdoor
    -- strip flat while it furnishes the rooms.  The detector towered the
    -- display cabinets, boxed the potted palms into 32px 4-tile-deep
    -- monoliths, raised the 2F larder cabinet as a 48px tower taller than
    -- the walls, gave the same wall band three different heights
    -- (8/16/48) on one map -- and sank the whole cabinet bank AND both
    -- front-door mats into pond lips, because nine tile ids here
    -- ($04/$14/$22/$23/$32/$33/$38/$48/$57) sit in the engine's
    -- stale-cache water set.
    MANSION = {
      -- one 16px face for every wall course, indoors and out: the rooms'
      -- north band (80), the interior partition (30) with its white top
      -- rim (76/77), the doorway lintel over the front door (22/23), the
      -- east exterior wall the landing runs along (74/75) with its
      -- junction pieces (72/73 -- 72 is a water trap -- and 88/89), the
      -- band's feet and corners (90/91/92/93), and the roof's own rim
      -- and corner blocks (78/79).  The roof parapet railing (15 over
      -- 31, with end caps 42/43 and 33/49) is drawn a full 16px tall, so
      -- it stays in the same band rather than dropping to `fence`: on an
      -- open roof a knee-high rail reads as a kerb.  48 and 6/7 are the
      -- rooftop shed's base course.
      wall = { 6, 7, 15, 22, 23, 30, 31, 33, 42, 43, 48, 49, 72, 73,
               74, 75, 76, 77, 78, 79, 80, 88, 89, 90, 91, 92, 93 },
      -- the display cabinets along the north wall of 1F and the chief's
      -- house: TALL drawings, not deep ones, so each rank collapses onto
      -- a one-cell-deep box at its drawn height.  34/35 are the shelf
      -- row of the short cabinets, 40/21 + 56/87 the two rows of the
      -- tall ones (the pair with the trophy in the glass), 50/51 the
      -- plinth.  Their top row is 38/41, pinned `table` below because
      -- the mansion's big tables wear the same trim -- the bookcase
      -- builder adopts it as the rank's CAP, which lands the short
      -- cabinets at 24px and the tall ones at 32px, exactly their drawn
      -- heights.  45/46 + 61/62 + 63/47 is 2F's larder cabinet, four
      -- drawn rows standing free of any wall: 32px and one cell deep
      -- instead of the 48px tower the detector built.
      -- Six of these ids are water-fallback traps ($22/$23/$32/$33/$38
      -- /$57) -- the whole cabinet bank was a pond.
      bookcase = { 21, 34, 35, 40, 45, 46, 47, 50, 51, 56, 61, 62, 63,
                   87 },
      -- table height.  The long tables in 1F and the chief's house
      -- (38/39/41 top edge, 54/55/57 body, 60/58/59 the front rail with
      -- its two legs) and the writing desks on 2F and 3F (36/37/52/53
      -- the back edge with the papers and the ball on it, 64/65/66/67
      -- the body).  The desks' aprons (2/3/85/86 over 18/19) are drawn
      -- into the WALKABLE cell in front and stay flat floor, which is
      -- how the artist placed them.
      -- Known compromise: the rooftop shed on CELADON_MANSION_ROOF is
      -- drawn with the table's own top and body tiles (38/39/41 over
      -- five rows of 54/55/57) with a door punched in its base, so it
      -- comes out a 12px block rather than a shed.  Nothing towers there
      -- any more -- the detector had its east columns at 48px -- and no
      -- per-tile pin can give one drawing two heights.
      table = { 36, 37, 38, 39, 41, 52, 53, 54, 55, 57, 58, 59, 60,
                64, 65, 66, 67 },
      -- the stool at the 2F/3F desk: a whole cell of drawing (2/3 over
      -- 18/19) sitting in a WALKABLE cell, so flat floor until pinned.
      -- The 8px standee pool, seat height, as in Red's rooms.
      stool = { 2, 3, 18, 19 },
      -- the potted palms: two cells of drawing (68/69 crown, 8/9 fronds,
      -- 70/71 stem, 24/25 pot), mostly silhouette, so the THIN standee
      -- pool -- the same numbers the generic HOUSE entry uses, and the
      -- same answer every interior plant gets.  The detector had them as
      -- 32px boxes four tiles deep.
      prop = { 8, 9, 24, 25, 68, 69, 70, 71 },
      -- the front-door mats of 1F and the chief's house.  Their bottom
      -- tile is $14, which the engine's stale-cache fallback counts as
      -- water in every tileset, so the mat -- and the whole cell with it
      -- -- recessed into a pond lip just inside the door.  It is a flat
      -- rug on the floor.
      ground = { 4, 20 },
      -- Deliberately NOT pinned: the interior checker floor (17), the
      -- landing's open-air ground (1), the black surround (16, authored
      -- void), the back and rooftop doors (81-84, walkable and folded
      -- into their facade), the desk aprons (85/86), and the landing
      -- edge (5).
      -- CANNOT be pinned, engine-side: the four staircases (12/13/28/29
      -- the rising flight, 10/11/26/27 the sunken one) are in this
      -- tileset's doorTiles, and Structures' door fold OVERWRITES the
      -- resolved shape of any door cell whose north neighbour is upright
      -- -- without checking `authored` -- so a stair_e / stair_down_w pin
      -- is silently discarded.  The indoor flights therefore read as
      -- doorways folded into the north wall band, which is at least what
      -- they are (you walk into them from the room).  The roof's two
      -- flights, which stand clear of any wall, come out as a shallow
      -- 8px lip -- a stairwell mouth, near enough -- and pinning them
      -- `wall` would be worse: it would plug the openings with a 16px
      -- block in the middle of the roof.  See the report.
    },

    -- Silph Co's 11th floor (the president's office), Bill's house and
    -- the Pokemon Fan Club -- three rooms that share one tileset and
    -- almost no furniture.  The detector raised Silph's side walls as
    -- 48px towers (the drawn band is three cell rows deep, so it
    -- measured the whole column), split the Fan Club's wall band across
    -- 0/8/16px AND a pond lip, boxed Bill's two transporter drums into
    -- 48px slabs five tiles deep, and left every chair flat because they
    -- sit in walkable cells.  Six ids here ($14/$1F/$32/$34/$40/$48) sit
    -- in the engine's stale-cache water set -- including $1F, the main
    -- FLOOR tile, which sank wherever it shared a cell with $48.
    INTERIOR = {
      -- the wall band, one 16px face throughout: the rooms' face-on
      -- courses (52 upper, 68 lower; 16 in Bill's house and Silph's
      -- outer band), the courses seen from above along the south and the
      -- partitions (87 top, 88 bottom), the side walls (89/90), the end
      -- caps and junction blocks (45/46), the framed Pokemon portraits
      -- hung in the band (19/20 over 35/36), and the padded bench built
      -- into the Fan Club's north wall (49/50/51 -- its lower half,
      -- 65/66/67, is drawn into the walkable cell in front and stays
      -- flat, the way the artist drew it).
      -- 93/94 are Silph's CARD KEY door: the block only exists while the
      -- door is locked (data.field.cardKey swaps it out), so it never
      -- appears in maps.lua -- but the probe sees it, and unpinned it
      -- came out 0px/8px in the middle of a 16px wall.
      -- Bill's pipework belongs here too: the stubs either side of each
      -- drum (32/48, 37/53) and the run between them (38/54), all drawn
      -- 16px tall against the band.
      wall = { 16, 19, 20, 32, 35, 36, 37, 38, 45, 46, 48, 49, 50, 51,
               52, 53, 54, 68, 87, 88, 89, 90, 93, 94 },
      -- Bill's two transporter drums: a TALL drawing (four rows of
      -- cylinder plus a base course), not a deep one.  The bookcase
      -- collapse gives each drum one cell of depth at its full 32px
      -- height instead of the 48px, five-tile-deep slab the detector
      -- built, and its top face wears the drum's own lid.  7/8/9/10 is
      -- the lid, 23/24/25/26 and 39/40/41/42 the barrel, 55/56/57/58 the
      -- footing.
      bookcase = { 7, 8, 9, 10, 23, 24, 25, 26, 39, 40, 41, 42,
                   55, 56, 57, 58 },
      -- The big OCTAGONAL boardroom table -- the Fan Club's and Silph
      -- 11F's, the same drawing in both -- half a cell high, and half a
      -- cell on purpose.  A `counter` is ONE band: exactly the drawing's
      -- bottom row stands up as the front and every row above it rides
      -- the top face IN DRAWN ORDER.  For a table drawn in PLAN that is
      -- the only class that reproduces the plan; a taller box wears its
      -- NORTH row's art across the whole top face and smears it.
      --
      -- The octagon itself is cut at TILE granularity, which is the
      -- finest the mesher has: an authored tile is its own 8x8 column,
      -- so the bevel is drawn by choosing which tiles rise.  Reading the
      -- Fan Club rows (Silph is the identical shape eight rows further
      -- down the map):
      --   row 4        72 74 74 74 74 73         6 tiles wide
      --   rows 5-8   72 <----- 8 tiles -----> 73  8 tiles wide
      --   row 9        63 64 64 64 64 81         6 tiles wide
      --   row 10          75 76 76 75            4 tiles wide
      -- 72/73 are the north chamfer, 63/81 the south one, 77/78 the
      -- straight flanks, 74 the north rim and 64 the top itself.  75/76
      -- -- the front apron with its two drawn legs -- is pinned so the
      -- octagon's south edge closes and the legs stand on the front face
      -- instead of lying painted on the floor; it sits in the walkable
      -- cell in front of the table, which is the cell a player stands in
      -- to talk across it, and an 8px apron there reads as standing AT
      -- the table (the same arrangement as the Center's counter).
      -- 79 and 82, the OUTER corner of the south bevel, are `ground` --
      -- see the ground group.
      --
      -- 91/92, the statue's pedestal, ride the top face here rather than
      -- standing with the statue: those two ids are ALSO the wall band's
      -- base blocks where a side wall meets the south course in Silph,
      -- so six tiles at the foot of Silph's walls sit 8px instead of
      -- 16px.  It is a notch at the foot of a wall the player never
      -- faces, and the alternatives are worse in both directions -- a
      -- 16px stub standing in the middle of the boardroom table, or a
      -- paper cutout standing at the foot of every south wall.
      -- 40 and 48 are water-fallback traps: unpinned, the table's whole
      -- north-west cell was a pond, and it dragged the floor tile $1F
      -- sharing that cell down with it.
      counter = { 63, 64, 72, 73, 74, 75, 76, 77, 78, 81, 91, 92 },
      -- The Pokemon statue standing in the middle of both boardroom
      -- tables: a per-pixel cutout, ONE voxel deep, standing ON the
      -- table through the authored-box support rule -- a standee drawn
      -- directly above an authored box rises from that box's top, which
      -- is how the gym's bird statues stand on their plinths and the
      -- potted plant stands on Red's table.  17/18 is the crown and the
      -- head, 33/34 the face and the top rim of the pedestal it stands
      -- in; the pedestal proper (91/92) stays `counter` under its feet.
      -- The four claimed tiles keep rendering as the tabletop they were
      -- cut out of, so the table is whole underneath.
      -- `cutout` and not `prop`: the drawing has NO floor margin -- it
      -- is surrounded on all four sides by the tabletop's own mid grey
      -- -- and the cutout pool's stricter contract makes mid shades
      -- background unconditionally, so the tabletop drains away cleanly
      -- while the black outline, the paint whites and everything they
      -- enclose survive.  Pinned `counter` with the rest of the table
      -- (what it was) the statue was painted FLAT on the tabletop.
      cutout = { 17, 18, 33, 34 },
      -- Bill's desk and the Silph president's, at table height: 11-14
      -- the surface with the terminal and the ball on it, 27-30 the
      -- front edge.  Their aprons (43/44 + 91/92 on the row below) are
      -- drawn into the WALKABLE cell in front; 43/44 belong to the stool
      -- there, not to the desk.
      table = { 11, 12, 13, 14, 27, 28, 29, 30 },
      -- the seats: Bill's desk stool (43/44 over 59/60) and the Fan
      -- Club's four members' chairs (61/62 over 59/60), a whole cell
      -- each.  All of them sit in WALKABLE cells, so they were flat
      -- floor until pinned; the 8px standee pool puts them at seat
      -- height, which is also where a character standing on the cell
      -- ends up.
      stool = { 43, 44, 59, 60, 61, 62 },
      -- flat, and pinned flat on purpose.  31 is the rooms' floor tile
      -- and needs no pin for its 980 walkable placements -- but the
      -- water test runs per CELL on the engine's own stale set, BEFORE
      -- any neighbouring pin can help, so the floor tiles sharing the
      -- Fan Club's and Silph's north-west table cell with $48 sank into
      -- the pond with it.  A pin is the only rule that outranks it.
      -- 1/2 are the curve of Bill's drums where they meet the floor,
      -- drawn below the pinned barrel and flat where they lie.
      -- 79/82 are the OUTER corner of the octagon's south bevel, one
      -- tile beyond 63/81 on each side.  Raised with the rest of the
      -- table they squared both bottom corners off and left an 8px stub
      -- standing in the floor a tile away from the table on each side;
      -- flat they are what they are drawn as -- the table's cast shadow
      -- where the bevel meets the floor -- and the octagon closes with a
      -- clean 45 degree step on all four corners.
      ground = { 1, 2, 31, 79, 82 },
      -- Deliberately NOT pinned: the doormats (70/71) and Silph's warp
      -- pads, stairwells and elevator mouth (3/4, 5/6/21/22, 83-86) are
      -- walkable and already flat; 47 is the black surround outside the
      -- building's footprint and the void rule authors it; 69 is the
      -- shadow course under Bill's drums, drawn into a walkable cell and
      -- correct flat.
    },

    -- The Cable Club rooms and the Bike Shop (one tileset, three maps).
    -- COLOSSEUM and TRADE_CENTER are the same 5x4 room with a different
    -- machine in the middle and a different board on the wall; BIKE_SHOP
    -- reuses the same wall, floor and counter for a showroom full of
    -- bicycles.  Between them the three maps place every tile.
    --
    -- What was wrong: the Bike Shop's bicycles came out at 0 and 8 --
    -- each bike sliced in half at ankle height with its top row missing,
    -- and the leftmost rack fused into the wall and towered to 32.  The
    -- shop's whole L-shaped counter stood at wall height, a 16px slab
    -- you could not see over.  Both Cable Club rooms lost their stools
    -- (a walkable cell, so they flattened to floor) and their machine
    -- came out 0/8/16 in the same object.  And the Game Boy link poster
    -- above the door has $32 in its bottom-left corner, so the poster
    -- had a pond in it -- the shore-set trap, and TRADE_CENTER's link
    -- table carries the other one, $48.
    CLUB = {
      -- The wall band stays ONE 16px face.  6 is the striped panel,
      -- 52 the fluted pillar that breaks it every three cells (its
      -- rounded foot, 53, stands one row lower on the floor and is
      -- walkable, so it stays flat ground in front of the band).
      -- Drawn INTO the band and therefore wall as well: the two
      -- bicycles hung on the Bike Shop's wall (1/2/3 over 17/18/19,
      -- exactly two tile rows = exactly the band's height), the Cable
      -- Club's link poster (48/49/50/51 -- 50 is $32, the shore trap
      -- that had it recessing to -2), and the Trade Center's pair of
      -- lit notice boards (63/68/68/69 over 66/67/67/70).
      wall = { 1, 2, 3, 6, 17, 18, 19, 48, 49, 50, 51, 52, 63, 66, 67,
               68, 69, 70 },
      -- Counters, half a cell high -- the house rule for anything you
      -- lean on.  The Bike Shop's L: the till run's top (7/8, the
      -- tileset's own counterTiles) with its inside corner (54), east
      -- arm (16) and end cap (5), all over the front panel 23/24.  8px
      -- is one clean band, so the drawn front stands up and the counter
      -- top stays a top; at 12 or 16 it reads as a wall stub.
      -- 71/72/73/74 is the TRADE_CENTER link table, which shares that
      -- same 23/24 front: its surface is drawn from ABOVE (two Game
      -- Boys lying on it, cables between), so it belongs riding the top
      -- face, not standing up.  72 is $48, the second shore trap.
      counter = { 5, 7, 8, 16, 23, 24, 54, 71, 72, 73, 74 },
      -- The Colosseum's battle machine: a console drawn face-on, four
      -- tiles wide and three rows tall, grilled side towers (59/62 and
      -- 55/58), a dark screen bay (60/61, 56/57) and the two white
      -- horns that crown it (64/65).  24px is its drawn height, so
      -- `desk` folds the whole drawing upright as one machine instead
      -- of the 0/8/16 rubble the detector left.
      desk = { 55, 56, 57, 58, 59, 60, 61, 62, 64, 65 },
      -- The two stools that flank each Cable Club machine: seat 42/43
      -- over base 38/39, in every one of the four placements across
      -- both rooms and nowhere else in the tileset.  Their cells are
      -- walkable, so without a pin they were floor; at seat height a
      -- character standing on one sits on it.
      stool = { 38, 39, 42, 43 },
      -- The showroom bicycles -- six of them standing on the Bike Shop
      -- floor, in two columns, each drawn 3 tiles by 2 side-on.  The
      -- THIN standee pool, not `bookcase`: a bike is nearly all air
      -- (two wheel rings and a frame), and collapsing a rack of them
      -- onto a one-cell-deep box at full height would trade six
      -- bicycles for one blank 32px panel wearing a bicycle print.  As
      -- cutouts they segment cleanly -- the drawing has floor margin on
      -- three sides and its own black outline seals the wheels -- and
      -- the standee builder's connected-component split gives each bike
      -- its own feet in its own cell even where a lower bike's
      -- handlebar stem touches the wheel of the one drawn above it.
      -- 11/12/14 the saddle and bar row, 27/28/9 the frame and wheels.
      prop = { 9, 11, 12, 14, 27, 28 },
      -- The crate and the standing pump beside the shop's south wall
      -- (29/13 over 21/22), twice.  A separate pool from the bicycles
      -- on purpose, and the thicker one: a crate is a deliberate object
      -- with a body, where a bike is a silhouette.
      billboard = { 13, 21, 22, 29 },
      -- The Bike Shop floor's second checker phase.  It is NOT in the
      -- tileset's walkable list, so the cells it floors resolve by rule
      -- 4 and it rose as a wall stub -- or, worse, got swept into the
      -- bicycle beside it and dragged to 8px.  It is floor; it is flat.
      ground = { 30 },
      -- Left to the derived default on purpose:
      --   $0F $1F    the main floor checker -> walkable, ground
      --   $0A $1A    the dark slab under the Bike Shop's exit warp -> a
      --              threshold mat, walkable, flat
      --   $35        the pillar's rounded foot -> its cell is walkable
      --              (you walk in front of the pillar), so it lies flat
      --              against the 16px band, which is what a plinth does
      --   $26-$29 $2C-$2F  the octagon painted on both Cable Club
      --              floors.  Ground markings seen from above, and every
      --              cell they sit in is walkable, so rule 3 already
      --              keeps them perfectly flat.  ($26/$27 are shared
      --              with the stool bases above and pinned there; they
      --              appear nowhere else in either room.)
    },

    -- The S.S. Anne, inside: both cabin decks and their corridors, the
    -- bow, the kitchen, the captain's room -- and two Kanto houses
    -- (Cerulean's badge man, Fuchsia's Good Rod fisher) that borrow the
    -- liner's furniture set.  Twelve maps, and SS_ANNE_CAPTAINS_ROOM plus
    -- SS_ANNE_KITCHEN between them place every tile the group uses.
    --
    -- Everything was wrong here, in every one of the ways indoors goes
    -- wrong.  The wall-touching cabin table and the BED were merged into
    -- the wall and towered to 32px, so a bunk read as a bank of lockers
    -- wearing a porthole on top.  The corridor wall band measured 24px
    -- instead of 16.  In the two houses the band came out at height 0 --
    -- the drawing runs off the top of the map, so the detector had no run
    -- to measure and the room had no walls at all.  Every stool, chair and
    -- staircase sat in a WALKABLE cell and flattened to floor, so the
    -- captain's room had no stairs, no chairs and no seat.  And the
    -- barrels' top-left tile is $48, which the engine's stale-cache shore
    -- set counts as water in every tileset but SHIP_PORT: each barrel had
    -- a pond dug into its lid.
    SHIP = {
      -- The wall band stays ONE 16px face.  Blank courses (16), the
      -- lower trim (18/19), the portholes (2/3), and the band's corner
      -- pieces where a corridor meets it (32/33 white, 48/49 trim,
      -- 34/50 the black outer corner).  $32 (50) is the shore-set trap:
      -- unpinned it recesses into a pond lip in the middle of a
      -- bulkhead, and it drags the whole 16x16 cell down with it,
      -- because rule 2 judges a cell by its bottom-left tile.
      --
      -- The black rim is wall too, not void: 17 is the band's cap seen
      -- from above (so the fold tops the bulkhead with it), 21/22 the
      -- vertical faces that run down both sides of every corridor, 51
      -- the ship's south bulkhead, and 5/6/37/38 the four corners of the
      -- notch each cabin doorway is cut into.  Left to the detector
      -- these came out 8, 16, 24 and 48 in the same room.  Only $01 --
      -- pure black, the space OUTSIDE the hull -- is left alone: the
      -- void rule flattens it, which is what darkness should do.
      --
      -- 14/15/30/31 are the cabin door drawn INTO the band (its cell is
      -- walkable, since the player steps on it to warp, so unpinned the
      -- door punched a flat hole through the wall).  84/85 are the
      -- captain's chair BACK, drawn into the band above his seat -- so
      -- the chair reads as a high-backed swivel chair jutting from the
      -- wall instead of a separate tower.  45/61 are the bow deck's
      -- rope rail and 46/47/62/63 its stepped bulwark: the same 16px
      -- course, so the open deck is fenced at one height.
      wall = { 2, 3, 5, 6, 14, 15, 16, 17, 18, 19, 21, 22, 30, 31, 32,
               33, 34, 37, 38, 45, 46, 47, 48, 49, 50, 51, 61, 62, 63,
               84, 85 },
      -- Every table in the group, at 12px: the kitchen's three banquet
      -- tables (twelve tile rows deep), the counter run along the
      -- kitchen's south wall, the captain's desk, and the writing table
      -- in the two houses.  Corners 9/12, north edge 10, side edges
      -- 25/28, the surface 44, the plain apron 11 and the drawer front
      -- 59/60.  One 8px band folds up, so the drawn apron stands as the
      -- front and every row above rides the top face in drawn order --
      -- which is how the tableware stays tableware: the plate (26), the
      -- covered platter (64/65/80/81), the kitchen stove's burner grid
      -- (53) and the captain's open book (68/69) are all drawn FROM
      -- ABOVE, so they belong lying on the top face, not standing up as
      -- cutouts.  59/60 doubles as the chest of drawers at the foot of
      -- every cabin bunk; 12px puts it a hand above the mattress, which
      -- is where a bedside chest belongs.
      table = { 9, 10, 11, 12, 25, 26, 28, 44, 53, 59, 60, 64, 65, 68,
                69, 80, 81 },
      -- The cabin bunk: a mattress drawn from above, so its art stays on
      -- the TOP face and it lies low.  70/71 the pillow, 86/87 the
      -- mattress.  (Its drawer end is in `table` above.)
      bed = { 70, 71, 86, 87 },
      -- Seats, in the standee pool: the round stool that appears in
      -- every cabin, the badge house and the captain's room (7/8 seat
      -- over 23/24 legs), and the captain's own chair (66/67 seat over
      -- the same 23/24 base, its back pinned into the wall above).
      -- Seat height 8 keeps a character standing on the stool's
      -- (walkable) cell sitting at seat height rather than floating.
      -- The drawings have real floor margin on all four sides, so the
      -- black-outline flood eats the checker around them and leaves the
      -- seat whole.
      stool = { 7, 8, 23, 24, 66, 67 },
      -- The captain's storage rack: three shelf ranks (54 left, 43
      -- right) drawn four tile rows tall against the wall.  TALL, not
      -- deep -- the bookcase builder collapses it onto one cell of depth
      -- at its drawn height, and adopts the row above (9/12, pinned
      -- `table` as the tabletop corners they also are) as its cap.
      -- Boxed by the detector it was a 16px stub with the wall beside it
      -- towered to 24.
      bookcase = { 43, 54 },
      -- The galley barrels -- three down the kitchen's east wall, one in
      -- the captain's room, one in each house.  A per-pixel cutout in
      -- the THIN pool, the treatment Lt. Surge's trash cans get: 72/73
      -- the lid, 88/89 the banded body.  72 is $48, the shore-set trap
      -- that had each barrel resolving to water at -2.
      prop = { 72, 73, 88, 89 },
      -- The stairs, both flights, in every map that has them (1F, 2F,
      -- 3F, B1F and the captain's room).  Same two drawings the whole
      -- game uses, and the warp table says which is which: 41/42/57/58
      -- is the light flight that always leads UP a deck, climbing east
      -- the way its treads step; 39/40/55/56 is the dark stairwell that
      -- always leads DOWN, sinking westward.  Both cells are walkable,
      -- so unpinned both were flat floor and the decks did not connect.
      stair_e = { 41, 42, 57, 58 },
      stair_down_w = { 39, 40, 55, 56 },
      -- Left to the derived default on purpose:
      --   $01        pure black outside the hull -> void, flat darkness
      --   $04 $23    deck planking and grating   -> walkable, ground
      --   $0D $1D    cabin floor checker         -> walkable, ground
      --   $4A        cabin door threshold        -> walkable, ground
      --   $24 $34    the dark slab under the exit warp in the cabins and
      --              the two houses: a threshold mat with no wall around
      --              it, walkable, and flat is the honest reading
      --   $14        the SEA around SS_ANNE_BOW.  It is the one tile id
      --              the stale-cache water set names in every tileset,
      --              and here that guess is simply RIGHT -- the bow deck
      --              really does stand in open water, so it is the one
      --              trap tile in this group that must NOT be pinned.
    },

    -- Vermilion Dock: the quay, the boarding gangway, and the S.S. Anne
    -- herself moored alongside.  One map, and it is the only place in
    -- the game where a whole VESSEL is drawn as map art rather than as a
    -- building sprite.
    --
    -- The detector read the liner as a volume and raised her 48px --
    -- three cells, taller than she is long is wide -- with her columns
    -- stepping 48/40/24/0 across the hull, so the drawing was folded
    -- UPRIGHT and smeared up a lumpy monolith.  Both ends of the hull
    -- fell to 0 instead, and the port bow ($40/$41/$51) sat in a cell
    -- whose bottom-left tile is open water, so rule 2 sank it to -2 and
    -- the ship had a hole in her nose.
    --
    -- (This tileset is the one place the engine does NOT count $32 and
    -- $48 as shore -- Map.lua's NO_SHORE_TILESETS -- because $32 IS the
    -- gangway here.  So the usual shore trap does not apply, and $14 is
    -- honest open water.  Nothing in this entry is dodging a water
    -- fallback; the whole entry is about the ship.)
    SHIP_PORT = {
      -- The hull, every tile of her, as a `roof`: a box wearing its art
      -- on the TOP face.  That is what the drawing IS -- the liner seen
      -- from above and slightly astern, funnels and boats and deck rail
      -- on the top rows, hull plating on the bottom two -- so folding it
      -- upright was always going to smear.  28px of freeboard reads as a
      -- liner beside a quay at 0 and water at -2 without towering, and
      -- the side bands crop from each edge tile's own art, so the flank
      -- the player faces wears the hull plating that is drawn there.
      -- Rows north to south: bow rail and boat deck (0/2-7/9/11-15),
      -- superstructure (16-31), midships (32-47), waterline strake
      -- (48-53 and 61-63 in the stern), hull plating (64-69, 77-79) and
      -- the boot topping (81-85, 90-93).
      roof = { 0, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 14, 15,
               16, 17, 18, 19, 21, 22, 23, 24, 25, 28, 29, 30, 31,
               32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 44, 45, 46, 47,
               48, 51, 52, 53, 54, 55, 56, 57, 61, 62,
               64, 65, 66, 67, 68, 69, 77, 78, 79,
               81, 82, 83, 85, 90, 91, 93 },
      -- The quayside crates, a 2x2-tile box each (86/87 lid, 1/80
      -- body), stacked two cells deep in all four corners of the dock,
      -- and the pallet stacks flanking the gangway head (49).  A crate
      -- IS a 16px cube: one course, art folded up the face it shows.
      -- Unpinned the corner stacks fused into one taller volume.
      wall = { 1, 49, 80, 86, 87 },
      -- The delivery van parked on the north quay: drawn face-on, four
      -- tiles by two, with clear pavement all round it -- so it takes
      -- the standing per-pixel cutout with a body (10 voxels), not a
      -- rectangular block that would swallow the air above its cab.
      -- 72/73/74/75 the cab and box, 88/89/60/76 the wheels and skirt.
      billboard = { 60, 72, 73, 74, 75, 76, 88, 89 },
      -- Left to the derived default on purpose:
      --   $0A        the quay's paving -> walkable, ground
      --   $32 $3B    the gangway planks -> walkable, ground, so the walk
      --              from the quay to the warp stays flush at 0 and
      --              meets the hull's flank rather than climbing it
      --   $14        open water -> the tileset's own water, -2
      --   $3A        the shaded strip along the quay's foot.  Its cell's
      --              bottom-left tile is water, so rule 2 puts it at
      --              water level -- which is correct: it is the dock's
      --              shadow lying ON the water, and the 2px lip between
      --              it and the paving is exactly the shoreline the
      --              water class exists to draw.
    },

    -- The facilities: twenty-one maps off one 96-tile atlas -- Silph Co's
    -- ten office floors, the four Rocket Hideout basements, the four
    -- Pokemon Mansion floors, the Power Plant, and the Cinnabar and
    -- Saffron gyms.  One pin therefore has to read right in a laboratory,
    -- an open-plan office, a burnt mansion and a gym at once; where a
    -- graphic genuinely means two things the note says which reading won.
    -- The failures are the usual indoor ones, louder: the detector raised
    -- whole wall COLUMNS to 48px, stood the lab consoles up as 32px
    -- cabinets towering over the very band they are drawn INTO, fused
    -- vertical runs of computer terminals into 48px monoliths, boxed the
    -- potted-plant rows into one slab wearing leaves on its top face, and
    -- left both staircases lying flat on the floor.  Silph Co's lobby
    -- island is tile $14 -- the engine's stale-cache water id -- and sank
    -- into a pond in the middle of the foyer.
    FACILITY = {
      -- The wall band stays ONE 16px face: the dark courses (42/58
      -- horizontal, 43/44 vertical, 45/46 the top corners, 59/60 the
      -- bottom caps) and Silph Co's own pale striped band (87/89).  A
      -- north-south run of 43/44 is one continuous drawing, so unpinned
      -- the detector measured the whole column and raised it to 48.
      --
      -- Everything DRAWN BUILT INTO that band is `wall` too, the
      -- Center's-healing-console rule, so it reads as equipment jutting
      -- from the band rather than a separate tower:
      --   74/75 the machine's two dials over 76/77 its footed base -- one
      --     graphic serving the Cinnabar Gym's quiz consoles, Silph Co's
      --     and the Power Plant's equipment banks and the Mansion's lab
      --     rigs.  Drawn three rows tall under a one-row wall cap, which
      --     is why the detector called it 32
      --   9/10 screen over 25/26 base: the computer terminal.  It is
      --     ALSO the free-standing maze wall of Rocket Hideout B2F/B3F
      --     and the terminal rows of the Power Plant hall, and 16 -- its
      --     drawn height -- is right in every one of them
      --   64/80 the Mansion 2F balustrade seen face-on, 65/81 its
      --     north-south run.  65 repeats down a whole column, so it
      --     towered exactly like the wall did
      --   86/88 the lift doors of Silph Co: a walkable warp cell, but a
      --     pin is look-only, so the doors stand in the wall band
      --     instead of lying flat as a mat (the Center does the same
      --     with its window/warp tile)
      --   8/24 and 36/37 the shutters the card-key doors and the
      --     Cinnabar Gym quiz gates stamp CLOSED at runtime
      --     (field.cardKeyDoors' blocks $54/$5F/$2D).  They are in no
      --     map's block list, so nothing but this line covers them; the
      --     detector read them as an 8px stub lying in the doorway
      wall = { 8, 9, 10, 24, 25, 26, 36, 37, 42, 43, 44, 45, 46,
               58, 59, 60, 64, 65, 74, 75, 76, 77, 80, 81, 86,
               87, 88, 89 },

      -- The tall display cabinet of the Mansion and Silph 3F/8F/9F: cap
      -- row 40/41 over two ranks of 56/57, one cell wide and drawn FOUR
      -- rows tall.  A tall drawing, not a deep one, so it takes the
      -- Mart's shelf-rack treatment and collapses onto a one-cell-deep
      -- box at its full 32px -- as `wall` it flattened into a bench two
      -- cells deep, which is the shape of its footprint, not the shape
      -- of the thing.  Its base course is the computer terminal's own
      -- 25/26, listed under `wall` above and therefore shared: that
      -- stays a 16px block, and reads as the cabinet's plinth.
      bookcase = { 40, 41, 56, 57 },

      -- The grey slab family -- every desk, bench, worktop and service
      -- counter in the tileset is cut from these seven pieces: 13/14 the
      -- top corners, 2 the top edge between them, 29/30 the body's side
      -- edges, 53 its fill, 68/69 the legs, 18 the counter's front panel
      -- (the tileset's own counterTiles).
      --
      -- `counter` -- 8px, half a cell -- not `table` or `desk`, because
      -- the drawing is a TOP surface seen from above with one row of
      -- front elevation at its south end: one clean band folds exactly
      -- that bottom row (68/69 legs, or 18) up as the front and rides
      -- every row above it on the top face in drawn order, which is what
      -- a seven-cell Silph Co bench actually looks like.  At 12 or 16
      -- the same drawing reads as a wall stub, the failure the Center's
      -- counters are pinned against.
      --
      -- 13/14 and 29/30 double as the CAP and body of the wall consoles
      -- (blocks $60/$62/$64/$66/$7F).  The benches win the tie on count
      -- -- 142 block placements across 18 maps against the consoles' 105
      -- across 14 -- and the compromise costs the consoles nothing: the
      -- capped rows sit NORTH of the 16px dial face, so an 8px ledge
      -- behind a 16px machine is occluded from every southward camera.
      counter = { 2, 13, 14, 18, 29, 30, 53, 68, 69 },

      -- Plants, the thin standee pool, as in every other interior.  Two
      -- drawings: the tall potted palm of Silph Co, the Hideout and the
      -- Mansion (crown 5/6/21/22 over pot 7/15/23/31, a 1x2-cell
      -- object), and the gym planter of Cinnabar, Saffron and the
      -- Mansion (crown 39/47, bowl 55/63, box 61/62).  Unpinned the
      -- detector fused a six-plant row into one box wearing the leaf
      -- dither as a lid.  The crown's checker highlights share the
      -- floor's shades so the mask drains some of them -- the same
      -- accepted trade as the Center's bush.
      prop = { 5, 6, 7, 15, 21, 22, 23, 31, 39, 47, 55, 61, 62, 63 },

      -- Both flights UP, both climbing EAST.  3/4/19/78 is the one-cell
      -- open staircase of the Mansion (1F->2F, 2F->3F) and the Hideout
      -- (B1F->Game Corner): white treads whose risers step up toward the
      -- upper right.  90/91 over 67/52 is Silph Co's own stairwell, set
      -- into the north wall band on every floor -- courses of tread whose
      -- east ends step back one notch at a time.  BOTH cells are
      -- WALKABLE (19 and 67 are the tileset's warp tiles), so unpinned
      -- they resolved to flat ground and the steps were painted on the
      -- floor.  Silph's drawing is the one genuinely ambiguous flight in
      -- the tileset -- read as a west rise it builds a ramp that leaves a
      -- gap against the east jamb, so east it is, which also makes one
      -- consistent story out of every up-stair in the group.
      stair_e = { 3, 4, 19, 78, 52, 67, 90, 91 },
      -- The staircase DOWN (11/12/27/28): three treads in a black
      -- stairwell, shortening and darkening west to east, so the flight
      -- descends EAST into the dark.  One graphic again, for every
      -- down-stair in the group.  (Where the Mansion 3F variant hangs
      -- directly under the wall band, block $73, the engine's door fold
      -- claims the cell first -- 27 is one of the tileset's doorTiles --
      -- and stands the art up in the band as a doorway.  That reads
      -- fine, and the fold runs after this profile, so it is not
      -- something a pin can or should undo.)
      stair_down_e = { 11, 12, 27, 28 },

      -- The rubble drifts of the Mansion and the Power Plant (83/84 over
      -- 54/38): two black-outlined boulders per cell on a plain grey
      -- ground, tiling wall-to-wall across whole rooms.  Drawn ROUND, so
      -- they take the overworld canopy's archetype -- one voxel hull per
      -- 16x16 cell carved from the darkest-pixel outline -- which is the
      -- only class that keeps a repeating field as separate lumps: a
      -- standee pool would cluster a whole drift into one giant flat
      -- cutout, and the volume path gave 16px slabs with 48px towers
      -- wherever a drift touched a wall.
      cylinder = { 38, 54, 83, 84 },

      -- Silph Co 1F's lobby island (tile $14), the cross-shaped dither
      -- the reception terminals ring.  $14 is one of the three ids the
      -- engine's stale-cache water set claims in EVERY tileset, and it
      -- is not on this tileset's walkable list, so it fell straight to
      -- `water` and opened a pond in the middle of the foyer.  It is a
      -- floor-level mat drawn from above: flat.
      ground = { 20 },

      -- Left to the derived defaults on purpose, having been checked:
      --   51, the Hideout's black fill, is all-black art, so the void
      --     rule already flattens it -- which is what a room's interior
      --     darkness should be
      --   32/33/48/49 -- the four quarter-tiles the Hideout's spinner
      --     arrows and the Saffron/Silph warp diamonds are assembled
      --     from -- and 94, the Hideout's floor panel, are on the
      --     tileset's walkable list and come out flat ground unaided
      --   1 (the checker floor), 17 (the Mansion's upper-floor boards)
      --     and 66/82 (the entrance carpet) likewise
      --   the other two stale-cache water ids, $32 and $48, are never
      --     placed by any of the twenty-one maps, so only $14 above
      --     needed the guard
    },

    -- Pokemon Tower's seven floors and Agatha's room (one tileset).
    -- Every floor is the same octagonal chamber: a ring of wall panels
    -- ($09/$0A over $19/$1A) cut out of a mid-grey mass ($11), with a
    -- field of gravestones inside it, and Agatha's room is that chamber
    -- shrunk.  The ring and the mass the detector already reads as one
    -- 16px course (probed) -- they are listed anyway so the answer is
    -- authored rather than inferred from a repeat count, and so the
    -- panels can never fuse into the gravestones that touch them.
    -- What the detector got WRONG was everything else: the headstones
    -- came out as 8px stubs with their arched tops dropped, both
    -- stairwells were flattened by the walkable-cell rule, and the
    -- potted palms lost their crowns to a 16px box.
    -- (Nothing here needs pinning against the void rule: the tileset's
    -- one all-black tile is $47, and no map in the group places it.)
    CEMETERY = {
      -- One 16px course: the chamber's wall ring ($09/$0A over
      -- $19/$1A), the grey mass beyond it ($11) so the room reads as a
      -- chamber cut into solid stock rather than a fence standing on a
      -- plain, and Agatha's north band ($20 over $30).
      wall = { 9, 10, 25, 26,
               17,
               32, 48 },
      -- The reception counter of POKEMON_TOWER_1F -- the only counter in
      -- the group, and the ROM's own counterTiles for this tileset name
      -- $12 as exactly that.  It is an L that fences the receptionist
      -- into the south-east corner: the east-west arm drawn face-on
      -- ($02 the surface over $12 the front panel, eight cells of it)
      -- meeting the north-south arm drawn from above ($1D/$1E, eight
      -- tile rows, which the volume path would have towered to 64px).
      -- The first pass put all four in `wall` and the barrier came out
      -- a full-height partition with the receptionist hidden behind it
      -- to the shoulders.  Half a cell is what a counter is: she leans
      -- on it, the drawn surface ($02) rides the top face and the drawn
      -- panel ($12) folds up the front, and both arms come out the same
      -- height so the corner turns cleanly instead of stepping.  The
      -- cells stay blocked either way -- pins are look-only.
      counter = { 2, 18, 29, 30 },
      -- The gravestones ($05/$06 over $15/$16): a headstone drawn
      -- face-on, one per cell, 314 of them across the seven floors and
      -- Agatha's room.  The volume path measured the drawing as its
      -- bottom row alone and left an 8px stub -- the plinth without the
      -- stone.  `post` is the per-CELL standee pool: each cell is
      -- extracted on its own as a per-pixel cutout 6 voxels deep, so
      -- the arched top comes back and a 4x2 block of graves stands as
      -- eight separate stones instead of one 32px sheet with the back
      -- row floating above the front (which is what one shared
      -- billboard cluster would have made of them).  The stone's white
      -- side margins let the background flood in; its own white checker
      -- band is sealed by the black arch and survives.
      post = { 5, 6, 21, 22 },
      -- The flight UP to the next floor ($03/$04 over $13/$14): real
      -- rising steps, climbing east the way the risers are drawn (short
      -- at the west, tall at the east -- the same drawing idiom as Red's
      -- house).  Its collision tile is $13, which IS in the tileset's
      -- walkable list, so rule 3 had laid the whole flight flat; and its
      -- south-east tile is $14, the water-fallback trap id -- harmless
      -- only because the cell's own bottom-left is $13, and pinned here
      -- so it can never matter.
      stair_e = { 3, 4, 19, 20 },
      -- The flight DOWN ($0B/$0C over $1B/$1C): a sunken stairwell.
      -- The drawn step edges are high and lit at the WEST and fall away
      -- dark to the east, so the flight descends eastward -- the mirror
      -- of Red's bedroom stair.  Walkable ($1B) and flattened for the
      -- same reason as the flight up.
      stair_down_e = { 11, 12, 27, 28 },
      -- The potted palm that flanks Mr. Fuji's shrine on 7F and stands
      -- in Agatha's room ($27/$2F crown, $37/$3F fronds, $3D/$3E
      -- planter): a plant, so the THIN standee pool, like every other
      -- interior plant.  It is drawn 24px tall across THREE tile rows,
      -- which is why the box path dropped its crown row entirely and
      -- kept a 16px planter; a standee takes the whole drawing at its
      -- real height.  It backs onto the wall ring, and a separate pool
      -- keeps it from being absorbed into it.
      prop = { 39, 47, 55, 63, 61, 62 },
      -- (Nothing else needs an entry.  The tower's floor ($01) and 5F's
      -- healing pad ($22) are walkable, so rule 3 lays them flat where
      -- they are drawn; the mass, ring, graves, stairs and palm above
      -- are every other tile the eight maps place.)
    },

    -- The two Underground Paths (Route 5<->6 north-south, Route 7<->8
    -- west-east): one blockset, two maps, and the plainest geometry in
    -- the game -- a tiled corridor cut out of black.  Most of it was
    -- already right, because the black it is cut from ($10) is solid
    -- black and the void rule flattens it (`10v00` over every border
    -- block), and the lattice floor ($0B/$0C) with the diagonal shadow
    -- strip along its west wall ($15/$18) are walkable and lie flat.
    -- Two things were not.
    --
    -- The SOUTH rim.  The corridor's near wall is drawn as a single 8px
    -- light line ($02) with black under it, so the volume builder
    -- measured a one-row drawing and raised half a course -- an 8px
    -- kerb (`02w08` along the whole bottom row of
    -- UNDERGROUND_PATH_WEST_EAST) facing a proper 16px far wall
    -- (`06w16`/`09w16`).  Pinned, the corridor closes with one band all
    -- round.  The east and west rim lines ($16/$17) already read 16 --
    -- their columns repeat -- and join the same authored course so the
    -- whole enclosure is one decision.
    --
    -- The STAIRS.  $03/$04 over $13/$14 is a real flight drawn in
    -- profile, treads climbing to the upper right, and it is the warp
    -- back up to the surface at both ends of both corridors.  Its cell
    -- is walkable, so it resolved to flat ground and the staircase was
    -- a painting (`03g00 04g00 / 13g00 14g00`).  stair_e builds the
    -- flight the drawing shows, rising east.  $14 is also the $14
    -- WATER-FALLBACK id: the walkable cell was hiding the trap here
    -- rather than dodging it, and the pin settles it either way.
    UNDERGROUND = {
      wall = { 6, 9,               -- $06 over $09, the far wall band
               2,                  -- $02, the near wall's light line
               22, 23 },           -- $16/$17, the east and west rims
      stair_e = { 3, 4, 19, 20 },  -- $03/$04 over $13/$14
      -- The blockset also carries the wall's unplaced corner variants
      -- ($05/$08 north-west, $07/$0A north-east, $11 south-west, $12
      -- south-east).  Neither map places them; they belong with the
      -- wall band above if one ever does.
    },

    -- The approach to the Pokemon League: two maps, INDIGO_PLATEAU (the
    -- forecourt the League itself stands on) and ROUTE_23 (the long
    -- climb up to it, with its badge-check gates).  Everything this
    -- blockset draws is one piece of architecture -- striated rock
    -- walls, white pillars, and the bird STATUES that line both the
    -- avenue and the plaza.  29 of its 73 blocks are never placed, so
    -- every tile named below really is one of these two maps'.
    --
    -- A statue is built exactly like the badge gyms' (see GYM above):
    -- one cell of FIGURE ($10/$12 over $28/$29) standing on one cell of
    -- PLINTH ($15/$16 the cap over $30/$31 the plaque).  47 of them --
    -- 12 on INDIGO_PLATEAU, six a side down the avenue, and 35 more
    -- across ROUTE_23's plaza (blocks $42/$43; the $25/$26 twins that
    -- stand the same statue on grass are never placed).
    --
    -- What the detector made of them is the bug this entry exists for.
    -- On the avenue the statues stack with NO gap: the plinth's plaque
    -- row is drawn directly above the next figure's head, so the
    -- flood-fill joined all six of a column into ONE region 24 tile rows
    -- tall, and the volume builder's repeat scan read 32px down one half
    -- of the drawing and 24px down the other.  Each row came out as a
    -- continuous stepped RIDGE of boxes wearing the statue art folded
    -- onto its south face -- probed INDIGO_PLATEAU tiles (16,12)-(17,35)
    -- at 32/24 and (22,12)-(23,35) mirrored.  ROUTE_23's plaza statues
    -- stand alone and fared no better: 24px boxes with the figure's top
    -- row skipped outright.
    --
    -- Pinned the gyms' way the ridge becomes statues.  The plinth is a
    -- SOLID 16px `wall` block; the figure is a per-pixel cutout 5 voxels
    -- deep (the thin `prop` pool) that rides the plinth's top face
    -- through the authored-box support rule and collapses to the
    -- plinth's SINGLE cell of footprint -- Structures' wall-support case,
    -- so the base never marches backwards.
    --
    -- The one thing the gyms did not have to deal with: $28/$29 is
    -- SHARED.  The same bird is drawn again at the foot of every white
    -- pillar, framed there by the pillar's black edge ($25/$26 over that
    -- same $28/$29, blocks $18/$1B) -- 80 of them, 76 down ROUTE_23 and
    -- four on INDIGO_PLATEAU (its two outer corners and the pair
    -- flanking the League's recess).  So $25/$26 joins the same pool:
    -- pinning half a cell would have stood a half-height bird under a
    -- wall.  That in turn is why the pillar itself is pinned -- see the
    -- last paragraph of `wall`.
    PLATEAU = {
      -- ONE 16px course for every piece of masonry here.
      --
      -- $03 is the striated rock face, 2436 placements and the bulk of
      -- both maps.  It already read 16 nearly everywhere, but in the
      -- columns of INDIGO_PLATEAU's rim that stand over a corner pillar
      -- the repeat scan came out 24 -- a stagger in the plateau's
      -- skyline (probed `03w24` at tiles (8,0)-(9,2), (12,0)-(13,2) and
      -- their two mirrors).  Authored, the rim is one course.
      --
      -- $0D/$0F/$0E are the League's outer wall -- top band, face and
      -- base.  The same three tiles draw the Pokemon League's own
      -- facade, the long walls flanking the avenue, and every
      -- badge-check gate down ROUTE_23.
      --
      -- $15/$16 + $05/$06 + $30/$31 are the pilaster: cap, shaft, and
      -- the plaque base.  $15/$16 over $30/$31 IS the statue's plinth --
      -- the artist drew the same stone twice -- which is why one pin
      -- serves the gate corners and the statues alike.
      --
      -- $2E/$2F the white pillar shaft and $20/$21 its cap change no
      -- HEIGHT: they derive 16 already.  What the pin buys is
      -- `authored`, which is exactly what the prop support rule tests.
      -- Without it a pillar-foot bird finds no support, drops to ground
      -- level, and leaves a hole punched clean through the pillar
      -- (probed, shot, then fixed).
      -- TWO courses (32px) for the masonry that ENCLOSES both maps -- the
      -- plateau's rim and every wall around the terraces.  It is drawn two
      -- cells tall, which is exactly the height of a statue on its plinth
      -- (a 16px plinth under a 16px standee), and that is the read: you are
      -- walking in a walled compound whose wall matches the statues lining
      -- it, not a room with a 16px skirting.  At one course the rim was a
      -- kerb you appeared to look over.
      --
      -- $03 the striated rock face, $0D/$0F/$0E the League's outer wall
      -- (top band, face, base -- the same three tiles draw the League's
      -- facade, the walls flanking the avenue and every badge-check gate
      -- down ROUTE_23), and $2E/$2F the white pillar shaft with $20/$21 its
      -- cap.  These four groups are the enclosure.
      cliff = { 3, 13,
                32, 33, 46, 47 },
      -- THE GATE WALLS, stacked rather than laid out in depth.  $0D/$0F/$0E
      -- (13/15/14 -- top band, face, base) draw the League's facade, the
      -- walls flanking the avenue and every badge-check gate down ROUTE_23,
      -- as FOUR tile rows: 13 / 15 / 15 / 14.  That is 32px of artwork
      -- depicting one wall, and at one class per row it built four boxes
      -- marching north, so the wall was 32px DEEP -- you saw the southmost
      -- row's face and the rest hid behind it.
      --
      -- `bookcase` collapses the run onto a single one-cell-deep box at its
      -- full drawn height: bands from the south are base, face, face, top
      -- band, and the two rows behind are vacated.  Same mechanism the
      -- Mart's back wall uses.
      -- ...and the PILASTER stacks with it.  $05/$06 is its shaft, and it
      -- is drawn only ever inside a pilaster, so it needs no rule.  Without
      -- this the pale columns stood 16px against a 32px brown wall and
      -- their top vertices sat a whole course below the wall's crown.
      bookcase = { 14, 15, 5, 6 },
      -- Tile 13 is DUAL-USE and needs resolving per position.  It is the
      -- gate wall's TOP BAND (block $28's first row) and it is also the
      -- BASE COURSE under a column of rock face (blocks $18/$1A/$1B, last
      -- row).  Pinned `bookcase` outright the second use became a one-row
      -- rank -- an 8px stub under the rock, 352 of them over both maps.
      --
      -- ABOVE cannot tell them apart, which is what `when_below` is for.
      -- Scanned over both maps through the engine's own tileAt, the tile
      -- above a 13 is the rock face $03 for 140 base courses AND for 64
      -- gate bands -- so a rule on `above` misfires on those 64 (it did:
      -- their runs came out 2 and 3 bands instead of 4).  BELOW splits it
      -- exactly: the wall's own face $0F sits under the top band and under
      -- nothing else, 336 against 352.  So 13 defaults to `cliff` and is
      -- promoted where the face is drawn beneath it.
      --
      -- 14 and 15 need no rule: 14 only ever sits under 15, 15 only ever
      -- under 13 or 15.
      when_below = {
        [13] = { { below = { 15 }, class = "bookcase" } },
        -- The pilaster's CAP ($15/$16) is the same stone as the statue's
        -- plinth top -- the artist drew it twice -- so it too resolves per
        -- position.  Scanned over both maps: a cap with the shaft $05/$06
        -- beneath it is a pilaster (76 of them) and one with the plaque
        -- base $30/$31 beneath it is a statue's plinth (47).  Default
        -- `wall`, promoted here, so the plinth keeps its single course and
        -- the statue standing on it still totals the 32px the wall is.
        [21] = { { below = { 5 }, class = "bookcase" } },
        [22] = { { below = { 6 }, class = "bookcase" } },
      },
      -- The other two ends of the same pair of drawings, keyed the other
      -- way round.  A pilaster is capped at BOTH ends, so its lower cap has
      -- the shaft ABOVE it (8 placements); and the plaque base $30/$31 is a
      -- pilaster's foot when the shaft is above it (68) but a statue's
      -- plinth bottom when the cap $15/$16 is (47).
      when_above = {
        [21] = { { above = { 5 }, class = "bookcase" } },
        [22] = { { above = { 6 }, class = "bookcase" } },
        [48] = { { above = { 5 }, class = "bookcase" } },
        [49] = { { above = { 6 }, class = "bookcase" } },
      },
      -- The vacated rows behind a collapsed wall take the cell ABOVE the
      -- run rather than the default hidden floor: here that is more rock
      -- face on ROUTE_23 and the plateau's paving or grass on INDIGO_
      -- PLATEAU, so the wall reads as set INTO the terrace instead of
      -- standing in front of a trench of synthesized ground.
      bookcase_backfill = "above",
      -- ONE course, and it must stay one: $15/$16 + $05/$06 + $30/$31 is
      -- the pilaster -- cap, shaft, plaque base -- and $15/$16 over $30/$31
      -- IS the statue's plinth, the artist having drawn the same stone
      -- twice.  Raising it would carry every statue standee up to 48px and
      -- break the very match the cliff height was chosen for.
      -- $05/$06 is NOT here: it moved to `bookcase` above, and a tile
      -- listed in two groups resolves by whichever `pairs` order wins --
      -- half the pilasters kept the shaft as `wall`, which broke the run
      -- and left their caps as isolated 8px stubs.  One group per tile.
      wall = { 21, 22, 48, 49 },
      -- The statues, and the same bird at the pillar feet.  Black-outline
      -- segmented: the outline and everything it encloses stay, the sky
      -- and the paving around them flood away.
      prop = { 16, 18, 40, 41, 37, 38 },
      -- Round drawings, one voxel ball per 16x16 cell -- the treatment
      -- the overworld's canopies and Celadon's hedge take.
      --
      -- $07/$08 over $17/$18: the seven canopies planted on pillar tops
      -- along ROUTE_23 (blocks $44/$45; the $0F block that tiles four of
      -- them together is never placed).  Boxed, the canopy art smeared
      -- down the whole pillar column beneath it.
      --
      -- $2A/$2B over $22/$1D: the boulders strewn across ROUTE_23's
      -- middle terrace (blocks $02/$13/$16), one per cell and NOT
      -- walkable.  As boxes they sat flat enough to look painted onto
      -- the path; as balls they read as the obstacles they are.
      cylinder = { 7, 8, 23, 24,
                   29, 34, 42, 43 },
      -- The Route 23 sign, one cell, block $48's only placement.
      -- Unpinned it probed `09w00 0Aw00 / 19w08 1Aw08` -- an 8px stub
      -- with its board skipped.  Same thin plate on a stick every other
      -- outdoor sign gets.
      signpost = { 9, 10, 25, 26 },
      -- The Route 22 gate's roof, drawn from ABOVE and filling
      -- ROUTE_23's last two block rows ($3D the tiling, $3E/$44 its
      -- edges, $40/$41 the corners).  Art on the TOP face -- the way
      -- SHIP_PORT's hull is pinned -- rather than folded up a 16px kerb.
      -- It stands past the map's last walkable row (you warp to
      -- ROUTE_22_GATE before you reach it), so this is a tidy-up rather
      -- than a fix.
      roof = { 61, 62, 64, 65, 68 },
      -- The ground painted where a pinned figure's cell used to be:
      -- $23, the pale paving both maps are floored with.  It is also the
      -- white the pillars are drawn in, so the cell a pillar-foot bird
      -- vacates reads as more pillar -- where the neighbour vote left a
      -- BLACK hole, having nothing to elect (all four neighbours of that
      -- cell are wall).  On the avenue and the plaza the statues' own
      -- cells simply keep the paving they stand on.
      prop_ground = { [16] = 35, [18] = 35, [40] = 35, [41] = 35,
                      [37] = 35, [38] = 35 },
      -- Deliberately NOT pinned:
      --
      -- $14, the water -- 1446 placements, the pond on ROUTE_23's middle
      -- terrace -- and its bank shading $32/$33/$1F.  $14 and $32 are
      -- two of the three stale-cache water ids the trap is named for,
      -- but here they are honestly water: TILEANIM_WATER animates $14,
      -- the pond is real, and $32/$33/$1F are drawn in the TOP half of
      -- water cells as the waterline itself, so the cell rule dropping
      -- them to -2 is what the art means.  Left to fall through to the
      -- engine's water set.  ($48, the third trap id, is not in this
      -- atlas at all -- it stops at $45.)
      --
      -- $0B/$0C over $1B/$1C, the barred doors: the Pokemon League's two
      -- and Victory Road's two.  They are the tileset's own doorTiles,
      -- so the door fold already stands them upright in the facade;
      -- probed 16px identically before and after this entry.
      --
      -- $23/$2C/$2D are in the walkable list outright, and $45 is the
      -- tileset's grassTile, which derives its own standing-tuft pin.
      --
      -- The Victory Road entrance is a `buildings` template
      -- (victory_road_gate, at the bottom of this file): 36x6 tiles at
      -- ROUTE_23 (0,58), and its ends are built out of $25/$26/$28/$29
      -- and $15/$16/$05/$06.  Buildings claim their tiles before any of
      -- the above can reach them -- probed `b` class over all 216 of
      -- them, unchanged by this entry.
    },
  },

  -- Buildings whose whole sprite is voxelized band by band (lib/Buildings.lua,
  -- the pipeline in assets/docs/buidling_to_voxel/).  A building is matched by its
  -- exact tile grid -- the drawings are catalogued in assets/docs/buildings/ -- so
  -- every map that places the same art gets the same model: one entry
  -- voxelizes Red's house, Blue's house, Bill's, the Copycat's and the two
  -- Fuchsia houses alike.
  --
  -- Only the BAND TABLE is authored here, because only it needs a human to
  -- read the drawing.  Everything measurable is measured off the pixels:
  -- the silhouette, the taper rate (which IS the roof's slope), the eave
  -- height, and every window and doorway (a non-black region its own black
  -- frame seals off).  Fields:
  --
  --   tiles      the tile-id grid that identifies the building, rows of the
  --              8px tile atlas, north row first
  --   roofRows   how many rows off the top are drawn as TOP-FACING roof;
  --              the rest of the drawing is the facade, seen face-on
  --   roofBack   rows laid along the north rim, one row per voxel of depth
  --   roofFront  rows laid along the south rim (the fascia and eave course)
  --   roofCycle  the row run the middle depth cycles; its length must be
  --              the roof texture's period or the courses will not line up
  --   slab       roof thickness in voxels
  --   frontEave  how far the roof overhangs the facade
  --   ledge      a band that juts two voxels past the walls (an awning),
  --              or nil
  --   seal       sides the drawing runs off rather than closing with its
  --              own outline, as a string of n/s/e/w; the silhouette
  --              flood does not seed there. Only needed by a drawing
  --              trimmed flush to its art -- one whose base course is a
  --              row of brick rather than the black threshold every other
  --              building stands on. Omit it unless the fill says
  --              otherwise: sealing a side the drawing does NOT run off
  --              swallows the terrain beside it.
  --
  -- Nothing here describes the roof's SHAPE, because nothing needs to: the
  -- topmost drawn row of each column is the elevation profile, so a drawn
  -- taper becomes a slope and a roof drawn from straight above comes out
  -- level.  That is why the flat-roofed civic block and its sixteen
  -- relatives -- every Center and Mart, the gyms and gates, the department
  -- store and Silph Co -- share one band table below, differing only in
  -- their tile grids.  The sloped ones fall into three groups just as
  -- cleanly, by the depth of the roof band: 16 rows (Red's house), 32
  -- (Oak's lab) or 64 (the museum).  Before authoring a new one, check
  -- whether its roof band is already pixel for pixel one of those.
  --
  -- assets/docs/buildings/B26 is deliberately absent.  Its drawing has no
  -- black base course -- it ends on a row of light brick -- so the
  -- silhouette flood, which comes in from the border through light pixels,
  -- climbs up through the wall and hollows it out.  Every other building
  -- is sealed by a black threshold row.  Reading it would mean changing
  -- the flood itself, which every model here depends on, for one scenery
  -- placement.
  buildings = {
    OVERWORLD = {
      -- assets/docs/buildings/B30: the POKEMON TOWER -- the one drawing
      -- in the catalogue that STRADDLES A MAP BOUNDARY.  Twelve of its
      -- twenty rows stand in ROUTE_10's last rows (the 64px purple roof
      -- band plus two window courses); the other eight -- five more
      -- courses and the base with the door -- are on LAVENDER_TOWN,
      -- where the tower begins at tile row 0.  Modelled per map it came
      -- out as two buildings, one per half.
      --
      -- `topRows` composites ROUTE_10's twelve rows ABOVE the matched
      -- grid, so the model is built from the COMPLETE twenty-row drawing
      -- -- 96px of facade under the real 64px roof -- while placement
      -- still matches only the eight Lavender rows.  Its `claimOnly`
      -- twin below claims the ROUTE_10 rows and stamps nothing, so the
      -- roof half does not also stand as its own building.
      --
      -- BOTH COME FIRST IN THIS LIST ON PURPOSE.  The tower's upper
      -- twelve rows are `gabled_block_6x6` tile for tile -- the artist
      -- drew the top of the tower as an ordinary six-cell block -- so
      -- that template matches at ROUTE_10 (24,132) too.  Placement is
      -- first-claim-wins (see Buildings.build), so claiming here before
      -- the generic block reaches it is what keeps the second tower from
      -- being stamped behind this one.
      --
      -- The 13-id last row is kept from the first attempt: the bare
      -- 12-wide body grid is B14's lower two-thirds tile for tile, and
      -- the extra id stops this template stamping inside
      -- `flat_block_6x6`'s three placements (`matches` walks a row to
      -- its own length, while `read` composites only #tiles[1] columns,
      -- so a 13th id constrains placement without entering the drawing).
      {
        id = "pokemon_tower",
        topRows = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
        },
        tiles = {
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79, 17 },
        },
        roofRows = 64, roofBack = 8, roofFront = 8, roofCycle = { 8, 31 },
        slab = 4, frontEave = 4, ledge = nil,
      },
      -- the tower's roof half, where it actually stands on ROUTE_10:
      -- claimed flat so the drawing does not ALSO fold up as a building
      -- behind the modelled tower (see topRows above)
      {
        id = "pokemon_tower_top",
        claimOnly = true,
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
        },
      },
      -- assets/docs/buildings/B07: the two-storey gabled house.  Coursed cap over
      -- a gable wall, an awning with its double black underline, then the
      -- ground floor with the door.  7 placements, Red's and Blue's among
      -- them.  Course rhythm: a dark line every 4 rows.
      {
        id = "gabled_house",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 34, 10, 10, 40, 41 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 34, 11, 12, 10, 10, 34, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = { 24, 31 },
      },

      -- assets/docs/buildings/B31: Oak's lab.  The same architecture with a roof
      -- band twice as deep -- the extra rows are DEPTH, not height, so the
      -- lab is a bigger footprint under the same storey.  Its cross-hatch
      -- roof texture repeats every 8 rows, and it has no awning: the band
      -- that would be one is the roof's own eave course.
      {
        id = "oaks_lab",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 10, 75, 75, 10, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 11, 12, 10, 10, 10, 10, 10, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B03: the flat-roofed commercial block --
      -- Celadon's diner, hotel, chief's house and prize room, the Bike
      -- Shop, the Fan Club, Mr. Psychic's, the Underground Path entrances.
      -- 15 placements, the most of any voxelized drawing.  The lattice
      -- field is drawn from straight above, so the measured taper is flat
      -- and the whole band is depth under one level roof; the eave course
      -- is the roof's own south rim, lab-style, no awning.  Lattice period
      -- 8, the lab's rhythm again.
      {
        id = "flat_commercial",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 75, 75, 75, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B05: every Pokemon Center in the game
      -- (Celadon, Cerulean, Cinnabar, Fuchsia, Lavender, Pewter,
      -- Saffron, Vermilion, Viridian, Mt Moon, Rock Tunnel). B03's
      -- block with the POKe sign hung beside the door; the sign is
      -- too wide to be a pane, so it stays flush.
      {
        id = "pokecenter",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 66, 67, 75, 31 },
          { 78, 26, 27, 28, 74, 74, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B06: every Poke Mart (Cerulean,
      -- Cinnabar, Fuchsia, Lavender, Pewter, Saffron, Vermilion,
      -- Viridian). The Center's twin, MART on the sign.
      {
        id = "pokemart",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 68, 69, 75, 31 },
          { 78, 26, 27, 28, 74, 74, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B02: the plain 4x4 block: one window
      -- course over blank brick and no door. 15 placements, scenery
      -- in every city bar the Celadon Mart roof stair.
      {
        id = "flat_block_4x4",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B08: the same block two cells deeper,
      -- 6 placements, all scenery.
      {
        id = "flat_block_4x6",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B13: the 6x4 scenery block, 4
      -- placements.
      {
        id = "flat_block_6x4",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B14: the 6x6 scenery block, 3
      -- placements.
      {
        id = "flat_block_6x6",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B27: the 8x4 scenery block, one
      -- placement on Route 11.
      {
        id = "flat_block_8x4",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B09: the wide storefront: Celadon's
      -- Game Corner, the Pokemon Mansion, Cinnabar Lab, the Safari
      -- Zone gate and Fuchsia's meeting room.
      {
        id = "game_corner",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B15: Celadon Mansion and the Route 6
      -- and Route 12 gates.
      {
        id = "celadon_mansion",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B18: the Route 2 gate, and the museum's
      -- east entrance beside it in Pewter.  The museum HALL itself is
      -- B24 below, a different drawing with a sloped roof.
      {
        id = "route_2_gate",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B29: Fuchsia Gym, the block with GYM
      -- on the sign.
      {
        id = "fuchsia_gym",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 34, 47, 63, 34, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 34, 34, 34, 34, 75, 75, 75, 31 },
          { 15, 75, 11, 12, 10, 10, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B28: the Route 5 underground-path
      -- gate.
      {
        id = "route_5_gate",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B21: the Route 22 league gate, the
      -- widest of the family at 12 cells.
      {
        id = "route_22_gate",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B25: the Power Plant.
      {
        id = "power_plant",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B22: Celadon's department store: six
      -- window courses over the MART sign.
      {
        id = "celadon_mart",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 11, 12, 10, 10, 68, 69, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 27, 28, 26, 26, 74, 74, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B20: Silph Co. Twelve cells of plot
      -- and ten courses of windows under the same roof band, so it
      -- stands as the tallest thing in Kanto.
      {
        id = "silph_co",
        tiles = {
          { 76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90 },
          { 92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B24: the Pewter museum's hall, and the only
      -- building in the family with a SLOPED roof: the same 2:1 taper the
      -- lab and Red's house are drawn with, over a roof band twice the
      -- lab's depth.  The drawing repeats its whole lattice-and-course
      -- motif -- rows 8..31 again at 32..55 -- which is what fixes the
      -- cycle at 24 rather than the bare lattice's 8: the drawing proves
      -- the period.  The last band (rows 56..63) is the roof's fascia,
      -- wider than the wall it covers, so it stays in the roof band and
      -- lands on the south rim.
      {
        id = "museum",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 64, roofBack = 8, roofFront = 8, roofCycle = { 8, 31 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B10: the gym. Cinnabar, Pewter,
      -- Vermilion and Viridian wear this drawing, and so does the
      -- Fighting Dojo next door to Saffron's. Oak's lab's roof band
      -- exactly, tile for tile, over a facade with GYM on the sign.
      {
        id = "gym",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 34, 47, 63, 34, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B16: the big-city gym: Celadon,
      -- Cerulean and Saffron. Two cells wider than the standard
      -- gym, and it carries the GYM sign twice.
      {
        id = "gym_large",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 34, 47, 63, 34, 34, 47, 63, 34, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B01: the commonest drawing in the
      -- game at 19 placements, and every one of them scenery: a
      -- gabled block with two window courses and no door. Red's
      -- house's roof band, tile for tile, but no awning under it.
      {
        id = "gabled_block_4x3",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 31 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B04: the little 4x2 cottage, 12
      -- placements and nearly all of them somebody's home: Mr
      -- Fuji's, the Cubone house, Bill's grandpa's, the Name
      -- Rater's, the Viridian school house, the Route 8 underground
      -- path.
      {
        id = "gabled_cottage",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 11, 12, 10, 10, 40, 41 },
          { 78, 26, 27, 28, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B17: the wide 6x2 house: Cerulean's
      -- badge, trade and trashed houses.
      {
        id = "gabled_house_wide",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 11, 12, 35, 10, 10, 35, 10, 10, 40, 41 },
          { 78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B11: the 6x2 scenery block, 5
      -- placements, no door.
      {
        id = "gabled_block_6x2",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 34, 35, 10, 10, 35, 10, 10, 40, 41 },
          { 78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B34: the 4x2 scenery block, one
      -- placement in Fuchsia.
      {
        id = "gabled_block_4x2",
        tiles = {
          {  5,  6,  7,  7,  7,  7,  8,  9 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 34, 10, 10, 40, 41 },
          { 78, 26, 26, 26, 26, 26, 26, 79 },
        },
        roofRows = 16, roofBack = 7, roofFront = 9, roofCycle = { 5, 8 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B33: the Route 5 day care.
      {
        id = "daycare",
        tiles = {
          {  5,  6, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 10, 10, 10, 10, 40, 41 },
          { 15, 34, 34, 34, 34, 34, 34, 31 },
          { 15, 10, 10, 10, 11, 12, 10, 31 },
          { 78, 26, 26, 26, 27, 28, 26, 79 },
        },
        roofRows = 32, roofBack = 7, roofFront = 8, roofCycle = { 5, 12 },
        slab = 4, frontEave = 4, ledge = nil,
      },

      -- assets/docs/buildings/B26: the Route 10 scenery block,
      -- structurally the museum's twin -- Oak's lab's roof band,
      -- and its rows 8..31 repeat at 32..55 exactly as the museum's
      -- do. It needs `seal` because its drawing has no black base
      -- course: it ends on a row of light brick, and unsealed the
      -- flood climbs in from the south border through the mortar
      -- and hollows the wall out (72% of the sprite survives
      -- instead of 95%, in 65 pieces instead of 1).
      {
        id = "gabled_block_6x6",
        tiles = {
          {  5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25 },
          { 21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25 },
          { 37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
          { 15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31 },
          { 15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31 },
        },
        roofRows = 64, roofBack = 8, roofFront = 8, roofCycle = { 8, 31 },
        slab = 4, frontEave = 4, ledge = nil, seal = "s",
      },
    },

    FOREST = {
      -- assets/docs/buildings/B12: the Safari Zone rest houses --
      -- Center, East, North, West and the Secret House. A
      -- corrugated roof over a plank facade; its stripe repeats
      -- every 5 rows, not the OVERWORLD lattice's 8.
      {
        id = "safari_rest_house",
        tiles = {
          {  8,  9,  9,  9,  9,  9,  9, 12 },
          { 24, 25, 25, 25, 25, 25, 25, 28 },
          { 40, 41, 42, 43,  1,  1, 41, 44 },
          { 56, 41, 58, 59, 41, 41, 41, 60 },
        },
        roofRows = 17, roofBack = 5, roofFront = 3, roofCycle = { 5, 9 },
        slab = 4, frontEave = 4, ledge = nil,
      },
    },
  },
}
