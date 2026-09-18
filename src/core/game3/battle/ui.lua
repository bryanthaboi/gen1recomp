-- FRLG battle UI (pret battle_bg windows + battle_interface). Chrome from ROM extract.

local Message = nil
pcall(function()
  Message = require("src.ui.game3.message")
end)
local Choice = nil
pcall(function()
  Choice = require("src.ui.game3.choice")
end)

local Commands = require("src.core.game3.battle.commands")
local State = require("src.core.game3.battle.state")
local Moves = require("src.core.game3.battle.moves")
local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local BattleChrome = require("src.ui.game3.battle_chrome")
local BattleBg = require("src.core.game3.battle.bg")
local Healthbox = require("src.core.game3.battle.healthbox")
local Pokemon = require("src.core.game3.pokemon")
local Window = require("src.ui.game3.window")
local Types = require("src.core.game3.battle.types")
local BallOpen = require("src.core.game3.battle.ball_open")

local Ui = {}

Ui._queue = {}
Ui._showing = false
Ui._headless = false
Ui._log = {}
Ui._mode = "none" -- "none"|"menu"|"moves"|"bag"
Ui._menuIndex = 1
Ui._moveIndex = 1
Ui._moveIndexBattler = nil
Ui._st = nil
Ui._pendingCommand = nil
Ui._pendingYesNo = nil
Ui._session = nil
Ui._active = 0
Ui._actionCursor = {}
Ui._moveCursor = {}
Ui._moveCursorMon = {}
Ui._target = nil
Ui._bounce = { hb = {}, mon = {} }
Ui._preview = nil
Ui._partnerAction = nil

-- pokefirered/src/battle_script_commands.c:5149
local BATTLE_YESNO = { left = 24, top = 9, style = "battle" }

-- pret sBattlerCoords (singles) — CreateSprite CENTER before pic y_offset
local ENEMY_MON = { x = 176, y = 40 }
local PLAYER_MON = { x = 72, y = 80 }

local PicCoords = nil
pcall(function()
  PicCoords = require("src.core.game3.battle.pic_coords")
end)

--- pret GetBattlerSpriteFinal_Y (a3=TRUE / BATTLER_COORD_Y_PIC_OFFSET).
local SPECIES_CASTFORM = 385
-- pokefirered/src/battle_anim_mons.c:48
local CASTFORM_FRONT_Y = { [0] = 17, 9, 9, 8 }
-- pokefirered/src/battle_anim_mons.c:56
local CASTFORM_ELEV = { [0] = 13, 14, 13, 13 }
-- pokefirered/src/battle_anim_mons.c:65
local CASTFORM_BACK_Y = { [0] = 0, 0, 0, 0 }

local function live_battler(side)
  local Battle = package.loaded["src.core.game3.battle"]
  local st = Battle and Battle._st
  local Anim = package.loaded["src.core.game3.battle.anim"]
  local b
  if type(side) == "number" then
    b = st and ((side == 0 and st.player) or (side == 1 and st.enemy) or (st.battlers and st.battlers[side]))
  else
    b = st and st[side]
  end
  if Anim and Anim.shownBattler then b = Anim.shownBattler(side, b) end
  return b, st
end

-- pokefirered/src/battle_gfx_sfx_util.c:1000
local function castform_form(side, battler)
  local Anim = package.loaded["src.core.game3.battle.anim"]
  local pres = Anim and Anim._present and Anim._present[side]
  if not (pres and battler and pres.castformForm ~= nil) then return 0 end
  if pres.castformMon ~= nil and pres.castformMon ~= battler.mon then return 0 end
  local f = (tonumber(pres.castformForm) or 0) % 128
  if f < 0 or f > 3 then return 0 end
  return f
end
Ui.castformForm = castform_form

-- pokefirered/src/pokemon.c:6247
local function shows_ghost(side, st)
  if side ~= "enemy" or not (st and st.ghostBattle) then return false end
  local Anim = package.loaded["src.core.game3.battle.anim"]
  local pres = Anim and Anim._present and Anim._present.enemy
  return not (pres and pres.ghostUnveiled)
end
Ui.showsGhost = shows_ghost

local function is_double(st)
  st = st or Ui._st
  return type(st) == "table" and st.double == true
end

local function battler_sprite_center(side, species, base, form, ghost)
  if type(side) == "number" then
    local id = side
    side = (id % 2 == 0) and "player" or "enemy"
    local _, st = live_battler(id)
    base = base or (PicCoords and PicCoords.battlerCoords and PicCoords.battlerCoords(is_double(st), id))
    if is_double(st) and side == "player" and PicCoords and species then
      local sp = tonumber(species) or 0
      local yo = (PicCoords.back and PicCoords.back[sp]) or 0
      if sp == SPECIES_CASTFORM then yo = CASTFORM_BACK_Y[form or 0] or 0 end
      -- pokefirered/src/battle_anim_mons.c:252
      local y = math.min(base.y + yo + 8, 160 - 64 + 8)
      return base.x, y - 4
    end
  end
  local cx, cy = base.x, (side == "player") and (base.y - 4) or base.y
  if not PicCoords or not species then return cx, cy end
  local sp = tonumber(species) or 0
  if ghost == nil or (form == nil and sp == SPECIES_CASTFORM) then
    local b, st = live_battler(side)
    if ghost == nil then ghost = shows_ghost(side, st) end
    if form == nil and sp == SPECIES_CASTFORM then form = castform_form(side, b) end
  end
  if side == "player" then
    local yo = (PicCoords.back and PicCoords.back[sp]) or 0
    if sp == SPECIES_CASTFORM then yo = CASTFORM_BACK_Y[form or 0] or 0 end
    cy = base.y + yo + 4 -- shifted up 4px
  elseif ghost then
    -- pokefirered/src/battle_anim_mons.c:297
    cy = base.y
  else
    local yo = (PicCoords.front and PicCoords.front[sp]) or 0
    local elev = (PicCoords.elev and PicCoords.elev[sp]) or 0
    if sp == SPECIES_CASTFORM then
      yo = CASTFORM_FRONT_Y[form or 0] or yo
      elev = CASTFORM_ELEV[form or 0] or elev
    end
    cy = base.y + yo - elev
  end
  return cx, cy
end
Ui.battlerSpriteCenter = battler_sprite_center

function Ui.battlerPic(side, battler, species)
  local b, st = live_battler(side)
  if type(side) == "number" then side = (side % 2 == 0) and "player" or "enemy" end
  battler = battler or b
  if shows_ghost(side, st) and Pokemon.ghostPic then
    local g = Pokemon.ghostPic()
    if g then return g, 0, true end
  end
  local sp = tonumber(species) or (battler and tonumber(battler.species))
  if not sp then return nil, 0, false end
  local form = (sp == SPECIES_CASTFORM) and castform_form(side, battler) or 0
  local entry
  if side == "player" and Pokemon.backPic then entry = Pokemon.backPic(sp, form) end
  if not entry and Pokemon.frontPic then entry = Pokemon.frontPic(sp, form) end
  return entry, form, false
end

function Ui.reset(opts)
  opts = opts or {}
  Ui._timed = nil
  Ui._linger = false
  Ui._queue = {}
  Ui._showing = false
  Ui._headless = opts.headless and true or false
  Ui._log = {}
  Ui._mode = "none"
  Ui._menuIndex = 1
  Ui._moveIndex = 1
  Ui._moveIndexBattler = nil
  Ui._st = nil
  Ui._pendingCommand = nil
  Ui._pendingYesNo = nil
  Ui._active = 0
  Ui._actionCursor = {}
  Ui._moveCursor = {}
  Ui._moveCursorMon = {}
  Ui._target = nil
  Ui._bounce = { hb = {}, mon = {} }
  Ui._preview = nil
  Ui._partnerAction = nil
  if not Ui._headless then
    pcall(BattleChrome.install, nil)
  end
end

function Ui.bindState(st, session)
  Ui._st = st
  if session ~= nil then Ui._session = session end
end

function Ui.bindSession(session)
  Ui._session = session
end

