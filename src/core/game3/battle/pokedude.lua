local Pokedude = {}

local PLAYER, OPPONENT = 0, 1

-- pokefirered/include/teachy_tv.h:4
local TTVSCR_BATTLE, TTVSCR_STATUS, TTVSCR_MATCHUPS, TTVSCR_CATCHING = 0, 1, 2, 3

-- pokefirered/include/constants/battle.h:78
Pokedude.OUTCOME = { WON = 1, LOST = 2, DREW = 3, RAN = 4, CAUGHT = 7 }

-- pokefirered/include/constants/items.h:7
local ITEM_POKE_BALL = 4
local ITEM_ANTIDOTE = 14

-- pokefirered/include/constants/trainers.h:175
Pokedude.BACK_PIC = 4

-- pokefirered/src/pokeball.c:389
function Pokedude.sendOutOrigin(st)
  if st and st.pokedude then return 32, 64 end
  return 48, 70
end

-- pokefirered/src/battle_controller_pokedude.c:2326 sParties_Battle
Pokedude.PARTIES = {
  [TTVSCR_BATTLE] = {
    { side = PLAYER, level = 15, species = 19, moves = { 33, 39, 158, 98 }, nature = 1, gender = 0 },
    { side = OPPONENT, level = 18, species = 16, moves = { 33, 28, 16, 98 }, nature = 4, gender = 0 },
  },
  -- pokefirered/src/battle_controller_pokedude.c:2347 sParties_Status
  [TTVSCR_STATUS] = {
    { side = PLAYER, level = 15, species = 19, moves = { 33, 39, 158, 98 }, nature = 1, gender = 0 },
    { side = OPPONENT, level = 14, species = 43, moves = { 71, 230, 77 }, nature = 19, gender = 0 },
  },
  -- pokefirered/src/battle_controller_pokedude.c:2368 sParties_Matchups
  [TTVSCR_MATCHUPS] = {
    { side = PLAYER, level = 15, species = 60, moves = { 55, 95, 145 }, nature = 19, gender = 0 },
    { side = PLAYER, level = 15, species = 12, moves = { 93, 77, 78, 79 }, nature = 19, gender = 0 },
    { side = OPPONENT, level = 14, species = 43, moves = { 71, 230, 77 }, nature = 19, gender = 0 },
  },
  -- pokefirered/src/battle_controller_pokedude.c:2397 sParties_Catching
  [TTVSCR_CATCHING] = {
    { side = PLAYER, level = 15, species = 12, moves = { 93, 77, 79, 78 }, nature = 19, gender = 0 },
    { side = OPPONENT, level = 11, species = 39, moves = { 47, 111, 1 }, nature = 23, gender = 0 },
  },
}

local function row(p, o, dp, dop)
  return { cursor = { [PLAYER] = p, [OPPONENT] = o }, delay = { [PLAYER] = dp, [OPPONENT] = dop } }
end

-- pokefirered/src/battle_controller_pokedude.c:2002 sInputScripts_ChooseAction_Battle
local ACTION_ROWS = {
  row(0, 0, 64, 0), row(4, 4, 0, 0),
  row(0, 0, 64, 0), row(1, 0, 64, 0), row(0, 0, 64, 0),
  row(0, 0, 64, 0), row(2, 0, 64, 0), row(0, 0, 64, 0),
  row(0, 0, 64, 0), row(0, 0, 64, 0), row(1, 0, 64, 0),
}
local ACTION_BASE = { [TTVSCR_BATTLE] = 0, [TTVSCR_STATUS] = 2, [TTVSCR_MATCHUPS] = 5, [TTVSCR_CATCHING] = 8 }

