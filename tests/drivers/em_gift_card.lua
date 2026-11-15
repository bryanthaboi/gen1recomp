local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_gift_card", "/tmp/em_gift_card")
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
  if not check(type(raw) == "string", "identity has an Emerald save") then return finish() end
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
  local MysteryGift = require("src.core.game3.mystery_gift")
  local EI = require("src.core.game3.rse.event_islands")
  local Bag = require("src.core.game3.bag")
  session = Runtime.getSession()
  Natives.ensureBound(session)
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end

  check(MysteryGift.familyOf(session) == "rse", "the live session is rse")
  check(not EI.enabled(session), "the EVENT TICKETS option stays off; only the Wonder Card delivers")

  local C = require("src.core.game3.constants").of("emerald")
  local function item(name) return C:require("items", name) end
  for _, name in ipairs({ "ITEM_EON_TICKET", "ITEM_AURORA_TICKET", "ITEM_MYSTIC_TICKET", "ITEM_OLD_SEA_MAP" }) do
    while Bag.has(session.bag, item(name), 1) do Bag.remove(session.bag, item(name), 1) end
  end
  for _, f in ipairs({ "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND", "FLAG_ENABLE_SHIP_BIRTH_ISLAND", "FLAG_ENABLE_SHIP_NAVEL_ROCK",
    "FLAG_ENABLE_SHIP_FARAWAY_ISLAND", "FLAG_RECEIVED_AURORA_TICKET", "FLAG_RECEIVED_MYSTIC_TICKET",
    "FLAG_RECEIVED_OLD_SEA_MAP", "FLAG_BATTLED_DEOXYS", "FLAG_CAUGHT_MEW", "FLAG_CAUGHT_LUGIA", "FLAG_CAUGHT_HO_OH" }) do
    S.setFlag(f, false)
  end
  S.setVar("VAR_DISTRIBUTE_EON_TICKET", 0)

  local function preset(key)
    for _, e in ipairs(require("tests.fixtures.game3_gift_cards").cards("rse")) do
      if e.key == key then return MysteryGift.normalizeCard(e.card, "emerald") end
    end
  end

  local pagesSeen = {}
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

  local function talkToMan(label)
    if not teleport("EM_LILYCOVE_CITY_POKEMON_CENTER_2F", 1, 6, "up") then return false end
    local man = S.objectByScript("CableClub_EventScript_MysteryGiftMan")
    if not check(man ~= nil and not man.hidden, label .. ": the Mystery Gift man stands in the 2F") then return false end
    S.goTo(game, { man.cellX, man.cellY + 2 })
    S.face(game, "up")
    U.tap(game, "a")
    U.wait(10)
    local shotTaken = false
    local Message = require("src.ui.game3.message")
    pagesSeen = {}
    S.settle(game, { limit = 4000, watch = function()
      if Message.isOpen() then
        local page = Message.currentPage()
        if type(page) ~= "string" then page = table.concat(type(page) == "table" and page or {}, " ") end
        if pagesSeen[#pagesSeen] ~= page then pagesSeen[#pagesSeen + 1] = page end
      end
      if not shotTaken and Message.isOpen() then
        shotTaken = true
        U.wait(20)
        shot(label)
      end
    end })
    return true
  end
  local function saw(fragment)
    for _, p in ipairs(pagesSeen) do
      if tostring(p):gsub("%s+", " "):find(fragment, 1, true) then return true end
    end
    note("pages: " .. table.concat(pagesSeen, " | "):gsub("\n", " "))
    return false
  end

  local cases = {
    { key = "rse_aurora_ticket", item = "ITEM_AURORA_TICKET", flags = { "FLAG_ENABLE_SHIP_BIRTH_ISLAND", "FLAG_RECEIVED_AURORA_TICKET" } },
    { key = "rse_mystic_ticket", item = "ITEM_MYSTIC_TICKET", flags = { "FLAG_ENABLE_SHIP_NAVEL_ROCK", "FLAG_RECEIVED_MYSTIC_TICKET" } },
    { key = "rse_old_sea_map", item = "ITEM_OLD_SEA_MAP", flags = { "FLAG_ENABLE_SHIP_FARAWAY_ISLAND", "FLAG_RECEIVED_OLD_SEA_MAP" } },
    { key = "rse_eon_ticket", item = "ITEM_EON_TICKET", flags = { "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND" } },
  }
  for i, c in ipairs(cases) do
    check(MysteryGift.receiveCard(session, preset(c.key)), c.key .. ": the Wonder Card saves")
    if c.key == "rse_eon_ticket" then
      check(S.var("VAR_DISTRIBUTE_EON_TICKET") == 1, "eon_ticket: VAR_DISTRIBUTE_EON_TICKET raised")
    else
      check(EI.cardGift(session) ~= nil, c.key .. ": the card maps to its ROM ramscript")
    end
    if talkToMan(string.format("%02d_%s", i, c.key)) then
      check(Bag.has(session.bag, item(c.item), 1), c.key .. ": the man hands over " .. c.item)
      for _, f in ipairs(c.flags) do check(S.flag(f), c.key .. ": " .. f .. " set") end
    end
  end
  check(S.var("VAR_DISTRIBUTE_EON_TICKET") == 0, "the eon distribution script clears VAR_DISTRIBUTE_EON_TICKET")

  while #session.party > 5 do table.remove(session.party) end
  S.setFlag("FLAG_MYSTERY_GIFT_DONE", false)
  local before = #session.party
  check(MysteryGift.receiveCard(session, preset("rse_surf_pichu")), "surf_pichu: the Wonder Card saves")
  check(EI.cardGift(session) and EI.cardGift(session).id == "surfPichu", "surf_pichu: the card maps to its ROM ramscript")
  if talkToMan("10_rse_surf_pichu") then
    local mon = session.party[before + 1]
    check(#session.party == before + 1, "surf_pichu: the ROM script gives one egg")
    check(mon and mon.species == C:require("species", "SPECIES_PICHU") and (mon.isEgg or mon.egg),
      "surf_pichu: the egg is a Pichu egg")
    check(mon and mon.moves and mon.moves[3] == C:require("moves", "MOVE_SURF"), "surf_pichu: slot 3 holds SURF")
    check(S.flag("FLAG_MYSTERY_GIFT_DONE"), "surf_pichu: FLAG_MYSTERY_GIFT_DONE set")
    check(saw("POKéMON EGG") or saw("POKeMON EGG") or saw("EGG"), "surf_pichu: sText_MysteryGiftEgg shown")
  end
  if talkToMan("11_rse_surf_pichu_again") then
    check(#session.party == before + 1, "surf_pichu: a second visit gives nothing")
    check(saw("MYSTERY GIFT"), "surf_pichu: returnram falls through to the thank-you text")
  end

  S.setFlag("FLAG_MYSTERY_GIFT_DONE", false)
  check(MysteryGift.receiveCard(session, preset("rse_battle_card")), "battle_card: the Wonder Card saves")
  check(EI.cardGift(session) and EI.cardGift(session).id == "battleCard", "battle_card: the card maps to its ROM ramscript")
  local potion = item("ITEM_POTION")
  local function potions() return tonumber(Bag.get(session.bag, potion)) or 0 end
  local p0 = potions()
  if talkToMan("12_rse_battle_card_info") then
    check(potions() == p0, "battle_card: under three wins gives nothing")
    check(saw("BATTLE COUNT CARD"), "battle_card: sText_MysteryGiftBattleCountCard shown")
  end
  MysteryGift.ensure(session).cardMetadata.battlesWon = 3
  if talkToMan("13_rse_battle_card_prize") then
    check(potions() > p0, "battle_card: three wins gives the POTION")
    check(S.flag("FLAG_MYSTERY_GIFT_DONE"), "battle_card: FLAG_MYSTERY_GIFT_DONE set")
    check(saw("three battles"), "battle_card: sText_MysteryGiftBattleCountCard_WonPrize shown")
  end

  check(MysteryGift.receiveCard(session, preset("rse_stamp_card")), "stamp_card: the Wonder Card saves")
  check(EI.cardGift(session) and EI.cardGift(session).id == "stampCard", "stamp_card: the card maps to its ROM ramscript")
  if talkToMan("14_rse_stamp_card") then
    local left = MysteryGift.getCardStat(session, MysteryGift.CARD_STAT_MAX_STAMPS)
      - MysteryGift.getCardStat(session, MysteryGift.CARD_STAT_NUM_STAMPS)
    check(saw("You have " .. left .. " more to collect"), "stamp_card: STR_VAR_1 is the stamps left (" .. left .. ")")
  end

  S.setVar("VAR_ALTERING_CAVE_WILD_SET", 8)
  check(MysteryGift.receiveCard(session, preset("rse_altering_cave")), "altering_cave: the Wonder Card saves")
  check(EI.cardGift(session) and EI.cardGift(session).id == "alteringCave", "altering_cave: the card maps to its ROM ramscript")
  if talkToMan("15_rse_altering_cave") then
    check(S.var("VAR_ALTERING_CAVE_WILD_SET") == 9, "altering_cave: the ROM script steps the wild set to 9")
    check(saw("ALTERING CAVE"), "altering_cave: sText_MysteryGiftAlteringCave shown")
  end
  if talkToMan("16_rse_altering_cave_wrap") then
    check(S.var("VAR_ALTERING_CAVE_WILD_SET") == 0, "altering_cave: the ROM script wraps past the last table")
  end
  return finish()
end
