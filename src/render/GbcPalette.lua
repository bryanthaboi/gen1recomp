-- Draws a 4-shade GB image through a GBC palette.
--
-- Every 2bpp sheet the importer writes is grayscale: shade 0 is white
-- (or transparent), shade 3 is black (ImageWriter.SHADES).  A GBC game picks
-- four real colors per tile instead, so this recovers the shade index from the
-- red channel and substitutes the palette entry -- one shader for map tiles,
-- OW sprites, battle pics and menu chrome alike.
--
-- Shade recovery is exact rather than approximate: the source values are
-- 1, 2/3, 1/3, 0, so rounding (1 - r) * 3 lands on 0..3 with a half-step of
-- headroom either side, which survives texture filtering set to nearest.
--
-- Alpha passes through untouched, so a sheet written with transparent shade 0
-- (OW sprites, the font) keeps its cutout.

-- COLOR (the port's own display option, Gold's answer to the Gen 1 COLORS
-- row).  Every colour in the Gen 2 port arrives here, because a CGB game's
-- colour IS its palettes -- so one substitution at this seam recolours the
-- whole game without a single screen knowing about it:
--
--   DMG      the original grey Game Boy.  Every palette collapses to the
--            four hardware shades, and the sheets that are drawn straight
--            (chrome, text) are already those shades, so the screen is
--            uniformly monochrome.
--   CLASSIC  the DMG pea-soup green.  Rendered as DMG and then run through
--            the green ramp as a final full-screen pass, which is what
--            GbcPalette.presentColors is for -- a shade map is exactly what
--            this shader already does, so it needs no second shader.

local GbcPalette = {}

GbcPalette.MODES = { "gbc", "dmg", "classic" }
GbcPalette.MODE_LABELS = { gbc = "GEN 2", dmg = "DMG", classic = "CLASSIC",
                            custom = "GBC" }
GbcPalette.mode = "gbc"

GbcPalette.CUSTOM_MODE = "custom"

-- rBGP's four shades as the hardware shows them.
local DMG_SHADES = {
  { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 },
}
-- #9BBC0F / #8BAC0F / #306230 / #0F380F, the same ramp Gen 1's CLASSIC uses.
local CLASSIC_SHADES = {
  { 155, 188, 15 }, { 139, 172, 15 }, { 48, 98, 48 }, { 15, 56, 15 },
}

local SHADER_SOURCE = [[
extern vec3 pal0;
extern vec3 pal1;
extern vec3 pal2;
extern vec3 pal3;

vec4 effect(vec4 tint, Image tex, vec2 uv, vec2 screen) {
  vec4 px = Texel(tex, uv);
  float shade = floor((1.0 - px.r) * 3.0 + 0.5);
  vec3 rgb = pal0;
  if (shade > 2.5) {
    rgb = pal3;
  } else if (shade > 1.5) {
    rgb = pal2;
  } else if (shade > 0.5) {
    rgb = pal1;
  }
  return vec4(rgb, px.a) * tint;
}
]]

-- BG drawn over OBJ with OAM priority: palette index 0 is transparent to the
-- sprite underneath (hardware OBJ-behind-BG rule), colours 1-3 are opaque.
local KEYED_SHADER_SOURCE = [[
extern vec3 pal0;
extern vec3 pal1;
extern vec3 pal2;
extern vec3 pal3;

vec4 effect(vec4 tint, Image tex, vec2 uv, vec2 screen) {
  vec4 px = Texel(tex, uv);
  float shade = floor((1.0 - px.r) * 3.0 + 0.5);
  vec3 rgb = pal0;
  if (shade > 2.5) {
    rgb = pal3;
  } else if (shade > 1.5) {
    rgb = pal2;
  } else if (shade > 0.5) {
    rgb = pal1;
  }
  float alpha = shade < 0.5 ? 0.0 : px.a;
  return vec4(rgb, alpha) * tint;
}
]]

