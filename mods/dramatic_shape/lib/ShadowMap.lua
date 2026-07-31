-- Voxel world mode: the sun's own pass -- a real shadow map.
--
-- The old drop shadows were decals: each character's sprite frame squashed
-- flat onto the ground plane it stood on. That can only ever paint the
-- FLOOR, so a shadow stopped dead at the foot of a wall, and nothing but a
-- character cast one at all -- buildings, trees, signs and ledges threw
-- nothing.
--
-- So render the scene once from the sun instead. An orthographic camera
-- pointed down the sun line stores, per texel, how far the light travelled
-- before it hit something; the main pass transforms each fragment into that
-- same space and asks whether anything got there first. What the sun cannot
-- see is in shadow, whatever surface it happens to be -- so a shadow climbs
-- a wall, drapes over a roof and slides across a passing NPC without a
-- single case in the code, and every caster is simply whatever the pass
-- draws: the terrain mesh (buildings, trees, ledges, props -- all of it)
-- plus one upright card per character.
--
-- Depth is stored in an ORDINARY color canvas, packed into two 8-bit
-- channels (~16 bits over the frustum, well under a tenth of a world
-- pixel). A readable depth texture would be tidier, but depth sampling is
-- the least portable corner of the graphics API and this mod's whole
-- contract is that an unsupported driver falls back rather than errors --
-- everything here is pcall-guarded and `available()` reports the result,
-- with VoxelScene dropping back to the flat decal shadows when it says no.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel = V.require("VoxelState")

local ShadowMap = {}

-- The sun, as the shear a shadow takes: a point `y` world-pixels above the
-- ground drops its shadow (KX*y, KZ*y) away from the point under it. Both
-- negative hangs the sun in the SOUTHEAST, so every shadow falls northwest
-- -- up and to the left on screen, since the camera puts north at the top
-- and east to the right at every tilt.
--
-- Their MAGNITUDE is how low the sun sits: hypot(KX, KZ) = 1.01 puts it
-- about 45 degrees up, so a 16px character throws a shadow about as long
-- as it is tall -- against the 62-degree noon these started at, which read
-- as a smudge under everybody's feet.
--
-- Their RATIO is the compass bearing, and it leans WEST of northwest on
-- purpose. A character is drawn as a slab leaning back away from the
-- camera, which covers the ground directly north of its feet -- so a
-- shadow thrown due north lands entirely underneath the figure casting it
-- and is never seen. At 0.85 west the shadow reaches 13px out against the
-- sprite's own 8px half-width, so it clears the slab and reads, while 0.55
-- north still puts it a clear 23 degrees up from horizontal on screen.
ShadowMap.KX = -0.85      -- west drift per pixel of height
ShadowMap.KZ = -0.55      -- north drift per pixel of height

-- Shadow map edge, in texels -- chosen per frame from this ladder, because
-- the light frustum is sized to the WORLD VIEW and that swings by 3x
-- between the closest zoom and a maximised window at the widest. A fixed
-- edge is either wasteful at one end or a blur at the other.
--
-- TARGET is the world pixels per texel worth paying for: at a third of a
-- pixel a shadow edge lands inside the pixel grid this whole mode exists
-- to keep crisp, and finer buys nothing the grid can show. The smallest
-- size that meets it wins, and the ladder tops out at 2048 (16 MB, and the
-- depth buffer behind it matches) rather than chasing the target forever.
ShadowMap.SIZES = { 1024, 1536, 2048 }
ShadowMap.TARGET = 0.45
ShadowMap.res = 1024      -- the rung in use; read by the main pass's filter

-- The tallest geometry the pass covers: gabled buildings and border forest
-- run well under this, and the margin it buys costs only resolution --
-- with the sun this low the frustum has to widen by most of HEIGHT again
-- on every side to catch what casts in from off-screen.
ShadowMap.HEIGHT = 160

