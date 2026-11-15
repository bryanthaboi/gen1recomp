-- Hand-ported OAKS_LAB flavor: the simple talk texts (scripts/OaksLab.asm;
-- OAK1, the starter balls and RIVAL live in data/scripts/oaks_lab.lua).

local TextBox = require("src.render.TextBox")

return {
  OAKS_LAB = {
    -- data/events/hidden_events.asm:147
    onInteract = function(game, ow, fx, fy)
      local t = game.data.text
      -- engine/events/hidden_events/oaks_lab_posters.asm:1
      if fy == 0 and fx == 4 then
        game.stack:push(TextBox.new(game,
          t._PushStartText))
        return true
      end
      if fy == 0 and fx == 5 then
        local owned = 0
        for _ in pairs(game.save.pokedex.owned or {}) do owned = owned + 1 end
        game.stack:push(TextBox.new(game,
          owned >= 2
            and t._StrengthsAndWeaknessesText
            or t._SaveOptionText))
        return true
      end
      -- engine/events/hidden_events/oaks_lab_email.asm:1
      if fy == 1 and (fx == 0 or fx == 1) then
        if ow.player.facing ~= "up" then return false end
        game.stack:push(TextBox.new(game,
          t._OakLabEmailText))
        return true
      end
      return false
    end,
    talk = {
      -- OaksLabGirlText (scripts/OaksLab.asm)
      TEXT_OAKSLAB_GIRL = {
        { "face_player" },
        { "show_text", "_OaksLabGirlText" },
      },

      -- OaksLabPokedexText, used for both the POKEDEX1 and POKEDEX2
      -- table objects (scripts/OaksLab.asm OaksLab_TextPointers)
      TEXT_OAKSLAB_POKEDEX1 = {
        { "face_player" },
        { "show_text", "_OaksLabPokedexText" },
      },
      TEXT_OAKSLAB_POKEDEX2 = {
        { "face_player" },
        { "show_text", "_OaksLabPokedexText" },
      },

      -- OaksLabScientistText, used for both SCIENTIST1 and SCIENTIST2
      -- (scripts/OaksLab.asm OaksLab_TextPointers)
      TEXT_OAKSLAB_SCIENTIST1 = {
        { "face_player" },
        { "show_text", "_OaksLabScientistText" },
      },
      TEXT_OAKSLAB_SCIENTIST2 = {
        { "face_player" },
        { "show_text", "_OaksLabScientistText" },
      },
    },
  },
}
