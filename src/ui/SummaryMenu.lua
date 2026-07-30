-- Pokémon status screen, laid out like the original's two pages
-- (engine/pokemon/status_screen.asm): page 1 = pic, No., HP bar,
-- STATUS/, the ATTACK/DEFENSE/SPEED/SPECIAL box and TYPE1/TYPE2/
-- IDNo/OT; page 2 = EXP and the moves with PP.  A flips pages, B (or
-- A on page 2) closes.

local Font = require("src.render.Font")
-- status_screen.asm PrintMonType prints the type's DISPLAY name from the
-- TypeNames table, not the constant: species types are stored as pokered
-- constants (RomExtractor:typesById) and PSYCHIC's is "PSYCHIC_TYPE" (so it
-- won't collide with the PSYCHIC move), which would overflow the TYPE field.
-- TypeChart.displayName maps it back to "PSYCHIC", like HallOfFame and the
-- battle move-type box already do (#214).
local TypeChart = require("src.battle.TypeChart")
local Strings = require("src.core.Strings")
local Stats = require("src.pokemon.Stats")

local SummaryMenu = {}
SummaryMenu.__index = SummaryMenu
SummaryMenu.isOpaque = true

-- SGB: SetPal_StatusScreen -- HP-bar palette overall, mon pic zone in
-- the species palette
function SummaryMenu:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local mon = self.mon
  if not mon then return P.wholeNamed(game.data, "MEWMON") end
  local bar = P.pal(game.data, P.barPalName(mon.hp, mon.stats.hp))
  if not bar then return nil end
  return { P.whole(bar), P.zone(P.monPal(game.data, mon.species), 1, 0, 7, 6) }
end

function SummaryMenu.new(game, mon)
  -- status_screen.asm:66-76: StatusScreen recalculates the stat block before
  -- it draws anything when the mon came from a box or the daycare ("mon is
  -- in a box or daycare" -> CalcStats), because box_struct carries none.
  -- Bill's PC hands us that mon table directly (src/ui/BoxMenu.lua's STATS
  -- submenu entry), and for a .sav imported through
  -- src/save_convert/GenSave.lua it really does arrive with mon.stats nil,
  -- which crashed the HP bar draw below (#233).  Redundant once
  -- SaveData.validate has run over a loaded save, but this is the site the
  -- original recomputes at, and it also covers a mon handed in by a mod.
  Stats.ensure(game.data.pokemon[mon.species], mon)
  local self = setmetatable({ game = game, mon = mon, page = 1 }, SummaryMenu)
  local Sprites = require("src.pokemon.Sprites")
  local path = Sprites.path(game.data, mon.species, "front",
    { mon = mon, kind = "summary" })
  if path then
    local ok, img = pcall(love.graphics.newImage, path)
    self.sprite = ok and img or nil
  end
  require("src.core.Sound").playCry(game.data, mon.species)
  return self
end

function SummaryMenu:update(dt)
  local input = self.game.input
  -- both A and B advance the pages (WaitForTextScrollButtonPress)
  if input:wasPressed("a") or input:wasPressed("b") then
    if self.page == 1 then
      self.page = 2
    else
      self.game.stack:pop()
    end
  end
end

-- DrawLineBox (status_screen.asm): a vertical edge down the right,
-- a corner, a horizontal run leftward and the half-arrow ending --
-- drawn from the same HUD tiles the original loads
local function drawLineBox(tx, ty, b, c)
  local HudTiles = require("src.render.HudTiles")
  -- Under the status screen's overlay the vertical is $78 -- DrawLineBox
  -- writes `ld [hl], $78` (status_screen.asm:222), and :90-93 is what puts
  -- hud_2's single bar tile there.  $73 is the <ID> glyph on this screen,
  -- not a line, so the whole box has to come off statusTile (#280).  The
  -- drawn shapes are unchanged: hud_2 tile 0 is the same bar the battle
  -- layout parks at $73.
  for i = 0, b - 1 do HudTiles.statusTile(0x78, tx * 8, (ty + i) * 8) end
  HudTiles.statusTile(0x77, tx * 8, (ty + b) * 8)
  for i = 1, c do HudTiles.statusTile(0x76, (tx - i) * 8, (ty + b) * 8) end
  HudTiles.statusTile(0x6F, (tx - c - 1) * 8, (ty + b) * 8)
end

-- home/pokemon.asm:335-345 PrintLevel: the "<LV>" (":L") tile at (tx,ty)
-- then the level LEFT_ALIGNed after it; at level 100 hl is decremented so
-- the third digit is written back OVER the ":L" tile.  Both status pages
-- print a level this way, and src/ui/PartyMenu.lua models the same rule for
-- its rows. #280
local function printLevel(tx, ty, level)
  local HudTiles = require("src.render.HudTiles")
  local x = tx * 8
  if level < 100 then
    HudTiles.statusTile(0x6E, x, ty * 8)
    x = x + 8
  end
  Font.draw(tostring(level), x, ty * 8)
end

function SummaryMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local mon = self.mon
  local game = self.game
  local data = game.data
  local def = data.pokemon[mon.species]

  -- shared header: pic (1,0), name (9,1), № + dex number (1,7).  The pic is
  -- MIRRORED -- status_screen.asm:170 draws it through
  -- LoadFlippedFrontSpriteByMonIndex (home/pokemon.asm sets wSpriteFlipped),
  -- the same routine the intro's NIDORINO show-off uses (OakSpeech picFlip:
  -- negative x scale anchored at the pic's right edge). #280
  if self.sprite then
    love.graphics.draw(self.sprite, 8 + self.sprite:getWidth(),
                       math.max(0, 56 - self.sprite:getHeight()), 0, -1, 1)
  end
  local HudTiles = require("src.render.HudTiles")
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(mon.nickname or def.name, 72, 8)
  -- status_screen.asm:109-113 backs hl up from DrawLineBox's end to write
  -- the single-tile '№' at (1,7) and '<DOT>' at (2,7); :143-146 then
  -- PrintNumbers the dex number (LEADING_ZEROES, 3 digits) at (3,7).
  -- Spelling "No." out of three letter tiles pushed every digit a column
  -- right of the original. #280
  HudTiles.statusTile(0x74, 8, 56)  -- №
  Font.drawCode(0xF2, 16, 56)       -- <DOT> (charmap.asm:182)
  Font.draw(("%03d"):format(def.dex or 0), 24, 56)

  if self.page == 1 then
    -- HP bar (11,3) + numbers row 4, STATUS/ (9,6), the DrawLineBox
    -- bracket around the name/HP block, and PrintLevel at (14,2).  The
    -- level belongs to page 1 ONLY: StatusScreen2 opens with ClearScreenArea
    -- over (9,2) 5x10 (status_screen.asm:303-305), which wipes it. #280
    printLevel(14, 2, mon.level)
    drawLineBox(19, 1, 6, 10)
    HudTiles.drawHPBar(data, 11, 3, mon, 1) -- wHPBarType 1
    Font.draw(("%3d/%3d"):format(mon.hp, mon.stats.hp), 96, 32)
    Font.draw(Strings("STATUS/"), 72, 48)
    Font.draw(mon.status or "OK", 128, 48)

    -- stats box (0,8) 10x10: names rows 9/11/13/15, values indented
    Font.drawBox(0, 8, 10, 10)
    local stats = {
      { "ATTACK", mon.stats.attack }, { "DEFENSE", mon.stats.defense },
      { "SPEED", mon.stats.speed }, { "SPECIAL", mon.stats.special },
    }
    for i, s in ipairs(stats) do
      local y = 72 + (i - 1) * 16
      Font.draw(Strings(s[1]), 8, y)
      Font.draw(("%3d"):format(s[2]), 48, y + 8)
    end

    -- TYPE1/TYPE2/IDNo/OT column (10,9) with values indented (11,10)
    drawLineBox(19, 9, 8, 6)
    Font.draw(Strings("TYPE1/"), 80, 72)
    Font.draw(def.types[1] and TypeChart.displayName(def.types[1]) or "", 88, 80)
    if def.types[2] then
      Font.draw(Strings("TYPE2/"), 80, 88)
      Font.draw(TypeChart.displayName(def.types[2]), 88, 96)
    end
    -- TypesIDNoOTText's third row is "<ID>№/" (status_screen.asm:205-210):
    -- two single-tile glyphs and a slash, three columns wide, not the five
    -- letter tiles "IDNo/" this used to spell out. #280
    HudTiles.statusTile(0x73, 80, 104) -- <ID>
    HudTiles.statusTile(0x74, 88, 104) -- №
    Font.draw("/", 96, 104)
    -- the trainer ID is rolled at new game (SaveData.newGame) and
    -- backfilled on load for old saves
    Font.draw(("%05d"):format(mon.otId or game.save.player.id or 0), 96, 112)
    Font.draw(Strings("OT/"), 80, 120)
    Font.draw(mon.ot or game.save.player.name or "RED", 96, 128)
  else
    -- page 2: EXP + the moves with PP (StatusScreen2)
    drawLineBox(19, 1, 6, 10)
    Font.draw(Strings("EXP POINTS"), 72, 24)
    -- PrintNumber at (12,4) with 7 columns: the exp is RIGHT-aligned into
    -- cols 12-18 (status_screen.asm:400-403), not left-aligned from col 12.
    -- #280
    Font.draw(("%7d"):format(mon.exp), 96, 32)
    -- StatusScreen2: "LEVEL UP" at (9,5); next-exp PrintNumber 7 cols at
    -- (7,6); the narrow '<to>' tile at (14,6); PrintLevel at (16,6)
    -- (status_screen.asm:393-403).  The old "%d to L%d" string at x=88
    -- overflowed the DrawLineBox edge.
    Font.draw(Strings("LEVEL UP"), 72, 40)
    local Growth = require("src.pokemon.Growth")
    local nextExp = mon.level < 100
      and (Growth.expForLevel(def.growthRate, mon.level + 1) - mon.exp) or 0
    Font.draw(("%7d"):format(math.max(0, nextExp)), 56, 48)
    HudTiles.statusTile(0x70, 112, 48) -- '<to>' at (14,6), was missing (#280)
    printLevel(16, 6, math.min(100, mon.level + 1))
    Font.drawBox(0, 8, 20, 10)
    for i = 1, 4 do
      local mv = mon.moves[i]
      local y = 72 + (i - 1) * 16
      if mv then
        local mdef = data.moves[mv.id]
        Font.draw(mdef.name, 16, y)
        Font.draw(Strings("PP"), 88, y + 8)
        Font.draw(("%2d/%2d"):format(mv.pp, mdef.pp), 112, y + 8)
      else
        Font.draw("-", 16, y)
        Font.draw("--", 112, y + 8)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return SummaryMenu
