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

-- TMNotebookText (data/text/text_2.asm) has no leading underscore, so the
-- extractor never collects it and the pamphlet's text is inlined.
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
  local items, showMenu, askHeading
  function showMenu()
    game.stack:push(Menu.new(game, items,
      { tx = 0, ty = 0, tw = 15, th = 10, rowStep = 1 }))
  end
  function askHeading()
    game.stack:push(TextBox.new(game,
      text._LinkCableHelpText2 or "Which heading do\nyou want to read?",
      showMenu))
  end
  items = {}
  for i, label in ipairs(LINK_HEADINGS) do
    items[i] = { label = label, onSelect = function()
      game.stack:push(TextBox.new(game,
        text["_LinkCableInfoText" .. i] or label, askHeading))
    end }
  end
  items[#items + 1] = { label = "STOP READING" }
  game.stack:push(TextBox.new(game,
    text._LinkCableHelpText1 or "TRAINER TIPS\fUsing a Game Link\nCable",
    askHeading))
end

return {
  onInteract = function(game, ow, fx, fy)
    if fy == 0 and (fx == 3 or fx == 4) then
      linkCableHelp(game)
      return true
    end
    if fx == 3 and fy == 4 then
      game.stack:push(TextBox.new(game, TM_NOTEBOOK_TEXT))
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
      { "jump", 13 },                                          -- 4
      { "give_pokemon", "EEVEE", 25 },                         -- 5
      { "jump_if_false", 12 },                                 -- 6 (party+box full)
      { "play_sound", "Get_Item1" },                           -- 7 (GotMonText jingle)
      { "show_text", "_GotMonText", { RAM = "EEVEE" } },       -- 8
      { "set_flag", "EVENT_GOT_EEVEE" },                       -- 9
      { "hide_object", "CELADON_MANSION_ROOF_HOUSE",
        "CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL" },          -- 10
      { "jump", 13 },                                          -- 11
      { "show_text", "_BoxIsFullText" },                       -- 12
    },
  },
}
