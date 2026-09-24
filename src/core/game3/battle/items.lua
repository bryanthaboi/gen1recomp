-- In-battle item use: balls (catch), medicine, X items, Poké Doll.
-- Catch odds follow pret battle_script_commands.c (simplified shake check).

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")
local Pokemon = require("src.core.game3.pokemon")
local Types = require("src.core.game3.battle.types")

local BattleItems = {}

-- pret sBallCatchBonuses (×10): Ultra=20, Great=15, Poke=10, Safari=15
local BALL_MULT = {
  [1] = 255, -- MASTER (handled specially)
  [2] = 20,  -- ULTRA
  [3] = 15,  -- GREAT
  [4] = 10,  -- POKE
  [5] = 15,  -- SAFARI
  [6] = 10,  -- NET (default; type boost below)
  [7] = 10,  -- DIVE
  [8] = 10,  -- NEST (level boost)
  [9] = 10,  -- REPEAT
  [10] = 10, -- TIMER
  [11] = 10, -- LUXURY
  [12] = 10, -- PREMIER
}

local function band(a, m) return bit.band(tonumber(a) or 0, m) end

local function effect_of(itemId)
  local info = ItemsData.info(itemId)
  local e = info and info.effect
  return type(e) == "table" and e or nil
end

BattleItems.isFlute = ItemUse.isFlute

-- pokefirered/src/party_menu.c:5339
function BattleItems.isStatBooster(id)
  local e = effect_of(id)
  if not e then return false end
  return band(e[1], 0x3F) ~= 0 or band(e[2], 0xFF) ~= 0 or band(e[3], 0xFF) ~= 0 or band(e[4], 0x80) ~= 0
end


local Catching = require("src.core.game3.battle.catching")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local BattleText = require("src.core.game3.battle.battle_text")
local Adapter = require("src.core.game3.battle.adapter")

-- src/strings.c:254
local function wont_have_effect()
  return RomText.ascii("gText_WontHaveEffect")
end

-- pokefirered/src/item_use.c:578
local function player_used(session, itemId)
  return RomText.ascii("gText_PlayerUsedVar2", { playerName = session and session.name,
    stringVars = { nil, ItemsData.displayName(itemId) } })
end

-- pokefirered/src/pokemon.c:4957
local STAT_INDEX = { attack = 1, defense = 2, speed = 3, spAtk = 4, spDef = 5, accuracy = 6 }

function BattleItems.isBall(id)
  return Catching.isBall(id)
end

function BattleItems.isBattleUsable(id)
  local info = ItemsData.info(id)
  if not info then return false end
  local bu = tonumber(info.battleUsage) or 0
  if bu > 0 then return true end
  local pocket = info.pocket
  return pocket == "POKE_BALLS" or pocket == "BERRY_POUCH"
end

function BattleItems.needsPartySelect(id)
  if not id then return false end
  if Catching.isBall(id) then return false end
  local num = ItemsData.toNumericId(id) or tonumber(id)
  if num == 80 then return false end -- POKE_DOLL
  if BattleItems.isStatBooster(id) then return false end
  local use = ItemsData.fieldUseKind(id)
  local info = ItemsData.info(id)
  local bu = info and tonumber(info.battleUsage) or 0
  if bu == 1 or use == "heal" or use == "status" or use == "revive"
      or (info and info.pocket == "BERRY_POUCH") then
    return true
  end
  return false
end

local function active_for_slot(st, partySlot)
  if not st or not partySlot then return nil end
  if st.player and st.player.partyIndex == partySlot then return st.player end
  local b2 = st.double and st.battlers and st.battlers[2]
  if b2 and b2.partyIndex == partySlot then return b2 end
  return nil
end

-- pokefirered/src/pokemon.c:4081
local function status2_cure(b, e, apply)
  if not b or not e then return false end
  local changed = false
  if band(e[1], 0x80) ~= 0 and b.expInfatuated then
    changed = true
    if apply then b.expInfatuated, b.expInfatuatedWith, b.expInfatuatedBy = nil, nil, nil end
  end
  -- pokefirered/src/pokemon.c:4189
  if band(e[4], 0x01) ~= 0 and (tonumber(b.confusionTurns) or 0) > 0 then
    changed = true
    if apply then b.confusionTurns = nil end
  end
  return changed
