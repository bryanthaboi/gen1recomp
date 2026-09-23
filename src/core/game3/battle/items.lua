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

local X_STAT = {
  [75] = "attack",   -- X ATTACK
  [76] = "defense",  -- X DEFEND
  [77] = "speed",    -- X SPEED
  [78] = "accuracy", -- X ACCURACY
  [79] = "spAtk",    -- X SPECIAL
}


local Catching = require("src.core.game3.battle.catching")
local Strings = require("src.core.Strings")

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
  if num and X_STAT[num] then return false end -- X items
  local use = ItemsData.fieldUseKind(id)
  local info = ItemsData.info(id)
  local bu = info and tonumber(info.battleUsage) or 0
  if bu == 1 or use == "heal" or use == "status" or use == "revive"
      or (info and info.pocket == "BERRY_POUCH") then
    return true
  end
  return false
end

function BattleItems.canUseOn(st, itemId, partySlot, mon, moveSlot)
  if not mon or not itemId then return false, Strings("It won't have any effect.") end
  if mon.isEgg then return false, Strings("An EGG can't be used on.") end
  local hp = tonumber(mon.hp) or 0
  local maxHp = tonumber(mon.maxHp or mon.maxhp) or 1
  local mk = ItemsData.medicineKind(itemId)
  local use = ItemsData.fieldUseKind(itemId)
  -- pokefirered/src/party_menu.c:4675 TryUsePPItemInBattle
  if use == "pp" then
    if ItemUse.ppItemHasEffect(mon, itemId, moveSlot or 1) then return true end
    return false, Strings("It won't have any effect.")
  end
  if mk == "revive" or use == "revive" then
    if hp > 0 then return false, Strings("It won't have any effect.") end
    return true
  elseif hp <= 0 then
    return false, Strings("It won't have any effect.")
  elseif mk == "status" or use == "status" then
    local s = mon.status
    if not s or s == 0 or s == "" then return false, Strings("It won't have any effect.") end
    return true
  else
    if hp >= maxHp then return false, Strings("It won't have any effect.") end
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
  local function say(t)
    msgs[#msgs + 1] = t
    if adapter and adapter.say then adapter:say(t) end
  end

  if not itemId or not bag then
    return "error", msgs, false, false
  end
  if not Bag.has(bag, itemId, 1) then
    say(Strings("You don't have that item."))
    return "error", msgs, false, false
  end

  local num = ItemsData.toNumericId(itemId) or tonumber(itemId)
  local name = ItemsData.displayName(itemId)

  -- Poké Doll → flee wild
  if num == 80 then
    if not st.wild then
      say(Strings("This can't be used right now."))
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(Strings("%s used\nthe %s!", tostring(session and session.name or "RED"), name))
    say(Strings("Got away safely!"))
    return "doll", msgs, true, true
  end

  -- Balls
  if BattleItems.isBall(itemId) then
    if not st.wild then
      say(Strings("The TRAINER blocked\nthe BALL!"))
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(Strings("%s used\nthe %s!", tostring(session and session.name or "RED"), name))
    local rng = adapter and adapter.rng and adapter:rng() or math.random
    local foe = Catching.targetFor(st, battlerId)
    local caught, shakes = BattleItems.tryCatch(itemId, foe, st, rng, session)
    if caught then
      local res = Catching.storeCaught(session, foe, itemId)
      local fmon = foe and foe.mon
      local ename = (fmon and ((fmon.nickname ~= "" and fmon.nickname) or fmon.name))
        or Pokemon.name(foe and foe.species) or "POKéMON"
      say(Strings("Gotcha!\n%s was caught!", ename))
      if res and res.firstTimeCaught then
        say(Strings("%s's data was\nadded to the POKéDEX.", ename))
      end
      if res and res.location == "pc" then
        -- pokefirered/src/battle_script_commands.c:9617
        local Storage = require("src.core.game3.storage")
        say(Storage.pcTransferMessage(session, ename))
      end
      return "catch", msgs, true, true
    end
    if shakes == 0 then
      say(Strings("Oh no! The POKéMON broke free!"))
    elseif shakes == 1 then
      say(Strings("Aww! It appeared to be caught!"))
    elseif shakes == 2 then
      say(Strings("Aargh! Almost had it!"))
    else
      say(Strings("Shoot! It was so close too!"))
    end
    return "fail_catch", msgs, true, false
  end

  -- X items
  if num and X_STAT[num] then
    local stat = X_STAT[num]
    local battler = user_battler(st, battlerId)
    if not battler or not battler.stages then
      return "error", msgs, false, false
    end
    local cur = battler.stages[stat] or 0
    if cur >= 6 then
      say(Strings("It won't have any effect."))
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(Strings("%s used\nthe %s!", tostring(session and session.name or "RED"), name))
    if adapter and adapter.changeStages then
      adapter:changeStages(battler, { [stat] = 1 })
    else
      battler.stages[stat] = math.min(6, cur + 1)
    end
    local label = Strings(({
      attack = "ATTACK", defense = "DEFENSE", speed = "SPEED",
      accuracy = "ACCURACY", spAtk = "SP. ATK",
    })[stat] or stat)
    local pname = battler.mon and (battler.mon.nickname or battler.mon.name) or "POKéMON"
    say(Strings("%s's %s\nrose!", pname, label))
    -- pokefirered/src/data/pokemon/item_effects.h:225
    if battler.mon then
      local Pokemon = require("src.core.game3.pokemon")
      Pokemon.itemFriendship(battler.mon, Pokemon.STAT_BOOST_FRIENDSHIP_CHANGE,
        { mapSec = Pokemon.currentMapSec(session) })
    end
    return "xitem", msgs, true, false
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
      say(Strings("It won't have any effect."))
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(Strings("%s used\nthe %s!", tostring(session and session.name or "RED"), name))
    return "heal", msgs, true, false
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
      say(Strings("It won't have any effect."))
      return "error", msgs, false, false
    end
    local ok = false
    local mk = ItemsData.medicineKind(itemId)
    -- pokefirered/src/pokemon.c:4258
    if mk == "revive" or use == "revive" or num == ItemUse.ITEM_REVIVAL_HERB then
      local max = num == 25 or num == ItemUse.ITEM_REVIVAL_HERB
      if num == 45 then
        ok = ItemUse.reviveAll(party)
      else
        ok = ItemUse.revive(mon, max)
      end
    elseif mk == "status" or use == "status" then
      ok = ItemUse.clearStatus(mon, itemId)
    else
      ok = ItemUse.healMon(session, mon, itemId)
    end
    if not ok then
      say(Strings("It won't have any effect."))
      return "error", msgs, false, false
    end
    -- pokefirered/src/pokemon.c:4481
    if num and ItemUse.BITTER_MEDICINE_FRIENDSHIP[num] then
      local Pokemon = require("src.core.game3.pokemon")
      Pokemon.itemFriendship(mon, ItemUse.BITTER_MEDICINE_FRIENDSHIP[num],
        { mapSec = Pokemon.currentMapSec(session) })
    end
    Bag.remove(bag, itemId, 1)
    say(Strings("%s used\nthe %s!", tostring(session and session.name or "RED"), name))
    if st.player and st.player.partyIndex == partySlot then
      sync_player_battler(st)
    end
    local b2 = st.double and st.battlers and st.battlers[2]
    if b2 and b2.partyIndex == partySlot then sync_player_battler(st, 2) end
    -- pokefirered/src/battle_controller_oak_old_man.c:394
    if num == 13 then
      local Oak = require("src.core.game3.battle.oak_advice")
      Oak.sayOnce(st, Oak.FLAG_HP_RESTORE, "keepAnEyeOnHp", say)
    end
    return "heal", msgs, true, false
  end

  say(Strings("This can't be used right now."))
  return "error", msgs, false, false
end

local ENEMY_CURE_TEXT = {
  [0] = Strings.source("%s's %s\nsnapped it out of confusion!"),
  [1] = Strings.source("%s's %s\ncured paralysis!"),
  [2] = Strings.source("%s's %s\ndefrosted it!"),
  [3] = Strings.source("%s's %s\nhealed its burn!"),
  [4] = Strings.source("%s's %s\ncured poison!"),
  [5] = Strings.source("%s's %s\nwoke it from its sleep!"),
}

local ENEMY_STAT_NAME = { [1] = "ATTACK", [2] = "DEFENSE", [3] = "SPEED", [4] = "SP. ATK", [5] = "SP. DEF", [6] = "accuracy" }

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
  local iname = ItemsData.displayName(item)
  local bname = adapter:displayName(b)
  local trainer = (st.trainerClassName and st.trainerClassName ~= "")
    and (st.trainerClassName .. " " .. (st.trainerName or "")) or (st.trainerName or "TRAINER")
  -- pokefirered/data/battle_scripts_2.s:134
  adapter:pushEvent({ kind = "item_use", battler = id, side = b.side, item = item, se = "SE_USE_ITEM" })
  adapter:say(Strings("%s\nused %s!", trainer, iname))
  if e then enemy_item_effects(st, adapter, b, e) end
  local T = AiItems.TYPE
  if kind == T.FULL_RESTORE or kind == T.HEAL_HP then
    adapter:say(Strings("%s's %s\nrestored health!", bname, iname))
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
    adapter:say(Strings(ENEMY_CURE_TEXT[chooser] or ENEMY_CURE_TEXT[0], bname, iname))
    adapter:pushEvent({ kind = "status", battler = id, side = b.side })
  elseif kind == T.X_STAT then
    if AiItems.band(flags, 0x80) ~= 0 then
      adapter:say(Strings("%s used\n%s to hustle!", bname, iname))
    else
      local stat, f = 1, flags
      while f > 0 and f % 2 == 0 do
        f = math.floor(f / 2)
        stat = stat + 1
      end
      adapter:say(Strings("Using %s, the %s\nof %s rose!", iname, Strings(ENEMY_STAT_NAME[stat] or "ATTACK"), bname))
    end
  elseif kind == T.GUARD_SPECS then
    -- pokefirered/src/battle_main.c:4216
    if st.double then
      adapter:say(Strings("%s is getting\npumped!", bname))
    else
      adapter:say(Strings("%s became\nshrouded in MIST!", ((b.side == "player") and Strings("Ally") or Strings("Foe"))))
    end
  end
  return true
end

return BattleItems
