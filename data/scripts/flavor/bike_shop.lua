-- BikeShop (BIKE_SHOP) flavor dialogue
-- Source: pokered/scripts/BikeShop.asm, pokered/text/BikeShop.asm
--
-- TEXT_BIKESHOP_CLERK lives in data/scripts/story2.lua (M.BIKE_SHOP): the
-- voucher exchange and the BICYCLE/CANCEL price window need more than
-- command rows (#568).

local TextBox = require("src.render.TextBox")

-- data/events/hidden_events.asm:542
local BIKE_DISPLAYS = {
  { 1, 0 }, { 2, 1 }, { 1, 2 }, { 3, 2 }, { 0, 4 }, { 1, 5 },
}

return {
  BIKE_SHOP = {
    -- engine/events/hidden_events/new_bike.asm:1
    onInteract = function(game, ow, fx, fy)
      for _, c in ipairs(BIKE_DISPLAYS) do
        if c[1] == fx and c[2] == fy then
          game.stack:push(TextBox.new(game,
            (game.data.text or {})._NewBicycleText or "A shiny new\nBICYCLE!"))
          return true
        end
      end
      return false
    end,

    talk = {
      -- BikeShopMiddleAgedWomanText (pokered/scripts/BikeShop.asm):
      -- always shows the same flavor line, no branching.
      TEXT_BIKESHOP_MIDDLE_AGED_WOMAN = {
        { "face_player" },
        { "show_text", "_BikeShopMiddleAgedWomanText" },
      },

      -- BikeShopYoungsterText (pokered/scripts/BikeShop.asm):
      -- CheckEvent EVENT_GOT_BICYCLE ; jr nz, .gotBike
      -- before the player owns a bike -> TheseBikesAreExpensiveText
      -- after the player owns a bike  -> CoolBikeText
      -- The check reads the bag, not the event: the port hands out the
      -- BICYCLE itself (a key item, so it cannot be tossed), and that also
      -- reads right on saves written before the clerk set the event (#567).
      TEXT_BIKESHOP_YOUNGSTER = {
        { "face_player" },                                            -- 1
        { "check_item", "BICYCLE" },                                  -- 2
        { "jump_if_true", 6 },                                        -- 3
        { "show_text", "_BikeShopYoungsterTheseBikesAreExpensiveText" }, -- 4
        { "jump", "end" },                                            -- 5
        { "show_text", "_BikeShopYoungsterCoolBikeText" },            -- 6
      },
    },
  },
}
