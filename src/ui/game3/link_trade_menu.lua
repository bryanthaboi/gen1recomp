local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")

local LinkTradeMenu = {}

LinkTradeMenu.CACHE_SUB = "trade"

local T = 8
local PARTY_SIZE = 6
local CANCEL_POS = PARTY_SIZE * 2
-- pokefirered/src/trade.c:332
local DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT = 1, 2, 3, 4
-- pokefirered/src/trade.c:86
local QUEUE_DELAY_MSG = 3
-- pokefirered/src/trade.c:2086
local CONFIRM_PROMPT_DELAY = 120
-- pokefirered/src/trade.c:2273
local SELECTED_MOVE_FRAMES = 20
-- pokefirered/include/constants/songs.h:281
local MUS_GAME_CORNER = 273
-- pokefirered/include/constants/songs.h:9
local SE_SELECT = 5
-- pokefirered/src/pokemon_icon.c:938
local ICON_ANIM_FRAMES = { [0] = 6, 8, 14, 22 }
-- pokefirered/src/battle_interface.c:1844
local HEALTHBAR_PIXELS = 48
-- pokefirered/src/trade.c:326
local MENU_TEXT_COLORS = {
  fg = { 1, 1, 1, 1 },
  shadow = { 115 / 255, 115 / 255, 115 / 255, 1 },
  bg = { 0, 0, 0, 0 },
}

-- pokefirered/src/trade.c:546
local MSG = {
  STANDBY = "gText_Trade_CommunicationStandby",
  CANCELED = "gText_TradeHasBeenCanceled",
  ONLY_MON2 = "gText_OnlyPkmnForBattle",
  WAITING_FOR_FRIEND = "gText_WaitingForFriendToFinish",
  FRIEND_WANTS_TO_TRADE = "gText_FriendWantsToTrade",
  MON_CANT_BE_TRADED = "gText_PkmnCantBeTradedNow",
  FRIENDS_MON_CANT_BE_TRADED = "gText_OtherTrainersPkmnCantBeTraded",
}

-- pokefirered/src/trade.c:349
LinkTradeMenu.CURSOR_DEST = {
  [0] = { { 4, 2, 12, 12, 0, 0 }, { 2, 4, 12, 12, 0, 0 }, { 7, 6, 1, 0, 0, 0 }, { 1, 6, 7, 0, 0, 0 } },
  [1] = { { 5, 3, 12, 12, 0, 0 }, { 3, 5, 12, 12, 0, 0 }, { 0, 7, 6, 1, 0, 0 }, { 6, 7, 0, 1, 0, 0 } },
  [2] = { { 0, 0, 0, 0, 0, 0 }, { 4, 0, 0, 0, 0, 0 }, { 9, 8, 7, 6, 0, 0 }, { 3, 1, 0, 0, 0, 0 } },
  [3] = { { 1, 1, 1, 1, 0, 0 }, { 5, 1, 1, 1, 0, 0 }, { 2, 9, 8, 7, 0, 0 }, { 8, 9, 6, 6, 0, 0 } },
  [4] = { { 2, 2, 2, 2, 0, 0 }, { 0, 0, 0, 0, 0, 0 }, { 11, 10, 9, 8, 7, 6 }, { 5, 3, 1, 0, 0, 0 } },
  [5] = { { 3, 3, 3, 3, 0, 0 }, { 1, 1, 1, 1, 0, 0 }, { 4, 4, 4, 4, 0, 0 }, { 10, 8, 6, 0, 0, 0 } },
  [6] = { { 10, 8, 12, 0, 0, 0 }, { 8, 10, 12, 0, 0, 0 }, { 1, 0, 0, 0, 0, 0 }, { 7, 0, 1, 0, 0, 0 } },
  [7] = { { 12, 0, 0, 0, 0, 0 }, { 9, 12, 0, 0, 0, 0 }, { 6, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 } },
  [8] = { { 6, 0, 0, 0, 0, 0 }, { 10, 6, 0, 0, 0, 0 }, { 3, 2, 1, 0, 0, 0 }, { 9, 7, 0, 0, 0, 0 } },
  [9] = { { 7, 0, 0, 0, 0, 0 }, { 11, 12, 0, 0, 0, 0 }, { 8, 0, 0, 0, 0, 0 }, { 2, 1, 0, 0, 0, 0 } },
  [10] = { { 8, 0, 0, 0, 0, 0 }, { 6, 0, 0, 0, 0, 0 }, { 5, 4, 3, 2, 1, 0 }, { 11, 9, 7, 0, 0, 0 } },
  [11] = { { 9, 0, 0, 0, 0, 0 }, { 12, 0, 0, 0, 0, 0 }, { 10, 0, 0, 0, 0, 0 }, { 4, 2, 0, 0, 0, 0 } },
  [12] = { { 11, 9, 7, 6, 0, 0 }, { 7, 6, 0, 0, 0, 0 }, { 12, 0, 0, 0, 0, 0 }, { 12, 0, 0, 0, 0, 0 } },
}

