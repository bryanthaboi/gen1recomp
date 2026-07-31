-- Voxel world mode: the 3D pass -- shader, depth buffer and camera.
--
-- World space is world PIXELS, so every coordinate the 2D paths already
-- compute drops straight in with no unit conversion:
--
--   +X  map east   (world-pixel x)
--   +Y  up         (0 is the ground plane)
--   +Z  map south  (world-pixel y)
--
-- A character at rest faces +Z, i.e. toward a camera parked to the south,
-- which is what "facing down" means in the 2D game -- and a character card
-- is drawn in exactly that pose, leaning back rather than yawing.
--
-- The camera orbits the view centre at Voxel.angle: 0 is straight down
-- (what the flat 2D view already is) and 50 degrees leans toward the
-- horizon. Distance and field of view are tied to Voxel.FOCAL, which is the
-- same constant Tilt projects with, so a given angle frames the world
-- identically in both modes -- switching between them changes the geometry,
-- not the framing.
--
-- Every GPU object is pcall-guarded and `available()` reports the result:
-- headless test runs and any driver without depth-canvas support fall back
-- to the existing tilt/flat paths rather than erroring.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel = V.require("VoxelState")
local ShadowMap = V.require("ShadowMap")
local VoxelGrid = V.require("VoxelGrid")
local WorldCurve = V.require("WorldCurve")
local Sky = V.require("Sky")
local DayNight = V.require("DayNight")
local GlassMask = V.require("GlassMask")

local Voxel3D = {}

-- Vertex format shared by terrain chunks and character models: a position,
-- the map-canvas / sprite-sheet pixel it samples, and a per-vertex darken
-- factor that gives a face its angle to the sun without a normal or a
-- light uniform. Cast shadows are a separate thing entirely -- see
-- ShadowMap, which the pixel shader below samples on top of this.
Voxel3D.FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexShade", "float", 1 },
}

-- Face shading by direction id: top faces stay
-- full brightness, sides step down so an extruded block reads as solid
-- instead of a flat sticker, and the faces turned away from the sun are
-- darkest. The sun hangs in the SOUTHEAST (see ShadowMap), so south and
-- east are the lit flanks and north and west the shaded ones -- east and
-- west used to share one value back when the sun sat due northwest and the
-- two were symmetric about it.
--
-- This is still worth baking even now that the shadow pass throws real
-- shadows: a face turned away from the sun is dark because of its ANGLE,
-- which no shadow map measures, and the two compound the way they should
-- -- an away-facing wall that is also occluded goes darker still.
Voxel3D.FACE_SHADE = {
  [1] = 0.84,   -- +X east (toward the sun)
  [2] = 0.72,   -- -X west (away)
  [3] = 1.00,   -- +Y up
  [4] = 0.55,   -- -Y down
  [5] = 0.90,   -- +Z south (toward the camera, and toward the sun)
  [6] = 0.68,   -- -Z north (away)
}

