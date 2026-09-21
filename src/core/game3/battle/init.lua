-- Game3 owned battle engine entry.
-- Anim VM + hit sequencer pace presentation; effects/residuals owned.

local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")
local Engine = require("src.core.game3.battle.engine")
local Ui = require("src.core.game3.battle.ui")
local Damage = require("src.core.game3.battle.damage")
local Commands = require("src.core.game3.battle.commands")
local Moves = require("src.core.game3.battle.moves")
local Anim = require("src.core.game3.battle.anim")
local AnimSeq = require("src.core.game3.battle.anim_seq")
local ExpSeq = require("src.core.game3.battle.exp_seq")
local EvoSeq = require("src.core.game3.battle.evo_seq")
local IntroSeq = require("src.core.game3.battle.intro_seq")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Experience = require("src.core.game3.battle.experience")
local Pokemon = require("src.core.game3.pokemon")
local Evolution = require("src.core.game3.evolution")
local LearnMove = require("src.core.game3.battle.learn_move")
local Task = require("src.core.game3.task")
local Trainers = require("src.core.game3.scripting.trainers")
local SwitchSeq = require("src.core.game3.battle.switch_seq")
local Oak = require("src.core.game3.battle.oak_advice")
local Rules = require("src.core.game3.battle.rules")
local ModRuntime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local BattleChrome = require("src.ui.game3.battle_chrome")
local Fade = require("src.ui.game3.fade")

local Battle = {}

Battle._active = false
Battle._st = nil
Battle._adapter = nil
Battle._phase = nil
Battle._actions = nil
Battle._actionI = 1
Battle._onDone = nil
Battle._pendingEnd = nil
Battle._auto = false
Battle._metaAct = nil
Battle._headless = false
Battle._fade = true
Battle._lowHpSong = false
Battle._residualEvents = nil
Battle._residualIndex = 1
Battle._residualStepState = nil

local D = {}