function Ui.push(text, cb)
  if not text or text == "" then
    if cb then cb() end
    return
  end
  Ui._log[#Ui._log + 1] = text
  Ui._queue[#Ui._queue + 1] = cb and { text = text, cb = cb } or text
end

-- pokefirered/src/battle_script_commands.c:2041
function Ui.pushTimed(text, waitFrames, cb)
  if not text or text == "" then
    if cb then cb() end
    return
  end
  Ui._log[#Ui._log + 1] = text
  Ui._queue[#Ui._queue + 1] = { text = text, cb = cb, timed = true, wait = waitFrames or 64 }
end

local function message_blocking()
  if not (Message and Message.isOpen and Message.isOpen()) then return false end
  return not Ui._linger
end

function Ui.busy()
  if Ui._headless then return false end
  if Choice and Choice.active then return true end
  if Ui._timed then return true end
  if message_blocking() then return true end
  if Ui._showing then return true end
  if #Ui._queue > 0 then return true end
  return false
end

--- True while battle text is queued or on screen (intro / turn messages).
function Ui.dialogPending()
  if Ui._headless then return false end
  if Ui._timed then return true end
  if message_blocking() then return true end
  if Ui._showing then return true end
  return #Ui._queue > 0
end

--- YES/NO during award/learn (Choice.yesNo). cb(true|false)
function Ui.askYesNo(a, b)
  local cb = (type(a) == "function") and a or b
  local prompt = (type(a) == "string") and a or nil
  if Ui._headless then
    if cb then cb(false) end
    return
  end
  if not Choice then
    if cb then cb(false) end
    return
  end
  if prompt and prompt ~= "" and Message and Message.show then
    Ui._log[#Ui._log + 1] = prompt
    Message.show(prompt, { frame = "battle", battle = true, stay = true })
    -- pokefirered/data/battle_scripts_1.s:3127
    Ui._pendingYesNo = cb or false
    return
  end
  Choice.yesNo(cb, BATTLE_YESNO)
end

local function open_pending_yesno()
  if Ui._pendingYesNo == nil then return false end
  if not (Message and Message.isOpen and Message.isOpen()) then
    Ui._pendingYesNo = nil
    return false
  end
  if not (Message.isWaiting and Message.isWaiting()) then return true end
  local cb = Ui._pendingYesNo
  Ui._pendingYesNo = nil
  -- pokefirered/data/battle_scripts_1.s:3129
  Choice.yesNo(function(yes)
    if Message.isOpen() and Message.close then Message.close() end
    if cb then cb(yes) end
  end, BATTLE_YESNO)
  return true
end

function Ui.yesNoPending()
  return Ui._pendingYesNo ~= nil
end

--- Multi-choice forget list. cb(0-based index) or cb(-1)/cb(127) on cancel.
function Ui.askForget(labels, cb, ctx)
  if Ui._headless then
    if cb then cb(-1) end
    return
  end
  if ctx and ctx.mon then
    local ok, SummaryMenu = pcall(require, "src.ui.game3.summary_menu")
    if ok and SummaryMenu and SummaryMenu.openMenu then
      -- pokefirered/src/battle_script_commands.c:5194
      SummaryMenu.openMenu({ ctx.mon }, 1, {
        mode = "select_move",
        moveToLearn = ctx.moveId,
        onSelectMove = function(slotIdx)
          if cb then cb(slotIdx) end
        end,
      })
      return
    end
  end
  if not Choice then
    if cb then cb(-1) end
    return
  end
  Choice.multi(labels, 0, cb, { left = 14, top = 2 })
end

function Ui.choiceActive()
  return Choice and Choice.active
end

function Ui.waitingForCommand()
  return Ui._mode == "menu" or Ui._mode == "moves" or Ui._mode == "bag" or Ui._mode == "target"
end

local function open_battle_bag()
  local BagMenu = require("src.ui.game3.bag_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Ui._session
    or (Runtime and Runtime.getSession and Runtime.getSession())
  local bag = session and session.bag
  if not bag then
    Ui.push("The BAG is empty.")
    Ui._mode = "menu"
    return
  end
  Ui._mode = "bag"
  BagMenu.show(bag, {
    session = session,
    battle = true,
    onBattleUse = function(itemId, partySlot)
      if itemId == nil then
        Ui._mode = "menu"
        return
      end
      Ui._pendingCommand = {
        kind = "bag",
        user = "player",
        itemId = itemId,
        partySlot = partySlot,
      }
      if is_double() then Ui._pendingCommand.battler = Ui._active or 0 end
      Ui._mode = "none"
    end,
    onClose = function()
      -- close already notifies onBattleUse(nil) when cancelled
    end,
  })
end

function Ui.isShowing()
  return Ui._showing or Ui.busy() or (Message and Message.isOpen and Message.isOpen())
end

local function active_battler(st)
  st = st or Ui._st
  if not st then return nil end
  local id = Ui._active or 0
  if id == 0 then return st.player end
  return st.battlers and st.battlers[id]
end
Ui.activeBattlerObject = active_battler

function Ui.activeBattler()
  return Ui._active or 0
end

function Ui.battlePartyOrder(st)
  return require("src.ui.game3.party_menu").battleOrder(st)
end

function Ui.openPartyMenu(st, battlerId, opts)
  opts = opts or {}
  st = st or Ui._st
  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Ui._session
    or (Runtime and Runtime.getSession and Runtime.getSession())
  local party = (st and st.playerParty) or (session and session.party) or {}
  local overlay = session and session.move_overlay
  local id = tonumber(battlerId) or 0
  local forced = opts.forced and true or false
  if st and st.playerParty then
    for _, bid in ipairs({ 0, 2 }) do
      local b = (bid == 0 and st.player) or (st.double and st.battlers and st.battlers[bid])
      if b then State.syncBattlerToParty(b, st.playerParty) end
    end
  end
  PartyMenu.show(party, overlay, {
    mode = forced and "battle_faint" or "battle_switch",
    layout = (st and st.double) and "double" or nil,
    battleOrder = st and st.playerParty and Ui.battlePartyOrder(st) or nil,
    session = session,
    activeSlot = (st and st.player and st.player.partyIndex) or 1,
    battle = true,
    validate = function(pi)
      if opts.validate then return opts.validate(pi) end
      if st and st.double then return Commands.switchError(st, pi, forced, id) end
      return Commands.switchError(st, pi, forced)
    end,
    onSelect = function(pi)
      if opts.onSelect then opts.onSelect(pi) end
    end,
    onClose = opts.onClose,
  })
end

local function open_battle_party_double()
  local id = Ui._active or 0
  Ui._mode = "party"
  Ui.openPartyMenu(Ui._st, id, {
    onSelect = function(slot)
      if slot == nil then
        Ui._mode = "menu"
        return
      end
      Ui._pendingCommand = {
        kind = "switch",
        user = "player",
        battler = id,
        slot = slot,
      }
      Ui._mode = "none"
    end,
    onClose = function()
      Ui._mode = "menu"
    end,
  })
end

local function open_battle_party()
  if is_double() then return open_battle_party_double() end
  local PartyMenu = require("src.ui.game3.party_menu")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Ui._session
    or (Runtime and Runtime.getSession and Runtime.getSession())
  local State = require("src.core.game3.battle.state")
  if Ui._st and Ui._st.player and Ui._st.playerParty then
    State.syncBattlerToParty(Ui._st.player, Ui._st.playerParty)
  end
  local party = (Ui._st and Ui._st.playerParty) or (session and session.party)
  local overlay = (session and session.move_overlay)
  local activeSlot = (Ui._st and Ui._st.player and Ui._st.player.partyIndex) or 1
  Ui._mode = "party"
  PartyMenu.show(party, overlay, {
    mode = "battle_switch",
    session = session,
    activeSlot = activeSlot,
    battle = true,
    validate = function(slot) return Commands.switchError(Ui._st, slot) end,
    onSelect = function(slot)
      if slot == nil or slot == activeSlot then
        Ui._mode = "menu"
        return
      end
      Ui._pendingCommand = {
        kind = "switch",
        user = "player",
        slot = slot,
      }
      Ui._mode = "none"
    end,
    onClose = function()
      Ui._mode = "menu"
    end,
  })
end

function Ui.openMenu(battlerId, opts)
  Ui._linger = false
  Ui._timed = nil
  Ui._mode = "menu"
  Ui._target = nil
  Ui._active = tonumber(battlerId) or 0
  Ui._partnerAction = opts and opts.partnerAction or nil
  if is_double() then
    -- pokefirered/src/battle_controller_player.c:2421
    Ui._menuIndex = Ui._actionCursor[Ui._active] or 1
  else
    Ui._menuIndex = 1
  end
  Ui._pendingCommand = nil
  if Message and Message.open then
    Message.open = false
  end
  Ui._showing = false
end

function Ui.clearLinger()
  if Ui._linger and Message and Message.close then Message.close() end
  Ui._linger = false
end

function Ui.selectionPump()
  if Ui._mode ~= "selmsg" then return false end
  if not Ui.pump() then return true end
  if Ui._selCmd then
    Ui._pendingCommand = Ui._selCmd
    Ui._selCmd = nil
    Ui._mode = "none"
  else
    Ui._mode = Ui._selReturn or "moves"
  end
  Ui._selReturn = nil
  return true
end

function Ui.takeCommand()
  local c = Ui._pendingCommand
  Ui._pendingCommand = nil
  if c then
    -- pokefirered/src/battle_controller_player.c:2809
    Ui._bounce = { hb = {}, mon = {} }
    Ui._target = nil
    Ui._preview = nil
  end
  return c
end

local function pop_queue()
  local item = table.remove(Ui._queue, 1)
  if type(item) == "table" then return item.text, item.cb, item end
  return item, nil, nil
end

local function show_next()
  if Ui._showing then return end
  if #Ui._queue == 0 then return end
  local text, cb, item = pop_queue()
  if Ui._headless then
    if cb then cb() end
    return
  end
  Ui._linger = false
  if item and item.timed and Message and Message.show then
    Ui._showing = true
    Ui._timed = { frames = 0, wait = item.wait or 64, cb = cb }
    Message.show(text, { frame = "battle", battle = true, stay = true })
    return
  end
  if Message and Message.show then
    Ui._showing = true
    Message.show(text, {
      frame = "battle",
      battle = true,
      done = function()
        Ui._showing = false
        if cb then cb() end
      end,
    })
  elseif cb then
    cb()
  end
end

local function tick_timed()
  local t = Ui._timed
  if not t then return false end
  local onLast = Message and Message.isWaiting and Message.isWaiting()
    and (Message._page or 1) >= #(Message._pages or {})
  if not onLast then return true end
  t.frames = t.frames + 1
  if t.frames < t.wait then return true end
  Ui._timed = nil
  Ui._showing = false
  Ui._linger = true
  if t.cb then t.cb() end
  return false
end

function Ui.pump()
  if Ui._headless then
    while #Ui._queue > 0 do
      local _, cb = pop_queue()
      if cb then cb() end
    end
    Ui._showing = false
    Ui._timed = nil
    return true
  end
  if tick_timed() then return false end
  if open_pending_yesno() then return false end
  if message_blocking() then
    return false
  end
  Ui._showing = false
  if #Ui._queue > 0 then
    show_next()
    return false
  end
  return true
end

local function play_select()
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    Audio.playSe(SE.SE_SELECT)
  end)
end

local function grid_nav(index, input, maxN)
  local c = (index or 1) - 1
  if input:wasPressed("left") or input:wasPressed("right") then
    c = (c % 2 == 0) and (c + 1) or (c - 1)
  elseif input:wasPressed("up") or input:wasPressed("down") then
    c = (c < 2) and (c + 2) or (c - 2)
  else
    return index, false
  end
  if c < 0 or c >= (maxN or 4) then return index, false end
  return c + 1, true
end

-- pokefirered/src/battle_controller_player.c:1381
local function move_count(mon)
  local n = 0
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    if mv and mv ~= 0 and mv ~= "" then n = n + 1 end
  end
  if n < 1 then n = 1 end
  return n
end

-- pokefirered/src/battle_main.c:2380
local function open_move_menu()
  if is_double() then
    local id = Ui._active or 0
    local battler = active_battler()
    local mon = battler and battler.mon
    if mon ~= Ui._moveCursorMon[id] then
      Ui._moveCursorMon[id] = mon
      Ui._moveCursor[id] = 1
    end
    local n = move_count(mon)
    local idx = tonumber(Ui._moveCursor[id]) or 1
    if idx < 1 then idx = 1 end
    if idx > n then idx = n end
    Ui._moveCursor[id] = idx
    Ui._moveIndex = idx
    Ui._mode = "moves"
    return
  end
  local battler = Ui._st and Ui._st.player
  if battler ~= Ui._moveIndexBattler then
    Ui._moveIndexBattler = battler
    Ui._moveIndex = 1
  end
  local n = move_count(battler and battler.mon)
  local idx = tonumber(Ui._moveIndex) or 1
  if idx < 1 then idx = 1 end
  if idx > n then idx = n end
  Ui._moveIndex = idx
  Ui._mode = "moves"
end

local MT = { SELECTED = 0, DEPENDS = 1, USER_OR_SELECTED = 2, RANDOM = 4, BOTH = 8, USER = 16, FOES_AND_ALLY = 32, OPPONENTS_FIELD = 64 }
local MOVE_CURSE = 174
local TYPE_GHOST = 7
local ITEM_PREMIER_BALL = 12
-- pokefirered/src/battle_controller_player.c:171
local TARGET_IDENTITIES = { 0, 2, 3, 1 }

local function band(a, b)
  local bit = require("bit")
  return bit.band(tonumber(a) or 0, tonumber(b) or 0)
end

local function move_num(mv)
  local n = tonumber(mv)
  if n then return n end
  if mv == nil or mv == "" then return 0 end
  if Moves.numForName then
    local norm = Moves.normalizeId and Moves.normalizeId(mv) or mv
    return Moves.numForName(norm) or 0
  end
  return 0
end

local function is_type(b, t)
  return b and (tonumber(b.type1) == t or tonumber(b.type2) == t)
end

-- pokefirered/src/battle_controller_player.c:444
local function move_target_type(battler, mv)
  if move_num(mv) == MOVE_CURSE then
    return is_type(battler, TYPE_GHOST) and MT.SELECTED or MT.USER
  end
  local def = mv and Moves.get(mv)
  return tonumber(def and def.target) or 0
end
Ui.moveTargetType = move_target_type

local function absent(st, id)
  if not st then return true end
  if st.absent and st.absent[id] then return true end
  local b = (id == 0 and st.player) or (id == 1 and st.enemy) or (st.battlers and st.battlers[id])
  return b == nil
end

-- pokefirered/src/pokemon.c:2651
local function count_except_active(st, id)
  local n = 0
  for i = 0, 3 do
    if i ~= id and not absent(st, i) then n = n + 1 end
  end
  return n
end

-- pokefirered/src/battle_controller_player.c:437
function Ui.targetSelection(st, id, slot)
  st = st or Ui._st
  id = tonumber(id) or 0
  local b = (id == 0 and st.player) or (st.battlers and st.battlers[id])
  local mon = b and b.mon
  local mv = mon and mon.moves and mon.moves[slot]
  local tt = move_target_type(b, mv)
  local opposingLeft = (id % 2 == 0) and 1 or 0
  local cursor = (band(tt, MT.USER) ~= 0) and id or opposingLeft
  if not (st and st.double) then return false, cursor, cursor end
  local can = band(tt, MT.RANDOM + MT.BOTH + MT.DEPENDS + MT.FOES_AND_ALLY + MT.OPPONENTS_FIELD + MT.USER) == 0
  local pp = mon and mon.pp and tonumber(mon.pp[slot])
  if pp ~= nil and pp == 0 then
    can = false
  elseif band(tt, MT.USER + MT.USER_OR_SELECTED) == 0 and count_except_active(st, id) <= 1 then
    -- pokefirered/src/pokemon.c:2686
    cursor = absent(st, opposingLeft) and (opposingLeft + 2) or opposingLeft
    can = false
  end
  if not can then return false, cursor, cursor end
  local start
  if band(tt, MT.USER + MT.USER_OR_SELECTED) ~= 0 then
    start = id
  elseif absent(st, opposingLeft) then
    start = opposingLeft + 2
  else
    start = opposingLeft
  end
  return true, cursor, start
end

-- pokefirered/src/battle_main.c:2091
local function start_bounce(kind, id, delta, amp)
  local t = Ui._bounce[kind]
  if t[id] then return end
  t[id] = { idx = (kind == "hb") and 128 or 192, delta = delta, amp = amp, y = 0, fresh = true }
end

-- pokefirered/src/battle_main.c:2132
local function end_bounce(kind, id)
  Ui._bounce[kind][id] = nil
end

local function end_all_bounces()
  Ui._bounce = { hb = {}, mon = {} }
end

-- pokefirered/src/trig.c:4
local function sin_q8(idx, amp)
  local v = math.floor(math.sin((idx % 256) * math.pi / 128) * 256 + 0.5)
  return math.floor(v * amp / 256)
end

-- pokefirered/src/battle_main.c:2159
local function tick_bounces()
  for _, kind in ipairs({ "hb", "mon" }) do
    for _, bo in pairs(Ui._bounce[kind]) do
      if bo.fresh then
        bo.fresh = false
        bo.y = 0
      else
        bo.y = sin_q8(bo.idx, bo.amp) + bo.amp
        bo.idx = (bo.idx + bo.delta) % 256
      end
    end
  end
end

function Ui.bounceOffset(kind, id)
  local bo = Ui._bounce[kind] and Ui._bounce[kind][id]
  return bo and bo.y or 0
end

local PREVIEW_ALL = { [114] = true, [201] = true, [195] = true, [240] = true, [241] = true, [258] = true, [300] = true, [346] = true }
local PREVIEW_ALLIES = { [219] = true, [115] = true, [113] = true, [54] = true, [215] = true, [312] = true }
local MOVE_HELPING_HAND = 270

-- pokefirered/src/battle_controller_player.c:2889
local function preview_targets(st, id, slot)
  local b = active_battler(st)
  local mv = b and b.mon and b.mon.moves and b.mon.moves[slot]
  local tt = move_target_type(b, mv)
  local num = move_num(mv)
  local partner = (id + 2) % 4
  if tt == MT.SELECTED or tt == MT.DEPENDS or tt == MT.USER_OR_SELECTED or tt == MT.RANDOM then
    return { [0] = true, [1] = true, [2] = true, [3] = true }, 0
  elseif tt == MT.BOTH or tt == MT.OPPONENTS_FIELD then
    return { [1] = true, [3] = true }, 8
  elseif tt == MT.USER then
    if PREVIEW_ALL[num] then return { [0] = true, [1] = true, [2] = true, [3] = true }, 8 end
    if PREVIEW_ALLIES[num] then return { [0] = true, [2] = true }, 8 end
    if num == MOVE_HELPING_HAND then return { [partner] = true }, 8 end
    return { [id] = true }, 8
  elseif tt == MT.FOES_AND_ALLY then
    return { [1] = true, [partner] = true, [3] = true }, 8
  end
  return {}, 0
end

local ALL_BATTLERS = { [0] = true, [1] = true, [2] = true, [3] = true }

local function fade_state()
  local f = Ui._preview
  if not f then
    f = { active = false, objY = {}, objToggle = false, mask = {}, y = 0, target = 0,
      delay = 0, delayCounter = 0, finishing = false, finCounter = 0 }
    Ui._preview = f
  end
  return f
end

-- pokefirered/src/palette.c:393
local function fade_update(f)
  if not f.active then return end
  if f.finishing then
    -- pokefirered/src/palette.c:757
    if f.finCounter == 4 then
      f.active, f.finishing, f.finCounter = false, false, 0
    else
      f.finCounter = f.finCounter + 1
    end
    return
  end
  if not f.objToggle then
    if f.delayCounter < f.delay then
      f.delayCounter = f.delayCounter + 1
      return
    end
    f.delayCounter = 0
  else
    for id in pairs(f.mask) do f.objY[id] = f.y end
  end
  f.objToggle = not f.objToggle
  if not f.objToggle then
    if f.y == f.target then
      f.mask = {}
      f.finishing = true
    elseif f.y > f.target then
      f.y = math.max(f.target, f.y - 2)
    else
      f.y = math.min(f.target, f.y + 2)
    end
  end
end

-- pokefirered/src/palette.c:151
local function fade_begin(mask, delay, startY, targetY)
  local f = fade_state()
  if f.active then return false end
  f.mask, f.delay, f.delayCounter = mask, delay, delay
  f.y, f.target = startY, targetY
  f.active = true
  fade_update(f)
  return true
end

-- pokefirered/src/palette.c:349
local function fade_reset_clear()
  local f = fade_state()
  f.active, f.finishing, f.finCounter, f.delayCounter, f.y, f.target = false, false, 0, 0, 0, 0
  fade_begin(ALL_BATTLERS, 0, 0, 0)
end

local function tick_preview()
  if not is_double() then return end
  local f = fade_state()
  if Ui._mode == "moves" then
    -- pokefirered/src/battle_controller_player.c:442
    local mask, y = preview_targets(Ui._st, Ui._active or 0, Ui._moveIndex)
    fade_begin(mask, 8, y, 0)
  end
  fade_update(f)
end

function Ui.previewCoeff(id)
  local f = Ui._preview
  return (f and f.objY[id]) or 0
end

-- pokefirered/src/battle_main.c:2019
local function blink_start(t)
  t.blinkCounter = 8
  t.hidden = false
end

local function tick_target()
  local t = Ui._target
  if not t then return end
  t.blinkCounter = (t.blinkCounter or 8) - 1
  if t.blinkCounter <= 0 then
    t.hidden = not t.hidden
    t.blinkCounter = 8
  end
end

function Ui.targetHidden(id)
  local t = Ui._target
  return t ~= nil and t.cursor == id and t.hidden == true
end

function Ui.targetCursor()
  return Ui._target and Ui._target.cursor or nil
end

function Ui.tick()
  local m = Ui._mode
  if m == "menu" or m == "moves" or m == "target" or m == "selmsg" then
    local id = Ui._active or 0
    if m == "menu" then
      -- pokefirered/src/battle_controller_player.c:223
      start_bounce("hb", id, 7, 1)
      start_bounce("mon", id, 7, 1)
    elseif m == "target" and Ui._target then
      -- pokefirered/src/battle_controller_player.c:326
      local cur = Ui._target.cursor
      start_bounce("hb", cur, 15, 1)
      for i = 0, 3 do
        if i ~= cur then end_bounce("hb", i) end
      end
    end
    tick_bounces()
    tick_target()
  elseif m ~= "bag" and m ~= "party" then
    end_all_bounces()
  end
  tick_preview()
end

local function finish_move_choice(id, slot, target)
  local err = Commands.selectionError(Ui._st, slot, id)
  if err then
    -- pokefirered/src/battle_main.c:3277
    Ui._selCmd = nil
    Ui._selReturn = "moves"
    Ui._mode = "selmsg"
    Ui.push(err)
    return
  end
  Ui._pendingCommand = Commands.playerAction(Ui._st, 1, slot, id, target)
  Ui._mode = "none"
  end_all_bounces()
end

local function enter_target_mode(id, slot, start, cb)
  Ui._target = { battler = id, slot = slot, cursor = start, cb = cb }
  blink_start(Ui._target)
  Ui._mode = "target"
end

-- pokefirered/src/battle_controller_player.c:493
function Ui.chooseTarget(st, battlerId, moveSlot, cb)
  if st then Ui._st = st end
  local id = tonumber(battlerId) or 0
  Ui._active = id
  local needs, target, start = Ui.targetSelection(Ui._st, id, moveSlot)
  if not needs then
    if cb then cb(target) end
    return false
  end
  Ui._moveIndex = moveSlot
  enter_target_mode(id, moveSlot, start, cb or false)
  return true
end

-- pokefirered/src/battle_controller_player.c:355
local function cycle_target(dir)
  local t = Ui._target
  local st = Ui._st
  local b = active_battler(st)
  local mv = b and b.mon and b.mon.moves and b.mon.moves[t.slot]
  local def = mv and Moves.get(mv)
  local userOrSel = band(def and def.target, MT.USER_OR_SELECTED) ~= 0
  local pos = 1
  for i = 1, 4 do
    if TARGET_IDENTITIES[i] == t.cursor then pos = i break end
  end
  for _ = 1, 8 do
    pos = pos + dir
    if pos < 1 then pos = 4 elseif pos > 4 then pos = 1 end
    local cand = TARGET_IDENTITIES[pos]
    local ok
    if cand % 2 == 0 then
      ok = (cand ~= t.battler) or userOrSel
    else
      ok = true
    end
    if absent(st, cand) then ok = false end
    if ok then
      t.cursor = cand
      break
    end
  end
  blink_start(t)
end

local function handle_target_input(input)
  local t = Ui._target
  if not t then
    Ui._mode = "moves"
    return true
  end
  if input:wasPressed("a") then
    play_select()
    local cur, cb, id, slot = t.cursor, t.cb, t.battler, t.slot
    Ui._target = nil
    end_bounce("hb", cur)
    if cb then
      Ui._mode = "none"
      cb(cur)
    else
      finish_move_choice(id, slot, cur)
    end
    return true
  elseif input:wasPressed("b") then
    play_select()
    local cur, cb, id = t.cursor, t.cb, t.battler
    Ui._target = nil
    -- pokefirered/src/battle_controller_player.c:346
    start_bounce("hb", id, 7, 1)
    start_bounce("mon", id, 7, 1)
    end_bounce("hb", cur)
    if cb then
      Ui._mode = "none"
      cb(nil)
    else
      Ui._mode = "moves"
    end
    return true
  elseif input:wasPressed("left") or input:wasPressed("up") then
    play_select()
    cycle_target(-1)
    return true
  elseif input:wasPressed("right") or input:wasPressed("down") then
    play_select()
    cycle_target(1)
    return true
  end
  return true
end

local function handle_double_input(input)
  local st = Ui._st
  local id = Ui._active or 0
  if Ui._mode == "target" then
    return handle_target_input(input)
  end
  if Ui._mode == "menu" then
    -- pokefirered/src/battle_controller_player.c:219
    local c = (Ui._menuIndex or 1) - 1
    local nc = c
    if input:wasPressed("a") then
      play_select()
      Ui._actionCursor[id] = Ui._menuIndex
      local kind = Commands.MENU[Ui._menuIndex]
      if kind == "FIGHT" then
        local act, msg = Commands.fightShortcut(st, id)
        if act and msg then
          Ui._selCmd = act
          Ui._mode = "selmsg"
          Ui.push(msg)
        elseif act then
          Ui._pendingCommand = act
          Ui._mode = "none"
          end_all_bounces()
        else
          open_move_menu()
        end
      elseif kind == "BAG" then
        open_battle_bag()
      elseif kind == "POKEMON" or kind == "POKéMON" then
        open_battle_party()
      else
        local Engine = package.loaded["src.core.game3.battle.engine"]
        local BattleMod = package.loaded["src.core.game3.battle"]
        local ad = BattleMod and BattleMod._adapter
        local canRun, why = true, nil
        if Engine and Engine.canRun and ad and st then
          canRun, why = Engine.canRun(st, ad, active_battler(st))
        end
        if not canRun and why then
          Ui._selCmd = nil
          Ui._selReturn = "menu"
          Ui._mode = "selmsg"
          Ui.push(why)
        else
          Ui._pendingCommand = Commands.playerAction(st, Ui._menuIndex, nil, id)
          Ui._mode = "none"
          end_all_bounces()
        end
      end
      return true
    elseif input:wasPressed("left") then
      if c % 2 == 1 then nc = c - 1 end
    elseif input:wasPressed("right") then
      if c % 2 == 0 then nc = c + 1 end
    elseif input:wasPressed("up") then
      if c >= 2 then nc = c - 2 end
    elseif input:wasPressed("down") then
      if c < 2 then nc = c + 2 end
    elseif input:wasPressed("b") then
      -- pokefirered/src/battle_controller_player.c:286
      if id == 2 and not (st.absent and st.absent[0]) then
        local pa = Ui._partnerAction
        local refund = nil
        if pa and pa.kind == "bag" then
          local item = tonumber(pa.itemId or pa.item)
          if item and item <= ITEM_PREMIER_BALL then
            refund = item
          else
            return true
          end
        end
        play_select()
        Ui._pendingCommand = { kind = "cancel_partner", battler = id, refundItem = refund }
        Ui._mode = "none"
        end_all_bounces()
      end
      return true
    elseif input:wasPressed("start") then
      -- pokefirered/src/battle_controller_player.c:306
      local Healthbox = require("src.core.game3.battle.healthbox")
      Healthbox.swapHpBarsWithHpText(st)
      return true
    end
    if nc ~= c then
      play_select()
      Ui._menuIndex = nc + 1
      Ui._actionCursor[id] = Ui._menuIndex
    end
    return true
  elseif Ui._mode == "bag" or Ui._mode == "party" then
    return true
  elseif Ui._mode == "moves" then
    local b = active_battler(st)
    local n = move_count(b and b.mon)
    local c = (Ui._moveIndex or 1) - 1
    local nc = c
    -- pokefirered/src/battle_controller_player.c:511
    if input:wasPressed("left") then
      if c % 2 == 1 then nc = c - 1 end
    elseif input:wasPressed("right") then
      if c % 2 == 0 and c + 1 < n then nc = c + 1 end
    elseif input:wasPressed("up") then
      if c >= 2 then nc = c - 2 end
    elseif input:wasPressed("down") then
      if c < 2 and c + 2 < n then nc = c + 2 end
    end
    local idx, moved = nc + 1, nc ~= c
    if moved then
      Ui._moveIndex = idx
      Ui._moveCursor[id] = idx
      play_select()
      -- pokefirered/src/battle_controller_player.c:521
      fade_begin(ALL_BATTLERS, 0, 0, 0)
      return true
    end
    if input:wasPressed("a") then
      play_select()
      local slot = Ui._moveIndex
      local needs, target, start = Ui.targetSelection(st, id, slot)
      fade_reset_clear()
      if needs then
        enter_target_mode(id, slot, start, false)
      else
        finish_move_choice(id, slot, target)
      end
      return true
    elseif input:wasPressed("b") then
      play_select()
      fade_reset_clear()
      Ui._mode = "menu"
      return true
    end
  end
  return false
end

function Ui.handleInput(input)
  if not input then return false end
  Ui.tick()

  -- Learn-move / evo YES-NO and forget list
  if Choice and Choice.active then
    if input:wasPressed("up") then
      Choice.move(-1)
      return true
    elseif input:wasPressed("down") then
      Choice.move(1)
      return true
    elseif input:wasPressed("a") then
      Choice.confirm()
      return true
    elseif input:wasPressed("b") then
      Choice.cancel()
      return true
    end
    return true
  end

  if not Ui.waitingForCommand() then return false end
  if is_double() then return handle_double_input(input) end
  if Ui._mode == "menu" then
    local idx, moved = grid_nav(Ui._menuIndex, input, 4)
    if moved then
      Ui._menuIndex = idx
      play_select()
      return true
    end
    if input:wasPressed("a") then
      play_select()
      local kind = Commands.MENU[Ui._menuIndex]
      if kind == "FIGHT" then
        local act, msg = Commands.fightShortcut(Ui._st)
        if act and msg then
          Ui._selCmd = act
          Ui._mode = "selmsg"
          Ui.push(msg)
        elseif act then
          Ui._pendingCommand = act
          Ui._mode = "none"
        else
          open_move_menu()
        end
      elseif kind == "BAG" then
        open_battle_bag()
      elseif kind == "POKEMON" or kind == "POKéMON" then
        open_battle_party()
      else
        -- pokefirered/src/battle_main.c:3246
        local Engine = package.loaded["src.core.game3.battle.engine"]
        local BattleMod = package.loaded["src.core.game3.battle"]
        local ad = BattleMod and BattleMod._adapter
        local canRun, why = true, nil
        if Engine and Engine.canRun and ad and Ui._st then
          canRun, why = Engine.canRun(Ui._st, ad, Ui._st.player)
        end
        if not canRun and why then
          Ui._selCmd = nil
          Ui._selReturn = "menu"
          Ui._mode = "selmsg"
          Ui.push(why)
        else
          Ui._pendingCommand = Commands.playerAction(Ui._st, Ui._menuIndex, nil)
          Ui._mode = "none"
        end
      end
      return true
    elseif input:wasPressed("b") then
      return true
    end
  elseif Ui._mode == "bag" or Ui._mode == "party" then
    -- Input owned by BagMenu / PartyMenu via Battle.update
    return true
  elseif Ui._mode == "moves" then
    -- pokefirered/src/battle_controller_player.c:526
    local idx, moved = grid_nav(Ui._moveIndex, input, move_count(Ui._st and Ui._st.player and Ui._st.player.mon))
    if moved then
      Ui._moveIndex = idx
      play_select()
      return true
    end
    if input:wasPressed("a") then
      play_select()
      -- pokefirered/src/battle_main.c:3277
      local err = Commands.selectionError(Ui._st, Ui._moveIndex)
      if err then
        Ui._selCmd = nil
        Ui._mode = "selmsg"
        Ui.push(err)
        return true
      end
      Ui._pendingCommand = Commands.playerAction(Ui._st, 1, Ui._moveIndex)
      Ui._mode = "none"
      return true
    elseif input:wasPressed("b") then
      play_select()
      Ui._mode = "menu"
      return true
    end
  end
  return false
end

local function draw_menu_text(text, x, y, opts)
  opts = opts or {}
  FrlgFont.draw(tostring(text or ""), x, y, {
    small = opts.small ~= nil and opts.small or false,
    colors = opts.colors or FrlgFont.COLOR.NORMAL,
  })
end

local function draw_prompt_text(text, x, y)
  FrlgFont.draw(tostring(text or ""), x, y, {
    colors = FrlgFont.COLOR.WHITE,
  })
end

local GRAY_SHADER_SRC = [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc) * color;
  vec3 c5 = floor(c.rgb * 31.0 + 0.5);
  float g = floor((c5.r + c5.g + c5.b) / 3.0);
  return vec4(vec3(g / 31.0), c.a);
}
]]
local grayShader = nil

-- pokefirered/src/battle_anim_mons.c:1287
local function set_gray_shader()
  if grayShader == nil then
    local ok, sh = pcall(love.graphics.newShader, GRAY_SHADER_SRC)
    grayShader = ok and sh or false
  end
  if not grayShader then return false end
  love.graphics.setShader(grayShader)
  return true
end

local STAT_MASK_SRC = [[
extern Image maskTex;
extern vec2 origin;
extern vec2 size;
extern vec2 scroll;
extern float flip;
extern float eva;
extern float darken;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 m = Texel(tex, tc);
  if (m.a < 0.01) discard;
  vec2 t = tc;
  if (flip > 0.5) t.x = 1.0 - t.x;
  vec2 pos = floor(origin + t * size);
  vec4 k = Texel(maskTex, (pos + scroll + vec2(0.5)) / 256.0);
  if (k.a < 0.01) discard;
  if (darken > 0.5) return vec4(0.0, 0.0, 0.0, eva);
  return vec4(k.rgb, eva);
}
]]
local statMaskShader = nil

-- pokefirered/src/battle_anim_utility_funcs.c:526
local function draw_stat_mask(pres, img, cx, cy, sx, sy)
  local sm = pres and pres.statMask
  if not (sm and (tonumber(sm.eva) or 0) > 0) then return end
  local Anim = require("src.core.game3.battle.anim")
  local vm = Anim.vm and Anim.vm()
  if not (vm and vm.active) then return end
  local mask = Anim.statMaskImage(sm.tilemap, sm.pal)
  if not mask then return end
  if statMaskShader == nil then
    local ok, sh = pcall(love.graphics.newShader, STAT_MASK_SRC)
    statMaskShader = ok and sh or false
  end
  if not statMaskShader then return end
  local iw, ih = img:getDimensions()
  local w, h = iw * math.abs(sx), ih * math.abs(sy)
  local ok = pcall(function()
    statMaskShader:send("maskTex", mask)
    statMaskShader:send("origin", { cx - 32 * math.abs(sx), cy - 32 * math.abs(sy) })
    statMaskShader:send("size", { w, h })
    statMaskShader:send("scroll", { tonumber(sm.x) or 0, tonumber(sm.y) or 0 })
    statMaskShader:send("flip", sx < 0 and 1 or 0)
    statMaskShader:send("eva", math.min(1, (tonumber(sm.eva) or 0) / 16))
    statMaskShader:send("darken", 0)
  end)
  if not ok then return end
  local eva = math.min(16, tonumber(sm.eva) or 0)
  local evb = sm.evb and math.min(16, tonumber(sm.evb) or 0) or (16 - eva)
  love.graphics.setShader(statMaskShader)
  love.graphics.setColor(1, 1, 1, 1)
  if eva + evb ~= 16 then
    -- pokefirered/src/battle_anim_utility_funcs.c:306
    pcall(function()
      statMaskShader:send("darken", 1)
      statMaskShader:send("eva", 1 - evb / 16)
    end)
    love.graphics.draw(img, cx, cy, 0, sx, sy, 32, 32)
    pcall(function()
      statMaskShader:send("darken", 0)
      statMaskShader:send("eva", eva / 16)
    end)
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.draw(img, cx, cy, 0, sx, sy, 32, 32)
    love.graphics.setBlendMode("alpha", "alphamultiply")
  else
    love.graphics.draw(img, cx, cy, 0, sx, sy, 32, 32)
  end
  love.graphics.setShader()
end

local MOSAIC_SRC = [[
extern vec2 texSize;
extern float block;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 px = floor(tc * texSize / block) * block;
  return Texel(tex, (px + vec2(0.5)) / texSize) * color;
}
]]
local mosaicShader = nil

