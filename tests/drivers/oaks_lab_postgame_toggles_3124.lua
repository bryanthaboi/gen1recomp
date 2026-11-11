-- scripts/OaksLab.asm:72-75, :480, :635, :965-975
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local GameVersion = require("src.core.GameVersion")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/3124"
  local yellow = GameVersion.isYellow()
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[3124] " .. (cond and "PASS " or "FAIL ") .. line)
  end
  local function finish()
    print("[3124] " .. (fails == 0 and "ALL PASS" or (fails .. " FAILURES")))
    love.event.quit(fails == 0 and 0 or 1)
    while true do coroutine.yield() end
  end
  local function shown(name)
    for _, n in ipairs(game.overworld and game.overworld.npcs or {}) do
      if n.def and n.def.name == name then return true end
    end
    return false
  end
  local function idle()
    local ow = game.overworld
    if not ow or game.stack:top() ~= ow then return false end
    if ow.runner and ow.runner:isRunning() then return false end
    if ow.scriptMoves and #ow.scriptMoves > 0 then return false end
    if ow.emote or ow.transitioning or ow.pendingScript then return false end
    if ow.player.moving then return false end
    return true
  end

  local lastText
  local origNew = TextBox.new
  TextBox.new = function(g, text, ...)
    lastText = text
    return origNew(g, text, ...)
  end

  local save = game.save
  save.player.name = (save.player.name and save.player.name ~= "") and save.player.name or "RED"
  local starter = yellow and "PIKACHU" or "SQUIRTLE"
  save.party = { Pokemon.new(game.data, starter, 50) }
  save.pokedex = save.pokedex or {}
  save.pokedex.owned = { [starter] = true, PIDGEY = true, RATTATA = true }
  save.pokedex.seen = { [starter] = true, PIDGEY = true, RATTATA = true }
  local f = save.flags
  for k in pairs(f) do f[k] = nil end
  for _, k in ipairs({ "EVENT_FOLLOWED_OAK_INTO_LAB", "EVENT_FOLLOWED_OAK_INTO_LAB_2",
                       "EVENT_OAK_ASKED_TO_CHOOSE_MON", "EVENT_GOT_STARTER",
                       "EVENT_BATTLED_RIVAL_IN_OAKS_LAB", "EVENT_GOT_OAKS_PARCEL",
                       "EVENT_OAK_GOT_PARCEL", "EVENT_GOT_POKEDEX",
                       "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE", "EVENT_GOT_POKEBALLS_FROM_OAK",
                       "EVENT_BEAT_CHAMPION_RIVAL" }) do
    f[k] = true
  end
  if yellow then
    f.EVENT_CHOSE_PIKACHU = true
    save.pikachuInBall = true
  else
    f.EVENT_CHOSE_SQUIRTLE = true
  end
  save.objectToggles = { OAKS_LAB = {
    OAKSLAB_RIVAL = true, OAKSLAB_OAK1 = false, OAKSLAB_OAK2 = true,
    OAKSLAB_POKEDEX1 = false, OAKSLAB_POKEDEX2 = false,
  } }
  local balls = yellow and { "OAKSLAB_EEVEE_POKE_BALL" }
    or { "OAKSLAB_CHARMANDER_POKE_BALL", "OAKSLAB_SQUIRTLE_POKE_BALL", "OAKSLAB_BULBASAUR_POKE_BALL" }
  for _, b in ipairs(balls) do save.objectToggles.OAKS_LAB[b] = yellow end

  U.teleport(game, "PALLET_TOWN", 12, 12, "up")
  U.wait(20)
  for _ = 1, 600 do
    if game.overworld and game.overworld.map.id == "OAKS_LAB" then break end
    U.hold(game, "up", 4)
  end
  ok(game.overworld and game.overworld.map.id == "OAKS_LAB", "walked through the door into OAKS_LAB")
  for _ = 1, 600 do
    if idle() then break end
    U.wait(1)
  end
  local t = save.objectToggles.OAKS_LAB
  ok(t.OAKSLAB_OAK1 == true and t.OAKSLAB_OAK2 == false, "toggles: OAK1 shown, OAK2 hidden")
  ok(t.OAKSLAB_RIVAL == false, "toggles: RIVAL hidden")
  if yellow then
    ok(t.OAKSLAB_EEVEE_POKE_BALL == false, "toggles: EEVEE ball hidden")
  else
    ok(t.OAKSLAB_SQUIRTLE_POKE_BALL == false and t.OAKSLAB_BULBASAUR_POKE_BALL == false,
       "toggles: player and rival balls hidden")
    ok(t.OAKSLAB_CHARMANDER_POKE_BALL == true, "toggles: third ball back on the table")
  end
  ok(shown("OAKSLAB_OAK1"), "Oak at his desk on entry")
  ok(not shown("OAKSLAB_OAK2"), "no door Oak on entry")
  ok(not shown("OAKSLAB_RIVAL"), "no rival on entry")

  for _ = 1, 120 do
    local p = game.overworld.player
    if p.cellY <= 3 and not p.moving then break end
    U.hold(game, "up", 4)
  end
  for _ = 1, 60 do
    if idle() then break end
    U.wait(1)
  end
  local p = game.overworld.player
  ok(p.cellX == 5 and p.cellY == 3, "player below Oak at (5,3), at " .. p.cellX .. "," .. p.cellY)
  ok(U.shot(game, DIR .. "/3124_01_oak_at_desk_no_rival.png"), "lab shot written")
  lastText = nil
  U.tap(game, "a")
  for _ = 1, 120 do
    if lastText then break end
    U.wait(1)
  end
  local want = game.data.text._OaksLabOak1HowIsYourPokedexComingText
  ok(want ~= nil and lastText == want, "Oak opens with the Pokedex rating")
  for _ = 1, 200 do
    if idle() then break end
    U.tap(game, "a")
    U.wait(2)
  end
  TextBox.new = origNew
  finish()
end
