-- pokemon_recolor: a per-species palette on every battle pic. Nothing else.
--
-- transforms.lua repaints the player's own front and back pics with a
-- four-shade ramp derived from reference artwork (Gen 3, as it happens);
-- the mod ships those ramps as integers and no pixels at all. This file does the two things a
-- transform cannot:
--
--   1. trueColor, so the renderer stops re-shading the repaint into the
--      active palette's four greys and throwing the colour away.
--   2. a pokemon.sprite wrapper, because DexEntryMenu loads pics without
--      going through Assets.resolve and would otherwise show the untouched
--      cache file while every other screen shows the repaint.
--
-- Species reviewed as looking better in vanilla are simply absent from
-- ramps.lua, so they are never repainted and never flagged: the engine
-- colours them exactly as it always did.

local loadchunk = loadstring or load

return function(mod)
  -- ramps.lua is generated, so treat it as data that may be stale, absent
  -- or half-written. A bad table costs the recolour, never the load.
  local source = mod:read("ramps.lua")
  if not source then
    mod.log:warn("ramps.lua missing -- run 'python3 "
      .. "tools/derive_palettes.py <pokeemerald>/graphics/pokemon' from "
      .. "this mod's directory; battle pics keep their vanilla palettes")
    return
  end

  local chunk, err = loadchunk(source, "ramps.lua")
  local ok, list = false, nil
  if chunk then ok, list = pcall(chunk) end
  if not ok or type(list) ~= "table" then
    mod.log:error("ramps.lua did not load (%s) -- re-run the tool to "
      .. "regenerate it; battle pics keep their vanilla palettes",
      tostring(err or list))
    return
  end

  -- Where AssetTransform puts this mod's output. Naming the derived tree
  -- rather than the ROM cache is deliberate: a mod has no business
  -- reaching into the player's cache by name, and modkit's MK301 enforces
  -- exactly that.
  local DERIVED = "save/mod-derived/" .. mod.id .. "/"

  local painted, absent = 0, 0
  local derivedFor = {}

  for _, entry in ipairs(list) do
    -- Every species is listed so its choice survives regeneration, but a
    -- variant of 1 carries no ramp: it is recorded, not repainted, and
    -- must not be flagged either.  Keying off the ramp rather than the
    -- variant number means a malformed row is skipped rather than trusted.
    if type(entry) == "table" and entry.id and entry.ramp
        and entry.front and entry.back then
      if mod.content.pokemon:get(entry.id) then
        -- patch, not override: naming one field leaves baseStats,
        -- learnset, types and evolutions exactly as the merged view had
        -- them, so this stays a graphics mod for every species.
        --
        -- The pic paths are NOT touched. The transform wrote its repaint
        -- under the same relative name, so the resolver swaps the file in
        -- underneath the record that already points at it.
        mod.content.pokemon:patch(entry.id, { trueColor = true })
        painted = painted + 1
        for _, rel in ipairs({ entry.front, entry.back }) do
          if type(rel) == "string" then
            derivedFor[rel:match("[^/]+$") or rel] = rel
          end
        end
      else
        absent = absent + 1
      end
    end
  end

  if absent > 0 then
    mod.log:warn("%d listed species were not in the merged view; another "
      .. "mod may have removed them", absent)
  end
  mod.log:info("recoloured %d species", painted)

  -- Matched on the tail of the path, so this never has to spell the cache
  -- tree, and a pic another mod redirected elsewhere passes through
  -- untouched.
  mod.hooks:wrap("pokemon.sprite", function(nxt, path, ctx)
    path = nxt(path, ctx)
    if type(path) ~= "string" then return path end
    local rel = derivedFor[path:match("[^/]+$") or ""]
    if rel and #path >= #rel and path:sub(-#rel) == rel then
      return DERIVED .. rel
    end
    return path
  end)

  mod.events:on("assets.transformed", function(ev)
    if ev.modId ~= mod.id then return end
    if ev.count == 0 then
      mod.log:warn("nothing repainted -- import your ROM first, then "
        .. "delete save/mod-derived/%s to re-run the transform", mod.id)
    else
      mod.log:info("repainted %d pics from your own cache", ev.count)
    end
  end)
end
