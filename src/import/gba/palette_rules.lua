-- Category → Gen2 BG slot + 4-shade demake ramp.
-- Map profiles (outdoor / network / house / harbor) select the room ruleset.
-- Network also composes material roles (floor / wall / machine / screen / …)
-- so tweaking the machine does not retint plaza walls.

local PaletteRules = {}

-- Slot plan (8 GBC BG pals):
-- 1 water | 2 grass road | 3 sand | 4 cliff/stairs | 5 building fronts
-- 6 roofs | 7 cool metal (Network Machine / escalator) | 8 trees
-- Slot 5 mid shade is window-blue — never put gray metal there (reads as water stain).
-- Outdoor stairs share cliff (not front).
PaletteRules.SLOT = {
  WATER = 1,
  SHORT_GRASS = 2,
  TALL_GRASS = 2,
  TOWN_PATH = 2,
  TREE = 8,
  SAND = 3,
  CLIFF = 4,
  COAST_CLIFF = 4,
  ROCK_DECK = 4,
  LEDGE = 4,
  CAVE = 4,
  PIER = 4,
  STAIR = 4,
  PATH = 5,
  BLOCKED = 5,
  BUILDING = 6,
  DOOR = 6,
  SIGN = 4, -- wood post / board uses cliff-brown family (not house front)
}

PaletteRules.RAMP = {
  [1] = { -- water
    { 198, 222, 255 }, { 90, 156, 239 }, { 33, 90, 189 }, { 8, 24, 66 },
  },
  [2] = { -- grass / town grass-road
    { 165, 222, 99 }, { 82, 173, 49 }, { 41, 115, 24 }, { 16, 49, 8 },
  },
  [3] = { -- sand
    { 247, 230, 156 }, { 222, 189, 90 }, { 181, 140, 49 }, { 99, 74, 24 },
  },
  [4] = { -- cliff / rock / pier / outdoor stairs
    { 206, 173, 140 }, { 156, 115, 82 }, { 107, 74, 49 }, { 49, 33, 24 },
  },
  [5] = { -- building fronts only: white, window-blue, gray, black
    { 239, 239, 239 }, { 115, 156, 206 }, { 132, 132, 140 }, { 24, 24, 33 },
  },
  [6] = { -- roofs only (PC orange / house magenta) — not shared with fronts
    { 247, 206, 165 }, { 222, 132, 82 }, { 181, 74, 123 }, { 74, 24, 57 },
  },
  [7] = { -- cool metal (Network Machine body / escalator) — screens use slot 1
    { 198, 206, 214 }, { 132, 140, 156 }, { 74, 82, 99 }, { 24, 28, 41 },
  },
  [8] = { -- trees
    { 140, 189, 74 }, { 57, 132, 33 }, { 33, 82, 16 }, { 8, 33, 0 },
  },
  -- Tree tips over cliff: green shades + brown shades in one 8×8 (like roof
  -- magenta+cream). Nearest-colour bake, not Y-threshold.
  [9] = {
    { 165, 206, 90 }, { 74, 148, 41 }, { 156, 115, 82 }, { 49, 33, 24 },
  },
}

PaletteRules.TREE_CLIFF_SLOT = 9

PaletteRules.OWNER_PRIORITY = {
  WATER = 80,
  CLIFF = 70,
  COAST_CLIFF = 70,
  ROCK_DECK = 65,
  LEDGE = 65,
  CAVE = 60,
  SAND = 55,
  BUILDING = 50,
  DOOR = 50,
  TREE = 45,
  TALL_GRASS = 40,
  SHORT_GRASS = 35,
  TOWN_PATH = 35,
  SIGN = 30,
  PIER = 25,
  STAIR = 20,
  PATH = 15,
  BLOCKED = 10,
}

PaletteRules.LOCKED = {
  TREE = true,
  WATER = true,
  BUILDING = true,
  DOOR = true,
  SIGN = true,
  SAND = true,
  -- Map-edge cliffs must not be stolen by house neighbour votes.
  CLIFF = true,
  COAST_CLIFF = true,
  ROCK_DECK = true,
  LEDGE = true,
  -- Pier wood must not be stolen by adjacent water (was painting dock edges blue).
  PIER = true,
}

function PaletteRules.slotFor(category)
  return PaletteRules.SLOT[category or ""] or 5
end

function PaletteRules.rampForSlot(slot)
  return PaletteRules.RAMP[slot] or PaletteRules.RAMP[5]
end

function PaletteRules.rampFor(category)
  return PaletteRules.rampForSlot(PaletteRules.slotFor(category))
end

function PaletteRules.priority(category)
  return PaletteRules.OWNER_PRIORITY[category or ""] or 0
end

function PaletteRules.isLocked(category)
  return PaletteRules.LOCKED[category or ""] == true
end