-- pokefirered/src/battle_anim_effects_3.c:2223
local function set_mosaic_shader(img, level)
  if mosaicShader == nil then
    local ok, sh = pcall(love.graphics.newShader, MOSAIC_SRC)
    mosaicShader = ok and sh or false
  end
  if not mosaicShader then return false end
  local iw, ih = img:getDimensions()
  local ok = pcall(function()
    mosaicShader:send("texSize", { iw, ih })
    mosaicShader:send("block", (tonumber(level) or 0) + 1)
  end)
  if not ok then return false end
  love.graphics.setShader(mosaicShader)
  return true
end

local AFFINE_SRC = [[
extern float m;
extern vec3 off;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc) * color;
  return vec4(clamp(c.rgb * m + off, 0.0, 1.0), c.a);
}
]]
local affineShader = nil

-- pokefirered/src/palette.c:471
local function set_affine_shader(st)
  if type(st) ~= "table" then return false end
  if affineShader == nil then
    local ok, sh = pcall(love.graphics.newShader, AFFINE_SRC)
    affineShader = ok and sh or false
  end
  if not affineShader then return false end
  local ok = pcall(function()
    affineShader:send("m", tonumber(st.m) or 1)
    affineShader:send("off", { tonumber(st.r) or 0, tonumber(st.g) or 0, tonumber(st.b) or 0 })
  end)
  if not ok then return false end
  love.graphics.setShader(affineShader)
  return true
