-- Hand-ported from pret/pokered scripts/CeladonMansionRoofHouse.asm
-- (CeladonMansionRoofHouseEeveePokeballText): the poke ball on the table
-- holds an Eevee (level 25).  The text_asm calls GivePokemon immediately
-- (no confirm prompt) and, on success, hides the ball object
-- (TOGGLE_CELADON_MANSION_EEVEE_GIFT predef HideObject, persisted in
-- wToggleableObjectFlags) -- the hidden ball is the original's whole
-- re-gift guard.  If the party AND box are full GivePokemon fails
-- (BoxIsFullText, .party_full) and the ball stays for later.
--
-- EVENT_GOT_EEVEE is port-internal bookkeeping with no pokered
-- equivalent, kept for save compatibility: rows 1-4 also self-heal
-- older saves (flag set before the port hid the ball) by hiding the
-- leftover ball on the next interaction.
--
-- The room's two readables (data/events/hidden_events.asm,
-- hidden_events_for CELADON_MANSION_ROOF_HOUSE):
--   hidden_text_predef 3, 0 / 4, 0  PrintBlackboardLinkCableText, LinkCableHelp
--   hidden_text_predef 3, 4         PrintNotebookText, TMNotebook
-- tools/extract/field.py only parses `hidden_event` rows, so no
-- hidden_text_predef row reaches data/generated/field.lua and both tiles
-- were dead A presses (#391).  Same hook shape as the bedroom SNES in
-- data/scripts/flavor/reds_house_2f.lua (#135).  hidden_text_predef puts
-- the predef id in the facing byte, so neither tile gates on facing.

local Menu = require("src.ui.Menu")
local TextBox = require("src.render.TextBox")

-- TMNotebookText (data/text/text_2.asm) has no leading underscore, but the
-- extractor now collects any top-level label in a dedicated text file
-- regardless (tools/extract/text.py), so this is the real ROM label --
-- the literal below is only the fallback for a catalog without it.
local TM_NOTEBOOK_TEXT = "It's a pamphlet\non TMs.\f...\f"
  .. "There are 50 TMs\nin all.\f"
  .. "There are also 5\nHMs that can be\vused repeatedly.\f"
  .. "SILPH CO."

-- LinkCableHelp (engine/events/hidden_events/school_blackboard.asm):
-- HowToLinkText's four headings in the 15x10 box at the top left; picking
-- a heading prints its LinkCableInfoText and returns to the menu, B or
-- STOP READING closes.
local LINK_HEADINGS = { "HOW TO LINK", "COLOSSEUM", "TRADE CENTER" }

local function linkCableHelp(game)
  local text = game.data.text or {}
  local items, menu, openMenu
  local function closeAll()
    game.stack:pop()
  end
  items = {}
  for i, label in ipairs(LINK_HEADINGS) do
    items[i] = { label = label, keepOpen = true, onSelect = function()
      game.stack:push(TextBox.new(game,
        text["_LinkCableInfoText" .. i] or label))
    end }
  end
  items[#items + 1] = { label = "STOP READING", onSelect = closeAll }
  menu = Menu.new(game, items,
    { tx = 0, ty = 0, tw = 15, th = 10, rowStep = 2, itemY = 2,
      onCancel = closeAll })
  function openMenu() game.stack:push(menu) end
  game.stack:push(TextBox.new(game,
    text._LinkCableHelpText1 or "TRAINER TIPS\fUsing a Game Link\nCable",
    function()
      game.stack:push(TextBox.new(game,
        text._LinkCableHelpText2 or "Which heading do\nyou want to read?",
        nil, { stay = { onShown = openMenu } }))
    end))
end

return {
  onInteract = function(game, ow, fx, fy)
    if fy == 0 and (fx == 3 or fx == 4) then
      linkCableHelp(game)
      return true
    end
    if fx == 3 and fy == 4 then
      local text = game.data.text or {}
      game.stack:push(TextBox.new(game, text.TMNotebookText or TM_NOTEBOOK_TEXT))
      return true
    end
    return false
  end,
  talk = {
    TEXT_CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL = {
      { "check_flag", "EVENT_GOT_EEVEE" },                     -- 1
      { "jump_if_false", 5 },                                  -- 2
      { "hide_object", "CELADON_MANSION_ROOF_HOUSE",
        "CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL" },          -- 3 (old saves)
      { "jump", 11 },                                          -- 4
      { "give_pokemon", "EEVEE", 25, false, true },            -- 5
      { "jump_if_false", 10 },                                 -- 6 (party+box full)
      -- scripts/CeladonMansionRoofHouse.asm:17-20 (#426)
      { "set_flag", "EVENT_GOT_EEVEE" },                       -- 7
      { "hide_object", "CELADON_MANSION_ROOF_HOUSE",
        "CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL" },          -- 8
      { "jump", 11 },                                          -- 9
      { "show_text", "_BoxIsFullText" },                       -- 10
    },
  },
}