-- Depth slack at the comparison, in world pixels. Too little and a lit
-- surface shadows itself in a moire of acne; too much and a shadow detaches
-- from the foot of what casts it. The frustum is ~400 world pixels deep and
-- the packed depth resolves under 0.01 of one, so there is room.
--
-- It cannot be ONE number, because what the comparison has to forgive is
-- not fixed: the map stores one depth for a whole texel, so a lit surface
-- reads its own depth wrong by however far it RAMPS across that texel --
-- the texel's world size times the surface's slope in the light's frame.
-- The texel swings from a third of a world pixel at the closest zoom to
-- well over one at a maximised window on the widest, so a constant bias is
-- generous at one end of the ladder and short at the other. Short shows up
-- as diagonal bands of acne across big lit surfaces -- diagonal because
-- the moire runs along neither the world grid nor the screen's, but along
-- the depth ramp in the sun's own frame, and the sun sits southeast.
--
-- So: a floor for what does not scale (the packed depth's quantisation,
-- and the two passes reaching the same world point by different matrices),
-- plus a term in texels for what does.
ShadowMap.BIAS = 0.5

-- World pixels of slack per world pixel of texel, for the steepest LIT
-- surface here: a roof pitched 45 degrees and turned away from the sun,
-- whose depth ramps about 3.1 world pixels per texel crossed on EITHER of
-- the light frame's two axes (a vertical wall, by comparison, manages 1.7,
-- flat ground 0.7, and anything steeper than that roof has its back to the
-- sun and never reads the map at all). The 2x2 filter's taps sit half a
-- texel out on both axes at once, so the worst a tap can disagree by is
-- half the ramp along each -- which is where the halving that turns 6.2
-- into 3.1 comes from, and why it is the SUM of the two components rather
-- than their magnitude.
--
-- Measured against the artefact rather than trusted: the probe
-- (tests/voxel_acne_probe.lua) counts isolated shadowed pixels on lit
-- surfaces, and the banding stops at slack ~2.4 world px on the widest
-- rung -- where this lands 3.1 * 0.83 + 0.5.
ShadowMap.SLOPE = 3.1

-- The slack `fit` last worked out, in world pixels -- BIAS + SLOPE*texel.
-- Read by probes; `ShadowMap.bias` is the same number as the [0,1] depth
-- the map actually stores.
ShadowMap.slack = ShadowMap.BIAS

local SHADER = [[
  varying float vDepth;
#ifdef VERTEX
  uniform mat4 lightVP;
  uniform mat4 model;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec4 c = lightVP * (model * vertex_position);
    // the projection is orthographic, so w is 1 and clip z IS the depth,
    // linear in world units along the sun line
    vDepth = c.z * 0.5 + 0.5;
    return c;
  }
#endif
#ifdef PIXEL
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    // the same alpha discard the main pass uses: a sprite card casts its
    // silhouette, not its 16x16 bounding box
    if (Texel(tex, tc).a < 0.5) discard;
    // pack into two channels: the high byte in red, the low in green
    float d = clamp(vDepth, 0.0, 1.0) * 255.0;
    return vec4(floor(d) / 255.0, fract(d), 0.0, 1.0);
  }
#endif
]]

local shader = nil            -- nil = untried, false = unavailable
local canvas = nil            -- nil = untried, false = unavailable
local canvasRes = 0           -- the edge `canvas` was made at
local blank = nil             -- 1x1 stand-in so the sampler is never unbound
local drawing = false
local ready = false
local lastSig = nil
local prevBlend, prevAlphaMode = nil, nil

local IDENTITY = Mat4.identity()

-- world -> [0,1] cube, applied on top of the clip matrix: the main pass
-- samples the map with the xy and compares against the z
local TO_UNIT = { 0.5, 0, 0, 0.5,
                  0, 0.5, 0, 0.5,
                  0, 0, 0.5, 0.5,
                  0, 0, 0, 1 }

-- world -> light clip space, for the pass that FILLS the map
ShadowMap.clipVP = IDENTITY
-- world -> the unit cube, for the pass that READS it
ShadowMap.uvVP = IDENTITY
-- ShadowMap.BIAS expressed in the [0,1] depth the map stores
ShadowMap.bias = 0

local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = (ok and sh) or false
  end
  return shader or nil
end

-- The map canvas at edge `res`, rebuilt when the rung changes (a zoom
-- step, a window resize). `false` is sticky: a driver that could not make
-- one at all is not asked again every frame.
local function getCanvas(res)
  if canvas == false then return nil end
  if canvas and canvasRes == res then return canvas end
  local ok, c = pcall(love.graphics.newCanvas, res, res)
  if not (ok and c) then
    canvas = false
    return nil
  end
  -- nearest: the 2x2 filter in the main pass wants raw texels, and a
  -- linearly blended PACKED depth is not a depth at all
  c:setFilter("nearest", "nearest")
  pcall(c.setWrap, c, "clamp", "clamp")
  if canvas and canvas.release then pcall(canvas.release, canvas) end
  canvas, canvasRes = c, res
  ready = false
  return canvas