end

local rowQuads = {}
local function row_quad(iw, ih, r)
  local key = iw * 100000 + ih * 100 + r
  local q = rowQuads[key]
  if not q then
    q = love.graphics.newQuad(0, r, iw, 1, iw, ih)
    rowQuads[key] = q
  end
  return q
end

local function bg_blend_params(bb)
  if type(bb) ~= "table" then return nil end
  local coeff = tonumber(bb.coeff) or 0
  if coeff <= 0 then return nil end
  local c = bb.color
  if type(c) == "number" then
    return coeff, c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
  elseif type(c) == "table" then
    return coeff, (c[1] or 0) * 31, (c[2] or 0) * 31, (c[3] or 0) * 31
  end
  return coeff, 0, 0, 0
end

--- Draw mon pic at GetBattlerSpriteFinal_Y center (64×64 → TL = center−32).
-- Applies Anim present offsets / alpha / visibility / z (Dig/Fly hide).
local function draw_mon_sprite(battler, base, back, id)
  if not battler then return end
  local side = back and "player" or "enemy"
  local key = id or side
  local Anim = require("src.core.game3.battle.anim")
  local pres = Anim.present(key)
  if pres and (pres.visible == false or pres.blinkHidden or pres.battlerInvisible or pres.invisible) then return end
  if id and Ui.targetHidden(id) then return end
  battler = Anim.shownBattler(key, battler) or battler

  local sp = battler.species
  if not sp and battler.mon and Pokemon.speciesOf then
    sp = Pokemon.speciesOf(battler.mon)
  elseif not sp and battler.mon then
    sp = battler.mon.species or battler.mon.speciesId
  end
  local tf = nil
  if battler.expTransform then
    tf = pres and pres.transformSpecies
    if not tf and not (pres and pres.pendingTransform) then tf = battler.expTransform.species end
  end
  if tf then sp = tf end
  local ghost = shows_ghost(side, Ui._st)
  local form = (tonumber(sp) == SPECIES_CASTFORM) and castform_form(side, battler) or 0
  local cx, cy = battler_sprite_center(id or side, sp, base, form, ghost)
  if pres then
    cx = cx + (pres.ox or 0)
    cy = cy + (pres.oy or 0)
  end
  cy = cy + Ui.bounceOffset("mon", id or (back and 0 or 1))
  local scale = (pres and pres.scale) or 1
  local darken = (pres and pres.darken) or 0
  local entry
  local dollImg = pres and pres.substitute and Anim.substituteImage(key)
  if dollImg then
    -- pokefirered/src/battle_gfx_sfx_util.c:794
    entry = { image = dollImg }
    cx = base.x + (pres.ox or 0)
    cy = (pres.substituteY or Anim.substituteY(key)) + (pres.oy or 0)
  end
  if not entry and ghost and Pokemon.ghostPic then
    entry = Pokemon.ghostPic()
  end
  if not entry and back and Pokemon.backPic then
    entry = Pokemon.backPic(sp, form)
  end
  if not entry then
    entry = Pokemon.frontPic and Pokemon.frontPic(sp, form)
  end
  if entry and entry.image then
    local a = (pres and pres.alpha) or 1
    local flash = pres and (pres.flash or 0) or 0
    local shade = 1 - darken * (1 - 8 / 255)
    if flash > 0 then
      love.graphics.setColor(1, 1, 1, a * (0.4 + 0.6 * ((flash % 2 == 0) and 1 or 0.3)))
    else
      love.graphics.setColor(shade, shade, shade, a)
    end
    local hFlip = (pres and pres.hFlip) and true or false
    local sx = (hFlip and -1 or 1) * scale * ((pres and pres.sx) or 1)
    local sy = scale * ((pres and pres.sy) or 1)
    local rot = (pres and pres.rotation) or 0
    local blended
    if id then
      blended = BallOpen.setBlendShader(BallOpen.monBlend(id))
      if not blended and id < 2 then blended = BallOpen.setBlendShader(BallOpen.monBlend(side)) end
    else
      blended = BallOpen.setBlendShader(BallOpen.monBlend(side))
    end
    if not blended and pres then
      if pres.palAffine then
        blended = set_affine_shader(pres.palAffine)
      elseif (tonumber(pres.mosaic) or 0) > 0 then
        blended = set_mosaic_shader(entry.image, pres.mosaic)
      elseif pres.grayscale then
        blended = set_gray_shader()
      elseif (tonumber(pres.blendCoeff) or 0) > 0 then
        local c = pres.blendColor or { 1, 1, 1 }
        blended = BallOpen.setBlendShader(pres.blendCoeff * 16, (c[1] or 0) * 31, (c[2] or 0) * 31, (c[3] or 0) * 31)
      end
    end
    if not blended and tf and not dollImg then
      -- pokefirered/src/battle_gfx_sfx_util.c:747
      blended = BallOpen.setBlendShader(6, 31, 31, 31)
    end
    if not blended and id then
      local pc = Ui.previewCoeff(id)
      -- pokefirered/src/battle_controller_player.c:2987
      if pc > 0 then blended = BallOpen.setBlendShader(pc, 31, 31, 31) end
    end
    if pres and type(pres.hShift) == "table" and rot == 0 and sy == 1 then
      local img = entry.image
      local iw, ih = img:getDimensions()
      local top = math.floor(cy - 32 + 0.5)
      for r = 0, ih - 1 do
        local q = row_quad(iw, ih, r)
        local dx = tonumber(pres.hShift[top + r]) or 0
        love.graphics.draw(img, q, cx + dx, top + r, 0, sx, 1, 32, 0)
      end
    else
      love.graphics.draw(entry.image, cx, cy, rot, sx, sy, 32, 32)
    end
    if blended then love.graphics.setShader() end
    if pres and pres.statMask and not dollImg then draw_stat_mask(pres, entry.image, cx, cy, sx, sy) end
  else
    -- Placeholder silhouette so lunge/shake is visible before full pic extract.
    local a = (pres and pres.alpha) or 1
    local flash = pres and (pres.flash or 0) or 0
    if flash > 0 and flash % 2 == 0 then
      love.graphics.setColor(1, 1, 1, a)
    elseif back then
      love.graphics.setColor(0.35, 0.55, 0.95, a)
    else
      love.graphics.setColor(0.95, 0.45, 0.35, a)
    end
    local hw = 24 * scale
    local rot = (pres and pres.rotation) or 0
    local sx = (pres and pres.sx) or 1
    local sy = (pres and pres.sy) or 1
    if rot ~= 0 or sx ~= 1 or sy ~= 1 then
      love.graphics.push()
      love.graphics.translate(cx, cy)
      love.graphics.rotate(rot)
      love.graphics.scale(sx, sy)
      love.graphics.rectangle("fill", -hw, -hw, hw * 2, hw * 2)
      love.graphics.setColor(1, 1, 1, a * 0.9)
      love.graphics.rectangle("line", -hw, -hw, hw * 2, hw * 2)
      love.graphics.pop()
    else
      love.graphics.rectangle("fill", cx - hw, cy - hw, hw * 2, hw * 2)
      love.graphics.setColor(1, 1, 1, a * 0.9)
      love.graphics.rectangle("line", cx - hw, cy - hw, hw * 2, hw * 2)
    end
  end
