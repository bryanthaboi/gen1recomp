local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local RomText = require("src.core.game3.rom_text")
local ItemsData = require("src.core.game3.items_data")
local Gfx = require("src.ui.game3.rse.pokeblock_gfx")

local PBag = { isMenu = true }

PBag.ID = "rse_pyramid_bag"
PBag.open = false

-- pokeemerald/src/battle_pyramid_bag.c:208
PBag.WIN_LIST = { 14, 2, 15, 16 }
PBag.WIN_INFO = { 0, 13, 14, 6 }
-- pokeemerald/src/battle_pyramid_bag.c:257
PBag.MENU_WIN = { { 22, 17, 7, 2 }, { 22, 15, 7, 4 }, { 15, 15, 14, 4 } }
PBag.YESNO_WIN = { 24, 15, 5, 4 }
PBag.TOSS_WIN = { 24, 17, 5, 2 }
-- pokeemerald/src/battle_pyramid_bag.c:184
PBag.ACTIONS = {
  field = { "USE_FIELD", "GIVE", "TOSS", "CANCEL" },
  party = { "USE_FIELD", "GIVE", "TOSS", "CANCEL" },
  choose_toss = { "TOSS", "CANCEL" },
  battle = { "USE_BATTLE", "CANCEL" },
  battle_cannot = { "CANCEL" },
}
PBag.ACTION_TEXT = {
  USE_FIELD = "gMenuText_Use", TOSS = "gMenuText_Toss", GIVE = "gMenuText_Give", CANCEL = "gText_Cancel2",
  USE_BATTLE = "gMenuText_Use",
}
-- pokeemerald/include/battle_pyramid_bag.h:9
PBag.LOCATION = { field = 0, battle = 1, party = 2, choose_toss = 3 }
-- pokeemerald/src/battle_pyramid_bag.c:1550
PBag.SPRITE_X, PBag.SPRITE_Y = 68, 56
-- pokeemerald/src/battle_pyramid_bag.c:340
PBag.SHAKE = { { -2, 2 }, { 2, 4 }, { -2, 4 }, { 2, 2 } }
PBag.MAX_SHOWN = 8

local st = {}
PBag._st = st

-- pokeemerald/src/battle_pyramid_bag.c:201
local LIGHT_GRAY = { fg = FrlgFont.STDPAL[3], shadow = FrlgFont.STDPAL[1], bg = FrlgFont.STDPAL[0] }

local function Py() return require("src.core.game3.rse.frontier.pyramid") end
local function gfx() return Gfx.of("rse/pyramid") end

local function se(name)
  pcall(function() require("src.core.game3.audio").playSe(name) end)
end

local function session()
  if st.session then return st.session end
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function lists()
  return Py().bagLists(session())
end

-- pokeemerald/src/battle_pyramid_bag.c:792
function PBag.refresh()
  Py().compactBag(session())
  local items = lists()
  local n = 0
  for i = 1, Py().BAG_ITEMS_COUNT do
    if items[i] ~= 0 then n = n + 1 end
  end
  st.count = n + 1
  st.maxShown = math.min(PBag.MAX_SHOWN, st.count)
  local cur = Py().bagCursor or { cursor = 0, scroll = 0 }
  if cur.scroll ~= 0 and cur.scroll + st.maxShown > st.count then cur.scroll = st.count - st.maxShown end
  if cur.scroll + cur.cursor >= st.count then cur.cursor = math.max(0, st.count - 1 - cur.scroll) end
  Py().bagCursor = cur
end

local function pos()
  local c = Py().bagCursor
  return c.scroll + c.cursor
end

local function selectedItem()
  local items, qty = lists()
  local p = pos()
  if p >= st.count - 1 then return nil end
  return items[p + 1], qty[p + 1], p + 1
end
PBag.selectedItem = selectedItem

local function itemName(id)
  local pocket = ItemsData.pocketOf(id)
  if pocket == "BERRY_POUCH" then
    return RomText.plain("gText_NumberItem_TMBerry", { stringVars = { string.format("%02d", ItemsData.berryNumber(id) or 0),
      ItemsData.displayName(id) } })
  end
  return ItemsData.displayName(id)