-- pokefirered/src/trade.c:442
LinkTradeMenu.SPRITE_COORDS = {
  [0] = { 1, 5 }, { 8, 5 }, { 1, 10 }, { 8, 10 }, { 1, 15 }, { 8, 15 },
  { 16, 5 }, { 23, 5 }, { 16, 10 }, { 23, 10 }, { 16, 15 }, { 23, 15 },
  { 23, 18 },
}

-- pokefirered/src/trade.c:478
LinkTradeMenu.BOX_COORDS = {
  [0] = { 1, 3 }, { 8, 3 }, { 1, 8 }, { 8, 8 }, { 1, 13 }, { 8, 13 },
  { 16, 3 }, { 23, 3 }, { 16, 8 }, { 23, 8 }, { 16, 13 }, { 23, 13 },
}

-- pokefirered/src/trade.c:773
LinkTradeMenu.SELECTED_COORDS = { [0] = { 4, 3 }, [1] = { 19, 3 } }

LinkTradeMenu.open = false
LinkTradeMenu._art = nil
LinkTradeMenu._artTried = false
LinkTradeMenu._artError = nil

local function trade()
  return require("src.core.game3.link.trade")
end

local function link()
  return require("src.core.game3.link")
end

local function pokemon()
  return require("src.core.game3.pokemon")
end

local function audio()
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and type(Audio) == "table" then return Audio end
  return nil
end

local function playSe(id)
  local Audio = audio()
  if Audio and Audio.playSe then pcall(Audio.playSe, id) end
end

local function myParty()
  local s = link().session()
  return (s and s.party) or {}
end

local function partyOf(side)
  if side == 0 then return myParty() end
  return trade().peerParty or {}
end

