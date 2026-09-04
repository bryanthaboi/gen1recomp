-- Pokédex entry page: front sprite, kind, height/weight and the real
-- dex description (data/pokemon/dex_entries.asm + dex_text.asm).
--
-- `species` may be a species id string, or a table
-- `{ species = id, forceOwned = true }`.  forceOwned mirrors pret's
-- StarterDex (engine/events/starter_dex.asm), which temporarily sets the
-- owned bit so Oak's lab ball previews show height/weight/description
-- without permanently marking the mon owned.
--
-- `onDone` (optional) runs right after the page pops itself, the way a
-- TextBox onDone does; map scripts use it to continue once the player
-- closes the entry (the Fighting Dojo prize balls chain their take-it
-- prompt off it).

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

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

local function ownedFor(game, def, forceOwned)
  return forceOwned
    or (game.save.pokedex and game.save.pokedex.owned[def.id]) or false
end

-- home/text.asm:245 (<PAGE>), home/text.asm:204 (<DEXEND>)
local function descPages(game, def, forceOwned)
  local e = def.dexEntry or {}
  local owned = ownedFor(game, def, forceOwned)
  local text = owned and e.text and game.data.text[e.text] or nil
  if not text then return nil end
  local pages = {}
  for chunk in (text .. "\f"):gmatch("(.-)\f") do
    local lines = {}
    for line in (chunk:gsub("\v", "\n") .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
    if #lines > 0 then pages[#pages + 1] = lines end
  end
  if #pages == 0 then return nil end
  local last = pages[#pages]
  last[#last] = last[#last] .. "."
  return pages
end

-- engine/gfx/load_pokedex_tiles.asm: gfx/pokedex/pokedex.png, codes $60..$71
local frameCache = {}
local function frameSheet(game)
  local fx = game.data.field and game.data.field.overworldFx
  local def = fx and fx.pokedexFrame
  local path = def and def.path
  if not path then return nil end
  local hit = frameCache[path]
  if hit ~= nil then return hit or nil end
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok or not img then
    frameCache[path] = false
    return nil
  end
  local iw, ih = img:getDimensions()
  local quads = {}
  for i = 0, 17 do
    quads[i] = love.graphics.newQuad((i % 3) * 8,
                                     math.floor(i / 3) * 8, 8, 8, iw, ih)
  end
  frameCache[path] = { img = img, quads = quads }
  return frameCache[path]
end

-- engine/gfx/load_pokedex_tiles.asm:8-11: PokeballTileGraphics -> tile $72
local ballCache
local function ballSheet()
  if ballCache == nil then
    local ok, img = pcall(love.graphics.newImage,
                          "assets/generated/battle/balls.png")
    if ok and img then
      ballCache = { img = img,
                    quad = love.graphics.newQuad(0, 0, 8, 8,
                                                 img:getDimensions()) }
    else
      ballCache = false
    end
  end
  return ballCache or nil
end

-- one tile of the sheet, for the CONTENTS screen's divider column
-- (engine/menus/pokedex.asm:350, DrawPokedexVerticalLine)
function DexEntryMenu.tile(game, code, tx, ty)
  if code == 0x72 then
    local ball = ballSheet()
    if ball then love.graphics.draw(ball.img, ball.quad, tx * 8, ty * 8) end
    return
  end
  local frame = frameSheet(game)
  if not (frame and code) then return end
  local quad = frame.quads[code - 0x60]
  if quad then love.graphics.draw(frame.img, quad, tx * 8, ty * 8) end
end

-- engine/menus/pokedex.asm:601
local DIVIDER = {
  0x68, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x6B,
  0x6B, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6A,
}

function DexEntryMenu.new(game, speciesOrOpts, onDone)
  local species, forceOwned = resolveArgs(speciesOrOpts)
  local self = setmetatable({ game = game, forceOwned = forceOwned,
                              onDone = onDone }, DexEntryMenu)
  self.def = game.data.pokemon[species]
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, species, "front", { kind = "dex" })
  -- pcall's second return has to survive the guard (#307)
  local ok, img = false, nil
  if path then ok, img = pcall(love.graphics.newImage, path) end
  self.sprite = ok and img or nil
  self.spriteTrueColor = self.sprite and trueColor or false
  self.page = 1
  self.blink = 0
  local pages = descPages(game, self.def, forceOwned)
  self.pageCount = pages and #pages or 1
  -- engine/menus/pokedex.asm:500-506, home/pokemon.asm:145-148
  self.crySrc = require("src.core.Sound").playCry(game.data, species)
  return self
end

-- home/pokemon.asm:148 (jp WaitForSoundToFinish)
function DexEntryMenu:crying()
  local src = self.crySrc
  if not src then return false end
  local ok, playing = pcall(src.isPlaying, src)
  if ok and playing then return true end
  self.crySrc = nil
  return false
end

function DexEntryMenu:update(dt)
  local input = self.game.input
  self.blink = ((self.blink or 0) + 1) % 60
  if self:crying() then return end
  if input:wasPressed("a") or input:wasPressed("b") then
    -- home/text.asm:245
    if self.page < (self.pageCount or 1) then
      self.page = self.page + 1
      return
    end
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function DexEntryMenu:draw()
  DexEntryMenu.render(self.game, self.def, self.sprite, self.forceOwned,
                      self.spriteTrueColor, self.page,
                      { crying = self:crying(),
                        arrow = (self.blink or 0) < 30 })
end

-- Static entry-page renderer, shared with the printer stand-in
-- (src/core/Printer.lua renders the same page into a PNG the way
-- PrintPokedexEntry rendered it to the Game Boy Printer).
-- engine/menus/pokedex.asm:399
function DexEntryMenu.render(game, def, sprite, forceOwned, trueColor, page, state)
  page = page or 1
  state = state or {}
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local frame = frameSheet(game)
  if frame then
    local function tile(code, tx, ty)
      love.graphics.draw(frame.img, frame.quads[code - 0x60], tx * 8, ty * 8)
    end
    -- engine/menus/pokedex.asm:418
    for tx = 1, 18 do
      tile(0x64, tx, 0)
      tile(0x6f, tx, 17)
    end
    for ty = 1, 16 do
      tile(0x66, 0, ty)
      tile(0x67, 19, ty)
    end
    tile(0x63, 0, 0)
    tile(0x65, 19, 0)
    tile(0x6c, 0, 17)
    tile(0x6e, 19, 17)
    -- engine/menus/pokedex.asm:445
    for tx = 0, 19 do
      tile(DIVIDER[tx + 1], tx, 9)
    end
  end
  if sprite then
    -- engine/menus/pokedex.asm:503, home/pokemon.asm:96 (flipped)
    local w, h = sprite:getDimensions()
    local x = 8 + math.floor((8 - w / 8) / 2) * 8
    local y = 8 + (7 - h / 8) * 8
    love.graphics.draw(sprite, x + w, y, 0, -1, 1)
    -- the unshaded pass needs the pic bounds (#350)
    if trueColor then
      require("src.render.PaletteFX").markTrueColor(x, y, w, h)
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
  -- engine/menus/pokedex.asm:454
  Font.draw(def.name, 72, 16)
  local e = def.dexEntry or {}
  -- engine/menus/pokedex.asm:468, kind string only (PokeText is unreferenced)
  Font.draw(e.kind or "?", 72, 32)
  -- same number width as the list (constants.dexDigits), so a dex past 999
  -- prints the extra digit everywhere at once
  local digits = (game.data.constants or {}).dexDigits or 3
  -- engine/menus/pokedex.asm:478
  Font.draw(Strings("No.") .. ("%0" .. digits .. "d"):format(def.dex or 0),
            16, 64)
  local owned = ownedFor(game, def, forceOwned)
  local metric = e.heightM ~= nil
  local numbers = owned and e.heightFt
  -- engine/menus/pokedex.asm:449
  if not metric then
    Font.draw(Strings("HT"), 72, 48)
    Font.draw("′", 112, 48)
    Font.draw("″", 136, 48)
    Font.draw(Strings("WT"), 72, 64)
    Font.draw(Strings("lb"), 136, 64)
    if not numbers then
      Font.draw("?", 104, 48)
      Font.draw("??", 120, 48)
      Font.draw("???", 112, 64)
    end
  end
  -- engine/menus/pokedex.asm:516: everything below the divider waits on the
  -- cry the line above it started
  if state.crying then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  -- engine/menus/pokedex.asm:515-566
  if numbers then
    if metric then
      Font.draw((Strings("GR. %.1fm", e.heightM):gsub("(%d)%.(%d)", "%1,%2")), 72, 48)
      Font.draw((Strings("GEW. %.1fkg", e.weightKg or 0):gsub("(%d)%.(%d)", "%1,%2")), 72, 64)
    else
      Font.draw(("%2d"):format(e.heightFt), 96, 48)
      Font.draw(("%02d"):format(e.heightIn or 0), 120, 48)
      Font.draw(("%6.1f"):format((e.weight or 0) / 10), 88, 64)
    end
  end
  local pages = descPages(game, def, forceOwned)
  if pages then
    -- engine/menus/pokedex.asm:568
    local lines = pages[page] or pages[#pages]
    for i, line in ipairs(lines) do
      Font.draw(line, 8, 72 + i * 16)
    end
    -- home/text.asm:245 places the '▼' and home/joypad2.asm:55-83 blinks it
    if page < #pages and state.arrow ~= false then
      Font.drawCode(Theme.moreArrow, 144, 128)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return DexEntryMenu
