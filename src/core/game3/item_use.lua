-- FRLG field item-use handlers for game3 bag.

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Pokemon = require("src.core.game3.pokemon")
local ModRuntime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local Capabilities = require("src.core.game3.capabilities")

local ItemUse = {}

-- pokefirered/src/data/pokemon/item_effects.h:80
local HERB_HEAL = { [30] = 50, [31] = 200 }
local ITEM_REVIVAL_HERB = 33

-- pokefirered/src/data/pokemon/item_effects.h:81
local BITTER_MEDICINE_FRIENDSHIP = {
  [30] = { -5, -5, -10 },
  [31] = { -10, -10, -15 },
  [32] = { -5, -5, -10 },
  [33] = { -15, -15, -20 },
}
ItemUse.BITTER_MEDICINE_FRIENDSHIP = BITTER_MEDICINE_FRIENDSHIP
ItemUse.ITEM_REVIVAL_HERB = ITEM_REVIVAL_HERB

local function heal_amount(id)
  local n = ItemsData.HEAL_AMOUNT[id]
  if n then return n end
  local num = ItemsData.toNumericId(id) or tonumber(id)
  if num and HERB_HEAL[num] then return HERB_HEAL[num] end
  if num and ItemsData.HEAL_AMOUNT[num] then return ItemsData.HEAL_AMOUNT[num] end
  -- Pack holdEffectParam: Potion=20, Super=50, Hyper=200, Full Restore=255→full
  local info = ItemsData.info(id)
  local param = info and tonumber(info.holdEffectParam)
  if param and param > 0 then
    if param >= 255 then return 9999 end
    return param
  end
  return nil
end

local function mon_status(mon)
  if not mon then return nil, 0 end
  local st = mon.status
  local sleep = tonumber(mon.sleep) or 0
  if type(st) == "string" and st ~= "" and st ~= "0" then return st, sleep end
  local n = tonumber(st) or 0
  if n ~= 0 then return n, sleep end
  if sleep > 0 then return "SLP", sleep end
  return nil, 0
end

--- Apply heal to one party slot. Returns ok, restoredAmount
function ItemUse.healMon(session, mon, id)
  if not mon then return false, 0 end
  local kind = ItemsData.medicineKind(id)
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
  local hp = tonumber(mon.hp) or 0
  if maxHp <= 0 then return false, 0 end

  if kind == "full_restore" then
    if hp <= 0 then return false, 0 end
    local changed = false
    local restored = 0
    if hp < maxHp then
      restored = maxHp - hp
      mon.hp = maxHp
      changed = true
    end
    local st = mon_status(mon)
    if st then
      mon.status = nil
      mon.sleep = 0
      changed = true
    end
    return changed, restored
  end

  local amt = heal_amount(id)
  if not amt then return false, 0 end
  if hp <= 0 then return false, 0 end
  if hp >= maxHp then return false, 0 end
  local newHp
  if amt >= 9999 then
    newHp = maxHp
  else
    newHp = math.min(maxHp, hp + amt)
  end
  local restored = newHp - hp
  mon.hp = newHp
  return true, restored
end

-- pokefirered/include/constants/item_effects.h:20
local STATUS_BIT = {
  PSN = 0x10, TOX = 0x10, BRN = 0x08, FRZ = 0x04, SLP = 0x20, PAR = 0x02,
  [1] = 0x10, [2] = 0x10, [3] = 0x08, [4] = 0x04, [5] = 0x20, [6] = 0x02,
}
local CURED_TEXT_KIND = { [0x10] = "poison", [0x08] = "burn", [0x04] = "freeze", [0x20] = "sleep", [0x02] = "paralysis" }

-- pokefirered/src/pokemon.c:4511
function ItemUse.clearStatus(mon, id)
  if not mon then return false, nil end
  local st, sleep = mon_status(mon)
  if not st and sleep <= 0 then return false, nil end
  local info = ItemsData.info(id)
  local e = info and info.effect
  if type(e) ~= "table" then return false, nil end
  local mask = bit.band(tonumber(e[4]) or 0, 0x3E)
  local have = STATUS_BIT[st] or ((sleep > 0) and 0x20) or 0
  if bit.band(mask, have) == 0 then return false, nil end
  local cured = CURED_TEXT_KIND[mask] or "status"
  mon.status = nil
  mon.sleep = 0
  return true, cured
end

function ItemUse.revive(mon, max)
  if not mon then return false, 0 end
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
  local hp = tonumber(mon.hp) or 0
  if hp > 0 or maxHp <= 0 then return false, 0 end
  if max then
    mon.hp = maxHp
  else
    mon.hp = math.max(1, math.floor(maxHp / 2))
  end
  mon.status = nil
  mon.sleep = 0
  return true, mon.hp
end

function ItemUse.reviveAll(party)
  local any = false
  for _, mon in ipairs(party or {}) do
    if ItemUse.revive(mon, true) then any = true end
  end
  return any
end

-- pokefirered/src/party_menu.c:1647
local function bag_full_text(itemId)
  local pocket = ItemsData.pocketOf(itemId)
  local name
  if pocket == "TM_CASE" then
    name = ItemsData.displayName(ItemsData.ITEM_TM_CASE)
  elseif pocket == "BERRY_POUCH" then
    name = ItemsData.displayName(ItemsData.ITEM_BERRY_POUCH)
  else
    name = RomText.plain("gText_MenuBag")
  end
  return RomText.box("gText_BagFullCouldNotRemoveItem", { stringVars = { name } })
end

