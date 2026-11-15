local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_harbor_event_tickets", "/tmp/em_harbor_event_tickets")

local TICKETS = { "ITEM_EON_TICKET", "ITEM_AURORA_TICKET", "ITEM_MYSTIC_TICKET", "ITEM_OLD_SEA_MAP" }
local SHIP_FLAGS = { "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND", "FLAG_ENABLE_SHIP_BIRTH_ISLAND",
  "FLAG_ENABLE_SHIP_NAVEL_ROCK", "FLAG_ENABLE_SHIP_FARAWAY_ISLAND" }
local SHOWN_FLAGS = { "FLAG_SHOWN_EON_TICKET", "FLAG_SHOWN_AURORA_TICKET", "FLAG_SHOWN_MYSTIC_TICKET",
  "FLAG_SHOWN_OLD_SEA_MAP" }
local DESTS = {
  { "SOUTHERN", "EM_SOUTHERN_ISLAND_EXTERIOR" },
  { "NAVEL", "EM_NAVEL_ROCK_HARBOR" },
  { "BIRTH", "EM_BIRTH_ISLAND_HARBOR" },
  { "FARAWAY", "EM_FARAWAY_ISLAND_ENTRANCE" },
}

local function label(o)
  return tostring(type(o) == "table" and (o.text or o.label or o[1]) or o)
end