local function partyCount(side)
  return math.min(PARTY_SIZE, #partyOf(side))
end

local function resetState()
  LinkTradeMenu.pos = 0
  LinkTradeMenu.cursor = 1
  LinkTradeMenu.cb = "loading"
  LinkTradeMenu.subCursor = 1
  LinkTradeMenu.yesNoCursor = 1
  LinkTradeMenu.confirming = false
  LinkTradeMenu.message = nil
  LinkTradeMenu.bottom = "choose"
  LinkTradeMenu.cursorVisible = true
  LinkTradeMenu.submenuVisible = false
  LinkTradeMenu.queue = {}
  LinkTradeMenu.frame = 0
  LinkTradeMenu.fade = 16
  LinkTradeMenu.fadeDir = 0
  LinkTradeMenu.fadeThen = nil
  LinkTradeMenu.selected = { [0] = { state = 0 }, [1] = { state = 0 } }
  LinkTradeMenu.icons = { [0] = {}, [1] = {} }
  LinkTradeMenu.timer = 0
  LinkTradeMenu.exitStarted = false
  LinkTradeMenu._heldKey = nil
  LinkTradeMenu._heldFrames = 0
end

resetState()

function LinkTradeMenu.isOpen()
  return LinkTradeMenu.open and true or false
end

local function cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  return (ok and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
end

local function read_bytes(rel)
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  if not (ok and Dataset and Dataset.cache) then return nil end
  local okR, d = pcall(function() return Dataset.cache():read(rel) end)
  if okR and type(d) == "string" and #d > 0 then return d end
  return nil
end

local SHEETS = { "menu_bg1", "stripes_bg2", "stripes_bg3", "party_box", "moves_box",
  "mon_box", "menu_tiles", "cursor" }

-- pokefirered/src/trade.c:1368
function LinkTradeMenu.loadArt()
  if LinkTradeMenu._artTried then
    if LinkTradeMenu._artError then error(LinkTradeMenu._artError, 0) end
    return LinkTradeMenu._art
  end
  LinkTradeMenu._artTried = true
  local root = cache_root() .. "/" .. LinkTradeMenu.CACHE_SUB
  local src = read_bytes(root .. "/manifest.lua")
  local chunk = src and load(src, "@trade/manifest.lua", "t", {})
  local okM, man = false, nil
  if chunk then okM, man = pcall(chunk) end
  if not (okM and type(man) == "table") then
    LinkTradeMenu._artError = "link_trade_menu: trade/manifest.lua is not in the cache"
    error(LinkTradeMenu._artError, 0)
  end
  local art = { manifest = man }
  for _, name in ipairs(SHEETS) do
    local entry = man[name]
    local w = tonumber(entry and entry.width)
    local h = tonumber(entry and entry.height)
    local rgba = w and h and read_bytes(root .. "/" .. name .. ".rgba")
    if not (rgba and #rgba >= w * h * 4) then
      LinkTradeMenu._artError = "link_trade_menu: trade/" .. name .. ".rgba is not in the cache"
      error(LinkTradeMenu._artError, 0)
    end
    local image = love.graphics.newImage(love.image.newImageData(w, h, "rgba8", rgba))
    image:setFilter("nearest", "nearest")
    art[name] = image
  end
  local cols = tonumber(man.menu_tiles.columns) or 16
  local sw, sh = art.menu_tiles:getDimensions()
  art.tileQuads = {}
  for t = 0, (tonumber(man.menu_tiles.tiles) or 148) - 1 do
    art.tileQuads[t] = love.graphics.newQuad((t % cols) * T, math.floor(t / cols) * T, T, T, sw, sh)
  end
  local cw, ch = art.cursor:getDimensions()
  local fh = tonumber(man.cursor.frame_h) or 32
  art.cursorQuads = {
    [0] = love.graphics.newQuad(0, 0, cw, fh, cw, ch),
    [1] = love.graphics.newQuad(0, fh, cw, fh, cw, ch),
  }
  -- pokefirered/src/trade.c:2421
  art.eggCopyQuad = love.graphics.newQuad(3 * T, 0, T, T, art.mon_box:getDimensions())
  LinkTradeMenu._art = art
  return art
end

function LinkTradeMenu.invalidate()
  LinkTradeMenu._art = nil
  LinkTradeMenu._artTried = false
  LinkTradeMenu._artError = nil
end

-- pokefirered/src/trade.c:1401
function LinkTradeMenu.optionsActive()
  local active = {}
  local mine, theirs = partyCount(0), partyCount(1)
  for i = 0, PARTY_SIZE - 1 do
    active[i] = i < mine
    active[i + PARTY_SIZE] = i < theirs
  end
  active[CANCEL_POS] = true
  return active
end

-- pokefirered/src/trade.c:1770
function LinkTradeMenu.newCursorPosition(pos, dir, active)
  active = active or LinkTradeMenu.optionsActive()
  for _, nextPos in ipairs(LinkTradeMenu.CURSOR_DEST[pos][dir]) do
    if active[nextPos] then return nextPos end
  end
  return 0
end

-- pokefirered/src/battle_interface.c:2165
function LinkTradeMenu.hpBarLevel(hp, maxHp)
  hp = tonumber(hp) or 0
  maxHp = tonumber(maxHp) or hp
  if hp == maxHp then return 4 end
  if maxHp <= 0 then return 0 end
  -- pokefirered/src/battle_interface.c:2155
  local f = math.floor(hp * HEALTHBAR_PIXELS / maxHp)
  if f == 0 and hp > 0 then f = 1 end
  if f > 24 then return 3 end
  if f > 9 then return 2 end
  if f > 0 then return 1 end
  return 0
end

-- pokefirered/src/daycare.c:1357
local function nameHasGenderSymbol(name, gender)
  local males, females = 0, 0
  for _ in tostring(name or ""):gmatch("♂") do males = males + 1 end
  for _ in tostring(name or ""):gmatch("♀") do females = females + 1 end
  if gender == "M" then return males ~= 0 and females == 0 end
  if gender == "F" then return females ~= 0 and males == 0 end
  return false
end

-- pokefirered/src/trade.c:2397
function LinkTradeMenu.levelGenderTiles(mon)
  local P = pokemon()
  if P.isEgg(mon) then return { egg = true, symbol = 0x80, symbolFlip = true } end
  local level = math.floor(tonumber(mon and mon.level) or 0)
  local out = { ones = 0x70 + level % 10 }
  if math.floor(level / 10) ~= 0 then out.tens = 0x60 + math.floor(level / 10) end
  local okG, gender = pcall(P.gender, P.speciesOf(mon), mon and mon.personality)
  if not okG then gender = "U" end
  local name = P.displayName(mon)
  if gender == "M" then
    out.symbol = nameHasGenderSymbol(name, "M") and 0x83 or 0x84
  elseif gender == "F" then
    out.symbol = nameHasGenderSymbol(name, "F") and 0x83 or 0x85
  else
    out.symbol = 0x83
  end
  return out
end

-- pokefirered/src/trade.c:2339
function LinkTradeMenu.movesLines(mon)
  local P = pokemon()
  if P.isEgg(mon) then return { RomText.plain("gText_4Qmark") } end
  local lines = {}
  local moves = (mon and mon.moves) or {}
  for i = 1, 4 do
    local mv = moves[i]
    local id = tonumber(type(mv) == "table" and (mv.id or mv.move) or mv) or 0
    local name = ""
    if id ~= 0 then
      local okN, n = pcall(P.moveName, id)
      name = okN and n or ""
    end
    lines[i] = tostring(name or "")
  end
  return lines
end

-- pokefirered/src/party_menu.c:2785
function LinkTradeMenu.heldItemFrame(mon)
  return require("src.ui.game3.party_menu").heldItemFrame(mon)
end

local function setPos(pos)
  LinkTradeMenu.pos = pos
  if pos < PARTY_SIZE then LinkTradeMenu.cursor = pos + 1 end
end

-- pokefirered/src/trade.c:1788
local function moveCursor(dir)
  local nextPos = LinkTradeMenu.newCursorPosition(LinkTradeMenu.pos, dir)
  if nextPos ~= LinkTradeMenu.pos then playSe(SE_SELECT) end
  setPos(nextPos)
end

-- pokefirered/src/trade.c:2519
local function queueMessage(text)
  local q = LinkTradeMenu.queue
  q[#q + 1] = { delay = QUEUE_DELAY_MSG, text = text }
end

-- pokefirered/src/trade.c:2535
local function runQueue()
  local q = LinkTradeMenu.queue
  local i = 1
  while i <= #q do
    local action = q[i]
    if action.delay ~= 0 then
      action.delay = action.delay - 1
      i = i + 1
    else
      LinkTradeMenu.message = action.text
      table.remove(q, i)
    end
  end
end

-- pokefirered/src/palette.c:151
local function startFade(dir, after)
  LinkTradeMenu.fadeDir = dir
  LinkTradeMenu.fadeThen = after
  LinkTradeMenu.fade = dir > 0 and 0 or 16
end

local function tickFade()
  if LinkTradeMenu.fadeDir == 0 then return end
  local y = LinkTradeMenu.fade + 2 * LinkTradeMenu.fadeDir
  if y > 0 and y < 16 then
    LinkTradeMenu.fade = y
    return
  end
  LinkTradeMenu.fade = math.max(0, math.min(16, y))
  LinkTradeMenu.fadeDir = 0
  local after = LinkTradeMenu.fadeThen
  LinkTradeMenu.fadeThen = nil
  if after then after() end
end

local function hasGraphics()
  return type(love) == "table" and love.graphics ~= nil
end

-- pokefirered/src/trade.c:826 CB2_CreateTradeMenu
function LinkTradeMenu.show()
  if LinkTradeMenu.open then return true end
  LinkTradeMenu.open = true
  resetState()
  -- pokefirered/src/trade.c:853
  LinkTradeMenu.message = RomText.plain(MSG.STANDBY)
  Stack.push("link_trade", LinkTradeMenu, { hideBelow = true })
  return true
end

local function restoreSong()
  if not LinkTradeMenu._song then return end
  LinkTradeMenu._song = nil
  local Audio = audio()
  if Audio and Audio.restoreMapSong then pcall(Audio.restoreMapSong) end
end

function LinkTradeMenu.close(opts)
  if not LinkTradeMenu.open then return false end
  LinkTradeMenu.open = false
  LinkTradeMenu.message = nil
  LinkTradeMenu.confirming = false
  LinkTradeMenu.queue = {}
  Stack.pop("link_trade")
  if opts and opts.keepSong then
    LinkTradeMenu._song = nil
  else
    restoreSong()
  end
  return true
end

function LinkTradeMenu.reset()
  LinkTradeMenu.open = false
  LinkTradeMenu._song = nil
  resetState()
  Stack.pop("link_trade")
  return true
end

-- pokefirered/src/trade.c:1042
local function enterMenu()
  LinkTradeMenu.message = nil
  LinkTradeMenu.cb = "main"
  setPos(0)
  if hasGraphics() then
    local Audio = audio()
    -- pokefirered/src/trade.c:1049
    if Audio and Audio.playSong and pcall(Audio.playSong, MUS_GAME_CORNER) then
      LinkTradeMenu._song = true
    end
  end
  -- pokefirered/src/trade.c:1065
  startFade(-1)
end

-- pokefirered/src/trade.c:1882
local function redrawChooseAPokemonWindow()
  LinkTradeMenu.submenuVisible = false
  LinkTradeMenu.cb = "main"
  LinkTradeMenu.cursorVisible = true
  LinkTradeMenu.bottom = "choose"
end

-- pokefirered/src/trade.c:2496
local function redrawPartyWindow(side)
  LinkTradeMenu.selected[side] = { state = 0 }
  LinkTradeMenu.bottom = "choose"
end

-- pokefirered/src/trade.c:1939
local function showSummary(side, idx)
  LinkTradeMenu.cb = "summary"
  LinkTradeMenu.submenuVisible = false
  startFade(1, function()
    local SummaryMenu = require("src.ui.game3.summary_menu")
    SummaryMenu.openMenu(partyOf(side), idx + 1, {
      mode = "trade",
      enemyParty = side == 1,
      -- pokefirered/src/pokemon_summary_screen.c:3251
      owner = side == 1 and trade().peer and {
        playerName = trade().peer.name,
        trainerId = tonumber(trade().peer.trainerId) or 0,
      } or nil,
      onClose = function()
        -- pokefirered/src/trade.c:1236
        local last = math.floor(tonumber(SummaryMenu._cursor) or (idx + 1))
        setPos(side * PARTY_SIZE + math.max(0, math.min(partyCount(side), last) - 1))
        redrawChooseAPokemonWindow()
        startFade(-1)
      end,
    })
  end)
end

-- pokefirered/src/trade.c:1890
local function tradeSelectedMon()
  local LT = trade()
  local ok, code = LT.offer(LinkTradeMenu.pos + 1)
  if ok then
    -- pokefirered/src/trade.c:1813
    LinkTradeMenu.message = RomText.plain(MSG.STANDBY)
    LinkTradeMenu.cursorVisible = false
    LinkTradeMenu.cb = "ready_wait"
    return true
  end
  local Trade = require("src.core.game3.scripting.natives_trade")
  queueMessage(Trade.refusalText(code) or RomText.plain(MSG.MON_CANT_BE_TRADED))
  LinkTradeMenu.cb = "trade_canceled"
  return false
end

-- pokefirered/src/trade.c:2227
local function setSelectedMon(side, idx)
  local sel = LinkTradeMenu.selected[side]
  if sel.state ~= 0 then return end
  sel.state = 1
  sel.idx = math.max(0, math.min(PARTY_SIZE - 1, math.floor(tonumber(idx) or 0)))
end

-- pokefirered/src/trade.c:2241
local function drawSelectedMonScreen(side)
  local sel = LinkTradeMenu.selected[side]
  if sel.state == 1 then
    local from = LinkTradeMenu.SPRITE_COORDS[side * PARTY_SIZE + sel.idx]
    local c0 = LinkTradeMenu.SPRITE_COORDS[side * PARTY_SIZE]
    local c1 = LinkTradeMenu.SPRITE_COORDS[side * PARTY_SIZE + 1]
    sel.fromX, sel.fromY = from[1] * T + 14, from[2] * T - 12
    sel.toX = math.floor((c0[1] + c1[1]) / 2) * T + 14
    sel.toY = c0[2] * T - 12
    sel.x, sel.y, sel.t = sel.fromX, sel.fromY, 0
    sel.state = 2
    if side == 0 then LinkTradeMenu.submenuVisible = false end
  elseif sel.state == 2 then
    sel.t = sel.t + 1
    local k = math.min(1, sel.t / SELECTED_MOVE_FRAMES)
    sel.x = sel.fromX + math.floor((sel.toX - sel.fromX) * k)
    sel.y = sel.fromY + math.floor((sel.toY - sel.fromY) * k)
    if sel.t >= SELECTED_MOVE_FRAMES then sel.state = 3 end
  elseif sel.state == 3 then
    sel.x, sel.y = sel.toX, sel.toY
    sel.state = 4
  elseif sel.state == 4 then
    sel.state = 5
  end
end

-- pokefirered/src/trade.c:1637
local function canceledMessage(LT)
  local leader = LT.isLeader()
  local r = LT.lastResult
  if (leader and r == "player_canceled") or (not leader and r == "partner_canceled") then
    return RomText.plain(MSG.FRIEND_WANTS_TO_TRADE)
  end
  return RomText.plain(MSG.CANCELED)
end

local SELECTING = { selected_mons = true, okay_wait = true, confirm_prompt = true }
local KEEP_OPEN = { menu = true, ready_wait = true, confirm = true, confirm_wait = true, canceled = true }

local function syncLink(LT)
  if LT.state == "confirm" and not SELECTING[LinkTradeMenu.cb] then
    -- pokefirered/src/trade.c:1652
    LinkTradeMenu.message = nil
    LinkTradeMenu.confirming = false
    setSelectedMon(0, tonumber(LT.cursor) or LinkTradeMenu.pos)
    setSelectedMon(1, (tonumber(LT.partnerCursor) or 0) % PARTY_SIZE)
    LinkTradeMenu.cb = "selected_mons"
  elseif LT.state == "canceled" and LinkTradeMenu.cb ~= "trade_canceled" then
    LinkTradeMenu.queue = {}
    LinkTradeMenu.confirming = false
    LinkTradeMenu.message = canceledMessage(LT)
    LinkTradeMenu.cb = "trade_canceled"
  end
end

local function tickIcons()
  for side = 0, 1 do
    local party = partyOf(side)
    local anims = LinkTradeMenu.icons[side]
    for i = 1, partyCount(side) do
      local a = anims[i]
      if not a then
        a = { t = 0, f = 0 }
        anims[i] = a
      end
      local mon = party[i] or {}
      -- pokefirered/src/trade.c:2725
      local anim = 4 - LinkTradeMenu.hpBarLevel(mon.hp, mon.maxHp or mon.hp)
      local dur = ICON_ANIM_FRAMES[anim]
      if not dur then
        a.t, a.f = 0, 0
      else
        a.t = a.t + 1
        if a.t >= dur then
          a.t = 0
          a.f = 1 - a.f
        end
      end
    end
  end
end

-- pokefirered/src/menu.c:369
local function menuInput(input, field)
  local cur = LinkTradeMenu[field]
  if input:wasPressed("a") then
    playSe(SE_SELECT)
    return cur
  end
  if input:wasPressed("b") then return "b" end
  if input:wasPressed("up") and cur > 1 then
    LinkTradeMenu[field] = cur - 1
    playSe(SE_SELECT)
  elseif input:wasPressed("down") and cur < 2 then
    LinkTradeMenu[field] = cur + 1
    playSe(SE_SELECT)
  end
  return nil
end

-- pokefirered/src/main.c:286
local KEY_REPEAT_START, KEY_REPEAT_CONTINUE = 40, 5
local DIRS = { "up", "down", "left", "right" }

-- pokefirered/src/main.c:309
local function trackHeld(input)
  local key
  if input.isDown then
    for _, d in ipairs(DIRS) do
      if input:isDown(d) then
        key = d
        break
      end
    end
  end
  if key ~= LinkTradeMenu._heldKey or (key and input:wasPressed(key)) then
    LinkTradeMenu._heldKey = key
    LinkTradeMenu._heldFrames = 0
  elseif key then
    LinkTradeMenu._heldFrames = (LinkTradeMenu._heldFrames or 0) + 1
  end
end

local function joyRept(input, key)
  if input:wasPressed(key) then return true end
  local n = LinkTradeMenu._heldFrames or 0
  return LinkTradeMenu._heldKey == key and n >= KEY_REPEAT_START
    and (n - KEY_REPEAT_START) % KEY_REPEAT_CONTINUE == 0
end

-- pokefirered/src/trade.c:1830
local function processMenuInput(input)
  if joyRept(input, "up") then moveCursor(DIR_UP)
  elseif joyRept(input, "down") then moveCursor(DIR_DOWN)
  elseif joyRept(input, "left") then moveCursor(DIR_LEFT)
  elseif joyRept(input, "right") then moveCursor(DIR_RIGHT)
  end
  if not input:wasPressed("a") then return end
  playSe(SE_SELECT)
  local pos = LinkTradeMenu.pos
  if pos < PARTY_SIZE then
    LinkTradeMenu.subCursor = 1
    LinkTradeMenu.submenuVisible = true
    LinkTradeMenu.cb = "selected"
  elseif pos < CANCEL_POS then
    showSummary(1, pos - PARTY_SIZE)
  else
    -- pokefirered/src/trade.c:1867
    LinkTradeMenu.yesNoCursor = 1
    LinkTradeMenu.bottom = "cancel"
    LinkTradeMenu.cb = "cancel_prompt"
  end
end

function LinkTradeMenu.handleInput(input)
  if not (input and LinkTradeMenu.open) then return end
  trackHeld(input)
  if LinkTradeMenu.fadeDir ~= 0 then return end
  local cb = LinkTradeMenu.cb
  if cb == "main" then
    processMenuInput(input)
  elseif cb == "selected" then
    -- pokefirered/src/trade.c:1890
    local choice = menuInput(input, "subCursor")
    if choice == "b" then
      playSe(SE_SELECT)
      redrawChooseAPokemonWindow()
    elseif choice == 1 then
      showSummary(0, LinkTradeMenu.pos)
    elseif choice == 2 then
      tradeSelectedMon()
    end
  elseif cb == "cancel_prompt" then
    -- pokefirered/src/trade.c:2043
    local choice = menuInput(input, "yesNoCursor")
    if choice == 1 then
      LinkTradeMenu.message = RomText.plain(MSG.WAITING_FOR_FRIEND)
      LinkTradeMenu.cursorVisible = false
      LinkTradeMenu.cb = "idle"
      trade().cancelSelect()
    elseif choice == 2 or choice == "b" then
      playSe(SE_SELECT)
      redrawChooseAPokemonWindow()
    end
  elseif cb == "confirm_prompt" then
    -- pokefirered/src/trade.c:2008
    local choice = menuInput(input, "yesNoCursor")
    if choice == 1 then
      LinkTradeMenu.confirming = false
      LinkTradeMenu.cb = "idle"
      local LT = trade()
      LT.confirm(true)
      -- pokefirered/src/trade.c:1976
      if LT.lastResult == LT.PLAYER_MON_INVALID then
        queueMessage(RomText.plain(MSG.ONLY_MON2))
      elseif LT.lastResult == LT.PARTNER_MON_INVALID then
        queueMessage(RomText.plain(MSG.FRIENDS_MON_CANT_BE_TRADED))
      else
        queueMessage(RomText.plain(MSG.STANDBY))
      end
    elseif choice == 2 or choice == "b" then
      LinkTradeMenu.confirming = false
      LinkTradeMenu.cb = "idle"
      queueMessage(RomText.plain(MSG.STANDBY))
      trade().confirm(false)
    end
  elseif cb == "trade_canceled" then
    -- pokefirered/src/trade.c:2094
    if input:wasPressed("a") then
      playSe(SE_SELECT)
      LinkTradeMenu.message = nil
      LinkTradeMenu.submenuVisible = false
      redrawPartyWindow(0)
      redrawPartyWindow(1)
      trade().resumeMenu()
      LinkTradeMenu.cb = "main"
      LinkTradeMenu.cursorVisible = true
    end
  end
end

local function exitWithFade(LT, toScene)
  if LinkTradeMenu.cb ~= "exiting" then
    LinkTradeMenu.cb = "exiting"
    LinkTradeMenu.cursorVisible = false
    LinkTradeMenu.confirming = false
    LinkTradeMenu.queue = {}
    LinkTradeMenu.timer = 0
    LinkTradeMenu.exitStarted = false
    if not toScene and not LT.isLeader() then
      -- pokefirered/src/trade.c:1643
      LinkTradeMenu.message = RomText.plain(MSG.WAITING_FOR_FRIEND)
    end
  end
  if LinkTradeMenu.exitStarted then return end
  if toScene and LT.isLeader() then
    -- pokefirered/src/trade.c:1293 CB_FadeToStartTrade
    LinkTradeMenu.timer = LinkTradeMenu.timer + 1
    if LinkTradeMenu.timer < 16 then return end
  end
  LinkTradeMenu.exitStarted = true
  -- pokefirered/src/trade.c:1302, :2117
  startFade(1, function()
    LinkTradeMenu.close({ keepSong = toScene })
  end)
end

-- pokefirered/src/trade.c:1350
function LinkTradeMenu.update(_dt)
  if not LinkTradeMenu.open then return end
  local LT = trade()
  LinkTradeMenu.frame = LinkTradeMenu.frame + 1
  tickFade()
  if not LinkTradeMenu.open then return end
  if LinkTradeMenu.cb == "loading" then
    -- pokefirered/src/trade.c:935
    if LT.peer ~= nil then enterMenu() end
  else
    runQueue()
    syncLink(LT)
    tickIcons()
    drawSelectedMonScreen(0)
    drawSelectedMonScreen(1)
    if LinkTradeMenu.cb == "selected_mons" then
      -- pokefirered/src/trade.c:2073
      if LinkTradeMenu.selected[0].state == 5 and LinkTradeMenu.selected[1].state == 5 then
        -- pokefirered/src/trade.c:1588
        LinkTradeMenu.bottom = "okay"
        LinkTradeMenu.timer = 0
        LinkTradeMenu.cb = "okay_wait"
      end
    elseif LinkTradeMenu.cb == "okay_wait" then
      -- pokefirered/src/trade.c:2083
      LinkTradeMenu.timer = LinkTradeMenu.timer + 1
      if LinkTradeMenu.timer > CONFIRM_PROMPT_DELAY then
        LinkTradeMenu.timer = 0
        LinkTradeMenu.yesNoCursor = 1
        LinkTradeMenu.confirming = true
        LinkTradeMenu.cb = "confirm_prompt"
      end
    end
  end
  if not KEEP_OPEN[LT.state] then
    local toScene = LT.state == "exchange" or LT.state == "scene"
    if (toScene or LT.state == "exit") and hasGraphics() then
      exitWithFade(LT, toScene)
    else
      LinkTradeMenu.close({ keepSong = toScene })
    end
  end
end

local function drawText(text, x, y, colors, small)
  FrlgFont.draw(tostring(text or ""), x, y, { colors = colors, small = small, maxWidth = 240 })
end

-- pokefirered/src/trade.c:2397
local function drawLevelAndGender(art, mon, boxX, boxY)
  local g = love.graphics
  g.draw(art.mon_box, boxX * T, boxY * T)
  local tiles = LinkTradeMenu.levelGenderTiles(mon)
  local x, y = boxX + 4, boxY + 1
  local function tile(t, tx, ty, flip)
    local q = t and art.tileQuads[t]
    if not q then return end
    if flip then
      g.draw(art.menu_tiles, q, tx * T + T, ty * T, 0, -1, 1)
    else
      g.draw(art.menu_tiles, q, tx * T, ty * T)
    end
  end
  if tiles.egg then
    g.draw(art.mon_box, art.eggCopyQuad, x * T, (y - 1) * T)
  else
    tile(tiles.tens, x, y)
    tile(tiles.ones, x + 1, y)
  end
  tile(tiles.symbol, x + 1, y - 1, tiles.symbolFlip)
end

-- pokefirered/src/trade.c:2371
local function drawNickname(mon, winLeft, winTop, width)
  local name = pokemon().displayName(mon)
  local w = FrlgFont.measure(name, { small = true })
  drawText(name, winLeft * T + math.floor((width - w) / 2), winTop * T + 4, FrlgFont.COLOR.WHITE, true)
end

-- pokefirered/src/trade.c:997
local function drawNameSprite(name, centerX)
  local w = FrlgFont.measure(name)
  drawText(name, math.floor((56 - w) / 2) + centerX - 16, 9 - 8 + 2, MENU_TEXT_COLORS)
end

local function drawMessage()
  if not LinkTradeMenu.message then return end
  -- pokefirered/src/trade.c:2581
  Chrome.fixedStdFrame(4, 7, 22, 4)
  FrlgFont.draw(LinkTradeMenu.message, 4 * T, 7 * T + 2, { maxWidth = 22 * T })
end

local function drawYesNo()
  -- pokefirered/src/trade.c:744
  Chrome.stdFrame(21, 13, 6, 4)
  local labels = { RomText.plain("gText_Yes"), RomText.plain("gText_No") }
  for i, lab in ipairs(labels) do
    local y = 13 * T + 2 + (i - 1) * 14
    if i == LinkTradeMenu.yesNoCursor then Window.cursorPx(21 * T, y) end
    Window.printPx(lab, 21 * T + 8, y)
  end
end

local function drawSubmenu()
  -- pokefirered/src/trade.c:1850
  Chrome.stdFrame(17, 15, 12, 4)
  local labels = { RomText.plain("gText_TradeAction_Summary"), RomText.plain("gText_TradeAction_Trade") }
  for i, lab in ipairs(labels) do
    local y = 15 * T + (i - 1) * 16
    if i == LinkTradeMenu.subCursor then Window.cursorPx(17 * T, y) end
    Window.printPx(lab, 17 * T + 8, y)
  end
end

local BOTTOM_TEXT = {
  -- pokefirered/src/trade.c:987
  choose = function() return RomText.at("sActionTexts", 1) end,
  -- pokefirered/src/trade.c:1869
  cancel = function() return RomText.at("sActionTexts", 4) end,
  -- pokefirered/src/trade.c:1588
  okay = function() return RomText.plain("gText_IsThisTradeOkay") end,
}

function LinkTradeMenu.draw()
  if not (LinkTradeMenu.open and hasGraphics()) then return end
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 240, 160)
  if LinkTradeMenu.cb == "loading" then
    drawMessage()
    g.setColor(1, 1, 1, 1)
    return
  end
  local art = LinkTradeMenu.loadArt()
  local LT = trade()
  g.setColor(1, 1, 1, 1)
  -- pokefirered/src/trade.c:1359
  local scroll = LinkTradeMenu.frame % 256
  g.draw(art.stripes_bg3, scroll, 0)
  g.draw(art.stripes_bg3, scroll - 256, 0)
  g.draw(art.stripes_bg2, -scroll, 0)
  g.draw(art.stripes_bg2, 256 - scroll, 0)
  g.draw(art.menu_bg1, 0, 0)
  for side = 0, 1 do
    local sel = LinkTradeMenu.selected[side]
    local party = partyOf(side)
    if sel.state == 0 then
      for i = 0, partyCount(side) - 1 do
        local c = LinkTradeMenu.BOX_COORDS[side * PARTY_SIZE + i]
        drawLevelAndGender(art, party[i + 1], c[1], c[2])
      end
    else
      -- pokefirered/src/trade.c:2281
      g.draw(sel.state >= 3 and art.moves_box or art.party_box, 120 * side, 0)
      if sel.state >= 5 and party[sel.idx + 1] then
        local c = LinkTradeMenu.SELECTED_COORDS[side]
        drawLevelAndGender(art, party[sel.idx + 1], c[1], c[2])
      end
    end
  end

  if LinkTradeMenu.cursorVisible then
    local pos = LinkTradeMenu.pos
    if pos == CANCEL_POS then
      -- pokefirered/src/trade.c:1794
      g.draw(art.cursor, art.cursorQuads[1], 240 - 16 - 32, 160 - 16)
    else
      local c = LinkTradeMenu.SPRITE_COORDS[pos]
      g.draw(art.cursor, art.cursorQuads[0], c[1] * T + 32 - 32, c[2] * T - 16)
    end
  end

  for side = 0, 1 do
    local sel = LinkTradeMenu.selected[side]
    local party = partyOf(side)
    for i = 0, partyCount(side) - 1 do
      local x, y
      if sel.state == 0 then
        local c = LinkTradeMenu.SPRITE_COORDS[side * PARTY_SIZE + i]
        x, y = c[1] * T + 14, c[2] * T - 12
      elseif i == sel.idx and sel.x then
        x, y = sel.x, sel.y
      end
      local icon = x and pokemon().monIcon(party[i + 1])
      if icon and icon.image then
        local a = LinkTradeMenu.icons[side][i + 1]
        local q = icon.quads and (icon.quads[a and a.f or 0] or icon.quads[0])
        if q then g.draw(icon.image, q, x - 16, y - 16) end
      end
      -- pokefirered/src/party_menu.c:2816
      local holdFrame = x and LinkTradeMenu.heldItemFrame(party[i + 1])
      if holdFrame then
        local PartyMenu = require("src.ui.game3.party_menu")
        local hold = PartyMenu.heldItemSheet()
        g.draw(hold.image, hold.quads[holdFrame], x + 4 - hold.w / 2, y + 10 - hold.h / 2)
      end
    end
  end

  local s = link().session()
  drawNameSprite((s and s.name) or "", 48)
  drawNameSprite((LT.peer and LT.peer.name) or "", 168)
  -- pokefirered/src/trade.c:1024
  drawText(RomText.at("sActionTexts", 0), 215 - 16, 151 - 8 + 2, MENU_TEXT_COLORS)
  -- pokefirered/src/trade.c:1034
  drawText(BOTTOM_TEXT[LinkTradeMenu.bottom](), 24 - 16, 150 - 8 + 2, MENU_TEXT_COLORS)

  for side = 0, 1 do
    local sel = LinkTradeMenu.selected[side]
    local party = partyOf(side)
    if sel.state == 0 then
      for i = 0, partyCount(side) - 1 do
        local c = LinkTradeMenu.SPRITE_COORDS[side * PARTY_SIZE + i]
        drawNickname(party[i + 1], c[1] - 1, c[2], 64)
      end
    elseif sel.state >= 4 and party[sel.idx + 1] then
      local mon = party[sel.idx + 1]
      -- pokefirered/src/trade.c:2307
      drawNickname(mon, side == 0 and 2 or 17, 5, 80)
      local mx = side == 0 and 3 or 18
      for li, line in ipairs(LinkTradeMenu.movesLines(mon)) do
        drawText(line, mx * T, 8 * T + (li - 1) * 14, FrlgFont.COLOR.WHITE)
      end
    end
  end

  if LinkTradeMenu.submenuVisible then drawSubmenu() end
  drawMessage()
  if LinkTradeMenu.cb == "cancel_prompt" or LinkTradeMenu.cb == "confirm_prompt" then drawYesNo() end

  if LinkTradeMenu.fade > 0 then
    g.setColor(0, 0, 0, LinkTradeMenu.fade / 16)
    g.rectangle("fill", 0, 0, 240, 160)
  end
  g.setColor(1, 1, 1, 1)
end

return LinkTradeMenu