function PaletteRules.isBuildingCategory(category)
  return category == "BUILDING" or category == "DOOR"
end

--------------------------------------------------------------------------
-- Shared colour predicates (profile may swap magenta / roof variants)
--------------------------------------------------------------------------

local function is_water_blue(r, g, b)
  local chroma = b - math.max(r, g)
  return b > 150 and chroma > 55
end

local function is_brown_rock(r, g, b)
  return r > 100 and g > 70 and b <= math.max(g + 8, r * 0.72)
    and (r + g) > b * 1.9 and math.abs(r - g) < 65
end

-- Darker cliff lips / wet rock (shore edge means often sit below is_brown_rock).
local function is_dark_cliff_lip(r, g, b)
  if is_water_blue(r, g, b) then return false end
  return r > 55 and g > 40 and r >= g - 5 and g >= b - 20
    and (r + g) > b * 1.55 and b < 145
    and math.abs(r - g) < 70
end

-- Brown+blue quad means read as muted purple — cliff, not house-roof magenta.
-- Bright roof bodies (sum ≳ 400) stay on the roof path via is_magenta / rebar.
local function is_muddy_shore_purple(r, g, b)
  local sum = r + g + b
  if sum > 400 or sum < 160 then return false end
  local chroma = math.max(r, g, b) - math.min(r, g, b)
  return chroma < 55 and g + 8 < r and g + 8 < b
    and r > 70 and b > 70 and math.abs(r - b) < 45
end

local function is_strong_magenta_roof(r, g, b)
  return r > 155 and b > 155
    and (r + b) / 2 > g + 28 and b > g + 18 and r > g + 10
end

local function is_orange_roof(r, g, b)
  -- PC orange + cream; exclude sand (g≈r) which was becoming magenta corners.
  return r > 175 and g > 100 and r >= g
    and (r - b) > 90 and (g - b) > 40
    and g < r * 0.90
end

-- Bright magenta lip only (indoor-safe; cream floors must not trip this).
local function is_magenta_roof_bright(r, g, b)
  return r > 140 and b > 140 and r >= g and b >= g
    and (r + b) / 2 > g + 12
end

-- Outdoor house roofs: bright lip + dark purple body (~132,82,148).
-- Must not catch PC white fronts or window blue.
local function is_magenta_roof_outdoor(r, g, b)
  if is_magenta_roof_bright(r, g, b) then
    return true
  end
  if is_water_blue(r, g, b) then
    return false
  end
  -- Dark roof body: B leads G, R still warm-purple (not cool gray cliff).
  return b > 118 and r > 95 and b >= g + 12 and r >= g - 8
    and (r + b) / 2 > g + 18
    and math.abs(r - b) < 55
end

local function is_foliage_green(r, g, b)
  return g > r + 8 and g > b + 8 and g > 70
end

local function is_plaza_green(r, g, b)
  return g > 170 and g > r + 40 and g >= b
end

local function is_wood_tan(r, g, b)
  return r > 150 and r < 235 and g > 130 and g < 210
    and b <= g + 5 and b < r * 0.95
    and r + g > b * 2.0
    and math.abs(r - g) < 50
end

local function is_sand_tan(r, g, b)
  return r > 200 and g > 190 and b < g * 0.78 and r >= g - 20
    and (r + g) > b * 2.2 and math.abs(r - g) < 40
end

local function is_coral_metal(r, g, b)
  return r > 170 and g > 95 and g < 170 and b > 80 and b < 155
    and r > g + 25 and r > b + 15
end

local function is_red_rebar(r, g, b)
  return r > 120 and r >= g - 5 and g < 160 and b < 170
    and not is_water_blue(r, g, b)
    and (r > b + 5 or r > g + 15)
end

local function terrain_slot_from_mean(r, g, b)
  if is_water_blue(r, g, b) then return 1 end
  if is_foliage_green(r, g, b) then return 8 end
  if r > 190 and g > 160 and b < g * 0.72 then return 3 end
  if is_brown_rock(r, g, b) then return 4 end
  return 4
end

-- Cream / ivory floors & walls (FRLG Network Center plaza). Must not use slot 5:
-- that ramp's mid shade is window-blue and turns cream floors cyan while
-- stealing luminance range from the dark Network Machine body.
-- Warm bias is soft so beige walls (183,175,169) still count.
local function is_cream_ivory(r, g, b)
  local sum = r + g + b
  -- abs(r-g) < 40 (not 50): dusty rose desk wood (204,158,154) must hit wood_tan.
  return r > 165 and g > 150 and b > 110 and sum > 450
    and math.abs(r - g) < 40 and g >= b - 8
    and (r + g) / 2 >= b + 6
end

