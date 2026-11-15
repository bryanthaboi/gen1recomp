-- Red's House 2F (pokered data/events/hidden_events.asm +
-- engine/events/hidden_objects PrintRedSNESText).
--
-- The bedroom SNES is a hidden_event at (3, 5) with ANY_FACING that
-- prints _RedBedroomSNESText.  field.py extracts OpenRedsPC on this map
-- but skips PrintRedSNESText, so interaction was a no-op (#135).

local TextBox = require("src.render.TextBox")

return {
  REDS_HOUSE_2F = {
    -- hidden_events.asm:
    --   hidden_event 3, 5, PrintRedSNESText, ANY_FACING
    onInteract = function(game, ow, fx, fy)
      if fx ~= 3 or fy ~= 5 then return false end
      local text = game.data.text._RedBedroomSNESText
      game.stack:push(TextBox.new(game, text))
      return true
    end,
  },
}