-- Phases in which the level-up stat window can still be dismissed by the
-- player.  Input routing and drawing both key off this, so the window can never
-- linger somewhere it can no longer be dismissed (#2324).
local STAT_WINDOW_PHASES = {
  awarding = true,
  evolving = true,
  switching = true,
  shift_prompt = true,
  catch_nickname_prompt = true,
}

function Battle.statWindowPhase()
  return STAT_WINDOW_PHASES[Battle._phase] == true
end

-- pokefirered/src/battle_interface.c:2168
local function hp_bar_red(hp, maxHp)
  if not BattleChrome or not BattleChrome.hpBarLevel then return false end
  return BattleChrome.hpBarLevel(hp, maxHp) == "red"
end

local function stop_low_hp_song()
  if not Battle._lowHpSong then return end
  Battle._lowHpSong = false
  if Audio and Audio.stopSe and SE then
    Audio.stopSe(SE.SE_LOW_HEALTH)
  end
end

--- pret HandleLowHpMusicChange / HandleBattleLowHpMusicChange
local function update_low_hp_music()
  local st = Battle._st
  local mon = st and st.player and st.player.mon
  if not mon then
    stop_low_hp_song()
    return
  end
  if Anim.hpTweening and Anim.hpTweening() then return end
  local pres = Anim.present("player")
  local hp = math.floor(tonumber(pres and pres.displayHp) or tonumber(mon.hp) or 0)
  local maxHp = math.floor(tonumber(pres and pres.displayMaxHp) or tonumber(mon.maxHp) or 0)
  local red = hp_bar_red(hp, maxHp)
  if red and not Battle._lowHpSong then
    Battle._lowHpSong = true
    if Audio and Audio.playSe and SE then
      Audio.playSe(SE.SE_LOW_HEALTH, { loop = true })
    end
  elseif not red then
    stop_low_hp_song()
  end
end

local function party_menu_input(PartyMenu, input)
  local SummaryMenu = package.loaded["src.ui.game3.summary_menu"]
  if SummaryMenu and SummaryMenu.isOpen and SummaryMenu.isOpen() then
    if SummaryMenu.update then SummaryMenu.update(1 / 60) end
    SummaryMenu.handleInput(input)
    return
  end
  PartyMenu.handleInput(input)
end

-- pokefirered/src/battle_script_commands.c:1108
local function seq_push(text, wait)
  local t = tostring(text or "")
  local used = AnimSeq.isMoveUsedText(t) or t:find(" used\n", 1, true) or t:find(" used ", 1, true)
  Ui.pushTimed(t, tonumber(wait) or (used and 0 or 64))
end

local function push_msgs(list)
  for _, t in ipairs(list or {}) do
    Ui.push(t)
  end
end

local function foe_mon_from(foe)
  if type(foe) ~= "table" then
    return Damage.ensureStats({
      species = 16, level = 3,
      moves = { 33, 45 }, pp = { 35, 40 },
    }, 3)
  end
  local Pokemon = require("src.core.game3.pokemon")
  local Rng = require("src.core.game3.rng")
  local species = foe.species or foe.id or 16
  local personality = foe.personality
  if personality == nil then
    -- pret GenerateWildMon → CreateMonWithNature uses Random stream;
    -- Random32 matches Unown path; nature comes from personality % 25.
    personality = Rng.Random32()
  end
  local gender = foe.gender
  if gender ~= "M" and gender ~= "F" and gender ~= "U" then
    gender = Pokemon.gender and Pokemon.gender(species, personality) or "U"
  end
  local ivs = foe.ivs
  if ivs == nil then
    local iv1 = Rng.Random()
    local iv2 = Rng.Random()
    ivs = {
      hp  = iv1 % 32,
      atk = math.floor(iv1 / 32) % 32,
      def = math.floor(iv1 / 1024) % 32,
      spe = iv2 % 32,
      spa = math.floor(iv2 / 32) % 32,
      spd = math.floor(iv2 / 1024) % 32,
    }
  end
  local item = foe.item
  if item == nil then
    local meta = Pokemon.speciesMeta and Pokemon.speciesMeta(species)
    if meta then
      local common = tonumber(meta.itemCommon) or 0
      local rare = tonumber(meta.itemRare) or 0
      if common ~= 0 or rare ~= 0 then
        local r = Rng.Random() % 100
        if common ~= 0 and rare ~= 0 then
          if r < 50 then item = common
          elseif r < 55 then item = rare end
        elseif common ~= 0 then
          if r < 50 then item = common end
        elseif rare ~= 0 then
          if r < 5 then item = rare end
        end
      end
    end
  end
  local mon = {
    species = species,
    level = foe.level or 5,
    hp = foe.hp,
    maxHp = foe.maxHp,
    moves = foe.moves,
    pp = foe.pp,
    status = foe.status,
    attack = foe.attack or foe.atk,
    defense = foe.defense or foe.def,
    spAtk = foe.spAtk or foe.spa,
    spDef = foe.spDef or foe.spd,
    speed = foe.speed or foe.spe,
    item = item,
    gender = gender,
    ivs = ivs,
    evs = foe.evs,
    personality = personality,
    nature = foe.nature or (Pokemon.natureId and Pokemon.natureId(personality)) or 0,
    ability = foe.ability or foe.abilityId,
    dvs = foe.dvs,
  }
  local needMoves = not mon.moves or #mon.moves == 0
  if needMoves then
    if Pokemon.movesAtLevel then
      local moves, pp, maxPp = Pokemon.movesAtLevel(mon.species, mon.level)
      if moves and #moves > 0 then
        mon.moves = moves
        mon.pp = pp
        mon.maxPp = maxPp
      end
    end
  end
  if not mon.moves or #mon.moves == 0 then
    mon.moves = { 33 }
    mon.pp = { 35 }
    mon.maxPp = { 35 }
  end
  if not mon.maxPp or #mon.maxPp == 0 then
    mon.maxPp = {}
    for i, m in ipairs(mon.moves) do
      mon.maxPp[i] = Pokemon.movePp and Pokemon.movePp(m) or 35
    end
  end
  if not mon.pp or #mon.pp == 0 then
    mon.pp = {}
    for i, m in ipairs(mon.moves) do
      mon.pp[i] = mon.maxPp[i] or 35
    end
  end
  return Damage.ensureStats(mon, mon.level)
end

local ITEM_SILPH_SCOPE = 359

-- pokefirered/src/battle_setup.c:220
local function ghost_battle(opts, st)
  if opts.ghost ~= nil then return opts.ghost and true or false end
  if type(opts.foe) == "table" and opts.foe.ghost ~= nil then return opts.foe.ghost and true or false end
  if not st.wild then return false end
  local Map = package.loaded["src.core.game3.map"]
  local mapId = opts.mapId or (Map and Map.current)
  if type(mapId) ~= "string" then return false end
  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local tower = false
  for f = 1, 7 do
    local id = okC and MapCatalog.pretToEngine("PokemonTower_" .. f .. "F") or ("FR_POKEMON_TOWER_" .. f .. "F")
    if mapId == id then tower = true break end
  end
  if not tower then return false end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = opts.session or (Runtime and Runtime.getSession and Runtime.getSession())
  local okB, Bag = pcall(require, "src.core.game3.bag")
  if okB and session and session.bag and Bag.has and Bag.has(session.bag, ITEM_SILPH_SCOPE, 1) then return false end
  return true
end

-- pokefirered/src/battle_util.c:1709
local function overworld_weather()
  local W = package.loaded["src.core.game3.weather"]
  local id = W and tonumber(W.get and W.get() or W.current) or 0
  if id == 3 or id == 5 or id == 13 then return "RAIN" end
  if id == 8 then return "SAND" end
  if id == 12 then return "SUN" end
  return nil
end

local function action_view(act)
  if type(act) ~= "table" then return nil end
  local G3 = require("src.mods.Gen3Compat")
  local num = act.kind == "move" and act.move ~= nil and Engine.moveNum(act.move) or nil
  local name = num and G3.moveName(num) or nil
  return {
    kind = act.kind, id = name, move = name, moveNum = num, slot = act.slot,
    index = act.kind == "switch" and act.slot or nil,
    item = act.itemId and G3.itemName(act.itemId) or nil, itemId = act.itemId,
    battler = act.battler, target = act.target,
  }
end

-- pokefirered/src/battle_main.c:3532
local function open_turn(st, playerAct, enemyAct, chosen)
  st._modTurnOpen = true
  if not ModRuntime.wants("battle.turn_started") then return end
  local actions
  if chosen then
    actions = {}
    for id = 0, 3 do actions[id] = action_view(chosen[id]) end
  end
  ModRuntime.emit("battle.turn_started", {
    battle = st, turn = st.turn, playerAction = action_view(playerAct),
    enemyAction = action_view(enemyAct), actions = actions,
  })
end

-- pokefirered/src/battle_main.c:2953
local function close_turn(st)
  if not (st and st._modTurnOpen) then return end
  st._modTurnOpen = nil
  if ModRuntime.wants("battle.turn_ended") then
    ModRuntime.emit("battle.turn_ended", { battle = st, turn = st.turn })
  end
end

function Battle.isActive()
  return Battle._active == true
end

function Battle.getResult()
  return Battle._st and Battle._st.result
end

function Battle.getState()
  return Battle._st
end

local function finish(result)
  if not Battle._active then return end
  stop_low_hp_song()
  Battle._active = false
  Battle._phase = nil
  Battle._residualEvents = nil
  Battle._residualIndex = 1
  Battle._residualStepState = nil
  Battle._pendingChoice = nil
  D.reset()
  local st = Battle._st
  close_turn(st)
  if st then
    st.over = true
    st.result = result or st.result or "win"
    local Runtime=package.loaded["src.core.game3.runtime"]
    local session=Runtime and Runtime.getSession()
    if session and not Battle._headless then
      require("src.core.game3.quest_log_recorder").battle(session,st)
    end
  end
  AnimSeq.reset()
  CatchSeq.reset()
  ExpSeq.reset()
  EvoSeq.reset()
  IntroSeq.reset()
  LearnMove.reset()
  SwitchSeq.reset()
  Anim.reset({ headless = true })
  local okM, Message = pcall(require, "src.ui.game3.message")
  if okM and Message then
    if Message.setFrame then Message.setFrame("dialogue") end
    if Message.open and Message.close then Message.close() end
  end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.unlock then Field.unlock() end
  if Battle._headless then
    local okF, Fade = pcall(require, "src.ui.game3.fade")
    if okF and Fade and Fade.clear then Fade.clear() end
  end
  -- Victory BGM starts in begin_win_award (while awards play). Map BGM is
  -- restored by battle_bridge on exit — do not clobber victory here.
  local cb = Battle._onDone
  Battle._onDone = nil
  if cb then cb(st and st.result or result or "win", st) end
  -- pokefirered/src/safari_zone.c:66
  if st and st.safari and st.endReason == "no_safari_balls" then
    local okS, Safari = pcall(require, "src.core.game3.safari")
    -- pokefirered/src/safari_zone.c:12 GetSafariZoneFlag
    if okS and Safari and Safari.isActive and Safari.isActive(st.session) then
      Safari.outOfBallsMidBattle(st.session)
    end
  end
end

function Battle.start(opts)
  opts = opts or {}
  if Battle._active then
    return nil, "battle already active"
  end
  local playerParty = opts.playerParty or {}
  if #playerParty == 0 then
    return nil, "empty party"
  end
  local foeMon = foe_mon_from(opts.foe)
  local foeParty = opts.foeParty
  if not foeParty and opts.foe and opts.foe.party then
    foeParty = {}
    for _, fm in ipairs(opts.foe.party) do
      foeParty[#foeParty + 1] = foe_mon_from(fm)
    end
  end
  if foeParty and foeParty[1] and type(opts.foe) == "table" and opts.foe.species == nil and opts.foe.id == nil then
    foeMon = foeParty[1]
  end
  Moves.loadRomPack(opts.cache)
  local double = (opts.double == true) and not opts.wild
  local st = State.new({
    wild = opts.wild,
    double = double or nil,
    playerIndex = opts.playerIndex or State.firstUsable(playerParty) or 1,
    playerParty = playerParty,
    foeMon = foeMon,
    foeParty = foeParty,
    rng = opts.rng,
  })
  D.reset()
  st.ghostBattle = ghost_battle(opts, st)
  if st.ghostBattle then
    -- pokefirered/src/battle_setup.c:326
    st.ghostUnveiled = (opts.ghostUnveiled or (type(opts.foe) == "table" and opts.foe.ghostUnveiled)) and true or nil
    -- pokefirered/src/battle_setup.c:334
    if st.enemy and st.enemy.mon then st.enemy.mon.nickname = Strings("GHOST") end
  end
  Battle._headless = opts.headless and true or false
  Battle._auto = (opts.autoFight == true) or (opts.headless and opts.autoFight ~= false)
  Battle._fade = (opts.fade ~= false) and not Battle._headless
  Ui.reset({ headless = opts.headless })
  do
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = opts.session
      or (Runtime and Runtime.getSession and Runtime.getSession())
    st.session = session
    st.dex = opts.dex or (session and session.dex)
    Ui.bindState(st, session)
    st.playerName = session and session.name or "PLAYER"
    -- pokefirered/src/battle_main.c:2618
    if session and session.dex and foeMon and (foeMon.species or foeMon.speciesId)
        and not (st.ghostBattle and not st.ghostUnveiled) then
      local Dex = require("src.core.game3.dex")
      Dex.setSeen(session.dex, foeMon.species or foeMon.speciesId)
      local b3 = st.double and not st.absent[3] and st.battlers[3]
      if b3 and b3.mon then Dex.setSeen(session.dex, b3.mon.species or b3.mon.speciesId) end
    end
    -- pokefirered/src/pokemon.c:1796
    local wildMon = st.wild and st.enemy and st.enemy.mon
    local otId = session and tonumber(session.trainerId or session.id or session.playerId)
    if wildMon and otId then
      local Catching = require("src.core.game3.battle.catching")
      wildMon.otId = otId
      wildMon.otSecretId = Catching.playerSecretId(session)
    end
  end
  Anim.reset({ headless = opts.headless, double = st.double })
  AnimSeq.reset()
  CatchSeq.reset()
  ExpSeq.reset()
  IntroSeq.reset()
  SwitchSeq.reset()
  -- Align party exp to ROM growth curves before battle display
  for _, mon in ipairs(playerParty) do
    Experience.syncExpToLevel(mon)
  end
  if foeMon then Experience.syncExpToLevel(foeMon) end
  if foeParty then
    for _, fm in ipairs(foeParty) do
      Experience.syncExpToLevel(fm)
    end
  end
  Anim.syncDisplayFromState(st)
  Battle._st = st
  Battle._adapter = Adapter.new(st, function(text) Ui.push(text) end)
  Battle._onDone = opts.onDone
  Battle._active = true
  Battle._lowHpSong = false
  Battle._phase = "intro"
  Battle._actions = nil
  Battle._actionI = 1
  Battle._pendingEnd = nil
  Battle._metaAct = nil
  Battle._pendingChoice = nil

  -- Trainer presentation identity
  local trainerId = opts.trainerId
    or (opts.foe and opts.foe.trainerId)
    or (foeMon and foeMon.trainerId)
  local rivalName = opts.rivalName
  local playerGender = opts.playerGender or 0
  local trainerInfo = nil
  if trainerId and not st.wild then
    trainerInfo = Trainers.info(trainerId, { rivalName = rivalName })
  end

  local BattleBg = require("src.core.game3.battle.bg")
  local terrain = opts.terrain
  -- pokefirered/src/battle_main.c:689
  if terrain == nil and (opts.mapBehavior ~= nil or opts.mapType ~= nil) then
    terrain = BattleBg.resolveFromBehavior(opts.mapBehavior, opts.mapKind, opts.mapType)
  end
  if terrain == nil and opts.mapKind then
    terrain = BattleBg.resolveFromMapKind(opts.mapKind)
  end
  if terrain == nil then
    terrain = BattleBg.TERRAIN.BUILDING
  end
  st.terrain = terrain
  -- pokefirered/src/battle_bg.c:714
  BattleBg.setTerrain(BattleBg.resolveOverride(terrain, {
    link = st.link or opts.link,
    trainerTower = st.trainerTower or opts.trainerTower,
    pokedude = st.pokedude or opts.pokedude,
    trainer = (not st.wild) and trainerInfo ~= nil,
    trainerClass = trainerInfo and trainerInfo.class,
    mapBattleScene = opts.mapBattleScene,
  }))

  st.trainerId = trainerId
  st.trainerClassName = trainerInfo and trainerInfo.className
  st.trainerName = trainerInfo and trainerInfo.name
  st.trainerPicId = (opts.trainerPicId)
    or (trainerInfo and trainerInfo.pic)
  st.trainerPartySize = trainerInfo and trainerInfo.partySize
  st.defeatText = opts.defeatText
  st.victoryText = opts.victoryText
  st.earlyRival = opts.earlyRival or false
  st.rivalFlags = tonumber(opts.rivalFlags) or 0
  -- pokefirered/src/battle_main.c:3783
  st.rivalHealAfter = st.earlyRival and (st.rivalFlags % 2 == 1)
  st.wildScripted = opts.wildScripted or (opts.foe and opts.foe.wildScripted) or false
  st.legendary = opts.legendary or (opts.foe and opts.foe.legendary) or false
  st.safari = opts.safari or (opts.foe and opts.foe.safari) or false
  if st.safari then
    -- pokefirered/src/battle_main.c:2565
    State.zeroBattler(st.player)
    -- pokefirered/src/battle_main.c:2284
    local fspecies = foeMon and (foeMon.species or foeMon.speciesId)
    local fmeta = fspecies and Pokemon.speciesMeta and Pokemon.speciesMeta(fspecies)
    st.safariState = Rules.safari.newState(fmeta and fmeta.catchRate,
      fmeta and fmeta.safariZoneFleeRate)
    -- pokefirered/src/safari_zone.c:9
    local carried = st.session and st.session.safari and tonumber(st.session.safari.balls)
    if carried then st.safariState.balls = math.max(0, math.floor(carried)) end
  end
  st.roamer = opts.roamer or (opts.foe and opts.foe.roamer) or false
  st.firstBattle = opts.firstBattle or (opts.foe and opts.foe.firstBattle) or false
  st.oldManTutorial = opts.oldManTutorial or (opts.foe and opts.foe.oldManTutorial) or false
  -- pret gTrainers[].aiFlags / items[4] — drive battle AI scripts + item use.
  st.aiFlags = opts.aiFlags
    or (st.safari and 0x40000000)
    or (st.roamer and 0x20000000)
    or (st.legendary and 7) -- CHECK_BAD_MOVE | TRY_TO_FAINT | CHECK_VIABILITY
    or (st.wildScripted and 1) -- CHECK_BAD_MOVE
    or (trainerInfo and trainerInfo.aiFlags)
    or (st.wild and 0 or 1) -- wild: no scripts; fallback trainer: CHECK_BAD_MOVE
  st.trainerItems = opts.trainerItems
    or (trainerInfo and trainerInfo.items)
    or { 0, 0, 0, 0 }
  st.playerGender = playerGender
  st.overworldWeather = opts.overworldWeather or overworld_weather()
  do
    -- pokefirered/src/battle_controllers.c:59
    local okAi, Ai = pcall(require, "src.core.game3.battle.ai")
    if okAi and Ai and Ai.battleStart then Ai.battleStart(st) end
  end

  -- Battle BGM (if not already playing from transition start)
  do
    local Audio = require("src.core.game3.audio")
    local song = opts.song
    if not song then
      if st.wild then
        local foeSpecies = foeMon and (foeMon.species or foeMon.speciesId or foeMon.id)
        if foeSpecies == 150 then
          song = Audio.role("battleMewtwo") or 340
        elseif foeSpecies == 386 then
          song = Audio.role("battleDeoxys") or 339
        elseif foeSpecies == 144 or foeSpecies == 145 or foeSpecies == 146 or foeSpecies == 249 or foeSpecies == 250 then
          song = Audio.role("battleLegend") or 341
        else
          song = Audio.role("battleWild") or 298
        end
      else
        local role, fallback = Trainers.getBattleMusicRole(trainerId)
        song = Audio.role(role) or fallback
      end
    end
    if song then
      Audio.playSong(song)
    end
  end

  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.lock then Field.lock() end

  local introOpts = {
    pushMsg = function(text) Ui.push(text) end,
    headless = opts.headless,
    trainerId = trainerId,
    trainerPicId = st.trainerPicId,
    playerGender = playerGender,
    rivalName = rivalName,
  }
  if not IntroSeq.begin(st, introOpts) then
    -- Headless / skip: push FRLG strings for log parity.
    local ename = State.displayName(st.enemy)
    if st.ghostBattle then
      for _, t in ipairs(IntroSeq.headlessGhostIntro(st)) do Ui.push(t) end
    elseif st.wild then
      Ui.push(Strings("Wild %s appeared!", ename))
    elseif st.double then
      for _, t in ipairs(D.headlessIntro(st, trainerId, rivalName)) do Ui.push(t) end
    else
      local strings = Trainers.introStrings(trainerId, ename, { rivalName = rivalName })
      Ui.push(strings.wants)
      Ui.push(strings.sentOut)
    end
    -- pokefirered/src/battle_main.c:2801
    if not st.double and not st.safari then
      Ui.push(Strings("Go! %s!", State.displayName(st.player)))
    end
    -- pokefirered/src/battle_controller_oak_old_man.c:626
    if Oak.active(st) and not st.oakIntroDone then
      st.oakIntroDone = true
      Oak.say(st, "forPetesSake")
    end
  end

  if opts.onStarted then opts.onStarted(st) end

  if opts.headless and opts.autoFight ~= false then
    Battle._auto = true
    Battle.runToEnd()
  end
  return true
end

local function end_if_over()
  local st = Battle._st
  if not st or not st.over then return false end
  if not st.endReason and not AnimSeq.ended() then return false end
  Battle._actions = {}
  Battle._metaAct = nil
  Battle._pendingEnd = st.result or "run"
  Battle._phase = "ending"
  return true
end

-- pokefirered/src/battle_main.c:3682
local function focus_punch_prelude()
  local st, ad = Battle._st, Battle._adapter
  local list = st._focusPunchSetup
  st._focusPunchSetup = nil
  if not list then
    list = {}
    for _, a in ipairs(Battle._actions or {}) do
      local u = a.user
      if type(u) == "string" then u = st[u] end
      local mv = a.move and Moves.get(a.move)
      if u and mv and tonumber(mv.effect) == 170 and not u.expLockedMove and not ad:hasStatus(u, "SLP") then
        list[#list + 1] = u
      end
    end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return (a.expTurnOrder or 9) < (b.expTurnOrder or 9) end)
  local mark = ad:eventMark()
  local prev = ad._say
  ad._say = function() end
  for _, b in ipairs(list) do
    if not ad:isFainted(b) then
      ad:playAnim("general", "FOCUS_PUNCH_SETUP", b, b)
      ad:say(Strings("%s is tightening\nits focus!", ad:displayName(b)))
    end
  end
  ad._say = prev
  return ad:eventsSince(mark)
end

-- pokefirered/src/battle_main.c:2856
local function begin_start_effects()
  local st, ad = Battle._st, Battle._adapter
  if not (st and ad and Engine.battleStartEffects) or st._startEffectsDone then return false end
  st._startEffectsDone = true
  local mark = ad:eventMark()
  local prev = ad._say
  ad._say = function() end
  local ok = pcall(Engine.battleStartEffects, st, ad)
  ad._say = prev
  if not ok then return false end
  local evs = ad:eventsSince(mark)
  if #evs == 0 then return false end
  if Battle._headless then
    for _, e in ipairs(evs) do
      if e.kind == "msg" then Ui.push(e.text) end
    end
    Anim.syncDisplayFromState(st)
    return false
  end
  AnimSeq.beginEvents(evs, seq_push)
  Battle._phase = "startfx"
  return true
end

local function begin_turn_with(playerAct)
  local st = Battle._st
  local ad = Battle._adapter
  if st and st.double then return D.startSelection() end
  st.turn = st.turn + 1
  local enemyAct = Commands.enemyAction(st)
  local actions, meta = Engine.planTurnFromActions(st, ad, playerAct, enemyAct)
  open_turn(st, playerAct, enemyAct, nil)
  Battle._actions = actions
  Battle._actionI = 1
  Battle._metaAct = meta
  Battle._phase = "actions"
  local evs = focus_punch_prelude()
  if evs and #evs > 0 then
    if Battle._headless then
      for _, e in ipairs(evs) do
        if e.kind == "msg" then Ui.push(e.text) end
      end
    else
      AnimSeq.beginEvents(evs, seq_push)
      Battle._phase = "preturn"
    end
  end
end

local function choice_hooks()
  return {
    pushMsg = function(text, cb) Ui.push(text, cb) end,
    askYesNo = function(a, b) Ui.askYesNo(a, b) end,
    askForget = function(labels, cb, ctx) Ui.askForget(labels, cb, ctx) end,
    headless = Battle._headless,
    battleText = true,
  }
end
Battle._choiceHooksForTests = choice_hooks

local function begin_evo_or_end()
  local st = Battle._st
  Battle._pendingEnd = Battle._pendingEnd or "win"
  if Battle._pendingEnd ~= "win" or not st then
    Battle._phase = "ending"
    return
  end
  local leveled = Battle._leveledUp or ExpSeq.leveledSet()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = (Runtime and Runtime.getSession and Runtime.getSession()) or (Battle._st and Battle._st.session)
  local pending = Evolution.pending(st.playerParty, leveled, session)
  if Battle._headless then
    local Pokemon = require("src.core.game3.pokemon")
    for _, entry in ipairs(pending) do
      local fromName = Pokemon.displayMonName(entry.mon)
      local intoName = Pokemon.name(entry.toSpecies) or "?"
      Ui.push(Strings("What?\n%s is evolving!", fromName))
      Evolution.apply(entry.mon, entry.toSpecies, session)
      Ui.push(Strings("Congratulations! Your %s\nevolved into %s!", fromName, intoName))
    end
    Battle._phase = "ending"
    return
  end
  local hooks = choice_hooks()
  hooks.session = session
  local started = EvoSeq.begin(pending, hooks)
  if started then
    Battle._phase = "evolving"
  else
    Battle._phase = "ending"
  end
end

local function send_out_enemy_next(nextEnemyIdx)
  local st = Battle._st
  if not st then return end
  local pushFn = function(text) Ui.push(text) end
  local onDone = function()
    Battle._phase = "command"
    if Battle._auto then
      begin_turn_with(Commands.playerAction(st, 1, 1))
    else
      Ui.openMenu()
    end
  end
  if Battle._headless or Battle._auto then
    SwitchSeq.beginSendOut(st, "enemy", nextEnemyIdx, {
      headless = true,
      pushMsg = pushFn,
      onDone = onDone,
    })
  else
    SwitchSeq.beginSendOut(st, "enemy", nextEnemyIdx, {
      headless = false,
      pushMsg = pushFn,
      onDone = onDone,
    })
    Battle._phase = "switching"
  end
end

-- pokefirered/src/battle_main.c:3781
function D.pushBattleLost(st)
  if st and st.earlyRival then
    -- pokefirered/data/battle_scripts_1.s:2953
    if st.victoryText and st.victoryText ~= "" then Ui.push(st.victoryText) end
    -- pokefirered/src/battle_controller_oak_old_man.c:1780
    Oak.say(st, "howDisappointing")
    if st.rivalHealAfter then return end
  end
  Ui.push(Strings("You have no more\nPOKéMON left!"))
  Ui.push(Strings("%s blacked out!", ((st and st.playerName) or "PLAYER")))
end

local function handle_player_faint(opts)
  opts = opts or {}
  local st = Battle._st
  if not st then return end
  if st.player and st.playerParty then
    State.syncBattlerToParty(st.player, st.playerParty)
  end
  local hasLiving = Engine.hasLivingMons(st.playerParty)
  if not hasLiving then
    Battle._pendingEnd = "lose"
    Battle._phase = "ending"
    D.pushBattleLost(st)
    return
  end

  if Battle._headless or Battle._auto then
    local nextI = Engine.nextLivingMonIndex(st.playerParty, st.player and st.player.partyIndex) or 1
    SwitchSeq.beginSendOut(st, "player", nextI, {
      headless = true,
      pushMsg = function(t) Ui.push(t) end,
      onDone = function()
        Battle._phase = "command"
        if Battle._auto then
          begin_turn_with(Commands.playerAction(st, 1, 1))
        else
          Ui.openMenu()
        end
      end,
    })
    return
  end

  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  State.syncBattlerToParty(st.player, st.playerParty)
  if Ui.clearLinger then Ui.clearLinger() end
  Battle._phase = "switching"
  PartyMenu.show(st.playerParty or (session and session.party), session and session.move_overlay, {
    mode = "battle_faint",
    session = session,
    activeSlot = st.player.partyIndex,
    battle = true,
    validate = function(slot) return Commands.switchError(st, slot, true) end,
    onSelect = function(slot)
      SwitchSeq.beginSendOut(st, "player", slot, {
        headless = false,
        pushMsg = function(t) Ui.push(t) end,
        onDone = function()
          Battle._phase = "command"
          Ui.openMenu()
        end,
      })
      Battle._phase = "switching"
    end,
  })
end

local function begin_trainer_win(st)
  Battle._pendingEnd = "win"
  local Audio = require("src.core.game3.audio")
  local role, fallback
  if st and st.wild then
    role, fallback = "victoryWild", 311
  else
    role, fallback = Trainers.getVictoryMusicRole(st and st.trainerId)
  end
  Audio.playSong(Audio.role(role) or fallback)

  local pname = st.playerName or "PLAYER"
  local function push_defeated()
    local trName = (st.trainerClassName and st.trainerClassName ~= "")
      and (st.trainerClassName .. " " .. (st.trainerName or ""))
      or (st.trainerName or "TRAINER")
    -- pokefirered/data/battle_scripts_1.s:2912
    Ui.push(Strings("%s defeated\n%s!", pname, trName))
  end
  local function push_lose_text_and_money()
    local Trainers = require("src.core.game3.scripting.trainers")
    local dialogs = Trainers.dialogs(st.trainerId)
    local defeatSpeech = st.defeatText or (dialogs and dialogs.defeat)
    -- pokefirered/data/battle_scripts_1.s:2915
    if defeatSpeech and defeatSpeech ~= "" then
      Ui.push(defeatSpeech)
    end
    local Prize = require("src.core.game3.battle.prize")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    if session then
      local info = Trainers.info(st.trainerId)
      local lastLevel = info and tonumber(info.lastLevel)
      if not lastLevel or lastLevel < 1 then
        lastLevel = st.enemy and st.enemy.mon and tonumber(st.enemy.mon.level) or 1
      end
      local gained = Prize.awardTrainerWin(session, st.trainerId, {
        lastLevel = lastLevel,
        double = st.double or false,
        moneyMultiplier = st.moneyMultiplier or 1,
      })
      if gained > 0 then
        Ui.push(Prize.moneyMessage(session.name or pname, gained))
        -- pokefirered/src/battle_controller_oak_old_man.c:1776
        Oak.say(st, "winEarnsPrize")
      end
    end
  end

  local function give_payday_money_and_pickup()
    local Prize = require("src.core.game3.battle.prize")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = (Runtime and Runtime.getSession and Runtime.getSession()) or st.session
    -- pokefirered/data/battle_scripts_1.s:2920
    local bonus = Prize.payDay(session, st.payDayCoins, { moneyMultiplier = st.moneyMultiplier or 1 })
    if bonus > 0 then
      Ui.push(Prize.payDayMessage((session and session.name) or pname, bonus))
    end
    Prize.pickup((session and session.party) or st.playerParty)
  end

  if not st.wild and st.trainerId and not Battle._headless then
    push_defeated()
    SwitchSeq.beginTrainerSlideIn(st, {
      headless = false,
      onDone = function()
        push_lose_text_and_money()
        give_payday_money_and_pickup()
        begin_evo_or_end()
      end,
    })
    Battle._phase = "switching"
  else
    if not st.wild and st.trainerId then
      push_defeated()
      push_lose_text_and_money()
    end
    -- pokefirered/src/battle_main.c:3764
    give_payday_money_and_pickup()
    begin_evo_or_end()
  end
end

local function push_awards_headless(awards)
  local Pokemon = require("src.core.game3.pokemon")
  for _, entry in ipairs(awards or {}) do
    local r = entry.result or {}
    if (r.gained or 0) > 0 then
      local name = entry.battler and State.displayName(entry.battler)
        or Pokemon.displayMonName(entry.mon)
      if entry.boosted then
        Ui.push(Strings("%s gained a boosted\n%s EXP. Points!", name, tostring(r.gained)))
      else
        Ui.push(Strings("%s gained\n%s EXP. Points!", name, tostring(r.gained)))
      end
      for _, lv in ipairs(r.levels or {}) do
        Ui.push(Strings("%s grew to\nLV. %s!", name, tostring(lv)))
        Battle._leveledUp[entry.partyIndex or 1] = true
      end
      for _, lv in ipairs(r.levels or {}) do
        for _, mv in ipairs(Pokemon.movesLearnedAt(
          tonumber(entry.mon and entry.mon.species), lv)) do
          if Pokemon.teachMove(entry.mon, mv) then
            Ui.push(Strings("%s learned\n%s!", name, Pokemon.moveName(mv)))
          end
        end
      end
    end
  end
end

local function handle_enemy_faint(opts)
  opts = opts or {}
  local st = Battle._st
  if not st then return end
  stop_low_hp_song()
  if st.enemy and st.foeParty then
    State.syncBattlerToParty(st.enemy, st.foeParty)
  end
  local awards = {}
  if st and st.enemy then
    local partIndices = {}
    if st.enemy.participants then
      for pi, _ in pairs(st.enemy.participants) do
        partIndices[#partIndices + 1] = pi
      end
      table.sort(partIndices)
    end
    awards = Experience.awardFoe(st, st.enemy, {
      trainer = not st.wild,
      partyIndices = (#partIndices > 0) and partIndices or nil,
    })
  end
  Battle._leveledUp = {}
  local nextEnemyIdx = (not st.wild) and Engine.nextLivingMonIndex(st.foeParty, st.enemy and st.enemy.partyIndex)
  if nextEnemyIdx then
    -- pokefirered/src/battle_controller_opponent.c:1416
    local okS, pick = pcall(Engine.mostSuitableMon, st, Battle._adapter, "enemy")
    if okS and pick and st.foeParty[pick] and (tonumber(st.foeParty[pick].hp) or 0) > 0 then
      nextEnemyIdx = pick
    end
  end

  local onAwardsFinished = function()
    if not nextEnemyIdx then
      begin_trainer_win(st)
    else
      if opts.onFinished then
        send_out_enemy_next(nextEnemyIdx)
        opts.onFinished()
        return
      end
      local okO, Options = pcall(require, "src.core.game3.options")
      local okR, Runtime = pcall(require, "src.core.game3.runtime")
      local session = okR and Runtime.getSession and Runtime.getSession()
      local battleStyle = (okO and session and Options.battleStyle and Options.battleStyle(session)) or "shift"
      if Battle._headless or Battle._auto or opts.mutual or battleStyle == "set" or State.isFainted(st.player) then
        send_out_enemy_next(nextEnemyIdx)
      else
        local nextMon = st.foeParty[nextEnemyIdx]
        local nextSp = nextMon and (nextMon.species or nextMon.speciesId)
        local Pokemon = require("src.core.game3.pokemon")
        local nextName = Pokemon.name(nextSp)
        local trName = (st.trainerClassName and st.trainerClassName ~= "")
          and (st.trainerClassName .. " " .. (st.trainerName or ""))
          or (st.trainerName or "TRAINER")
        Ui.push(Strings("%s is\nabout to use %s.\\pWill %s change\nPOKéMON?", trName, nextName, (st.playerName or "PLAYER")))
        Battle._shiftEnemyIdx = nextEnemyIdx
        Battle._shiftAsked = false
        Battle._phase = "shift_prompt"
      end
    end
  end

  local hooks = choice_hooks()
  if Battle._headless then
    push_awards_headless(awards)
    onAwardsFinished()
    return
  end

  local started = ExpSeq.begin(awards, hooks.pushMsg, nil, hooks)
  if started then
    Battle._leveledUp = ExpSeq.leveledSet() or {}
    Battle._onExpDone = onAwardsFinished
    Battle._phase = "awarding"
  else
    onAwardsFinished()
  end
end

local function check_faints_and_end()
  local st = Battle._st
  local ad = Battle._adapter
  if not st then return false end
  -- pokefirered/src/battle_util.c:1146
  if st.safari then return false end

  local pFainted = State.isFainted(st.player)
  local eFainted = State.isFainted(st.enemy)

  if pFainted and eFainted then
    local playerHasLiving = Engine.hasLivingMons(st.playerParty)
    local enemyHasLiving = Engine.hasLivingMons(st.foeParty)
    if not playerHasLiving then
      handle_player_faint()
      return true
    elseif not enemyHasLiving then
      handle_enemy_faint({ mutual = true })
      return true
    else
      handle_enemy_faint({ mutual = true, onFinished = function()
        handle_player_faint()
      end })
      return true
    end
  elseif eFainted then
    handle_enemy_faint()
    return true
  elseif pFainted then
    handle_player_faint()
    return true
  end

  local endResult = Engine.checkEnd(st, ad)
  if endResult == "win" then
    handle_enemy_faint()
    return true
  elseif endResult == "lose" then
    handle_player_faint()
    return true
  end

  return false
end

local function begin_win_award()
  handle_enemy_faint()
end

local function after_actions()
  local st = Battle._st
  local ad = Battle._adapter
  if st and st.double then return D.afterActions() end
  if end_if_over() then return end
  local events = Engine.collectResidualEvents(st, ad)
  close_turn(st)
  Battle._residualEvents = events
  Battle._residualIndex = 1
  Battle._residualStepState = "start"

  if Battle._headless then
    for _, evt in ipairs(events or {}) do
      push_msgs(evt.msgs)
    end
    Ui.pump()
    if check_faints_and_end() then
      return
    end
    Battle._phase = "command"
    if Battle._auto then
      begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
    end
    return
  end

  local stream = {}
  for _, evt in ipairs(events or {}) do
    for _, e in ipairs(evt.events or {}) do stream[#stream + 1] = e end
  end
  AnimSeq.beginEvents(stream, seq_push)
  Battle._phase = "residuals"
end

local function battle_session(st)
  if st and st.session then return st.session end
  local Runtime = package.loaded["src.core.game3.runtime"]
  return (Runtime and Runtime.getSession and Runtime.getSession()) or nil
end

-- pokefirered/src/safari_zone.c:9
local function safari_sync_balls(st)
  local session = battle_session(st)
  if not (session and st and st.safariState) then return end
  session.safari = session.safari or {}
  session.safari.balls = st.safariState.balls
end
Battle.safariSyncBalls = safari_sync_balls

local function resume_actions()
  Battle._phase = "actions"
  if not Battle._actions or not Battle._actions[Battle._actionI] then
    after_actions()
  end
end

-- pokefirered/data/battle_scripts_2.s:105
local function safari_out_of_balls(st)
  if not (st and st.safari and st.safariState) then return false end
  if (tonumber(st.safariState.balls) or 0) > 0 then return false end
  Ui.push(Strings("ANNOUNCER: You're out of\nSAFARI BALLS! Game over!"))
  Battle._actions = {}
  st.over = true
  -- pokefirered/data/battle_scripts_2.s:112
  st.result = "no_safari_balls"
  st.endReason = "no_safari_balls"
  Battle._pendingEnd = "no_safari_balls"
  Battle._phase = "ending"
  return true
end

local SAFARI_BALL_ITEM = 5

-- pokefirered/src/battle_main.c:4371
local function step_safari_ball()
  local st, ad = Battle._st, Battle._adapter
  local sf = st.safariState
  local session = battle_session(st)
  if sf then sf.balls = math.max(0, (tonumber(sf.balls) or 0) - 1) end
  safari_sync_balls(st)
  st.lastUsedItem = SAFARI_BALL_ITEM
  local Catching = require("src.core.game3.battle.catching")
  local rng = (ad and ad.rng and ad:rng()) or st.rng
  local caught, shakes = Catching.tryCatch(SAFARI_BALL_ITEM, st.enemy, st, session, rng)
  local headless = Battle._headless or (Ui and Ui._headless) or false
  CatchSeq.begin(st, SAFARI_BALL_ITEM, caught, shakes, {
    pushMsg = function(text) Ui.push(text) end,
    headless = headless,
    session = session,
  })
  if caught then
    Battle._actions = {}
    st.over = true
    st.result = "catch"
    Battle._pendingEnd = "catch"
    if headless then
      Battle._phase = "ending"
    else
      Battle._phase = "catching"
    end
    return
  end
  if not headless then
    Battle._phase = "catching"
    return
  end
  if safari_out_of_balls(st) then return end
  return resume_actions()
end

-- pokefirered/src/battle_main.c:4382
local function step_safari(meta)
  local st, ad = Battle._st, Battle._adapter
  if meta.action == "ball" then return step_safari_ball() end
  local sf = st.safariState
  local session = battle_session(st)
  local playerName = (session and (session.name or session.playerName)) or st.playerName or "RED"
  local ename = State.displayName(st.enemy)
  local rng = (ad and ad.rng and ad:rng()) or st.rng
  local mark = ad:eventMark()
  local prev = ad._say
  ad._say = function() end
  if meta.action == "rock" then
    -- pokefirered/src/battle_main.c:4398
    Rules.safari.throwRock(sf, rng)
    ad:say(Strings("%s threw a ROCK\nat the %s!", playerName, ename))
    ad:playAnim("general", "ROCK_THROW", st.player, st.enemy)
  else
    Rules.safari.throwBait(sf, rng)
    ad:say(Strings("%s threw some BAIT\nat the %s!", playerName, ename))
    ad:playAnim("general", "BAIT_THROW", st.player, st.enemy)
  end
  ad._say = prev
  local evs = ad:eventsSince(mark)
  if Battle._headless then
    for _, e in ipairs(evs) do
      if e.kind == "msg" then Ui.push(e.text) end
    end
    return resume_actions()
  end
  AnimSeq.beginEvents(evs, seq_push)
  Battle._phase = "animating"
end

-- pokefirered/src/battle_main.c:4334
local function step_safari_enemy(act)
  local st, ad = Battle._st, Battle._adapter
  local ename = State.displayName(st.enemy)
  local mark = ad:eventMark()
  local prev = ad._say
  ad._say = function() end
  if act.kind == "run" then
    -- pokefirered/src/battle_message.c:323
    ad:say(Strings("Wild %s fled!", ename))
    st.over = true
    st.result = "run"
    st.endReason = "enemy_fled"
  else
    local reaction = Rules.safari.watchStep(st.safariState)
    if reaction == "angry" then
      st.safariReaction = 1
      ad:say(Strings("%s is angry!", ename))
    elseif reaction == "eating" then
      st.safariReaction = 2
      ad:say(Strings("%s is eating!", ename))
    else
      st.safariReaction = 0
      ad:say(Strings("%s is watching\ncarefully!", ename))
    end
    ad:playAnim("general", "SAFARI_REACTION", st.enemy, st.enemy)
  end
  ad._say = prev
  local evs = ad:eventsSince(mark)
  if Battle._headless then
    for _, e in ipairs(evs) do
      if e.kind == "msg" then Ui.push(e.text) end
    end
    if end_if_over() then return end
    return resume_actions()
  end
  AnimSeq.beginEvents(evs, seq_push)
  Battle._phase = "animating"
end

local function step_action()
  local st = Battle._st
  local ad = Battle._adapter
  if st and st.double then return D.stepAction() end
  if end_if_over() then return end

  if Battle._metaAct then
    local meta = Battle._metaAct
    Battle._metaAct = nil
    if meta.kind == "safari" then
      return step_safari(meta)
    elseif meta.kind == "run" and st.safari then
      -- pokefirered/src/battle_main.c:4414
      pcall(function()
        require("src.core.game3.audio").playSe(require("src.core.game3.se_ids").SE_FLEE)
      end)
      Battle._actions = {}
      st.over = true
      st.result = "run"
      st.endReason = "safari_run"
      Battle._pendingEnd = "run"
      Battle._phase = "ending"
      return
    elseif meta.kind == "run" then
      local mark = ad:eventMark()
      local prev = ad._say
      ad._say = function() end
      local fled = Commands.tryFlee(st, ad)
      ad._say = prev
      local evs = ad:eventsSince(mark)
      if fled then
        st.over = true
        st.result = "run"
        st.endReason = "flee"
      end
      -- pokefirered/src/battle_message.c:320
      local function flee_push(text)
        if fled then
          pcall(function()
            require("src.core.game3.audio").playSe(require("src.core.game3.se_ids").SE_FLEE)
          end)
        end
        seq_push(text)
      end
      if Battle._headless then
        for _, e in ipairs(evs) do
          if e.kind == "msg" then Ui.push(e.text) end
        end
        if fled then
          Battle._pendingEnd = "run"
          Battle._phase = "ending"
          return
        end
      else
        AnimSeq.beginEvents(evs, flee_push)
        Battle._phase = "animating"
        return
      end
    elseif meta.kind == "bag" then
      local Catching = require("src.core.game3.battle.catching")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      local bag = session and session.bag

      if Catching.isBall(meta.itemId) and st.ghostBattle then
        -- pokefirered/src/battle_script_commands.c:9473
        local Bag = require("src.core.game3.bag")
        if bag and Bag.has(bag, meta.itemId, 1) then Bag.remove(bag, meta.itemId, 1) end
        local pushFn = function(text, wait)
          if wait then Ui.pushTimed(text, wait) else Ui.push(text) end
        end
        local headless = Battle._headless or (Ui and Ui._headless)
        CatchSeq.begin(st, meta.itemId, false, 0, {
          pushMsg = pushFn, headless = headless, session = session, ghostDodge = true,
        })
        if not headless then
          Battle._phase = "catching"
          return
        end
      elseif Catching.isBall(meta.itemId) then
        if not st.wild then
          Ui.push(Strings("The TRAINER blocked\nthe BALL!"))
          Battle._actions = {}
          Battle._phase = "command"
          Ui.openMenu()
          return
        end
        local Bag = require("src.core.game3.bag")
        if not bag or not Bag.has(bag, meta.itemId, 1) then
          Ui.push(Strings("You don't have that item."))
          Battle._actions = {}
          Battle._phase = "command"
          Ui.openMenu()
          return
        end
        Bag.remove(bag, meta.itemId, 1)
        local rng = ad and ad.rng and ad:rng() or st.rng
        local caught, shakes = Catching.tryCatch(meta.itemId, st.enemy, st, session, rng)
        local pushFn = function(text) Ui.push(text) end
        if Battle._headless or (Ui and Ui._headless) then
          CatchSeq.begin(st, meta.itemId, caught, shakes, {
            pushMsg = pushFn,
            headless = true,
            session = session,
          })
          if caught then
            Battle._actions = {}
            st.over = true
            st.result = "catch"
            Battle._pendingEnd = "catch"
            Battle._phase = "ending"
            return
          end
        else
          CatchSeq.begin(st, meta.itemId, caught, shakes, {
            pushMsg = pushFn,
            headless = false,
            session = session,
          })
          Battle._phase = "catching"
          return
        end
      else
        local BattleItems = require("src.core.game3.battle.items")
        local result, _msgs, endsTurn, endsBattle = BattleItems.use(
          st, ad, bag, session, meta.itemId, meta.partySlot)
        if endsBattle then
          Battle._actions = {}
          if result == "catch" then
            st.over = true
            st.result = "catch"
            Battle._pendingEnd = "catch"
          else
            st.over = true
            st.result = "run"
            Battle._pendingEnd = "run"
          end
          Battle._phase = "ending"
          return
        end
        if not endsTurn or result == "error" then
          Battle._actions = {}
          Battle._phase = "command"
          Ui.openMenu()
          return
        end
        if result == "heal" and st.player and st.player.partyIndex == meta.partySlot then
          local p = Anim.present("player")
          local logical = tonumber(st.player.mon and st.player.mon.hp) or 0
          if p and p.displayHp ~= nil and math.abs(logical - p.displayHp) >= 1 then
            Anim.tweenHp("player", p.displayHp, logical, st.player.mon.maxHp)
          end
        end
      end
    elseif meta.kind == "switch" then
      -- Pursuit interrupt check
      local enemyAct = nil
      local enemyActIdx = nil
      for idx, a in ipairs(Battle._actions or {}) do
        if a.user == "enemy" and a.kind == "move" then
          enemyAct = a
          enemyActIdx = idx
          break
        end
      end
      if enemyAct and Engine.isPursuit(enemyAct.move) and not State.isFainted(st.enemy) then
        table.remove(Battle._actions, enemyActIdx)
        local out = {}
        Engine.resolveMove(enemyAct.user, st.player, enemyAct.move, enemyAct.slot, ad, st, out, { pursuitSwitch = true })
        local animMeta = out._anim
        if Battle._headless or not animMeta then
          push_msgs(out)
          if State.isFainted(st.player) then
            Battle._actions = {}
            handle_player_faint()
            return
          end
        else
          AnimSeq.begin(animMeta, seq_push)
          Battle._phase = "animating"
          return
        end
      end

      local newSlot = meta.slot or 1
      local pushFn = function(text) Ui.push(text) end
      local onDone = function()
        Battle._phase = "actions"
        if not Battle._actions or not Battle._actions[Battle._actionI] then
          after_actions()
        end
      end
      if Battle._headless then
        SwitchSeq.beginPlayerSwitch(st, newSlot, {
          headless = true,
          pushMsg = pushFn,
          onDone = onDone,
        })
        -- Fall through to enemy action list
      else
        SwitchSeq.beginPlayerSwitch(st, newSlot, {
          headless = false,
          pushMsg = pushFn,
          onDone = onDone,
        })
        Battle._phase = "switching"
        return
      end
    end
  end

  local act = Battle._actions and Battle._actions[Battle._actionI]
  if not act then
    after_actions()
    return
  end
  Battle._actionI = Battle._actionI + 1

  if st.safari and (act.kind == "watch" or act.kind == "run") then
    return step_safari_enemy(act)
  end
  if act.meta then
    if not Battle._actions[Battle._actionI] then after_actions() end
    return
  end
  if act.kind == "switch" and act.battler == 1 then return D.singleEnemySwitch(act) end
  if act.kind == "item" then return D.enemyItem(act) end

  local uBattler = (type(act.user) == "string" and st and st[act.user]) or act.user
  local tBattler = (type(act.target) == "string" and st and st[act.target]) or act.target
  if uBattler and uBattler.side and st and st[uBattler.side] then uBattler = st[uBattler.side] end
  if tBattler and tBattler.side and st and st[tBattler.side] then tBattler = st[tBattler.side] end

  if State.isFainted(uBattler) or State.isFainted(tBattler) then
    if not Battle._actions[Battle._actionI] then after_actions() end
    return
  end

  local out = {}
  st.interactiveChoices = not (Battle._headless or Battle._auto)
  Engine.resolveMove(act.user, act.target, act.move, act.slot, ad, st, out)
  st.interactiveChoices = nil
  Battle._pendingChoice = out.pendingChoice
  local animMeta = out._anim
  if Battle._headless or not animMeta then
    push_msgs(out)
    if end_if_over() then return end
  else
    AnimSeq.begin(animMeta, seq_push)
    Battle._phase = "animating"
    return
  end

  if check_faints_and_end() then
    return
  end
  if not Battle._actions[Battle._actionI] then
    after_actions()
  end
end

-- pokefirered/src/battle_script_commands.c:4626
local function open_pending_choice()
  local st, ad = Battle._st, Battle._adapter
  local req = Battle._pendingChoice
  Battle._pendingChoice = nil
  local pc = st.pendingChoice
  local uid = (pc and pc.M and pc.M.user and pc.M.user.id) or 0
  local function resume(slot)
    st.interactiveChoices = true
    local out = Engine.resumeChoice(st, ad, slot)
    st.interactiveChoices = nil
    Battle._pendingChoice = out and out.pendingChoice
    if out and out._anim and not Battle._headless then
      AnimSeq.begin(out._anim, seq_push)
      Battle._phase = "animating"
    else
      for _, t in ipairs(out or {}) do Ui.push(t) end
      Battle._phase = "actions"
      if st.double and not Battle._pendingChoice then D.afterEach() end
    end
  end
  if Battle._headless or Battle._auto or not (req and req.kind == "baton_pass") then
    resume(req and req.candidates and req.candidates[1])
    return
  end
  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  State.syncBattlerToParty(st.player, st.playerParty)
  if Ui.clearLinger then Ui.clearLinger() end
  Battle._phase = "switching"
  if st.double and Ui.openPartyMenu then
    return Ui.openPartyMenu(st, uid, {
      forced = true,
      validate = function(slot) return Commands.switchError(st, slot, true, uid) end,
      onSelect = function(slot) resume(slot) end,
    })
  end
  PartyMenu.show(st.playerParty or (session and session.party), session and session.move_overlay, {
    mode = "battle_faint",
    session = session,
    activeSlot = st.player.partyIndex,
    activeSlots = st.double and D.activeSlots(st) or nil,
    battlerId = st.double and uid or nil,
    battle = true,
    validate = function(slot) return Commands.switchError(st, slot, true, st.double and uid or nil) end,
    onSelect = function(slot) resume(slot) end,
  })
end
Battle._openPendingChoiceForTests = open_pending_choice

local function after_anim_sequence()
  if Battle._pendingChoice then
    open_pending_choice()
    return
  end
  if Battle._singleAfterAnim then
    local scont = Battle._singleAfterAnim
    Battle._singleAfterAnim = nil
    if end_if_over() then return end
    return scont()
  end
  if Battle._st and Battle._st.double then
    local cont = Battle._dblAfterAnim
    Battle._dblAfterAnim = nil
    if cont then return cont() end
    if end_if_over() then return end
    return D.afterEach()
  end
  if end_if_over() then return end
  if check_faints_and_end() then
    return
  end
  Battle._phase = "actions"
  if not Battle._actions or not Battle._actions[Battle._actionI] then
    after_actions()
  end
end

local SEL_ORDER = { 0, 2 }

local function has_flag(t, f)
  return math.floor((tonumber(t) or 0) / f) % 2 == 1
end

function D.reset()
  Battle._dblSel = nil
  Battle._dblFaint = nil
  Battle._dblSwitch = nil
  Battle._dblAfterAnim = nil
  Battle._dblLeveled = nil
  Battle._singleAfterAnim = nil
end

function D.activeSlots(st)
  local out = {}
  for _, id in ipairs(SEL_ORDER) do
    local b = State.battler(st, id)
    if b and not State.isAbsent(st, id) then out[#out + 1] = b.partyIndex end
  end
  return out
end

function D.capture(fn)
  local ad = Battle._adapter
  if not ad then return {} end
  local mark = ad:eventMark()
  local prev = ad._say
  ad._say = function() end
  pcall(fn)
  ad._say = prev
  return ad:eventsSince(mark)
end

-- pokefirered/src/battle_message.c:1591
function D.headlessIntro(st, trainerId, rivalName)
  local strings = Trainers.introStrings(trainerId, State.displayName(st.enemy), { rivalName = rivalName })
  local out = { strings.wants }
  local b3 = not State.isAbsent(st, 3) and State.battler(st, 3)
  if b3 then
    local info = strings.info or {}
    local class = info.className or Strings("POKéMON TRAINER")
    local first, second = State.displayName(st.enemy), State.displayName(b3)
    if info.name and info.name ~= "" then
      out[#out + 1] = Strings("%s %s sent\nout %s and %s!", class, info.name, first, second)
    else
      out[#out + 1] = Strings("%s sent\nout %s and %s!", class, first, second)
    end
  else
    out[#out + 1] = strings.sentOut
  end
  local b2 = not State.isAbsent(st, 2) and State.battler(st, 2)
  if b2 then
    out[#out + 1] = Strings("Go! %s and\n%s!", State.displayName(st.player), State.displayName(b2))
  else
    out[#out + 1] = Strings("Go! %s!", State.displayName(st.player))
  end
  return out
end

-- pokefirered/src/battle_main.c:3125
function D.lockedAction(st, id)
  local b = State.battler(st, id)
  if not b or not (b.expLockedMove or b.expMustRecharge) then return nil end
  local mon = b.mon or {}
  local slot = b.expLockedSlot or 1
  local mv = b.expLockedMove or b.lastMoveId or b.lastMove or (mon.moves and mon.moves[slot])
  return { kind = "move", battler = id, move = mv, slot = slot, target = st.moveTarget and st.moveTarget[id] }
end

function D.autoAction(st, id)
  local act = Commands.fightShortcut(st, id)
  if act then
    act.battler = id
    return act
  end
  for slot = 1, 4 do
    if Commands.moveUsable(st, slot, id) then return Commands.playerAction(st, 1, slot, id) end
  end
  return Commands.playerAction(st, 1, 1, id)
end

-- pokefirered/src/battle_controller_player.c:447
function D.targetPlan(st, id, cmd)
  local b = State.battler(st, id)
  local mv = Moves.get(cmd.move)
  local tt = tonumber(mv and mv.target) or 0
  local num = tonumber(cmd.move) or tonumber(mv and mv.id)
  if num == 174 then
    local Types = require("src.core.game3.battle.types")
    local ad = Battle._adapter
    local ghost = ad and b and Types.ID and Types.ID.GHOST and ad:hasType(b, Types.ID.GHOST)
    tt = ghost and 0 or 0x10
  end
  local opposing = (id % 2 == 0) and 1 or 0
  local cursor = has_flag(tt, 0x10) and id or opposing
  local can = not (has_flag(tt, 0x04) or has_flag(tt, 0x08) or has_flag(tt, 0x01)
    or has_flag(tt, 0x20) or has_flag(tt, 0x40) or has_flag(tt, 0x10))
  local pp = b and b.mon and b.mon.pp and cmd.slot and tonumber(b.mon.pp[cmd.slot])
  if pp == 0 then
    can = false
  elseif not (has_flag(tt, 0x10) or has_flag(tt, 0x02)) then
    local others = 0
    for oid = 0, 3 do
      if oid ~= id and State.isPresent(st, oid) then others = others + 1 end
    end
    if others <= 1 then
      -- pokefirered/src/pokemon.c:2700
      cursor = State.isAbsent(st, opposing) and State.PARTNER(opposing) or opposing
      can = false
    end
  end
  local start = cursor
  if can then
    if has_flag(tt, 0x10) or has_flag(tt, 0x02) then
      start = id
    elseif State.isAbsent(st, opposing) then
      start = State.PARTNER(opposing)
    else
      start = opposing
    end
  end
  return can, cursor, start, tt
end

function D.startSelection()
  local st = Battle._st
  st.monToSwitchInto = {}
  Battle._phase = "command"
  Battle._dblSel = { chosen = {}, pos = 1 }
  return D.advanceSelection()
end

-- pokefirered/src/battle_main.c:3097
function D.advanceSelection()
  local st, sel = Battle._st, Battle._dblSel
  if not sel then return end
  while sel.pos <= #SEL_ORDER do
    local id = SEL_ORDER[sel.pos]
    local b = State.battler(st, id)
    if not b or State.isAbsent(st, id) then
      sel.pos = sel.pos + 1
    else
      local locked = D.lockedAction(st, id)
      if locked then
        sel.chosen[id] = locked
        sel.pos = sel.pos + 1
      elseif Battle._auto then
        sel.chosen[id] = D.autoAction(st, id)
        sel.pos = sel.pos + 1
      else
        sel.active = id
        st.activeBattler = id
        return D.openMenu(id)
      end
    end
  end
  return D.finishSelection()
end

-- pokefirered/src/battle_controller_player.c:286
function D.cancelPartner()
  local st, sel = Battle._st, Battle._dblSel
  local c0 = sel and sel.chosen[0]
  if c0 and c0.kind == "bag" then
    local Catching = require("src.core.game3.battle.catching")
    if not Catching.isBall(c0.itemId) then return end
  end
  pcall(function()
    require("src.core.game3.audio").playSe(require("src.core.game3.se_ids").SE_SELECT)
  end)
  sel.chosen[0] = nil
  if st.monToSwitchInto then st.monToSwitchInto[0] = nil end
  sel.pos = 1
  return D.advanceSelection()
end

function D.openMenu(id)
  local sel = Battle._dblSel
  return Ui.openMenu(id, { partnerAction = (id == 2 and sel) and sel.chosen[0] or nil })
end

function D.commit(cmd)
  local sel = Battle._dblSel
  if not sel then return end
  sel.chosen[cmd.battler] = cmd
  sel.pos = sel.pos + 1
  return D.advanceSelection()
end

function D.onCommand(cmd)
  local st, sel = Battle._st, Battle._dblSel
  if not sel or not sel.active then return end
  local id = sel.active
  if cmd.kind == "cancel_partner" then
    if id == 2 and not State.isAbsent(st, 0) then return D.cancelPartner() end
    return D.openMenu(id)
  end
  local b = State.battler(st, id)
  if cmd.battler ~= id then
    if cmd.kind == "move" and cmd.slot and b and b.mon and b.mon.moves and b.mon.moves[cmd.slot] then
      cmd.move = b.mon.moves[cmd.slot]
    end
    cmd.battler = id
  end
  if cmd.kind == "move" then
    if cmd.target == nil and cmd.move ~= "STRUGGLE" then
      local can, cursor, start = D.targetPlan(st, id, cmd)
      if not can then
        cmd.target = cursor
      elseif Ui.chooseTarget then
        sel.targeting = true
        Ui.chooseTarget(st, id, cmd.slot, function(targetId)
          sel.targeting = false
          if targetId == nil then
            if Ui.openMoveMenu then return Ui.openMoveMenu(id) end
            return D.openMenu(id)
          end
          cmd.target = targetId
          return D.commit(cmd)
        end)
        return
      else
        cmd.target = start
      end
    end
  elseif cmd.kind == "switch" then
    local err = cmd.slot and Commands.switchError(st, cmd.slot, false, id)
    if err or not cmd.slot then
      if err then Ui.push(err, function() D.openMenu(id) end) else D.openMenu(id) end
      return
    end
    st.monToSwitchInto[id] = cmd.slot
  end
  return D.commit(cmd)
end

function D.commandUpdate(input)
  local sel = Battle._dblSel
  if not sel then return D.startSelection() end
  if sel.targeting then
    if input then Ui.handleInput(input) end
    return
  end
  local BagMenu = require("src.ui.game3.bag_menu")
  if BagMenu.isOpen and BagMenu.isOpen() then
    if input then BagMenu.handleInput(input) end
    return
  end
  local PartyMenu = require("src.ui.game3.party_menu")
  if PartyMenu.isOpen and PartyMenu.isOpen() then
    if input then party_menu_input(PartyMenu, input) end
    return
  end
  if Ui._mode == "bag" or Ui._mode == "party" then
    Ui._mode = "menu"
  end
  if Ui.selectionPump() then
    local scmd = Ui.takeCommand()
    if scmd then D.onCommand(scmd) end
    return
  end
  if input then Ui.handleInput(input) end
  local cmd = Ui.takeCommand()
  if cmd then D.onCommand(cmd) end
end

-- pokefirered/src/battle_main.c:3532
function D.finishSelection()
  local st, ad = Battle._st, Battle._adapter
  local sel = Battle._dblSel
  local chosen = sel and sel.chosen or {}
  Battle._dblSel = nil
  st.activeBattler = nil
  for _, id in ipairs({ 1, 3 }) do
    if State.battler(st, id) and not State.isAbsent(st, id) then
      chosen[id] = Commands.enemyAction(st, id)
    end
  end
  st.turn = st.turn + 1
  Battle._actions = Engine.planTurnActions(st, ad, chosen)
  open_turn(st, chosen[0], chosen[1], chosen)
  Battle._actionI = 1
  Battle._metaAct = nil
  Battle._phase = "actions"
  local evs = focus_punch_prelude()
  if evs and #evs > 0 then
    if Battle._headless then
      for _, e in ipairs(evs) do
        if e.kind == "msg" then Ui.push(e.text) end
      end
    else
      AnimSeq.beginEvents(evs, seq_push)
      Battle._phase = "preturn"
    end
  end
end

-- pokefirered/src/battle_main.c:3704
function D.stepAction()
  local st, ad = Battle._st, Battle._adapter
  if end_if_over() then return end
  local acts = Battle._actions or {}
  local act
  while true do
    act = acts[Battle._actionI]
    if not act then return D.afterActions() end
    Battle._actionI = Battle._actionI + 1
    if Engine.actionRunnable(st, act) then break end
  end
  act.done = true
  local user = State.battler(st, act.battler)
  if act.kind == "move" then
    if not user or State.isFainted(user) then return D.afterEach() end
    local out = {}
    st.interactiveChoices = not (Battle._headless or Battle._auto)
    Engine.resolveMove(act.battler, act.target, act.move, act.slot, ad, st, out)
    st.interactiveChoices = nil
    Battle._pendingChoice = out.pendingChoice
    if Battle._headless or not out._anim then
      push_msgs(out)
      if Battle._pendingChoice then return open_pending_choice() end
      return D.afterEach()
    end
    AnimSeq.begin(out._anim, seq_push)
    Battle._phase = "animating"
    return
  elseif act.kind == "switch" then
    return D.beginSwitch(act)
  elseif act.kind == "bag" then
    return D.useBag(act)
  elseif act.kind == "run" then
    return D.run(act)
  elseif act.kind == "item" then
    return D.enemyItem(act)
  end
  return D.afterEach()
end

-- pokefirered/src/battle_main.c:4433
function D.afterEach()
  if end_if_over() then return end
  return D.faintFlow(function()
    Battle._phase = "actions"
  end)
end

-- pokefirered/src/battle_main.c:2953
function D.afterActions()
  local st, ad = Battle._st, Battle._adapter
  if end_if_over() then return end
  local events = Engine.collectResidualEvents(st, ad)
  close_turn(st)
  if Battle._headless then
    for _, evt in ipairs(events or {}) do push_msgs(evt.msgs) end
    Ui.pump()
    return D.endTurn()
  end
  local stream = {}
  for _, evt in ipairs(events or {}) do
    for _, e in ipairs(evt.events or {}) do stream[#stream + 1] = e end
  end
  AnimSeq.beginEvents(stream, seq_push)
  Battle._phase = "residuals"
end

function D.endTurn()
  return D.faintFlow(function()
    Battle._st.monToSwitchInto = {}
    return D.startSelection()
  end)
end

-- pokefirered/src/battle_util.c:1144
function D.faintFlow(onDone)
  Engine.refreshAbsent(Battle._st)
  Battle._dblFaint = { stage = "exp", onDone = onDone }
  return D.faintStep()
end

function D.presentAwards(awards)
  if not awards or #awards == 0 then return false end
  Battle._dblLeveled = Battle._dblLeveled or {}
  Battle._leveledUp = Battle._dblLeveled
  if Battle._headless then
    push_awards_headless(awards)
    return false
  end
  local hooks = choice_hooks()
  hooks.double = true
  if not ExpSeq.begin(awards, hooks.pushMsg, nil, hooks) then return false end
  Battle._onExpDone = function()
    for k, v in pairs(ExpSeq.leveledSet() or {}) do Battle._dblLeveled[k] = v end
    Battle._leveledUp = Battle._dblLeveled
    Battle._phase = "actions"
    return D.faintStep()
  end
  Battle._phase = "awarding"
  return true
end

function D.faintStep()
  local st, ad = Battle._st, Battle._adapter
  local F = Battle._dblFaint
  if not F or not st then return end
  if F.stage == "exp" then
    for _, id in ipairs(Engine.expAwardOrder(st)) do
      local foe = State.battler(st, id)
      if foe and not foe._expGiven then
        foe._expGiven = true
        if st.foeParty then State.syncBattlerToParty(foe, st.foeParty) end
        local awards = Experience.awardFoe(st, foe, { trainer = not st.wild })
        -- pokefirered/src/battle_util.c:1181
        State.opponentSwitchInResetSentPokes(st, foe)
        if D.presentAwards(awards) then return end
      end
    end
    F.stage = "check"
  end
  if F.stage == "check" then
    -- pokefirered/data/battle_scripts_1.s:2825
    local res = Engine.checkEnd(st, ad)
    if res == "win" or res == "lose" then
      Battle._dblFaint = nil
      Battle._actions = {}
      stop_low_hp_song()
      if res == "win" then
        Battle._leveledUp = Battle._dblLeveled or {}
        return begin_trainer_win(st)
      end
      return D.lose()
    end
    F.stage = "repl"
  end
  if F.stage == "repl" then
    for id = 0, 3 do
      local b = State.battler(st, id)
      if b and not State.isAbsent(st, id) and State.isFainted(b) then
        local cands = Engine.replacementCandidates(st, id)
        if #cands == 0 then
          -- pokefirered/src/battle_script_commands.c:4870
          Engine.markAbsent(st, id)
        else
          return D.pickReplacement(id, cands)
        end
      end
    end
    F.stage = "after"
  end
  Battle._dblFaint = nil
  -- pokefirered/src/battle_util.c:1208
  local evs = D.capture(function() Engine.afterAction(st, ad) end)
  if #evs > 0 and not Battle._headless then
    AnimSeq.beginEvents(evs, seq_push)
    Battle._phase = "animating"
    Battle._dblAfterAnim = F.onDone
    return
  end
  for _, e in ipairs(evs) do
    if e.kind == "msg" then Ui.push(e.text) end
  end
  if F.onDone then return F.onDone() end
end

function D.lose()
  Battle._pendingEnd = "lose"
  Battle._phase = "ending"
  D.pushBattleLost(Battle._st)
end

-- pokefirered/src/battle_script_commands.c:4855
function D.pickReplacement(id, cands)
  local st, ad = Battle._st, Battle._adapter
  local function go(slot)
    st.monToSwitchInto[id] = slot
    return D.sendOut(id, slot)
  end
  if State.sideOf(id) == "enemy" then
    -- pokefirered/src/battle_controller_opponent.c:1410
    local ok, pick = pcall(Engine.mostSuitableMon, st, ad, id)
    for _, c in ipairs(cands) do
      if ok and c == pick then return go(pick) end
    end
    return go(cands[1])
  end
  if Battle._headless or Battle._auto then return go(cands[1]) end
  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  for _, pid in ipairs(SEL_ORDER) do
    local pb = State.battler(st, pid)
    if pb then State.syncBattlerToParty(pb, st.playerParty) end
  end
  if Ui.clearLinger then Ui.clearLinger() end
  Battle._phase = "switching"
  if Ui.openPartyMenu then
    return Ui.openPartyMenu(st, id, {
      forced = true,
      validate = function(slot) return Commands.switchError(st, slot, true, id) end,
      onSelect = function(slot)
        if slot == nil then return D.pickReplacement(id, cands) end
        return go(slot)
      end,
    })
  end
  local b0 = State.battler(st, 0)
  PartyMenu.show(st.playerParty or (session and session.party), session and session.move_overlay, {
    mode = "battle_faint",
    session = session,
    activeSlot = b0 and b0.partyIndex,
    activeSlots = D.activeSlots(st),
    battlerId = id,
    battle = true,
    validate = function(slot) return Commands.switchError(st, slot, true, id) end,
    onSelect = function(slot)
      if slot == nil then return D.pickReplacement(id, cands) end
      return go(slot)
    end,
  })
end

function D.sendOut(id, slot)
  local started = SwitchSeq.beginDoubleSwitch(Battle._st, id, slot, {
    headless = Battle._headless or Battle._auto,
    reason = "replace",
    pushMsg = function(t) Ui.push(t) end,
    onDone = function() return D.faintStep() end,
  })
  if started then Battle._phase = "switching" end
end

-- pokefirered/data/battle_scripts_1.s:3046
function D.beginSwitch(act)
  local st = Battle._st
  local id = act.battler
  local slot = act.slot or (st.monToSwitchInto and st.monToSwitchInto[id])
  if not slot then return D.afterEach() end
  Ui.push(SwitchSeq.returnText(st, id))
  Battle._dblSwitch = { id = id, slot = slot, pursuers = (State.sideOf(id) == "player") and { 3, 1 } or { 2, 0 }, i = 1 }
  return D.switchStep()
end

-- pokefirered/src/battle_script_commands.c:8337
function D.pursuitRow(st, pid, targetId)
  if State.isAbsent(st, pid) then return nil end
  local ad = Battle._adapter
  local user = State.battler(st, pid)
  local target = State.battler(st, targetId)
  if not user or State.isFainted(user) or not target or State.isFainted(target) then return nil end
  for _, row in ipairs(st.turnActions or {}) do
    if row.battler == pid and row.kind == "move" and not row.done and not row.finished
        and Engine.isPursuit(row.move) then
      local tgt = row.target
      if type(tgt) == "table" then tgt = tgt.id end
      if tgt == nil and st.moveTarget then tgt = st.moveTarget[pid] end
      if tgt == targetId and not ad:hasStatus(user, "SLP") and not ad:hasStatus(user, "FRZ")
          and (tonumber(user.expTruantCounter) or 0) == 0 then
        return row
      end
    end
  end
  return nil
end

function D.switchStep()
  local st, ad = Battle._st, Battle._adapter
  local sw = Battle._dblSwitch
  if not sw then return end
  while sw.i <= #sw.pursuers do
    local pid = sw.pursuers[sw.i]
    sw.i = sw.i + 1
    local row = D.pursuitRow(st, pid, sw.id)
    if row then
      row.done = true
      local out = {}
      Engine.resolveMove(pid, sw.id, row.move, row.slot, ad, st, out, { pursuitSwitch = true })
      if Battle._headless or not out._anim then
        push_msgs(out)
      else
        AnimSeq.begin(out._anim, seq_push)
        Battle._phase = "animating"
        Battle._dblAfterAnim = D.switchStep
        return
      end
    end
  end
  Battle._dblSwitch = nil
  local b = State.battler(st, sw.id)
  if not b or State.isFainted(b) then
    if st.monToSwitchInto then st.monToSwitchInto[sw.id] = nil end
    return D.afterEach()
  end
  local started = SwitchSeq.beginDoubleSwitch(st, sw.id, sw.slot, {
    withdraw = true,
    noWithdrawMsg = true,
    reason = "switch",
    headless = Battle._headless,
    pushMsg = function(t) Ui.push(t) end,
    onDone = function() return D.afterEach() end,
  })
  if started then Battle._phase = "switching" end
end

-- pokefirered/data/battle_scripts_2.s:134
function D.enemyItem(act)
  local st, ad = Battle._st, Battle._adapter
  local evs = D.capture(function() Engine.performEnemyItem(st, ad, act) end)
  if Battle._headless or #evs == 0 then
    for _, e in ipairs(evs) do
      if e.kind == "msg" then Ui.push(e.text) end
    end
    Anim.syncDisplayFromState(st)
    if st.double then return D.afterEach() end
    Battle._phase = "actions"
    if not Battle._actions[Battle._actionI] then after_actions() end
    return
  end
  AnimSeq.beginEvents(evs, seq_push)
  Battle._phase = "animating"
end

-- pokefirered/data/battle_scripts_1.s:3046
function D.singleEnemySwitch(act)
  local st, ad = Battle._st, Battle._adapter
  local slot = act.slot or (st.monToSwitchInto and st.monToSwitchInto[1])
  local function cont()
    Battle._phase = "actions"
    if not (Battle._actions and Battle._actions[Battle._actionI]) then after_actions() end
  end
  if not slot or State.isFainted(st.enemy) then return cont() end
  Ui.push(SwitchSeq.returnText(st, 1))
  local function do_switch()
    if State.isFainted(st.enemy) then
      if st.monToSwitchInto then st.monToSwitchInto[1] = nil end
      if check_faints_and_end() then return end
      return cont()
    end
    local started = SwitchSeq.beginDoubleSwitch(st, 1, slot, {
      withdraw = true,
      noWithdrawMsg = true,
      reason = "switch",
      headless = Battle._headless,
      pushMsg = function(t) Ui.push(t) end,
      onDone = cont,
    })
    if started then Battle._phase = "switching" end
  end
  local prow = D.pursuitRow(st, 0, 1)
  if not prow then return do_switch() end
  for i = #(Battle._actions or {}), 1, -1 do
    if Battle._actions[i] == prow then table.remove(Battle._actions, i) end
  end
  prow.done = true
  local out = {}
  Engine.resolveMove(st.player, st.enemy, prow.move, prow.slot, ad, st, out, { pursuitSwitch = true })
  if Battle._headless or not out._anim then
    push_msgs(out)
    return do_switch()
  end
  AnimSeq.begin(out._anim, seq_push)
  Battle._phase = "animating"
  Battle._singleAfterAnim = do_switch
end

function D.useBag(act)
  local st, ad = Battle._st, Battle._adapter
  if State.sideOf(act.battler) ~= "player" then return D.afterEach() end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local bag = session and session.bag
  local Catching = require("src.core.game3.battle.catching")
  if Catching.isBall(act.itemId) then
    local Bag = require("src.core.game3.bag")
    if bag and Bag.has(bag, act.itemId, 1) then Bag.remove(bag, act.itemId, 1) end
    local okI, Items = pcall(require, "src.core.game3.items")
    local iname = okI and Items.displayName and Items.displayName(act.itemId) or "POKé BALL"
    -- pokefirered/data/battle_scripts_2.s:54
    Ui.push(Strings("%s used\n%s!", st.playerName or "PLAYER", iname))
    -- pokefirered/data/battle_scripts_2.s:116
    Ui.push(Strings("The TRAINER blocked the BALL!"))
    Ui.push(Strings("Don't be a thief!"))
    return D.afterEach()
  end
  local BattleItems = require("src.core.game3.battle.items")
  local result = BattleItems.use(st, ad, bag, session, act.itemId, act.partySlot, act.battler)
  if result == "heal" then
    for _, id in ipairs(SEL_ORDER) do
      local b = State.battler(st, id)
      if b and b.partyIndex == act.partySlot and not State.isAbsent(st, id) then
        local p = Anim.present(id)
        local logical = tonumber(b.mon and b.mon.hp) or 0
        if p and p.displayHp ~= nil and math.abs(logical - p.displayHp) >= 1 then
          Anim.tweenHp(id, p.displayHp, logical, b.mon.maxHp)
        end
      end
    end
  end
  return D.afterEach()
end

function D.run(act)
  local st, ad = Battle._st, Battle._adapter
  local fled = false
  local evs = D.capture(function()
    fled = Engine.tryFlee(st, ad, State.battler(st, act.battler)) and true or false
  end)
  for _, e in ipairs(evs) do
    if e.kind == "msg" then Ui.push(e.text) end
  end
  if fled then
    st.over = true
    st.result = "run"
    st.endReason = "flee"
    Battle._pendingEnd = "run"
    Battle._phase = "ending"
    return
  end
  return D.afterEach()
end

-- pokefirered/data/battle_scripts_2.s:87
local function finish_catch_flow(catchRes, ename, nicknamed)
  if catchRes and catchRes.location == "pc" then
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local Storage = require("src.core.game3.storage")
    -- pokefirered/src/battle_script_commands.c:9617
    local page = Storage.pcTransferMessage(session, ename or "POKéMON")
    if not nicknamed then
      Battle._phase = "catch_pc_msg"
      Ui.push(page)
      return
    end
  end
  Battle._actions = {}
  Battle._pendingEnd = "catch"
  Battle._phase = "ending"
end

local function start_post_catch_flow(catchRes)
  if Battle._headless then
    Battle._actions = {}
    Battle._pendingEnd = "catch"
    Battle._phase = "ending"
    return
  end

  local enemy = Battle._st and Battle._st.enemy
  local mon = (catchRes and catchRes.mon) or (enemy and enemy.mon)
  local sp = (enemy and enemy.mon and (enemy.mon.species or enemy.mon.speciesId))
    or (catchRes and catchRes.mon and (catchRes.mon.species or catchRes.mon.speciesId))
    or (enemy and enemy.species) or 1
  local ename = (mon and (mon.nickname ~= "" and mon.nickname or mon.name))
    or Pokemon.name(sp) or "POKéMON"
  local gender = (mon and (mon.gender or (mon.isFemale and 1))) or (enemy and enemy.gender) or 0
  local personality = (mon and mon.personality) or 0

  local function prompt_nickname()
    Battle._phase = "catch_nickname_prompt"
    -- pokefirered/src/battle_message.c:477
    Ui.askYesNo(Strings("Give a nickname to the\ncaptured %s?", ename), function(yes)
      if yes then
        local okN, Naming = pcall(require, "src.ui.game3.naming")
        if okN and Naming and Naming.open then
          Battle._phase = "catch_naming"
          Naming.open({
            template = "CAUGHT_MON",
            maxLen = 10,
            species = sp,
            gender = gender,
            personality = personality,
            seed = ename,
            -- pokefirered/src/naming_screen.c:696
            sentToPc = (catchRes and catchRes.location == "pc") or false,
            -- pret naming_screen.c:1712 DrawMonTextEntryBox: gSpeciesNames[mon]
            -- + gText_PkmnsNickname. The hand-written "YOUR POKEMON'S NICKNAME?"
            -- was 141px wide and spilled over the frame's right edge.
            title = Naming.monTitle(Pokemon.name(sp)),
            onDone = function(nick)
              if nick and nick ~= "" and nick ~= ename then
                if mon then mon.nickname = nick end
              end
              -- pokefirered/src/battle_script_commands.c:9853
              finish_catch_flow(catchRes, ename, true)
            end,
          })
          return
        end
      end
      finish_catch_flow(catchRes, ename)
    end)
  end

  if catchRes and catchRes.firstTimeCaught and sp then
    local okP, Pokedex = pcall(require, "src.ui.game3.pokedex")
    if okP and Pokedex and Pokedex.showRegistration then
      Battle._phase = "pokedex_reg"
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      Pokedex.showRegistration(sp, {
        session = session,
        onDone = function()
          prompt_nickname()
        end,
      })
      return
    end
  end

  prompt_nickname()
end

Battle.startPostCatchFlow = start_post_catch_flow
Battle.finishCatchFlow = finish_catch_flow

function Battle.update(dt, game)
  if not Battle._active then return end

  -- A stat window whose phase can no longer dismiss it must not linger (#2324).
  if not Battle.statWindowPhase() then
    local StatGrowth = package.loaded["src.ui.game3.stat_growth"]
    if StatGrowth and StatGrowth.isOpen and StatGrowth.isOpen() then
      StatGrowth.close({ silent = true })
    end
  end

  local input = game and game.input
  local Pokedex = package.loaded["src.ui.game3.pokedex"]
  if Pokedex and Pokedex.isOpen and Pokedex.isOpen() then
    if input then Pokedex.handleInput(input) end
    return
  end

  local Naming = package.loaded["src.ui.game3.naming"]
  if Naming and Naming.isOpen and Naming.isOpen() then
    if input then Naming.update(input, dt or (1 / 60)) end
    return
  end

  if not Battle._headless then
    Anim.update(dt or 0)
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.tickCry then Audio.tickCry(dt or 1 / 60) end
    update_low_hp_music()
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() and PartyMenu.update then
      PartyMenu.update(dt or (1 / 60))
    end
  end

  if Battle._phase == "command" and not Battle._auto and Battle._st and Battle._st.double then
    D.commandUpdate(input)
    return
  end

  if Battle._phase == "command" and not Battle._auto then
    local BagMenu = require("src.ui.game3.bag_menu")
    if BagMenu.isOpen and BagMenu.isOpen() then
      if input then BagMenu.handleInput(input) end
      return
    end
    local PartyMenu = require("src.ui.game3.party_menu")
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      if input then party_menu_input(PartyMenu, input) end
      return
    end
    if Ui._mode == "bag" or Ui._mode == "party" then
      Ui._mode = "menu"
    end
    if Ui.selectionPump() then
      local scmd = Ui.takeCommand()
      if scmd then begin_turn_with(scmd) end
      return
    end
    if input then Ui.handleInput(input) end
    local cmd = Ui.takeCommand()
    if cmd then
      begin_turn_with(cmd)
    end
    return
  end

  if Battle._phase == "preturn" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    if AnimSeq.update() then
      Battle._phase = "actions"
    end
    return
  end

  -- Choice input during award / shift prompt / evolution learn-move prompts / catch nickname prompt / evolving
  if Battle.statWindowPhase()
      and not Battle._auto and game and game.input then
    local EvolutionScene = package.loaded["src.ui.game3.evolution_scene"]
    if EvolutionScene and EvolutionScene.isOpen and EvolutionScene.isOpen() then
      EvolutionScene.handleInput(game.input)
      return
    end
    local StatGrowth = package.loaded["src.ui.game3.stat_growth"]
    if StatGrowth and StatGrowth.isOpen and StatGrowth.isOpen() then
      if StatGrowth.handleInput(game.input) then
        return
      end
    end
    local SummaryMenu = package.loaded["src.ui.game3.summary_menu"]
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if (Battle._phase == "awarding" or Battle._phase == "evolving")
        and SummaryMenu and SummaryMenu.isOpen and SummaryMenu.isOpen()
        and not (PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen()) then
      SummaryMenu.handleInput(game.input)
      return
    end
    if Ui.choiceActive and Ui.choiceActive() then
      Ui.handleInput(game.input)
      return
    end
  end

  -- Intro: pump dialogs even while slide tweens run
  if Battle._phase == "intro" then
    if not Ui.pump() then return end
    if IntroSeq.update() then
      -- pokefirered/src/battle_controller_oak_old_man.c:626
      local stIntro = Battle._st
      if stIntro and Oak.active(stIntro) and not stIntro.oakIntroDone then
        stIntro.oakIntroDone = true
        if Oak.say(stIntro, "forPetesSake") then return end
      end
      if begin_start_effects() then return end
      Battle._phase = "command"
      if Battle._auto then
        begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
      else
        Ui.openMenu()
      end
    end
    return
  end

  if Battle._phase == "startfx" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    if AnimSeq.update() then
      Battle._phase = "command"
      if Battle._auto then
        begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
      else
        Ui.openMenu()
      end
    end
    return
  end

  -- Mid-turn switch-in during faint / pursuit
  if Battle._phase == "faint_switch" then
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() then
      if input then party_menu_input(PartyMenu, input) end
      return
    end
    if Anim.busy() then return end
    if Ui.choiceActive and Ui.choiceActive() then
      return
    end
    if not Ui.pump() then return end
    if SwitchSeq.update() then
      Battle._phase = "actions"
      if not Battle._actions or not Battle._actions[Battle._actionI] then
        after_actions()
      end
    end
    return
  end

  -- Shift prompt: after dialog dismissed, open Yes/No box
  if Battle._phase == "shift_prompt" then
    if not Ui.pump() then return end
    if Ui.choiceActive and Ui.choiceActive() then
      if input then Ui.handleInput(input) end
      return
    end
    if not Battle._shiftAsked then
      Battle._shiftAsked = true
      Ui.askYesNo(function(yes)
        Battle._shiftAsked = false
        local nextEnemyIdx = Battle._shiftEnemyIdx
        Battle._shiftEnemyIdx = nil
        local st = Battle._st
        if yes and st then
          local PartyMenu = require("src.ui.game3.party_menu")
          local Runtime = package.loaded["src.core.game3.runtime"]
          local session = Runtime and Runtime.getSession and Runtime.getSession()
          State.syncBattlerToParty(st.player, st.playerParty)
          PartyMenu.show(st.playerParty or (session and session.party), session and session.move_overlay, {
            mode = "battle_switch",
            session = session,
            activeSlot = st.player.partyIndex,
            battle = true,
            validate = function(slot)
              if slot == st.player.partyIndex then return nil end
              return Commands.switchError(st, slot, true)
            end,
            onSelect = function(pSlot)
              if pSlot == nil or pSlot == st.player.partyIndex then
                send_out_enemy_next(nextEnemyIdx)
              else
                SwitchSeq.beginShiftSwitch(st, pSlot, nextEnemyIdx, {
                  headless = false,
                  pushMsg = function(t) Ui.push(t) end,
                  onDone = function()
                    Battle._phase = "command"
                    Ui.openMenu()
                  end,
                })
                Battle._phase = "switching"
              end
            end,
            onClose = function()
              send_out_enemy_next(nextEnemyIdx)
            end,
          })
          Battle._phase = "switching"
        else
          send_out_enemy_next(nextEnemyIdx)
        end
      end)
    end
    return
  end

  -- Switch / send-out presentation
  if Battle._phase == "switching" then
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() then
      if input then party_menu_input(PartyMenu, input) end
      return
    end
    if Anim.busy() then return end
    if Ui.choiceActive and Ui.choiceActive() then
      return
    end
    if not Ui.pump() then return end
    SwitchSeq.update()
    return
  end

  -- Anim sequence owns presentation pacing
  if Battle._phase == "animating" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    local done = AnimSeq.update()
    if done then
      after_anim_sequence()
    end
    return
  end

  -- Poké Ball catch presentation
  if Battle._phase == "catching" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    local done = CatchSeq.update()
    if done then
      local res = CatchSeq.result()
      if res == "catch" then
        local catchRes = CatchSeq.catchResult and CatchSeq.catchResult()
        start_post_catch_flow(catchRes)
      elseif safari_out_of_balls(Battle._st) then
        return
      else
        Battle._phase = "actions"
        if not Battle._actions or not Battle._actions[Battle._actionI] then
          after_actions()
        end
      end
    end
    return
  end

  if Battle._phase == "pokedex_reg" then
    return
  end

  if Battle._phase == "catch_nickname_prompt" then
    if not Ui.pump() then return end
    return
  end

  if Battle._phase == "catch_naming" then
    return
  end

  if Battle._phase == "catch_pc_msg" then
    if not Ui.pump() then return end
    Battle._actions = {}
    Battle._pendingEnd = "catch"
    Battle._phase = "ending"
    return
  end

  -- EXP award / level-up / learn-move
  if Battle._phase == "awarding" then
    if Anim.busy() then return end
    if Ui.choiceActive and Ui.choiceActive() then return end
    if not Ui.pump() then return end
    local done = ExpSeq.update()
    if done then
      Battle._leveledUp = ExpSeq.leveledSet() or Battle._leveledUp
      local cb = Battle._onExpDone
      Battle._onExpDone = nil
      if cb then
        cb()
      else
        begin_evo_or_end()
      end
    end
    return
  end

  -- Post-battle evolution (EVO_LEVEL)
  if Battle._phase == "evolving" then
    local EvolutionScene = package.loaded["src.ui.game3.evolution_scene"]
    if EvolutionScene and EvolutionScene.isOpen and EvolutionScene.isOpen() then
      if not Battle._auto and game and game.input then
        EvolutionScene.handleInput(game.input)
      end
      return
    end
    if Ui.choiceActive and Ui.choiceActive() then return end
    if not Ui.pump() then return end
    local done = EvoSeq.update()
    if done then
      Battle._phase = "ending"
    end
    return
  end

  if Battle._phase == "residuals" then
    if Anim.busy() then return end
    if not Ui.pump() then return end
    if not AnimSeq.update() then return end
    Battle._residualEvents = nil
    Battle._residualIndex = 1
    Battle._residualStepState = nil
    if Battle._st and Battle._st.double then
      D.endTurn()
      return
    end
    if check_faints_and_end() then
      return
    end
    Battle._phase = "command"
    if Battle._auto then
      begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
    else
      Ui.openMenu()
    end
    return
  end

  if Anim.busy() then return end
  if not Ui.pump() then return end

  if Battle._phase == "actions" then
    step_action()
    if (Battle._headless or not Battle._fade) and Battle._phase == "ending" then
      finish(Battle._pendingEnd or "win")
    end
    return
  end

  if Battle._phase == "ending" then
    if Battle._headless or not Battle._fade then
      finish(Battle._pendingEnd or "win")
    else
      Battle._phase = "fade_out"
      local okA, Audio = pcall(require, "src.core.game3.audio")
      if okA and Audio and Audio.fadeOutBgm then
        Audio.fadeOutBgm(5)
      end
      local okF, Fade = pcall(require, "src.ui.game3.fade")
      if okF and Fade and Fade.begin then
        Fade.begin(Fade.MODE.TO_BLACK, 1, function()
          finish(Battle._pendingEnd or "win")
        end)
      else
        finish(Battle._pendingEnd or "win")
      end
    end
    return
  end

  if Battle._phase == "fade_out" then
    return
  end

  if Battle._phase == "command" and Battle._auto then
    begin_turn_with(Commands.playerAction(Battle._st, 1, 1))
  end
end

function Battle.runToEnd()
  if not Battle._active then return Battle.getResult() end
  Battle._auto = true
  Battle._headless = true
  local savedLog = Ui.log and Ui.log() or {}
  Ui.reset({ headless = true })
  Ui.bindState(Battle._st)
  if savedLog and #savedLog > 0 then
    for _, t in ipairs(savedLog) do
      Ui._log[#Ui._log + 1] = t
    end
  end
  Anim.reset({ headless = true, double = Battle._st and Battle._st.double })
  AnimSeq.reset()
  CatchSeq.reset()
  ExpSeq.reset()
  EvoSeq.reset()
  IntroSeq.reset()
  LearnMove.reset()
  local guard = 0
  while Battle._active and guard < 800 do
    guard = guard + 1
    Battle.update(0, nil)
  end
  return Battle.getResult()
end

function Battle.draw(_game, w, h)
  if not Battle._active then return end
  Ui.draw(w, h)
end

function Battle.abort(result)
  if Battle._active then finish(result or "run") end
end

return Battle