local function is_cool_metal(r, g, b)
  -- Machine panels / escalator: cool gray–blue-gray, not bright screen cyan.
  local sum = r + g + b
  return sum < 520 and b >= r - 8 and b >= g - 20
    and math.abs(r - g) < 55 and not is_cream_ivory(r, g, b)
end

-- Bright monitor / Network Machine screen (strongly cyan).
local function is_cyan_screen(r, g, b)
  return b > 195 and g > 170 and b > r + 20 and (r + g + b) > 520
end

-- Blue stool seats / crate lids (pale blue-white, not strong screen cyan).
local function is_blue_furniture(r, g, b)
  local sum = r + g + b
  return b > 200 and sum > 580 and b >= g - 5 and b > r + 5
    and (b - r) < 45
    and not is_cream_ivory(r, g, b)
end

-- Near-achromatic gray wall TVs / panels. Strict chroma so blue-gray Network
-- Machine body (e.g. 111,118,127 with b≫r) still hits is_cool_metal → machine.
local function is_wall_tv(r, g, b)
  local sum = r + g + b
  return sum < 470 and sum > 220
    and math.abs(r - g) < 12 and math.abs(g - b) < 12
    and math.abs(b - r) < 12
    and not is_cyan_screen(r, g, b)
end

local function is_pink_accent(r, g, b)
  -- True magenta/pink trim (B leads G). Dusty rose desk wood has g≈b — not accent.
  return r > 150 and b > 120 and g < 170
    and (r + b) / 2 > g + 12 and r > g + 8
    and b > g + 5
end

local function is_white_chrome(r, g, b)
  local sum = r + g + b
  return sum > 580 and math.abs(r - g) < 30 and math.abs(g - b) < 35
    and not is_blue_furniture(r, g, b) and not is_cyan_screen(r, g, b)
end

--------------------------------------------------------------------------
-- Material roles (composed on top of map profiles)
-- Map profile = which room; role = walls / floor / machine / screen / …
--
-- LOCKED (Network Machine — do not retune without an explicit ask):
--   machine → slot 7, screen → slot 1. Mid cohere keeps body/screen split.
--------------------------------------------------------------------------

PaletteRules.ROLES = {
  floor = { id = "floor", slot = 3 },             -- cream plaza (warm sand)
  -- Warm tan (cliff/wood family) — NOT slot 5 (window-blue) or 7 (machine gray).
  wall = { id = "wall", slot = 4 },
  -- LOCKED: Network Machine body. Same gray that currently looks correct in-game.
  machine = { id = "machine", slot = 7 },
  -- LOCKED: Network Machine / monitor cyan tops.
  screen = { id = "screen", slot = 1 },
  furniture_blue = { id = "furniture_blue", slot = 1 },
  furniture_wood = { id = "furniture_wood", slot = 4 },
  accent = { id = "accent", slot = 6 },           -- pink rails / wall trim only
  plant = { id = "plant", slot = 2 },
  escalator = { id = "escalator", slot = 7 },
  void = { id = "void", slot = 7 },
}

local function role_slot(roleId)
  local role = PaletteRules.ROLES[roleId]
  return role and role.slot or 5
end

--- Pick a material role for one 8×8 under a map profile.
function PaletteRules.resolveRole(mapProfileId, category, meanR, meanG, meanB, _quadIndex, _opts)
  meanR, meanG, meanB = meanR or 0, meanG or 0, meanB or 0
  category = category or ""

  if category == "SIGN" then
    return "furniture_wood"
  end
  if category == "TREE" then
    return "plant"
  end
  if category == "WATER" then
    return "screen"
  end

  if mapProfileId ~= "network" then
    if category == "STAIR" then return "wall" end
    if is_pink_accent(meanR, meanG, meanB) or is_orange_roof(meanR, meanG, meanB) then
      return "accent"
    end
    if is_wood_tan(meanR, meanG, meanB) then return "furniture_wood" end
    if is_cream_ivory(meanR, meanG, meanB) then return "wall" end
    if PaletteRules.isBuildingCategory(category) then return "wall" end
    return "wall"
  end

  -- Network Center role stack (order matters).
  -- LOCKED path: bright cyan → screen; cool blue-gray metal → machine (big PC).
  if category == "STAIR" then
    if is_pink_accent(meanR, meanG, meanB) then return "accent" end
    return "escalator"
  end
  if is_cyan_screen(meanR, meanG, meanB) then
    return "screen"
  end
  -- Wall-mounted TV / dark gray monitors → dark shade of WALL (not machine pal).
  if is_wall_tv(meanR, meanG, meanB) then
    return "wall"
  end
  if is_cool_metal(meanR, meanG, meanB) then
    return "machine"
  end
  -- True pink trim only — dusty rose desk wood is not accent.
  if is_pink_accent(meanR, meanG, meanB)
    or is_strong_magenta_roof(meanR, meanG, meanB) then
    return "accent"
  end
  if is_blue_furniture(meanR, meanG, meanB) then
    return "furniture_blue"
  end
  if is_plaza_green(meanR, meanG, meanB) or is_foliage_green(meanR, meanG, meanB) then
    return "plant"
  end
  -- Cream before wood: plaza / beige walls false-trigger wood tan.
  if is_cream_ivory(meanR, meanG, meanB) then
    if PaletteRules.isBuildingCategory(category) then
      return "wall"
    end
    return "floor"
  end
  if is_wood_tan(meanR, meanG, meanB) then
    return "furniture_wood"
  end
  if is_white_chrome(meanR, meanG, meanB) then
    return "wall"
  end
  if is_brown_rock(meanR, meanG, meanB) and meanR > meanB + 15 then
    return "furniture_wood"
  end
  if (meanR + meanG + meanB) < 80 then
    return "void"
  end
  if PaletteRules.isBuildingCategory(category) then
    return "machine"
  end
  if category == "SHORT_GRASS" or category == "TOWN_PATH" or category == "PATH"
    or category == "BLOCKED" then
    return "floor"
  end
  return "machine"
