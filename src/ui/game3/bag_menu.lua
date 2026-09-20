-- FRLG Bag menu (item_menu.c field) — pockets, cursor, USE/TOSS/GIVE/REGISTER.
-- Layout matching pret GBA layout: left pocket & bag art + bottom icon/desc, right item list.

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")
local Options = require("src.core.game3.options")
local Trig = require("src.core.game3.trig")
local PartyView = require("src.core.game3.battle.party_view")
local Strings = require("src.core.Strings")

local BagMenu = {}

BagMenu.open = false
BagMenu.cursor = 1
BagMenu.pocketIdx = 1
BagMenu.scroll = 0
BagMenu.mode = "list" -- list | action | party | toss
BagMenu.actionCursor = 1
BagMenu.partyCursor = 1
BagMenu.partyPurpose = "use" -- use | give
BagMenu.tossQty = 1
BagMenu.ACTIONS = { "USE", "TOSS", "GIVE", "CANCEL" }

local VISIBLE = 6
local LIST_TOP = 1
local LIST_LEFT = 11
local LIST_W = 18
local LIST_H = 13

-- include/constants/songs.h:251
local SE_BAG_CURSOR = 245
local SE_BAG_POCKET = 246
local SE_SELECT = 5

-- src/item_menu_icons.c:81
local SHAKE_ROT = { -2, -4, -2, 0, 2, 4, 2, 0, -2, -4, -2, 0 }

-- src/bag.c:13
local WIN_WHITE = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }
local CURSOR_SELECTED = { fg = FrlgFont.STDPAL[3], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }
-- src/item_menu.c:285
local ITEM_BLUE = { fg = FrlgFont.STDPAL[8], shadow = FrlgFont.STDPAL[9], bg = FrlgFont.STDPAL[0] }

local sessionState = setmetatable({}, { __mode = "k" })

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function actions_for_pocket(pocket, row)
  if BagMenu._battle then
    -- src/item_menu.c:1344
    local num = row and ItemsData.toNumericId(row.id)
    if num == ItemsData.ITEM_BERRY_POUCH then
      return { "OPEN", "CANCEL" }
    end
    local BattleItems = require("src.core.game3.battle.items")
    if row and BattleItems.isBattleUsable(row.id) then
      return { "USE", "CANCEL" }
    end
    return { "CANCEL" }
  end
  pocket = pocket or "ITEMS"
  local info = row and (row.info or ItemsData.info(row.id))
  local registrable = info and (tonumber(info.registrability) or 0) > 0
  if pocket == "KEY_ITEMS" then
    if registrable then
      return { "USE", "SET", "CANCEL" }
    end
    return { "USE", "CANCEL" }
  elseif pocket == "POKE_BALLS" then
    return { "GIVE", "TOSS", "CANCEL" }
  elseif pocket == "TM_CASE" then
    return { "USE", "CANCEL" }
  elseif pocket == "BERRY_POUCH" then
    return { "USE", "GIVE", "TOSS", "CANCEL" }
  end
  return { "USE", "GIVE", "TOSS", "CANCEL" }
end

function BagMenu.isOpen()
  return BagMenu.open
end

function BagMenu.currentPocket()
  return ItemsData.BAG_POCKET_ORDER[BagMenu.pocketIdx] or "ITEMS"
end

function BagMenu.list(pocket)
  pocket = pocket or BagMenu.currentPocket()
  local bag = BagMenu._bag
  if not bag then return {} end
  local rows
  if bag.pockets then
    rows = Bag.listPocket(bag, pocket)
  else
    if not bag.stacks then return {} end
    rows = {}
    for id, qty in pairs(bag.stacks) do
      if ItemsData.pocketOf(id) == pocket and qty and qty > 0 then
        rows[#rows + 1] = {
          id = id,
          qty = qty,
          name = ItemsData.displayName(id),
          info = ItemsData.info(id),
          description = ItemsData.description(id),
        }
      end
    end
    table.sort(rows, function(a, b)
      return tostring(a.name) < tostring(b.name)
    end)
  end
  return rows
end

local function max_showed(total)
  -- src/item_menu.c:1005
  return math.min(VISIBLE, total)
end

