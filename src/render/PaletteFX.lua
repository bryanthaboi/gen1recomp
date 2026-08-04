-- SGB-style colorization post-pass.  The Super Game Boy colored the DMG
-- picture by assigning 4-color palettes to rectangular screen regions
-- (ATTR_BLK packets, data/sgb/sgb_packets.asm).  States expose
-- sgbPalettes() returning a list of zones; the finished 160x144 frame is
-- then drawn once per zone through a shader that remaps the four DMG
-- shades to that zone's palette.
--
-- Port display option: COLORS (OG RED / OG BLUE / OG YELLOW / SGB /
-- ADVANCED / OG / OG INV / SGB INV / CLASSIC) transforms every zone's
-- palette at send time via effectiveColors.  ADVANCED (the `redpp` id
-- below) swaps the named-palette pack for pokered-gbc SuperPalettes
-- (data/palettes_gbc.lua), including per-species mon colors.  OG YELLOW
-- (Yellow playthrough + `ogred` id) uses pokeyellow CGBBasePalettes
-- (data/palettes_yellow.lua / ROM cgbBase).

local GameVersion = require("src.core.GameVersion")

local PaletteFX = {}

local shader -- false = unavailable (headless / no shader support)
local gbcPack -- false = missing; nil = not loaded yet
local yellowPack -- false = missing; nil = not loaded yet

-- Cycle order matches OptionsMenu / hotkey 2.  The three real colorizations
-- come first (OG RED/BLUE/YELLOW = GBC hardware, SGB = per-map Super Game Boy,
-- ADVANCED = pokered-gbc per-tile), then the DMG-shade novelty modes.
PaletteFX.MODES = { "ogred", "gbc", "redpp", "og", "og_inv", "gbc_inv", "classic" }
-- `gbc`/`gbc_inv`/`redpp` keep their save-value ids for back-compat while
-- their LABELS say what the mode actually is: "SGB"/"SGB INV" because the old
-- "GBC" label was a misnomer (it never was the real Game Boy Color palette),
-- and "ADVANCED" because `redpp` is the richest colorization of the three
-- rather than anything Red-specific -- it reads as a misnomer outright on a
-- Blue playthrough.  Comments elsewhere still call it RED++, the name it has
-- carried in this file since it landed.
PaletteFX.MODE_LABELS = {
  ogred = "OG RED", gbc = "SGB", redpp = "ADVANCED", og = "OG",
  og_inv = "OG INV", gbc_inv = "SGB INV", classic = "CLASSIC",
}
PaletteFX.mode = "gbc"