end

local function draw_action_menu(st)
  -- B_WIN_ACTION_PROMPT @ (1,15) after scroll → px (8,120); printer (2,2) → (10,122)
  -- B_WIN_ACTION_MENU @ (17,15) → (136,120); printer (0,2) → (136,122)
  -- ActionSelectionCreateCursorAt: tile (16+7*col, 35+row) → after scroll (128,120);
  -- cursor is a 1×2 BG pip whose ink lines up with printer y=2 text → draw at text Y.
  local ab = st and (is_double(st) and active_battler(st) or st.player)
  local name = ab and State.displayName(ab) or "POKéMON"
  draw_prompt_text(string.format("What will\n%s do?", name), 10, 122)
  local labels = { "FIGHT", "BAG", "POKéMON", "RUN" }
  local positions = {
    { 136, 122 }, { 184, 122 },
    { 136, 138 }, { 184, 138 },
  }
  local c = Ui._menuIndex - 1
  local cursorPos = {
    { 128, 122 }, { 176, 122 },
    { 128, 138 }, { 176, 138 },
  }
  local cp = cursorPos[c + 1] or cursorPos[1]
  Window.cursorPx(cp[1], cp[2], { colors = FrlgFont.COLOR.NORMAL })
  for i, pos in ipairs(positions) do
    draw_menu_text(labels[i], pos[1], pos[2], { small = false, colors = FrlgFont.COLOR.NORMAL })
  end