local function clamp_cursor()
  local rows = BagMenu.list()
  local total = #rows + 1
  local shown = max_showed(total)
  if BagMenu.cursor > total then BagMenu.cursor = total end
  if BagMenu.cursor < 1 then BagMenu.cursor = 1 end
  if BagMenu.scroll > total - shown then BagMenu.scroll = total - shown end
  if BagMenu.cursor <= BagMenu.scroll then
    BagMenu.scroll = BagMenu.cursor - 1
  end
  if BagMenu.cursor > BagMenu.scroll + shown then
    BagMenu.scroll = BagMenu.cursor - shown
  end
  if BagMenu.scroll < 0 then BagMenu.scroll = 0 end
  return rows
end

local function bag_state()
  local key = BagMenu._session or BagMenu._bag or BagMenu
  local st = sessionState[key]
  if not st then
    st = { pocket = 1, pos = {} }
    sessionState[key] = st
  end
  return st
end

local function save_pos()
  local st = bag_state()
  st.pocket = BagMenu.pocketIdx
  st.pos[BagMenu.pocketIdx] = { cursor = BagMenu.cursor, scroll = BagMenu.scroll }
end

local function load_pos(pocketIdx)
  local p = bag_state().pos[pocketIdx]
  BagMenu.cursor = p and p.cursor or 1
  BagMenu.scroll = p and p.scroll or 0
end

-- src/item_menu.c:866
local function settle_scroll()
  local st = bag_state()
  for p, pos in pairs(st.pos) do
    local total = #BagMenu.list(ItemsData.BAG_POCKET_ORDER[p]) + 1
    local shown = max_showed(total)
    if pos.cursor > total then pos.cursor = total end
    if pos.scroll > total - shown then pos.scroll = total - shown end
    if pos.scroll < 0 then pos.scroll = 0 end
    local row = pos.cursor - pos.scroll - 1
    if row > 3 then
      local j = 0
      while j <= row - 3 do
        if pos.scroll + shown == total then break end
        row = row - 1
        pos.scroll = pos.scroll + 1
        j = j + 1
      end
    end
  end
end

local function field_fade_in()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.begin then
    Fade.begin(Fade.MODE.FROM_BLACK, 1)
  end
end

-- src/item_menu.c:915
local function begin_open(curtain)
  BagMenu._exit = nil
  BagMenu._open = { k = 0, curtain = curtain }
end

-- src/item_menu.c:893, 941
local function begin_exit(curtain, cb)
  BagMenu._open = nil
  BagMenu._switch = nil
  BagMenu._exit = { k = 0, curtain = curtain, cb = cb }
end

local function reshow()
  if BagMenu.open then begin_open(false) end
end

-- Close the bag and report the chosen item to the battle system.  partySlot is
-- the real party index for party-targeted items, or nil otherwise.  Shared with
-- the Berry Pouch so a berry picked there takes the same route as a potion.
function BagMenu.battleUse(itemId, partySlot)
  begin_exit(true, function()
    save_pos()
    local cb = BagMenu._onBattleUse
    BagMenu._battleUsed = true
    BagMenu.open = false
    BagMenu._battle = false
    BagMenu._onBattleUse = nil
    Stack.pop("bag")
    if cb then cb(itemId, partySlot) end
  end)
end

function BagMenu.show(sessionBag, opts)
  opts = opts or {}
  BagMenu.open = true
  if sessionBag and sessionBag.pockets then
    BagMenu._bag = sessionBag
    BagMenu._session = opts.session or (sessionBag.party and sessionBag)
  elseif sessionBag and (sessionBag.bag or sessionBag.party) then
    BagMenu._bag = sessionBag.bag or opts.bag
    BagMenu._session = opts.session or sessionBag
  else
    BagMenu._bag = opts.bag or sessionBag
    BagMenu._session = opts.session or (type(sessionBag) == "table" and sessionBag.party and sessionBag)
  end
  BagMenu._battle = opts.battle and true or false
  BagMenu._onBattleUse = opts.onBattleUse
  local st = bag_state()
  BagMenu.pocketIdx = opts.pocketIdx or st.pocket or 1
  BagMenu.mode = "list"
  BagMenu.partyPurpose = "use"
  BagMenu.tossQty = 1
  BagMenu._onClose = opts.onClose
  if opts.pocket then
    for i, p in ipairs(ItemsData.BAG_POCKET_ORDER) do
      if p == opts.pocket then BagMenu.pocketIdx = i; break end
    end
  end
  if not ItemsData.BAG_POCKET_ORDER[BagMenu.pocketIdx] then BagMenu.pocketIdx = 1 end
  settle_scroll()
  load_pos(BagMenu.pocketIdx)
  clamp_cursor()
  BagMenu._switch = nil
  BagMenu._shake = nil
  BagMenu._arrowK = 0
  BagMenu._heldKey = nil
  BagMenu._bagAnim = { n = 0 }
  begin_open(true)
  Stack.push("bag", BagMenu, { hideBelow = not BagMenu._battle })
