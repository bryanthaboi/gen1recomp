local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_spinda_unown_dex"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_spinda_unown_dex")
    love.event.quit(0)
  else
    print("FAIL game3_spinda_unown_dex failures=" .. failures)
    love.event.quit(1)
  end
end

local SPINDA, UNOWN = 308, 201
local P_A, P_B = 0x12345678, 0xFEDCBA98
local P_UNOWN_D = 0xFC000003

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Pokemon = require("src.core.game3.pokemon")
  local Party = require("src.core.game3.party")
  local Dex = require("src.core.game3.dex")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local Pokedex = require("src.ui.game3.pokedex")
  local FieldEffects = require("src.core.game3.field_effects")
  local BattleChrome = require("src.ui.game3.battle_chrome")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return end
  session.party = {}
  Party.giveMon(session, 6, 50)

  local rgbaA, rgbaB = Pokemon.spindaRgba(P_A, false), Pokemon.spindaRgba(P_B, false)
  result(rgbaA and rgbaB and #rgbaA == 64 * 64 * 4 and rgbaA ~= rgbaB,
    "two Spinda personalities bake different spot patterns")
  result(FieldEffects.loadSheet("ss_anne_wake", 16, 32, 2) ~= nil
    and FieldEffects.loadSheet("ss_anne_smoke", 16, 16, 4) ~= nil, "SS Anne wake/smoke sheets come from the cache")
  result(BattleChrome.hasHpBoldDigits(), "bold HP digits come from the cache")

  local function wildBattle(species, personality, shotName)
    local ok, err = BattleBridge.startWild(Runtime._mod, game,
      { species = species, level = 10, personality = personality }, { fade = false })
    if not result(ok == true, "wild battle started " .. tostring(err or "")) then return nil end
    local ready = false
    for _ = 1, 3000 do
      if Ui._mode == "menu" and not Anim.busy() then ready = true break end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
    result(ready, "battle reached the action menu")
    U.wait(20)
    local st = Battle._st
    local enemy = st and st.enemy
    local entry = Ui.battlerPic("enemy", enemy)
    local want = Pokemon.frontPic(Pokemon.picSpecies(species, personality), 0,
      Pokemon.isShiny(enemy and enemy.mon), personality)
    result(enemy and enemy.mon and enemy.mon.personality == personality,
      string.format("foe personality is 0x%08X", personality))
    result(entry and want and entry.image == want.image,
      string.format("battle foe pic is the personality 0x%08X pic", personality))
    if shotName then U.shot(game, DIR .. "/" .. shotName) end
    BattleBridge.finishPending("run")
    U.wait(40)
    return entry
  end

  local eA = wildBattle(SPINDA, P_A, "r3_spinda_battle_12345678.png")
  local eB = wildBattle(SPINDA, P_B, "r3_spinda_battle_FEDCBA98.png")
  result(eA and eB and eA.image ~= eB.image, "battle Spinda pics differ between personalities")
  result(session.dex.spindaPersonality == P_A,
    "pokedex keeps the first-seen Spinda personality (pokemon.c:6243)")

  wildBattle(UNOWN, P_UNOWN_D, nil)
  result(session.dex.unownPersonality == P_UNOWN_D, "pokedex records the first-seen Unown personality")

  session.party = {}
  Party.giveMon(session, SPINDA, 20)
  Party.giveMon(session, SPINDA, 20)
  session.party[1].personality, session.party[1].isShiny = P_A, nil
  session.party[2].personality, session.party[2].isShiny = P_B, nil
  local sA, sB = Pokemon.monFrontPic(session.party[1]), Pokemon.monFrontPic(session.party[2])
  result(sA and sB and sA.image ~= sB.image, "summary Spinda pics differ between personalities")
  result(sA and eA and sA.image == eA.image, "summary and battle share the personality 0x12345678 pic")

  SummaryMenu.openMenu(session.party, 1, { session = session })
  U.wait(90)
  U.shot(game, DIR .. "/r3_spinda_summary_12345678.png")
  SummaryMenu.close()
  U.wait(20)
  SummaryMenu.openMenu(session.party, 2, { session = session })
  U.wait(90)
  U.shot(game, DIR .. "/r3_spinda_summary_FEDCBA98.png")
  SummaryMenu.close()
  U.wait(20)

  local dexPic = Pokemon.dexFrontPic(UNOWN, Dex.defaultPersonality(session.dex, UNOWN))
  local unownD = Pokemon.frontPic(415)
  local unownA = Pokemon.frontPic(UNOWN)
  result(dexPic and unownD and dexPic.image == unownD.image and dexPic.image ~= unownA.image,
    "pokedex Unown pic is the recorded letter D")
  Pokedex.show(session.dex, { session = session, mode = "national" })
  U.wait(20)
  Pokedex.selectedSpecies = UNOWN
  Pokedex.screen = "data"
  Pokedex.dataPage = 1
  Pokedex.page = "entry"
  U.wait(30)
  result(Pokedex.screen == "data", "dex entry page open on UNOWN")
  U.shot(game, DIR .. "/r3_dex_unown_d_entry.png")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local PokedexData = require("src.core.game3.pokedex_data")
  local drawn = {}
  local realDraw = FrlgFont.draw
  FrlgFont.draw = function(text, ...)
    drawn[#drawn + 1] = tostring(text)
    return realDraw(text, ...)
  end
  local function pageShows(needle)
    for _, s in ipairs(drawn) do
      if s:find(needle, 1, true) then return true end
    end
    return false
  end
  local function showEntry(sp, shotName)
    Pokedex.selectedSpecies = sp
    U.wait(10)
    drawn = {}
    U.wait(20)
    U.shot(game, DIR .. "/" .. shotName)
  end

  local MUDKIP = Pokemon.speciesFromNational(258)
  Party.giveMon(session, MUDKIP, 20)
  result(Dex.isCaught(session.dex, SPINDA) and Dex.isCaught(session.dex, MUDKIP), "Spinda and Mudkip are caught")
  local natList = PokedexData.getOrderList("numerical_national", session.dex)
  result(natList[327] == SPINDA and natList[258] == MUDKIP,
    "national list slot 327 is Spinda and slot 258 is Mudkip")

  showEntry(SPINDA, "r3_dex_spinda_entry.png")
  result(pageShows("№327"), "Spinda page shows No327")
  result(not pageShows("№308"), "Spinda page does not show the internal id 308")
  result(pageShows("SPOT PANDA POKéMON"), "Spinda page shows SPOT PANDA")
  result(pageShows("11.0 lbs."), "Spinda page shows 11.0 lbs")
  result(pageShows("No two SPINDA"), "Spinda page shows the Spinda flavor text")

  showEntry(MUDKIP, "r3_dex_mudkip_entry.png")
  result(pageShows("№258"), "Mudkip page shows No258")
  result(pageShows("MUD FISH POKéMON"), "Mudkip page shows MUD FISH")
  result(pageShows("16.8 lbs."), "Mudkip page shows 16.8 lbs")
  FrlgFont.draw = realDraw
  Pokedex.close()
  U.wait(10)
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver error: " .. tostring(err)) end
  finish()
end