end

-- A 1x1 opaque white image. The main pass's shader always declares the
-- shadow sampler, so something has to be bound even on the frames (and the
-- drivers) where there is no map -- unpacked it reads as depth 1 + 1/255,
-- which is beyond the far plane and therefore "nothing occludes anything".
local function getBlank()
  if blank == nil then
    local ok, img = pcall(function()
      local data = love.image.newImageData(1, 1)
      data:setPixel(0, 0, 1, 1, 1, 1)
      return love.graphics.newImage(data)
    end)
    blank = (ok and img) or false
  end
  return blank or nil
end

-- Whether the sun pass can run at all. False headless, without shaders, or
-- where the canvas cannot be made -- VoxelScene then keeps the flat decal
-- shadows, which need nothing but a quad.
function ShadowMap.available()
  if not (love.graphics and love.graphics.newCanvas
          and love.graphics.setDepthMode) then
    return false
  end
  -- the smallest rung is enough to answer the question; fit() picks the
  -- one this frame actually wants
  return getShader() ~= nil and getCanvas(ShadowMap.SIZES[1]) ~= nil
end

-- The map to sample, or the blank stand-in. Never nil once the main pass
-- has a shader at all, because an unbound sampler is a driver-dependent
-- crash rather than a driver-dependent fallback.
function ShadowMap.texture()
  if ready and canvas then return canvas end
  return getBlank()
end

-- True while the map holds a frame the main pass can read.
function ShadowMap.active()
  return ready and canvas ~= nil and canvas ~= false
end

-- The direction the light TRAVELS, normalized. The shear is the shadow a
-- unit of height throws, so the displacement from a point to where its
-- shadow lands is (KX, -1, KZ) -- which is the ray.
local function sunDir()
  local x, y, z = ShadowMap.KX, -1, ShadowMap.KZ
  local l = math.sqrt(x * x + y * y + z * z)
  return { x / l, y / l, z / l }
end

ShadowMap.sunDir = sunDir

-- How far NORTH of the view centre the camera can still see ground, in
-- world pixels: the top edge of the view frustum dropped onto the ground
-- plane. The lower the camera the further that reaches, and past about 64
-- degrees the ray clears the horizon and the honest answer is "forever" --
-- hence the cap. Ground beyond it compresses into a few pixels near the
-- skyline, and its shadows with it, so the border fade in the main pass
-- eases them out rather than the frustum ending on a hard line.
ShadowMap.FAR_CAP = 2.5     -- multiples of the view height

local function groundReach(vh)
  local a = Voxel.angle or 0
  local cap = ShadowMap.FAR_CAP * vh
  -- half the vertical field of view: the same FOCAL the camera projects
  -- with, so the two frusta agree about what is on screen
  local half = math.atan(1 / (2 * Voxel.FOCAL))
  local below = (math.pi / 2 - a) - half     -- top ray, below horizontal
  if below <= 0.02 then return cap end
  local dist = Voxel.FOCAL * vh
  local horizon = dist * math.cos(a) / math.tan(below)
  return math.max(vh / 2, math.min(cap, horizon - dist * math.sin(a)))
end