end

function BagMenu.close()
  if BagMenu.open then save_pos() end
  BagMenu._open = nil
  BagMenu._exit = nil
  BagMenu._switch = nil
  BagMenu.open = false
  local battleCb = BagMenu._onBattleUse
  local wasBattle = BagMenu._battle
  BagMenu._battle = false
  BagMenu._onBattleUse = nil
  Stack.pop("bag")
  local cb = BagMenu._onClose
  BagMenu._onClose = nil
  if cb then cb() end
  if wasBattle and battleCb and not BagMenu._battleUsed then
    battleCb(nil)
  end
  BagMenu._battleUsed = nil
end

local function close_to_field()
  local battle = BagMenu._battle
  BagMenu.close()
  if not battle then field_fade_in() end
end

local function refresh_actions()
  local rows = BagMenu.list()
  local row = rows[BagMenu.cursor]
  BagMenu.ACTIONS = actions_for_pocket(BagMenu.currentPocket(), row)
  if BagMenu.actionCursor > #BagMenu.ACTIONS then
    BagMenu.actionCursor = 1
  end
end

local function pocket_switch_dir(input, pocketIdx)
  -- src/item_menu.c:1124
  local lr = Options.lrMode(BagMenu._session)
  if input:wasPressed("left") or (lr and input:wasPressed("l")) then
    if pocketIdx <= 1 then return 0 end
    se(SE_BAG_POCKET)
    return -1
  end
  if input:wasPressed("right") or (lr and input:wasPressed("r")) then
    if pocketIdx >= #ItemsData.BAG_POCKET_ORDER then return 0 end
    se(SE_BAG_POCKET)
    return 1
  end
  return 0
end

-- src/item_menu.c:1147
local function start_switch(dir)
  save_pos()
  BagMenu.pocketIdx = BagMenu.pocketIdx + dir
  load_pos(BagMenu.pocketIdx)
  clamp_cursor()
  BagMenu._switch = { dir = dir, k = 0 }
  BagMenu._bagAnim = { n = 0 }
  if BagMenu._shake then BagMenu._shake.cb = false end
end

local function shake_ended()
  local s = BagMenu._shake
  return s == nil or (s.phase == "shake" and s.j >= 13)
end

-- src/item_menu.c:677
local function cursor_moved()
  se(SE_BAG_CURSOR)
  if shake_ended() then
    BagMenu._shake = { phase = "shake", j = 0, cb = true }
  end
end

-- src/list_menu.c:438
local function move_cursor(down)
  local total = #BagMenu.list() + 1
  local shown = max_showed(total)
  local scroll = BagMenu.scroll
  local row = BagMenu.cursor - scroll - 1
  local newRow
  if not down then
    newRow = (shown == 1) and 0 or (shown - (math.floor(shown / 2) + shown % 2) - 1)
    if scroll == 0 then
      if row == 0 then return false end
      row = row - 1
    elseif row > newRow then
      row = row - 1
    else
      row = newRow
      scroll = scroll - 1
    end
  else
    newRow = (shown == 1) and 0 or (math.floor(shown / 2) + shown % 2)
    if scroll == total - shown then
      if row >= shown - 1 then return false end
      row = row + 1
    elseif row < newRow then
      row = row + 1
    else
      row = newRow
      scroll = scroll + 1
    end
  end
  BagMenu.scroll = scroll
  BagMenu.cursor = scroll + row + 1
  return true