end

-- pokeemerald/src/battle_pyramid_bag.c:379
-- pokeemerald/src/battle_pyramid_bag.c:687
function PBag.returnTo(location)
  local ret = Py().manifest().bagReturnTo[(PBag.LOCATION[location] or 0) + 1]
  return ret and require("src.core.game3.scripting.text_ir").toPlain(RomText.refIr(ret), {}) or ""
end

function PBag.show(opts)
  opts = opts or {}
  for k in pairs(st) do st[k] = nil end
  st.session = opts.session
  st.location = opts.location or "field"
  st.returnTo = PBag.returnTo(st.location)
  st.onClose = opts.onClose
  st.onUse = opts.onUse
  st.onGive = opts.onGive
  Py().bagCursor = Py().bagCursor or { cursor = 0, scroll = 0 }
  PBag.refresh()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.clear then Fade.clear() end
  st.mode = "list"
  st.fade, st.fadeDir = 16, -1
  st.frame = 0
  st.shake = nil
  st.menuCursor = 1
  st.info = nil
  PBag.open = true
  Stack.push(PBag.ID, PBag, { hideBelow = true, fullscreen = true })
  return true
end

function PBag.isOpen() return PBag.open end

-- pokeemerald/src/battle_pyramid_bag.c:856
function PBag.close(after)
  st.closeAfter = after
  st.fadeDir = 1
  st.mode = "closing"
end

local function finish()
  PBag.open = false
  Stack.pop(PBag.ID)
  local after = st.closeAfter
  local cb = st.onClose
  st.closeAfter = nil
  if after then after() end
  if cb then cb() end
end

function PBag.reset()
  PBag.open = false
  Stack.pop(PBag.ID)
  for k in pairs(st) do st[k] = nil end
end

local function startShake()
  st.shake = 1
  st.shakeT = 0
end

local function actionsFor()
  local loc = st.location
  if loc == "battle" then
    local item = selectedItem()
    local info = item and ItemsData.info(item)
    if info and (tonumber(info.battleUsage) or 0) ~= 0 then return PBag.ACTIONS.battle end
    return PBag.ACTIONS.battle_cannot
  end
  return PBag.ACTIONS[loc] or PBag.ACTIONS.field
end

local function message(text, after)
  st.message = text
  st.messageAfter = after
  st.mode = "message"
end

-- pokeemerald/src/battle_pyramid_bag.c:1245
local function tempBag(item, qty)
  local Bag = require("src.core.game3.bag")
  local b = Bag.new()
  Bag.add(b, item, qty)
  return b, Bag
end

local function applyDelta(view, Bag, before)
  local sess = session()
  local seen = {}
  for id, n in pairs(before) do
    seen[id] = true
    local now = Bag.get(view, id)
    if now < n then Py().bagRemove(sess, id, n - now, nil) end
    if now > n then Py().bagAdd(sess, id, now - n) end
  end
  for _, pocket in pairs(view.pockets or {}) do
    for _, slot in ipairs(pocket) do
      local id = ItemsData.toNumericId(slot.id) or slot.id
      if not seen[id] and (tonumber(slot.qty) or 0) > 0 then Py().bagAdd(sess, id, slot.qty) end
    end
  end
end

local function openParty(mode, item, qty)
  local PartyMenu = require("src.ui.game3.party_menu")
  local view, Bag = tempBag(item, qty)
  local before = { [item] = qty }
  local sess = session()
  st.suspended = true
  PartyMenu.show(sess.party, sess.moveOverlay, {
    session = sess, bag = view, item = item, mode = mode,
    onClose = function()
      applyDelta(view, Bag, before)
      st.suspended = false
      PBag.refresh()
      st.mode = "list"
    end,
  })
end

