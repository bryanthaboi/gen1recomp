-- Battle entry for Sevii: owned game3 battle + white-out / FRLG money (H3/H6/H7).
-- No host Battle / no save.party swap. H4 remaps are transitional (party_view keeps Gen3 ids).

local Party = require("src.core.game3.party")
local PartyView = require("src.core.game3.battle.party_view")
local Downgrade = require("src.core.game3.battle_downgrade")
local Pokemon = require("src.core.game3.pokemon")
local ModRuntime = require("src.mods.Runtime")

local BattleBridge = {}

BattleBridge._remap = nil
BattleBridge._battleParty = nil
BattleBridge._interceptInstalled = false
BattleBridge._whiteoutHook = nil
BattleBridge._finish = nil

local function runtimeActive()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.isActive and Runtime.isActive()
end

-- pokefirered/include/constants/flags.h:1327
local FLAG_SYS_SAFARI_MODE = 0x800

-- pokefirered/src/battle_setup.c:239
local function safari_mode_active(session)
  if session and session.safari and session.safari.active then return true end
  local okS, Space = pcall(require, "src.core.game3.scripting.space")
  if not okS or not Space or not Space.store then return false end
  local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
  if not okF or not Flags or not Flags.getFlag then return false end
  return Flags.getFlag(Space.store, nil, FLAG_SYS_SAFARI_MODE) and true or false
end

-- pokefirered/src/overworld.c:1270
local function map_battle_scene(mapId, game)
  if type(mapId) ~= "string" then return nil end
  local g = game
  if not g then
    local Runtime = package.loaded["src.core.game3.runtime"]
    g = Runtime and Runtime._game
  end
  local def = g and g.data and g.data.maps and g.data.maps[mapId]
  if not def then return nil end
  return tonumber(def.battleType)
end
BattleBridge.mapBattleScene = map_battle_scene

local BADGE_LOSS_MULT = { 2, 4, 6, 9, 12, 16, 20, 25, 30 } -- index 0..8 badges
local BADGE_FLAGS = {
  0x820, 0x821, 0x822, 0x823, 0x824, 0x825, 0x826, 0x827, -- FLAG_BADGE01..08
}

local function count_badges(session, hostSave)
  local flags = nil
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.getStore and Space.getStore()
  if store and store.flags then
    flags = store.flags
  elseif session and session.flags then
    flags = session.flags
  end
  if flags then
    local n = 0
    for _, fid in ipairs(BADGE_FLAGS) do
      if flags[fid] or flags[tostring(fid)] then n = n + 1 end
    end
    return math.min(8, n)
  end
  local badges = 0
  if hostSave then
    local inv = hostSave.inventory or {}
    for id, qty in pairs(inv) do
      if type(id) == "string" and id:find("BADGE", 1, true) and (qty or 0) > 0 then
        badges = badges + 1
      end
    end
    if type(hostSave.badges) == "number" then
      badges = math.max(badges, hostSave.badges)
    elseif type(hostSave.badges) == "table" then
      local c = 0
      for _, v in pairs(hostSave.badges) do if v then c = c + 1 end end
      badges = math.max(badges, c)
    end
  end
  return math.max(0, math.min(8, badges))
end

function BattleBridge.calcMoneyLossFrlg(session, hostSave)
  local maxLv = 1
  local party = session and session.party
  if type(party) == "table" then
    for _, mon in ipairs(party) do
      local lv = tonumber(mon and mon.level) or 1
      if lv > maxLv then maxLv = lv end
    end
  end
  local badges = count_badges(session, hostSave)
  -- pret: toplevel * 4 * sWhiteOutMoneyLossMultipliers[nbadges]
  local mult = BADGE_LOSS_MULT[badges + 1] or 2
  return maxLv * 4 * mult
end

function BattleBridge.applyFrlgMoneyLoss(session, hostSave)
  local loss = BattleBridge.calcMoneyLossFrlg(session, hostSave)
  local money = tonumber(session and session.money) or tonumber(hostSave and hostSave.money) or 0
  money = math.max(0, money - loss)
  if session then session.money = money end
  if hostSave then hostSave.money = money end
  return loss, money