end

local function indoor_terrain_slot(r, g, b, isMagenta)
  if is_water_blue(r, g, b) then
    return 1
  end
  if is_plaza_green(r, g, b) or is_foliage_green(r, g, b) then
    return 2
  end
  if is_coral_metal(r, g, b) or is_red_rebar(r, g, b)
    or is_strong_magenta_roof(r, g, b) or is_orange_roof(r, g, b)
    or isMagenta(r, g, b) or is_pink_accent(r, g, b) then
    return 6
  end
  if is_cream_ivory(r, g, b) then
    return 5
  end
  if is_wood_tan(r, g, b) or is_brown_rock(r, g, b) then
    return 4
  end
  if math.abs(r - g) < 30 and math.abs(g - b) < 30 then
    return 5
  end
  return 5
end

local function network_slot_from_role(category, meanR, meanG, meanB, quadIndex, opts)
  local role = PaletteRules.resolveRole("network", category, meanR, meanG, meanB, quadIndex, opts)
  return role_slot(role)
end

--------------------------------------------------------------------------
-- Profile builders
--------------------------------------------------------------------------

local function outdoor_building_part(isMagenta, meanR, meanG, meanB, quadIndex, opts)
  meanR, meanG, meanB = meanR or 0, meanG or 0, meanB or 0
  opts = opts or {}
  if is_wood_tan(meanR, meanG, meanB) then
    return 4
  end
  if is_coral_metal(meanR, meanG, meanB) then
    return 6
  end
  if is_orange_roof(meanR, meanG, meanB) or isMagenta(meanR, meanG, meanB) then
    return 6
  end
  local topHalf = quadIndex == 0 or quadIndex == 1
  if topHalf and opts.bottomIsRoof then
    return terrain_slot_from_mean(meanR, meanG, meanB)
  end
  if is_plaza_green(meanR, meanG, meanB) then
    return 2
  end
  return 5
end

local function outdoor_refine(isMagenta, slot, category, meanR, meanG, meanB, quadIndex, opts)
  meanR, meanG, meanB = meanR or 0, meanG or 0, meanB or 0
  opts = opts or {}
  if category == "SIGN" or category == "STAIR" or category == "PIER" then
    return 4
  end
  if PaletteRules.isBuildingCategory(category) then
    return outdoor_building_part(isMagenta, meanR, meanG, meanB, quadIndex, opts)
  end
  if category == "WATER" then
    if is_water_blue(meanR, meanG, meanB) then
      return 1
    end
    -- Shore / cliff edges first: brown∩blue means look purple and must not
    -- land on the magenta roof ramp (slot 6).
    if is_muddy_shore_purple(meanR, meanG, meanB)
      or is_brown_rock(meanR, meanG, meanB)
      or is_dark_cliff_lip(meanR, meanG, meanB) then
      return 4
    end
    if is_coral_metal(meanR, meanG, meanB) or is_red_rebar(meanR, meanG, meanB) then
      return 6
    end
    if is_sand_tan(meanR, meanG, meanB) then
      return 3
    end
    if meanR > 170 and meanG > 140 and meanB > 120
      and meanR >= meanG and meanG >= meanB - 10
      and (meanR - meanB) < 70 then
      return 4
    end
    return 1
  end
  -- TREE: pure canopy stays slot 8. Mixed tip|cliff quads are assigned slot 9
  -- in extract via quadIsTreeCliffMix (needs the full 8×8, not just the mean).
  if category == "TREE" then
    return 8
  end
  if PaletteRules.isLocked(category) then
    return slot
  end
  if category == "BLOCKED" or category == "PATH" then
    if is_brown_rock(meanR, meanG, meanB) or is_dark_cliff_lip(meanR, meanG, meanB) then
      return 4
    end
    if is_muddy_shore_purple(meanR, meanG, meanB) then
      return 4
    end
    if is_sand_tan(meanR, meanG, meanB) then
      return 3
    end
    if is_water_blue(meanR, meanG, meanB) then
      return 1
    end
    if is_coral_metal(meanR, meanG, meanB) then
      return 6
    end
    if is_strong_magenta_roof(meanR, meanG, meanB) or isMagenta(meanR, meanG, meanB) then
      return 6
    end
    if is_foliage_green(meanR, meanG, meanB) then
      return 8
    end
    if meanB >= meanR - 5 and meanB >= meanG - 5 and meanR + meanG + meanB < 520 then
      return 4
    end
    return 5
  end
  if category == "TOWN_PATH" or category == "SHORT_GRASS" or category == "SAND" then
    if is_sand_tan(meanR, meanG, meanB) then
      return 3
    end
    if is_coral_metal(meanR, meanG, meanB) then
      return 6
    end
    if is_orange_roof(meanR, meanG, meanB) or is_strong_magenta_roof(meanR, meanG, meanB)
      or isMagenta(meanR, meanG, meanB) then
      return 6
    end
    if is_wood_tan(meanR, meanG, meanB) then
      return 4
    end
  end
  return slot