end

local function held_repeat(input, key)
  if input:wasPressed(key) then return true end
  -- src/main.c:309
  return BagMenu._heldKey == key and BagMenu._heldFrames >= 40
    and (BagMenu._heldFrames - 40) % 5 == 0
end

local function track_held(input)
  local key
  if input.isDown then
    if input:isDown("up") then key = "up" elseif input:isDown("down") then key = "down" end
  end
  if key ~= BagMenu._heldKey or input:wasPressed(key or "") then
    BagMenu._heldKey = key
    BagMenu._heldFrames = 0
  elseif key then
    BagMenu._heldFrames = (BagMenu._heldFrames or 0) + 1
  end
end

local function open_submenu(fn)
  begin_exit(false, fn)
end

local function handle_menu_input(input)
  if BagMenu.mode == "toss" then
    local rows = BagMenu.list()
    local row = rows[BagMenu.cursor]
    local maxQ = row and (tonumber(row.qty) or 1) or 1
    if input:wasPressed("up") or input:wasPressed("right") then
      BagMenu.tossQty = math.min(maxQ, BagMenu.tossQty + 1)
      se(5)
    elseif input:wasPressed("down") or input:wasPressed("left") then
      BagMenu.tossQty = math.max(1, BagMenu.tossQty - 1)
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      if row then
        Bag.remove(BagMenu._bag, row.id, BagMenu.tossQty)
      end
      BagMenu.mode = "list"
      clamp_cursor()
    elseif input:wasPressed("b") then
      se(9)
      BagMenu.mode = "action"
    end
    return
  end

  if BagMenu.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      se(5)
      BagMenu.mode = "list"
      BagMenu.messageText = nil
      clamp_cursor()
    end
    return
  end

  if BagMenu.mode == "action" then
    refresh_actions()
    if input:wasPressed("up") then
      BagMenu.actionCursor = ((BagMenu.actionCursor - 2) % #BagMenu.ACTIONS) + 1
      se(5)
    elseif input:wasPressed("down") then
      BagMenu.actionCursor = (BagMenu.actionCursor % #BagMenu.ACTIONS) + 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      local act = BagMenu.ACTIONS[BagMenu.actionCursor]
      local rows = clamp_cursor()
      local row = rows[BagMenu.cursor]
      local party = (BagMenu._session and BagMenu._session.party) or {}
      if act == "CANCEL" or not row then
        BagMenu.mode = "list"
      elseif act == "USE" then
        if BagMenu._battle and BagMenu._onBattleUse then
          local BattleItems = require("src.core.game3.battle.items")
          if BattleItems.needsPartySelect(row.id) then
            local PartyMenu = require("src.ui.game3.party_menu")
            local Battle = package.loaded["src.core.game3.battle"]
            local st = Battle and Battle._st
            -- Mid-battle the party list has to come from the live battle copy:
            -- session.party is only written back once the battle ends, so
            -- reading it here shows pre-battle HP and refuses heals that would
            -- in fact work.
            local liveParty = PartyView.live(BagMenu._session)
            -- pokefirered/src/party_menu.c:5878
            PartyMenu.show(liveParty, BagMenu._session and BagMenu._session.moveOverlay, {
              session = BagMenu._session,
              bag = BagMenu._bag,
              item = row.id,
              mode = "use",
              battle = true,
              battleOrder = st and st.playerParty and PartyMenu.battleOrder(st) or nil,
              layout = (st and st.double) and "double" or nil,
              onSelect = function(slot)
                if not slot or slot == 7 then
                  PartyMenu.close()
                  return
                end
                -- PartyMenu.show's battleOrder wrapper (party_menu.lua
                -- apply_battle_order) already turned the tapped row into a real
                -- party slot, so translating again would heal the wrong mon.
                local realSlot = slot
                local mon = liveParty and liveParty[realSlot]
                local canUse, err = BattleItems.canUseOn(st, row.id, realSlot, mon)
                if not canUse then
                  se(9)
                  PartyMenu.showMessage(err or Strings("It won't have any effect."), function()
                    PartyMenu.mode = "use"
                  end)
                  return
                end
                PartyMenu.close()
                BagMenu.battleUse(row.id, realSlot)
              end,
              onClose = function()
                BagMenu.mode = "list"
                clamp_cursor()
              end,
            })
            return
          else
            -- src/item_use.c:742
            BagMenu.battleUse(row.id, nil)
            return
          end
        else
          local numId = ItemsData.toNumericId(row.id)
          if numId == ItemsData.ITEM_TM_CASE or row.id == "TM_CASE" then
            local savedState = { pocketIdx = BagMenu.pocketIdx, cursor = BagMenu.cursor, scroll = BagMenu.scroll }
            local TmCase = require("src.ui.game3.tm_case")
            open_submenu(function()
              TmCase.show(BagMenu._session, BagMenu._bag, {
                session = BagMenu._session,
                bag = BagMenu._bag,
                onClose = function()
                  BagMenu.pocketIdx = savedState.pocketIdx
                  BagMenu.cursor = savedState.cursor
                  BagMenu.scroll = savedState.scroll
                  BagMenu.mode = "list"
                  clamp_cursor()
                  reshow()
                end,
              })
            end)
            return
          elseif numId == ItemsData.ITEM_BERRY_POUCH or row.id == "BERRY_POUCH" then
            local savedState = { pocketIdx = BagMenu.pocketIdx, cursor = BagMenu.cursor, scroll = BagMenu.scroll }
            local BerryPouch = require("src.ui.game3.berry_pouch")
            open_submenu(function()
              BerryPouch.show(BagMenu._session, BagMenu._bag, {
                session = BagMenu._session,
                bag = BagMenu._bag,
                onClose = function()
                  BagMenu.pocketIdx = savedState.pocketIdx
                  BagMenu.cursor = savedState.cursor
                  BagMenu.scroll = savedState.scroll
                  BagMenu.mode = "list"
                  clamp_cursor()
                  reshow()
                end,
              })
            end)
            return
          elseif ItemUse.needsPartyTarget(row.id) then
            if #party == 0 then
              BagMenu.mode = "message"
              BagMenu.messageText = Strings("There is no POKéMON.")
            else
              local PartyMenu = require("src.ui.game3.party_menu")
              open_submenu(function()
                PartyMenu.show(party, BagMenu._session and BagMenu._session.moveOverlay, {
                  session = BagMenu._session,
                  bag = BagMenu._bag,
                  item = row.id,
                  mode = "use",
                  onClose = function()
                    BagMenu.mode = "list"
                    clamp_cursor()
                    reshow()
                  end,
                })
              end)
            end
          else
            local ok, kind, text = ItemUse.useField(BagMenu._session, BagMenu._bag, row.id, nil)
            if kind == "vs_seeker" and not ok then
              BagMenu.mode = "message"
              BagMenu.messageText = text
            elseif kind == "vs_seeker" then
              -- pokefirered/src/item_use.c:727
              local session = BagMenu._session
              begin_exit(true, function()
                BagMenu.close()
                local StartMenu = package.loaded["src.ui.game3.start_menu"]
                if StartMenu and StartMenu.isOpen and StartMenu.isOpen() then
                  StartMenu.open = false
                  StartMenu._onClose = nil
                  Stack.pop("start")
                end
                field_fade_in()
                require("src.core.game3.vs_seeker").use(session, nil)
              end)
              return
            elseif kind == "itemfinder" then
              local session = BagMenu._session
              begin_exit(true, function()
                BagMenu.close()
                local StartMenu = package.loaded["src.ui.game3.start_menu"]
                if StartMenu and StartMenu.isOpen and StartMenu.isOpen() then
                  StartMenu.open = false
                  StartMenu._onClose = nil
                  Stack.pop("start")
                end
                field_fade_in()
                local Field = require("src.core.game3.field")
                Field.useItemfinder(session, true)
              end)
              return
            else
              BagMenu.mode = "list"
              clamp_cursor()
            end
          end
        end
      elseif act == "GIVE" then
        local pocket = BagMenu.currentPocket()
        if pocket == "KEY_ITEMS" or pocket == "TM_CASE" then
          BagMenu.mode = "message"
          BagMenu.messageText = Strings("This item can't be held.")
        elseif #party == 0 then
          BagMenu.mode = "message"
          BagMenu.messageText = Strings("There is no POKéMON.")
        else
          local PartyMenu = require("src.ui.game3.party_menu")
          -- src/item_menu.c:1620
          open_submenu(function()
            PartyMenu.show(party, BagMenu._session and BagMenu._session.moveOverlay, {
              session = BagMenu._session,
              bag = BagMenu._bag,
              item = row.id,
              mode = "give",
              onClose = function()
                BagMenu.mode = "list"
                clamp_cursor()
                reshow()
              end,
            })
          end)
        end
      elseif act == "OPEN" then
        local BerryPouch = require("src.ui.game3.berry_pouch")
        open_submenu(function()
          BerryPouch.show(BagMenu._session, BagMenu._bag, {
            session = BagMenu._session,
            bag = BagMenu._bag,
            onClose = function()
              BagMenu.mode = "list"
              clamp_cursor()
              reshow()
            end,
          })
        end)
        return
      elseif act == "TOSS" then
        BagMenu.mode = "toss"
        BagMenu.tossQty = 1
      elseif act == "SET" or act == "REGISTER" then
        if BagMenu._session and row then
          if BagMenu._session.registeredItem == row.id then
            BagMenu._session.registeredItem = nil
          else
            BagMenu._session.registeredItem = row.id
          end
        end
        BagMenu.mode = "list"
      end
    elseif input:wasPressed("b") then
      se(9)
      BagMenu.mode = "list"
    end
    return
  end

  -- src/item_menu.c:1050
  local dir = pocket_switch_dir(input, BagMenu.pocketIdx)
  if dir ~= 0 then
    start_switch(dir)
    return
  end
  if input:wasPressed("select") and not BagMenu._battle then
    local rows = clamp_cursor()
    local row = rows[BagMenu.cursor]
    if row and BagMenu.currentPocket() == "KEY_ITEMS" then
      local info = row.info or ItemsData.info(row.id)
      local registrable = info and (tonumber(info.registrability) or 0) > 0
      if registrable and BagMenu._session then
        if BagMenu._session.registeredItem == row.id then
          BagMenu._session.registeredItem = nil
        else
          BagMenu._session.registeredItem = row.id
        end
        se(5)
      end
    end
    return
  end
  local rows = clamp_cursor()
  if input:wasPressed("a") then
    se(SE_SELECT)
    if BagMenu.cursor > #rows then
      -- src/item_menu.c:1085
      begin_exit(true, close_to_field)
    else
      BagMenu.mode = "action"
      BagMenu.actionCursor = 1
      refresh_actions()
    end
  elseif input:wasPressed("b") then
    se(SE_SELECT)
    begin_exit(true, close_to_field)
  elseif held_repeat(input, "up") then
    if move_cursor(false) then cursor_moved() end
  elseif held_repeat(input, "down") then
    if move_cursor(true) then cursor_moved() end
  end
end

-- src/item_menu.c:1169
local function run_transitions(input)
  local ex = BagMenu._exit
  if ex then
    ex.k = ex.k + 1
    if ex.k >= 15 then
      BagMenu._exit = nil
      if ex.cb then ex.cb() end
    end
    return true
  end
  local op = BagMenu._open
  if op then
    op.k = op.k + 1
    if op.k < 23 then return true end
    BagMenu._open = nil
  end
  local sw = BagMenu._switch
  if sw then
    local dir = pocket_switch_dir(input, BagMenu.pocketIdx)
    if dir ~= 0 then
      start_switch(dir)
      return true
    end
    sw.k = sw.k + 1
    if sw.k >= 13 then
      BagMenu._switch = nil
      clamp_cursor()
    end
    return true
  end
  return false
end

local function arrows_live()
  return BagMenu.mode == "list" and not BagMenu._switch
end

-- src/sprite.c:304
local function animate_sprites()
  if BagMenu._bagAnim then
    BagMenu._bagAnim.n = BagMenu._bagAnim.n + 1
    if BagMenu._bagAnim.n > 6 then BagMenu._bagAnim = nil end
  end
  local s = BagMenu._shake
  if s then
    if s.phase == "shake" then
      if s.j < 13 then
        s.j = s.j + 1
      elseif s.cb then
        s.phase = "idle"
      else
        BagMenu._shake = nil
      end
    else
      BagMenu._shake = nil
    end
  end
  if arrows_live() then
    BagMenu._arrowK = (BagMenu._arrowK or -1) + 1
  else
    BagMenu._arrowK = nil
  end
end

function BagMenu.handleInput(input)
  if BagMenu._battle then
    local top = Stack.top()
    if top and top.mod ~= BagMenu and top.mod and top.mod.handleInput then
      return top.mod.handleInput(input)
    end
  end
  track_held(input)
  if not run_transitions(input) then
    handle_menu_input(input)
  end
  animate_sprites()
end

local NO_INPUT = { wasPressed = function() return false end }

function BagMenu.settle()
  for _ = 1, 64 do
    if not (BagMenu._open or BagMenu._exit or BagMenu._switch) then return end
    BagMenu.handleInput(NO_INPUT)
  end
end

local function bob(k, freq)
  if not k or k < 1 then return 0 end
  local v = Trig.sin(((k - 1) * freq) % 256) * 2 / 256
  return v < 0 and math.ceil(v) or math.floor(v)
end

function BagMenu.draw()
  if not BagMenu.open then return end
  local pocket = BagMenu.currentPocket()
  local rows = clamp_cursor()
  local total = #rows + 1
  local switching = BagMenu._switch ~= nil
  local selected = BagMenu.mode ~= "list"

  local female = false
  local session = BagMenu._session
  if session and (session.gender == 1 or session.gender == "female"
      or session.playerGender == 1) then
    female = true
  end

  local okC, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  local chrome = okC and BagChrome and BagChrome.ready and BagChrome.ready()
  if chrome then
    BagChrome.drawBg(0, 0, { female = female })
    if switching then
      BagChrome.drawListFrame(math.min(12, BagMenu._switch.k), female)
    end
    if selected then
      BagChrome.drawDescSelected()
    end
    local anim = BagMenu._bagAnim
    local frame, y2 = nil, 0
    if anim then
      y2 = math.min(0, anim.n - 5)
      if anim.n <= 5 then frame = 0 end
    end
    local rot = 0
    local s = BagMenu._shake
    if s and s.phase == "shake" and s.j >= 1 and s.j <= 12 then rot = SHAKE_ROT[s.j] end
    BagChrome.drawBag(8, 36 + y2, {
      female = female, pocketIdx = BagMenu.pocketIdx, frame = frame, rotation = rot,
    })
  end

  if not switching then
    -- src/bag.c:226
    local pLabel = Strings(ItemsData.POCKET_LABEL[pocket] or pocket)
    local tw = FrlgFont.measure(pLabel)
    FrlgFont.draw(pLabel, 8 + math.floor((72 - tw) / 2), 9, { colors = WIN_WHITE })
  end

  if not chrome then
    Window.stdFrame(Window.template(LIST_LEFT, LIST_TOP, LIST_W, LIST_H))
  end
  if not switching then
    local shown = max_showed(total)
    for i = 1, shown do
      local idx = BagMenu.scroll + i
      if idx > total then break end
      local y = 10 + (i - 1) * 16
      if idx == BagMenu.cursor then
        if selected then
          FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, 89, y, { colors = CURSOR_SELECTED })
        else
          Window.cursorPx(89, y)
        end
      end
      local r = rows[idx]
      if not r then
        FrlgFont.draw(Strings("CANCEL"), 97, y, { colors = FrlgFont.COLOR.NORMAL })
      else
        local label = r.name
        if session and session.registeredItem
            and ItemsData.toNumericId(session.registeredItem) == ItemsData.toNumericId(r.id) then
          label = "►" .. label
        end
        local num = ItemsData.toNumericId(r.id)
        local colors = (num == ItemsData.ITEM_TM_CASE or num == ItemsData.ITEM_BERRY_POUCH)
          and ITEM_BLUE or FrlgFont.COLOR.NORMAL
        FrlgFont.draw(label, 97, y, { maxWidth = 96, colors = colors })
        local info = r.info or ItemsData.info(r.id)
        local important = info and (tonumber(info.importance) or 0) ~= 0
        if pocket ~= "KEY_ITEMS" and pocket ~= "TM_CASE" and not important then
          -- src/item_menu.c:716
          FrlgFont.draw(string.format("×%3d", r.qty or 1), 198, y,
            { small = true, colors = FrlgFont.COLOR.NORMAL })
        end
      end
    end
  end

  if chrome and BagMenu._arrowK and BagMenu._arrowK >= 1 then
    -- src/item_menu.c:287, 759
    local k = BagMenu._arrowK
    if BagMenu.pocketIdx > 1 then
      BagChrome.drawArrow("left", 0 + bob(k, 8), 64)
    end
    if BagMenu.pocketIdx < #ItemsData.BAG_POCKET_ORDER then
      BagChrome.drawArrow("right", 64 + bob(k, -8), 64)
    end
    local shown = max_showed(total)
    if BagMenu.scroll > 0 then
      BagChrome.drawArrow("up", 152, 0 + bob(k, 8))
    end
    if BagMenu.scroll < total - shown then
      BagChrome.drawArrow("down", 152, 96 + bob(k, -8))
    end
  end

  local sel = rows[BagMenu.cursor]
  if chrome and not switching then
    if sel then
      BagChrome.drawItemIcon(sel.id, 8, 124)
    else
      -- src/data/item_icon_table.h:402
      BagChrome.drawItemIcon(ItemsData.ITEMS_COUNT or 375, 8, 124)
    end
  end

  if BagMenu.mode ~= "action" and not switching then
    if not chrome then
      Window.stdFrame(Window.template(5, 14, 25, 6))
    end
    local desc = sel and sel.description
    if not sel then desc = Strings("CLOSE BAG") end
    if desc then
      -- src/item_menu.c:756 (window 1 at (5, 14), x=0, y=3, maxWidth=200, linePitch=14)
      FrlgFont.draw(desc, 40, 115, { colors = WIN_WHITE, maxWidth = 200, linePitch = 14 })
    end
  end

  -- Action Pop-up Menu (pret bag.c: tilemapLeft = 22, tilemapTop = 19 - actCount * 2, width = 7, height = actCount * 2)
  if BagMenu.mode == "action" then
    -- Bottom left prompt window (pret bag.c: sWindowTemplates[6] = (6, 15, 14, 4))
    if sel then
      Window.stdFrame(Window.template(6, 15, 14, 4))
      FrlgFont.draw(Strings("%s is\nselected.", (sel.name or "ITEM")), 6 * 8 + 4, 15 * 8 + 2, { maxWidth = 14 * 8, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
    end

    refresh_actions()
    local actCount = #BagMenu.ACTIONS
    local popW = 7
    local popH = actCount * 2
    local popX = 22
    local popY = 19 - popH
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, act in ipairs(BagMenu.ACTIONS) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == BagMenu.actionCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      FrlgFont.draw(Strings(act), popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  end

  -- Toss Quantity Pop-up
  if BagMenu.mode == "toss" and sel then
    local popX = 16
    local popY = 10
    local popW = 12
    local popH = 4
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    FrlgFont.draw(Strings("TOSS HOW MANY?"), popX * 8 + 4, popY * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(string.format("× %02d", BagMenu.tossQty), popX * 8 + 24, (popY + 2) * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })
  end

  -- In-bag message modal
  if BagMenu.mode == "message" and BagMenu.messageText then
    Window.stdFrame(Window.template(5, 14, 25, 6))
    local wrapped = FrlgFont.wrap(BagMenu.messageText, 192)
    FrlgFont.draw(wrapped, 40, 115, { maxWidth = 192, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
  end

  local level, curtain = 0, 0
  local op, ex = BagMenu._open, BagMenu._exit
  if op then
    -- src/item_menu.c:915, src/palette.c:393
    level = math.max(0, 16 - 2 * math.floor(op.k / 2))
    if op.curtain then curtain = math.max(0, math.min(160, 192 - 16 * op.k)) end
  elseif ex then
    level = math.min(16, 4 * math.floor(ex.k / 2))
    if ex.curtain then curtain = math.min(160, 16 * ex.k) end
  end
  if level > 0 then
    love.graphics.setColor(0, 0, 0, level / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
  end
  if curtain > 0 then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 240, curtain)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return BagMenu