-- ------- dark-cave state (wMapPalOffset)
--
-- Unlike the per-frame shadeMap further down, this outlives a frame: ADVANCED
-- resolves real colour per tile and BAKES it (tileset atlas, sprite sheets),
-- so FadePal2's shift has to reach those bakes and their cache keys rather
-- than a shader (#383).  OverworldState owns it: armed before the map's atlas
-- is built, cleared by FLASH.
local darkWorld = false

-- returns true when the flag actually changed, so the caller can rebuild
function PaletteFX.setDarkWorld(on)
  on = on and true or false
  if darkWorld == on then return false end
  darkWorld = on
  return true
end

function PaletteFX.darkWorld() return darkWorld end

-- cache-key suffix for anything baked under the dark shift
function PaletteFX.darkKey() return darkWorld and "#dark" or "" end

-- FadePal2 sets rOBP0 = `dc 3,3,3,2` as well as rBGP, so EVERY OBJ colour a
-- sprite can carry lands on shade 3: the player, trainers and item balls are
-- black silhouettes until FLASH (#383).  Applied to whatever 4-colour OBP the
-- active mode resolved, with a distinct cache group so the lit and dark bakes
-- of one sheet never collide in SpriteRenderer's obpCache.
function PaletteFX.darkObp(colors, group)
  if not (colors and darkWorld) then return colors, group end
  return PaletteFX.permute(colors, PaletteFX.DARK_BGP), tostring(group) .. "dark"
end

-- the same shift folded into a baked 8-group world palette array (ADVANCED)
local function darkGroups(groups)
  if not (groups and darkWorld) then return groups end
  local out = {}
  for i = 1, #groups do
    out[i] = PaletteFX.permute(groups[i], PaletteFX.DARK_BGP)
  end
  return out
end

-- Classic DMG pea-soup greens (#9BBC0F / #8BAC0F / #306230 / #0F380F)
PaletteFX.CLASSIC = {
  { 155, 188, 15 }, { 139, 172, 15 }, { 48, 98, 48 }, { 15, 56, 15 },
}

-- OG RED: the Game Boy Color boot-ROM auto-palette for Pokemon Red.  Pokemon
-- Red ships no CGB code (pokered's wOnCGB is hardwired 0), so on a Game Boy
-- Color the boot ROM colorizes it with ONE global palette pair -- a red
-- background and green objects -- applied to the whole game with no per-map
-- variation (that variety was the Super Game Boy's doing, i.e. SGB mode).
-- Lightest shade first, matching the SGB palette tables.  Values verified
-- against hardware captures of Pallet Town and Oak's Lab.
PaletteFX.GBC_BG = {
  { 255, 255, 255 }, { 255, 132, 132 }, { 148, 58, 58 }, { 0, 0, 0 },
}
PaletteFX.GBC_OBJ = {
  { 255, 255, 255 }, { 123, 255, 49 }, { 0, 132, 0 }, { 0, 0, 0 },
}

-- OG BLUE: Pokemon Blue's Game Boy Color boot-ROM auto-palette.  Same
-- one-global-pair scheme as OG RED (Blue also ships no CGB code), but the boot
-- ROM gives Blue its OWN entry rather than a recolored Red: a light-blue/blue
-- BACKGROUND and -- unlike Red -- a PINK object palette (OBP0).  Values from
-- Bulbapedia's "List of color palettes ... Generation I" GBC boot-ROM table
-- (BG 0x63A5FF/0x0000FF, OBJ 0xFF8484/0x943A3A), confirmed against a Gambatte
-- hardware capture.  The earlier code mirrored GBC_BG channel-for-channel
-- (0x8484FF/0x3A3A94) and reused Red's green sprites for both versions on the
-- premise that Red and Blue "share the green-character look"; both premises
-- are wrong -- Blue's background is a genuinely different blue and its
-- characters are pink (#155).  Lightest shade first, like GBC_BG.
PaletteFX.GBC_BG_BLUE = {
  { 255, 255, 255 }, { 99, 165, 255 }, { 0, 0, 255 }, { 0, 0, 0 },
}
-- Blue's OBJ palette (OBP0) is the red/pink ramp -- the very same colors OG
-- RED uses for its BACKGROUND (GBC_BG), just applied to objects instead.
PaletteFX.GBC_OBJ_BLUE = {
  { 255, 255, 255 }, { 255, 132, 132 }, { 148, 58, 58 }, { 0, 0, 0 },
}

-- The active game's OG boot-ROM background palette: blue for a Blue
-- playthrough, red for Red.  White (index 1) and black (index 4) are
-- identical across Red/Blue, so callers that only touch the endpoints
-- (e.g. BattleState's zone white/black snap) need no version branch there.
-- Yellow is CGB-enhanced (pokeyellow CGBBasePalettes): named zones go through
-- pal() / usesYellowCgb(), and ogBg() falls back to CGBBase PAL_ROUTE for any
-- remaining whole-screen callers -- never Blue's GBC_BG_BLUE.
function PaletteFX.ogBg()
  if GameVersion.isBlue() then return PaletteFX.GBC_BG_BLUE end
  if GameVersion.isYellow() then
    local y = PaletteFX.yellowPack()
    local route = y and y.cgbBase and y.cgbBase.ROUTE
    if route then return route end
  end
  return PaletteFX.GBC_BG
end

-- The active game's OG boot-ROM object palette (OBP0): Blue's pink ramp for a
-- Blue playthrough, Red's green otherwise.  Returns the colors AND a
-- version-distinct cache-group string, because SpriteRenderer.getObpImage keys
-- its baked-image cache by (image path, group): a shared group would collide a
-- Red bake with a Blue one and one version would show the other's colors.
-- Yellow OG does not bake a boot-ROM OBJ (usesSpriteObp is false); this path
-- is unused there and kept as Red green only as a safe leftover.
function PaletteFX.ogObj()
  if GameVersion.isBlue() then
    return PaletteFX.darkObp(PaletteFX.GBC_OBJ_BLUE, "gbcobj_blue")
  end
  return PaletteFX.darkObp(PaletteFX.GBC_OBJ, "gbcobj")
end

-- The DMG object ramp every mode except OG RED bakes onto overworld sprites,
-- plus its cache group (same two-value contract as ogObj).  Entry 1 is never
-- read -- SpriteRenderer.getObpImage keys OBJ color 0 to alpha, the hardware's
-- unconditional OBJ transparency -- and entries 2..4 are OBJ colors 1..3 sent
-- through rOBP0 = $D0 (home/fade.asm FadePal4 `dc 3,1,0,0`, the entry
-- LoadGBPal reads while wMapPalOffset is 0): color 1 -> DMG shade 0, color 2
-- -> shade 1, color 3 -> shade 3.  Leaving the result in DMG shades is the
-- whole point: the zone shader then colors a character out of the same map
-- palette it colors the ground with, which is all the Super Game Boy can do to
-- an OBJ (#301), and the OBP0 lift is what puts Red's cap on the ROUTE
-- palette's grass green instead of its light-blue (#150).
PaletteFX.OBP0_SHADES = {
  { 255, 255, 255 }, { 255, 255, 255 }, { 170, 170, 170 }, { 0, 0, 0 },
}

function PaletteFX.dmgObj()
  return PaletteFX.darkObp(PaletteFX.OBP0_SHADES, "obp0")
end

local INV_MAP = { [0] = 3, [1] = 2, [2] = 1, [3] = 0 }

function PaletteFX.shader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern vec3 c0; extern vec3 c1; extern vec3 c2; extern vec3 c3;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 p = Texel(tex, tc);
        vec3 mapped = p.r > 0.83 ? c0 : (p.r > 0.5 ? c1 : (p.r > 0.17 ? c2 : c3));
        return vec4(mapped, p.a);
      }
    ]])
    shader = ok and sh or false
  end
  return shader or nil
end

-- Shade-remap variant that also keys shade 0 (DMG white / lightest gray)
-- to transparent -- the GB OBJ-to-BG priority trick.  Tilt mode's upright
-- pass uses it for tall-grass feet overdraw: the patch must be colorized
-- to match the ground grass it hides, yet let the sprite show through the
-- grass tile's white gaps.  The flat path gets this from TileRenderer's
-- color-0 key plus the whole-canvas zone colorization at blit time; the
-- upright canvas is composited with no zone pass, so the two are fused
-- into one shader here.  Same c0..c3 uniforms as shader(), so sendColors
-- feeds it identically.
local keyedShader -- false = unavailable (headless / no shader support)

function PaletteFX.keyedShader()
  if keyedShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern vec3 c0; extern vec3 c1; extern vec3 c2; extern vec3 c3;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 p = Texel(tex, tc);
        vec3 mapped = p.r > 0.83 ? c0 : (p.r > 0.5 ? c1 : (p.r > 0.17 ? c2 : c3));
        float a = (p.r > 0.83 && p.g > 0.83 && p.b > 0.83) ? 0.0 : p.a;
        return vec4(mapped, a);
      }
    ]])
    keyedShader = ok and sh or false
  end
  return keyedShader or nil