end

function BattleBridge.installWhiteoutIntercept(mod, game)
  if BattleBridge._interceptInstalled then return end
  BattleBridge._interceptInstalled = true

  local function onWhiteout()
    local Runtime = require("src.core.game3.runtime")
    if not Runtime.isActive() then return false end
    local session = Runtime.getSession()
    BattleBridge.applyFrlgMoneyLoss(session, game and game.save)
    local Field = require("src.core.game3.field")
    Field.respawnAtHeal()
    return true
  end
  BattleBridge._whiteoutHook = onWhiteout

  local ok, World = pcall(require, "src.world.gen2.World")
  if ok and World then
    if type(World.whiteOut) == "function" and not World._game3WhiteOut then
      local prev = World.whiteOut
      World.whiteOut = function(self, ...)
        if onWhiteout() then return end
        return prev(self, ...)
      end
      World._game3WhiteOut = true
    end
    if type(World.warpToPokemonCenter) == "function" and not World._game3WarpPC then
      local prev = World.warpToPokemonCenter
      World.warpToPokemonCenter = function(self, ...)
        if runtimeActive() and onWhiteout() then return end
        return prev(self, ...)
      end
      World._game3WarpPC = true
    end
  end
end

local LEAD_FIELDS = { "species", "level", "rawIv", "iv", "ivs", "evs", "heldItem",
  "moves", "personality" }

-- pokefirered/src/battle_main.c:1539
local function hooked_trainer_party(foe, trainerId)
  if type(foe) ~= "table" or type(foe.party) ~= "table" or #foe.party == 0 then return foe end
  local G3 = require("src.mods.Gen3Compat")
  local named = G3.partyNames(foe.party)
  local out = ModRuntime.call("trainer.party", function(_, _, party)
    return party
  end, foe.trainerClass, trainerId, named)
  if type(out) ~= "table" or #out == 0 then return foe end
  local copy = {}
  for k, v in pairs(foe) do copy[k] = v end
  copy.party = G3.partyNums(out)
  local lead = copy.party[1]
  for _, key in ipairs(LEAD_FIELDS) do copy[key] = lead[key] end
  return copy
end

local function battle_payload(Battle, opts, foe, isDouble)
  local st = Battle.getState and Battle.getState()
  local G3 = require("src.mods.Gen3Compat")
  local enemy = st and st.enemy and st.enemy.mon
  local sp = enemy and tonumber(enemy.species or enemy.speciesId)
  local tid = opts.trainerId or (foe and foe.trainerId)
  return {
    battle = st, kind = opts.wild and "wild" or "trainer",
    trainerId = (not opts.wild) and tid or nil,
    trainerClass = (not opts.wild) and foe and foe.trainerClass or nil,
    species = G3.speciesName(sp), speciesId = sp,
    level = enemy and enemy.level, double = isDouble and true or false,
  }
end

local function writeback(session, battleParty, remap, result, save, opts)
  opts = opts or {}
  if not session then return end
  Downgrade.writebackPlayerPp(session.party, session.move_overlay, remap, battleParty)
  for i, mon in ipairs(session.party or {}) do
    local src = battleParty and battleParty[i]
    if src then
      Party.applyBattleFields(mon, {
        hp = src.hp,
        maxHp = src.maxHp,
        status = src.status,
        sleep = src.sleep,
        level = src.level,
        exp = src.exp,
        pp = src.pp,
        maxPp = src.maxPp,
        moves = src.moves,
        species = src.species or src.speciesId,
        speciesId = src.speciesId or src.species,
        name = src.name,
        growthRate = src.growthRate,
        evs = src.evs,
        friendship = src.friendship,
        pokerus = src.pokerus,
        attack = src.attack or src.atk,
        defense = src.defense or src.def,
        speed = src.speed or src.spe,
        spAtk = src.spAtk or src.spa,
        spDef = src.spDef or src.spd,
        _allowMoveRewrite = true,
      })
    end
  end
  local lost = (result == "lose" or result == "whiteout" or result == "blackout")
  if not lost then return end

  -- pret CB2_EndTrainerBattle EARLY_RIVAL + RIVAL_BATTLE_HEAL_AFTER:
  -- heal and continue script — no white-out warp.
  local flags = tonumber(opts.rivalFlags) or 0
  local healAfter = opts.noWhiteout
    or (opts.earlyRival and (flags % 2 == 1)) -- bit0 = RIVAL_BATTLE_HEAL_AFTER
  if healAfter then
    Party.healAll(session.party)
    return
  end

  BattleBridge.applyFrlgMoneyLoss(session, save)
  local Field = require("src.core.game3.field")
  Field.respawnAtHeal()