-- Fit the light frustum to the ground the camera can see, plus the margin
-- the casters for it stand in.
--
-- Both are ASYMMETRIC, and for opposite reasons. The camera sits south of
-- its focus and looks north, so the ground it sees runs far north and
-- barely south. The sun sits southeast, so the things whose shadows land
-- on that ground stand south and east of it -- which means the caster
-- margin is only ever needed on two of the four sides. Paying for it on
-- all four (and for a view-sized box at every pitch) is what the first cut
-- did, and at 75 degrees it covered about a third of what was on screen.
--
-- The box is snapped to whole texels. Without that, a frustum that slides
-- continuously with the camera reprojects every shadow edge a fraction of a
-- texel every frame and the whole world's shadows crawl and shimmer while
-- you walk.
local function fit(cx, cy, vw, vh)
  local f = sunDir()
  local view = Mat4.lookAt({ 0, 0, 0 }, f, { 0, 0, -1 })

  local reach = ShadowMap.HEIGHT
                * math.max(math.abs(ShadowMap.KX), math.abs(ShadowMap.KZ)) + 24
  local north = groundReach(vh)
  -- the view widens with distance, so the far ground spans more than the
  -- near ground does; half the depth is a serviceable stand-in for the
  -- frustum's true spread and costs a good deal less resolution
  local spread = north * 0.5
  local xs = { cx - vw / 2 - spread, cx + vw / 2 + spread + reach }
  local ys = { -32, ShadowMap.HEIGHT }         -- -32 covers recessed water
  local zs = { cy - north, cy + vh / 2 + reach }

  local l, r, b, t, zn, zf
  for _, x in ipairs(xs) do
    for _, y in ipairs(ys) do
      for _, z in ipairs(zs) do
        local px = view[1] * x + view[2] * y + view[3] * z + view[4]
        local py = view[5] * x + view[6] * y + view[7] * z + view[8]
        local pz = view[9] * x + view[10] * y + view[11] * z + view[12]
        l = l and math.min(l, px) or px
        r = r and math.max(r, px) or px
        b = b and math.min(b, py) or py
        t = t and math.max(t, py) or py
        zn = zn and math.min(zn, pz) or pz
        zf = zf and math.max(zf, pz) or pz
      end
    end
  end

  local w, h = r - l, t - b

  -- pick the resolution rung: the smallest that resolves TARGET world
  -- pixels per texel across the wider side, else the largest there is
  local res = ShadowMap.SIZES[#ShadowMap.SIZES]
  for _, size in ipairs(ShadowMap.SIZES) do
    if math.max(w, h) / size <= ShadowMap.TARGET then
      res = size
      break
    end
  end
  ShadowMap.res = res

  -- the box's SIZE is fixed (the sun and the view size are), so snapping
  -- its corner to a texel multiple moves it in whole texels only
  local tx, ty = w / res, h / res
  l = math.floor(l / tx) * tx
  b = math.floor(b / ty) * ty
  r, t = l + w, b + h

  -- view-space z runs NEGATIVE into the scene; ortho() wants distances,
  -- and the slack keeps geometry taller than HEIGHT from being clipped
  -- clean out of the pass instead of merely casting a truncated shadow
  local near, far = -zf - 64, -zn + 64
  local proj = Mat4.ortho(l, r, b, t, near, far)
  -- flip clip-space Y for the same reason the camera does: we bypass
  -- LOVE's transform_projection, and canvas coordinates run Y DOWN, so
  -- without this the map is stored upside down relative to the uv the
  -- main pass reads it with
  proj = Mat4.mul(Mat4.scale(1, -1, 1), proj)

  ShadowMap.clipVP = Mat4.mul(proj, view)
  ShadowMap.uvVP = Mat4.mul(TO_UNIT, ShadowMap.clipVP)
  -- what the frustum ended up covering, for probes: the lateral extent in
  -- world pixels divided by RES is how fine a shadow edge can land
  ShadowMap.extent = { r - l, t - b, far - near }
  -- the slack the comparison needs, against the coarser of the two texel
  -- axes (the box is asymmetric, and one number has to cover both)
  ShadowMap.slack = ShadowMap.BIAS
                    + ShadowMap.SLOPE * math.max(w, h) / res
  -- the stored depth spans the frustum, so a world-pixel bias is that
  -- fraction of it
  ShadowMap.bias = ShadowMap.slack / math.max(1, far - near)
end

-- How much of the compare's forgiveness a snugged caster takes back, 0..1.
-- Short of 1 on purpose: at exactly 1 the card's own fragments compare
-- against their own stored depth on a float-equality knife edge and can
-- speckle. The tenth left over is dozens of times the packed depth's
-- quantization -- ample for that -- and leaves the contact gap around a
-- quarter of a world pixel at any sun, which no zoom resolves.
ShadowMap.SNUG = 0.9

-- A CASTER snugged up the sun ray -- moved TOWARD the light -- before it is
-- drawn into the map.
--
-- The depth compare forgives `slack` world pixels (BIAS + the SLOPE term)
-- so lit surfaces do not acne against their own texels -- but that same
-- forgiveness is what lets the ground right next to a standing figure read
-- as lit: a receiver within `slack` of its blocker along the ray passes the
-- test, so the first stretch of every shadow is forgiven away and on screen
-- it starts that far from the feet, further the lower the sun. The classic
-- peter-panning; unseen while the sun hung at a fixed 45 degrees, plain at
-- a day/night golden hour or under the moon.
--
-- Moving the card ALONG ITS OWN RAY changes nothing about where its shadow
-- falls -- every point stays on the same light ray -- but moving it toward
-- the sun stores it SHALLOWER, so a ground point right at the foot is
-- already `slack` deeper than the stored blocker and fails the lit test:
-- the root lands back under the feet. Nothing else is touched -- no
-- terrain moved, so the acne margin the slack exists for is intact where
-- it matters. For sprite cards and other thin stand-ins only.
--
-- ONE OBLIGATION comes with it: the caster's LIT draw must hand this same
-- snugged transform to its shadow lookup (Voxel3D.draw's `sunModel`).
-- Stored and lookup then agree exactly, as they did before snugging, and
-- the compare keeps its full acne margin. A caster stored snugged but read
-- un-snugged is 0.9 of the margin short, and the loss shows up as diagonal
-- moire bands crawling across the card.
--
-- Valid between begin() and the next begin(): `slack` and the sun hold
-- still between redraws of the map, so a lit frame that reuses last
-- frame's map computes the same displacement it was stored with.
function ShadowMap.snug(model)
  local f = sunDir()
  local s = -ShadowMap.slack * ShadowMap.SNUG
  return Mat4.mul(Mat4.translate(f[1] * s, f[2] * s, f[3] * s),
                  model or IDENTITY)
end

-- Whether the map has to be redrawn for `sig` -- a caller-built stamp of
-- everything the pass depends on (camera, terrain meshes, every pose). A
-- frame that changes none of it reuses the map it already has, which is
-- most of a dialog, a menu or any moment standing still.
function ShadowMap.stale(sig)
  return not ready or sig ~= lastSig
end

-- Begin the sun pass. Returns false when it could not start, in which case
-- the caller must not draw into it or call finish.
function ShadowMap.begin(cx, cy, vw, vh)
  local sh = getShader()
  if not sh then return false end
  -- fit first: it is what decides which resolution rung this view wants
  fit(cx, cy, vw, vh)
  local c = getCanvas(ShadowMap.res)
  if not c then return false end
  local ok = pcall(love.graphics.setCanvas, { c, depth = true })
  if not ok then
    pcall(love.graphics.setCanvas)
    return false
  end
  prevBlend, prevAlphaMode = love.graphics.getBlendMode()
  -- white clears to depth 1 + 1/255, past the far plane: a texel nothing
  -- was drawn into can never shadow anything
  love.graphics.clear(1, 1, 0, 1, true, true)
  love.graphics.setDepthMode("lequal", true)
  love.graphics.setMeshCullMode("none")
  -- replace, not alpha blend: these are packed numbers, not colors
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setShader(sh)
  love.graphics.setColor(1, 1, 1, 1)
  pcall(sh.send, sh, "lightVP", "row", ShadowMap.clipVP)
  drawing = true
  ready = false
  return true
end

-- Draw one caster. Same signature as Voxel3D.draw minus the camera-ward
-- pull, which is a trick for the VIEW's depth buffer and would drag a
-- shadow off whatever throws it.
function ShadowMap.draw(mesh, texture, model)
  if not (drawing and mesh) then return end
  local sh = getShader()
  if texture then mesh:setTexture(texture) end
  pcall(sh.send, sh, "model", "row", model or IDENTITY)
  love.graphics.draw(mesh)
end

-- Close the pass and stamp it with the signature it was drawn for.
function ShadowMap.finish(sig)
  if not drawing then return end
  drawing = false
  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.setCanvas()
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlphaMode)
  love.graphics.setColor(1, 1, 1, 1)
  lastSig = sig
  ready = true
end

-- Drop the GPU objects (window resize, hot reload).
function ShadowMap.invalidate()
  canvas, canvasRes, blank = nil, 0, nil
  drawing, ready, lastSig = false, false, nil
end

return ShadowMap