end

local function draw_move_menu(st)
  local ab = st and (is_double(st) and active_battler(st) or st.player)
  local mon = ab and ab.mon
  local positions = {
    { 16, 122 }, { 88, 122 },
    { 16, 138 }, { 88, 138 },
  }
  local cursorPos = {
    { 8, 122 }, { 80, 122 },
    { 8, 138 }, { 80, 138 },
  }
  local c = Ui._moveIndex - 1
  local cp = cursorPos[c + 1] or cursorPos[1]
  Window.cursorPx(cp[1], cp[2], { colors = FrlgFont.COLOR.NORMAL })
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    -- pokefirered/src/data/text/move_names.h:2
    local label = "-"
    if mv and mv ~= 0 and mv ~= "" then
      label = Moves.displayName(mv)
    end
    draw_menu_text(label, positions[i][1], positions[i][2], { small = true, colors = FrlgFont.COLOR.NORMAL })
  end
  local slot = Ui._moveIndex
  local mv = mon and mon.moves and mon.moves[slot]
  if mv and mv ~= 0 and mv ~= "" then
    local def = Moves.get(mv)
    local pp = mon.pp and mon.pp[slot] or 0
    local maxPp = mon.maxPp and mon.maxPp[slot] or (def and def.pp) or pp
    draw_menu_text(string.format("PP %d/%d", pp, maxPp), 168, 122, { small = true, colors = FrlgFont.COLOR.NORMAL })
    draw_menu_text(Types.get(def and def.type) or "NORMAL", 168, 138, { small = true, colors = FrlgFont.COLOR.NORMAL })
  end