end

local function outdoor_slot(isMagenta, category, meanR, meanG, meanB, quadIndex, opts)
  if category == "SIGN" then
    return 4
  end
  if PaletteRules.isBuildingCategory(category) then
    return outdoor_building_part(isMagenta, meanR, meanG, meanB, quadIndex, opts)
  end
  return PaletteRules.slotFor(category)
end

local function indoor_refine(isMagenta, slot, category, meanR, meanG, meanB, _quadIndex, _opts)
  meanR, meanG, meanB = meanR or 0, meanG or 0, meanB or 0
  if category == "SIGN" or category == "PIER" then
    return 4
  end
  if PaletteRules.isBuildingCategory(category) then
    if is_wood_tan(meanR, meanG, meanB) then return 4 end
    if is_coral_metal(meanR, meanG, meanB) or is_orange_roof(meanR, meanG, meanB)
      or isMagenta(meanR, meanG, meanB) or is_strong_magenta_roof(meanR, meanG, meanB)
      or is_pink_accent(meanR, meanG, meanB) then
      return 6
    end
    if is_plaza_green(meanR, meanG, meanB) then return 2 end
    return 5
  end
  if category == "WATER" then
    if is_water_blue(meanR, meanG, meanB) then return 1 end
    if is_coral_metal(meanR, meanG, meanB) or is_red_rebar(meanR, meanG, meanB) then
      return 6
    end
    return 1
  end
  return slot
end

local function indoor_slot(isMagenta, category, meanR, meanG, meanB, _quadIndex, _opts)
  if category == "SIGN" then
    return 4
  end
  if category == "TREE" then
    return 8
  end
  if category == "WATER" then
    return 1
  end
  if category == "STAIR" then
    return 5
  end
  if PaletteRules.isBuildingCategory(category) then
    if is_wood_tan(meanR, meanG, meanB) then return 4 end
    if is_coral_metal(meanR, meanG, meanB) or is_orange_roof(meanR, meanG, meanB)
      or isMagenta(meanR, meanG, meanB) or is_strong_magenta_roof(meanR, meanG, meanB)
      or is_pink_accent(meanR, meanG, meanB) then
      return 6
    end
    if is_plaza_green(meanR, meanG, meanB) then
      return 2
    end
    return 5
  end
  return indoor_terrain_slot(meanR, meanG, meanB, isMagenta)
end

local function network_slot(_isMagenta, category, meanR, meanG, meanB, quadIndex, opts)
  return network_slot_from_role(category, meanR, meanG, meanB, quadIndex, opts)
end

local function network_refine(_isMagenta, _slot, category, meanR, meanG, meanB, quadIndex, opts)
  return network_slot_from_role(category, meanR, meanG, meanB, quadIndex, opts)
end

function PaletteRules.slotForRole(roleId)
  return role_slot(roleId)
end

