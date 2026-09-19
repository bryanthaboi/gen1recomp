-- FRLG field item-use handlers for game3 bag.

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Pokemon = require("src.core.game3.pokemon")
local ModRuntime = require("src.mods.Runtime")

local ItemUse = {}

local function heal_amount(id)
  local n = ItemsData.HEAL_AMOUNT[id]
  if n then return n end
  local num = ItemsData.toNumericId(id) or tonumber(id)
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

function ItemUse.clearStatus(mon, id)
  if not mon then return false, nil end
  local st, sleep = mon_status(mon)
  if not st and sleep <= 0 then return false, nil end
  local num = ItemsData.toNumericId(id) or tonumber(id)
  local cured = "status"
  -- Specific cures when known; FULL HEAL / powder clear all.
  if num == 14 then -- ANTIDOTE
    if st ~= "PSN" and st ~= "TOX" and st ~= 1 and st ~= 2 then return false, nil end
    cured = "poison"
  elseif num == 15 then -- BURN
    if st ~= "BRN" and st ~= 3 then return false, nil end
    cured = "burn"
  elseif num == 16 then -- ICE / FREEZE
    if st ~= "FRZ" and st ~= 4 then return false, nil end
    cured = "freeze"
  elseif num == 17 then -- AWAKENING
    if st ~= "SLP" and sleep <= 0 and st ~= 5 then return false, nil end
    cured = "sleep"
  elseif num == 18 then -- PARLYZ
    if st ~= "PAR" and st ~= 6 then return false, nil end
    cured = "paralysis"
  end
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

