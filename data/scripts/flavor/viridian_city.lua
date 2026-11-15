-- Viridian City flavor dialogue (pokered/scripts/ViridianCity.asm).
-- Ports the text_asm bodies for GAMBLER1, YOUNGSTER2 and GIRL.
--
-- Not ported here (already handled elsewhere / not talk-reachable):
--  * TEXT_VIRIDIANCITY_FISHER (TM42 gift) -- already ported as a
--    `gift()` entry in data/scripts/story5.lua's M.VIRIDIAN_CITY.talk.
--  * TEXT_VIRIDIANCITY_OLD_MAN (the walking man at (17,5)) and
--    TEXT_VIRIDIANCITY_OLD_MAN_SLEEPY (the sleeper at (18,9)) -- both
--    live in data/scripts/story.lua, which owns this map's onStep gate
--    and can reach the `old_man_demo` command for the real catch
--    tutorial.  Keep them there: story.lua loads BEFORE this file, so a
--    duplicate here would silently win the merge.
--  * TEXT_VIRIDIANCITY_GYM_LOCKED -- a step-triggered blocking text
--    (ViridianCityCheckGymOpenScript), implemented by story5.lua's
--    onStep chain (viridianGymLock -> viridianOldManStep) for this map.

local M = {}

local function text(game) return game.data.text end

local function push(game, s, done)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, s, done))
end

-- PrintText on a text_end string returns with the box still drawn and
-- YesNoChoice then draws the menu above it (InitYesNoTextBoxParameters,
-- engine/menus/text_box.asm); no A press clears the question first.  Ride
-- TextBox's opts.choice, the same as Commands.ask (#854).
local function ask(game, s, cb)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, s, nil, { choice = cb }))
end

M.VIRIDIAN_CITY = {
  talk = {
    -- pokered/scripts/ViridianCity.asm:150
    -- pokeyellow/scripts/ViridianCity_2.asm:10
    TEXT_VIRIDIANCITY_GAMBLER1 = function(game, ow, npc, done)
      local t = text(game)
      local sevenBadges = game.save.inventory and
        game.save.inventory.BOULDERBADGE and game.save.inventory.CASCADEBADGE
        and game.save.inventory.THUNDERBADGE and game.save.inventory.RAINBOWBADGE
        and game.save.inventory.SOULBADGE and game.save.inventory.MARSHBADGE
        and game.save.inventory.VOLCANOBADGE and not game.save.inventory.EARTHBADGE
      local flags = game.save.flags or {}
      local beatGiovanni = flags.EVENT_BEAT_GIOVANNI
        or flags.EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI
      if sevenBadges or beatGiovanni then
        push(game, t._ViridianCityGambler1GymLeaderReturnedText, done)
      else
        push(game, t._ViridianCityGambler1GymAlwaysClosedText, done)
      end
    end,

    -- scripts/ViridianCity.asm:171
    TEXT_VIRIDIANCITY_YOUNGSTER2 = function(game, ow, npc, done)
      local t = text(game)
      ask(game, t._ViridianCityYoungster2YouWantToKnowAboutText, function(yes)
        if yes then
          push(game, t.ViridianCityYoungster2CaterpieAndWeedleDescriptionText, done)
        else
          push(game, t.ViridianCityYoungster2OkThenText, done)
        end
      end)
    end,

    -- ViridianCityGirlText (scripts/ViridianCity.asm): before the
    -- player has the Pokedex she scolds her grandpa for being mean
    -- (he hasn't had his coffee yet); after EVENT_GOT_POKEDEX she talks
    -- about the winding trail through Viridian Forest to Pewter.
    TEXT_VIRIDIANCITY_GIRL = function(game, ow, npc, done)
      local t = text(game)
      if game.save.flags and game.save.flags.EVENT_GOT_POKEDEX then
        push(game, t._ViridianCityGirlWhenIGoShopText, done)
      else
        push(game, t._ViridianCityGirlHasntHadHisCoffeeYetText, done)
      end
    end,

  },
}

return M
