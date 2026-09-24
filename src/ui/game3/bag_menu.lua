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
local RomText = require("src.core.game3.rom_text")
local TextIR = require("src.core.game3.scripting.text_ir")

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
local SE_USE_ITEM = 1
local SE_GLASS_FLUTE = 110

-- src/item_menu_icons.c:81
local SHAKE_ROT = { -2, -4, -2, 0, 2, 4, 2, 0, -2, -4, -2, 0 }

-- src/item_use.c:159
local FIELD_EXIT_FADE = { bike = true, rod = true }

-- src/bag.c:13
local WIN_WHITE = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }
local CURSOR_SELECTED = { fg = FrlgFont.STDPAL[3], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] }
-- src/item_menu.c:285
local ITEM_BLUE = { fg = FrlgFont.STDPAL[8], shadow = FrlgFont.STDPAL[9], bg = FrlgFont.STDPAL[0] }

local sessionState = setmetatable({}, { __mode = "k" })

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

-- src/menu_helpers.c:114 MenuHelpers_IsLinkActive
-- src/union_room.c:4558 InUnionRoom
local function link_menus_active()
  local Map = package.loaded["src.core.game3.map"]
  if Map and Map.current == "FR_UNION_ROOM" then return true end
  local Link = package.loaded["src.core.game3.link"]
  return type(Link) == "table" and Link.link ~= nil and Link.inLinkRoom() == true
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
  -- src/item_menu.c:1370
  if link_menus_active() then
    local num = row and ItemsData.toNumericId(row.id)
    if num == ItemsData.ITEM_TM_CASE or num == ItemsData.ITEM_BERRY_POUCH then
      return { "USE", "CANCEL" }
    end
    if pocket == "KEY_ITEMS" then return { "CANCEL" } end
    return { "GIVE", "CANCEL" }
  end
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
function BagMenu.battleUse(itemId, partySlot, moveSlot, usedInMenu)
  begin_exit(true, function()
    save_pos()
    local cb = BagMenu._onBattleUse
    BagMenu._battleUsed = true
    BagMenu.open = false
    BagMenu._battle = false
    BagMenu._onBattleUse = nil
    Stack.pop("bag")
    if cb then cb(itemId, partySlot, moveSlot, usedInMenu) end
  end)
end

local QUIET_ADAPTER = { say = function() end }

-- pokefirered/src/party_menu.c:4464 ItemUseCB_MedicineStep
function BagMenu.commitBattlePartyUse(st, itemId, realSlot, mon, beforeUse)
  local PartyMenu = require("src.ui.game3.party_menu")
  local BattleItems = require("src.core.game3.battle.items")
  local isPp = ItemsData.fieldUseKind(itemId) == "pp"
  local function wont_have_effect(err)
    se(5) -- pokefirered/src/party_menu.c:4490
    PartyMenu.showMessage(err or RomText.box("gText_WontHaveEffect"), function()
      PartyMenu.mode = "use"
    end)
  end
  local function commit(moveSlot)
    local canUse, err = BattleItems.canUseOn(st, itemId, realSlot, mon, moveSlot)
    if not canUse then return wont_have_effect(err) end
    local displaySlot = PartyMenu.cursor
    local startHp = tonumber(mon and mon.hp) or 0
    local result, _, _, _, text = BattleItems.use(st, QUIET_ADAPTER, BagMenu._bag, BagMenu._session,
      itemId, realSlot, nil, moveSlot)
    if result ~= "heal" then return wont_have_effect() end
    local function go()
      PartyMenu.close()
      if beforeUse then beforeUse() end
      BagMenu.battleUse(itemId, realSlot, moveSlot, true)
    end
    -- pokefirered/src/party_menu.c:4498
    se(BattleItems.isFlute(itemId) and SE_GLASS_FLUTE or SE_USE_ITEM)
    local endHp = tonumber(mon and mon.hp) or startHp
    if endHp > startHp then
      -- pokefirered/src/party_menu.c:4514 PartyMenuModifyHP
      PartyMenu.startHpAnim(displaySlot, startHp, endHp, tonumber(mon.maxHp or mon.maxhp) or endHp, function()
        PartyMenu.showMessage(text, go)
      end)
      return
    end
    PartyMenu.showMessage(text, go)
  end
  if isPp and mon and not mon.isEgg and ItemUse.ppItemNeedsMove(itemId) then
    se(5)
    PartyMenu.pickPpMove(mon, itemId, commit)
    return
  end
  commit(nil)
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
  BagMenu._location = opts.location
  BagMenu._sell = nil
  BagMenu._onBattleUse = opts.onBattleUse
  local st = bag_state()
  BagMenu.pocketIdx = opts.pocketIdx or st.pocket or 1
  BagMenu.mode = "list"
  BagMenu.messageText = nil
  BagMenu._msgPages = nil
  BagMenu._msgPage = 1
  BagMenu._msgDone = nil
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
  BagMenu._statBoost = nil
  BagMenu._shake = nil
  BagMenu._arrowK = 0
  BagMenu._heldKey = nil
  BagMenu._bagAnim = { n = 0 }
  begin_open(true)
  Stack.push("bag", BagMenu, { hideBelow = not BagMenu._battle, fullscreen = not BagMenu._battle })