-- rBGP, the DMG background palette register, as a remap of an ALREADY DRAWN
-- texture.
--
-- A frame this port has finished drawing holds CGB colours and no shade index
-- any more, so the remap has to run backwards: match the pixel to the palette
-- entry that produced it, then substitute whatever the rBGP byte sends that
-- entry to.  With one palette that is exact, because the four entries are the
-- only colours the texture can hold; a composited frame is only as exact as
-- GbcPalette.remapTable's dedupe (see the `ambiguous` count there).
--
-- `remapTol` is a SQUARED distance and it is what keeps this pass off pixels
-- that were never a palette colour -- a letterboxed border, a linear-filtered
-- resample -- rather than snapping them to the nearest entry.  Palette colours
-- land on exact 1/255 steps through a nearest-filtered canvas, so the default
-- is a couple of steps of headroom and nothing like the gap between two
-- entries of the same palette.
local REMAP_SOURCE = [[
extern int remapCount;
extern float remapTol;
extern vec3 remapSrc[64];
extern vec3 remapDst[64];

vec4 effect(vec4 tint, Image tex, vec2 uv, vec2 screen) {
  vec4 px = Texel(tex, uv);
  vec3 mapped = px.rgb;
  float best = remapTol;
  for (int i = 0; i < 64; i++) {
    if (i >= remapCount) { break; }
    vec3 d = px.rgb - remapSrc[i];
    float dist = dot(d, d);
    if (dist < best) {
      best = dist;
      // Indexed by the LOOP variable and never by a value carried out of the
      // loop: GLSL ES 1.00 only allows a constant-index-expression into a
      // uniform array, which a loop counter is and `best`'s winner is not.
      mapped = remapDst[i];
    }
  }
  return vec4(mapped, px.a) * tint;
}
]]

-- The compiled-in array length above.  A map's eight BG palettes plus its
-- eight OBJ palettes are 64 colours before dedupe, which is the worst case
-- this has to hold (home/fade.asm:32-38).
GbcPalette.REMAP_MAX = 64
-- Squared RGB distance, in 0..1 units: three 8-bit steps.
GbcPalette.REMAP_TOLERANCE = (3 / 255) ^ 2

local shader = nil
local failed = false
local keyedShader = nil
local keyedFailed = false
local remapShader = nil
local remapFailed = false

-- nil (and a one-shot warning) if shaders are unavailable, so callers can fall
-- back to the plain grayscale draw instead of crashing a whole boot.
function GbcPalette.shader()
  if shader or failed then return shader end
  if not (love and love.graphics and love.graphics.newShader) then
    failed = true
    return nil
  end
  local ok, result = pcall(love.graphics.newShader, SHADER_SOURCE)
  if not ok then
    failed = true
    return nil
  end
  shader = result
  return shader
end

function GbcPalette.keyedShader()
  if keyedShader or keyedFailed then return keyedShader end
  if not (love and love.graphics and love.graphics.newShader) then
    keyedFailed = true
    return nil
  end
  local ok, result = pcall(love.graphics.newShader, KEYED_SHADER_SOURCE)
  if not ok then
    keyedFailed = true
    return nil
  end
  keyedShader = result
  return keyedShader
end

-- The same contract as GbcPalette.shader for the backwards pass: nil rather
-- than an error, so a caller can fall back to its own approximation.
function GbcPalette.remapShader()
  if remapShader or remapFailed then return remapShader end
  if not (love and love.graphics and love.graphics.newShader) then
    remapFailed = true
    return nil
  end
  local ok, result = pcall(love.graphics.newShader, REMAP_SOURCE)
  if not ok then
    remapFailed = true
    return nil
  end
  remapShader = result
  return remapShader
end

function GbcPalette.available()
  return GbcPalette.shader() ~= nil
end