-- pokeemerald/src/battle_pyramid_bag.c:1085
local function useOnField(item)
  local pocket = ItemsData.pocketOf(item)
  local info = ItemsData.info(item) or {}
  if pocket == "KEY_ITEMS" or pocket == "POKE_BALLS" or pocket == "TM_CASE" or ItemsData.isMail and ItemsData.isMail(item) then
    return message(RomText.plain("gText_DadsAdvice", { playerName = session() and session().name }), function() st.mode = "list" end)
  end
  local ItemUse = require("src.core.game3.item_use")
  if ItemUse.needsPartyTarget(item) then
    local _, qty = selectedItem()
    return openParty("use", item, qty or 1)
  end
  message(RomText.plain("gText_DadsAdvice", { playerName = session() and session().name }), function() st.mode = "list" end)
  return info
end

-- pokeemerald/src/battle_pyramid_bag.c:1245
local function give(item, qty)
  local info = ItemsData.info(item) or {}
  if ItemsData.isMail and ItemsData.isMail(item) then
    return message(RomText.plain("gText_CantWriteMail"), function() st.mode = "list" end)
  end
  if (tonumber(info.importance) or 0) ~= 0 then
    return message(RomText.plain("gText_Var1CantBeHeld", { stringVars = { itemName(item) } }), function() st.mode = "list" end)
  end
  if st.location == "party" and st.onGive then
    local cb = st.onGive
    return PBag.close(function() cb(item) end)
  end
  openParty("give", item, qty)
end

local function runAction(name)
  local item, qty = selectedItem()
  if not item then st.mode = "list" return end
  if name == "CANCEL" then
    st.mode = "list"
  elseif name == "USE_FIELD" then
    useOnField(item)
  elseif name == "GIVE" then
    give(item, qty)
  elseif name == "TOSS" then
    st.tossNum, st.tossMax = 1, qty
    if qty == 1 then st.mode = "toss_confirm" st.yesNo = 1 else st.mode = "toss" end
  elseif name == "USE_BATTLE" then
    local cb = st.onUse
    PBag.close(function() if cb then cb(item) end end)
  end
end

-- pokeemerald/src/battle_pyramid_bag.c:735
local function moveSlot(from, to)
  local items, qty = lists()
  if from == to then return end
  local fi, fq = items[from + 1], qty[from + 1]
  if to > from then
    to = to - 1
    for i = from, to - 1 do items[i + 1], qty[i + 1] = items[i + 2], qty[i + 2] end
  else
    for i = from, to + 1, -1 do items[i + 1], qty[i + 1] = items[i], qty[i] end
  end
  items[to + 1], qty[to + 1] = fi, fq
end
PBag.moveSlot = moveSlot

local function moveCursor(delta)
  local c = Py().bagCursor
  local p = c.scroll + c.cursor + delta
  if p < 0 or p >= st.count then return false end
  if delta > 0 then
    if c.cursor < st.maxShown - 1 and not (c.cursor >= math.floor(st.maxShown / 2) and c.scroll + st.maxShown < st.count) then
      c.cursor = c.cursor + 1
    else
      c.scroll = c.scroll + 1
    end
  else
    if c.cursor > 0 and not (c.cursor <= math.floor(st.maxShown / 2) - 1 and c.scroll > 0) then
      c.cursor = c.cursor - 1
    else
      c.scroll = c.scroll - 1
    end
  end
  return true
end

-- pokeemerald/src/battle_pyramid_bag.c:1361 PerformItemSwap, :1386 CancelItemSwap
local function endSwap(commit)
  local from, to = st.swapFrom, pos()
  if commit and from ~= to and from ~= to - 1 then moveSlot(from, to) end
  if from < to then Py().bagCursor.cursor = math.max(0, Py().bagCursor.cursor - 1) end
  st.swapFrom = nil
  st.mode = "list"
end