--- Mid-level role vote so one object is not four independent guesses.
-- Returns length-4 role id array.
function PaletteRules.cohereMidRoles(profileId, category, roles)
  roles = { roles[1], roles[2], roles[3], roles[4] }
  category = category or ""

  -- Category hard constraints before voting.
  for i = 1, 4 do
    local r = roles[i] or "machine"
    if PaletteRules.isBuildingCategory(category) and r == "floor" then
      roles[i] = "wall" -- never paint walls with plaza sand
    elseif (category == "SHORT_GRASS" or category == "TOWN_PATH" or category == "PATH")
      and (r == "wall" or r == "machine") then
      roles[i] = "floor"
    elseif category == "STAIR" and r ~= "accent" then
      roles[i] = "escalator"
    end
  end

  if profileId ~= "network" then
    return roles
  end

  local counts = {}
  for i = 1, 4 do
    local r = roles[i]
    counts[r] = (counts[r] or 0) + 1
  end
  local function n(r) return counts[r] or 0 end
  local function force(r)
    return { r, r, r, r }
  end
  local function majority()
    local maj, majN = roles[1], 0
    for r, c in pairs(counts) do
      if c > majN then maj, majN = r, c end
    end
    return maj, majN
  end

  -- Stairs / escalator: one metal set (pink rails stay accent if majority).
  if category == "STAIR" then
    if n("accent") >= 2 then return force("accent") end
    return force("escalator")
  end

  -- Walls / corners / desk (BUILDING)
  if PaletteRules.isBuildingCategory(category) then
    -- LOCKED: solid machine / solid screen mids (big PC) — do not retune.
    if n("machine") >= 3 then
      return force("machine")
    end
    if n("screen") >= 3 then
      return force("screen")
    end
    -- Wall + embedded TV/panel (no cyan screen): whole mid stays wall so the
    -- TV becomes a dark wall shade instead of pulling machine gray into beige.
    if n("wall") >= 2 and n("machine") >= 1 and n("screen") == 0
      and n("furniture_wood") == 0 and n("furniture_blue") == 0 then
      return force("wall")
    end
    -- Pink trim band: accent + anything else → accent|wall only.
    if n("accent") >= 2 then
      local out = { roles[1], roles[2], roles[3], roles[4] }
      for i = 1, 4 do
        if out[i] ~= "accent" then out[i] = "wall" end
      end
      return out
    end
    -- Reception desk: gray metal top (LOCKED machine) + wood front; drop accent.
    if n("furniture_wood") >= 1 and n("machine") >= 1 then
      if n("machine") >= 2 and n("furniture_wood") >= 2 then
        return { "machine", "machine", "furniture_wood", "furniture_wood" }
      end
      local out = { roles[1], roles[2], roles[3], roles[4] }
      for i = 1, 4 do
        if out[i] == "accent" or out[i] == "screen" or out[i] == "plant"
          or out[i] == "wall" then
          if out[i] == "wall" then
            out[i] = "machine"
          else
            out[i] = "furniture_wood"
          end
        end
      end
      return out
    end
    -- Pure / mostly wall.
    if n("wall") >= 1 and n("machine") == 0 and n("screen") == 0
      and n("furniture_blue") == 0 and n("furniture_wood") == 0 then
      return force("wall")
    end
    if n("wall") >= 1 and n("machine") == 0 and n("screen") == 0
      and n("furniture_blue") == 0 then
      return force("wall")
    end
    -- Furniture stools: keep blue/wood split.
    if n("furniture_blue") + n("furniture_wood") >= 3 then
      local out = { roles[1], roles[2], roles[3], roles[4] }
      for i = 1, 4 do
        if out[i] ~= "furniture_blue" and out[i] ~= "furniture_wood" then
          out[i] = (n("furniture_blue") >= n("furniture_wood")) and "furniture_blue" or "furniture_wood"
        end
      end
      return out
    end
  end

  -- Plaza floor mids: stay sand.
  if category == "SHORT_GRASS" or category == "TOWN_PATH" or category == "PATH" then
    if n("floor") >= 2 then return force("floor") end
  end

  local maj, majN = majority()
  if majN >= 3 then
    return force(maj)
  end
  return roles
end

function PaletteRules.slotsFromRoles(roles)
  local slots = {}
  for i = 1, 4 do
    slots[i] = role_slot(roles[i] or "wall")
  end
  return slots
end

--- Back-compat wrapper used by tests / callers that only have slots.
function PaletteRules.cohereMidSlots(profileId, category, slots, _means)
  -- Without roles, only snap clear 3–1 majorities.
  slots = { slots[1], slots[2], slots[3], slots[4] }
  local counts = {}
  for i = 1, 4 do
    local s = slots[i] or 5
    counts[s] = (counts[s] or 0) + 1
  end
  local maj, majN = slots[1], 0
  for s, c in pairs(counts) do
    if c > majN then maj, majN = s, c end
  end
  if profileId == "network" and majN >= 2 then
    -- Warm wall slot majority on a building mid (wall role uses slot 4).
    if maj == 4 and majN >= 2 and PaletteRules.isBuildingCategory(category) then
      return { 4, 4, 4, 4 }
    end
  end
  if majN >= 3 then
    return { maj, maj, maj, maj }
  end
  return slots
end

--- Only flat monitor screens use nearest-to-ramp quantize.
-- Floors/walls/machines need luminance cuts so grout lines and vents survive.
function PaletteRules.usesFixedRampQuantize(profileId, role)
  return profileId == "network" and role == "screen"
