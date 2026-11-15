local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_event_islands", "/tmp/em_event_islands")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has the post-Hall-of-Fame save") then return finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Natives = require("src.core.game3.scripting.natives")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  session = Runtime.getSession()
  Natives.ensureBound(session)
  require("tests.drivers.em_f4_hooks").install()
  local EI = require("src.core.game3.rse.event_islands")
  check(Natives.handlerFor("DoDeoxysRockInteraction") ~= nil and Natives.handlerFor("SetDeoxysRockPalette") ~= nil,
    "DoDeoxysRockInteraction / SetDeoxysRockPalette bound on Emerald")
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end

  local D = require("src.core.game3.rse.frontier.trainers")
  local function tough(name, moves)
    local m = D.createMon(S.species(name), 70, 31, 0, tonumber(session.trainerId) or 0, { otName = session.name })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_SHADOW_BALL" }),
    tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    tough("SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }),
  }

  local function teleport(mapId, x, y, facing)
    S.settle(game)
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    if not ok then note("Map.load " .. mapId .. ": " .. tostring(err)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    U.wait(30)
    S.settle(game)
    return ok
  end

  check(not EI.enabled(session), "event tickets start OFF")
  local row = EI.optionRow()
  row.step({ options = game.options, session = session })
  check(EI.enabled(session), "the EVENT TICKETS option row turns the distribution on")
  check(EI.pendingGift(session) == nil, "no ticket is handed out until the relay publishes one")
  local feedCards = {}
  for _, b in ipairs(require("tests.fixtures.game3_gift_cards").cards("rse")) do
    feedCards[#feedCards + 1] = { key = b.key, card = b.card }
  end
  EI.applyFeed(session, { cards = feedCards })
  EI.sync(session, { offline = true })
  check(S.var("VAR_DISTRIBUTE_EON_TICKET") == 1, "VAR_DISTRIBUTE_EON_TICKET raised for the Mystery Gift man")

  if not check(teleport("EM_LILYCOVE_CITY_POKEMON_CENTER_2F", 1, 6, "up"), "Lilycove Pokemon Center 2F loads") then
    return finish()
  end
  local man = S.objectByScript("CableClub_EventScript_MysteryGiftMan")
  if not check(man ~= nil and not man.hidden, "the Mystery Gift man stands in the 2F (CableClub_OnTransition)") then
    return finish()
  end
  shot("01_mystery_gift_man")
  local tickets = { "ITEM_EON_TICKET", "ITEM_AURORA_TICKET", "ITEM_MYSTIC_TICKET", "ITEM_OLD_SEA_MAP" }
  for i, t in ipairs(tickets) do
    man = S.objectByScript("CableClub_EventScript_MysteryGiftMan")
    S.goTo(game, { man.cellX, man.cellY + 2 })
    S.face(game, "up")
    U.tap(game, "a")
    U.wait(10)
    local shotTaken = false
    S.settle(game, { limit = 4000, watch = function()
      if i == 2 and not shotTaken and require("src.ui.game3.message").isOpen() then
        shotTaken = true
        U.wait(20)
        shot("02_wonder_card_ticket")
      end
    end })
    check(S.hasItem(t), "talk " .. i .. " delivers " .. t)
  end
  check(S.flag("FLAG_ENABLE_SHIP_SOUTHERN_ISLAND") and S.flag("FLAG_ENABLE_SHIP_BIRTH_ISLAND")
    and S.flag("FLAG_ENABLE_SHIP_NAVEL_ROCK") and S.flag("FLAG_ENABLE_SHIP_FARAWAY_ISLAND"),
    "all four FLAG_ENABLE_SHIP_* flags set by the ticket scripts")
  check(EI.pendingGift(session) == nil, "no wonder card left to deliver")

  local function ferryOnce(dest, arrive)
    teleport("EM_LILYCOVE_CITY_HARBOR", 8, 12, "up")
    local attendant = S.objectByScript("LilycoveCity_Harbor_EventScript_FerryAttendant")
    if not attendant then return false end
    S.talkTo(game, attendant)
    local listed = false
    S.settle(game, { limit = 20000, until_ = function() return S.mapNow() == arrive end,
      choice = function(ch)
        local labels = {}
        for _, o in ipairs(ch.options or {}) do labels[#labels + 1] = tostring(type(o) == "table" and (o.text or o.label or o[1]) or o) end
        note("ferry choice: " .. table.concat(labels, " | "))
        for idx, o in ipairs(ch.options or {}) do
          local t = tostring(type(o) == "table" and (o.text or o.label or o[1]) or o)
          if t:upper():find(dest, 1, true) then
            listed = true
            return idx
          end
        end
        return "yes"
      end })
    note("ferry to " .. dest .. ": listed=" .. tostring(listed) .. " map=" .. tostring(S.mapNow()))
    return listed and S.mapNow() == arrive
  end
  local function ferry(dest, arrive)
    for _ = 1, 3 do
      if ferryOnce(dest, arrive) then return true end
    end
    return false
  end

  if check(ferry("SOUTHERN", "EM_SOUTHERN_ISLAND_EXTERIOR"), "the S.S. Tidal sails to SOUTHERN ISLAND with the EON TICKET") then
    shot("03_southern_island")
    S.travel(game, { "EM_SOUTHERN_ISLAND_INTERIOR" }, { repel = false, settle = { limit = 4000 } })
    if check(S.mapNow() == "EM_SOUTHERN_ISLAND_INTERIOR", "walked into the Southern Island interior") then
      S.goTo(game, { 13, 12 })
      S.face(game, "up")
      U.tap(game, "a")
      local sawBattle = false
      S.settle(game, { limit = 20000, onBattleStart = function(st)
        sawBattle = true
        local foe = st.enemy and st.enemy.mon
        check(foe and (foe.species == S.species("SPECIES_LATIAS") or foe.species == S.species("SPECIES_LATIOS")),
          "the Lati at the rock is Latias or Latios (" .. tostring(foe and foe.species) .. ")")
        S.pendingBattleShot = "04_lati_battle"
      end })
      check(sawBattle, "BattleSetup_StartLatiBattle starts the Lati battle")
      check(S.flag("FLAG_DEFEATED_LATIAS_OR_LATIOS") or S.flag("FLAG_CAUGHT_LATIAS_OR_LATIOS"),
        "the Southern Island Lati is resolved")
    end
  end

  if check(ferry("BIRTH", "EM_BIRTH_ISLAND_HARBOR"), "the S.S. Tidal sails to BIRTH ISLAND with the AURORA TICKET") then
    S.travel(game, { "EM_BIRTH_ISLAND_EXTERIOR" }, { repel = false, settle = { limit = 4000 } })
    if check(S.mapNow() == "EM_BIRTH_ISLAND_EXTERIOR", "walked onto Birth Island") then
      shot("05_birth_island")
      local moves, sawDeoxys = 0, false
      local lastResult
      local coords = EI.manifest().deoxysRockCoords
      for touch = 1, 13 do
        local rock = Objects.find(EI.LOCALID_ROCK)
        if not rock or rock.hidden then break end
        local level = S.var("VAR_DEOXYS_ROCK_LEVEL")
        local nxt = coords[math.min(level + 2, #coords)]
        local best, bestCost
        for _, dlt in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }) do
          local tx, ty = rock.cellX + dlt[1], rock.cellY + dlt[2]
          local cost = (math.abs(tx - Player.cellX) + math.abs(ty - Player.cellY)) * 100 + math.abs(tx - nxt[1]) + math.abs(ty - nxt[2])
          if not bestCost or cost < bestCost then best, bestCost = { tx, ty, dlt[3] }, cost end
        end
        S.goTo(game, { best[1], best[2] })
        S.face(game, best[3])
        U.tap(game, "a")
        U.wait(10)
        S.settle(game, { limit = 20000, onBattleStart = function(st)
          sawDeoxys = true
          local foe = st.enemy and st.enemy.mon
          check(foe and foe.species == S.species("SPECIES_DEOXYS"), "the triangle summons Deoxys")
          S.pendingBattleShot = "07_deoxys_battle"
        end })
        lastResult = require("src.core.game3.scripting.natives_event_islands").lastResult
        if lastResult == EI.ROCK.PROGRESSED then moves = moves + 1 end
        note(string.format("touch %d result %s level %d rock %d,%d player %d,%d steps %d", touch, tostring(lastResult),
          S.var("VAR_DEOXYS_ROCK_LEVEL"), rock.cellX, rock.cellY, Player.cellX, Player.cellY, S.var("VAR_DEOXYS_ROCK_STEP_COUNT")))
        require("src.core.game3.scripting.natives_event_islands").lastResult = nil
        if touch == 4 then shot("06_triangle_level_" .. S.var("VAR_DEOXYS_ROCK_LEVEL")) end
        if sawDeoxys then break end
      end
      check(moves == 10, "the triangle moved ten times (" .. moves .. ")")
      check(sawDeoxys, "solving the triangle starts the Deoxys battle")
      check(S.flag("FLAG_BATTLED_DEOXYS") or S.flag("FLAG_DEFEATED_DEOXYS"), "Deoxys resolved")
    end
  end

  if check(ferry("NAVEL", "EM_NAVEL_ROCK_HARBOR"), "the S.S. Tidal sails to NAVEL ROCK with the MYSTIC TICKET") then
    shot("08_navel_rock")
    teleport("EM_NAVEL_ROCK_TOP", 13, 19, "up")
    local sawHoOh = false
    S.goTo(game, { 12, 11 })
    S.step(game, "up")
    S.settle(game, { limit = 20000, onBattleStart = function(st)
      local foe = st.enemy and st.enemy.mon
      sawHoOh = foe and foe.species == S.species("SPECIES_HO_OH")
      S.pendingBattleShot = "09_ho_oh_battle"
    end })
    check(sawHoOh, "the Navel Rock summit coord event starts the Ho-Oh battle")
    teleport("EM_NAVEL_ROCK_BOTTOM", 14, 18, "up")
    note("after bottom teleport: map " .. tostring(S.mapNow()) .. " player " .. Player.cellX .. "," .. Player.cellY)
    local lugia = S.objectByScript("NavelRock_Bottom_EventScript_Lugia") or Objects.find(1)
    local sawLugia = false
    note("lugia " .. tostring(lugia and lugia.cellX) .. "," .. tostring(lugia and lugia.cellY) .. " hidden=" .. tostring(lugia and lugia.hidden))
    if lugia then
      teleport("EM_NAVEL_ROCK_BOTTOM", lugia.cellX, lugia.cellY + 1, "up")
      lugia = S.objectByScript("NavelRock_Bottom_EventScript_Lugia") or Objects.find(1)
      S.face(game, "up")
      note("at lugia: map " .. tostring(S.mapNow()) .. " player " .. Player.cellX .. "," .. Player.cellY .. " facing " .. tostring(Player.facing))
      U.tap(game, "a")
      U.wait(10)
      S.settle(game, { limit = 20000, onBattleStart = function(st)
        local foe = st.enemy and st.enemy.mon
        sawLugia = foe and foe.species == S.species("SPECIES_LUGIA")
        S.pendingBattleShot = "10_lugia_battle"
      end })
    end
    check(sawLugia, "Lugia waits at the bottom of Navel Rock")
  end

  if check(ferry("FARAWAY", "EM_FARAWAY_ISLAND_ENTRANCE"), "the S.S. Tidal sails to FARAWAY ISLAND with the OLD SEA MAP") then
    S.travel(game, { "EM_FARAWAY_ISLAND_INTERIOR" }, { repel = false, settle = { limit = 4000 } })
    check(S.mapNow() == "EM_FARAWAY_ISLAND_INTERIOR", "walked into Faraway Island")
    local mew = S.objectByScript("FarawayIsland_Interior_EventScript_Mew") or Objects.find(1)
    check(mew ~= nil, "Mew is on Faraway Island")
    shot("11_faraway_island")
  end

  note("player at " .. tostring(S.mapNow()) .. " " .. Player.cellX .. "," .. Player.cellY)
  finish()
end
