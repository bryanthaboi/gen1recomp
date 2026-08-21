-- Summer Beach House (scripts/SummerBeachHouse.asm), Yellow's Route 19
-- surf shack.  The Surfin' Dude only lets a party Pikachu that knows
-- SURF ride (IsSurfingPikachuInParty, home/map_objects.asm); saying yes
-- runs the Surfing Pikachu minigame (src/ui/SurfingMinigame.lua).  The
-- corner printer shows/prints the high score once you have surfed this
-- visit (BIT_PIKACHU_MAP_SURF_SELECT is a per-map-load flag, so the
-- session markers live on the overworld state, not the save).

local function surfingPikachu(game)
  for _, mon in ipairs(game.save.party or {}) do
    if mon.species == "PIKACHU" then
      for _, mv in ipairs(mon.moves or {}) do
        if mv.id == "SURF" then return mon end
      end
    end
  end
  return nil
end

local function push(game, text, done, opts)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, done, opts))
end

-- the two-variant posters: the surf-capable line once a surfing
-- Pikachu is along, the plain one otherwise
local function poster(n)
  return function(game, ow, npc, done)
    local t = game.data.text
    local key = ("_SummerBeachHousePoster%dText%d"):format(
      n, surfingPikachu(game) and 1 or 2)
    push(game, t[key] or "A surfing poster.", done)
  end
end

return {
  SUMMER_BEACH_HOUSE = {
    talk = {
      TEXT_SUMMERBEACHHOUSE_SURFINDUDE = function(game, ow, npc, done)
        local t = game.data.text
        if not surfingPikachu(game) then
          push(game, t._SummerBeachHouseSurfinDudeText4
            or "Dogs and burgers\non special today!", done)
          return
        end
        -- Text1 on the first ask each visit, the short Text3 after
        local ask = ow.surfinDudeAsked
          and (t._SummerBeachHouseSurfinDudeText3 or "Wanna go SURF?")
          or (t._SummerBeachHouseSurfinDudeText1
              or "Whoa!\nYour PIKACHU knows\nhow to SURF!\fGive it a go?")
        ow.surfinDudeAsked = true
        push(game, ask, function()
          local ChoiceBox = require("src.ui.ChoiceBox")
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then
              push(game, t._SummerBeachHouseSurfinDudeText2
                or "Come SURF anytime,\nmy friend!", done)
              return
            end
            local SurfingMinigame = require("src.ui.SurfingMinigame")
            game.stack:push(SurfingMinigame.new(game, function()
              ow.surfedThisVisit = true -- BIT_PIKACHU_MAP_SURF_SELECT
              require("src.core.Music").playMap(game.data, ow.map.id)
              done()
            end))
          end))
        end)
      end,

      TEXT_SUMMERBEACHHOUSE_PIKACHU = function(game, ow, npc, done)
        local t = game.data.text
        -- scripts/SummerBeachHouse.asm:68
        push(game, t._SummerBeachHousePikachuText or "PIKACHU: Pikaa!",
          done, { auto = { wait = true, delay = 0, sound = function()
            return require("src.core.Sound").playCry(game.data, "PIKACHU")
          end } })
      end,

      TEXT_SUMMERBEACHHOUSE_POSTER1 = poster(1),
      TEXT_SUMMERBEACHHOUSE_POSTER2 = poster(2),
      TEXT_SUMMERBEACHHOUSE_POSTER3 = poster(3),

      TEXT_SUMMERBEACHHOUSE_PRINTER = function(game, ow, npc, done)
        local t = game.data.text
        if not surfingPikachu(game) then
          push(game, t._SummerBeachHousePrinterText1
            or "It's some sort of\na machine...", done)
          return
        end
        push(game, t._SummerBeachHousePrinterText2
          or "SUMMER BEACH HOUSE\nPRINTER, it says.", function()
          if not ow.surfedThisVisit then
            done()
            return
          end
          push(game, t._SummerBeachHousePrinterText3
            or "The Hi-Score is\nshown.\fPRINT it out?", function()
            local ChoiceBox = require("src.ui.ChoiceBox")
            game.stack:push(ChoiceBox.new(game, function(yes)
              if not yes then
                done()
                return
              end
              -- PrintSurfingMinigameHighScore -> PNG stand-in
              local Printer = require("src.core.Printer")
              local Font = require("src.render.Font")
              local Strings = require("src.core.Strings")
              local hi = game.save.surfingHighScore or 0
              local name = game.save.player.name or "RED"
              local saved, err = Printer.save("surf_hiscore", 160, 64,
                function()
                  love.graphics.setColor(1, 1, 1, 1)
                  love.graphics.rectangle("fill", 0, 0, 160, 64)
                  love.graphics.setColor(0, 0, 0, 1)
                  love.graphics.rectangle("line", 2.5, 2.5, 155, 59)
                  Font.draw(Strings("SUMMER BEACH HOUSE"), 8, 10)
                  Font.draw(Strings("SURFING Hi-Score"), 8, 24)
                  Font.draw(name, 8, 40)
                  Font.draw(Strings("%d pts", hi), 96, 40)
                end)
              push(game, saved
                and Strings("Printed!\fSaved as\n%s\vin the save\nfolder.",
                            saved)
                or Strings("Printer error!\n%s", tostring(err)), done)
            end))
          end)
        end)
      end,
    },
  },
}
