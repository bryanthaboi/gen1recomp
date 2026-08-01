-- Non-pausing party-status overview on the AYN Thor's second screen: shows
-- while walking around the overworld (or with a non-opaque overlay like a
-- text box open on top of it) -- icon, nickname, level, HP bar and status
-- condition for each party member. Never reads input and never blocks
-- gameplay; contrast with src/battle/BattleState.lua's SecondScreen usage,
-- which takes over the same panel for battle menus.
--
-- drawRows() draws only the rows themselves, at whatever origin/transform
-- is already active -- src/render/OverworldSecondScreen.lua composes it
-- alongside the pause-menu column on one shared canvas/push, so it owns
-- SecondScreen.begin()/finish(). draw() is the standalone entry point
-- (its own begin/finish, availability/ownership checks) for any other
-- caller that wants just the party panel on its own.
local SecondScreen = require("src.render.SecondScreen")
local HudTiles = require("src.render.HudTiles")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local PartyMenu = require("src.ui.PartyMenu")

local PartyStatusHUD = {}

local ROW_H = 24
local MAX_ROWS = 6 -- a full party; the 144px content area is exactly 6 * 24
local CONTENT_W, CONTENT_H = 160, 144
local BORDER = 8 -- one tile, matching Font.drawBox's own border thickness
-- Published so callers (src/render/OverworldSecondScreen.lua, draw()
-- below) can size their canvas/layout around the bordered panel without
-- hardcoding its dimensions redundantly.
PartyStatusHUD.WIDTH = CONTENT_W + BORDER * 2
PartyStatusHUD.HEIGHT = CONTENT_H + BORDER * 2

local PUSH_EVERY_N_FRAMES = 20 -- party HP/status/order changes rarely --
                                -- no need to stall the GPU every tick the
                                -- way a live menu does

local frame = 0

-- Whether some other state already drew to the second screen this frame
-- (see BattleState:usesSecondScreenText) -- the HUD yields the panel
-- rather than racing it for the same push.
local function secondScreenClaimedByStack(stack)
  for i = 1, #(stack and stack.states or {}) do
    local state = stack.states[i]
    if state and state.usesSecondScreenText and state:usesSecondScreenText() then
      return true
    end
  end
  return false
end

function PartyStatusHUD.drawRows(game)
  local party = game.save and game.save.party
  if not party or #party == 0 then return end

  -- The classic GB bordered box (corner + line glyphs) instead of a plain
  -- fill, matching the pause-menu column's own Font.drawBox border. It
  -- already fills its interior white, so no separate rectangle("fill")
  -- is needed; content below is drawn inset by one tile (BORDER) to clear
  -- the border glyphs, the same margin Menu:draw() leaves for its own box.
  Font.drawBox(0, 0, PartyStatusHUD.WIDTH / 8, PartyStatusHUD.HEIGHT / 8)
  love.graphics.push()
  love.graphics.translate(BORDER, BORDER)
  love.graphics.setColor(0, 0, 0, 1)

  for i = 1, math.min(#party, MAX_ROWS) do
    local mon = party[i]
    local def = game.data.pokemon[mon.species]
    local y = (i - 1) * ROW_H

    -- PartyMenu.drawIcon expects white active (it draws full-color icon
    -- art, not a tinted glyph) -- restore black after for the text below.
    love.graphics.setColor(1, 1, 1, 1)
    PartyMenu.drawIcon(game, mon, 2, y + 4, false, 0)
    love.graphics.setColor(0, 0, 0, 1)

    Font.draw(mon.nickname or def.name, 20, y + 1)
    HudTiles.tile(0x6E, 104, y + 1) -- <LV>
    Font.draw(tostring(mon.level), 112, y + 1)

    -- grayFill=false always: unlike PartyMenu's canvas, this one never
    -- goes through the main render pipeline's SGB zone pass, so the bar
    -- needs its own direct per-pixel tint or it would just stay gray.
    HudTiles.drawHPBar(game.data, 2.5, (y + 11) / 8, mon, nil, false)
    Font.draw(("%3d/%3d"):format(math.max(0, mon.hp), mon.stats.hp), 96, y + 11)

    if mon.hp <= 0 then
      Font.draw(Strings("FNT"), 136, y + 1)
    elseif mon.status then
      Font.draw(mon.status, 136, y + 1)
    end
  end
  love.graphics.pop()
end

function PartyStatusHUD.draw(game)
  if not SecondScreen.available() then return end
  if secondScreenClaimedByStack(game.stack) then return end
  local party = game.save and game.save.party
  if not party or #party == 0 then return end

  frame = frame + 1
  if frame % PUSH_EVERY_N_FRAMES ~= 0 then return end

  SecondScreen.begin(PartyStatusHUD.WIDTH, PartyStatusHUD.HEIGHT)
  PartyStatusHUD.drawRows(game)
  SecondScreen.finish()
end

return PartyStatusHUD