end

-- pokefirered/src/pokemon.c:4089
local function stat_booster(st, b, e, apply)
  if not b or not e then return false end
  b.stages = b.stages or {}
  local changed = false
  local function raise(key, n)
    local cur = b.stages[key] or 0
    if n > 0 and cur < 6 then
      changed = true
      if apply then b.stages[key] = math.min(6, cur + n) end
    end
  end
  raise("attack", band(e[1], 0x0F))
  if band(e[1], 0x30) ~= 0 and not (b.focusEnergy or b.expFocusEnergy) then
    changed = true
    if apply then b.focusEnergy = true end
  end
  raise("defense", math.floor(band(e[2], 0xF0) / 16))
  raise("speed", band(e[2], 0x0F))
  raise("accuracy", math.floor(band(e[3], 0xF0) / 16))
  raise("spAtk", band(e[3], 0x0F))
  -- pokefirered/src/pokemon.c:4156
  local side = b.side == "enemy" and st.enemySide or st.playerSide
  if band(e[4], 0x80) ~= 0 and side and (tonumber(side.expMistTurns) or 0) == 0 then
    changed = true
    if apply then side.expMistTurns = 5 end
  end
  return changed
end

-- pokefirered/src/pokemon.c:1611
local STATS_TO_RAISE = { [0] = "attack", "attack", "speed", "defense", "spAtk", "accuracy" }

-- pokefirered/src/pokemon.c:4965 Battle_PrintStatBoosterEffectMessage
local function stat_booster_text(st, b, e)
  local text
  local function rose(idx)
    local stat = STATS_TO_RAISE[idx]
    text = BattleText.get("STRINGID_DEFENDERSSTATROSE", Adapter.fill(st, { def = b,
      buff1 = RomText.at("gStatNamesTable", STAT_INDEX[stat]), buff2 = BattleText.get("STRINGID_STATROSE") }))
  end
  local masks = { { 0x0F, 0x30 }, { 0x0F, 0xF0 }, { 0x0F, 0xF0 } }
  for i = 0, 2 do
    local byte = e[i + 1]
    if band(byte, masks[i + 1][1]) ~= 0 then rose(i * 2) end
    if band(byte, masks[i + 1][2]) ~= 0 then
      if i ~= 0 then
        rose(i * 2 + 1)
      else
        text = BattleText.get("STRINGID_PKMNGETTINGPUMPED", Adapter.fill(st, { atk = b }))
      end
    end
  end
  if band(e[4], 0x80) ~= 0 then
    text = BattleText.get("STRINGID_PKMNSHROUDEDINMIST", Adapter.fill(st, { atk = b }))
  end
  return text
end

function BattleItems.canUseOn(st, itemId, partySlot, mon, moveSlot)
  if not mon or not itemId then return false, wont_have_effect() end
  if mon.isEgg then return false, Strings("An EGG can't be used on.") end
  local hp = tonumber(mon.hp) or 0
  local maxHp = tonumber(mon.maxHp or mon.maxhp) or 1
  local mk = ItemsData.medicineKind(itemId)
  local use = ItemsData.fieldUseKind(itemId)
  -- pokefirered/src/party_menu.c:4675 TryUsePPItemInBattle
  if use == "pp" then
    if ItemUse.ppItemHasEffect(mon, itemId, moveSlot or 1) then return true end
    return false, wont_have_effect()
  end
  local e = effect_of(itemId)
  if mk == "revive" or use == "revive" then
    if hp > 0 then return false, wont_have_effect() end
    return true
  elseif hp <= 0 then
    return false, wont_have_effect()
  elseif status2_cure(active_for_slot(st, partySlot), e, false) then
    return true
  elseif mk == "status" or use == "status" then
    local s = mon.status
    if not s or s == 0 or s == "" then return false, wont_have_effect() end
    return true
  elseif e and band(e[5], 0x04) == 0 then
    return false, wont_have_effect()
  else
    local s = mon.status
    local cures = e and band(e[4], 0x3E) ~= 0 and s and s ~= 0 and s ~= ""
    if hp >= maxHp and not cures then return false, wont_have_effect() end
    return true
  end