end

-- pokefirered/src/pokemon.c:5483
local function league_trainer_class(foe, opts)
  local tid = tonumber((opts and opts.trainerId) or (foe and foe.trainerId))
  if tid then
    local okT, Trainers = pcall(require, "src.core.game3.scripting.trainers")
    local info = okT and Trainers and Trainers.info and Trainers.info(tid)
    if info and info.class ~= nil then return info.class end
  end
  return foe and foe.trainerClass
end

-- pokefirered/src/battle_main.c:713
function BattleBridge.applyLeagueFriendship(session, battleParty, foe, opts)
  opts = opts or {}
  if opts.wild or type(session) ~= "table" then return false end
  if not Pokemon.isLeagueTrainerClass(league_trainer_class(foe, opts)) then return false end
  local ctx = { leagueBattle = true, mapSec = Pokemon.currentMapSec(session) }
  local changed = false
  for i, mon in ipairs(session.party or {}) do
    if Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_LEAGUE_BATTLE, ctx) then
      changed = true
      if battleParty and battleParty[i] then
        battleParty[i].friendship = Pokemon.friendshipOf(mon)
      end
    end
  end
  return changed
end

--- Start owned game3 battle (async). opts.done(result) when finished.
-- opts.earlyRival / opts.rivalFlags / opts.noWhiteout: Oaks Lab tutorial loss.
function BattleBridge.start(mod, game, foe, opts)
  opts = opts or {}
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not session then return nil, "no session" end

  BattleBridge.installWhiteoutIntercept(mod, game)

  local battleParty, remap = PartyView.fromSession(session.party, session.move_overlay)
  if #battleParty == 0 then return nil, "empty party" end
  local isDouble = (not opts.wild) and (opts.double or (foe and foe.doubleBattle)) and true or false
  if isDouble and Party.monsStateToDoubles(session.party) ~= Party.PLAYER_HAS_TWO_USABLE_MONS then
    return nil, "need two mons"
  end

  BattleBridge._remap = remap
  BattleBridge._battleParty = battleParty

  BattleBridge.applyLeagueFriendship(session, battleParty, foe, opts)

  local save = game and game.save
  local done = opts.done

  if not opts.wild and ModRuntime.wantsHook("trainer.party") then
    foe = hooked_trainer_party(foe, opts.trainerId or (foe and foe.trainerId))
  end

  local function finish(result)
    -- pokefirered/src/battle_main.c:196
    local okN, Natives = pcall(require, "src.core.game3.scripting.natives")
    if okN and Natives and Natives.outcome_to_code then
      session.battleOutcome = Natives.outcome_to_code(result or "win")
    end
    writeback(session, battleParty, remap, result, save, opts)
    -- pokefirered/src/battle_main.c:3861
    if ModRuntime.wants("battle.ended") then
      local B = package.loaded["src.core.game3.battle"]
      ModRuntime.emit("battle.ended", {
        battle = B and B.getState and B.getState() or nil, result = result or "win",
      })
    end
    BattleBridge._remap = nil
    BattleBridge._battleParty = nil
    BattleBridge._finish = nil
    pcall(function()
      require("src.core.game3.audio").restoreMapSong()
    end)
    local okF, Fade = pcall(require, "src.ui.game3.fade")
    if okF and Fade and Fade.begin and not opts.headless and opts.fade ~= false then
      Fade.begin(Fade.MODE.FROM_BLACK, 1)
    end
    -- pokefirered/src/battle_setup.c:432
    local okS, Space = pcall(require, "src.core.game3.scripting.space")
    if okS and Space and Space.returnToField then
      pcall(Space.returnToField)
    end
    if done then done(result or "win") end
  end
  BattleBridge._finish = finish

  local Battle = require("src.core.game3.battle")
  local Map = package.loaded["src.core.game3.map"] or require("src.core.game3.map")
  local mapId = Map.current
  local mapDef = game and game.data and game.data.maps and mapId and game.data.maps[mapId]
  local mapKind = (mapDef and mapDef.kind) or opts.mapKind
  local mapType = (mapDef and mapDef.mapType) or opts.mapType
  local mapBattleScene = (mapDef and mapDef.battleType) or opts.mapBattleScene
    or map_battle_scene(mapId, game)
  -- pokefirered/src/battle_setup.c:471 PlayerGetDestCoords
  local mapBehavior = opts.mapBehavior
  if mapBehavior == nil then
    local okC, Collision = pcall(require, "src.core.game3.collision")
    local okP, Player = pcall(require, "src.core.game3.player")
    if okC and okP and Collision.behavior then
      local bx, by = Player.cellX, Player.cellY
      if Player.moving then bx, by = Player.targetX, Player.targetY end
      mapBehavior = Collision.behavior(bx, by)
    end
  end

  local gender = 0
  if session.gender == "female" or session.gender == "F" or session.gender == 1 then
    gender = 1
  elseif save and (save.gender == 1 or save.gender == "female" or save.gender == "F") then
    gender = 1
  end

  local wildScripted = opts.wildScripted or (foe and foe.wildScripted)
  local legendary = opts.legendary or (foe and foe.legendary)
  local roamer = opts.roamer or (foe and foe.roamer)
  -- pokefirered/src/battle_setup.c:237
  local standardWild = opts.wild and not opts.trainerId
    and not wildScripted and not legendary and not roamer
    and not opts.firstBattle and not opts.oldManTutorial
  local startOpts = {
    wild = opts.wild,
    wildScripted = wildScripted,
    legendary = legendary,
    safari = opts.safari or (foe and foe.safari)
      or (standardWild and safari_mode_active(session)) or nil,
    roamer = roamer,
    firstBattle = opts.firstBattle or (foe and foe.firstBattle),
    oldManTutorial = opts.oldManTutorial or (foe and foe.oldManTutorial),
    aiFlags = opts.aiFlags or (foe and foe.aiFlags),
    double = isDouble,
    playerParty = battleParty,
    foe = foe,
    headless = opts.headless,
    fade = opts.fade,
    rng = opts.rng,
    mapKind = mapKind,
    mapType = mapType,
    mapBehavior = mapBehavior,
    mapBattleScene = mapBattleScene,
    terrain = opts.terrain,
    trainerId = opts.trainerId or (foe and foe.trainerId),
    defeatText = opts.defeatText or (foe and foe.defeatText),
    victoryText = opts.victoryText or (foe and foe.victoryText),
    earlyRival = opts.earlyRival,
    rivalFlags = opts.rivalFlags,
    rivalName = opts.rivalName or session.rivalName or (save and save.rivalName),
    playerGender = opts.playerGender or gender,
    onDone = function(result)
      finish(result)
    end,
    onStarted = function()
      -- pokefirered/src/battle_main.c:612
      if ModRuntime.wants("battle.started") then
        ModRuntime.emit("battle.started", battle_payload(Battle, opts, foe, isDouble))
      end
    end,
  }

  local function resolve_battle_song(o, so)
    if o and o.song then return o.song end
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if not (okA and Audio) then return nil end
    if (o and o.wild) or (so and so.wild) then
      local f = (o and o.foe) or (so and so.foe)
      local sp = f and (f.species or f.id or f.speciesId)
      if sp == 150 then
        return Audio.role("battleMewtwo") or 340
      elseif sp == 386 then
        return Audio.role("battleDeoxys") or 339
      elseif sp == 144 or sp == 145 or sp == 146 or sp == 249 or sp == 250 then
        return Audio.role("battleLegend") or 341
      end
      return Audio.role("battleWild") or 298
    else
      local tid = (so and so.trainerId) or (o and o.trainerId) or (o and o.foe and o.foe.trainerId)
      local okTr, Trainers = pcall(require, "src.core.game3.scripting.trainers")
      if not (okTr and Trainers and Trainers.getBattleMusicRole) then
        return Audio.role("battleTrainer") or 297
      end
      local role, fallback = Trainers.getBattleMusicRole(tid)
      return Audio.role(role) or fallback
    end
  end

  local battleSong = resolve_battle_song(opts, startOpts)
  startOpts.song = battleSong

  -- pret CreateBattleStartTask: PlayMapChosenOrBattleBGM starts immediately
  -- on frame 1 of the battle transition on the overworld.
  if not opts.headless and battleSong then
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.playSong then
      Audio.playSong(battleSong)
    end
  end

  local function doStart()
    local ok, err = Battle.start(startOpts)
    if not ok then
      BattleBridge._finish = nil
      BattleBridge._remap = nil
      BattleBridge._battleParty = nil
      if done then done("win") end
      return nil, err
    end
    return true
  end

  if opts.headless or opts.fade == false then
    return doStart()
  end

  local okT, BattleTransition = pcall(require, "src.core.game3.battle_transition")
  if okT and BattleTransition and BattleTransition.start then
    local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
    if Field and Field.lock then Field.lock() end

    local leadMon = battleParty and battleParty[1]
    local playerLv = leadMon and (leadMon.level or leadMon.lvl) or 5
    local foeLv = (foe and foe.level) or (foe and foe.party and foe.party[1] and (foe.party[1].level or foe.party[1].lvl)) or 3
    if isDouble then
      playerLv, foeLv = PartyView.doubleTransitionLevels(battleParty, foe and foe.party)
    end

    local pickOpts = {
      wild = opts.wild,
      mapKind = mapKind,
      terrain = opts.terrain,
      playerLevel = playerLv,
      enemyLevel = foeLv,
      trainerId = startOpts.trainerId,
      playerGender = startOpts.playerGender,
      transitionId = opts.transitionId,
    }
    local tid = BattleTransition.pick(pickOpts)
    BattleTransition.start(tid, pickOpts, function()
      doStart()
    end)
    return true
  end

  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.begin then
    local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
    if Field and Field.lock then Field.lock() end
    Fade.begin(Fade.MODE.TO_BLACK, 1, function()
      doStart()
    end)
    return true
  end
  return doStart()
end

function BattleBridge.startWild(mod, game, encounter, opts)
  opts = opts or {}
  opts.wild = true
  -- pret battle_setup.c resets the encounter cooldown when a battle starts, so
  -- the grace period re-arms after every wild battle -- including ones nothing
  -- stepped into (scripted battles, fishing).
  local okE, Encounters = pcall(require, "src.core.game3.encounters")
  if okE and Encounters and Encounters.resetRateModifiers then
    Encounters.resetRateModifiers()
  end
  return BattleBridge.start(mod, game, encounter, opts)
end

--- Tests / emergency: complete pending battle writeback.
function BattleBridge.finishPending(result)
  local Battle = package.loaded["src.core.game3.battle"]
    or require("src.core.game3.battle")
  if Battle.isActive and Battle.isActive() then
    Battle.abort(result or "win")
    return
  end
  if BattleBridge._finish then
    local f = BattleBridge._finish
    BattleBridge._finish = nil
    return f(result or "win")
  end
end

return BattleBridge
