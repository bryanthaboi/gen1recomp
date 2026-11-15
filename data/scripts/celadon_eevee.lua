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

-- engine/events/hidden_events/school_blackboard.asm:9
local function linkCableHelp(game)
  local text = game.data.text
  local headings = assert(text.HowToLinkText,
    "HowToLinkText missing from the text cache")
  local items, menu, openMenu
  local function closeAll()
    game.stack:pop()
  end
  items = {}
  for heading in (headings .. "\n"):gmatch("(.-)\n") do
    local i = #items + 1
    items[i] = { label = heading, keepOpen = true, onSelect = function()
      game.stack:push(TextBox.new(game,
        text["_LinkCableInfoText" .. i]))
    end }
  end
  -- engine/events/hidden_events/school_blackboard.asm:42
  items[4].keepOpen, items[4].onSelect = nil, closeAll
  menu = Menu.new(game, items,
    { tx = 0, ty = 0, tw = 15, th = 10, rowStep = 2, itemY = 2,
      onCancel = closeAll })
  function openMenu() game.stack:push(menu) end
  game.stack:push(TextBox.new(game,
    text._LinkCableHelpText1,
    function()
      game.stack:push(TextBox.new(game,
        text._LinkCableHelpText2,
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
      local text = game.data.text
      game.stack:push(TextBox.new(game, text.TMNotebookText))
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