local function step(inp)
  st.frame = st.frame + 1
  if st.shake then
    st.shakeT = st.shakeT + 1
    local seg = PBag.SHAKE[st.shake]
    if st.shakeT >= seg[2] then
      st.shake, st.shakeT = st.shake + 1, 0
      if st.shake > #PBag.SHAKE then st.shake = nil end
    end
  end
  if st.fadeDir ~= 0 then
    st.fade = st.fade + st.fadeDir * 2
    if st.fade <= 0 then st.fade, st.fadeDir = 0, 0
    elseif st.fade >= 16 then
      st.fade, st.fadeDir = 16, 0
      if st.mode == "closing" then finish() end
    end
    return
  end
  if st.suspended then return end
  local m = st.mode
  if m == "list" then
    if inp.new.select and st.location ~= "party" then
      if pos() ~= st.count - 1 then
        se("SE_SELECT")
        st.swapFrom = pos()
        st.mode = "swap"
      end
    elseif inp.rep.up then
      if moveCursor(-1) then se("SE_SELECT") startShake() end
    elseif inp.rep.down then
      if moveCursor(1) then se("SE_SELECT") startShake() end
    elseif inp.new.a then
      se("SE_SELECT")
      local item = selectedItem()
      if not item then
        PBag.close()
      elseif st.location == "party" then
        give(item, select(2, selectedItem()))
      else
        st.mode = "action"
        st.menuCursor = 1
      end
    elseif inp.new.b then
      se("SE_SELECT")
      PBag.close()
    end
  elseif m == "action" then
    local acts = actionsFor()
    local grid = #acts == 4
    local c = st.menuCursor
    if grid then
      if inp.new.up and c > 2 then c = c - 2 elseif inp.new.down and c <= 2 then c = c + 2
      elseif inp.new.left and c % 2 == 0 then c = c - 1 elseif inp.new.right and c % 2 == 1 then c = c + 1 end
    else
      if inp.new.up and c > 1 then c = c - 1 elseif inp.new.down and c < #acts then c = c + 1 end
    end
    if c ~= st.menuCursor then se("SE_SELECT") st.menuCursor = c end
    if inp.new.a then
      se("SE_SELECT")
      runAction(acts[st.menuCursor])
    elseif inp.new.b then
      se("SE_SELECT")
      st.mode = "list"
    end
  elseif m == "toss" then
    local n = st.tossNum
    if inp.rep.up then n = (n % st.tossMax) + 1
    elseif inp.rep.down then n = n - 1 if n < 1 then n = st.tossMax end
    elseif inp.rep.right then n = math.min(st.tossMax, n + 10)
    elseif inp.rep.left then n = math.max(1, n - 10) end
    if n ~= st.tossNum then se("SE_SELECT") st.tossNum = n end
    if inp.new.a then se("SE_SELECT") st.mode = "toss_confirm" st.yesNo = 1
    elseif inp.new.b then se("SE_SELECT") st.mode = "list" end
  elseif m == "toss_confirm" then
    if inp.new.up or inp.new.down then se("SE_SELECT") st.yesNo = 3 - st.yesNo end
    if inp.new.a then
      se("SE_SELECT")
      if st.yesNo == 1 then st.mode = "toss_done" else st.mode = "list" end
    elseif inp.new.b then
      se("SE_SELECT")
      st.mode = "list"
    end
  elseif m == "toss_done" then
    if inp.new.a or inp.new.b then
      se("SE_SELECT")
      local item, _, slot = selectedItem()
      if item then Py().bagRemove(session(), item, st.tossNum, slot) end
      PBag.refresh()
      st.mode = "list"
    end
  elseif m == "swap" then
    -- pokeemerald/src/battle_pyramid_bag.c:1324
    if inp.new.select then
      se("SE_SELECT")
      endSwap(true)
      return
    end
    if inp.new.a then
      se("SE_SELECT")
      endSwap(true)
    elseif inp.new.b then
      se("SE_SELECT")
      endSwap(false)
    -- pokeemerald/src/battle_pyramid_bag.c:634
    elseif inp.rep.up then
      if moveCursor(-1) then se("SE_SELECT") startShake() end
    elseif inp.rep.down then
      if moveCursor(1) then se("SE_SELECT") startShake() end
    end
  elseif m == "message" then
    if inp.new.a or inp.new.b then
      se("SE_SELECT")
      local after = st.messageAfter
      st.message, st.messageAfter = nil, nil
      if after then after() else st.mode = "list" end
    end
  end
end

function PBag.handleInput(input)
  if not PBag.open then return end
  st.input = require("src.ui.game3.rse.pokeblock_case").snapshot(input)
end

function PBag.update()
  if not PBag.open then return end
  local inp = st.input or { new = {}, held = {}, rep = {} }
  st.input = nil
  step(inp)
