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
    push(game, t[key], done)
  end
end

return {
  SUMMER_BEACH_HOUSE = {
    talk = {
      TEXT_SUMMERBEACHHOUSE_SURFINDUDE = function(game, ow, npc, done)
        local t = game.data.text
        if not surfingPikachu(game) then
          push(game, t._SummerBeachHouseSurfinDudeText4, done)
          return
        end
        -- Text1 on the first ask each visit, the short Text3 after
        local ask = ow.surfinDudeAsked
          and t._SummerBeachHouseSurfinDudeText3
          or t._SummerBeachHouseSurfinDudeText1
        ow.surfinDudeAsked = true
        push(game, ask, nil, { choice = function(yes)
            if not yes then
              push(game, t._SummerBeachHouseSurfinDudeText2, done)
              return
            end
            local SurfingMinigame = require("src.ui.SurfingMinigame")
            game.stack:push(SurfingMinigame.new(game, function()
              ow.surfedThisVisit = true -- BIT_PIKACHU_MAP_SURF_SELECT
              require("src.core.Music").playMap(game.data, ow.map.id)
              done()
            end))
          end })
      end,

      TEXT_SUMMERBEACHHOUSE_PIKACHU = function(game, ow, npc, done)
        local t = game.data.text
        -- scripts/SummerBeachHouse.asm:68
        push(game, t._SummerBeachHousePikachuText,
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
          push(game, t._SummerBeachHousePrinterText1, done)
          return
        end
        push(game, t._SummerBeachHousePrinterText2, function()
          if not ow.surfedThisVisit then
            done()
            return
          end
          push(game, t._SummerBeachHousePrinterText3, nil, { choice = function(yes)
              local SurfHiScore = require("src.ui.SurfHiScore")
              if not yes then
                -- scripts/SummerBeachHouse.asm:174
                game.stack:push(SurfHiScore.new(game, done))
                return
              end
              -- scripts/SummerBeachHouse_2.asm:7
              local Printer = require("src.core.Printer")
              local Strings = require("src.core.Strings")
              local saved, err = Printer.save("surf_hiscore", 160, 144,
                function() SurfHiScore.render(game) end)
              push(game, saved
                and (Strings("Printed!\f") .. Printer.savedWhereText(saved))
                or Strings("Printer error!\n%s", tostring(err)), done)
            end })
        end)
      end,
    },
  },
}
