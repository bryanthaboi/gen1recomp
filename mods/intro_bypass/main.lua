-- Intro Bypass mod for gen1recomp
-- Adds a "BYPASS INTRO" entry to the title menu, next to NEW GAME:
--   NEW GAME      -> the vanilla Oak intro / story
--   BYPASS INTRO  -> quick setup flow:
--       1. Name your player
--       2. Pick a starter (starters + legendaries)
--       3. Normal or shiny
--       4. Level (default 10, changeable)
-- Then you land straight in the overworld with your mon.
--
-- Requires engine_internals (Pokemon.new / Stats.calc for shiny DVs,
-- SaveData.newGame + overworld bootstrap for the skip).

local BYPASS_SCREEN = "IntroBypassFlow"

local STARTERS = {
  { id = "CHARMANDER", label = "CHARMANDER" },
  { id = "BULBASAUR", label = "BULBASAUR" },
  { id = "SQUIRTLE", label = "SQUIRTLE" },
  { id = "PIKACHU", label = "PIKACHU" },
  { id = "MEW", label = "MEW" },
  { id = "MEWTWO", label = "MEWTWO" },
  { id = "ARTICUNO", label = "ARTICUNO" },
  { id = "ZAPDOS", label = "ZAPDOS" },
  { id = "MOLTRES", label = "MOLTRES" },
}

-- Gen 2 shiny formula applied to Gen 1 DVs (Stats.isShiny): Defense/Speed/
-- Special DV == 10 and Attack DV in {2,3,6,7,10,11,14,15}.  All-10 works.
local SHINY_DVS = { attack = 10, defense = 10, speed = 10, special = 10, hp = 10 }

return function(mod)
  local Pokemon, Stats, SaveData, OverworldState, Screens, ModRuntime
  local gameRef

  mod.events:on("game.ready", function(payload)
    Pokemon = require("src.pokemon.Pokemon")
    Stats = require("src.pokemon.Stats")
    SaveData = require("src.core.SaveData")
    OverworldState = require("src.world.OverworldController")
    Screens = require("src.ui.Screens")
    ModRuntime = require("src.mods.Runtime")
    gameRef = payload and payload.game
  end)

  -- A NEW GAME that skips the Oak intro: same bootstrap as Game:makeTitleState
  -- onNewGame, but instead of pushing OakSpeech it pushes our setup flow.
  local function startBypass(game)
    game = game or gameRef
    if not (game and SaveData) then return end
    while game.stack:top() do game.stack:pop() end
    game.save = SaveData.newGame(game:bootConfig())
    game:adoptSave(game.save)
    ModRuntime.emit("save.created", { save = game.save })
    game:applyOptions(game.save.options)
    game.stack:push(OverworldState, game.save.player.map,
                    game.save.player.x, game.save.player.y,
                    game.save.player.facing)
    Screens.push(game, BYPASS_SCREEN, function() end)
  end

  -- Title menu: NEW GAME stays vanilla, BYPASS INTRO is an extra entry.
  mod.hooks:wrap("ui.title_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "NEW GAME", {
      label = "BYPASS INTRO",
      onSelect = function()
        startBypass(game)
      end,
    })
  end)

  -- The quick setup flow; a stub screen that drives the sub-screens
  -- (naming, starter, shiny, level) on top, then pops itself to reveal
  -- the overworld pushed underneath.
  mod.content.screens:register(BYPASS_SCREEN, {
    new = function(game, onDone)
      local stub = {
        isOpaque = true,
        update = function() end,
        draw = function() end,
      }

      local function finish()
        game.stack:pop() -- pop the stub
        if onDone then onDone() end
      end

      local function pickLevel(species, shiny)
        game.stack:push(mod.ui.QuantityBox.new(game, {
          max = 100,
          start = 10,
          onDone = function(level)
            if level then
              local mon = Pokemon.new(game.data, species, level)
              if shiny then
                mon.dvs = SHINY_DVS
                mon.stats = Stats.calc(game.data.pokemon[species], level,
                                       mon.dvs, mon.statExp)
                mon.hp = mon.stats.hp
              end
              game.save.party = { mon }
            end
            finish()
          end,
        }))
      end

      local function pickShiny(species)
        game.stack:push(mod.ui.Menu.new(game, {
          { label = "NORMAL", onSelect = function() pickLevel(species, false) end },
          { label = "SHINY", onSelect = function() pickLevel(species, true) end },
        }, { cancelable = false }))
      end

      local function pickStarter()
        local items = {}
        for _, s in ipairs(STARTERS) do
          items[#items + 1] = { label = s.label, value = s.id }
        end
        game.stack:push(mod.ui.ListMenu.new(game, "CHOOSE STARTER", items, {
          pageJump = true,
          onChoose = function(item, menu)
            menu:close()
            pickShiny(item.value)
          end,
        }))
      end

      stub.enter = function(self)
        game.stack:push(mod.ui.NamingScreen.new(game, {
          title = "YOUR NAME?",
          presets = { "RED", "ASH", "JACK" },
          maxLen = 7,
          onDone = function(name)
            game.save.player.name = name
            pickStarter()
          end,
        }))
      end

      return stub
    end,
  })

  mod.log:info("intro_bypass loaded (BYPASS INTRO added to the title menu)")
end