end

local function female()
  local s = session()
  return s and (s.gender == 1 or s.gender == "female" or s.playerGender == 1) or false
end

local function background()
  if st.bg then return st.bg end
  local g = gfx()
  local m = g:manifest()
  st.bg = g:renderMap(g:map("menu"), "screen", Gfx.palette(m.palettes.interface, {}, 0), { rows = 20, backdrop = true })
  return st.bg
end

local function bagSprite()
  local g = gfx()
  local m = g:manifest()
  local lvl = tonumber(require("src.core.game3.rse.frontier.util").frontier(session()).lvlMode) or 0
  local pal = m.palettes.sprite[(lvl ~= 0) and 2 or 1]
  return g:sprite("sprite", 0, 64, 64, pal)
end

local function printAt(text, win, x, y, opts)
  FrlgFont.draw(text, win[1] * 8 + x, win[2] * 8 + y, opts or { font = "narrow", colors = FrlgFont.COLOR.NORMAL })
end

local function description()
  local item = selectedItem()
  if st.mode == "action" and item then
    return RomText.plain("gText_Var1IsSelected", { stringVars = { itemName(item) } })
  elseif st.mode == "toss" and item then
    return RomText.plain("gText_TossHowManyVar1s", { stringVars = { itemName(item) } })
  elseif st.mode == "toss_confirm" and item then
    return RomText.plain("gText_ConfirmTossItems", { stringVars = { itemName(item), tostring(st.tossNum) } })
  elseif st.mode == "toss_done" and item then
    return RomText.plain("gText_ThrewAwayVar2Var1s", { stringVars = { itemName(item), tostring(st.tossNum) } })
  elseif st.mode == "swap" and st.swapFrom then
    local items = lists()
    return RomText.plain("gText_MoveVar1Where", { stringVars = { itemName(items[st.swapFrom + 1]) } })
  end
  if item then return ItemsData.description(item) or "" end
  return RomText.plain("gText_ReturnToVar1", { stringVars = { st.returnTo or "" } })
end
PBag.description = description

-- pokeemerald/src/menu_helpers.c:399 CreateSwapLineSprites
local SWAP_LINE = {}
for i = 0, 7 do
  -- pokeemerald/src/menu_helpers.c:434 UpdateSwapLineSpritesPos
  SWAP_LINE[i + 1] = { frame = i == 0 and 0 or 4, x = i * 16 + 120 - (i == 7 and 8 or 0), y = 0 }
end
local swapLineImg = {}

-- pokeemerald/src/battle_pyramid_bag.c:1605 UpdateSwapLinePos
function PBag.swapLine()
  if st.mode ~= "swap" or not st.swapFrom then return nil end
  local y = 1 + (Py().bagCursor.cursor + 1) * 16
  for i = 1, #SWAP_LINE do SWAP_LINE[i].y = y end
  return SWAP_LINE
end

-- pokeemerald/src/battle_pyramid_bag.c:641
function PBag.iconItem()
  if st.mode == "swap" and st.swapFrom then
    local items = lists()
    return items[st.swapFrom + 1]
  end
  return (selectedItem())
end

local function drawSwapLine()
  local sprites = PBag.swapLine()
  if not sprites then return end
  local g = Gfx.of("rse/pokeblock")
  if swapLineImg.gfx ~= g then
    local pal = g:manifest().palettes.swap_line
    swapLineImg.gfx = g
    swapLineImg[0] = g:sprite("swap_line", 0, 16, 16, pal)
    swapLineImg[4] = g:sprite("swap_line", 4, 16, 16, pal)
  end
  love.graphics.setColor(1, 1, 1, 1)
  for i = 1, #sprites do
    local s = sprites[i]
    love.graphics.draw(swapLineImg[s.frame], s.x - 8, s.y - 8)
  end
end

