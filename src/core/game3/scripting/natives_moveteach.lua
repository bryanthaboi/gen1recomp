-- pokefirered/src/party_menu_specials.c:24, pokefirered/src/learn_move.c:367

local MoveLearn = require("src.core.game3.move_learn")

local MoveTeach = {}

-- pokefirered/data/specials.inc:230
local SPECIAL_CHOOSE_MON_FOR_MOVE_RELEARNER = 0xDB
-- pokefirered/data/specials.inc:231
local SPECIAL_SELECT_MOVE_DELETER_MOVE = 0xDC
-- pokefirered/data/specials.inc:232
local SPECIAL_MOVE_DELETER_FORGET_MOVE = 0xDD
-- pokefirered/data/specials.inc:233
local SPECIAL_BUFFER_MOVE_DELETER_NICKNAME_AND_MOVE = 0xDE
-- pokefirered/data/specials.inc:234
local SPECIAL_GET_NUM_MOVES_SELECTED_MON_HAS = 0xDF
-- pokefirered/data/specials.inc:235
local SPECIAL_TEACH_MOVE_RELEARNER_MOVE = 0xE0
-- pokefirered/data/specials.inc:408
local SPECIAL_CHOOSE_MON_FOR_MOVE_TUTOR = 0x18D
-- pokefirered/data/specials.inc:430
local SPECIAL_CAPE_BRINK_GET_MOVE = 0x1A3
-- pokefirered/data/specials.inc:431
local SPECIAL_HAS_LEARNED_ALL_CAPE_BRINK = 0x1A4

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320
local VAR_0x8006 = 0x8006 -- pokefirered/include/constants/vars.h:321
local VAR_0x8007 = 0x8007 -- pokefirered/include/constants/vars.h:322

local PARTY_SIZE = 6 -- pokefirered/include/constants/global.h:78
local MAX_MON_MOVES = 4 -- pokefirered/include/constants/global.h:77
-- pokefirered/include/constants/party_menu.h:62
local PARTY_MENU_TYPE_MOVE_RELEARNER = 7

MoveTeach.SPECIAL = {
  ChooseMonForMoveRelearner = SPECIAL_CHOOSE_MON_FOR_MOVE_RELEARNER,
  SelectMoveDeleterMove = SPECIAL_SELECT_MOVE_DELETER_MOVE,
  MoveDeleterForgetMove = SPECIAL_MOVE_DELETER_FORGET_MOVE,
  BufferMoveDeleterNicknameAndMove = SPECIAL_BUFFER_MOVE_DELETER_NICKNAME_AND_MOVE,
  GetNumMovesSelectedMonHas = SPECIAL_GET_NUM_MOVES_SELECTED_MON_HAS,
  TeachMoveRelearnerMove = SPECIAL_TEACH_MOVE_RELEARNER_MOVE,
  ChooseMonForMoveTutor = SPECIAL_CHOOSE_MON_FOR_MOVE_TUTOR,
  CapeBrinkGetMoveToTeachLeadPokemon = SPECIAL_CAPE_BRINK_GET_MOVE,
  HasLearnedAllMovesFromCapeBrinkTutor = SPECIAL_HAS_LEARNED_ALL_CAPE_BRINK,
}

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function varGet(ctx, id)
  local v = tonumber(flagsMod().getVar(nil, ctx, id)) or 0
  if v == 0 and ctx and type(ctx.getVar) == "function" then
    v = tonumber(ctx:getVar(id)) or 0
  end
  return v
end

local function varSet(ctx, id, value)
  flagsMod().setVar(nil, ctx, id, value)
  if ctx and type(ctx.setVar) == "function" then ctx:setVar(id, value) end
end

local function sessionOf()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function flagStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf()
  return (Space and Space.store) or (session and session.store) or nil
end

local function chosenMon(ctx)
  local session = sessionOf()
  local party = session and session.party
  local slot = varGet(ctx, VAR_0x8004)
  if not party or slot >= PARTY_SIZE then return nil, session end
  return party[slot + 1], session
end

local function tickVm()
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm then Space.vm:tick() end
end

-- pokefirered/src/scrcmd.c:1697 ScrCmd_bufferstring
local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

