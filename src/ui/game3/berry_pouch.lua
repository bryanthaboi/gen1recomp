-- FRLG Berry Pouch UI 1:1 with pokefirered (berry_pouch.c).
--
-- Window Layouts (pokefirered/src/berry_pouch.c):
--   WIN_LIST:        tilemapLeft=11, tilemapTop=1,  width=18, height=14 -> (88, 8, 144, 112), 7 visible rows, pitch=16
--   WIN_DESCRIPTION: tilemapLeft=5,  tilemapTop=16, width=25, height=4  -> (40, 128, 200, 32), text at (40, 130)
--   WIN_HEADER:      tilemapLeft=1,  tilemapTop=1,  width=9,  height=2  -> (8, 8, 72, 16), text centered at (tx, 9)
--   WIN_SELECTED:    tilemapLeft=6,  tilemapTop=15, width=14, height=4  -> (48, 120, 112, 32)
--   WIN_CONTEXT:     tilemapLeft=22, tilemapTop=11, width=7,  height=8  -> (176, 88, 56, 64)
--   WIN_TOSS_LABEL:  tilemapLeft=6,  tilemapTop=15, width=16, height=4  -> (48, 120, 128, 32)
--   WIN_TOSS_QTY:    tilemapLeft=24, tilemapTop=15, width=5,  height=4  -> (192, 120, 40, 32)
--   WIN_TOSS_PROMPT: tilemapLeft=6,  tilemapTop=15, width=15, height=4  -> (48, 120, 120, 32)
--   WIN_YES_NO:      tilemapLeft=23, tilemapTop=15, width=6,  height=4  -> (184, 120, 48, 32)
--   WIN_MSG:         tilemapLeft=2,  tilemapTop=15, width=26, height=4  -> (16, 120, 208, 32)
--
-- Sprites:
--   Berry Pouch Sprite: 64x64 centered at (40, 76) -> top-left (8, 44), wobbles on open and cursor move.
--   Item Icon Sprite:   24x24 centered in 32x32 at (24, 147) -> top-left (12, 135).

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")
local PartyView = require("src.core.game3.battle.party_view")
local Strings = require("src.core.Strings")

local BerryPouch = {}

BerryPouch.open = false
BerryPouch.cursor = 1
BerryPouch.scroll = 0
BerryPouch.mode = "list" -- "list" | "action" | "toss_select" | "toss_confirm" | "message"
BerryPouch.actionCursor = 1
BerryPouch.yesNoCursor = 1
BerryPouch.tossQty = 1
BerryPouch.messageText = nil
BerryPouch.wobbleTimer = 0

local VISIBLE = 7
local ACTIONS = { "USE", "GIVE", "TOSS", "EXIT" }

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

function BerryPouch.isOpen()
  return BerryPouch.open
end

function BerryPouch.list()
  local bag = BerryPouch._bag
  if not bag then return {} end
  local rows = Bag.listPocket(bag, "BERRY_POUCH")
  return rows or {}
end

local function clamp_cursor()
  local rows = BerryPouch.list()
  local total = #rows + 1 -- berries + CLOSE option
  if total < 1 then total = 1 end

  if BerryPouch.cursor > total then BerryPouch.cursor = total end
  if BerryPouch.cursor < 1 then BerryPouch.cursor = 1 end

  if BerryPouch.cursor <= BerryPouch.scroll then
    BerryPouch.scroll = BerryPouch.cursor - 1
  end
  if BerryPouch.cursor > BerryPouch.scroll + VISIBLE then
    BerryPouch.scroll = BerryPouch.cursor - VISIBLE
  end
  if BerryPouch.scroll < 0 then BerryPouch.scroll = 0 end
  local maxScroll = math.max(0, total - VISIBLE)
  if BerryPouch.scroll > maxScroll then BerryPouch.scroll = maxScroll end

  return rows, total
end