end

--- Outdoor tree tip over cliff: bake by nearest shade of the hybrid ramp.
function PaletteRules.usesNearestRampBake(slot)
  return slot == PaletteRules.TREE_CLIFF_SLOT
end

local function bgr555_to_rgb_u8(c)
  c = c or 0
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return r5 * 255 / 31, g5 * 255 / 31, b5 * 255 / 31
end

--- True when an 8×8 has both foliage green and cliff brown (tree tip on rock
-- or stump on grass/cliff). `category` softens thresholds for CLIFF mids where
-- the tip is painted onto the rock tile (fewer brown samples than a stump).
function PaletteRules.quadIsTreeCliffMix(buf64, category)
  if not buf64 then return false end
  category = category or ""
  local greenN, brownN = 0, 0
  for i = 1, 64 do
    local r, g, b = bgr555_to_rgb_u8(buf64[i])
    if is_foliage_green(r, g, b) then
      greenN = greenN + 1
    elseif is_brown_rock(r, g, b) or is_dark_cliff_lip(r, g, b)
      or (r > 140 and g > 100 and b < r * 0.85 and r >= g and g >= b - 10
        and (r + g) > b * 1.7 and not is_water_blue(r, g, b)) then
      -- Cliff tan / rock highlight (slot-4 light shade territory).
      brownN = brownN + 1
    end
  end
  if greenN >= 6 and brownN >= 6 then
    return true
  end
  -- Tip painted onto a cliff/blocked mid: strong green blob + some rock.
  if (category == "CLIFF" or category == "COAST_CLIFF" or category == "BLOCKED")
    and greenN >= 8 and brownN >= 3 then
    return true
  end
  return false
end

local function make_outdoor_profile(id)
  local isMagenta = is_magenta_roof_outdoor
  return {
    id = id,
    indoor = false,
    isOrangeRoof = is_orange_roof,
    isMagentaRoof = isMagenta,
    isRoofColor = function(r, g, b)
      return is_orange_roof(r, g, b) or isMagenta(r, g, b)
    end,
    buildingPartSlot = function(meanR, meanG, meanB, quadIndex, opts)
      return outdoor_building_part(isMagenta, meanR, meanG, meanB, quadIndex, opts)
    end,
    slotForContext = function(category, meanR, meanG, meanB, quadIndex, opts)
      return outdoor_slot(isMagenta, category, meanR, meanG, meanB, quadIndex, opts)
    end,
    refineSlot = function(slot, category, meanR, meanG, meanB, quadIndex, opts)
      return outdoor_refine(isMagenta, slot, category, meanR, meanG, meanB, quadIndex, opts)
    end,
  }
end

local function make_indoor_profile(id)
  -- Strict bright magenta only — dark outdoor body must not steal cream floors.
  local isMagenta = is_magenta_roof_bright
  return {
    id = id,
    indoor = true,
    isOrangeRoof = is_orange_roof,
    isMagentaRoof = isMagenta,
    isRoofColor = function(r, g, b)
      return is_orange_roof(r, g, b) or isMagenta(r, g, b)
    end,
    buildingPartSlot = function(meanR, meanG, meanB, quadIndex, opts)
      -- Indoor buildings still use front/wood/accent; rear-lip path unused.
      return indoor_slot(isMagenta, "BUILDING", meanR, meanG, meanB, quadIndex, opts)
    end,
    slotForContext = function(category, meanR, meanG, meanB, quadIndex, opts)
      return indoor_slot(isMagenta, category, meanR, meanG, meanB, quadIndex, opts)
    end,
    refineSlot = function(slot, category, meanR, meanG, meanB, quadIndex, opts)
      return indoor_refine(isMagenta, slot, category, meanR, meanG, meanB, quadIndex, opts)
    end,
  }
end

local function make_network_profile()
  local isMagenta = is_magenta_roof_bright
  return {
    id = "network",
    indoor = true,
    isOrangeRoof = is_orange_roof,
    isMagentaRoof = isMagenta,
    isRoofColor = function(r, g, b)
      return is_orange_roof(r, g, b) or isMagenta(r, g, b)
    end,
    buildingPartSlot = function(meanR, meanG, meanB, quadIndex, opts)
      return network_slot_from_role("BUILDING", meanR, meanG, meanB, quadIndex, opts)
    end,
    slotForContext = function(category, meanR, meanG, meanB, quadIndex, opts)
      return network_slot(isMagenta, category, meanR, meanG, meanB, quadIndex, opts)
    end,
    refineSlot = function(slot, category, meanR, meanG, meanB, quadIndex, opts)
      return network_refine(isMagenta, slot, category, meanR, meanG, meanB, quadIndex, opts)
    end,
  }
end