end

function BagMenu.close()
  if BagMenu.open then save_pos() end
  BagMenu._open = nil
  BagMenu._exit = nil
  BagMenu._switch = nil
  BagMenu._msgDone = nil
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

-- src/item_menu.c:194 sItemMenuContextActions
local ACTION_TEXT = { USE = 0, TOSS = 1, SET = 2, GIVE = 3, CANCEL = 4, OPEN = 7 }
-- include/constants/items.h:432
local ITEM_BICYCLE = 360

-- src/item_menu.c:1401
local function action_label(act, row)
  local i = ACTION_TEXT[act]
  local num = row and ItemsData.toNumericId(row.id)
  if act == "SET" and num and BagMenu._session
      and ItemsData.toNumericId(BagMenu._session.registeredItem) == num then
    i = 10
  elseif act == "USE" and not BagMenu._battle and BagMenu.currentPocket() == "KEY_ITEMS" then
    local Player = package.loaded["src.core.game3.player"]
    if num == ItemsData.ITEM_TM_CASE or num == ItemsData.ITEM_BERRY_POUCH then
      i = 7
    elseif num == ITEM_BICYCLE and Player and Player.biking then
      i = 9
    end
  end
  return RomText.at("sItemMenuContextActions", i)
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
  if BagMenu._location == "itempc" then return 0 end
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

-- src/text.c:796
local function show_bag_message(text, onDone)
  local pages = TextIR.splitPages(TextIR.restoreExt((TextIR.protectExt(text):gsub("\\p", "\f"))))
  BagMenu.mode = "message"
  BagMenu._msgPages = #pages > 1 and pages or nil
  BagMenu._msgPage = 1
  BagMenu.messageText = pages[1] or text
  BagMenu._msgDone = onDone
end

-- src/item_menu.c:1018 DisplayItemMessageInBag
BagMenu.showMessage = show_bag_message

-- src/item_use.c:182
local function use_field_from_bag(session, bag, id)
  return ItemUse.useField(session, bag, id, nil)
end

-- src/item_menu.c:1787 Task_ItemContext_Sell
local function begin_sell(row)
  local num = ItemsData.toNumericId(row.id)
  local savedState = { pocketIdx = BagMenu.pocketIdx, cursor = BagMenu.cursor, scroll = BagMenu.scroll }
  local function back()
    BagMenu.pocketIdx = savedState.pocketIdx
    BagMenu.cursor = savedState.cursor
    BagMenu.scroll = savedState.scroll
    BagMenu.mode = "list"
    clamp_cursor()
    reshow()
  end
  if num == ItemsData.ITEM_TM_CASE then
    -- src/item_menu.c:1825 GoToTMCase_Sell
    open_submenu(function()
      require("src.ui.game3.tm_case").show(BagMenu._session, BagMenu._bag, {
        session = BagMenu._session, bag = BagMenu._bag, sell = true, onClose = back,
      })
    end)
    return
  elseif num == ItemsData.ITEM_BERRY_POUCH then
    -- src/item_menu.c:1830 GoToBerryPouch_Sell
    open_submenu(function()
      require("src.ui.game3.berry_pouch").show(BagMenu._session, BagMenu._bag, {
        session = BagMenu._session, bag = BagMenu._bag, sell = true, onClose = back,
      })
    end)
    return
  end
  BagMenu.mode = "sell"
  BagMenu._sell = require("src.ui.game3.sell_flow").start({
    itemId = row.id,
    owned = row.qty,
    session = BagMenu._session,
    bag = BagMenu._bag,
    onDone = function()
      BagMenu._sell = nil
      BagMenu.mode = "list"
      clamp_cursor()
    end,
  })