-- pokefirered/src/battle_controller_pokedude.c:2070 sInputScripts_ChooseMove_Battle
local MOVE_ROWS = {
  [TTVSCR_BATTLE] = { row(2, 2, 64, 0), row(255, 255, 0, 0) },
  [TTVSCR_STATUS] = { row(2, 2, 64, 0), row(2, 0, 64, 0), row(2, 0, 64, 0), row(255, 255, 0, 0) },
  [TTVSCR_MATCHUPS] = { row(2, 0, 64, 0), row(0, 0, 64, 0), row(0, 0, 64, 0), row(255, 255, 0, 0) },
  [TTVSCR_CATCHING] = { row(0, 2, 64, 0), row(2, 2, 64, 0), row(255, 255, 0, 0) },
}

local function vo(cmd, side, stringId, kind)
  return { cmd = cmd, side = side, stringId = stringId, kind = kind }
end

-- pokefirered/src/battle_controller_pokedude.c:2146 sPokedudeTextScripts_Battle
Pokedude.TEXT_SCRIPTS = {
  [TTVSCR_BATTLE] = {
    vo("chooseaction", PLAYER, nil, "voiceover"),
    vo("printstring", OPPONENT, "STRINGID_USEDMOVE", "voiceover"),
    vo("chooseaction", PLAYER, nil, "voiceover"),
    vo("printstring", PLAYER, "STRINGID_PKMNGAINEDEXP", "voiceover"),
  },
  [TTVSCR_STATUS] = {
    vo("chooseaction", PLAYER, nil, nil),
    vo("chooseaction", PLAYER, nil, "healthbox"),
    vo("openbag", PLAYER, nil, "voiceover"),
    vo("printstring", OPPONENT, "STRINGID_USEDMOVE", "voiceover"),
    vo("printstring", PLAYER, "STRINGID_PKMNGAINEDEXP", "voiceover"),
  },
  [TTVSCR_MATCHUPS] = {
    vo("printstring", OPPONENT, "STRINGID_USEDMOVE", "voiceover"),
    vo("chooseaction", PLAYER, nil, "voiceover"),
    vo("choosepokemon", PLAYER, nil, "voiceover"),
    vo("printstring", OPPONENT, "STRINGID_USEDMOVE", "voiceover"),
    vo("chooseaction", PLAYER, nil, "voiceover"),
    vo("choosemove", PLAYER, nil, "voiceover"),
    vo("printstring", PLAYER, "STRINGID_PKMNGAINEDEXP", "voiceover"),
  },
  [TTVSCR_CATCHING] = {
    vo("chooseaction", PLAYER, nil, "voiceover"),
    vo("chooseaction", PLAYER, nil, nil),
    vo("chooseaction", PLAYER, nil, "voiceover"),
    vo("printstring", OPPONENT, "STRINGID_PKMNFASTASLEEP", "voiceover"),
    vo("openbag", PLAYER, nil, "voiceover"),
    vo("endlinkbattle", PLAYER, nil, "voiceover"),
  },
}

-- pokefirered/src/battle_controller_pokedude.c:2288
Pokedude.TEXT_TABLES = {
  [TTVSCR_BATTLE] = "sPokedudeTexts_Battle",
  [TTVSCR_STATUS] = "sPokedudeTexts_Status",
  [TTVSCR_MATCHUPS] = "sPokedudeTexts_TypeMatchup",
  [TTVSCR_CATCHING] = "sPokedudeTexts_Catching",
}

function Pokedude.textKey(script, index0)
  local RomText = require("src.core.game3.rom_text")
  return RomText.key(assert(Pokedude.TEXT_TABLES[script], "no pokedude text table"), index0)
end

-- pokefirered/src/item_menu.c:2262 Task_Bag_TeachyTvCatching
local BAG_ITEM = { [TTVSCR_STATUS] = ITEM_ANTIDOTE, [TTVSCR_CATCHING] = ITEM_POKE_BALL }

-- pokefirered/include/constants/songs.h:306
local MUS_VS_WILD = 298
-- pokefirered/include/constants/songs.h:319
local MUS_VICTORY_WILD = 311