end


local function draw_enemy_trainer(stage)
  if not stage or not stage.trainer then return end
  local TrainerPic = require("src.core.game3.trainer_pic")
  local te = stage.trainer.enemy
  if te and te.visible then
    local picId = te.picId
    if picId ~= nil then
      local entry = TrainerPic.front(picId)
      if entry and entry.image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(entry.image, 176 + (te.ox or 0) - 32, 40 + (te.oy or 0) - 32)
      end
    end
  end
end

local function draw_player_trainer(stage)
  if not stage or not stage.trainer then return end
  local TrainerPic = require("src.core.game3.trainer_pic")
  local tp = stage.trainer.player
  if tp and tp.visible then
    local entry = TrainerPic.back(tp.gender or 0)
    if entry and entry.image then
      local frame = math.max(0, math.min(4, tonumber(tp.frame) or 0))
      local q = stage._backQuad
      if not q and love and love.graphics then
        -- quads cached on stage weakly; recreate each frame is fine for one sprite
      end
      local key = "back_" .. tostring(frame)
      Ui._trainerQuads = Ui._trainerQuads or {}
      if not Ui._trainerQuads[key] then
        Ui._trainerQuads[key] = love.graphics.newQuad(0, frame * 64, 64, 64, 64, 320)
      end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        entry.image, Ui._trainerQuads[key],
        80 + (tp.ox or 0) - 32, 80 + (tp.oy or 0) - 32)
    end
  end
end

local function draw_ball_entry(ball)
  if not ball or not ball.visible then return end
  local bx = (ball.x or 0) + (ball.ox or 0)
  local by = (ball.y or 0) + (ball.oy or 0)
  local rot = tonumber(ball.rot) or 0
  local frame = math.max(0, math.min(2, tonumber(ball.frame) or 0))
  local darken = tonumber(ball.darken) or 0
  local flash = tonumber(ball.flash) or 0
  local shade = math.max(0, math.min(1, 1 - darken * (1 - 8 / 255)))

  local alpha = tonumber(ball.alpha) or 1
  if flash > 0 and flash % 2 == 0 then
    love.graphics.setColor(1, 1, 1, alpha)
  else
    love.graphics.setColor(shade, shade, shade, alpha)
  end

  Ui._ballPoke = Ui._ballPoke or nil
  local img = Ui._ballPoke
  if img == nil then
    local candidates = {
      "data/generated/gba/intro/ball_poke.png",
      "data/generated/gba/intro/ballPoke.png",
    }
    for _, rel in ipairs(candidates) do
      if love and love.filesystem and love.filesystem.getInfo(rel) then
        local ok, loaded = pcall(love.graphics.newImage, rel)
        if ok and loaded then
          if loaded.setFilter then loaded:setFilter("nearest", "nearest") end
          img = loaded
          break
        end
      end
    end
    Ui._ballPoke = img or false
  end

  if img then
    Ui._ballQuads = Ui._ballQuads or {}
    local key = "ball_" .. frame
    if not Ui._ballQuads[key] then
      local iw, ih = img:getDimensions()
      Ui._ballQuads[key] = love.graphics.newQuad(0, frame * 16, 16, 16, iw, ih)
    end
    local blend = ball.blend
    local blended = blend and BallOpen.setBlendShader(blend.coeff, blend.r, blend.g, blend.b)
    love.graphics.draw(img, Ui._ballQuads[key], bx, by, rot, 1, 1, 8, 8)
    if blended then love.graphics.setShader() end
  else
    -- Procedural 16x16 Poké Ball fallback
    love.graphics.push()
    love.graphics.translate(bx, by)
    love.graphics.rotate(rot)
    love.graphics.setColor(0.9, 0.2, 0.2, 1)
    love.graphics.arc("fill", 0, 0, 7, math.pi, 0)
    love.graphics.setColor(0.95, 0.95, 0.95, 1)
    love.graphics.arc("fill", 0, 0, 7, 0, math.pi)
    love.graphics.setColor(0.15, 0.15, 0.15, 1)
    love.graphics.circle("line", 0, 0, 7)
    love.graphics.rectangle("fill", -7, -1, 14, 2)
    love.graphics.circle("fill", 0, 0, 2.5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 0, 0, 1.2)
    love.graphics.pop()
  end

  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/battle_controller_player.c:2105
