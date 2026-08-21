-- The cursor/border/geometry constants every menu used to redeclare
-- locally, centralized so field.theme can restyle all of them at once.
-- Defaults are the current literals; the merge never runs without a mod,
-- so a vanilla boot draws byte-identically.

local Font = require("src.render.Font")
local Merge = require("src.mods.Merge")
local Renderer = require("src.render.Renderer")

local Theme = {
  cursor = 0xED,        -- the filled arrow (charmap.asm $ED)
  cursorHollow = 0xEC,  -- the unfilled arrow left on chosen rows
  moreArrow = 0xEE,     -- more-below marker (charmap.asm $EE)
  tile = 8,
  cols = Renderer.WIDTH / 8,
  rows = Renderer.HEIGHT / 8,
  textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 },
  -- InitYesNoTextBoxParameters / AskName: hlcoord 14, 7 (YES_NO_MENU 4x3)
  choiceBox = { tx = 14, ty = 7, tw = 6, th = 5 },
  -- YesNoChoicePokeCenter: hlcoord 11, 6 (HEAL_CANCEL_MENU 7x4, blank line
  -- before the first item) -- home/yes_no.asm:21, data/yes_no_menu_strings.asm:16
  healCancelBox = { tx = 11, ty = 6, tw = 9, th = 6, firstItem = 2 },
  -- EnemySendOutFirstMon inlines its own TWO_OPTION_MENU at hlcoord 0, 7
  -- instead of the shared right-hand one -- engine/battle/core.asm:1378-1384
  trainerSwitchBox = { tx = 0, ty = 7, tw = 6, th = 5 },
  -- SaveTheGame_YesOrNo pins its TWO_OPTION_MENU at hlcoord 0, 7 too --
  -- engine/menus/save.asm:186-192
  saveBox = { tx = 0, ty = 7, tw = 6, th = 5 },
}

function Theme.load(data)
  -- Font.load rebuilds its border table, so pick it up here rather than at
  -- require time
  Theme.border = Font.BORDER
  local t = data and data.field and data.field.theme
  if t then
    Merge.deepMerge(Theme, t)
    Font.BORDER = Theme.border
  end
end

return Theme