PaletteRules.PROFILES = {
  sevii_outdoor_town = make_outdoor_profile("sevii_outdoor_town"),
  sevii_outdoor_route = make_outdoor_profile("sevii_outdoor_route"),
  network = make_network_profile(),
  house = make_indoor_profile("house"),
  harbor = make_indoor_profile("harbor"),
}

--- Auto-select profile from tileset pair + map environment.
-- opts.profile / opts.profileId force a named profile when present.
function PaletteRules.resolveProfile(pairName, environment, opts)
  opts = opts or {}
  local forced = opts.profileId or opts.profile
  if type(forced) == "table" and forced.id then
    return forced
  end
  if type(forced) == "string" and PaletteRules.PROFILES[forced] then
    return PaletteRules.PROFILES[forced]
  end

  if pairName == "network" then
    return PaletteRules.PROFILES.network
  end
  if pairName == "house" then
    return PaletteRules.PROFILES.house
  end
  if pairName == "harbor" then
    return PaletteRules.PROFILES.harbor
  end

  -- Indoor without a known pair (tests / future maps).
  if opts.indoor or environment == "INDOOR"
    or (pairName ~= nil and pairName ~= "sevii_outdoor") then
    return PaletteRules.PROFILES.network
  end

  if environment == "ROUTE" then
    return PaletteRules.PROFILES.sevii_outdoor_route
  end
  return PaletteRules.PROFILES.sevii_outdoor_town
end

local function profile_from_opts(opts, pairName, environment)
  opts = opts or {}
  if opts._profile then
    return opts._profile
  end
  return PaletteRules.resolveProfile(pairName or opts.pairName, environment or opts.environment, opts)
end

--------------------------------------------------------------------------
-- Public API (profile-aware; defaults keep outdoor behaviour for tests)
--------------------------------------------------------------------------

function PaletteRules.buildingPartSlot(meanR, meanG, meanB, quadIndex, opts)
  opts = opts or {}
  local profile = profile_from_opts(opts, opts.pairName, opts.environment)
  return profile.buildingPartSlot(meanR, meanG, meanB, quadIndex, opts)
end

function PaletteRules.refineSlot(slot, category, meanR, meanG, meanB, quadIndex, opts)
  opts = opts or {}
  local profile = opts._profile
  if not profile then
    if opts.indoor == true and not opts.pairName and not opts.profileId then
      profile = PaletteRules.PROFILES.network
    else
      profile = profile_from_opts(opts, opts.pairName, opts.environment)
    end
  end
  return profile.refineSlot(slot, category, meanR, meanG, meanB, quadIndex, opts)
end

function PaletteRules.ownCategory(selfCat, neighbourCounts)
  selfCat = selfCat or "TOWN_PATH"
  if PaletteRules.isLocked(selfCat) then
    return selfCat
  end
  neighbourCounts = neighbourCounts or {}
  local best, bestScore = selfCat, PaletteRules.priority(selfCat) + 50
  for cat, n in pairs(neighbourCounts) do
    if n and n > 0 then
      local score = PaletteRules.priority(cat) + n * 8
      if score > bestScore then
        best, bestScore = cat, score
      end
    end
  end
  return best
end

--- Indoor cream/wood/accent helper (Network profile predicates).
function PaletteRules.indoorTerrainSlot(meanR, meanG, meanB)
  return indoor_terrain_slot(meanR or 0, meanG or 0, meanB or 0, is_magenta_roof_bright)
end

function PaletteRules.slotForContext(category, environment, pairName, meanR, meanG, meanB, quadIndex, opts)
  opts = opts or {}
  local profile = PaletteRules.resolveProfile(pairName, environment, opts)
  opts._profile = profile
  opts.indoor = profile.indoor
  opts.pairName = pairName
  opts.environment = environment
  return profile.slotForContext(category, meanR, meanG, meanB, quadIndex, opts)
end

--- True if RGB is roof orange/magenta under the resolved profile (for rear-lip).
function PaletteRules.isRoofColor(meanR, meanG, meanB, pairName, environment, opts)
  local profile = PaletteRules.resolveProfile(pairName, environment, opts)
  return profile.isRoofColor(meanR or 0, meanG or 0, meanB or 0)
end

function PaletteRules.specialPalettes()
  local out = {}
  local n = math.max(8, PaletteRules.TREE_CLIFF_SLOT or 8)
  for i = 1, n do
    local ramp = PaletteRules.RAMP[i]
    if ramp then
      out[i] = {
        { ramp[1][1], ramp[1][2], ramp[1][3] },
        { ramp[2][1], ramp[2][2], ramp[2][3] },
        { ramp[3][1], ramp[3][2], ramp[3][3] },
        { ramp[4][1], ramp[4][2], ramp[4][3] },
      }
    end
  end
  return out
end

return PaletteRules