end

-- ATTR_BLK inclusive tile rect -> pixel-space zone.  colors == false is
-- the trueColor opt-out: a real zone whose rect blits with no shader, so
-- full-color art survives the pass.  nil still means "no zone at all".
function PaletteFX.zone(colors, tx1, ty1, tx2, ty2)
  if colors == nil then return nil end
  return { colors = colors, x = tx1 * 8, y = ty1 * 8,
           w = (tx2 - tx1 + 1) * 8, h = (ty2 - ty1 + 1) * 8 }
end

-- the trueColor zone a sprite/tileset record asks for by name
function PaletteFX.trueColorZone(tx1, ty1, tx2, ty2)
  return PaletteFX.zone(false, tx1, ty1, tx2, ty2)
end

-- ------- trueColor zone collection

-- A sprites/tilesets record carrying trueColor = true must not reach the
-- shade-remap shader (14 §trueColor propagation), but the states that
-- build the zone list know nothing about which records the frame drew.
-- So the renderer that draws one reports its covering rect here, in the
-- coordinates of the canvas it is filling, and Renderer:endFrame appends
-- the frame's rects to that pass's zone list as colors == false zones --
-- the region is then re-blit unshaded on top of the colorized pass.
-- No vanilla record sets the flag, so both buckets stay empty every frame
-- and the zone lists are exactly the ones the states returned.
local trueColorRects = { ui = {}, world = {} }
local currentPass = nil
-- Horizontal shift applied to UI-pass marks.  A wide battle keeps its 304px
-- surface through every classic state it opens, and Game:draw centres each
-- of those with a translate while centerClassicZones shifts their zone list
-- by the same amount.  A rect reported from inside that translate has to
-- move with it, or the unshaded re-blit lands 72 columns off and the pic
-- keeps the shade remap -- the party STATS screen in a wide battle (#637).
-- World-pass marks are already in world-canvas space and are never centred.
local markOffsetX = 0

-- which canvas the renderer is filling.  nil for a pass that composites
-- with no zone list of its own (tilt's upright billboards carry their own
-- per-sprite colorization), which drops its rects on the floor.
function PaletteFX.setPass(name)
  currentPass = trueColorRects[name] and name or nil
end

function PaletteFX.clearTrueColor()
  for _, rects in pairs(trueColorRects) do
    for i = #rects, 1, -1 do rects[i] = nil end
  end
  markOffsetX = 0
end

-- Game:draw declares the translate it is drawing a classic state under, so
-- that state's marks land where its pixels did.  Cleared with the rects at
-- the top of every frame (Renderer:beginFrame). #637
function PaletteFX.setMarkOffset(dx)
  markOffsetX = tonumber(dx) or 0
end

function PaletteFX.markTrueColor(x, y, w, h)
  local rects = currentPass and trueColorRects[currentPass]
  if not rects or w <= 0 or h <= 0 then return end
  if currentPass == "ui" then x = x + markOffsetX end
  rects[#rects + 1] = { colors = false, x = x, y = y, w = w, h = h }
end

function PaletteFX.trueColorRects(name)
  return trueColorRects[name] or {}
end

function PaletteFX.whole(colors)
  return PaletteFX.zone(colors, 0, 0, 19, 17)
end

-- Red++ / pokered-gbc SuperPalette pack (committed; optional if absent).
function PaletteFX.gbcPack()
  if gbcPack == nil then
    local ok, pack = pcall(require, "data.palettes_gbc")
    gbcPack = ok and pack or false
  end
  return gbcPack or nil
end

-- pokeyellow SuperPalettes + CGBBasePalettes (committed; not wiped by import).
-- ROM import may also stamp palettes.cgbBase; yellowCgbNamedPal prefers that.
function PaletteFX.yellowPack()
  if yellowPack == nil then
    local ok, pack = pcall(require, "data.palettes_yellow")
    yellowPack = ok and pack or false
  end
  return yellowPack or nil
end

function PaletteFX.usesGbcPack(mode)
  mode = mode or PaletteFX.mode
  return mode == "redpp"
end

-- Yellow's authentic GBC look is CGBBasePalettes (per-map), not a boot-ROM
-- auto-palette.  The shared `ogred` save id wears that table on a Yellow
-- playthrough and labels itself "OG YELLOW".
function PaletteFX.usesYellowCgb(mode)
  mode = mode or PaletteFX.mode
  return GameVersion.isYellow() and mode == "ogred"
end

-- Whether the active mode bakes a per-OBJ palette onto overworld sprites
-- (the OBP bake + post-zone redraw path).  OG RED / OG BLUE do: the Game Boy
-- Color boot ROM hands the game one global object palette (PaletteFX.ogObj --
-- green over Red's red background, pink over Blue's blue background), so on
-- that machine the player and NPCs carry a fixed object color instead of
-- tinting with whatever region palette their feet stand over.  An EARLIER
-- attempt at per-sprite color baked GBC_BG (the RED background ramp) onto
-- characters -- that was the "reds coloring on the player/NPCs" bug; the object
-- palette is GBC_OBJ (green), so baking that here is the fix, not that
-- regression.  Terrain is unaffected -- pal() below still hands SGB its per-map
-- BG palette; only OG RED short-circuits BG to the one global red palette.
--
-- OG YELLOW does NOT.  Yellow ships CGB code and colors regions via
-- CGBBasePalettes the same way SGB mode colors SuperPalettes, so sprites tint
-- with the map zone (usesSpriteObp stays off).
--
-- SGB does NOT.  The Super Game Boy colorizes the composited DMG picture it is
-- handed and cannot tell an OBJ pixel from a BG one; pokered never sends the
-- OBJ_TRN packet that would enable SGB sprite mode (data/sgb/sgb_packets.asm
-- defines ATTR_BLK / PAL_SET / PAL_TRN / MLT_REQ / CHR_TRN / PCT_TRN and
-- nothing else), so a character there wears the very palette its map does.
-- Baking GBC_OBJ over it was issue #301 ("people in SGB mode are green": the
-- boot-ROM greens sat on top of ROUTE's own greens and blues).  What issue
-- #150 actually caught was the missing rOBP0 step, not a missing object
-- palette: overworld OBJs run through OBP0 = $D0 (home/fade.asm FadePal4
-- `dc 3,1,0,0`), which lifts OBJ color 1 to DMG shade 0 and color 2 to shade 1,
-- so Red's cap lands on the ROUTE palette's shade-1 GRASS GREEN and blends into
-- the grass exactly as #150's reference shot shows.  Drawn with an identity
-- shade map it landed on shade 2 = light-blue instead, which is the clash #150
-- reported.  SpriteRenderer bakes that OBP0 ramp (PaletteFX.dmgObj) and lets
-- the zone shader color the result.  RED++ colors sprites through the
-- usesGbcPack() path in SpriteRenderer instead.
function PaletteFX.usesSpriteObp(mode)
  mode = mode or PaletteFX.mode
  return mode == "ogred" and not GameVersion.isYellow()
end

-- ------- post-zone sprite redraw (OG RED)
--
-- In OG RED the world canvas still runs through the whole-screen zone
-- shade-remap shader, which would corrupt an OBP-baked sprite's true-color
-- pixels.  (SGB used to come through here too; it no longer bakes an object
-- palette at all, so its characters are colorized by the zone like the ground
-- they stand on and never queue a replay -- see usesSpriteObp, #301.)  So SpriteRenderer draws the baked sprite into the canvas (its
-- pixels come out zone-tinted there) AND records the draw here;
-- Renderer:endFrame replays the list on top of the finished zone pass,
-- scaled into screen space -- the GBC's OBJ-over-BG compositing, one draw
-- late.  Entries carrying `colors` are re-colorized draws (the tall-grass
-- feet overdraw, which must keep hiding sprite feet) issued through the
-- color-0-keyed shade-remap shader.  World pass only; cleared per frame.
local spriteRedraws = {}

function PaletteFX.clearSpriteRedraws()
  for i = #spriteRedraws, 1, -1 do spriteRedraws[i] = nil end
end

function PaletteFX.markSpriteRedraw(image, quad, x, y, sx, colors, keyed)
  if currentPass ~= "world" then return end
  spriteRedraws[#spriteRedraws + 1] =
    { image = image, quad = quad, x = x, y = y, sx = sx or 1,
      colors = colors, keyed = keyed }
end

-- whether a draw issued right now would land in the redraw list -- the
-- OBP bake is only correct when the replay can restore it after the zone
-- pass (tilt's upright pass colorizes per-billboard instead, so sprites
-- there keep the raw sheet)
function PaletteFX.spriteRedrawPassActive()
  return currentPass == "world"
end

function PaletteFX.spriteRedraws()
  return spriteRedraws
end

-- Active named-palette table for COLORS: RED++ uses data/palettes_gbc.lua,
-- everything else uses the ROM-imported data.palettes.
function PaletteFX.pack(data)
  if PaletteFX.usesGbcPack() then
    local g = PaletteFX.gbcPack()
    if g then return g end
  end
  return data and data.palettes or nil
end

-- SuperPalettes that differ between Red and Blue (pokered data/sgb/
-- sgb_palettes.asm IF DEF(_RED)/_BLUE).  data/palettes_gbc.lua is the
-- Red-derived pokered-gbc pack, so under RED++ a Blue playthrough must
-- read these from the ROM-imported table or the title ribbon stays red
-- and the Game Corner reels keep Red's pink (issue #128).
-- Yellow is intentionally NOT in BLUE_VERSIONED: skip Blue LOGO1/SLOTS*
-- recolors.  OG YELLOW (usesYellowCgb) reads CGBBasePalettes; SGB mode on
-- Yellow keeps SuperPalettes.
local BLUE_VERSIONED = {
  LOGO1 = true, SLOTS2 = true, SLOTS3 = true, SLOTS4 = true,
}

local function romNamedPal(data, name)
  local p = data and data.palettes
  return p and p.palettes and p.palettes[name]
end

local function yellowCgbNamedPal(data, name)
  local p = data and data.palettes
  local fromRom = p and p.cgbBase and p.cgbBase[name]
  if fromRom then return fromRom end
  local y = PaletteFX.yellowPack()
  return y and y.cgbBase and y.cgbBase[name] or nil
end

-- named palette from the active pack (nil on stale builds / missing name).
-- RED++ falls back to the ROM pack for names the gbc table omits (rare).
-- OG RED / OG BLUE short-circuit EVERY name to the one global GBC boot-ROM
-- BG palette (the hardware had a single BGP for the whole game), so terrain
-- zones, battle HP bars / text, and menu boxes all come out red/blue --
-- everything a background tile drew.  Objects do not come through here
-- (they bake GBC_OBJ), so this stays a BG-only hook.
-- OG YELLOW instead resolves each name through CGBBasePalettes.
function PaletteFX.pal(data, name)
  if PaletteFX.mode == "ogred" and not GameVersion.isYellow() then
    return PaletteFX.ogBg()
  end
  -- Blue-only ROM override for versioned SuperPals.  Yellow (isYellow) and
  -- Red keep the active pack / Red-like path -- do not apply Blue recolors.
  if GameVersion.isBlue() and BLUE_VERSIONED[name] then
    local fromRom = romNamedPal(data, name)
    if fromRom then return fromRom end
  end
  if PaletteFX.usesYellowCgb() then
    local fromCgb = yellowCgbNamedPal(data, name)
    if fromCgb then return fromCgb end
  end
  local p = PaletteFX.pack(data)
  local c = p and p.palettes[name]
  if c then return c end
  if GameVersion.isYellow() then
    local y = PaletteFX.yellowPack()
    local yc = y and y.palettes and y.palettes[name]
    if yc then return yc end
  end
  if PaletteFX.usesGbcPack() then
    return romNamedPal(data, name)
  end
  return nil
end

-- the species' palette (data/pokemon/palettes.asm), MEWMON for unknowns.
-- transformed forces PAL_GRAYMON (Ditto's palette) regardless of species
-- (engine/gfx/palettes.asm DeterminePaletteID: bit TRANSFORMED, a; a
-- Transformed mon's pic is tinted gray, not the copied species' own
-- SGB color).  RED++ uses per-species pals from mon_palettes.asm.
function PaletteFX.monPal(data, species, transformed)
  -- OG RED / OG BLUE: a battle mon pic is a BG tile on the Game Boy Color
  -- (drawn into the tilemap, colored by BGP), so it wears the global boot-ROM
  -- BG palette, not a per-species one -- matching the hardware capture where
  -- both mons are red/pink (or blue/pink) on the white field.
  -- OG YELLOW keeps per-species CGBBasePalettes (Yellow had real CGB code).
  if PaletteFX.mode == "ogred" and not GameVersion.isYellow() then
    return PaletteFX.ogBg()
  end
  local p = PaletteFX.pack(data)
  if not p then return nil end
  if transformed then
    if PaletteFX.usesYellowCgb() then
      return PaletteFX.pal(data, "GRAYMON")
    end
    return p.palettes.GRAYMON
        or (data and data.palettes and data.palettes.palettes.GRAYMON)
  end
  -- a species' own `palette` field (per-record override) wins over the
  -- vanilla species->name map. Mod-registered palettes live in
  -- data.palettes.palettes even when the active pack is the RED++ gbc pack,
  -- so fall back to it when the pack itself doesn't carry the name.
  local def = data and data.pokemon and data.pokemon[species]
  if def and def.palette then
    if PaletteFX.usesYellowCgb() then
      local yc = PaletteFX.pal(data, def.palette)
      if yc then return yc end
    end
    local pal = p.palettes[def.palette]
             or (data and data.palettes and data.palettes.palettes[def.palette])
    if pal then return pal end
  end
  local name = p.pokemon[species] or "MEWMON"
  if PaletteFX.usesYellowCgb() then
    local yc = PaletteFX.pal(data, name)
    if yc then return yc end
  end
  local c = p.palettes[name]
  if c then return c end
  if PaletteFX.usesGbcPack() and data and data.palettes then
    name = data.palettes.pokemon[species] or "MEWMON"
    return data.palettes.palettes[name]
  end
  if GameVersion.isYellow() then
    local y = PaletteFX.yellowPack()
    if y and y.pokemon then
      name = y.pokemon[species] or "MEWMON"
      return y.palettes and y.palettes[name]
    end
  end
  return nil
end

-- palette name a species currently resolves to (for image-cache keys)
function PaletteFX.monPalName(data, species, transformed)
  if transformed then return "GRAYMON" end
  -- honor the per-record palette override, matching monPal
  local def = data and data.pokemon and data.pokemon[species]
  if def and def.palette and data.palettes
     and data.palettes.palettes[def.palette] then
    return def.palette
  end
  local p = PaletteFX.pack(data)
  if p and p.pokemon[species] then return p.pokemon[species] end
  if data and data.palettes and data.palettes.pokemon[species] then
    return data.palettes.pokemon[species]
  end
  return "MEWMON"
end

-- ------- true GBC overworld coloring (color/loadpalettes.asm,
-- color/data/*, color/sprites.asm ColorOverworldSprite) -------------------
--
-- RED++ pairs its named-palette battle/mon colors above with pokered-gbc's
-- real per-tile system: LoadTilesetPalette assigns one of 8 four-color BG
-- palettes to every tile GRAPHIC in a tileset (by tile id, not by map
-- position), and LoadTownPalette swaps just the ROOF slot (index 6) per
-- town/route. `data/palettes_gbc.lua`'s `world` table holds the extracted
-- data (tools/extract/palettes.py extract_gbc_world); these queries are
-- mode-independent (only check the pack exists) so TileRenderer can
-- precompute geometry once regardless of the active COLORS mode -- callers
-- that resolve to actual on-screen COLOR should gate on usesGbcPack()
-- themselves, the same way they already gate other RED++-only behavior.
--
-- LoadTilesetPalette's 3 hardcoded single-tile fixes (Celadon Mart) and
-- LoadTownPalette's Route 6/Saffron y<2 roof split are control flow, not
-- data, so they are not in the extracted pack -- they live here instead.
local TILE_GROUP_EXCEPTIONS = {
  -- tile ids $4b-$4f -> BLUE (outside sky, seen through the mart's roof)
  CELADON_MART_ROOF = { tiles = { [0x4b] = true, [0x4c] = true, [0x4d] = true,
                                  [0x4e] = true, [0x4f] = true }, group = 3 },
  -- tile $37 -> BROWN (counter miscoloration fix)
  CELADON_MART_3F   = { tiles = { [0x37] = true }, group = 5 },
  -- tiles $07/$08/$17/$18 -> YELLOW (bench, blue by default)
  CELADON_MART_1F   = { tiles = { [0x07] = true, [0x08] = true,
                                  [0x17] = true, [0x18] = true }, group = 4 },
}

-- keyed by tileset id (applies on every map that uses it), consulted after
-- the per-map table above
local TILESET_GROUP_EXCEPTIONS = {
  -- tile $22 (the hollow-square grave marker) -> GRAY: the extracted pack
  -- files it under the bright blue family, which makes a purely
  -- decorative floor marker read as an interactive pad
  CEMETERY = { tiles = { [0x22] = true }, group = 0 },
}

-- pokered-gbc's lobby.bst repoints the Celadon LOBBY table's flat top
-- at a duplicate tile ($5a, BROWN) so the tabletop and the checkerboard
-- floor -- both raw tile $37 -- can take different palettes; the
-- vanilla-derived blockset shares the one tile id, so the RED++ atlas
-- path re-creates the duplicate: the alias slot is baked as a copy of
-- `tile` in `group`'s colors, and the listed 0-based block cells draw
-- the alias instead of the shared tile.
--
-- Three LOBBY blocks share tile $37 on their flat surfaces:
--   block 29: 2x2 table top at cells 5/6/9/10
--   block 45: 2-tile strip at cells 13/14
--   block 49: 2-tile strip at cells 1/2
-- CELADON_DINER uses all three (#84, #85, #86); CELADON_MART_ROOF
-- uses only block 29 (#52/#53).
local LOBBY_TABLE_TOP_ALIAS = {
  { block = 29, cells = { [5] = true, [6] = true, [9] = true, [10] = true },
    tile = 0x37, alias = 0x5a, group = 5 },
  { block = 45, cells = { [13] = true, [14] = true },
    tile = 0x37, alias = 0x5a, group = 5 },
  { block = 49, cells = { [1] = true, [2] = true },
    tile = 0x37, alias = 0x5a, group = 5 },
}
PaletteFX.TILE_ALIASES = {
  CELADON_MART_ROOF = LOBBY_TABLE_TOP_ALIAS,
  CELADON_DINER = LOBBY_TABLE_TOP_ALIAS,
}
local ROOF_GROUP = 6
local ROUTE_6_SAFFRON = { mapId = "ROUTE_6", useMapId = "SAFFRON_CITY", cellYBelow = 2 }

-- whether the extracted pack has real per-tile GBC data for this tileset
-- (false for a mod tileset with no pokered-gbc counterpart, or when the
-- pack failed to load at all)
function PaletteFX.hasWorldTileset(tileset)
  local pack = PaletteFX.gbcPack()
  local w = pack and pack.world
  return (w and w.tileGroups[tileset]) ~= nil
end

-- the palette-group (0-7) a tile GRAPHIC id resolves to in this tileset,
-- with the current map's tile-id exceptions (if any) applied first
function PaletteFX.worldGroupAt(tileset, mapId, tileId)
  local pack = PaletteFX.gbcPack()
  local w = pack and pack.world
  local groups = w and w.tileGroups[tileset]
  if not groups then return nil end
  local exc = TILE_GROUP_EXCEPTIONS[mapId]
  if exc and exc.tiles[tileId] then return exc.group end
  exc = TILESET_GROUP_EXCEPTIONS[tileset]
  if exc and exc.tiles[tileId] then return exc.group end
  return groups[tileId] or 7 -- TEXT: tile ids past the tileset's 96 (menus)
end

-- this tileset's resolved 8-entry {r,g,b}x4 palette array, with the ROOF
-- slot swapped to the current town/route (Route 6's north end uses
-- Saffron's roof colors while the player stands in its top 2 cell rows,
-- like pokered's wYCoord check -- data is Game.data, for the map lookup)
function PaletteFX.worldGroupColors(data, tileset, mapId, playerCellY)
  local pack = PaletteFX.gbcPack()
  local w = pack and pack.world
  local base = w and w.groupColors[tileset]
  if not base then return nil end
  if not w.roofGroup[tileset] then return darkGroups(base) end
  local roofMapId = mapId
  if mapId == ROUTE_6_SAFFRON.mapId and playerCellY
     and playerCellY < ROUTE_6_SAFFRON.cellYBelow then
    roofMapId = ROUTE_6_SAFFRON.useMapId
  end
  local roofMap = data and data.maps and data.maps[roofMapId]
  local roof = roofMap and w.roofByMapIndex[roofMap.index]
  if not roof then return darkGroups(base) end
  local out = {}
  for i = 1, 8 do out[i] = base[i] end
  -- LoadTownPalette only overwrites W2_BgPaletteData + $32, i.e. colors 1
  -- and 2 (0-indexed) of the 4-color ROOF slot -- color 0 (background,
  -- typically the sky-through-gaps white) and color 3 (outline black) keep
  -- the tileset's own OUTDOOR_ROOF/INDOOR_ROOF base, only the roof
  -- material's 2 middle shades are town-specific
  local base4 = base[ROOF_GROUP + 1]
  out[ROOF_GROUP + 1] = { base4[1], roof[1], roof[2], base4[4] }
  return darkGroups(out)
end

-- an overworld sprite's resolved 4-color OBJ palette (ColorOverworldSprite),
-- or nil when unassigned/unavailable, plus the resolved group index (for
-- callers that want a stable cache key without hashing the colors table).
-- spriteDef carries the ROM picture-id crosswalk in its `source` field
-- ("ROM:SpriteSheetPointerTable[N]"); seed (any stable per-instance value,
-- e.g. an NPC's `id`) resolves the "random" sentinel -- a deliberate
-- approximation of ColorOverworldSprite's per-OAM-slot pseudo-random pick
-- (`swap a; and 3` on the sprite's OAM offset, which has no equivalent
-- here): a stable hash instead, so the same NPC instance always shows the
-- same one of the 4 SPR_PAL_* colors.
function PaletteFX.spriteObp(spriteDef, seed)
  local pack = PaletteFX.gbcPack()
  local w = pack and pack.world
  local src = spriteDef and (spriteDef.paletteSource or spriteDef.source)
  if not (w and src) then return nil end
  local idx = tonumber(src:match("%[(%d+)%]"))
  -- RedBikeSprite and SurfingPikachuSprite load outside
  -- SpriteSheetPointerTable, so their source has no bracketed index;
  -- they wear the player's OBP palette (spriteAssignment[0]).
  if not idx and (src:find("RedBikeSprite", 1, true)
                  or src:find("SurfingPikachuSprite", 1, true)) then
    idx = 0
  end
  local group = idx and w.spriteAssignment[idx]
  if group == nil then return nil end
  if group == "random" then
    local h = 0
    seed = tostring(seed or "")
    for i = 1, #seed do h = (h * 31 + seed:byte(i)) % 4294967296 end
    group = h % 4
  end
  return PaletteFX.darkObp(w.spritePalettes[group], group)
end

-- GetHealthBarColor (home/palettes.asm) on the standard 48px bar
function PaletteFX.barPalName(hp, maxHp)
  local px = maxHp > 0 and math.floor(hp * 48 / maxHp) or 0
  if hp > 0 and px < 1 then px = 1 end
  return px >= 27 and "GREENBAR" or px >= 10 and "YELLOWBAR" or "REDBAR"
end

-- convenience: a single whole-screen zone for a named palette
function PaletteFX.wholeNamed(data, name)
  local c = PaletteFX.pal(data, name)
  return c and { PaletteFX.whole(c) } or nil
end

-- The four DMG grays the extracted art uses (255/170/85/0), as a
-- palette-shaped table -- shade index 0 (lightest) first, like the SGB
-- palettes in data/generated/palettes.lua.
PaletteFX.GRAYS = { { 255, 255, 255 }, { 170, 170, 170 },
                    { 85, 85, 85 }, { 0, 0, 0 } }

-- Permute a 4-color palette through a BGP-style shade map
-- (map[i] = the shade color index i displays as, i = 0..3).  Emulates
-- pokered's SetAnimationBGPalette / AnimationFlashScreen* writes to
-- rBGP composed with the SGB colorization: the SGB colors the remapped
-- DMG shade, so a screen region shows palette[map[shade]].
function PaletteFX.permute(colors, map)
  if not map then return colors end
  return { colors[map[0] + 1], colors[map[1] + 1],
           colors[map[2] + 1], colors[map[3] + 1] }
end

-- ------- global shade map (rBGP)
--
-- home/fade.asm's LoadGBPal writes ONE rBGP for the whole screen, indexing
-- FadePal4 - wMapPalOffset.  A dark cave sets wMapPalOffset = 6
-- (home/overworld.asm's ROCK_TUNNEL_1F check; the value rides in the extracted
-- field.darkMaps.palOffset), which lands on FadePal2 = `dc 3,3,3,2`: DMG white
-- drops to shade 2 and every darker shade goes to shade 3.  So the WHOLE
-- screen darkens -- the original never cuts a window of light around the
-- player (#322) -- and FLASH clears wMapPalOffset again
-- (engine/menus/start_sub_menus.asm .flash).
--
-- Renderer:beginFrame clears this every frame and the state that draws a dark
-- map re-arms it while it draws, so it can never outlive the map it belongs
-- to: a battle or a full-screen menu draws with no map beneath it and comes
-- out lit, exactly like init_battle_variables.asm's `ld [wMapPalOffset], a`
-- leaves the original.
PaletteFX.DARK_BGP = { [0] = 2, [1] = 3, [2] = 3, [3] = 3 }

local shadeMap = nil

function PaletteFX.setShadeMap(map)
  shadeMap = map
end

function PaletteFX.shadeMap()
  return shadeMap
end

function PaletteFX.setMode(mode)
  local prev = PaletteFX.mode
  local ok = false
  for _, m in ipairs(PaletteFX.MODES) do
    if m == mode then
      PaletteFX.mode = mode
      ok = true
      break
    end
  end
  if not ok then PaletteFX.mode = "gbc" end
  -- battle pics and overworld sprites bake the active pack into ImageData;
  -- drop those caches when the pack (or any COLORS mode) changes so the
  -- next draw re-tints
  if prev ~= PaletteFX.mode then
    pcall(function() require("src.battle.BattleState").invalidate() end)
    pcall(function() require("src.render.SpriteRenderer").invalidate() end)
    -- RED++'s baked tileset atlas (TileRenderer.getGbcAtlas) is built once
    -- per loaded map, so a mode toggle needs every cached Map/TileRenderer
    -- dropped and the currently-visible one rebuilt in place -- otherwise
    -- the on-screen map keeps its stale (wrong-mode) atlas until the next
    -- map transition happens to reload it.
    pcall(function()
      require("src.world.MapLoader").invalidateAll()
      local Game = require("src.core.Game")
      if Game.overworld and Game.overworld.map and Game.overworld.reloadMap then
        Game.overworld:reloadMap(Game.overworld.map.id, "colors")
      end
    end)
  end
end

function PaletteFX.cycleMode()
  local cur = PaletteFX.mode or "gbc"
  local idx = 1
  for i, m in ipairs(PaletteFX.MODES) do
    if m == cur then idx = i; break end
  end
  PaletteFX.setMode(PaletteFX.MODES[idx % #PaletteFX.MODES + 1])
  return PaletteFX.mode
end

function PaletteFX.applyOptions(opts)
  PaletteFX.setMode(opts and opts.colors or "gbc")
end

function PaletteFX.modeLabel(mode)
  mode = mode or PaletteFX.mode
  -- The GBC hardware mode wears the running game's name: OG RED / OG BLUE
  -- (boot-ROM auto-palette) or OG YELLOW (pokeyellow CGBBasePalettes).
  if mode == "ogred" and GameVersion.isBlue() then return "OG BLUE" end
  if mode == "ogred" and GameVersion.isYellow() then return "OG YELLOW" end
  return PaletteFX.MODE_LABELS[mode] or "GBC"
end

-- When a state exposes no SGB zones but COLORS needs a forced palette
-- (OG / OG INV / CLASSIC), invent a whole-screen zone so the shade-remap
-- shader still runs.  GBC / RED++ / GBC INV leave nil alone (raw DMG canvas).
function PaletteFX.ensureZones(zones)
  if zones and zones[1] then return zones end
  local mode = PaletteFX.mode or "gbc"
  if mode == "og" or mode == "og_inv" or mode == "classic" then
    return { PaletteFX.whole(PaletteFX.GRAYS) }
  end
  return zones
end

-- Transform a 4-color palette for the active COLORS display mode.
-- GBC and RED++ pass the zone colors through (RED++ already swapped the
-- pack in pal/monPal); OG* / CLASSIC replace; GBC INV permutes shades.
-- The "paper" shade of the active display mode: what a DMG-white background
-- pixel ends up as once colorization has run.  Every palette in the SGB pack
-- carries the same off-white (255,239,255) as color 0, so this is well
-- defined for the whole screen rather than per zone.  Goes through
-- PaletteFX.pal so OG RED short-circuits to the one global boot-ROM BG
-- palette and RED++ falls back to the ROM pack, then through effectiveColors
-- so the mono and inverted modes get their own paper (CLASSIC's pea green,
-- and the dark paper the inverted modes should have).  Returns r, g, b in
-- 0..1, white if nothing resolves.
function PaletteFX.paperShade(data)
  local base = PaletteFX.pal(data, "GREENBAR") or PaletteFX.GRAYS
  local colors = PaletteFX.effectiveColors(base) or base
  local c = colors and colors[1]
  if not c then return 1, 1, 1 end
  return c[1] / 255, c[2] / 255, c[3] / 255
end

function PaletteFX.effectiveColors(c)
  if not c then return nil end
  local mode = PaletteFX.mode or "gbc"
  local out = c
  if mode == "og" then
    out = PaletteFX.GRAYS
  elseif mode == "og_inv" then
    out = PaletteFX.permute(PaletteFX.GRAYS, INV_MAP)
  elseif mode == "classic" then
    out = PaletteFX.CLASSIC
  elseif mode == "gbc_inv" then
    out = PaletteFX.permute(c, INV_MAP)
  end
  -- The shade map goes on LAST: rBGP is a hardware register write, so it
  -- composes on top of whatever colors the display mode settled on -- a dark
  -- cave has to read dark in CLASSIC's pea greens and in plain DMG grays too
  -- (#322).  permute() is the identity (and returns `out` itself, which the
  -- mod-graphics parity check leans on) while nothing has armed one.
  return PaletteFX.permute(out, shadeMap)
end

-- send a 4-color (0-255 RGB) palette to the shade-remap shader, after
-- applying the active COLORS display mode
function PaletteFX.sendColors(shader, c)
  c = PaletteFX.effectiveColors(c)
  if not c then return end
  shader:send("c0", { c[1][1] / 255, c[1][2] / 255, c[1][3] / 255 })
  shader:send("c1", { c[2][1] / 255, c[2][2] / 255, c[2][3] / 255 })
  shader:send("c2", { c[3][1] / 255, c[3][2] / 255, c[3][3] / 255 })
  shader:send("c3", { c[4][1] / 255, c[4][2] / 255, c[4][3] / 255 })
end

return PaletteFX
