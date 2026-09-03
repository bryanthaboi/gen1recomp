-- Celadon Mansion 3F, the GAME FREAK dev floor
-- (pokered+pokeyellow/scripts/CeladonMansion3F.asm).  Every dev's
-- text_asm counts set bits in wPokedexOwned against NUM_POKEMON - 1
-- (150, discounting Mew).  The game designer shows the diploma
-- (DisplayDiploma -> src/ui/Diploma.lua) on a completed dex; Yellow's
-- graphic artist then offers the printed copy (PrintDiploma, stood in
-- by src/core/Printer.lua's PNG export like the Pokédex PRNT item).

local function ownedCount(game)
  local dex = game.save.pokedex
  local owned = 0
  if dex and dex.owned then
    for _ in pairs(dex.owned) do owned = owned + 1 end
  end
  return owned
end

return {
  CELADON_MANSION_3F = {
    talk = {
      TEXT_CELADONMANSION3F_GAME_DESIGNER = function(game, ow, npc, done)
        local t = game.data.text
        local TextBox = require("src.render.TextBox")
        if ownedCount(game) < 150 then
          game.stack:push(TextBox.new(game,
            t._CeladonMansion3FGameDesignerText
            or "Is that right?\nI'm the game\ndesigner!\fFilling up your\nPOKéDEX is tough,\nbut don't quit!",
            done))
          return
        end
        game.stack:push(TextBox.new(game,
          t._CeladonMansion3FGameDesignerCompletedDexText
          or "Wow! Excellent!\nYou completed\nyour POKéDEX!\nCongratulations!",
          function()
            local Diploma = require("src.ui.Diploma")
            game.stack:push(Diploma.new(game, function()
              -- Yellow tags on the unlocked-printing line (CompletedDexText2)
              local after = require("src.core.GameVersion").isYellow()
                and (t._CeladonMansion3FGameDesignerCompletedDexText2
                     or "You can print out\nyour diploma with\nthe GAME BOY\nPrinter!")
                or nil
              if after then
                game.stack:push(TextBox.new(game, after, done))
              else
                done()
              end
            end))
          end))
      end,

      TEXT_CELADONMANSION3F_GRAPHIC_ARTIST = function(game, ow, npc, done)
        local t = game.data.text
        local TextBox = require("src.render.TextBox")
        local yellow = require("src.core.GameVersion").isYellow()
        if not (yellow and ownedCount(game) >= 150) then
          game.stack:push(TextBox.new(game,
            t._CeladonMansion3FGraphicArtistText
            or "I'm the graphic\nartist!\nI drew you!", done))
          return
        end
        -- _CeladonMansion3FGraphicArtistText2: offer to print the diploma
        game.stack:push(TextBox.new(game,
          t._CeladonMansion3FGraphicArtistText2
          or "I'm the graphic\nartist!\fShould I print\nyour diploma?",
          function()
            local ChoiceBox = require("src.ui.ChoiceBox")
            game.stack:push(ChoiceBox.new(game, function(yes)
              if not yes then
                game.stack:push(TextBox.new(game,
                  t._CeladonMansion3FGraphicArtistText3
                  or "Oh. But it's a\nspecial diploma!", done))
                return
              end
              local Printer = require("src.core.Printer")
              local Diploma = require("src.ui.Diploma")
              local Strings = require("src.core.Strings")
              local saved, err = Printer.save("diploma", 160, 144, function()
                Diploma.render(game)
              end)
              -- the PRNT stand-in always reports where the PNG landed
              game.stack:push(TextBox.new(game, saved
                and (Strings("There you go!\f") .. Printer.savedWhereText(saved))
                or Strings("Printer error!\n%s", tostring(err)), done))
            end))
          end))
      end,
    },
  },
}