local SIDE_OF = { player = PLAYER, enemy = OPPONENT, [PLAYER] = PLAYER, [OPPONENT] = OPPONENT }

-- pokefirered/src/battle_message.c:1693
local STRING_ALIAS = { sText_AttackerUsedX = "STRINGID_USEDMOVE", [4] = "STRINGID_USEDMOVE" }

-- pokefirered/src/pokemon.c:1877 CreateMonWithGenderNatureLetter
local function create_mon(info)
  local Pokemon = require("src.core.game3.pokemon")
  local Rng = require("src.core.game3.rng")
  local SummaryData = require("src.core.game3.summary_data")
  local want = (info.gender == 0) and "M" or "F"
  local personality
  repeat
    personality = Rng.Random32()
  until Pokemon.natureId(personality) == info.nature and Pokemon.gender(info.species, personality) == want
  local moves, pp, maxPp = {}, {}, {}
  -- pokefirered/src/battle_controller_pokedude.c:2696 SetMonMoveSlot
  for j = 1, 4 do
    local mv = info.moves[j]
    if mv and mv ~= 0 then
      moves[#moves + 1] = mv
      pp[#pp + 1] = Pokemon.movePp(mv)
      maxPp[#maxPp + 1] = Pokemon.movePp(mv)
    end
  end
  local growthRate = Pokemon.growthRate(info.species)
  local ability = Pokemon.abilityId(info.species, personality)
  local meta = Pokemon.speciesMeta(info.species)
  -- pokefirered/src/pokemon.c:1904 CreateMon
  local mon = {
    species = info.species,
    speciesId = info.species,
    speciesNumbering = Pokemon.NUMBERING_INTERNAL,
    name = Pokemon.name(info.species),
    nickname = "",
    level = info.level,
    metLevel = info.level,
    growthRate = growthRate,
    exp = SummaryData.expForLevel(growthRate, info.level),
    moves = moves,
    pp = pp,
    maxPp = maxPp,
    personality = personality,
    nature = info.nature,
    ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    ability = ability,
    abilityId = ability,
    gender = want,
    item = 0,
    friendship = meta and meta.friendship or 70,
    happiness = meta and meta.friendship or 70,
    pokeball = ITEM_POKE_BALL,
  }
  Pokemon.applyStats(mon)
  return mon
end

-- pokefirered/src/battle_controller_pokedude.c:2675 InitPokedudePartyAndOpponent
function Pokedude.build(scriptId)
  local rows = Pokedude.PARTIES[tonumber(scriptId)]
  if not rows then error("no pokedude party for script " .. tostring(scriptId)) end
  local party, foes = {}, {}
  for _, info in ipairs(rows) do
    local mon = create_mon(info)
    if info.side == PLAYER then party[#party + 1] = mon else foes[#foes + 1] = mon end
  end
  return party, foes
end

function Pokedude.newState(scriptId)
  return {
    script = tonumber(scriptId) or TTVSCR_BATTLE,
    messageNo = 0,
    battlers = {
      [PLAYER] = { actionIdx = 0, moveIdx = 0, timer = 0, actionCursor = 0, moveCursor = 0 },
      [OPPONENT] = { actionIdx = 0, moveIdx = 0, timer = 0, actionCursor = 0, moveCursor = 0 },
    },
    log = {},
  }
end

function Pokedude.textFor(st, index0)
  local BattleText = require("src.core.game3.battle.battle_text")
  return BattleText.get(Pokedude.textKey(st.pd.script, index0), { playerName = st.playerName })
end

local function push_voiceover(st, index0, entry, onDone)
  local Ui = require("src.core.game3.battle.ui")
  local text = Pokedude.textFor(st, index0)
  st.pd.log[#st.pd.log + 1] = Pokedude.textKey(st.pd.script, index0)
  Ui.markVoiceover(text, { litHealthbox = entry.kind == "healthbox" })
  Ui.push(text, function()
    -- pokefirered/src/battle_controller_pokedude.c:2573 msg_idx == STRINGID_PKMNGAINEDEXP
    if entry.stringId == "STRINGID_PKMNGAINEDEXP" then
      local Audio = require("src.core.game3.audio")
      Audio.playSong(MUS_VICTORY_WILD)
    end
    if onDone then onDone() end
  end)
end

-- pokefirered/src/battle_controller_pokedude.c:2508 HandlePokedudeVoiceoverEtc
function Pokedude.event(st, cmd, side, stringId)
  local pd = st and st.pd
  if not pd then return false end
  side = SIDE_OF[side]
  stringId = STRING_ALIAS[stringId] or stringId
  local script = Pokedude.TEXT_SCRIPTS[pd.script] or {}
  local queued = false
  while true do
    local entry = script[pd.messageNo + 1]
    if not entry or entry.cmd ~= cmd or entry.side ~= side then break end
    if cmd == "printstring" and entry.stringId ~= stringId then break end
    local index0 = pd.messageNo
    pd.messageNo = pd.messageNo + 1
    if not entry.kind then break end
    push_voiceover(st, index0, entry)
    queued = true
  end
  return queued
end

local function action_row(pd, idx)
  return ACTION_ROWS[ACTION_BASE[pd.script] + idx + 1]
end

local function move_row(pd, idx)
  return MOVE_ROWS[pd.script][idx + 1]
end

-- pokefirered/src/battle_controller_pokedude.c:2459
local function take_action(pd, side)
  local b = pd.battlers[side]
  local r = action_row(pd, b.actionIdx)
  b.actionIdx = b.actionIdx + 1
  local nxt = action_row(pd, b.actionIdx)
  if nxt and nxt.cursor[side] == 4 then b.actionIdx = 0 end
  return r.cursor[side]
end

-- pokefirered/src/battle_controller_pokedude.c:2490
local function take_move(pd, side)
  local b = pd.battlers[side]
  local r = move_row(pd, b.moveIdx)
  b.moveIdx = b.moveIdx + 1
  if move_row(pd, b.moveIdx).cursor[side] == 255 then b.moveIdx = 0 end
  return r.cursor[side]
end

-- pokefirered/src/battle_controller_pokedude.c:2429 PokedudeSimulateInputChooseAction
function Pokedude.enemyAction(st)
  local pd = st.pd
  local choice = take_action(pd, OPPONENT)
  local mon = st.enemy and st.enemy.mon or {}
  local slot = 1
  if choice == 0 then
    slot = take_move(pd, OPPONENT) + 1
  end
  local mv = mon.moves and mon.moves[slot]
  if not mv or mv == 0 then slot, mv = 1, mon.moves and mon.moves[1] end
  return { kind = "move", move = mv, slot = slot, user = "enemy" }
end

local function action_command(st, choice, moveSlot)
  local pd = st.pd
  if choice == 1 then
    return { kind = "bag", user = "player", itemId = BAG_ITEM[pd.script] or ITEM_POKE_BALL,
      partySlot = st.player and st.player.partyIndex or 1 }
  elseif choice == 2 then
    -- pokefirered/src/party_menu.c:2020 Task_PartyMenu_Pokedude
    return { kind = "switch", user = "player", slot = (st.player and st.player.partyIndex == 2) and 1 or 2 }
  elseif choice == 3 then
    return { kind = "run", user = "player" }
  end
  local Commands = require("src.core.game3.battle.commands")
  return Commands.playerAction(st, 1, moveSlot or 1)
end

function Pokedude.autoPlayerAction(st)
  local pd = st.pd
  Pokedude.event(st, "chooseaction", PLAYER)
  local choice = take_action(pd, PLAYER)
  if choice == 0 then
    Pokedude.event(st, "choosemove", PLAYER)
    return action_command(st, 0, take_move(pd, PLAYER) + 1)
  elseif choice == 1 then
    Pokedude.event(st, "openbag", PLAYER)
  elseif choice == 2 then
    Pokedude.event(st, "choosepokemon", PLAYER)
  end
  return action_command(st, choice)
end

local function select_se()
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  Audio.playSe(SE.SE_SELECT)
end

local function menu_session(Ui)
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Ui._session or (Runtime and Runtime.getSession and Runtime.getSession())
end

local function menu_cancel(pd)
  pd.menu = nil
  pd.step = "menu_cancelled"
  require("src.core.game3.battle").quitPokedude()
end

local QUIET_ADAPTER = { say = function() end }

-- pokefirered/src/party_menu.c:5866 Pokedude_ChooseMonForInBattleItem
local function open_item_party(st, Ui, itemId)
  local pd = st.pd
  local PartyMenu = require("src.ui.game3.party_menu")
  local State = require("src.core.game3.battle.state")
  local session = menu_session(Ui)
  if st.player and st.playerParty then State.syncBattlerToParty(st.player, st.playerParty) end
  pd.menu = "party"
  PartyMenu.showPokedude(st.playerParty, {
    plan = "item",
    session = session,
    bag = session and session.bag,
    item = itemId,
    battleOrder = PartyMenu.battleOrder(st),
    activeSlot = st.player and st.player.partyIndex or 1,
    onUse = function(slot)
      local BattleItems = require("src.core.game3.battle.items")
      local RomText = require("src.core.game3.rom_text")
      local Pokemon = require("src.core.game3.pokemon")
      local mon = st.playerParty[slot]
      local result = BattleItems.use(st, QUIET_ADAPTER, session and session.bag, session, itemId, slot)
      if result ~= "heal" then return RomText.box("gText_WontHaveEffect", { maxWidth = 216 }) end
      -- pokefirered/src/party_menu.c:4345
      return RomText.box("gText_PkmnCuredOfPoison", { stringVars = { Pokemon.displayMonName(mon) }, maxWidth = 216 })
    end,
    onSelect = function(slot)
      pd.menu = nil
      pd.menuCmd = { kind = "bag", user = "player", itemId = itemId, partySlot = slot, pokedudeUsed = true }
    end,
    onCancel = function() menu_cancel(pd) end,
  })
end

-- pokefirered/src/battle_controller_pokedude.c:376 CompleteWhenChoseItem
local function open_bag(st, Ui)
  local pd = st.pd
  local BagMenu = require("src.ui.game3.bag_menu")
  local session = menu_session(Ui)
  local plan = (pd.script == TTVSCR_STATUS) and "status" or "catching"
  pd.menu = "bag"
  Ui._mode = "bag"
  BagMenu.showPokedude(session and session.bag, {
    session = session,
    plan = plan,
    onItem = function(itemId)
      Ui._mode = "none"
      if plan == "status" then
        -- pokefirered/src/item_menu.c:2351 ItemMenu_SetExitCallback(Pokedude_ChooseMonForInBattleItem)
        open_item_party(st, Ui, itemId)
        return
      end
      pd.menu = nil
      pd.menuCmd = { kind = "bag", user = "player", itemId = itemId }
    end,
    onCancel = function()
      Ui._mode = "none"
      menu_cancel(pd)
    end,
  })
end

-- pokefirered/src/party_menu.c:5859 Pokedude_OpenPartyMenuInBattle
local function open_switch_party(st, Ui)
  local pd = st.pd
  local PartyMenu = require("src.ui.game3.party_menu")
  local State = require("src.core.game3.battle.state")
  local Commands = require("src.core.game3.battle.commands")
  if st.player and st.playerParty then State.syncBattlerToParty(st.player, st.playerParty) end
  pd.menu = "party"
  Ui._mode = "party"
  PartyMenu.showPokedude(st.playerParty, {
    plan = "switch",
    session = menu_session(Ui),
    activeSlot = st.player and st.player.partyIndex or 1,
    validate = function(slot) return Commands.switchError(st, slot) end,
    onSelect = function(slot)
      Ui._mode = "none"
      pd.menu = nil
      pd.menuCmd = { kind = "switch", user = "player", slot = slot }
    end,
    onCancel = function()
      Ui._mode = "none"
      menu_cancel(pd)
    end,
  })
end

local function open_menu(st, Ui, choice)
  if Ui._headless then return action_command(st, choice) end
  st.pd.step = "menu"
  if choice == 1 then open_bag(st, Ui) else open_switch_party(st, Ui) end
  return nil
end

local NO_INPUT = { wasPressed = function() return false end, isDown = function() return false end }

local function menu_step(st, Ui, input)
  local pd = st.pd
  if pd.menuCmd then
    local cmd = pd.menuCmd
    pd.menuCmd = nil
    pd.step = nil
    return cmd
  end
  if pd.menu == "bag" then
    require("src.ui.game3.bag_menu").handleInput(input or NO_INPUT)
  elseif pd.menu == "party" then
    local PartyMenu = require("src.ui.game3.party_menu")
    if PartyMenu.isOpen() then PartyMenu.handleInput(input or NO_INPUT) end
  end
  if pd.menuCmd then return menu_step(st, Ui, input) end
  return nil
end

-- pokefirered/src/battle_controller_pokedude.c:2429 PokedudeSimulateInputChooseAction
-- pokefirered/src/battle_controller_pokedude.c:2477 PokedudeSimulateInputChooseMove
function Pokedude.commandStep(st, Ui, input)
  local pd = st.pd
  local b = pd.battlers[PLAYER]
  local step = pd.step
  if step == "menu" then return menu_step(st, Ui, input) end
  if step == "menu_cancelled" then return nil end
  if step == nil then
    Ui._mode = "none"
    if Pokedude.event(st, "chooseaction", PLAYER) then
      pd.step = "vo_action"
      return nil
    end
    step = "open_action"
  end
  if step == "vo_action" or step == "vo_move" or step == "vo_bag" or step == "vo_party" then
    if not Ui.pump() then return nil end
    if step == "vo_action" then step = "open_action"
    elseif step == "vo_move" then step = "open_move"
    else
      pd.step = nil
      return open_menu(st, Ui, pd.choice)
    end
  end
  if step == "open_action" then
    Ui.openMenu()
    Ui._menuIndex = b.actionCursor + 1
    b.timer = 0
    pd.step = "action"
    return nil
  end
  if step == "open_move" then
    Ui._mode = "moves"
    Ui._moveIndexBattler = st.player
    Ui._moveIndex = b.moveCursor + 1
    b.timer = 0
    pd.step = "move"
    return nil
  end
  Ui.tick()
  if step == "action" then
    local r = action_row(pd, b.actionIdx)
    local target, delay = r.cursor[PLAYER], r.delay[PLAYER]
    if delay == b.timer then
      select_se()
      b.timer = 0
      local choice = take_action(pd, PLAYER)
      pd.choice = choice
      if choice == 0 then
        Ui._mode = "none"
        if Pokedude.event(st, "choosemove", PLAYER) then
          pd.step = "vo_move"
          return nil
        end
        pd.step = "open_move"
        return nil
      end
      Ui._mode = "none"
      local cmd = (choice == 1 and "openbag") or (choice == 2 and "choosepokemon") or nil
      if cmd and Pokedude.event(st, cmd, PLAYER) then
        pd.step = (choice == 1) and "vo_bag" or "vo_party"
        return nil
      end
      pd.step = nil
      if cmd then return open_menu(st, Ui, choice) end
      return action_command(st, choice)
    end
    if b.actionCursor ~= target and math.floor(delay / 2) == b.timer then
      select_se()
      b.actionCursor = target
      Ui._menuIndex = target + 1
    end
    b.timer = b.timer + 1
    return nil
  end
  if step == "move" then
    local r = move_row(pd, b.moveIdx)
    local target, delay = r.cursor[PLAYER], r.delay[PLAYER]
    if delay == b.timer then
      select_se()
      b.timer = 0
      local slot = take_move(pd, PLAYER) + 1
      pd.step = nil
      Ui._mode = "none"
      return action_command(st, 0, slot)
    end
    if b.moveCursor ~= target and math.floor(delay / 2) == b.timer then
      select_se()
      b.moveCursor = target
      Ui._moveIndex = target + 1
    end
    b.timer = b.timer + 1
    return nil
  end
  return nil
end

local function stack_module()
  return require("src.ui.game3.stack")
end

local HIDDEN_MENUS = { "src.ui.game3.bag_menu", "src.ui.game3.start_menu" }

local function hide_menus(saved)
  saved.menus = {}
  for _, name in ipairs(HIDDEN_MENUS) do
    local mod = package.loaded[name]
    if mod and mod.open then
      saved.menus[name] = true
      mod.open = false
    end
  end
end

local function show_menus(saved)
  for name in pairs(saved.menus or {}) do
    local mod = package.loaded[name]
    if mod then mod.open = true end
  end
end

local function finish_battle(session, opts, saved, result)
  local TeachyTv = require("src.core.game3.teachy_tv")
  -- pokefirered/src/item_menu.c:2082 RestorePlayerBag
  TeachyTv.restorePlayerBag(session)
  local Stack = stack_module()
  Stack._layers = saved.layers
  show_menus(saved)
  local outcome = Pokedude.OUTCOME.WON
  if result == "draw" then outcome = Pokedude.OUTCOME.DREW
  elseif result == "catch" then outcome = Pokedude.OUTCOME.CAUGHT
  elseif result == "lose" then outcome = Pokedude.OUTCOME.LOST
  elseif result == "run" then outcome = Pokedude.OUTCOME.RAN end
  -- pokefirered/src/teachy_tv.c:1207 TeachyTvRestorePlayerPartyCallback
  if opts.onDone then opts.onDone(outcome) end
end

-- pokefirered/src/teachy_tv.c:1172 TeachyTvPrepBattle
function Pokedude.startTeachyTvBattle(session, scriptId, opts)
  opts = opts or {}
  local Battle = require("src.core.game3.battle")
  if Battle.isActive() then return false end
  local party, foes = Pokedude.build(scriptId)
  local saved = {}
  local function start()
    local Stack = stack_module()
    saved.layers = Stack._layers
    Stack._layers = {}
    -- pokefirered/src/teachy_tv.c:1175 TeachyTvFree
    hide_menus(saved)
    local TeachyTv = require("src.core.game3.teachy_tv")
    TeachyTv.initPokedudeBag(session, scriptId)
    local BattleBg = require("src.core.game3.battle.bg")
    local ok, err = Battle.start({
      wild = true,
      pokedude = true,
      pdScriptNum = scriptId,
      playerParty = party,
      foe = foes[1],
      session = session,
      playerName = session and session.name,
      playerGender = Pokedude.BACK_PIC,
      terrain = BattleBg.TERRAIN.GRASS,
      onDone = function(result)
        finish_battle(session, opts, saved, result)
      end,
    })
    if not ok then
      finish_battle(session, opts, saved, "draw")
      error("pokedude battle failed to start: " .. tostring(err))
    end
  end
  if opts.headless then
    start()
    return true
  end
  -- pokefirered/src/teachy_tv.c:1180 PlayMapChosenOrBattleBGM(MUS_DUMMY)
  local Audio = require("src.core.game3.audio")
  Audio.playSong(MUS_VS_WILD)
  -- pokefirered/src/teachy_tv.c:1195 BattleTransition_StartOnField
  local BattleTransition = require("src.core.game3.battle_transition")
  BattleTransition.start(opts.transition or BattleTransition.ID.SLICE,
    { overUi = true }, start)
  return true
end

return Pokedude