end

function BattleItems.ballMultiplier(itemId, foeBattler, st, session)
  return Catching.ballMultiplier(itemId, foeBattler, st, session)
end

function BattleItems.catchOdds(itemId, foeBattler, st, session)
  return Catching.catchOdds(itemId, foeBattler, st, session)
end

function BattleItems.tryCatch(itemId, foeBattler, st, rng, session)
  return Catching.tryCatch(itemId, foeBattler, st, session, rng)
end

function BattleItems.storeCaught(session, foeBattler, ballId)
  local res = Catching.storeCaught(session, foeBattler, ballId)
  return res.location
end

local function user_battler(st, battlerId)
  if battlerId == nil or battlerId == 0 then return st.player end
  return st.battlers and st.battlers[battlerId] or st.player
end

-- pokefirered/src/item_use.c:757
function BattleItems.statBoosterHasEffect(st, itemId, battlerId)
  return stat_booster(st, user_battler(st, battlerId), effect_of(itemId), false)
end

local function sync_player_battler(st, battlerId)
  local b = user_battler(st, battlerId)
  if not b or not b.mon then return end
  b.fainted = (tonumber(b.mon.hp) or 0) <= 0
  b.status = b.mon.status
end

--- Use a battle item. Returns:
--   result: "catch"|"fail_catch"|"heal"|"xitem"|"doll"|"cancel"|"error"
--   msgs: string list
--   endsTurn: bool (enemy may still move unless endsBattle)
--   endsBattle: bool
function BattleItems.use(st, adapter, bag, session, itemId, partySlot, battlerId, moveSlot)
  local msgs = {}
  local function say(t, id)
    msgs[#msgs + 1] = t
    if adapter and adapter.say then adapter:say(t, id) end
  end
  local function say_id(id, fill)
    say(BattleText.get(id, fill), (BattleText.key(id, fill)))
  end

  if not itemId or not bag then
    return "error", msgs, false, false
  end
  if not Bag.has(bag, itemId, 1) then
    say(Strings("You don't have that item."))
    return "error", msgs, false, false
  end

  local num = ItemsData.toNumericId(itemId) or tonumber(itemId)

  -- Poké Doll → flee wild
  if num == 80 then
    if not st.wild then
      say(Strings("This can't be used right now."))
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    -- pokefirered/src/item_use.c:821
    say(player_used(session, itemId))
    return "doll", msgs, true, true
  end

  -- Balls
  if BattleItems.isBall(itemId) then
    local fill = Adapter.fill(st, { lastItem = itemId, playerName = (session and session.name) or st.playerName })
    if not st.wild then
      -- pokefirered/data/battle_scripts_2.s:118
      say_id("STRINGID_TRAINERBLOCKEDBALL", fill)
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    -- pokefirered/data/battle_scripts_2.s:57
    say_id("STRINGID_PLAYERUSEDITEM", fill)
    local rng = adapter and adapter.rng and adapter:rng()
      or require("src.core.game3.battle.link_guard").source("items.rng", math.random)
    local foe = Catching.targetFor(st, battlerId)
    local caught, shakes = BattleItems.tryCatch(itemId, foe, st, rng, session)
    if caught then
      local res = Catching.storeCaught(session, foe, itemId)
      local ename = require("src.core.game3.battle.state").displayName(foe)
      fill.opponentMon1 = foe
      -- pokefirered/data/battle_scripts_2.s:77
      say_id("STRINGID_GOTCHAPKMNCAUGHT", fill)
      if res and res.firstTimeCaught then
        say_id("STRINGID_PKMNDATAADDEDTODEX", fill)
      end
      if res and res.location == "pc" then
        -- pokefirered/src/battle_script_commands.c:9617
        local Storage = require("src.core.game3.storage")
        say(Storage.pcTransferMessage(session, ename))
      end
      return "catch", msgs, true, true
    end
    -- pokefirered/src/battle_message.c:1151
    say_id(({ [0] = "STRINGID_PKMNBROKEFREE", "STRINGID_ITAPPEAREDCAUGHT",
      "STRINGID_AARGHALMOSTHADIT", "STRINGID_SHOOTSOCLOSE" })[math.min(3, tonumber(shakes) or 0)], fill)
    return "fail_catch", msgs, true, false
  end

  -- pokefirered/src/item_use.c:755 BattleUseFunc_StatBooster
  if BattleItems.isStatBooster(itemId) then
    local e = effect_of(itemId)
    local battler = user_battler(st, battlerId)
    if not stat_booster(st, battler, e, true) then
      -- pokefirered/src/item_use.c:758
      say(wont_have_effect())
      return "error", msgs, false, false
    end
    -- pokefirered/src/item_use.c:774
    Bag.remove(bag, itemId, 1)
    -- pokefirered/src/data/pokemon/item_effects.h:225
    if battler.mon then
      local Pokemon = require("src.core.game3.pokemon")
      Pokemon.itemFriendship(battler.mon, Pokemon.STAT_BOOST_FRIENDSHIP_CHANGE,
        { mapSec = Pokemon.currentMapSec(session) })
    end
    -- pokefirered/data/battle_scripts_2.s:130
    return "xitem", msgs, true, false, stat_booster_text(st, battler, e)
  end

  -- Medicine / berries on party mon
  local use = ItemsData.fieldUseKind(itemId)
  local info = ItemsData.info(itemId)
  -- pokefirered/src/party_menu.c:4675 TryUsePPItemInBattle
  if use == "pp" then
    local party = st.playerParty or (session and session.party)
    if not partySlot then
      return "need_slot", msgs, false, false
    end
    local mon = party and party[partySlot]
    local battler
    if st.player and st.player.partyIndex == partySlot then
      battler = st.player
    elseif st.double and st.battlers and st.battlers[2] and st.battlers[2].partyIndex == partySlot then
      battler = st.battlers[2]
    end
    if battler then
      local State = require("src.core.game3.battle.state")
      State.syncBattlerToParty(battler, party)
    end
    if not mon or not ItemUse.applyPpItem(mon, itemId, moveSlot or 1, battler, session) then
      say(wont_have_effect())
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    -- pokefirered/src/party_menu.c:4700
    return "heal", msgs, true, false, ItemUse.ppItemText(mon, itemId, moveSlot or 1)
  end
  local bu = info and tonumber(info.battleUsage) or 0
  if bu == 1 or use == "heal" or use == "status" or use == "revive"
      or (info and info.pocket == "BERRY_POUCH") then
    -- Prefer in-battle party copy (writeback syncs to session).
    local party = st.playerParty or (session and session.party)
    if not partySlot then
      return "need_slot", msgs, false, false
    end
    local mon = party and party[partySlot]
    if not mon then
      say(wont_have_effect())
      return "error", msgs, false, false
    end
    local ok, cured = false, nil
    local hpBefore = tonumber(mon.hp) or 0
    local mk = ItemsData.medicineKind(itemId)
    local e = effect_of(itemId)
    local active = active_for_slot(st, partySlot)
    local asleep = mon.status == "SLP" or mon.status == 5 or (tonumber(mon.sleep) or 0) > 0
    -- pokefirered/src/pokemon.c:4258
    if mk == "revive" or use == "revive" or num == ItemUse.ITEM_REVIVAL_HERB then
      local max = num == 25 or num == ItemUse.ITEM_REVIVAL_HERB
      if num == 45 then
        ok = ItemUse.reviveAll(party)
      else
        ok = ItemUse.revive(mon, max)
      end
    elseif mk == "status" or use == "status" then
      ok, cured = ItemUse.clearStatus(mon, itemId)
    else
      ok = ItemUse.healMon(session, mon, itemId)
    end
    if status2_cure(active, e, true) then ok = true end
    if not ok then
      say(wont_have_effect())
      return "error", msgs, false, false
    end
    -- pokefirered/src/pokemon.c:4178
    if active and asleep and e and band(e[4], 0x20) ~= 0 and not (mon.status or (tonumber(mon.sleep) or 0) > 0) then
      active.expNightmare = nil
    end
    -- pokefirered/src/party_menu.c:5345
    if e then cured = ItemUse.cureKind(itemId) end
    -- pokefirered/src/pokemon.c:4481
    if num and ItemUse.BITTER_MEDICINE_FRIENDSHIP[num] then
      local Pokemon = require("src.core.game3.pokemon")
      Pokemon.itemFriendship(mon, ItemUse.BITTER_MEDICINE_FRIENDSHIP[num],
        { mapSec = Pokemon.currentMapSec(session) })
    end
    -- pokefirered/src/party_menu.c:4498
    if not BattleItems.isFlute(itemId) then Bag.remove(bag, itemId, 1) end
    if st.player and st.player.partyIndex == partySlot then
      sync_player_battler(st)
    end
    local b2 = st.double and st.battlers and st.battlers[2]
    if b2 and b2.partyIndex == partySlot then sync_player_battler(st, 2) end
    return "heal", msgs, true, false, ItemUse.medicineText(mon, hpBefore, cured)
  end

  say(Strings("This can't be used right now."))
  return "error", msgs, false, false
end

-- pokefirered/src/battle_controller_oak_old_man.c:388
function BattleItems.afterPlayerItem(st, adapter, itemId)
  if (ItemsData.toNumericId(itemId) or tonumber(itemId)) ~= 13 then return false end
  local Oak = require("src.core.game3.battle.oak_advice")
  return Oak.sayOnce(st, Oak.FLAG_HP_RESTORE, "keepAnEyeOnHp", function(t, id)
    if adapter and adapter.say then adapter:say(t, id) end
  end)
end

-- pokefirered/src/battle_message.c:1195
local ENEMY_CURE_TEXT = {
  [0] = "STRINGID_PKMNSITEMSNAPPEDOUT",
  [1] = "STRINGID_PKMNSITEMCUREDPARALYSIS",
  [2] = "STRINGID_PKMNSITEMDEFROSTEDIT",
  [3] = "STRINGID_PKMNSITEMHEALEDBURN",
  [4] = "STRINGID_PKMNSITEMCUREDPOISON",
  [5] = "STRINGID_PKMNSITEMWOKEIT",
}

-- pokefirered/src/pokemon.c:4001
local function enemy_item_effects(st, ad, b, e)
  local AiItems = require("src.core.game3.battle.ai_items")
  local band = AiItems.band
  if band(e[1], 0x80) ~= 0 and b.expInfatuated then b.expInfatuated, b.expInfatuatedWith = nil, nil end
  if band(e[1], 0x30) ~= 0 and not b.expFocusEnergy then
    b.expFocusEnergy, b.focusEnergy = true, true
  end
  local function raise(key, n)
    local cur = b.stages and b.stages[key] or 0
    if n > 0 and cur < 6 then ad:changeStages(b, { [key] = n }) end
  end
  raise("attack", band(e[1], 0x0F))
  raise("defense", math.floor(band(e[2], 0xF0) / 16))
  raise("speed", band(e[2], 0x0F))
  raise("accuracy", math.floor(band(e[3], 0xF0) / 16))
  raise("spAtk", band(e[3], 0x0F))
  local side = ad:ownSide(b)
  if band(e[4], 0x80) ~= 0 and side and (tonumber(side.expMistTurns) or 0) == 0 then
    side.expMistTurns = 5
  end
  local s = AiItems.statusName(b)
  local cure = (band(e[4], 0x20) ~= 0 and s == "SLP") or (band(e[4], 0x10) ~= 0 and (s == "PSN" or s == "TOX"))
    or (band(e[4], 0x08) ~= 0 and s == "BRN") or (band(e[4], 0x04) ~= 0 and s == "FRZ")
    or (band(e[4], 0x02) ~= 0 and s == "PAR")
  if cure then
    if s == "SLP" then b.expNightmare = nil end
    ad:clearStatus(b)
  end
  if band(e[4], 0x01) ~= 0 and (tonumber(b.confusionTurns) or 0) > 0 then b.confusionTurns = nil end
  if band(e[5], 0x04) ~= 0 then
    local hp, maxHp = ad:hp(b), ad:maxHp(b)
    local revive = band(e[5], 0x40) ~= 0
    if (revive and hp == 0) or (not revive and hp ~= 0) then
      local data = e.hp or 0
      if data == AiItems.HEAL_HP_FULL then
        data = maxHp - hp
      elseif data == AiItems.HEAL_HP_HALF then
        data = math.floor(maxHp / 2)
        if data == 0 then data = 1 end
      elseif data == AiItems.HEAL_HP_LVL_UP then
        data = 0
      end
      if maxHp ~= hp then ad:heal(b, data) end
    end
  end
  if b.mon then b.status = b.mon.status end
end

-- pokefirered/src/battle_main.c:4150
function BattleItems.enemyUse(st, adapter, act)
  local AiItems = require("src.core.game3.battle.ai_items")
  local State = require("src.core.game3.battle.state")
  local id = act and (act.battler or 1) or 1
  local b = State.battler(st, id)
  if not b or not b.mon or not act.item then return false end
  local item = act.item
  local e = AiItems.effect(item)
  local kind = act.aiItemType or (e and AiItems.itemType(item, e))
  local flags = tonumber(act.aiItemFlags) or 0
  b.expFuryCutter, b.destinyBond, b.expDestinyBond, b.expGrudge = 0, nil, nil, nil
  local fill = { scrActive = b, atk = b, lastItem = item }
  -- pokefirered/data/battle_scripts_2.s:134
  adapter:pushEvent({ kind = "item_use", battler = id, side = b.side, item = item, se = "SE_USE_ITEM" })
  adapter:sayText("STRINGID_TRAINER1USEDITEM", fill)
  if e then enemy_item_effects(st, adapter, b, e) end
  local T = AiItems.TYPE
  if kind == T.FULL_RESTORE or kind == T.HEAL_HP then
    adapter:sayText("STRINGID_PKMNSITEMRESTOREDHEALTH", fill)
    adapter:pushEvent({ kind = "status", battler = id, side = b.side })
  elseif kind == T.CURE_CONDITION then
    local chooser = 0
    if flags % 2 == 1 then
      if AiItems.band(flags, 0x3E) ~= 0 then chooser = 5 end
    else
      local f = flags
      while f > 0 and f % 2 == 0 do
        f = math.floor(f / 2)
        chooser = chooser + 1
      end
    end
    adapter:sayText(ENEMY_CURE_TEXT[chooser], fill)
    adapter:pushEvent({ kind = "status", battler = id, side = b.side })
  elseif kind == T.X_STAT then
    if AiItems.band(flags, 0x80) ~= 0 then
      adapter:sayText("STRINGID_PKMNUSEDXTOGETPUMPED", fill)
    else
      local stat, f = 1, flags
      while f > 0 and f % 2 == 0 do
        f = math.floor(f / 2)
        stat = stat + 1
      end
      -- pokefirered/src/battle_main.c:4205
      fill.buff1 = RomText.at("gStatNamesTable", stat)
      fill.buff2 = BattleText.get("STRINGID_STATROSE")
      adapter:sayText("STRINGID_USINGITEMSTATOFPKMNROSE", fill)
    end
  elseif kind == T.GUARD_SPECS then
    -- pokefirered/src/battle_main.c:4216
    if st.double then
      adapter:sayText("STRINGID_PKMNGETTINGPUMPED", fill)
    else
      adapter:sayText("STRINGID_PKMNSHROUDEDINMIST", fill)
    end
  end
  return true
end

return BattleItems