end

-- src/item_menu.c:2004 Task_TryDoItemDeposit
local function try_deposit()
  local Storage = require("src.core.game3.storage")
  local row = BagMenu.list()[BagMenu.cursor]
  if Storage.addPcItem(BagMenu._session, row.id, BagMenu.tossQty) then
    require("src.core.game3.quest_log_recorder").event(BagMenu._session, "StoredItemInPC",
      { ItemsData.displayName(row.id) })
    BagMenu._depositPending = { id = row.id, qty = BagMenu.tossQty }
    BagMenu.mode = "deposit_done"
    BagMenu._depositText = RomText.box("gText_DepositedStrVar2StrVar1s",
      { stringVars = { row.name, tostring(BagMenu.tossQty) } })
  else
    show_bag_message(RomText.plain("gText_NoRoomToStoreItems"))
  end
end

-- src/item_menu.c:1959 Task_ItemContext_Deposit
local function begin_deposit(row)
  BagMenu.tossQty = 1
  if (tonumber(row.qty) or 1) == 1 then
    try_deposit()
  else
    BagMenu.mode = "deposit"
  end
end

local function handle_menu_input(input)
  if BagMenu.mode == "sell" and BagMenu._sell then
    BagMenu._sell:handleInput(input)
    return
  end
  if BagMenu.mode == "flute_wait" then
    -- pokefirered/src/item_use.c:607
    local w = BagMenu._fluteWait
    w.frames = w.frames + 1
    if w.frames >= ItemUse.BLACK_WHITE_FLUTE_DELAY then
      BagMenu._fluteWait = nil
      ItemUse.playBlackWhiteFlute()
      show_bag_message(w.text)
    end
    return
  end
  -- src/item_menu.c:1974 Task_SelectQuantityToDeposit
  if BagMenu.mode == "deposit" then
    BagMenu._depositK = (BagMenu._depositK or 0) + 1
    local row = BagMenu.list()[BagMenu.cursor]
    local qmax = math.min(999, tonumber(row.qty) or 1)
    local q = BagMenu.tossQty
    if input:wasPressed("up") then
      q = q + 1
      if q > qmax then q = 1 end
    elseif input:wasPressed("down") then
      q = q - 1
      if q <= 0 then q = qmax end
    elseif input:wasPressed("right") then
      q = math.min(qmax, q + 10)
    elseif input:wasPressed("left") then
      q = math.max(1, q - 10)
    end
    if q ~= BagMenu.tossQty then
      BagMenu.tossQty = q
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      try_deposit()
    elseif input:wasPressed("b") then
      se(5)
      BagMenu.mode = "list"
    end
    return
  end
  -- src/item_menu.c:1563 Task_WaitAB_RedrawAndReturnToBag
  if BagMenu.mode == "deposit_done" then
    if input:wasPressed("a") or input:wasPressed("b") then
      se(5)
      local p = BagMenu._depositPending
      BagMenu._depositPending = nil
      if p then Bag.remove(BagMenu._bag, p.id, p.qty) end
      BagMenu.mode = "list"
      clamp_cursor()
    end
    return
  end
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
      se(5) -- src/item_menu.c:1528
      BagMenu.mode = "toss_confirm"
      BagMenu.yesNoCursor = 1
    elseif input:wasPressed("b") then
      se(5) -- pokefirered/src/item_menu.c:1540
      BagMenu.mode = "list"
    end
    return
  end
  -- src/item_menu.c:1502 Task_ConfirmTossItems
  if BagMenu.mode == "toss_confirm" then
    if input:wasPressed("up") or input:wasPressed("down") then
      BagMenu.yesNoCursor = (BagMenu.yesNoCursor == 1) and 2 or 1
      se(5)
    elseif input:wasPressed("a") and BagMenu.yesNoCursor == 1 then
      se(5)
      BagMenu.mode = "toss_done"
    elseif input:wasPressed("a") or input:wasPressed("b") then
      se(5) -- src/item_menu.c:1511
      BagMenu.mode = "list"
    end
    return
  end
  -- src/item_menu.c:1563 Task_WaitAB_RedrawAndReturnToBag
  if BagMenu.mode == "toss_done" then
    if input:wasPressed("a") or input:wasPressed("b") then
      se(5)
      local row = BagMenu.list()[BagMenu.cursor]
      if row then
        Bag.remove(BagMenu._bag, row.id, BagMenu.tossQty)
      end
      BagMenu.mode = "list"
      clamp_cursor()
    end
    return
  end

  if BagMenu.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      se(5)
      local pages = BagMenu._msgPages
      -- pokefirered/src/text.c:796
      if pages and BagMenu._msgPage < #pages then
        BagMenu._msgPage = BagMenu._msgPage + 1
        BagMenu.messageText = pages[BagMenu._msgPage]
        return
      end
      BagMenu.mode = "list"
      BagMenu.messageText = nil
      BagMenu._msgPages = nil
      BagMenu._msgPage = 1
      clamp_cursor()
      -- pokefirered/src/item_menu.c:1018 DisplayItemMessageInBag followUpFunc
      local onDone = BagMenu._msgDone
      BagMenu._msgDone = nil
      if onDone then onDone() end
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
                BagMenu.commitBattlePartyUse(st, row.id, realSlot, mon)
              end,
              onClose = function()
                BagMenu.mode = "list"
                clamp_cursor()
              end,
            })
            return
          elseif BattleItems.isStatBooster(row.id) then
            local Battle = package.loaded["src.core.game3.battle"]
            local Ui = package.loaded["src.core.game3.battle.ui"]
            local st = Battle and Battle._st
            local battlerId = (st and st.double and Ui and Ui._active) or 0
            -- pokefirered/src/item_use.c:755 BattleUseFunc_StatBooster
            if not (st and BattleItems.statBoosterHasEffect(st, row.id, battlerId)) then
              show_bag_message(RomText.box("gText_WontHaveEffect"))
              return
            end
            BagMenu._statBoost = { frames = 0, st = st, itemId = row.id, battlerId = battlerId }
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
              BagMenu.messageText = RomText.plain("gText_ThereIsNoPokemon")
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
            local ok, kind, text = use_field_from_bag(BagMenu._session, BagMenu._bag, row.id)
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
            elseif ok and kind == "escape" then
              -- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback
              begin_exit(true, function()
                BagMenu.close()
                local StartMenu = package.loaded["src.ui.game3.start_menu"]
                if StartMenu and StartMenu.isOpen and StartMenu.isOpen() then
                  StartMenu.open = false
                  StartMenu._onClose = nil
                  Stack.pop("start")
                end
                field_fade_in()
                ItemUse.runOnFieldCallback()
              end)
              return
            elseif ok and FIELD_EXIT_FADE[kind] ~= nil then
              -- pokefirered/src/item_use.c:159
              local fade = FIELD_EXIT_FADE[kind]
              begin_exit(true, function()
                BagMenu.close()
                local StartMenu = package.loaded["src.ui.game3.start_menu"]
                if StartMenu and StartMenu.isOpen and StartMenu.isOpen() then
                  StartMenu.open = false
                  StartMenu._onClose = nil
                  Stack.pop("start")
                end
                if fade then field_fade_in() end
              end)
              return
            elseif ok and kind == "black_white_flute" then
              -- pokefirered/src/item_use.c:582
              BagMenu.mode = "flute_wait"
              BagMenu._fluteWait = { frames = 0, text = text }
            elseif ok and kind == "map" then
              -- pokefirered/src/item_use.c:649
              BagMenu.mode = "list"
              clamp_cursor()
            elseif text then
              -- pokefirered/src/item_use.c:186
              show_bag_message(text)
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
          -- src/item_menu.c:1635
          BagMenu.messageText = RomText.box("gText_ItemCantBeHeld",
            { stringVars = { ItemsData.displayName(row.id) } })
        elseif #party == 0 then
          BagMenu.mode = "message"
          BagMenu.messageText = RomText.plain("gText_ThereIsNoPokemon")
        else
          local PartyMenu = require("src.ui.game3.party_menu")
          local giveSource = BagMenu._location == "party" and ItemUse.partyGiveSource(BagMenu._bag) or nil
          -- src/item_menu.c:1620
          open_submenu(function()
            PartyMenu.show(party, BagMenu._session and BagMenu._session.moveOverlay, {
              session = BagMenu._session,
              bag = BagMenu._bag,
              item = row.id,
              mode = "give",
              giveSource = giveSource,
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
        -- src/item_menu.c:1491
        BagMenu.tossQty = 1
        BagMenu.yesNoCursor = 1
        BagMenu.mode = ((tonumber(row.qty) or 1) == 1) and "toss_confirm" or "toss"
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
      se(5) -- pokefirered/src/item_menu.c:1453
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
    elseif BagMenu._location == "shop" then
      begin_sell(rows[BagMenu.cursor])
    elseif BagMenu._location == "itempc" then
      begin_deposit(rows[BagMenu.cursor])
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

local NO_INPUT = { wasPressed = function() return false end }

local function press_input(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
end

-- pokefirered/include/constants/items.h:7
local ITEM_POKE_BALL = 4
local ITEM_ANTIDOTE = 14

BagMenu.POKEDUDE_PLANS = {
  -- pokefirered/src/item_menu.c:2262 Task_Bag_TeachyTvCatching
  catching = {
    { at = 102, key = "right" }, { at = 204, key = "right" },
    { at = 306, key = "down" }, { at = 408, key = "down" },
    { at = 510, key = "up" }, { at = 612, key = "up" },
    { at = 714, key = "a", item = ITEM_POKE_BALL },
    { at = 816, exit = true },
  },
  -- pokefirered/src/item_menu.c:2316 Task_Bag_TeachyTvStatus
  status = {
    { at = 102, key = "down" },
    { at = 204, key = "a", item = ITEM_ANTIDOTE },
    { at = 306, exit = true },
  },
}

local function finish_pokedude(itemId)
  local pd = BagMenu._pokedude
  if not pd then return end
  BagMenu._pokedude = nil
  BagMenu.close()
  -- pokefirered/src/item_menu.c:2089 RestorePlayerBag
  sessionState[pd.key] = pd.savedState
  for k, v in pairs(pd.view or {}) do BagMenu[k] = v end
  if itemId then
    if pd.onItem then pd.onItem(itemId) end
  elseif pd.onCancel then
    pd.onCancel()
  end
end

local function pokedude_tick(input)
  local pd = BagMenu._pokedude
  local inp = NO_INPUT
  if not (pd.done or BagMenu._open or BagMenu._exit) then
    if input and input.wasPressed and input:wasPressed("b") then
      -- pokefirered/src/item_menu.c:2192 Task_BButtonInterruptTeachyTv
      pd.done = true
      begin_exit(true, function() finish_pokedude(nil) end)
    else
      local entry = pd.plan[pd.index]
      if entry and pd.frames == entry.at then
        pd.index = pd.index + 1
        if entry.item then pd.item = entry.item end
        if entry.exit then
          se(SE_SELECT)
          BagMenu.mode = "list"
          pd.done = true
          -- pokefirered/src/item_menu.c:2309 Task_Pokedude_FadeFromBag
          begin_exit(true, function() finish_pokedude(pd.item) end)
        else
          inp = press_input(entry.key)
        end
      end
      pd.frames = pd.frames + 1
    end
  end
  track_held(inp)
  if not run_transitions(inp) then
    handle_menu_input(inp)
  end
  animate_sprites()
end

function BagMenu.isPokedude()
  return BagMenu._pokedude ~= nil
end

-- pokefirered/src/item_menu.c:2162 InitPokedudeBag
function BagMenu.showPokedude(sessionBag, opts)
  opts = opts or {}
  local plan = BagMenu.POKEDUDE_PLANS[opts.plan]
  if not plan then error("no pokedude bag plan " .. tostring(opts.plan)) end
  local key = opts.session or sessionBag
  local saved = sessionState[key]
  -- pokefirered/src/item_menu.c:2069 sBackupPlayerBag->pocket = gBagMenuState.pocket
  local view = {}
  for _, k in ipairs({ "pocketIdx", "cursor", "scroll", "mode", "actionCursor", "ACTIONS",
    "_bag", "_session", "_battle", "_location", "_onClose", "_onBattleUse" }) do
    view[k] = BagMenu[k]
  end
  -- pokefirered/src/item_menu.c:2079 ResetBagCursorPositions
  sessionState[key] = { pocket = 1, pos = {} }
  BagMenu.show(sessionBag, { session = opts.session, battle = true, pocket = "ITEMS" })
  BagMenu._pokedude = {
    plan = plan, index = 1, frames = 0, key = key, savedState = saved, view = view,
    onItem = opts.onItem, onCancel = opts.onCancel,
  }
end

-- pokefirered/src/item_use.c:766 Task_BattleUse_StatBooster_DelayAndPrint
local function stat_boost_tick()
  local sb = BagMenu._statBoost
  sb.frames = sb.frames + 1
  if sb.frames <= 7 then return end
  BagMenu._statBoost = nil
  local BattleItems = require("src.core.game3.battle.items")
  se(SE_USE_ITEM)
  local _, _, _, _, text = BattleItems.use(sb.st, QUIET_ADAPTER, BagMenu._bag, BagMenu._session,
    sb.itemId, nil, sb.battlerId)
  -- pokefirered/src/item_use.c:779 Task_BattleUse_StatBooster_WaitButton_ReturnToBattle
  show_bag_message(text or "", function()
    BagMenu.battleUse(sb.itemId, nil, nil, true)
  end)
end

function BagMenu.handleInput(input)
  if BagMenu._battle then
    local top = Stack.top()
    if top and top.mod ~= BagMenu and top.mod and top.mod.handleInput then
      return top.mod.handleInput(input)
    end
  end
  if BagMenu._pokedude then return pokedude_tick(input) end
  if BagMenu._statBoost then return stat_boost_tick() end
  track_held(input)
  if not run_transitions(input) then
    handle_menu_input(input)
  end
  animate_sprites()
end

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
    BagChrome.drawBg(0, 0, { female = female, itemPc = BagMenu._location == "itempc" })
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

  if BagMenu._location == "itempc" then
    -- src/bag.c:232 BagDrawDepositItemTextBox
    Window.fixedStdFrame(Window.template(1, 1, 8, 2))
    local dLabel = RomText.plain("gText_DepositItem")
    FrlgFont.draw(dLabel, 8 + math.floor((64 - FrlgFont.measure(dLabel, { small = true })) / 2), 8 + 1,
      { small = true, colors = FrlgFont.COLOR.NORMAL })
  elseif not switching then
    -- src/bag.c:226
    local pLabel = ItemsData.POCKET_LABEL[pocket]
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
        -- src/item_menu.c:645
        FrlgFont.draw(RomText.plain("gFameCheckerText_Cancel"), 97, y, { colors = FrlgFont.COLOR.NORMAL })
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
    local switchArrows = BagMenu._location ~= "itempc"
    if switchArrows and BagMenu.pocketIdx > 1 then
      BagChrome.drawArrow("left", 0 + bob(k, 8), 64)
    end
    if switchArrows and BagMenu.pocketIdx < #ItemsData.BAG_POCKET_ORDER then
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

  if BagMenu.mode ~= "action" and BagMenu.mode ~= "deposit" and BagMenu.mode ~= "deposit_done" and not switching then
    if not chrome then
      Window.stdFrame(Window.template(5, 14, 25, 6))
    end
    local desc = sel and sel.description
    -- src/item_menu.c:754
    if not sel then desc = RomText.plain("gText_CloseBag") end
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
      -- src/item_menu.c:1434
      FrlgFont.draw(RomText.box("gText_Var1IsSelected", { stringVars = { sel.name } }), 6 * 8 + 4, 15 * 8 + 2, { maxWidth = 14 * 8, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
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
      FrlgFont.draw(action_label(act, sel), popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  end

  local text_opts = { linePitch = 15, colors = FrlgFont.COLOR.NORMAL }
  -- src/item_menu.c:1308 InitQuantityToTossOrDeposit
  if BagMenu.mode == "toss" and sel then
    Window.stdFrame(Window.template(6, 15, 16, 4))
    FrlgFont.draw(RomText.box("gText_TossOutHowManyStrVar1s", { stringVars = { sel.name } }), 6 * 8, 15 * 8 + 2, text_opts)
    Window.stdFrame(Window.template(24, 15, 5, 4))
    -- src/item_menu.c:1326
    local times = RomText.plain("gText_TimesStrVar1", { stringVars = { string.format("%03d", BagMenu.tossQty) } })
    FrlgFont.draw(times, 24 * 8 + 4, 15 * 8 + 10, { small = true, colors = FrlgFont.COLOR.NORMAL })
  end
  -- src/item_menu.c:1502 Task_ConfirmTossItems
  if BagMenu.mode == "toss_confirm" and sel then
    Window.stdFrame(Window.template(6, 15, 15, 4))
    FrlgFont.draw(RomText.box("gText_ThrowAwayStrVar2OfThisItemQM",
      { stringVars = { [2] = tostring(BagMenu.tossQty) } }), 6 * 8, 15 * 8 + 2, text_opts)
    -- src/bag.c:296 BagCreateYesNoMenuBottomRight
    Window.stdFrame(Window.template(23, 15, 6, 4))
    FrlgFont.draw(RomText.plain("gText_Yes"), 23 * 8 + 8, 15 * 8 + 2, text_opts)
    FrlgFont.draw(RomText.plain("gText_No"), 23 * 8 + 8, 15 * 8 + 18, text_opts)
    Window.cursorPx(23 * 8, 15 * 8 + 2 + (BagMenu.yesNoCursor == 2 and 16 or 0))
  end
  -- src/item_menu.c:1308 InitQuantityToTossOrDeposit
  if BagMenu.mode == "deposit" and sel then
    Window.fixedStdFrame(Window.template(6, 15, 16, 4))
    FrlgFont.draw(RomText.box("gText_DepositHowManyStrVars1", { stringVars = { sel.name } }), 6 * 8, 15 * 8 + 2, text_opts)
    Window.stdFrame(Window.template(24, 15, 5, 4))
    FrlgFont.draw(RomText.plain("gText_TimesStrVar1", { stringVars = { string.format("%03d", BagMenu.tossQty) } }),
      24 * 8 + 4, 15 * 8 + 10, { small = true, letterSpacing = 1, colors = FrlgFont.COLOR.NORMAL })
    -- src/item_menu.c:796 CreateArrowPair_QuantitySelect
    local okB, BagChromeQ = pcall(require, "src.ui.game3.bag_chrome")
    if okB and BagChromeQ then
      local k = BagMenu._depositK or 0
      BagChromeQ.drawArrow("up", 212 - 8, 120 - 8 + bob(k + 1, 8))
      BagChromeQ.drawArrow("down", 212 - 8, 152 - 8 + bob(k + 1, -8))
    end
  end
  -- src/item_menu.c:2012
  if BagMenu.mode == "deposit_done" and BagMenu._depositText then
    Window.fixedStdFrame(Window.template(6, 15, 23, 4))
    FrlgFont.draw(BagMenu._depositText, 6 * 8, 15 * 8 + 2, text_opts)
  end
  -- src/item_menu.c:1552 Task_TossItem_Yes
  if BagMenu.mode == "toss_done" and sel then
    Window.stdFrame(Window.template(6, 15, 23, 4))
    FrlgFont.draw(RomText.box("gText_ThrewAwayStrVar2StrVar1s",
      { stringVars = { sel.name, tostring(BagMenu.tossQty) } }), 6 * 8, 15 * 8 + 2, text_opts)
  end

  -- In-bag message modal
  -- src/item_menu.c:1021 OpenBagWindow(5), src/menu_helpers.c:24
  if BagMenu.mode == "message" and BagMenu.messageText then
    local Chrome = require("src.ui.game3.chrome")
    Window.dialogueFrame()
    local w = Chrome.DLG_W * 8
    FrlgFont.draw(FrlgFont.wrap(BagMenu.messageText, w), Chrome.DLG_LEFT * 8, Chrome.DLG_TOP * 8 + 1,
      { maxWidth = w, colors = FrlgFont.COLOR.NORMAL })
  end

  if BagMenu.mode == "sell" and BagMenu._sell then
    BagMenu._sell:draw()
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