local SHADER = [[
  varying float vShade;
  varying vec3 vSun;          // this fragment's place in the sun's view
#ifdef VOXEL_GRID
  // model space, one unit per voxel -- see VoxelGrid. Precision matters
  // here in a way it does not for a colour: the seam is the FRACTIONAL
  // part of a coordinate that runs to a few thousand across a big route,
  // so a mediump varying would quantise the fraction away entirely.
  varying LOVE_HIGHP_OR_MEDIUMP vec3 vGrid;
#endif
#ifdef VERTEX
  uniform mat4 vp;
  uniform mat4 model;
  uniform mat4 sunModel;      // where the SUN sees this vertex (see below)
  uniform mat4 sunVP;         // world -> the shadow map's unit cube
  uniform vec3 eye;
  uniform float pull;
  uniform vec3 curve;         // xy = the focus in world XZ, z = k; 0 = off
  attribute float VertexShade;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vShade = VertexShade;
#ifdef VOXEL_GRID
    // MODEL space, deliberately: every mesh here is built a unit per
    // voxel in its own frame, so the seams ride the model however it is
    // posed rather than the world's grid sliding across a leaning sprite
    vGrid = vertex_position.xyz;
#endif
    vec4 w = model * vertex_position;
    // The shadow lookup runs off `sunModel`, not `model`. For terrain the
    // two are the same matrix, but a character is drawn as a slab LEANING
    // back by the camera's pitch -- a trick played on the viewer, which
    // the sun never saw: it lit the upright card. Looking up with the
    // leaned position asks whether the sun reached a place the figure is
    // not, and since the lean tips the body north and shadows now fall
    // north, every sprite's own card fell across its front. Looking up
    // with the card's position asks the question the sun actually
    // answered. (The pull below is excluded for the same reason: it is a
    // depth trick aimed at the camera's own buffer.)
    vSun = (sunVP * (sunModel * vertex_position)).xyz;
    // The curved world (see WorldCurve): drop every vertex by the square
    // of how far its column stands from the camera's focus. Applied AFTER
    // the shadow lookup above and clear of the wireframe's model space, so
    // both are worked out on the flat world and the bend carries them
    // along -- which is why neither has to know this exists. Along Y only,
    // so a column moves as one piece: the world tips away and the
    // buildings standing on it stay upright.
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= dot(cd, cd) * curve.z;
    }
    // camera-ward pull: move the vertex along ITS OWN ray to the eye.
    // This is a pure depth bias -- the projection of a point moved along
    // its eye ray is bit-identical, so there is no screen drift at all.
    // (An earlier CPU version translated along the central view axis,
    // which preserved only the screen centre and made off-centre sprites
    // and grass swim against the ground while the camera scrolled.)
    if (pull > 0.0) {
      w.xyz += normalize(eye - w.xyz) * pull;
    }
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform Image sunMap;
  uniform float sunDark;      // how far into black a shadow goes; 0 = off
  uniform float sunBias;
  uniform vec2 sunTexel;

  // the two-channel pack ShadowMap writes: high byte, then low
  float sunDepth(vec2 uv) {
    vec4 c = Texel(sunMap, uv);
    return c.r + c.g * (1.0 / 255.0);
  }

  // 1.0 in full sun, 1.0 - sunDark in full shadow. Four taps half a texel
  // out on the diagonals: a 2x2 box filter, which is what turns the
  // shadow map's texel staircase into a one-pixel soft edge.
  float sunlight(vec3 p) {
    if (sunDark <= 0.0) return 1.0;
    // outside the sun's frustum nothing was recorded, so nothing occludes
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) {
      return 1.0;
    }
    // Ease the shadows off at the frustum's rim. The map covers the ground
    // the camera can see out to a cap, and past the low rungs -- 75 degrees
    // especially -- the horizon is further than any box worth paying for.
    // Without this the covered region simply ENDS, drawing a hard line
    // across the middle distance where every shadow stops at once; with it
    // the far field just loses them, which reads as distance.
    vec2 e = min(p.xy, 1.0 - p.xy);
    float edge = smoothstep(0.0, 0.06, min(e.x, e.y));
    if (edge <= 0.0) return 1.0;
    float z = p.z - sunBias;
    float lit = step(z, sunDepth(p.xy + sunTexel * vec2(-0.5, -0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5, -0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2(-0.5,  0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5,  0.5)));
    return 1.0 - sunDark * edge * (1.0 - lit * 0.25);
  }

#ifdef VOXEL_GRID
  uniform float gridDark;     // how far toward black a seam pulls; 0 = off
  uniform float gridWidth;    // seam width, in display pixels

  // How much of this fragment a voxel seam covers, 0 to 1.
  float voxelSeam(vec3 p) {
    // how much of `p` this fragment spans on screen, per axis: the
    // conversion from model units to display pixels, measured rather than
    // derived, so it holds under any camera pitch or zoom
    vec3 w = fwidth(p);
    vec3 d = abs(fract(p + 0.5) - 0.5);      // distance to the nearest plane
    // The axis a face does not vary along is that face's own normal, and
    // its distance is a constant zero -- take it at face value and every
    // face floods solid. Push those axes out of reach instead of dividing
    // by their zero.
    vec3 live = step(1e-4, w);
    vec3 px = d / max(w, vec3(1e-6)) + (1.0 - live) * 1e6;
    float near = min(min(px.x, px.y), px.z);
    // Fade out where a voxel is too small to hold a line. Survey zoom
    // draws a world pixel at about a display pixel, and a wall seen nearly
    // edge-on squashes one to nothing at any zoom -- either way the seams
    // land closer together than they are wide, and drawn anyway they stop
    // being a wireframe and become a flat 45% dimming of the whole scene.
    // The tightest axis decides, which is the honest test of whether the
    // grid can be resolved at all.
    float span = 1.0 / max(max(w.x, max(w.y, w.z)), 1e-6);
    float fade = clamp((span - 2.0) * 0.5, 0.0, 1.0);
    // the textbook antialiased line: solid within the half-width, fading
    // over the one pixel outside it
    return fade * clamp(gridWidth * 0.5 + 0.5 - near, 0.0, 1.0);
  }
#endif

  uniform vec3 ghostColor;    // the flat silhouette colour
  uniform float ghost;        // 0 = shade normally, 1 = flatten to it
  uniform vec3 dayTint;       // the hour's light on the world; 1,1,1 = noon
  uniform Image glassMask;    // opaque where the atlas texel is window glass
  uniform vec2 glassSize;     // the mask's dimensions: tc -> atlas texels
  uniform float glassNight;   // 0 = daylight .. 1 = the lamps are on
  uniform float glassPhase;   // the glint's phase: advances with TRAVEL
  uniform float glassGlint;   // and its strength: 0 while standing still
  uniform float glassOn;      // 0 for sprite-sheet draws (see Voxel3D.glass)

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 p = Texel(tex, tc);
    // sprite sheets key GB OBJ color 0 to alpha 0; discarding rather than
    // blending keeps those texels out of the depth buffer, so a model never
    // carves a transparent hole out of whatever stands behind it
    if (p.a < 0.5) discard;
    // the hour's tint multiplies like the sun terms do: it is LIGHT, the
    // same warm or moonlit cast on every surface, not a palette swap
    vec3 rgb = p.rgb * vShade * sunlight(vSun) * dayTint;
#ifdef VOXEL_GRID
    // darken what is there rather than painting a colour, so a seam across
    // dark grass and one across a white roof each stay in their own palette
    rgb *= 1.0 - gridDark * voxelSeam(vGrid);
#endif
    // WINDOW GLASS, marked per atlas texel by the mask (see GlassMask).
    // By day a thin diagonal glint crosses the panes WHILE THE VIEW MOVES
    // -- the phase is fed by the camera's own travel and the strength dies
    // within a beat of standing still, because a reflection is something
    // the viewpoint does: still camera, still glass. It lifts the texel
    // toward sky-white and leaves the art visible through it. After dark
    // the pane is LIT: the texel's own shine pattern carried into a warm
    // lamp colour, replacing the shaded answer above -- so a lit window
    // ignores the sun, every shadow and the hour's tint, exactly as a
    // window with a lamp behind it does.
    // glassOn gates the whole thing per DRAW: the mask is shaped like the
    // tileset atlas, and only meshes textured FROM that atlas may consult
    // it -- a character samples its own sprite sheet, whose coordinates
    // land on the mask's pane rectangles by accident and would stripe the
    // cast with lamplight at night.
    float glass = Texel(glassMask, tc).a * glassOn;
    if (glass > 0.0) {
      // the sweep lives in the PANE's own space (atlas texels), not the
      // screen's: a pattern anchored to the screen has the world sliding
      // through it at zoom speed whenever the camera pans, which strobed --
      // worst where the pan and the phase ran opposite ways. Anchored to
      // the glass, panning moves nothing; only the phase does, a fraction
      // of a texel per step, the same in every walking direction.
      float sweep = sin(tc.x * glassSize.x * 0.8 - glassPhase);
      float glint = pow(max(sweep, 0.0), 20.0) * 0.55 * glassGlint;
      vec3 pane = mix(rgb, vec3(0.93, 0.97, 1.0), glint * glass);
      float shine = dot(p.rgb, vec3(0.299, 0.587, 0.114));
      vec3 lamp = vec3(1.0, 0.84, 0.5) * (0.5 + 0.55 * shine);
      rgb = mix(pane, lamp, glassNight * glass);
    }
    // The hidden player is a SHAPE, not a dimmed picture of itself. Tinting
    // through `color` could only multiply the sprite's own pixels, which
    // darkens each one by its own amount and keeps the character's internal
    // detail; replacing the colour outright is what makes it read as one
    // solid silhouette. Last in the chain, so neither the sun nor a voxel
    // seam can mottle it.
    rgb = mix(rgb, ghostColor, ghost);
    return vec4(rgb, 1.0) * color;
  }