local function channel(colors, index)
  local c = colors and colors[index]
  if not c then return 0, 0, 0 end
  return (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255
end

GbcPalette.customRamp = nil

function GbcPalette.setCustomRamp(ramp)
  local prev = GbcPalette.customRamp
  GbcPalette.customRamp = ramp
  if (prev ~= nil) ~= (ramp ~= nil) or prev ~= ramp then
    pcall(function() require("src.render.SpriteRenderer").invalidate() end)
  end
end

-- What a palette actually draws as under the current COLOR mode.  Anything
-- that reads a colour out of a palette directly -- a canvas cleared to BG
-- colour 0, say -- has to go through this too, or the backdrop would keep its
-- cart colour while everything on top of it went grey.
function GbcPalette.resolve(colors)
  if GbcPalette.customRamp then return GbcPalette.customRamp end
  if GbcPalette.mode == "gbc" then return colors end
  return DMG_SHADES
end

--------------------------------------------------------------------------
-- rBGP as data
--------------------------------------------------------------------------

-- %11100100.  The `dc` macro emits colour 3 FIRST, so `dc 3, 2, 1, 0` packs to
-- $e4 and reads back as "colour i shows shade i": the identity.
GbcPalette.BGP_IDENTITY = 0xe4

-- The byte's four 2-bit fields, colour 0 in the low bits, returned 1-based so
-- shades[i + 1] is the shade colour i shows.
function GbcPalette.bgpShades(byte)
  byte = byte or GbcPalette.BGP_IDENTITY
  local shades = {}
  for index = 0, 3 do
    shades[index + 1] = math.floor(byte / (4 ^ index)) % 4
  end
  return shades
end

-- CopyPals (home/palettes.asm), which is the whole of what DmgToCgbBGPals does
-- on a CGB: a palette's four entries are REORDERED by the rBGP byte, so a pixel
-- drawn as colour i comes back as colour bgp(i) OF ITS OWN PALETTE.
--
-- This is why a brightness veil can never be right and this table can: $f9
-- (`dc 3, 3, 2, 1`) means "one step darker along this palette's own ramp", and
-- no two palettes have the same ramp.  Returns `colors` itself for the identity
-- so the common case allocates nothing.
function GbcPalette.remap(colors, byte)
  if not colors then return nil end
  if not byte or byte == GbcPalette.BGP_IDENTITY then return colors end
  local shades = GbcPalette.bgpShades(byte)
  local out = {}
  for index = 1, 4 do
    out[index] = colors[shades[index] + 1] or colors[4]
  end
  return out
end

-- The rBGP byte every subsequent GbcPalette.use / .with / .color folds in, or
-- nil for the identity.
--
-- This is the FORWARD half of the register and the exact one: a screen that is
-- still being drawn can take the permutation on its palettes before they ever
-- reach the shader, which is bit for bit DmgToCgbBGPals.  Only a frame that is
-- already baked (World's map canvas) needs the backwards pass above.
--
-- GbcPalette.useRaw deliberately does NOT fold it in: the CLASSIC present pass
-- goes through useRaw and is not a BG palette, so a byte left standing there
-- would permute the green ramp itself.
GbcPalette.bgp = nil

-- Set the active byte, returning the previous one so a caller can restore it.
-- The identity is stored as nil, so `setBgp($e4)` is the same as clearing it.
function GbcPalette.setBgp(byte)
  local previous = GbcPalette.bgp
  if byte == GbcPalette.BGP_IDENTITY then byte = nil end
  GbcPalette.bgp = byte
  return previous
end

-- One colour out of a palette, mode and active rBGP byte applied.  `index` is
-- 1-based.
function GbcPalette.color(colors, index)
  local resolved = GbcPalette.remap(GbcPalette.resolve(colors), GbcPalette.bgp)
  if resolved and resolved[index] then return resolved[index] end
  return GbcPalette.remap(DMG_SHADES, GbcPalette.bgp)[index]
end

-- The palette the finished frame is presented through, or nil when the frame
-- is already the right colour.  Only CLASSIC needs one: the scene under it has
-- rendered in the four DMG shades, so mapping those to the green ramp is the
-- same shade substitution every other call here makes.
function GbcPalette.presentColors()
  if GbcPalette.mode ~= "classic" then return nil end
  return CLASSIC_SHADES
end

function GbcPalette.setMode(mode)
  if mode == GbcPalette.CUSTOM_MODE then
    GbcPalette.mode = mode
    return mode
  end
  for _, name in ipairs(GbcPalette.MODES) do
    if name == mode then
      GbcPalette.mode = mode
      return mode
    end
  end
  GbcPalette.mode = "gbc"
  return GbcPalette.mode
end

function GbcPalette.modeLabel(mode)
  return GbcPalette.MODE_LABELS[mode or GbcPalette.mode] or "GEN 2"
end

-- Advance GBC -> DMG -> CLASSIC -> GBC.  `delta` may be -1 to step back, so
-- the OPTION screen's left press walks the ladder the other way.
function GbcPalette.cycle(delta)
  local at = 1
  for index, name in ipairs(GbcPalette.MODES) do
    if name == GbcPalette.mode then at = index break end
  end
  local count = #GbcPalette.MODES
  at = (at - 1 + (delta or 1)) % count + 1
  GbcPalette.mode = GbcPalette.MODES[at]
  GbcPalette.setCustomRamp(nil)
  return GbcPalette.mode
end

function GbcPalette.applyOptions(opts)
  local mode = GbcPalette.setMode(opts and opts.color or "gbc")
  local id = opts and opts.palette
  if id and id ~= "" then
    local ok, Palette = pcall(require, "src.render.Palette")
    GbcPalette.setCustomRamp(ok and Palette.ramp(id) or nil)
  else
    GbcPalette.setCustomRamp(nil)
  end
  return mode
end

-- Point the shader at one 4-color palette. Colors are 0-255 triples, matching
-- palettes.lua.  Returns false when there is no shader to configure.
--
-- Mode first, then rBGP: on the hardware the register indexes whatever the
-- palette buffer holds, and in DMG/CLASSIC mode that buffer IS the four grey
-- shades, so remapping the resolved palette is what the DMG itself does.
function GbcPalette.use(colors)
  return GbcPalette.useRaw(
    GbcPalette.remap(GbcPalette.resolve(colors), GbcPalette.bgp))
end

-- The same, ignoring the COLOR mode.  The present pass needs it: it IS the
-- mode, so running its own palette back through resolve would flatten the
-- green ramp to grey and the mode would do nothing.
function GbcPalette.useRaw(colors)
  local sh = GbcPalette.shader()
  if not sh then return false end
  for i = 0, 3 do
    local r, g, b = channel(colors, i + 1)
    sh:send("pal" .. i, { r, g, b })
  end
  love.graphics.setShader(sh)
  return true
end

function GbcPalette.useKeyed(colors)
  local sh = GbcPalette.keyedShader()
  if not sh then return false end
  local resolved = GbcPalette.remap(GbcPalette.resolve(colors), GbcPalette.bgp)
  for i = 0, 3 do
    local r, g, b = channel(resolved, i + 1)
    sh:send("pal" .. i, { r, g, b })
  end
  love.graphics.setShader(sh)
  return true
end

function GbcPalette.clear()
  if love and love.graphics then love.graphics.setShader() end
end

--------------------------------------------------------------------------
-- The backwards pass: remapping a frame that is already drawn
--------------------------------------------------------------------------

local function colorKey(c)
  return math.floor(c[1] or 0) .. "," .. math.floor(c[2] or 0)
    .. "," .. math.floor(c[3] or 0)
end

-- Source and destination colour lists for REMAP_SOURCE, deduplicated.
--
-- `bgPalettes` is a LIST OF PALETTES the rBGP byte reaches: DmgToCgbBGPals
-- pushes one byte through all eight BG palettes at once, so they all take the
-- same permutation.  `objPalettes` is the list it does NOT reach -- OBJ colours
-- go through the separate DmgToCgbObjPals, which the flash never calls -- and
-- they are here mapping to THEMSELVES, so a sprite's colours are recognised and
-- left alone instead of being matched onto a BG entry and swept along.
--
-- Returns src, dst (0..1 triples, both padded to REMAP_MAX) and two counts:
-- `count`, the live length, and `ambiguous`.
--
-- `ambiguous` is the exact limit of this whole pass, and it is worth naming: a
-- colour that is entry 1 of one palette and entry 2 of another has two right
-- answers, and a composited frame threw away which one this pixel was.  The
-- first writer wins, which is why BG palettes are walked first and in slot
-- order -- the reading that matches "the whole picture flashes".  Nothing here
-- is approximate when `ambiguous` is 0.
--
-- BG and OBJ together are 64 entries before dedupe, which is REMAP_MAX.  BG
-- is walked first anyway: losing the sprite guard costs a few sprite pixels,
-- losing a BG palette would cost the effect.
function GbcPalette.remapTable(bgPalettes, byte, objPalettes, ramp, objRamped)
  local src, dst = {}, {}
  local seen = {}
  local ambiguous = 0

  local function add(colors, mapped)
    if not (colors and mapped) then return end
    for index = 1, 4 do
      local from, to = colors[index], mapped[index]
      if from and to and #src < GbcPalette.REMAP_MAX then
        local key = colorKey(from)
        local at = seen[key]
        if at then
          -- Same colour, different destination: the pixel cannot say which
          -- palette drew it, so the first answer stands and this is counted.
          if colorKey(dst[at]) ~= colorKey(to) then ambiguous = ambiguous + 1 end
        else
          src[#src + 1] = { from[1], from[2], from[3] }
          dst[#dst + 1] = { to[1], to[2], to[3] }
          seen[key] = #src
        end
      end
    end
  end

  -- ../pokecrystal/engine/battle/battle_transition.asm:592-607
  local forced = ramp and GbcPalette.resolve(ramp)
  local forcedBg = forced and GbcPalette.remap(forced, byte)

  for _, colors in ipairs(bgPalettes or {}) do
    local resolved = GbcPalette.resolve(colors)
    add(resolved, forcedBg or GbcPalette.remap(resolved, byte))
  end
  -- ../pokecrystal/engine/battle/battle_transition.asm:100-122
  if forced then add(forced, forcedBg) end
  for index, colors in ipairs(objPalettes or {}) do
    local resolved = GbcPalette.resolve(colors)
    if forced and objRamped and objRamped[index] then
      add(resolved, forced)
    else
      add(resolved, resolved)
    end
  end

  local count = #src
  -- Shader:send fills the whole declared array, so the tail is padded with a
  -- copy of the first entry; `count` keeps the loop off it either way.
  for index = count + 1, GbcPalette.REMAP_MAX do
    src[index] = src[1] and { src[1][1], src[1][2], src[1][3] } or { 0, 0, 0 }
    dst[index] = dst[1] and { dst[1][1], dst[1][2], dst[1][3] } or { 0, 0, 0 }
  end
  return src, dst, count, ambiguous
end

-- Bind the remap shader for a draw of an already-rendered texture.  Returns
-- false when there is no shader or no palette, so a caller can fall back to
-- whatever approximation it had before; on success it also returns the
-- `ambiguous` count, which is 0 when the pass is exact.
function GbcPalette.useRemap(bgPalettes, byte, objPalettes, ramp, objRamped)
  if not GbcPalette.remapShader() then return false end
  return GbcPalette.useRemapUniforms(
    GbcPalette.remapUniforms(bgPalettes, byte, objPalettes, ramp, objRamped))
end

function GbcPalette.remapUniforms(bgPalettes, byte, objPalettes, ramp, objRamped)
  local src, dst, count, ambiguous =
    GbcPalette.remapTable(bgPalettes, byte, objPalettes, ramp, objRamped)
  if count == 0 then return nil end
  local sendSrc, sendDst = {}, {}
  for index = 1, GbcPalette.REMAP_MAX do
    sendSrc[index] = { src[index][1] / 255, src[index][2] / 255,
      src[index][3] / 255 }
    sendDst[index] = { dst[index][1] / 255, dst[index][2] / 255,
      dst[index][3] / 255 }
  end
  return { src = sendSrc, dst = sendDst, count = count, ambiguous = ambiguous }
end

function GbcPalette.useRemapUniforms(uniforms)
  local sh = GbcPalette.remapShader()
  if not (sh and uniforms) then return false end
  -- pcall rather than an assert: a driver that will not take a 64-entry vec3
  -- array should drop the effect, not take the battle down with it.
  local ok = pcall(function()
    sh:send("remapCount", uniforms.count)
    sh:send("remapTol", GbcPalette.REMAP_TOLERANCE)
    sh:send("remapSrc", unpack(uniforms.src))
    sh:send("remapDst", unpack(uniforms.dst))
  end)
  if not ok then
    remapFailed = true
    remapShader = nil
    return false
  end
  love.graphics.setShader(sh)
  return true, uniforms.ambiguous
end

-- Run `body` with `colors` active, restoring whatever shader was set before.
-- Nested use is safe: the previous shader is captured, not assumed to be nil.
function GbcPalette.with(colors, body)
  local previous = love and love.graphics and love.graphics.getShader
    and love.graphics.getShader() or nil
  local applied = GbcPalette.use(colors)
  local ok, err = pcall(body)
  if love and love.graphics then love.graphics.setShader(previous) end
  if not ok then error(err, 0) end
  return applied
end

function GbcPalette.keyedWith(colors, body)
  local previous = love and love.graphics and love.graphics.getShader
    and love.graphics.getShader() or nil
  local applied = GbcPalette.useKeyed(colors)
  local ok, err = pcall(body)
  if love and love.graphics then love.graphics.setShader(previous) end
  if not ok then error(err, 0) end
  return applied
end

function GbcPalette.withRaw(colors, body)
  local previous = love and love.graphics and love.graphics.getShader
    and love.graphics.getShader() or nil
  local applied = GbcPalette.useRaw(colors)
  local ok, err = pcall(body)
  if love and love.graphics then love.graphics.setShader(previous) end
  if not ok then error(err, 0) end
  return applied
end

return GbcPalette