local function draw_intro_ball(stage)
  if not stage then return end
  draw_ball_entry(stage.ball)
  local balls = stage.balls
  if type(balls) == "table" then
    for id = 0, 3 do
      local e = rawget(balls, id)
      if e and e ~= stage.ball then draw_ball_entry(e) end
    end
  end
end

local function battler_at(st, id)
  if id == 0 then return st.player end
  if id == 1 then return st.enemy end
  return st.battlers and st.battlers[id]
end

-- pokefirered/src/battle_anim_mons.c:1908
local function draw_double_mons(st, stage, Anim, screenFxActive)
  local order = (Anim.monDrawOrder and Anim.monDrawOrder(st)) or PicCoords.DRAW_ORDER
  local band = Anim.particleBand
  local function particles(k)
    local lo, hi
    if band then lo, hi = band(k, st) end
    if not lo then
      lo = (k == 0) and 0 or (k * 100 + 1)
      hi = (k >= #order) and 999 or (k * 100 + 99)
    end
    Anim.drawParticles(lo, hi)
  end
  draw_enemy_trainer(stage)
  particles(0)
  for k, id in ipairs(order) do
    if id % 2 == 0 and k > 1 and order[k - 1] % 2 == 1 then
      draw_player_trainer(stage)
    end
    if not (st.absent and st.absent[id]) then
      local b = battler_at(st, id)
      local base = (Anim.coords and Anim.coords(st, id)) or PicCoords.battlerCoords(true, id)
      draw_mon_sprite(b, base, id % 2 == 0, id)
    end
    if screenFxActive then Anim.beginScreenEffect() end
    particles(k)
  end
end

-- pokefirered/src/battle_interface.c:540
local function draw_double_healthboxes(st, Anim)
  for id = 3, 0, -1 do
    local b = battler_at(st, id)
    if b and not (st.absent and st.absent[id]) then
      Healthbox.draw(id, Anim.shownBattler(id, b), { st = st, oy = Ui.bounceOffset("hb", id) })
    end
  end
end

-- pokefirered/src/battle_interface.c:1080
function Ui.partySummaryCoords(st, battlerId, isSwitchingMons)
  local id = tonumber(battlerId) or 0
  if id % 2 == 0 then return 136, 96 end
  if isSwitchingMons and is_double(st) and id ~= 3 then return 104, 16 end
  return 104, 40
end

local function draw_party_bars(stage)
  if not stage or not stage.partyBar then return end
  local m = BattleChrome.manifest and BattleChrome.manifest() or {}
  local enemy = stage.partyBar.enemy
  if enemy and enemy.visible then
    local pos = m.partyBarOpponent or { x = 104, y = 40 }
    BattleChrome.drawPartyBar(enemy.x or pos.x, enemy.y or pos.y, enemy.balls, enemy.ox, true)
  end
  local player = stage.partyBar.player
  if player and player.visible then
    local pos = m.partyBarPlayer or { x = 136, y = 96 }
    BattleChrome.drawPartyBar(pos.x, pos.y, player.balls, player.ox, false)
  end
end

function Ui.draw(w, h)
  if not (love and love.graphics) then return end
  w = w or Display.W
  h = h or Display.H

  local Anim = require("src.core.game3.battle.anim")
  local st = Ui._st
  local stage = Anim.stage and Anim.stage()

  local enemyOx = 0
  local playerOx = 0
  if stage and stage.bgSlide then
    enemyOx = stage.bgSlide.enemyOx or 0
    playerOx = stage.bgSlide.playerOx or 0
  end
  -- pokefirered/src/battle_intro.c:139
  local bgOx = 0
  if (enemyOx ~= 0 or playerOx ~= 0) and stage and stage.slide then
    bgOx = math.floor((tonumber(stage.slide) or 0) * 154 * 6 + 0.5)
  end

  local bgDim = (stage and stage.bgDim) or 0
  if bgDim > 0 then
    local s = math.max(0, 1 - bgDim * 0.65)
    love.graphics.setColor(s, s, s, 1)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end

  local screenFxActive = Anim.beginScreenEffect and Anim.beginScreenEffect()

  -- pokefirered/src/battle_anim_special.c:1888
  local bgBlended = not screenFxActive and BallOpen.setBlendShader(BallOpen.bgCoeff(), 31, 31, 31)
  if not bgBlended and not screenFxActive and Anim._bgPalAffine then
    bgBlended = set_affine_shader(Anim._bgPalAffine)
  end
  if not bgBlended and not screenFxActive then
    local bc, br, bg_, bb = bg_blend_params(Anim._bgBlend)
    if bc then bgBlended = BallOpen.setBlendShader(bc, br, bg_, bb) end
  end
  local bg3 = Anim._bg3Scroll
  if bg3 == nil then
    local vm = Anim.vm and Anim.vm()
    bg3 = vm and vm.active and vm.bg3 or nil
  end
  local bg3x = (type(bg3) == "table" and tonumber(bg3.x)) or 0
  local bg3y = (type(bg3) == "table" and tonumber(bg3.y)) or 0
  if bg3x ~= 0 or bg3y ~= 0 then
    love.graphics.push()
    love.graphics.translate(-bg3x, -bg3y)
  end
  if not BattleBg.draw(nil, enemyOx, playerOx, bgOx) then
    love.graphics.setColor(0.92, 0.94, 0.96, 1)
    love.graphics.rectangle("fill", 0, 0, w, 112)
  end
  if bg3x ~= 0 or bg3y ~= 0 then
    love.graphics.pop()
  end
  if bgBlended then love.graphics.setShader() end
  if screenFxActive then Anim.beginScreenEffect() end
  love.graphics.setColor(1, 1, 1, 1)

  -- pret-ish 5-layer z:
  -- 1. Behind Enemy & Background FX (Z: 0 .. 99)
  -- 2. Enemy Mon (Z: 100)
  -- 3. In front of Enemy / Behind Player / Mid-field (Z: 101 .. 199)
  -- 4. Player Mon (Z: 200)
  -- 5. In front of Player & Global Foreground (Z: 201 .. 999)
  local dbl = st and is_double(st)
  if dbl then
    draw_double_mons(st, stage, Anim, screenFxActive)
  else
  draw_enemy_trainer(stage)
  Anim.drawParticles(0, 99)
  if st then
    draw_mon_sprite(st.enemy, ENEMY_MON, false)
  end
  if screenFxActive then Anim.beginScreenEffect() end
  Anim.drawParticles(101, 199)
  -- pokefirered/src/battle_anim_mons.c:1908
  draw_player_trainer(stage)
  if st then
    draw_mon_sprite(st.player, PLAYER_MON, true)
  end
  if screenFxActive then Anim.beginScreenEffect() end
  Anim.drawParticles(201, 999)
  end
  draw_intro_ball(stage)
  -- pokefirered/src/pokeball.c:770
  BallOpen.draw()
  if screenFxActive then Anim.endScreenEffect() end
  if dbl then
    draw_double_healthboxes(st, Anim)
  elseif st then
    Healthbox.draw("enemy", Anim.shownBattler("enemy", st.enemy), { oy = Ui.bounceOffset("hb", 1) })
    Healthbox.draw("player", Anim.shownBattler("player", st.player), { oy = Ui.bounceOffset("hb", 0) })
  end
  draw_party_bars(stage)

  local panelMode = "none"
  if Ui._mode == "menu" then
    panelMode = "menu"
  elseif Ui._mode == "moves" or Ui._mode == "target" then
    panelMode = "moves"
  end
  BattleChrome.drawPanel(panelMode)

  if Ui._mode == "menu" then
    draw_action_menu(st)
  elseif Ui._mode == "moves" or Ui._mode == "target" then
    draw_move_menu(st)
  end

  local BagMenu = package.loaded["src.ui.game3.bag_menu"]
  if not BagMenu then
    local ok, M = pcall(require, "src.ui.game3.bag_menu")
    if ok then BagMenu = M end
  end
  if BagMenu and BagMenu.isOpen and BagMenu.isOpen() and BagMenu.draw then
    BagMenu.draw()
  end

  if Choice and Choice.active and Choice.draw then
    Choice.draw()
  end

  local PartyMenu = package.loaded["src.ui.game3.party_menu"]
  if not PartyMenu then
    local ok, M = pcall(require, "src.ui.game3.party_menu")
    if ok then PartyMenu = M end
  end
  if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() and PartyMenu.draw then
    PartyMenu.draw()
  end

  local Pokedex = package.loaded["src.ui.game3.pokedex"]
  if Pokedex and Pokedex.isOpen and Pokedex.isOpen() and Pokedex.draw then
    Pokedex.draw()
  end

  local StatGrowth = package.loaded["src.ui.game3.stat_growth"]
  if StatGrowth and StatGrowth.isOpen and StatGrowth.isOpen() and StatGrowth.draw then
    StatGrowth.draw()
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function Ui.log()
  return Ui._log
end

return Ui