--- Give item to party mon as held item. Returns ok, reason, messageText.
function ItemUse.giveToMon(session, bag, id, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then return false, "noparty", "There's no POKéMON!" end
  local pocket = ItemsData.pocketOf(id)
  if pocket == "KEY_ITEMS" or pocket == "TM_CASE" then
    return false, "cant_hold", "This item can't be held."
  end
  if not Bag.has(bag, id, 1) then
    return false, "none", "You don't have that item."
  end
  local prev = mon.item or mon.heldItem
  if prev and prev ~= 0 and prev ~= "" and prev ~= "NONE" then
    -- Swap: return previous to bag if possible
    if not Bag.canAdd(bag, prev, 1) then
      return false, "bag_full", "The BAG is full."
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
    text = string.format("Took the %s and\ngave the %s to\n%s.", ItemsData.displayName(prev), ItemsData.displayName(id), monName)
  else
    text = string.format("%s was given\nto %s.", ItemsData.displayName(id), monName)
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
  if not mon then return false, "noparty", "There's no POKéMON!" end
  local held = mon.item or mon.heldItem
  local monName = Pokemon.displayMonName(mon)
  if not held or held == 0 or held == "" or held == "NONE" then
    return false, "none", monName .. " isn't\nholding anything."
  end
  if not Bag.canAdd(bag, held, 1) then
    return false, "bag_full", "The BAG is full. The\nitem could not be removed."
  end
  mon.item = nil
  mon.heldItem = nil
  Bag.add(bag, held, 1)
  local text = string.format("Took the %s from\n%s and put it in the BAG.", ItemsData.displayName(held), monName)
  require("src.core.game3.quest_log_recorder").event(session,"TookHeldItemFromMon",
    {monName,ItemsData.displayName(held)})
  return true, "take", text
end

local function is_outdoor(session)
  local mapId = session and session.map
  if type(mapId) ~= "string" then return false end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local data = game and game.data and game.data.maps
  local def = data and data[mapId]
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

local function can_escape(session)
  if not session or not session.healMap then return false end
  if session.map == session.healMap then return false end
  -- pret: caves / indoors that aren't the heal point. Deny pure outdoors.
  return not is_outdoor(session)
end

function ItemUse.useEscapeRope(session, bag, id)
  if not can_escape(session) then
    return false, "escape", "OAK: This isn't the\ntime to use that!"
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local mod = Runtime and Runtime._mod
  local game = Runtime and Runtime._game
  local Field = package.loaded["src.core.game3.field"]
  Bag.remove(bag, id, 1)
  local t = tostring(session.name or "RED") .. " used\nESCAPE ROPE."
  local hx = session.healX or 8
  local hy = session.healY or 5
  local mapId = session.healMap
  local Warp = require("src.core.game3.warp")
  if mod and game then
    Warp.request(mod, game, mapId, hx, hy, "down", { fade = true })
  elseif Field and Field.respawnAtHeal then
    -- Fallback: heal warp without consuming party heal intent
    local Map = require("src.core.game3.map")
    Map.load(mod, game, mapId, { x = hx, y = hy, facing = "down" })
  end
  return true, "escape", t
end

function ItemUse.useBike(session)
  if not is_outdoor(session) then
    return false, "bike", "OAK: This isn't the\ntime to use that!"
  end
  local Player = require("src.core.game3.player")
  Player.biking = not Player.biking
  local t
  if Player.biking then
    t = tostring(session.name or "RED") .. " got on the\nBICYCLE."
  else
    t = tostring(session.name or "RED") .. " got off the\nBICYCLE."
  end
  return true, "bike", t
end

--- Check TM pre-flight compatibility and known moves matching retail FRLG.
-- Returns status ("knows" | "incompatible" | "ok"), messageText, moveId, moveName
function ItemUse.checkTmPreflight(mon, tmId)
  if not mon then return "none", "There's no POKéMON!", nil, nil end
  local moveId = Pokemon.moveFromTmItem(tmId)
  local monName = Pokemon.displayMonName(mon)
  local moveName = Pokemon.moveName(moveId) or "MOVE"
  if not moveId then
    return "invalid", "This isn't the time to use\nthat!", nil, nil
  end
  if Pokemon.knowsMove(mon, moveId) then
    return "knows", string.format("%s already knows\n%s.", monName, moveName), moveId, moveName
  end
  local species = tonumber(mon.species or mon.speciesId)
  if not Pokemon.canLearnTmItem(species, tmId) then
    return "incompatible", string.format("%s can't learn\n%s.", monName, moveName), moveId, moveName
  end
  local prompt = string.format("Booted up a TM.\nIt contained %s.\nTeach %s to %s?", moveName, moveName, monName)
  return "ok", prompt, moveId, moveName
end

--- Teach TM/HM. partySlot required. Consumes TM (not HM).
function ItemUse.useTm(session, bag, id, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then
    return false, "noparty", "There's no POKéMON!"
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
      return true, "tm", string.format("%s learned\n%s!", monName, moveName)
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
    return false, "full", monName .. " can't learn\nmore than four moves."
  end
  return true, "tm", string.format("%s learned\n%s!", monName, moveName)
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
  if not mon then return false, "none", "There's no POKéMON!" end
  local lvl = tonumber(mon.level) or 1
  local hp = tonumber(mon.hp) or 0
  if lvl >= 100 or hp <= 0 then
    return false, "no_effect", "It won't have any effect."
  end
  local oldMax = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 1
  local oldHp = hp
  mon.level = lvl + 1
  Pokemon.applyStats(mon)
  local newMax = tonumber(mon.maxHp) or tonumber(mon.maxhp) or oldMax
  mon.hp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
  ItemUse.levelUpEvent(mon, mon.level)
  local t = string.format("%s grew to\nLv. %d!", Pokemon.displayMonName(mon), mon.level)
  return true, "level", t
end

function ItemUse.useEvolutionStone(session, mon, itemId, bag)
  local Evolution = require("src.core.game3.evolution")
  local target = Evolution.itemTarget and Evolution.itemTarget(mon, itemId, session)
  if not target then
    return false, "no_evo", "It won't have any effect."
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
    return true, "evo", "Evolving..."
  else
    Evolution.apply(mon, target, session, bag, "item")
    local t = string.format("%s evolved into\n%s!", oldName, newName)
    return true, "evo", t
  end
end

--- Try field use. partySlot optional for heal/status/revive/tm/give.
-- Returns ok, reason, messageText
local function useField(session, bag, id, partySlot)
  local info = ItemsData.info(id)
  if not info then return false, "unknown", "Unknown item." end
  local use = ItemsData.fieldUseKind(id)

  if use == "battle" then
    return false, "battle", "This can't be used outside\nof battle."
  end

  if use == "map" then
    local RegionMap = require("src.ui.game3.region_map")
    RegionMap.show({ session = session })
    return true, "map", "Used TOWN MAP."
  end

  if use == "bike" then
    return ItemUse.useBike(session)
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
    local t = "The repelling effect wore\non for a while."
    return true, "repel", t
  end

  if use == "vs_seeker" or id == ItemsData.ITEM_VS_SEEKER or id == "VS_SEEKER"
      or ItemsData.toNumericId(id) == ItemsData.ITEM_VS_SEEKER then
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
    return true, "tm_case", "Opened TM CASE."
  end

  if id == ItemsData.ITEM_BERRY_POUCH or id == "BERRY_POUCH"
      or ItemsData.toNumericId(id) == ItemsData.ITEM_BERRY_POUCH then
    local BerryPouch = require("src.ui.game3.berry_pouch")
    BerryPouch.show(session, bag)
    return true, "berry_pouch", "Opened BERRY POUCH."
  end

  if use == "key" or use == "rod" or use == "berry" or use == "mail"
      or use == "flute" or use == "none" then
    local t = "OAK: This isn't the\ntime to use that!"
    return false, use, t
  end

  if use == "heal" or use == "status" or use == "revive" or use == "tm"
      or use == "pp" or use == "level" or use == "evo" or use == "vitamin" then
    local party = session and session.party
    if not party or #party < 1 then
      return false, "noparty", "There is no POKéMON."
    end
    if not partySlot then
      return false, "need_slot", "Select a POKéMON."
    end
    local mon = party[partySlot]
    if not mon then
      return false, "noparty", "There is no POKéMON."
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
    elseif use == "revive" then
      if num == 45 then -- Sacred Ash
        ok = ItemUse.reviveAll(party)
        text = "All POKéMON's HP was\nfully restored!"
      else
        local max = num == 25 or tostring(id) == "MAX_REVIVE"
        ok = ItemUse.revive(mon, max)
        text = string.format("%s's HP was\nrestored!", monName)
      end
    elseif use == "status" then
      local stOk, cured = ItemUse.clearStatus(mon, id)
      ok = stOk
      if cured == "poison" then
        text = string.format("%s was\ncured of poison.", monName)
      elseif cured == "paralysis" then
        text = string.format("%s was\ncured of paralysis.", monName)
      elseif cured == "burn" then
        text = string.format("%s's burn\nwas healed.", monName)
      elseif cured == "freeze" then
        text = string.format("%s was\ndefrosted.", monName)
      elseif cured == "sleep" then
        text = string.format("%s woke up.", monName)
      else
        text = string.format("%s recovered\nfrom illness!", monName)
      end
    elseif use == "pp" then
      return false, "pp", "It won't have any effect."
    elseif use == "vitamin" then
      return false, "vitamin", "It won't have any effect."
    else
      local healOk, restored = ItemUse.healMon(session, mon, id)
      ok = healOk
      if restored and restored > 0 then
        text = string.format("%s's HP was\nrestored by %d points.", monName, restored)
      else
        text = string.format("%s's HP was\nrestored!", monName)
      end
    end

    if ok then
      Bag.remove(bag, id, 1)
      return true, use, text or "It restored health!"
    end
    return false, "noeffect", text or "It won't have any effect."
  end

  return false, "none", "OAK: This isn't the\ntime to use that!"
end

function ItemUse.useField(session,bag,id,partySlot)
  local ok,kind,text
  if ModRuntime.wantsHook("item.use") then
    local Runtime=package.loaded["src.core.game3.runtime"]
    ok,kind,text=ModRuntime.call("item.use",function(_,_,hid,hslot)
      return useField(session,bag,hid,hslot)
    end,Runtime and Runtime._game,nil,id,partySlot,bag)
  else
    ok,kind,text=useField(session,bag,id,partySlot)
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