local function closeMessage()
  local okM, Message = pcall(require, "src.ui.game3.message")
  if okM and Message and Message.isOpen and Message.isOpen() and Message.close then
    Message.close()
  end
end

-- pokefirered/src/party_menu_specials.c:38, pokefirered/src/party_menu.c:6317
local function takeScreen()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if not (okF and Fade and Fade.begin and Fade.MODE) then return function() end end
  local covered = not (Fade.isActive and Fade.isActive()) and (tonumber(Fade.t) or 0) >= 16
  if not (covered and Fade.mode == Fade.MODE.TO_BLACK) then return function() end end
  Fade.clear()
  return function()
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() end)
  end
end

MoveTeach.HANDLERS = {
  -- pokefirered/src/party_menu_specials.c:24
  [SPECIAL_CHOOSE_MON_FOR_MOVE_RELEARNER] = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    local applied = false
    local function apply()
      if applied then return end
      applied = true
      -- pokefirered/src/party_menu.c:1201
      varSet(ctx, VAR_0x8005, MoveLearn.countRelearnableMoves((chosenMon(ctx))))
    end
    local yielded = Natives.choosePartyMon(ctx, adapters, PARTY_MENU_TYPE_MOVE_RELEARNER)
    if not yielded then
      apply()
      return false
    end
    local closedPoll = ctx.nativePoll
    ctx.nativePoll = function()
      if closedPoll and not closedPoll() then return false end
      apply()
      return true
    end
    return true
  end,
  -- pokefirered/src/learn_move.c:367
  [SPECIAL_TEACH_MOVE_RELEARNER_MOVE] = function(ctx, adapters)
    local mon, session = chosenMon(ctx)
    local okUi, MoveRelearner = pcall(require, "src.ui.game3.move_relearner")
    if not (mon and okUi and type(MoveRelearner) == "table" and MoveRelearner.show) then
      varSet(ctx, VAR_0x8004, 0)
      return false
    end
    local Natives = require("src.core.game3.scripting.natives")
    return Natives.yieldHost(ctx, adapters, function(done)
      local okM, Message = pcall(require, "src.ui.game3.message")
      if okM and Message and Message.isOpen and Message.isOpen() and Message.close then
        Message.close()
      end
      MoveRelearner.show(mon, {
        session = session,
        onDone = function(learned)
          -- pokefirered/src/learn_move.c:519
          varSet(ctx, VAR_0x8004, learned and 1 or 0)
          done()
          tickVm()
        end,
      })
    end)
  end,
  -- pokefirered/src/party_menu_specials.c:44
  [SPECIAL_SELECT_MOVE_DELETER_MOVE] = function(ctx, adapters)
    local mon, session = chosenMon(ctx)
    local okUi, SummaryMenu = pcall(require, "src.ui.game3.summary_menu")
    if not (mon and okUi and type(SummaryMenu) == "table" and SummaryMenu.openMenu) then
      varSet(ctx, VAR_0x8005, MAX_MON_MOVES)
      return false
    end
    local Natives = require("src.core.game3.scripting.natives")
    local slot = varGet(ctx, VAR_0x8004) + 1
    local restore = takeScreen()
    return Natives.yieldHost(ctx, adapters, function(done)
      closeMessage()
      -- pokefirered/src/pokemon_summary_screen.c:1050 ShowSelectMovePokemonSummaryScreen
      SummaryMenu.openMenu(session and session.party, slot, {
        session = session,
        mode = "select_move",
        onSelectMove = function(slotIdx)
          -- pokefirered/src/pokemon_summary_screen.c:3859
          varSet(ctx, VAR_0x8005, tonumber(slotIdx) or MAX_MON_MOVES)
          restore()
          done()
          tickVm()
        end,
      })
    end)
  end,
  -- pokefirered/src/party_menu_specials.c:92
  [SPECIAL_MOVE_DELETER_FORGET_MOVE] = function(ctx)
    local mon = chosenMon(ctx)
    if not mon then return false end
    MoveLearn.forgetMove(mon, varGet(ctx, VAR_0x8005))
    return false
  end,
  -- pokefirered/src/party_menu_specials.c:61
  [SPECIAL_BUFFER_MOVE_DELETER_NICKNAME_AND_MOVE] = function(ctx, adapters)
    local mon = chosenMon(ctx)
    if not mon then return false end
    local Pokemon = require("src.core.game3.pokemon")
    setStringVar(ctx, adapters, 1, Pokemon.displayMonName(mon))
    local moveId = Pokemon.moveIdAt(mon, varGet(ctx, VAR_0x8005) + 1)
    setStringVar(ctx, adapters, 2, Pokemon.moveName(moveId) or "")
    return false
  end,
  -- pokefirered/src/party_menu_specials.c:50
  [SPECIAL_GET_NUM_MOVES_SELECTED_MON_HAS] = function(ctx)
    local mon = chosenMon(ctx)
    local Pokemon = require("src.core.game3.pokemon")
    varSet(ctx, VAR_RESULT, mon and Pokemon.moveSlotCount(mon) or 0)
    return false
  end,
  -- pokefirered/src/party_menu.c:5793 ChooseMonForMoveTutor
  [SPECIAL_CHOOSE_MON_FOR_MOVE_TUTOR] = function(ctx, adapters)
    -- pokefirered/src/party_menu.c:855
    varSet(ctx, VAR_RESULT, 0)
    local tutor = varGet(ctx, VAR_0x8005)
    local session = sessionOf()
    local party = session and session.party
    local okUi, PartyMenu = pcall(require, "src.ui.game3.party_menu")
    if not (party and party[1] and okUi and type(PartyMenu) == "table" and PartyMenu.show) then
      return false
    end
    local auto = nil
    if tutor >= MoveLearn.TUTOR_MOVE_COUNT then
      -- pokefirered/src/party_menu.c:5814
      auto = varGet(ctx, VAR_0x8007) + 1
    end
    local Natives = require("src.core.game3.scripting.natives")
    local restore = takeScreen()
    return Natives.yieldHost(ctx, adapters, function(done)
      closeMessage()
      PartyMenu.show(party, nil, {
        mode = "move_tutor",
        tutor = tutor,
        autoSlot = auto,
        session = session,
        onClose = function()
          -- pokefirered/src/party_menu.c:4841
          varSet(ctx, VAR_RESULT, PartyMenu._tutorResult and 1 or 0)
          restore()
          done()
          tickVm()
        end,
      })
    end)
  end,
  -- pokefirered/src/field_specials.c:2219 CapeBrinkGetMoveToTeachLeadPokemon
  [SPECIAL_CAPE_BRINK_GET_MOVE] = function(ctx, adapters)
    local session = sessionOf()
    local party = (session and session.party) or {}
    local lead = MoveLearn.leadMonIndex(party)
    varSet(ctx, VAR_0x8007, lead)
    local mon = party[lead + 1]
    local row = MoveLearn.capeBrinkRow(mon)
    if not row then
      varSet(ctx, VAR_RESULT, 0)
      return false
    end
    local Pokemon = require("src.core.game3.pokemon")
    setStringVar(ctx, adapters, 2, Pokemon.moveName(row.move) or "")
    varSet(ctx, VAR_0x8005, row.tutor)
    if flagsMod().getFlag(flagStore(), ctx, row.flag) then
      varSet(ctx, VAR_RESULT, 0)
      return false
    end
    varSet(ctx, VAR_0x8006, Pokemon.moveSlotCount(mon))
    varSet(ctx, VAR_RESULT, 1)
    return false
  end,
  -- pokefirered/src/field_specials.c:2274 HasLearnedAllMovesFromCapeBrinkTutor
  [SPECIAL_HAS_LEARNED_ALL_CAPE_BRINK] = function(ctx)
    local tutor = varGet(ctx, VAR_0x8005)
    local Flags = flagsMod()
    local store = flagStore()
    local burn = MoveLearn.CAPE_BRINK[2]
    for i = 0, 1 do
      if MoveLearn.CAPE_BRINK[i].tutor == tutor then burn = MoveLearn.CAPE_BRINK[i] end
    end
    Flags.setFlag(store, ctx, burn.flag, true)
    local count = 0
    for i = 0, 2 do
      if Flags.getFlag(store, ctx, MoveLearn.CAPE_BRINK[i].flag) then count = count + 1 end
    end
    varSet(ctx, VAR_RESULT, count == 3 and 1 or 0)
    return false
  end,
}

return MoveTeach