-- Party-menu options for using/giving the selected berry.
--
-- In battle this has to go through the battle system: ItemUse.useField, which
-- the party menu falls back to, only knows session.party, and that snapshot is
-- not written back until the battle ends.  A berry used there would be eaten
-- with no effect on the live battler, so hand it to BagMenu instead - the same
-- route a potion takes from the bag.
local function party_opts(row, mode, party)
  local opts = {
    session = BerryPouch._session,
    bag = BerryPouch._bag,
    item = row.id,
    mode = mode,
    onClose = function()
      BerryPouch.mode = "list"
      clamp_cursor()
    end,
  }
  if mode ~= "use" then return opts end

  local BagMenu = require("src.ui.game3.bag_menu")
  local Battle = package.loaded["src.core.game3.battle"]
  local st = Battle and Battle._st
  local BattleItems = require("src.core.game3.battle.items")
  if not (st and st.playerParty and BagMenu._battle and BagMenu._onBattleUse
          and BattleItems.needsPartySelect(row.id)) then
    return opts
  end

  local PartyMenu = require("src.ui.game3.party_menu")
  opts.battle = true
  opts.battleOrder = PartyMenu.battleOrder(st)
  opts.layout = st.double and "double" or nil
  opts.onSelect = function(slot)
    if not slot or slot == 7 then
      PartyMenu.close()
      return
    end
    local mon = party[slot]
    local canUse, err = BattleItems.canUseOn(st, row.id, slot, mon)
    if not canUse then
      se(5) -- pokefirered/src/party_menu.c:4490
      PartyMenu.showMessage(err or Strings("It won't have any effect."), function()
        PartyMenu.mode = "use"
      end)
      return
    end
    PartyMenu.close()
    BerryPouch.close()
    BagMenu.battleUse(row.id, slot)
  end
  return opts
end

function BerryPouch.show(session, bag, opts)
  opts = opts or {}
  BerryPouch.open = true
  BerryPouch._session = session or opts.session
  BerryPouch._bag = bag or opts.bag or (session and session.bag)
  BerryPouch._onClose = opts.onClose
  BerryPouch.cursor = opts.cursor or 1
  BerryPouch.scroll = opts.scroll or 0
  BerryPouch.mode = "list"
  BerryPouch.actionCursor = 1
  BerryPouch.yesNoCursor = 1
  BerryPouch.tossQty = 1
  BerryPouch.messageText = nil
  BerryPouch.wobbleTimer = 0.25 -- Authentically trigger affine wobble on open
  clamp_cursor()
  Stack.push("berry_pouch", BerryPouch, { hideBelow = true })
end

function BerryPouch.close()
  BerryPouch.open = false
  Stack.pop("berry_pouch")
  local cb = BerryPouch._onClose
  BerryPouch._onClose = nil
  if cb then cb() end
end

function BerryPouch.update(dt)
  if BerryPouch.wobbleTimer > 0 then
    BerryPouch.wobbleTimer = math.max(0, BerryPouch.wobbleTimer - (dt or 0.016))
  end
end

