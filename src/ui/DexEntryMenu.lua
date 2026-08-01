-- Pokédex entry page: front sprite, kind, height/weight and the real
-- dex description (data/pokemon/dex_entries.asm + dex_text.asm).
--
-- `species` may be a species id string, or a table
-- `{ species = id, forceOwned = true }`.  forceOwned mirrors pret's
-- StarterDex (engine/events/starter_dex.asm), which temporarily sets the
-- owned bit so Oak's lab ball previews show height/weight/description
-- without permanently marking the mon owned.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local DexEntryMenu = {}
DexEntryMenu.__index = DexEntryMenu
DexEntryMenu.isOpaque = true

-- SGB: PalPacket_Pokedex (BROWNMON) + the mon pic zone in its palette
function DexEntryMenu:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local base = P.pal(game.data, "BROWNMON")
  if not base then return nil end
  return { P.whole(base),
           P.zone(P.monPal(game.data, self.def and self.def.id), 1, 1, 8, 8) }
end

local function resolveArgs(speciesOrOpts)
  if type(speciesOrOpts) == "table" then
    return speciesOrOpts.species or speciesOrOpts[1],
           speciesOrOpts.forceOwned and true or false
  end
  return speciesOrOpts, false
end

function DexEntryMenu.new(game, speciesOrOpts)
  local species, forceOwned = resolveArgs(speciesOrOpts)
  local self = setmetatable({ game = game, forceOwned = forceOwned }, DexEntryMenu)
  self.def = game.data.pokemon[species]
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, species, "front", { kind = "dex" })
  -- `path and pcall(...)` truncates to one value, so img was always nil and
  -- every dex page drew without its pic (#307); the guard has to be a
  -- statement for pcall's second return to survive.
  local ok, img = false, nil
  if path then ok, img = pcall(love.graphics.newImage, path) end
  self.sprite = ok and img or nil
  self.spriteTrueColor = self.sprite and trueColor or false
  require("src.core.Sound").playCry(game.data, species)
  return self
end

function DexEntryMenu:update(dt)
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
  end
end

function DexEntryMenu:draw()
  DexEntryMenu.render(self.game, self.def, self.sprite, self.forceOwned,
                      self.spriteTrueColor)
end

-- Static entry-page renderer, shared with the printer stand-in
-- (src/core/Printer.lua renders the same page into a PNG the way
-- PrintPokedexEntry rendered it to the Game Boy Printer).
function DexEntryMenu.render(game, def, sprite, forceOwned, trueColor)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if sprite then
    local y = math.max(0, 60 - sprite:getHeight())
    love.graphics.draw(sprite, 8, y)
    -- a full-color pic has to sit out the SGB recolor, so mark its bounds
    -- for the unshaded pass (#350).  The printer path leaves trueColor nil:
    -- it renders to its own PNG canvas, and a mark left behind there would
    -- bleed into the next real frame.
    if trueColor then
      require("src.render.PaletteFX").markTrueColor(8, y, sprite:getDimensions())
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(def.name, 72, 8)
  local e = def.dexEntry or {}
  -- English R/B prints only the kind string (hlcoord 9,4 PlaceString).
  -- PokeText ("#"/POKéMON) is an unreferenced JPN leftover in pokedex.asm;
  -- appending " POKéMON" here clipped longer kinds ("LIZARD POKé").
  Font.draw(e.kind or "?", 72, 20)
  -- same number width as the list (constants.dexDigits), so a dex past 999
  -- prints the extra digit everywhere at once
  local digits = (game.data.constants or {}).dexDigits or 3
  Font.draw(("No.%0" .. digits .. "d"):format(def.dex or 0), 72, 32)
  local owned = forceOwned
    or (game.save.pokedex and game.save.pokedex.owned[def.id])
  -- height/weight print only once owned, like the description
  -- (pokedex.asm: "if the pokemon has not been owned, don't print the
  -- height, weight, or description")
  if owned and e.heightFt then
    -- feet/inches use the dex screen's ′/″ glyphs ("HT  ?′??″" in
    -- pokedex.asm; the tiles come from gfx/pokedex/pokedex.png via
    -- engine/gfx/load_pokedex_tiles.asm)
    if e.heightM then
      -- metric entries (EUR imports and translation mods) print with the
      -- comma decimal and their own labels: "AL 1,9m" / "PE 120,0kg" in
      -- Spanish (engine/menus/pokedex.asm HeightWeightText), GR./GEW. as
      -- the historical translation-mod default
      local heightLabel = e.heightLabel or "GR."
      local weightLabel = e.weightLabel or "GEW."
      Font.draw(((heightLabel .. " %.1fm"):format(e.heightM)
        :gsub("(%d)%.(%d)", "%1,%2")), 64, 44)
      Font.draw(((weightLabel .. " %.1fkg"):format(e.weightKg or 0)
        :gsub("(%d)%.(%d)", "%1,%2")), 64, 54)
    else
      Font.draw(Strings("HT %d′%02d″", e.heightFt, e.heightIn or 0), 72, 44)
      Font.draw(Strings("WT %.1flb", (e.weight or 0) / 10), 72, 54)
    end
  end
  local text = owned and e.text and game.data.text[e.text] or nil
  local y = 72
  if text then
    for line in (text:gsub("\v", "\n"):gsub("\f", "\n") .. "\n"):gmatch("(.-)\n") do
      if y > 132 then break end
      Font.draw(line, 8, y)
      y = y + 10
    end
  else
    Font.draw(Strings("Data unknown."), 8, y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return DexEntryMenu
