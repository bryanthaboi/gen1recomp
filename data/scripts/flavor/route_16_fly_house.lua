-- Route 16 Fly House flavor dialogue
-- Source: pokered/scripts/Route16FlyHouse.asm, pokered/text/Route16FlyHouse.asm

return {
  ROUTE_16_FLY_HOUSE = {
    talk = {
      -- scripts/Route16FlyHouse.asm:45-51
      TEXT_ROUTE16FLYHOUSE_FEAROW = {
        { "play_cry", "FEAROW", true },
        { "show_text", "_Route16FlyHouseFearowText" },
      },
    },
  },
}