#endif
]]

-- Two compilations of SHADER: the plain scene, and the same thing with the
-- voxel wireframe compiled in. The wireframe needs shader derivatives
-- (fwidth), the one piece of this a driver can refuse, so it is a separate
-- build rather than a branch -- a refusal costs the grid and nothing else.
-- Each entry is nil = untried, false = unavailable.
local shaders = { [false] = nil, [true] = nil }
local activeShader = nil      -- the variant this pass bound

-- Scene canvases, one per NAMED SLOT. There are exactly two callers and
-- they want different sizes -- the free-roam pass renders at the window's
-- pixel dimensions, the overworld battle at the GB's 160x144 -- and a
-- single cached canvas made every battle entry and exit reallocate one.
-- A slot reallocates only when its OWN size changes, which is a window
-- resize, so the pair is stable for a session.
local slots = {}
local canvas, canvasW, canvasH = nil, 0, 0   -- the slot this pass bound
local active = false

local IDENTITY = Mat4.identity()

-- Whether the driver admits to supporting derivatives. Only a hint --
-- the compile below is the real test -- but it saves building a shader
-- that was never going to work, and it is how LOVE reports the ES2
-- extension the grid rides on.
local function derivativesOK()
  if not (love.graphics and love.graphics.getSupported) then return false end
  local ok, caps = pcall(love.graphics.getSupported)
  return ok and caps and caps.shaderderivatives == true
end

-- The scene shader. `grid` asks for the wireframe variant, and nil comes
-- back when that one will not build -- callers then fall back to the plain
-- one rather than losing the whole 3D pass.
function Voxel3D.shader(grid)
  grid = grid and true or false
  if shaders[grid] == nil then
    if grid and not derivativesOK() then
      shaders[grid] = false
    else
      local src = grid and ("#define VOXEL_GRID 1\n" .. SHADER) or SHADER
      local ok, sh = pcall(love.graphics.newShader, src)
      shaders[grid] = ok and sh or false
    end
  end
  return shaders[grid] or nil
end

-- Whether the 3D path can run at all. False on a headless test run (no
-- love.graphics), without shader support, or where a depth canvas cannot be
-- created -- every caller treats that as "stay on the 2D path".
function Voxel3D.available()
  if not (love.graphics and love.graphics.newCanvas
          and love.graphics.setDepthMode) then
    return false
  end
  return Voxel3D.shader() ~= nil
end

-- Build a mesh in the shared format. `verts` is the LOVE vertex list and
-- `map` the triangle index list. Returns nil when meshes are unavailable,
-- which the callers treat the same way they treat a missing model.
function Voxel3D.newMesh(verts, map)
  if #verts == 0 then return nil end
  local ok, mesh = pcall(love.graphics.newMesh, Voxel3D.FORMAT, verts,
                         "triangles", "static")
  if not ok then return nil end
  if map and #map > 0 then pcall(mesh.setVertexMap, mesh, map) end
  return mesh
end

-- The quad corner offsets and UV corners for one face direction, in the
-- order the vertex map below stitches into two triangles. Corners are unit
-- offsets from the voxel's (x, y, z) minimum corner.
Voxel3D.FACE_CORNERS = {
  [1] = { { 1, 0, 0 }, { 1, 0, 1 }, { 1, 1, 1 }, { 1, 1, 0 } },  -- +X
  [2] = { { 0, 0, 1 }, { 0, 0, 0 }, { 0, 1, 0 }, { 0, 1, 1 } },  -- -X
  [3] = { { 0, 1, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 0, 1, 1 } },  -- +Y
  [4] = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 }, { 0, 0, 0 } },  -- -Y
  [5] = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } },  -- +Z
  [6] = { { 1, 0, 0 }, { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 } },  -- -Z
}