function PBag.draw()
  if not PBag.open then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(background(), 0, 0)
  local rot = 0
  if st.shake then rot = PBag.SHAKE[st.shake][1] * math.pi * 2 / 256 end
  local spr = bagSprite()
  love.graphics.draw(spr, PBag.SPRITE_X, PBag.SPRITE_Y, rot, 1, 1, 32, 32)
  local items, qty = lists()
  local c = Py().bagCursor
  local W = PBag.WIN_LIST
  for i = 0, st.maxShown - 1 do
    local idx = c.scroll + i
    local y = 1 + i * 16
    if st.mode == "swap" then
      -- pokeemerald/src/battle_pyramid_bag.c:653
      if idx == st.swapFrom then
        FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, W[1] * 8, W[2] * 8 + y, { colors = LIGHT_GRAY })
      end
    elseif idx == pos() then
      FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, W[1] * 8, W[2] * 8 + y,
        { colors = (st.mode == "list") and FrlgFont.COLOR.NORMAL or LIGHT_GRAY })
    end
    if idx == st.count - 1 then
      printAt(RomText.plain("gText_CloseBag"), W, 8, y)
    elseif items[idx + 1] and items[idx + 1] ~= 0 then
      printAt(itemName(items[idx + 1]), W, 8, y)
      local q = RomText.plain("gText_xVar1", { stringVars = { string.format("%2d", qty[idx + 1]) } })
      printAt(q, W, 119 - FrlgFont.measure(q, { font = "narrow" }), y)
    end
  end
  drawSwapLine()
  local item = PBag.iconItem()
  local okBC, BagChrome = pcall(require, "src.ui.game3.rse.bag_chrome")
  if okBC and BagChrome and BagChrome.drawItemIcon then
    BagChrome.drawItemIcon(item and ItemsData.toNumericId(item) or BagChrome.returnIconIndex(), 24 - 16, 88 - 16)
  end
  printAt(description(), PBag.WIN_INFO, 3, 1, { colors = FrlgFont.COLOR.NORMAL, maxWidth = PBag.WIN_INFO[3] * 8 - 3 })
  if st.mode == "action" then
    local acts = actionsFor()
    local tpl = #acts == 4 and PBag.MENU_WIN[3] or PBag.MENU_WIN[#acts]
    Window.stdFrame(Window.template(tpl[1], tpl[2], tpl[3], tpl[4]))
    for i, a in ipairs(acts) do
      local col = #acts == 4 and ((i - 1) % 2) or 0
      local row = #acts == 4 and math.floor((i - 1) / 2) or (i - 1)
      local x, y = tpl[1] * 8 + 8 + col * 56, tpl[2] * 8 + 1 + row * 16
      FrlgFont.draw(RomText.plain(PBag.ACTION_TEXT[a]), x, y, { font = "narrow", colors = FrlgFont.COLOR.NORMAL })
      if i == st.menuCursor then Window.cursorPx(x - 8, y) end
    end
  elseif st.mode == "toss" then
    local T = PBag.TOSS_WIN
    Window.stdFrame(Window.template(T[1], T[2], T[3], T[4]))
    local t = RomText.plain("gText_xVar1", { stringVars = { string.format("%02d", st.tossNum) } })
    FrlgFont.draw(t, T[1] * 8 + math.floor((40 - FrlgFont.measure(t)) / 2), T[2] * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })
  elseif st.mode == "toss_confirm" then
    local Y = PBag.YESNO_WIN
    Window.stdFrame(Window.template(Y[1], Y[2], Y[3], Y[4]))
    FrlgFont.draw(RomText.plain("gText_Yes"), Y[1] * 8 + 8, Y[2] * 8 + 1, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(RomText.plain("gText_No"), Y[1] * 8 + 8, Y[2] * 8 + 17, { colors = FrlgFont.COLOR.NORMAL })
    Window.cursorPx(Y[1] * 8, Y[2] * 8 + 1 + (st.yesNo == 2 and 16 or 0))
  elseif st.mode == "message" and st.message then
    Chrome.dialogueFrame()
    local left, top, width = Chrome.dialogueWindow()
    FrlgFont.draw(FrlgFont.wrap(st.message, width * 8), left * 8, top * 8 + 1,
      { maxWidth = width * 8, colors = FrlgFont.COLOR.NORMAL, linePitch = FrlgFont.linePitch() })
  end
  if st.fade > 0 then
    love.graphics.setColor(0, 0, 0, st.fade / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return PBag
