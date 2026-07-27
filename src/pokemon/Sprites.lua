-- Runtime Pokémon art resolution.  Content registries freeze after load,
-- so a mod that lets the player pick an alternate skin mid-session cannot
-- patch pokemon.spriteFront / icons.bySpecies.  These helpers are the
-- sanctioned seam: every battle pic and party icon load goes through
-- pokemon.sprite / pokemon.icon, which stay live for the whole process.

local Runtime = require("src.mods.Runtime")

local Sprites = {}

local function samePath(path) return path end

-- Resolve a battle / menu front or back pic path for `species`.
-- side: "front" | "back"
-- opts.mon: the live mon when available (per-instance skins)
-- opts.kind: "battle" | "summary" | "dex" | "evolution" | "hof" | "trade"
--            | "title" | "oak" | "credits" (informational for wrappers)
-- Returns path, trueColor.
function Sprites.path(data, species, side, opts)
  opts = opts or {}
  local def = data and data.pokemon and data.pokemon[species]
  if not def then return nil, false end
  local path = side == "back" and def.spriteBack or def.spriteFront
  local ctx = {
    species = species,
    side = side == "back" and "back" or "front",
    kind = opts.kind or "battle",
    mon = opts.mon,
    trueColor = def.trueColor and true or false,
    data = data,
  }
  if path and Runtime.wantsHook("pokemon.sprite") then
    local hooked = Runtime.call("pokemon.sprite", samePath, path, ctx)
    if type(hooked) == "string" and hooked ~= "" then path = hooked end
  end
  return path, ctx.trueColor and true or false
end

-- Resolve a party-menu icon image path for `mon`.
-- vanillaPath is the path PartyMenu already picked from icons.bySpecies /
-- def.icon / icons.byDex; the hook may replace it.
-- Returns path (possibly nil).
function Sprites.iconPath(data, mon, vanillaPath, opts)
  opts = opts or {}
  if not vanillaPath and not Runtime.wantsHook("pokemon.icon") then
    return vanillaPath
  end
  local species = mon and mon.species
  local ctx = {
    species = species,
    mon = mon,
    name = opts.name,
    data = data,
    kind = "icon",
  }
  if not Runtime.wantsHook("pokemon.icon") then return vanillaPath end
  local hooked = Runtime.call("pokemon.icon", samePath, vanillaPath, ctx)
  if type(hooked) == "string" and hooked ~= "" then return hooked end
  if hooked == nil or hooked == false then return nil end
  return vanillaPath
end

return Sprites