function BerryPouch.handleInput(input)
  local rows, total = clamp_cursor()
  local row = rows[BerryPouch.cursor]

  -- 1. Toss Quantity Select Mode (Task_Toss_SelectMultiple)
  if BerryPouch.mode == "toss_select" then
    local maxQ = row and (tonumber(row.qty) or 1) or 1
    if input:wasPressed("up") or input:wasPressed("right") then
      if BerryPouch.tossQty < maxQ then
        BerryPouch.tossQty = BerryPouch.tossQty + 1
      else
        BerryPouch.tossQty = 1 -- wrap around to 1
      end
      se(5)
    elseif input:wasPressed("down") or input:wasPressed("left") then
      if BerryPouch.tossQty > 1 then
        BerryPouch.tossQty = BerryPouch.tossQty - 1
      else
        BerryPouch.tossQty = maxQ -- wrap around to max
      end
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      BerryPouch.mode = "toss_confirm"
      BerryPouch.yesNoCursor = 1
    elseif input:wasPressed("b") then
      se(5) -- pokefirered/src/berry_pouch.c:1142
      BerryPouch.mode = "list"
    end
    return
  end

  -- 2. Toss Confirmation Mode (Task_AskTossMultiple & CreateYesNoMenuWin3)
  if BerryPouch.mode == "toss_confirm" then
    if input:wasPressed("up") or input:wasPressed("down") then
      BerryPouch.yesNoCursor = (BerryPouch.yesNoCursor == 1) and 2 or 1
      se(5)
    elseif input:wasPressed("b") then
      se(5) -- pokefirered/src/menu_helpers.c:57
      BerryPouch.mode = "list"
    elseif input:wasPressed("a") then
      if BerryPouch.yesNoCursor == 1 then
        -- YES: Toss items
        se(5)
        if row then
          local bName = row.name or ItemsData.displayName(row.id)
          Bag.remove(BerryPouch._bag, row.id, BerryPouch.tossQty)
          BerryPouch.mode = "message"
          BerryPouch.messageText = Strings("Threw away %d\n%s.", BerryPouch.tossQty, bName)
          clamp_cursor()
        else
          BerryPouch.mode = "list"
        end
      else
        -- NO: Cancel toss
        se(5) -- pokefirered/src/menu_helpers.c:57
        BerryPouch.mode = "list"
      end
    end
    return
  end

  -- 3. Message Mode
  if BerryPouch.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      se(5)
      BerryPouch.mode = "list"
      BerryPouch.messageText = nil
      clamp_cursor()
    end
    return
  end

  -- 4. Context Action Menu Mode (Task_NormalContextMenu)
  if BerryPouch.mode == "action" then
    if input:wasPressed("up") then
      BerryPouch.actionCursor = ((BerryPouch.actionCursor - 2) % #ACTIONS) + 1
      se(5)
    elseif input:wasPressed("down") then
      BerryPouch.actionCursor = (BerryPouch.actionCursor % #ACTIONS) + 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      local act = ACTIONS[BerryPouch.actionCursor]
      local party = PartyView.live(BerryPouch._session)
      if act == "EXIT" or not row then
        BerryPouch.mode = "list"
      elseif act == "USE" then
        if ItemUse.needsPartyTarget(row.id) then
          if #party == 0 then
            BerryPouch.mode = "message"
            BerryPouch.messageText = Strings("There is no POKéMON.")
          else
            local PartyMenu = require("src.ui.game3.party_menu")
            PartyMenu.show(party, BerryPouch._session and BerryPouch._session.moveOverlay,
              party_opts(row, "use", party))
          end
        else
          BerryPouch.mode = "message"
          BerryPouch.messageText = Strings("OAK: This isn't the\ntime to use that!")
        end
      elseif act == "GIVE" then
        if #party == 0 then
          BerryPouch.mode = "message"
          BerryPouch.messageText = Strings("There is no POKéMON.")
        else
          local PartyMenu = require("src.ui.game3.party_menu")
          PartyMenu.show(party, BerryPouch._session and BerryPouch._session.moveOverlay, {
            session = BerryPouch._session,
            bag = BerryPouch._bag,
            item = row.id,
            mode = "give",
            onClose = function()
              BerryPouch.mode = "list"
              clamp_cursor()
            end,
          })
        end
      elseif act == "TOSS" then
        local maxQ = row and (tonumber(row.qty) or 1) or 1
        if maxQ == 1 then
          BerryPouch.tossQty = 1
          BerryPouch.mode = "toss_confirm"
          BerryPouch.yesNoCursor = 1
        else
          BerryPouch.tossQty = 1
          BerryPouch.mode = "toss_select"
        end
      end
    elseif input:wasPressed("b") then
      se(5) -- pokefirered/src/berry_pouch.c:1052
      BerryPouch.mode = "list"
    end
    return
  end

  -- 5. List Navigation Mode (Task_BerryPouchMain)
  if input:wasPressed("up") then
    if total > 0 then
      BerryPouch.cursor = ((BerryPouch.cursor - 2) % total) + 1
      BerryPouch.wobbleTimer = 0.25
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("down") then
    if total > 0 then
      BerryPouch.cursor = (BerryPouch.cursor % total) + 1
      BerryPouch.wobbleTimer = 0.25
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("left") or input:wasPressed("l") then
    if total > 0 then
      BerryPouch.cursor = math.max(1, BerryPouch.cursor - VISIBLE)
      BerryPouch.wobbleTimer = 0.25
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("right") or input:wasPressed("r") then
    if total > 0 then
      BerryPouch.cursor = math.min(total, BerryPouch.cursor + VISIBLE)
      BerryPouch.wobbleTimer = 0.25
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("a") then
    if BerryPouch.cursor == total then
      -- CLOSE option selected
      se(5) -- pokefirered/src/berry_pouch.c:963
      BerryPouch.close()
    elseif row then
      -- Berry selected
      BerryPouch.mode = "action"
      BerryPouch.actionCursor = 1
      se(5)
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    se(5) -- pokefirered/src/berry_pouch.c:957
    BerryPouch.close()
  end
end

function BerryPouch.draw()
  if not BerryPouch.open then return end
  local rows, total = clamp_cursor()
  local sel = rows[BerryPouch.cursor]

  local okC, BerryPouchChrome = pcall(require, "src.ui.game3.berry_pouch_chrome")
  local hasChrome = okC and BerryPouchChrome and BerryPouchChrome.ready and BerryPouchChrome.ready()
  local isFemale = false
  local session = BerryPouch._session
  if session and (session.gender == 1 or session.gender == "female" or session.playerGender == 1) then
    isFemale = true
  end

  -- 1. Background (BG 1)
  if hasChrome then
    BerryPouchChrome.drawBg(0, 0, { female = isFemale })
  else
    -- Fallback Background (Berry Pouch Green/Teal Theme)
    love.graphics.setColor(0.18, 0.48, 0.35, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)

    -- Header Frame
    Window.stdFrame(Window.template(1, 1, 9, 2))
    -- List Menu Frame
    Window.stdFrame(Window.template(11, 1, 18, 14))
    -- Description Frame
    Window.stdFrame(Window.template(5, 16, 25, 4))
  end

  -- 2. Header (WIN 2: tilemapLeft=1, tilemapTop=1, width=9, height=2 -> 72px center at y=9)
  local headerTitle = Strings("BERRY POUCH")
  local tw = FrlgFont.measure(headerTitle)
  local tx = math.floor((72 - tw) / 2) + 8
  FrlgFont.draw(headerTitle, tx, 9, { colors = FrlgFont.COLOR.LIGHT })

  -- 3. Berry Pouch Sprite (64x64 centered at (40, 72) -> top-left at (8, 40))
  local wobbleAngle = 0
  if BerryPouch.wobbleTimer > 0 then
    -- 1:1 affine wobble oscillation (-2..+2 deltas)
    wobbleAngle = math.sin((BerryPouch.wobbleTimer / 0.25) * math.pi * 4) * 0.08
  end
  if hasChrome then
    BerryPouchChrome.drawPouch(8, 40, wobbleAngle)
  end

  -- 4. Item Icon Sprite (24x24 centered in 27x27 white box at (20, 143) -> top-left at (8, 131))
  if sel and BerryPouch.cursor <= #rows then
    local okB, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
    if okB and BagChrome and BagChrome.drawItemIcon then
      BagChrome.drawItemIcon(sel.id, 8, 131)
    end
  end

  -- 5. Description Box (WIN 1: tilemapLeft=5, tilemapTop=16, width=25, height=4 -> screen (40, 128, 200, 32))
  if BerryPouch.cursor == total then
    local closeDesc = Strings("The BERRY POUCH will be\nput away.")
    FrlgFont.draw(closeDesc, 40, 130, { colors = FrlgFont.COLOR.LIGHT, linePitch = 14 })
  elseif sel then
    local desc = sel.description or ItemsData.description(sel.id) or ""
    FrlgFont.draw(desc, 40, 130, { colors = FrlgFont.COLOR.LIGHT, linePitch = 14 })
  end

  -- 6. List Menu (WIN 0: tilemapLeft=11, tilemapTop=1, width=18, height=14 -> 7 visible rows, pitch=16)
  if BerryPouch.scroll > 0 then
    FrlgFont.draw("▲", 160, 8, { colors = FrlgFont.COLOR.DARK_GRAY })
  end
  if BerryPouch.scroll + VISIBLE < total then
    FrlgFont.draw("▼", 160, 120, { colors = FrlgFont.COLOR.DARK_GRAY })
  end

  for i = 1, VISIBLE do
    local idx = BerryPouch.scroll + i
    if idx > total then break end
    local y = 10 + (i - 1) * 16

    -- Selector Arrow at x = 89
    if idx == BerryPouch.cursor and BerryPouch.mode == "list" then
      Window.cursorPx(89, y)
    end

    if idx <= #rows then
      local r = rows[idx]
      local berryNum = ItemsData.berryNumber(r.id) or idx
      -- №xx in FONT_SMALL at x = 97
      local noStr = string.format("№%02d", berryNum)
      FrlgFont.draw(noStr, 97, y, { small = true, colors = FrlgFont.COLOR.NORMAL })

      -- Berry Name in FONT_NORMAL at x = 121 (spaced after №xx)
      local bName = r.name or ItemsData.displayName(r.id)
      FrlgFont.draw(bName, 121, y, { colors = FrlgFont.COLOR.NORMAL })

      -- Quantity ×%3d in FONT_SMALL at x = 198
      local qStr = string.format("×%3d", r.qty or 1)
      FrlgFont.draw(qStr, 198, y, { small = true, colors = FrlgFont.COLOR.NORMAL })
    else
      -- CLOSE option in FONT_NORMAL at x = 97
      FrlgFont.draw(Strings("CLOSE"), 97, y, { colors = FrlgFont.COLOR.NORMAL })
    end
  end

  -- 7. Context Menu (WIN 13: 22, 11, 7, 8) + Selected Message (WIN 6: 6, 15, 14, 4)
  if BerryPouch.mode == "action" and sel then
    local bName = sel.name or ItemsData.displayName(sel.id)

    -- WIN 6: Selected message
    Window.stdFrame(Window.template(6, 15, 14, 4))
    local selMsg = Strings("%s is\nselected.", bName)
    FrlgFont.draw(selMsg, 52, 124, { colors = FrlgFont.COLOR.NORMAL, linePitch = 14 })

    -- WIN 13: Action menu
    Window.stdFrame(Window.template(22, 11, 7, 8))
    for i, act in ipairs(ACTIONS) do
      local rowY = 90 + (i - 1) * 16
      if i == BerryPouch.actionCursor then
        Window.cursorPx(177, rowY)
      end
      FrlgFont.draw(Strings(act), 185, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  end

  -- 8. Toss Quantity Select UI (WIN 8: 6, 15, 16, 4 + WIN 0: 24, 15, 5, 4)
  if BerryPouch.mode == "toss_select" and sel then
    local bName = sel.name or ItemsData.displayName(sel.id)

    -- WIN 8: Prompt
    Window.stdFrame(Window.template(6, 15, 16, 4))
    local tossMsg = Strings("Toss out how many\n%s?", bName)
    FrlgFont.draw(tossMsg, 52, 122, { colors = FrlgFont.COLOR.NORMAL, linePitch = 14 })

    -- WIN 0: Quantity with arrows
    Window.stdFrame(Window.template(24, 15, 5, 4))
    local qStr = string.format("×%02d", BerryPouch.tossQty)
    FrlgFont.draw(qStr, 196, 130, { small = true, colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw("▲", 212, 122, { colors = FrlgFont.COLOR.DARK_GRAY })
    FrlgFont.draw("▼", 212, 144, { colors = FrlgFont.COLOR.DARK_GRAY })
  end

  -- 9. Toss Confirmation Modal (WIN 7: 6, 15, 15, 4 + WIN 3: 23, 15, 6, 4)
  if BerryPouch.mode == "toss_confirm" and sel then
    -- WIN 7: Confirmation prompt
    Window.stdFrame(Window.template(6, 15, 15, 4))
    local confMsg = Strings("Throw away %d of\nthis item?", BerryPouch.tossQty)
    FrlgFont.draw(confMsg, 52, 124, { colors = FrlgFont.COLOR.NORMAL, linePitch = 14 })

    -- WIN 3: YES / NO
    Window.stdFrame(Window.template(23, 15, 6, 4))
    local yesY = 124
    local noY = 140
    if BerryPouch.yesNoCursor == 1 then
      Window.cursorPx(185, yesY)
    else
      Window.cursorPx(185, noY)
    end
    FrlgFont.draw(Strings("YES"), 193, yesY, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(Strings("NO"), 193, noY, { colors = FrlgFont.COLOR.NORMAL })
  end

  -- 10. Dialogue Message Modal (WIN 5: 2, 15, 26, 4)
  if BerryPouch.mode == "message" and BerryPouch.messageText then
    Window.stdFrame(Window.template(2, 15, 26, 4))
    FrlgFont.draw(BerryPouch.messageText, 20, 124, { colors = FrlgFont.COLOR.NORMAL, linePitch = 14 })
  end
end

return BerryPouch