--- Give item to party mon as held item. Returns ok, reason, messageText.
function ItemUse.giveToMon(session, bag, id, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then return false, "noparty", Strings("There's no POKéMON!") end
  local pocket = ItemsData.pocketOf(id)
  if pocket == "KEY_ITEMS" or pocket == "TM_CASE" then
    return false, "cant_hold", Strings("This item can't be held.")
  end
  if not Bag.has(bag, id, 1) then
    return false, "none", Strings("You don't have that item.")
  end
  local prev = mon.item or mon.heldItem
  if prev and prev ~= 0 and prev ~= "" and prev ~= "NONE" then
    -- Swap: return previous to bag if possible
    if not Bag.canAdd(bag, prev, 1) then
      return false, "bag_full", bag_full_text(prev)
    end
  end
  Bag.remove(bag, id, 1)
  if prev and prev ~= 0 and prev ~= "" and prev ~= "NONE" then
    Bag.add(bag, prev, 1)
  end
  mon.item = ItemsData.toNumericId(id) or id
  mon.heldItem = mon.item
  local monName = Pokemon.displayMonName(mon)
  local text
  if prev and prev ~= 0 and prev ~= "" and prev ~= "NONE" then
    text = Strings("Took the %s and\ngave the %s to\n%s.", ItemsData.displayName(prev), ItemsData.displayName(id), monName)
  else
    text = Strings("%s was given\nto %s.", ItemsData.displayName(id), monName)
  end
  local Q=require("src.core.game3.quest_log_recorder")
  if prev and prev~=0 and prev~="" and prev~="NONE" then
    Q.event(session,"SwappedHeldItemsOnMon",{monName,ItemsData.displayName(prev),ItemsData.displayName(id)})
  else Q.event(session,"GaveMonHeldItem",{monName,ItemsData.displayName(id)}) end
  return true, "give", text
end

--- Take held item from party mon. Returns ok, reason, messageText.
function ItemUse.takeFromMon(session, bag, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then return false, "noparty", Strings("There's no POKéMON!") end
  local held = mon.item or mon.heldItem
  local monName = Pokemon.displayMonName(mon)
  if not held or held == 0 or held == "" or held == "NONE" then
    return false, "none", Strings("%s isn't\nholding anything.", monName)
  end
  if not Bag.canAdd(bag, held, 1) then
    return false, "bag_full", bag_full_text(held)
  end
  mon.item = nil
  mon.heldItem = nil
  Bag.add(bag, held, 1)
  local text = Strings("Took the %s from\n%s and put it in the BAG.", ItemsData.displayName(held), monName)
  require("src.core.game3.quest_log_recorder").event(session,"TookHeldItemFromMon",
    {monName,ItemsData.displayName(held)})
  return true, "take", text
end

-- pokefirered/include/global.fieldmap.h:191 gMapHeader
local function current_map_def(session)
  local mapId = session and session.map
  if type(mapId) ~= "string" then return nil end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local data = game and game.data and game.data.maps
  local def = data and data[mapId]
  if def then return def end
  local Map = package.loaded["src.core.game3.map"]
  local cur = Map and Map.currentDef and Map.currentDef()
  if type(cur) == "table" and cur.id == mapId then return cur end
  return nil
end

-- pokefirered/src/overworld.c:948 Overworld_IsBikingAllowed
local function map_header_flag(session, key)
  local def = current_map_def(session)
  if def == nil or def[key] == nil then return nil end
  return (tonumber(def[key]) or 0) ~= 0
end

local function is_outdoor(session)
  local mapId = session and session.map
  if type(mapId) ~= "string" then return false end
  local def = current_map_def(session)
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  if type(pair) == "string" and pair:find("outdoor", 1, true) then
    return true
  end
  -- Heuristic when layout pair missing
  if mapId:find("HOUSE", 1, true) or mapId:find("CENTER", 1, true)
      or mapId:find("GYM", 1, true) or mapId:find("MART", 1, true)
      or mapId:find("LAB", 1, true) or mapId:find("CAVE", 1, true)
      or mapId:find("TUNNEL", 1, true) or mapId:find("TOWER", 1, true)
      or mapId:find("MANSION", 1, true) then
    return false
  end
  if mapId:find("ROUTE", 1, true) or mapId:find("TOWN", 1, true)
      or mapId:find("CITY", 1, true) or mapId:find("ISLAND", 1, true) then
    return true
  end
  return false
end

-- pokefirered/src/item_use.c:614 CanUseEscapeRopeOnCurrMap
local function can_escape(session)
  if not session then return false end
  return map_header_flag(session, "allowEscaping") == true
end

function ItemUse.useEscapeRope(session, bag, id)
  if not can_escape(session) then
    return false, "escape", Strings("OAK: This isn't the\ntime to use that!")
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local mod = Runtime and Runtime._mod
  local game = Runtime and Runtime._game
  local Field = package.loaded["src.core.game3.field"]
  Bag.remove(bag, id, 1)
  local t = Strings("%s used\nESCAPE ROPE.", tostring(session.name or "RED"))
  local hx = session.healX or 8
  local hy = session.healY or 5
  local mapId = session.healMap or "FR_PLAYERS_HOUSE_1F"
  -- pokefirered/src/field_effect.c:2126 SetWarpDestinationToEscapeWarp
  local esc = session.escapeWarp
  if type(esc) == "table" and type(esc.map) == "string" then
    mapId = esc.map
    hx = tonumber(esc.x) or hx
    hy = tonumber(esc.y) or hy
  end
  local Warp = require("src.core.game3.warp")
  -- pokefirered/src/item_use.c:642 Task_UseDigEscapeRopeOnField
  local function leave()
    if mod and game then
      Warp.request(mod, game, mapId, hx, hy, "down", { fade = true })
    elseif Field and Field.respawnAtHeal then
      local Map = require("src.core.game3.map")
      Map.load(mod, game, mapId, { x = hx, y = hy, facing = "down" })
    end
  end
  -- pokefirered/src/item_use.c:634 ItemUseOnFieldCB_EscapeRope
  local function onField()
    local okM, Message = pcall(require, "src.ui.game3.message")
    if okM and Message and Message.show then
      -- pokefirered/src/new_menu_helpers.c:641 DisplayItemMessageOnField
      Message.show(t, { done = leave })
    else
      leave()
    end
  end
  -- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback
  if not ItemUse.setUpOnFieldCallback(onField) then onField() end
  return true, "escape", t
end

-- pokefirered/src/item_use.c:253 FieldUseFunc_Bike
function ItemUse.useBike(session)
  -- pokefirered/src/overworld.c:948 Overworld_IsBikingAllowed
  local biking = map_header_flag(session, "bikingAllowed")
  if biking == nil then biking = is_outdoor(session) end
  if not biking then
    local t = Strings("OAK: This isn't the\ntime to use that!")
    return false, "bike", t
  end
  local Player = require("src.core.game3.player")
  -- pokefirered/src/item_use.c:276 ItemUseOnFieldCB_Bicycle
  if not Player.biking then
    pcall(function()
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      if Audio and Audio.playSe then Audio.playSe(SE.SE_BIKE_BELL) end
    end)
  end
  Player.biking = not Player.biking
  require("src.core.game3.audio").bikeMusic(Player.biking)
  local t
  if Player.biking then
    t = Strings("%s got on the\nBICYCLE.", tostring(session.name or "RED"))
  else
    t = Strings("%s got off the\nBICYCLE.", tostring(session.name or "RED"))
  end
  return true, "bike", t
end

--- Check TM pre-flight compatibility and known moves matching retail FRLG.
-- Returns status ("knows" | "incompatible" | "ok"), messageText, moveId, moveName
function ItemUse.checkTmPreflight(mon, tmId)
  if not mon then return "none", Strings("There's no POKéMON!"), nil, nil end
  local moveId = Pokemon.moveFromTmItem(tmId)
  local monName = Pokemon.displayMonName(mon)
  local moveName = Pokemon.moveName(moveId) or "MOVE"
  if not moveId then
    return "invalid", Strings("This isn't the time to use\nthat!"), nil, nil
  end
  if Pokemon.knowsMove(mon, moveId) then
    return "knows", Strings("%s already knows\n%s.", monName, moveName), moveId, moveName
  end
  local species = tonumber(mon.species or mon.speciesId)
  if not Pokemon.canLearnTmItem(species, tmId) then
    return "incompatible", Strings("%s can't learn\n%s.", monName, moveName), moveId, moveName
  end
  local prompt = Strings("Booted up a TM.\nIt contained %s.\nTeach %s to %s?", moveName, moveName, monName)
  return "ok", prompt, moveId, moveName
end

--- Teach TM/HM. partySlot required. Consumes TM (not HM).
function ItemUse.useTm(session, bag, id, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then
    return false, "noparty", Strings("There's no POKéMON!")
  end
  local status, preflightMsg, moveId, moveName = ItemUse.checkTmPreflight(mon, id)
  if status ~= "ok" then
    return false, status, preflightMsg
  end
  local monName = Pokemon.displayMonName(mon)

  local isHm = ItemsData.isHm(id)
  local consumed = false

  local function finish_consume(learned)
    if learned then
      -- pokefirered/src/party_menu.c:4287
      Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_LEARN_TMHM,
        { mapSec = Pokemon.currentMapSec(session) })
      require("src.core.game3.quest_log_recorder").event(session,
        isHm and "MonLearnedMoveFromHM" or "MonLearnedMoveFromTM",{monName,moveName})
    end
    if learned and not isHm and not consumed then
      Bag.remove(bag, id, 1)
      consumed = true
    end
  end

  if Pokemon.moveSlotCount(mon) < 4 then
    local ok = Pokemon.teachMove(mon, moveId)
    if ok then
      finish_consume(true)
      return true, "tm", Strings("%s learned\n%s!", monName, moveName)
    end
  end

  local LearnMove = require("src.core.game3.battle.learn_move")
  LearnMove.begin({
    mon = mon,
    moveId = moveId,
    displayName = monName,
    headless = true,
    onDone = function(learned)
      finish_consume(learned)
    end,
  })
  if Pokemon.moveSlotCount(mon) >= 4 then
    return false, "full", Strings("%s can't learn\nmore than four moves.", monName)
  end
  return true, "tm", Strings("%s learned\n%s!", monName, moveName)
end

--- Check if using this item requires selecting a party Pokémon target.
function ItemUse.needsPartyTarget(id)
  if not id then return false end
  local info = ItemsData.info(id)
  if not info then return false end
  local use = ItemsData.fieldUseKind(id)
  if use == "heal" or use == "status" or use == "revive" or use == "tm"
      or use == "pp" or use == "level" or use == "evo" or use == "vitamin" then
    return true
  end
  if info.pocket == "TM_CASE" then return true end
  return false
end

-- pokefirered/src/party_menu.c:5018
function ItemUse.levelUpEvent(mon, level)
  if not ModRuntime.wants("pokemon.level_up") then return end
  local G3 = require("src.mods.Gen3Compat")
  local learnable, learnableIds = {}, {}
  for _, mv in ipairs(Pokemon.movesLearnedAt(tonumber(mon.species or mon.speciesId), level)) do
    learnable[#learnable + 1] = G3.moveName(mv)
    learnableIds[#learnableIds + 1] = mv
  end
  ModRuntime.emit("pokemon.level_up", {
    mon = mon, level = level, prevLevel = level - 1,
    learnable = learnable, learnableIds = learnableIds, via = "item",
  })
end

function ItemUse.useRareCandy(session, mon)
  if not mon then return false, "none", Strings("There's no POKéMON!") end
  local lvl = tonumber(mon.level) or 1
  local hp = tonumber(mon.hp) or 0
  if lvl >= 100 or hp <= 0 then
    return false, "no_effect", Strings("It won't have any effect.")
  end
  local oldMax = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 1
  local oldHp = hp
  mon.level = lvl + 1
  Pokemon.applyStats(mon)
  local newMax = tonumber(mon.maxHp) or tonumber(mon.maxhp) or oldMax
  mon.hp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
  -- pokefirered/src/data/pokemon/item_effects.h:200 sItemEffect_RareCandy
  Pokemon.itemFriendship(mon, Pokemon.VITAMIN_FRIENDSHIP_CHANGE,
    { mapSec = Pokemon.currentMapSec(session) })
  ItemUse.levelUpEvent(mon, mon.level)
  local t = Strings("%s grew to\nLv. %d!", Pokemon.displayMonName(mon), mon.level)
  return true, "level", t
end

-- pokefirered/src/data/pokemon/item_effects.h:168
local VITAMIN_STAT = {
  [63] = "hp", [64] = "atk", [65] = "def", [66] = "spe", [67] = "spa", [70] = "spd",
}
local VITAMIN_ADD_EV = 10

local function vitamin_stat_name(key)
  -- pokefirered/src/strings.c:248
  if key == "hp" then return Strings("HP") end
  if key == "atk" then return Strings("ATTACK") end
  if key == "def" then return Strings("DEFENSE") end
  if key == "spe" then return Strings("SPEED") end
  if key == "spa" then return Strings("SP. ATK") end
  return Strings("SP. DEF")
end

function ItemUse.useVitamin(session, mon, itemId)
  if not mon then return false, "none", Strings("There's no POKéMON!") end
  local num = ItemsData.toNumericId(itemId) or tonumber(itemId)
  local key = VITAMIN_STAT[num]
  if not key then
    return false, "no_effect", Strings("It won't have any effect.")
  end
  -- pokefirered/src/party_menu.c:4405 NotUsingHPEVItemOnShedinja
  if key == "hp" and (tonumber(mon.species or mon.speciesId) or 0) == 303 then
    return false, "no_effect", Strings("It won't have any effect.")
  end
  local gained = Pokemon.raiseEvFromItem(mon, key, VITAMIN_ADD_EV)
  if not gained or gained <= 0 then
    return false, "no_effect", Strings("It won't have any effect.")
  end
  Pokemon.itemFriendship(mon, Pokemon.VITAMIN_FRIENDSHIP_CHANGE,
    { mapSec = Pokemon.currentMapSec(session) })
  -- pokefirered/src/strings.c:298 gText_PkmnBaseVar2StatIncreased
  local t = Strings("%s's base %s\nstat was raised.",
    Pokemon.displayMonName(mon), vitamin_stat_name(key))
  return true, "vitamin", t
end

-- pokefirered/include/constants/item_effects.h:34
local ITEM4_HEAL_PP_ALL, ITEM4_HEAL_PP_ONE, ITEM4_PP_UP = 0x08, 0x10, 0x20
local ITEM5_PP_MAX = 0x10

local function s8(v)
  v = tonumber(v) or 0
  if v >= 0x80 then return v - 0x100 end
  return v
end

-- pokefirered/src/pokemon.c:4001
local function pp_effect(id)
  local info = ItemsData.info(id)
  local e = info and info.effect
  if type(e) ~= "table" then return nil end
  local e4, e5 = tonumber(e[5]) or 0, tonumber(e[6]) or 0
  local idx = 7
  for b = 0, 2 do
    if bit.band(e4, bit.lshift(1, b)) ~= 0 then idx = idx + 1 end
  end
  local r = {
    up = bit.band(e4, ITEM4_PP_UP) ~= 0,
    max = bit.band(e5, ITEM5_PP_MAX) ~= 0,
  }
  if bit.band(e4, ITEM4_HEAL_PP_ALL) ~= 0 then
    r.heal = tonumber(e[idx]) or 0
    r.one = bit.band(e4, ITEM4_HEAL_PP_ONE) ~= 0
    idx = idx + 1
  end
  if not (r.up or r.max or r.heal) then return nil end
  for b = 0, 3 do
    if bit.band(e5, bit.lshift(1, b)) ~= 0 then idx = idx + 1 end
  end
  if bit.band(e5, 0xE0) ~= 0 then
    r.friendship = {}
    for k, b in ipairs({ 0x20, 0x40, 0x80 }) do
      if bit.band(e5, b) ~= 0 then
        r.friendship[k] = s8(e[idx])
        idx = idx + 1
      end
    end
  end
  return r
end

local function has_move(mon, s)
  local m = Pokemon.moveIdAt(mon, s)
  return m ~= nil and m > 0
end

-- pokefirered/src/pokemon.c:3898
local function pp_with_bonus(mon, s, n)
  local base = tonumber(Pokemon.movePp(Pokemon.moveIdAt(mon, s))) or 0
  return base + math.floor(base * 20 * n / 100)
end

local function pp_bonus(mon, s)
  if type(mon.ppBonusesPacked) == "number" then
    return bit.band(bit.rshift(mon.ppBonusesPacked, (s - 1) * 2), 3)
  end
  local m = tonumber(mon.maxPp and mon.maxPp[s])
  if not m then return 0 end
  local best = 0
  for n = 0, 3 do
    local v = pp_with_bonus(mon, s, n)
    if v == m then return n end
    if v <= m then best = n end
  end
  return best
end

-- pokefirered/src/pokemon.c:4202, :4344, :4463
local function pp_plan(mon, id, moveSlot)
  local e = pp_effect(id)
  if not e or not mon then return nil, nil end
  local out = {}
  if e.up or e.max then
    local s = tonumber(moveSlot)
    if s and has_move(mon, s) then
      local n = pp_bonus(mon, s)
      local cur = pp_with_bonus(mon, s, n)
      local nn
      if e.up and n < 3 and cur > 4 then nn = n + 1 end
      if e.max and n < 3 then nn = 3 end
      if nn then
        local newMax = pp_with_bonus(mon, s, nn)
        out[#out + 1] = {
          slot = s, bonus = nn, max = newMax,
          pp = (tonumber(mon.pp and mon.pp[s]) or 0) + newMax - cur,
        }
      end
    end
  elseif e.heal then
    for s = 1, 4 do
      if (not e.one or s == tonumber(moveSlot)) and has_move(mon, s) then
        local max = pp_with_bonus(mon, s, pp_bonus(mon, s))
        local cur = tonumber(mon.pp and mon.pp[s]) or 0
        if cur ~= max then
          out[#out + 1] = { slot = s, pp = math.min(max, cur + e.heal) }
        end
      end
    end
  end
  return out, e
end

-- pokefirered/src/party_menu.c:4591, :4709
function ItemUse.ppItemNeedsMove(id)
  local e = pp_effect(id)
  return e ~= nil and (e.one or e.up or e.max) and true or false
end

function ItemUse.ppItemBoosts(id)
  local e = pp_effect(id)
  return e ~= nil and (e.up or e.max) and true or false
end

-- pokefirered/src/pokemon.c:4529
function ItemUse.ppItemHasEffect(mon, id, moveSlot)
  local plan = pp_plan(mon, id, moveSlot)
  return plan ~= nil and #plan > 0
end

-- pokefirered/src/party_menu.c:4340
function ItemUse.ppItemText(mon, id, moveSlot)
  if ItemUse.ppItemBoosts(id) then
    return Strings("%s's PP increased.", Pokemon.moveName(Pokemon.moveIdAt(mon, moveSlot)) or "")
  end
  return Strings("PP was restored.")
end

function ItemUse.applyPpItem(mon, id, moveSlot, battler, session)
  local plan, e = pp_plan(mon, id, moveSlot)
  if not plan or #plan == 0 then return false end
  mon.pp = mon.pp or {}
  for _, c in ipairs(plan) do
    mon.pp[c.slot] = c.pp
    if c.max then
      mon.maxPp = mon.maxPp or {}
      mon.maxPp[c.slot] = c.max
      if type(mon.ppBonusesPacked) == "number" then
        local shift = (c.slot - 1) * 2
        mon.ppBonusesPacked = bit.bor(bit.band(mon.ppBonusesPacked, bit.bnot(bit.lshift(3, shift))),
          bit.lshift(c.bonus, shift))
      end
    end
    -- pokefirered/src/pokemon.c:4366
    local bMon = battler and battler.mon
    if bMon and bMon ~= mon and not battler.transformed
        and (not battler.permanentSlots or battler.permanentSlots[c.slot]) then
      bMon.pp = bMon.pp or {}
      bMon.pp[c.slot] = c.pp
    end
  end
  -- pokefirered/src/pokemon.c:3976
  if e.friendship then
    Pokemon.itemFriendship(mon, e.friendship, { mapSec = Pokemon.currentMapSec(session) })
  end
  return true
end

function ItemUse.useEvolutionStone(session, mon, itemId, bag)
  local Evolution = require("src.core.game3.evolution")
  local target = Evolution.itemTarget and Evolution.itemTarget(mon, itemId, session)
  if not target then
    return false, "no_evo", Strings("It won't have any effect.")
  end
  local oldName = Pokemon.displayMonName(mon)
  local newName = Pokemon.name(target) or "POKéMON"

  local okEv, EvolutionScene = pcall(require, "src.ui.game3.evolution_scene")
  if okEv and EvolutionScene and EvolutionScene.start and love and love.graphics then
    local Audio = require("src.core.game3.audio")
    EvolutionScene.start(mon, target, {
      canStop = false,
      session = session,
      bag = bag,
      savedSong = Audio._mapSong,
      via = "item",
    })
    return true, "evo", Strings("Evolving...")
  else
    Evolution.apply(mon, target, session, bag, "item")
    local t = Strings("%s evolved into\n%s!", oldName, newName)
    return true, "evo", t
  end
end

-- pokefirered/include/constants/items.h:273
local ROD_ITEMS = { [262] = true, [263] = true, [264] = true }
local ITEM_BLACK_FLUTE = 42
local ITEM_WHITE_FLUTE = 43
local ITEM_POKE_FLUTE = 350
-- pokefirered/include/constants/items.h:432 ITEM_BICYCLE
local ITEM_BICYCLE = 360
-- pokefirered/include/constants/items.h:438 ITEM_TEACHY_TV
local ITEM_TEACHY_TV = 366
-- pokefirered/include/constants/items.h:435 ITEM_FAME_CHECKER
local ITEM_FAME_CHECKER = 363
local ITEM_AWAKENING = 17
-- pokefirered/include/constants/flags.h:1330
local FLAG_SYS_WHITE_FLUTE_ACTIVE = 0x803
local FLAG_SYS_BLACK_FLUTE_ACTIVE = 0x804
-- pokefirered/include/constants/songs.h:114
local SE_GLASS_FLUTE = 110
-- pokefirered/include/constants/songs.h:346 MUS_POKE_FLUTE
local MUS_POKE_FLUTE = 338

local function sys_flag(session, flagId, value)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Flags = require("src.core.game3.scripting.flags")
  if Space and Space.store then
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx or nil, flagId, value)
  end
  if session then
    session.flags = session.flags or {}
    session.flags[flagId] = value or nil
  end
end

local function play_se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

local function not_the_time(session)
  -- pokefirered/src/strings.c:188 gText_OakForbidsUseOfItemHere
  return Strings("OAK: %s!\nThis isn't the time to use that!",
    tostring((session and session.name) or "RED"))
end

-- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback
function ItemUse.exitMenusToField()
  local closed = false
  local BagMenu = package.loaded["src.ui.game3.bag_menu"]
  if BagMenu and BagMenu.isOpen and BagMenu.isOpen() and BagMenu.close then
    BagMenu.close()
    closed = true
  end
  local StartMenu = package.loaded["src.ui.game3.start_menu"]
  if StartMenu and StartMenu.isOpen and StartMenu.isOpen() then
    StartMenu.open = false
    StartMenu._onClose = nil
    local okS, Stack = pcall(require, "src.ui.game3.stack")
    if okS and Stack and Stack.pop then Stack.pop("start") end
    closed = true
  end
  if closed then
    local okF, Fade = pcall(require, "src.ui.game3.fade")
    if okF and Fade and Fade.begin and Fade.MODE then
      Fade.begin(Fade.MODE.FROM_BLACK, 1)
    end
  end
  return closed
end

-- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback
function ItemUse.setUpOnFieldCallback(cb)
  local BagMenu = package.loaded["src.ui.game3.bag_menu"]
  if not (BagMenu and BagMenu.isOpen and BagMenu.isOpen()) then return false end
  ItemUse._onFieldCB = cb
  return true
end

-- pokefirered/src/item_use.c:176 Task_WaitFadeIn_CallItemUseOnFieldCB
function ItemUse.runOnFieldCallback()
  local cb = ItemUse._onFieldCB
  ItemUse._onFieldCB = nil
  if cb then cb() end
  return cb ~= nil
end

-- pokefirered/src/item_use.c:182 DisplayItemMessageInCurrentContext
function ItemUse.showFieldMessage(text, onDone)
  if not text then return false end
  -- pokefirered/src/item_menu.c:1018 DisplayItemMessageInBag
  local BagMenu = package.loaded["src.ui.game3.bag_menu"]
  if BagMenu and BagMenu.isOpen and BagMenu.isOpen() and BagMenu.showMessage then
    BagMenu.showMessage(text, onDone)
    return true
  end
  -- pokefirered/src/new_menu_helpers.c:641 DisplayItemMessageOnField
  local okM, Message = pcall(require, "src.ui.game3.message")
  if not (okM and Message and Message.show) then return false end
  Message.show(text, { done = onDone })
  return true
end

-- pokefirered/src/item_use.c:296 CanFish
function ItemUse.canFish()
  local P = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local FieldMoves = require("src.core.game3.field_moves")
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local d = DELTA[P.facing or "down"] or DELTA.down
  local fx, fy = P.cellX + d[1], P.cellY + d[2]
  local beh = Collision.behavior and Collision.behavior(fx, fy)
  if FieldMoves.isWaterfallBehavior(beh) then return false end
  if not P.surfing then
    -- pokefirered/src/field_player_avatar.c:1209 IsPlayerFacingSurfableFishableWater
    return (Collision.isWater and Collision.isWater(fx, fy)) == true
  end
  return (Collision.isSurfable and Collision.isSurfable(beh)) == true
    and Collision.isWater(fx, fy) == true
end

-- pokefirered/src/item_use.c:286 FieldUseFunc_Rod
function ItemUse.useRod(session, id)
  if not ItemUse.canFish() then
    -- pokefirered/src/item_use.c:294 PrintNotTheTimeToUseThat
    local text = not_the_time(session)
    return false, "rod", text
  end
  local info = ItemsData.info(id)
  local Field = require("src.core.game3.field")
  -- pokefirered/src/item_use.c:326 ItemUseOnFieldCB_Rod
  Field.startFishing(tonumber(info and info.secondaryId) or 0)
  return true, "rod", nil
end

-- pokefirered/src/item_use.c:359 FieldUseFunc_PokeFlute
function ItemUse.usePokeFlute(session)
  local woke = false
  for _, mon in ipairs((session and session.party) or {}) do
    local isEgg = mon.isEgg or (type(mon.egg) == "boolean" and mon.egg)
    if not isEgg and ItemUse.clearStatus(mon, ITEM_AWAKENING) then woke = true end
  end
  if not woke then
    -- pokefirered/src/strings.c:204 gText_PlayedPokeFluteCatchy
    local text = Strings("Played the POKé FLUTE.\\pNow, that's a catchy tune!")
    return true, "flute", text
  end
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playFanfare then Audio.playFanfare(MUS_POKE_FLUTE) end
  end)
  -- pokefirered/src/strings.c:205 gText_PlayedPokeFlute, :206 gText_PokeFluteAwakenedMon
  local text =
    Strings("Played the POKé FLUTE.\\pThe POKé FLUTE awakened sleeping\nPOKéMON.")
  return true, "flute", text
end

-- pokefirered/src/item_use.c:582 FieldUseFunc_BlackWhiteFlute
function ItemUse.useBlackWhiteFlute(session, num)
  local ctx = {
    playerName = tostring((session and (session.name or session.playerName)) or ""),
    stringVars = { [2] = ItemsData.displayName(num) },
  }
  local text
  if num == ITEM_WHITE_FLUTE then
    sys_flag(session, FLAG_SYS_WHITE_FLUTE_ACTIVE, true)
    sys_flag(session, FLAG_SYS_BLACK_FLUTE_ACTIVE, false)
    -- pokefirered/src/item_use.c:590
    text = RomText.box("gText_UsedVar2WildLured", ctx)
  else
    sys_flag(session, FLAG_SYS_BLACK_FLUTE_ACTIVE, true)
    sys_flag(session, FLAG_SYS_WHITE_FLUTE_ACTIVE, false)
    -- pokefirered/src/item_use.c:599
    text = RomText.box("gText_UsedVar2WildRepelled", ctx)
  end
  return true, "black_white_flute", text
end

-- pokefirered/src/item_use.c:605 Task_UsedBlackWhiteFlute
ItemUse.BLACK_WHITE_FLUTE_DELAY = 8

function ItemUse.playBlackWhiteFlute()
  play_se(SE_GLASS_FLUTE)
end

--- Try field use. partySlot optional for heal/status/revive/tm/give.
-- Returns ok, reason, messageText
local function useField(session, bag, id, partySlot, moveSlot)
  local info = ItemsData.info(id)
  if not info then return false, "unknown", Strings("Unknown item.") end
  local use = ItemsData.fieldUseKind(id)

  if use == "battle" then
    return false, "battle", Strings("This can't be used outside\nof battle.")
  end

  if use == "map" then
    local RegionMap = require("src.ui.game3.region_map")
    RegionMap.show({ session = session })
    return true, "map", Strings("Used TOWN MAP.")
  end

  if use == "bike" then
    return ItemUse.useBike(session)
  end

  -- pokefirered/src/item_use.c:337 FieldUseFunc_CoinCase
  if use == "coin_case" then
    local coins = Bag.Coins and Bag.Coins.get and Bag.Coins.get(session) or 0
    -- pokefirered/src/strings.c:193 gText_CoinCase
    return true, "coin_case", Strings("Your COINS:\n%d", coins)
  end

  -- pokefirered/src/item_use.c:348 FieldUseFunc_PowderJar
  if use == "powder_jar" then
    -- pokefirered/src/berry_powder.c:90 GetBerryPowder
    local powder = math.floor(tonumber(session and session.berryPowder) or 0)
    if powder < 0 then powder = 0 end
    -- pokefirered/src/strings.c:202 gText_PowderQty
    return true, "powder_jar", Strings("POWDER QTY: %d", powder)
  end

  if use == "escape" then
    return ItemUse.useEscapeRope(session, bag, id)
  end

  if use == "repel" then
    local steps = ItemsData.REPEL_STEPS[id]
      or ItemsData.REPEL_STEPS[ItemsData.toNumericId(id) or -1]
      or 100
    session.repelSteps = steps
    Bag.remove(bag, id, 1)
    local t = Strings("The repelling effect wore\non for a while.")
    return true, "repel", t
  end

  if use == "vs_seeker" or id == ItemsData.ITEM_VS_SEEKER or id == "VS_SEEKER"
      or ItemsData.toNumericId(id) == ItemsData.ITEM_VS_SEEKER then
    if not Capabilities.gate(session, "vs_seeker") then
      return false, "vs_seeker", nil
    end
    local VsSeeker = require("src.core.game3.vs_seeker")
    if not VsSeeker.canUseHere(session) then
      return false, "vs_seeker", VsSeeker.notTimeText(session)
    end
    return true, "vs_seeker", nil
  end

  if use == "itemfinder" or id == ItemsData.ITEM_ITEMFINDER or id == "ITEMFINDER"
      or ItemsData.toNumericId(id) == ItemsData.ITEM_ITEMFINDER then
    local Field = require("src.core.game3.field")
    local ok, kind, text = Field.useItemfinder(session)
    return ok, kind or "itemfinder", text
  end

  if id == ItemsData.ITEM_TM_CASE or id == "TM_CASE"
      or ItemsData.toNumericId(id) == ItemsData.ITEM_TM_CASE then
    local TmCase = require("src.ui.game3.tm_case")
    TmCase.show(session, bag)
    return true, "tm_case", Strings("Opened TM CASE.")
  end

  if id == ItemsData.ITEM_BERRY_POUCH or id == "BERRY_POUCH"
      or ItemsData.toNumericId(id) == ItemsData.ITEM_BERRY_POUCH then
    local BerryPouch = require("src.ui.game3.berry_pouch")
    BerryPouch.show(session, bag)
    return true, "berry_pouch", Strings("Opened BERRY POUCH.")
  end

  -- pokefirered/src/item_use.c:518 FieldUseFunc_TeachyTv
  if id == ITEM_TEACHY_TV or id == "TEACHY_TV"
      or ItemsData.toNumericId(id) == ITEM_TEACHY_TV then
    if not Capabilities.gate(session, "teachy_tv") then
      return false, "teachy_tv", nil
    end
    local TeachyTv = require("src.core.game3.teachy_tv")
    TeachyTv.show(session, bag)
    return true, "teachy_tv", nil
  end

  -- pokefirered/src/item_use.c:680 FieldUseFunc_FameChecker
  if id == ITEM_FAME_CHECKER or id == "FAME_CHECKER"
      or ItemsData.toNumericId(id) == ITEM_FAME_CHECKER then
    if not Capabilities.gate(session, "fame_checker") then
      return false, "fame_checker", nil
    end
    local FameCheckerUi = require("src.ui.game3.fame_checker")
    -- pokefirered/src/item_use.c:696 UseFameCheckerFromBag
    local okBag, BagMenu = pcall(require, "src.ui.game3.bag_menu")
    local fromBag = okBag and BagMenu and BagMenu.open and true or false
    FameCheckerUi.show(session, { fromBag = fromBag })
    return true, "fame_checker", nil
  end

  do
    local num = ItemsData.toNumericId(id) or tonumber(id)
    if ROD_ITEMS[num] then
      return ItemUse.useRod(session, id)
    end
    if num == ITEM_POKE_FLUTE then
      return ItemUse.usePokeFlute(session)
    end
    if use == "black_white_flute" then
      return ItemUse.useBlackWhiteFlute(session, num)
    end
    -- pokefirered/src/item_use.c:253 FieldUseFunc_Bike
    if num == ITEM_BICYCLE then
      return ItemUse.useBike(session)
    end
  end

  if use == "key" or use == "rod" or use == "berry" or use == "mail"
      or use == "flute" or use == "none" then
    local t = Strings("OAK: This isn't the\ntime to use that!")
    return false, use, t
  end

  if use == "heal" or use == "status" or use == "revive" or use == "tm"
      or use == "pp" or use == "level" or use == "evo" or use == "vitamin" then
    local party = session and session.party
    if not party or #party < 1 then
      return false, "noparty", RomText.box("gText_ThereIsNoPokemon")
    end
    if not partySlot then
      return false, "need_slot", Strings("Select a POKéMON.")
    end
    local mon = party[partySlot]
    if not mon then
      return false, "noparty", RomText.box("gText_ThereIsNoPokemon")
    end
    local ok = false
    local text = nil
    local _
    local num = ItemsData.toNumericId(id) or tonumber(id)
    local monName = Pokemon.displayMonName(mon)

    if use == "tm" then
      return ItemUse.useTm(session, bag, id, partySlot)
    elseif use == "evo" then
      ok, _, text = ItemUse.useEvolutionStone(session, mon, id, bag)
    elseif use == "level" then
      ok, _, text = ItemUse.useRareCandy(session, mon)
    -- pokefirered/src/pokemon.c:4258
    elseif use == "revive" or num == ITEM_REVIVAL_HERB then
      if num == 45 then -- Sacred Ash
        ok = ItemUse.reviveAll(party)
        text = Strings("All POKéMON's HP was\nfully restored!")
      else
        local max = num == 25 or num == ITEM_REVIVAL_HERB or tostring(id) == "MAX_REVIVE"
        ok = ItemUse.revive(mon, max)
        text = Strings("%s's HP was\nrestored!", monName)
      end
    elseif use == "status" then
      local stOk, cured = ItemUse.clearStatus(mon, id)
      ok = stOk
      if cured == "poison" then
        text = Strings("%s was\ncured of poison.", monName)
      elseif cured == "paralysis" then
        text = Strings("%s was\ncured of paralysis.", monName)
      elseif cured == "burn" then
        text = Strings("%s's burn\nwas healed.", monName)
      elseif cured == "freeze" then
        text = Strings("%s was\ndefrosted.", monName)
      elseif cured == "sleep" then
        text = Strings("%s woke up.", monName)
      else
        text = Strings("%s recovered\nfrom illness!", monName)
      end
    elseif use == "pp" then
      if moveSlot == nil and ItemUse.ppItemNeedsMove(id) then
        return false, "need_move", nil
      end
      moveSlot = moveSlot or 1
      -- pokefirered/src/party_menu.c:4657
      ok = ItemUse.applyPpItem(mon, id, moveSlot, nil, session)
      if ok then text = ItemUse.ppItemText(mon, id, moveSlot) end
    elseif use == "vitamin" then
      ok, _, text = ItemUse.useVitamin(session, mon, id)
    else
      local healOk, restored = ItemUse.healMon(session, mon, id)
      ok = healOk
      if restored and restored > 0 then
        text = Strings("%s's HP was\nrestored by %d points.", monName, restored)
      else
        text = Strings("%s's HP was\nrestored!", monName)
      end
    end

    if ok then
      -- pokefirered/src/pokemon.c:4481
      if BITTER_MEDICINE_FRIENDSHIP[num] then
        Pokemon.itemFriendship(mon, BITTER_MEDICINE_FRIENDSHIP[num],
          { mapSec = Pokemon.currentMapSec(session) })
      end
      Bag.remove(bag, id, 1)
      return true, use, text or Strings("It restored health!")
    end
    return false, "noeffect", text or Strings("It won't have any effect.")
  end

  return false, "none", Strings("OAK: This isn't the\ntime to use that!")
end

function ItemUse.useField(session,bag,id,partySlot,moveSlot)
  local ok,kind,text
  if ModRuntime.wantsHook("item.use") then
    local Runtime=package.loaded["src.core.game3.runtime"]
    ok,kind,text=ModRuntime.call("item.use",function(_,_,hid,hslot)
      return useField(session,bag,hid,hslot,moveSlot)
    end,Runtime and Runtime._game,nil,id,partySlot,bag)
  else
    ok,kind,text=useField(session,bag,id,partySlot,moveSlot)
  end
  if ok and kind~="tm" and kind~="tm_case" and kind~="berry_pouch" and kind~="vs_seeker" then
    local Items=require("src.core.game3.items")
    local Pokemon=require("src.core.game3.pokemon")
    local mon=partySlot and session and session.party and session.party[partySlot]
    require("src.core.game3.quest_log_recorder").event(session,
      mon and "UsedItemOnMonAtThisLocation" or "UsedTheItem",
      {Items.displayName(id),mon and Pokemon.displayMonName(mon)})
  end
  return ok,kind,text
end
return ItemUse