-- Append the six indices of quad `n` (0-based) to a triangle index list.
function Voxel3D.pushQuad(map, n)
  local b = n * 4
  map[#map + 1] = b + 1
  map[#map + 1] = b + 2
  map[#map + 1] = b + 3
  map[#map + 1] = b + 1
  map[#map + 1] = b + 3
  map[#map + 1] = b + 4
end

-- ---------------------------------------------------------------- camera --

-- An explicit camera, replacing the orbit below for as long as it is set:
-- { eye = {x,y,z}, focus = {x,y,z}, fov = radians, curve = k or nil }.
--
-- The orbit is the free-roam camera and it is described entirely by ONE
-- number, the pitch, because that is all a camera following the player over
-- their own map ever needs. A staged shot -- the overworld battle's
-- over-the-shoulder rig (see BattleCam) -- is a placed camera: it has a yaw,
-- it does not sit above its focus, and its framing comes from the arena
-- rather than from the view size. Rather than widen the orbit into
-- something that could express both and be the wrong shape for each, a
-- caller with a camera of its own simply hands it over.
--
-- Everything downstream is unchanged by this: the shader uniforms, project()
-- and the overlay all read Voxel3D.vp / Voxel3D.eye, which are set the same
-- way either way.
Voxel3D.camera = nil

-- View and projection for a `vw` x `vh` world-pixel view centred on
-- (cx, cy) in world pixels. Returns the combined matrix.
function Voxel3D.viewProjection(cx, cy, vw, vh)
  local cam = Voxel3D.camera
  if cam then
    local eye, focus = cam.eye, cam.focus
    Voxel3D.eye = eye
    -- kept beside the eye for horizonY: where the sky's pale end goes is a
    -- question about which way this camera looks, and only these two answer it
    Voxel3D.focus = focus
    local dx = eye[1] - focus[1]
    local dy = eye[2] - focus[2]
    local dz = eye[3] - focus[3]
    local dist = math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
    local proj = Mat4.perspective(cam.fov, vw / vh,
                                  math.max(1, dist * 0.05), dist * 4 + 4096)
    -- the same clip-space Y flip the orbit needs, for the same reason: we
    -- bypass LOVE's transform_projection and canvas coordinates run Y down
    proj = Mat4.mul(Mat4.scale(1, -1, 1), proj)
    -- world up, so the horizon stays level -- a placed camera that rolled
    -- with its own pitch would tip the whole arena
    return Mat4.mul(proj, Mat4.lookAt(eye, focus, { 0, 1, 0 }))
  end

  local a = Voxel.angle
  local focal = Voxel.FOCAL
  local dist = focal * vh
  -- the FOV that makes a straight-down camera at `dist` frame exactly `vh`
  -- world pixels, which is the framing the flat view already has
  local fov = 2 * math.atan(1 / (2 * focal))

  local focus = { cx, 0, cy }
  local eye = { cx, dist * math.cos(a), cy + dist * math.sin(a) }
  -- exposed for camera-facing billboards (VoxelScene yaws sprites at it)
  Voxel3D.eye = eye
  Voxel3D.focus = focus
  -- perpendicular to the view direction in the YZ plane: north is screen-up
  -- when looking straight down, +Y is screen-up when looking level. Never
  -- parallel to the view direction, so there is no degenerate a = 0 case.
  local up = { 0, math.sin(a), -math.cos(a) }

  local proj = Mat4.perspective(fov, vw / vh,
                                math.max(1, dist * 0.05), dist * 4 + 4096)
  -- Flip clip-space Y. Mat4.perspective emits textbook GL clip space with
  -- +Y up, but we bypass LOVE's own transform_projection, and LOVE's canvas
  -- coordinates run Y DOWN -- so without this the entire scene composites
  -- vertically mirrored: north at the bottom and buildings extruding
  -- downward. Winding flips with it, which is free here because the pass
  -- draws with culling off.
  proj = Mat4.mul(Mat4.scale(1, -1, 1), proj)
  return Mat4.mul(proj, Mat4.lookAt(eye, focus, up))
end

-- ------- the horizon
--
-- Where the ground plane's vanishing line lands, in canvas pixels down from the
-- top edge, or nil when this camera has no horizon to find.
--
-- Not a fraction picked by eye. A direction ALONG the ground is a point at
-- infinity, and putting one through the same matrix the geometry is drawn with
-- gives the line every ground plane in the scene converges on -- so the sky's
-- pale end meets the horizon at any pitch, fov, window shape or zoom, and rides
-- the camera tween instead of having to be retuned against it.
--
-- The world CURVE is not in it, and cannot be: it bends distant ground down in
-- the vertex shader, so the ground's apparent edge sits BELOW this line by
-- however much the bend took. What shows in between is the haze the sky's fill
-- already is, which is what a curved-away horizon should look like.
--
-- nil in two cases, both meaning "no horizon in this frame": a camera looking
-- straight down, whose forward direction has no horizontal part to send to
-- infinity, and one whose vanishing line is behind it.
function Voxel3D.horizonY(h)
  local m, eye, focus = Voxel3D.vp, Voxel3D.eye, Voxel3D.focus
  if not (m and eye and focus and h and h > 0) then return nil end
  local dx = focus[1] - eye[1]
  local dz = focus[3] - eye[3]
  local len = math.sqrt(dx * dx + dz * dz)
  if len < 1e-6 then return nil end
  dx, dz = dx / len, dz / len
  -- a DIRECTION, so its w is zero and the matrix's translation column drops
  -- out; the clip-space Y flip is already baked into m, so this comes out in
  -- canvas coordinates rather than needing one
  local y = m[5] * dx + m[7] * dz
  local w = m[13] * dx + m[15] * dz
  if w <= 1e-6 then return nil end
  return (y / w * 0.5 + 0.5) * h
end

-- ------- the hour's light
--
-- What the scene shader multiplies every surface by (see dayTint in the
-- shader). Set per pass by whoever knows what map is being drawn --
-- VoxelScene for free-roam, BattleScene for the arena -- because "is this
-- outdoors" is the map's question, not this pass's. Neutral until somebody
-- answers it, so a caller that never does draws exactly what it always drew.
Voxel3D.tint = { 1, 1, 1 }

-- The window-glass pass, set the same way and for the same reason: the
-- MASK belongs to the map's tileset (GlassMask.texture) and how lit the
-- panes are belongs to the hour and to being outdoors at all
-- (DayNight.windowLight). nil / 0 -- the defaults -- draw no glass effect.
Voxel3D.glassMask = nil
Voxel3D.glassNight = 0

-- the glint, fed by the camera's TRAVEL rather than by a clock (see
-- VoxelScene.glintStep): the phase is radians already wrapped to 2pi, and
-- the strength is 0 whenever the view has been still for a beat
Voxel3D.glassPhase = 0
Voxel3D.glassGlint = 0

-- The sun or moon disc's place on this camera's canvas, or nil when the
-- body is set, on the southern half of the sky, or behind the camera.
--
-- The direction comes from DayNight (true bearing, squashed elevation) and
-- goes through the SAME matrix the geometry is drawn with, as a point at
-- infinity -- exactly how horizonY finds the vanishing line. So the disc's
-- azimuth is honest: it stands over the point on the horizon its shadows
-- point away from, at every pitch, fov, window shape and zoom.
--
-- Must run after beginScene has set Voxel3D.vp for this frame's camera.
function Voxel3D.skyBody(w, h)
  local m = Voxel3D.vp
  local b = m and DayNight.body()
  if not b then return nil end
  local x = m[1] * b.dx + m[2] * b.dy + m[3] * b.dz
  local y = m[5] * b.dx + m[6] * b.dy + m[7] * b.dz
  local ww = m[13] * b.dx + m[14] * b.dy + m[15] * b.dz
  if ww <= 1e-6 then return nil end
  local amt, color = DayNight.glow()
  return {
    x = (x / ww * 0.5 + 0.5) * w,
    y = (y / ww * 0.5 + 0.5) * h,
    moon = b.moon,
    glowAmt = amt,
    glowColor = color,
  }
end

-- ----------------------------------------------------------------- scene --

-- Begin the 3D pass into a `w` x `h` pixel canvas centred on world
-- (cx, cy), covering `vw` x `vh` world pixels. Returns false when the pass
-- could not start, in which case the caller must not call endScene.
-- `sky` is an optional {r, g, b, a} in 0..1 to clear the void to, for the
-- pitch where the horizon is in frame (VoxelScene.skyFor). nil leaves the
-- void transparent, which is what every rung below it wants.
-- `slot` names which cached canvas to render into (see `slots` above);
-- omitted is the free-roam world pass.
function Voxel3D.beginScene(w, h, cx, cy, vw, vh, sky, slot)
  -- the wireframe variant when the player has it on AND it built; either
  -- answer falls through to the plain scene rather than to no scene
  local grid = VoxelGrid.enabled()
  local sh = grid and Voxel3D.shader(true) or nil
  if not sh then
    grid, sh = false, Voxel3D.shader()
  end
  if not sh then return false end
  local name = slot or "world"
  local held = slots[name]
  if not (held and held.w == w and held.h == h) then
    local ok, c = pcall(love.graphics.newCanvas, w, h)
    if not ok then return false end
    c:setFilter("nearest", "nearest")
    if held and held.canvas and held.canvas.release then
      pcall(held.canvas.release, held.canvas)
    end
    held = { canvas = c, w = w, h = h }
    slots[name] = held
  end
  canvas, canvasW, canvasH = held.canvas, w, h
  -- a depth buffer is what makes occlusion real: walk behind a building and
  -- the building wins, with no y-sorting anywhere
  local ok = pcall(love.graphics.setCanvas,
                   { canvas, depth = true })
  if not ok then
    pcall(love.graphics.setCanvas)
    return false
  end
  -- Ahead of the clear, because the sky's bands are placed off the ground
  -- plane's vanishing line and that is a property of this matrix.
  Voxel3D.vp = Voxel3D.viewProjection(cx, cy, vw, vh)
  if sky then
    love.graphics.clear(sky[1], sky[2], sky[3], sky[4] or 1, true, true)
    -- The sky goes down here, in the one window in this function where a
    -- rectangle is just a rectangle: the depth mode and the scene shader are
    -- both set below. Sky.paint puts them aside anyway -- beginScene is not the
    -- only thing that has ever left a shader bound.
    --
    -- w / vw is this frame's pixels per WORLD pixel, which is the size a diorama
    -- pixel is on screen: the sky's dither grid is cut to that, so its squares
    -- are the same size as the world's own and follow every resize and zoom.
    -- The banded sky also hangs the hour's sun or moon (skyBody projects it
    -- through this very camera); a flat sky has no bands and hangs nothing.
    Sky.paint(w, h, sky, Voxel3D.horizonY(h), w / math.max(1, vw or w),
              sky.bands and Voxel3D.skyBody(w, h) or nil)
  else
    love.graphics.clear(0, 0, 0, 0, true, true)
  end
  love.graphics.setDepthMode("lequal", true)
  -- models mirror on X for right-facing and alternate walk steps, which
  -- flips winding; hidden faces are already culled at build time, so there
  -- is nothing to gain from backface culling and a real bug to avoid
  love.graphics.setMeshCullMode("none")
  love.graphics.setShader(sh)
  love.graphics.setColor(1, 1, 1, 1)
  pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
  pcall(sh.send, sh, "eye", Voxel3D.eye)
  -- the sun's frame, filled by ShadowMap just before this pass opened.
  -- Sent unconditionally: the sampler is declared either way, and leaving
  -- one unbound is a driver-dependent crash rather than a fallback.
  local map = ShadowMap.active()
  pcall(sh.send, sh, "sunVP", "row", map and ShadowMap.uvVP or IDENTITY)
  local tex = ShadowMap.texture()
  if tex then pcall(sh.send, sh, "sunMap", tex) end
  pcall(sh.send, sh, "sunDark", map and Voxel3D.SHADOW_ALPHA or 0)
  pcall(sh.send, sh, "sunBias", ShadowMap.bias)
  local texel = 1 / ShadowMap.res
  pcall(sh.send, sh, "sunTexel", { texel, texel })
  if grid then
    pcall(sh.send, sh, "gridDark", VoxelGrid.DARK)
    pcall(sh.send, sh, "gridWidth", VoxelGrid.WIDTH)
  end
  -- ordinary shading until the silhouette pass asks for otherwise. Sent
  -- every frame rather than once, because a scene that opened mid-ghost --
  -- a driver hiccup between beginGhost and endGhost -- would otherwise
  -- start out flattening everything it drew.
  pcall(sh.send, sh, "ghost", 0)
  pcall(sh.send, sh, "ghostColor", Voxel3D.GHOST_COLOR)
  -- the hour's light, as the caller last set it (see Voxel3D.tint)
  pcall(sh.send, sh, "dayTint", Voxel3D.tint or { 1, 1, 1 })
  -- the window glass: the tileset's mask (or the blank -- the sampler is
  -- declared either way, and unbound is a driver-dependent crash), how lit
  -- the panes are, and the movement-fed glint as the caller last set it
  local mask = Voxel3D.glassMask or GlassMask.blank()
  if mask then
    pcall(sh.send, sh, "glassMask", mask)
    local ok, mw, mh = pcall(mask.getDimensions, mask)
    pcall(sh.send, sh, "glassSize", { ok and mw or 1, ok and mh or 1 })
  end
  pcall(sh.send, sh, "glassNight", Voxel3D.glassNight or 0)
  pcall(sh.send, sh, "glassPhase", Voxel3D.glassPhase or 0)
  pcall(sh.send, sh, "glassGlint", Voxel3D.glassGlint or 0)
  -- on until a sprite pass says otherwise, reset per frame like `ghost`
  pcall(sh.send, sh, "glassOn", 1)
  -- the curved world bends about the camera's focus, so the horizon keeps
  -- a fixed distance ahead of the player rather than sitting on the map.
  -- A placed camera may decline it outright (Voxel3D.camera.curve = 0).
  local placed = Voxel3D.camera
  Voxel3D.curveK = (placed and placed.curve) or WorldCurve.k(vh)
  Voxel3D.curveX, Voxel3D.curveZ = cx, cy
  pcall(sh.send, sh, "curve", { cx, cy, Voxel3D.curveK })
  -- clip w at the focus point, the reference depth project() reports scale
  -- against (so scale == 1 for anything standing at the view centre)
  local m = Voxel3D.vp
  Voxel3D.focusW = m[13] * cx + m[14] * 0 + m[15] * cy + m[16]
  activeShader = sh
  active = true
  return true
end

-- Depth handling for the character pass. Gen 1 draws sprites over the
-- background unconditionally, so characters render with the depth test
-- forced to pass (still writing depth: the grass mesh drawn after them
-- tests against it to overdraw feet). "test" restores normal occlusion.
function Voxel3D.depth(mode)
  if not active then return end
  pcall(love.graphics.setDepthMode, mode == "always" and "always" or "lequal",
        true)
end

-- ------------------------------------------------ the player's own ghost --

-- The silhouette's colour, and how solid it is.
--
-- ONE flat grey rather than a dimmed copy of the sprite, so the shape reads
-- at a glance instead of competing with whatever is showing through it --
-- and translucent rather than opaque, so it stays a hint of where the
-- player is rather than a hole punched in the building. The wall it is
-- seen through still shows, which is what keeps it reading as "behind
-- that" instead of "in front of it".
Voxel3D.GHOST_COLOR = { 0.26, 0.26, 0.28 }
Voxel3D.GHOST_ALPHA = 0.5

-- Draw a character AGAIN wherever the ordinary draw LOST the depth test.
--
-- Honest occlusion is the point of this mode -- walk behind the Mart and the
-- Mart is genuinely in front of you -- but a player who cannot see their own
-- character has lost track of where they are standing, which the flat game
-- never allowed. So the figure is drawn a second time with the test
-- INVERTED: "greater" passes exactly where "lequal" failed, and LOVE hands
-- the compare straight to glDepthFunc, so the two are true complements.
-- Every texel of the sprite is therefore drawn once and once only -- solid
-- where it is visible, translucent where it is not -- with no seam where
-- they meet and no double-blending anywhere.
--
-- Nothing is drawn at all when nothing is in the way, and no code here ever
-- asks whether the player is occluded: the depth buffer already knows, and
-- the test is the question.
--
-- Depth WRITES are off. This pass is behind the scenery by definition, and
-- writing would file the hidden figure's depth in front of the building
-- hiding it -- the grass pass at the end of the frame reads that buffer.
--
-- The caller redraws through the ordinary character path, so the ghost keeps
-- the same mesh, matrix and camera-ward PULL as the real draw. The pull
-- matching is what keeps the leaning-over-a-near-wall case out of here: pull
-- already won that fight for the solid draw, so this pass finds nothing left
-- to paint and a character merely standing close to a wall does not shimmer
-- a ghost over it.
function Voxel3D.beginGhost()
  if not active then return end
  pcall(love.graphics.setDepthMode, "greater", false)
  love.graphics.setColor(1, 1, 1, Voxel3D.GHOST_ALPHA)
  if activeShader then
    pcall(activeShader.send, activeShader, "ghostColor", Voxel3D.GHOST_COLOR)
    pcall(activeShader.send, activeShader, "ghost", 1)
  end
end

-- Flatten whatever is drawn next to one solid colour, or nil to stop.
--
-- The same `ghost` path the silhouette uses, WITHOUT beginGhost's inverted
-- depth test and half alpha -- this is for something drawn normally that
-- simply wants to come out one colour, which is what a hit flash on a sprite
-- is. beginScene resets the uniform every frame, so a pass that forgets to
-- clear it cannot leak into the next one.
-- `amount` is how far toward that colour, 0..1; omitted is all the way.
-- Anything short of 1 leaves the sprite's own shading showing through, which
-- is the difference between a hit flash and a white cut-out.
function Voxel3D.flatten(color, amount)
  if not (active and activeShader) then return end
  local sh = activeShader
  if color then
    pcall(sh.send, sh, "ghostColor", color)
    pcall(sh.send, sh, "ghost", math.max(0, math.min(1, amount or 1)))
  else
    pcall(sh.send, sh, "ghost", 0)
  end
end

-- Whether what is drawn next carries the voxel wireframe. false for the
-- length of a draw, true to put it back.
--
-- The wireframe reads a mesh's OWN model space and darkens its integer
-- planes (see VoxelGrid), which is only a wireframe because every mesh in
-- this mode is built ONE UNIT PER VOXEL: terrain in world pixels, a
-- character card in the sprite's own pixels. A mesh whose model space does
-- not mean that gets no wireframe out of the same shader -- it gets
-- whichever of its integer planes happen to fall inside it, which is a
-- stray line rather than a seam.
--
-- So this is not a style switch. It is how a mesh that is not on the voxel
-- grid says so, and the alternative -- rescaling such a mesh until its
-- units happen to be voxels -- would change what it IS to satisfy a
-- shading pass.
--
-- Sent rather than branched because the plain scene shader has no such
-- uniform, and the send simply does not take there -- which is right: with
-- no wireframe compiled in there is nothing to suppress.
function Voxel3D.seams(on)
  if not (active and activeShader) then return end
  pcall(activeShader.send, activeShader, "gridDark",
        on and VoxelGrid.DARK or 0)
end

-- Whether what is drawn next may consult the glass mask. false for the
-- length of a sprite-sheet pass, true to put it back.
--
-- Same shape as seams(), for the same reason: the mask means "this ATLAS
-- texel is window glass", so it is only an answer for meshes textured from
-- the tileset atlas. A sprite sheet's coordinates land wherever they land
-- on it, and at night that painted lamplight stripes down whoever was
-- standing in the wrong part of their own sheet.
function Voxel3D.glass(on)
  if not (active and activeShader) then return end
  pcall(activeShader.send, activeShader, "glassOn", on and 1 or 0)
end

function Voxel3D.endGhost()
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", true)
  love.graphics.setColor(1, 1, 1, 1)
  -- back to ordinary shading before anything else draws; leaving it set
  -- would flatten the grass pass that follows into one grey sheet
  if activeShader then
    pcall(activeShader.send, activeShader, "ghost", 0)
  end
end

-- -------------------------------------------------------------- shadows --

-- The sun. One direction, shared by everything that needs to know where
-- the light comes from: the shadow map, the flat fallback below, and the
-- baked contact shading in ChunkMesher. Both shears are negative, which
-- hangs it in the SOUTHEAST and throws every shadow northwest -- up and to
-- the left on screen.
Voxel3D.SHADOW_KX = ShadowMap.KX   -- west drift per pixel of height
Voxel3D.SHADOW_KZ = ShadowMap.KZ   -- north drift per pixel of height
Voxel3D.SHADOW_EPS = 0.25     -- float above the ground to dodge z-fighting
Voxel3D.SHADOW_ALPHA = 0.40   -- how far into black a shadowed surface goes

-- Whether real shadows are running this frame. False headless and on any
-- driver the sun pass could not start on, which is when VoxelScene falls
-- back to the flat decals below.
function Voxel3D.shadowsActive()
  return ShadowMap.active()
end

-- The upright card a character presents to the sun: its 16x16 sprite quad
-- (corners (0,0,0)..(16,16,0), feet at y = 0) standing on the middle of
-- the cell whose top-left is world (px, py), feet at height `y`.
--
-- This is the caster the shadow pass draws -- deliberately NOT the leaning
-- slab the camera sees. The slab tips back by the camera's pitch to read
-- face-on, which is a trick played on the viewer; letting the sun see it
-- too would shrink every shadow to nothing as the camera flattened toward
-- top-down. The sun sees the figure standing up, at every tilt.
--
-- The z-flatten matters when this is used the other way round, as the
-- lookup transform a lit slab reads its own shadowing with (Voxel3D.draw's
-- `sunModel`): it collapses the slab's side relief onto the card plane, so
-- every vertex asks about the exact surface the sun recorded rather than
-- one a few pixels behind it, and a figure cannot fringe itself. On the
-- caster itself it is a no-op -- that quad is already flat.
function Voxel3D.casterMatrix(px, py, y, mirror)
  local m = Mat4.translate(px + 8, y, py + 8)
  if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
  return Mat4.mul(Mat4.mul(m, Mat4.translate(-8, 0, 0)),
                  Mat4.scale(1, 1, 0))
end

-- FALLBACK ONLY (no shadow map: headless, or a driver that cannot make the
-- canvas). Character drop shadows as decals -- the sprite frame squashed
-- flat onto its ground plane and drawn translucent black. It can only ever
-- paint the floor, which is the whole reason ShadowMap exists.
--
-- Flattening is measured from the ground plane, so a hop slides the whole
-- shadow along the sun line while it stays glued to the ground -- the
-- classic jump-shadow tell.
function Voxel3D.shadowMatrix(px, py, gh, lift, mirror)
  local card = Voxel3D.casterMatrix(px, py, gh + (lift or 0), mirror)
  -- flatten about the ground plane: y' = 0, x/z shear by height above it
  local squash = { 1, Voxel3D.SHADOW_KX, 0, 0,
                   0, 0,                 0, 0,
                   0, Voxel3D.SHADOW_KZ, 1, 0,
                   0, 0,                 0, 1 }
  local m = Mat4.mul(squash, Mat4.mul(Mat4.translate(0, -gh, 0), card))
  return Mat4.mul(Mat4.translate(0, gh + Voxel3D.SHADOW_EPS, 0), m)
end

-- The decal pass draws between terrain and characters: depth-tested so a
-- building still hides a shadow behind it, but NOT depth-writing -- the
-- grass tufts drawn at the end of the frame must keep beating the ground
-- plane, and one quad per entity has no self-overlap to guard against.
function Voxel3D.beginShadows()
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", false)
  love.graphics.setColor(0, 0, 0, Voxel3D.SHADOW_ALPHA)
end

function Voxel3D.endShadows()
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", true)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draw one mesh with `model` (a Mat4) applied. Texture may be nil to keep
-- whatever the mesh already carries. `pull` moves every vertex toward the
-- eye along its own ray (see the shader) -- the artifact-free depth bias
-- the character and grass passes ride in front of the terrain.
--
-- `sunModel` is where the SHADOW PASS put this same geometry, and defaults
-- to `model` because for everything but a character the two are one matrix.
-- A character is drawn leaning and cast upright, so it must hand over the
-- upright transform or it reads its own shadow as falling on itself.
function Voxel3D.draw(mesh, texture, model, pull, sunModel)
  if not (active and mesh) then return end
  -- the variant beginScene actually bound, not whichever one is default:
  -- sending a uniform to the other shader would go nowhere
  local sh = activeShader
  if not sh then return end
  if texture then mesh:setTexture(texture) end
  -- LOVE defaults matrix uniforms to column-major; Mat4 is row-major
  pcall(sh.send, sh, "model", "row", model or IDENTITY)
  pcall(sh.send, sh, "sunModel", "row", sunModel or model or IDENTITY)
  pcall(sh.send, sh, "pull", pull or 0)
  love.graphics.draw(mesh)
end

-- Project a world point to canvas pixels: returns (x, y, scale), or nil
-- when the point is behind the camera. `scale` is how much bigger a thing
-- at that depth appears than one at the focus point, so a caller can size
-- with it -- or ignore it and draw unscaled, which is what tilt mode's
-- billboards do.
--
-- This is what lets the overworld's FX closures (the "!" bubble, the heal
-- machine, the Fly bird, the fishing rod) draw in voxel mode completely
-- unchanged: they stay ordinary 2D draws, anchored to wherever their ground
-- point lands under the same camera the 3D pass used.
function Voxel3D.project(wx, wy, wz)
  local m = Voxel3D.vp
  if not m then return nil end
  -- the same drop the vertex shader applies, or every FX anchored to a
  -- ground point floats off its own feet the moment that ground bends
  wy = wy - WorldCurve.drop(Voxel3D.curveK or 0, Voxel3D.curveX or 0,
                            Voxel3D.curveZ or 0, wx, wz)
  local cx = m[1] * wx + m[2] * wy + m[3] * wz + m[4]
  local cy = m[5] * wx + m[6] * wy + m[7] * wz + m[8]
  local cw = m[13] * wx + m[14] * wy + m[15] * wz + m[16]
  if cw <= 1e-6 then return nil end
  -- viewProjection already flipped clip-space Y into LOVE's Y-down canvas
  -- convention, so both axes map the same way here -- no second flip
  local x = (cx / cw * 0.5 + 0.5) * canvasW
  local y = (cy / cw * 0.5 + 0.5) * canvasH
  return x, y, (Voxel3D.focusW or cw) / cw
end

-- Re-bind the scene canvas for ordinary 2D drawing (no depth test), so
-- screen-space overlays can be composited into the same image the 3D pass
-- just filled. Pairs with endScene, which unbinds it.
function Voxel3D.beginOverlay()
  if not canvas then return false end
  love.graphics.setShader()
  love.graphics.setDepthMode()
  local ok = pcall(love.graphics.setCanvas, canvas)
  if not ok then return false end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- Close the overlay begun by beginOverlay.
function Voxel3D.endOverlay()
  love.graphics.setCanvas()
  active, activeShader = false, nil
end

-- End the pass and hand back the rendered canvas.
function Voxel3D.endScene()
  if not active then return nil end
  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.setMeshCullMode("none")
  love.graphics.setCanvas()
  active, activeShader = false, nil
  return canvas
end

function Voxel3D.canvas()
  return canvas
end

-- Drop the GPU objects (window resize, hot reload).
function Voxel3D.invalidate()
  for name, held in pairs(slots) do
    if held.canvas and held.canvas.release then
      pcall(held.canvas.release, held.canvas)
    end
    slots[name] = nil
  end
  canvas, canvasW, canvasH = nil, 0, 0
  ShadowMap.invalidate()
  -- the sky is part of this pass and holds a shader of its own
  Sky.invalidate()
  -- and the glass masks are textures of this context too
  GlassMask.invalidate()
end

return Voxel3D