local function labels(ch)
  local out = {}
  for _, o in ipairs(ch.options or {}) do out[#out + 1] = label(o):upper() end
  return out
end

local function has(list, word)
  for _, l in ipairs(list) do
    if l:find(word, 1, true) then return true end
  end
  return false
end

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local EI = require("src.core.game3.rse.event_islands")
    local Gift = require("src.core.game3.mystery_gift")
    S.setFlag("FLAG_SYS_GAME_CLEAR", true)
    S.setFlag("FLAG_MET_SCOTT_ON_SS_TIDAL", true)
    S.giveMon("SPECIES_SWAMPERT", 70, { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" })
    session.repelSteps = 0
    require("src.core.game3.encounters").onStep = function() return nil end

    EI.setEnabled(session, true)
    local feed = {}
    for _, b in ipairs(require("tests.fixtures.game3_gift_cards").cards("rse")) do feed[#feed + 1] = { key = b.key, card = b.card } end
    EI.applyFeed(session, { cards = feed })
    EI.sync(session, { offline = true })

    if not d.check(M.goTo(game, "EM_LILYCOVE_CITY_POKEMON_CENTER_2F", 1, 6, "up"), "Lilycove Pokemon Center 2F loads") then
      return d.finish()
    end
    for i, t in ipairs(TICKETS) do
      local man = S.objectByScript("CableClub_EventScript_MysteryGiftMan")
      if not d.check(man ~= nil, "Mystery Gift man present for talk " .. i) then return d.finish() end
      S.goTo(game, { man.cellX, man.cellY + 2 })
      S.face(game, "up")
      U.tap(game, "a")
      U.wait(10)
      S.settle(game, { limit = 4000 })
      d.check(S.hasItem(t), "delivery " .. i .. " gives " .. t)
    end
    for i, f in ipairs(SHIP_FLAGS) do
      d.check(S.flag(f), TICKETS[i] .. " delivery sets " .. f)
    end

    d.check(game:saveGame() ~= false, "game saved after the deliveries")
    local SaveData = require("src.core.SaveData")
    local Schema = require("src.core.game3.save_schema_firered")
    local saved = SaveData.load("emerald")
    if not d.check(type(saved) == "table", "save file written") then return d.finish() end
    local reloaded = Schema.fromSaveTable(saved)
    require("src.core.game3.options").bind(reloaded, game.options)
    game:adoptSave(reloaded, true)
    game:_enterField(reloaded, "continue")
    U.wait(30)
    S.settle(game)
    require("src.core.game3.scripting.natives").ensureBound(S.session())
    for i, f in ipairs(SHIP_FLAGS) do
      d.check(S.flag(f) and S.hasItem(TICKETS[i]), f .. " and " .. TICKETS[i] .. " survive save and continue")
    end

    local ListMenu = require("src.core.game3.scripting.natives_listmenu").Menu
    local lastScroll = false

    local function ferryMenu(pick, shotName)
      M.goTo(game, "EM_LILYCOVE_CITY_HARBOR", 8, 12, "up")
      local attendant = S.objectByScript("LilycoveCity_Harbor_EventScript_FerryAttendant")
      if not attendant then return nil end
      S.talkTo(game, attendant)
      local seen
      lastScroll = false
      local function capture(l)
        if not (has(l, "EXIT") and (has(l, "SOUTHERN") or has(l, "NAVEL") or has(l, "BIRTH") or has(l, "FARAWAY"))) then
          return nil
        end
        seen = l
        d.note("ferry menu: " .. table.concat(l, " | "))
        if shotName then
          U.wait(20)
          d.shot(game, shotName)
          shotName = nil
        end
        for idx, t in ipairs(l) do
          if t:find(pick.word, 1, true) then return idx end
        end
        return #l
      end
      local opts = { limit = 20000,
        choice = function(ch) return capture(labels(ch)) or "yes" end,
        watch = function()
          if not ListMenu.isOpen() then return false end
          local l = {}
          for i, t in ipairs(ListMenu.labels or {}) do l[i] = label(t):upper() end
          seen = nil
          local want = capture(l)
          if not want then return false end
          for _ = 1, 16 do
            local at = (ListMenu.scroll or 0) + (ListMenu.row or 1)
            if at == want then break end
            U.tap(game, at < want and "down" or "up")
            U.wait(4)
          end
          seen = l
          lastScroll = true
          U.tap(game, "a")
          U.wait(6)
          return true
        end }
      if pick.arrive then opts.until_ = function() return S.mapNow() == pick.arrive end end
      S.settle(game, opts)
      return seen
    end

    local none = ferryMenu({ word = "EXIT", arrive = "EM_FARAWAY_ISLAND_ENTRANCE" })
    d.check(none == nil and S.mapNow() == "EM_FARAWAY_ISLAND_ENTRANCE" and S.flag("FLAG_SHOWN_OLD_SEA_MAP"),
      "first talk runs the OLD SEA MAP showing straight to FARAWAY ISLAND (now " .. tostring(S.mapNow()) .. ")")

    local first = ferryMenu({ word = "EXIT" }, "01_first_time_tickets_menu")
    d.check(first and #first == 4 and has(first, "SOUTHERN") and has(first, "NAVEL") and has(first, "BIRTH"),
      "second talk lists the three unshown ticket islands plus EXIT")
    for i, f in ipairs(SHOWN_FLAGS) do d.check(S.flag(f), "showing sets " .. f .. " (" .. TICKETS[i] .. ")") end

    local regular = ferryMenu({ word = "EXIT" }, "02_regular_destination_menu")
    d.check(regular and #regular == 7 and has(regular, "SLATEPORT") and has(regular, "FRONTIER")
      and has(regular, "SOUTHERN") and has(regular, "NAVEL") and has(regular, "BIRTH") and has(regular, "FARAWAY"),
      "regular menu lists SLATEPORT, BATTLE FRONTIER, the four islands and EXIT")
    d.check(lastScroll, "the seven-row destination menu opens as the scrollable multichoice")

    for _, dest in ipairs(DESTS) do
      local arrived = false
      for _ = 1, 2 do
        ferryMenu({ word = dest[1], arrive = dest[2] })
        if S.mapNow() == dest[2] then arrived = true break end
      end
      d.check(arrived, "ferry to " .. dest[1] .. " lands on " .. dest[2] .. " (now " .. tostring(S.mapNow()) .. ")")
      if arrived then
        U.wait(30)
        d.shot(game, "03_arrived_" .. dest[1]:lower())
      end
    end
    d.finish()
  end, debug.traceback)
  if not ok then
    d.check(false, "driver error: " .. tostring(err))
    d.finish()
  end
end
